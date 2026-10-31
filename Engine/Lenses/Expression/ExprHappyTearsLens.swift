import CoreGraphics
import CoreImage

/// Laugh your head off: cartoon tears squirt out of your eyes in arcs, fall under gravity and splash.
final class ExprHappyTearsLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    /// It takes a broad smile to start, and a fair bit less to carry on.
    static let startAt = 0.7, stopAt = 0.45

    private enum Kind { static let drop = 0, splash = 1, ring = 2 }

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var tears = ParticleSystem(capacity: 220)
    private var rng = SplitMix64(seed: 0x7EA25)
    private var crying = ExprLatch()
    private var wet = Ramp()
    private var owed = [0.0, 0.0]
    /// Where the drops land and splash, in pixels (a little below the shoulders). Set from the face each frame.
    private var floorY = -1000.0
    private var scale = 1.0
    private(set) var splashCount = 0

    var dropCount: Int { tears.particles.filter { $0.kind == Kind.drop }.count }
    var isCrying: Bool { crying.isOn }

    init() { tears.gravity = SIMD2(0, -1500) }

    func restart() {
        tears.removeAll()
        crying.reset()
        wet = Ramp()
        owed = [0, 0]
        splashCount = 0
    }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Laugh out loud")
        let dt = input.dt

        if let face = input.face {
            crying.update(face.smile, on: Self.startAt, off: Self.stopAt)
            scale = face.exprScale
            tears.gravity = SIMD2(0, -1500 * scale)
            floorY = face.eyeCenter.y - face.interocular * 2.3
            wet.move(toward: crying.isOn ? 1 : 0, dt: dt, rate: crying.isOn ? 3 : 1.5)
            if crying.isOn { emit(from: face, dt: dt) }
        } else {
            crying.reset()
            wet.move(toward: 0, dt: dt, rate: 4)
        }
        let floor = floorY
        var landed: [SIMD2<Double>] = []
        tears.step(dt) { p in
            guard p.kind == Kind.drop, p.position.y < floor, p.velocity.y < 0 else { return }
            p.age = p.life                                   // this one is done; it leaves a splash
            landed.append(SIMD2(p.position.x, floor))
        }
        for spot in landed { splash(at: spot) }
        if input.face == nil && tears.particles.isEmpty && wet.value < 0.01 { return input.composed }

        guard let layer = input.services.exprOverlay({ ctx in draw(ctx, face: input.face) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    private func emit(from face: FaceState, dt: Double) {
        let up = SIMD2(Double(face.up.dx), Double(face.up.dy)), across = face.acrossVector
        for (i, side) in [-1.0, 1.0].enumerated() {
            owed[i] += dt * (8 + 5 * face.smile)
            while owed[i] >= 1 {
                owed[i] -= 1
                let start = face.exprPoint(side * 0.6, -0.1).simd
                let outward = Double.random(in: 120...330, using: &rng) * scale, lift = Double.random(in: 150...430, using: &rng) * scale
                tears.emit(Particle(position: start, velocity: across * side * outward + up * lift,
                                    life: 3, size: Double.random(in: 15...26, using: &rng) * scale, hue: 0, kind: Kind.drop))
            }
        }
    }

    /// A tiny ring and a few droplets thrown back up.
    private func splash(at p: SIMD2<Double>) {
        splashCount += 1
        tears.emit(Particle(position: p, velocity: .zero, life: 0.18, size: 14 * scale, hue: 0, kind: Kind.ring))
        for _ in 0..<5 {
            let angle = Double.random(in: 0.5...(Double.pi - 0.5), using: &rng)
            let speed = Double.random(in: 180...340, using: &rng) * scale
            tears.emit(Particle(position: p, velocity: SIMD2(cos(angle), sin(angle)) * speed, life: Double.random(in: 0.22...0.38, using: &rng),
                                size: Double.random(in: 5...9, using: &rng) * scale, hue: 0, kind: Kind.splash))
        }
    }

    private func draw(_ ctx: CGContext, face: FaceState?) {
        // Wet streaks down the cheeks while you cry, strongest under the eye and fading out toward the jaw.
        if let face, wet.value > 0.01 {
            ctx.setLineCap(.butt)
            let steps = 8
            for side in [-1.0, 1.0] {
                for i in 0..<steps {
                    let a = Double(i) / Double(steps), b = Double(i + 1) / Double(steps)
                    let from = face.exprPoint(side * (0.52 + 0.06 * a), -0.2 - 0.8 * a), to = face.exprPoint(side * (0.52 + 0.06 * b), -0.2 - 0.8 * b)
                    let fade = (1 - a) * wet.value
                    ctx.setStrokeColor(exprColor((0.55, 0.82, 1.0), 0.3 * fade))
                    ctx.setLineWidth(face.interocular * 0.13)
                    ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
                    ctx.setStrokeColor(exprColor((0.93, 0.98, 1.0), 0.55 * fade))
                    ctx.setLineWidth(face.interocular * 0.04)
                    ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
                }
            }
        }
        for p in tears.particles {
            let at = CGPoint(x: p.position.x, y: p.position.y)
            switch p.kind {
            case Kind.drop:
                let heading = atan2(p.velocity.y, p.velocity.x)
                let stretch = min(1.5, 1 + hypot(p.velocity.x, p.velocity.y) / (1400 * max(scale, 0.3)))
                ctx.saveGState()
                ctx.translateBy(x: at.x, y: at.y)
                ctx.rotate(by: heading)
                ctx.scaleBy(x: stretch, y: 1)
                ctx.exprStamp(ExprSprites.tear(), at: .zero, height: p.size * 1.7)
                ctx.restoreGState()
            case Kind.ring:
                // The splat as the drop lands: a flattened blob that spreads and is gone in a blink.
                let t = p.progress
                let w = p.size * (0.8 + 0.9 * exprOutCubic(t))
                ctx.saveGState()
                ctx.translateBy(x: at.x, y: at.y)
                ctx.scaleBy(x: 1, y: 0.32 * (1 - 0.5 * t))
                ctx.exprStamp(ExprSprites.tear(), at: .zero, height: w * 1.6, rotation: .pi / 2, alpha: 1 - t)
                ctx.restoreGState()
            default:
                ctx.exprStamp(ExprSprites.tear(), at: at, height: p.size * 1.8, rotation: atan2(p.velocity.y, p.velocity.x), alpha: 1 - p.progress)
            }
        }
    }
}
