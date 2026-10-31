import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// The pairs of inks the duotone prints with and how they change over time. Pure, so it can be tested.
enum LookDuotonePlan {
    /// A dark ink and a light ink. Chosen by hand, because most pairs of colours picked at random look muddy.
    static let pairs: [(dark: LookColour, light: LookColour)] = [
        ((0.10, 0.03, 0.36), (1.00, 0.55, 0.52)),     // indigo and coral
        ((0.03, 0.07, 0.30), (1.00, 0.80, 0.62)),     // navy and peach
        ((0.36, 0.02, 0.16), (1.00, 0.84, 0.35)),     // wine and gold
        ((0.04, 0.02, 0.28), (1.00, 0.48, 0.78)),     // midnight and hot pink
        ((0.00, 0.17, 0.21), (1.00, 0.87, 0.64)),     // deep teal and apricot cream
        ((0.25, 0.00, 0.40), (1.00, 0.66, 0.24)),     // grape and tangerine
    ]

    /// Seconds each pair is on screen before melting into the next.
    static let hold = 9.0

    /// The inks at a moment: one pair of the list, easing smoothly into the next.
    static func inks(at time: Double) -> (dark: LookColour, light: LookColour) {
        let place = time / hold
        let index = Int(place.rounded(.down))
        let fraction = LookKit.smoothstep(0.6, 1, place - Double(index))
        let n = pairs.count
        let a = pairs[(index % n + n) % n], b = pairs[((index + 1) % n + n) % n]
        return (blend(a.dark, b.dark, fraction), blend(a.light, b.light, fraction))
    }

    /// The colour between a pair of inks: a deeper, richer shade of the light ink, leaning a quarter of the way to the dark one.
    /// Most of a face is middle tones, and a plain mix of two inks goes grey or green there; a deep version of the light ink keeps
    /// skin warm and alive.
    static func middle(of inks: (dark: LookColour, light: LookColour)) -> LookColour {
        var h: CGFloat = 0, sat: CGFloat = 0, v: CGFloat = 0, alpha: CGFloat = 0
        NSColor(srgbRed: CGFloat(inks.light.r), green: CGFloat(inks.light.g), blue: CGFloat(inks.light.b), alpha: 1).getHue(&h, saturation: &sat, brightness: &v, alpha: &alpha)
        let deep = Palette.rgb(hue: Double(h), saturation: min(1, Double(sat) * 1.3 + 0.2), brightness: Double(v) * 0.64)
        return LookKit.mix(deep, inks.dark, 0.25)
    }

    /// Between two colours by the shortest way round the colour wheel, so the colours stay vivid on the way. Mixing reds and
    /// greens directly passes through mud.
    static func blend(_ a: LookColour, _ b: LookColour, _ f: Double) -> LookColour {
        func hsb(_ c: LookColour) -> (h: Double, s: Double, b: Double) {
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, alpha: CGFloat = 0
            NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &alpha)
            return (Double(h), Double(s), Double(v))
        }
        let x = hsb(a), y = hsb(b)
        var turn = y.h - x.h
        if turn > 0.5 { turn -= 1 } else if turn < -0.5 { turn += 1 }
        var hue = x.h + turn * f
        hue -= hue.rounded(.down)
        return Palette.rgb(hue: hue, saturation: x.s + (y.s - x.s) * f, brightness: x.b + (y.b - x.b) * f)
    }
}

/// A two-ink poster: the picture printed in just a dark colour and a light one, which slowly change. When the cutout is
/// available, the room is printed a step darker than you, so you stand out from it.
final class LookDuotoneLens: Lens {
    let needs: LensNeeds = [.matte]

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        // Brightness as the eye sees it, with a firm curve so the two inks do most of the work.
        let tone = LookKit.perceptual(LookKit.grey(input.composed.clampedToExtent().applyingGaussianBlur(sigma: 1.0).cropped(to: rect)))
        let firm = tone.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.55, kCIInputBrightnessKey: 0.0])

        // You and the room are printed in the same two inks, but the room sits a step darker so you stand out from it.
        let inks = LookDuotonePlan.inks(at: input.time)
        // You are lifted a little, so a dark face still prints in the lighter ink rather than sinking into the dark one.
        let you = LookDuotoneLens.printed(LookKit.levels(firm.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.82]), gain: 1, bias: 0.03), inks: inks, rect: rect)
        guard let matte = input.matte else { return you }
        let room = LookDuotoneLens.printed(LookKit.levels(firm, gain: 0.8, bias: 0.0), inks: inks, rect: rect)
        // Printed on paper: a fine tooth that never moves.
        return LookKit.grained(LookKit.blend(you, over: room, mask: matte), frame: 5, rect: rect, amount: 0.1, size: 1.2).cropped(to: rect)
    }

    /// Brightness (on the eye's scale) printed in two inks, with a vivid colour between them: a plain mix of two inks goes grey
    /// in the middle, and most of a face is middle.
    private static func printed(_ tone: CIImage, inks: (dark: LookColour, light: LookColour), rect: CGRect) -> CIImage {
        let middle = LookDuotonePlan.middle(of: inks)
        guard let strip = LookKit.ramp([(0, inks.dark), (0.5, middle), (1, inks.light)]) else { return tone }
        return LookKit.colourise(tone, with: CIImage(cgImage: strip)).cropped(to: rect)
    }
}
