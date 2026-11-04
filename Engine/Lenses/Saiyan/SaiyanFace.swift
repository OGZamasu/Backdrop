import CoreGraphics
import CoreImage
import Foundation

/// The face half of the Dragon Ball lens: hair, eyebrows and eyes for every form.
///
/// The lens feeds it through `HeadwearRig` like any costume, and tells it the form with `apply(_:)` before each `advance`. It draws in two
/// layers: Super Saiyan 3's long hair behind the person (`drawBack`), and everything else over the face (`draw`). Base draws nothing at all.
///
/// - Hair (`SaiyanHair`): springs up with an overshoot when the form changes while its colour crosses over from the old form's, trembles,
///   lifts and takes on the next form's colour while powering up, blazes white in the flash, sways with the head, and glints now and then.
/// - Brows and eyes (`SaiyanEyes`): bold brows in the hair's colour over the real ones (Super Saiyan 3 bares the brow ridge instead), and
///   recoloured irises under the real eyelids.
final class SaiyanFace: HeadwearCostume {
    var hint: String { "Hold both fists up to power up." }
    /// The long Super Saiyan 3 hair falls behind the shoulders, so the lens gives the face a layer behind the person.
    var hasBackLayer: Bool { true }
    /// Whether anything goes behind the person on this frame (Super Saiyan 3's long hair, and while it grows in or goes): the lens can skip
    /// the back layer when it is false.
    var drawsBehind: Bool { isDrawing && SaiyanHair.showsLongHair(body) }

    /// Whether the lens took the hair with `hairImage(_:)` after the latest `draw`. While it does, `draw` leaves the hair out of the layer
    /// and the graphics chip lays it: the one turned and scaled copy of the whole hair is most of this piece's work on the processor. A lens
    /// that never asks gets the hair painted into the layer, like any costume.
    private var lensTakesHair = false
    /// Whether the lens washed the back layer with `washBack(_:)` after the latest `drawBack`; while it does, the wash is left to the chip.
    private var lensWashesBack = false

    private(set) var body = SaiyanBodyState()
    /// The person's skin colour, sRGB 0...1, which the lens samples from the camera now and then. Used to bare the brow ridge of Super Saiyan 3,
    /// to cover the real brows under the drawn ones, and to shade where hair meets the forehead; a medium tone until the first sample.
    var skin = SIMD3<Double>(0.86, 0.68, 0.58)

    let hair = SaiyanHair()
    let eyes = SaiyanEyes()

    init() {}

    /// The body state of this frame: the form, the change in progress, the charge. Called by the lens before `advance`.
    func apply(_ state: SaiyanBodyState) { body = state }

    func reset() {
        body = SaiyanBodyState()
        hair.reset()
        eyes.reset()
    }

    /// Whether this state draws anything at all: base draws nothing, except while powering up (the hair flickers) or powering down.
    var isDrawing: Bool {
        !(body.form.isBase && (body.previousForm.isBase || body.transition >= 0.999) && body.charge <= 0.02)
    }

    func advance(_ frame: HeadwearFrame) {
        guard isDrawing else { return }
        hair.advance(frame, body)
    }

    func drawBack(_ pen: HeadwearPen, _ frame: HeadwearFrame, behindPerson: Bool) {
        // With no cutout to put the person in front of it, the long hair would cover them: leave it out.
        guard behindPerson, isDrawing else { return }
        hair.drawBack(pen, frame, body, entrance: HeadwearEase.smoothstep(frame.seen / 0.15), washHere: !lensWashesBack)
        lensWashesBack = false
    }

    /// The layer `drawBack` painted, with the long hair's colour wash done on the graphics chip: the same wash as the front hair, so the two
    /// match while powering up, in the flash and through a change. A lens that calls this right after `drawBack` saves the processor the
    /// wash; one that never does gets it painted into the layer.
    func washBack(_ layer: CIImage) -> CIImage {
        lensWashesBack = true
        guard let tint = hair.backTint else { return layer }
        return tint.wash(layer)
    }

    func draw(_ pen: HeadwearPen, _ frame: HeadwearFrame) {
        guard isDrawing else { hair.forget(); return }
        frame.inFace(pen.ctx) { eyes.drawEyes(pen, frame, body, appear: HeadwearEase.smoothstep(frame.seen / 0.2)) }
        var pieces = eyes.pieces(frame, body, skin: skin)
        if let band = hairline(frame) { pieces.append(band) }
        hair.draw(pen, frame, body, pieces: pieces, layOver: !lensTakesHair)
        lensTakesHair = false
    }

    /// The hair of the latest `draw`, in place over the face: a lens that lays this over the layer `draw` painted (every frame, right after
    /// `draw`) takes the heaviest part of the face off the processor. It carries the skin that goes under the hair, and the hair's colour
    /// washes are done here on the graphics chip. Nil when no hair is showing.
    func hairImage(_ frame: HeadwearFrame) -> CIImage? {
        lensTakesHair = true
        guard let p = hair.picture, p.alpha > 0.004 else { return nil }
        func placed(_ image: CGImage, _ box: CGRect) -> CIImage {
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let place = CGAffineTransform(scaleX: box.width / w, y: box.height / h)
                .concatenating(CGAffineTransform(translationX: box.minX, y: box.minY))
                .concatenating(CGAffineTransform(scaleX: CGFloat(p.scale * frame.io), y: CGFloat(p.scale * frame.io)))
                .concatenating(CGAffineTransform(rotationAngle: CGFloat(frame.roll)))
                .concatenating(CGAffineTransform(translationX: frame.center.x, y: frame.center.y))
            return CIImage(cgImage: image).transformed(by: place)
        }
        var out = placed(p.hair, p.box)
        if let t = p.tint { out = t.wash(out) }
        if let skin = p.skin { out = out.composited(over: placed(skin, p.skinBox)) }
        return p.alpha < 0.999 ? out.fading(p.alpha) : out
    }

    /// How much of the hair mass covers the head: all of it in any form but base, fading as it powers down.
    private var coverage: Double {
        let changing = body.transition < 0.999 && body.previousForm != body.form
        if !body.form.isBase {
            // Rising from base, it comes in with the hair mass.
            return changing && body.previousForm.isBase ? HeadwearEase.smoothstep(body.transition / 0.12) : 1
        }
        guard changing, !body.previousForm.isBase else { return 0 }
        return 1 - HeadwearEase.smoothstep(body.transition)
    }

    /// The skin just under the hairline, which hides a low fringe of the person's own, with the hair's shadow along its top.
    private func hairline(_ f: HeadwearFrame) -> SaiyanPiece? {
        let a = coverage
        guard a > 0.004 else { return nil }
        let head = SaiyanHair.steadied(f.head)
        let k = SaiyanHair.size(of: head)
        let line = head.up(SaiyanCap.hairlineY)
        // From where the brows rest, so raising them does not move it.
        let brow = (f.head.brow * 40).rounded() / 40
        let skin = SaiyanFaceKit.colour(self.skin)
        let bottom = brow + 0.1, top = line + 0.02
        let wide = head.wide
        let key = "\(Int((wide * 50).rounded()))-\(Int((head.tall * 50).rounded()))-\(Int((brow * 40).rounded()))"
            + "-\(Int((self.skin.x * 40).rounded()))-\(Int((self.skin.y * 40).rounded()))-\(Int((self.skin.z * 40).rounded()))"
        let window = CGRect(x: -1.1 * wide, y: min(bottom, top) - 0.1, width: 2.2 * wide, height: max(top, bottom) - min(bottom, top) + 0.36 * k)
        return SaiyanPiece(name: "saiyan-hairline-\(key)", at: .zero, window: window, alpha: a, layer: .skin) { pen in
            if top > bottom {
                SaiyanFaceKit.softOval(pen.ctx, at: hwp(0, (top + bottom) / 2), rx: 0.98 * wide, ry: (top - bottom) / 2 + 0.06, skin.faded(0.82))
            }
            SaiyanFaceKit.softOval(pen.ctx, at: hwp(0, line - 0.02), rx: 0.95 * wide, ry: 0.11 * k, skin.darker(0.28).faded(0.42))
        }
    }
}
