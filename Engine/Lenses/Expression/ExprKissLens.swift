import CoreGraphics
import CoreImage

/// Blow kisses: pucker your lips and lipstick kiss marks fly out of your mouth, spin toward the camera and land on the
/// glass around you, then fade. Hold the pucker and they keep coming.
final class ExprKissLens: ExprOverlayLens {
    /// A pucker is a mouth this much narrower than your mouth at rest, and it ends once the mouth is back to this.
    static let puckerAt = 0.8, releaseAt = 0.88
    /// Seconds between kisses while you hold a pucker.
    static let repeatEvery = 0.55
    static let flightTime = 0.5, stayTime = 2.2, fadeTime = 0.45

    /// One kiss in flight or stuck to the glass, in pixels.
    struct Mark {
        var from: CGPoint
        var to: CGPoint
        var age = 0.0
        var turn: Double
        var size: Double
        var arc: Double
    }

    private var puckered = ExprLatch()
    /// Mouth width over eye spacing at rest, learned as you go. Starts at a typical face's.
    private var restWidth = 0.84
    private var sinceKiss = 10.0
    /// Seconds until the next little heart drifts off your lips while you aren't kissing, to show the lens is on.
    private var idleHeart = 0.8
    private(set) var marks: [Mark] = []
    private var hearts = ParticleSystem(capacity: 30)
    private var rng = SplitMix64(seed: 0x1C155)
    private(set) var kissCount = 0

    var isPuckered: Bool { puckered.isOn }

    override var hintText: String { "Pucker up and blow a kiss" }
    override var isFinished: Bool { presence.face == nil && marks.isEmpty && hearts.particles.isEmpty }

    override init() {
        super.init()
        hearts.gravity = SIMD2(0, 60)
        hearts.drag = 1.2
    }

    override func restart() {
        super.restart()
        puckered.reset(); restWidth = 0.84; sinceKiss = 10; idleHeart = 0.8; marks = []; hearts.removeAll(); kissCount = 0
    }

    /// How narrow the mouth is next to its usual width: 1 at rest, lower in a pucker.
    func narrowness(_ face: FaceState) -> Double {
        (face.mouthWidth / max(face.interocular, 1)) / restWidth
    }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        sinceKiss += dt
        if let face {
            let ratio = face.mouthWidth / max(face.interocular, 1)
            // The resting width follows wider mouths quickly and narrower ones only slowly, and never while puckered or
            // smiling, so a held pucker never becomes the new normal.
            if !puckered.isOn && face.smile < 0.3 {
                restWidth += (ratio - restWidth) * min(1, dt / (ratio > restWidth ? 0.8 : 8))
            }
            let was = puckered.isOn
            // A latch on "how much of the usual width is left", flipped so that narrower is more.
            puckered.update(1 - narrowness(face), on: 1 - Self.puckerAt, off: 1 - Self.releaseAt)
            if puckered.isOn && face.smile < 0.4 && (!was || sinceKiss >= Self.repeatEvery) && sinceKiss >= 0.3 { launch(face) }
            idleHeart -= dt
            if !puckered.isOn && idleHeart <= 0 {
                idleHeart = 1.7
                let side = Bool.random(using: &rng) ? 1.0 : -1.0
                let corner = face.exprPoint(side * 0.45, -0.95)
                let drift = face.acrossVector * side * 70 + SIMD2(Double(face.up.dx), Double(face.up.dy)) * 40
                hearts.emit(Particle(position: corner.simd, velocity: drift * face.exprScale, life: 1.3, size: face.interocular * 0.2,
                                     hue: Double.random(in: 0..<6.28, using: &rng), kind: 0))
            }
        } else {
            puckered.reset()
        }
        for i in marks.indices { marks[i].age += dt }
        marks.removeAll { $0.age > Self.flightTime + Self.stayTime + Self.fadeTime }
        hearts.step(dt)
    }

    private func launch(_ face: FaceState) {
        sinceKiss = 0
        kissCount += 1
        let io = face.interocular
        // Somewhere around the head, never over the middle of the face, always well inside the picture.
        let angle = Double.random(in: -0.5...(Double.pi + 0.5), using: &rng)
        let reach = Double.random(in: 1.9...3.0, using: &rng)
        let size = io * Double.random(in: 0.85...1.15, using: &rng)
        let raw = CGPoint(x: face.eyeCenter.x + cos(angle) * reach * io * 1.15, y: face.exprFaceCenter.y + sin(angle) * reach * io * 0.8)
        let to = face.exprKeepInside(raw, half: CGSize(width: size * 0.6, height: size * 0.4), in: bounds)
        if marks.count >= 8 { marks.removeFirst() }
        marks.append(Mark(from: face.mouth, to: to, turn: Double.random(in: -0.45...0.45, using: &rng), size: size, arc: Double.random(in: -0.5...0.5, using: &rng)))
        // A few little hearts chase the kiss out, so nothing lingers over the face.
        let toward = atan2(to.y - face.mouth.y, to.x - face.mouth.x)
        for _ in 0..<3 {
            let a = toward + Double.random(in: -0.35...0.35, using: &rng)
            hearts.emit(Particle(position: face.mouth.simd, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 380...620, using: &rng) * face.exprScale,
                                 life: Double.random(in: 0.7...1.1, using: &rng), size: io * Double.random(in: 0.16...0.24, using: &rng),
                                 hue: Double.random(in: 0..<6.28, using: &rng), kind: Int.random(in: 0..<2, using: &rng)))
        }
    }

    /// A lipstick print: two full lips with a cupid's bow, the creases of the lips and a soft sheen on the lower one.
    static let print: CGImage? = ExprSprites.make("expr-kiss-print", side: 256) { ctx in
        let upper = CGMutablePath()
        upper.move(to: CGPoint(x: -0.9, y: 0.02))
        upper.addCurve(to: CGPoint(x: -0.06, y: 0.42), control1: CGPoint(x: -0.62, y: 0.3), control2: CGPoint(x: -0.32, y: 0.55))
        upper.addQuadCurve(to: CGPoint(x: 0.06, y: 0.42), control: CGPoint(x: 0, y: 0.3))
        upper.addCurve(to: CGPoint(x: 0.9, y: 0.02), control1: CGPoint(x: 0.32, y: 0.55), control2: CGPoint(x: 0.62, y: 0.3))
        upper.addQuadCurve(to: CGPoint(x: -0.9, y: 0.02), control: CGPoint(x: 0, y: -0.06))
        upper.closeSubpath()
        let lower = CGMutablePath()
        lower.move(to: CGPoint(x: -0.86, y: -0.02))
        lower.addQuadCurve(to: CGPoint(x: 0.86, y: -0.02), control: CGPoint(x: 0, y: -0.1))
        lower.addCurve(to: CGPoint(x: -0.86, y: -0.02), control1: CGPoint(x: 0.5, y: -0.62), control2: CGPoint(x: -0.5, y: -0.62))
        lower.closeSubpath()
        let lipstick = ExprPalette.Ramp(light: (1.0, 0.42, 0.52), base: (0.88, 0.1, 0.26), dark: (0.62, 0.02, 0.16), edge: (0.48, 0.0, 0.12))
        for lip in [upper, lower] {
            ExprPaint.glossy(ctx, lip, lipstick, edgeWidth: 0.025, shadow: 0.22, shine: 0, rim: 0.3)
            // The fine creases a real print leaves.
            ctx.saveGState()
            ctx.addPath(lip); ctx.clip()
            ctx.setStrokeColor(exprColor((0.5, 0.0, 0.1), 0.45)); ctx.setLineWidth(0.022); ctx.setLineCap(.round)
            for k in -7...7 {
                let x = Double(k) * 0.11
                ctx.move(to: CGPoint(x: x, y: -0.6)); ctx.addQuadCurve(to: CGPoint(x: x * 1.1, y: 0.5), control: CGPoint(x: x * 0.8, y: 0)); ctx.strokePath()
            }
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.translateBy(x: -0.2, y: -0.3)
        ctx.rotate(by: -0.12)
        ctx.setFillColor(exprColor((1, 0.85, 0.9), 0.55))
        ctx.fillEllipse(in: CGRect(x: -0.24, y: -0.05, width: 0.48, height: 0.1))
        ctx.restoreGState()
    }

    override func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        for p in hearts.particles {
            let t = p.progress
            ctx.exprStamp(ExprSprites.heart(variant: p.kind), at: CGPoint(x: p.position.x + sin(p.age * 5 + p.hue) * p.size * 0.4, y: p.position.y),
                          height: p.size * exprOutBack(min(1, p.age / 0.25)), rotation: sin(p.age * 3 + p.hue) * 0.3, alpha: 1 - exprSmoothstep(0.55, 1, t))
        }
        for m in marks {
            let fly = min(1, m.age / Self.flightTime)
            let e = exprOutCubic(fly)
            // The flight bends to one side and comes toward you, growing; the landing squashes it flat for a moment.
            let bend = sin(fly * .pi) * m.arc * m.size
            let at = CGPoint(x: m.from.x + (m.to.x - m.from.x) * e + bend, y: m.from.y + (m.to.y - m.from.y) * e + abs(bend) * 0.5)
            let landed = max(0, m.age - Self.flightTime)
            let squash = landed > 0 ? 1 + 0.18 * exp(-landed * 14) * cos(landed * 30) : 1
            let grow = 0.25 + 0.75 * exprOutBack(fly, overshoot: 2.2)
            let fade = 1 - exprSmoothstep(Self.flightTime + Self.stayTime, Self.flightTime + Self.stayTime + Self.fadeTime, m.age)
            ctx.saveGState()
            ctx.translateBy(x: at.x, y: at.y)
            ctx.rotate(by: m.turn * e + (1 - e) * 2.5 * m.arc)
            ctx.scaleBy(x: squash, y: 1 / squash)
            ctx.exprStamp(Self.print, at: .zero, height: m.size * grow, alpha: fade)
            ctx.restoreGState()
        }
    }
}
