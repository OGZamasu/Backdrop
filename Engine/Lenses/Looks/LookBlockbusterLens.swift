import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// How the widescreen bars come in. Pure, so it can be tested.
enum LookBlockbusterPlan {
    /// The shape of a cinema screen, wider than a video call's.
    static let aspect = 2.2

    /// How tall each bar is when fully in, for a frame of this size.
    static func barHeight(for size: CGSize) -> Double { max(0, (size.height - size.width / aspect) / 2) }

    /// 0 when the look starts, sliding to 1 over a second with a soft landing.
    static func barsIn(after seconds: Double) -> Double {
        let t = min(1, max(0, seconds / 1.1))
        return 1 - pow(1 - t, 3)
    }
}

/// A summer blockbuster: skin pushed warm and golden, everything else into deep teal, a film curve with rich blacks, a soft
/// glow on the highlights, fine grain and widescreen bars that slide in when you pick it.
final class LookBlockbusterLens: Lens {
    let needs: LensNeeds = []

    private var clock = LookClock()

    func restart() { clock.restart() }

    /// Orange and teal: skin (found by its hue, so any skin tone) is warmed towards amber, and the rest of the picture is cooled
    /// towards teal, most of all in the shadows. The brightness of every tone is kept; only its colour moves.
    static func grade(_ c: SIMD3<Float>) -> SIMD3<Float> {
        // Only clearly skin-coloured things count as skin here, so a beige wall still goes teal.
        let skin = LookTone.skinness(c) * LookTone.smooth(0.22, 0.34, LookTone.hsv(c).y)
        var x = LookTone.filmic(c, contrast: 1.28, black: 0.022, white: 0.975, pivot: 0.43)
        let l = LookTone.luma(x)
        let shadow = 1 - LookTone.smooth(0.05, 0.55, l), light = LookTone.smooth(0.55, 1.0, l)
        let cool = SIMD3<Float>(-0.07, 0.025, 0.06) * (0.45 + 0.55 * shadow) * (1 - skin)
        let warm = SIMD3<Float>(0.055, 0.012, -0.06) * skin
        x += cool + warm + SIMD3<Float>(0.02, 0.008, -0.025) * light
        let saturation: Float = 1.08 + 0.12 * skin
        return simd_clamp(LookTone.saturate(x, saturation), SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
    }

    private static let cube = LookGrade { grade($0) }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let t = clock.elapsed(at: input.time)
        let graded = Self.cube.apply(input.composed)
        // Highlights bloom softly and warmly, as through a big glass lens.
        let glow = LookKit.glow(graded, rect: rect, threshold: 0.6, sigma: 7, tint: (1.0, 0.86, 0.7))
        let bloomed = LookKit.screen(LookKit.levels(glow, gain: 0.3), over: graded)
        let shaded = LookKit.multiply(LookKit.ovalVignette(rect, reach: 0.45, edge: LookKit.lin(0.62)), over: bloomed)
        let grainy = LookKit.filmGrain(shaded, frame: Int(input.time * 24), rect: rect, amount: 0.1, size: 1.1)

        // The bars, sliding in from the top and bottom.
        let bar = LookBlockbusterPlan.barHeight(for: rect.size) * LookBlockbusterPlan.barsIn(after: t)
        guard bar > 0.5 else { return grainy.cropped(to: rect) }
        let black = CIImage(color: CIColor(red: 0.008, green: 0.008, blue: 0.01))
        let bars = black.cropped(to: CGRect(x: rect.minX, y: rect.maxY - bar, width: rect.width, height: bar))
            .composited(over: black.cropped(to: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bar)))
        return bars.composited(over: grainy).cropped(to: rect)
    }
}
