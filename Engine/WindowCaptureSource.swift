import CoreImage
import CoreMedia
import ScreenCaptureKit

/// A live window or screen as your backdrop: slides, a dashboard, a terminal, anything.
final class WindowCaptureSource: NSObject, BackgroundSource, SCStreamOutput, SCStreamDelegate {
    enum Target {
        case window(bundleID: String, title: String?)
        case display
    }

    var fitsContent: Bool { true }
    /// Called on an arbitrary queue if capture can't start (most often: Screen Recording not allowed).
    var onError: ((String) -> Void)?

    private let target: Target
    private let lock = NSLock()
    private var stream: SCStream?
    private var latest: CVPixelBuffer?
    private var generation = 0

    init(target: Target) { self.target = target }

    func start() {
        let mine = lock.withLock { () -> Int in generation += 1; return generation }
        Task { [weak self] in await self?.begin(generation: mine) }
    }

    func stop() {
        let old = lock.withLock { () -> SCStream? in
            generation += 1
            defer { stream = nil; latest = nil }
            return stream
        }
        if let old { Task { try? await old.stopCapture() } }
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        lock.withLock { latest }.map { CIImage(cvPixelBuffer: $0) }
    }

    // MARK: Capture

    private func begin(generation mine: Int) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let filter = makeFilter(from: content) else {
                onError?("Couldn't find that window. Is the app open?")
                return
            }

            // Capture at native pixel size, capped so a 6K display doesn't flood the pipeline.
            let scale = CGFloat(filter.pointPixelScale)
            var width = filter.contentRect.width * scale
            var height = filter.contentRect.height * scale
            let cap: CGFloat = 2560
            if width > cap { height *= cap / width; width = cap }

            let configuration = SCStreamConfiguration()
            configuration.width = max(Int(width), 2)
            configuration.height = max(Int(height), 2)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = true
            configuration.queueDepth = 3

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "app.backdrop.window-capture"))
            try await stream.startCapture()

            let stale = lock.withLock { () -> Bool in
                guard generation == mine else { return true }
                self.stream = stream
                return false
            }
            if stale { try? await stream.stopCapture() }
        } catch {
            onError?("Screen capture failed: \(error.localizedDescription)")
        }
    }

    private func makeFilter(from content: SCShareableContent) -> SCContentFilter? {
        switch target {
        case .display:
            guard let display = content.displays.first else { return nil }
            // Leave our own windows out, or the preview becomes a hall of mirrors.
            let ours = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
            return SCContentFilter(display: display, excludingWindows: ours)

        case .window(let bundleID, let title):
            let candidates = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == bundleID && $0.frame.width > 200 && $0.frame.height > 150
            }
            let named = title.flatMap { wanted in candidates.first { ($0.title ?? "").localizedCaseInsensitiveContains(wanted) } }
            let largest = candidates.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            guard let window = named ?? largest else { return nil }
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    // MARK: SCStreamOutput / SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        lock.withLock { latest = buffer }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?("Screen capture stopped: \(error.localizedDescription)")
    }
}
