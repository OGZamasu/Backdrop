import CoreImage
import CoreImage.CIFilterBuiltins

/// When and how the picture breaks up. Pure, so it can be tested without drawing anything.
enum GlitchPlan {
    struct Tear: Equatable { var y: Double; var height: Double; var shift: Double }

    /// A block of the picture broken out of place, as a damaged video stream does: moved, with its colours swapped round, or
    /// crushed into a few coarse squares.
    struct Block: Equatable {
        var rect: CGRect
        var dx: Double
        var dy: Double
        /// 0 leaves the colours alone, 1 swaps red and blue, 2 turns them round once.
        var swap: Int
        var crushed: Bool
    }

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

    /// Blocks on a 16-pixel grid, more of them the worse the burst. Changes 12 times a second.
    static func blocks(at time: Double, burst: Double, size: CGSize) -> [Block] {
        guard burst > 0.2 else { return [] }
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64((time * 12).rounded(.down))) &* 0x94D0_49BB &+ 23)
        let columns = Int(size.width / 16), rows = Int(size.height / 16)
        return (0..<Int(burst * 9)).map { _ in
            let w = Int.random(in: 2...8, using: &rng), h = Int.random(in: 1...4, using: &rng)
            let x = Int.random(in: 0..<max(1, columns - w), using: &rng), y = Int.random(in: 0..<max(1, rows - h), using: &rng)
            return Block(rect: CGRect(x: x * 16, y: y * 16, width: w * 16, height: h * 16),
                         dx: Double(Int.random(in: -5...5, using: &rng) * 16), dy: Double(Int.random(in: -2...2, using: &rng) * 16),
                         swap: Int.random(in: 0...2, using: &rng), crushed: Double.random(in: 0..<1, using: &rng) < 0.4)
        }
    }
}

/// A digital signal breaking up now and then: a whisper of colour fringing while it is calm, then short bursts of torn
/// strips, colour channels sliding apart and blocks of the picture knocked out of place and crushed.
final class GlitchLens: Lens {
    let needs: LensNeeds = []

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect, t = input.time
        let burst = GlitchPlan.burst(at: t)
        let split = 1.5 + 26 * burst

        func channel(_ source: CIImage, _ r: Double, _ g: Double, _ b: Double, dx: Double, dy: Double = 0) -> CIImage {
            source
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ])
                .clampedToExtent().transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: rect)
        }
        // Screen-blending three single-colour copies rebuilds the picture, with the colours misregistered.
        func split3(_ source: CIImage, by amount: Double) -> CIImage {
            channel(source, 1, 0, 0, dx: amount)
                .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: channel(source, 0, 1, 0, dx: 0)])
                .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: channel(source, 0, 0, 1, dx: -amount, dy: amount * 0.15)])
                .cropped(to: rect)
        }
        var picture = split3(input.composed, by: split)

        // Torn strips, each with its own colour slip.
        for tear in GlitchPlan.tears(at: t, burst: burst, height: rect.height) {
            let band = CGRect(x: rect.minX, y: rect.minY + tear.y, width: rect.width, height: tear.height).intersection(rect)
            guard !band.isEmpty else { continue }
            let moved = picture.clampedToExtent().transformed(by: CGAffineTransform(translationX: tear.shift, y: 0)).cropped(to: band)
            picture = moved.composited(over: picture)
        }

        // Broken blocks: lifted from elsewhere in the frame, sometimes with the colours swapped or crushed into coarse squares.
        let source = picture
        for block in GlitchPlan.blocks(at: t, burst: burst, size: rect.size) {
            let target = block.rect.offsetBy(dx: rect.minX, dy: rect.minY).intersection(rect)
            guard !target.isEmpty else { continue }
            var piece = source.clampedToExtent().transformed(by: CGAffineTransform(translationX: block.dx, y: block.dy))
            switch block.swap {
            case 1: piece = piece.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 1, w: 0), "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0)])
            case 2: piece = piece.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 1, w: 0), "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0)])
            default: break
            }
            if block.crushed {
                piece = piece.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: 8.0, kCIInputCenterKey: CIVector(x: target.minX, y: target.minY)])
                    .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 5.0])
            }
            picture = piece.cropped(to: target).composited(over: picture)
        }

        // Fine scan lines always, a little snow only while it is breaking up.
        var result = LookKit.scanlines(rect, period: 3, darkness: 0.1).composited(over: picture)
        if burst > 0.05 {
            let snow = LookKit.speckle(rect, frame: Int(t * 30), coverage: 0.05, strength: 0.35 * burst, size: 1, stretch: 3, colour: (0.9, 0.95, 1))
            result = snow.composited(over: result)
        }
        return result.cropped(to: rect)
    }
}
