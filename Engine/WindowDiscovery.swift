import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

/// What sharing a window needs to know about one, copied from ScreenCaptureKit so that choosing a window can be tested.
struct WindowFacts: Equatable {
    var id: CGWindowID
    var bundleID: String
    var appName: String
    var title: String
    /// In points, from the top left of the main screen (the same space as a screen's frame).
    var frame: CGRect
    var layer: Int
    /// On the desktop you are looking at. A window on another desktop is not, and an app that has gone full screen lives on one of its own.
    var onScreen: Bool
    /// An ordinary app with a Dock icon, rather than a helper or a menu bar app.
    var regularApp: Bool
}

extension WindowFacts {
    init?(_ window: SCWindow) {
        guard let app = window.owningApplication else { return nil }
        self.init(id: window.windowID, bundleID: app.bundleIdentifier, appName: app.applicationName, title: window.title ?? "",
                  frame: window.frame, layer: window.windowLayer, onScreen: window.isOnScreen,
                  regularApp: NSRunningApplication(processIdentifier: app.processID)?.activationPolicy == .regular)
    }
}

enum WindowFinder {
    /// An ordinary window big enough to be worth sharing: not a menu, a tooltip or a small panel.
    static func isShareable(_ window: WindowFacts) -> Bool {
        window.layer == 0 && window.frame.width > 200 && window.frame.height > 150
    }

    /// Whether a window covers a screen the way an app that has gone full screen does: as wide as the screen, and reaching from the menu bar
    /// (or the notch) to the bottom. `screens` are in the same space as the window's frame.
    static func fillsAScreen(_ frame: CGRect, screens: [CGRect]) -> Bool {
        screens.contains { screen in
            abs(frame.width - screen.width) <= 2 && abs(frame.minX - screen.minX) <= 2
                && frame.minY >= screen.minY - 2 && frame.minY - screen.minY <= 100
                && frame.height >= screen.height - 100 && frame.height <= screen.height + 2
        }
    }

    /// The windows to offer for sharing: everything on this desktop, and the full-screen ones on other desktops. A window on another
    /// desktop that is not full screen is left out, since from here it cannot be told from one that is hidden or minimised; the picker
    /// checks that the full-screen ones can really be captured.
    static func listable(_ windows: [WindowFacts], screens: [CGRect], excluding bundleID: String?) -> [WindowFacts] {
        windows.filter { window in
            window.bundleID != bundleID && isShareable(window)
                && (window.onScreen || (window.regularApp && fillsAScreen(window.frame, screens: screens)))
        }
    }

    /// The window to capture for an app. The window itself if it is still open, wherever it is now: going full screen keeps its id and
    /// moves it to another desktop, and it is captured from there just the same. Failing that, its replacement (the app was reopened, or
    /// a slideshow opened its own window): one with the same title, or else the largest, looking at what is on this desktop first and
    /// then at full-screen windows on other desktops.
    static func pick(bundleID: String, title: String?, windowID: CGWindowID?, among windows: [WindowFacts], screens: [CGRect]) -> WindowFacts? {
        let mine = windows.filter { $0.bundleID == bundleID && isShareable($0) }
        if let windowID, let same = mine.first(where: { $0.id == windowID }) { return same }
        let wanted = title.flatMap { $0.isEmpty ? nil : $0 }
        let pools = [mine.filter(\.onScreen), mine.filter { !$0.onScreen && fillsAScreen($0.frame, screens: screens) }]
        for pool in pools {
            let named = wanted.flatMap { text in pool.first { $0.title.localizedCaseInsensitiveContains(text) } }
            if let found = named ?? pool.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) { return found }
        }
        return nil
    }
}

/// A picture of a window that is on another desktop, such as an app that has gone full screen. ScreenCaptureKit's one-shot screenshot
/// refuses those but a stream captures them, so this takes the first frame of a short stream. It gives nil when no picture arrives, which
/// is what a hidden or minimised window does, so it also says which windows can be shared at all.
final class WindowSnapshot: NSObject, SCStreamOutput, @unchecked Sendable {
    private static let context = CIContext()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var finished = false
    private var picture: CGImage?

    static func capture(_ window: SCWindow, longSide: CGFloat = 960, timeout: Double = 1.2) async -> CGImage? {
        await WindowSnapshot().run(window, longSide: longSide, timeout: timeout)
    }

    private func run(_ window: SCWindow, longSide: CGFloat, timeout: Double) async -> CGImage? {
        let scale = min(1, longSide / max(window.frame.width, window.frame.height, 1))
        let configuration = SCStreamConfiguration()
        configuration.width = max(2, Int(window.frame.width * scale))
        configuration.height = max(2, Int(window.frame.height * scale))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: nil)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "app.backdrop.window-snapshot"))
            try await stream.startCapture()
        } catch {
            return nil
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak self] in self?.deliver(nil) }
        let image = await withCheckedContinuation { (waiting: CheckedContinuation<CGImage?, Never>) in
            let ready = lock.withLock { () -> (done: Bool, image: CGImage?) in
                if finished { return (true, picture) }
                continuation = waiting
                return (false, nil)
            }
            if ready.done { waiting.resume(returning: ready.image) }
        }
        try? await stream.stopCapture()
        return image
    }

    private func deliver(_ image: CGImage?) {
        let waiting = lock.withLock { () -> CheckedContinuation<CGImage?, Never>? in
            guard !finished else { return nil }
            finished = true
            picture = image
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(returning: image)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        deliver(Self.context.createCGImage(image, from: image.extent))
    }
}
