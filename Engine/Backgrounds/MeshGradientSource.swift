import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// How one gradient preset is mixed: a ground colour and a few "inks" that each glow around a point and drift slowly
/// on their own small orbits.
struct BackdropMeshRecipe {
    struct Ink {
        var color: BackdropRGB
        /// Home position, as shares of the width and height (0,0 bottom left).
        var x: Double, y: Double
        /// How far the ink reaches, as a share of the width.
        var reach: Double
        /// Orbit size (shares of the width and height) and speed (radians a second).
        var orbitX: Double = 0.10, orbitY: Double = 0.08, speed: Double = 0.07, phase: Double = 0
    }

    var ground: BackdropRGB
    var inks: [Ink]
    /// How much the ground colour holds its own against the inks (0.1 lets the inks fill everything, 1 keeps them apart).
    var groundWeight: Double = 0.12
    /// Film grain, 0 to 1.5.
    var grain: Double = 0.8
    /// How much the corners darken.
    var vignette: Double = 0.16
    /// How strongly the faint folds of light show (0 none, 0.08 clear).
    var sheen: Double = 0.05
}

/// A slowly moving mesh gradient: colours mix in Oklab on a small grid (cheap, and only smooth things live there), the grid
/// is warped by slow waves so the shapes are organic rather than round blobs, enlarged smoothly to the frame, and finished
/// with fine grain and dither so it never bands. Everything comes from the clock, so a stall cannot make it jump.
final class GradientSource: BackgroundSource {
    private static let cols = 48, rows = 27
    private let recipe: BackdropMeshRecipe
    private let inkLab: [SIMD3<Double>]
    private let groundLab: SIMD3<Double>
    private var pixels: [Float]

    init(preset: GradientPreset) {
        recipe = preset.mesh
        inkLab = recipe.inks.map { BackdropInk.oklab($0.color) }
        groundLab = BackdropInk.oklab(recipe.ground)
        pixels = [Float](repeating: 1, count: Self.cols * Self.rows * 4)
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        fill(at: time)
        let bytes = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        let small = CIImage(bitmapData: bytes, bytesPerRow: Self.cols * 16, size: CGSize(width: Self.cols, height: Self.rows),
                            format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        // A B-spline enlargement: the smoothest there is, with no ringing.
        let enlarge = CIFilter.bicubicScaleTransform()
        enlarge.inputImage = small.clampedToExtent()
        enlarge.scale = Float(1280.0 / Double(Self.cols - 1))
        enlarge.aspectRatio = Float((720.0 / Double(Self.rows - 1)) / (1280.0 / Double(Self.cols - 1)))
        enlarge.parameterB = 1
        enlarge.parameterC = 0
        guard let big = enlarge.outputImage else { return nil }
        let half = CGFloat(1280.0 / Double(Self.cols - 1)) / 2
        let placed = big.transformed(by: CGAffineTransform(translationX: -half, y: -half)).cropped(to: BackdropPainter.frame)
        return BackdropFinish.finish(BackdropFinish.vignette(placed, strength: recipe.vignette), grain: recipe.grain)
    }

    /// The mix at every grid point, in linear RGB.
    private func fill(at time: Double) {
        let cols = Self.cols, rows = Self.rows
        // Each ink's place now. The clock is folded into a turn first, so weeks of uptime cannot cost precision.
        let centres: [(x: Double, y: Double, inv: Double)] = recipe.inks.map { ink in
            let a = 2 * Double.pi * BackdropMath.fract(time * ink.speed / (2 * .pi) + ink.phase / (2 * .pi))
            let b = 2 * Double.pi * BackdropMath.fract(time * ink.speed * 0.73 / (2 * .pi) + ink.phase * 1.7 / (2 * .pi))
            // Squared falloff, sharpened: each ink holds a region of its own with a soft seam, rather than all of them
            // averaging out to one muddy middle colour.
            let r = ink.reach * 0.62
            return (ink.x + ink.orbitX * cos(a), (ink.y + ink.orbitY * sin(b)) * 9 / 16, 1 / (2 * r * r))
        }
        let warpA = 2 * Double.pi * BackdropMath.fract(time * 0.013), warpB = 2 * Double.pi * BackdropMath.fract(time * 0.009 + 0.3)
        let ground = recipe.groundWeight
        inkLab.withUnsafeBufferPointer { labs in
            pixels.withUnsafeMutableBufferPointer { out in
                for j in 0..<rows {
                    // The first row in memory is the top of the picture.
                    let v = 1 - Double(j) / Double(rows - 1)
                    for i in 0..<cols {
                        let u = Double(i) / Double(cols - 1)
                        // Slow waves bend the space the inks glow in, so their edges curve and flow.
                        let wx = u + 0.045 * sin(v * 5.1 + warpA) + 0.025 * sin((u + v) * 7.3 - warpB)
                        let wy = v * 9 / 16 + 0.035 * sin(u * 4.3 - warpB) + 0.02 * sin((u - v) * 8.1 + warpA)
                        var total = ground
                        var lab = groundLab * ground
                        for k in 0..<centres.count {
                            let dx = wx - centres[k].x, dy = wy - centres[k].y
                            let w = exp(-(dx * dx + dy * dy) * centres[k].inv)
                            total += w
                            lab += labs[k] * w
                        }
                        var mixed = lab / total
                        // A slow, faint fold of light across it, like silk, so it has form and not just colour.
                        let fold = sin(wx * 5.2 + wy * 7.4 + warpA * 2) * 0.5 + sin(wx * 2.3 - wy * 4.1 - warpB) * 0.5
                        mixed.x *= 1 + recipe.sheen * fold
                        let rgb = BackdropInk.linearRGB(mixed)
                        let at = (j * cols + i) * 4
                        out[at] = Float(max(0, rgb.x))
                        out[at + 1] = Float(max(0, rgb.y))
                        out[at + 2] = Float(max(0, rgb.z))
                    }
                }
            }
        }
    }
}

// MARK: - The presets' recipes

extension GradientPreset {
    /// The palettes, named for what they are: every ink is chosen to sit well behind skin and to stay clear of skin tone in the
    /// middle of the frame, where a head goes.
    var mesh: BackdropMeshRecipe {
        typealias Ink = BackdropMeshRecipe.Ink
        let c = BackdropRGB.init(hex:)
        switch self {
        case .aurora:
            return BackdropMeshRecipe(ground: c(0x0A1A2C), inks: [
                Ink(color: c(0x13B58C), x: 0.18, y: 0.78, reach: 0.26, speed: 0.06, phase: 0.3),
                Ink(color: c(0x6B4FE0), x: 0.86, y: 0.82, reach: 0.24, speed: 0.05, phase: 2.0),
                Ink(color: c(0x0C6E7E), x: 0.62, y: 0.22, reach: 0.30, speed: 0.04, phase: 4.1),
                Ink(color: c(0x8CF5C4), x: 0.08, y: 0.30, reach: 0.12, speed: 0.08, phase: 1.1),
                Ink(color: c(0x24306E), x: 0.50, y: 0.60, reach: 0.22, speed: 0.05, phase: 5.2),
            ])
        case .sunset:
            return BackdropMeshRecipe(ground: c(0x2A1238), inks: [
                Ink(color: c(0xF0624D), x: 0.15, y: 0.18, reach: 0.26, speed: 0.05, phase: 0.2),
                Ink(color: c(0xFFAE5C), x: 0.88, y: 0.20, reach: 0.20, speed: 0.06, phase: 1.7),
                Ink(color: c(0xC2357A), x: 0.80, y: 0.70, reach: 0.26, speed: 0.04, phase: 3.3),
                Ink(color: c(0x5A2A8C), x: 0.40, y: 0.88, reach: 0.30, speed: 0.05, phase: 4.6),
                Ink(color: c(0x8E2E6E), x: 0.50, y: 0.50, reach: 0.20, speed: 0.04, phase: 2.6),
            ], groundWeight: 0.1)
        case .ocean:
            return BackdropMeshRecipe(ground: c(0x041A3A), inks: [
                Ink(color: c(0x0B5DA8), x: 0.25, y: 0.70, reach: 0.30, speed: 0.05, phase: 0.6),
                Ink(color: c(0x3FB7D9), x: 0.85, y: 0.82, reach: 0.20, speed: 0.06, phase: 2.2),
                Ink(color: c(0x0A3C70), x: 0.70, y: 0.25, reach: 0.30, speed: 0.04, phase: 4.0),
                Ink(color: c(0x5ED6C8), x: 0.06, y: 0.12, reach: 0.14, speed: 0.07, phase: 5.1),
                Ink(color: c(0x173E8F), x: 0.48, y: 0.55, reach: 0.22, speed: 0.05, phase: 1.4),
            ])
        case .graphite:
            return BackdropMeshRecipe(ground: c(0x16171B), inks: [
                Ink(color: c(0x4A4E58), x: 0.22, y: 0.80, reach: 0.30, speed: 0.04, phase: 0.4),
                Ink(color: c(0x2C3038), x: 0.80, y: 0.30, reach: 0.30, speed: 0.04, phase: 2.5),
                Ink(color: c(0x6C7280), x: 0.86, y: 0.86, reach: 0.16, speed: 0.05, phase: 4.2),
                Ink(color: c(0x23262D), x: 0.40, y: 0.20, reach: 0.26, speed: 0.04, phase: 1.3),
                Ink(color: c(0x3A3F4A), x: 0.55, y: 0.62, reach: 0.22, speed: 0.03, phase: 5.5),
            ], grain: 1.0, vignette: 0.22)
        case .forest:
            return BackdropMeshRecipe(ground: c(0x07211A), inks: [
                Ink(color: c(0x1E6B45), x: 0.20, y: 0.72, reach: 0.30, speed: 0.05, phase: 0.1),
                Ink(color: c(0x7CB342), x: 0.88, y: 0.84, reach: 0.18, speed: 0.06, phase: 1.9),
                Ink(color: c(0x0F5A5A), x: 0.75, y: 0.28, reach: 0.28, speed: 0.04, phase: 3.6),
                Ink(color: c(0x2E8B57), x: 0.06, y: 0.15, reach: 0.18, speed: 0.06, phase: 5.0),
                Ink(color: c(0x134032), x: 0.50, y: 0.50, reach: 0.24, speed: 0.04, phase: 2.7),
            ])
        case .candy:
            return BackdropMeshRecipe(ground: c(0x7A3E9C), inks: [
                Ink(color: c(0xF77FB3), x: 0.12, y: 0.80, reach: 0.24, speed: 0.06, phase: 0.5),
                Ink(color: c(0x6FD6EA), x: 0.90, y: 0.78, reach: 0.20, speed: 0.06, phase: 2.0),
                Ink(color: c(0xFFC2D9), x: 0.86, y: 0.14, reach: 0.18, speed: 0.05, phase: 3.9),
                Ink(color: c(0x9F6BE0), x: 0.20, y: 0.18, reach: 0.26, speed: 0.05, phase: 5.3),
                Ink(color: c(0x8D4FC0), x: 0.50, y: 0.55, reach: 0.22, speed: 0.04, phase: 1.2),
            ], groundWeight: 0.15, grain: 0.7, vignette: 0.10)
        case .lavender:
            return BackdropMeshRecipe(ground: c(0x3A2F6E), inks: [
                Ink(color: c(0x9C8CE6), x: 0.18, y: 0.80, reach: 0.26, speed: 0.05, phase: 0.8),
                Ink(color: c(0xC7B8F5), x: 0.88, y: 0.86, reach: 0.18, speed: 0.06, phase: 2.4),
                Ink(color: c(0x8FB4EE), x: 0.82, y: 0.22, reach: 0.24, speed: 0.04, phase: 4.4),
                Ink(color: c(0x5B4AA8), x: 0.18, y: 0.15, reach: 0.26, speed: 0.05, phase: 1.6),
                Ink(color: c(0x6A5BB8), x: 0.50, y: 0.55, reach: 0.22, speed: 0.04, phase: 3.1),
            ], groundWeight: 0.15, vignette: 0.12)
        case .ember:
            return BackdropMeshRecipe(ground: c(0x170507), inks: [
                Ink(color: c(0xA3241A), x: 0.22, y: 0.25, reach: 0.30, speed: 0.06, phase: 0.2),
                Ink(color: c(0xFF7A1F), x: 0.86, y: 0.18, reach: 0.18, speed: 0.07, phase: 1.8),
                Ink(color: c(0x6E1010), x: 0.75, y: 0.75, reach: 0.28, speed: 0.05, phase: 3.4),
                Ink(color: c(0xE04A1C), x: 0.08, y: 0.85, reach: 0.16, speed: 0.06, phase: 4.9),
                Ink(color: c(0x3D0A0E), x: 0.50, y: 0.58, reach: 0.24, speed: 0.04, phase: 2.2),
            ], grain: 1.0, vignette: 0.2)
        case .mint:
            return BackdropMeshRecipe(ground: c(0x0E4A4C), inks: [
                Ink(color: c(0x58C9A8), x: 0.18, y: 0.78, reach: 0.26, speed: 0.05, phase: 0.6),
                Ink(color: c(0xB8F2D8), x: 0.88, y: 0.86, reach: 0.18, speed: 0.06, phase: 2.1),
                Ink(color: c(0x5BC6DC), x: 0.84, y: 0.20, reach: 0.24, speed: 0.04, phase: 3.8),
                Ink(color: c(0x1D7A72), x: 0.16, y: 0.16, reach: 0.26, speed: 0.05, phase: 5.0),
                Ink(color: c(0x237E78), x: 0.50, y: 0.56, reach: 0.22, speed: 0.04, phase: 1.3),
            ], groundWeight: 0.15, vignette: 0.12)
        case .midnight:
            return BackdropMeshRecipe(ground: c(0x03051A), inks: [
                Ink(color: c(0x1A2470), x: 0.22, y: 0.70, reach: 0.30, speed: 0.04, phase: 0.3),
                Ink(color: c(0x5B33A8), x: 0.86, y: 0.82, reach: 0.22, speed: 0.05, phase: 2.2),
                Ink(color: c(0x2D45B8), x: 0.78, y: 0.22, reach: 0.22, speed: 0.04, phase: 4.0),
                Ink(color: c(0x0B0F3A), x: 0.45, y: 0.40, reach: 0.30, speed: 0.04, phase: 1.0),
                Ink(color: c(0x7C4FD6), x: 0.06, y: 0.10, reach: 0.12, speed: 0.06, phase: 5.5),
            ], grain: 1.0, vignette: 0.22)
        case .roseGold:
            return BackdropMeshRecipe(ground: c(0x5E3442), inks: [
                Ink(color: c(0xC98A8E), x: 0.16, y: 0.80, reach: 0.24, speed: 0.05, phase: 0.4),
                Ink(color: c(0xF2C9A4), x: 0.88, y: 0.86, reach: 0.16, speed: 0.06, phase: 2.0),
                Ink(color: c(0xB76E86), x: 0.84, y: 0.24, reach: 0.24, speed: 0.04, phase: 3.6),
                Ink(color: c(0x7A4058), x: 0.18, y: 0.16, reach: 0.26, speed: 0.05, phase: 5.1),
                Ink(color: c(0x8E4F63), x: 0.50, y: 0.56, reach: 0.22, speed: 0.04, phase: 1.5),
            ], groundWeight: 0.15, vignette: 0.14)
        case .neon:
            return BackdropMeshRecipe(ground: c(0x0A0420), inks: [
                Ink(color: c(0xFF2DA6), x: 0.12, y: 0.25, reach: 0.22, speed: 0.07, phase: 0.2),
                Ink(color: c(0x00D4FF), x: 0.88, y: 0.72, reach: 0.20, speed: 0.07, phase: 2.4),
                Ink(color: c(0x5B1AB8), x: 0.70, y: 0.20, reach: 0.26, speed: 0.05, phase: 4.0),
                Ink(color: c(0x2A0C6E), x: 0.30, y: 0.80, reach: 0.28, speed: 0.05, phase: 1.1),
                Ink(color: c(0x150838), x: 0.50, y: 0.52, reach: 0.22, speed: 0.04, phase: 3.0),
            ], grain: 0.9, vignette: 0.2)
        case .lagoon:
            return BackdropMeshRecipe(ground: c(0x06323F), inks: [
                Ink(color: c(0x12A3A3), x: 0.20, y: 0.75, reach: 0.26, speed: 0.05, phase: 0.9),
                Ink(color: c(0xB7E35A), x: 0.90, y: 0.88, reach: 0.14, speed: 0.06, phase: 2.6),
                Ink(color: c(0x1C6FB8), x: 0.80, y: 0.30, reach: 0.28, speed: 0.04, phase: 4.3),
                Ink(color: c(0x2FD3B5), x: 0.08, y: 0.14, reach: 0.18, speed: 0.06, phase: 5.6),
                Ink(color: c(0x0B4E66), x: 0.50, y: 0.55, reach: 0.22, speed: 0.04, phase: 1.9),
            ])
        case .nectar:
            return BackdropMeshRecipe(ground: c(0x3A0D2E), inks: [
                Ink(color: c(0xFF8A3D), x: 0.10, y: 0.22, reach: 0.22, speed: 0.06, phase: 0.7),
                Ink(color: c(0xE8336E), x: 0.85, y: 0.30, reach: 0.26, speed: 0.05, phase: 2.3),
                Ink(color: c(0xFFC94A), x: 0.92, y: 0.90, reach: 0.12, speed: 0.07, phase: 4.1),
                Ink(color: c(0x7B1E5A), x: 0.25, y: 0.85, reach: 0.28, speed: 0.04, phase: 5.4),
                Ink(color: c(0x5C1446), x: 0.50, y: 0.55, reach: 0.22, speed: 0.04, phase: 3.2),
            ], groundWeight: 0.1)
        case .iris:
            return BackdropMeshRecipe(ground: c(0x1B1446), inks: [
                Ink(color: c(0x4B3BD1), x: 0.18, y: 0.72, reach: 0.28, speed: 0.05, phase: 0.3),
                Ink(color: c(0xF2A07B), x: 0.90, y: 0.15, reach: 0.15, speed: 0.06, phase: 2.0),
                Ink(color: c(0xA05CD6), x: 0.80, y: 0.78, reach: 0.24, speed: 0.05, phase: 3.7),
                Ink(color: c(0x2A5BD7), x: 0.10, y: 0.12, reach: 0.20, speed: 0.06, phase: 5.2),
                Ink(color: c(0x2C1F70), x: 0.50, y: 0.52, reach: 0.24, speed: 0.04, phase: 1.4),
            ])
        case .sage:
            return BackdropMeshRecipe(ground: c(0x2E3B2F), inks: [
                Ink(color: c(0x8FA67E), x: 0.15, y: 0.78, reach: 0.26, speed: 0.04, phase: 0.5),
                Ink(color: c(0xD9CBA3), x: 0.90, y: 0.88, reach: 0.14, speed: 0.05, phase: 2.2),
                Ink(color: c(0xB36A4A), x: 0.86, y: 0.16, reach: 0.18, speed: 0.04, phase: 3.9),
                Ink(color: c(0x55705A), x: 0.20, y: 0.18, reach: 0.26, speed: 0.04, phase: 5.0),
                Ink(color: c(0x3F5444), x: 0.50, y: 0.56, reach: 0.24, speed: 0.03, phase: 1.7),
            ], groundWeight: 0.15, grain: 1.0, vignette: 0.16)
        case .glacier:
            return BackdropMeshRecipe(ground: c(0x0F2A4A), inks: [
                Ink(color: c(0x7FB8E6), x: 0.15, y: 0.82, reach: 0.24, speed: 0.05, phase: 0.6),
                Ink(color: c(0xE3F1FA), x: 0.90, y: 0.90, reach: 0.14, speed: 0.06, phase: 2.5),
                Ink(color: c(0x2F6FA8), x: 0.82, y: 0.25, reach: 0.28, speed: 0.04, phase: 4.2),
                Ink(color: c(0x9AD3D9), x: 0.08, y: 0.12, reach: 0.16, speed: 0.06, phase: 5.7),
                Ink(color: c(0x1D4B78), x: 0.50, y: 0.54, reach: 0.24, speed: 0.04, phase: 1.2),
            ], groundWeight: 0.14)
        case .cobalt:
            return BackdropMeshRecipe(ground: c(0x050B2E), inks: [
                Ink(color: c(0x1F4BFF), x: 0.20, y: 0.30, reach: 0.26, speed: 0.06, phase: 0.4),
                Ink(color: c(0x00C2FF), x: 0.88, y: 0.82, reach: 0.18, speed: 0.06, phase: 2.1),
                Ink(color: c(0x0E1F8C), x: 0.75, y: 0.20, reach: 0.30, speed: 0.04, phase: 3.8),
                Ink(color: c(0x6A7BFF), x: 0.10, y: 0.88, reach: 0.14, speed: 0.07, phase: 5.3),
                Ink(color: c(0x0A1660), x: 0.50, y: 0.55, reach: 0.22, speed: 0.04, phase: 1.6),
            ], grain: 0.9, vignette: 0.2)
        }
    }
}
