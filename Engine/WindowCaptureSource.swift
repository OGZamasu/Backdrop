import CoreImage
import CoreMedia
import ScreenCaptureKit

/// How a screen or window is captured: whether the pointer shows, and how many frames a second.
struct CaptureOptions: Equatable {
    var showsCursor = true
    /// 30 or 60.
    var framesPerSecond = 30
}

/// A live window or screen as your backdrop: slides, a dashboard, a terminal, anything.
final class WindowCaptureSource: NSObject, BackgroundSource, SCStreamOutput, SCStreamDelegate {
    enum Target: Equatable {
        /// A window, found by its id when it is still open, otherwise by app (and title).
        case window(bundleID: String, title: String?, windowID: CGWindowID? = nil)
        /// A particular screen, or the main one for nil.
        case display(CGDirectDisplayID?)
    }

    var fitsContent: Bool { true }
    /// Called on an arbitrary queue if capture can't start (most often: Screen Recording not allowed).
    var onError: ((String) -> Void)?
    /// Called on an arbitrary queue whenever `status` changes.
    var onStatus: ((StageContentStatus) -> Void)?

    private let target: Target
    private let lock = NSLock()
    private var stream: SCStream?
    private var configuration: SCStreamConfiguration?
    private var latest: CVPixelBuffer?
    /// The part of `latest` that holds the window, in Core Image's pixel coordinates (origin lower left).
    private var crop: CGRect?
    private var generation = 0
    private var options: CaptureOptions
    private var paused = false
    private var state = StageContentStatus.starting
    private var retry: DispatchWorkItem?
    /// When the window's shape has differed from the stream's for a while, the stream is resized to match.
    private var mismatchSince: CFTimeInterval?

    init(target: Target, options: CaptureOptions = CaptureOptions()) {
        self.target = target
        self.options = options
    }

    /// What the capture is doing right now.
    var status: StageContentStatus { lock.withLock { paused && state == .live ? .paused : state } }

    func start() {
        let mine = lock.withLock { () -> Int in generation += 1; return generation }
        Task { [weak self] in await self?.begin(generation: mine) }
    }

    func stop() {
        let old = lock.withLock { () -> SCStream? in
            generation += 1
            retry?.cancel()
            retry = nil
            defer { stream = nil; latest = nil; crop = nil }
            return stream
        }
        if let old { Task { try? await old.stopCapture() } }
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        let (buffer, crop) = lock.withLock { (latest, self.crop) }
        guard let buffer else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let crop, crop.width > 8, crop.height > 8 else { return image }
        return image.cropped(to: crop)
    }

    /// Shows or hides the pointer, or changes the frame rate, without restarting.
    func setOptions(_ new: CaptureOptions) {
        let (stream, config) = lock.withLock { () -> (SCStream?, SCStreamConfiguration?) in
            options = new
            return (stream, configuration)
        }
        guard let stream, let config else { return }
        apply(to: config)
        Task { try? await stream.updateConfiguration(config) }
    }

    /// While paused nothing new is shown, so ask for very few frames: it saves the work of capturing a screen nobody sees.
    func setPaused(_ on: Bool) {
        let (stream, config, changed) = lock.withLock { () -> (SCStream?, SCStreamConfiguration?, Bool) in
            let changed = paused != on
            paused = on
            return (stream, configuration, changed)
        }
        if changed { onStatus?(status) }
        guard changed, let stream, let config else { return }
        apply(to: config)
        Task { try? await stream.updateConfiguration(config) }
    }

    private func apply(to config: SCStreamConfiguration) {
        let (options, paused) = lock.withLock { (self.options, self.paused) }
        let fps = paused ? 2 : max(1, min(60, options.framesPerSecond))
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.showsCursor = options.showsCursor
        config.queueDepth = fps > 30 ? 5 : 3
    }

    private func setState(_ new: StageContentStatus) {
        let changed = lock.withLock { () -> Bool in
            guard state != new else { return false }
            state = new
            return true
        }
        if changed { onStatus?(status) }
    }

    // MARK: Capture

    private func begin(generation mine: Int) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let filter = makeFilter(from: content) else {
                if case .window = target {
                    // The window may simply not be open yet: show the calm card and look again shortly.
                    setState(.lost)
                    scheduleRetry(generation: mine)
                } else {
                    onError?("Couldn't find that screen.")
                }
                return
            }

            let configuration = SCStreamConfiguration()
            let size = Self.pixelSize(filter.contentRect.size, scale: CGFloat(filter.pointPixelScale))
            configuration.width = size.width
            configuration.height = size.height
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            // A window that is resized is scaled to fit the stream and keeps its shape; the frames say where it sits.
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            apply(to: configuration)

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "app.backdrop.window-capture"))
            try await stream.startCapture()

            let stale = lock.withLock { () -> Bool in
                guard generation == mine else { return true }
                self.stream = stream
                self.configuration = configuration
                return false
            }
            if stale { try? await stream.stopCapture() }
        } catch {
            let denied = !CGPreflightScreenCaptureAccess()
            setState(denied ? .denied : .lost)
            onError?(denied ? "Allow Backdrop in System Settings › Privacy & Security › Screen Recording to share your screen."
                            : "Screen capture failed: \(error.localizedDescription)")
            if !denied { scheduleRetry(generation: mine) }
        }
    }

    /// Native pixel size, capped so a 6K display doesn't flood the pipeline.
    static func pixelSize(_ points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        var width = points.width * scale
        var height = points.height * scale
        let cap: CGFloat = 2560
        if width > cap { height *= cap / width; width = cap }
        if height > cap { width *= cap / height; height = cap }
        return (max(Int(width), 2), max(Int(height), 2))
    }

    /// Looks for a lost window again in a couple of seconds, so it comes back on its own when it is opened again.
    private func scheduleRetry(generation mine: Int) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lock.withLock({ self.generation == mine && self.stream == nil }) else { return }
            Task { await self.begin(generation: mine) }
        }
        lock.withLock {
            retry?.cancel()
            retry = work
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func makeFilter(from content: SCShareableContent) -> SCContentFilter? {
        switch target {
        case .display(let id):
            let chosen = id.flatMap { want in content.displays.first { $0.displayID == want } }
            let main = content.displays.first { $0.displayID == CGMainDisplayID() }
            guard let display = chosen ?? main ?? content.displays.first else { return nil }
            // Leave our own windows out, or the preview becomes a hall of mirrors.
            let ours = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
            return SCContentFilter(display: display, excludingWindows: ours)

        case .window(let bundleID, let title, let windowID):
            let candidates = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == bundleID && $0.frame.width > 200 && $0.frame.height > 150
            }
            let exact = windowID.flatMap { id in candidates.first { $0.windowID == id } }
            let named = title.flatMap { wanted in candidates.first { ($0.title ?? "").localizedCaseInsensitiveContains(wanted) } }
            let largest = candidates.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            guard let window = exact ?? named ?? largest else { return nil }
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    // MARK: SCStreamOutput / SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, let frameStatus = SCFrameStatus(rawValue: raw) else { return }
        switch frameStatus {
        case .complete:
            guard let buffer = sampleBuffer.imageBuffer else { return }
            let crop = Self.contentCrop(info, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            lock.withLock {
                latest = buffer
                self.crop = crop
            }
            setState(.live)
            resizeIfShapeChanged(crop: crop, buffer: buffer)
        case .stopped:
            setState(.lost)
        default:
            // Idle (nothing changed), blank or suspended (minimised): keep showing the last frame.
            break
        }
    }

    /// Where the window sits inside the frame, in Core Image's pixel coordinates. ScreenCaptureKit reports it in points from the top
    /// left; the conversion is checked against the buffer so a surprise in the units can never crop away the picture.
    static func contentCrop(_ info: [SCStreamFrameInfo: Any], width: Int, height: Int) -> CGRect? {
        guard let dict = info[.contentRect] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: dict as CFDictionary),
              rect.width > 0, rect.height > 0 else { return nil }
        let scale = (info[.scaleFactor] as? CGFloat) ?? 1
        let contentScale = (info[.contentScale] as? CGFloat) ?? 1
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let options = [scale, scale * contentScale, 1].map { k in
            CGRect(x: rect.minX * k, y: rect.minY * k, width: rect.width * k, height: rect.height * k)
        }
        guard let pixels = options.first(where: { $0.maxX <= bounds.maxX + 2 && $0.maxY <= bounds.maxY + 2 && $0.width >= bounds.width * 0.2 }) else {
            return nil
        }
        let flipped = CGRect(x: pixels.minX, y: CGFloat(height) - pixels.maxY, width: pixels.width, height: pixels.height)
            .integral.intersection(bounds)
        // Close enough to the whole frame: use the whole frame.
        if abs(flipped.width - bounds.width) < 3, abs(flipped.height - bounds.height) < 3 { return nil }
        return flipped
    }

    /// A window that has changed shape is letterboxed inside the stream. Once it has stayed that way for half a second, the stream
    /// is resized to the new shape so no resolution is wasted on the bars.
    private func resizeIfShapeChanged(crop: CGRect?, buffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        guard let crop else { lock.withLock { mismatchSince = nil }; return }
        let w = CGFloat(CVPixelBufferGetWidth(buffer)), h = CGFloat(CVPixelBufferGetHeight(buffer))
        let mismatch = abs(crop.width / crop.height - w / h) / (w / h) > 0.03
        let (stream, config, due) = lock.withLock { () -> (SCStream?, SCStreamConfiguration?, Bool) in
            if !mismatch { mismatchSince = nil; return (nil, nil, false) }
            let since = mismatchSince ?? now
            mismatchSince = since
            guard now - since > 0.5 else { return (nil, nil, false) }
            mismatchSince = nil
            return (stream, configuration, true)
        }
        guard due, let stream, let config else { return }
        // Keep about the same number of pixels, in the new shape.
        let area = w * h, shape = crop.width / crop.height
        let size = Self.pixelSize(CGSize(width: (area * shape).squareRoot(), height: (area / shape).squareRoot()), scale: 1)
        config.width = size.width
        config.height = size.height
        Task { try? await stream.updateConfiguration(config) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let mine = lock.withLock { () -> Int in
            if self.stream === stream { self.stream = nil; self.configuration = nil }
            return generation
        }
        setState(.lost)
        scheduleRetry(generation: mine)
    }
}
