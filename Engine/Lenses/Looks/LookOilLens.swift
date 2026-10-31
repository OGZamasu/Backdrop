import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// An oil painting: the picture is simplified into soft patches of paint that keep their edges, broken into small dabs of
/// colour, laid on in short strokes that run in different directions in different parts of the canvas; the thick paint catches
/// the light from the upper left, and the whole thing has the warm glow of varnish over a faint canvas weave.
final class LookOilLens: Lens {
    let needs: LensNeeds = []

    /// The directions the bristle marks run in, one for each region of the canvas.
    private static let directions: [Double] = [0.55, 2.2, -0.35]

    /// The relief of the bristle marks and the weave, made once in the background and kept.
    private let canvas = LookBake()

    private static let slope = CIVector(values: [-2, -1, 0, -1, 0, 1, 0, 1, 2], count: 9)

    /// Light from the upper left, from the slope of a height map: ridges catch it on one side and are shaded on the other.
    /// A flat area comes out at 0.5, which is neutral to a soft-light blend.
    private static func lit(_ height: CIImage, strength: Double) -> CIImage {
        let relief = height.applyingFilter("CIConvolution3X3", parameters: ["inputWeights": slope, "inputBias": 0.5])
        return LookKit.levels(relief, gain: strength, bias: 0.5 - 0.5 * strength)
    }

    /// Warm varnish: a gentle curve, a little more colour, golden lights and umber shadows.
    private static let varnish = LookGrade { c in
        var x = LookTone.filmic(c, contrast: 1.12, black: 0.03, white: 0.97)
        let l = LookTone.luma(x)
        x += SIMD3<Float>(0.025, 0.01, -0.03) * LookTone.smooth(0.4, 0.95, l)
        x += SIMD3<Float>(0.02, 0.0, -0.02) * (1 - LookTone.smooth(0.0, 0.35, l))
        return LookTone.saturate(x, 1.18)
    }

    private static func canvas(for rect: CGRect) -> CIImage {
        // Regions: big soft blobs of noise, cut at two levels, so each part of the canvas belongs to one of three directions.
        let blobs = LookKit.noise(rect, frame: 12, size: 70).clampedToExtent().applyingGaussianBlur(sigma: 30).cropped(to: rect)
        let spread = LookKit.levels(blobs, gain: 5, bias: -2.0)
        let first = LookKit.levels(spread, gain: 3, bias: -0.6)
        let second = LookKit.levels(spread, gain: 3, bias: -1.6)
        // Bristle marks in each direction, chosen by the same regions, as a height map lit from the upper left.
        let marks = directions.enumerated().map { i, angle in
            LookKit.levels(LookKit.noise(rect, frame: 5 + i * 7, size: 2.0).clampedToExtent()
                .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 6.0, kCIInputAngleKey: angle]).cropped(to: rect), gain: 1.8, bias: -0.4)
        }
        let bristles = LookKit.blend(marks[2], over: LookKit.blend(marks[1], over: marks[0], mask: first), mask: second)
        // Canvas weave: two sets of fine threads crossing, very faint under the paint.
        let threads = CIFilter.stripesGenerator()
        threads.center = .zero
        threads.color0 = CIColor(red: 0.42, green: 0.42, blue: 0.42)
        threads.color1 = CIColor(red: 0.58, green: 0.58, blue: 0.58)
        threads.width = 2.4
        threads.sharpness = 0.3
        let warp = (threads.outputImage ?? CIImage(color: .gray)).cropped(to: rect)
        let weave = LookKit.multiply(warp.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: rect), over: warp)
        return lit(bristles, strength: 0.22)
            .applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: LookKit.levels(weave, gain: 0.5, bias: 0.3)]).cropped(to: rect)
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let texture = canvas.image("\(rect)", rect: rect, context: input.services.context) { Self.canvas(for: rect) }
        // Paint is worked at half size: the patches are big anyway, and every filter here costs by the pixel. Smoothing that
        // keeps edges, then opening and closing the shapes, rounds every patch off the way a loaded brush does.
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        let small = LookKit.shrink(input.composed, rect: rect, by: 0.5)
        let patches = small.applyingFilter("CIGuidedFilter", parameters: ["inputGuideImage": small, "inputRadius": 4.0, "inputEpsilon": 0.01])
            .clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 1.5]).applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1.5])
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1.5]).applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 1.5])
            .cropped(to: half)
        let paint = Self.varnish.apply(LookKit.enlarge(patches, to: rect, from: half))
        // Broken colour: part of every patch is laid on in small flat dabs.
        let dabs = paint.clampedToExtent().applyingFilter("CICrystallize", parameters: [kCIInputRadiusKey: 6.0, kCIInputCenterKey: CIVector(x: 0, y: 0)]).cropped(to: rect)
        let painted = LookKit.mixImages(paint, dabs, 0.35).cropped(to: rect)
        // Where one patch of paint meets another it stands proud and catches the light, and the bristle marks do too.
        let ridges = Self.lit(LookKit.perceptual(LookKit.grey(painted)).clampedToExtent().applyingGaussianBlur(sigma: 0.8).cropped(to: rect), strength: 1.4)
        let lit = ridges.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: painted])
        return texture.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: lit]).cropped(to: rect)
    }
}
