import CoreGraphics
import Foundation
import simd

/// Solar Flare. Frame your eyes with both open hands, close together in front of your face, and hold a moment: light gathers in your
/// palms, then the picture goes blinding white and slowly comes back through a warm glare, with a star of rays and a lens flare
/// streaking out from your hands. It cannot go off twice in a row by accident: it waits four seconds and for you to drop the pose.
final class SolarFlareMove: SaiyanMove {
    let id = "solar-flare"
    let name = "Solar Flare"
    let hint = "Bring both open hands together in front of your face and hold."

    enum Phase: Equatable { case idle, posing, flare }

    /// Near white, a little warm.
    static let signature = SIMD3<Double>(1.0, 0.97, 0.9)
    static let warm = SIMD3<Double>(1.0, 0.86, 0.62)
    static let anamorphic = SIMD3<Double>(0.62, 0.8, 1.0)

    static let claimSeconds = 0.08
    static let holdSeconds = 0.35
    /// Both palms within this many palm lengths of each other.
    static let together = 1.8
    /// Each palm within this many eye spacings of the middle of the face.
    static let reach = 1.7
    static let calmSpeed = 2.5
    /// The white holds for a blink, then fades over `fadeSeconds`.
    static let whiteSeconds = 0.08
    static let fadeSeconds = 1.6
    static let cooldownSeconds = 4.0

    private(set) var phase = Phase.idle
    private(set) var flares = 0
    private var poseFor = 0.0
    private var brokenFor = 0.0
    private var phaseTime = 0.0
    private var cooldown = 0.0
    /// Set once the pose is let go after a flare, so holding it does not flash again and again.
    private var armed = true
    private var source = CGPoint.zero
    private var palmA = CGPoint.zero, palmB = CGPoint.zero
    private var handSize = 100.0
    private var trail = SaiyanHandTrail()
    private var colour = SolarFlareMove.signature
    private var power = 0.0
    private var time = 0.0
    private var rect = CGRect(x: 0, y: 0, width: 1280, height: 720)

    init() {}

    var isEngaged: Bool { phase == .posing || (phase == .flare && phaseTime < 0.9) }

    var hasLight: Bool { phase == .posing || phase == .flare }

    var status: LensStatus? {
        switch phase {
        case .posing: return LensStatus("Solar Flare", detail: "Hold your hands by your eyes")
        case .flare: return LensStatus("Solar Flare!")
        case .idle: return nil
        }
    }

    /// 0...1 how far through the hold the pose is.
    private var gathering: Double { phase == .posing ? SaiyanOrbKit.clamp01(poseFor / Self.holdSeconds) : 0 }

    /// How much of the flare is left: 1 at the burst, easing to 0 over the fade.
    private var envelope: Double {
        guard phase == .flare else { return 0 }
        let attack = SaiyanOrbKit.clamp01(phaseTime / 0.04)
        let u = SaiyanOrbKit.clamp01((phaseTime - Self.whiteSeconds) / Self.fadeSeconds)
        return attack * pow(1 - u, 1.6)
    }

    var screenEffect: SaiyanScreenEffect {
        var e = SaiyanScreenEffect()
        switch phase {
        case .posing:
            // The room brightens a touch as the light gathers: the wind-up before the burst.
            e.flash = 0.1 * pow(gathering, 2)
            e.flashTint = Self.warm
        case .flare:
            let t = phaseTime
            let u = SaiyanOrbKit.clamp01((t - Self.whiteSeconds) / Self.fadeSeconds)
            let attack = 0.1 + 0.9 * SaiyanOrbKit.clamp01(t / 0.03)
            e.flash = t < Self.whiteSeconds ? attack : pow(1 - u, 2.2)
            e.flashTint = SaiyanOrbKit.mix(SaiyanOrbKit.white, colour * Self.warm, SaiyanOrbKit.smooth(u * 1.6))
            e.shake = (0.25 + 0.1 * power) * exp(-t / 0.16) * (1 - SaiyanOrbKit.smooth((t - 0.4) / 0.3))
        case .idle:
            break
        }
        if e.flash < 0.002 { e.flash = 0 }
        return e
    }

    func reset() {
        phase = .idle
        poseFor = 0
        brokenFor = 0
        phaseTime = 0
        cooldown = 0
        armed = true
        trail.reset()
    }

    // MARK: Update

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) {
        let dt = WorldKit.clamped(c.dt)
        time = c.time
        rect = c.rect
        power = c.power
        colour = c.palette.tinting(Self.signature, amount: 0.3)
        trail.update(c.hands, time: c.time)
        cooldown = max(0, cooldown - dt)
        phaseTime += dt
        let pose = framedFace(c)
        if pose == nil, phase != .posing { armed = true }
        if let pose {
            palmA = pose.0.palm
            palmB = pose.1.palm
            source = SaiyanOrbKit.midpoint(palmA, palmB)
            handSize = max(pose.0.size, pose.1.size)
        }

        let calm = pose.map { trail.meanSpeed($0.0.id, over: 0.25) < Self.calmSpeed && trail.meanSpeed($0.1.id, over: 0.25) < Self.calmSpeed } ?? false

        switch phase {
        case .idle:
            if mayBegin, armed, cooldown <= 0, calm {
                poseFor += dt
                if poseFor >= Self.claimSeconds {
                    phase = .posing
                    phaseTime = 0
                }
            } else {
                poseFor = 0
            }
        case .posing:
            if calm {
                poseFor += dt
                brokenFor = 0
                if poseFor >= Self.holdSeconds { burst() }
            } else {
                brokenFor += dt
                // A blink of the tracker is forgiven; letting go is not.
                if brokenFor > 0.15 {
                    phase = .idle
                    poseFor = 0
                }
            }
        case .flare:
            if phaseTime >= Self.whiteSeconds + Self.fadeSeconds + 0.05 {
                phase = .idle
                phaseTime = 0
                poseFor = 0
            }
        }
    }

    private func burst() {
        phase = .flare
        phaseTime = 0
        flares += 1
        cooldown = Self.cooldownSeconds
        armed = false
    }

    /// Both open hands close together in front of the face: the eyes framed by the palms. One hand over the face is not it, nor two
    /// hands apart, nor anything without a face to frame.
    private func framedFace(_ c: SaiyanMoveContext) -> (HandState, HandState)? {
        guard let face = c.face, c.hands.count >= 2 else { return nil }
        let near = c.hands.filter { SaiyanZones.isNearFace($0, face, reach: Self.reach) && c.gestures.pose(of: $0.id) == .openPalm }
        guard near.count >= 2, SaiyanZones.together(near[0], near[1], within: Self.together) else { return nil }
        return (near[0], near[1])
    }

    // MARK: Drawing

    /// Ghosts of the flare strung along the line from the light through the middle of the picture: how far along, how big, what tint.
    private static let ghosts: [(Double, Double, SIMD3<Double>)] = [(0.55, 34, SIMD3(1.0, 0.72, 0.4)), (1.25, 70, SIMD3(0.45, 0.95, 0.85)),
                                                                   (1.6, 26, SIMD3(0.75, 0.55, 1.0)), (2.1, 96, SIMD3(0.55, 0.75, 1.0)),
                                                                   (-0.35, 44, SIMD3(1.0, 0.6, 0.55))]

    func washes() -> [SaiyanWash] {
        let scale = rect.width / 1280
        switch phase {
        case .posing:
            let g = gathering
            var out = [SaiyanWash(center: source, radius: handSize * (1.2 + 1.4 * g), colour: Self.warm, alpha: 0.35 * g)]
            for p in [palmA, palmB] { out.append(SaiyanWash(center: p, radius: handSize * (0.6 + 0.6 * g), colour: Self.warm, alpha: 0.5 * g)) }
            return out
        case .flare:
            let e = envelope
            let u = SaiyanOrbKit.clamp01((phaseTime - Self.whiteSeconds) / Self.fadeSeconds)
            let reachOut = SaiyanOrbKit.easeOutBack(phaseTime / 0.22, overshoot: 1.1)
            // The white-hot heart, the glare round it, and a warm wash over the whole picture.
            var out = [SaiyanWash(center: source, radius: 150 * scale * (1 + 0.4 * u), colour: SaiyanOrbKit.white, alpha: e),
                       SaiyanWash(center: source, radius: 380 * scale * (1 + 0.7 * u), colour: SaiyanOrbKit.lift(colour, 0.4), alpha: 0.95 * e),
                       SaiyanWash(center: source, radius: 950 * scale, colour: colour * Self.warm, alpha: 0.32 * e)]
            for p in [palmA, palmB] { out.append(SaiyanWash(center: p, radius: handSize * 0.9, colour: Self.warm, alpha: 0.5 * e)) }
            let axis = CGPoint(x: rect.midX, y: rect.midY) - source
            for (k, (f, size, tint)) in Self.ghosts.enumerated() {
                out.append(SaiyanWash(center: SaiyanOrbKit.point(source, axis, f), radius: size * scale * (0.9 + 0.2 * reachOut), colour: tint,
                                      alpha: 0.3 * e * (0.7 + 0.3 * WorldKit.hash(k))))
            }
            return out
        case .idle:
            return []
        }
    }

    func drawLight(in ctx: CGContext) {
        guard hasLight else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        if phase == .posing { drawGathering(ctx) } else { drawFlare(ctx) }
        ctx.restoreGState()
    }

    /// Light pooling in both palms and a small star kindling between them.
    private func drawGathering(_ ctx: CGContext) {
        let g = gathering
        let flicker = 0.9 + 0.1 * sin(time * 37)
        for p in [palmA, palmB] { SaiyanOrbKit.glow(ctx, at: p, radius: handSize * 0.28 * (0.5 + g), colour: SaiyanOrbKit.white, alpha: 0.7 * g * flicker) }
        SaiyanOrbKit.glint(ctx, at: source, radius: handSize * (0.3 + 0.6 * g * g), colour: colour, alpha: g)
        // The first rays peek out just before the burst.
        let peek = SaiyanOrbKit.smooth((g - 0.55) / 0.45)
        if peek > 0.004 {
            for k in 0..<4 {
                SaiyanOrbKit.ray(ctx, from: source, angle: Double(k) * .pi / 2, length: handSize * (1 + 3 * peek), width: 12, colour: colour, alpha: 0.6 * peek)
            }
        }
    }

    private func drawFlare(_ ctx: CGContext) {
        let e = envelope
        guard e > 0.004 else { return }
        let t = phaseTime
        let scale = rect.width / 1280
        let reachOut = SaiyanOrbKit.easeOutBack(t / 0.22, overshoot: 1.1)
        let length = rect.width * (0.62 + 0.3 * power) * (0.45 + 0.55 * reachOut)
        let cool = SaiyanOrbKit.mix(colour, Self.anamorphic, 0.4)

        // A star of rays: four long ones square to the picture, four short ones between, and a fringe of fine ones that shimmer.
        for k in 0..<4 {
            let a = Double(k) * .pi / 2
            SaiyanOrbKit.ray(ctx, from: source, angle: a, length: length * (k % 2 == 0 ? 1 : 0.8), width: 20 * scale, colour: colour, alpha: e)
            SaiyanOrbKit.ray(ctx, from: source, angle: a + .pi / 4, length: length * 0.36, width: 12 * scale, colour: SaiyanOrbKit.mix(colour, Self.warm, 0.4),
                             alpha: 0.85 * e)
        }
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi + 0.2 + 0.5 * WorldKit.hash(k &* 13 &+ flares)
            let shimmer = 0.6 + 0.4 * sin(time * (9 + Double(k)) + Double(k))
            SaiyanOrbKit.ray(ctx, from: source, angle: a, length: length * (0.12 + 0.2 * WorldKit.hash(k &* 7 &+ 3)), width: 6 * scale, colour: colour,
                             alpha: 0.6 * e * shimmer)
        }

        // The long streak a bright light leaves straight across a camera picture.
        let half = rect.width * (0.55 + 0.45 * reachOut)
        for side in [-1.0, 1.0] {
            SaiyanOrbKit.sliver(ctx, from: CGPoint(x: source.x + side * half, y: source.y), to: CGPoint(x: source.x - side * 30 * scale, y: source.y),
                                width: 10 * scale, colour: cool, alpha: 0.8 * e)
        }
        SaiyanOrbKit.glint(ctx, at: source, radius: 70 * scale * (0.8 + 0.4 * reachOut), colour: SaiyanOrbKit.white, alpha: e)

        // A ring of light thrown off by the burst.
        let u = SaiyanOrbKit.clamp01(t / 0.55)
        if u < 1 {
            SaiyanOrbKit.ring(ctx, center: source, radius: 40 * scale + SaiyanOrbKit.easeOut(u) * rect.width * 0.7, width: 4 * scale * (1 - 0.6 * u), colour: colour,
                              alpha: 0.8 * (1 - u) * (1 - u), thread: false)
        }
    }
}
