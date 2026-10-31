import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Where the late sun sits and where its flare falls. Pure, so it can be tested.
enum LookGoldenHourPlan {
    /// The sun, just off the upper left corner, drifting a little so the flare is never quite still.
    static func sun(at time: Double, size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (-0.04 + 0.025 * sin(time * 0.21)), y: size.height * (0.97 + 0.02 * sin(time * 0.17 + 1)))
    }

    struct Ghost {
        var centre: CGPoint
        var radius: Double
        var colour: LookColour
        var alpha: Double
    }

    /// The flare: soft rings and discs strung along the line from the sun through the middle of the picture.
    static func ghosts(sun: CGPoint, size: CGSize) -> [Ghost] {
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        let steps: [(Double, Double, LookColour, Double)] = [
            (0.55, 26, (1.0, 0.85, 0.55), 0.16), (0.85, 60, (0.75, 1.0, 0.75), 0.07), (1.25, 18, (1.0, 0.7, 0.9), 0.14),
            (1.5, 95, (0.7, 0.85, 1.0), 0.05), (1.8, 38, (1.0, 0.78, 0.5), 0.1),
        ]
        return steps.map { along, radius, colour, alpha in
            Ghost(centre: CGPoint(x: sun.x + (mid.x - sun.x) * along, y: sun.y + (mid.y - sun.y) * along), radius: radius * size.height / 720,
                  colour: colour, alpha: alpha)
        }
    }
}

/// The last hour of sun: everything warmed to gold with soft violet shadows, a low sun glowing in from the upper left, light
/// catching the edge of your hair and shoulders, and a gentle flare across the lens.
final class LookGoldenHourLens: Lens {
    let needs: LensNeeds = [.matte]

    private let flares = LookDisplayCache()

    /// Gold in the lights, amber in the middle, a soft violet in the shadows, and a little more colour.
    private static let warm = LookGrade { c in
        var x = LookTone.filmic(c, contrast: 1.12, black: 0.03, white: 0.985, pivot: 0.45)
        let l = LookTone.luma(x)
        x += SIMD3<Float>(0.06, 0.022, -0.075) * LookTone.smooth(0.35, 0.95, l)
        x += SIMD3<Float>(0.03, 0.0, -0.035) * (1 - abs(l - 0.5) * 2)
        x += SIMD3<Float>(0.018, -0.008, 0.03) * (1 - LookTone.smooth(0.05, 0.4, l))
        return LookTone.saturate(x, 1.12)
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect, t = input.time
        let sun = LookGoldenHourPlan.sun(at: t, size: rect.size)
        let graded = Self.warm.apply(input.composed)

        // The sun's warm wash, strongest near it and fading across the frame.
        let wash = CIFilter.radialGradient()
        wash.center = CGPoint(x: rect.minX + sun.x, y: rect.minY + sun.y)
        wash.radius0 = 0
        wash.radius1 = Float(rect.width * 0.95)
        wash.color0 = CIColor(red: 0.95, green: 0.62, blue: 0.28)
        wash.color1 = CIColor(red: 0, green: 0, blue: 0)
        let core = CIFilter.radialGradient()
        core.center = wash.center
        core.radius0 = 0
        core.radius1 = Float(rect.height * 0.32)
        core.color0 = CIColor(red: 1, green: 0.93, blue: 0.75)
        core.color1 = CIColor(red: 0, green: 0, blue: 0)
        var picture = graded
        if let glow = wash.outputImage?.cropped(to: rect), let disc = core.outputImage?.cropped(to: rect) {
            picture = LookKit.screen(LookKit.levels(disc, gain: 0.95), over: LookKit.screen(LookKit.levels(glow, gain: 0.55), over: picture))
        }

        // Rim light: the sun catches the edges of you that face it, inside your outline.
        if let matte = input.matte {
            let half = LookKit.size(of: rect, scaledBy: 0.5)
            let solid = LookKit.levels(LookKit.shrink(matte, rect: rect, by: 0.5), gain: 6, bias: -2.5).clampedToExtent()
            // The light side of you: your outline shifted away from the sun and taken from itself leaves a thin crescent on the
            // edges that face it.
            let away = solid.transformed(by: CGAffineTransform(translationX: 3.5, y: -3.5))
            let crescent = solid.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: away])
            let band = LookKit.multiply(solid, over: LookKit.levels(crescent.applyingGaussianBlur(sigma: 2.2).cropped(to: half), gain: 1.5))
            let facing = CIFilter.linearGradient()
            facing.point0 = CGPoint(x: sun.x / 2, y: sun.y / 2)
            facing.point1 = CGPoint(x: half.width * 0.6, y: half.height * 0.25)
            facing.color0 = CIColor(red: 1, green: 1, blue: 1)
            facing.color1 = CIColor(red: 0.15, green: 0.15, blue: 0.15)
            let lit = LookKit.multiply((facing.outputImage ?? CIImage(color: .white)).cropped(to: half), over: band)
            let rim = LookKit.tint(LookKit.enlarge(lit, to: rect, from: half), by: (1.0, 0.78, 0.45))
            picture = LookKit.screen(rim, over: picture)
        }

        // The flare, redrawn only when the sun has drifted a couple of pixels.
        let ghosts = LookGoldenHourPlan.ghosts(sun: sun, size: rect.size)
        let key = String(format: "%.0f %.0f", (sun.x / 2).rounded(), (sun.y / 2).rounded())
        if let flare = flares.layer(key, size: rect.size, draw: { ctx in
            for ghost in ghosts {
                ctx.glow(center: CGPoint(x: rect.minX + ghost.centre.x, y: rect.minY + ghost.centre.y), radius: ghost.radius,
                         red: ghost.colour.r, green: ghost.colour.g, blue: ghost.colour.b, alpha: ghost.alpha)
                ctx.setStrokeColor(CGColor(colorSpace: LookKit.space, components: [ghost.colour.r, ghost.colour.g, ghost.colour.b, ghost.alpha * 0.6])!)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: CGRect(x: rect.minX + ghost.centre.x - ghost.radius * 0.8, y: rect.minY + ghost.centre.y - ghost.radius * 0.8,
                                             width: ghost.radius * 1.6, height: ghost.radius * 1.6))
            }
        }) {
            picture = LookKit.screen(flare, over: picture)
        }
        let soft = LookKit.multiply(LookKit.ovalVignette(rect, reach: 0.5, edge: LookKit.lin(0.7)), over: picture)
        return LookKit.filmGrain(soft, frame: Int(t * 24), rect: rect, amount: 0.07, size: 1.1).cropped(to: rect)
    }
}
