import CoreGraphics
import Foundation

/// Food and fruit for the face games, drawn in vector once and kept: lit from the top left, with an edge of their own colour, a
/// glint and a few considered details, so they read as one family next to each other.
enum FaceGameFood {
    typealias Tone = FaceGamePaint.Tone

    enum Kind: Int, CaseIterable {
        case pizza, burger, donut, apple, cookie, strawberry, watermelon, cherries, banana, grapes, orange, pear

        /// The colour of its juice or crumbs, for the particles when it is eaten.
        var juice: Tone {
            switch self {
            case .pizza: return Tone(1, 0.78, 0.3)
            case .burger: return Tone(0.85, 0.6, 0.3)
            case .donut: return Tone(1, 0.55, 0.72)
            case .apple: return Tone(0.95, 0.25, 0.25)
            case .cookie: return Tone(0.82, 0.58, 0.32)
            case .strawberry: return Tone(0.95, 0.2, 0.3)
            case .watermelon: return Tone(1, 0.35, 0.4)
            case .cherries: return Tone(0.85, 0.1, 0.2)
            case .banana: return Tone(1, 0.88, 0.4)
            case .grapes: return Tone(0.6, 0.35, 0.85)
            case .orange: return Tone(1, 0.6, 0.15)
            case .pear: return Tone(0.7, 0.85, 0.3)
            }
        }
    }

    /// The picture of a food, 160 pixels square with the food filling most of it.
    static func sprite(_ kind: Kind) -> CGImage? {
        FaceGameArt.sprite("food-\(kind)", width: 160, height: 160) { ctx, _ in
            switch kind {
            case .pizza: pizza(ctx)
            case .burger: burger(ctx)
            case .donut: donut(ctx)
            case .apple: apple(ctx)
            case .cookie: cookie(ctx)
            case .strawberry: strawberry(ctx)
            case .watermelon: watermelon(ctx)
            case .cherries: cherries(ctx)
            case .banana: banana(ctx)
            case .grapes: grapes(ctx)
            case .orange: orange(ctx)
            case .pear: pear(ctx)
            }
        }
    }

    // MARK: Pieces

    private static func leaf(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, width: Double, tone: Tone = FaceGamePalette.leaf) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        let nx = -dy / len * width, ny = dx / len * width
        let path = CGMutablePath()
        path.move(to: a)
        path.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2 + nx, y: (a.y + b.y) / 2 + ny))
        path.addQuadCurve(to: a, control: CGPoint(x: (a.x + b.x) / 2 - nx, y: (a.y + b.y) / 2 - ny))
        path.closeSubpath()
        FaceGameArt.fillLit(ctx, path, tone: tone, edgeWidth: 3)
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: tone), 0.7))
        ctx.setLineWidth(2)
        ctx.move(to: a)
        ctx.addLine(to: CGPoint(x: a.x + dx * 0.8, y: a.y + dy * 0.8))
        ctx.strokePath()
    }

    private static func stem(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, bend: Double, width: Double = 6) {
        ctx.setLineCap(.round)
        let control = CGPoint(x: (a.x + b.x) / 2 + bend, y: (a.y + b.y) / 2)
        for (w, tone) in [(width + 3, Tone(0.24, 0.14, 0.08)), (width, Tone(0.5, 0.32, 0.16))] {
            ctx.setStrokeColor(FaceGamePaint.cg(tone))
            ctx.setLineWidth(CGFloat(w))
            ctx.move(to: a)
            ctx.addQuadCurve(to: b, control: control)
            ctx.strokePath()
        }
    }

    private static func circle(_ c: CGPoint, _ r: Double, clockwise: Bool = false) -> CGMutablePath {
        let p = CGMutablePath()
        p.addArc(center: c, radius: CGFloat(r), startAngle: 0, endAngle: 2 * .pi, clockwise: clockwise)
        p.closeSubpath()
        return p
    }

    // MARK: Fruit

    private static func apple(_ ctx: CGContext) {
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 80, y: 24))
        body.addCurve(to: CGPoint(x: 22, y: 82), control1: CGPoint(x: 52, y: 12), control2: CGPoint(x: 20, y: 42))
        body.addCurve(to: CGPoint(x: 78, y: 126), control1: CGPoint(x: 24, y: 122), control2: CGPoint(x: 56, y: 136))
        body.addCurve(to: CGPoint(x: 138, y: 82), control1: CGPoint(x: 102, y: 136), control2: CGPoint(x: 136, y: 122))
        body.addCurve(to: CGPoint(x: 80, y: 24), control1: CGPoint(x: 140, y: 42), control2: CGPoint(x: 108, y: 12))
        body.closeSubpath()
        FaceGameArt.fillLit(ctx, body, tone: Tone(0.9, 0.17, 0.2), edgeWidth: 4)
        // A blush of yellow-green near the top, like a real apple.
        FaceGamePaint.spark(ctx, at: CGPoint(x: 104, y: 112), radius: 26, tone: Tone(1, 0.7, 0.3), alpha: 0.35)
        stem(ctx, from: CGPoint(x: 79, y: 118), to: CGPoint(x: 86, y: 148), bend: -6)
        leaf(ctx, from: CGPoint(x: 86, y: 136), to: CGPoint(x: 124, y: 150), width: 11)
        FaceGameArt.highlight(ctx, center: CGPoint(x: 50, y: 100), width: 28, height: 15, rotation: 0.9, alpha: 0.75)
        FaceGameArt.highlight(ctx, center: CGPoint(x: 42, y: 78), width: 9, height: 7, alpha: 0.6)
    }

    private static func pear(_ ctx: CGContext) {
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 80, y: 18))
        body.addCurve(to: CGPoint(x: 30, y: 62), control1: CGPoint(x: 48, y: 18), control2: CGPoint(x: 28, y: 36))
        body.addCurve(to: CGPoint(x: 66, y: 118), control1: CGPoint(x: 32, y: 88), control2: CGPoint(x: 60, y: 96))
        body.addCurve(to: CGPoint(x: 94, y: 118), control1: CGPoint(x: 70, y: 136), control2: CGPoint(x: 90, y: 136))
        body.addCurve(to: CGPoint(x: 130, y: 62), control1: CGPoint(x: 100, y: 96), control2: CGPoint(x: 128, y: 88))
        body.addCurve(to: CGPoint(x: 80, y: 18), control1: CGPoint(x: 132, y: 36), control2: CGPoint(x: 112, y: 18))
        body.closeSubpath()
        FaceGameArt.fillLit(ctx, body, tone: Tone(0.66, 0.84, 0.28), edgeWidth: 4)
        FaceGamePaint.spark(ctx, at: CGPoint(x: 108, y: 54), radius: 24, tone: Tone(1, 0.55, 0.3), alpha: 0.3)
        stem(ctx, from: CGPoint(x: 80, y: 126), to: CGPoint(x: 88, y: 150), bend: -5)
        leaf(ctx, from: CGPoint(x: 86, y: 140), to: CGPoint(x: 118, y: 132), width: 9)
        FaceGameArt.highlight(ctx, center: CGPoint(x: 54, y: 66), width: 24, height: 14, rotation: 1.0, alpha: 0.7)
    }

    private static func orange(_ ctx: CGContext) {
        let c = CGPoint(x: 80, y: 74)
        FaceGameArt.litBall(ctx, center: c, radius: 58, tone: Tone(1, 0.56, 0.12), edgeWidth: 4, gloss: 0)
        // The dimpled peel: tiny darker pits, only on the body.
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - 54, y: c.y - 54, width: 108, height: 108))
        ctx.clip()
        ctx.setFillColor(FaceGamePaint.cg(Tone(0.75, 0.3, 0.02), 0.28))
        for i in 0..<46 {
            let a = FaceGamePaint.hash(i, 1) * 2 * .pi, d = sqrt(FaceGamePaint.hash(i, 2)) * 52
            ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * d - 1.6, y: c.y + sin(a) * d - 1.6, width: 3.2, height: 3.2))
        }
        ctx.restoreGState()
        FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 22, y: c.y + 26), width: 32, height: 17, rotation: 0.6, alpha: 0.65)
        ctx.setFillColor(FaceGamePaint.cg(Tone(0.3, 0.45, 0.12)))
        ctx.fillEllipse(in: CGRect(x: 75, y: 127, width: 10, height: 8))
        leaf(ctx, from: CGPoint(x: 82, y: 131), to: CGPoint(x: 120, y: 146), width: 10)
    }

    private static func cherries(_ ctx: CGContext) {
        let red = Tone(0.82, 0.08, 0.18)
        let left = CGPoint(x: 52, y: 50), right = CGPoint(x: 106, y: 44)
        stem(ctx, from: CGPoint(x: left.x + 4, y: left.y + 26), to: CGPoint(x: 96, y: 142), bend: -18, width: 5)
        stem(ctx, from: CGPoint(x: right.x - 2, y: right.y + 26), to: CGPoint(x: 96, y: 142), bend: 10, width: 5)
        leaf(ctx, from: CGPoint(x: 96, y: 140), to: CGPoint(x: 132, y: 124), width: 10)
        for p in [left, right] {
            FaceGameArt.litBall(ctx, center: p, radius: 30, tone: red, edgeWidth: 3.5, gloss: 0.8)
        }
    }

    private static func strawberry(_ ctx: CGContext) {
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 80, y: 16))
        body.addCurve(to: CGPoint(x: 24, y: 94), control1: CGPoint(x: 52, y: 20), control2: CGPoint(x: 20, y: 60))
        body.addCurve(to: CGPoint(x: 80, y: 124), control1: CGPoint(x: 28, y: 122), control2: CGPoint(x: 58, y: 126))
        body.addCurve(to: CGPoint(x: 136, y: 94), control1: CGPoint(x: 102, y: 126), control2: CGPoint(x: 132, y: 122))
        body.addCurve(to: CGPoint(x: 80, y: 16), control1: CGPoint(x: 140, y: 60), control2: CGPoint(x: 108, y: 20))
        body.closeSubpath()
        FaceGameArt.fillLit(ctx, body, tone: Tone(0.92, 0.15, 0.24), edgeWidth: 4)
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        for row in 0..<6 {
            for col in 0..<6 {
                let x = 34 + Double(col) * 18 + (row % 2 == 0 ? 0 : 9), y = 32 + Double(row) * 16
                ctx.setFillColor(FaceGamePaint.cg(Tone(0.5, 0.04, 0.1), 0.35))
                ctx.fillEllipse(in: CGRect(x: x - 3, y: y - 4.5, width: 6.5, height: 9))
                ctx.setFillColor(FaceGamePaint.cg(Tone(1, 0.86, 0.42)))
                ctx.fillEllipse(in: CGRect(x: x - 2, y: y - 2.5, width: 4, height: 6))
            }
        }
        ctx.restoreGState()
        for k in 0..<5 {
            let a = .pi / 2 + (Double(k) - 2) * 0.62
            leaf(ctx, from: CGPoint(x: 80, y: 122), to: CGPoint(x: 80 + cos(a - .pi / 2 * 0.0) * 34 * (k == 2 ? 0.7 : 1), y: 122 + sin(a) * 18 - 6), width: 7)
        }
        stem(ctx, from: CGPoint(x: 80, y: 124), to: CGPoint(x: 84, y: 146), bend: 4, width: 5)
        FaceGameArt.highlight(ctx, center: CGPoint(x: 48, y: 90), width: 22, height: 12, rotation: 1.1, alpha: 0.7)
    }

    private static func watermelon(_ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 80, y: 84)
        ctx.rotate(by: -0.28)
        func half(_ r: Double) -> CGMutablePath {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -r, y: 8))
            p.addArc(center: CGPoint(x: 0, y: 8), radius: CGFloat(r), startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
            p.closeSubpath()
            return p
        }
        FaceGameArt.fillLit(ctx, half(66), tone: Tone(0.16, 0.56, 0.24), edgeWidth: 4)
        FaceGameArt.fillLit(ctx, half(57), tone: Tone(0.8, 0.95, 0.6), edgeWidth: 0)
        FaceGameArt.fillLit(ctx, half(52), tone: Tone(0.98, 0.3, 0.36), edgeWidth: 0)
        ctx.setFillColor(FaceGamePaint.cg(Tone(1, 0.6, 0.6), 0.5))
        ctx.fill(CGRect(x: -52, y: 4, width: 104, height: 4))
        for (x, y) in [(-26.0, -14.0), (0.0, -24.0), (26.0, -14.0), (-12.0, -36.0), (14.0, -36.0), (-38.0, -2.0), (38.0, -2.0)] {
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.12, 0.08, 0.1)))
            ctx.fillEllipse(in: CGRect(x: x - 3.5, y: y - 5, width: 7, height: 10))
            ctx.setFillColor(FaceGamePaint.cg(Tone(1, 1, 1), 0.4))
            ctx.fillEllipse(in: CGRect(x: x - 2, y: y + 0.5, width: 2.5, height: 3))
        }
        ctx.restoreGState()
    }

    private static func banana(_ ctx: CGContext) {
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 18, y: 104))
        body.addCurve(to: CGPoint(x: 140, y: 110), control1: CGPoint(x: 34, y: 26), control2: CGPoint(x: 120, y: 18))
        body.addCurve(to: CGPoint(x: 18, y: 104), control1: CGPoint(x: 112, y: 64), control2: CGPoint(x: 46, y: 62))
        body.closeSubpath()
        FaceGameArt.fillLit(ctx, body, tone: Tone(1, 0.84, 0.26), edgeWidth: 4)
        ctx.setStrokeColor(FaceGamePaint.cg(Tone(1, 0.97, 0.7), 0.7))
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 34, y: 82))
        ctx.addCurve(to: CGPoint(x: 122, y: 82), control1: CGPoint(x: 48, y: 46), control2: CGPoint(x: 104, y: 42))
        ctx.strokePath()
        ctx.setFillColor(FaceGamePaint.cg(Tone(0.36, 0.22, 0.1)))
        ctx.fillEllipse(in: CGRect(x: 12, y: 98, width: 12, height: 12))
        ctx.addPath(FaceGamePaint.roundedPath(CGRect(x: 134, y: 104, width: 12, height: 22), radius: 4))
        ctx.fillPath()
    }

    private static func grapes(_ ctx: CGContext) {
        let tone = Tone(0.52, 0.28, 0.78)
        let rows: [[Double]] = [[-36, 0, 36], [-18, 18], [-36, 0, 36], [-18, 18], [0]]
        var balls: [CGPoint] = []
        for (r, xs) in rows.enumerated() { for x in xs { balls.append(CGPoint(x: 80 + x, y: 116 - Double(r) * 22)) } }
        stem(ctx, from: CGPoint(x: 80, y: 128), to: CGPoint(x: 86, y: 150), bend: 6, width: 5)
        leaf(ctx, from: CGPoint(x: 84, y: 140), to: CGPoint(x: 126, y: 146), width: 12)
        for p in balls { FaceGameArt.litBall(ctx, center: p, radius: 19, tone: tone, edgeWidth: 3, gloss: 0.7) }
    }

    // MARK: Treats

    private static func pizza(_ ctx: CGContext) {
        let slice = CGMutablePath()
        slice.move(to: CGPoint(x: 80, y: 14))
        slice.addLine(to: CGPoint(x: 22, y: 118))
        slice.addQuadCurve(to: CGPoint(x: 138, y: 118), control: CGPoint(x: 80, y: 134))
        slice.closeSubpath()
        FaceGameArt.fillLit(ctx, slice, tone: Tone(1, 0.8, 0.32), edgeWidth: 4, edgeTone: Tone(0.72, 0.42, 0.12))
        // Melted cheese drips over the edges.
        ctx.setFillColor(FaceGamePaint.cg(Tone(1, 0.78, 0.3)))
        for (x, y, r) in [(52.0, 66.0, 7.0), (106.0, 72.0, 6.0)] { ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 1.6, width: r * 2, height: r * 2.4)) }
        for (x, y, r) in [(80.0, 92.0, 14.0), (62.0, 60.0, 11.0), (96.0, 50.0, 10.0), (78.0, 34.0, 8.0)] {
            FaceGameArt.litBall(ctx, center: CGPoint(x: x, y: y), radius: r, tone: Tone(0.8, 0.18, 0.16), edgeWidth: 2.5, gloss: 0.5)
        }
        ctx.setFillColor(FaceGamePaint.cg(Tone(0.24, 0.55, 0.2)))
        for (x, y) in [(70.0, 76.0), (100.0, 86.0), (88.0, 66.0), (60.0, 96.0)] {
            ctx.fillEllipse(in: CGRect(x: x - 3, y: y - 2, width: 6, height: 4))
        }
        let crust = FaceGamePaint.roundedPath(CGRect(x: 14, y: 108, width: 132, height: 30), radius: 15)
        FaceGameArt.fillLit(ctx, crust, tone: Tone(0.88, 0.56, 0.24), edgeWidth: 4)
        FaceGameArt.highlight(ctx, center: CGPoint(x: 52, y: 128), width: 40, height: 8, alpha: 0.5)
    }

    private static func burger(_ ctx: CGContext) {
        let bun = Tone(0.93, 0.62, 0.26)
        FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: 22, y: 20, width: 116, height: 28), radius: 13), tone: bun, edgeWidth: 4)
        FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: 18, y: 44, width: 124, height: 26), radius: 12), tone: Tone(0.45, 0.24, 0.14), edgeWidth: 4)
        // Cheese with a drip.
        let cheese = CGMutablePath()
        cheese.move(to: CGPoint(x: 20, y: 70))
        cheese.addLine(to: CGPoint(x: 140, y: 70))
        cheese.addLine(to: CGPoint(x: 140, y: 64))
        cheese.addLine(to: CGPoint(x: 104, y: 64))
        cheese.addLine(to: CGPoint(x: 96, y: 50))
        cheese.addLine(to: CGPoint(x: 88, y: 64))
        cheese.addLine(to: CGPoint(x: 20, y: 64))
        cheese.closeSubpath()
        FaceGameArt.fillLit(ctx, cheese, tone: Tone(1, 0.8, 0.22), edgeWidth: 3)
        // Lettuce: a wavy green band.
        let lettuce = CGMutablePath()
        lettuce.move(to: CGPoint(x: 16, y: 74))
        for i in 0...8 { lettuce.addQuadCurve(to: CGPoint(x: 16 + Double(i + 1) * 16, y: 74), control: CGPoint(x: 24 + Double(i) * 16, y: i % 2 == 0 ? 62 : 84)) }
        lettuce.addLine(to: CGPoint(x: 144, y: 84))
        lettuce.addLine(to: CGPoint(x: 16, y: 84))
        lettuce.closeSubpath()
        FaceGameArt.fillLit(ctx, lettuce, tone: Tone(0.42, 0.8, 0.3), edgeWidth: 3)
        let top = CGMutablePath()
        top.move(to: CGPoint(x: 20, y: 82))
        top.addCurve(to: CGPoint(x: 140, y: 82), control1: CGPoint(x: 20, y: 148), control2: CGPoint(x: 140, y: 148))
        top.closeSubpath()
        FaceGameArt.fillLit(ctx, top, tone: bun, edgeWidth: 4)
        for (x, y, a) in [(54.0, 116.0, 0.4), (78.0, 126.0, -0.2), (102.0, 114.0, 0.7), (66.0, 100.0, -0.6), (94.0, 98.0, 0.2), (118.0, 98.0, -0.3), (40.0, 96.0, 0.3)] {
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: CGFloat(a))
            ctx.setFillColor(FaceGamePaint.cg(Tone(1, 0.95, 0.8)))
            ctx.fillEllipse(in: CGRect(x: -4, y: -2.2, width: 8, height: 4.4))
            ctx.restoreGState()
        }
        FaceGameArt.highlight(ctx, center: CGPoint(x: 52, y: 122), width: 34, height: 14, rotation: 0.4, alpha: 0.55)
    }

    private static func donut(_ ctx: CGContext) {
        let c = CGPoint(x: 80, y: 78)
        let dough = circle(c, 60)
        dough.addPath(circle(c, 18, clockwise: true))
        FaceGameArt.fillLit(ctx, dough, tone: Tone(0.9, 0.62, 0.32), edgeWidth: 4)
        var radii: [Double] = []
        for i in 0..<14 { radii.append(52 + 5 * sin(Double(i) * 2.1)) }
        let icing = CGMutablePath()
        icing.addPath(FaceGameArt.blob(center: c, radii: radii, rotation: 0.2))
        icing.addPath(circle(c, 24, clockwise: true))
        FaceGameArt.fillLit(ctx, icing, tone: Tone(1, 0.54, 0.72), edgeWidth: 3)
        let tones = [FaceGamePalette.sun, FaceGamePalette.sky, FaceGamePalette.mint, FaceGamePalette.cream, FaceGamePalette.grape]
        ctx.setLineCap(.round)
        ctx.setLineWidth(4)
        for i in 0..<22 {
            let a = FaceGamePaint.hash(i, 3) * 2 * .pi, d = 30 + FaceGamePaint.hash(i, 4) * 18
            let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
            let turn = FaceGamePaint.hash(i, 5) * .pi
            ctx.setStrokeColor(FaceGamePaint.cg(tones[i % tones.count]))
            ctx.move(to: CGPoint(x: p.x - cos(turn) * 4, y: p.y - sin(turn) * 4))
            ctx.addLine(to: CGPoint(x: p.x + cos(turn) * 4, y: p.y + sin(turn) * 4))
            ctx.strokePath()
        }
        FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 28, y: c.y + 30), width: 30, height: 14, rotation: 0.7, alpha: 0.6)
    }

    private static func cookie(_ ctx: CGContext) {
        let c = CGPoint(x: 80, y: 78)
        var radii: [Double] = []
        for i in 0..<16 { radii.append(58 + 3.5 * sin(Double(i) * 2.7) + 2 * cos(Double(i) * 5.1)) }
        FaceGameArt.fillLit(ctx, FaceGameArt.blob(center: c, radii: radii), tone: Tone(0.86, 0.6, 0.32), edgeWidth: 4)
        for (x, y, r) in [(-24.0, 20.0, 10.0), (14.0, 28.0, 8.0), (26.0, -6.0, 11.0), (-10.0, -24.0, 9.0), (-30.0, -14.0, 7.0), (6.0, 2.0, 7.0), (30.0, -32.0, 6.0)] {
            var chip: [Double] = []
            for k in 0..<7 { chip.append(r * (0.85 + 0.25 * FaceGamePaint.hash(Int(x * 7 + y) + k, 9))) }
            FaceGameArt.fillLit(ctx, FaceGameArt.blob(center: CGPoint(x: c.x + x, y: c.y + y), radii: chip), tone: Tone(0.3, 0.16, 0.1), edgeWidth: 2)
        }
        FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 26, y: c.y + 32), width: 30, height: 12, rotation: 0.7, alpha: 0.4)
    }

    // MARK: Bonus and danger

    /// A golden star with a ring of light: worth more than anything else.
    static var golden: CGImage? {
        FaceGameArt.sprite("food-golden", width: 160, height: 160) { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            FaceGamePaint.spark(ctx, at: c, radius: 78, tone: FaceGamePalette.sun, alpha: 0.55)
            let path = FaceGameArt.star(center: c, radius: 62, inner: 0.5, round: true)
            FaceGameArt.fillLit(ctx, path, tone: Tone(1, 0.78, 0.18), edgeWidth: 5, edgeTone: Tone(0.66, 0.36, 0.04))
            let inner = FaceGameArt.star(center: CGPoint(x: c.x, y: c.y + 2), radius: 40, inner: 0.5, round: true)
            ctx.addPath(inner)
            ctx.setStrokeColor(FaceGamePaint.cg(Tone(1, 0.95, 0.65), 0.7))
            ctx.setLineWidth(3)
            ctx.strokePath()
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 16, y: c.y + 24), width: 30, height: 16, rotation: 0.6, alpha: 0.85)
        }
    }

    /// Where on the bomb picture the fuse ends, as a fraction of its size from the middle, for the spark.
    static let fuseTip = CGPoint(x: 0.36, y: 0.44)

    /// A round black bomb with a metal cap and a fuse. The burning spark is drawn live on top.
    static var bomb: CGImage? {
        FaceGameArt.sprite("food-bomb", width: 160, height: 160) { ctx, _ in
            let c = CGPoint(x: 74, y: 68)
            FaceGameArt.litBall(ctx, center: c, radius: 54, tone: Tone(0.2, 0.21, 0.32), edgeWidth: 4, gloss: 0)
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 22, y: c.y + 24), width: 34, height: 18, rotation: 0.7, alpha: 0.55)
            ctx.saveGState()
            ctx.translateBy(x: c.x + 30, y: c.y + 42)
            ctx.rotate(by: -0.6)
            FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: -15, y: -8, width: 30, height: 20), radius: 5), tone: Tone(0.66, 0.68, 0.78), edgeWidth: 3)
            ctx.restoreGState()
            ctx.setLineCap(.round)
            for (w, tone) in [(9.0, Tone(0.3, 0.2, 0.1)), (5.0, Tone(0.86, 0.72, 0.48))] {
                ctx.setStrokeColor(FaceGamePaint.cg(tone))
                ctx.setLineWidth(CGFloat(w))
                ctx.move(to: CGPoint(x: c.x + 38, y: c.y + 54))
                ctx.addCurve(to: CGPoint(x: 80 + 160 * fuseTip.x, y: 80 + 160 * fuseTip.y),
                             control1: CGPoint(x: c.x + 52, y: c.y + 72), control2: CGPoint(x: 120, y: 132))
                ctx.strokePath()
            }
        }
    }
}
