import CoreGraphics
import Foundation

/// The Staring Contest's cast and props: a family of silly blob creatures ("goofs") that close in to make you blink, the eye
/// that shows how shut yours look, and the hypnotic swirl. All drawn once and kept.
enum StaringContestArt {
    typealias Tone = FaceGamePaint.Tone

    /// How many different goofs there are.
    static let goofCount = 8

    private static let goofTones: [Tone] = [FaceGamePalette.grape, FaceGamePalette.teal, FaceGamePalette.bubblegum, FaceGamePalette.sun,
                                            FaceGamePalette.sky, FaceGamePalette.mint, FaceGamePalette.tangerine, FaceGamePalette.coral]

    /// One goof, 180 pixels square.
    static func goof(_ variant: Int) -> CGImage? {
        let v = ((variant % goofCount) + goofCount) % goofCount
        return FaceGameArt.sprite("staring-goof-\(v)", width: 180, height: 180) { ctx, _ in drawGoof(ctx, v) }
    }

    private static func drawGoof(_ ctx: CGContext, _ v: Int) {
        let tone = goofTones[v]
        let c = CGPoint(x: 90, y: 80)
        var radii: [Double] = []
        for i in 0..<12 { radii.append(58 + 6 * sin(Double(i) * (1.7 + Double(v) * 0.3)) + 3 * cos(Double(i * (v + 2)))) }
        let body = FaceGameArt.blob(center: c, radii: radii, rotation: Double(v) * 0.4)

        // Antennae, horns or ears go behind the body.
        ctx.setLineCap(.round)
        switch v % 3 {
        case 0:
            for side in [-1.0, 1.0] {
                let tip = CGPoint(x: c.x + side * 34, y: c.y + 98)
                ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: tone)))
                ctx.setLineWidth(9)
                ctx.move(to: CGPoint(x: c.x + side * 16, y: c.y + 44))
                ctx.addQuadCurve(to: tip, control: CGPoint(x: c.x + side * 8, y: c.y + 84))
                ctx.strokePath()
                ctx.setStrokeColor(FaceGamePaint.cg(tone))
                ctx.setLineWidth(5)
                ctx.move(to: CGPoint(x: c.x + side * 16, y: c.y + 44))
                ctx.addQuadCurve(to: tip, control: CGPoint(x: c.x + side * 8, y: c.y + 84))
                ctx.strokePath()
                FaceGameArt.litBall(ctx, center: tip, radius: 10, tone: goofTones[(v + 3) % goofCount], edgeWidth: 3, gloss: 0.7)
            }
        case 1:
            for side in [-1.0, 1.0] {
                let horn = CGMutablePath()
                horn.move(to: CGPoint(x: c.x + side * 20, y: c.y + 46))
                horn.addQuadCurve(to: CGPoint(x: c.x + side * 50, y: c.y + 92), control: CGPoint(x: c.x + side * 22, y: c.y + 84))
                horn.addQuadCurve(to: CGPoint(x: c.x + side * 46, y: c.y + 40), control: CGPoint(x: c.x + side * 56, y: c.y + 62))
                horn.closeSubpath()
                FaceGameArt.fillLit(ctx, horn, tone: FaceGamePalette.cream, edgeWidth: 3.5)
            }
        default:
            for side in [-1.0, 1.0] {
                ctx.saveGState()
                ctx.translateBy(x: c.x + side * 50, y: c.y + 30)
                ctx.rotate(by: CGFloat(side * -0.5))
                FaceGameArt.fillLit(ctx, CGPath(ellipseIn: CGRect(x: -16, y: -8, width: 32, height: 46), transform: nil), tone: tone, edgeWidth: 4)
                ctx.restoreGState()
            }
        }

        FaceGameArt.fillLit(ctx, body, tone: tone, edgeWidth: 5)
        FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 26, y: c.y + 32), width: 36, height: 18, rotation: 0.6, alpha: 0.5)
        // A belly patch.
        ctx.setFillColor(FaceGamePaint.cg(FaceGameArt.lighter(tone, 0.3), 0.6))
        ctx.fillEllipse(in: CGRect(x: c.x - 26, y: c.y - 54, width: 52, height: 34))

        // Eyes: googly pairs, a cyclops, three in a row or crossed.
        func eye(_ p: CGPoint, _ r: Double, look: CGPoint) {
            ctx.setFillColor(FaceGamePaint.cg(FaceGameArt.edge(of: tone)))
            ctx.fillEllipse(in: CGRect(x: p.x - r - 3, y: p.y - r - 3, width: r * 2 + 6, height: r * 2 + 6))
            ctx.setFillColor(FaceGamePaint.cg(Tone(1, 1, 1)))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            let pr = r * 0.48
            let q = CGPoint(x: p.x + look.x * (r - pr - 1), y: p.y + look.y * (r - pr - 1))
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.ink))
            ctx.fillEllipse(in: CGRect(x: q.x - pr, y: q.y - pr, width: pr * 2, height: pr * 2))
            ctx.setFillColor(FaceGamePaint.cg(Tone(1, 1, 1)))
            ctx.fillEllipse(in: CGRect(x: q.x - pr * 0.6, y: q.y + pr * 0.15, width: pr * 0.5, height: pr * 0.5))
        }
        switch v % 4 {
        case 0:
            eye(CGPoint(x: c.x - 20, y: c.y + 14), 18, look: CGPoint(x: 0.7, y: 0.5))
            eye(CGPoint(x: c.x + 22, y: c.y + 18), 14, look: CGPoint(x: -0.6, y: -0.6))
        case 1:
            eye(CGPoint(x: c.x, y: c.y + 16), 26, look: CGPoint(x: 0, y: -0.2))
        case 2:
            eye(CGPoint(x: c.x - 28, y: c.y + 12), 12, look: CGPoint(x: 0.6, y: 0))
            eye(CGPoint(x: c.x, y: c.y + 22), 14, look: CGPoint(x: 0, y: 0.7))
            eye(CGPoint(x: c.x + 28, y: c.y + 12), 12, look: CGPoint(x: -0.6, y: 0))
        default:
            eye(CGPoint(x: c.x - 18, y: c.y + 16), 17, look: CGPoint(x: 0.75, y: 0))
            eye(CGPoint(x: c.x + 18, y: c.y + 16), 17, look: CGPoint(x: -0.75, y: 0))
        }

        // Mouths: a grin with the tongue out, a wobbly line, a surprised O, or one big tooth.
        let ink = FaceGamePaint.cg(FaceGamePalette.ink)
        let m = CGPoint(x: c.x, y: c.y - 20)
        switch (v / 2) % 4 {
        case 0:
            let grin = CGMutablePath()
            grin.move(to: CGPoint(x: m.x - 26, y: m.y + 4))
            grin.addQuadCurve(to: CGPoint(x: m.x + 26, y: m.y + 4), control: CGPoint(x: m.x, y: m.y - 30))
            grin.closeSubpath()
            ctx.addPath(grin)
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.38, 0.06, 0.14)))
            ctx.fillPath()
            FaceGameArt.fillLit(ctx, CGPath(roundedRect: CGRect(x: m.x - 2, y: m.y - 30, width: 18, height: 24), cornerWidth: 9, cornerHeight: 9, transform: nil),
                                tone: FaceGamePalette.coral, edgeWidth: 2.5)
        case 1:
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(6)
            ctx.move(to: CGPoint(x: m.x - 24, y: m.y))
            ctx.addCurve(to: CGPoint(x: m.x + 24, y: m.y), control1: CGPoint(x: m.x - 8, y: m.y + 12), control2: CGPoint(x: m.x + 8, y: m.y - 12))
            ctx.strokePath()
        case 2:
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.38, 0.06, 0.14)))
            ctx.fillEllipse(in: CGRect(x: m.x - 11, y: m.y - 16, width: 22, height: 26))
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(4)
            ctx.strokeEllipse(in: CGRect(x: m.x - 11, y: m.y - 16, width: 22, height: 26))
        default:
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(6)
            ctx.move(to: CGPoint(x: m.x - 26, y: m.y + 4))
            ctx.addQuadCurve(to: CGPoint(x: m.x + 26, y: m.y + 4), control: CGPoint(x: m.x, y: m.y - 18))
            ctx.strokePath()
            ctx.setFillColor(FaceGamePaint.cg(Tone(1, 1, 1)))
            ctx.fill(CGRect(x: m.x - 6, y: m.y - 14, width: 12, height: 10))
        }
    }

    /// A marquee bulb in its dark casing, lit with a warm glow or dim, 40 pixels square.
    static func bulb(lit: Bool, red: Bool) -> CGImage? {
        FaceGameArt.sprite("staring-bulb-\(lit)-\(red)", width: 40, height: 40) { ctx, _ in
            let c = CGPoint(x: 20, y: 20)
            let tone = red ? FaceGamePalette.coral : FaceGamePalette.sun
            if lit { FaceGamePaint.spark(ctx, at: c, radius: 20, tone: tone, alpha: 0.75) }
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.ink))
            ctx.fillEllipse(in: CGRect(x: c.x - 9.5, y: c.y - 9.5, width: 19, height: 19))
            let r = lit ? 7.0 : 5.5
            if lit {
                FaceGameArt.litBall(ctx, center: c, radius: r, tone: FaceGameArt.lighter(tone, 0.55), gloss: 0.6)
            } else {
                ctx.setFillColor(FaceGamePaint.cg(tone * 0.45))
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }
        }
    }

    /// Light and shade for the frame, laid over its flat colour: brighter to the top left, deeper to the bottom right.
    static var frameGloss: CGImage? {
        FaceGameArt.sprite("staring-frame-gloss", width: 332, height: 332) { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.addPath(FaceGamePaint.roundedPath(rect, radius: 44))
            ctx.clip()
            let colors = [FaceGamePaint.cg(Tone(1, 1, 1), 0.38), FaceGamePaint.cg(Tone(1, 1, 1), 0), FaceGamePaint.cg(FaceGamePalette.ink, 0.32)] as CFArray
            if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: colors, locations: [0, 0.45, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 60, y: size.height), end: CGPoint(x: size.width - 60, y: 0), options: [])
            }
        }
    }
}
