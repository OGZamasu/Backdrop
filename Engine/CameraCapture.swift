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

    /// The name our own virtual camera advertises. Never capture from it: that's a feedback loop.
    static let virtualCameraName = "Backdrop Camera"

    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified)
            .devices.filter { $0.localizedName != virtualCameraName }
    }

    /// Frames arrive on `queue`.
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private let queue: DispatchQueue
    private let sessionQueue = DispatchQueue(label: "app.backdrop.camera-session")
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()

    init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
    }

    var isRunning: Bool { session.isRunning }

    /// Starts capture without blocking the caller. `completion` reports setup errors.
    func start(deviceID: String?, completion: @escaping (Error?) -> Void = { _ in }) {
        sessionQueue.async {
            do {
                try self.configure(deviceID: deviceID)
                self.session.startRunning()
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func stop() {
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

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
        onFrame?(buffer, sampleBuffer.presentationTimeStamp)
    }
}
