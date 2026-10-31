import CoreImage
import CoreImage.CIFilterBuiltins

/// A pencil drawing on cream paper: graphite outlines and loose shading strokes, redrawn a few times a second so the
/// drawing shimmers like hand-drawn animation while the paper stays still.
final class LookPencilLens: Lens {
    let needs: LensNeeds = []

    private static let graphite: LookColour = (0.10, 0.11, 0.15)
    private static let paper: LookColour = (0.97, 0.95, 0.90)

    /// How many times a second the drawing is redrawn.
    static let redraws = 8.0

    /// Two sheets of slanting pencil strokes, one steeper than the other, made once in the background and kept.
    private let looseSheet = LookBake(), tightSheet = LookBake()

    private func strokeSheets(for rect: CGRect, context: CIContext) -> (loose: CIImage, tight: CIImage) {
        // Noise smeared along a line is a mass of random strokes; stretching the contrast leaves them as crisp streaks.
        func sheet(seed: Int, angle: Double, length: Double) -> CIImage {
            let smeared = LookKit.noise(rect, frame: seed, size: 1.1)
                .clampedToExtent().applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: length, kCIInputAngleKey: angle]).cropped(to: rect)
            return LookKit.levels(smeared, gain: 9, bias: -3.9)
        }
        let key = "\(rect)"
        return (looseSheet.image(key, rect: rect, context: context) { sheet(seed: 21, angle: 0.8, length: 15) },
                tightSheet.image(key, rect: rect, context: context) { sheet(seed: 33, angle: -0.6, length: 11) })
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let drawing = Int((input.time * Self.redraws).rounded(.down))

        // Pencil on paper is done in how things look, not in light, so everything here is on the eye's own scale.
        // A touch of blur first, or the camera's noise would be drawn in as scribble.
        var tone = LookKit.perceptual(LookKit.grey(input.composed.clampedToExtent().applyingGaussianBlur(sigma: 1.1).cropped(to: rect)))
        // An artist draws the sitter fully and sketches the room in lightly behind, so a dark backdrop does not become a wall of
        // hatching that swamps you.
        if let matte = input.matte {
            tone = LookKit.blend(tone, over: LookKit.levels(tone, gain: 0.5, bias: 0.5), mask: matte).cropped(to: rect)
        }

        // The classic trick: divide the picture by a blurred copy of itself. Flat areas come out white; wherever the brightness
        // changes quickly, a dark line is left. A wider blur draws bolder lines.
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        let blurred = LookKit.shrink(tone, rect: rect, by: 0.5).applyingFilter("CIColorInvert")
            .clampedToExtent().applyingGaussianBlur(sigma: 4.5).cropped(to: half)
        let lines = LookKit.enlarge(blurred, to: rect, from: half)
            .applyingFilter("CIColorDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: tone])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 2.4])

        // Shadows are shaded in with strokes: the darker the picture, the more of the strokes show. Deep shadow gets a second set
        // crossing the first. Each redraw uses the sheets the other way up, so the shading shimmers too.
        let sheets = strokeSheets(for: rect, context: input.services.context)
        let flip = drawing % 2 == 0 ? CGAffineTransform.identity
            : CGAffineTransform(translationX: -rect.midX, y: -rect.midY).concatenating(CGAffineTransform(rotationAngle: .pi)).concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
        let dark = tone.applyingFilter("CIColorInvert")
        let light = LookKit.multiply(LookKit.levels(dark, gain: 1.3, bias: -0.45), over: sheets.loose.transformed(by: flip).cropped(to: rect))
        let deep = LookKit.multiply(LookKit.levels(dark, gain: 1.8, bias: -1.0), over: sheets.tight.transformed(by: flip).cropped(to: rect))
        let shading = LookKit.screen(deep, over: light).applyingFilter("CIColorInvert")
        let smudge = LookKit.levels(tone, gain: 0.2, bias: 0.8)
        let drawn = LookKit.multiply(lines, over: LookKit.multiply(LookKit.levels(shading, gain: 0.42, bias: 0.58), over: smudge))

        // The hand never draws a line in quite the same place twice.
        let wobble = LookKit.noise(rect, frame: drawing, size: 26, spread: 0.9)
        let shaky = drawn.clampedToExtent()
            .applyingFilter("CIDisplacementDistortion", parameters: ["inputDisplacementImage": wobble, kCIInputScaleKey: 7.0])
            .cropped(to: rect)

        // Dark lines in graphite, white as paper.
        let ink = LookKit.linear(LookKit.levels(shaky, gain: 1.1, bias: -0.08))
            .applyingFilter("CIFalseColor", parameters: ["inputColor0": LookKit.ciColour(Self.graphite), "inputColor1": LookKit.ciColour(Self.paper)])

        // The drawing stops short of the edges of the page, raggedly, as a sketch does.
        let page = CIImage(color: LookKit.ciColour(Self.paper)).cropped(to: rect)
        let ragged = LookKit.multiply(LookKit.noise(rect, frame: 23, size: 26, mean: 1, spread: 0.7), over: LookKit.ovalVignette(rect, reach: 0.6, edge: 0))
        let sketch = LookKit.blend(ink, over: page, mask: LookKit.levels(ragged, gain: 2.4, bias: -0.25))

        // The paper has a fibre and a tooth, and stays where it is.
        let fibre = LookKit.noise(rect, frame: 3, size: 1.2, mean: 0.93, spread: 0.12)
        let cloud = LookKit.noise(rect, frame: 11, size: 30, mean: 0.95, spread: 0.1)
        return LookKit.multiply(fibre, over: LookKit.multiply(cloud, over: sketch)).cropped(to: rect)
    }
}
