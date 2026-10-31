import CoreGraphics
import CoreImage

/// Lose your temper: shout (open wide) and the anger builds. Your face flushes red, an anger mark throbs on your forehead
/// and steam blasts out of both sides of your head in puffs, harder the longer you keep it up.
final class ExprFumingLens: ExprOverlayLens {
    static let startAt = 0.45, stopAt = 0.25

    private var shouting = ExprLatch()
    /// How angry, 0 to 1: it builds while you shout and cools off slowly after.
    private var rage = Ramp()
    private var mark = ExprSpring()
    private var steam = ParticleSystem(capacity: 160)
    private var rng = SplitMix64(seed: 0xF00F)
    private var owed = 0.0

    var isShouting: Bool { shouting.isOn }
    var anger: Double { rage.value }
    var steamCount: Int { steam.particles.count }

    override var hintText: String { "Open wide and shout" }
    override var isFinished: Bool { presence.face == nil && steam.particles.isEmpty }

    override init() {
        super.init()
        steam.gravity = SIMD2(0, 160)
        steam.drag = 2.2
    }

    override func restart() {
        super.restart()
        shouting.reset(); rage = Ramp(); mark.reset(); steam.removeAll(); owed = 0
    }

    /// A puff of steam: a soft white ball, lit from the top left, that thins out at its edge.
    static let puff: CGImage? = ExprSprites.make("expr-steam-puff", side: 128) { ctx in
        if let g = ExprShapes.gradient([((1, 1, 1), 0), ((0.96, 0.96, 1.0), 0.42), ((0.7, 0.72, 0.84), 0.78), ((0.62, 0.64, 0.78), 1)], alphas: [0.98, 0.92, 0.55, 0]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: -0.25, y: 0.25), startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        }
    }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        if let face {
            shouting.update(face.mouthOpen, on: Self.startAt, off: Self.stopAt)
            rage.move(toward: shouting.isOn ? 1 : 0, dt: dt, rate: shouting.isOn ? 1.1 : 0.45)
            if rage.value > 0.15 { vent(face, dt: dt, time: time) }
        } else {
            shouting.reset()
            rage.move(toward: 0, dt: dt, rate: 2)
        }
        mark.step(toward: rage.value > 0.3 ? 1 : 0, dt: dt, frequency: 3.5, damping: 0.4)
        steam.step(dt)
    }

    /// Steam comes in pulses, like a kettle about to boil over: more, faster and bigger as the anger builds.
    private func vent(_ face: FaceState, dt: Double, time: Double) {
        let pressure = rage.value
        let pulse = 0.5 + 0.5 * sin(time * (6 + 6 * pressure))
        owed += dt * 46 * pressure * (0.35 + 0.65 * pulse)
        let scale = face.exprScale
        while owed >= 1 {
            owed -= 1
            let side = Bool.random(using: &rng) ? 1.0 : -1.0
            let ear = face.exprPoint(side * 1.12, -0.28)
            let out = face.acrossVector * side
            let up = SIMD2(Double(face.up.dx), Double(face.up.dy))
            let speed = Double.random(in: 260...460, using: &rng) * scale * (0.6 + 0.6 * pressure)
            steam.emit(Particle(position: ear.simd, velocity: out * speed + up * Double.random(in: 40...160, using: &rng) * scale,
                                life: Double.random(in: 0.7...1.2, using: &rng), size: face.interocular * Double.random(in: 0.16...0.26, using: &rng),
                                hue: Double.random(in: 0..<6.28, using: &rng)))
        }
    }

    override func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        let r = rage.value
        if let face {
            let fade = presence.alpha
            ctx.saveGState()
            ctx.setAlpha(CGFloat(fade))
            // At full boil the whole head trembles.
            let tremble = r > 0.7 ? sin(time * 43) * 0.018 * (r - 0.7) / 0.3 : 0
            ctx.inFaceSpace(face) {
                ctx.translateBy(x: tremble, y: 0)
                drawFlush(ctx, amount: r)
                if mark.value > 0.01 { drawMark(ctx, size: mark.value, time: time) }
            }
            ctx.restoreGState()
        }
        guard let puff = Self.puff else { return }
        for p in steam.particles {
            let t = p.progress
            let grow = 0.45 + 1.6 * exprOutCubic(t)
            let alpha = min(1, p.age / 0.08) * (1 - exprSmoothstep(0.35, 1, t)) * 0.9
            ctx.exprStamp(puff, at: CGPoint(x: p.position.x, y: p.position.y), height: p.size * 2 * grow, rotation: p.hue, alpha: alpha)
        }
    }

    /// Red rising up the face from the chin, strongest on the cheeks.
    private func drawFlush(_ ctx: CGContext, amount: Double) {
        guard amount > 0.01 else { return }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: -0.5)
        ctx.scaleBy(x: 1.15, y: 1.45)
        let stops: [(Double, Double)] = [(0, 0.42), (0.55, 0.36), (0.85, 0.12), (1, 0)]
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { exprColor((0.95, 0.12, 0.12), $0.1 * amount) } as CFArray,
                              locations: stops.map { CGFloat($0.0) }) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: 0, y: -0.25), startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        }
        ctx.restoreGState()
    }

    /// The four-bracket anger mark, red with a white edge so it shows on hair and skin alike, throbbing.
    private func drawMark(_ ctx: CGContext, size: Double, time: Double) {
        let throb = 1 + 0.14 * max(0, sin(time * 9))
        ctx.saveGState()
        ctx.translateBy(x: 0.6, y: 1.0)
        ctx.rotate(by: -0.2)
        ctx.scaleBy(x: 0.2 * size * throb, y: 0.2 * size * throb)
        let bracket = CGMutablePath()
        for q in 0..<4 {
            let a = Double(q) * .pi / 2 + .pi / 4
            let c = CGPoint(x: cos(a) * 0.95, y: sin(a) * 0.95)
            // Each bracket bows toward the middle.
            let from = CGPoint(x: c.x + cos(a + .pi / 2) * 0.55, y: c.y + sin(a + .pi / 2) * 0.55)
            let to = CGPoint(x: c.x + cos(a - .pi / 2) * 0.55, y: c.y + sin(a - .pi / 2) * 0.55)
            bracket.move(to: from)
            bracket.addQuadCurve(to: to, control: CGPoint(x: c.x * 0.35, y: c.y * 0.35))
        }
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.setStrokeColor(exprColor((1, 1, 1), 0.95)); ctx.setLineWidth(0.62)
        ctx.addPath(bracket); ctx.strokePath()
        ctx.setStrokeColor(exprColor((0.86, 0.08, 0.16))); ctx.setLineWidth(0.36)
        ctx.addPath(bracket); ctx.strokePath()
        ctx.restoreGState()
    }
}
