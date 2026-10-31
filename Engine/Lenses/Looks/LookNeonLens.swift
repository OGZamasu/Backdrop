import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// What colour the neon tubes are and how bright. Pure, so it can be tested without drawing anything.
enum LookNeonPlan {
    /// Where the tubes are on the colour wheel, 0..<1. A full turn takes about 25 seconds.
    static func hue(at time: Double) -> Double {
        let turn = time / 25
        return turn - turn.rounded(.down)
    }

    /// How bright the tubes are, 0.3...1. Steady, apart from a short stutter every so often, like a sign that needs a new tube.
    static func brightness(at time: Double) -> Double {
        let window = 7.0
        let index = Int((time / window).rounded(.down))
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9 &+ 99)
        guard Double.random(in: 0..<1, using: &rng) < 0.75 else { return 1 }
        let start = Double.random(in: 0...(window - 1), using: &rng)
        let local = time - Double(index) * window - start
        guard local >= 0, local < 0.7 else { return 1 }
        let step = Int(local * 14)
        guard step % 2 == 0 else { return 1 }
        var dip = SplitMix64(seed: UInt64(bitPattern: Int64(index &* 31 &+ step)))
        return 0.3 + 0.25 * Double.random(in: 0..<1, using: &dip)
    }
}

/// The room goes dark and you are drawn round with a glowing neon tube, which slowly changes colour: a white-hot core in a
/// coloured glass sheath, a bloom round it, its light thrown on the wall behind you and catching the edge of you.
final class LookNeonLens: Lens {
    let needs: LensNeeds = [.matte]

    /// The room at night: under a third of its brightness, most of its colour gone, a cool cast.
    private static let night = LookGrade(size: 24) { c in
        let dim = LookTone.saturate(c, 0.45) * 0.3
        return dim * SIMD3<Float>(0.92, 0.96, 1.08)
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        guard let matte = input.matte else { return input.composed.gain(0.55) }
        let hue = LookNeonPlan.hue(at: input.time)
        let level = LookNeonPlan.brightness(at: input.time)
        let tube = Palette.rgb(hue: hue, saturation: 0.92)
        let halo = Palette.rgb(hue: hue + 0.06, saturation: 0.95)
        let hot = LookKit.mix(tube, (1, 1, 1), 0.7)

        // The room goes dark, so the tube is the light. You stay as you are, a shade dimmer.
        let room = Self.night.apply(input.scenery)
        let body = LookKit.blend(LookKit.levels(input.composed, gain: 0.88), over: room, mask: matte).cropped(to: rect)

        // The outline is found at half size, which is plenty for a glow and a quarter of the work.
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        let solid = LookKit.levels(LookKit.shrink(matte, rect: rect, by: 0.5).clampedToExtent().applyingGaussianBlur(sigma: 1.3).cropped(to: half),
                                   gain: 8, bias: -3.5)
        let edge = solid.clampedToExtent()
        let wide = edge.applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: 2.6]).applyingGaussianBlur(sigma: 0.8).cropped(to: half)
        let thin = edge.applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: 1.0]).cropped(to: half)
        let near = wide.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: half)
        let quarter = LookKit.size(of: rect, scaledBy: 0.25), eighth = LookKit.size(of: rect, scaledBy: 0.125)
        let far = LookKit.enlarge(LookKit.shrink(wide, rect: half, by: 0.5).clampedToExtent().applyingGaussianBlur(sigma: 11).cropped(to: quarter),
                                  to: half, from: quarter)
        let spill = LookKit.enlarge(LookKit.shrink(wide, rect: half, by: 0.25).clampedToExtent().applyingGaussianBlur(sigma: 9).cropped(to: eighth),
                                    to: half, from: eighth)

        // The wide glows light the wall; inside the outline they would wash out your colours, so there they are held back to a
        // thin coloured rim, as a real tube lights the edge of whoever stands in front of it.
        let shield = LookKit.levels(solid.clampedToExtent().applyingGaussianBlur(sigma: 3).cropped(to: half).applyingFilter("CIColorInvert"), gain: 0.88, bias: 0.12)
        let rim = LookKit.multiply(LookKit.levels(near, gain: 0.5), over: solid)
        let outside = LookKit.screen(LookKit.tint(spill, by: scaled(tube, 3.2 * level)),
                                     over: LookKit.screen(LookKit.tint(far, by: scaled(halo, 2.0 * level)), over: LookKit.tint(near, by: scaled(tube, 2.4 * level))))
        let lights = LookKit.screen(LookKit.multiply(outside, over: shield),
                                    over: LookKit.screen(LookKit.tint(rim, by: scaled(tube, level)),
                                                         over: LookKit.screen(LookKit.tint(wide, by: scaled(tube, 1.1 * level)),
                                                                              over: LookKit.tint(thin, by: scaled(hot, 1.2 * level)))))
        let glow = LookKit.enlarge(lights, to: rect, from: half)
        return LookKit.screen(glow, over: body).cropped(to: rect)
    }

    private func scaled(_ c: LookColour, _ k: Double) -> LookColour { (c.r * k, c.g * k, c.b * k) }
}
