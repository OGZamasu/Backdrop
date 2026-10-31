import CoreGraphics
import Foundation

/// The look of Flappy Face: drifting clouds and rolling hills that slide by at their own speeds, lit pipes with caps and moss,
/// a scrolling strip of ground, and the bird whose head is your face. Every piece is drawn once and kept.
enum FlappyFaceArt {
    typealias Tone = FaceGamePaint.Tone

    /// The pipes' green, a little fresher than grass.
    static let pipeGreen = Tone(0.36, 0.78, 0.36)
    static let feather = Tone(1, 0.8, 0.22)
    static let beak = Tone(1, 0.52, 0.18)

    // MARK: Backdrop

    /// A fluffy cloud lit from above, in two shapes and two sizes. Brow Runner's sky uses them too.
    static func cloud(_ variant: Int, small: Bool) -> CGImage? {
        let scale = small ? 0.7 : 1.0
        return FaceGameArt.sprite("flappy-cloud-\(variant)-\(small)", width: Int(260 * scale), height: Int(130 * scale)) { ctx, _ in
            ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            let size = CGSize(width: 260, height: 130)
            let puffs: [(Double, Double, Double)] = variant == 0
                ? [(70, 52, 38), (118, 70, 50), (170, 58, 40), (205, 44, 28), (40, 40, 26)]
                : [(60, 46, 30), (104, 62, 42), (152, 66, 46), (196, 48, 30)]
            let body = CGMutablePath()
            for (x, y, r) in puffs { body.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
            body.addPath(FaceGamePaint.roundedPath(CGRect(x: 26, y: 18, width: 204, height: 36), radius: 18))
            ctx.addPath(body)
            ctx.setStrokeColor(FaceGamePaint.cg(Tone(0.66, 0.74, 0.9), 0.7))
            ctx.setLineWidth(4)
            ctx.strokePath()
            ctx.saveGState()
            ctx.addPath(body)
            ctx.clip()
            if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: [FaceGamePaint.cg(Tone(1, 1, 1)), FaceGamePaint.cg(Tone(0.86, 0.9, 1))] as CFArray,
                                  locations: [0.4, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 14), options: [])
            }
            ctx.restoreGState()
        }
    }

    /// One repeat of the far hills: soft teal humps with a few round trees, lit from the top left.
    private static var hills: CGImage? {
        FaceGameArt.sprite("flappy-hills", width: 640, height: 150) { ctx, size in
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            var x = 0.0
            while x <= size.width {
                path.addLine(to: CGPoint(x: x, y: 70 + 34 * sin(x / size.width * 2 * .pi * 2 + 0.6) + 16 * sin(x / size.width * 2 * .pi * 5)))
                x += 8
            }
            path.addLine(to: CGPoint(x: size.width, y: 0))
            path.closeSubpath()
            FaceGameArt.fillLit(ctx, path, tone: Tone(0.38, 0.72, 0.62), edgeWidth: 0)
            for i in 0..<7 {
                let tx = 40 + Double(i) * 88 + 20 * FaceGamePaint.hash(i, 3)
                let base = 70 + 34 * sin(tx / size.width * 2 * .pi * 2 + 0.6) + 16 * sin(tx / size.width * 2 * .pi * 5)
                let r = 16 + 9 * FaceGamePaint.hash(i, 4)
                ctx.setFillColor(FaceGamePaint.cg(Tone(0.24, 0.42, 0.36)))
                ctx.fill(CGRect(x: tx - 3, y: base - 6, width: 6, height: r * 0.8))
                FaceGameArt.litBall(ctx, center: CGPoint(x: tx, y: base + r * 0.9), radius: r, tone: Tone(0.3, 0.62, 0.5), gloss: 0)
            }
        }
    }

    /// One repeat of the near bushes, darker and quicker than the hills.
    private static var bushes: CGImage? {
        FaceGameArt.sprite("flappy-bushes", width: 512, height: 90) { ctx, _ in
            let tone = Tone(0.26, 0.6, 0.34)
            let path = CGMutablePath()
            for i in 0..<9 {
                let x = Double(i) * 64 + 16 * FaceGamePaint.hash(i, 7)
                let r = 26 + 14 * FaceGamePaint.hash(i, 8)
                path.addEllipse(in: CGRect(x: x - r, y: 30 - r * 0.4, width: r * 2, height: r * 1.7))
            }
            path.addRect(CGRect(x: -10, y: 0, width: 532, height: 34))
            FaceGameArt.fillLit(ctx, path, tone: tone, edgeWidth: 0)
        }
    }

    static func drawBackdrop(_ ctx: CGContext, size: CGSize, travelled: Double, time: Double) {
        for i in 0..<5 {
            let speed = i < 2 ? 0.08 : 0.16
            let span = size.width + 400
            let x = FaceGamePaint.wrap(Double(i) * span / 5 + 160 * FaceGamePaint.hash(i, 1) - travelled * speed - time * 8, span) - 200
            let y = size.height * (0.62 + 0.24 * FaceGamePaint.hash(i, 2))
            guard let image = cloud(i % 2, small: i < 2) else { continue }
            FaceGameArt.blit(ctx, image, at: CGPoint(x: x - Double(image.width) / 2, y: y - Double(image.height) / 2), alpha: i < 2 ? 0.55 : 0.8)
        }
        tile(ctx, hills, y: groundTop - 6, scroll: travelled * 0.25, size: size, alpha: 0.92)
        tile(ctx, bushes, y: groundTop - 4, scroll: travelled * 0.55, size: size, alpha: 1)
    }

    private static let groundTop = 34.0

    /// Repeats a picture across the screen at its own size, on whole pixels, so it goes down without resampling.
    private static func tile(_ ctx: CGContext, _ image: CGImage?, y: Double, scroll: Double, size: CGSize, alpha: Double) {
        guard let image else { return }
        let w = Double(image.width)
        var x = -FaceGamePaint.wrap(scroll, w).rounded()
        while x < size.width {
            FaceGameArt.blit(ctx, image, at: CGPoint(x: x, y: y), alpha: alpha)
            x += w
        }
    }

    private static var groundTile: CGImage? {
        FaceGameArt.sprite("flappy-ground", width: 96, height: 40) { ctx, size in
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.86, 0.7, 0.44)))
            ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 30))
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.78, 0.6, 0.36)))
            for k in 0..<2 {
                let x = Double(k) * 48
                let stripe = CGMutablePath()
                stripe.move(to: CGPoint(x: x, y: 0)); stripe.addLine(to: CGPoint(x: x + 20, y: 0))
                stripe.addLine(to: CGPoint(x: x + 40, y: 24)); stripe.addLine(to: CGPoint(x: x + 20, y: 24))
                stripe.closeSubpath()
                ctx.addPath(stripe)
            }
            ctx.fillPath()
            if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: [FaceGamePaint.cg(Tone(0.56, 0.86, 0.36)), FaceGamePaint.cg(Tone(0.34, 0.66, 0.24))] as CFArray,
                                  locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 40), end: CGPoint(x: 0, y: 24), options: [])
            }
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.2, 0.42, 0.16)))
            ctx.fill(CGRect(x: 0, y: 22, width: size.width, height: 3))
        }
    }

    static func drawGround(_ ctx: CGContext, size: CGSize, height: Double, travelled: Double) {
        tile(ctx, groundTile, y: 0, scroll: travelled, size: size, alpha: 1)
    }

    // MARK: Pipes

    private static func pipeGradient() -> CGGradient? {
        let edge = FaceGameArt.edge(of: pipeGreen)
        let colors = [edge, pipeGreen, FaceGameArt.lighter(pipeGreen, 0.55), pipeGreen, pipeGreen * 0.72, edge].map { FaceGamePaint.cg($0) } as CFArray
        return CGGradient(colorsSpace: FaceGamePaint.space, colors: colors, locations: [0, 0.07, 0.26, 0.42, 0.88, 1])
    }

    /// The pipe's body at full screen height; each pipe shows the part it needs through a clip, so it is never resampled.
    private static var pipeBody: CGImage? {
        FaceGameArt.sprite("flappy-pipe-body", width: 120, height: 740) { ctx, size in
            if let g = pipeGradient() { ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: 0), options: []) }
        }
    }

    /// The wide lip at the end of a pipe, with moss along the top when `moss` is set; `flipped` for the pipes hanging from above.
    private static func pipeCap(moss: Bool, flipped: Bool = false) -> CGImage? {
        FaceGameArt.sprite("flappy-pipe-cap-\(moss)-\(flipped)", width: 148, height: 62) { ctx, size in
            if flipped {
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: 1, y: -1)
            }
            let rect = CGRect(x: 2, y: 4, width: 144, height: 44)
            let path = FaceGamePaint.roundedPath(rect, radius: 9)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            if let g = pipeGradient() { ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: []) }
            ctx.setFillColor(FaceGamePaint.cg(Tone(1, 1, 1), 0.22))
            ctx.fill(CGRect(x: rect.minX, y: rect.maxY - 9, width: rect.width, height: 5))
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.ink, 0.22))
            ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 7))
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: pipeGreen)))
            ctx.setLineWidth(3.5)
            ctx.strokePath()
            for x in [18.0, 130.0] {
                FaceGameArt.litBall(ctx, center: CGPoint(x: x, y: rect.midY), radius: 4.5, tone: Tone(0.8, 0.9, 0.7), gloss: 0.4)
            }
            if moss {
                let tone = Tone(0.5, 0.86, 0.32)
                let blob = CGMutablePath()
                for i in 0..<7 {
                    let x = 14 + Double(i) * 20 + 6 * FaceGamePaint.hash(i, 2)
                    let r = 8 + 5 * FaceGamePaint.hash(i, 3)
                    blob.addEllipse(in: CGRect(x: x - r, y: rect.maxY - r * 0.5, width: r * 2, height: r * 1.5))
                }
                FaceGameArt.fillLit(ctx, blob, tone: tone, edgeWidth: 2, edgeTone: Tone(0.2, 0.45, 0.16))
            }
        }
    }

    static func drawPipe(_ ctx: CGContext, x: Double, gapCenter: Double, gap: Double, width: Double, size: CGSize) {
        guard x < size.width + 40, x + width > -40 else { return }
        let lowTop = gapCenter - gap / 2, highBottom = gapCenter + gap / 2
        let capHeight = 44.0, overhang = 12.0
        let px = x.rounded()
        if let body = pipeBody {
            for clip in [CGRect(x: px, y: -10, width: width, height: lowTop - capHeight + 12),
                         CGRect(x: px, y: highBottom + capHeight - 2, width: width, height: size.height - highBottom - capHeight + 12)] where clip.height > 0 {
                ctx.saveGState()
                ctx.clip(to: clip)
                FaceGameArt.blit(ctx, body, at: CGPoint(x: px, y: -10))
                ctx.restoreGState()
            }
        }
        // The lip throws a soft shadow down the pipe below it.
        for (y, up) in [(lowTop - capHeight, false), (highBottom + capHeight, true)] {
            let colors = [FaceGamePaint.cg(FaceGamePalette.ink, 0.3), FaceGamePaint.cg(FaceGamePalette.ink, 0)] as CFArray
            if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: colors, locations: [0, 1]) {
                ctx.saveGState()
                ctx.clip(to: CGRect(x: x, y: up ? y : y - 16, width: width, height: 16))
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y), end: CGPoint(x: 0, y: up ? y + 16 : y - 16), options: [])
                ctx.restoreGState()
            }
        }
        FaceGameArt.blit(ctx, pipeCap(moss: true), at: CGPoint(x: px - overhang - 2, y: lowTop - capHeight - 4))
        FaceGameArt.blit(ctx, pipeCap(moss: false, flipped: true), at: CGPoint(x: px - overhang - 2, y: highBottom - 14))
    }

    // MARK: The bird

    private static var head: CGImage? {
        FaceGameArt.sprite("flappy-head", width: 136, height: 150) { ctx, _ in
            let c = CGPoint(x: 64, y: 66)
            // A crest of three feathers on top.
            for (dx, angle, len) in [(-10.0, 0.5, 30.0), (2.0, 0.15, 36.0), (14.0, -0.25, 28.0)] {
                ctx.saveGState()
                ctx.translateBy(x: c.x + dx, y: c.y + 46)
                ctx.rotate(by: CGFloat(angle))
                FaceGameArt.fillLit(ctx, CGPath(ellipseIn: CGRect(x: -7, y: 0, width: 14, height: len), transform: nil), tone: feather, edgeWidth: 3)
                ctx.restoreGState()
            }
            FaceGameArt.litBall(ctx, center: c, radius: 54, tone: feather, edgeWidth: 4, gloss: 0)
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 26, y: c.y + 36), width: 30, height: 14, rotation: 0.6, alpha: 0.6)
            // The beak, in two parts, to the right.
            let upper = CGMutablePath()
            upper.move(to: CGPoint(x: c.x + 44, y: c.y + 2))
            upper.addQuadCurve(to: CGPoint(x: c.x + 72, y: c.y - 8), control: CGPoint(x: c.x + 66, y: c.y + 8))
            upper.addLine(to: CGPoint(x: c.x + 46, y: c.y - 10))
            upper.closeSubpath()
            let lower = CGMutablePath()
            lower.move(to: CGPoint(x: c.x + 46, y: c.y - 10))
            lower.addLine(to: CGPoint(x: c.x + 66, y: c.y - 12))
            lower.addQuadCurve(to: CGPoint(x: c.x + 44, y: c.y - 22), control: CGPoint(x: c.x + 60, y: c.y - 22))
            lower.closeSubpath()
            FaceGameArt.fillLit(ctx, lower, tone: beak * 0.85, edgeWidth: 3)
            FaceGameArt.fillLit(ctx, upper, tone: beak, edgeWidth: 3)
        }
    }

    private static func wing(front: Bool) -> CGImage? {
        FaceGameArt.sprite("flappy-wing-\(front)", width: 80, height: 56) { ctx, _ in
            let tone = front ? FaceGameArt.lighter(feather, 0.25) : feather * 0.86
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 72, y: 32))
            path.addCurve(to: CGPoint(x: 6, y: 30), control1: CGPoint(x: 56, y: 54), control2: CGPoint(x: 18, y: 52))
            path.addCurve(to: CGPoint(x: 72, y: 32), control1: CGPoint(x: 20, y: 8), control2: CGPoint(x: 52, y: 10))
            path.closeSubpath()
            FaceGameArt.fillLit(ctx, path, tone: tone, edgeWidth: 3)
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: tone), 0.55))
            ctx.setLineWidth(2)
            ctx.setLineCap(.round)
            for k in 0..<3 {
                let y = 22 + Double(k) * 7
                ctx.move(to: CGPoint(x: 20 + Double(k) * 4, y: y))
                ctx.addLine(to: CGPoint(x: 46, y: y + 4))
            }
            ctx.strokePath()
        }
    }

    private static var tail: CGImage? {
        FaceGameArt.sprite("flappy-tail", width: 64, height: 64) { ctx, _ in
            for (angle, len) in [(0.45, 40.0), (0.0, 46.0), (-0.45, 38.0)] {
                ctx.saveGState()
                ctx.translateBy(x: 56, y: 32)
                ctx.rotate(by: CGFloat(.pi + angle))
                FaceGameArt.fillLit(ctx, CGPath(ellipseIn: CGRect(x: 0, y: -8, width: len, height: 16), transform: nil), tone: FaceGamePalette.tangerine, edgeWidth: 3)
                ctx.restoreGState()
            }
        }
    }

    /// The bird, drawn around the origin facing right. `flap` is a running phase for the wings.
    static func drawBird(_ ctx: CGContext, radius r: Double, flap: Double, crop: CGImage?, hurt: Bool) {
        // A quick downstroke and a slower recovery, so the wing snaps rather than swinging evenly.
        let beat = sin(flap) + 0.3 * sin(2 * flap)
        let wingAngle = -0.1 + 0.55 * beat
        let squash = 1 - 0.22 * max(0, -cos(flap))
        FaceGameArt.stamp(ctx, tail, at: CGPoint(x: -r * 1.2, y: -r * 0.1), height: 50, rotation: 0.08 * sin(flap * 0.5))
        drawWing(ctx, front: false, at: CGPoint(x: -r * 0.15, y: r * 0.15), angle: wingAngle * 0.8 + 0.2, squash: squash)
        FaceGameArt.stamp(ctx, head, at: CGPoint(x: r * 0.12, y: r * 0.12), height: 150 * r / 42 * 0.82)
        let face = CGRect(x: -r * 0.86, y: -r * 0.86, width: r * 1.72, height: r * 1.72)
        FaceGamePaint.drawFace(ctx, crop: crop, in: face, corner: r * 0.86, fallback: hurt ? "😵" : "🙂")
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: feather)))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: face)
        if hurt {
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.coral, 0.3))
            ctx.fillEllipse(in: face)
        }
        drawWing(ctx, front: true, at: CGPoint(x: -r * 0.5, y: -r * 0.3), angle: wingAngle, squash: squash)
    }

    private static func drawWing(_ ctx: CGContext, front: Bool, at p: CGPoint, angle: Double, squash: Double) {
        guard let image = wing(front: front) else { return }
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: CGFloat(angle))
        ctx.scaleBy(x: 1, y: CGFloat(squash))
        // Hinged at its right end, where it meets the body.
        ctx.draw(image, in: CGRect(x: -70, y: -28, width: 80, height: 56))
        ctx.restoreGState()
    }

    private static func featherSprite(white: Bool) -> CGImage? {
        FaceGameArt.sprite("flappy-feather-\(white)", width: 40, height: 20) { ctx, _ in
            let tone = white ? FaceGamePalette.cream : feather
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 2, y: 10))
            path.addQuadCurve(to: CGPoint(x: 38, y: 10), control: CGPoint(x: 20, y: 22))
            path.addQuadCurve(to: CGPoint(x: 2, y: 10), control: CGPoint(x: 20, y: -2))
            path.closeSubpath()
            FaceGameArt.fillLit(ctx, path, tone: tone, edgeWidth: 2)
        }
    }

    static func drawFeather(_ ctx: CGContext, at p: CGPoint, size: Double, angle: Double, alpha: Double, white: Bool) {
        FaceGameArt.stamp(ctx, featherSprite(white: white), at: p, height: size, rotation: angle, alpha: alpha)
    }
}
