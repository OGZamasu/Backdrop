import CoreGraphics
import Foundation
import simd

/// Finger Beam. Point one finger out to the side and hold it still: a spark builds at the fingertip, then a thin, piercing magenta beam with
/// a white core shoots along the finger to the edge of the picture. It lasts while you keep pointing, up to two seconds.
final class FingerBeamMove: SaiyanMove {
    let id = "finger-beam"
    let name = "Finger Beam"
    let hint = "Point one finger out to the side and hold it still."
    private(set) var isEngaged = false

    // Thresholds, measured on `HandFixtures` and Vision's readings in `HandFixtures.gallery` (see `SaiyanBeamMoveTests`).

    /// Seconds pointing still before the spark starts, and before it fires.
    static let engageAfter = 0.25
    static let fireAfter = 0.6
    /// Held still: the palm slower than this many palm lengths a second, the fingertip slower than `tipStillBelow`, and the aim steady to
    /// within `steadyWithin` radians over the last quarter second. Pointing while talking moves at 2 to 5.
    static let stillBelow = 1.0
    static let tipStillBelow = 1.6
    static let steadyWithin = 0.2
    /// Pointing out to the side, not up: the finger within this many degrees of level (a raised "one moment" finger reads 80 or more).
    static let sidewaysWithin = 50.0
    /// Seen side on, not pointed at the camera: the finger reads 0.84 palms across the picture, under 0.5 pointed down the lens.
    static let aimLengthAbove = 0.5
    /// The fingertip clear of the face: a finger at the chin or the temple is thinking, not aiming.
    static let faceClear = 1.3
    /// The longest a beam lasts, and the slope it is held within.
    static let longest = 2.0
    static let slopeLimit = 0.7

    static let signature = SIMD3<Double>(0.96, 0.3, 0.88)

    private enum Phase { case idle, aiming, firing, spent }

    private var phase = Phase.idle
    private var hold = SaiyanHold(grace: 0.25)
    /// While it fires: whether the finger is still pointing, with a little patience.
    private var keep = SaiyanHold(grace: 0.25)
    private var aims = SaiyanTrail<Double>(span: 0.4)
    private var tip = HandFXSteady(calm: 2.4, eager: 0.03)
    private var angle = 0.0
    private var handID: Int?
    private var size = 110.0
    private var spent = 0.0
    private var face: FaceState?
    private var faceLost = 9.0
    private var sparkLevel = HandFXLevel(rise: 0.08, fall: 0.14)
    private var rig = SaiyanBeamRig(style: SaiyanBeamRig.Style(core: 0.2, rings: false, filaments: 1, wobble: 0.5, grow: 0.08,
                                                               fade: 0.25, kick: 0.18, rumble: 0.04, flash: 0.06, sparks: 320, impact: 2.2), seed: 0xF1B3)
    private var ki = SaiyanKi(FingerBeamMove.signature, palette: SaiyanForm.base.palette)
    private var power = 0.0
    private var time = 0.0
    private(set) var fired = 0

    init() {}

    var hasLight: Bool { sparkLevel.value > 0.003 || rig.hasLight }
    var isFiring: Bool { rig.isPouring }
    var beam: SaiyanBeamLook? { rig.look }

    var status: LensStatus? {
        switch phase {
        case .aiming: return LensStatus("Hold still...", detail: "Keep pointing to fire")
        case .firing: return LensStatus("Finger Beam!", detail: "Lower your hand to stop")
        default: return nil
        }
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
        hold.reset()
        keep.reset()
        aims.removeAll()
        tip.reset()
        handID = nil
        spent = 0
        face = nil
        faceLost = 9
        sparkLevel = HandFXLevel(rise: 0.08, fall: 0.14)
        rig.reset()
    }

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) {
        let dt = WorldKit.clamped(c.dt)
        time = c.time
        power = c.power
        ki = SaiyanKi(Self.signature, palette: c.palette, tint: 0.5)
        if let f = c.face { face = f; faceLost = 0 } else { faceLost += dt }
        let usable = faceLost < 0.5 ? face : nil

        let pointing = c.hands.filter { c.gestures.pose(of: $0.id).isPointing }
        let hand = pointing.first { $0.id == handID } ?? (pointing.count == 1 ? pointing[0] : nil)
        var posed: Bool? = false
        if let h = hand {
            if h.unseenFor > 0 {
                posed = nil
            } else {
                aims.add(atan2(Double(h.aim.dy), Double(h.aim.dx)), at: time)
                if let f = usable { posed = isAiming(h, face: f) }
            }
        } else {
            aims.removeAll()
        }
        hold.update(posed, dt: dt)
        // Firing, the finger only has to keep pointing out, not keep still: the beam sweeps with it.
        let loose: Bool? = hand.map { $0.unseenFor > 0 ? nil : $0.aimLength > Self.aimLengthAbove * 0.8 && HandFXPose.extended(.index, in: $0) > 0.5 } ?? false
        keep.update(loose, dt: dt)
        if let h = hand, h.unseenFor <= 0 {
            tip.update(h.indexTip, dt: dt, snap: h.size * 2)
            size = h.size
            if phase != .firing || keep.isHeld { aim(h, c, dt: dt) }
        }

        switch phase {
        case .idle:
            if !mayBegin {
                // Another move has the hands: a point held through it is not a fresh one, so it must drop first.
                if keep.isHeld { phase = .spent; spent = 0 }
            } else if hold.isHeld, hold.held >= Self.engageAfter, let h = hand {
                phase = .aiming
                isEngaged = true
                handID = h.id
            }
        case .aiming:
            if !hold.isHeld {
                phase = .idle
                isEngaged = false
                handID = nil
            } else if hold.held >= Self.fireAfter {
                fire(c)
            }
        case .firing:
            if !keep.isHeld || (rig.shot?.age ?? 0) > Self.longest { rig.release() }
            if !rig.isPouring {
                phase = .spent
                isEngaged = false
                spent = 0
            }
        case .spent:
            // Once is enough: the finger has to stop pointing before it can fire again.
            spent += dt
            if spent > 0.5, !keep.isHeld {
                phase = .idle
                handID = nil
            }
        }

        sparkLevel.approach(phase == .aiming ? 1 : 0, dt: dt)
        rig.update(dt: dt, time: time, origin: phase == .firing ? tip.point : nil, angle: phase == .firing ? angle : nil, rect: c.rect)
    }

    private func isAiming(_ h: HandState, face: FaceState) -> Bool {
        let classified = HandGesture.Pose.classify(h)
        guard classified.isPointing, h.aimLength > Self.aimLengthAbove,
              atan2(abs(Double(h.aim.dy)), abs(Double(h.aim.dx))) * 180 / .pi < Self.sidewaysWithin,
              SaiyanBeamHands.speed(h) < Self.stillBelow, hypot(Double(h.tipVelocity.dx), Double(h.tipVelocity.dy)) / h.size < Self.tipStillBelow else { return false }
        let recent = aims.within(0.25, of: time)
        if let first = recent.first, recent.contains(where: { abs(atan2(sin($0 - first), cos($0 - first))) > Self.steadyWithin }) { return false }
        let middle = SaiyanBeamHands.midpoint(face.eyeCenter, face.mouth)
        return HandState.distance(h.indexTip, middle) / max(face.interocular, 1) > Self.faceClear
    }

    /// Follows the finger's aim, kept out to the side.
    private func aim(_ h: HandState, _ c: SaiyanMoveContext, dt: Double) {
        let raw = atan2(Double(h.aim.dy), Double(h.aim.dx))
        let side = abs(h.aim.dx) > 0.2 ? (h.aim.dx > 0 ? 1.0 : -1.0) : c.outward(from: h.indexTip)
        let target = SaiyanBeamHands.sideways(raw, side: side, limit: Self.slopeLimit)
        let delta = atan2(sin(target - angle), cos(target - angle))
        angle += abs(delta) > 1.2 ? delta : delta * min(1, dt / 0.06)
    }

    private func fire(_ c: SaiyanMoveContext) {
        let from = tip.point ?? CGPoint(x: c.rect.midX, y: c.rect.midY)
        let width = (15 + 16 * power) * SaiyanBeamKit.handScale(size)
        rig.style.kick = 0.16 + 0.12 * power
        rig.fire(from: from, angle: angle, width: width, ki: ki, pour: .infinity, crackle: Int(power * 2.5), rect: c.rect)
        phase = .firing
        fired += 1
        keep.reset()
        keep.update(true, dt: 0)
    }

    // MARK: Drawing

    func washes() -> [SaiyanWash] {
        var out = rig.washes()
        if sparkLevel.value > 0.003, let p = tip.point {
            out.append(SaiyanWash(center: p, radius: sparkSize * 4 + 16, colour: ki.body, alpha: 0.45 * sparkLevel.value))
        }
        return out
    }

    func drawLight(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        rig.drawLight(in: ctx)
        if sparkLevel.value > 0.003, let p = tip.point {
            let v = sparkLevel.value, s = sparkSize * (1 + 0.1 * sin(time * 27))
            SaiyanBeamKit.glowDisc(at: p, radius: s * 2, ki: ki, alpha: v, in: ctx)
            SaiyanBeamKit.spikes(at: p, count: 6, rotation: angle + time * 2, length: s * 2.6, base: s * 0.4, axis: angle, bias: 0.5,
                                 colour: ki.lit(0.45), alpha: 0.8 * v, time: time, seed: 53, in: ctx)
            // A thin line of light already reaching out along the finger, the beam about to come.
            let reach = s * 4 * v
            let ahead = CGPoint(x: p.x + cos(angle) * reach, y: p.y + sin(angle) * reach)
            let needle = CGMutablePath()
            SaiyanBeamKit.teardrop(needle, head: ahead, angle: angle, length: reach, width: max(2.5, s * 0.4))
            SaiyanBeamKit.fill(needle, colour: ki.lit(0.5), alpha: 0.8 * v, in: ctx)
            SaiyanBeamKit.crackle(around: p, radius: s * 0.7, count: 1 + Int(power * 2), reach: 1.5...2.6, time: time, seed: 53, colour: ki.lit(0.3),
                                  strength: v * 0.7, in: ctx)
        }
        ctx.restoreGState()
    }

    /// The spark grows as the hold goes on.
    private var sparkSize: Double {
        let k = WorldKit.smoothstep(Self.engageAfter, Self.fireAfter, hold.held)
        return (4 + 12 * k) * SaiyanBeamKit.handScale(size) * (1 + 0.3 * power)
    }
}
