import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Become an alien: a big forehead and a small chin, green skin, glossy black eyes and wiggling antennae.
/// Raising your eyebrows perks the antennae up; blinking shuts the big eyes.
final class ExprAlienLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var visibleFor = 0.0
    private var perk = 0.0
    private var bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)

    /// How far the antennae stand up, 0 relaxed to 1 on alert.
    var antennaePerk: Double { perk }

    func restart() { visibleFor = 0; perk = 0 }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Take me to your leader")
        guard let face = input.face else { visibleFor = 0; perk = 0; return input.composed }
        let dt = input.dt
        visibleFor += dt
        perk = exprEase(perk, toward: face.browRaise, dt: dt, tau: 0.12)
        let morph = exprSmoothstep(0, 0.4, visibleFor)             // the change comes over you rather than snapping on

        var picture = warped(input, face: face, amount: morph)
        picture = greened(picture, input: input, face: face, amount: morph)

        bounds = input.rect
        guard let layer = input.services.exprOverlay({ ctx in draw(ctx, face: face, time: input.time, amount: morph) }) else { return picture }
        return layer.composited(over: picture).cropped(to: input.rect)
    }

    // MARK: The warp

    /// A swollen forehead over a pinched chin.
    private func warped(_ input: LensInput, face: FaceState, amount: Double) -> CIImage {
        let io = face.interocular
        let forehead = face.exprPoint(0, 0.95), chin = face.exprPoint(0, -1.45)
        let foreheadReach = io * 1.5, chinReach = io * 1.0
        let region = ExprWarp.union(of: [(forehead, foreheadReach), (chin, chinReach)])
        return ExprWarp.apply(to: input.composed, in: region, bounds: input.rect) { source in
            let big = ExprWarp.bump(source, center: forehead, radius: foreheadReach, scale: 0.55 * amount)
            return ExprWarp.bump(big, center: chin, radius: chinReach, scale: -0.6 * amount)
        }
    }

    // MARK: The skin

    /// Tints the face green, keeping its light and shade. Only the person is tinted when there is a cutout to say where they are.
    private func greened(_ picture: CIImage, input: LensInput, face: FaceState, amount: Double) -> CIImage {
        let region = face.exprRegion(around: face.exprPoint(0, -1.0), radius: 2.4).integral.intersection(input.rect)
        guard amount > 0.01, !region.isNull, let wash = input.services.exprOverlay({ ctx in
            ctx.inFaceSpace(face) {
                ctx.translateBy(x: 0, y: -0.6)
                ctx.scaleBy(x: 1.2, y: 1.45)
                let stops: [(Double, Double)] = [(0, 0.95), (0.62, 0.9), (0.88, 0.2), (1, 0)]
                if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: stops.map { exprColor((0.28, 0.85, 0.3), $0.1 * amount) } as CFArray,
                                      locations: stops.map { CGFloat($0.0) }) {
                    ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
                    // The neck goes green too, fading out toward the collar, so there is no line under the chin.
                    ctx.saveGState()
                    ctx.translateBy(x: 0, y: -0.95)
                    ctx.scaleBy(x: 0.42, y: 0.42)
                    ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
                    ctx.restoreGState()
                }
            }
        }) else { return picture }

        let blend = CIFilter.colorBlendMode()
        blend.inputImage = wash.cropped(to: region)
        blend.backgroundImage = picture.cropped(to: region)
        var tinted = blend.outputImage?.cropped(to: region) ?? picture.cropped(to: region)
        if let matte = input.matte, input.background != nil {
            let keep = CIFilter.blendWithMask()
            keep.inputImage = tinted
            keep.backgroundImage = picture.cropped(to: region)
            keep.maskImage = matte
            tinted = keep.outputImage?.cropped(to: region) ?? tinted
        }
        return tinted.composited(over: picture).cropped(to: input.rect)
    }

    // MARK: Eyes and antennae

    private func draw(_ ctx: CGContext, face: FaceState, time: Double, amount: Double) {
        // Room above the head, in face units, so a face close to the camera gets shorter antennae instead of clipped ones.
        let topMargin = bounds.maxY - bounds.height * 0.05
        let up = Double(face.up.dy)
        let room = up > 0.3 ? (topMargin - face.eyeCenter.y) / (face.interocular * up) - 1.22 : 2
        let fit = min(1, max(0.35, room / 1.3))
        ctx.inFaceSpace(face) {
            for side in [-1.0, 1.0] { drawAntenna(ctx, side: side, time: time, amount: amount * fit) }
            for side in [-1.0, 1.0] { drawEye(ctx, side: side, blink: face.blink, amount: amount) }
        }
    }

    private func drawEye(_ ctx: CGContext, side: Double, blink: Double, amount: Double) {
        ctx.saveGState()
        ctx.translateBy(x: side * 0.5, y: 0.02)
        ctx.rotate(by: -side * 0.42)                    // the outer corners tip down
        ctx.scaleBy(x: 0.44 * amount, y: 0.44 * amount * max(0.1, 1 - 0.9 * blink))
        let almond = CGMutablePath()
        almond.move(to: CGPoint(x: -1, y: 0))
        almond.addQuadCurve(to: CGPoint(x: 1, y: 0), control: CGPoint(x: -0.1, y: 1.45))
        almond.addQuadCurve(to: CGPoint(x: -1, y: 0), control: CGPoint(x: 0.1, y: -1.45))
        almond.closeSubpath()

        ctx.saveGState()
        ctx.addPath(almond); ctx.clip()
        if let g = ExprShapes.gradient([((0.2, 0.24, 0.36), 0), ((0.02, 0.03, 0.06), 0.55), ((0, 0, 0), 1)]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: -0.25, y: 0.35), startRadius: 0, endCenter: CGPoint(x: 0, y: 0), endRadius: 1.3, options: [])
        }
        ctx.restoreGState()
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(exprColor((0.05, 0.1, 0.12)))
        ctx.setLineWidth(0.08)
        ctx.addPath(almond); ctx.strokePath()

        // The shine on glossy black.
        ctx.setFillColor(exprColor((1, 1, 1), 0.85))
        ctx.saveGState()
        ctx.translateBy(x: -0.28, y: 0.32)
        ctx.rotate(by: 0.5)
        ctx.fillEllipse(in: CGRect(x: -0.3, y: -0.1, width: 0.6, height: 0.2))
        ctx.restoreGState()
        ctx.setFillColor(exprColor((1, 1, 1), 0.35))
        ctx.fillEllipse(in: CGRect(x: 0.3, y: -0.35, width: 0.2, height: 0.1))
        ctx.restoreGState()
    }

    private func drawAntenna(_ ctx: CGContext, side: Double, time: Double, amount: Double) {
        let phase = side > 0 ? 0.0 : 1.3
        let wag = 0.2 * sin(time * 3.1 + phase) + 0.07 * sin(time * 7.3 + phase * 2)
        let lean = side * (0.4 - 0.28 * perk) + wag
        let length = (0.95 + 0.2 * perk) * amount
        let base = CGPoint(x: side * 0.42, y: 1.22)
        let bend = lean - side * 0.4
        let control = CGPoint(x: base.x + sin(bend) * length * 0.55, y: base.y + cos(bend) * length * 0.55)
        let tip = CGPoint(x: base.x + sin(lean) * length, y: base.y + cos(lean) * length * 0.95)

        ctx.setLineCap(.round)
        for (width, colour) in [(0.11, (0.08, 0.28, 0.12)), (0.06, (0.36, 0.74, 0.38)), (0.02, (0.7, 0.95, 0.62))] as [(Double, ExprRGB)] {
            ctx.setStrokeColor(exprColor(colour))
            ctx.setLineWidth(width)
            ctx.move(to: base); ctx.addQuadCurve(to: tip, control: control); ctx.strokePath()
        }
        // A glowing bulb at the end, throbbing.
        let throb = 0.5 + 0.5 * sin(time * 4.2 + phase)
        let radius = 0.16 * amount
        ctx.setBlendMode(.plusLighter)
        ctx.glow(center: tip, radius: 0.36 * amount, red: 0.5, green: 1, blue: 0.4, alpha: 0.2 + 0.25 * throb + 0.2 * perk)
        ctx.setBlendMode(.normal)
        if let g = ExprShapes.gradient([((0.95, 1.0, 0.65), 0), ((0.4, 0.9, 0.3), 0.6), ((0.12, 0.55, 0.15), 1)]) {
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2)); ctx.clip()
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: tip.x - radius * 0.3, y: tip.y + radius * 0.3), startRadius: 0,
                                   endCenter: tip, endRadius: radius * 1.25, options: [])
            ctx.restoreGState()
        }
        ctx.setStrokeColor(exprColor((0.08, 0.35, 0.1)))
        ctx.setLineWidth(0.025)
        ctx.strokeEllipse(in: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
    }
}
