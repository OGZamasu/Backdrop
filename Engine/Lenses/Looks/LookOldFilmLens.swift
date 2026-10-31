import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// The scratches, dust and hairs on one frame of old film, and how the frame shakes. Pure, so it can be tested.
enum LookFilmPlan {
    enum Mark: Equatable {
        /// A line down the film. `light` scratches are scored through the emulsion, dark ones are dirt.
        case scratch(x: Double, from: Double, to: Double, lean: Double, light: Bool)
        case speck(x: Double, y: Double, size: Double, light: Bool)
        case hair(x: Double, y: Double, length: Double, angle: Double, curl: Double)
    }

    /// Film runs at 12 pictures a second here: the grain, the flicker and the dust change that often and no more.
    static let rate = 12.0

    static func frame(at time: Double) -> Int { Int((time * rate).rounded(.down)) }

    private static func generator(_ frame: Int, salt: UInt64) -> SplitMix64 {
        SplitMix64(seed: UInt64(bitPattern: Int64(frame)) &* 0x9E37_79B9_7F4A_7C15 &+ salt)
    }

    /// How much light gets through this frame: a flutter of a few per cent, now and then a dim one.
    static func exposure(frame: Int) -> Double {
        var rng = generator(frame, salt: 1)
        let flutter = 0.94 + 0.08 * Double.random(in: 0..<1, using: &rng)
        return Double.random(in: 0..<1, using: &rng) < 0.06 ? flutter * 0.84 : flutter
    }

    /// How far the frame sits off true, in pixels.
    static func weave(frame: Int) -> (dx: Double, dy: Double) {
        var rng = generator(frame, salt: 2)
        return (Double.random(in: -2.2...2.2, using: &rng), Double.random(in: -1.6...1.6, using: &rng))
    }

    static func marks(frame: Int, size: CGSize) -> [Mark] {
        var found: [Mark] = []
        // A scratch stays through a few frames, since it is in the film itself and not on the lens.
        var scratches = generator(frame / 5, salt: 3)
        if Double.random(in: 0..<1, using: &scratches) < 0.7 {
            let x = Double.random(in: 0.05...0.95, using: &scratches) * size.width
            let length = Double.random(in: 0.2...0.6, using: &scratches) * size.height
            let top = Double.random(in: 0.0...1.0, using: &scratches) * (size.height - length) + length
            found.append(.scratch(x: x, from: top, to: top - length, lean: Double.random(in: -12...12, using: &scratches), light: Double.random(in: 0..<1, using: &scratches) < 0.7))
        }
        var rng = generator(frame, salt: 4)
        for _ in 0..<Int.random(in: 3...9, using: &rng) {
            found.append(.speck(x: Double.random(in: 0..<size.width, using: &rng), y: Double.random(in: 0..<size.height, using: &rng),
                                size: Double.random(in: 1.2...4.2, using: &rng), light: Double.random(in: 0..<1, using: &rng) < 0.35))
        }
        if Double.random(in: 0..<1, using: &rng) < 0.22 {
            found.append(.hair(x: Double.random(in: 0.1...0.9, using: &rng) * size.width, y: Double.random(in: 0.1...0.9, using: &rng) * size.height,
                               length: Double.random(in: 30...90, using: &rng), angle: Double.random(in: 0..<(2 * .pi), using: &rng),
                               curl: Double.random(in: -0.6...0.6, using: &rng)))
        }
        return found
    }
}

/// A flickering reel of old silver film: a rich black-and-white print with a warm tone in the lights, a glow round bright
/// things, grain, dust, scratches and hairs, and the frame weaving in the gate.
final class LookOldFilmLens: Lens {
    let needs: LensNeeds = []

    /// Panchromatic silver: red a little strong, which is kind to skin; a film curve with deep (not crushed) blacks and
    /// whites that roll off; a warm cream in the lights and a cooler, neutral grey in the shadows.
    private static let silver = LookGrade { c in
        let grey = simd_dot(c, SIMD3<Float>(0.40, 0.48, 0.12))
        let v = LookTone.filmic(grey, contrast: 1.4, black: 0.05, white: 0.93, pivot: 0.36)
        let warm = SIMD3<Float>(1.0, 0.93, 0.80), cool = SIMD3<Float>(0.95, 0.97, 1.0)
        let tone = LookTone.mix(cool, warm, LookTone.smooth(0.15, 0.85, v))
        return v * tone
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let frame = LookFilmPlan.frame(at: input.time)
        let shake = LookFilmPlan.weave(frame: frame)

        // Unsteady, and zoomed in a hair so the shake never shows an edge.
        let zoom = CGAffineTransform(translationX: -rect.midX, y: -rect.midY).concatenating(CGAffineTransform(scaleX: 1.03, y: 1.03))
            .concatenating(CGAffineTransform(translationX: rect.midX + shake.dx, y: rect.midY + shake.dy))
        let steady = input.composed.clampedToExtent().transformed(by: zoom).cropped(to: rect)

        // The print, and the lamp of the projector flickering through it.
        let print = LookKit.levels(Self.silver.apply(steady), gain: LookFilmPlan.exposure(frame: frame))

        // Old lenses glow round the lights.
        let halo = LookKit.glow(print, rect: rect, threshold: 0.42, sigma: 6, tint: (1.0, 0.9, 0.78))
        let soft = LookKit.screen(LookKit.levels(halo, gain: 0.4), over: print)

        // The gate is brighter in the middle and falls off unevenly towards the corners.
        let dark = LookKit.multiply(LookKit.ovalVignette(rect, reach: 0.3, edge: LookKit.lin(0.38)), over: soft)
        let grainy = LookKit.filmGrain(dark, frame: frame, rect: rect, amount: 0.34, size: 1.5)

        guard let dirt = input.services.overlay({ ctx in self.draw(LookFilmPlan.marks(frame: frame, size: rect.size), in: ctx) }) else { return grainy }
        return dirt.composited(over: grainy).cropped(to: rect)
    }

    private func draw(_ marks: [LookFilmPlan.Mark], in ctx: CGContext) {
        let light = CGColor(red: 1, green: 0.96, blue: 0.86, alpha: 0.5)
        let dark = CGColor(red: 0.05, green: 0.03, blue: 0.02, alpha: 0.78)
        ctx.setLineCap(.round)
        for mark in marks {
            switch mark {
            case let .scratch(x, from, to, lean, isLight):
                ctx.setStrokeColor(isLight ? light : dark)
                ctx.setLineWidth(isLight ? 1.4 : 1.8)
                ctx.move(to: CGPoint(x: x, y: from))
                ctx.addLine(to: CGPoint(x: x + lean, y: to))
                ctx.strokePath()
            case let .speck(x, y, size, isLight):
                ctx.setFillColor(isLight ? light : dark)
                ctx.fillEllipse(in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size * 0.8))
            case let .hair(x, y, length, angle, curl):
                ctx.setStrokeColor(dark)
                ctx.setLineWidth(1.3)
                let end = CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length)
                let bend = CGPoint(x: x + cos(angle + curl) * length * 0.55, y: y + sin(angle + curl) * length * 0.55)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addQuadCurve(to: end, control: bend)
                ctx.strokePath()
            }
        }
    }
}
