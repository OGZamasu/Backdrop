import CoreGraphics
import Foundation
import simd

/// Kamehameha. Cup both hands together at your side with the fingers pointing out sideways, and hold: an orb of blue-white energy grows
/// between them while the status line chants. Push the hands out (along the fingers, at the camera, or spring them apart) and a huge beam
/// roars across the picture to its edge.
final class KamehamehaMove: SaiyanMove {
    let id = "kamehameha"
    let name = "Kamehameha"
    let hint = "Cup both hands together at your side, fingers pointing out, and hold. Then push them out."
    private(set) var isEngaged = false

    // Thresholds, measured on `HandFixtures` (see `SaiyanBeamMoveTests`).

    /// The palms within this many palm lengths of each other: cupped hands with the wrists together read 0.6 to 1.1.
    static let togetherWithin = 1.6
    /// Fingers within this many degrees of level: a hand pointing sideways reads 3, turned half a radian off level 25 to 32.
    static let sidewaysWithin = 40.0
    /// Both hands pointing the same way: the cosine between their axes.
    static let alignedAbove = 0.7
    /// Not a fist or a pointing finger: an open hand reads 1, a peace sign 0.5, a cupped claw about 0.4, a pointing finger 0.25, a fist 0.
    static let openAbove = 0.35
    /// The palms below the chin, in face units below the eyes (the chin is about 1.7 down), so it never meets the Solar Flare in front of
    /// the face, and not off at the far side of the picture.
    static let belowEyes = -1.9
    static let besideWithin = 6.0
    /// Both palms slower than this, in palm lengths a second, while the pose is taken.
    static let stillBelow = 2.5
    /// Seconds held before the move claims the hands, before the orb starts, and to fill it.
    static let engageAfter = 0.2
    static let orbAfter = 0.35
    static let chargeSeconds = 2.0
    /// The least charge that fires anything.
    static let fireCharge = 0.3
    /// A fire is still read for this long after the pose breaks: hands blur and change shape in a thrust.
    static let releaseWindow = 0.35
    /// Pushed at the camera: the palms this much bigger than their smallest over `pushWindow`. Held still they vary by under 3 percent.
    static let pushGrowth = 1.2
    static let pushWindow = 0.3
    /// Thrust along the fingers: this many palm lengths in `thrustWindow` seconds (about 3 palm lengths a second).
    static let thrustTravel = 0.6
    static let thrustWindow = 0.2
    /// Sprung apart: the palms at least this far apart, and this much further than they were over `pushWindow`.
    static let apartAbove = 1.9
    static let apartGrowth = 0.9

    static let signature = SIMD3<Double>(0.36, 0.7, 1.0)

    private enum Phase { case idle, charging, firing }

    /// The two hands as one reading.
    private struct Pair {
        var a: HandState
        var b: HandState
        var centre: CGPoint
        var size: Double
        /// Palm to palm, in palm lengths.
        var separation: Double
        /// The way the fingers point, the two hands averaged.
        var axis: SIMD2<Double>
        /// A hand is being carried through a gap by the tracker.
        var unsure: Bool
    }

    private struct Mark {
        var centre: CGPoint
        var size: Double
        var separation: Double
    }

    private var phase = Phase.idle
    private var hold = SaiyanHold(grace: 0.25)
    private var trail = SaiyanTrail<Mark>(span: 0.5)
    private(set) var charge = 0.0
    private var cooldown = 0.0
    private var face: FaceState?
    private var faceLost = 9.0
    /// Where the orb sits, steadied.
    private var orbAt = HandFXSteady(calm: 2.2, eager: 0.02)
    /// Which way the fingers point, as an angle, steadied.
    private var aim = 0.0
    private var axis: SIMD2<Double> { SIMD2(cos(aim), sin(aim)) }
    private var size = 110.0
    private var orbLevel = HandFXLevel(rise: 0.12, fall: 0.16)
    private var rig = SaiyanBeamRig(style: SaiyanBeamRig.Style(core: 0.12, ringSpacing: 1.0, ringSpeed: 1500, filaments: 3, solid: 1,
                                                               grow: 0.22, fade: 0.5, sparks: 50), seed: 0x6A3E)
    private var motes = SaiyanMotes(seed: 0x6A3F)
    private var ki = SaiyanKi(KamehamehaMove.signature, palette: SaiyanForm.base.palette)
    private var power = 0.0
    private var time = 0.0
    /// How the latest beam was set off ("thrust", "push" or "apart"), and how many have been fired, for the tests.
    private(set) var lastTrigger: String?
    private(set) var fired = 0

    init() {}

    var hasLight: Bool { orbLevel.value > 0.003 || rig.hasLight || !motes.isEmpty }
    var isFiring: Bool { rig.isPouring }
    var beam: SaiyanBeamLook? { rig.look }
    var orbRadius: Double { Self.radius(charge: charge, size: size, power: power) * orbLevel.value }

    var status: LensStatus? {
        guard isEngaged else { return nil }
        if phase == .firing { return LensStatus("Kamehameha!") }
        if charge >= 1 { return LensStatus("Release!", detail: "Push your hands out to fire") }
        let chant = ["Ka...", "me...", "ha...", "me..."]
        return LensStatus(chant[min(3, Int(charge * 4))], detail: charge >= Self.fireCharge ? "Push your hands out to fire" : "Keep holding")
    }

    var screenEffect: SaiyanScreenEffect {
        var e = SaiyanScreenEffect()
        e.shake = max(rig.shake, phase == .charging && charge >= 1 ? 0.04 + 0.06 * power : 0)
        e.flash = rig.flash
        e.flashTint = rig.flashTint
        return e
    }

    /// The orb's radius: up to about 0.6 palm lengths when full (1.2 across), a little more in the stronger forms.
    static func radius(charge: Double, size: Double, power: Double) -> Double {
        let eased = charge * charge * (3 - 2 * charge)
        return 110 * SaiyanBeamKit.handScale(size) * (0.1 + 0.52 * eased) * (1 + 0.25 * power)
    }

    func reset() {
        phase = .idle
        isEngaged = false
        hold.reset()
        trail.removeAll()
        charge = 0
        cooldown = 0
        face = nil
        faceLost = 9
        orbAt.reset()
        orbLevel = HandFXLevel(rise: 0.12, fall: 0.16)
        rig.reset()
        motes.removeAll()
    }

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) {
        let dt = WorldKit.clamped(c.dt)
        time = c.time
        power = c.power
        ki = SaiyanKi(Self.signature, palette: c.palette, tint: 0.75)
        if let f = c.face { face = f; faceLost = 0 } else { faceLost += dt }
        let usable = faceLost < 0.5 ? face : nil

        let p = pair(c.hands)
        var posed: Bool? = false
        if let p {
            trail.add(Mark(centre: p.centre, size: p.size, separation: p.separation), at: time)
            if let f = usable { posed = p.unsure ? nil : isPosed(p, face: f) }
            if posed != false || phase != .idle { follow(p, dt: dt) }
        }
        hold.update(posed, dt: dt)
        cooldown = max(0, cooldown - dt)

        switch phase {
        case .idle:
            if mayBegin, cooldown <= 0, hold.isHeld, hold.held >= Self.engageAfter {
                phase = .charging
                isEngaged = true
                charge = 0
            }
        case .charging:
            if posed == true, hold.held >= Self.orbAfter || charge > 0.05 { charge = min(1, charge + dt / Self.chargeSeconds) }
            let reading = hold.missing <= hold.grace + Self.releaseWindow
            if charge >= Self.fireCharge, reading, let how = trigger() {
                fire(c, how: how)
            } else if !reading {
                // Let go without firing: the energy leaks away, and comes back if the hands do.
                charge = max(0, charge - dt / 0.6)
                if charge <= 0 {
                    phase = .idle
                    isEngaged = false
                }
            }
        case .firing:
            if !rig.isPouring {
                phase = .idle
                isEngaged = false
                cooldown = 0.5
            }
        }

        orbLevel.approach(phase == .charging && charge > 0 ? 1 : 0, dt: dt)
        let origin = p.map { SaiyanBeamHands.offset($0.centre, $0.axis, by: $0.size * 0.7) }
        rig.update(dt: dt, time: time, origin: phase == .firing ? origin : nil, angle: nil, rect: c.rect)
        let r = Self.radius(charge: charge, size: size, power: power)
        motes.update(dt: dt, rate: phase == .charging && charge > 0 ? 22 + 70 * charge : 0, reach: r * 2.2 + 34)
    }

    // MARK: Reading the hands

    private func pair(_ hands: [HandState]) -> Pair? {
        guard hands.count >= 2 else { return nil }
        let a = hands[0], b = hands[1]
        let size = (a.size + b.size) / 2
        let ua = HandFXKit.up(of: a), ub = HandFXKit.up(of: b)
        let sum = ua + ub
        let axis = simd_length(sum) > 1e-6 ? simd_normalize(sum) : ua
        return Pair(a: a, b: b, centre: SaiyanBeamHands.midpoint(a.palm, b.palm), size: size,
                    separation: HandState.distance(a.palm, b.palm) / max(a.size, b.size), axis: axis, unsure: a.unseenFor > 0 || b.unseenFor > 0)
    }

    private func isPosed(_ p: Pair, face: FaceState) -> Bool {
        guard p.separation < Self.togetherWithin, simd_dot(HandFXKit.up(of: p.a), HandFXKit.up(of: p.b)) > Self.alignedAbove else { return false }
        for h in [p.a, p.b] {
            let local = SaiyanZones.palm(h, face)
            guard SaiyanZones.fingerElevation(h) < Self.sidewaysWithin, HandFXPose.openness(h) > Self.openAbove,
                  local.y < Self.belowEyes, abs(local.x) < Self.besideWithin, SaiyanBeamHands.speed(h) < Self.stillBelow else { return false }
        }
        return true
    }

    /// Moves the orb and the aim with the hands.
    private func follow(_ p: Pair, dt: Double) {
        size = p.size
        let centre = SaiyanBeamHands.offset(p.centre, p.axis, by: p.size * 0.55)
        orbAt.update(centre, dt: dt, snap: p.size * 3)
        guard phase != .firing else { return }
        let target = atan2(p.axis.y, p.axis.x)
        if phase == .idle && hold.held < Self.engageAfter * 0.5 {
            aim = target
        } else {
            aim += atan2(sin(target - aim), cos(target - aim)) * min(1, dt / 0.1)
        }
    }

    /// How the hands are setting the beam off, if they are: pushed at the camera, thrust along the fingers, or sprung apart.
    private func trigger() -> String? {
        guard let last = trail.last else { return nil }
        let recent = trail.within(Self.pushWindow, of: time)
        if let smallest = recent.map(\.size).min(), last.size > smallest * Self.pushGrowth { return "push" }
        if let closest = recent.map(\.separation).min(), last.separation > max(Self.apartAbove, closest + Self.apartGrowth) { return "apart" }
        if let from = trail.since(Self.thrustWindow, of: time), from.time < time {
            let moved = SIMD2(Double(last.centre.x - from.value.centre.x), Double(last.centre.y - from.value.centre.y)) / last.size
            if simd_dot(moved, axis) > Self.thrustTravel { return "thrust" }
        }
        return nil
    }

    private func fire(_ c: SaiyanMoveContext, how: String) {
        let from = orbAt.point ?? trail.last?.centre ?? CGPoint(x: c.rect.midX, y: c.rect.midY)
        let side = abs(axis.x) > 0.3 ? (axis.x > 0 ? 1.0 : -1.0) : c.outward(from: from)
        let angle = SaiyanBeamHands.sideways(atan2(axis.y, axis.x), side: side, limit: 0.3)
        let width = 110 * SaiyanBeamKit.handScale(size) * (0.95 + 1.0 * power) * (0.7 + 0.4 * charge)
        rig.style.kick = 0.45 + 0.35 * power
        rig.style.rumble = 0.1 + 0.12 * power
        rig.style.flash = 0.22 + 0.15 * power
        rig.fire(from: from, angle: angle, width: min(380, width), ki: ki, pour: 1.0 + 0.9 * charge, crackle: 1 + Int(power * 3), rect: c.rect)
        phase = .firing
        lastTrigger = how
        fired += 1
        charge = 0
        trail.removeAll()
    }

    // MARK: Drawing

    func washes() -> [SaiyanWash] {
        var out = rig.washes()
        if orbLevel.value > 0.003, let c = orbAt.point {
            let r = Self.radius(charge: charge, size: size, power: power)
            out.append(SaiyanWash(center: c, radius: r * 2.8 + 24, colour: ki.body, alpha: 0.42 * orbLevel.value))
        }
        return out
    }

    func drawSolids(in ctx: CGContext) {
        rig.drawSolids(in: ctx)
        guard orbLevel.value > 0.003, let c = orbAt.point else { return }
        SaiyanBeamKit.drawOrbSolid(at: c, radius: orbRadius * pulse, ki: ki, alpha: orbLevel.value, in: ctx)
    }

    func drawLight(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        if orbLevel.value > 0.003, let c = orbAt.point {
            let r = orbRadius * pulse
            motes.draw(at: c, radius: r, colour: ki.lit(0.3), alpha: orbLevel.value, in: ctx)
            SaiyanBeamKit.drawOrbLight(at: c, radius: r, ki: ki, alpha: orbLevel.value, time: time, seed: 11, crackle: 1 + Int(charge * 4 + power * 3),
                                       full: charge >= 1 ? 1 : 0, in: ctx)
        } else if !motes.isEmpty, let c = orbAt.point {
            motes.draw(at: c, radius: 4, colour: ki.lit(0.3), alpha: 1, in: ctx)
        }
        rig.drawLight(in: ctx)
        ctx.restoreGState()
    }

    /// The orb breathes, quicker as it fills.
    private var pulse: Double { 1 + (0.03 + 0.04 * charge) * sin(time * (7 + 6 * charge)) }
}
