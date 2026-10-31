import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// A colour newspaper print: the picture is rebuilt from four screens of cyan, magenta, yellow and black dots in real process
/// inks on cream paper, a touch out of register, with the ink spreading softly into the paper. The screens slowly sway, so the
/// dots drift across the picture.
final class LookHalftoneLens: Lens {
    let needs: LensNeeds = []

    /// The screen's angle in radians. It sways a few degrees either way, so the dots never quite stand still.
    static func screenAngle(at time: Double) -> Double { 0.42 + 0.16 * sin(time * 0.35) }

    private static let paper: LookColour = (0.975, 0.945, 0.865)

    /// One printing plate: which ink, how far its screen is turned from the others and how far out of register it sits.
    private struct Plate {
        let ink: LookColour
        let angle: Double
        let offset: CGPoint
        /// How much of this ink each colour needs (white is none), on the eye's scale.
        let amount: LookGrade
    }

    /// How much black ink: only the deep shadows, so colours stay clean.
    private static func key(_ c: SIMD3<Float>) -> Float { LookTone.smooth(0.25, 1.0, 1 - max(c.x, max(c.y, c.z))) * 0.85 }

    private static func plate(_ ink: LookColour, angle: Double, offset: CGPoint, _ share: @escaping (SIMD3<Float>) -> Float) -> Plate {
        Plate(ink: ink, angle: angle, offset: offset, amount: LookGrade(size: 16) { c in SIMD3(repeating: 1 - min(1, max(0, share(c)))) })
    }

    private static let plates: [Plate] = [
        plate((0.00, 0.62, 0.89), angle: 0.26, offset: CGPoint(x: 1.2, y: 0)) { c in (1 - c.x) - key(c) * 0.9 },
        plate((0.90, 0.13, 0.50), angle: 1.31, offset: CGPoint(x: -0.8, y: 1.0)) { c in ((1 - c.y) - key(c) * 0.9) * 0.92 },
        plate((1.00, 0.89, 0.10), angle: 0.0, offset: .zero) { c in ((1 - c.z) - key(c) * 0.9) * 0.85 },
        plate((0.13, 0.12, 0.14), angle: 0.785, offset: .zero) { c in key(c) },
    ]

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        // A soft blur first keeps the camera's noise from turning into stray dots, and print likes strong colour.
        let bold = input.composed.clampedToExtent().applyingGaussianBlur(sigma: 1.6).cropped(to: rect)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.25, kCIInputContrastKey: 1.06])
        let sway = Self.screenAngle(at: input.time) - 0.42
        var printed = CIImage(color: LookKit.ciColour(Self.paper)).cropped(to: rect)
        for plate in Self.plates {
            // The plate's coverage as grey (white is no ink) is screened into dots, and the dots are printed in the plate's ink.
            // The screen works on the eye's scale, or it would lay down far too much ink.
            let coverage = LookKit.perceptual(plate.amount.apply(bold))
            let dots = coverage.applyingFilter("CIDotScreen", parameters: [
                kCIInputCenterKey: CIVector(x: rect.midX, y: rect.midY), kCIInputAngleKey: plate.angle + sway,
                kCIInputWidthKey: 10.0, kCIInputSharpnessKey: 0.62,
            ])
            let inked = dots.applyingFilter("CIFalseColor", parameters: ["inputColor0": LookKit.ciColour(plate.ink), "inputColor1": CIColor(red: 1, green: 1, blue: 1)])
                .clampedToExtent().transformed(by: CGAffineTransform(translationX: plate.offset.x, y: plate.offset.y)).cropped(to: rect)
            printed = LookKit.multiply(inked, over: printed)
        }
        // Newsprint has a tooth to it, and yellows a little towards the edges.
        let aged = LookKit.multiply(LookKit.tint(LookKit.ovalVignette(rect, reach: 0.55, edge: 0.82), by: (1, 0.98, 0.9)), over: printed)
        return LookKit.grained(aged, frame: 7, rect: rect, amount: 0.16, size: 1.3).cropped(to: rect)
    }
}
