import CoreGraphics
import CoreImage

/// Huge sparkly anime eyes over yours. Smile and they squint happily with stars in them while blush marks glow on your
/// cheeks and sparkles pop around your head; blink and they blink.
final class ExprAnimeEyesLens: ExprOverlayLens {
    /// Smile needed to go happy, and (lower) to stay happy.
    static let startAt = 0.5, stopAt = 0.3

    /// The iris, from its dark top to its glowing bottom.
    static let iris: [(ExprRGB, Double)] = [((0.14, 0.08, 0.36), 0), ((0.33, 0.24, 0.74), 0.45), ((0.46, 0.66, 0.96), 0.82), ((0.66, 0.94, 1.0), 1)]

    private var smiling = ExprLatch()
    private var happy = ExprSpring()
    private var sparkles = ParticleSystem(capacity: 60)
    private var rng = SplitMix64(seed: 0xA21E)
    private var owed = 0.0

    var isHappy: Bool { smiling.isOn }
    /// How far the eyes have gone into their happy squint, 0...1.
    var happiness: Double { happy.value }
    var sparkleCount: Int { sparkles.particles.count }

    override var hintText: String { "Smile!" }
    override var isFinished: Bool { presence.face == nil && sparkles.particles.isEmpty }

    override init() {
        super.init()
        sparkles.gravity = SIMD2(0, -30)
        sparkles.drag = 1.5
    }

    override func restart() {
        super.restart()
        smiling.reset(); happy.reset(); sparkles.removeAll(); owed = 0
    }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        if let face {
            let was = smiling.isOn
            smiling.update(face.smile, on: Self.startAt, off: Self.stopAt)
            if smiling.isOn && !was { burst(face, count: 9) }
            if smiling.isOn {
                owed += dt * 3
                while owed >= 1 { owed -= 1; burst(face, count: 1) }
            }
        } else {
            smiling.reset()
        }
        happy.step(toward: smiling.isOn ? 1 : 0, dt: dt, frequency: 3.2, damping: 0.6)
        sparkles.step(dt)
    }

    private func burst(_ face: FaceState, count: Int) {
        let scale = face.exprScale
        for _ in 0..<count {
            let angle = Double.random(in: 0.2...(Double.pi - 0.2), using: &rng) + face.roll
            let reach = Double.random(in: 1.15...1.7, using: &rng)
            let at = face.exprPoint(cos(angle - face.roll) * reach * 1.15, sin(angle - face.roll) * reach * 0.9 + 0.1)
            sparkles.emit(Particle(position: at.simd, velocity: SIMD2(cos(angle), sin(angle)) * 40 * scale,
                                   life: Double.random(in: 0.6...1.1, using: &rng), size: Double.random(in: 14...28, using: &rng) * scale,
                                   hue: Double.random(in: 0..<6.28, using: &rng), kind: Int.random(in: 0..<4, using: &rng)))
        }
    }

    // MARK: Drawing

    /// One big open eye, baked. `side` -1 is the eye on the left of the picture; its lash flick points outward.
    static func eye(side: Int) -> CGImage? {
        ExprSprites.make("anime-eye-\(side)", side: 320) { ctx in
            let flip = Double(side)
            let white = CGPath(ellipseIn: CGRect(x: -0.6, y: -0.82, width: 1.2, height: 1.5), transform: nil)
            // A soft shadow under the eye, then the white, lit from the top left.
            ExprPaint.glossy(ctx, white, ExprPalette.snow, edgeWidth: 0, shadow: 0.25, shine: 0, rim: 0)
            ctx.saveGState()
            ctx.addPath(white); ctx.clip()
            // The upper lid's shadow on the white.
            if let g = ExprShapes.gradient([((0.55, 0.5, 0.72), 0), ((0.55, 0.5, 0.72), 1)], alphas: [0.55, 0]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0.68), end: CGPoint(x: 0, y: 0.25), options: [])
            }
            let iris = CGPath(ellipseIn: CGRect(x: -0.47, y: -0.78, width: 0.94, height: 1.3), transform: nil)
            ctx.saveGState()
            ctx.addPath(iris); ctx.clip()
            if let g = ExprShapes.gradient(Self.iris) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0.52), end: CGPoint(x: 0, y: -0.78), options: [])
            }
            // A glowing crescent at the bottom of the iris and a ring of fine lines, for depth.
            if let g = ExprShapes.gradient([((0.8, 1.0, 1.0), 0), ((0.8, 1.0, 1.0), 1)], alphas: [0.7, 0]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: 0, y: -0.62), startRadius: 0, endCenter: CGPoint(x: 0, y: -0.62), endRadius: 0.5, options: [])
            }
            ctx.setStrokeColor(exprColor((0.12, 0.06, 0.3), 0.35)); ctx.setLineWidth(0.02)
            for i in 0..<14 {
                let a = Double(i) / 14 * 2 * .pi
                ctx.move(to: CGPoint(x: cos(a) * 0.2, y: -0.13 + sin(a) * 0.28))
                ctx.addLine(to: CGPoint(x: cos(a) * 0.42, y: -0.13 + sin(a) * 0.58)); ctx.strokePath()
            }
            ctx.restoreGState()
            ctx.setStrokeColor(exprColor((0.1, 0.04, 0.24))); ctx.setLineWidth(0.045)
            ctx.addPath(iris); ctx.strokePath()
            // The pupil.
            ctx.setFillColor(exprColor((0.06, 0.02, 0.14)))
            ctx.fillEllipse(in: CGRect(x: -0.19, y: -0.4, width: 0.38, height: 0.56))
            ctx.restoreGState()

            // The upper lash line: thick ink over the top of the eye, with a flick at the outer corner.
            let lid = CGMutablePath()
            lid.move(to: CGPoint(x: -0.66 * flip, y: 0.12))
            lid.addCurve(to: CGPoint(x: 0.6 * flip, y: 0.42), control1: CGPoint(x: -0.5 * flip, y: 0.92), control2: CGPoint(x: 0.42 * flip, y: 0.96))
            lid.addQuadCurve(to: CGPoint(x: 0.9 * flip, y: 0.62), control: CGPoint(x: 0.76 * flip, y: 0.5))
            lid.addQuadCurve(to: CGPoint(x: 0.66 * flip, y: 0.3), control: CGPoint(x: 0.8 * flip, y: 0.36))
            lid.addCurve(to: CGPoint(x: -0.66 * flip, y: 0.12), control1: CGPoint(x: 0.4 * flip, y: 0.8), control2: CGPoint(x: -0.46 * flip, y: 0.8))
            lid.closeSubpath()
            ctx.setFillColor(exprColor(ExprPalette.ink)); ctx.addPath(lid); ctx.fillPath()
            ctx.setStrokeColor(exprColor(ExprPalette.ink)); ctx.setLineWidth(0.07); ctx.setLineJoin(.round)
            ctx.addPath(lid); ctx.strokePath()
            // Lashes off the outer corner and a fine lower lash line.
            ctx.setLineCap(.round); ctx.setLineWidth(0.05)
            for (x, y, dx, dy) in [(0.78, 0.54, 0.16, 0.2), (0.64, 0.7, 0.12, 0.24)] as [(Double, Double, Double, Double)] {
                ctx.move(to: CGPoint(x: x * flip, y: y)); ctx.addLine(to: CGPoint(x: (x + dx) * flip, y: y + dy)); ctx.strokePath()
            }
            ctx.setLineWidth(0.035)
            ctx.move(to: CGPoint(x: 0.2 * flip, y: -0.8)); ctx.addQuadCurve(to: CGPoint(x: 0.55 * flip, y: -0.5), control: CGPoint(x: 0.48 * flip, y: -0.76))
            ctx.strokePath()
            // Highlights, always top left, whichever eye.
            ctx.setFillColor(exprColor((1, 1, 1)))
            ctx.fillEllipse(in: CGRect(x: -0.36, y: -0.06, width: 0.32, height: 0.42))
            ctx.fillEllipse(in: CGRect(x: 0.1, y: -0.56, width: 0.14, height: 0.14))
            ctx.setFillColor(exprColor((1, 1, 1), 0.85))
            ctx.fillEllipse(in: CGRect(x: 0.14, y: 0.06, width: 0.09, height: 0.09))
        }
    }

    override func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        for p in sparkles.particles {
            let t = p.progress
            let size = p.size * exprOutBack(min(1, p.age / 0.2)) * (1 - 0.6 * exprSmoothstep(0.5, 1, t))
            ctx.exprStamp(ExprSprites.twinkle(variant: p.kind), at: CGPoint(x: p.position.x, y: p.position.y), height: size * 2.2,
                          rotation: p.age * 1.2 + p.hue, alpha: 1 - exprSmoothstep(0.6, 1, t))
        }
        guard let face else { return }
        let fade = presence.alpha
        let pop = popIn
        let h = happy.value
        ctx.saveGState()
        ctx.setAlpha(CGFloat(fade))
        ctx.inFaceSpace(face) {
            drawBlush(ctx, amount: 0.25 + 0.75 * h, time: time)
            // A happy squint: the eye narrows from below (still covering yours) and stars come out in it.
            let squint = 1 - 0.3 * max(0, min(1, h))
            let open = max(0, 1 - face.blink)
            for (i, side) in [-1.0, 1.0].enumerated() {
                let centre = CGPoint(x: side * 0.5, y: 0.04)
                // The highlights shimmer: the eye breathes a touch, as if wet.
                let breathe = 1 + 0.015 * sin(time * 2.3 + Double(i))
                if open > 0.04 {
                    ctx.saveGState()
                    ctx.translateBy(x: centre.x, y: centre.y + 0.14 * (1 - squint) + 0.06 * (1 - open))
                    ctx.scaleBy(x: breathe * pop, y: open * squint * breathe * pop)
                    ctx.exprPlace(Self.eye(side: i == 0 ? -1 : 1), at: .zero, height: 1.12)
                    ctx.restoreGState()
                    if h > 0.02 {
                        // The smile's lower lid, curving up under the eye, and a star in each eye.
                        ctx.setLineCap(.round)
                        ctx.setStrokeColor(exprColor(ExprPalette.ink, min(1, h) * open)); ctx.setLineWidth(0.05)
                        ctx.move(to: CGPoint(x: centre.x - 0.26, y: centre.y - 0.26))
                        ctx.addQuadCurve(to: CGPoint(x: centre.x + 0.26, y: centre.y - 0.26), control: CGPoint(x: centre.x, y: centre.y - 0.12))
                        ctx.strokePath()
                        let twinkle = 0.85 + 0.15 * sin(time * 7 + Double(i) * 2)
                        ctx.exprPlace(ExprSprites.twinkle(variant: 0), at: CGPoint(x: centre.x + 0.08, y: centre.y + 0.02), height: 0.42 * min(1, h) * twinkle * open,
                                      rotation: time * 0.8, alpha: min(1, h))
                    }
                }
                // Shut: a soft lash line.
                let shut = 1 - open
                guard shut > 0.05 else { continue }
                ctx.setLineCap(.round)
                ctx.setStrokeColor(exprColor(ExprPalette.ink, min(1, shut * 1.4)))
                ctx.setLineWidth(0.075)
                ctx.move(to: CGPoint(x: centre.x - 0.3, y: centre.y + 0.02))
                ctx.addQuadCurve(to: CGPoint(x: centre.x + 0.3, y: centre.y + 0.02), control: CGPoint(x: centre.x, y: centre.y - 0.2))
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }

    /// Pink ovals under the eyes with a few quick hatch strokes, the anime way of saying "flustered".
    private func drawBlush(_ ctx: CGContext, amount: Double, time: Double) {
        for side in [-1.0, 1.0] {
            let c = CGPoint(x: side * 0.72, y: -0.62)
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.scaleBy(x: 1, y: 0.55)
            ctx.glow(center: .zero, radius: 0.36, red: 1, green: 0.42, blue: 0.56, alpha: 0.55 * amount)
            ctx.restoreGState()
            ctx.setLineCap(.round)
            ctx.setStrokeColor(exprColor((0.92, 0.3, 0.45), 0.8 * amount))
            ctx.setLineWidth(0.035)
            for k in -1...1 {
                let x = c.x + Double(k) * 0.11
                ctx.move(to: CGPoint(x: x - 0.04, y: c.y - 0.07)); ctx.addLine(to: CGPoint(x: x + 0.05, y: c.y + 0.07)); ctx.strokePath()
            }
        }
    }
}
