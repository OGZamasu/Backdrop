import CoreGraphics
import Foundation
import simd

/// The eyes and eyebrows of every form of the Dragon Ball lens: irises recoloured under the real eyelids, bold angular brows in the hair's
/// colour, and for Super Saiyan 3 a bare, heavy brow ridge. Base draws nothing. Everything here is in face units.
///
/// The eyes are drawn directly every frame (they blink and glow). The brows and the skin that covers the real ones are kept paintings
/// that go into the hair's picture (`SaiyanPiece`), so they cost nothing extra, and the hair's colour wash crosses them over with it.
final class SaiyanEyes {
    /// How much of each part shows on the latest frame, 0...1. Read by the tests.
    private(set) var browShowing = 0.0
    private(set) var ridgeShowing = 0.0
    private(set) var irisShowing = 0.0

    func reset() { browShowing = 0; ridgeShowing = 0; irisShowing = 0 }

    /// How far a form's look is in, from one form to the next over the first part of a change.
    private static func blend(_ s: SaiyanBodyState) -> Double {
        guard s.previousForm != s.form, s.transition < 0.999 else { return 1 }
        return HeadwearEase.smoothstep(s.transition / 0.6)
    }

    private static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> { a + (b - a) * t }

    /// Works out how much of the brows, the bare ridge and the irises show for this state.
    func update(_ s: SaiyanBodyState) {
        let k = Self.blend(s)
        let from = s.previousForm, to = s.form
        func amount(_ yes: (SaiyanForm) -> Bool) -> Double { SaiyanFaceKit.lerp(yes(from) ? 1 : 0, yes(to) ? 1 : 0, k) }
        browShowing = amount { !$0.isBase && $0.hasBrows }
        ridgeShowing = amount { !$0.hasBrows }
        irisShowing = amount { $0.eyes != .natural }
    }

    /// A colour key for a skin tone, in steps fine enough not to show and coarse enough not to repaint for camera noise.
    private static func skinKey(_ skin: SIMD3<Double>) -> String {
        "\(Int((skin.x * 40).rounded()))-\(Int((skin.y * 40).rounded()))-\(Int((skin.z * 40).rounded()))"
    }

    /// The brows and the skin over the real brows (or Super Saiyan 3's bare ridge), as pieces for the hair's picture.
    func pieces(_ f: HeadwearFrame, _ s: SaiyanBodyState, skin: SIMD3<Double>) -> [SaiyanPiece] {
        update(s)
        var out: [SaiyanPiece] = []
        let brow = f.local(f.face.browCenter).y
        let skinColour = SaiyanFaceKit.colour(skin), key = Self.skinKey(skin)
        if browShowing > 0.004 {
            // Painted in the colours of whichever form has brows; while two do, the hair's wash crosses them over.
            let form = !s.form.isBase && s.form.hasBrows ? s.form : s.previousForm
            // The real brow's lift and the scowl while powering up, in small steps.
            let raise = (HeadwearEase.clamp01(f.face.browRaise) * 8).rounded() / 8
            let furrow = (HeadwearEase.clamp01(s.charge) * 4).rounded() / 4
            for side in [-1.0, 1.0] {
                let box = CGRect(x: side > 0 ? 0.04 : -1.04, y: -0.22, width: 1.0, height: 0.42)
                out.append(SaiyanPiece(name: "saiyan-brow-\(Int(side))-\(Int(raise * 8))-\(Int(furrow * 4))-\(form)", at: hwp(0, brow), window: box,
                                       alpha: browShowing, layer: .underHair) { pen in
                    Self.paintBrow(pen, side: side, raise: raise, furrow: furrow, palette: form.palette)
                })
            }
        }
        if ridgeShowing > 0.004 {
            out.append(SaiyanPiece(name: "saiyan-ridge-\(key)", at: hwp(0, brow), window: CGRect(x: -1.06, y: -0.22, width: 2.12, height: 0.42),
                                   alpha: ridgeShowing, layer: .skin) { pen in Self.paintRidge(pen, skin: skinColour) })
        }
        if browShowing > 0.004 {
            for side in [-1.0, 1.0] {
                let box = CGRect(x: side > 0 ? 0.0 : -1.06, y: -0.2, width: 1.06, height: 0.34)
                // Its strength is painted in, so when settled it is copied whole (anything copied part-faded is several times slower).
                out.append(SaiyanPiece(name: "saiyan-browcover-\(Int(side))-\(key)", at: hwp(0, brow), window: box, alpha: browShowing,
                                       layer: .skin) { pen in
                    SaiyanFaceKit.softOval(pen.ctx, at: hwp(side * 0.53, -0.025), rx: 0.47, ry: 0.135, skinColour.faded(0.92))
                })
            }
        }
        return out
    }

    /// Draws the irises, in face units. `appear` fades them in when the face arrives.
    func drawEyes(_ pen: HeadwearPen, _ f: HeadwearFrame, _ s: SaiyanBodyState, appear: Double) {
        update(s)
        let alpha = irisShowing * appear
        guard alpha > 0.004 else { return }
        let k = Self.blend(s)
        let from = s.previousForm, to = s.form
        let style = to.eyes != .natural ? to.eyes : from.eyes
        let colour = to.eyes == .natural ? from.palette.eye : (from.eyes == .natural ? to.palette.eye : Self.mix(from.palette.eye, to.palette.eye, k))
        let open = HeadwearEase.clamp01(1 - 1.15 * f.face.blink)
        for side in [-1.0, 1.0] {
            drawEye(pen, at: hwp(side * 0.5, 0), side: side, style: style, colour: colour, open: open, charge: HeadwearEase.clamp01(s.charge),
                    flash: min(1, s.flash), clock: f.clock, alpha: alpha)
        }
    }

    // MARK: Brows

    /// One brow, around the real brow line at y = 0: thick and low at the inner end, angled up to a sharp outer point, lifted with the real
    /// brow and drawn down hard while powering up.
    static func paintBrow(_ pen: HeadwearPen, side: Double, raise: Double, furrow: Double, palette: SaiyanPalette) {
        let lift = 0.06 * raise
        let inner = 0.05 * raise - 0.035 * furrow
        func p(_ x: Double, _ y: Double, _ innerShare: Double) -> CGPoint { hwp(side * x, y + lift + (inner - lift) * innerShare) }
        let top = [p(0.12, 0.03, 1), p(0.34, 0.096, 0.4), p(0.6, 0.118, 0), p(0.84, 0.066, 0)]
        let tip = p(0.97, 0.016, 0)
        let bottom = [p(0.84, 0.014, 0), p(0.6, -0.016, 0), p(0.36, -0.07, 0.4), p(0.16, -0.15, 1)]
        let path = CGMutablePath()
        path.move(to: top[0])
        SaiyanFaceKit.addCurve(through: top, to: path)
        path.addLine(to: tip)
        path.addLine(to: bottom[0])
        SaiyanFaceKit.addCurve(through: bottom, to: path)
        path.closeSubpath()
        let c = { SaiyanFaceKit.colour($0) }
        let base = c(palette.hairBase), shade = c(palette.hairShade), light = c(palette.hairHighlight)
        pen.paint(path, [base.mixed(with: light, 0.45), base, base.mixed(with: shade, 0.5), shade.darker(0.15)])
        // A hard highlight along the top edge, the way the hair is lit.
        let sheen = CGMutablePath()
        let upper = [p(0.2, 0.044, 0.85), p(0.38, 0.086, 0.3), p(0.62, 0.104, 0)]
        sheen.move(to: upper[0])
        SaiyanFaceKit.addCurve(through: upper, to: sheen)
        SaiyanFaceKit.addCurve(through: [p(0.62, 0.104, 0), p(0.42, 0.052, 0.3), p(0.2, 0.044, 0.85)], to: sheen)
        sheen.closeSubpath()
        pen.fill(sheen, light.faded(0.8))
        pen.stroke(path, shade.darker(0.55).faded(0.95), width: 0.02)
    }

    /// Super Saiyan 3 has no eyebrows: around the real brow line at y = 0, the real brows are covered with skin and the brow ridge bulges,
    /// shadowed under and lit on top, creased between the eyes.
    static func paintRidge(_ pen: HeadwearPen, skin: HeadwearColor) {
        let ctx = pen.ctx
        for side in [-1.0, 1.0] {
            SaiyanFaceKit.softOval(ctx, at: hwp(side * 0.52, -0.02), rx: 0.47, ry: 0.14, skin)
        }
        for side in [-1.0, 1.0] {
            SaiyanFaceKit.softOval(ctx, at: hwp(side * 0.52, -0.075), rx: 0.37, ry: 0.048, turn: side * 0.14, skin.darker(0.34).faded(0.5))
            SaiyanFaceKit.softOval(ctx, at: hwp(side * 0.56, -0.035), rx: 0.3, ry: 0.02, turn: side * 0.14, skin.darker(0.45).faded(0.32))
            SaiyanFaceKit.softOval(ctx, at: hwp(side * 0.48, 0.045), rx: 0.32, ry: 0.05, turn: side * 0.1, skin.lighter(0.22).faded(0.36))
            SaiyanFaceKit.softOval(ctx, at: hwp(side * 0.075, 0.02), rx: 0.022, ry: 0.1, turn: -side * 0.15, skin.darker(0.3).faded(0.42))
            SaiyanFaceKit.softOval(ctx, at: hwp(side * 0.12, 0.03), rx: 0.024, ry: 0.09, turn: -side * 0.15, skin.lighter(0.16).faded(0.26))
        }
    }

    // MARK: Eyes

    /// One iris, recoloured over the real one and cut to the eye's opening, so the lid closes over it in a blink.
    private func drawEye(_ pen: HeadwearPen, at c: CGPoint, side: Double, style: SaiyanForm.Eyes, colour: SIMD3<Double>, open: Double,
                         charge: Double, flash: Double, clock: Double, alpha: Double) {
        let eye = SaiyanFaceKit.colour(colour, alpha)
        let breathe = 0.5 + 0.5 * sin(clock * 2.2 + side)
        // The glow round the eye: faint for Super Saiyan, more for the calm forms, silver for Ultra Instinct; brighter while powering up.
        let glowBase: Double
        switch style {
        case .teal: glowBase = 0.1
        case .calm: glowBase = 0.22
        case .silver: glowBase = 0.32
        case .natural: glowBase = 0
        }
        let glow = (glowBase * (0.85 + 0.15 * breathe) + 0.3 * charge + 0.5 * flash) * alpha * (0.3 + 0.7 * open)
        if glow > 0.004 {
            pen.glow(at: c, radius: 0.3, SaiyanFaceKit.colour(colour).lighter(0.3).faded(glow), additive: true)
        }
        guard open > 0.04 else { return }
        let ow = 0.2, oh = 0.094 * pow(open, 0.85)
        let opening = HeadwearShape.smooth([hwp(c.x - side * ow, c.y + 0.004), hwp(c.x - side * ow * 0.55, c.y + oh * 0.93), hwp(c.x + side * 0.02, c.y + oh),
                                            hwp(c.x + side * ow * 0.6, c.y + oh * 0.8), hwp(c.x + side * ow, c.y + 0.012), hwp(c.x + side * ow * 0.55, c.y - oh * 0.8),
                                            hwp(c.x, c.y - oh), hwp(c.x - side * ow * 0.55, c.y - oh * 0.76)])
        let r = style == .silver ? 0.1 : 0.104
        let disc = HeadwearShape.ellipse(c, rx: r, ry: r)
        let inside = HeadwearShape.ellipse(c, rx: r - 0.014, ry: r - 0.014)
        pen.clipped(to: opening) {
            // The dark ring at the iris's edge, then the iris lit from below, as painted eyes are.
            let ring = style == .silver ? HeadwearColor(hex: 0x4E5872, alpha: alpha) : eye.darker(0.62)
            pen.fill(disc, ring.faded(0.92 * alpha))
            let colours: [HeadwearColor]
            switch style {
            case .teal: colours = [eye.lighter(0.5), eye.lighter(0.12), eye, eye.darker(0.35)]
            case .calm: colours = [eye.lighter(0.3), eye.lighter(0.06), eye.darker(0.18)]
            case .silver: colours = [HeadwearColor(1, 1, 1, alpha), eye, eye.darker(0.18), HeadwearColor(hex: 0x8C98B6, alpha: alpha)]
            case .natural: colours = [eye]
            }
            pen.paintRound(inside, center: hwp(c.x, c.y - 0.04), radius: r * 1.1, colours)
            if style == .teal {
                pen.fill(HeadwearShape.ellipse(c, rx: 0.034, ry: 0.036), eye.darker(0.78).faded(0.92 * alpha))
            }
            // The upper lid's shadow across the top of the iris.
            pen.clipped(to: disc) {
                if let g = HeadwearPen.gradient([HeadwearColor(0, 0, 0, 0.5 * alpha), HeadwearColor(0, 0, 0, 0)]) {
                    pen.ctx.drawLinearGradient(g, start: hwp(c.x, c.y + oh), end: hwp(c.x, c.y + oh * 0.1), options: [.drawsBeforeStartLocation])
                }
                if flash > 0.01 { pen.fill(disc, HeadwearColor(1, 1, 1, 0.6 * flash * alpha)) }
            }
            // The catch light: hard and white for Super Saiyan, softer for the calm forms; it breathes a little.
            let h = 1 + 0.08 * sin(clock * 2.9 + side * 1.3)
            let (size, strength): (Double, Double) = style == .calm ? (0.02, 0.6) : style == .silver ? (0.019, 0.95) : (0.026, 0.97)
            pen.fill(HeadwearShape.ellipse(hwp(c.x - 0.032, c.y + 0.03), rx: size * h, ry: size * 0.82 * h, turn: 0.4), HeadwearColor(1, 1, 1, strength * alpha))
            pen.fill(HeadwearShape.ellipse(hwp(c.x + 0.036, c.y - 0.033), rx: 0.01, ry: 0.01), HeadwearColor(1, 1, 1, 0.7 * strength * alpha))
        }
    }
}
