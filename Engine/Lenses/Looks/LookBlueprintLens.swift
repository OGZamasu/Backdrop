import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Where the blueprint's dimension lines go. Pure, so it can be tested.
enum LookBlueprintPlan {
    /// The lines that measure you: across the top of your head, and down its side from crown to chin.
    struct Dimensions: Equatable {
        var headLeft: Double
        var headRight: Double
        var crown: Double
        var side: Double
    }

    static func dimensions(for head: LookHead.Found) -> Dimensions {
        Dimensions(headLeft: head.centre.x - head.width / 2, headRight: head.centre.x + head.width / 2, crown: head.top, side: head.centre.x + head.width * 0.82)
    }

    /// Eases one set of lines towards another, `rate` per second.
    static func ease(_ a: Dimensions, toward b: Dimensions, dt: Double, rate: Double = 6) -> Dimensions {
        let k = 1 - exp(-max(0, dt) * rate)
        return Dimensions(headLeft: a.headLeft + (b.headLeft - a.headLeft) * k, headRight: a.headRight + (b.headRight - a.headRight) * k,
                          crown: a.crown + (b.crown - a.crown) * k, side: a.side + (b.side - a.side) * k)
    }
}

/// A technical drawing of you: white lines on blueprint blue over a fine grid, you drawn boldly and the room lightly, with
/// dimension lines that measure your head and follow you, inside a drawing border with a title block.
final class LookBlueprintLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private static let blue: LookColour = (0.06, 0.25, 0.53)
    private static let chalk: LookColour = (0.9, 0.96, 1.0)

    private var clock: LookClock
    private let paper = LookDisplayCache()
    private let measures = LookDisplayCache()
    private var dimensions: LookBlueprintPlan.Dimensions?
    /// How much the dimension lines show, 0...1, so they fade in and out rather than blink.
    private var shown = 0.0

    init(startDate: Date = Date()) { clock = LookClock(startDate: startDate) }

    func restart() { clock.restart(); dimensions = nil; shown = 0; measures.reset() }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        _ = clock.elapsed(at: input.time)

        // The drawing: dark lines found the pencil-sketch way (a picture divided by a blurred copy of itself), drawn in white.
        let tone = LookKit.perceptual(LookKit.grey(input.composed.clampedToExtent().applyingGaussianBlur(sigma: 1.0).cropped(to: rect)))
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        let blurred = LookKit.shrink(tone, rect: rect, by: 0.5).applyingFilter("CIColorInvert").clampedToExtent().applyingGaussianBlur(sigma: 3).cropped(to: half)
        let sketch = LookKit.enlarge(blurred, to: rect, from: half)
            .applyingFilter("CIColorDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: tone])
        var lines = LookKit.levels(sketch.applyingFilter("CIColorInvert"), gain: 3.2, bias: -0.08)
        if let matte = input.matte {
            // The room is drawn lightly; you are drawn in full, with a firm outline.
            lines = LookKit.blend(lines, over: LookKit.levels(lines, gain: 0.45), mask: matte)
            let solid = LookKit.levels(LookKit.shrink(matte, rect: rect, by: 0.5), gain: 6, bias: -2.5)
            let outline = solid.clampedToExtent().applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: 1.0]).applyingGaussianBlur(sigma: 0.5).cropped(to: half)
            lines = lines.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: LookKit.levels(LookKit.enlarge(outline, to: rect, from: half), gain: 1.6)])
        }

        let date = clock.date(after: 0)
        guard let sheet = paper.layer("\(Int(rect.width))-\(LookClock.day(date))", size: rect.size, draw: { ctx in Self.drawSheet(ctx, rect: rect, date: date) }) else {
            return input.composed
        }
        let drawn = LookKit.blend(CIImage(color: LookKit.ciColour(Self.chalk)).cropped(to: rect), over: sheet, mask: lines)

        // Dimension lines follow you, eased, and fade when nobody is there.
        let head = input.matteGrid.flatMap { LookHead.find(in: $0) }
        if let head {
            let target = LookBlueprintPlan.dimensions(for: head)
            // The cutout shivers by a few pixels from frame to frame; the drawing only moves for a real change.
            let settled = dimensions.map { max(abs($0.headLeft - target.headLeft), abs($0.headRight - target.headRight), abs($0.crown - target.crown)) < 4 } ?? false
            if !settled { dimensions = dimensions.map { LookBlueprintPlan.ease($0, toward: target, dt: input.dt) } ?? target }
        }
        shown = min(1, max(0, shown + (head == nil ? -1 : 1) * max(0, input.dt) * 3))
        guard shown > 0.01, let d = dimensions else { return drawn.cropped(to: rect) }
        // The lines are redrawn only when they have moved by a pixel or faded a step.
        let key = String(format: "%.0f %.0f %.0f %.0f %.2f", d.headLeft, d.headRight, d.crown, d.side, (shown * 20).rounded() / 20)
        guard let marks = measures.layer(key, size: rect.size, draw: { ctx in Self.drawDimensions(ctx, d, rect: rect, alpha: (shown * 20).rounded() / 20) }) else {
            return drawn.cropped(to: rect)
        }
        return marks.composited(over: drawn).cropped(to: rect)
    }

    private static func ink(_ alpha: Double) -> CGColor {
        CGColor(colorSpace: LookKit.space, components: [CGFloat(chalk.r), CGFloat(chalk.g), CGFloat(chalk.b), CGFloat(alpha)])!
    }

    /// The paper: blueprint blue, a little uneven, a fine grid and a heavier one, a border and the title block.
    private static func drawSheet(_ ctx: CGContext, rect: CGRect, date: Date) {
        let space = LookKit.space
        ctx.setFillColor(CGColor(colorSpace: space, components: [CGFloat(blue.r), CGFloat(blue.g), CGFloat(blue.b), 1])!)
        ctx.fill(rect)
        var rng = SplitMix64(seed: 88)
        for _ in 0..<14 {
            let p = CGPoint(x: Double.random(in: 0..<rect.width, using: &rng), y: Double.random(in: 0..<rect.height, using: &rng))
            ctx.glow(center: p, radius: Double.random(in: 120...320, using: &rng), red: 0.0, green: 0.12, blue: 0.3, alpha: 0.18)
        }
        ctx.setLineWidth(1)
        for (step, alpha) in [(20.0, 0.07), (100.0, 0.16)] {
            ctx.setStrokeColor(ink(alpha))
            var x = rect.minX + 40
            while x < rect.maxX - 40 { ctx.move(to: CGPoint(x: x, y: rect.minY + 40)); ctx.addLine(to: CGPoint(x: x, y: rect.maxY - 40)); x += step }
            var y = rect.minY + 40
            while y < rect.maxY - 40 { ctx.move(to: CGPoint(x: rect.minX + 40, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX - 40, y: y)); y += step }
            ctx.strokePath()
        }
        // The border, double-ruled.
        ctx.setStrokeColor(ink(0.85))
        ctx.setLineWidth(2.5)
        ctx.stroke(rect.insetBy(dx: 30, dy: 30))
        ctx.setLineWidth(1)
        ctx.stroke(rect.insetBy(dx: 38, dy: 38))
        // The title block, lower right.
        let block = CGRect(x: rect.maxX - 38 - 330, y: rect.minY + 38, width: 330, height: 108)
        ctx.setFillColor(CGColor(colorSpace: space, components: [CGFloat(blue.r * 0.85), CGFloat(blue.g * 0.85), CGFloat(blue.b * 0.85), 1])!)
        ctx.fill(block)
        ctx.setLineWidth(1.5)
        ctx.stroke(block)
        for row in 1..<3 {
            let y = block.minY + block.height * CGFloat(row) / 3
            ctx.move(to: CGPoint(x: block.minX, y: y)); ctx.addLine(to: CGPoint(x: block.maxX, y: y))
        }
        ctx.move(to: CGPoint(x: block.minX + 124, y: block.minY)); ctx.addLine(to: CGPoint(x: block.minX + 124, y: block.maxY))
        ctx.strokePath()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM.yy"
        let rows = [("SUBJECT", "YOU"), ("SCALE", "1 : 1"), ("DATE", formatter.string(from: date))]
        let white = NSColor(srgbRed: CGFloat(chalk.r), green: CGFloat(chalk.g), blue: CGFloat(chalk.b), alpha: 0.95)
        for (i, row) in rows.enumerated() {
            let y = block.maxY - block.height * CGFloat(i + 1) / 3 + 10
            LookKit.text(row.0, in: ctx, at: CGPoint(x: block.minX + 12, y: y + 1), size: 15, colour: white.withAlphaComponent(0.75), weight: .medium, tracking: 1.5)
            LookKit.text(row.1, in: ctx, at: CGPoint(x: block.minX + 138, y: y - 2), size: 20, colour: white, weight: .semibold, tracking: 1)
        }
    }

    /// Dimension lines: a span across your head with arrowheads and its width, and a line down from your crown.
    private static func drawDimensions(_ ctx: CGContext, _ d: LookBlueprintPlan.Dimensions, rect: CGRect, alpha: Double) {
        let colour = ink(0.9 * alpha)
        ctx.setStrokeColor(colour)
        ctx.setFillColor(colour)
        ctx.setLineWidth(1.5)
        let y = min(rect.maxY - 70, d.crown + 34)
        func arrow(at p: CGPoint, pointing dx: CGFloat, _ dy: CGFloat) {
            ctx.move(to: p)
            ctx.addLine(to: CGPoint(x: p.x - dx * 12 - dy * 4, y: p.y - dy * 12 - dx * 4))
            ctx.addLine(to: CGPoint(x: p.x - dx * 12 + dy * 4, y: p.y - dy * 12 + dx * 4))
            ctx.closePath()
            ctx.fillPath()
        }
        // Extension lines up from the sides of the head, then the span between them.
        for x in [d.headLeft, d.headRight] {
            ctx.move(to: CGPoint(x: x, y: d.crown - 30)); ctx.addLine(to: CGPoint(x: x, y: y + 10))
        }
        ctx.move(to: CGPoint(x: d.headLeft, y: y)); ctx.addLine(to: CGPoint(x: d.headRight, y: y))
        ctx.strokePath()
        arrow(at: CGPoint(x: d.headLeft, y: y), pointing: -1, 0)
        arrow(at: CGPoint(x: d.headRight, y: y), pointing: 1, 0)
        let width = String(format: "%.0f", max(0, d.headRight - d.headLeft))
        LookKit.text(width, in: ctx, at: CGPoint(x: (d.headLeft + d.headRight) / 2, y: y + 6), size: 20, colour: NSColor(cgColor: colour) ?? .white,
                     weight: .semibold, tracking: 1, anchor: .centre)
        // Down the side of the head, from the crown to the chin, with ticks at both ends and the height along it.
        let x = min(rect.maxX - 80, d.side)
        let chin = d.crown - (d.headRight - d.headLeft) * 1.3
        guard d.crown - chin > 40 else { return }
        for y in [d.crown, chin] { ctx.move(to: CGPoint(x: x - 14, y: y)); ctx.addLine(to: CGPoint(x: x + 8, y: y)) }
        ctx.move(to: CGPoint(x: x, y: d.crown)); ctx.addLine(to: CGPoint(x: x, y: chin))
        ctx.strokePath()
        arrow(at: CGPoint(x: x, y: d.crown), pointing: 0, 1)
        arrow(at: CGPoint(x: x, y: chin), pointing: 0, -1)
        ctx.saveGState()
        ctx.translateBy(x: x + 10, y: (d.crown + chin) / 2)
        ctx.rotate(by: -.pi / 2)
        LookKit.text(String(format: "%.0f", d.crown - chin), in: ctx, at: .zero, size: 20, colour: NSColor(cgColor: colour) ?? .white, weight: .semibold, tracking: 1, anchor: .centre)
        ctx.restoreGState()
    }
}
