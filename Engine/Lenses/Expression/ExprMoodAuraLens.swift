import CoreGraphics
import CoreImage

/// A glow around your head that shows your mood: blue and calm, golden when you smile, violet when you are surprised,
/// red and big when you open wide. Behind you when there is a backdrop, a soft halo around you when there isn't.
final class ExprMoodAuraLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    static let calm: ExprRGB = (0.25, 0.55, 1.0)
    static let happy: ExprRGB = (1.0, 0.8, 0.16)
    static let surprised: ExprRGB = (0.78, 0.33, 1.0)
    static let loud: ExprRGB = (1.0, 0.16, 0.14)

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var tint = ExprMoodAuraLens.calm
    private var span = 1.0
    private var visible = Ramp()

    /// The colour of the glow right now.
    var colour: ExprRGB { tint }
    /// How big the glow is compared with calm, 1 and up.
    var size: Double { span }
    /// Whether the last frame put the glow behind you (there was a backdrop to put it on) or as a halo over the picture.
    private(set) var glowedBehind = false

    func restart() {
        tint = Self.calm; span = 1; visible = Ramp()
    }

    /// The colour and size a face is asking for: each expression pulls the glow toward its colour.
    static func mood(for f: FaceState) -> (colour: ExprRGB, size: Double) {
        let smile = exprSmoothstep(0.3, 0.8, f.smile)
        let brows = exprSmoothstep(0.35, 0.85, f.browRaise)
        let open = exprSmoothstep(0.35, 0.85, f.mouthOpen) * (1 - smile)      // a laugh is happy, not angry
        var colour = calm, size = 1.0
        colour = exprMix(colour, happy, smile); size += 0.25 * smile
        colour = exprMix(colour, surprised, brows); size += 0.3 * brows
        colour = exprMix(colour, loud, open); size += 0.55 * open
        return (colour, size)
    }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Show your mood")
        let dt = input.dt
        guard let face = input.face else {
            visible.move(toward: 0, dt: dt, rate: 3)
            return input.composed
        }
        let want = Self.mood(for: face)
        tint = exprMix(tint, want.colour, 1 - exp(-dt / 0.3))
        span = exprEase(span, toward: want.size, dt: dt, tau: 0.35)
        visible.move(toward: 1, dt: dt, rate: 2.5)

        let behind = input.matte != nil && input.background != nil
        glowedBehind = behind
        guard let layer = input.services.exprOverlay({ ctx in draw(ctx, face: face, time: input.time, behind: behind) }) else { return input.composed }
        if behind, let backdrop = input.background {
            return input.placingPerson(over: layer.composited(over: backdrop)).cropped(to: input.rect)
        }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    private func draw(_ ctx: CGContext, face: FaceState, time: Double, behind: Bool) {
        let breathe = 1 + 0.045 * sin(time * 2.1)
        let k = visible.value
        let rx = (behind ? 2.3 : 2.45) * span * breathe, ry = (behind ? 2.75 : 2.9) * span * breathe

        ctx.inFaceSpace(face) {
            ctx.translateBy(x: 0, y: -0.15)
            ctx.scaleBy(x: rx, y: ry)
            // Behind you the glow can be solid in the middle; over you it leaves a gap for the face.
            let stops: [(Double, Double)] = behind
                ? [(0, 0.95), (0.35, 0.85), (0.6, 0.45), (0.8, 0.16), (1, 0)]
                : [(0, 0), (0.5, 0), (0.64, 0.5), (0.78, 0.38), (0.9, 0.12), (1, 0)]
            let colours = stops.map { exprColor(tint, $0.1 * k) }
            if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours as CFArray,
                                  locations: stops.map { CGFloat($0.0) }) {
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
            }
        }

        // Motes drifting around the glow, brighter than it.
        ctx.setBlendMode(.plusLighter)
        let io = face.interocular
        for i in 0..<14 {
            let seed = Double(i)
            let angle = seed * 2.399 + time * (0.25 + 0.1 * Double(i % 3))
            let reach = 0.62 + 0.34 * (seed * 0.618).truncatingRemainder(dividingBy: 1)
            let p = face.exprPoint(cos(angle) * rx * reach, sin(angle) * ry * reach - 0.15)
            let twinkle = pow(max(0, sin(time * 2.6 + seed * 1.7)), 2)
            ctx.exprStamp(ExprSprites.twinkle(variant: 0), at: p, height: io * (0.1 + 0.16 * twinkle), rotation: time * 0.6 + seed, alpha: (0.25 + 0.75 * twinkle) * k)
        }
        ctx.setBlendMode(.normal)
    }
}
