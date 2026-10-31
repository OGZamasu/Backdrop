import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Night skyline

/// A city at night across the river: three depths of towers, their windows lit warm and cool, the glow of the city on
/// the low clouds, and the lights' reflections trembling in the water. Now and then a window goes dark or lights up, and
/// the warning lights on the tallest roofs pulse slowly.
final class BackdropNightSkyline: BackdropScene {
    typealias RGB = BackdropRGB
    private struct Window { let rect: CGRect, warm: Bool, period: Double, phase: Double, on: Double }
    private static let river: CGFloat = 110

    private var windows: [Window] = []
    private var beacons: [CGPoint] = []
    private var canvas: BackdropCanvas?

    override func paint() -> CIImage? {
        var live: [Window] = []
        var tops: [CGPoint] = []
        guard let city = BackdropPainter.paint({ ctx in
            let h = Self.river
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: h, width: 1280, height: 720 - h), [
                (at: 0, color: RGB(hex: 0x5A3F66)), (at: 0.18, color: RGB(hex: 0x2E2A55)), (at: 0.55, color: RGB(hex: 0x141A3C)), (at: 1, color: RGB(hex: 0x060A1C)),
            ])
            var rng = SplitMix64(seed: 0x5C1)
            for _ in 0..<60 {
                let p = CGPoint(x: .random(in: 0..<1280, using: &rng), y: .random(in: 480..<720, using: &rng))
                let r = CGFloat.random(in: 0.5...1.1, using: &rng)
                ctx.setFillColor(RGB(0.9, 0.92, 1).cg(Double.random(in: 0.2...0.6, using: &rng)))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            // Three depths of towers: hazy and small far away, then taller, then the dark giants at the edges. The middle
            // stays low so a head sits against the night sky.
            let layers: [(count: Int, heights: ClosedRange<CGFloat>, widths: ClosedRange<CGFloat>, colour: RGB, lit: Double, window: CGSize, alpha: Double)] = [
                (30, 50...190, 30...70, RGB(hex: 0x262C52), 0.25, CGSize(width: 2, height: 3), 0.45),
                (18, 90...330, 50...110, RGB(hex: 0x141936), 0.32, CGSize(width: 3, height: 5), 0.75),
                (7, 330...600, 90...170, RGB(hex: 0x090C1E), 0.38, CGSize(width: 4, height: 7), 0.95),
            ]
            for (depth, layer) in layers.enumerated() {
                var x: CGFloat = -40
                while x < 1300 {
                    let w = CGFloat.random(in: layer.widths, using: &rng)
                    var tall = CGFloat.random(in: layer.heights, using: &rng)
                    let centre = abs(x + w / 2 - 640)
                    if depth == 2 && centre < 420 { x += w * 1.6; continue }            // the giants stand only at the sides
                    if depth == 1 && centre < 260 { tall *= 0.55 }
                    let body = CGRect(x: x, y: h - 4, width: w, height: tall)
                    BackdropPainter.fill(ctx, CGPath(rect: body, transform: nil),
                                         gradient: [(at: 0, color: layer.colour.mixed(RGB(hex: 0x5A3F66), 0.25 - Double(depth) * 0.08)), (at: 1, color: layer.colour)],
                                         from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h + tall))
                    // A rim of city glow on the left edge of each tower.
                    ctx.setFillColor(RGB(hex: 0x8A7AB8).cg(0.10 + 0.04 * Double(2 - depth)))
                    ctx.fill(CGRect(x: x, y: h, width: 2, height: tall))
                    if depth > 0 && Double.random(in: 0..<1, using: &rng) < 0.35 {
                        // A spire or mast, with a warning light.
                        ctx.setFillColor(layer.colour.cg)
                        ctx.fill(CGRect(x: x + w / 2 - 1.5, y: h + tall, width: 3, height: CGFloat.random(in: 20...60, using: &rng)))
                        tops.append(CGPoint(x: x + w / 2, y: h + tall + 50))
                    }
                    // Windows on a grid, some lit.
                    let gapX = layer.window.width * 2.4, gapY = layer.window.height * 1.9
                    var wy = h + 10
                    while wy < h + tall - 14 {
                        var wx = x + 6
                        while wx < x + w - 6 {
                            let roll = Double.random(in: 0..<1, using: &rng)
                            let rect = CGRect(x: wx, y: wy, width: layer.window.width, height: layer.window.height)
                            let warm = Double.random(in: 0..<1, using: &rng) < 0.7
                            if depth > 0 && roll < 0.035 {
                                live.append(Window(rect: rect, warm: warm, period: .random(in: 18...70, using: &rng), phase: .random(in: 0..<1, using: &rng),
                                                   on: .random(in: 0.3...0.8, using: &rng)))
                            } else if roll < layer.lit {
                                let tint = warm ? RGB(hex: 0xFFD48A) : RGB(hex: 0xBFD8FF)
                                ctx.setFillColor(tint.cg(layer.alpha * Double.random(in: 0.55...1.0, using: &rng)))
                                ctx.fill(rect)
                            }
                            wx += gapX
                        }
                        wy += gapY
                    }
                    x += w + CGFloat.random(in: 0...10, using: &rng)
                }
                // Haze between depths.
                if let g = BackdropPaint.gradient([(at: 0, r: 0.35, g: 0.27, b: 0.45, a: 0.35), (at: 1, r: 0.35, g: 0.27, b: 0.45, a: 0)]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h + 160), options: [])
                }
            }
            // The river.
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: h), [(at: 0, color: RGB(hex: 0x05070F)), (at: 1, color: RGB(hex: 0x141833))])
        }) else { return nil }
        windows = live
        beacons = tops
        // Reflections: the city flipped into the river, stretched and smeared down, dark.
        let reflection = city.cropped(to: CGRect(x: 0, y: Self.river, width: 1280, height: 200))
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1.2).concatenating(CGAffineTransform(translationX: 0, y: Self.river * 2.2)))
        let smeared = reflection.clampedToExtent().applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 14, kCIInputAngleKey: Double.pi / 2])
            .cropped(to: CGRect(x: 0, y: 0, width: 1280, height: Self.river - 2))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.55)])
        let picture = smeared.composited(over: city)
        return BackdropFinish.finish(BackdropFinish.vignette(picture, strength: 0.25), grain: 0.8)
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        if canvas == nil { canvas = BackdropCanvas(width: 1280, height: 720) }
        guard let canvas else { return still }
        canvas.clear()
        let ctx = canvas.context
        for w in windows {
            // Each window keeps its own hours: on for part of its cycle, with a short fade either side.
            let p = BackdropMotion.loop(time, period: w.period, offset: w.phase)
            let level = BackdropMath.smoothstep(0, 0.02, p) * (1 - BackdropMath.smoothstep(w.on, w.on + 0.02, p))
            guard level > 0.01 else { continue }
            ctx.setFillColor((w.warm ? RGB(hex: 0xFFD48A) : RGB(hex: 0xBFD8FF)).cg(level * 0.9))
            ctx.fill(w.rect)
        }
        for (i, b) in beacons.enumerated() {
            let pulse = pow(0.5 + 0.5 * BackdropMotion.wave(time, rate: 2.4, phase: Double(i) * 0.7), 2)
            BackdropPainter.glow(ctx, at: b, radius: 9, color: RGB(hex: 0xFF4A3A), alpha: 0.25 + 0.6 * pulse)
        }
        // Low cloud lit by the city drifting over, and the river's reflections trembling.
        let alive = BackdropPainter.shimmer(still, at: time, amount: 0.07, scale: 3.2, speed: CGPoint(x: 18, y: 0))
        guard let lights = canvas.image() else { return alive }
        return lights.composited(over: alive)
    }
}

// MARK: - Tokyo rain

/// A narrow street in the rain at night: tall signs in pink, cyan and amber glowing down both sides, a fog of coloured
/// light at the far end, and the wet road throwing it all back. Rain falls in two depths.
final class BackdropTokyoRain: BackdropScene {
    typealias RGB = BackdropRGB
    private static let vanish = CGPoint(x: 640, y: 330)
    private static let road: CGFloat = 200
    private struct Drop { let x: Double, y: Double, speed: Double, length: Double, alpha: Double }
    private let drops: [Drop]
    private var canvas: BackdropCanvas?

    override init() {
        var rng = SplitMix64(seed: 0x70C10)
        drops = (0..<140).map { _ in
            let near = Double.random(in: 0..<1, using: &rng)
            return Drop(x: .random(in: 0..<1, using: &rng), y: .random(in: 0..<1, using: &rng), speed: 500 + 700 * near,
                        length: 14 + 30 * near, alpha: 0.08 + 0.18 * near)
        }
    }

    /// Sign colours: hot pink, cyan, amber, lime and violet.
    private static let neon: [RGB] = [RGB(hex: 0xFF3E9A), RGB(hex: 0x38E0FF), RGB(hex: 0xFFB338), RGB(hex: 0x8CFF6A), RGB(hex: 0xB070FF)]

    override func paint() -> CIImage? {
        guard let street = BackdropPainter.paint(width: 960, height: 540, { ctx in
            let v = Self.vanish
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: RGB(hex: 0x16112A)), (at: 0.45, color: RGB(hex: 0x2A1C46)), (at: 1, color: RGB(hex: 0x0A0816))])
            // Fog of light at the far end of the street.
            BackdropPainter.glow(ctx, at: v, radius: 420, color: RGB(hex: 0xC24A9A), alpha: 0.38, squash: 0.8, blend: .screen)
            BackdropPainter.glow(ctx, at: CGPoint(x: v.x, y: v.y - 40), radius: 200, color: RGB(hex: 0xFF9AC8), alpha: 0.25, blend: .screen)
            var rng = SplitMix64(seed: 0x51C)
            // Facades on both sides, receding to the vanishing point, each hung with signs.
            for side: CGFloat in [-1, 1] {
                let outer = side < 0 ? CGFloat(0) : 1280
                let facade = CGMutablePath()
                facade.move(to: CGPoint(x: outer, y: -20)); facade.addLine(to: CGPoint(x: outer, y: 740))
                facade.addLine(to: CGPoint(x: v.x + side * 140, y: v.y + 260)); facade.addLine(to: CGPoint(x: v.x + side * 140, y: v.y - 60)); facade.closeSubpath()
                BackdropPainter.fill(ctx, facade, gradient: [(at: 0, color: RGB(hex: 0x0D0A18)), (at: 1, color: RGB(hex: 0x241A3A))],
                                     from: CGPoint(x: outer, y: 0), to: CGPoint(x: v.x + side * 140, y: 0))
                // Floors: rows of small windows running back to the far end, some lit.
                ctx.saveGState()
                ctx.addPath(facade); ctx.clip()
                for row in 0..<14 {
                    let level = -0.2 + Double(row) * 0.12             // height of the floor, relative to the far end
                    var t = 0.04
                    while t < 0.95 {
                        let x = outer + (v.x + side * 140 - outer) * CGFloat(t)
                        let scale = 1 - CGFloat(t) * 0.82
                        let y = v.y + CGFloat(level) * 520 * scale
                        if Double.random(in: 0..<1, using: &rng) < 0.45 {
                            let warm = Bool.random(using: &rng)
                            ctx.setFillColor((warm ? RGB(hex: 0xFFC98A) : RGB(hex: 0x9FB8FF)).cg(0.55 * Double(scale) + 0.15))
                            ctx.fill(CGRect(x: x, y: y, width: 18 * scale, height: 12 * scale))
                        }
                        t += 0.045 + 0.05 * (1 - t)
                    }
                }
                ctx.restoreGState()
                // Signs: tall boards near, shrinking toward the far end.
                for k in 0..<9 {
                    let f = CGFloat(k) / 9                       // 0 near ... 1 far
                    let depthScale = 1 - f * 0.85
                    let x = outer + (v.x + side * 150 - outer) * (f * 0.95 + 0.04)
                    let w = 64 * depthScale, h = CGFloat.random(in: 160...330, using: &rng) * depthScale
                    let y = v.y + CGFloat.random(in: -150...130, using: &rng) * depthScale + 40 * (1 - depthScale)
                    let colour = Self.neon[Int.random(in: 0..<Self.neon.count, using: &rng)]
                    let board = CGRect(x: x - w / 2, y: y, width: w, height: h)
                    BackdropPainter.glow(ctx, at: CGPoint(x: board.midX, y: board.midY), radius: h * 0.9, color: colour, alpha: 0.35, squash: 1.2, blend: .screen)
                    BackdropPainter.fill(ctx, BackdropPainter.rounded(board, 3), colour.scaled(0.35).cg)
                    ctx.setStrokeColor(colour.mixed(RGB(1, 1, 1), 0.4).cg(0.95))
                    ctx.setLineWidth(max(1, 3 * depthScale))
                    ctx.stroke(board.insetBy(dx: 2, dy: 2))
                    // Glyph-like marks: little bright blocks stacked down the board (no real letters).
                    var gy = board.maxY - w * 0.3
                    while gy > board.minY + w * 0.3 {
                        let gw = w * CGFloat.random(in: 0.35...0.6, using: &rng), gh = w * CGFloat.random(in: 0.18...0.32, using: &rng)
                        ctx.setFillColor(colour.mixed(RGB(1, 1, 1), 0.55).cg(0.95))
                        ctx.fill(CGRect(x: board.midX - gw / 2, y: gy - gh, width: gw, height: gh * 0.4))
                        ctx.fill(CGRect(x: board.midX - gw / 2 + gw * 0.4, y: gy - gh, width: gw * 0.2, height: gh))
                        gy -= gh + w * 0.14
                    }
                }
                // Shop fronts at street level: warm light spilling out.
                for k in 0..<5 {
                    let f = CGFloat(k) / 5
                    let x = outer + (v.x + side * 150 - outer) * (f * 0.9 + 0.05)
                    let w = 140 * (1 - f * 0.8)
                    BackdropPainter.glow(ctx, at: CGPoint(x: x, y: Self.road + 40 * (1 - f)), radius: w, color: RGB(hex: 0xFFC27A), alpha: 0.3, squash: 0.6, blend: .screen)
                }
            }
            // Overhead cables sagging across.
            ctx.setStrokeColor(RGB(0, 0, 0).cg(0.6)); ctx.setLineWidth(1.5)
            for k in 0..<4 {
                let y = 560 + CGFloat(k) * 34
                ctx.move(to: CGPoint(x: -10, y: y)); ctx.addQuadCurve(to: CGPoint(x: 1290, y: y + 20), control: CGPoint(x: 640, y: y - 70)); ctx.strokePath()
            }
            // The road: dark and wet.
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: Self.road), [(at: 0, color: RGB(hex: 0x07060E)), (at: 1, color: RGB(hex: 0x1C1530))])
        }) else { return nil }
        // The wet road reflects everything above it, smeared downward.
        let road = Self.road
        let above = street.cropped(to: CGRect(x: 0, y: road, width: 1280, height: 400))
        let mirror = above.transformed(by: CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: road * 2)))
            .clampedToExtent().applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 22, kCIInputAngleKey: Double.pi / 2])
            .cropped(to: CGRect(x: 0, y: 0, width: 1280, height: road))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.6)])
        let picture = BackdropPainter.defocus(mirror.composited(over: street), sigma: 1.6)
        return BackdropFinish.finish(BackdropFinish.vignette(picture, strength: 0.3), grain: 1.0)
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        if canvas == nil { canvas = BackdropCanvas(width: 640, height: 360) }
        guard let canvas else { return still }
        canvas.clear()
        let ctx = canvas.context
        ctx.setLineCap(.round)
        for d in drops {
            let y = (1 - BackdropMath.fract(d.y + d.speed * time / 760)) * 380 - 10
            let x = d.x * 680 - 20 + (380 - y) * 0.12
            ctx.setStrokeColor(RGB(0.85, 0.9, 1).cg(d.alpha))
            ctx.setLineWidth(d.length > 30 ? 1.2 : 0.8)
            ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x - d.length * 0.06, y: y + d.length * 0.5)); ctx.strokePath()
        }
        guard let rain = canvas.image(scale: 2) else { return still }
        return rain.composited(over: still)
    }
}
