import AppKit
import CoreImage

/// What a game can see of the player.
struct GameWorld {
    let size: CGSize
    /// The person's silhouette, or nil if the game doesn't use it.
    let matte: MatteQuery?
    /// Where the silhouette moved since the last frame.
    let motion: MatteQuery?
    let face: FaceState?
    /// A square picture of the player's face, for games that make it the star. Only supplied when `wantsFaceCrop`.
    var faceCrop: CGImage? = nil
    /// The hands in view, up to two. Empty when the game doesn't use them or none are found.
    var hands: [HandState] = []
}

/// The rules and look of a game, with no pipeline in it, so the rules can be tested exactly.
///
/// The game draws only its own world (`draw`). Everything else on screen (the waiting card, the countdown, the score and status
/// plates, the hints, the pause and the result card) is drawn by `GameLens` from `GameScreens`, the same for every game. The hooks
/// after `draw` let a game fill those screens in richer detail; each has a sensible default made from `score` and `summary`.
protocol Game {
    static var title: String { get }
    /// One line telling the player what to do, shown during the countdown.
    static var hint: String { get }
    /// Whether the game draws the player's face, so the lens should cut it out of the camera each frame.
    static var wantsFaceCrop: Bool { get }
    /// What the waiting screen asks for: "Step into the frame to play", or "Hold up your hand" for a game played with hands.
    static var presenceHint: String { get }
    init(size: CGSize, seed: UInt64)

    var score: Int { get }
    var isOver: Bool { get }
    /// Lives left, time left: whatever belongs beside the score, as words for the status line.
    var summary: String { get }

    mutating func step(_ dt: Double, world: GameWorld)
    /// Draws the game's own world: its art, never its score, title or result (the screens draw those).
    func draw(in ctx: CGContext, time: Double)

    // MARK: Screens

    /// What the plates in the corners show while the game is played.
    var readout: GameUIReadout { get }
    /// How the round went, for the result card.
    var result: GameUIResult { get }
    /// A line or two shown in turn along the bottom in the first seconds of play, to teach the game while it is played.
    static var onboarding: [String] { get }
    /// The game's own colour: its title and highlights on every card.
    static var accent: SIMD3<Double> { get }
    /// How the game is played, for the icon on its cards.
    static var icon: GameUIIcon { get }
    /// The word over the score: "SCORE", "METRES".
    static var scoreLabel: String { get }
    /// The score as a person reads it: "12.3 s", "245".
    static func scoreText(_ score: Int) -> String
    /// Draws one more of the game's sprites ahead of time, so the first frame of play does not stall baking them all at once.
    /// Called once a frame during the countdown with `step` counting up from 0; returns false when there is nothing left to bake.
    static func warmUp(_ step: Int) -> Bool
    /// How many pixels across the face picture is cut, for games that show the face big.
    static var faceCropSide: Int { get }
    /// Called instead of `step` while the result card shows, so the game can ease its pieces out of the card's way. Nothing in the
    /// rules may change here.
    mutating func settle(_ dt: Double)
}

extension Game {
    static var wantsFaceCrop: Bool { false }
    static var presenceHint: String { "Step into the frame to play" }

    /// The score, with the summary as a word in the status plate.
    var readout: GameUIReadout { GameUIReadout(score: score, label: summary.isEmpty ? nil : summary) }
    var result: GameUIResult { GameUIResult(headline: "Game over", line: summary) }
    /// The hint, a sentence at a time.
    static var onboarding: [String] { GameUIType.sentences(hint) }
    static var accent: SIMD3<Double> { GameUIPalette.gold }
    static var icon: GameUIIcon { .automatic }
    static var scoreLabel: String { "SCORE" }
    static func scoreText(_ score: Int) -> String { "\(score)" }
    static func warmUp(_ step: Int) -> Bool { false }
    static var faceCropSide: Int { 128 }
    mutating func settle(_ dt: Double) {}
}

/// A status line that can be read from the interface while the video queue keeps writing it.
final class StatusBox {
    private let lock = NSLock()
    private var stored: LensStatus?
    var value: LensStatus? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Remembers best scores between launches.
protocol ScoreStore {
    func best(for id: String) -> Int
    func record(_ score: Int, for id: String)
}

final class DefaultsScoreStore: ScoreStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func best(for id: String) -> Int { defaults.integer(forKey: "backdrop.best.\(id)") }
    func record(_ score: Int, for id: String) {
        if score > best(for: id) { defaults.set(score, forKey: "backdrop.best.\(id)") }
    }
}

final class MemoryScoreStore: ScoreStore {
    private var scores: [String: Int] = [:]
    func best(for id: String) -> Int { scores[id] ?? 0 }
    func record(_ score: Int, for id: String) { scores[id] = max(score, scores[id] ?? 0) }
}

/// Runs any game as a lens: waits for the player, counts down, plays, shows how it went, and starts again, all in the shared
/// `GameScreens`. What counts as "the player is here" depends on what the lens needs: a silhouette for a body game, a hand for a
/// hand game, a face for a face game (`HandGameLens` and `FaceGameLens` are this runner with those rules).
///
/// It keeps playing through a short loss of tracking, pauses (and says so, low in the picture) when the player has been gone a
/// while, remembers best scores, and bakes the screens' and the game's pictures a little at a time during the countdown so play
/// never starts with a stall.
class GameLens<G: Game>: Lens {
    enum Phase: Equatable {
        case waiting
        case countdown(Double)
        case playing
        case over(Double)
    }

    let needs: LensNeeds
    var wantsMatteGrid: Bool { needs.contains(.matte) }
    /// What the player plays with, from `needs`: hands if it needs hands, a face if it needs only a face, otherwise the body.
    let player: GameUIPlayer

    private(set) var phase = Phase.waiting
    private(set) var game: G
    private let id: String
    private let store: ScoreStore
    private let make: () -> G
    private let look: GameScreens.Look

    /// Seconds of the player seen while waiting. It drains instead of resetting on a missed frame, so a flickering tracker still
    /// starts a round, and empties once the player has really gone.
    private var presence = 0.0
    private var absentFor = 0.0
    /// Seconds of play, not counting pauses.
    private var playedFor = 0.0
    /// Seconds since the current phase began.
    private var phaseAge = 0.0
    private var previousGrid: MatteGrid?
    private var best: Int
    private var beatRecord = false
    private var finalResult: GameUIResult?
    private var motion = GameUIMotion()
    private var warmStep = 0
    private var lineWarmStep = 0
    private var rehearsed = false
    private let frameSize: CGSize
    private var gameWarmStep = 0
    /// The opening hints, worked out on first use (on the video queue: laying out text is not for the main thread).
    private lazy var onboarding: [String] = G.onboarding
    /// Whether the game's pictures are baked; from then on its world shows behind the countdown.
    private var warmed = false
    private var warmedAt = 0.0
    private var cropTick = 0
    /// The live tip on show along the bottom, and how far it has faded in: a tip fades rather than popping, and a new one waits for
    /// the old one to fade out.
    private var tipText: String?
    private var tipAlpha = 0.0

    class var countdownSeconds: Double { 3 }
    class var gameOverSeconds: Double { 6 }
    /// How long the player can be gone before the game pauses.
    class var absenceGrace: Double { 1.5 }
    /// How long the opening hints stay up.
    class var onboardingSeconds: Double { 7 }
    /// How long the player has to be there before a round starts.
    class var settleSeconds: Double { 0.5 }
    /// The resampling the game's own art is drawn with; nil leaves the overlay's default.
    class var artInterpolation: CGInterpolationQuality? { nil }

    init(id: String, needs: LensNeeds, store: ScoreStore = DefaultsScoreStore(), size: CGSize = CGSize(width: 1280, height: 720),
         make: ((CGSize, UInt64) -> G)? = nil) {
        self.id = id
        self.needs = needs
        self.store = store
        let player: GameUIPlayer = needs.contains(.hands) ? .hands : (needs.contains(.face) && !needs.contains(.matte) ? .face : .body)
        self.player = player
        frameSize = size
        let build = make ?? { G(size: $0, seed: $1) }
        let factory = { build(size, UInt64.random(in: .min ... .max)) }
        self.make = factory
        game = factory()
        best = store.best(for: id)
        look = GameScreens.Look(title: G.title, hint: G.hint, presenceHint: G.presenceHint, accent: G.accent,
                                icon: G.icon == .automatic ? player.icon : G.icon, scoreLabel: G.scoreLabel, player: player)
        GameScreens.prepare(look)
    }

    var status: LensStatus? { published.value }
    private let published = StatusBox()

    private func currentStatus() -> LensStatus {
        let bestLine = "Best \(G.scoreText(best))"
        switch phase {
        case .waiting: return LensStatus(G.presenceHint, detail: bestLine)
        case .countdown: return LensStatus("Get ready…", detail: G.hint)
        case .playing: return LensStatus("Score \(G.scoreText(game.score))", detail: "\(game.summary) · Best \(G.scoreText(max(best, game.score)))")
        case .over:
            let detail = beatRecord ? "New best!" : bestLine
            switch finalResult?.kind ?? .lost {
            case .won: return LensStatus("You win! \(G.scoreText(game.score))", detail: detail)
            case .timeUp: return LensStatus("Time's up: \(G.scoreText(game.score))", detail: detail)
            case .lost: return LensStatus("Game over: \(G.scoreText(game.score))", detail: detail)
            }
        }
    }

    func restart() {
        game = make()
        motion.reset()
        beatRecord = false
        finalResult = nil
        playedFor = 0
        tipText = nil
        tipAlpha = 0
        phase = .countdown(Self.countdownSeconds)
        phaseAge = 0
        warmStep = 0
        lineWarmStep = 0
        gameWarmStep = 0
        published.value = currentStatus()
    }

    /// Ends the round now, as if the game had finished: for tests and previews of the result card.
    func endRound() {
        if phase == .playing { finish() }
    }

    func render(_ input: LensInput) -> CIImage {
        let dt = max(0, input.dt)
        let present = isPresent(input)
        if present {
            presence += dt
            absentFor = 0
        } else {
            absentFor += dt
            presence = absentFor > 0.4 ? 0 : max(0, presence - dt * 0.5)
        }
        phaseAge += dt

        // The face picture is cut out on every other frame: reading it back from the graphics card is the dearest thing a face game
        // does, and fifteen new pictures a second look just as live.
        cropTick += 1
        let crop = G.wantsFaceCrop && phase == .playing && cropTick % 2 == 1 ? faceCrop(from: input) : nil
        let motionGrid = input.matteGrid.flatMap { grid in previousGrid.map { grid.motion(since: $0) } }
        let world = GameWorld(size: input.rect.size, matte: input.matteGrid, motion: motionGrid, face: input.face, faceCrop: crop, hands: input.hands)

        switch phase {
        case .waiting:
            if presence >= Self.settleSeconds { restart() }
        case .countdown(let remaining):
            warmUp(time: input.time)
            if remaining - dt <= 0 {
                phase = .playing
                phaseAge = 0
            } else {
                phase = .countdown(remaining - dt)
            }
        case .playing:
            if absentFor < Self.absenceGrace {
                game.step(dt, world: world)
                playedFor += dt
            }
            let readout = game.readout
            motion.step(dt, readout: readout, record: best > 0 && game.score > best)
            fadeTip(toward: absentFor < Self.absenceGrace && playedFor > 0.5 && onboardingLine() == nil ? readout.tip : nil, dt: dt)
            if game.isOver { finish() }
        case .over(let elapsed):
            game.settle(dt)
            if elapsed + dt >= Self.gameOverSeconds {
                phase = .waiting
                phaseAge = 0
                presence = absentFor < 0.3 ? Self.settleSeconds : 0      // straight into the next round if you're still here
            } else {
                phase = .over(elapsed + dt)
            }
        }
        if wantsMatteGrid { previousGrid = input.matteGrid?.snapshot() }
        published.value = currentStatus()

        let size = input.rect.size, time = input.time
        guard let layer = input.services.overlay({ ctx in self.draw(ctx, size: size, time: time) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    /// Moves the tip toward `wanted`: fading in, fading out, or out and back in with new words.
    private func fadeTip(toward wanted: String?, dt: Double) {
        if let wanted, wanted == tipText || tipAlpha < 0.02 {
            tipText = wanted
            tipAlpha = min(1, tipAlpha + dt / 0.25)
        } else {
            tipAlpha = max(0, tipAlpha - dt / 0.2)
        }
    }

    /// Bakes one more of the screens' pictures, then the opening hints, then one more of the game's, each frame of the countdown.
    private func warmUp(time: Double) {
        guard !warmed else { return }
        if GameScreens.warmUp(warmStep, look: look) {
            warmStep += 1
        } else if lineWarmStep < onboarding.count {
            _ = GameUIType.image(onboarding[lineWarmStep], size: 25, weight: .bold)
            lineWarmStep += 1
        } else if !rehearsed {
            // The plates as they will first look, drawn where nobody sees them, so their words and widths are ready for "GO".
            rehearsed = true
            if let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: GameUISprites.space,
                                   bitmapInfo: Sprites.bitmapInfo) {
                GameScreens.plates(ctx, size: frameSize, look: look, readout: game.readout, scoreText: G.scoreText(game.score),
                                   best: best > 0 ? G.scoreText(best) : nil, record: false, motion: GameUIMotion(), time: 0)
            }
        } else if G.warmUp(gameWarmStep) {
            gameWarmStep += 1
        } else {
            warmed = true
            warmedAt = time
        }
    }

    /// The face as a small square picture, so a game can draw it as a character.
    private func faceCrop(from input: LensInput) -> CGImage? {
        guard let face = input.face else { return nil }
        let side = max(face.rect.width, face.rect.height) * 0.95
        guard side > 4 else { return nil }
        let box = CGRect(x: face.rect.midX - side / 2, y: face.rect.midY - side / 2, width: side, height: side)
        let out = CGFloat(G.faceCropSide)
        let scale = out / side
        let picture = input.camera.cropped(to: box)
            .transformed(by: CGAffineTransform(translationX: -box.minX, y: -box.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale)))
        return input.services.context.createCGImage(picture, from: CGRect(x: 0, y: 0, width: out, height: out),
                                                    format: .BGRA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    private func isPresent(_ input: LensInput) -> Bool {
        switch player {
        case .hands: return !input.hands.isEmpty
        case .face: return input.face != nil
        case .body: return (input.matteGrid?.fraction ?? 0) > 0.03
        }
    }

    private func finish() {
        beatRecord = game.score > best
        finalResult = game.result
        store.record(game.score, for: id)
        best = store.best(for: id)
        phase = .over(0)
        phaseAge = 0
    }

    // MARK: Drawing

    private func drawArt(_ ctx: CGContext, time: Double, alpha: Double = 1) {
        ctx.saveGState()
        if let quality = Self.artInterpolation { ctx.interpolationQuality = quality }
        if alpha < 0.99 {
            ctx.setAlpha(CGFloat(max(0, alpha)))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            game.draw(in: ctx, time: time)
            ctx.endTransparencyLayer()
        } else {
            game.draw(in: ctx, time: time)
        }
        ctx.restoreGState()
    }

    private func draw(_ ctx: CGContext, size: CGSize, time: Double) {
        switch phase {
        case .waiting:
            GameScreens.waiting(ctx, size: size, look: look, progress: presence / Self.settleSeconds, best: best > 0 ? G.scoreText(best) : nil,
                                age: phaseAge, time: time)
        case .countdown(let remaining):
            // The game's world fades in behind the card once its pictures are ready, so the board is there before "GO".
            if warmed { drawArt(ctx, time: time, alpha: (time - warmedAt) / 0.3) }
            GameScreens.countdown(ctx, size: size, look: look, remaining: remaining, total: Self.countdownSeconds, time: time)
        case .playing:
            drawArt(ctx, time: time)
            let readout = game.readout
            let record = best > 0 && game.score > best
            GameScreens.plates(ctx, size: size, look: look, readout: readout, scoreText: G.scoreText(readout.score),
                               best: best > 0 ? G.scoreText(best) : nil, record: record, motion: motion, time: time)
            if playedFor < 0.7 { GameScreens.go(ctx, size: size, look: look, age: playedFor, time: time) }
            if absentFor >= Self.absenceGrace {
                GameScreens.paused(ctx, size: size, look: look, age: absentFor - Self.absenceGrace, time: time)
            } else if let line = onboardingLine() {
                GameScreens.pill(ctx, size: size, text: line.text, look: look, alpha: line.alpha, time: time)
            } else if let tip = tipText {
                GameScreens.pill(ctx, size: size, text: tip, look: look, alpha: GameUIEase.inOut(tipAlpha), time: time)
            }
        case .over(let elapsed):
            drawArt(ctx, time: time)
            GameScreens.result(ctx, size: size, look: look, result: finalResult ?? game.result, score: game.score, scoreText: G.scoreText,
                               best: best > 0 ? G.scoreText(best) : nil, newBest: beatRecord, age: elapsed, total: Self.gameOverSeconds, time: time)
        }
    }

    /// The opening hint showing now, if any: each line in turn, fading in and out, after "GO" has cleared.
    private func onboardingLine() -> (text: String, alpha: Double)? {
        let lines = onboarding
        let start = 0.6
        guard !lines.isEmpty, playedFor >= start, playedFor < start + Self.onboardingSeconds else { return nil }
        let per = Self.onboardingSeconds / Double(lines.count)
        let local = playedFor - start
        let index = min(lines.count - 1, Int(local / per))
        let within = local - Double(index) * per
        let alpha = min(1, within / 0.3, (per - within) / 0.4)
        return alpha > 0.01 ? (lines[index], alpha) : nil
    }
}
