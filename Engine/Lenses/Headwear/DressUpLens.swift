import CoreGraphics
import CoreImage

/// Dress-up: a costume that sits on your head and face and follows every tilt, with a little life of its own.
///
/// The lens only looks after the plumbing: it turns the face into steady readings (`HeadwearRig`), hands them to the costume
/// and lays what the costume paints over the picture. What each costume looks like and how it reacts is in its own file.
final class DressUpLens: Lens {
    typealias Kind = HeadwearKind

    /// How long the costume takes to fade away once the face is lost, and to come back after a blip.
    static let fadeOut = 0.28, fadeIn = 0.15

    let needs: LensNeeds
    var status: LensStatus? { statusBox.value }

    let kind: Kind
    /// What is being worn. Exposed so tests can look at its springs and states.
    private(set) var costume: HeadwearCostume

    private let rig = HeadwearRig()
    private let statusBox = StatusBox()
    private var hint = FaceHint()
    /// The last frame with a face in it, kept so the costume can fade out where it was.
    private var last: HeadwearFrame?
    /// How much of the costume shows, 0...1: it fades rather than vanishing when the face is lost.
    private(set) var presence = 0.0

    init(kind: Kind) {
        self.kind = kind
        costume = kind.makeCostume()
        // A costume with something behind you (wings, a cape) needs the cutout to put you in front of it.
        needs = costume.hasBackLayer ? [.face, .matte] : [.face]
    }

    func restart() {
        rig.reset()
        costume.reset()
        last = nil
        presence = 0
    }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status(costume.hint)
        let dt = min(0.1, max(0, input.dt))
        let frame: HeadwearFrame
        if let now = rig.update(input.face, dt: input.dt, bounds: input.rect) {
            // A fresh entrance plays its own animation; coming back after a blip fades in where it was.
            presence = now.seen <= dt + 1e-9 ? 1 : min(1, presence + dt / Self.fadeIn)
            costume.advance(now)
            last = now
            frame = now
        } else {
            presence = max(0, presence - dt / Self.fadeOut)
            if rig.hasForgotten { costume.reset() }
            guard let held = last, presence > 0.01 else { last = nil; presence = 0; return input.composed }
            frame = held
        }
        let alpha = HeadwearEase.smoothstep(presence)

        var picture = input.composed
        var backIsInFront = false
        if costume.hasBackLayer {
            if input.matte != nil, let back = input.services.overlay({ ctx in costume.drawBack(HeadwearPen(ctx: ctx), frame, behindPerson: true) }) {
                picture = input.placingPerson(over: (alpha < 0.999 ? back.fading(alpha) : back).composited(over: input.scenery))
            } else {
                backIsInFront = true
            }
        }
        guard let layer = input.services.overlay({ ctx in
            let pen = HeadwearPen(ctx: ctx)
            if backIsInFront { costume.drawBack(pen, frame, behindPerson: false) }
            costume.draw(pen, frame)
        }) else { return picture }
        return (alpha < 0.999 ? layer.fading(alpha) : layer).composited(over: picture).cropped(to: input.rect)
    }
}
