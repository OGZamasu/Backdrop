import CoreGraphics
import CoreImage

/// A big striped sun setting over a neon grid that rolls toward you.
///
/// The sky, sun, hills, the sun's reflection on the floor and the grid's long lines are painted once, smoothly (16 bits a
/// channel, then dithered, so the long sky gradient cannot band). Each frame redraws only the grid's cross lines, which
/// are all that move, each with a soft glow under a bright core.
final class SynthwaveSource: BackgroundSource {
    private static let size = CGSize(width: 1280, height: 720)
    private static let horizon: CGFloat = 292           // height of the horizon above the bottom edge
    private static let vanishing = CGPoint(x: 640, y: horizon)
    private static let sunCentre = CGPoint(x: 905, y: horizon + 92)
    private static let sunRadius: CGFloat = 178

    /// The palette: night indigo, violet, magenta, hot pink, sunset orange and gold; the grid's neon pink and its core.
    private enum Palette {
        static let night = BackdropRGB(hex: 0x0B0322), violet = BackdropRGB(hex: 0x2C0A55), magenta = BackdropRGB(hex: 0x9E1A7E)
        static let pink = BackdropRGB(hex: 0xFF3D8B), orange = BackdropRGB(hex: 0xFF8A4C), gold = BackdropRGB(hex: 0xFFD45E)
        static let neon = BackdropRGB(hex: 0xFF38C8), core = BackdropRGB(hex: 0xFFB0F0)
    }

    private var backdrop: CIImage?
    private var canvas: BackdropCanvas?

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        if backdrop == nil { backdrop = BackdropBake.flatten(Self.makeBackdrop()) }
        if canvas == nil { canvas = BackdropCanvas(width: Int(Self.size.width), height: Int(Self.horizon) + 2) }
        guard let backdrop, let canvas else { return nil }
        canvas.clear()
        drawCrossLines(into: canvas.context, at: time)
        guard let lines = canvas.image() else { return backdrop }
        return lines.composited(over: backdrop)
    }

    // MARK: The moving part

    /// Lines across the floor. Seen in perspective, a line `u` steps away sits `k / (u + a)` below the horizon, so the
    /// floor's lines bunch together toward the horizon; sliding `u` along makes the grid roll in.
    private func drawCrossLines(into ctx: CGContext, at time: CFTimeInterval) {
        let phase = BackdropMath.fract(time * 0.42)
        let nearest = 0.30
        let span = Double(Self.horizon)
        ctx.setLineCap(.butt)
        for i in 0..<26 {
            let steps = Double(i) + 1 - phase
            let below = span * nearest / (nearest + steps * 0.62)      // pixels under the horizon
            guard below > 1.5 else { continue }
            let y = Double(Self.horizon) - below
            let strength = BackdropMath.smoothstep(2, 70, below)       // fade into the haze toward the horizon
            let width = 0.7 + 2.6 * BackdropMath.smoothstep(0, span, below)
            for (scale, alpha, colour) in [(7.0, 0.07, Palette.neon), (3.2, 0.18, Palette.neon), (1.0, 0.95, Palette.core)] {
                ctx.setStrokeColor(colour.cg(alpha * strength))
                ctx.setLineWidth(CGFloat(width * scale))
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: Self.size.width, y: y)); ctx.strokePath()
            }
        }
    }

    // MARK: The still part

    private static func makeBackdrop() -> CIImage? {
        guard let painted = BackdropPainter.paint({ ctx in
            let h = horizon
            // Sky: night at the top, through violet and magenta to a hot glow at the horizon.
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: h, width: 1280, height: 720 - h), [
                (at: 0.0, color: Palette.orange.mixed(Palette.pink, 0.4)), (at: 0.12, color: Palette.pink.scaled(0.9)),
                (at: 0.36, color: Palette.magenta), (at: 0.66, color: Palette.violet), (at: 1.0, color: Palette.night),
            ])
            var rng = SplitMix64(seed: 0x5917)
            for _ in 0..<90 {
                let y = CGFloat.random(in: (h + 220)..<720, using: &rng)
                let x = CGFloat.random(in: 0..<1280, using: &rng)
                let r = CGFloat.random(in: 0.5...1.4, using: &rng)
                ctx.setFillColor(BackdropRGB(1, 0.9, 1).cg(Double.random(in: 0.25...0.85, using: &rng) * Double((y - h - 200) / (720 - h - 200))))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            drawSun(into: ctx)
            drawHills(into: ctx)
            // Floor: deep violet, glowing where it meets the horizon.
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: h), [
                (at: 0, color: BackdropRGB(hex: 0x080114)), (at: 0.8, color: BackdropRGB(hex: 0x1E0538)), (at: 1, color: BackdropRGB(hex: 0x4A0C5E)),
            ])
            // The sun's reflection on the floor: a soft column of warm light under it.
            BackdropPainter.glow(ctx, at: CGPoint(x: sunCentre.x, y: h - 10), radius: 260, color: Palette.pink, alpha: 0.38, squash: 0.45, blend: .screen)
            BackdropPainter.glow(ctx, at: CGPoint(x: sunCentre.x, y: h - 60), radius: 120, color: Palette.orange, alpha: 0.30, squash: 1.6, blend: .screen)
            drawLongLines(into: ctx)
            // Haze where the floor meets the sky, over the far ends of the lines.
            if let haze = BackdropPaint.gradient([(at: 0, r: 1.0, g: 0.42, b: 0.62, a: 0.62), (at: 1, r: 1.0, g: 0.42, b: 0.62, a: 0)]) {
                ctx.drawLinearGradient(haze, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h - 80), options: [])
                ctx.drawLinearGradient(haze, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h + 46), options: [])
            }
            ctx.setFillColor(BackdropRGB(1, 0.78, 0.92).cg(0.9))
            ctx.fill(CGRect(x: 0, y: h - 1.2, width: 1280, height: 2.4))
        }) else { return nil }
        return BackdropFinish.finish(painted, grain: 0.6)
    }

    /// The sun: a bloom of light, then a disc from gold at the top to hot pink at the foot, cut by slits that widen downward.
    private static func drawSun(into ctx: CGContext) {
        let c = sunCentre, r = sunRadius
        BackdropPainter.glow(ctx, at: c, radius: r * 2.6, color: Palette.pink, alpha: 0.42, blend: .screen)
        BackdropPainter.glow(ctx, at: c, radius: r * 1.35, color: Palette.orange, alpha: 0.40, blend: .screen)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: horizon, width: 1280, height: 720))   // the foot of the sun sinks below the horizon
        let disc = CGMutablePath()
        disc.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        // The slits are gaps, so they are cut out of the disc rather than painted over it.
        var y = c.y + r * 0.12
        var gap: CGFloat = 3
        while y > c.y - r {
            disc.addRect(CGRect(x: c.x - r - 2, y: y - gap, width: r * 2 + 4, height: gap))
            y -= gap + 13 + (c.y - y) * 0.035
            gap += 2.6
        }
        ctx.addPath(disc)
        ctx.clip(using: .evenOdd)
        BackdropPainter.vertical(ctx, CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), [
            (at: 0, color: Palette.pink), (at: 0.45, color: Palette.orange), (at: 0.85, color: Palette.gold), (at: 1, color: BackdropRGB(hex: 0xFFF0A0)),
        ])
        ctx.restoreGState()
    }

    /// Two ranges of low hills along the horizon: the far one hazy and pink-edged, the near one dark with a neon rim on
    /// the side facing the sun. They part around the sun so it is not hidden.
    private static func drawHills(into ctx: CGContext) {
        let ranges: [(height: CGFloat, seed: Double, top: BackdropRGB, bottom: BackdropRGB, rim: Double)] = [
            (78, 3.1, BackdropRGB(hex: 0x5A1470), BackdropRGB(hex: 0x2A0846), 0.35),
            (44, 7.7, BackdropRGB(hex: 0x220634), BackdropRGB(hex: 0x12021E), 0.85),
        ]
        for range in ranges {
            var ridge: [CGPoint] = []
            for x in stride(from: -8.0, through: 1288.0, by: 8) {
                let wave = BackdropNoise.ridge(x / 140, seed: range.seed, octaves: 6)
                let sides = BackdropMath.smoothstep(150, 430, abs(x - Double(sunCentre.x)))
                ridge.append(CGPoint(x: x, y: horizon + range.height * CGFloat((wave * 0.5 + 0.5) * sides)))
            }
            BackdropPainter.fill(ctx, BackdropPainter.ridge(ridge, floor: horizon), gradient: [(at: 0, color: range.bottom), (at: 1, color: range.top)],
                                 from: CGPoint(x: 0, y: horizon), to: CGPoint(x: 0, y: horizon + range.height))
            let edge = CGMutablePath()
            edge.addLines(between: ridge)
            ctx.addPath(edge)
            ctx.setStrokeColor(Palette.neon.cg(range.rim * 0.25))
            ctx.setLineWidth(5)
            ctx.strokePath()
            ctx.addPath(edge)
            ctx.setStrokeColor(Palette.core.cg(range.rim))
            ctx.setLineWidth(1.4)
            ctx.strokePath()
        }
    }

    /// The lines that run away to the vanishing point, glow first, then the bright core. They are the same in every frame.
    private static func drawLongLines(into ctx: CGContext) {
        ctx.setLineCap(.butt)
        for j in -16...16 {
            let foot = CGPoint(x: vanishing.x + CGFloat(j) * 170, y: 0)
            let alpha = j == 0 ? 0.55 : 1.0
            for (width, a, colour) in [(CGFloat(12), 0.06, Palette.neon), (5, 0.16, Palette.neon), (1.7, 0.9, Palette.core)] {
                ctx.setStrokeColor(colour.cg(a * alpha))
                ctx.setLineWidth(width)
                ctx.move(to: vanishing); ctx.addLine(to: foot); ctx.strokePath()
            }
        }
    }
}
