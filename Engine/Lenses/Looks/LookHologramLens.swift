import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// When the projection stutters. Pure, so it can be tested.
enum LookHologramPlan {
    /// A band of the projection that slips sideways for a moment.
    struct Slip: Equatable {
        var y: Double
        var height: Double
        var shift: Double
    }

    static let cycle = 3.2

    /// Most of the time nothing; now and then, for a fifth of a second, a band slips.
    static func slip(at time: Double, height: Double) -> Slip? {
        let index = Int((time / cycle).rounded(.down))
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(index)) &* 0xC2B2_AE3D_27D4_EB4F &+ 13)
        guard Double.random(in: 0..<1, using: &rng) < 0.6 else { return nil }
        let start = Double.random(in: 0...(cycle - 0.3), using: &rng)
        let local = time - Double(index) * cycle - start
        guard local >= 0, local < 0.2 else { return nil }
        return Slip(y: Double.random(in: 0.15...0.85, using: &rng) * height, height: Double.random(in: 14...60, using: &rng),
                    shift: Double.random(in: -1...1, using: &rng) * 18)
    }

    /// How bright the projection is: a faint shimmer, never a strobe.
    static func shimmer(at time: Double) -> Double { 0.94 + 0.04 * sin(time * 9.1) + 0.02 * sin(time * 23.7) }
}

/// You as a hologram: a glowing blue projection, a little see-through, with scan lines rolling up through you, a bright edge,
/// colour fringes and the odd stutter, standing in a dark room lit by the projector's beam.
final class LookHologramLens: Lens {
    let needs: LensNeeds = [.matte]

    /// The room with the lights off: most of its colour gone, dark and blue.
    private static let dark = LookGrade(size: 24) { c in LookTone.saturate(c, 0.3) * SIMD3<Float>(0.16, 0.2, 0.28) }

    /// The projection's light, from deep blue through cyan to white.
    private static let ramp: CIImage? = LookKit.ramp([
        (0.0, (0.0, 0.02, 0.08)), (0.35, (0.0, 0.25, 0.55)), (0.7, (0.25, 0.8, 1.0)), (1.0, (0.85, 1.0, 1.0)),
    ]).map { CIImage(cgImage: $0) }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect, t = input.time
        guard let ramp = Self.ramp else { return input.composed }
        let room = Self.dark.apply(input.scenery)

        // The projection: your brightness in blue light, lifted so a dark face still shows, the colours a pixel or two apart. A
        // projection is soft, so this is worked at half size.
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        let tone = LookKit.perceptual(LookKit.grey(LookKit.shrink(input.composed, rect: rect, by: 0.5))).applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.75])
        let light = LookKit.levels(LookKit.colourise(tone, with: ramp), gain: LookHologramPlan.shimmer(at: t))
        var projection = LookKit.enlarge(LookKit.fringe(light, rect: half, pixels: 1.5), to: rect, from: half)
        // Scan lines rolling slowly upwards, drawn crisp at full size.
        let lines = CIFilter.stripesGenerator()
        lines.center = CGPoint(x: CGFloat((t * 18).truncatingRemainder(dividingBy: 6)), y: 0)
        lines.color0 = CIColor(red: 0.55, green: 0.55, blue: 0.55)
        lines.color1 = CIColor(red: 1, green: 1, blue: 1)
        lines.width = 3
        lines.sharpness = 0.4
        if let scan = lines.outputImage?.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: rect) {
            projection = LookKit.multiply(scan, over: projection)
        }
        if let slip = LookHologramPlan.slip(at: t, height: rect.height) {
            let band = CGRect(x: rect.minX, y: rect.minY + slip.y, width: rect.width, height: slip.height)
            projection = projection.clampedToExtent().transformed(by: CGAffineTransform(translationX: CGFloat(slip.shift), y: 0)).cropped(to: band)
                .composited(over: projection)
        }

        // The projector's beam rises from below and lights the room faintly.
        let beam = CIFilter.radialGradient()
        beam.center = CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.15)
        beam.radius0 = 0
        beam.radius1 = Float(rect.height * 0.95)
        beam.color0 = CIColor(red: 0.05, green: 0.32, blue: 0.5)
        beam.color1 = CIColor(red: 0, green: 0, blue: 0)
        let litRoom = LookKit.screen((beam.outputImage ?? CIImage(color: .black)).cropped(to: rect), over: room)

        guard let matte = input.matte else { return LookKit.screen(projection, over: litRoom).cropped(to: rect) }
        // A bright edge round you, and the room faintly visible through you.
        let solid = LookKit.levels(LookKit.shrink(matte, rect: rect, by: 0.5), gain: 6, bias: -2.5)
        let edge = solid.clampedToExtent().applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: 1.5])
            .applyingGaussianBlur(sigma: 2).cropped(to: half)
        let rim = LookKit.tint(LookKit.enlarge(edge, to: rect, from: half), by: (0.35, 0.9, 1.0))
        let glow = LookKit.glow(LookKit.multiply(matte, over: projection), rect: rect, threshold: 0.35, sigma: 6, tint: (0.3, 0.75, 1.0))
        let ghost = LookKit.screen(LookKit.levels(projection, gain: 0.9), over: litRoom)
        let you = LookKit.blend(ghost, over: litRoom, mask: LookKit.levels(matte, gain: 0.92))
        return LookKit.screen(LookKit.screen(rim, over: LookKit.levels(glow, gain: 0.45)), over: you).cropped(to: rect)
    }
}
