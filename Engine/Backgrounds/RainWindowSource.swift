import CoreGraphics
import CoreImage

/// Rain running down a window at night, over the blurred lights of a city.
///
/// The street outside is painted once, far out of focus: lamps and windows become soft discs, shop signs soft bars of
/// colour, car lights a red and white smear along the bottom. The glass is fogged a little, more toward the bottom, and
/// covered in beads of water; each bead is a tiny lens, so it shows the street inside it upside down and sharper, with a
/// glint at the top and a dark edge underneath. Each frame draws only the drops that are running, in fits and starts,
/// each wiping a clear trail through the fog and leaving a few small beads behind. Where a drop is comes from the clock.
final class RainWindowSource: BackgroundSource {
    private struct Runner {
        let x: Double
        let period: Double            // seconds to run the whole height of the glass
        let phase: Double
        let radius: Double
        let wobble: Double
    }

    private static let size = CGSize(width: 1280, height: 720)
    private let runners: [Runner]
    private var canvas: BackdropCanvas?
    private var window: CIImage?
    private var street: CGImage?
    /// The street at a tenth of its size: all a drop ever shows of it, and far cheaper to draw into one.
    private var thumb: CGImage?

    init(seed: UInt64 = 0x4A1D) {
        var rng = SplitMix64(seed: seed)
        runners = (0..<14).map { i in
            Runner(x: (Double(i) + .random(in: 0.1...0.9, using: &rng)) / 14 * Self.size.width,
                   period: .random(in: 7...17, using: &rng), phase: .random(in: 0..<1, using: &rng),
                   radius: .random(in: 5...9, using: &rng), wobble: .random(in: 0..<(2 * .pi), using: &rng))
        }
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        if street == nil { street = Self.makeStreet() }
        if window == nil, let street { window = BackdropBake.flatten(Self.makeWindow(street)) }
        if canvas == nil { canvas = BackdropCanvas(width: Int(Self.size.width), height: Int(Self.size.height)) }
        if thumb == nil, let street { thumb = Self.shrunk(street) }
        guard let canvas, let window, let thumb else { return nil }

        canvas.clear()
        let ctx = canvas.context
        for runner in runners { draw(runner, street: thumb, into: ctx, at: time) }
        // The lights outside shimmer through the rain on the glass.
        let alive = BackdropPainter.shimmer(window, at: time, amount: 0.09, scale: 3, speed: CGPoint(x: 9, y: -14))
        guard let drops = canvas.image() else { return alive }
        return drops.composited(over: alive)
    }

    // MARK: Running drops

    private func draw(_ runner: Runner, street: CGImage, into ctx: CGContext, at time: CFTimeInterval) {
        // Falls from the top to the bottom in fits and starts: it hangs, then slides, then hangs again.
        let progress = BackdropMotion.loop(time, period: runner.period, offset: runner.phase)
        let stutter = progress + 0.03 * sin(progress * 2 * .pi * 7 + runner.wobble)
        let y = Self.size.height * (1.06 - stutter * 1.12)
        let wander = { (p: Double) in runner.x + 4 * sin(p * 2 * .pi * 3 + runner.wobble) }
        let x = wander(progress)
        let r = runner.radius

        // The trail it has wiped through the fog: a darker, clearer streak, narrowing and fading as it goes up.
        let trail = min(260, (1.06 * Self.size.height - y))
        if trail > 4 {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: y))
            var k = 1.0
            while k <= 8 {
                let back = progress - (trail / (Self.size.height * 1.12)) * k / 8
                path.addLine(to: CGPoint(x: wander(back), y: y + trail * k / 8))
                k += 1
            }
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(path)
            ctx.setStrokeColor(BackdropPaint.color(0.0, 0.02, 0.06, 0.16))
            ctx.setLineWidth(CGFloat(r * 1.1))
            ctx.strokePath()
            ctx.addPath(path)
            ctx.setStrokeColor(BackdropPaint.color(0.85, 0.92, 1, 0.10))
            ctx.setLineWidth(1)
            ctx.strokePath()
            ctx.restoreGState()
            // Small beads left behind in the trail.
            for k in 1...3 {
                let f = Double(k) / 3.5
                let bead = CGPoint(x: wander(progress - trail * f / (Self.size.height * 1.12)) + (k % 2 == 0 ? 1.5 : -1.5), y: y + trail * f)
                Self.bead(in: ctx, street: street, at: bead, radius: r * 0.32, stretch: 1.1)
            }
        }
        Self.bead(in: ctx, street: street, at: CGPoint(x: x, y: y), radius: r, stretch: 1.3)
    }

    /// A drop of water on glass: a little lens showing the street upside down inside it, with a dark rim underneath and a
    /// bright glint at the upper left.
    static func bead(in ctx: CGContext, street: CGImage, at c: CGPoint, radius r: Double, stretch: Double) {
        let body = CGRect(x: c.x - r, y: c.y - r * stretch, width: r * 2, height: r * 2 * stretch)
        ctx.saveGState()
        ctx.addEllipse(in: body)
        ctx.clip()
        // The view through it: a bead is a wide lens, so it holds the whole street, small and upside down.
        let view = CGFloat(r) * 3.4 / 1280
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: view, y: -view)
        ctx.translateBy(x: -640, y: -300)
        ctx.setAlpha(0.95)
        ctx.draw(street, in: BackdropPainter.frame)
        ctx.restoreGState()
        // Shading: the rim bends light away, so the top edge reads dark; the bottom edge gathers the street's light into a
        // bright crescent; and a sharp glint sits at the upper left.
        ctx.setLineCap(.round)
        ctx.setStrokeColor(BackdropPaint.color(0, 0.02, 0.06, 0.45))
        ctx.setLineWidth(CGFloat(max(0.7, r * 0.22)))
        ctx.addArc(center: c, radius: CGFloat(r * 0.86), startAngle: 0.35, endAngle: .pi - 0.35, clockwise: false)
        ctx.strokePath()
        ctx.setStrokeColor(BackdropPaint.color(1, 0.95, 0.88, 0.42))
        ctx.setLineWidth(CGFloat(max(0.6, r * 0.18)))
        ctx.addArc(center: CGPoint(x: c.x, y: c.y - r * (stretch - 1)), radius: CGFloat(r * 0.84), startAngle: .pi + 0.5, endAngle: 2 * .pi - 0.5, clockwise: false)
        ctx.strokePath()
        ctx.setFillColor(BackdropPaint.color(1, 1, 1, 0.9))
        let g = CGFloat(max(0.6, r * 0.17))
        ctx.fillEllipse(in: CGRect(x: c.x - r * 0.36 - g, y: c.y + r * stretch * 0.4 - g, width: g * 2, height: g * 2))
    }

    // MARK: Still pieces

    private static func shrunk(_ street: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: 128, height: 72, bitsPerComponent: 8, bytesPerRow: 0, space: BackdropCanvas.space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(street, in: CGRect(x: 0, y: 0, width: 128, height: 72))
        return ctx.makeImage()
    }

    /// The night street, painted sharp-ish (the beads show it sharper) and then blurred for the view past the glass.
    private static func makeStreet() -> CGImage? {
        guard let ctx = BackdropPainter.canvas(deep: false) else { return nil }
        BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: BackdropRGB(hex: 0x1C2640)), (at: 0.45, color: BackdropRGB(hex: 0x111C34)), (at: 1, color: BackdropRGB(hex: 0x0A1226))])
        var rng = SplitMix64(seed: 0xC17E)
        // Buildings' lit windows and signs.
        let signs: [BackdropRGB] = [BackdropRGB(hex: 0xFF4F8B), BackdropRGB(hex: 0x45D4FF), BackdropRGB(hex: 0xFFB347), BackdropRGB(hex: 0x9D7BFF)]
        for _ in 0..<9 {
            let w = CGFloat.random(in: 20...60, using: &rng), h = CGFloat.random(in: 50...160, using: &rng)
            let rect = CGRect(x: .random(in: 0..<1240, using: &rng), y: .random(in: 220...520, using: &rng), width: w, height: h)
            ctx.setFillColor(signs[Int.random(in: 0..<signs.count, using: &rng)].cg(0.75))
            ctx.fill(rect)
        }
        // Street lights and windows: discs of warm and coloured light, mostly low where the street is.
        let lights: [BackdropRGB] = [BackdropRGB(hex: 0xFFC46B), BackdropRGB(hex: 0xFF9A4D), BackdropRGB(hex: 0xFFE7B0), BackdropRGB(hex: 0xFF5A5F),
                                     BackdropRGB(hex: 0x5FB4FF), BackdropRGB(hex: 0x8E7BFF), BackdropRGB(hex: 0x4FE0C0)]
        ctx.setBlendMode(.plusLighter)
        for _ in 0..<70 {
            let tint = lights[Int.random(in: 0..<lights.count, using: &rng)]
            let radius = CGFloat.random(in: 10...34, using: &rng)
            let at = CGPoint(x: .random(in: 0..<1280, using: &rng), y: CGFloat.random(in: 0..<1, using: &rng).squareRoot() * 520 + 40)
            ctx.setFillColor(tint.cg(Double.random(in: 0.35...0.8, using: &rng)))
            ctx.fillEllipse(in: CGRect(x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2))
        }
        // Car lights along the bottom: a smear of red tail lights and white headlights.
        for _ in 0..<26 {
            let x = CGFloat.random(in: 0..<1280, using: &rng)
            let red = Bool.random(using: &rng)
            ctx.setFillColor((red ? BackdropRGB(hex: 0xFF3B30) : BackdropRGB(hex: 0xFFF2D8)).cg(0.7))
            ctx.fillEllipse(in: CGRect(x: x, y: CGFloat.random(in: 40...90, using: &rng), width: 14, height: 8))
        }
        ctx.setBlendMode(.normal)
        return ctx.makeImage()
    }

    /// The window: the street far out of focus, the fog on the glass, and the beads that sit still.
    private static func makeWindow(_ street: CGImage) -> CIImage? {
        let blurred = BackdropPainter.defocus(CIImage(cgImage: street), sigma: 14)
        // The out-of-focus lights read as discs with a soft rim: sharpen the blur's falloff a little by lifting contrast.
        let outside = blurred.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.12, kCIInputSaturationKey: 1.1])
        guard let glass = BackdropPainter.paint(deep: false, { ctx in
            if let fog = BackdropPaint.gradient([(at: 0, r: 0.62, g: 0.72, b: 0.86, a: 0.20), (at: 1, r: 0.62, g: 0.72, b: 0.86, a: 0.03)]) {
                ctx.drawLinearGradient(fog, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 720), options: [])
            }
            var rng = SplitMix64(seed: 0xD20B)
            let small = shrunk(street) ?? street
            for _ in 0..<220 {
                let at = CGPoint(x: .random(in: 0..<1280, using: &rng), y: .random(in: 0..<720, using: &rng))
                bead(in: ctx, street: small, at: at, radius: pow(Double.random(in: 0..<1, using: &rng), 2) * 5.5 + 1.5,
                     stretch: Double.random(in: 1.0...1.25, using: &rng))
            }
        }) else { return outside }
        let fogged = BackdropPainter.mottle(outside, amount: 0.06, scale: 1.4, channel: 1)
        return BackdropFinish.finish(BackdropFinish.vignette(glass.composited(over: fogged), strength: 0.2), grain: 0.9)
    }
}
