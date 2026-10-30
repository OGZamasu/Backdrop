import CoreImage
import CoreImage.CIFilterBuiltins

/// Looks, with no motion of their own: a Core Image filter or two over the finished picture.

/// Ink outlines and flat colour, like a comic panel.
final class ComicLens: Lens {
    let needs: LensNeeds = []

    func render(_ input: LensInput) -> CIImage {
        // Flat, bold colour, with ink lines laid over it. Core Image's own comic filter washes flat colour out to
        // white and only looks right on busy photographic texture, so this builds the look from parts.
        let colour = input.composed
            .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 7.0])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3, kCIInputContrastKey: 1.05])
        let ink = input.composed.applyingFilter("CILineOverlay", parameters: [
            "inputNRNoiseLevel": 0.05, "inputNRSharpness": 0.6, "inputEdgeIntensity": 1.6, "inputThreshold": 0.1, "inputContrast": 40,
        ])
        return ink.composited(over: colour).cropped(to: input.rect)
    }
}

/// Chunky pixels and a handful of colours: an 8-bit console.
final class PixelArtLens: Lens {
    let needs: LensNeeds = []
    private let block: Double

    init(block: Double = 14) { self.block = block }

    func render(_ input: LensInput) -> CIImage {
        input.composed
            .clampedToExtent()
            .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: block, kCIInputCenterKey: CIVector(x: 0, y: 0)])
            .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 6.0])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3])
            .cropped(to: input.rect)
    }
}

/// The left half of the picture and its reflection, so you have a twin.
final class MirrorLens: Lens {
    let needs: LensNeeds = []

    func render(_ input: LensInput) -> CIImage {
        let w = input.rect.width
        let left = input.composed.cropped(to: CGRect(x: input.rect.minX, y: input.rect.minY, width: w / 2, height: input.rect.height))
        let reflected = left.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: input.rect.minX + w, ty: 0))
        return left.composited(over: reflected).cropped(to: input.rect)
    }
}

/// The picture folded into turning petals.
final class KaleidoscopeLens: Lens {
    let needs: LensNeeds = []

    func render(_ input: LensInput) -> CIImage {
        let centre = CIVector(x: input.rect.midX, y: input.rect.midY)
        // The pattern is built from what lies along a few rays out of the centre, so enlarge the picture to put
        // the person, not the empty room, on those rays.
        let enlarged = CGAffineTransform(translationX: -input.rect.midX, y: -input.rect.midY)
            .concatenating(CGAffineTransform(scaleX: 2.1, y: 2.1))
            .concatenating(CGAffineTransform(translationX: input.rect.midX, y: input.rect.midY - 40))
        return input.composed
            .clampedToExtent()
            .transformed(by: enlarged)
            .applyingFilter("CIKaleidoscope", parameters: [
                "inputCount": 7, kCIInputCenterKey: centre, kCIInputAngleKey: input.time * 0.25,
            ])
            .cropped(to: input.rect)
    }
}
