import AVFoundation
import CoreImage

/// A second camera shown in the picture: your desk, your hands at a keyboard, a whiteboard, the room from another angle, an iPhone.
/// It is shared exactly like a window or a screen, so it can sit behind you, float as a panel, or fill the picture with you over it.
///
/// Its camera is only open while it is on the picture. It waits for Backdrop's own camera to be on, and pausing sharing closes it
/// again, so the camera's light is never on for something nobody can see. Unplug it and viewers see a calm card until it is back,
/// and it returns on its own when it is plugged in.
final class ExtraCameraSource: StageContentSource {
    let deviceID: String

    /// A camera may be any shape (a phone held upright is tall), so it is shown whole rather than cropped.
    var fitsContent: Bool { true }
    var needsLiveCamera: Bool { true }

    private let queue = DispatchQueue(label: "app.backdrop.second-camera", qos: .userInteractive)
    private let capture: CameraCapture
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var started = false
    private var paused = false
    private var denied = false
    /// The camera is unplugged, or has stopped sending frames.
    private var lost = false
    private var retry: DispatchSourceTimer?
    private var plugObserver: NSObjectProtocol?

    init(deviceID: String) {
        self.deviceID = deviceID
        capture = CameraCapture(queue: queue, strict: true)
        capture.onFrame = { [weak self] buffer, _ in self?.receive(buffer) }
        capture.onStatus = { [weak self] status in self?.setLost(status == .stalled) }
        // A camera plugged in while viewers are looking at the "disconnected" card should not wait for the next retry.
        plugObserver = NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self, self.lock.withLock({ self.started && !self.paused && self.lost }) else { return }
            self.open()
        }
    }

    deinit {
        if let plugObserver { NotificationCenter.default.removeObserver(plugObserver) }
        retry?.cancel()
        capture.stop()
    }

    /// What the camera is doing right now. Paused wins over everything, since a paused camera is closed.
    var status: StageContentStatus {
        lock.withLock {
            if denied { return .denied }
            if paused { return .paused }
            if lost { return .lost }
            return latest == nil ? .starting : .live
        }
    }

    func start() {
        lock.withLock { started = true }
        run()
    }

    func stop() {
        lock.withLock {
            started = false
            latest = nil
            lost = false
        }
        halt()
    }

    /// Pausing closes the camera, so its light goes off; the last frame is kept for the "Paused" card, and resuming opens it again.
    func setPaused(_ on: Bool) {
        let changed = lock.withLock { () -> Bool in
            defer { paused = on }
            return paused != on
        }
        guard changed else { return }
        if on { halt() } else { run() }
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        guard let buffer = lock.withLock({ latest }) else { return nil }
        return CIImage(cvPixelBuffer: buffer)
    }

    // MARK: Capture

    private func run() {
        guard lock.withLock({ started && !paused }) else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            open()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                if allowed { self?.open() } else { self?.setDenied() }
            }
        default:
            setDenied()
        }
    }

    private func open() {
        guard lock.withLock({ started && !paused }) else { return }
        capture.start(deviceID: deviceID) { [weak self] error in
            guard let self else { return }
            if let error {
                Log.camera.notice("second camera not available: \(error.localizedDescription, privacy: .public)")
                self.setLost(true)
                self.retrySoon()
            } else {
                self.stopRetrying()
                Log.camera.notice("second camera started")
            }
        }
    }

    private func halt() {
        stopRetrying()
        capture.stop()
    }

    /// While the camera cannot be opened (unplugged, or taken by another app) look again every couple of seconds.
    private func retrySoon() {
        lock.withLock {
            guard retry == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(300))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                guard self.lock.withLock({ self.started && !self.paused && self.lost }) else { self.stopRetrying(); return }
                self.open()
            }
            timer.resume()
            retry = timer
        }
    }

    private func stopRetrying() {
        lock.withLock {
            retry?.cancel()
            retry = nil
        }
    }

    // MARK: What the capture reports (internal so tests can drive it without a camera)

    /// A frame arrived: the camera is there.
    func receive(_ buffer: CVPixelBuffer) {
        lock.withLock {
            latest = buffer
            lost = false
        }
    }

    func setLost(_ gone: Bool) {
        lock.withLock { lost = gone }
    }

    func setDenied() {
        lock.withLock { denied = true }
    }
}
