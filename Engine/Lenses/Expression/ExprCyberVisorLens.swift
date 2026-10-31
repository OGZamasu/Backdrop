import CoreGraphics
import CoreImage

/// A sleek smoked-glass visor drops over your eyes with a scanner light sweeping inside it. Raise your eyebrows and it
/// switches to targeting mode (amber, with locks over each eye); smile and it goes party mode (a rainbow sweep).
final class ExprCyberVisorLens: ExprOverlayLens {
    static let browsOn = 0.5, browsOff = 0.3
    static let smileOn = 0.5, smileOff = 0.3

    private var targeting = ExprLatch()
    private var partying = ExprLatch()
    private var aim = ExprSpring()
    private var party = ExprSpring()
    private var sweep = 0.0

    var isTargeting: Bool { targeting.isOn }
    var isPartying: Bool { partying.isOn }

    override var hintText: String { "Raise your brows, or smile" }

    override func restart() {
        super.restart()
        targeting.reset(); partying.reset(); aim.reset(); party.reset(); sweep = 0
    }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        if let face {
            targeting.update(face.browRaise, on: Self.browsOn, off: Self.browsOff)
            partying.update(face.smile, on: Self.smileOn, off: Self.smileOff)
        } else {
            targeting.reset(); partying.reset()
        }
        aim.step(toward: targeting.isOn ? 1 : 0, dt: dt, frequency: 3, damping: 0.6)
        party.step(toward: partying.isOn && !targeting.isOn ? 1 : 0, dt: dt, frequency: 3, damping: 0.6)
        sweep += dt * (1.1 + 1.2 * max(0, party.value))
    }

    /// The visor's outline in face units: wide across the eyes, wrapping to the temples, with a dip for the nose.
    static let shape: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -1.3, y: 0.08))
        p.addCurve(to: CGPoint(x: 0, y: 0.42), control1: CGPoint(x: -1.26, y: 0.36), control2: CGPoint(x: -0.6, y: 0.44))
        p.addCurve(to: CGPoint(x: 1.3, y: 0.08), control1: CGPoint(x: 0.6, y: 0.44), control2: CGPoint(x: 1.26, y: 0.36))
        p.addCurve(to: CGPoint(x: 1.0, y: -0.3), control1: CGPoint(x: 1.32, y: -0.14), control2: CGPoint(x: 1.2, y: -0.28))
        p.addCurve(to: CGPoint(x: 0.14, y: -0.2), control1: CGPoint(x: 0.7, y: -0.33), control2: CGPoint(x: 0.36, y: -0.3))
        p.addQuadCurve(to: CGPoint(x: -0.14, y: -0.2), control: CGPoint(x: 0, y: -0.06))
        p.addCurve(to: CGPoint(x: -1.0, y: -0.3), control1: CGPoint(x: -0.36, y: -0.3), control2: CGPoint(x: -0.7, y: -0.33))
        p.addCurve(to: CGPoint(x: -1.3, y: 0.08), control1: CGPoint(x: -1.2, y: -0.28), control2: CGPoint(x: -1.32, y: -0.14))
        p.closeSubpath()
        return p
    }()

    /// The glass and its frame, baked: smoked glass, a chrome rim lit from the top left, two reflections and the earpieces.
    static let glass: CGImage? = ExprSprites.make("expr-visor-glass", side: 512) { ctx in
        ctx.scaleBy(x: 0.72, y: 0.72)
        let px = max(ctx.ctm.a, 1)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0.03 * px, height: -0.06 * px), blur: 0.09 * px, color: exprColor((0.02, 0.02, 0.06), 0.45))
        ctx.addPath(shape); ctx.setFillColor(exprColor((0.05, 0.07, 0.14), 0.9)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        if let g = ExprShapes.gradient([((0.16, 0.22, 0.4), 0), ((0.05, 0.07, 0.15), 0.55), ((0.1, 0.12, 0.24), 1)], alphas: [0.92, 0.9, 0.92]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0.45), end: CGPoint(x: 0, y: -0.33), options: [])
        }
        // Two slanted reflections across the glass.
        ctx.setFillColor(exprColor((1, 1, 1), 0.13))
        for (x, w) in [(-0.7, 0.26), (-0.3, 0.08)] {
            ctx.move(to: CGPoint(x: x, y: 0.5)); ctx.addLine(to: CGPoint(x: x + w, y: 0.5))
            ctx.addLine(to: CGPoint(x: x + w - 0.3, y: -0.4)); ctx.addLine(to: CGPoint(x: x - 0.3, y: -0.4)); ctx.closePath(); ctx.fillPath()
        }
        ctx.restoreGState()
        // Chrome rim: a dark outer line, a bright inner one, brightest along the top.
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(exprColor((0.16, 0.18, 0.26))); ctx.setLineWidth(0.075); ctx.addPath(shape); ctx.strokePath()
        ctx.setStrokeColor(exprColor((0.74, 0.8, 0.9))); ctx.setLineWidth(0.035); ctx.addPath(shape); ctx.strokePath()
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        ctx.translateBy(x: 0, y: -0.03)
        ctx.setStrokeColor(exprColor((1, 1, 1), 0.7)); ctx.setLineWidth(0.03); ctx.addPath(shape); ctx.strokePath()
        ctx.restoreGState()
        // Earpieces at the temples.
        for side in [-1.0, 1.0] {
            let piece = CGPath(roundedRect: CGRect(x: side * 1.34 - 0.07, y: -0.16, width: 0.14, height: 0.3), cornerWidth: 0.06, cornerHeight: 0.06, transform: nil)
            ExprPaint.glossy(ctx, piece, ExprPalette.Ramp(light: (0.9, 0.93, 1.0), base: (0.55, 0.6, 0.7), dark: (0.25, 0.28, 0.36), edge: (0.12, 0.13, 0.2)),
                             edgeWidth: 0.025, shadow: 0, shine: 0.5, rim: 0)
        }
    }

    override func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        guard let face else { return }
        let fade = presence.alpha
        let drop = (1 - exprOutBack(min(1, presence.visibleFor / 0.5))) * 1.1
        let target = max(0, min(1, aim.value)), fun = max(0, min(1, party.value))
        let accent = exprMix(exprMix(ExprPalette.neonCyan, ExprPalette.neonAmber, target), Palette.rgb(hue: (time * 0.35).truncatingRemainder(dividingBy: 1), saturation: 0.7), fun)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(fade))
        ctx.inFaceSpace(face) {
            ctx.translateBy(x: 0, y: 0.04 + drop)
            // Light spilling from the visor onto the face.
            ctx.setBlendMode(.plusLighter)
            ctx.saveGState(); ctx.scaleBy(x: 1, y: 0.45)
            ctx.glow(center: .zero, radius: 1.5, red: accent.r, green: accent.g, blue: accent.b, alpha: 0.18)
            ctx.restoreGState()
            ctx.setBlendMode(.normal)
            ctx.exprPlace(Self.glass, at: .zero, height: 2 / 0.72)
            ctx.saveGState()
            ctx.addPath(Self.shape); ctx.clip()
            ctx.setBlendMode(.plusLighter)
            drawScanner(ctx, accent: accent, time: time)
            if target > 0.02 { drawLocks(ctx, amount: target, accent: accent, time: time) }
            if fun > 0.02 { drawBars(ctx, amount: fun, time: time) }
            ctx.restoreGState()
            // An LED on each earpiece.
            for side in [-1.0, 1.0] {
                ctx.setBlendMode(.plusLighter)
                ctx.glow(center: CGPoint(x: side * 1.34, y: 0.06), radius: 0.09, red: accent.r, green: accent.g, blue: accent.b, alpha: 0.6 + 0.4 * sin(time * 3))
                ctx.setBlendMode(.normal)
            }
        }
        ctx.restoreGState()
    }

    /// A bar of light that sweeps from side to side, easing at the ends, with a trail behind it.
    private func drawScanner(_ ctx: CGContext, accent: ExprRGB, time: Double) {
        let phase = sweep.truncatingRemainder(dividingBy: 2)
        let going = phase < 1 ? 1.0 : -1.0
        let u = phase < 1 ? phase : 2 - phase
        let x = -1.05 + 2.1 * exprSmoothstep(0, 1, u)
        for k in 0..<7 {
            let lag = Double(k) * 0.07
            let tx = x - going * lag
            let a = (1 - Double(k) / 7) * (k == 0 ? 1 : 0.5)
            ctx.saveGState()
            ctx.translateBy(x: tx, y: 0.06)
            ctx.scaleBy(x: 0.6, y: 1.6)
            ctx.glow(center: .zero, radius: 0.22, red: accent.r, green: accent.g, blue: accent.b, alpha: a)
            ctx.restoreGState()
        }
        ctx.glow(center: CGPoint(x: x, y: 0.06), radius: 0.11, red: 1, green: 1, blue: 1, alpha: 1)
        // A thin line along the glass, lit near the light.
        ctx.setStrokeColor(exprColor(accent, 0.55)); ctx.setLineWidth(0.016)
        ctx.move(to: CGPoint(x: -1.15, y: 0.06)); ctx.addLine(to: CGPoint(x: 1.15, y: 0.06)); ctx.strokePath()
    }

    /// Targeting: a turning lock over each eye and tick marks.
    private func drawLocks(_ ctx: CGContext, amount: Double, accent: ExprRGB, time: Double) {
        for side in [-1.0, 1.0] {
            ctx.saveGState()
            ctx.translateBy(x: side * 0.5, y: 0.04)
            ctx.scaleBy(x: 1.4 - 0.4 * amount, y: 1.4 - 0.4 * amount)
            ctx.rotate(by: time * 1.5 * side)
            ctx.setStrokeColor(exprColor(accent, 0.9 * amount)); ctx.setLineWidth(0.025)
            let r = 0.2
            for q in 0..<4 {
                let a = Double(q) * .pi / 2
                ctx.addArc(center: .zero, radius: r, startAngle: a + 0.25, endAngle: a + .pi / 2 - 0.25, clockwise: false); ctx.strokePath()
                ctx.move(to: CGPoint(x: cos(a) * r * 0.55, y: sin(a) * r * 0.55)); ctx.addLine(to: CGPoint(x: cos(a) * r * 0.85, y: sin(a) * r * 0.85)); ctx.strokePath()
            }
            ctx.restoreGState()
        }
    }

    /// Party: little level bars dancing along the bottom of the glass.
    private func drawBars(_ ctx: CGContext, amount: Double, time: Double) {
        for i in 0..<14 {
            let x = -0.95 + Double(i) * 0.146
            let h = 0.05 + 0.2 * amount * (0.5 + 0.5 * sin(time * (7 + Double(i % 5)) + Double(i) * 1.3))
            let c = Palette.rgb(hue: Double(i) / 14 + time * 0.2, saturation: 0.65)
            ctx.setFillColor(exprColor((c.r, c.g, c.b), 0.75 * amount))
            ctx.fill(CGRect(x: x - 0.045, y: -0.2, width: 0.09, height: h))
        }
    }
}
