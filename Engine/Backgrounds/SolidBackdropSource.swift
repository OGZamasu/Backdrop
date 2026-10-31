import CoreImage
import CoreImage.CIFilterBuiltins

/// A studio colour. With `lit` on it is a real backdrop rather than a swatch: a background light pools softly behind the
/// head, the key light from the upper left grades it gently across, the corners fall away, and the surface has the faint
/// mottling of painted canvas (dark colours) or plaster (light ones), with a fine grain. With `lit` off the colour is
/// exactly the same everywhere, for chroma keying. Painted once; every frame after is free.
final class SolidBackdropSource: BackgroundSource {
    private let hex: String
    private let lit: Bool
    private var cached: CIImage?

    init(hex: String, lit: Bool) {
        self.hex = hex
        self.lit = lit
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        if cached == nil { cached = lit ? BackdropBake.flatten(Self.wall(hex: hex)) : Self.flat(hex: hex) }
        return cached
    }

    private static func colour(_ hex: String) -> BackdropRGB {
        let (r, g, b) = BackdropPaint.rgb(hex: hex) ?? (0.5, 0.5, 0.5)
        return BackdropRGB(r, g, b)
    }

    private static func flat(hex: String) -> CIImage {
        let c = colour(hex)
        let tone = CIColor(red: c.r, green: c.g, blue: c.b, colorSpace: BackdropCanvas.space) ?? CIColor.black
        return CIImage(color: tone).cropped(to: BackdropPainter.frame)
    }

    /// The painted wall for any colour, so a colour the user picks gets the same treatment as the built-in ones.
    static func wall(hex: String) -> CIImage? {
        let base = colour(hex)
        let dark = base.luminance < 0.25
        let picture = BackdropPainter.paint(width: 640, height: 360) { ctx in
            ctx.setFillColor(base.cg)
            ctx.fill(BackdropPainter.frame)
            // The key light, from the upper left: a broad, faint lift there and a faint fall toward the lower right.
            BackdropPainter.glow(ctx, at: CGPoint(x: 120, y: 760), radius: 1150, color: BackdropRGB(1, 0.98, 0.94), alpha: dark ? 0.10 : 0.07)
            BackdropPainter.glow(ctx, at: CGPoint(x: 1300, y: -120), radius: 900, color: BackdropRGB(0, 0, 0), alpha: dark ? 0.22 : 0.10)
            // The background light behind the head: stronger on a dark backdrop, where it is what separates you from it.
            let pool = base.mixed(BackdropRGB(1, 1, 1), dark ? 0.32 : 0.16)
            BackdropPainter.glow(ctx, at: CGPoint(x: 660, y: 420), radius: 600, color: pool, alpha: dark ? 0.55 : 0.6, squash: 0.78)
        }
        guard let painted = picture else { return nil }
        // Canvas for dark colours (bolder blotches), plaster for light ones (barely there).
        let blotchy = BackdropPainter.mottle(painted, amount: dark ? 0.075 : 0.022, scale: 2.4, channel: 0)
        let fine = BackdropPainter.mottle(blotchy, amount: dark ? 0.035 : 0.012, scale: 1.3, channel: 1, offset: CGPoint(x: 91, y: 37))
        return BackdropFinish.finish(BackdropFinish.vignette(fine, strength: dark ? 0.30 : 0.16), grain: dark ? 1.0 : 0.6)
    }
}
