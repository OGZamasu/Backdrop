import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Where the soft lights float. Pure, so it can be tested.
enum LookDreamyPlan {
    struct Light: Equatable {
        var centre: CGPoint
        var radius: Double
        var alpha: Double
        /// Which colour of the palette.
        var tint: Int
    }

    static let count = 16

    /// The out-of-focus lights at a moment: each drifts slowly up and sways, wraps round from the top to the bottom and twinkles
    /// gently. Worked out from the time alone, so a long pause never makes them jump.
    static func lights(at time: Double, size: CGSize) -> [Light] {
        var rng = SplitMix64(seed: 0xD7EA)
        return (0..<count).map { _ in
            let x = Double.random(in: 0..<1, using: &rng), y0 = Double.random(in: 0..<1, using: &rng)
            let speed = Double.random(in: 0.010...0.028, using: &rng), sway = Double.random(in: 0.01...0.03, using: &rng)
            let phase = Double.random(in: 0..<(2 * .pi), using: &rng)
            let radius = Double.random(in: 18...62, using: &rng), alpha = Double.random(in: 0.18...0.42, using: &rng)
            let tint = Int.random(in: 0..<4, using: &rng)
            var y = (y0 + time * speed).truncatingRemainder(dividingBy: 1.2)
            if y < 0 { y += 1.2 }
            let margin = radius / size.height
            let along = -margin + y / 1.2 * (1 + 2 * margin)
            let twinkle = 0.75 + 0.25 * sin(time * 0.8 + phase)
            return Light(centre: CGPoint(x: (x + sway * sin(time * 0.3 + phase)) * size.width, y: along * size.height),
                         radius: radius, alpha: alpha * twinkle, tint: tint)
        }
    }
}

/// Soft and flattering: a glow that blooms out of the highlights, pastel colour with lifted lavender shadows and peachy lights,
/// the edges of the picture melting into softness, and out-of-focus lights drifting up behind you.
final class LookDreamyLens: Lens {
    let needs: LensNeeds = [.matte]

    /// Pastel: low contrast, shadows lifted to a soft lavender, lights warmed to peach, colour a touch quieter.
    private static let pastel = LookGrade { c in
        var x = LookTone.filmic(c, contrast: 0.92, black: 0.075, white: 0.985, pivot: 0.5)
        let l = LookTone.luma(x)
        x += SIMD3<Float>(0.02, -0.005, 0.04) * (1 - LookTone.smooth(0.1, 0.6, l))
        x += SIMD3<Float>(0.025, 0.008, -0.012) * LookTone.smooth(0.45, 1.0, l)
        return LookTone.saturate(x, 0.93)
    }

    /// Peach, lavender, mint and warm white.
    private static let tints: [LookColour] = [(1.0, 0.82, 0.70), (0.85, 0.78, 1.0), (0.78, 1.0, 0.90), (1.0, 0.96, 0.88)]

    /// A bokeh disc in each colour: flat in the middle with a slightly brighter rim, the way an out-of-focus light looks
    /// through a lens. Drawn once, the first time they are needed.
    private static let discs: [CGImage] = tints.compactMap { c in
        let side = 128
        let colour = { (a: CGFloat) in CGColor(colorSpace: LookKit.space, components: [CGFloat(c.r), CGFloat(c.g), CGFloat(c.b), a])! }
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: LookKit.space,
                                  bitmapInfo: Sprites.bitmapInfo),
              let shape = CGGradient(colorsSpace: LookKit.space, colors: [colour(0.62), colour(0.66), colour(0.76), colour(0.0)] as CFArray,
                                     locations: [0, 0.7, 0.86, 1]) else { return nil }
        let mid = CGPoint(x: side / 2, y: side / 2)
        ctx.drawRadialGradient(shape, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: CGFloat(side) / 2 - 1, options: [])
        return ctx.makeImage()
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let graded = Self.pastel.apply(input.composed)
        // A diffusion filter: highlights bloom outwards, and a little of a soft copy is laid over everything.
        let quarter = LookKit.size(of: rect, scaledBy: 0.25)
        let soft = LookKit.enlarge(LookKit.shrink(graded, rect: rect, by: 0.25).clampedToExtent().applyingGaussianBlur(sigma: 3).cropped(to: quarter), to: rect, from: quarter)
        let bloom = LookKit.glow(graded, rect: rect, threshold: 0.32, sigma: 10, tint: (1.0, 0.9, 0.86))
        var picture = LookKit.screen(LookKit.levels(bloom, gain: 0.7), over: LookKit.mixImages(graded, soft, 0.22))
        // The edges melt away into the soft copy.
        let centre = LookKit.ovalVignette(rect, reach: 0.4, edge: 0)
        picture = LookKit.blend(picture, over: LookKit.screen(LookKit.levels(bloom, gain: 0.7), over: soft), mask: centre)

        // Lights drift up behind you.
        let lights = LookDreamyPlan.lights(at: input.time, size: rect.size)
        let discs = Self.discs
        guard !discs.isEmpty, let layer = input.services.overlay({ ctx in
            for light in lights {
                let box = CGRect(x: rect.minX + light.centre.x - light.radius, y: rect.minY + light.centre.y - light.radius, width: light.radius * 2, height: light.radius * 2)
                ctx.setAlpha(CGFloat(light.alpha))
                ctx.draw(discs[light.tint % discs.count], in: box)
            }
            ctx.setAlpha(1)
        }) else { return picture.cropped(to: rect) }
        let behind = LookKit.screen(layer, over: picture)
        guard let matte = input.matte else { return LookKit.mixImages(picture, behind, 0.6).cropped(to: rect) }
        return LookKit.blend(picture, over: behind, mask: matte).cropped(to: rect)
    }
}
