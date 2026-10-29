import AVFoundation
import AppKit
import Carbon.HIToolbox
import Combine
import ScreenCaptureKit
import ServiceManagement

struct WindowChoice: Identifiable, Hashable {
    let id: CGWindowID
    let bundleID: String
    let appName: String
    let title: String
}

@MainActor
final class AppModel: ObservableObject {
    // MARK: Collaborators

    let library = BackgroundLibrary()
    let rules = RuleStore()
    let installer = ExtensionInstaller()
    let preview = PreviewRelay()

    private let pipeline = FramePipeline()
    private let camera: CameraCapture
    private let sink = VirtualCameraSink()
    private let automation: AutomationEngine
    private let hotkeys = HotKeyCenter()
    private let defaults = UserDefaults.standard
    private var forwarding = Set<AnyCancellable>()
    private var activity: NSObjectProtocol?
    private var reportedPipelineStall = false

    // MARK: State

    @Published private(set) var isOn = false
    @Published private(set) var isStarting = false
    @Published private(set) var virtualCameraInstalled = false
    @Published private(set) var cameras: [AVCaptureDevice] = []
    @Published private(set) var selectedID: UUID
    /// A problem worth showing the user, such as a denied permission.
    @Published var message: String?
    @Published private(set) var launchAtLogin: Bool
    /// Whether frames are actually reaching the Backdrop Camera extension.
    @Published private(set) var sinkConnected = false
    /// macOS's own Background or Portrait effect is switched on for Backdrop's camera input. It would fight with the
    /// backdrop chosen here, and an app can't turn it off itself: it's a Control Center setting.
    @Published private(set) var systemEffectsOn = false

    /// Lets the menu bar popover open the Studio on a particular pane, or straight into an action.
    enum StudioRequest { case importFile, liveWindow, generate }
    @Published var studioPane: StudioView.Pane = .backgrounds
    @Published var studioRequest: StudioRequest?

    @Published var cameraID: String? {
        didSet {
            defaults.set(cameraID, forKey: Keys.camera)
            if isOn { camera.start(deviceID: cameraID) { [weak self] in self?.report($0) } }
        }
    }
    @Published var quality: PersonSegmenter.Quality {
        didSet { defaults.set(quality.rawValue, forKey: Keys.quality); pipeline.setQuality(quality) }
    }
    @Published var edgeSoftness: Double { didSet { defaults.set(edgeSoftness, forKey: Keys.edge); pushLook() } }
    @Published var lightWrap: Double { didSet { defaults.set(lightWrap, forKey: Keys.wrap); pushLook() } }
    @Published var colorMatch: Double { didSet { defaults.set(colorMatch, forKey: Keys.match); pushLook() } }

    private enum Keys {
        static let camera = "cameraID", quality = "quality", edge = "edgeSoftness"
        static let wrap = "lightWrap", match = "colorMatch", selected = "selectedBackground"
    }

    var selectedBackground: Background { library.background(withID: selectedID) ?? .off }

    // MARK: Lifecycle

    init() {
        camera = CameraCapture(queue: pipeline.queue)
        automation = AutomationEngine(store: rules)

        let saved = defaults.string(forKey: Keys.selected).flatMap(UUID.init(uuidString:))
        selectedID = saved ?? Background.softBlur.id
        cameraID = defaults.string(forKey: Keys.camera)
        quality = defaults.string(forKey: Keys.quality).flatMap(PersonSegmenter.Quality.init(rawValue:)) ?? .balanced
        edgeSoftness = defaults.object(forKey: Keys.edge) as? Double ?? CompositeParameters().edgeSoftness
        lightWrap = defaults.object(forKey: Keys.wrap) as? Double ?? CompositeParameters().lightWrap
        colorMatch = defaults.object(forKey: Keys.match) as? Double ?? CompositeParameters().colorMatch
        launchAtLogin = SMAppService.mainApp.status == .enabled
        cameras = CameraCapture.availableDevices()

        // Views watch the model, so changes in the library and rules need to reach it.
        library.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &forwarding)
        rules.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &forwarding)
        installer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &forwarding)

        wirePipeline()
        if library.background(withID: selectedID) == nil { selectedID = Background.softBlur.id }
        applySelection()
        pushLook()
        pipeline.setQuality(quality)

        automation.onMatch = { [weak self] rule in
            guard let self, let background = self.library.background(withID: rule.backgroundID) else { return }
            self.select(background.id)
            HUD.shared.show(background.name)
        }
        automation.start()
        installer.updateIfOutdated()
        registerHotkeys()
        observeDevices()
        startPolling()
    }

    private func wirePipeline() {
        // Both run on the pipeline queue.
        camera.onFrame = { [pipeline] buffer, time in pipeline.process(buffer, at: time) }
        camera.onStatus = { [weak self] status in Task { @MainActor in self?.cameraStatus(status) } }
        pipeline.onOutput = { [sink] buffer, _ in sink.send(buffer) }
        pipeline.onPreview = { [preview] image in preview.show(image) }
        preview.onDemandChanged = { [pipeline] wanted in pipeline.setPreviewEnabled(wanted) }
    }

    // MARK: Camera on / off

    func toggle() { isOn ? turnOff() : turnOn() }

    func turnOn() {
        guard !isOn, !isStarting else { return }
        isStarting = true
        message = nil
        Task { [weak self] in
            guard await Self.cameraAccess() else {
                self?.message = "Camera access is off. Allow Backdrop in System Settings › Privacy & Security › Camera."
                self?.isStarting = false
                return
            }
            guard let self else { return }
            camera.start(deviceID: cameraID) { error in
                Task { @MainActor in
                    self.isStarting = false
                    if let error { self.report(error); return }
                    self.isOn = true
                    self.pipeline.markStarted()
                    self.beginActivity()
                    self.sink.connect()
                }
            }
        }
    }

    func turnOff() {
        camera.stop()
        pipeline.stop()
        sink.disconnect()
        preview.show(nil)
        endActivity()
        isOn = false
    }

    /// While the camera is on this is live video, and it comes from a menu bar app that is never in front. Without
    /// saying so, macOS is free to throttle it (App Nap) just when another app has the focus.
    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                                                         reason: "Backdrop is sending live video to other apps")
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func cameraStatus(_ status: CameraCapture.Status) {
        switch status {
        case .stalled: message = "The camera stopped sending video, so Backdrop is restarting it."
        case .recovered: if message?.hasPrefix("The camera stopped") == true { message = nil }
        }
    }

    /// The camera is delivering but nothing comes out the other end: processing is stuck. Log it, once per episode.
    private func watchPipeline() {
        let quiet = pipeline.secondsSinceOutput
        if quiet > 3, camera.secondsSinceFrame < 1.5 {
            if !reportedPipelineStall {
                reportedPipelineStall = true
                Log.pipeline.notice("no finished frames for \(Int(quiet), privacy: .public) s although the camera is delivering")
            }
        } else if quiet < 1 {
            reportedPipelineStall = false
        }
    }

    private static func cameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func report(_ error: Error?) {
        if let error { message = error.localizedDescription }
    }

    // MARK: Choosing backgrounds

    func select(_ id: UUID) {
        guard library.background(withID: id) != nil else { return }
        selectedID = id
        defaults.set(id.uuidString, forKey: Keys.selected)
        applySelection()
    }

    func cycle(by step: Int) {
        let items = library.items
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selectedID } ?? 0
        let next = items[(index + step + items.count) % items.count]
        select(next.id)
        HUD.shared.show(next.name)
    }

    private func applySelection() {
        let background = selectedBackground
        let source = BackgroundSourceFactory.make(for: background, library: library)
        (source as? WindowCaptureSource)?.onError = { [weak self] text in
            Task { @MainActor in self?.message = text }
        }
        pipeline.setBackground(background, source: source)
    }

    // MARK: Editing the library

    func importFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { select(try library.importFile(at: url).id) } catch { message = error.localizedDescription }
        }
    }

    func addWindow(_ choice: WindowChoice) { select(library.addWindow(bundleID: choice.bundleID, appName: choice.appName, title: choice.title).id) }
    func addScreen() { select(library.addDisplay().id) }

    func saveGenerated(from url: URL, prompt: String) {
        do { select(try library.addGenerated(from: url, prompt: prompt).id) } catch { message = error.localizedDescription }
    }

    func setParallax(_ on: Bool, for id: UUID) {
        library.update(id) { $0.parallax = on }
        if let updated = library.background(withID: id) { pipeline.updateCurrentBackground(updated) }
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        library.update(id) { $0.name = trimmed }
    }

    func delete(_ id: UUID) {
        let wasSelected = id == selectedID
        library.remove(id)
        rules.forget(background: id)
        if wasSelected { select(Background.off.id) }
    }

    /// Windows that can be used as a live backdrop. Asks for Screen Recording the first time.
    func availableWindows() async -> [WindowChoice] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else {
            message = "Allow Backdrop in System Settings › Privacy & Security › Screen Recording to use a window as your background."
            return []
        }
        let me = Bundle.main.bundleIdentifier
        return content.windows.compactMap { window in
            guard let app = window.owningApplication, app.bundleIdentifier != me,
                  window.windowLayer == 0, window.frame.width > 200, window.frame.height > 150 else { return nil }
            return WindowChoice(id: window.windowID, bundleID: app.bundleIdentifier, appName: app.applicationName, title: window.title ?? "")
        }
        .sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
    }

    // MARK: Settings

    private func pushLook() {
        pipeline.setParameters(CompositeParameters(edgeSoftness: edgeSoftness, lightWrap: lightWrap, colorMatch: colorMatch))
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Starts a fresh copy and quits this one. A process only learns about a camera that appeared after it launched
    /// through CoreMediaIO's run loop; relaunching is the dependable way to start from a clean view of the devices.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Opens macOS's Video Effects panel, where Background and Portrait are switched off.
    func showVideoEffects() { AVCaptureDevice.showSystemUserInterface(.videoEffects) }

    func requestCalendarAccess() async -> Bool { await automation.requestCalendarAccess() }

    /// Shown under calendar rules so a rule that can't fire says why.
    var calendarAccessLabel: String? { automation.calendarAccessGranted ? nil : "Needs calendar access. Add the rule again to grant it." }

    // MARK: Hot keys, devices, polling

    private func registerHotkeys() {
        let modifiers = controlKey | optionKey
        let registered = [
            hotkeys.register(keyCode: kVK_RightArrow, modifiers: modifiers) { [weak self] in MainActor.assumeIsolated { self?.cycle(by: 1) } },
            hotkeys.register(keyCode: kVK_LeftArrow, modifiers: modifiers) { [weak self] in MainActor.assumeIsolated { self?.cycle(by: -1) } },
            hotkeys.register(keyCode: kVK_ANSI_B, modifiers: modifiers) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.toggle()
                    HUD.shared.show(self.isOn || self.isStarting ? "Camera on" : "Camera off")
                }
            },
        ]
        if registered.contains(false) { message = "Some keyboard shortcuts are taken by another app." }
    }

    private func observeDevices() {
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.cameras = CameraCapture.availableDevices() }
                .store(in: &forwarding)
        }
    }

    /// The extension can appear or vanish at any time (approval, update, removal), so keep checking.
    private func startPolling() {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let present = self.sink.isDevicePresent
                if present != self.virtualCameraInstalled { self.virtualCameraInstalled = present }
                let effectsOn = AVCaptureDevice.isBackgroundReplacementEnabled || AVCaptureDevice.isPortraitEffectEnabled
                if effectsOn != self.systemEffectsOn { self.systemEffectsOn = effectsOn }
                if self.isOn {
                    if present { self.sink.connect() } else { self.sink.disconnect() }
                    if let problem = self.sink.healthProblem() {
                        // The extension restarted or jammed. Rebuild the connection rather than feed a dead one.
                        Log.sink.notice("reconnecting: \(problem, privacy: .public)")
                        self.sink.disconnect()
                        self.sink.connect()
                    }
                    self.watchPipeline()
                }
                let connected = self.sink.isConnected
                if connected != self.sinkConnected { self.sinkConnected = connected }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
