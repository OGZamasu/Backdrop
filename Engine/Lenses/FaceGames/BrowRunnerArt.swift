import CoreGraphics
import Foundation

/// Brow Runner's obstacles, drawn once per shape and kept: ribbed cacti, nailed crates and glassy puddles, lit like the rest of
/// the face games.
enum BrowRunnerArt {
    typealias Tone = FaceGamePaint.Tone

    static let cactusGreen = Tone(0.3, 0.68, 0.36)

    /// A cactus `height` pixels tall above the ground line, with arms on the left and/or right. The ground line is 12 pixels up
    /// from the bottom of the picture, which is 100 pixels wide and centred on the trunk.
    static func cactus(height: Double, left: Bool, right: Bool) -> CGImage? {
        let h = (height / 2).rounded() * 2
        return FaceGameArt.sprite("runner-cactus-\(Int(h))-\(left)-\(right)", width: 100, height: Int(h) + 40) { ctx, size in
            let x = size.width / 2, base = 12.0
            let shape = CGMutablePath()
            shape.addPath(FaceGamePaint.roundedPath(CGRect(x: x - 17, y: base - 8, width: 34, height: h + 8), radius: 17))
            if left {
                shape.addPath(FaceGamePaint.roundedPath(CGRect(x: x - 42, y: base + h * 0.36, width: 34, height: 15), radius: 7.5))
                shape.addPath(FaceGamePaint.roundedPath(CGRect(x: x - 42, y: base + h * 0.36, width: 15, height: h * 0.34), radius: 7.5))
            }
            if right {
                shape.addPath(FaceGamePaint.roundedPath(CGRect(x: x + 8, y: base + h * 0.5, width: 34, height: 15), radius: 7.5))
                shape.addPath(FaceGamePaint.roundedPath(CGRect(x: x + 27, y: base + h * 0.5, width: 15, height: h * 0.3), radius: 7.5))
            }
            // The edge goes down first and wide, so where the arms meet the trunk there is no seam.
            ctx.addPath(shape)
            ctx.setLineWidth(7)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: cactusGreen)))
            ctx.strokePath()
            FaceGameArt.fillLit(ctx, shape, tone: cactusGreen)
            // Ribs down the trunk and a highlight on the lit side.
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: cactusGreen), 0.35))
            ctx.setLineWidth(2)
            for dx in [-7.0, 6.0] {
                ctx.move(to: CGPoint(x: x + dx, y: base))
                ctx.addLine(to: CGPoint(x: x + dx, y: base + h - 10))
            }
            ctx.strokePath()
            ctx.restoreGState()
            FaceGameArt.highlight(ctx, center: CGPoint(x: x - 9, y: base + h * 0.55), width: 8, height: h * 0.7, alpha: 0.4)
            // Spines.
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.cream, 0.9))
            ctx.setLineWidth(1.6)
            ctx.setLineCap(.round)
            for k in 0..<max(2, Int(h / 18)) {
                let y = base + 10 + Double(k) * 18
                for side in [-1.0, 1.0] {
                    ctx.move(to: CGPoint(x: x + side * 16, y: y + (side > 0 ? 9 : 0)))
                    ctx.addLine(to: CGPoint(x: x + side * 22, y: y + (side > 0 ? 11 : 2)))
                }
            }
            ctx.strokePath()
            if h > 68 {
                let top = CGPoint(x: x, y: base + h + 2)
                for k in 0..<5 {
                    let a = Double(k) / 5 * 2 * .pi + 0.3
                    FaceGameArt.fillLit(ctx, CGPath(ellipseIn: CGRect(x: top.x + cos(a) * 6 - 5, y: top.y + sin(a) * 6 - 5, width: 10, height: 10), transform: nil),
                                        tone: FaceGamePalette.bubblegum, edgeWidth: 1.5)
                }
                ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.sun))
                ctx.fillEllipse(in: CGRect(x: top.x - 3.5, y: top.y - 3.5, width: 7, height: 7))
            }
        }
    }

    /// One crate, 72 pixels square with 4 pixels of room around it.
    static var crate: CGImage? {
        FaceGameArt.sprite("runner-crate", width: 80, height: 80) { ctx, _ in
            let wood = Tone(0.88, 0.62, 0.32), plank = Tone(0.66, 0.42, 0.2)
            let box = CGRect(x: 6, y: 6, width: 68, height: 68)
            FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(box, radius: 6), tone: wood, edgeWidth: 4)
            ctx.saveGState()
            ctx.addPath(FaceGamePaint.roundedPath(box, radius: 6))
            ctx.clip()
            // Grain.
            ctx.setStrokeColor(FaceGamePaint.cg(plank, 0.35))
            ctx.setLineWidth(1.5)
            for k in 0..<6 {
                let y = box.minY + 14 + Double(k) * 8
                ctx.move(to: CGPoint(x: box.minX, y: y))
                ctx.addCurve(to: CGPoint(x: box.maxX, y: y + 2), control1: CGPoint(x: box.minX + 20, y: y + 4), control2: CGPoint(x: box.maxX - 24, y: y - 3))
            }
            ctx.strokePath()
            // The frame and the brace, each lit.
            let band = 11.0
            for rect in [CGRect(x: box.minX, y: box.minY, width: box.width, height: band), CGRect(x: box.minX, y: box.maxY - band, width: box.width, height: band),
                         CGRect(x: box.minX, y: box.minY, width: band, height: box.height), CGRect(x: box.maxX - band, y: box.minY, width: band, height: box.height)] {
                FaceGameArt.fillLit(ctx, CGPath(rect: rect, transform: nil), tone: plank, edgeWidth: 2)
            }
            let brace = CGMutablePath()
            brace.move(to: CGPoint(x: box.minX + band - 2, y: box.minY + band + 4))
            brace.addLine(to: CGPoint(x: box.minX + band + 4, y: box.minY + band - 2))
            brace.addLine(to: CGPoint(x: box.maxX - band + 2, y: box.maxY - band - 4))
            brace.addLine(to: CGPoint(x: box.maxX - band - 4, y: box.maxY - band + 2))
            brace.closeSubpath()
            FaceGameArt.fillLit(ctx, brace, tone: plank, edgeWidth: 2)
            ctx.restoreGState()
            for (dx, dy) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
                FaceGameArt.litBall(ctx, center: CGPoint(x: box.minX + 5.5 + dx * (box.width - 11), y: box.minY + 5.5 + dy * (box.height - 11)), radius: 3,
                                    tone: Tone(0.8, 0.8, 0.85), gloss: 0.5)
            }
        }
    }

    /// A puddle `width` pixels across and 34 tall, with 6 pixels of room around it.
    static func puddle(width: Double) -> CGImage? {
        let w = Int(width.rounded())
        return FaceGameArt.sprite("runner-puddle-\(w)", width: w + 12, height: 46) { ctx, _ in
            let rect = CGRect(x: 6, y: 6, width: Double(w), height: 34)
            let water = FaceGamePalette.sky * 0.85
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.4, 0.28, 0.18)))
            ctx.fillEllipse(in: rect.insetBy(dx: -3, dy: -3))
            FaceGameArt.fillLit(ctx, CGPath(ellipseIn: rect, transform: nil), tone: water, edgeWidth: 3, edgeTone: Tone(0.08, 0.26, 0.5))
            FaceGameArt.highlight(ctx, center: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.midY + 6), width: rect.width * 0.34, height: 7, alpha: 0.75)
            FaceGameArt.highlight(ctx, center: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.midY + 9), width: rect.width * 0.12, height: 4, alpha: 0.6)
        }
    }
}
