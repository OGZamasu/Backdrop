import AVFoundation
import AppKit

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum CameraError: LocalizedError {
        case noCamera
        case cannotUse(String)
        case suspended
        var errorDescription: String? {
            switch self {
            case .noCamera: return "No camera found."
            case .cannotUse(let name): return "Backdrop can't use \(name)."
            case .suspended: return "Camera capture is unavailable while the Mac is asleep or the camera is interrupted."
            }
        }
    }

    /// Told when the camera stops sending frames and when it starts again, on an arbitrary queue.
    enum Status { case stalled, recovered }

    /// The name our own virtual camera advertises. Never capture from it: that's a feedback loop.
    static let virtualCameraName = "Backdrop Camera"

    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified)
            .devices.filter { $0.localizedName != virtualCameraName }
    }

    /// Frames arrive on `queue`.
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    var onStatus: ((Status) -> Void)?

    private let queue: DispatchQueue
    /// A strict capture only ever uses the camera it was asked for. The main one falls back to the first camera it can find, which is
    /// right for the camera you chose last week and unplugged; a second camera must never quietly turn into some other camera.
    private let strict: Bool
    private let sessionQueue = DispatchQueue(label: "app.backdrop.camera-session")
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()

    // Shared between the pipeline queue (frames arrive), the session queue (watchdog) and the main thread.
    private let lock = NSLock()
    private var lastFrameAt = CFAbsoluteTimeGetCurrent()
    private var lifecycle = CameraLifecycle()
    private var deviceID: String?
    private var stallReported = false

    // Session queue only.
    private var watchdog = StallWatchdog()
    private var recoveryGraceUntil: CFAbsoluteTime = 0
    private var needsConfiguration = false
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    init(queue: DispatchQueue, strict: Bool = false) {
        self.queue = queue
        self.strict = strict
        super.init()
        observeSession()
        observeWorkspace()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        timer?.cancel()
    }

    var isRunning: Bool { session.isRunning }

    /// Seconds since the camera last delivered a frame.
    var secondsSinceFrame: TimeInterval { lock.withLock { CFAbsoluteTimeGetCurrent() - lastFrameAt } }

    /// Starts capture without blocking the caller. `completion` reports setup errors.
    /// Once started, it keeps itself going: a camera that errors out or goes quiet is restarted.
    func start(deviceID: String?, completion: @escaping (Error?) -> Void = { _ in }) {
        sessionQueue.async {
            let (previous, previousDevice) = self.lock.withLock { (self.lifecycle, self.deviceID) }
            // A previously active capture can accept a new device while suspended and resume it later.
            // An initial start must fail instead of silently starting a camera after the UI reported failure.
            guard !previous.isSleeping && !previous.isInterrupted || previous.wantsRunning else {
                completion(CameraError.suspended)
                return
            }
            self.lock.withLock {
                self.lifecycle.wantsRunning = true
                self.deviceID = deviceID
                self.lastFrameAt = CFAbsoluteTimeGetCurrent()
                self.stallReported = false
            }
            guard self.lock.withLock({ self.lifecycle.canRun }) else {
                self.needsConfiguration = true
                completion(nil)
                return
            }
            self.watchdog = StallWatchdog()
            do {
                try self.configure(deviceID: deviceID)
                self.needsConfiguration = false
                if self.lock.withLock({ self.lifecycle.canRun }) {
                    self.session.startRunning()
                    self.startWatchdog()
                }
                Log.camera.notice("capture started")
                completion(nil)
            } catch {
                self.lock.withLock {
                    self.lifecycle.wantsRunning = previous.wantsRunning
                    if !previous.wantsRunning { self.lifecycle.isInterrupted = false }
                    self.deviceID = previousDevice
                }
                Log.camera.error("capture failed to start: \(error.localizedDescription, privacy: .public)")
                completion(error)
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.lock.withLock {
                self.lifecycle.wantsRunning = false
                self.lifecycle.isInterrupted = false
            }
            self.timer?.cancel()
            self.timer = nil
            if self.session.isRunning { self.session.stopRunning() }
            Log.camera.notice("capture stopped")
        }
    }

    // MARK: Staying alive

    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            Log.camera.error("capture session error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            self?.sessionQueue.async { self?.checkForStall() }
        })
        // The system can stop a session for its own reasons. Stopping it ourselves also posts this, and
        // in that case `wantsRunning` is false or the session is already running again, so nothing happens.
        observers.append(center.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: session, queue: nil) { [weak self] _ in
            self?.sessionQueue.async {
                guard let self, self.lock.withLock({ self.lifecycle.canRun }), !self.session.isRunning else { return }
                Log.camera.notice("capture session stopped on its own")
                self.checkForStall()
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock {
                if self.lifecycle.wantsRunning { self.lifecycle.isInterrupted = true }
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock {
                self.lifecycle.isInterrupted = false
            }
            self.sessionQueue.async { self.resumeIfPossible() }
        })
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.lifecycle.isSleeping = true }
            self.sessionQueue.async {
                guard self.lock.withLock({ self.lifecycle.isSleeping }) else { return }
                self.timer?.cancel()
                self.timer = nil
                // Keep the session alive while asleep. macOS suspends the camera itself;
                // stopping here could suppress interruption-ended and strand recovery.
                Log.camera.notice("capture suspended for sleep")
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.lifecycle.isSleeping = false }
            self.sessionQueue.async { self.resumeIfPossible() }
        })
    }

    /// Reset the stale-frame baseline after any suspension before considering recovery.
    private func resumeIfPossible() {
        guard lock.withLock({ lifecycle.canRun }) else { return }
        let now = CFAbsoluteTimeGetCurrent()
        lock.withLock { lastFrameAt = now }
        watchdog = StallWatchdog()
        recoveryGraceUntil = now + watchdog.quietLimit
        if !session.isRunning || needsConfiguration { restartIfWanted(reason: "resumed") }
        if lock.withLock({ lifecycle.canRun }) { startWatchdog() }
    }

    private func startWatchdog() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.checkForStall() }
        timer.resume()
        self.timer = timer
    }

    private func checkForStall() {
        let (last, canRun) = lock.withLock { (lastFrameAt, lifecycle.canRun) }
        guard canRun else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now >= recoveryGraceUntil else { return }
        guard watchdog.shouldRestart(now: now, lastFrame: last, sessionRunning: session.isRunning) else { return }

        Log.camera.notice("no frames for \(String(format: "%.1f", now - last), privacy: .public) s (session running: \(self.session.isRunning, privacy: .public))")
        let firstReport = lock.withLock { () -> Bool in
            defer { stallReported = true }
            return !stallReported
        }
        if firstReport { onStatus?(.stalled) }
        restartIfWanted(reason: "stalled")
    }

    private func restartIfWanted(reason: String) {
        let (canRun, device) = lock.withLock { (lifecycle.canRun, deviceID) }
        guard canRun else { return }
        Log.camera.notice("restarting capture (\(reason, privacy: .public))")
        if session.isRunning { session.stopRunning() }
        guard lock.withLock({ lifecycle.canRun }) else { return }
        do {
            try configure(deviceID: device)
            needsConfiguration = false
            if lock.withLock({ lifecycle.canRun }) { session.startRunning() }
        } catch {
            // The camera may simply be gone (unplugged, lid shut). The watchdog tries again shortly.
            Log.camera.error("couldn't restart capture: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Setup

    private func configure(deviceID: String?) throws {
        let asked = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) }
        guard let device = asked ?? (strict ? nil : Self.availableDevices().first) else {
            throw CameraError.noCamera
        }
        let input: AVCaptureDeviceInput
        do { input = try AVCaptureDeviceInput(device: device) } catch { throw CameraError.cannotUse(device.localizedName) }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach { session.removeInput($0) }
        guard session.canAddInput(input) else { throw CameraError.cannotUse(device.localizedName) }
        session.addInput(input)
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high

        if !session.outputs.contains(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            // Better to skip a frame than to fall behind and lag your voice.
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = sampleBuffer.imageBuffer else { return }
        let (deliver, recovered) = lock.withLock { () -> (Bool, Bool) in
            guard lifecycle.canRun else { return (false, false) }
            lastFrameAt = CFAbsoluteTimeGetCurrent()
            defer { stallReported = false }
            return (true, stallReported)
        }
        guard deliver else { return }
        if recovered {
            Log.camera.notice("frames flowing again")
            onStatus?(.recovered)
        }
        onFrame?(buffer, sampleBuffer.presentationTimeStamp)
    }
}
