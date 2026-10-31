import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// A watercolour painting: soft transparent washes that bleed at their edges, pigment pooling darker where a wash dried,
/// granulating in the paper's tooth, the white of the paper left for the lights, a faint pencil underdrawing, and the room
/// washed in more lightly than you, fading out before the edges of the sheet.
final class LookWatercolourLens: Lens {
    let needs: LensNeeds = [.matte]

    private static let paper: LookColour = (0.985, 0.975, 0.95)

    /// Paint is transparent and goes on in layers: the light is gathered into a few soft steps (one per wash), every colour is
    /// lighter than the photograph and a little more colourful, and the shadows lean cool.
    private static let wash = LookGrade { c in
        var hsv = LookTone.hsv(c)
        let steps: [Float] = [0.18, 0.42, 0.66, 0.86, 1.0]
        var v = steps[0]
        for i in 1..<steps.count { v += (steps[i] - steps[i - 1]) * LookTone.smooth(Float(i) / 5 - 0.06, Float(i) / 5 + 0.06, hsv.z) }
        hsv.z = v * 0.6 + hsv.z * 0.4
        let layered = LookTone.rgb(hsv: hsv)
        var x = SIMD3<Float>(repeating: 1) - (SIMD3<Float>(repeating: 1) - LookTone.saturate(layered, 1.25)) * 0.74
        let l = LookTone.luma(x)
        x += SIMD3<Float>(-0.01, 0.0, 0.025) * (1 - LookTone.smooth(0.2, 0.7, l))
        return x
    }

    /// The sheet: cold-pressed paper's tooth as a relief lit from the upper left, and slow wandering noise that pushes the washes
    /// about. Made once in the background and kept.
    private let tooth = LookBake(), bleed = LookBake()

    private static let slope = CIVector(values: [-2, -1, 0, -1, 0, 1, 0, 1, 2], count: 9)

    private func sheet(for rect: CGRect, context: CIContext) -> (tooth: CIImage, bleed: CIImage) {
        let key = "\(rect)"
        let paper = tooth.image(key, rect: rect, context: context) {
            let height = LookKit.noise(rect, frame: 15, size: 3.2).clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: rect)
            return LookKit.levels(height.applyingFilter("CIConvolution3X3", parameters: ["inputWeights": Self.slope, "inputBias": 0.5]), gain: 0.22, bias: 0.39)
                .cropped(to: rect)
        }
        let wander = bleed.image(key, rect: rect, context: context) {
            LookKit.levels(LookKit.noise(rect, frame: 29, size: 34).clampedToExtent().applyingGaussianBlur(sigma: 10).cropped(to: rect), gain: 3, bias: -1)
        }
        return (paper, wander)
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let paperSheet = sheet(for: rect, context: input.services.context)
        // Washes: the picture smoothed hard but keeping its big edges, at half size, then lightened like paint.
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        let small = LookKit.shrink(input.composed, rect: rect, by: 0.5)
        let smooth = small.applyingFilter("CIGuidedFilter", parameters: ["inputGuideImage": small, "inputRadius": 8.0, "inputEpsilon": 0.05]).cropped(to: half)
        var paint = Self.wash.apply(LookKit.enlarge(smooth, to: rect, from: half))
        // The room is washed in more lightly than you.
        if let matte = input.matte { paint = LookKit.blend(paint, over: LookKit.mixImages(paint, CIImage(color: LookKit.ciColour(Self.paper)).cropped(to: rect), 0.4), mask: matte) }
        // Wet edges wander.
        let bled = paint.clampedToExtent().applyingFilter("CIDisplacementDistortion", parameters: ["inputDisplacementImage": paperSheet.bleed, kCIInputScaleKey: 14.0])
            .cropped(to: rect)

        // Pigment pools where a wash dried: just inside the darker side of every edge.
        let tone = LookKit.perceptual(LookKit.grey(LookKit.shrink(bled, rect: rect, by: 0.5))).clampedToExtent()
        let near = tone.applyingGaussianBlur(sigma: 1.5), wide = tone.applyingGaussianBlur(sigma: 4)
        let pooled = LookKit.levels(near.applyingFilter("CISubtractBlendMode", parameters: [kCIInputBackgroundImageKey: wide]).cropped(to: half), gain: 5)
        let pools = LookKit.levels(LookKit.enlarge(pooled, to: rect, from: half), gain: -0.6, bias: 1)
        // Washes dry unevenly: the pigment is a little denser in some places than others.
        let blotches = LookKit.levels(paperSheet.bleed, gain: 0.16, bias: 0.86)
        // The faint pencil underneath: fine dark lines from a tighter look at the picture.
        let fineTone = LookKit.perceptual(LookKit.grey(LookKit.shrink(input.composed, rect: rect, by: 0.5))).clampedToExtent()
        let pencil = LookKit.levels(fineTone.applyingGaussianBlur(sigma: 0.8).applyingFilter("CISubtractBlendMode", parameters: [kCIInputBackgroundImageKey: fineTone.applyingGaussianBlur(sigma: 2)])
            .cropped(to: half), gain: 8, bias: -0.15)
        let underdrawing = LookKit.levels(LookKit.enlarge(pencil, to: rect, from: half), gain: -0.35, bias: 1)

        // Granulation: the paint settles into the paper's tooth, more where it is darker.
        let painted = LookKit.multiply(underdrawing, over: LookKit.multiply(pools, over: LookKit.multiply(blotches, over: bled)))
        let grained = paperSheet.tooth.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: painted])

        // The painting stops short of the edges of the sheet, raggedly.
        let page = paperSheet.tooth.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: CIImage(color: LookKit.ciColour(Self.paper)).cropped(to: rect)])
        let ragged = LookKit.multiply(LookKit.levels(paperSheet.bleed, gain: 0.6, bias: 0.7), over: LookKit.ovalVignette(rect, reach: 0.62, edge: 0))
        return LookKit.blend(grained, over: page, mask: LookKit.levels(ragged, gain: 2.6, bias: -0.3)).cropped(to: rect)
    }
}
