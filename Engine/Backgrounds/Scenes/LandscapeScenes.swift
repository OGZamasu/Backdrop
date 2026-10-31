import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Places outdoors. Each is composed so the area behind a head stays calm and of a colour well apart from skin, with
/// the bright, busy parts (the sun, the glitter, the fire) off to one side.
enum BackdropLandscape {
    typealias RGB = BackdropRGB

    /// Fills `rect` with layered noise-driven clouds of `color`, densest where the noise is highest: for skies and mist.
    static func clouds(_ extent: CGRect, channel: Int, scale: CGFloat, offset: CGPoint, color: RGB, shade: RGB, threshold: Double, alpha: Double, stretch: CGFloat = 1) -> CIImage {
        let field = BackdropNoise.field(channel, scale: scale, offset: offset, stretch: stretch, extent: extent)
        return BackdropInk.colored(field, BackdropInk.table([
            (at: 0, color: shade, alpha: 0), (at: threshold, color: shade, alpha: 0),
            (at: threshold + (1 - threshold) * 0.45, color: shade.mixed(color, 0.5), alpha: alpha * 0.7), (at: 1, color: color, alpha: alpha),
        ]))
    }

    /// A pine silhouette standing on `base`, `height` tall.
    static func pine(_ ctx: CGContext, x: CGFloat, base: CGFloat, height h: CGFloat, color: CGColor, rng: inout SplitMix64, snow: CGColor? = nil) {
        let w = h * CGFloat.random(in: 0.24...0.30, using: &rng)
        let tree = CGMutablePath()
        let snowPath: CGMutablePath? = snow == nil ? nil : CGMutablePath()
        for t in 0..<7 {
            let f = CGFloat(t) / 7
            let y0 = base + h * f * 0.82
            let tierW = w * (1 - f * 0.82) * CGFloat.random(in: 0.88...1.08, using: &rng)
            let top = y0 + h * 0.25
            tree.move(to: CGPoint(x: x, y: top))
            tree.addLine(to: CGPoint(x: x - tierW, y: y0))
            for k in 1..<4 {
                let px = x - tierW + tierW * 2 * CGFloat(k) / 4
                tree.addLine(to: CGPoint(x: px - tierW * 0.1, y: y0 + h * 0.03))
                tree.addLine(to: CGPoint(x: px, y: y0 - h * CGFloat.random(in: 0...0.025, using: &rng)))
            }
            tree.addLine(to: CGPoint(x: x + tierW, y: y0))
            tree.closeSubpath()
            // Snow lying on the upper side of each tier.
            snowPath?.move(to: CGPoint(x: x, y: top))
            snowPath?.addLine(to: CGPoint(x: x - tierW * 0.8, y: y0 + h * 0.06))
            snowPath?.addQuadCurve(to: CGPoint(x: x + tierW * 0.4, y: y0 + h * 0.11), control: CGPoint(x: x - tierW * 0.1, y: y0 + h * 0.02))
            snowPath?.closeSubpath()
        }
        tree.addRect(CGRect(x: x - w * 0.06, y: base - 6, width: w * 0.12, height: h * 0.15))
        ctx.addPath(tree)
        ctx.setFillColor(color)
        ctx.fillPath()
        if let snow, let snowPath {
            ctx.addPath(snowPath)
            ctx.setFillColor(snow)
            ctx.fillPath()
        }
    }
}

// MARK: - Mountain lake at dawn

/// Layered mountains in the first light, mist on the water and their reflection in a still lake. A still.
final class BackdropMountainLake: BackdropScene {
    typealias RGB = BackdropRGB
    private static let shore: CGFloat = 230

    override func paint() -> CIImage? {
        let frame = BackdropPainter.frame
        guard let land = BackdropPainter.paint({ ctx in
            let h = Self.shore
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: h, width: 1280, height: 720 - h), [
                (at: 0, color: RGB(hex: 0xF3B58F)), (at: 0.18, color: RGB(hex: 0xD98E9C)), (at: 0.45, color: RGB(hex: 0x8C77A8)), (at: 1, color: RGB(hex: 0x2E3A6B)),
            ])
            BackdropPainter.glow(ctx, at: CGPoint(x: 210, y: h + 20), radius: 520, color: RGB(hex: 0xFFD3A0), alpha: 0.55, squash: 0.6, blend: .screen)
            // Ranges from far to near: hazier and lighter far away, deeper and bluer close by. The middle one rises behind
            // where a head would be, so the head sits against blue rather than the bright dawn.
            let ranges: [(base: CGFloat, height: CGFloat, seed: Double, wave: Double, rough: Double, color: RGB)] = [
                (h, 300, 2.3, 300, 0.9, RGB(hex: 0xA58DB2)), (h, 250, 5.1, 240, 0.8, RGB(hex: 0x6E6C9C)),
                (h, 150, 8.4, 200, 0.7, RGB(hex: 0x434D7E)), (h, 70, 3.7, 140, 0.4, RGB(hex: 0x27304F)),
            ]
            for (i, r) in ranges.enumerated() {
                var line = BackdropPainter.ridgeLine(base: r.base, height: r.height, seed: r.seed, wavelength: r.wave, rough: r.rough, step: 5)
                if i == 1 {
                    // A tall massif in the middle.
                    line = line.map { p in
                        let lift = CGFloat(exp(-pow(Double(p.x - 660) / 210, 2))) * 150
                        return CGPoint(x: p.x, y: p.y + lift)
                    }
                }
                let body = BackdropPainter.ridge(line, floor: h - 2)
                BackdropPainter.fill(ctx, body, gradient: [(at: 0, color: r.color.mixed(RGB(hex: 0x8C77A8), 0.25)), (at: 1, color: r.color)],
                                     from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h + r.height + 150))
                if i < 2 {
                    // Snow on the high slopes, pink where the dawn catches it.
                    ctx.saveGState()
                    ctx.addPath(body)
                    ctx.clip()
                    let snowLine = h + r.height * 0.84 + (i == 1 ? 110 : 0)
                    if let g = BackdropPaint.gradient([(at: 0, r: 0.96, g: 0.86, b: 0.89, a: 0), (at: 0.25, r: 0.96, g: 0.86, b: 0.89, a: 0.85), (at: 1, r: 0.98, g: 0.9, b: 0.92, a: 0.95)]) {
                        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: snowLine), end: CGPoint(x: 0, y: snowLine + 90), options: [.drawsAfterEndLocation])
                    }
                    ctx.restoreGState()
                }
                // Mist pooling at the foot of each range.
                if let g = BackdropPaint.gradient([(at: 0, r: 0.96, g: 0.84, b: 0.86, a: 0.38), (at: 1, r: 0.96, g: 0.84, b: 0.86, a: 0)]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h + 60 + CGFloat(3 - i) * 12), options: [])
                }
            }
            // The near shore: a band of pines.
            var rng = SplitMix64(seed: 0x1A4E)
            ctx.setFillColor(RGB(hex: 0x151B2E).cg)
            ctx.fill(CGRect(x: 0, y: h - 6, width: 1280, height: 10))
            for _ in 0..<60 {
                let x = CGFloat.random(in: -20...1300, using: &rng)
                if x > 420 && x < 880 && Bool.random(using: &rng) { continue }
                BackdropLandscape.pine(ctx, x: x, base: h - 4, height: CGFloat.random(in: 26...70, using: &rng), color: RGB(hex: 0x151B2E).cg, rng: &rng)
            }
        }) else { return nil }
        // Wisps of pink cloud.
        let wisps = BackdropLandscape.clouds(frame, channel: 2, scale: 3.4, offset: CGPoint(x: 90, y: 30), color: RGB(hex: 0xFBD9D2), shade: RGB(hex: 0xC48AA6),
                                             threshold: 0.55, alpha: 0.55, stretch: 0.35)
        let skyMask = CIFilter.linearGradient()
        skyMask.point0 = CGPoint(x: 0, y: 470); skyMask.point1 = CGPoint(x: 0, y: 620)
        skyMask.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0); skyMask.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        let highWisps = wisps.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: skyMask.outputImage?.cropped(to: frame) ?? wisps])
        let above = highWisps.composited(over: land).cropped(to: frame)
        // The lake: the world above, mirrored at the shore, a little darker and bluer, softened, with long ripples.
        let mirrored = above.transformed(by: CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: Self.shore * 2)))
        let water = BackdropPainter.defocus(mirrored, sigma: 2.5)
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.72, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.76, z: 0, w: 0),
                                                          "inputBVector": CIVector(x: 0, y: 0, z: 0.88, w: 0)])
            .cropped(to: CGRect(x: 0, y: 0, width: 1280, height: Self.shore - 4))
        guard let ripples = BackdropPainter.paint(deep: false, { ctx in
            var rng = SplitMix64(seed: 0x21BB)
            for _ in 0..<150 {
                let y = CGFloat.random(in: 0...(Self.shore - 12), using: &rng)
                let w = CGFloat.random(in: 40...260, using: &rng) * (0.5 + (Self.shore - y) / Self.shore)
                let x = CGFloat.random(in: -100...1280, using: &rng)
                ctx.setFillColor(RGB(1, 0.92, 0.95).cg(Double.random(in: 0.04...0.12, using: &rng)))
                ctx.fill(CGRect(x: x, y: y, width: w, height: 1.2))
            }
            if let g = BackdropPaint.gradient([(at: 0, r: 0.96, g: 0.86, b: 0.9, a: 0.35), (at: 1, r: 0.96, g: 0.86, b: 0.9, a: 0)]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: Self.shore - 4), end: CGPoint(x: 0, y: Self.shore - 60), options: [])
            }
        }) else { return nil }
        let picture = ripples.composited(over: water.composited(over: above))
        return BackdropFinish.finish(BackdropFinish.vignette(picture, strength: 0.18), grain: 0.7)
    }
}

// MARK: - Desert dunes

/// Smooth dunes under a deep blue sky: each with a sunlit face and a shadowed one split by a sharp crest. A still.
final class BackdropDesertDunes: BackdropScene {
    typealias RGB = BackdropRGB

    override func paint() -> CIImage? {
        guard let painted = BackdropPainter.paint({ ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [
                (at: 0, color: RGB(hex: 0xF1D2A6)), (at: 0.3, color: RGB(hex: 0xA9CBE0)), (at: 0.62, color: RGB(hex: 0x5C97C8)), (at: 1, color: RGB(hex: 0x23548F)),
            ])
            // The sun high on the left: a white-hot core in a broad glow.
            BackdropPainter.glow(ctx, at: CGPoint(x: 170, y: 640), radius: 520, color: RGB(1, 0.97, 0.88), alpha: 0.55, blend: .screen)
            BackdropPainter.glow(ctx, at: CGPoint(x: 170, y: 640), radius: 70, color: RGB(1, 1, 0.96), alpha: 1, blend: .screen)
            // Dunes, far to near. Each rises slowly into the wind and falls away steeply past a sharp crest. Light comes
            // from the upper left, so the long faces turned left are lit and the steep slip faces lie in shade.
            let dunes: [(base: CGFloat, height: CGFloat, wave: Double, phase: Double, lit: RGB, shade: RGB)] = [
                (225, 70, 700, 0.15, RGB(hex: 0xEDC499), RGB(hex: 0xC99069)),
                (160, 95, 620, 0.55, RGB(hex: 0xE9AE73), RGB(hex: 0xB5744B)),
                (70, 130, 560, 0.05, RGB(hex: 0xE39E5C), RGB(hex: 0x9E5A37)),
                (-40, 150, 520, 0.42, RGB(hex: 0xDB8E4B), RGB(hex: 0x8A4A2C)),
            ]
            func profile(_ x: Double, _ d: (base: CGFloat, height: CGFloat, wave: Double, phase: Double, lit: RGB, shade: RGB)) -> Double {
                let u = BackdropMath.fract(x / d.wave + d.phase)
                // A convex windward slope that is still climbing at the brink, so the crest is sharp; then a steep,
                // nearly straight slip face easing into the trough.
                let rise = u < 0.72 ? sin(u / 0.72 * 1.2) / sin(1.2) : pow(1 - (u - 0.72) / 0.28, 1.25)
                let swell = 0.75 + 0.25 * sin(x / (d.wave * 2.3) + d.phase * 9)
                return Double(d.base) + Double(d.height) * rise * swell
            }
            for d in dunes {
                let step = 2.0
                // Column by column, each coloured by how its slope faces the light, then shaded darker toward its foot.
                var x = -2.0
                while x < 1282 {
                    let y0 = profile(x, d), y1 = profile(x + step, d)
                    let slope = (y1 - y0) / step
                    let facing = BackdropMath.smoothstep(-0.25, 0.35, slope)
                    let colour = d.shade.mixed(d.lit, facing)
                    let top = CGFloat(max(y0, y1))
                    BackdropPainter.fill(ctx, CGPath(rect: CGRect(x: x, y: -20, width: step + 0.6, height: top + 20), transform: nil),
                                         gradient: [(at: 0, color: colour.scaled(0.78)), (at: 1, color: colour)],
                                         from: CGPoint(x: 0, y: d.base - 40), to: CGPoint(x: 0, y: top))
                    x += step
                }
                // The crest lines catch the light.
                var crest: [CGPoint] = []
                var px = -2.0
                while px < 1282 { crest.append(CGPoint(x: px, y: profile(px, d))); px += 3 }
                let line = CGMutablePath()
                line.addLines(between: crest)
                ctx.addPath(line)
                ctx.setStrokeColor(RGB(1, 0.92, 0.8).cg(0.3))
                ctx.setLineWidth(1.2)
                ctx.strokePath()
            }
            // Heat haze over the far dunes.
            if let g = BackdropPaint.gradient([(at: 0, r: 0.98, g: 0.88, b: 0.75, a: 0), (at: 0.5, r: 0.98, g: 0.88, b: 0.75, a: 0.28), (at: 1, r: 0.98, g: 0.88, b: 0.75, a: 0)]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 200), end: CGPoint(x: 0, y: 340), options: [])
            }
        }) else { return nil }
        let soft = BackdropPainter.defocus(painted, sigma: 0.8)
        return BackdropFinish.finish(BackdropFinish.vignette(BackdropPainter.mottle(soft, amount: 0.02, scale: 2.2, channel: 0), strength: 0.16), grain: 0.9)
    }
}

// MARK: - Sunset beach

/// The sun going down into the sea: banded clouds lit from below, a path of glitter on the water that sparkles, gentle
/// waves washing up the wet sand, and a palm leaning in at the left.
final class BackdropSunsetBeach: BackdropScene {
    typealias RGB = BackdropRGB
    private static let horizon: CGFloat = 330
    private static let sun = CGPoint(x: 930, y: 352)

    private struct Glint { let x: Double, y: Double, length: Double, rate: Double, phase: Double }
    private let glints: [Glint]
    private var canvas: BackdropCanvas?

    override init() {
        var rng = SplitMix64(seed: 0x5EA)
        glints = (0..<170).map { _ in
            // Most glints in a column under the sun, widening toward you.
            let depth = Double.random(in: 0..<1, using: &rng)
            let spread = 30 + 190 * depth
            return Glint(x: Double(Self.sun.x) + .random(in: -1...1, using: &rng) * spread * .random(in: 0.2...1, using: &rng),
                         y: Double(Self.horizon) - 4 - depth * 190, length: 6 + 26 * depth * .random(in: 0.4...1, using: &rng),
                         rate: .random(in: 1.2...3.2, using: &rng), phase: .random(in: 0..<(2 * .pi), using: &rng))
        }
    }

    override func paint() -> CIImage? {
        guard let painted = BackdropPainter.paint({ ctx in
            let h = Self.horizon
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: h, width: 1280, height: 720 - h), [
                (at: 0, color: RGB(hex: 0xFFB561)), (at: 0.12, color: RGB(hex: 0xF27C4F)), (at: 0.38, color: RGB(hex: 0xB8487A)),
                (at: 0.7, color: RGB(hex: 0x5B3474)), (at: 1, color: RGB(hex: 0x22204F)),
            ])
            BackdropPainter.glow(ctx, at: Self.sun, radius: 560, color: RGB(hex: 0xFFB070), alpha: 0.5, squash: 0.65, blend: .screen)
            BackdropPainter.glow(ctx, at: Self.sun, radius: 110, color: RGB(hex: 0xFFE2A8), alpha: 0.9, blend: .screen)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: h, width: 1280, height: 720))
            BackdropPainter.fill(ctx, CGPath(ellipseIn: CGRect(x: Self.sun.x - 52, y: Self.sun.y - 52, width: 104, height: 104), transform: nil),
                                 gradient: [(at: 0, color: RGB(hex: 0xFF9A4A)), (at: 1, color: RGB(hex: 0xFFF0C0))], from: CGPoint(x: 0, y: Self.sun.y - 52), to: CGPoint(x: 0, y: Self.sun.y + 52))
            ctx.restoreGState()
            // Long clouds lit from below: dark plum tops, glowing orange undersides.
            var rng = SplitMix64(seed: 0xC10D)
            for _ in 0..<16 {
                let y = CGFloat.random(in: (h + 50)...(h + 340), using: &rng)
                let w = CGFloat.random(in: 200...620, using: &rng)
                let x = CGFloat.random(in: -150...1200, using: &rng)
                let t = CGFloat.random(in: 8...20, using: &rng)
                // A soft plum body, and under it the sun's glow catching its lower edge.
                let lit = (y - h) / 340
                BackdropRoom.soft(ctx, CGPath(ellipseIn: CGRect(x: x, y: y, width: w, height: t), transform: nil),
                                  RGB(hex: 0x5E2F62).mixed(RGB(hex: 0x9C4A72), 1 - Double(lit)).cg(0.85), blur: t * 0.6)
                BackdropRoom.soft(ctx, CGPath(ellipseIn: CGRect(x: x + w * 0.08, y: y - t * 0.15, width: w * 0.84, height: t * 0.45), transform: nil),
                                  RGB(hex: 0xFFA36E).cg(0.75 * Double(1 - lit * 0.6)), blur: t * 0.35)
            }
            // Sea: dusky violet-blue, lighter toward the horizon, with the sun's broad reflection.
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: h), [
                (at: 0, color: RGB(hex: 0x1B1F45)), (at: 0.75, color: RGB(hex: 0x4A3A6E)), (at: 1, color: RGB(hex: 0xC8708A)),
            ])
            BackdropPainter.glow(ctx, at: CGPoint(x: Self.sun.x, y: h - 70), radius: 260, color: RGB(hex: 0xFF9A5C), alpha: 0.45, squash: 0.5, blend: .screen)
            // Wet sand at the bottom, holding a little of the sky.
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: 110), [(at: 0, color: RGB(hex: 0x3B2A3C)), (at: 1, color: RGB(hex: 0x6E4A5E))])
            ctx.setFillColor(RGB(1, 0.85, 0.8).cg(0.5)); ctx.fill(CGRect(x: 0, y: h - 1, width: 1280, height: 1.5))
            // A palm leaning in from the left.
            palm(ctx)
        }) else { return nil }
        return BackdropFinish.finish(BackdropFinish.vignette(painted, strength: 0.2), grain: 0.7)
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        if canvas == nil { canvas = BackdropCanvas(width: 640, height: 360) }
        guard let canvas else { return still }
        canvas.clear()
        let ctx = canvas.context
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.scaleBy(x: 0.5, y: 0.5)
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        // Glitter: each glint brightens and fades on its own beat.
        for g in glints {
            let level = pow(max(0, BackdropMotion.wave(time, rate: g.rate, phase: g.phase)), 3)
            guard level > 0.02 else { continue }
            ctx.setStrokeColor(RGB(1, 0.85, 0.6).cg(level * 0.85))
            ctx.setLineWidth(2.2)
            let drift = 6 * BackdropMotion.wave(time, rate: 0.4, phase: g.phase)
            ctx.move(to: CGPoint(x: g.x - g.length / 2 + drift, y: g.y)); ctx.addLine(to: CGPoint(x: g.x + g.length / 2 + drift, y: g.y)); ctx.strokePath()
        }
        // Waves washing up the sand: three lines of foam, each sliding up, thinning and sliding back.
        ctx.setBlendMode(.normal)
        for k in 0..<3 {
            let phase = BackdropMotion.loop(time, period: 7.5, offset: Double(k) / 3)
            let reach = 18 + 92 * sin(phase * .pi)
            let fade = sin(phase * .pi)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -10, y: reach))
            for x in stride(from: 0.0, through: 1290.0, by: 30) {
                path.addLine(to: CGPoint(x: x, y: reach + 6 * sin(x * 0.012 + Double(k) * 2 + phase * 3)))
            }
            path.addLine(to: CGPoint(x: 1290, y: 0)); path.addLine(to: CGPoint(x: -10, y: 0)); path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(RGB(hex: 0x6E5A86).cg(0.18 * fade))
            ctx.fillPath()
            let edge = CGMutablePath()
            edge.move(to: CGPoint(x: -10, y: reach))
            for x in stride(from: 0.0, through: 1290.0, by: 30) {
                edge.addLine(to: CGPoint(x: x, y: reach + 6 * sin(x * 0.012 + Double(k) * 2 + phase * 3)))
            }
            ctx.addPath(edge)
            ctx.setStrokeColor(RGB(1, 0.9, 0.9).cg(0.45 * fade))
            ctx.setLineWidth(3)
            ctx.strokePath()
        }
        // The sea's surface swells: broad patches of light sliding slowly across.
        let sea = BackdropPainter.shimmer(still, at: time, amount: 0.07, scale: 3.5, speed: CGPoint(x: 16, y: 0))
        guard let moving = canvas.image(scale: 2) else { return sea }
        return moving.composited(over: sea)
    }

    /// A palm leaning in from the left edge: a curved trunk and a crown of drooping fronds, all in silhouette.
    private func palm(_ ctx: CGContext) {
        let dark = RGB(hex: 0x1A1026).cg
        let trunk = CGMutablePath()
        trunk.move(to: CGPoint(x: -20, y: 0))
        trunk.addQuadCurve(to: CGPoint(x: 150, y: 600), control: CGPoint(x: 120, y: 260))
        trunk.addLine(to: CGPoint(x: 168, y: 596))
        trunk.addQuadCurve(to: CGPoint(x: 20, y: 0), control: CGPoint(x: 150, y: 250))
        trunk.closeSubpath()
        ctx.addPath(trunk); ctx.setFillColor(dark); ctx.fillPath()
        let crown = CGPoint(x: 158, y: 600)
        for k in 0..<9 {
            let angle = -0.3 + Double(k) * 0.42
            let length = 210.0 + Double(k % 3) * 40
            let tip = CGPoint(x: crown.x + cos(angle) * length, y: crown.y + sin(angle) * length * 0.55 - 70)
            let mid = CGPoint(x: crown.x + cos(angle) * length * 0.5, y: crown.y + sin(angle) * length * 0.4 + 30)
            let frond = CGMutablePath()
            frond.move(to: crown)
            frond.addQuadCurve(to: tip, control: mid)
            ctx.addPath(frond); ctx.setStrokeColor(dark); ctx.setLineWidth(5); ctx.strokePath()
            // Leaflets along the frond.
            for j in 1..<14 {
                let t = Double(j) / 14
                let p = CGPoint(x: (1 - t) * (1 - t) * crown.x + 2 * (1 - t) * t * mid.x + t * t * tip.x,
                                y: (1 - t) * (1 - t) * crown.y + 2 * (1 - t) * t * mid.y + t * t * tip.y)
                let len = 46 * (1 - t * 0.6)
                for side in [-1.0, 1.0] {
                    let a = angle + side * 1.2 - 0.6
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + cos(a) * len, y: p.y + sin(a) * len - 10))
                }
                ctx.setLineWidth(4)
                ctx.strokePath()
            }
        }
    }
}

// MARK: - Forest light

/// A path into a misty wood with sunlight falling in shafts between the trunks, motes of dust drifting in the light.
final class BackdropForestLight: BackdropScene {
    typealias RGB = BackdropRGB
    private struct Mote { let x: Double, y: Double, rise: Double, sway: Double, rate: Double, phase: Double, size: Double }
    private let motes: [Mote]
    private var beams: CIImage?
    private var canvas: BackdropCanvas?
    private var dot: CGImage?

    override init() {
        var rng = SplitMix64(seed: 0xF0457)
        motes = (0..<70).map { _ in
            Mote(x: .random(in: 0.25...0.95, using: &rng), y: .random(in: 0..<1, using: &rng), rise: .random(in: 3...9, using: &rng),
                 sway: .random(in: 6...20, using: &rng), rate: .random(in: 0.2...0.6, using: &rng), phase: .random(in: 0..<(2 * .pi), using: &rng),
                 size: .random(in: 1.2...3.2, using: &rng))
        }
    }

    override func paint() -> CIImage? {
        guard let painted = BackdropPainter.paint(width: 960, height: 540, { ctx in
            // Bright haze deep in the wood, darker toward the edges and the canopy.
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: RGB(hex: 0x4C5A3A)), (at: 0.35, color: RGB(hex: 0x9BB08A)), (at: 0.6, color: RGB(hex: 0xC4D0A6)), (at: 1, color: RGB(hex: 0x5F7046))])
            BackdropPainter.glow(ctx, at: CGPoint(x: 360, y: 560), radius: 600, color: RGB(hex: 0xFFF2C4), alpha: 0.45, blend: .screen)
            var rng = SplitMix64(seed: 0x7EE5)
            // Trunks in three depths: far ones pale and thin in the haze, near ones dark and thick.
            for (count, width, colour) in [(14, 8.0...16.0, RGB(hex: 0x7F8C6A)), (9, 18.0...34.0, RGB(hex: 0x4E5638)), (5, 46.0...90.0, RGB(hex: 0x23261A))] {
                for _ in 0..<count {
                    var x = CGFloat.random(in: -40...1320, using: &rng)
                    if x > 520 && x < 760 && width.upperBound > 40 { x += x < 640 ? -260 : 260 }
                    let w = CGFloat.random(in: CGFloat(width.lowerBound)...CGFloat(width.upperBound), using: &rng)
                    let lean = CGFloat.random(in: -18...18, using: &rng)
                    let trunk = CGMutablePath()
                    trunk.move(to: CGPoint(x: x - w / 2, y: -10)); trunk.addLine(to: CGPoint(x: x - w / 2 * 0.8 + lean, y: 740))
                    trunk.addLine(to: CGPoint(x: x + w / 2 * 0.8 + lean, y: 740)); trunk.addLine(to: CGPoint(x: x + w / 2, y: -10)); trunk.closeSubpath()
                    BackdropPainter.fill(ctx, trunk, gradient: [(at: 0, color: colour.mixed(RGB(hex: 0xE8E0B0), 0.18)), (at: 0.45, color: colour), (at: 1, color: colour.scaled(0.7))],
                                         from: CGPoint(x: x - w / 2, y: 0), to: CGPoint(x: x + w / 2, y: 0))
                }
                // Haze between the layers.
                ctx.setFillColor(RGB(hex: 0xC9D3A8).cg(0.16)); ctx.fill(BackdropPainter.frame)
            }
            // Canopy: dark leafy masses along the top.
            for _ in 0..<40 {
                BackdropPainter.glow(ctx, at: CGPoint(x: CGFloat.random(in: -50...1330, using: &rng), y: CGFloat.random(in: 640...760, using: &rng)),
                                     radius: CGFloat.random(in: 60...140, using: &rng), color: RGB(hex: 0x1F2A14), alpha: 0.8)
            }
            // The path, lighter, narrowing into the distance, and ferns along its edges.
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 420, y: 0)); path.addCurve(to: CGPoint(x: 700, y: 230), control1: CGPoint(x: 560, y: 90), control2: CGPoint(x: 760, y: 150))
            path.addLine(to: CGPoint(x: 722, y: 230)); path.addCurve(to: CGPoint(x: 900, y: 0), control1: CGPoint(x: 800, y: 160), control2: CGPoint(x: 700, y: 80)); path.closeSubpath()
            BackdropPainter.fill(ctx, path, gradient: [(at: 0, color: RGB(hex: 0x5A5238)), (at: 1, color: RGB(hex: 0x9EA07A))], from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 230))
            for _ in 0..<70 {
                var x = CGFloat.random(in: -20...1300, using: &rng)
                if x > 420 && x < 900 { x = x < 660 ? x - 300 : x + 300 }
                let y = CGFloat.random(in: -10...150, using: &rng)
                let size = CGFloat.random(in: 40...90, using: &rng)
                for k in 0..<6 {
                    let a = -0.5 + CGFloat(k) * 0.4 + CGFloat.random(in: -0.1...0.1, using: &rng) + .pi / 2 - 1
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addQuadCurve(to: CGPoint(x: x + cos(a) * size, y: y + sin(a) * size * 0.7), control: CGPoint(x: x + cos(a) * size * 0.4, y: y + sin(a) * size))
                }
                ctx.setStrokeColor(RGB(hex: 0x2D3A1E).cg(0.9)); ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.strokePath()
            }
        }) else { return nil }
        beams = BackdropBake.flatten(makeBeams())
        let soft = BackdropPainter.defocus(painted, sigma: 1.6)
        return BackdropFinish.finish(BackdropFinish.vignette(soft, strength: 0.3), grain: 0.8)
    }

    /// The shafts of light, as a picture of light on black, so each frame can make them breathe without redrawing them.
    private func makeBeams() -> CIImage? {
        BackdropPainter.paint(width: 640, height: 360) { ctx in
            ctx.setFillColor(RGB(0, 0, 0).cg); ctx.fill(BackdropPainter.frame)
            var rng = SplitMix64(seed: 0xBEA5)
            for _ in 0..<7 {
                let top = CGFloat.random(in: 120...700, using: &rng), w = CGFloat.random(in: 40...110, using: &rng)
                let beam = CGMutablePath()
                beam.move(to: CGPoint(x: top - w / 2, y: 740)); beam.addLine(to: CGPoint(x: top + w / 2, y: 740))
                beam.addLine(to: CGPoint(x: top + w * 1.4 + 330, y: -20)); beam.addLine(to: CGPoint(x: top - w * 0.2 + 330, y: -20)); beam.closeSubpath()
                ctx.saveGState()
                ctx.addPath(beam); ctx.clip()
                if let g = BackdropPaint.gradient([(at: 0, r: 1, g: 0.95, b: 0.75, a: 0.0), (at: 0.4, r: 1, g: 0.95, b: 0.75, a: 0.22), (at: 1, r: 1, g: 0.95, b: 0.75, a: 0.5)]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 720), options: [])
                }
                ctx.restoreGState()
            }
        }.map { BackdropPainter.defocus($0, sigma: 14) }
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        if canvas == nil { canvas = BackdropCanvas(width: 640, height: 360) }
        if dot == nil { dot = BackdropSprite.glow(RGB(1, 0.96, 0.82), side: 32, core: 0.9) }
        guard let beams, let canvas, let dot else { return still }
        let frame = BackdropPainter.frame
        // The shafts breathe: a slow wash of noise drifting across them brightens some and dims others.
        let breath = BackdropNoise.field(2, scale: 5, offset: CGPoint(x: time * 9, y: time * 2), extent: frame)
        let lit = beams.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: breath])
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1.5, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1.5, z: 0, w: 0),
                                                          "inputBVector": CIVector(x: 0, y: 0, z: 1.5, w: 0)])
        canvas.clear()
        let ctx = canvas.context
        ctx.setBlendMode(.plusLighter)
        for m in motes {
            let y = BackdropMath.fract(m.y + m.rise * time / 380) * 380 - 10
            let x = m.x * 640 + m.sway * BackdropMotion.wave(time, rate: m.rate, phase: m.phase)
            let twinkle = 0.5 + 0.5 * BackdropMotion.wave(time, rate: m.rate * 3, phase: m.phase * 2)
            ctx.setAlpha(CGFloat(0.25 + 0.5 * twinkle))
            let r = m.size
            ctx.draw(dot, in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        guard let dust = canvas.image(scale: 2) else { return still }
        let glowing = lit.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: still]).cropped(to: frame)
        return BackdropFinish.finish(dust.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: glowing]).cropped(to: frame))
    }
}

// MARK: - Snowy cabin

/// Looking out of a log cabin's window on a winter evening: snow falling past dark pines and a far, lit cabin, the warm
/// glow of the fire on the wooden walls inside, a candle on the sill.
final class BackdropSnowyCabin: BackdropScene {
    typealias RGB = BackdropRGB
    private static let glass = CGRect(x: 330, y: 150, width: 620, height: 500)
    private struct Flake { let x: Double, y: Double, fall: Double, sway: Double, rate: Double, phase: Double, size: Double }
    private let flakes: [Flake]
    private var outside: CIImage?
    private var room: CIImage?
    private var canvas: BackdropCanvas?
    private var flake: CGImage?

    override init() {
        var rng = SplitMix64(seed: 0x5A0)
        flakes = (0..<160).map { _ in
            let near = pow(Double.random(in: 0..<1, using: &rng), 2)
            return Flake(x: .random(in: 0..<1, using: &rng), y: .random(in: 0..<1, using: &rng), fall: 18 + 40 * near, sway: .random(in: 4...16, using: &rng),
                         rate: .random(in: 0.3...0.9, using: &rng), phase: .random(in: 0..<(2 * .pi), using: &rng), size: 1.0 + 4.0 * near)
        }
    }

    override func paint() -> CIImage? {
        outside = BackdropBake.flatten(paintOutside())
        room = BackdropBake.flatten(paintRoom())
        guard let outside, let room else { return nil }
        return room.composited(over: outside)
    }

    private func paintOutside() -> CIImage? {
        guard let view = BackdropPainter.paint(width: 960, height: 540, { ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0.2, color: RGB(hex: 0x8FA6C8)), (at: 0.5, color: RGB(hex: 0x4E6A98)), (at: 1, color: RGB(hex: 0x1E2C52))])
            var rng = SplitMix64(seed: 0x5A1)
            BackdropPainter.fill(ctx, BackdropPainter.ridge(BackdropPainter.ridgeLine(base: 300, height: 90, seed: 3.3, wavelength: 300, rough: 0.2), floor: 0), RGB(hex: 0x9DB0CE).cg)
            // A far cabin with a lit window.
            ctx.setFillColor(RGB(hex: 0x2B3550).cg); ctx.fill(CGRect(x: 760, y: 300, width: 70, height: 40))
            let roof = CGMutablePath(); roof.move(to: CGPoint(x: 750, y: 338)); roof.addLine(to: CGPoint(x: 795, y: 372)); roof.addLine(to: CGPoint(x: 840, y: 338)); roof.closeSubpath()
            ctx.addPath(roof); ctx.setFillColor(RGB(hex: 0xE4ECF6).cg); ctx.fillPath()
            ctx.setFillColor(RGB(hex: 0xFFC36B).cg); ctx.fill(CGRect(x: 776, y: 312, width: 14, height: 12))
            BackdropPainter.glow(ctx, at: CGPoint(x: 783, y: 318), radius: 40, color: RGB(hex: 0xFFB45A), alpha: 0.6, blend: .screen)
            for _ in 0..<26 {
                BackdropLandscape.pine(ctx, x: CGFloat.random(in: 300...1000, using: &rng), base: 280, height: CGFloat.random(in: 60...130, using: &rng),
                                       color: RGB(hex: 0x24324F).cg, rng: &rng, snow: RGB(hex: 0xC9D6EA).cg)
            }
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: 290), [(at: 0, color: RGB(hex: 0xB8C7DE)), (at: 1, color: RGB(hex: 0xDCE6F2))])
            for _ in 0..<10 {
                var x = CGFloat.random(in: 300...1000, using: &rng)
                if x > 520 && x < 760 { x += 260 }
                BackdropLandscape.pine(ctx, x: x, base: 180, height: CGFloat.random(in: 180...300, using: &rng), color: RGB(hex: 0x16213A).cg, rng: &rng,
                                       snow: RGB(hex: 0xD8E2F0).cg)
            }
        }) else { return nil }
        return BackdropPainter.defocus(view, sigma: 1.5)
    }

    /// The inside: log walls lit warm from the left, the window frame and sill, a candle. Transparent where the glass is.
    private func paintRoom() -> CIImage? {
        BackdropPainter.paint(width: 960, height: 540) { ctx in
            let glass = Self.glass
            ctx.saveGState()
            let wall = CGMutablePath()
            wall.addRect(BackdropPainter.frame)
            wall.addRect(glass)
            ctx.addPath(wall)
            ctx.clip(using: .evenOdd)
            // Logs: rounded horizontal timbers, each lit from above.
            var rng = SplitMix64(seed: 0x1065)
            for y in stride(from: CGFloat(-20), to: 740, by: 46) {
                let tone = RGB(hex: 0x6B4426).scaled(Double.random(in: 0.85...1.1, using: &rng))
                BackdropPainter.fill(ctx, BackdropPainter.rounded(CGRect(x: -10, y: y, width: 1300, height: 44), 22),
                                     gradient: [(at: 0, color: tone.scaled(0.55)), (at: 0.55, color: tone), (at: 0.85, color: tone.mixed(RGB(hex: 0xE8B070), 0.25)), (at: 1, color: tone.scaled(0.7))],
                                     from: CGPoint(x: 0, y: y), to: CGPoint(x: 0, y: y + 44))
            }
            // Firelight from the left and dark at the right.
            BackdropPainter.glow(ctx, at: CGPoint(x: -60, y: 260), radius: 760, color: RGB(hex: 0xFF9A4A), alpha: 0.5, blend: .screen)
            BackdropPainter.glow(ctx, at: CGPoint(x: 1340, y: 380), radius: 700, color: RGB(0, 0, 0), alpha: 0.5)
            ctx.restoreGState()
            // Frame and cross bars.
            let wood = RGB(hex: 0x4A2E18)
            ctx.setFillColor(wood.cg)
            let bar: CGFloat = 16
            ctx.fill(CGRect(x: glass.minX - 22, y: glass.minY - 22, width: glass.width + 44, height: 22))
            ctx.fill(CGRect(x: glass.minX - 22, y: glass.maxY, width: glass.width + 44, height: 22))
            ctx.fill(CGRect(x: glass.minX - 22, y: glass.minY, width: 22, height: glass.height))
            ctx.fill(CGRect(x: glass.maxX, y: glass.minY, width: 22, height: glass.height))
            ctx.fill(CGRect(x: glass.midX - bar / 2, y: glass.minY, width: bar, height: glass.height))
            ctx.fill(CGRect(x: glass.minX, y: glass.minY + glass.height * 0.55 - bar / 2, width: glass.width, height: bar))
            // Snow piled in the corners of the panes, and frost creeping in.
            for (x, y) in [(glass.minX, glass.minY), (glass.midX + bar / 2, glass.minY), (glass.minX, glass.minY + glass.height * 0.55 + bar / 2), (glass.midX + bar / 2, glass.minY + glass.height * 0.55 + bar / 2)] {
                let drift = CGMutablePath()
                drift.move(to: CGPoint(x: x, y: y)); drift.addQuadCurve(to: CGPoint(x: x + 120, y: y), control: CGPoint(x: x + 30, y: y + 26)); drift.closeSubpath()
                ctx.addPath(drift); ctx.setFillColor(RGB(hex: 0xEEF3FA).cg(0.9)); ctx.fillPath()
                BackdropPainter.glow(ctx, at: CGPoint(x: x + 10, y: y + 10), radius: 70, color: RGB(1, 1, 1), alpha: 0.25)
            }
            // The sill and a candle on it, glowing.
            BackdropPainter.fill(ctx, CGPath(rect: CGRect(x: glass.minX - 50, y: glass.minY - 46, width: glass.width + 100, height: 26), transform: nil),
                                 gradient: [(at: 0, color: RGB(hex: 0x3A2414)), (at: 1, color: RGB(hex: 0x8A5A30))], from: CGPoint(x: 0, y: glass.minY - 46), to: CGPoint(x: 0, y: glass.minY - 20))
            let candle = CGRect(x: glass.maxX - 90, y: glass.minY - 20, width: 26, height: 70)
            BackdropPainter.fill(ctx, BackdropPainter.rounded(candle, 4), gradient: [(at: 0, color: RGB(hex: 0xFFF3DC)), (at: 1, color: RGB(hex: 0xD8C6A6))], from: CGPoint(x: candle.minX, y: 0), to: CGPoint(x: candle.maxX, y: 0))
            BackdropPainter.glow(ctx, at: CGPoint(x: candle.midX, y: candle.maxY + 14), radius: 160, color: RGB(hex: 0xFFB45A), alpha: 0.45, blend: .screen)
            BackdropPainter.glow(ctx, at: CGPoint(x: candle.midX, y: candle.maxY + 12), radius: 12, color: RGB(1, 0.92, 0.6), alpha: 1, squash: 1.8, blend: .screen)
        }.map { BackdropFinish.vignette(BackdropPainter.defocus($0, sigma: 1.2), strength: 0.25) }
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        if canvas == nil { canvas = BackdropCanvas(width: 640, height: 360) }
        if flake == nil { flake = BackdropSprite.glow(RGB(1, 1, 1), side: 32, core: 1) }
        guard let canvas, let flake, let outside, let room else { return still }
        canvas.clear()
        let ctx = canvas.context
        let g = Self.glass
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: CGRect(x: g.minX / 2, y: g.minY / 2, width: g.width / 2, height: g.height / 2))
        for f in flakes {
            let y = Double(g.minY / 2) + (1 - BackdropMath.fract(f.y + f.fall * time / 300)) * Double(g.height / 2 + 20) - 10
            let x = Double(g.minX / 2) + f.x * Double(g.width / 2) + f.sway * BackdropMotion.wave(time, rate: f.rate, phase: f.phase)
            ctx.setAlpha(CGFloat(0.5 + 0.12 * f.size))
            let r = f.size
            ctx.draw(flake, in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        guard let snow = canvas.image(scale: 2) else { return still }
        // Firelight moving on the log walls.
        let firelit = BackdropPainter.shimmer(room, at: time, amount: 0.08, scale: 4, speed: CGPoint(x: 0, y: 22), channel: 2)
        return BackdropFinish.finish(firelit.composited(over: snow.composited(over: outside)))
    }
}
