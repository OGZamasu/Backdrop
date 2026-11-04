import CoreGraphics
import Foundation
import simd

/// Instant Transmission. Touch two fingers to your forehead and take them away again quickly: you collapse into a column of light and
/// vanish, leaving afterimages fanning out to either side, then flash back a moment later with a ghost sliding in after you.
///
/// The same touch held longer is Special Beam Cannon (another move), so this one only ever acts once the fingers have left the
/// forehead, and never for a touch that lasted past `SaiyanZones.instantTransmissionLimit`. It watches the touch without claiming
/// the hands, so the beam can still take over a long hold.
final class InstantTransmissionMove: SaiyanMove {
    let id = "instant-transmission"
    let name = "Instant Transmission"
    let hint = "Touch two fingers to your forehead and take them away quickly."

    enum Phase: Equatable { case idle, vanishing, gone, returning, after }

    /// Cool white-blue.
    static let signature = SIMD3<Double>(0.74, 0.9, 1.0)

    /// A touch shorter than this is a hand passing by, not a touch.
    static let shortestTouch = 0.08
    /// The fingers must be off the forehead this long before it counts as let go, so a flicker of the tracker does not end a long hold.
    static let releaseSeconds = 0.1
    /// A release waits this long for the other moves to free the hands (they are read one frame late).
    static let pendingSeconds = 0.25
    /// While touching, the hand must be calmer than this, in palm lengths a second.
    static let calmSpeed = 4.0
    static let vanishSeconds = 0.12
    static let goneSeconds = 0.4
    static let returnSeconds = 0.18
    static let afterSeconds = 0.55
    static let cooldownSeconds = 2.0

    private(set) var phase = Phase.idle
    private(set) var jumps = 0
    /// Seconds since the jump began.
    private(set) var sinceJump = 9.0

    private var touchStart: Double?
    private var lastTouch = 0.0
    private var touchHeld = 0.0
    private var overLimit = false
    private var touchHand: Int?
    private var pending: Double?
    private var phaseTime = 0.0
    private var cooldown = 0.0
    private var trail = SaiyanHandTrail()
    private var column = CGPoint.zero
    private var forehead = CGPoint.zero
    private var io = 84.0
    /// The head's tilt at the jump, so the rings round the forehead lie the way the head does.
    private var roll = 0.0
    private var side = 1.0
    private var sinceReturn = 9.0
    private var colour = InstantTransmissionMove.signature
    private var power = 0.0
    private var time = 0.0
    private var rect = CGRect(x: 0, y: 0, width: 1280, height: 720)
    private var motes = ParticleSystem(capacity: 120)
    private var rng = SplitMix64(seed: 0x7E1E)

    init() {
        motes.gravity = SIMD2(0, 160)
    }

    var isEngaged: Bool { phase != .idle && phase != .after }

    var hasLight: Bool { phase != .idle || !motes.particles.isEmpty }

    var status: LensStatus? { isEngaged ? LensStatus("Instant Transmission!") : nil }

    /// How wide the column of light is when it swallows you: head and shoulders.
    private var columnWidth: Double { io * 3.6 }

    var screenEffect: SaiyanScreenEffect {
        guard phase != .idle else { return .none }
        var e = SaiyanScreenEffect()
        let scale = rect.width / 1280
        switch phase {
        case .vanishing:
            let k = phaseTime / Self.vanishSeconds
            e.personOpacity = 1 - SaiyanOrbKit.easeIn(k)
            e.flash = 0.16 * SaiyanOrbKit.swell(k)
        case .gone:
            e.personOpacity = 0
        case .returning:
            e.personOpacity = SaiyanOrbKit.easeOut(phaseTime / Self.returnSeconds)
        default:
            break
        }
        if sinceReturn < 0.6 { e.flash = max(e.flash, 0.5 * exp(-sinceReturn / 0.11) * (1 - SaiyanOrbKit.smooth((sinceReturn - 0.35) / 0.25))) }
        e.flashTint = SaiyanOrbKit.lift(colour, 0.35)
        // Afterimages fanning out to both sides as you go.
        let fan = sinceJump
        if fan < 0.3 {
            let spread = 40 + 80 * SaiyanOrbKit.easeOut(fan / 0.18)
            let fade = 1 - SaiyanOrbKit.smooth(fan / 0.26)
            for (k, s) in [(1.0, -1.0), (1.0, 1.0), (2.0, -1.0), (2.0, 1.0)] {
                e.echoes.append(SaiyanEcho(offset: CGVector(dx: s * k * spread * scale, dy: 4 * k * scale), alpha: 0.28 * fade * (k > 1 ? 0.45 : 1),
                                           tint: colour, tintAmount: 0.42 + 0.12 * k, scale: 1 + 0.02 * fan))
            }
        }
        // A ghost sliding in after you as you come back.
        if sinceReturn < 0.5 {
            let k = SaiyanOrbKit.easeOut(sinceReturn / 0.36)
            let fade = 1 - SaiyanOrbKit.smooth(sinceReturn / 0.48)
            e.echoes.append(SaiyanEcho(offset: CGVector(dx: side * 120 * scale * (1 - k), dy: 0), alpha: 0.4 * fade, tint: colour, tintAmount: 0.5))
            e.echoes.append(SaiyanEcho(offset: CGVector(dx: side * 210 * scale * (1 - k), dy: 0), alpha: 0.2 * fade, tint: colour, tintAmount: 0.62))
        }
        if e.flash < 0.002 { e.flash = 0 }
        return e
    }

    func reset() {
        phase = .idle
        sinceJump = 9
        sinceReturn = 9
        touchStart = nil
        overLimit = false
        touchHand = nil
        pending = nil
        phaseTime = 0
        cooldown = 0
        trail.reset()
        motes.removeAll()
    }

    // MARK: Update

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) {
        let dt = WorldKit.clamped(c.dt)
        time = c.time
        rect = c.rect
        power = c.power
        colour = c.palette.tinting(Self.signature, amount: 0.4)
        trail.update(c.hands, time: c.time)
        cooldown = max(0, cooldown - dt)
        phaseTime += dt
        sinceJump += dt
        sinceReturn += dt

        watchTouch(c, dt: dt)
        if let released = pending {
            if time - released > Self.pendingSeconds + 1e-9 || c.face == nil {
                pending = nil
            } else if mayBegin, phase == .idle, cooldown <= 0, let face = c.face {
                jump(c, face: face)
                pending = nil
            }
        }

        switch phase {
        case .idle:
            break
        case .vanishing:
            if phaseTime >= Self.vanishSeconds { next(.gone) }
        case .gone:
            if phaseTime >= Self.goneSeconds {
                next(.returning)
                sinceReturn = 0
            }
        case .returning:
            if phaseTime >= Self.returnSeconds { next(.after) }
        case .after:
            if phaseTime >= Self.afterSeconds { next(.idle) }
        }

        // A shimmer where you were, rising away while you are gone.
        if phase == .vanishing || phase == .gone {
            let count = Int(dt * 90 + Double.random(in: 0..<1, using: &rng))
            for _ in 0..<count {
                let x = Double(column.x) + Double.random(in: -0.5...0.5, using: &rng) * columnWidth
                let y = Double(forehead.y) - io * Double.random(in: -0.6...3.4, using: &rng)
                motes.emit(Particle(position: SIMD2(x, y), velocity: SIMD2(Double.random(in: -20...20, using: &rng), Double.random(in: 60...200, using: &rng)),
                                    life: Double.random(in: 0.3...0.65, using: &rng), size: Double.random(in: 1.4...3.2, using: &rng)))
            }
        }
        motes.step(dt)
    }

    private func next(_ p: Phase) {
        phase = p
        phaseTime = 0
    }

    /// Follows a touch of the forehead: when it starts, how long it lasts, and whether it was let go in time.
    private func watchTouch(_ c: SaiyanMoveContext, dt: Double) {
        guard let face = c.face else {
            touchStart = nil
            return
        }
        let touching = c.hands.first { hand in
            let atForehead = SaiyanZones.fingersAtForehead(hand, face) || (hand.unseenFor > 0 && hand.id == touchHand && touchStart != nil)
            return atForehead && trail.meanSpeed(hand.id, over: 0.12) < Self.calmSpeed
        }
        if let hand = touching {
            if touchStart == nil {
                touchStart = time
                overLimit = false
                touchHand = hand.id
            }
            lastTouch = time
            // Measured on the clock from the first touch, flickers and all, the way the beam measures its hold.
            touchHeld = time - (touchStart ?? time) + dt
            if touchHeld > SaiyanZones.instantTransmissionLimit + 1e-6 { overLimit = true }
        } else if touchStart != nil, time - lastTouch >= Self.releaseSeconds - 1e-6 {
            // Let go. Only a touch that was short, but not too short, counts.
            if !overLimit, touchHeld >= Self.shortestTouch - 1e-6 { pending = time }
            touchStart = nil
            touchHand = nil
        }
    }

    private func jump(_ c: SaiyanMoveContext, face: FaceState) {
        io = max(face.interocular, 1)
        forehead = face.forehead
        roll = face.roll
        column = CGPoint(x: c.personCenter?.x ?? face.eyeCenter.x, y: face.eyeCenter.y)
        // The ghost comes back from the side the hand went.
        if let id = touchHand ?? c.hands.first?.id, let hand = c.hands.first(where: { $0.id == id }) {
            side = hand.palm.x >= face.eyeCenter.x ? 1 : -1
        } else {
            side = jumps % 2 == 0 ? 1 : -1
        }
        jumps += 1
        sinceJump = 0
        sinceReturn = 9
        cooldown = Self.cooldownSeconds
        next(.vanishing)
    }

    // MARK: Drawing

    /// The column of light: how bright its soft body is, how wide, and how bright the thin white line at its heart (which only shows
    /// while you collapse into it and as you come back out of it, never across your face once you are back).
    private var columnLight: (alpha: Double, width: Double, core: Double) {
        switch phase {
        case .vanishing:
            let k = phaseTime / Self.vanishSeconds
            return (SaiyanOrbKit.clamp01(k * 4), columnWidth * pow(1 - SaiyanOrbKit.easeIn(k), 1.2) + 5, SaiyanOrbKit.clamp01(k * 3))
        case .gone:
            let k = phaseTime / 0.18
            let a = 1 - SaiyanOrbKit.smooth(k)
            return (a, 5 * (1 - 0.6 * SaiyanOrbKit.clamp01(k)), a)
        case .returning:
            let k = phaseTime / Self.returnSeconds
            return (1, 6 + columnWidth * 0.75 * SaiyanOrbKit.easeOut(k), 1 - SaiyanOrbKit.smooth(k * 1.4))
        case .after:
            let k = phaseTime / 0.25
            return (1 - SaiyanOrbKit.smooth(k), columnWidth * 0.75 * (1 + 0.15 * k), 0)
        case .idle:
            return (0, 0, 0)
        }
    }

    func washes() -> [SaiyanWash] {
        let light = columnLight
        guard light.alpha > 0.004 else { return [] }
        // The soft body of the column: glows stacked up the picture, as wide as the column is.
        let reach = max(30, light.width * 0.55)
        var out = (0..<6).map { k -> SaiyanWash in
            let y = rect.minY + rect.height * (Double(k) + 0.5) / 6
            return SaiyanWash(center: CGPoint(x: column.x, y: y), radius: reach, colour: colour, alpha: 0.2 * light.alpha)
        }
        out.append(SaiyanWash(center: CGPoint(x: column.x, y: forehead.y - io * 1.2), radius: columnWidth * 1.3 + 40, colour: colour, alpha: 0.24 * light.alpha))
        return out
    }

    func drawLight(in ctx: CGContext) {
        guard hasLight else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        let scale = rect.width / 1280
        let light = columnLight
        if light.core > 0.004 {
            SaiyanOrbKit.column(ctx, x: column.x, bottom: rect.minY - 4, top: rect.maxY + 4, width: min(max(6, light.width * 0.5), 44 * scale), colour: colour,
                                alpha: light.core)
        }
        drawStreaks(ctx, scale: scale)
        drawRings(ctx, scale: scale)
        if sinceJump < 0.3 {
            let k = sinceJump / 0.3
            SaiyanOrbKit.glint(ctx, at: forehead, radius: io * (0.7 + 0.6 * SaiyanOrbKit.easeOut(k)), colour: SaiyanOrbKit.lift(colour, 0.5), alpha: 1 - SaiyanOrbKit.smooth(k))
        }
        for p in motes.particles {
            let fade = (1 - p.progress) * min(1, p.age / 0.08)
            SaiyanOrbKit.glow(ctx, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * 2.2, colour: SaiyanOrbKit.lift(colour, 0.4), alpha: 0.8 * fade)
        }
        ctx.restoreGState()
    }

    /// Lines of light shooting up off you as you go, and down into you as you come back.
    private func drawStreaks(_ ctx: CGContext, scale: Double) {
        let goingUp = sinceJump < 0.55
        let comingDown = sinceReturn < 0.3
        guard goingUp || comingDown else { return }
        for k in 0..<16 {
            let h1 = WorldKit.hash(k &* 17 &+ jumps), h2 = WorldKit.hash(k &* 29 &+ 5), h3 = WorldKit.hash(k &* 41 &+ 11)
            let x = Double(column.x) + (h1 - 0.5) * columnWidth * 1.25
            let length = (90 + 220 * h2) * scale
            let base = Double(forehead.y) - io * (3.6 - 4.2 * h3)
            if goingUp {
                let t = sinceJump
                let y = base + (900 + 900 * h2) * scale * t
                let alpha = SaiyanOrbKit.clamp01(t / 0.05) * (1 - SaiyanOrbKit.smooth(t / 0.55))
                SaiyanOrbKit.streak(ctx, head: CGPoint(x: x, y: y), angle: .pi / 2, length: length, width: (3 + 3 * h3) * scale, colour: colour, alpha: 0.9 * alpha)
            }
            if comingDown {
                let t = sinceReturn
                let y = base + (1 - SaiyanOrbKit.easeOut(t / 0.22)) * 360 * scale
                let alpha = 1 - SaiyanOrbKit.smooth(t / 0.3)
                SaiyanOrbKit.streak(ctx, head: CGPoint(x: x, y: y), angle: -.pi / 2, length: length * 0.8, width: (3 + 2 * h3) * scale, colour: colour,
                                    alpha: 0.8 * alpha)
            }
        }
    }

    /// Rings round the forehead: thrown out as you vanish, pulled in as you return.
    private func drawRings(_ ctx: CGContext, scale: Double) {
        for (k, delay) in [0.0, 0.07].enumerated() {
            let u = (sinceJump - delay) / 0.38
            if u > 0, u < 1 {
                SaiyanOrbKit.ring(ctx, center: forehead, radius: io * (0.5 + 2.3 * SaiyanOrbKit.easeOut(u)), squash: 0.32, angle: roll, width: (3.5 - Double(k)) * scale * (1 - 0.5 * u),
                                  colour: colour, alpha: (1 - u) * (1 - u), thread: k == 0)
            }
            let v = (sinceReturn - delay) / 0.24
            if v > 0, v < 1 {
                SaiyanOrbKit.ring(ctx, center: forehead, radius: io * (2.4 - 1.8 * SaiyanOrbKit.easeOut(v)), squash: 0.32, angle: roll, width: (3 - Double(k)) * scale,
                                  colour: colour, alpha: SaiyanOrbKit.swell(v), thread: false)
            }
        }
    }
}
