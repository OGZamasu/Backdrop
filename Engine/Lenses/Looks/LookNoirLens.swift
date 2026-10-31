import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// A detective film from the forties: rich black and white, the room in shadow but for bars of light falling through window
/// blinds, a key light on your face, smoke drifting through the beams, grain and a heavy vignette.
final class LookNoirLens: Lens {
    let needs: LensNeeds = [.matte]

    /// Black-and-white stock seen through a red filter (kind to skin), on a steep film curve: deep blacks that still hold a
    /// little detail and whites that roll off. A breath of cool in the greys, as silver prints have.
    private static let silver = LookGrade { c in
        let grey = simd_dot(c, SIMD3<Float>(0.5, 0.42, 0.08))
        let v = LookTone.filmic(grey, contrast: 1.65, black: 0.02, white: 0.97, pivot: 0.42)
        return SIMD3<Float>(v * 0.98, v * 0.99, min(1, v * 1.02))
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect, t = input.time
        let print = Self.silver.apply(input.composed)
        let quarter = LookKit.size(of: rect, scaledBy: 0.25)

        // Light through blinds: soft bars, slanting down from the upper right, falling in a patch on the wall behind you.
        let bars = CIFilter.stripesGenerator()
        bars.center = .zero
        bars.color0 = CIColor(red: 1, green: 1, blue: 1)
        bars.color1 = CIColor(red: 0, green: 0, blue: 0)
        bars.width = 9
        bars.sharpness = 0.55
        let slant = CGAffineTransform(rotationAngle: .pi / 2 + 0.42)
        let stripes = (bars.outputImage ?? CIImage(color: .white)).transformed(by: slant).cropped(to: quarter)
            .applyingGaussianBlur(sigma: 1.2).cropped(to: quarter)
        let patch = CIFilter.radialGradient()
        patch.center = CGPoint(x: quarter.width * 0.66, y: quarter.height * 0.6)
        patch.radius0 = Float(quarter.width * 0.08)
        patch.radius1 = Float(quarter.width * 0.55)
        patch.color0 = CIColor(red: 1, green: 1, blue: 1)
        patch.color1 = CIColor(red: 0, green: 0, blue: 0)
        let beams = LookKit.multiply(stripes, over: (patch.outputImage ?? CIImage(color: .white)).cropped(to: quarter))
        let wallLight = LookKit.levels(beams, gain: 1.15, bias: 0.12)

        // Smoke, drifting slowly through the light.
        let drift = CGAffineTransform(translationX: CGFloat(t * 3), y: CGFloat(t * 1.2))
        let smoke = LookKit.noise(quarter, frame: 41, size: 22).transformed(by: drift).clampedToExtent().applyingGaussianBlur(sigma: 9).cropped(to: quarter)
        let haze = LookKit.enlarge(LookKit.multiply(LookKit.levels(smoke, gain: 2.2, bias: -0.75), over: LookKit.levels(beams, gain: 0.7, bias: 0.12)), to: rect, from: quarter)

        // You are lit by a key light from the upper left, falling away down your body; the room only by the bars. Both are
        // worked out small and laid over the print in one go.
        var light = wallLight
        if let matte = input.matte {
            let key = CIFilter.radialGradient()
            key.center = CGPoint(x: quarter.width * 0.44, y: quarter.height * 0.72)
            key.radius0 = Float(quarter.height * 0.12)
            key.radius1 = Float(quarter.height * 0.85)
            key.color0 = CIColor(red: 1.08, green: 1.08, blue: 1.08)
            key.color1 = CIColor(red: 0.22, green: 0.22, blue: 0.22)
            light = LookKit.blend((key.outputImage ?? CIImage(color: .white)).cropped(to: quarter), over: wallLight, mask: LookKit.shrink(matte, rect: rect, by: 0.25))
        }
        // The corners fall to black, folded into the same light.
        light = LookKit.multiply(LookKit.ovalVignette(quarter, reach: 0.25, edge: LookKit.lin(0.15)), over: light)
        let picture = LookKit.screen(LookKit.levels(haze, gain: 0.3), over: LookKit.multiply(LookKit.enlarge(light, to: rect, from: quarter), over: print))

        // Light blooms a little, and the grain is that of fast film.
        let glow = LookKit.glow(picture, rect: rect, threshold: 0.55, sigma: 6)
        let bloomed = LookKit.screen(LookKit.levels(glow, gain: 0.35), over: picture)
        return LookKit.filmGrain(bloomed, frame: Int(t * 24), rect: rect, amount: 0.26, size: 1.3).cropped(to: rect)
    }
}
