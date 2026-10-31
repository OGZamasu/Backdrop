import CoreGraphics
import CoreImage

/// What every drawn expression lens has in common: it needs the face, keeps the status line up to date, fades in when a face
/// turns up and out when it is lost (drawing with the last face it saw while it goes), and draws one overlay a frame.
/// Subclasses override `hintText`, `step`, `isFinished` and `draw`.
class ExprOverlayLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    let statusBox = StatusBox()
    var hint = FaceHint()
    var presence = ExprPresence()
    /// The picture's bounds this frame, for keeping things inside it.
    var bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)

    /// The hint shown while a face is in view.
    var hintText: String { "" }

    /// Nothing is left to draw (no face, every particle gone). Then the picture is handed back untouched.
    var isFinished: Bool { presence.face == nil }

    /// Advances the lens's own state for a frame. `face` is the face seen this frame, or nil.
    func step(_ face: FaceState?, dt: Double, time: Double) {}

    /// Draws a frame. `face` is the face to draw with (the last one seen, while it fades), or nil.
    func draw(_ ctx: CGContext, face: FaceState?, time: Double) {}

    /// Starts over. Subclasses add their own state and call through.
    func restart() { presence.reset() }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status(hintText)
        bounds = input.rect
        let dt = min(max(input.dt, 0), 0.25)
        presence.update(input.face, dt: dt)
        step(input.face, dt: dt, time: input.time)
        if isFinished { return input.composed }
        guard let layer = input.services.exprOverlay({ ctx in draw(ctx, face: presence.face, time: input.time) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    /// How far the lens has popped in since the face appeared: 0 to 1 with a small overshoot.
    var popIn: Double { exprOutBack(min(1, presence.visibleFor / 0.35)) }
}

/// What every warping expression lens has in common: the face, the status line, a strength on a spring that eases in when a
/// face turns up and back to nothing when it is lost.
class ExprWarpLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    let statusBox = StatusBox()
    var hint = FaceHint()
    /// 0 with no face to 1 with one, on a spring so the warp swells in with a little overshoot (and eases out without one).
    var amount = ExprSpring()
    /// The last face seen, kept until the warp has eased all the way out after the face is lost.
    private(set) var lastFace: FaceState?

    var hintText: String { "" }

    init() { ExprWarpKernel.warmUp() }

    /// Advances the lens's own state for a frame.
    func step(_ face: FaceState?, dt: Double, time: Double) {}

    /// The warp for one face at full strength scaled by `strength`.
    func terms(for face: FaceState, strength: Double, time: Double) -> [ExprWarpTerm] { [] }

    /// A chance to draw over the warped picture (sheen, sparkles). Nil means nothing to add.
    func overlay(_ input: LensInput, face: FaceState, time: Double) -> CIImage? { nil }

    func restart() { lastFace = nil; amount.reset() }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status(hintText)
        let dt = min(max(input.dt, 0), 0.25)
        if let f = input.face { lastFace = f }
        amount.step(toward: input.face == nil ? 0 : 1, dt: dt, frequency: 2.6, damping: input.face == nil ? 1 : 0.5)
        step(input.face, dt: dt, time: input.time)
        if input.face == nil && abs(amount.value) < 0.004 { lastFace = nil }
        guard let face = lastFace else { return input.composed }
        let warped = ExprWarp.warp(input.composed, terms: terms(for: face, strength: amount.value, time: input.time), bounds: input.rect)
        guard let top = overlay(input, face: face, time: input.time) else { return warped }
        return top.composited(over: warped).cropped(to: input.rect)
    }
}
