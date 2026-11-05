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
    /// The window's size in points, for its thumbnail's shape.
    var size: CGSize = CGSize(width: 16, height: 10)
}

/// A screen that can be shared.
struct DisplayChoice: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let size: CGSize
    let isMain: Bool
}

@MainActor
final class AppModel: ObservableObject {
    // MARK: Collaborators

    let library = BackgroundLibrary()
    let rules = RuleStore()
    let installer = ExtensionInstaller()
    let preview = PreviewRelay()
    let lensLibrary = LensLibrary()

    private let pipeline = FramePipeline()
    private let camera: CameraCapture
    private let sink = VirtualCameraSink()
    private let automation: AutomationEngine
    private let hotkeys = HotKeyCenter()
    private let defaults = UserDefaults.standard
    private var forwarding = Set<AnyCancellable>()
    private var activity: NSObjectProtocol?
    private var reportedPipelineStall = false
    private var lensPoll: Task<Void, Never>?
    private var changeCounter = 0
    private var lensModified: Date?
    private let scores = DefaultsScoreStore()

    // MARK: State

    @Published private(set) var isOn = false
    @Published private(set) var isStarting = false
    @Published private(set) var virtualCameraInstalled = false
    /// macOS lists the camera extension as installed and enabled, yet no "Backdrop Camera" has turned up for a while.
    /// Seen after an upgrade while other apps were using the camera: the new extension is not started until they let go.
    @Published private(set) var cameraMissing = false
    private var missingMonitor = CameraMissingMonitor()
    private var pollCount = 0
    @Published private(set) var cameras: [AVCaptureDevice] = []
    /// The cameras that could be shown as a second picture: everything plugged in except the main camera and Backdrop's own.
    @Published private(set) var extraCameras: [CameraChoice] = []
    @Published private(set) var selectedID: UUID
    /// A problem worth showing the user, such as a denied permission.
    @Published var message: String?
    @Published private(set) var launchAtLogin: Bool
    /// The small label near the bottom of the screen when a shortcut changes the background or lens.
    @Published var showsOnScreenMessages: Bool {
        didSet { defaults.set(showsOnScreenMessages, forKey: Keys.hud) }
    }
    /// The global keyboard shortcuts. Off gives the keys back to other apps.
    @Published var shortcutsEnabled: Bool {
        didSet { defaults.set(shortcutsEnabled, forKey: Keys.shortcuts); applyShortcuts() }
    }
    /// Some shortcut could not be registered because another app already owns it.
    @Published private(set) var shortcutsTaken = false
    /// Whether frames are actually reaching the Backdrop Camera extension.
    @Published private(set) var sinkConnected = false
    /// macOS's own Background or Portrait effect is switched on for Backdrop's camera input. It would fight with the
    /// backdrop chosen here, and an app can't turn it off itself: it's a Control Center setting.
    @Published private(set) var systemEffectsOn = false

    /// The lens (a filter, face effect or game) layered over the picture, if any. Lenses are for the moment, so none is
    /// remembered across launches.
    @Published private(set) var lensID: String?
    /// What is being switched to, from the moment it is chosen until it is actually on the picture. Some things (a live
    /// window, a video, a face lens finding your face) take a moment, and without this nothing says so.
    @Published private(set) var switching: String?

    /// What the lens wants to say right now: a score, a hint, "looking for your face".
    @Published private(set) var lensStatus: LensStatus?

    /// Lets the menu bar popover open the Studio on a particular pane, or straight into an action.
    enum StudioRequest { case importFile, liveWindow, generate, share }
    @Published var studioPane: StudioView.Pane = .backgrounds
    @Published var studioRequest: StudioRequest?

    @Published var cameraID: String? {
        didSet {
            defaults.set(cameraID, forKey: Keys.camera)
            if isOn { camera.start(deviceID: cameraID) { [weak self] in self?.report($0) } }
            refreshCameras()
            dropSecondCameraIfMain()
        }
    }
    @Published var quality: PersonSegmenter.Quality {
        didSet { defaults.set(quality.rawValue, forKey: Keys.quality); pipeline.setQuality(quality) }
    }
    @Published var edgeSoftness: Double { didSet { defaults.set(edgeSoftness, forKey: Keys.edge); pushLook() } }
    @Published var lightWrap: Double { didSet { defaults.set(lightWrap, forKey: Keys.wrap); pushLook() } }
    @Published var colorMatch: Double { didSet { defaults.set(colorMatch, forKey: Keys.match); pushLook() } }

    // MARK: Present

    /// How a shared screen or window is arranged right now. Sliders, presets, the mouse on the preview and your hands all change this
    /// one layout; while something moves by hand or mouse the pipeline reports it back here about ten times a second.
    @Published private(set) var stage: StageLayout
    private var stageMemory: StageMemory
    private var stageSave: Task<Void, Never>?
    /// Whether the pointer shows in a shared screen or window.
    @Published var captureShowsCursor: Bool {
        didSet { defaults.set(captureShowsCursor, forKey: Keys.cursor); pushCaptureOptions() }
    }
    /// Frames a second for sharing: 30 or 60.
    @Published var captureFrameRate: Int {
        didSet { defaults.set(captureFrameRate, forKey: Keys.frameRate); pushCaptureOptions() }
    }
    /// Sharing paused: viewers see a calm "Paused" card instead of the screen. Not remembered across launches.
    @Published private(set) var sharePaused = false
    /// What the pipeline says about Present: hands in view, whether the share is live.
    @Published private(set) var stageReport: StageReport?
    /// Whether macOS lets Backdrop record the screen. Read without asking, so looking never shows a prompt.
    @Published private(set) var screenRecordingAllowed = CGPreflightScreenCaptureAccess()
    private weak var captureSource: WindowCaptureSource?
    /// The last background that was not a shared screen, for "Stop Sharing".
    private var lastNonShareID: UUID?

    private enum Keys {
        static let camera = "cameraID", quality = "quality", edge = "edgeSoftness"
        static let wrap = "lightWrap", match = "colorMatch", selected = "selectedBackground"
        static let hud = "showOnScreenMessages", shortcuts = "keyboardShortcuts"
        static let stage = "presentStage", cursor = "captureShowsCursor", frameRate = "captureFrameRate", lastNonShare = "lastNonShareBackground"
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
        showsOnScreenMessages = defaults.object(forKey: Keys.hud) as? Bool ?? true
        shortcutsEnabled = defaults.object(forKey: Keys.shortcuts) as? Bool ?? true
        cameras = CameraCapture.availableDevices()
        let memory = defaults.data(forKey: Keys.stage).flatMap { try? JSONDecoder().decode(StageMemory.self, from: $0) } ?? StageMemory()
        stageMemory = memory
        stage = memory.current
        captureShowsCursor = defaults.object(forKey: Keys.cursor) as? Bool ?? true
        captureFrameRate = defaults.object(forKey: Keys.frameRate) as? Int == 60 ? 60 : 30
        lastNonShareID = defaults.string(forKey: Keys.lastNonShare).flatMap(UUID.init(uuidString:))

        // Views watch the model, so changes in the library and rules need to reach it.
        library.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &forwarding)
        rules.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &forwarding)
        installer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &forwarding)
        lensLibrary.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &forwarding)
        // Someone editing a lens in another app changes the files; coming back to Backdrop picks the changes up.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.reloadLenses(); self?.refreshScreenRecording() } }
            .store(in: &forwarding)

        wirePipeline()
        if library.background(withID: selectedID) == nil { selectedID = Background.softBlur.id }
        applySelection()
        pushLook()
        pushStage()
        pipeline.setQuality(quality)

        automation.onMatch = { [weak self] rule in
            guard let self, let background = self.library.background(withID: rule.backgroundID) else { return }
            self.select(background.id)
            self.announce(background.name)
        }
        automation.start()
        installer.updateIfOutdated()
        applyShortcuts()
        observeDevices()
        refreshCameras()
        dropSecondCameraIfMain()
        startPolling()
    }

    private func wirePipeline() {
        // Both run on the pipeline queue.
        camera.onFrame = { [pipeline] buffer, time in pipeline.submit(buffer, at: time) }
        camera.onStatus = { [weak self] status in Task { @MainActor in self?.cameraStatus(status) } }
        pipeline.onOutput = { [sink] buffer, _ in sink.send(buffer) }
        pipeline.onPreview = { [preview] image in preview.show(image) }
        pipeline.onApplied = { [weak self] change in
            Task { @MainActor in
                guard let self, self.changeCounter == change else { return }
                self.switching = nil
            }
        }
        preview.onDemandChanged = { [pipeline] wanted in pipeline.setPreviewEnabled(wanted) }
        pipeline.onStageLayoutChanged = { [weak self] layout in
            Task { @MainActor in self?.stageMoved(layout) }
        }
        pipeline.onStageReport = { [weak self] report in
            Task { @MainActor in
                guard let self, self.stageReport != report else { return }
                self.stageReport = report
            }
        }
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
        switching = nil
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
        guard let chosen = library.background(withID: id) else { return }
        if !chosen.isStageContent {
            lastNonShareID = id
            defaults.set(id.uuidString, forKey: Keys.lastNonShare)
        } else if !selectedBackground.isStageContent {
            // A fresh share starts live, never paused.
            sharePaused = false
        }
        selectedID = id
        defaults.set(id.uuidString, forKey: Keys.selected)
        applySelection(change: beginChange(selectedBackground.name))
    }

    /// Notes that something was just chosen, so the interface can say it is on its way. Nil when nothing is running to show it.
    private func beginChange(_ name: String) -> Int? {
        guard isOn else { switching = nil; return nil }
        changeCounter += 1
        switching = name
        return changeCounter
    }

    func cycle(by step: Int) {
        let items = library.items
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selectedID } ?? 0
        let next = items[(index + step + items.count) % items.count]
        select(next.id)
        announce(next.name)
    }

    /// Shows a brief label near the bottom of the screen, unless that has been switched off in the Studio's settings.
    private func announce(_ text: String) {
        if showsOnScreenMessages { HUD.shared.show(text) }
    }

    private func applySelection(change: Int? = nil) {
        let background = selectedBackground
        let source = BackgroundSourceFactory.make(for: background, library: library, capture: captureOptions)
        let capture = source as? WindowCaptureSource
        capture?.onError = { [weak self] text in
            Task { @MainActor in
                self?.message = text
                self?.refreshScreenRecording()
            }
        }
        captureSource = capture
        if !background.isStageContent { stageReport = nil }
        pipeline.setBackground(background, source: source, change: change)
        pushStage()
        updateMirroring()
        Log.lens.notice("background: \(background.name, privacy: .public)")
    }

    // MARK: Lenses

    var selectedLens: LensInfo? { lensID.flatMap(lensLibrary.info(for:)) }

    /// Looks in the Lenses folder again. A lens that is on and has changed on disk is put on afresh; one that is gone comes off.
    func reloadLenses() {
        Task { [weak self] in
            guard let self else { return }
            await lensLibrary.reloadAsync()
            guard let id = lensID else { return }
            guard let info = lensLibrary.info(for: id) else { selectLens(nil); return }
            if info.modified != lensModified { selectLens(id) }
        }
    }

    /// Picks a lens, or takes the current one off with nil.
    func selectLens(_ id: String?) {
        let info = id.flatMap(lensLibrary.info(for:))
        lensID = info?.id
        lensModified = info?.modified
        let lens = info?.make()
        pipeline.setLens(lens, change: beginChange(info?.name ?? "no lens"))
        Log.lens.notice("lens: \(info?.name ?? "none", privacy: .public)")
        updateMirroring()
        lensStatus = lens?.status

        lensPoll?.cancel()
        guard let lens else { return }
        // Scores and countdowns change faster than the one-second housekeeping loop.
        lensPoll = Task { [weak self] in
            while !Task.isCancelled {
                let status = lens.status
                if self?.lensStatus != status { self?.lensStatus = status }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Steps through every lens in the order they are listed, with "no lens" as one more stop.
    func cycleLens(by step: Int) {
        let stops: [String?] = [nil] + lensLibrary.all.map(\.id)
        let index = stops.firstIndex { $0 == lensID } ?? 0
        let next = stops[(index + step + stops.count) % stops.count]
        selectLens(next)
        announce(next.flatMap(lensLibrary.info(for:)).map { "\($0.glyph) \($0.name)" } ?? "No lens")
    }

    /// New game, clean slate.
    func restartLens() {
        pipeline.restartLens()
        if let info = selectedLens { announce("\(info.glyph) \(info.name): new game") }
    }

    func bestScore(for id: String) -> Int { scores.best(for: id) }

    // MARK: Editing the library

    func importFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { select(try library.importFile(at: url).id) } catch { message = error.localizedDescription }
        }
    }

    func addWindow(_ choice: WindowChoice) {
        select(library.addWindow(bundleID: choice.bundleID, appName: choice.appName, title: choice.title, windowID: choice.id).id)
    }

    /// Shares the main screen, or with a choice a particular one.
    func addScreen(_ choice: DisplayChoice? = nil) {
        if let choice, NSScreen.screens.count > 1 {
            select(library.addDisplay(displayID: choice.id, name: choice.name).id)
        } else {
            select(library.addDisplay().id)
        }
    }

    /// Shows a second camera: behind you, as a panel, or filling the picture, like a shared window.
    func addCamera(_ choice: CameraChoice) {
        select(library.addCamera(deviceID: choice.id, name: choice.name).id)
    }

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

    /// The windows that can be shared, from a look at what is on screen (see `ShareCatalog`).
    nonisolated static func windows(in content: SCShareableContent) -> [WindowChoice] {
        let me = Bundle.main.bundleIdentifier
        return content.windows.compactMap { window in
            guard let app = window.owningApplication, app.bundleIdentifier != me,
                  window.windowLayer == 0, window.frame.width > 200, window.frame.height > 150 else { return nil }
            return WindowChoice(id: window.windowID, bundleID: app.bundleIdentifier, appName: app.applicationName, title: window.title ?? "",
                                size: window.frame.size)
        }
        .sorted { ($0.appName.localizedLowercase, $0.title) < ($1.appName.localizedLowercase, $1.title) }
    }

    /// The screens, named as macOS names them, main first.
    static func displays() -> [DisplayChoice] {
        let main = CGMainDisplayID()
        return NSScreen.screens.compactMap { screen -> DisplayChoice? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            return DisplayChoice(id: id, name: screen.localizedName, size: screen.frame.size, isMain: id == main)
        }
        .sorted { $0.isMain && !$1.isMain }
    }

    // MARK: Present

    /// A window, a screen or a second camera is on the picture, so there is something to arrange.
    var isPresenting: Bool { selectedBackground.isStageContent }

    /// A window or a screen is on the picture: what the "your screen is going out" indicators and Screen Recording are about.
    var isSharingScreen: Bool { selectedBackground.isScreenShare }

    /// A second camera is on the picture.
    var isShowingSecondCamera: Bool {
        if case .camera = selectedBackground.kind { return true }
        return false
    }

    /// The second camera on the picture, if it is also the one now chosen as the main camera: the same camera twice is only a copy
    /// of you, so the second picture goes away and the background it replaced comes back.
    private func dropSecondCameraIfMain() {
        guard case .camera(let id) = selectedBackground.kind, id == mainCameraID else { return }
        let name = selectedBackground.name
        stopSharing()
        message = "\(name) is now your main camera, so it can’t also be the second one."
    }

    /// The camera Backdrop is using as the main one: the one chosen, or the first it can find.
    var mainCameraID: String? { ExtraCameras.mainCameraID(selected: cameraID, available: cameras) }

    private func refreshCameras() {
        cameras = CameraCapture.availableDevices()
        extraCameras = ExtraCameras.discover(excluding: mainCameraID)
    }

    /// Your screen is going out to the call right now: the camera is on, a screen or window is the background, it is not paused, and
    /// the capture has not lost it.
    var isScreenGoingOut: Bool {
        guard isOn, isSharingScreen, !sharePaused else { return false }
        let status = stageReport?.status ?? .live
        return status != .lost && status != .denied
    }

    private var captureOptions: CaptureOptions { CaptureOptions(showsCursor: captureShowsCursor, framesPerSecond: captureFrameRate) }

    private func pushCaptureOptions() { captureSource?.setOptions(captureOptions) }

    /// A new layout from the interface: a slider, a toggle, a preset.
    func setStage(_ layout: StageLayout) {
        let previous = stage
        let clamped = layout.clamped()
        guard clamped != stage else { return }
        stage = clamped
        stageMemory.update(clamped)
        saveStageSoon()
        if clamped.surround != previous.surround || clamped.surroundBackdrop != previous.surroundBackdrop { pushSurround() }
        pushStage()
        if clamped.arrangement != previous.arrangement { updateMirroring() }
    }

    /// Changes one thing about the layout.
    func updateStage(_ change: (inout StageLayout) -> Void) {
        var next = stage
        change(&next)
        setStage(next)
    }

    func setArrangement(_ arrangement: StageArrangement) {
        guard arrangement != stage.arrangement else { return }
        stageMemory.switchTo(arrangement)
        let next = stageMemory.current
        stage = next
        saveStageSoon()
        pushSurround()
        pushStage()
        updateMirroring()
        if isPresenting { announce(arrangement.title) }
    }

    func applyPreset(_ preset: StagePreset) {
        let next = preset.apply(to: stage)
        if next.arrangement != stage.arrangement {
            stageMemory.switchTo(next.arrangement)
        }
        stage = next
        stageMemory.update(next)
        saveStageSoon()
        pushSurround()
        pushStage()
        updateMirroring()
    }

    func togglePause() {
        guard isPresenting else { return }
        sharePaused.toggle()
        pushStage()
        announce(sharePaused ? "Sharing paused" : "Sharing resumed")
    }

    /// Back to the background in use before sharing started.
    func stopSharing() {
        let back = lastNonShareID.flatMap { library.background(withID: $0) }.map(\.id) ?? Background.softBlur.id
        sharePaused = false
        select(back)
    }

    /// The mouse or trackpad on the Studio preview.
    func stagePointer(_ event: StagePointerEvent) { pipeline.sendStagePointer(event) }

    func refreshScreenRecording() {
        let allowed = CGPreflightScreenCaptureAccess()
        if allowed != screenRecordingAllowed { screenRecordingAllowed = allowed }
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// The backdrops that can go round a floating panel: everything but shared screens and cameras.
    var surroundChoices: [Background] { library.items.filter { !$0.isStageContent && $0.kind != .passthrough } }

    private func pushStage() {
        pipeline.setStage(stage, paused: sharePaused && isPresenting, title: isPresenting ? selectedBackground.name : nil)
    }

    private func pushSurround() {
        guard stage.surround == .backdrop, stage.arrangement == .floatingPanel else {
            pipeline.setStageSurround(nil)
            return
        }
        let chosen = stage.surroundBackdrop.flatMap { library.background(withID: $0) }
            ?? library.background(withID: Background.builtIns.first { $0.kind == .gradient(.midnight) }?.id ?? Background.softBlur.id)
        guard let chosen, !chosen.isStageContent else { pipeline.setStageSurround(nil); return }
        pipeline.setStageSurround(BackgroundSourceFactory.make(for: chosen, library: library))
    }

    /// The pipeline moved something (your hands, the mouse): take it, without sending it straight back.
    private func stageMoved(_ layout: StageLayout) {
        guard layout.arrangement == stage.arrangement else { return }
        stage = layout
        stageMemory.update(layout)
        saveStageSoon()
    }

    /// Saves half a second after the last change, so a drag is written once, not ten times a second.
    private func saveStageSoon() {
        stageSave?.cancel()
        stageSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(self.stageMemory) { self.defaults.set(data, forKey: Keys.stage) }
        }
    }

    /// The preview is a mirror, except where words must read the right way round: games and lenses with text, and a shared screen
    /// arranged as a panel or with you over it, where you look at your own slides.
    private func updateMirroring() {
        let info = selectedLens
        let lensText = info?.scored == true || info?.showsText == true
        let arranged = isPresenting && stage.arrangement.isArranged
        let mirrored = !(lensText || arranged)
        if preview.mirrored != mirrored { preview.mirrored = mirrored }
    }

    /// Every Present setting back to how it started; the share itself is kept.
    func resetStage() {
        stageMemory = StageMemory()
        stageMemory.switchTo(stage.arrangement)
        stage = stageMemory.current
        saveStageSoon()
        pushSurround()
        pushStage()
    }

    // MARK: Settings

    private func pushLook() {
        pipeline.setParameters(CompositeParameters(edgeSoftness: edgeSoftness, lightWrap: lightWrap, colorMatch: colorMatch))
    }

    /// Whether the cutout quality and the three look sliders are all at their starting values.
    var lookIsDefault: Bool {
        let start = CompositeParameters()
        return quality == .balanced && abs(edgeSoftness - start.edgeSoftness) < 0.001
            && abs(lightWrap - start.lightWrap) < 0.001 && abs(colorMatch - start.colorMatch) < 0.001
    }

    /// Cutout quality and the look sliders back to how they started.
    func resetLook() {
        let start = CompositeParameters()
        quality = .balanced
        edgeSoftness = start.edgeSoftness
        lightWrap = start.lightWrap
        colorMatch = start.colorMatch
    }

    /// Every setting in the Studio's Camera and Settings panes back to how it started. Backgrounds, lenses, rules,
    /// favourites and scores are kept, and so is "open at login", which is macOS's to remember.
    func resetSettings() {
        cameraID = nil
        resetLook()
        showsOnScreenMessages = true
        shortcutsEnabled = true
    }

    /// Where imported, generated and recorded backgrounds are kept.
    func showBackgroundsFolder() {
        try? FileManager.default.createDirectory(at: library.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(library.directory)
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

    private static let shortcutsTakenMessage = "Some keyboard shortcuts are taken by another app."

    /// Registers the shortcuts, or gives the keys back when they have been switched off.
    private func applyShortcuts() {
        hotkeys.unregisterAll()
        guard shortcutsEnabled else {
            shortcutsTaken = false
            if message == Self.shortcutsTakenMessage { message = nil }
            return
        }
        registerHotkeys()
    }

    /// The same list is shown in the Studio's Settings pane (StudioSettings.shortcuts); keep them in step.
    private func registerHotkeys() {
        let modifiers = controlKey | optionKey
        let registered = [
            hotkeys.register(keyCode: kVK_RightArrow, modifiers: modifiers) { [weak self] in MainActor.assumeIsolated { self?.cycle(by: 1) } },
            hotkeys.register(keyCode: kVK_LeftArrow, modifiers: modifiers) { [weak self] in MainActor.assumeIsolated { self?.cycle(by: -1) } },
            hotkeys.register(keyCode: kVK_UpArrow, modifiers: modifiers) { [weak self] in MainActor.assumeIsolated { self?.cycleLens(by: 1) } },
            hotkeys.register(keyCode: kVK_DownArrow, modifiers: modifiers) { [weak self] in MainActor.assumeIsolated { self?.cycleLens(by: -1) } },
            hotkeys.register(keyCode: kVK_ANSI_R, modifiers: modifiers) { [weak self] in MainActor.assumeIsolated { self?.restartLens() } },
            hotkeys.register(keyCode: kVK_ANSI_P, modifiers: modifiers) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.isPresenting { self.togglePause() } else { self.announce("Nothing is being shared") }
                }
            },
            hotkeys.register(keyCode: kVK_ANSI_B, modifiers: modifiers) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.toggle()
                    self.announce(self.isOn || self.isStarting ? "Camera on" : "Camera off")
                }
            },
        ]
        shortcutsTaken = registered.contains(false)
        if shortcutsTaken { message = Self.shortcutsTakenMessage }
    }

    private func observeDevices() {
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshCameras() }
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
                let missing = self.missingMonitor.poll(installedAndEnabled: self.installer.isInstalledAndEnabled, deviceVisible: present)
                if missing != self.cameraMissing {
                    self.cameraMissing = missing
                    if missing { Log.sink.notice("the camera extension is installed and enabled, but Backdrop Camera isn't being offered") }
                }
                // While it is missing, keep asking macOS what it thinks, so the advice follows the facts (switched off, replaced, gone).
                self.pollCount += 1
                if self.cameraMissing, self.pollCount % 30 == 0 { self.installer.refreshProperties() }
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
