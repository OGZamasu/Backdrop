import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Slow, smooth swirls of colour like folds of silk: the classic plasma, tuned down so it flatters a face instead of
/// fighting it.
///
/// Four waves are added up for each point of a very small grid (nine thousand points), after the grid itself is bent by
/// two slower waves so the bands curl instead of running straight; the total picks a colour from a ready-made palette
/// with a soft sheen in it. Enlarging that grid smoothly to the full frame leaves nothing but soft curves, and dither
/// keeps them from banding. The waves are looked up in tables, and the grid is built with plain pointer loops, so a
/// frame costs well under a millisecond.
final class PlasmaSource: BackgroundSource {
    private static let cols = 128, rows = 72
    private static let tableSize = 2048
    private static let size = CGSize(width: 1280, height: 720)

    /// sin over one turn, so each wave is a table lookup.
    private let sine: [Float]
    /// Palette entries, premultiplied RGBA8 (the plasma is opaque, so that is just RGBA).
    private let palette: [UInt32]
    /// Distance of each grid point from the middle, in turns of the radial wave, worked out once.
    private let ring: [Float]
    private var pixels: [UInt32]

    init() {
        sine = (0..<Self.tableSize).map { Float(sin(2 * Double.pi * Double($0) / Double(Self.tableSize))) }
        palette = Self.makePalette()
        var ring: [Float] = []
        ring.reserveCapacity(Self.cols * Self.rows)
        for y in 0..<Self.rows {
            for x in 0..<Self.cols {
                // Pixels are wider than tall in the picture, so measure in picture shape.
                let dx = (Float(x) / Float(Self.cols) - 0.5) * 16
                let dy = (Float(y) / Float(Self.rows) - 0.5) * 9
                ring.append((dx * dx + dy * dy).squareRoot() / 9)
            }
        }
        self.ring = ring
        pixels = [UInt32](repeating: 0, count: Self.cols * Self.rows)
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        fill(at: time)
        let bytes = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        let small = CIImage(bitmapData: bytes, bytesPerRow: Self.cols * 4, size: CGSize(width: Self.cols, height: Self.rows),
                            format: .RGBA8, colorSpace: BackdropCanvas.space)
        let enlarge = CIFilter.bicubicScaleTransform()
        enlarge.inputImage = small.clampedToExtent()
        enlarge.scale = Float(Self.size.width) / Float(Self.cols)
        enlarge.aspectRatio = 1
        enlarge.parameterB = 1
        enlarge.parameterC = 0
        guard let big = enlarge.outputImage?.cropped(to: CGRect(origin: .zero, size: Self.size)) else { return nil }
        return BackdropFinish.finish(BackdropFinish.vignette(big, strength: 0.18), grain: 0.6)
    }

    // MARK: Waves

    private func fill(at time: Double) {
        let cols = Self.cols, rows = Self.rows, n = Self.tableSize
        let mask = n - 1
        let turn = Float(n)

        // Each wave runs along x, along y, along a diagonal or outward from the middle, at its own slow speed. The clock
        // is reduced to part of a turn in full precision first: a camera clock can be weeks old, and a Float that large
        // could no longer tell one frame from the next.
        func phase(_ speed: Double) -> Float { Float(BackdropMath.fract(time * speed) * Double(n)) }
        let phaseA = phase(0.045), phaseB = phase(-0.037), phaseC = phase(0.029), phaseD = phase(-0.052)
        let bendA = phase(0.021), bendB = phase(-0.017)
        let paletteScale = Float(palette.count)
        let drift = Float(BackdropMath.fract(time * 0.012))

        sine.withUnsafeBufferPointer { sine in
            palette.withUnsafeBufferPointer { palette in
                ring.withUnsafeBufferPointer { ring in
                    pixels.withUnsafeMutableBufferPointer { out in
                        for y in 0..<rows {
                            let gy = Float(y) / Float(rows)
                            for x in 0..<cols {
                                let gx = Float(x) / Float(cols)
                                // Bend the grid first, so the bands curl like cloth rather than run straight.
                                let fx = gx + 0.09 * sine[(Int((gy * 1.1 + gx * 0.3) * turn + bendA) & mask)]
                                let fy = gy + 0.08 * sine[(Int((gx * 0.9 - gy * 0.2) * turn + bendB) & mask)]
                                let waveB = sine[(Int(fy * 1.7 * turn + phaseB) & mask)]
                                let waveA = sine[(Int(fx * 1.3 * turn + phaseA) & mask)]
                                let waveC = sine[(Int((fx * 0.9 + fy * 1.1) * turn + phaseC) & mask)]
                                let waveD = sine[(Int(ring[y * cols + x] * 1.5 * turn + phaseD) & mask)]
                                // Four waves add to -4...4; fold that into 0...1 and slide it slowly around the palette.
                                let total = (waveA + waveB + waveC + waveD) * 0.125 + 0.5 + drift
                                let wrapped = total - total.rounded(.down)
                                out[y * cols + x] = palette[min(palette.count - 1, Int(wrapped * paletteScale))]
                            }
                        }
                    }
                }
            }
        }
    }

    /// Night navy through indigo, violet and plum to a rose sheen and back by way of a deep teal, so the loop has no seam.
    /// Kept in the mid-tones: nothing as bright or as saturated as the face in front of it. Each band darkens toward its
    /// edges and lifts in its middle, which is what reads as the fold of a fabric.
    private static func makePalette() -> [UInt32] {
        let stops: [(Double, Double, Double)] = [
            (0.04, 0.05, 0.18), (0.12, 0.10, 0.38), (0.30, 0.12, 0.50), (0.56, 0.20, 0.56), (0.86, 0.48, 0.62),
            (0.52, 0.18, 0.52), (0.16, 0.12, 0.42), (0.06, 0.24, 0.40), (0.10, 0.40, 0.50), (0.05, 0.14, 0.28), (0.04, 0.05, 0.18),
        ]
        return (0..<512).map { i in
            let position = Double(i) / 512 * Double(stops.count - 1)
            let lower = min(stops.count - 2, Int(position))
            let t = BackdropMath.smoothstep(0, 1, position - Double(lower))
            let a = stops[lower], b = stops[lower + 1]
            func byte(_ x: Double) -> UInt32 { UInt32(min(255, max(0, (x * 255).rounded()))) }
            // RGBA in memory order, little-endian: red is the lowest byte.
            return byte(BackdropMath.mix(a.0, b.0, t)) | byte(BackdropMath.mix(a.1, b.1, t)) << 8
                | byte(BackdropMath.mix(a.2, b.2, t)) << 16 | 0xFF << 24
        }
    }
}
