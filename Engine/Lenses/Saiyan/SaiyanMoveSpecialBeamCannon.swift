import CoreGraphics
import Foundation
import simd

/// Special Beam Cannon. Hold your index and middle fingers to your forehead for longer than a touch (a quick touch is Instant Transmission):
/// a golden spark gathers at the fingertips with violet sparks spiralling round it. Pull the fingers away and point out to the side, and a
/// thin, fast golden beam with a violet spiral winding round it drills across the picture to the edge.
final class SpecialBeamCannonMove: SaiyanMove {
    let id = "special-beam-cannon"
    let name = "Special Beam Cannon"
    let hint = "Hold two fingers to your forehead, then point out to the side."
    private(set) var isEngaged = false

    /// Nothing at all happens before this: a shorter touch belongs to Instant Transmission.
    static let limit = SaiyanZones.instantTransmissionLimit
    static let chargeSeconds = 1.4
    static let fireCharge = 0.2
    /// Pulled away: the fingertips at least this many eye spacings from the forehead (touching is under 0.8).
    static let awayAbove = 1.4
    /// After the fingers leave the forehead, this long to point.
    static let releaseWindow = 0.9
    /// Pointing out: the index finger straight (an extended finger reads 1, curled 0) and seen side on (0.84 across the picture, under a
    /// third of that pointed at the camera).
    static let indexOutAbove = 0.6
    static let aimLengthAbove = 0.45
    /// The beam's slope is kept within this many radians of level.
    static let slopeLimit = 0.6

    static let gold = SIMD3<Double>(1.0, 0.8, 0.3)
    static let violet = SIMD3<Double>(0.62, 0.3, 1.0)

    private enum Phase { case idle, charging, firing }

    private var phase = Phase.idle
    private var touch = SaiyanHold(grace: 0.25)
    private var tips = HandFXSteady(calm: 2.0, eager: 0.03)
    private var handID: Int?
    private var releasedFor = 0.0
    private(set) var charge = 0.0
    private var cooldown = 0.0
    private var face: FaceState?
    private var faceLost = 9.0
    private var size = 110.0
    private var sparkLevel = HandFXLevel(rise: 0.1, fall: 0.2)
    private var rig = SaiyanBeamRig(style: SaiyanBeamRig.Style(core: 0.17, rings: false, filaments: 0, wobble: 0.25, grow: 0.12, fade: 0.3,
                                                               kick: 0.3, rumble: 0.05, flash: 0.12, sparks: 260, impact: 2.6), seed: 0x5BC1)
    private var motes = SaiyanMotes(seed: 0x5BC2, capacity: 24)
    private var core = SaiyanKi(SpecialBeamCannonMove.gold, palette: SaiyanForm.base.palette)
    private var spiral = SaiyanKi(SpecialBeamCannonMove.violet, palette: SaiyanForm.base.palette)
    private var power = 0.0
    private var time = 0.0
    private(set) var fired = 0

    init() {}

    var hasLight: Bool { sparkLevel.value > 0.003 || rig.hasLight || !motes.isEmpty }
    var isFiring: Bool { rig.isPouring }
    var beam: SaiyanBeamLook? { rig.look }

    var status: LensStatus? {
        guard isEngaged else { return nil }
        if phase == .firing { return LensStatus("Special Beam Cannon!") }
        if charge >= 1 { return LensStatus("Special Beam Cannon ready", detail: "Point your fingers out to the side") }
        return LensStatus("Charging Special Beam Cannon...", detail: charge >= Self.fireCharge ? "Point your fingers out to the side" : "Keep holding")
    }

    var screenEffect: SaiyanScreenEffect {
        var e = SaiyanScreenEffect()
        e.shake = rig.shake
        e.flash = rig.flash
        e.flashTint = rig.flashTint
        return e
    }

    func reset() {
        phase = .idle
        isEngaged = false
        touch.reset()
        tips.reset()
        handID = nil
        releasedFor = 0
        charge = 0
        cooldown = 0
        face = nil
        faceLost = 9
        sparkLevel = HandFXLevel(rise: 0.1, fall: 0.2)
        rig.reset()
        motes.removeAll()
    }

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) {
        let dt = WorldKit.clamped(c.dt)
        time = c.time
        power = c.power
        core = SaiyanKi(Self.gold, palette: c.palette, tint: 0.45)
        spiral = SaiyanKi(Self.violet, palette: c.palette, tint: 0.35)
        if let f = c.face { face = f; faceLost = 0 } else { faceLost += dt }
        let usable = faceLost < 0.5 ? face : nil

        var touching: Bool? = false
        if let f = usable {
            if let h = c.hands.first(where: { SaiyanZones.fingersAtForehead($0, f) }) {
                touching = h.unseenFor > 0 ? nil : true
                handID = h.id
                size = h.size
                tips.update(SaiyanBeamHands.twoTips(h), dt: dt, snap: h.size * 2)
            } else if touch.isHeld, let id = handID, let h = c.hands.first(where: { $0.id == id }), h.unseenFor > 0 {
                // The hand at the forehead is being carried through a blur: hold the touch as it is.
                touching = nil
            }
        }
        touch.update(touching, dt: dt)
        cooldown = max(0, cooldown - dt)

        switch phase {
        case .idle:
            if mayBegin, cooldown <= 0, touch.isHeld, touch.held > Self.limit {
                phase = .charging
                isEngaged = true
                charge = 0
                releasedFor = 0
            }
        case .charging:
            if touch.isHeld {
                releasedFor = 0
                if touching == true { charge = min(1, charge + dt / Self.chargeSeconds) }
            } else {
                releasedFor += dt
                if releasedFor <= Self.releaseWindow, charge >= Self.fireCharge, let f = usable, let h = pointingAway(c.hands, face: f) {
                    fire(c, hand: h)
                } else if releasedFor > Self.releaseWindow {
                    // Lowered without pointing: the spark fizzles out.
                    charge = max(0, charge - dt / 0.35)
                    if charge <= 0 {
                        phase = .idle
                        isEngaged = false
                        cooldown = 0.3
                    }
                }
            }
        case .firing:
            if !rig.isPouring {
                phase = .idle
                isEngaged = false
                cooldown = 0.6
            }
        }

        sparkLevel.approach(phase == .charging && charge > 0 ? 1 : 0, dt: dt)
        // While it fires, the beam leaves from the fingertip, wherever the hand goes.
        var origin: CGPoint?
        if phase == .firing, let id = handID, let h = c.hands.first(where: { $0.id == id }), h.unseenFor <= 0 { origin = h.indexTip }
        rig.update(dt: dt, time: time, origin: origin, angle: nil, rect: c.rect)
        motes.update(dt: dt, rate: phase == .charging && charge > 0 ? 14 + 26 * charge : 0, reach: sparkSize * 2.6 + 26)
    }

    /// The hand that has pulled away from the forehead and is pointing out, if there is one.
    private func pointingAway(_ hands: [HandState], face: FaceState) -> HandState? {
        let last = tips.point ?? face.forehead
        let candidates = hands.filter { $0.unseenFor <= 0 }
        let hand = candidates.first { $0.id == handID } ?? candidates.min { HandState.distance($0.indexTip, last) < HandState.distance($1.indexTip, last) }
        guard let h = hand, HandFXPose.extended(.index, in: h) > Self.indexOutAbove, h.aimLength > Self.aimLengthAbove,
              HandState.distance(h.indexTip, face.forehead) / max(face.interocular, 1) > Self.awayAbove else { return nil }
        return h
    }

    private func fire(_ c: SaiyanMoveContext, hand h: HandState) {
        let aim = SIMD2(Double(h.aim.dx), Double(h.aim.dy))
        let side = abs(aim.x) > 0.25 ? (aim.x > 0 ? 1.0 : -1.0) : c.outward(from: h.indexTip)
        let angle = SaiyanBeamHands.sideways(atan2(aim.y, aim.x), side: side, limit: Self.slopeLimit)
        let width = (12 + 13 * power) * SaiyanBeamKit.handScale(h.size) * (0.85 + 0.3 * charge)
        rig.style.kick = 0.25 + 0.2 * power
        rig.style.flash = 0.1 + 0.08 * power
        handID = h.id
        rig.fire(from: h.indexTip, angle: angle, width: width, ki: core, pour: 1.0 + 0.5 * charge, crackle: Int(power * 2.5), rect: c.rect)
        phase = .firing
        fired += 1
        charge = 0
    }

    /// The spark's size: from a pinprick to about a third of a palm.
    private var sparkSize: Double {
        let eased = charge * charge * (3 - 2 * charge)
        return (7 + 26 * eased) * SaiyanBeamKit.handScale(size) * (1 + 0.3 * power)
    }

    // MARK: Drawing

    func washes() -> [SaiyanWash] {
        var out = rig.washes()
        if let look = rig.look {
            // The spiral tints the light it throws on the room.
            for var w in SaiyanBeamKit.beamWashes(look, strength: 0.12) {
                w.colour = spiral.body
                w.radius *= 2.2
                out.append(w)
            }
        }
        if sparkLevel.value > 0.003, let p = tips.point {
            out.append(SaiyanWash(center: p, radius: sparkSize * 3.6 + 20, colour: core.body, alpha: 0.4 * sparkLevel.value))
            out.append(SaiyanWash(center: p, radius: sparkSize * 6 + 30, colour: spiral.body, alpha: 0.22 * sparkLevel.value))
        }
        return out
    }

    func drawLight(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        if let look = rig.look {
            let w = look.width
            let radius = w * 1.9 + 5, pitch = w * 4 + 34, spin = time * 26
            SaiyanBeamKit.drawSpiral(look, radius: radius, pitch: pitch, spin: spin, colour: spiral.body, lineWidth: max(2, w * 0.3), front: false, in: ctx)
            rig.drawLight(in: ctx)
            SaiyanBeamKit.drawSpiral(look, radius: radius, pitch: pitch, spin: spin, colour: spiral.lit(0.15), lineWidth: max(2, w * 0.3), front: true, in: ctx)
        } else {
            rig.drawLight(in: ctx)
        }
        if sparkLevel.value > 0.003, let p = tips.point { drawSpark(at: p, in: ctx) }
        ctx.restoreGState()
    }

    /// The gathering spark: a hot golden point with violet sparks circling it on a tilted ring, crackling, and a star once it is full.
    private func drawSpark(at p: CGPoint, in ctx: CGContext) {
        let v = sparkLevel.value
        let s = sparkSize * (1 + 0.08 * sin(time * 19))
        motes.draw(at: p, radius: s * 0.6, colour: spiral.lit(0.2), alpha: v, in: ctx)
        SaiyanBeamKit.glowDisc(at: p, radius: s * 1.3, ki: core, alpha: v, in: ctx)
        // A violet ring seen at a slant, turning, with three sparks racing round it, each trailing a streak along its path: the spiral
        // that the beam will drill with.
        let ring = s * 1.5 + 8, tilt = 0.4 + 0.1 * sin(time * 1.3)
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: CGFloat(0.35 * sin(time * 0.9)))
        SaiyanBeamKit.ring(at: .zero, rx: ring, ry: ring * tilt, thickness: max(1.5, s * 0.08), colour: spiral.lit(0.2), alpha: 0.55 * v, in: ctx)
        let trails = CGMutablePath(), heads = CGMutablePath()
        for k in 0..<3 {
            let a = time * 9 + Double(k) * 2 * .pi / 3
            let at = CGPoint(x: cos(a) * ring, y: sin(a) * ring * tilt)
            let heading = atan2(cos(a) * ring * tilt, -sin(a) * ring)
            // Smaller as they pass behind the spark.
            let near = 0.6 + 0.4 * sin(a)
            SaiyanBeamKit.teardrop(trails, head: at, angle: heading, length: ring * 1.2 * near, width: max(4, s * 0.38) * near)
            let h = max(2.5, s * 0.17) * near
            heads.addEllipse(in: CGRect(x: at.x - h, y: at.y - h, width: h * 2, height: h * 2))
        }
        SaiyanBeamKit.fill(trails, colour: spiral.lit(0.25), alpha: 0.85 * v, in: ctx)
        SaiyanBeamKit.fill(heads, colour: spiral.lit(0.75), alpha: v, in: ctx)
        ctx.restoreGState()
        SaiyanBeamKit.crackle(around: p, radius: s * 0.8, count: 1 + Int(charge * 3 + power * 2), reach: 1.6...3.0, time: time, seed: 41,
                              colour: spiral.lit(0.3), strength: v * 0.85, in: ctx)
        if charge >= 1 {
            SaiyanBeamKit.spikes(at: p, count: 6, rotation: time * 1.2, length: s * 3, base: s * 0.35, colour: core.lit(0.5), alpha: 0.75 * v,
                                 time: time, seed: 41, in: ctx)
        }
    }
}
