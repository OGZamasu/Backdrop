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
}

/// The rules and look of a game, with no pipeline in it, so the rules can be tested exactly.
protocol Game {
    static var title: String { get }
    /// One line telling the player what to do, shown during the countdown.
    static var hint: String { get }
    /// Whether the game draws the player's face, so the lens should cut it out of the camera each frame.
    static var wantsFaceCrop: Bool { get }
    init(size: CGSize, seed: UInt64)

    var score: Int { get }
    var isOver: Bool { get }
    /// Lives left, time left: whatever belongs beside the score.
    var summary: String { get }

    mutating func step(_ dt: Double, world: GameWorld)
    func draw(in ctx: CGContext, time: Double)
}

extension Game {
    static var wantsFaceCrop: Bool { false }
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

/// Runs any game as a lens: waits for you to step in, counts down, plays, shows your score, and starts again.
final class GameLens<G: Game>: Lens {
    enum Phase: Equatable {
        case waiting
        case countdown(Double)
        case playing
        case over(Double)
    }

    let needs: LensNeeds
    var wantsMatteGrid: Bool { needs.contains(.matte) }

    private(set) var phase = Phase.waiting
    private(set) var game: G
    private let id: String
    private let store: ScoreStore
    private let make: () -> G

    private var presentFor = 0.0
    private var absentFor = 0.0
    private var previousGrid: MatteGrid?
    private var best: Int
    private var beatRecord = false

    static var countdownSeconds: Double { 3 }
    static var gameOverSeconds: Double { 5 }
    /// How long you can be out of frame before the game pauses.
    static var absenceGrace: Double { 1.5 }

    init(id: String, needs: LensNeeds, store: ScoreStore = DefaultsScoreStore(), size: CGSize = CGSize(width: 1280, height: 720),
         make: ((CGSize, UInt64) -> G)? = nil) {
        self.id = id
        self.needs = needs
        self.store = store
        let build = make ?? { G(size: $0, seed: $1) }
        let factory = { build(size, UInt64.random(in: .min ... .max)) }
        self.make = factory
        game = factory()
        best = store.best(for: id)
    }

    var status: LensStatus? { published.value }

    private let published = StatusBox()

    private func currentStatus() -> LensStatus {
        switch phase {
        case .waiting: return LensStatus("Step into the frame", detail: "Best \(best)")
        case .countdown: return LensStatus("Get ready…", detail: "Best \(best)")
        case .playing: return LensStatus("Score \(game.score)", detail: "\(game.summary) · Best \(max(best, game.score))")
        case .over: return LensStatus("Game over: \(game.score)", detail: beatRecord ? "New best!" : "Best \(best)")
        }
    }

    func restart() {
        game = make()
        beatRecord = false
        phase = .countdown(Self.countdownSeconds)
        published.value = currentStatus()
    }

    func render(_ input: LensInput) -> CIImage {
        let dt = input.dt
        let present = isPresent(input)
        presentFor = present ? presentFor + dt : 0
        absentFor = present ? 0 : absentFor + dt

        let motion = input.matteGrid.flatMap { grid in previousGrid.map { grid.motion(since: $0) } }
        let crop = G.wantsFaceCrop ? faceCrop(from: input) : nil
        let world = GameWorld(size: input.rect.size, matte: input.matteGrid, motion: motion, face: input.face, faceCrop: crop)

        switch phase {
        case .waiting:
            if presentFor > 0.5 { restart() }
        case .countdown(let remaining):
            phase = remaining - dt <= 0 ? .playing : .countdown(remaining - dt)
        case .playing:
            if absentFor < Self.absenceGrace { game.step(dt, world: world) }
            if game.isOver { finish() }
        case .over(let elapsed):
            phase = elapsed + dt >= Self.gameOverSeconds ? .waiting : .over(elapsed + dt)
            if case .waiting = phase { presentFor = 0.5 }     // straight into the next round if you're still here
        }
        previousGrid = input.matteGrid?.snapshot()
        published.value = currentStatus()

        guard let layer = input.services.overlay({ ctx in self.draw(ctx, size: input.rect.size, time: input.time) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    /// The face as a small square picture, so a game can draw it as a character.
    private func faceCrop(from input: LensInput) -> CGImage? {
        guard let face = input.face else { return nil }
        let side = max(face.rect.width, face.rect.height) * 0.95
        let box = CGRect(x: face.rect.midX - side / 2, y: face.rect.midY - side / 2, width: side, height: side)
        let scale = 128 / side
        let picture = input.camera.cropped(to: box)
            .transformed(by: CGAffineTransform(translationX: -box.minX, y: -box.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale)))
        return input.services.context.createCGImage(picture, from: CGRect(x: 0, y: 0, width: 128, height: 128),
                                                    format: .BGRA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    private func isPresent(_ input: LensInput) -> Bool {
        if needs.contains(.face) { return input.face != nil }
        return (input.matteGrid?.fraction ?? 0) > 0.03
    }

    private func finish() {
        beatRecord = game.score > best
        store.record(game.score, for: id)
        best = store.best(for: id)
        phase = .over(0)
    }

    // MARK: Drawing

    private func draw(_ ctx: CGContext, size: CGSize, time: Double) {
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        switch phase {
        case .waiting:
            ctx.text(G.title.uppercased(), center: CGPoint(x: middle.x, y: middle.y + 60), size: 64)
            ctx.text("Step into the frame to play", center: CGPoint(x: middle.x, y: middle.y - 10), size: 34, weight: .semibold)
        case .countdown(let remaining):
            ctx.text(G.title.uppercased(), center: CGPoint(x: middle.x, y: size.height - 80), size: 56)
            ctx.text(G.hint, center: CGPoint(x: middle.x, y: size.height - 140), size: 30, weight: .semibold)
            ctx.text(String(Int(remaining.rounded(.up))), center: middle, size: 220)
        case .playing:
            game.draw(in: ctx, time: time)
            drawScore(ctx, size: size)
            if absentFor >= Self.absenceGrace {
                ctx.text("Come back to keep playing", center: middle, size: 48)
            }
        case .over:
            game.draw(in: ctx, time: time)
            ctx.text("GAME OVER", center: CGPoint(x: middle.x, y: middle.y + 70), size: 96)
            ctx.text("Score \(game.score)", center: CGPoint(x: middle.x, y: middle.y - 10), size: 54)
            ctx.text(beatRecord ? "New best!" : "Best \(best)", center: CGPoint(x: middle.x, y: middle.y - 70), size: 38,
                     color: beatRecord ? NSColor(red: 1, green: 0.85, blue: 0.2, alpha: 1) : .white, weight: .bold)
        }
    }

    private func drawScore(_ ctx: CGContext, size: CGSize) {
        ctx.text("\(game.score)", center: CGPoint(x: 90, y: size.height - 60), size: 72)
        ctx.text(game.summary, center: CGPoint(x: size.width - 190, y: size.height - 50), size: 34, weight: .bold)
        ctx.text("BEST \(max(best, game.score))", center: CGPoint(x: size.width - 190, y: size.height - 92), size: 24, weight: .semibold)
    }
}
