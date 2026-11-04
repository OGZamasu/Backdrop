import CoreGraphics
import Foundation
import simd

/// Final Flash. Hold both open palms up side by side at your chest, facing the camera: both palms glow and a yellow sphere gathers in front
/// of them. Push the palms at the camera and a very wide yellow-white beam blasts sideways across the picture with a big flash.
final class FinalFlashMove: SaiyanMove {
    let id = "final-flash"
    let name = "Final Flash"
    let hint = "Hold both open palms up side by side at your chest, then push them at the camera."
    private(set) var isEngaged = false

    // Thresholds, measured on `HandFixtures` (see `SaiyanBeamMoveTests`).

    /// Both hands open: an open hand reads 1, an OK sign 0.94, a peace sign 0.5.
    static let openAbove = 0.75
    /// Fingers up: upright reads 87 degrees from level, turned half a radian 58 to 65.
    static let upAbove = 52.0
    /// Side by side and close: palm to palm within this many palm lengths (touching thumbs read about 1.1), further apart across than up and
    /// down. The power-down pose of the body half is both palms at least 2.5 apart, so the two never meet.
    static let togetherWithin = 2.0
    /// Chest height, in face units below the eyes: under the chin far enough to stay out of the Solar Flare's reach in front of the face
    /// (1.7 eye spacings from the middle of the face), and in front of the body.
    static let chestTop = -2.3
    static let chestBottom = -6.5
    static let besideWithin = 4.0
    static let stillBelow = 2.5
    static let engageAfter = 0.2
    /// The sphere starts gathering after this, and fills over `chargeSeconds`.
    static let sphereAfter = 0.45
    static let chargeSeconds = 1.6
    static let fireCharge = 0.15
    static let releaseWindow = 0.35
    /// Pushed at the camera: both palms together this much bigger than their smallest over `pushWindow`.
    static let pushGrowth = 1.18
    static let pushWindow = 0.35

    static let signature = SIMD3<Double>(1.0, 0.85, 0.28)

    private enum Phase { case idle, charging, firing }

    private struct Pair {
        var a: HandState
        var b: HandState
        var centre: CGPoint
        var size: Double
        var unsure: Bool
    }

    private var phase = Phase.idle
    private var hold = SaiyanHold(grace: 0.25)
    private var sizes = SaiyanTrail<Double>(span: 0.5)
    private(set) var charge = 0.0
    private var cooldown = 0.0
    private var face: FaceState?
    private var faceLost = 9.0
    private var sphereAt = HandFXSteady(calm: 2.2, eager: 0.02)
    private var palms: (CGPoint, CGPoint)?
    private var size = 110.0
    private var level = HandFXLevel(rise: 0.14, fall: 0.18)
    private var rig = SaiyanBeamRig(style: SaiyanBeamRig.Style(core: 0.14, ringSpacing: 0.9, ringSpeed: 1700, filaments: 2, wobble: 1.2, solid: 1,
                                                               grow: 0.18, fade: 0.55, sparks: 55, impact: 0.85), seed: 0xF1A5)
    private var motes = SaiyanMotes(seed: 0xF1A6)
    private var ki = SaiyanKi(FinalFlashMove.signature, palette: SaiyanForm.base.palette)
    private var power = 0.0
    private var time = 0.0
    private(set) var fired = 0

    init() {}

    var hasLight: Bool { level.value > 0.003 || rig.hasLight || !motes.isEmpty }
    var isFiring: Bool { rig.isPouring }
    var beam: SaiyanBeamLook? { rig.look }
    var sphereRadius: Double { Self.radius(charge: charge, size: size, power: power) * level.value }

    var status: LensStatus? {
        guard isEngaged else { return nil }
        if phase == .firing { return LensStatus("Final Flash!") }
        if charge >= 1 { return LensStatus("Final Flash ready", detail: "Push both palms at the camera") }
        return LensStatus("Charging Final Flash...", detail: charge >= Self.fireCharge ? "Push both palms at the camera" : "Keep holding")
    }

    var screenEffect: SaiyanScreenEffect {
        var e = SaiyanScreenEffect()
        e.shake = max(rig.shake, phase == .charging && charge >= 1 ? 0.05 + 0.06 * power : 0)
        e.flash = rig.flash
        e.flashTint = rig.flashTint
        return e
    }

    static func radius(charge: Double, size: Double, power: Double) -> Double {
        let eased = charge * charge * (3 - 2 * charge)
        return 110 * SaiyanBeamKit.handScale(size) * (0.1 + 0.55 * eased) * (1 + 0.3 * power)
    }

    func reset() {
        phase = .idle
        isEngaged = false
        hold.reset()
        sizes.removeAll()
        charge = 0
        cooldown = 0
        face = nil
        faceLost = 9
        sphereAt.reset()
        palms = nil
        level = HandFXLevel(rise: 0.14, fall: 0.18)
        rig.reset()
        motes.removeAll()
    }

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) {
        let dt = WorldKit.clamped(c.dt)
        time = c.time
        power = c.power
        // Final Flash is yellow in every form: a strong tint toward a cool colour would pass through green on the way.
        ki = SaiyanKi(Self.signature, palette: c.palette, tint: 0.2)
        if let f = c.face { face = f; faceLost = 0 } else { faceLost += dt }
        let usable = faceLost < 0.5 ? face : nil

        let p = pair(c.hands)
        var posed: Bool? = false
        if let p {
            sizes.add(p.size, at: time)
            if let f = usable { posed = p.unsure ? nil : isPosed(p, c.gestures, face: f) }
            if posed != false || phase != .idle {
                size = p.size
                palms = (p.a.palm, p.b.palm)
                // The sphere gathers in front of the palms, a little up toward the fingers.
                let up = (HandFXKit.up(of: p.a) + HandFXKit.up(of: p.b)) / 2
                sphereAt.update(SaiyanBeamHands.offset(p.centre, up, by: p.size * 0.3), dt: dt, snap: p.size * 3)
            }
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
            if posed == true, hold.held >= Self.sphereAfter || charge > 0.05 { charge = min(1, charge + dt / Self.chargeSeconds) }
            let reading = hold.missing <= hold.grace + Self.releaseWindow
            if charge >= Self.fireCharge, reading, pushed() {
                fire(c)
            } else if !reading {
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
                cooldown = 0.6
            }
        }

        level.approach(phase == .charging && (charge > 0 || hold.held >= Self.engageAfter) ? 1 : 0, dt: dt)
        rig.update(dt: dt, time: time, origin: phase == .firing ? sphereAt.point : nil, angle: nil, rect: c.rect)
        motes.update(dt: dt, rate: phase == .charging && charge > 0 ? 20 + 60 * charge : 0,
                     reach: Self.radius(charge: charge, size: size, power: power) * 2.4 + 40)
    }

    // MARK: Reading the hands

    private func pair(_ hands: [HandState]) -> Pair? {
        guard hands.count >= 2 else { return nil }
        let a = hands[0], b = hands[1]
        return Pair(a: a, b: b, centre: SaiyanBeamHands.midpoint(a.palm, b.palm), size: (a.size + b.size) / 2, unsure: a.unseenFor > 0 || b.unseenFor > 0)
    }

    private func isPosed(_ p: Pair, _ gestures: HandGestureRecognizer, face: FaceState) -> Bool {
        let apart = p.b.palm - p.a.palm
        guard HandState.distance(p.a.palm, p.b.palm) < Self.togetherWithin * max(p.a.size, p.b.size), abs(apart.dx) > abs(apart.dy) else { return false }
        for h in [p.a, p.b] {
            let local = SaiyanZones.palm(h, face)
            guard gestures.pose(of: h.id) == .openPalm, HandFXPose.openness(h) > Self.openAbove, SaiyanZones.fingerElevation(h) > Self.upAbove,
                  h[.middleMCP].y > h.wrist.y, local.y < Self.chestTop, local.y > Self.chestBottom, abs(local.x) < Self.besideWithin,
                  SaiyanBeamHands.speed(h) < Self.stillBelow else { return false }
        }
        return true
    }

    /// Both palms pushed at the camera: they have grown quickly.
    private func pushed() -> Bool {
        guard let last = sizes.last, let smallest = sizes.within(Self.pushWindow, of: time).min() else { return false }
        return last > smallest * Self.pushGrowth
    }

    private func fire(_ c: SaiyanMoveContext) {
        let from = sphereAt.point ?? CGPoint(x: c.rect.midX, y: c.rect.midY)
        let side = c.outward(from: from)
        let width = 110 * SaiyanBeamKit.handScale(size) * (1.5 + 1.3 * power) * (0.8 + 0.3 * charge)
        rig.style.kick = 0.6 + 0.3 * power
        rig.style.rumble = 0.16 + 0.14 * power
        rig.style.flash = 0.45 + 0.2 * power
        rig.fire(from: from, angle: side > 0 ? 0 : .pi, width: min(300, max(70, width)), ki: ki, pour: 1.2 + 0.8 * charge, crackle: 1 + Int(power * 4), rect: c.rect)
        phase = .firing
        fired += 1
        charge = 0
        sizes.removeAll()
    }

    // MARK: Drawing

    func washes() -> [SaiyanWash] {
        var out = rig.washes()
        let v = level.value
        guard v > 0.003, let c = sphereAt.point else { return out }
        let r = Self.radius(charge: charge, size: size, power: power)
        out.append(SaiyanWash(center: c, radius: r * 2.6 + size * 0.6, colour: ki.body, alpha: (0.18 + 0.17 * charge) * v))
        if let palms {
            for p in [palms.0, palms.1] { out.append(SaiyanWash(center: p, radius: size * 1.1, colour: ki.body, alpha: (0.14 + 0.14 * charge) * v)) }
        }
        return out
    }

    func drawSolids(in ctx: CGContext) {
        rig.drawSolids(in: ctx)
        guard level.value > 0.003, charge > 0.01, let c = sphereAt.point else { return }
        SaiyanBeamKit.drawOrbSolid(at: c, radius: sphereRadius * pulse, ki: ki, alpha: level.value * min(1, charge * 6), in: ctx)
    }

    func drawLight(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        let v = level.value
        if v > 0.003, let c = sphereAt.point {
            let r = sphereRadius * pulse
            // Both palms glow, brighter as the sphere fills, with arcs leaping from each palm to the sphere.
            if let palms {
                let glowing = v * (0.45 + 0.55 * charge)
                let arcs = CGMutablePath()
                for (i, p) in [palms.0, palms.1].enumerated() {
                    let flicker = 1 + 0.08 * sin(time * 23 + Double(i) * 2.1)
                    SaiyanBeamKit.glowDisc(at: p, radius: size * 0.5 * flicker, ki: ki, alpha: 0.8 * glowing, in: ctx)
                    if charge > 0.05 {
                        let beat = Int(time * 15)
                        arcs.addLines(between: HandFXKit.zigzag(from: p, to: c, seed: UInt64(truncatingIfNeeded: beat &* 31 &+ i &* 977), amplitude: size * 0.14,
                                                                segments: 8))
                    }
                }
                SaiyanBeamKit.bolts(arcs, colour: ki.lit(0.3), strength: glowing * 0.8, width: 0.8 + 0.4 * charge, in: ctx)
            }
            if charge > 0.01 {
                let shown = v * min(1, charge * 6)
                motes.draw(at: c, radius: r, colour: ki.lit(0.3), alpha: shown, in: ctx)
                SaiyanBeamKit.drawOrbLight(at: c, radius: r, ki: ki, alpha: shown, time: time, seed: 23, crackle: 1 + Int(charge * 4 + power * 3),
                                           full: charge >= 1 ? 1 : 0, in: ctx)
            }
        }
        rig.drawLight(in: ctx)
        ctx.restoreGState()
    }

    private var pulse: Double { 1 + (0.03 + 0.05 * charge) * sin(time * (8 + 6 * charge)) }
}
