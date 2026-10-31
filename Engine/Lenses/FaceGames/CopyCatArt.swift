import CoreGraphics
import Foundation

/// The Copy Cat: a ginger cat drawn in vector that pulls each face the player has to copy. One picture per face, kept.
enum CopyCatArt {
    typealias Tone = FaceGamePaint.Tone

    static let fur = Tone(1, 0.66, 0.3)
    static let cream = Tone(1, 0.93, 0.8)
    static let pink = Tone(1, 0.6, 0.66)

    /// The cat making a face, 240 pixels square.
    static func cat(_ pose: CopyCatGame.Pose) -> CGImage? {
        FaceGameArt.sprite("copycat-\(pose)", width: 240, height: 240) { ctx, _ in draw(ctx, pose: pose) }
    }

    private static func draw(_ ctx: CGContext, pose: CopyCatGame.Pose) {
        let c = CGPoint(x: 120, y: 104)
        let ink = FaceGamePaint.cg(FaceGamePalette.ink)

        // Ears behind the head.
        for side in [-1.0, 1.0] {
            let ear = CGMutablePath()
            ear.move(to: CGPoint(x: c.x + side * 34, y: c.y + 62))
            ear.addQuadCurve(to: CGPoint(x: c.x + side * 76, y: c.y + 118), control: CGPoint(x: c.x + side * 52, y: c.y + 110))
            ear.addQuadCurve(to: CGPoint(x: c.x + side * 92, y: c.y + 34), control: CGPoint(x: c.x + side * 92, y: c.y + 92))
            ear.closeSubpath()
            FaceGameArt.fillLit(ctx, ear, tone: fur, edgeWidth: 3)
            let inner = CGMutablePath()
            inner.move(to: CGPoint(x: c.x + side * 46, y: c.y + 64))
            inner.addQuadCurve(to: CGPoint(x: c.x + side * 74, y: c.y + 104), control: CGPoint(x: c.x + side * 58, y: c.y + 98))
            inner.addQuadCurve(to: CGPoint(x: c.x + side * 82, y: c.y + 46), control: CGPoint(x: c.x + side * 82, y: c.y + 84))
            inner.closeSubpath()
            FaceGameArt.fillLit(ctx, inner, tone: pink)
        }

        // The head: wide at the cheeks.
        let head = CGMutablePath()
        head.move(to: CGPoint(x: c.x, y: c.y + 84))
        head.addCurve(to: CGPoint(x: c.x - 100, y: c.y - 6), control1: CGPoint(x: c.x - 70, y: c.y + 86), control2: CGPoint(x: c.x - 102, y: c.y + 44))
        head.addCurve(to: CGPoint(x: c.x, y: c.y - 82), control1: CGPoint(x: c.x - 98, y: c.y - 58), control2: CGPoint(x: c.x - 52, y: c.y - 82))
        head.addCurve(to: CGPoint(x: c.x + 100, y: c.y - 6), control1: CGPoint(x: c.x + 52, y: c.y - 82), control2: CGPoint(x: c.x + 98, y: c.y - 58))
        head.addCurve(to: CGPoint(x: c.x, y: c.y + 84), control1: CGPoint(x: c.x + 102, y: c.y + 44), control2: CGPoint(x: c.x + 70, y: c.y + 86))
        head.closeSubpath()
        FaceGameArt.fillLit(ctx, head, tone: fur, edgeWidth: 4)

        // Tabby stripes on the forehead and cheeks.
        ctx.saveGState()
        ctx.addPath(head)
        ctx.clip()
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: fur), 0.55))
        ctx.setLineCap(.round)
        ctx.setLineWidth(7)
        for dx in [-18.0, 0.0, 18.0] {
            ctx.move(to: CGPoint(x: c.x + dx, y: c.y + 86))
            ctx.addLine(to: CGPoint(x: c.x + dx * 0.8, y: c.y + (dx == 0 ? 54 : 62)))
        }
        for side in [-1.0, 1.0] {
            for k in 0..<2 {
                let y = c.y - 4 - Double(k) * 16
                ctx.move(to: CGPoint(x: c.x + side * 104, y: y))
                ctx.addLine(to: CGPoint(x: c.x + side * 80, y: y - 3))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()

        // The muzzle and blush.
        let muzzle = CGMutablePath()
        muzzle.addEllipse(in: CGRect(x: c.x - 46, y: c.y - 62, width: 50, height: 46))
        muzzle.addEllipse(in: CGRect(x: c.x - 4, y: c.y - 62, width: 50, height: 46))
        FaceGameArt.fillLit(ctx, muzzle, tone: cream)
        for side in [-1.0, 1.0] {
            FaceGamePaint.spark(ctx, at: CGPoint(x: c.x + side * 66, y: c.y - 30), radius: 20, tone: FaceGamePalette.coral, alpha: 0.45)
        }

        // Eyes.
        let eyeY = c.y + 18
        for side in [-1.0, 1.0] {
            let e = CGPoint(x: c.x + side * 42, y: eyeY)
            switch pose {
            case .eyesShut:
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(6)
                ctx.setLineCap(.round)
                ctx.addArc(center: CGPoint(x: e.x, y: e.y + 8), radius: 15, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
                ctx.strokePath()
            default:
                let wide = pose == .browsUp || pose == .openWide
                let w = wide ? 30.0 : 26.0, h = wide ? 40.0 : 32.0
                ctx.setFillColor(ink)
                ctx.fillEllipse(in: CGRect(x: e.x - w / 2, y: e.y - h / 2, width: w, height: h))
                ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.leaf * 1.1))
                ctx.fillEllipse(in: CGRect(x: e.x - w / 2 + 4, y: e.y - h / 2 + 4, width: w - 8, height: h - 8))
                ctx.setFillColor(ink)
                ctx.fillEllipse(in: CGRect(x: e.x - 5, y: e.y - h / 2 + 5, width: 10, height: h - 10))
                ctx.setFillColor(FaceGamePaint.cg(Tone(1, 1, 1)))
                ctx.fillEllipse(in: CGRect(x: e.x - w / 2 + 5, y: e.y + h * 0.08, width: 10, height: 10))
                ctx.fillEllipse(in: CGRect(x: e.x + 4, y: e.y - h * 0.3, width: 5, height: 5))
            }
            // Brows: raised high and arched when that is the face.
            if pose == .browsUp {
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(6)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: e.x - side * 18, y: eyeY + 40))
                ctx.addQuadCurve(to: CGPoint(x: e.x + side * 18, y: eyeY + 36), control: CGPoint(x: e.x, y: eyeY + 54))
                ctx.strokePath()
            }
        }

        // Nose.
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: c.x - 10, y: c.y - 14))
        nose.addLine(to: CGPoint(x: c.x + 10, y: c.y - 14))
        nose.addQuadCurve(to: CGPoint(x: c.x - 10, y: c.y - 14), control: CGPoint(x: c.x, y: c.y - 30))
        nose.closeSubpath()
        FaceGameArt.fillLit(ctx, nose, tone: pink, edgeWidth: 2)

        // Mouth.
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(5)
        ctx.setLineCap(.round)
        switch pose {
        case .openWide:
            let hole = CGRect(x: c.x - 24, y: c.y - 76, width: 48, height: 52)
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.42, 0.08, 0.16)))
            ctx.fillEllipse(in: hole)
            ctx.saveGState()
            ctx.addEllipse(in: hole)
            ctx.clip()
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.coral))
            ctx.fillEllipse(in: CGRect(x: c.x - 18, y: hole.minY - 10, width: 36, height: 30))
            ctx.restoreGState()
            ctx.strokeEllipse(in: hole)
        case .smile:
            let grin = CGMutablePath()
            grin.move(to: CGPoint(x: c.x - 40, y: c.y - 36))
            grin.addQuadCurve(to: CGPoint(x: c.x + 40, y: c.y - 36), control: CGPoint(x: c.x, y: c.y - 92))
            grin.closeSubpath()
            ctx.addPath(grin)
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.42, 0.08, 0.16)))
            ctx.fillPath()
            ctx.saveGState()
            ctx.addPath(grin)
            ctx.clip()
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.coral))
            ctx.fillEllipse(in: CGRect(x: c.x - 20, y: c.y - 74, width: 40, height: 22))
            ctx.restoreGState()
            ctx.addPath(grin)
            ctx.strokePath()
        case .browsUp:
            ctx.strokeEllipse(in: CGRect(x: c.x - 9, y: c.y - 52, width: 18, height: 20))
        default:
            ctx.move(to: CGPoint(x: c.x - 22, y: c.y - 34))
            ctx.addQuadCurve(to: CGPoint(x: c.x, y: c.y - 30), control: CGPoint(x: c.x - 12, y: c.y - 46))
            ctx.addQuadCurve(to: CGPoint(x: c.x + 22, y: c.y - 34), control: CGPoint(x: c.x + 12, y: c.y - 46))
            ctx.strokePath()
        }

        // Whiskers.
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.ink, 0.55))
        ctx.setLineWidth(2.5)
        for side in [-1.0, 1.0] {
            for k in 0..<3 {
                let y = c.y - 34 + Double(k) * 9
                ctx.move(to: CGPoint(x: c.x + side * 50, y: y))
                ctx.addLine(to: CGPoint(x: c.x + side * 108, y: y + Double(k - 1) * 10 + 4))
            }
        }
        ctx.strokePath()
    }
}
