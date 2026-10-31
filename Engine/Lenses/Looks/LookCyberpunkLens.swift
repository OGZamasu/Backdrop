import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Teal shadows and hot pink highlights, glowing lights with long horizontal streaks, and neon spilling in from the edges.
final class LookCyberpunkLens: Lens {
    let needs: LensNeeds = []

    private static let cubeSize = 32

    /// The colour grade as a lookup table (made once): every colour the camera can see, and what it becomes.
    private static let gradeTable: Data = {
        let n = cubeSize
        var table = [Float](repeating: 1, count: n * n * n * 4)
        var i = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let out = grade(SIMD3<Float>(Float(r), Float(g), Float(b)) / Float(n - 1))
                    table[i] = out.x; table[i + 1] = out.y; table[i + 2] = out.z
                    i += 4
                }
            }
        }
        return table.withUnsafeBufferPointer { Data(buffer: $0) }
    }()

    /// One colour in, one colour out, all on the eye's own scale. A film curve with a lifted toe (so a dark face keeps its detail),
    /// teal pushed into the shadows and magenta into the lights by shifting the colour rather than scaling it, which keeps every
    /// tone's brightness, and everything a little more colourful.
    static func grade(_ c: SIMD3<Float>) -> SIMD3<Float> {
        var x = LookTone.filmic(c, contrast: 1.3, black: 0.035, white: 0.985)
        let l = LookTone.luma(x)
        let shadow = 1 - LookTone.smooth(0.05, 0.6, l), light = LookTone.smooth(0.35, 0.95, l)
        x += SIMD3<Float>(-0.1, 0.045, 0.11) * shadow
        // Skin takes less of the magenta, so faces stay human under the neon.
        x += SIMD3<Float>(0.11, -0.08, 0.075) * light * (1 - 0.55 * LookTone.skinness(c))
        x = LookTone.saturate(x, 1.3)
        return simd_clamp(x, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
    }

    /// How far across the picture the soft diagonal flare is, 0...1, or nil while it rests. One sweep every ten seconds.
    static func flare(at time: Double) -> Double? {
        let phase = (time / 10).truncatingRemainder(dividingBy: 1)
        return phase < 0.28 ? phase / 0.28 : nil
    }

    /// A soft slanted stripe of light, brightest along its middle line.
    private static func lightBand(centre: CGPoint, halfWidth: CGFloat, rect: CGRect) -> CIImage? {
        let direction = CGPoint(x: cos(0.38), y: sin(0.38))
        let rise = CIFilter.linearGradient()
        rise.point0 = CGPoint(x: centre.x - direction.x * halfWidth, y: centre.y - direction.y * halfWidth)
        rise.point1 = centre
        rise.color0 = CIColor(red: 0, green: 0, blue: 0)
        rise.color1 = CIColor(red: 1, green: 1, blue: 1)
        let fall = CIFilter.linearGradient()
        fall.point0 = centre
        fall.point1 = CGPoint(x: centre.x + direction.x * halfWidth, y: centre.y + direction.y * halfWidth)
        fall.color0 = CIColor(red: 1, green: 1, blue: 1)
        fall.color1 = CIColor(red: 0, green: 0, blue: 0)
        guard let up = rise.outputImage, let down = fall.outputImage else { return nil }
        return LookKit.multiply(up.cropped(to: rect), over: down.cropped(to: rect))
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let t = input.time

        let graded = input.composed.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": Self.cubeSize, "inputCubeData": Self.gradeTable, "inputColorSpace": LookKit.space,
        ])

        // Lights: the brightest parts, worked out small.
        let small = LookKit.size(of: rect, scaledBy: 0.25)
        let lights = LookKit.levels(LookKit.shrink(graded, rect: rect, by: 0.25), gain: 3.4, bias: -2.55)
        let bloom = LookKit.enlarge(lights.clampedToExtent().applyingGaussianBlur(sigma: 5).cropped(to: small), to: rect, from: small)
        // Each small light is stretched sideways into a long blue-white streak, as an anamorphic lens does. Only small ones: a
        // streak from a whole bright wall would cut the picture in half, so what is left after "opening" the lights (the big
        // areas) is taken away.
        let big = lights.clampedToExtent().applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 4.0])
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 4.0]).cropped(to: small)
        let spots = lights.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: big])
        let streak = LookKit.enlarge(spots.clampedToExtent().applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 60.0, kCIInputAngleKey: 0.0])
            .applyingGaussianBlur(sigma: 1.2).cropped(to: small), to: rect, from: small)

        var picture = LookKit.screen(LookKit.tint(bloom, by: (0.95, 0.75, 1.0)), over: graded)
        picture = LookKit.screen(LookKit.tint(streak, by: (0.45, 0.9, 1.0)), over: picture)

        // Coloured light from either side, swaying slowly.
        let sway = CGFloat(sin(t * 0.45) * 90)
        let left = CIFilter.radialGradient()
        left.center = CGPoint(x: 0, y: rect.midY + sway)
        left.radius0 = 0
        left.radius1 = Float(rect.width * 0.55)
        left.color0 = CIColor(red: 0.0, green: 0.62, blue: 0.75)
        left.color1 = CIColor(red: 0, green: 0, blue: 0)
        let right = CIFilter.radialGradient()
        right.center = CGPoint(x: rect.maxX, y: rect.midY - sway)
        right.radius0 = 0
        right.radius1 = Float(rect.width * 0.55)
        right.color0 = CIColor(red: 0.85, green: 0.12, blue: 0.55)
        right.color1 = CIColor(red: 0, green: 0, blue: 0)
        if let leftLight = left.outputImage?.cropped(to: rect), let rightLight = right.outputImage?.cropped(to: rect) {
            picture = LookKit.screen(LookKit.levels(leftLight, gain: 0.28), over: picture)
            picture = LookKit.screen(LookKit.levels(rightLight, gain: 0.28), over: picture)
        }

        // Now and then a soft band of light slides across.
        if let sweep = Self.flare(at: t), let band = Self.lightBand(centre: CGPoint(x: -rect.width * 0.2 + rect.width * 1.4 * sweep, y: rect.midY),
                                                                   halfWidth: 170, rect: rect) {
            picture = LookKit.screen(LookKit.tint(band, by: (0.24, 0.62, 0.8)), over: picture)
        }

        let dark = LookKit.multiply(LookKit.vignette(rect, inner: 0.4, outer: 1.05, edge: LookKit.lin(0.5)), over: picture)
        return dark.cropped(to: rect)
    }
}
