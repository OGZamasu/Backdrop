import AVFoundation

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum CameraError: LocalizedError {
        case noCamera
        case cannotUse(String)
        var errorDescription: String? {
            switch self {
            case .noCamera: return "No camera found."
            case .cannotUse(let name): return "Backdrop can't use \(name)."
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
    private let sessionQueue = DispatchQueue(label: "app.backdrop.camera-session")
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()

    // Shared between the pipeline queue (frames arrive), the session queue (watchdog) and the main thread.
    private let lock = NSLock()
    private var lastFrameAt = CFAbsoluteTimeGetCurrent()
    private var wantsRunning = false
    private var deviceID: String?
    private var stallReported = false

    // Session queue only.
    private var watchdog = StallWatchdog()
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
        observeSession()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        timer?.cancel()
    }

    var isRunning: Bool { session.isRunning }

    /// Seconds since the camera last delivered a frame.
    var secondsSinceFrame: TimeInterval { lock.withLock { CFAbsoluteTimeGetCurrent() - lastFrameAt } }

    /// Starts capture without blocking the caller. `completion` reports setup errors.
    /// Once started, it keeps itself going: a camera that errors out or goes quiet is restarted.
    func start(deviceID: String?, completion: @escaping (Error?) -> Void = { _ in }) {
        sessionQueue.async {
            self.lock.withLock {
                self.wantsRunning = true
                self.deviceID = deviceID
                self.lastFrameAt = CFAbsoluteTimeGetCurrent()
                self.stallReported = false
            }
            self.watchdog = StallWatchdog()
            do {
                try self.configure(deviceID: deviceID)
                self.session.startRunning()
                self.startWatchdog()
                Log.camera.notice("capture started")
                completion(nil)
            } catch {
                Log.camera.error("capture failed to start: \(error.localizedDescription, privacy: .public)")
                completion(error)
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.lock.withLock { self.wantsRunning = false }
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
            self?.sessionQueue.async { self?.restartIfWanted(reason: "runtime error") }
        })
        // The system can stop a session for its own reasons. Stopping it ourselves also posts this, and
        // in that case `wantsRunning` is false or the session is already running again, so nothing happens.
        observers.append(center.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: session, queue: nil) { [weak self] _ in
            self?.sessionQueue.async {
                guard let self, self.lock.withLock({ self.wantsRunning }), !self.session.isRunning else { return }
                Log.camera.notice("capture session stopped on its own")
                self.restartIfWanted(reason: "stopped by the system")
            }
        })
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
        let (last, wants) = lock.withLock { (lastFrameAt, wantsRunning) }
        guard wants else { return }
        let now = CFAbsoluteTimeGetCurrent()
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
        let (wants, device) = lock.withLock { (wantsRunning, deviceID) }
        guard wants else { return }
        Log.camera.notice("restarting capture (\(reason, privacy: .public))")
        if session.isRunning { session.stopRunning() }
        do {
            try configure(deviceID: device)
            session.startRunning()
        } catch {
            // The camera may simply be gone (unplugged, lid shut). The watchdog tries again shortly.
            Log.camera.error("couldn't restart capture: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Setup

    private func configure(deviceID: String?) throws {
        guard let device = deviceID.flatMap({ AVCaptureDevice(uniqueID: $0) }) ?? Self.availableDevices().first else {
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
        let recovered = lock.withLock { () -> Bool in
            lastFrameAt = CFAbsoluteTimeGetCurrent()
            defer { stallReported = false }
            return stallReported
        }
        if recovered {
            Log.camera.notice("frames flowing again")
            onStatus?(.recovered)
        }
        onFrame?(buffer, sampleBuffer.presentationTimeStamp)
    }
}
