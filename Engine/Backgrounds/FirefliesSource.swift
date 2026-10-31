import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// A summer night at the edge of a wood, with fireflies drifting about and blinking.
///
/// The night is painted once in depth: a moonlit sky, far hills, then rows of pines that get darker and bigger toward
/// you with mist lying between them, each row edged with a thread of moonlight, and long grass in front. Each frame adds
/// the fireflies on a half-size surface, as light: far ones small and dim, near ones large, soft and out of focus.
/// Where a firefly is and how bright it is come from the clock alone.
final class FirefliesSource: BackgroundSource {
    private struct Fly {
        let x: Double, y: Double                         // the middle of its wandering, as shares of the picture
        let reachX: Double, reachY: Double               // how far it wanders, in half-size pixels
        let rateX: Double, rateY: Double, phaseX: Double, phaseY: Double
        let blinkPeriod: Double, blinkPhase: Double
        let depth: Double                                // 0 far ... 1 near
    }

    private static let size = CGSize(width: 1280, height: 720)
    private static let half = CGSize(width: 640, height: 360)
    /// Night colours: deep sky, teal haze near the horizon, the near-black greens of the trees, moonlight.
    private enum Palette {
        static let zenith = BackdropRGB(hex: 0x040817), sky = BackdropRGB(hex: 0x0A1C2C), haze = BackdropRGB(hex: 0x1B3A44)
        static let far = BackdropRGB(hex: 0x0E2631), middle = BackdropRGB(hex: 0x07161C), near = BackdropRGB(hex: 0x030B0E)
        static let moonlight = BackdropRGB(hex: 0xBFE3EA), glow = BackdropRGB(hex: 0xC8F56A)
    }

    private let flies: [Fly]
    private var canvas: BackdropCanvas?
    private var night: CIImage?
    private var glow: CGImage?
    private var soft: CGImage?

    init(seed: UInt64 = 0xF1F1) {
        var rng = SplitMix64(seed: seed)
        flies = (0..<46).map { _ in
            let depth = pow(Double.random(in: 0..<1, using: &rng), 1.6)
            return Fly(x: .random(in: 0.03...0.97, using: &rng), y: 0.12 + 0.36 * (1 - depth) * .random(in: 0.4...1.0, using: &rng) + 0.1 * depth,
                       reachX: .random(in: 14...60, using: &rng), reachY: .random(in: 10...30, using: &rng),
                       rateX: .random(in: 0.08...0.30, using: &rng), rateY: .random(in: 0.10...0.36, using: &rng),
                       phaseX: .random(in: 0..<(2 * .pi), using: &rng), phaseY: .random(in: 0..<(2 * .pi), using: &rng),
                       blinkPeriod: .random(in: 2.6...6.2, using: &rng), blinkPhase: .random(in: 0..<1, using: &rng), depth: depth)
        }
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        if canvas == nil { canvas = BackdropCanvas(width: Int(Self.half.width), height: Int(Self.half.height)) }
        if night == nil { night = BackdropBake.flatten(Self.makeNight()) }
        if glow == nil { glow = BackdropSprite.glow(Palette.glow, side: 64, core: 1, hot: 0.9) }
        if soft == nil { soft = BackdropSprite.bokeh(Palette.glow.mixed(BackdropRGB(1, 0.95, 0.6), 0.3), side: 64, softness: 4) }
        guard let canvas, let night, let glow, let soft else { return nil }

        canvas.clear()
        let ctx = canvas.context
        ctx.setBlendMode(.plusLighter)
        for fly in flies {
            // Each one lights up for a moment, fades, and stays nearly dark for a while.
            let beat = BackdropMotion.loop(time, period: fly.blinkPeriod, offset: fly.blinkPhase)
            let lit = pow(max(0, sin(beat * .pi)), 3.2)
            let at = CGPoint(x: Self.half.width * fly.x + fly.reachX * BackdropMotion.wave(time, rate: fly.rateX, phase: fly.phaseX),
                             y: Self.half.height * fly.y + fly.reachY * BackdropMotion.wave(time, rate: fly.rateY, phase: fly.phaseY)
                                + 3 * BackdropMotion.wave(time, rate: 1.9, phase: fly.phaseX))
            if fly.depth > 0.8 {
                // So near it is out of focus: a soft disc that swells a little as it lights.
                let radius = CGFloat(9 + 6 * fly.depth) * CGFloat(0.85 + 0.25 * lit)
                ctx.setAlpha(CGFloat(0.03 + 0.32 * lit))
                ctx.draw(soft, in: CGRect(x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2))
                continue
            }
            let scale = 0.55 + 0.9 * fly.depth
            let radius = CGFloat(10 * scale * (0.6 + 0.6 * lit))
            ctx.setAlpha(CGFloat((0.05 + 0.95 * lit) * (0.55 + 0.45 * fly.depth)))
            ctx.draw(glow, in: CGRect(x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2))
        }
        ctx.setAlpha(1)
        ctx.setBlendMode(.normal)

        guard let lights = canvas.image(scale: Self.size.width / Self.half.width) else { return night }
        let add = CIFilter.additionCompositing()
        add.inputImage = lights
        add.backgroundImage = night
        return add.outputImage?.cropped(to: CGRect(origin: .zero, size: Self.size)) ?? night
    }

    // MARK: Still pieces

    private static func makeNight() -> CIImage? {
        guard let painted = BackdropPainter.paint({ ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: Palette.haze), (at: 0.32, color: Palette.sky), (at: 1, color: Palette.zenith)])
            // Moon, with a wide pale halo and faint seas on its face.
            let moon = CGPoint(x: 1010, y: 590)
            BackdropPainter.glow(ctx, at: moon, radius: 380, color: Palette.moonlight, alpha: 0.16, blend: .screen)
            BackdropPainter.glow(ctx, at: moon, radius: 110, color: Palette.moonlight, alpha: 0.35, blend: .screen)
            BackdropPainter.fill(ctx, CGPath(ellipseIn: CGRect(x: moon.x - 32, y: moon.y - 32, width: 64, height: 64), transform: nil),
                                 gradient: [(at: 0, color: BackdropRGB(hex: 0xEAF4F6)), (at: 1, color: BackdropRGB(hex: 0xC9DCE2))],
                                 from: CGPoint(x: moon.x - 20, y: moon.y + 24), to: CGPoint(x: moon.x + 26, y: moon.y - 26))
            for (dx, dy, r) in [(CGFloat(8), CGFloat(6), CGFloat(9)), (-12, -8, 7), (-4, 14, 5), (14, -14, 4)] {
                BackdropPainter.glow(ctx, at: CGPoint(x: moon.x + dx, y: moon.y + dy), radius: r, color: BackdropRGB(hex: 0x9FB7BF), alpha: 0.6)
            }
            var rng = SplitMix64(seed: 0x57AB)
            for _ in 0..<70 {
                let at = CGPoint(x: .random(in: 0..<1280, using: &rng), y: .random(in: 360..<720, using: &rng))
                let r = CGFloat.random(in: 0.5...1.2, using: &rng)
                ctx.setFillColor(BackdropRGB(0.9, 0.95, 1).cg(Double.random(in: 0.2...0.7, using: &rng) * Double((at.y - 330) / 390)))
                ctx.fillEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2))
            }
            // Far hills, then mist, then rows of pines, each with mist settling in front of it.
            BackdropPainter.fill(ctx, BackdropPainter.ridge(BackdropPainter.ridgeLine(base: 210, height: 80, seed: 1.7, wavelength: 260), floor: 0), Palette.far.cg)
            mist(ctx, y: 200, depth: 70, alpha: 0.30)
            pines(ctx, rng: &rng, base: 170, count: 30, height: 150, color: Palette.middle, rim: 0.20)
            mist(ctx, y: 150, depth: 60, alpha: 0.22)
            pines(ctx, rng: &rng, base: 96, count: 14, height: 300, color: Palette.near, rim: 0.12, keepClear: 330...950)
            // Long grass in front.
            ctx.setFillColor(BackdropRGB(hex: 0x020607).cg)
            ctx.fill(CGRect(x: 0, y: 0, width: 1280, height: 50))
            for _ in 0..<460 {
                let x = CGFloat.random(in: -10..<1290, using: &rng)
                let h = CGFloat.random(in: 24...110, using: &rng)
                let lean = CGFloat.random(in: -24...24, using: &rng)
                let blade = CGMutablePath()
                blade.move(to: CGPoint(x: x - 2.5, y: 36))
                blade.addQuadCurve(to: CGPoint(x: x + lean, y: 36 + h), control: CGPoint(x: x - 1, y: 36 + h * 0.5))
                blade.addQuadCurve(to: CGPoint(x: x + 2.5, y: 36), control: CGPoint(x: x + lean * 0.4 + 1, y: 36 + h * 0.5))
                ctx.addPath(blade)
                ctx.fillPath()
            }
        }) else { return nil }
        return BackdropFinish.finish(BackdropFinish.vignette(painted, strength: 0.25), grain: 0.8)
    }

    /// A band of moonlit mist lying at `y`, fading up and down.
    private static func mist(_ ctx: CGContext, y: CGFloat, depth: CGFloat, alpha: Double) {
        let c = Palette.haze.mixed(Palette.moonlight, 0.25)
        guard let g = BackdropPaint.gradient([(at: 0, r: c.r, g: c.g, b: c.b, a: 0), (at: 0.5, r: c.r, g: c.g, b: c.b, a: alpha), (at: 1, r: c.r, g: c.g, b: c.b, a: 0)]) else { return }
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y - depth), end: CGPoint(x: 0, y: y + depth), options: [])
    }

    /// A row of pines standing on `base`: ragged tiers of branches, each tree first drawn in moonlight a hair up and to the
    /// right of itself, so a thread of light edges the side facing the moon.
    private static func pines(_ ctx: CGContext, rng: inout SplitMix64, base: CGFloat, count: Int, height: CGFloat, color: BackdropRGB,
                              rim: Double, keepClear: ClosedRange<CGFloat>? = nil) {
        ctx.setFillColor(color.cg)
        ctx.fill(CGRect(x: 0, y: 0, width: 1280, height: base))
        for i in 0..<count {
            let x = (CGFloat(i) + CGFloat.random(in: 0.1...0.9, using: &rng)) * 1280 / CGFloat(count)
            var h = height * CGFloat.random(in: 0.55...1.0, using: &rng)
            if let keepClear, keepClear.contains(x) { h *= 0.45 }
            let w = h * CGFloat.random(in: 0.24...0.32, using: &rng)
            let tree = CGMutablePath()
            let tiers = 7
            for t in 0..<tiers {
                let f = CGFloat(t) / CGFloat(tiers)
                let y0 = base + h * f * 0.82
                let tierW = w * (1 - f * 0.82) * CGFloat.random(in: 0.85...1.1, using: &rng)
                let top = y0 + h * 0.26
                // Ragged lower edge: a few drooping points instead of a straight line.
                tree.move(to: CGPoint(x: x, y: top))
                tree.addLine(to: CGPoint(x: x - tierW, y: y0 - h * 0.02))
                for k in 1..<4 {
                    let px = x - tierW + tierW * 2 * CGFloat(k) / 4
                    tree.addLine(to: CGPoint(x: px - tierW * 0.12, y: y0 + h * 0.035))
                    tree.addLine(to: CGPoint(x: px, y: y0 - h * CGFloat.random(in: 0.0...0.03, using: &rng)))
                }
                tree.addLine(to: CGPoint(x: x + tierW, y: y0 - h * 0.02))
                tree.closeSubpath()
            }
            tree.addRect(CGRect(x: x - w * 0.06, y: base - 4, width: w * 0.12, height: h * 0.2))
            ctx.saveGState()
            ctx.translateBy(x: 1.6, y: 1.2)
            ctx.addPath(tree)
            ctx.setFillColor(Palette.moonlight.cg(rim))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(tree)
            ctx.setFillColor(color.cg)
            ctx.fillPath()
        }
    }
}
