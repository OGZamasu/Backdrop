import CoreGraphics
import CoreImage

/// Stars twinkle in your eyes, and raising your eyebrows sets off a burst of sparkles.
final class ExprStarEyesLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    /// Brow raise needed to set off a burst, and (lower) to count as lowered again, so one raise is one burst.
    static let startAt = 0.55, stopAt = 0.35
    /// The fewest seconds between two bursts.
    static let cooldown = 0.45

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var sparkles = ParticleSystem(capacity: 160)
    private var rng = SplitMix64(seed: 0x57A25)
    private var raised = ExprLatch()
    private var sinceBurst = 10.0
    private var owed = 0.0
    private var visibleFor = 0.0
    private var glee = 0.0
    private(set) var burstCount = 0

    var sparkleCount: Int { sparkles.particles.count }
    var isRaised: Bool { raised.isOn }

    init() {
        sparkles.gravity = SIMD2(0, -40)
        sparkles.drag = 2.6
    }

    func restart() {
        sparkles.removeAll()
        raised.reset()
        sinceBurst = 10; owed = 0; visibleFor = 0; glee = 0; burstCount = 0
    }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Raise your eyebrows")
        let dt = input.dt
        sinceBurst += dt

        if let face = input.face {
            visibleFor += dt
            let was = raised.isOn
            raised.update(face.browRaise, on: Self.startAt, off: Self.stopAt)
            glee = exprEase(glee, toward: raised.isOn ? 1 : 0, dt: dt, tau: 0.12)
            if raised.isOn && !was && sinceBurst >= Self.cooldown { burst(from: face) }
            if raised.isOn { trickle(from: face, dt: dt) }
        } else {
            raised.reset()
            visibleFor = 0
            glee = 0
        }
        sparkles.step(dt)
        if input.face == nil && sparkles.particles.isEmpty { return input.composed }

        guard let layer = input.services.exprOverlay({ ctx in draw(ctx, face: input.face, time: input.time) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    private func burst(from face: FaceState) {
        sinceBurst = 0
        burstCount += 1
        let scale = face.exprScale
        for i in 0..<30 {
            let origin = i % 3 == 0 ? face.browCenter : (i % 3 == 1 ? face.leftEye : face.rightEye)
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let speed = Double.random(in: 200...520, using: &rng) * scale
            sparkles.emit(Particle(position: origin.simd, velocity: SIMD2(cos(angle), sin(angle)) * speed,
                                   life: Double.random(in: 0.7...1.3, using: &rng),
                                   size: Double.random(in: 14...34, using: &rng) * scale,
                                   hue: Double.random(in: 0..<(2 * .pi), using: &rng),
                                   kind: Int.random(in: 0..<4, using: &rng)))
        }
    }

    /// While the brows stay up, a few more keep drifting off.
    private func trickle(from face: FaceState, dt: Double) {
        owed += dt * 14
        let scale = face.exprScale
        while owed >= 1 {
            owed -= 1
            let side = Bool.random(using: &rng) ? 1.0 : -1.0
            let at = face.exprPoint(side * Double.random(in: 0.3...0.9, using: &rng), Double.random(in: -0.1...0.6, using: &rng))
            sparkles.emit(Particle(position: at.simd, velocity: SIMD2(Double.random(in: -40...40, using: &rng), Double.random(in: 10...90, using: &rng)) * scale,
                                   life: Double.random(in: 0.5...0.9, using: &rng),
                                   size: Double.random(in: 10...20, using: &rng) * scale,
                                   hue: Double.random(in: 0..<(2 * .pi), using: &rng),
                                   kind: Int.random(in: 0..<4, using: &rng)))
        }
    }

    private func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        for p in sparkles.particles {
            let t = p.progress
            let flicker = 0.6 + 0.4 * sin(p.age * 21 + p.hue)
            let shrink = (1 - exprSmoothstep(0.5, 1, t) * 0.7) * exprOutBack(min(1, p.age / 0.18))
            let at = CGPoint(x: p.position.x, y: p.position.y)
            let alpha = (1 - exprSmoothstep(0.55, 1, t)) * (0.6 + 0.4 * flicker)
            if p.kind == 3 {
                // Every fourth one is a little gold star that tumbles as it flies.
                ctx.exprStamp(ExprSprites.star(), at: at, height: p.size * 1.25 * shrink, rotation: p.age * 3 + p.hue, alpha: alpha)
            } else {
                ctx.exprStamp(ExprSprites.twinkle(variant: p.kind), at: at, height: p.size * 2.3 * shrink * (0.8 + 0.4 * flicker),
                              rotation: p.age * 1.5 + p.hue, alpha: alpha)
            }
        }
        guard let face else { return }

        let pop = 1 - pow(1 - min(1, visibleFor / 0.3), 3)
        let io = face.interocular
        for (i, eye) in [face.leftEye, face.rightEye].enumerated() {
            let phase = Double(i) * 1.9
            let twinkle = 0.5 + 0.5 * sin(time * 6.3 + phase)
            let size = io * 0.8 * (0.92 + 0.1 * twinkle) * (1 + 0.3 * glee) * pop
            let squash = 1 - 0.7 * face.blink
            // A tight warm halo that stays on the star, so it never smears gold over hair.
            ctx.setBlendMode(.plusLighter)
            ctx.glow(center: eye, radius: size * (0.62 + 0.08 * glee), red: 1, green: 0.86, blue: 0.45, alpha: 0.2 + 0.12 * glee)
            ctx.setBlendMode(.normal)
            ctx.saveGState()
            ctx.translateBy(x: eye.x, y: eye.y)
            ctx.rotate(by: face.roll + sin(time * 1.6 + phase) * 0.14)
            ctx.scaleBy(x: 1, y: squash)
            ctx.exprStamp(ExprSprites.star(), at: .zero, height: size)
            ctx.restoreGState()
            // A glint that comes and goes across the star.
            let glint = pow(max(0, sin(time * 3.4 + phase * 2)), 3)
            let glintAt = CGPoint(x: eye.x + io * 0.2, y: eye.y + io * 0.2)
            ctx.exprStamp(ExprSprites.twinkle(variant: 0), at: glintAt, height: io * 0.55 * glint * pop, rotation: time * 0.8, alpha: glint)
        }
    }
}
