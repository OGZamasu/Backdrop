import AVFoundation

/// One camera that can be shown as a second picture, described without touching the hardware.
struct CameraChoice: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case builtIn, iPhone, deskView, external

        /// The line under the name in the picker.
        var label: String {
            switch self {
            case .builtIn: return "Built-in camera"
            case .iPhone: return "iPhone camera"
            case .deskView: return "Desk View"
            case .external: return "External camera"
            }
        }

        var symbol: String {
            switch self {
            case .builtIn: return "web.camera"
            case .iPhone: return "iphone.gen3"
            case .deskView: return "desktopcomputer"
            case .external: return "video"
            }
        }

        /// Built-in first, then an iPhone, Desk View, and everything else.
        fileprivate var order: Int {
            switch self {
            case .builtIn: return 0
            case .iPhone: return 1
            case .deskView: return 2
            case .external: return 3
            }
        }
    }

    /// The device's unique id: what a saved second camera is found by.
    var id: String
    var name: String
    var kind: Kind
}

/// Which cameras can be a second camera, and which one is already the main camera.
///
/// The main camera is left out (the same camera twice is just a copy of you), and so is Backdrop's own virtual camera, which would
/// feed Backdrop back into itself.
enum ExtraCameras {
    /// The cameras to offer, in a steady order: built-in, iPhone, Desk View, then the others by name. Two cameras with the same name
    /// are told apart with a number, so both can be picked.
    static func choices(from found: [CameraChoice], excluding mainID: String?, virtualName: String = CameraCapture.virtualCameraName) -> [CameraChoice] {
        var seen = Set<String>()
        let usable = found.filter { $0.id != mainID && $0.name != virtualName && seen.insert($0.id).inserted }
        let sorted = usable.sorted {
            ($0.kind.order, $0.name.localizedLowercase, $0.id) < ($1.kind.order, $1.name.localizedLowercase, $1.id)
        }
        var counts: [String: Int] = [:]
        for camera in sorted { counts[camera.name, default: 0] += 1 }
        var number: [String: Int] = [:]
        return sorted.map { camera in
            guard counts[camera.name, default: 0] > 1 else { return camera }
            number[camera.name, default: 0] += 1
            var named = camera
            named.name = "\(camera.name) (\(number[camera.name]!))"
            return named
        }
    }

    /// The camera Backdrop is using as the main one: the one you chose, or else the first one it can find.
    static func mainCameraID(selected: String?, available: [AVCaptureDevice] = CameraCapture.availableDevices()) -> String? {
        if let selected, available.contains(where: { $0.uniqueID == selected }) { return selected }
        return available.first?.uniqueID
    }

    /// Every camera macOS is offering right now, as choices. Looking does not turn any of them on.
    static func discover(excluding mainID: String?) -> [CameraChoice] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera]
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
        return choices(from: devices.map(choice(for:)), excluding: mainID)
    }

    static func choice(for device: AVCaptureDevice) -> CameraChoice {
        CameraChoice(id: device.uniqueID, name: device.localizedName, kind: kind(of: device.deviceType))
    }

    static func kind(of type: AVCaptureDevice.DeviceType) -> CameraChoice.Kind {
        switch type {
        case .builtInWideAngleCamera: return .builtIn
        case .continuityCamera: return .iPhone
        case .deskViewCamera: return .deskView
        default: return .external
        }
    }

    /// Whether the camera a saved background points at is plugged in right now.
    static func isPresent(_ id: String) -> Bool { AVCaptureDevice(uniqueID: id) != nil }
}
