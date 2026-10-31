import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// The flicker, weave and light leaks of a home movie. Pure, so it can be tested.
enum LookSuperEightPlan {
    /// Home movies ran at 18 pictures a second; the grain, weave and flicker change that often.
    static let rate = 18.0

    static func frame(at time: Double) -> Int { Int((time * rate).rounded(.down)) }

    private static func generator(_ frame: Int, salt: UInt64) -> SplitMix64 {
        SplitMix64(seed: UInt64(bitPattern: Int64(frame)) &* 0xD6E8_FEB8_6659_FD93 &+ salt)
    }

    /// How far the frame sits off true in the gate, in pixels: a small weave, mostly up and down.
    static func weave(frame: Int) -> (dx: Double, dy: Double) {
        var rng = generator(frame, salt: 5)
        return (Double.random(in: -1.0...1.0, using: &rng), Double.random(in: -2.2...2.2, using: &rng))
    }

    /// The projector lamp's flicker, a few per cent.
    static func exposure(frame: Int) -> Double {
        var rng = generator(frame, salt: 9)
        return 0.95 + 0.07 * Double.random(in: 0..<1, using: &rng)
    }

    /// A glow of light leaking in at one edge of the film: where (0...1 round the frame, from the left edge up) and how strong.
    struct Leak: Equatable {
        var place: Double
        var strength: Double
        /// 0 a warm orange, 1 a deep red.
        var redness: Double
    }

    static let leakCycle = 7.0

    /// Every so often a leak swells and fades over a couple of seconds. Nil in between.
    static func leak(at time: Double) -> Leak? {
        let index = Int((time / leakCycle).rounded(.down))
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9 &+ 61)
        guard Double.random(in: 0..<1, using: &rng) < 0.65 else { return nil }
        let start = Double.random(in: 0...3.5, using: &rng)
        let length = Double.random(in: 2.0...3.2, using: &rng)
        let place = Double.random(in: 0..<1, using: &rng), redness = Double.random(in: 0...1, using: &rng)
        let progress = (time - Double(index) * leakCycle - start) / length
        guard progress >= 0, progress < 1 else { return nil }
        let swell = sin(.pi * progress)
        return Leak(place: place, strength: swell * swell, redness: redness)
    }
}

/// A home movie on Super 8: soft, warm, saturated colour with faded blacks, chunky grain, a red glow round the lights, the
/// picture weaving in a round-cornered gate, flicker, specks of dust and now and then a leak of orange light.
final class LookSuperEightLens: Lens {
    let needs: LensNeeds = []

    /// Warm reversal film from a summer holiday: faded blacks, rich reds and yellows, a little green-blue in the shadows.
    private static let stock = LookGrade { c in
        var x = LookTone.filmic(c, contrast: 1.32, black: 0.055, white: 0.955, pivot: 0.45)
        x *= SIMD3<Float>(1.05, 1.0, 0.86)
        let l = LookTone.luma(x)
        x += SIMD3<Float>(-0.015, 0.01, 0.03) * (1 - LookTone.smooth(0.05, 0.4, l))
        return LookTone.saturate(x, 1.22)
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let frame = LookSuperEightPlan.frame(at: input.time)
        let shake = LookSuperEightPlan.weave(frame: frame)

        // Small film holds little detail: worked at half size, softly, and weaving in the gate.
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        let moved = input.composed.clampedToExtent().transformed(by: CGAffineTransform(translationX: CGFloat(shake.dx), y: CGFloat(shake.dy)))
        let small = LookKit.shrink(moved, rect: rect, by: 0.5).clampedToExtent().applyingGaussianBlur(sigma: 0.7).cropped(to: half)
        let graded = LookKit.levels(Self.stock.apply(small), gain: LookSuperEightPlan.exposure(frame: frame))
        // Red glow round the lights, where light scatters back through the film.
        let halo = LookKit.glow(graded, rect: half, threshold: 0.5, sigma: 5, tint: (1.0, 0.42, 0.18), scale: 0.5)
        var picture = LookKit.screen(LookKit.levels(halo, gain: 0.55), over: graded)
        picture = LookKit.filmGrain(picture, frame: frame, rect: half, amount: 0.36, size: 1.25, chroma: 0.5)

        // A leak of light at one edge.
        if let leak = LookSuperEightPlan.leak(at: input.time) {
            let around = leak.place * 2 * (half.width + half.height)
            let spot: CGPoint
            if around < half.height { spot = CGPoint(x: 0, y: around) }
            else if around < half.height + half.width { spot = CGPoint(x: around - half.height, y: half.height) }
            else if around < 2 * half.height + half.width { spot = CGPoint(x: half.width, y: half.height - (around - half.height - half.width)) }
            else { spot = CGPoint(x: half.width - (around - 2 * half.height - half.width), y: 0) }
            let glow = CIFilter.radialGradient()
            glow.center = spot
            glow.radius0 = 0
            glow.radius1 = Float(half.height * 0.9)
            let warm = LookKit.mix((1.0, 0.55, 0.16), (0.95, 0.16, 0.08), leak.redness)
            glow.color0 = CIColor(red: CGFloat(warm.r * leak.strength * 0.8), green: CGFloat(warm.g * leak.strength * 0.8), blue: CGFloat(warm.b * leak.strength * 0.8))
            glow.color1 = CIColor(red: 0, green: 0, blue: 0)
            if let light = glow.outputImage?.cropped(to: half) { picture = LookKit.screen(light, over: picture) }
        }

        // The gate: round corners, a soft edge and the light falling off towards it.
        let gate = CIFilter.roundedRectangleGenerator()
        gate.extent = half.insetBy(dx: half.width * 0.035, dy: half.height * 0.05)
        gate.radius = Float(half.height * 0.09)
        gate.color = CIColor(red: 1, green: 1, blue: 1)
        let mask = (gate.outputImage ?? CIImage(color: .white)).composited(over: CIImage(color: .black)).applyingGaussianBlur(sigma: 3).cropped(to: half)
        let vignette = LookKit.ovalVignette(half, reach: 0.3, edge: LookKit.lin(0.5))
        let gated = LookKit.multiply(LookKit.multiply(mask, over: vignette), over: picture)
        let full = LookKit.enlarge(gated, to: rect, from: half)

        guard let dust = input.services.overlay({ ctx in Self.drawDust(ctx, frame: frame, rect: rect) }) else { return full }
        return dust.composited(over: full).cropped(to: rect)
    }

    /// A few specks of dust and lint, different on every frame.
    private static func drawDust(_ ctx: CGContext, frame: Int, rect: CGRect) {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(frame)) &* 0xA24B_AED4_963E_E407 &+ 3)
        let dark = CGColor(red: 0.06, green: 0.04, blue: 0.03, alpha: 0.7)
        let light = CGColor(red: 1, green: 0.95, blue: 0.85, alpha: 0.45)
        for _ in 0..<Int.random(in: 1...5, using: &rng) {
            let p = CGPoint(x: Double.random(in: 0.06...0.94, using: &rng) * rect.width, y: Double.random(in: 0.08...0.92, using: &rng) * rect.height)
            let r = Double.random(in: 1.2...3.4, using: &rng)
            ctx.setFillColor(Double.random(in: 0..<1, using: &rng) < 0.7 ? dark : light)
            ctx.fillEllipse(in: CGRect(x: rect.minX + p.x - r, y: rect.minY + p.y - r * 0.8, width: r * 2, height: r * 1.6))
        }
        if Double.random(in: 0..<1, using: &rng) < 0.12 {
            let start = CGPoint(x: rect.minX + Double.random(in: 0.1...0.9, using: &rng) * rect.width, y: rect.minY + Double.random(in: 0.1...0.9, using: &rng) * rect.height)
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), length = Double.random(in: 25...60, using: &rng)
            ctx.setStrokeColor(dark)
            ctx.setLineWidth(1.4)
            ctx.move(to: start)
            ctx.addQuadCurve(to: CGPoint(x: start.x + cos(a) * length, y: start.y + sin(a) * length),
                             control: CGPoint(x: start.x + cos(a + 0.6) * length * 0.6, y: start.y + sin(a + 0.6) * length * 0.6))
            ctx.strokePath()
        }
    }
}
