import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// A stained-glass window: the picture cut into pieces of jewel-coloured glass held in dark lead, fine pieces for you and big
/// ones for the room as in a real window, your features painted on the glass, the glass mottled and glowing with light from behind, and a slow sunbeam
/// passing across it.
final class LookStainedGlassLens: Lens {
    let needs: LensNeeds = [.matte]

    /// How big the pieces are: small for you, so you stay recognisable, and bigger for the room.
    private static let small = 13.0, large = 44.0

    /// The lead and the shading of each piece: worked out once in the background, since where the pieces fall depends only on
    /// their size, not on the picture. The pieces are cut at half size (the colour is too, every frame), plenty for glass this big.
    private let fineLead = LookBake(), coarseLead = LookBake(), fineShade = LookBake(), coarseShade = LookBake()

    /// Jewel glass: deep, rich colour with bright light coming through. Dull colours are given the colour their hue suggests
    /// (a beige wall becomes amber glass), while true greys and whites stay clear.
    private static let jewel = LookGrade { c in
        let x = LookTone.filmic(c, contrast: 1.25, black: 0.03, white: 0.99)
        var hsv = LookTone.hsv(x)
        hsv.y = min(1, max(hsv.y * 1.9, 0.62 * LookTone.smooth(0.04, 0.14, hsv.y)))
        hsv.z = min(1, hsv.z * 1.15 + 0.06)
        return LookTone.rgb(hsv: hsv)
    }

    /// Lead (a picture with its own transparency: dark, with a soft sheen along its upper edge) and the shade of each piece, for
    /// pieces of one size, at full size.
    private static func leading(radius: Double, width: Double, rect: CGRect) -> (lead: CIImage, shade: CIImage) {
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        // Each piece filled with a random colour, so every seam between pieces shows as an edge, however alike their glass is.
        let colourful = CIFilter.randomGenerator().outputImage.map { $0.cropped(to: half).settingAlphaOne(in: half) } ?? LookKit.noise(half, frame: 1)
        let pieces = colourful.clampedToExtent().applyingFilter("CICrystallize", parameters: [kCIInputRadiusKey: radius / 2, kCIInputCenterKey: CIVector(x: 0, y: 0)])
            .cropped(to: half)
        let seams = pieces.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 10.0]).cropped(to: half)
        let line = LookKit.levels(LookKit.grey(seams), gain: 4, bias: -0.2).clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: width / 2]).applyingGaussianBlur(sigma: 0.5).cropped(to: half)
        let mask = LookKit.levels(line, gain: 1.4, bias: -0.15)
        let sheen = mask.transformed(by: CGAffineTransform(translationX: -0.5, y: 0.5)).applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: mask])
        let metal = LookKit.screen(LookKit.levels(LookKit.multiply(sheen, over: mask), gain: 0.25), over: CIImage(color: CIColor(red: 0.07, green: 0.07, blue: 0.08)).cropped(to: half))
        let lead = metal.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: half), kCIInputMaskImageKey: mask])
        // Glass is never even: each piece a slightly different tint and thickness from its neighbours, and mottled within.
        let mottle = LookKit.noise(half, frame: 7, size: 4, mean: 0.94, spread: 0.2).clampedToExtent().applyingGaussianBlur(sigma: 1).cropped(to: half)
        let shade = LookKit.multiply(mottle, over: LookKit.levels(pieces, gain: 0.42, bias: 0.74))
        return (LookKit.enlarge(lead, to: rect, from: half), LookKit.enlarge(shade, to: rect, from: half))
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect, t = input.time
        let key = "\(rect)", context = input.services.context
        let fine = (lead: fineLead.image(key, rect: rect, context: context) { Self.leading(radius: Self.small, width: 0.9, rect: rect).lead },
                    shade: fineShade.image(key, rect: rect, context: context) { Self.leading(radius: Self.small, width: 0.9, rect: rect).shade })
        let coarse = (lead: coarseLead.image(key, rect: rect, context: context) { Self.leading(radius: Self.large, width: 2.4, rect: rect).lead },
                      shade: coarseShade.image(key, rect: rect, context: context) { Self.leading(radius: Self.large, width: 2.4, rect: rect).shade })
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        let glass = Self.jewel.apply(LookKit.shrink(input.composed, rect: rect, by: 0.5)).clampedToExtent()
        func pieces(_ radius: Double) -> CIImage {
            LookKit.enlarge(glass.applyingFilter("CICrystallize", parameters: [kCIInputRadiusKey: radius / 2, kCIInputCenterKey: CIVector(x: 0, y: 0)]).cropped(to: half),
                            to: rect, from: half)
        }
        var colour = LookKit.multiply(coarse.shade, over: pieces(Self.large))
        var leads = coarse.lead
        if let matte = input.matte {
            colour = LookKit.blend(LookKit.multiply(fine.shade, over: pieces(Self.small)), over: colour, mask: matte)
            // As in a real window, the figure is cut finer than the background, in lighter lead.
            leads = LookKit.blend(fine.lead.fading(0.8), over: coarse.lead, mask: matte)
            // The glass painter draws your features on in dark paint: eyes, brows, the line of the mouth.
            let tone = LookKit.perceptual(LookKit.grey(LookKit.shrink(input.composed, rect: rect, by: 0.5))).clampedToExtent()
            let near = tone.applyingGaussianBlur(sigma: 1.0), wide = tone.applyingGaussianBlur(sigma: 2.6)
            let paint = LookKit.levels(near.applyingFilter("CISubtractBlendMode", parameters: [kCIInputBackgroundImageKey: wide]).cropped(to: half), gain: 16, bias: -0.22)
            let painted = LookKit.multiply(LookKit.enlarge(paint, to: rect, from: half), over: matte)
            colour = LookKit.blend(CIImage(color: CIColor(red: 0.12, green: 0.08, blue: 0.06)).cropped(to: rect), over: colour, mask: LookKit.levels(painted, gain: 0.7))
        }
        // Light from behind, a slow sunbeam sweeping across, and the glass glowing with it.
        let sweep = CIFilter.linearGradient()
        let place = (t / 18).truncatingRemainder(dividingBy: 1) * 1.6 - 0.3
        sweep.point0 = CGPoint(x: rect.minX + rect.width * place, y: rect.maxY)
        sweep.point1 = CGPoint(x: rect.minX + rect.width * (place + 0.35), y: rect.minY)
        sweep.color0 = CIColor(red: 0.16, green: 0.14, blue: 0.1)
        sweep.color1 = CIColor(red: 0, green: 0, blue: 0)
        let lit = LookKit.screen((sweep.outputImage ?? CIImage(color: .black)).cropped(to: rect), over: colour)
        let glow = LookKit.glow(lit, rect: rect, threshold: 0.3, sigma: 7)
        let glowing = LookKit.screen(LookKit.levels(glow, gain: 0.6), over: lit)
        return leads.composited(over: glowing).cropped(to: rect)
    }
}
