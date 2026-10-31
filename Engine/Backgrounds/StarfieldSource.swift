import CoreGraphics
import CoreImage

/// Stars streaming out of the middle of the frame, as if the ship had gone to warp, past faint clouds of gas.
///
/// Every star's place is worked out from the clock alone, so there is nothing to carry from one frame to the next, a stall
/// cannot make them jump, and the same time always gives the same picture. The deep-space backdrop (nebula, far stars) is
/// painted once; each frame only draws the streaks: thin and faint at the tail, brighter at the head, and the nearest ones
/// with a small glow.
final class StarfieldSource: BackgroundSource {
    private struct Star {
        let x: Double          // where it sits across the view, -1...1 (before perspective)
        let y: Double
        let depth: Double      // 0...1, how far along its trip it is at time zero
        let speed: Double      // how fast it comes toward you, trips per second
        let tint: BackdropRGB
        let size: Double
    }

    private static let size = CGSize(width: 1280, height: 720)
    /// Star colours: blue-white, white, a pale gold, a pale violet, as real stars run.
    private static let tints: [BackdropRGB] = [
        BackdropRGB(1, 1, 1), BackdropRGB(0.78, 0.88, 1), BackdropRGB(0.62, 0.78, 1), BackdropRGB(1, 0.9, 0.74), BackdropRGB(0.88, 0.78, 1),
        BackdropRGB(0.7, 0.95, 1),
    ]
    private let stars: [Star]
    private var backdrop: CIImage?
    private var canvas: BackdropCanvas?
    private var head: CGImage?

    init(seed: UInt64 = 0x57A5) {
        var rng = SplitMix64(seed: seed)
        stars = (0..<320).map { _ in
            // Evenly spread over a disc: the square root keeps the middle from being crowded.
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let radius = Double.random(in: 0.05...1, using: &rng).squareRoot()
            return Star(x: cos(angle) * radius, y: sin(angle) * radius,
                        depth: .random(in: 0..<1, using: &rng),
                        speed: .random(in: 0.09...0.13, using: &rng),
                        tint: Self.tints[Int.random(in: 0..<Self.tints.count, using: &rng)],
                        size: .random(in: 0.8...1.7, using: &rng))
        }
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        if backdrop == nil { backdrop = BackdropBake.flatten(Self.makeBackdrop()) }
        if canvas == nil { canvas = BackdropCanvas(width: Int(Self.size.width), height: Int(Self.size.height)) }
        if head == nil { head = BackdropSprite.glow(BackdropRGB(0.85, 0.92, 1), side: 32, core: 0.9, hot: 0.8) }
        guard let backdrop, let canvas else { return nil }
        canvas.clear()
        draw(into: canvas.context, at: time)
        guard let streaks = canvas.image() else { return backdrop }
        return streaks.composited(over: backdrop)
    }

    // MARK: Drawing

    private func draw(into ctx: CGContext, at time: CFTimeInterval) {
        // The point everything flies out of wanders a little, as if the ship were slowly steering.
        let centre = CGPoint(x: Self.size.width * 0.5 + 70 * BackdropMotion.wave(time, rate: 0.09),
                             y: Self.size.height * 0.5 + 34 * BackdropMotion.wave(time, rate: 0.07, phase: 1))
        let reach: Double = 230            // how far from the centre a star is when it first appears
        let tail = 0.19                    // seconds of motion each streak shows
        ctx.setLineCap(.round)

        for star in stars {
            // Travelling from far (depth 1) to close (0), then starting over.
            let depth = max(0.02, BackdropMath.fract(star.depth - star.speed * time))
            let before = min(1, depth + star.speed * tail)
            let now = CGPoint(x: centre.x + star.x * reach / depth, y: centre.y + star.y * reach / depth)
            guard now.x > -40, now.x < Self.size.width + 40, now.y > -40, now.y < Self.size.height + 40 else { continue }
            let then = CGPoint(x: centre.x + star.x * reach / before, y: centre.y + star.y * reach / before)

            let closeness = 1 - depth
            let brightness = BackdropMath.smoothstep(0.02, 0.30, closeness) * (0.45 + 0.55 * closeness)
            let width = star.size * (0.5 + 1.7 * closeness * closeness)
            // Three pieces, thin and faint at the tail to full at the head, so each streak tapers.
            let t = star.tint
            for (from, to, alpha, w) in [(0.0, 0.45, 0.16, 0.45), (0.45, 0.8, 0.45, 0.75), (0.8, 1.0, 1.0, 1.0)] {
                let a = CGPoint(x: then.x + (now.x - then.x) * from, y: then.y + (now.y - then.y) * from)
                let b = CGPoint(x: then.x + (now.x - then.x) * to, y: then.y + (now.y - then.y) * to)
                ctx.setLineWidth(CGFloat(width * w))
                ctx.setStrokeColor(BackdropPaint.color(t.r, t.g, t.b, brightness * alpha))
                ctx.move(to: a)
                ctx.addLine(to: b)
                ctx.strokePath()
            }
            if closeness > 0.72, let head {
                let r = CGFloat(width * 3.2)
                ctx.setAlpha(CGFloat(brightness * 0.75))
                ctx.draw(head, in: CGRect(x: now.x - r, y: now.y - r, width: r * 2, height: r * 2))
                ctx.setAlpha(1)
            }
        }
    }

    /// Deep blue-black space with faint clouds of violet and teal gas, a dim glow where the stars come from, and a scatter
    /// of far stars, some with a small halo.
    private static func makeBackdrop() -> CIImage? {
        let frame = BackdropPainter.frame
        guard let base = BackdropPainter.paint(width: 640, height: 360, { ctx in
            if let g = BackdropPaint.gradient([(at: 0, r: 0.05, g: 0.045, b: 0.13), (at: 0.55, r: 0.018, g: 0.02, b: 0.07), (at: 1, r: 0.004, g: 0.005, b: 0.025)]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 360), startRadius: 0, endCenter: CGPoint(x: 640, y: 360), endRadius: 820, options: [.drawsAfterEndLocation])
            }
            BackdropPainter.glow(ctx, at: CGPoint(x: 640, y: 360), radius: 300, color: BackdropRGB(0.35, 0.45, 0.9), alpha: 0.10)
        }) else { return nil }
        // Gas: two broad fields of noise, each coloured only where it is strong and only faintly, so the clouds are thin
        // veils with shape rather than blotches. Two different sizes keep the noise from ever looking like a pattern.
        let violet = BackdropInk.colored(BackdropNoise.field(0, scale: 6.3, offset: CGPoint(x: 310, y: 120), extent: frame),
                                         BackdropInk.table([(at: 0, color: BackdropRGB(0, 0, 0), alpha: 0), (at: 0.45, color: BackdropRGB(0.22, 0.08, 0.32), alpha: 0),
                                                            (at: 0.78, color: BackdropRGB(0.34, 0.12, 0.46), alpha: 0.16), (at: 1, color: BackdropRGB(0.56, 0.3, 0.72), alpha: 0.28)]))
        let teal = BackdropInk.colored(BackdropNoise.field(1, scale: 4.1, offset: CGPoint(x: 40, y: 500), extent: frame),
                                       BackdropInk.table([(at: 0, color: BackdropRGB(0, 0, 0), alpha: 0), (at: 0.5, color: BackdropRGB(0.05, 0.2, 0.3), alpha: 0),
                                                          (at: 0.82, color: BackdropRGB(0.1, 0.34, 0.46), alpha: 0.12), (at: 1, color: BackdropRGB(0.3, 0.62, 0.74), alpha: 0.22)]))
        let clouds = BackdropPainter.defocus(teal.composited(over: violet), sigma: 10)
        var space = clouds.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: base]).cropped(to: frame)
        guard let stars = BackdropPainter.paint(deep: false, { ctx in
            var rng = SplitMix64(seed: 0xD1571)
            for i in 0..<230 {
                let at = CGPoint(x: .random(in: 0..<1280, using: &rng), y: .random(in: 0..<720, using: &rng))
                let r = CGFloat.random(in: 0.45...1.25, using: &rng)
                let t = tints[Int.random(in: 0..<tints.count, using: &rng)]
                let a = Double.random(in: 0.18...0.7, using: &rng)
                if i % 23 == 0 { BackdropPainter.glow(ctx, at: at, radius: 9, color: t, alpha: 0.35) }
                ctx.setFillColor(t.cg(a))
                ctx.fillEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2))
            }
        }) else { return space }
        space = stars.composited(over: space)
        return BackdropFinish.finish(space, grain: 0.5)
    }
}
