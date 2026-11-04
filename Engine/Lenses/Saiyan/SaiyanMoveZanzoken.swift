import CoreGraphics
import Foundation
import simd

/// Zanzoken, the afterimage dash. Sweep a hand sideways very fast and copies of you peel away behind the sweep, tinted in the form's
/// colour and fading, while streaks of speed rip across the picture.
///
/// The gesture recogniser's own swipe fires at about 6 palm lengths a second, which an eager wave reaches, so this reads the palm's path
/// itself and asks for much more: at least `fireSpeed` palm lengths a second, `travel` palm lengths covered in a fifth of a second, one
/// way only (a wave turns back), by a hand that was already in the picture (not one swinging in from the edge).
final class ZanzokenMove: SaiyanMove {
    let id = "zanzoken"
    let name = "Zanzoken"
    let hint = "Sweep one hand sideways very fast."

    /// The afterimages' colour in base form: a translucent blue. Other forms lend their own aura colour.
    static let signature = SIMD3<Double>(0.45, 0.72, 1.0)

    static let fireSpeed = 9.0
    /// Palm lengths the palm must cover over `window` seconds, mostly sideways.
    static let travel = 2.0
    static let window = 0.2
    /// In the half second before the sweep, the palm may not have been more than this many palm lengths over on the side it sweeps
    /// toward: a wave was just there. A small wind-up the other way is fine.
    static let turnBack = 1.0
    /// And never slower than this many pixels a second at 1280 wide, so tiny far-off hands do not fire on tracking jitter.
    static let minimumPixels = 450.0
    static let cooldownSeconds = 0.8
    static let engagedSeconds = 0.35
    static let lifeSeconds = 0.8

    private(set) var dashes = 0
    /// +1 for a sweep toward the right of the picture, -1 toward the left.
    private(set) var direction = 1.0
    /// Seconds since the latest dash.
    private(set) var since = 9.0

    private var cooldown = 0.0
    private var count = 3
    private var spacing = 50.0
    private var tint = ZanzokenMove.signature
    private var sweepFrom = CGPoint.zero, sweepTo = CGPoint.zero
    private var sweepSize = 100.0
    private var streaks: [Streak] = []
    private var trail = SaiyanHandTrail()
    private var rng = SplitMix64(seed: 0x2A2E)
    private var power = 0.0
    private var time = 0.0
    private var rect = CGRect(x: 0, y: 0, width: 1280, height: 720)

    private struct Streak {
        var y: Double
        var x: Double
        var speed: Double
        var length: Double
        var width: Double
        var delay: Double
    }

    init() {}

    var isEngaged: Bool { since < Self.engagedSeconds }

    var hasLight: Bool { since < Self.lifeSeconds }

    var status: LensStatus? { isEngaged ? LensStatus("Zanzoken!") : nil }

    var screenEffect: SaiyanScreenEffect {
        guard since < Self.lifeSeconds else { return .none }
        var e = SaiyanScreenEffect()
        let scale = rect.width / 1280
        let out = SaiyanOrbKit.easeOutBack(since / 0.14, overshoot: 1.3)
        for k in 1...count {
            let kd = Double(k)
            let fade = 1 - SaiyanOrbKit.smooth((since - 0.03 * kd) / (Self.lifeSeconds - 0.15))
            guard fade > 0.004 else { continue }
            let dx = -direction * spacing * kd * out * (1 + 0.2 * since) * scale
            // Each copy further back is fainter and more of the form's colour: the near one is still you, the far one a coloured ghost.
            e.echoes.append(SaiyanEcho(offset: CGVector(dx: dx, dy: 0), alpha: 0.46 * (1 - 0.17 * (kd - 1)) * fade, tint: tint,
                                       tintAmount: 0.28 + 0.11 * kd))
        }
        e.shake = 0.14 * exp(-since / 0.1) * (1 - SaiyanOrbKit.smooth((since - 0.3) / 0.2))
        if e.shake < 0.002 { e.shake = 0 }
        return e
    }

    func reset() {
        since = 9
        cooldown = 0
        streaks.removeAll()
        trail.reset()
    }

    // MARK: Update

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) {
        let dt = WorldKit.clamped(c.dt)
        time = c.time
        rect = c.rect
        power = c.power
        trail.update(c.hands, time: c.time)
        cooldown = max(0, cooldown - dt)
        since += dt
        guard mayBegin, cooldown <= 0 else { return }
        for hand in c.hands where hand.unseenFor <= 0 {
            if let sweep = sweep(hand) {
                dash(c, hand: hand, direction: sweep)
                break
            }
        }
    }

    /// The direction of a fast one-way sideways sweep of this hand, or nil.
    private func sweep(_ hand: HandState) -> Double? {
        let size = hand.size
        guard trail.known(hand.id, for: 0.4) else { return nil }
        let moved = trail.travel(hand.id, over: Self.window)
        let across = Double(moved.dx) / size
        guard abs(across) >= Self.travel, abs(Double(moved.dy)) <= abs(Double(moved.dx)) * 0.6 else { return nil }
        let way = across > 0 ? 1.0 : -1.0
        // Fast right now, in the same direction.
        let own = trail.velocity(hand.id, over: 0.07, fallback: hand.velocity)
        let speed = max(Double(own.dx) * way, Double(hand.velocity.dx) * way)
        guard speed / size >= Self.fireSpeed, speed >= Self.minimumPixels * rect.width / 1280 else { return nil }
        // Not a hand swinging in from outside the picture.
        guard let start = trail.origin(hand.id, within: Self.window), rect.insetBy(dx: size * 0.6, dy: 0).contains(start.palm) else { return nil }
        // Not the second half of a wave: in the half second before, the palm was never far over on the side it is sweeping toward.
        let ahead = trail.excursion(hand.id, from: Self.window + 0.5, to: Self.window, along: CGVector(dx: way, dy: 0), beyond: start.palm)
        guard ahead < Self.turnBack * size else { return nil }
        return way
    }

    private func dash(_ c: SaiyanMoveContext, hand: HandState, direction way: Double) {
        dashes += 1
        direction = way
        since = 0
        cooldown = Self.cooldownSeconds
        count = 3 + Int((2 * c.power).rounded())
        let farthest = min(200, 140 + 60 * c.power)
        spacing = farthest / Double(count)
        tint = c.form.isBase ? Self.signature : SaiyanOrbKit.mix(Self.signature, c.palette.auraMid, 0.8)
        sweepTo = hand.palm
        sweepFrom = CGPoint(x: hand.palm.x - way * hand.size * 2.6, y: hand.palm.y)
        sweepSize = hand.size
        // Streaks of speed across the picture, most of them about the height of the person.
        streaks = (0..<18).map { _ in
            let h = pow(Double.random(in: 0..<1, using: &rng), 0.8)
            return Streak(y: rect.minY + rect.height * (0.12 + 0.8 * h), x: rect.minX + rect.width * Double.random(in: -0.3...1.0, using: &rng),
                          speed: Double.random(in: 2200...3600, using: &rng), length: Double.random(in: 220...640, using: &rng),
                          width: Double.random(in: 2.4...6.5, using: &rng), delay: Double.random(in: 0...0.08, using: &rng))
        }
    }

    // MARK: Drawing

    func drawLight(in ctx: CGContext) {
        guard hasLight else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        let scale = rect.width / 1280
        let light = SaiyanOrbKit.lift(tint, 0.55)
        for s in streaks {
            let t = since - s.delay
            guard t > 0 else { continue }
            let fade = SaiyanOrbKit.clamp01(t / 0.04) * (1 - SaiyanOrbKit.smooth(t / 0.38))
            guard fade > 0.004 else { continue }
            let x0 = direction > 0 ? s.x : rect.maxX - (s.x - rect.minX)
            let head = CGPoint(x: x0 + direction * s.speed * t * scale, y: s.y)
            SaiyanOrbKit.streak(ctx, head: head, angle: direction > 0 ? 0 : .pi, length: s.length * scale, width: s.width * scale, colour: light,
                                alpha: 0.85 * fade)
        }
        // Motion lines left by the sweeping hand itself, trailing off behind it.
        let fade = 1 - SaiyanOrbKit.smooth(since / 0.28)
        if fade > 0.004 {
            let length = HandState.distance(sweepFrom, sweepTo)
            for (k, offset) in [-0.32, 0.04, 0.38].enumerated() {
                let head = CGPoint(x: sweepTo.x - direction * sweepSize * 0.3 * Double(k % 2), y: sweepTo.y + offset * sweepSize)
                SaiyanOrbKit.streak(ctx, head: head, angle: direction > 0 ? 0 : .pi, length: length * (0.75 + 0.15 * Double(k)), width: 5 * scale,
                                    colour: light, alpha: 0.8 * fade)
            }
        }
        ctx.restoreGState()
    }
}
