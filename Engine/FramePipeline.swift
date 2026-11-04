import CoreImage
import CoreMedia
import CoreVideo
import QuartzCore

/// Camera frame in, finished frame out: segment, composite, hand off to the virtual camera and the preview.
///
/// Configuration changes are applied on `queue`, the same queue the camera delivers frames on, so a frame
/// is never half-way through a background swap.
final class FramePipeline {
    let queue = DispatchQueue(label: "app.backdrop.pipeline", qos: .userInteractive)
    let compositor: Compositor

    /// Every finished frame (1280×720 BGRA). Called on `queue`.
    var onOutput: ((CVPixelBuffer, CMTime) -> Void)?
    /// A downscaled copy for the on-screen preview, delivered only while preview is enabled. Called on `queue`.
    var onPreview: ((CGImage) -> Void)?

    private let segmenter = PersonSegmenter()
    private let smoother = MaskSmoother()

    // The cutout (Vision, about 25 ms) runs on its own queue so the next frame's cutout is under way while this frame is
    // being composited. Everything else stays on `queue`.
    private let cutoutQueue = DispatchQueue(label: "app.backdrop.cutout", qos: .userInteractive)
    private var cutoutBusy = false
    private var waiting: (camera: CVPixelBuffer, time: CMTime)?
    /// Bumped by `stop()`, so a cutout that was in flight at the time is thrown away when it finishes.
    private var generation = 0
    /// Whether the current background's source is running (it is paused when the camera goes off).
    private var sourceRunning = false
    /// The timestamp of the last frame sent out. Anything older that turns up later (a slow cutout finishing after a newer
    /// frame was made without one) is thrown away rather than sent out of order.
    private var lastSentTime: CMTime?

    private var background = Background.off
    private var source: BackgroundSource?
    private var outgoing: (source: BackgroundSource, startedAt: CFTimeInterval)?
    private var parameters = CompositeParameters()
    private var previewEnabled = false
    private var frameCount = 0

    private var lens: Lens?
    private let lensServices: LensServices
    private let matteGrid: MatteGrid
    private var lastFrameAt: CFTimeInterval?
    private let faceTracker = FaceTrackingService()
    private var faceSmoother = FaceSmoother()
    private let handTracker = HandTrackingService()
    private var handSmoother = HandSmoother()

    // Present: a shared screen as a floating panel, or you moved over it, and the chrome for arranging them with your hands.
    private var stageLayout = StageLayout()
    private var stageController = StageHandController()
    private lazy var stageComposer = StageComposer(rect: compositor.rect, context: compositor.context)
    private var stagePaused = false
    private var stageTitle: String?
    private var stageSurroundSource: BackgroundSource?
    private var stagePointer: [StagePointerEvent] = []
    private var stageOverlay = StageOverlayState()
    /// The preview's chrome is drawn at the preview's own size (half the output).
    private lazy var overlayCanvas = OverlayCanvas(size: CGSize(width: compositor.rect.width / 2, height: compositor.rect.height / 2), slots: 2)
    private var lastStageReportAt: CFTimeInterval = 0
    private var stageWasActive = false
    private var lastStageSent: StageLayout?
    private var lastReport: StageReport?
    private var tracksHands = false
    /// What the share was doing this frame, worked out once and reported.
    private var frameShareStatus = StageContentStatus.starting

    /// The layout as hands or the mouse move it: often while something moves (about ten times a second) and once more when it
    /// settles. Called on `queue`.
    var onStageLayoutChanged: ((StageLayout) -> Void)?
    /// What Present is doing (hands in view, whether the share is live), whenever it changes. Called on `queue`.
    var onStageReport: ((StageReport) -> Void)?
    /// The chrome drawn over the last preview, for tests. Never part of the output.
    private(set) var lastOverlay = StageOverlayState()

    /// Replaces the person-cutout step. For tests, which have no Vision to lean on.
    var matteOverride: ((CVPixelBuffer) -> CVPixelBuffer?)?
    /// How much of each new cutout replaces the last one, 0...1. Tests set it to 1 so frames that jump about don't blend.
    var matteResponsiveness: Float {
        get { smoother.responsiveness }
        set { smoother.responsiveness = newValue }
    }
    /// Replaces face tracking. For tests, which have no real face.
    var faceOverride: (() -> FaceState?)?
    /// Replaces hand tracking. For tests, which have no real hands.
    var handsOverride: (() -> [HandState])?

    private let outputLock = NSLock()
    private var lastOutputAt = CFAbsoluteTimeGetCurrent()

    /// Seconds since a finished frame was last produced. Large while the camera is delivering means processing is stuck.
    var secondsSinceOutput: TimeInterval { outputLock.withLock { CFAbsoluteTimeGetCurrent() - lastOutputAt } }

    /// Call when the camera starts, so the clock begins then rather than at launch. Also starts the background's source again
    /// if turning the camera off had paused it (a video, a live window).
    func markStarted() {
        outputLock.withLock { lastOutputAt = CFAbsoluteTimeGetCurrent() }
        queue.async {
            self.lastSentTime = nil
            if !self.sourceRunning, let source = self.source {
                source.start()
                self.sourceRunning = true
                self.stageSurroundSource?.start()
            }
        }
    }

    /// Called on `queue` once a frame made after a change of background or lens has gone out and the new picture is really
    /// showing: for a background that means its source has delivered a frame, not just that the dark placeholder is up.
    var onApplied: ((Int) -> Void)?
    private var pendingChange: Int?
    private var settledFrames = 0
    private var showingPlaceholder = false

    // For the log: how fast frames are actually being made, so "it feels slow" can be checked against numbers.
    private var statsSince = CACurrentMediaTime()
    private var statsFrames = 0
    private var statsBusy = 0.0
    private var statsWorst = 0.0
    private var statsCutouts = 0
    private var statsCutoutBusy = 0.0

    private let transitionDuration: CFTimeInterval = 0.45

    init(compositor: Compositor = Compositor()) {
        self.compositor = compositor
        lensServices = LensServices(context: compositor.context, size: compositor.outputSize)
        matteGrid = MatteGrid(outputSize: compositor.outputSize)
    }

    // MARK: Configuration

    /// `change` is a number the caller will hear back in `onApplied` once the new background is on screen.
    func setBackground(_ new: Background, source newSource: BackgroundSource?, change: Int? = nil) {
        queue.async {
            if let change { self.pendingChange = change; self.settledFrames = 0 }
            if case .passthrough = new.kind {
                self.source?.stop()
                self.outgoing?.source.stop()
                self.source = nil
                self.outgoing = nil
                self.sourceRunning = false
            } else {
                (newSource as? StageContentSource)?.setPaused(self.stagePaused)
                newSource?.start()
                self.sourceRunning = newSource != nil
                if let old = self.source {
                    // Dissolve from whatever was showing, even if that was itself mid-dissolve.
                    self.outgoing?.source.stop()
                    self.outgoing = (old, CACurrentMediaTime())
                }
                self.source = newSource
            }
            self.background = new
        }
    }

    /// Applies edited settings (such as the parallax toggle) to the background already showing, without restarting its source.
    func updateCurrentBackground(_ updated: Background) {
        queue.async { if updated.id == self.background.id { self.background = updated } }
    }

    /// Puts a lens (an effect or game) on top of the picture, or takes it off with nil.
    func setLens(_ new: Lens?, change: Int? = nil) {
        queue.async {
            if let change { self.pendingChange = change; self.settledFrames = 0 }
            self.lens = new
            self.faceSmoother.reset()
            self.faceTracker.reset()
            self.handSmoother.reset()
            self.handTracker.reset()
        }
    }

    /// New game, clean slate.
    func restartLens() { queue.async { self.lens?.restart() } }

    func setParameters(_ new: CompositeParameters) { queue.async { self.parameters = new } }
    func setQuality(_ quality: PersonSegmenter.Quality) { segmenter.quality = quality }
    func setPreviewEnabled(_ enabled: Bool) { queue.async { self.previewEnabled = enabled } }

    // MARK: Present

    /// How a shared screen or window is arranged, whether sharing is paused, and the name to show under the panel. Places that
    /// differ from what this pipeline last reported glide to the new place; anything held by hand stays in the hand.
    func setStage(_ layout: StageLayout, paused: Bool, title: String?) {
        queue.async {
            self.stageLayout = layout.clamped()
            self.stageController.adopt(self.stageLayout)
            self.lastStageSent = self.stageController.layout
            self.stageTitle = title
            if paused != self.stagePaused {
                self.stagePaused = paused
                (self.source as? StageContentSource)?.setPaused(paused)
            }
        }
    }

    /// The library backdrop shown around a floating panel, when that is the surround chosen. Nil for none.
    func setStageSurround(_ newSource: BackgroundSource?) {
        queue.async {
            self.stageSurroundSource?.stop()
            self.stageSurroundSource = newSource
            if self.sourceRunning { newSource?.start() }
        }
    }

    /// The mouse or trackpad on the Studio preview.
    func sendStagePointer(_ event: StagePointerEvent) {
        queue.async {
            // Events are used up by frames; with no frames coming (camera off) keep only the latest few.
            self.stagePointer.append(event)
            if self.stagePointer.count > 48 { self.stagePointer.removeFirst(self.stagePointer.count - 48) }
        }
    }

    /// Whether this frame arranges a shared screen: a window or screen is the background and the arrangement is not plain Backdrop.
    private var isStaging: Bool { background.isScreenShare && stageLayout.arrangement.isArranged }

    func stop() {
        queue.async {
            self.generation += 1
            self.cutoutBusy = false
            self.waiting = nil
            self.lastSentTime = nil
            self.source?.stop()
            self.sourceRunning = false
            self.outgoing?.source.stop()
            self.outgoing = nil
            self.stageSurroundSource?.stop()
            self.smoother.reset()
        }
    }

    // MARK: Processing

    /// How the cutout for a frame is found: here and now, or already done on the cutout queue.
    enum Cutout {
        case compute
        case supplied(CVPixelBuffer?)
    }

    /// Whether the current background or lens needs to know where the person is.
    private var needsCutout: Bool {
        if case .passthrough = background.kind {
            return lens?.needs.contains(.matte) ?? false
        }
        return true
    }

    /// The camera's way in; call on `queue`. A frame that needs the cutout joins the line for it, and only the newest frame
    /// is kept while a cutout is under way, so a slow cutout skips frames instead of falling further behind. A frame that
    /// doesn't need one is made at once.
    ///
    /// Each frame is composited with the cutout made from that very frame, so nothing about how it looks changes: the
    /// cutout of the next frame simply runs while this one is composited and sent on.
    func submit(_ camera: CVPixelBuffer, at time: CMTime) {
        guard needsCutout else {
            waiting = nil                    // a frame still waiting for a cutout is older than this one and no longer needs it
            process(camera, at: time)
            return
        }
        waiting = (camera, time)
        startCutoutIfIdle()
    }

    private func startCutoutIfIdle() {
        guard !cutoutBusy, let next = waiting else { return }
        waiting = nil
        cutoutBusy = true
        let generation = self.generation
        cutoutQueue.async {
            let started = CACurrentMediaTime()
            let mask = self.matteOverride.map { $0(next.camera) } ?? self.segmenter.mask(for: next.camera)
            let took = CACurrentMediaTime() - started
            self.queue.async {
                guard generation == self.generation else { return }
                self.cutoutBusy = false
                self.statsCutouts += 1
                self.statsCutoutBusy += took
                // The next frame's cutout starts now, while this frame is composited.
                self.startCutoutIfIdle()
                self.process(next.camera, at: next.time, cutout: .supplied(mask))
            }
        }
    }

    /// Must be called on `queue`.
    func process(_ camera: CVPixelBuffer, at time: CMTime, cutout: Cutout = .compute) {
        if let last = lastSentTime, last.isValid, time.isValid, CMTimeCompare(time, last) < 0 { return }
        let now = CACurrentMediaTime()
        defer { recordStats(started: now) }
        let dt = min(0.1, max(1.0 / 240, now - (lastFrameAt ?? now - 1.0 / 30)))
        lastFrameAt = now

        let cameraImage = CIImage(cvPixelBuffer: camera)
        let fitted = compositor.fitted(cameraImage)
        var composed = fitted
        var backdrop: CIImage?
        // What a lens is handed as the camera and cutout: you as you now sit, which Present may have moved or scaled.
        var lensCamera = fitted
        var lensMatte: CIImage?
        var handTransform: CGAffineTransform?

        showingPlaceholder = false
        var passthrough = false
        if case .passthrough = background.kind { passthrough = true }
        let needsMatte = lens?.needs.contains(.matte) ?? false
        let staging = isStaging && !passthrough
        if !staging { stageOverlay = StageOverlayState() }

        // Hands, for a lens that reads them or for arranging Present by hand. One look serves both.
        let lensWantsHands = lens?.needs.contains(.hands) ?? false
        let stageWantsHands = staging && stageLayout.handControl && stageLayout.handItem != nil
        var hands: [HandState] = []
        if lensWantsHands || stageWantsHands {
            if let handsOverride {
                hands = handsOverride()
            } else {
                handTracker.submit(camera, transform: Compositor.fillTransform(cameraImage.extent, into: compositor.rect))
                hands = handSmoother.update(handTracker.latest(), dt: dt)
            }
            tracksHands = true
        } else if tracksHands {
            tracksHands = false
            handSmoother.reset()
            handTracker.reset()
        }

        if !passthrough || needsMatte {
            // If Vision hiccups, reuse the last matte. Only if there has never been one do we fall back to
            // a heavy blur, so the room you meant to hide is never shown, even for a frame.
            let produced: CVPixelBuffer?
            switch cutout {
            case .compute: produced = matteOverride.map { $0(camera) } ?? segmenter.mask(for: camera)
            case .supplied(let mask): produced = mask
            }
            let matteBuffer = produced.map(smoother.smooth) ?? smoother.latest
            if let matteBuffer {
                let refined = compositor.refinedMatte(camera: cameraImage, mask: Compositor.matte(from: matteBuffer), params: parameters)
                lensMatte = refined
                if !passthrough {
                    let parallax = background.parallax
                        ? CGPoint(x: (smoother.centroid.x - 0.5) * 2, y: (0.5 - smoother.centroid.y) * 2)
                        : nil
                    if staging {
                        let made = stage(camera: cameraImage, fitted: fitted, matte: refined, hands: hands, dt: dt, now: now, parallax: parallax)
                        backdrop = made.backdrop
                        composed = made.composed
                        lensCamera = made.camera
                        lensMatte = made.matte
                        handTransform = made.handTransform
                    } else {
                        let bg = backgroundImage(camera: cameraImage, now: now, parallax: parallax)
                        backdrop = bg
                        composed = compositor.composite(camera: cameraImage, matte: refined, background: bg, params: parameters)
                    }
                }
            } else if !passthrough {
                composed = compositor.fitted(cameraImage.clampedToExtent().applyingGaussianBlur(sigma: 40).cropped(to: cameraImage.extent))
            }
        }

        var finished = composed
        if let lens {
            var face: FaceState?
            if lens.needs.contains(.face) {
                if let faceOverride {
                    face = faceOverride()
                } else {
                    faceTracker.submit(camera, transform: Compositor.fillTransform(cameraImage.extent, into: compositor.rect))
                    face = faceSmoother.update(faceTracker.latest().flatMap(FaceFeatureExtractor.measure), dt: dt)
                }
            }
            // Hands are read on the camera picture; when Present has moved you, the lens gets them where you now are.
            let lensHands = lensWantsHands ? (handTransform.map { t in hands.map { $0.transformed(by: t) } } ?? hands) : []
            var grid: MatteGrid?
            if lens.wantsMatteGrid, let lensMatte {
                matteGrid.update(from: lensMatte, rect: compositor.rect, context: compositor.context)
                grid = matteGrid
            }
            let input = LensInput(time: now, dt: dt, rect: compositor.rect, camera: lensCamera, matte: lensMatte, background: backdrop,
                                  composed: composed, matteGrid: grid, face: face, services: lensServices, hands: lensHands)
            finished = lens.render(input).cropped(to: compositor.rect)
        }

        guard let output = compositor.makeOutputBuffer() else { return }
        compositor.render(finished, into: output)
        onOutput?(output, time)
        lastSentTime = time
        outputLock.withLock { lastOutputAt = CFAbsoluteTimeGetCurrent() }

        if let change = pendingChange {
            settledFrames = showingPlaceholder ? 0 : settledFrames + 1
            if settledFrames >= 2 {
                pendingChange = nil
                onApplied?(change)
            }
        }

        frameCount += 1
        if previewEnabled, frameCount % 2 == 0, let onPreview {
            var half = CIImage(cvPixelBuffer: output).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
            // The arranging chrome goes on the preview only, never on the picture other people see.
            if staging, !stageOverlay.isEmpty, let canvas = overlayCanvas {
                let ctx = canvas.begin()
                ctx.saveGState()
                ctx.scaleBy(x: 0.5, y: 0.5)
                StageOverlay.draw(stageOverlay, in: ctx, pixel: 2, picture: compositor.rect.size)
                ctx.restoreGState()
                half = canvas.image().composited(over: half)
            }
            if let image = compositor.context.createCGImage(half, from: half.extent) { onPreview(image) }
        }

        lastOverlay = stageOverlay
        if background.isScreenShare { reportStage(hands: hands) }
    }

    // MARK: Present

    /// Builds the picture for an arranged share: moves things by hand and mouse, draws the stage, and puts you on it.
    private func stage(camera: CIImage, fitted: CIImage, matte: CIImage, hands: [HandState], dt: Double, now: CFTimeInterval, parallax: CGPoint?)
        -> (backdrop: CIImage, composed: CIImage, camera: CIImage, matte: CIImage?, handTransform: CGAffineTransform?) {
        // Where you are: the middle of your cutout in output pixels, and how far that is from the middle of the picture.
        let c = smoother.centroid
        let e = camera.extent
        let anchor = CGPoint(x: e.minX + c.x * e.width, y: e.minY + (1 - c.y) * e.height)
            .applying(Compositor.fillTransform(e, into: compositor.rect))
        let head = CGPoint(x: (anchor.x / compositor.rect.width - 0.5) * 2, y: (anchor.y / compositor.rect.height - 0.5) * 2)

        let frame = source?.frame(at: now, camera: camera)
        let status = shareStatus(frame: frame)
        frameShareStatus = status
        showingPlaceholder = status == .starting

        let control = StageControlInput(hands: stageLayout.handControl ? hands : [], dt: dt, pointer: stagePointer, aspect: stageComposer.aspect,
                                        head: head, anchor: anchor, lensUsesHands: lens?.needs.contains(.hands) ?? false)
        stagePointer.removeAll()
        let out = stageController.step(control)
        stageOverlay = out.overlay
        reportLayout(out.layout, active: out.isActive, now: now)

        var surround: CIImage?
        if out.layout.surround == .backdrop, let s = stageSurroundSource, let picture = s.frame(at: now, camera: camera) {
            surround = compositor.prepareBackground(picture, fits: s.fitsContent, parallax: nil)
        }
        let inputs = StageComposer.Inputs(content: frame, status: status, title: stageTitle, layout: out.layout, live: out.live, camera: fitted,
                                          matte: matte, surround: surround, head: head, anchor: anchor, dt: dt)
        let bg = backgroundImage(camera: camera, now: now, parallax: parallax, stage: inputs)
        let person = stageComposer.person(inputs, over: bg, compositor: compositor, params: parameters)
        var transform: CGAffineTransform?
        if !out.layout.showsBubble, !StageGeometry.isIdentity(out.layout.presenter) {
            transform = StageGeometry.presenterTransform(out.layout.presenter, in: compositor.rect.size)
        }
        return (bg, person.composed, person.camera, person.matte, transform)
    }

    /// What the share is doing: paused by you, or whatever the capture says.
    private func shareStatus(frame: CIImage?) -> StageContentStatus {
        if stagePaused { return .paused }
        let status = (source as? StageContentSource)?.status ?? (frame == nil ? .starting : .live)
        return status == .live && frame == nil ? .starting : status
    }

    /// Hands the moving layout to the interface: ten times a second while something moves, and once more when it settles.
    private func reportLayout(_ layout: StageLayout, active: Bool, now: CFTimeInterval) {
        let settling = stageWasActive && !active
        stageWasActive = active
        guard let onStageLayoutChanged, layout != lastStageSent else { return }
        guard settling || !active || now - lastStageReportAt >= 0.1 else { return }
        lastStageReportAt = now
        lastStageSent = layout
        stageController.didReport(layout)
        onStageLayoutChanged(layout)
    }

    private func reportStage(hands: [HandState]) {
        let report = StageReport(handsSeen: tracksHands ? hands.filter { $0.unseenFor <= 0 }.count : nil,
                                 status: frameShareStatus,
                                 aspect: (stageComposer.aspect * 100).rounded() / 100,
                                 trackingIdle: tracksHands && handsOverride == nil && handTracker.isIdle)
        guard report != lastReport else { return }
        lastReport = report
        onStageReport?(report)
    }

    /// Once every ten seconds, notes the frame rate and how long a frame takes to make. A frame that takes longer than
    /// the camera's interval (33 ms at 30 fps) means the picture is falling behind.
    private func recordStats(started: CFTimeInterval) {
        let now = CACurrentMediaTime()
        let took = now - started
        statsFrames += 1
        statsBusy += took
        statsWorst = max(statsWorst, took)
        guard now - statsSince >= 10 else { return }
        let seconds = now - statsSince
        let cutout = statsCutouts > 0 ? Int(statsCutoutBusy / Double(statsCutouts) * 1000) : 0
        Log.pipeline.notice("\(String(format: "%.1f", Double(self.statsFrames) / seconds), privacy: .public) fps; compositing takes \(Int(self.statsBusy / Double(self.statsFrames) * 1000), privacy: .public) ms on average and \(Int(self.statsWorst * 1000), privacy: .public) ms at worst; the cutout, running alongside, takes \(cutout, privacy: .public) ms")
        statsSince = now
        statsFrames = 0
        statsBusy = 0
        statsWorst = 0
        statsCutouts = 0
        statsCutoutBusy = 0
    }

    private func backgroundImage(camera: CIImage, now: CFTimeInterval, parallax: CGPoint?, stage: StageComposer.Inputs? = nil) -> CIImage {
        func prepared(_ source: BackgroundSource?) -> CIImage? {
            guard let source, let frame = source.frame(at: now, camera: camera) else { return nil }
            return compositor.prepareBackground(frame, fits: source.fitsContent, parallax: parallax)
        }

        // Until a video or window delivers its first frame, hold a dark fill rather than showing the room.
        let placeholder = CIImage(color: CIColor(red: 0.07, green: 0.07, blue: 0.08)).cropped(to: compositor.rect)
        let current: CIImage
        if let stage {
            current = stageComposer.backdrop(stage)
        } else {
            // The source is asked for its frame once a frame: a capture or video hands out its newest each time it is asked.
            let raw = source?.frame(at: now, camera: camera)
            if let card = shareCard(frame: raw, camera: camera) {
                current = card
            } else {
                let frame = raw.map { compositor.prepareBackground($0, fits: source?.fitsContent ?? false, parallax: parallax) }
                showingPlaceholder = source != nil && frame == nil
                current = frame ?? placeholder
            }
        }

        guard let outgoing else { return current }
        let progress = (now - outgoing.startedAt) / transitionDuration
        if progress >= 1 {
            outgoing.source.stop()
            self.outgoing = nil
            return current
        }
        return compositor.dissolve(from: prepared(outgoing.source) ?? placeholder, to: current, progress: progress)
    }

    /// In the plain Backdrop arrangement a paused, closed or forbidden share shows its calm card full size, never a black picture.
    private func shareCard(frame: CIImage?, camera: CIImage) -> CIImage? {
        guard background.isScreenShare else { return nil }
        let status = shareStatus(frame: frame)
        frameShareStatus = status
        guard status == .paused || status == .lost || status == .denied else { return nil }
        let inputs = StageComposer.Inputs(content: frame, status: status, title: stageTitle, layout: stageLayout, camera: camera)
        return stageComposer.fullCard(inputs)
    }
}

extension Compositor {
    /// Wraps a single-channel matte without colour management. Gamma-converting a matte would bend
    /// its mid-tones, which are exactly the soft edge pixels.
    static func matte(from buffer: CVPixelBuffer) -> CIImage {
        CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
    }
}
