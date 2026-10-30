import CoreImage
import CoreImage.CIFilterBuiltins

/// When and how the picture breaks up. Pure, so it can be tested without drawing anything.
enum GlitchPlan {
    struct Tear: Equatable { var y: Double; var height: Double; var shift: Double }

    private static let window = 2.4

    /// How badly the picture is glitching right now, 0...1. Short bursts at irregular times.
    static func burst(at time: Double) -> Double {
        let index = Int((time / window).rounded(.down))
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9 &+ 17)
        guard Double.random(in: 0..<1, using: &rng) < 0.7 else { return 0 }
        let start = Double.random(in: 0...(window * 0.6), using: &rng)
        let length = Double.random(in: 0.12...0.5, using: &rng)
        let local = time - Double(index) * window - start
        guard local >= 0, local < length else { return 0 }
        return sin(.pi * local / length)
    }

    /// Strips of the picture knocked sideways. Changes about 15 times a second so it jitters.
    static func tears(at time: Double, burst: Double, height: Double) -> [Tear] {
        guard burst > 0.05 else { return [] }
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64((time * 15).rounded(.down))) &* 0xBF58_476D &+ 5)
        return (0..<(2 + Int(burst * 5))).map { _ in
            Tear(y: Double.random(in: 0...height, using: &rng),
                 height: Double.random(in: 8...70, using: &rng),
                 shift: Double.random(in: -1...1, using: &rng) * (30 + 130 * burst))
        }
    }
}

/// A failing video tape: colour channels drifting apart, torn bands, scan lines and snow.
final class GlitchLens: Lens {
    let needs: LensNeeds = []

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect, t = input.time
        let burst = GlitchPlan.burst(at: t)
        let split = 3 + 30 * burst

        func channel(_ r: Double, _ g: Double, _ b: Double, dx: Double, dy: Double = 0) -> CIImage {
            input.composed
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ])
                .clampedToExtent().transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: rect)
        }
        // Screen-blending three single-colour copies rebuilds the picture, with the colours misregistered.
        var picture = channel(1, 0, 0, dx: split)
            .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: channel(0, 1, 0, dx: 0)])
            .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: channel(0, 0, 1, dx: -split, dy: split * 0.15)])
            .cropped(to: rect)

        for tear in GlitchPlan.tears(at: t, burst: burst, height: rect.height) {
            let band = CGRect(x: rect.minX, y: tear.y, width: rect.width, height: tear.height).intersection(rect)
            guard !band.isEmpty else { continue }
            let moved = picture.clampedToExtent().transformed(by: CGAffineTransform(translationX: tear.shift, y: 0)).cropped(to: band)
            picture = moved.composited(over: picture)
        }

        // Scan lines, and a flicker of snow.
        let lines = CIFilter.stripesGenerator()
        lines.center = .zero
        lines.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0.24)
        lines.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        lines.width = 2
        lines.sharpness = 1
        let scan = lines.outputImage!.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: rect)
        let snow = CIFilter.randomGenerator().outputImage!
            .transformed(by: CGAffineTransform(translationX: CGFloat(t * 977 .truncatingRemainder(dividingBy: 1000)), y: CGFloat(t * 313 .truncatingRemainder(dividingBy: 1000))))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .fading(0.05 + 0.1 * burst)
            .cropped(to: rect)
        return snow.composited(over: scan.composited(over: picture)).cropped(to: rect)
    }
}
