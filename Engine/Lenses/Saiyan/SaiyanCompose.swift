import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// How the lens puts the pieces together, so that the pieces, the tests and the finished lens all compose them the same way.
///
/// The order, back to front: the scenery, the aura (`SaiyanAura.backLayer`), the long hair behind the shoulders, any afterimages of
/// the person, the person, the light over the body (`SaiyanAura.frontLight`), the hair and face, then the room is darkened if a move asks
/// for it, the moves' washes, solid bodies and light are added, and last the whole-picture effects (flash, shake).
enum SaiyanCompose {
    // MARK: Moves

    /// Adds the moves' light over `base`: first the room is darkened when a move asks for it (the Spirit Bomb darkening the sky), so the
    /// light is added to the darkened picture and keeps its full brightness; then the big soft washes (made on the graphics chip), the opaque
    /// bodies, and the additive layer with a bloom round everything bright in it. Uses two overlay layers.
    static func moves(_ set: SaiyanMoveSet, over base: CIImage, input: LensInput) -> CIImage {
        let darkness = set.screenEffect.darken
        guard set.hasLight || darkness > 0.002 else { return base }
        var lit = darkness > 0.002 ? dimmed(base, by: darkness) : base
        for w in set.washes() where w.alpha > 0.004 && w.radius > 1 {
            lit = WorldKit.adding(WorldKit.wash(center: w.center, radius: w.radius, red: w.colour.x, green: w.colour.y, blue: w.colour.z,
                                                alpha: w.alpha, in: input.rect), to: lit)
        }
        if let solid = input.services.overlay({ ctx in set.drawSolids(in: ctx) }) { lit = solid.composited(over: lit) }
        if let layer = input.services.overlay({ ctx in set.drawLight(in: ctx) }) {
            lit = HandFXLight.add(layer, to: lit, rect: input.rect, bloom: 0.7)
        }
        return lit.cropped(to: input.rect)
    }

    // MARK: The person

    /// Lays the person over `layer`, with the afterimages of an `echo` behind them and their opacity turned down when a move makes them
    /// vanish. With no cutout there is nothing to separate, so the picture as it is.
    static func person(_ input: LensInput, over layer: CIImage, effect: SaiyanScreenEffect) -> CIImage {
        guard let matte = input.matte else { return input.composed }
        var behind = layer
        if !effect.echoes.isEmpty {
            // The person alone, on nothing: what each afterimage is a copy of.
            let blend = CIFilter.blendWithMask()
            blend.inputImage = input.composed
            blend.backgroundImage = input.clear
            blend.maskImage = matte
            if let cutout = blend.outputImage {
                // Farthest first, so the nearest copy sits on top.
                for echo in effect.echoes.sorted(by: { hypot($0.offset.dx, $0.offset.dy) > hypot($1.offset.dx, $1.offset.dy) }) where echo.alpha > 0.004 {
                    behind = copy(of: cutout, echo, rect: input.rect).composited(over: behind)
                }
            }
        }
        guard effect.personOpacity < 0.998 else { return input.placingPerson(over: behind) }
        let k = CGFloat(max(0, effect.personOpacity))
        let softened = matte.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
        ])
        let blend = CIFilter.blendWithMask()
        blend.inputImage = input.composed
        blend.backgroundImage = behind
        blend.maskImage = softened
        return (blend.outputImage ?? behind).cropped(to: input.rect)
    }

    /// One afterimage: the cut-out person slid, scaled about the middle of the bottom edge, tinted and faded.
    private static func copy(of cutout: CIImage, _ echo: SaiyanEcho, rect: CGRect) -> CIImage {
        let anchor = CGPoint(x: rect.midX, y: rect.minY)
        let move = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(scaleX: CGFloat(echo.scale), y: CGFloat(echo.scale)))
            .concatenating(CGAffineTransform(translationX: anchor.x + echo.offset.dx, y: anchor.y + echo.offset.dy))
        let a = CGFloat(min(1, max(0, echo.tintAmount))), keep = 1 - a
        let tinted = cutout.transformed(by: move).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: keep, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: keep, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: keep, w: 0),
            "inputBiasVector": CIVector(x: CGFloat(echo.tint.x) * a, y: CGFloat(echo.tint.y) * a, z: CGFloat(echo.tint.z) * a, w: 0),
        ])
        return tinted.fading(echo.alpha)
    }

    // MARK: The whole picture

    /// The picture with the room and the person darkened (a slightly cool dark), 0 leaves it, 1 takes three quarters of the light away.
    static func dimmed(_ picture: CIImage, by amount: Double) -> CIImage {
        let k = CGFloat(1 - 0.74 * min(1, max(0, amount)))
        return picture.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: k * 1.04, w: 0),
        ])
    }

    /// Whites out and shakes a finished picture. (Darkening is done in `moves`, before the light is added, so the light is not dimmed too.)
    static func screen(_ effect: SaiyanScreenEffect, over picture: CIImage, rect: CGRect, time: Double) -> CIImage {
        var out = picture
        if effect.flash > 0.002 {
            let f: Double = min(1, effect.flash)
            let t = effect.flashTint
            let colour = CIColor(red: CGFloat(t.x * f), green: CGFloat(t.y * f), blue: CGFloat(t.z * f), alpha: CGFloat(f))
            out = WorldKit.adding(CIImage(color: colour).cropped(to: rect), to: out)
        }
        if effect.shake > 0.002 {
            let amount: Double = 14 * min(1, effect.shake) * Double(rect.width / 1280)
            let sx: Double = sin(time * 83) * 0.6 + sin(time * 131 + 1.3) * 0.4
            let sy: Double = sin(time * 97 + 0.7) * 0.6 + sin(time * 59 + 2.1) * 0.4
            let shift = CGAffineTransform(translationX: CGFloat(amount * sx), y: CGFloat(amount * sy))
            out = out.clampedToExtent().transformed(by: shift).cropped(to: rect)
        }
        return out.cropped(to: rect)
    }
}
