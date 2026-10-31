import CoreGraphics
import CoreImage

/// Hearts throb in your eyes, and when you smile a stream of little hearts floats up past your head.
final class ExprHeartEyesLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    /// Smile needed to start the stream, and (lower) to keep it going, so a flickering smile doesn't stutter it.
    static let startAt = 0.5, stopAt = 0.3

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var hearts = ParticleSystem(capacity: 90)
    private var rng = SplitMix64(seed: 0x4EA27)
    private var smiling = ExprLatch()
    private var owed = 0.0
    private var visibleFor = 0.0
    private var excitement = 0.0
    private var beatPhase = 0.0

    /// Little hearts in the air right now.
    var heartCount: Int { hearts.particles.count }
    var isStreaming: Bool { smiling.isOn }

    init() {
        hearts.gravity = .zero
        hearts.drag = 0.2
    }

    func restart() {
        hearts.removeAll()
        smiling.reset()
        owed = 0; visibleFor = 0; excitement = 0
    }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Smile for hearts")
        let dt = input.dt

        if let face = input.face {
            visibleFor += dt
            smiling.update(face.smile, on: Self.startAt, off: Self.stopAt)
            excitement = exprEase(excitement, toward: smiling.isOn ? 1 : 0, dt: dt, tau: 0.25)
            beatPhase += dt * (1.5 + 1.1 * excitement)
            if smiling.isOn { emit(from: face, dt: dt) }
        } else {
            smiling.reset()
            visibleFor = 0
            excitement = 0
        }
        hearts.step(dt)
        if input.face == nil && hearts.particles.isEmpty { return input.composed }

        guard let layer = input.services.exprOverlay({ ctx in draw(ctx, face: input.face) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    private func emit(from face: FaceState, dt: Double) {
        let scale = face.exprScale
        owed += dt * (5.5 + 7 * face.smile)
        while owed >= 1 {
            owed -= 1
            let side = Bool.random(using: &rng) ? 1.0 : -1.0
            let start = face.exprPoint(side * Double.random(in: 0.35...1.25, using: &rng), Double.random(in: 0.3...1.3, using: &rng))
            hearts.emit(Particle(position: start.simd,
                                 velocity: SIMD2(Double.random(in: -22...22, using: &rng), Double.random(in: 70...125, using: &rng)) * scale,
                                 life: Double.random(in: 1.2...1.9, using: &rng),
                                 size: Double.random(in: 18...36, using: &rng) * scale,
                                 hue: Double.random(in: 0..<(2 * .pi), using: &rng),
                                 kind: Int.random(in: 0..<3, using: &rng)))
        }
    }

    private func draw(_ ctx: CGContext, face: FaceState?) {
        for p in hearts.particles {
            let t = p.progress
            let grow = exprOutBack(min(1, p.age / 0.35), overshoot: 2.2)
            let fade = min(1, p.age / 0.12) * (1 - exprSmoothstep(0.6, 1, t))
            let sway = sin(p.age * 3.2 + p.hue) * p.size * 0.7
            let spot = CGPoint(x: p.position.x + sway, y: p.position.y)
            ctx.exprStamp(ExprSprites.heart(variant: p.kind), at: spot, height: p.size * (0.2 + 0.85 * grow),
                          rotation: sin(p.age * 2.4 + p.hue) * 0.35, alpha: fade)
        }
        guard let face else { return }

        // The hearts in the eyes: a quick double thump, a little faster when you smile.
        let pop = 1 - pow(1 - min(1, visibleFor / 0.3), 3)
        let thump = max(0, sin(beatPhase * 2 * .pi)) * 0.7 + max(0, sin(beatPhase * 2 * .pi * 2 - 1.4)) * 0.3
        let io = face.interocular
        // Rosy cheeks come up with the smile.
        if excitement > 0.02 {
            for side in [-1.0, 1.0] {
                let cheek = face.exprPoint(side * 0.78, -0.72)
                ctx.saveGState()
                ctx.translateBy(x: cheek.x, y: cheek.y)
                ctx.rotate(by: face.roll)
                ctx.scaleBy(x: 1, y: 0.6)
                ctx.glow(center: .zero, radius: io * 0.42, red: 1, green: 0.35, blue: 0.5, alpha: 0.42 * excitement * pop)
                ctx.restoreGState()
            }
        }
        let squash = 1 - 0.7 * face.blink
        for eye in [face.leftEye, face.rightEye] {
            let size = io * 0.74 * (0.9 + 0.2 * thump) * pop * (1 + 0.1 * excitement)
            ctx.glow(center: eye, radius: size * 0.8, red: 1, green: 0.35, blue: 0.5, alpha: 0.32 * pop)
            ctx.saveGState()
            ctx.translateBy(x: eye.x, y: eye.y)
            ctx.rotate(by: face.roll)
            ctx.scaleBy(x: 1, y: squash)
            ctx.exprStamp(ExprSprites.heart(variant: 0), at: .zero, height: size, alpha: 1)
            ctx.restoreGState()
        }
    }
}
