import CoreGraphics
import CoreImage
import Foundation
import simd

// The shared contract of the Dragon Ball lens. The lens is built from four independent pieces that meet here:
//
//   face   SaiyanFace         hair, brows and eyes of every form (a `HeadwearCostume`, fed by `HeadwearRig`)
//   body   SaiyanAura         the aura behind and the light over the person
//          SaiyanTransformation   reads both fists and the face, and decides the form
//   moves  `SaiyanMove`s      ten moves that read the hands and draw light, run by `SaiyanMoveSet`
//
// Everything is in output pixels, origin lower left, y up (as everywhere else in the lens code).

// MARK: - Body state

/// What the body half needs to draw one frame. Made by `SaiyanTransformation`.
struct SaiyanBodyState {
    var form: SaiyanForm = .base
    /// The form before the latest change, for blending between the two while `transition` runs.
    var previousForm: SaiyanForm = .base
    /// 0 at the moment the form changed to 1 when it has settled, over about 0.7 seconds.
    var transition = 1.0
    /// The strength of the form, 0...1, easing toward `form.power` after a change rather than jumping. The aura and the moves scale by it.
    var level = 0.0
    /// 0...1 how full the power-up is toward the next form. 0 when not powering up.
    var charge = 0.0
    /// Mouth open wide while fists are held: the charge is going up faster.
    var screaming = false
    /// 1 at the instant of a change, falling to 0 over about 0.6 seconds: the white flash.
    var flash = 0.0
    /// Seconds since the form last changed. Drives the shockwave rings. Large when nothing has changed for a while.
    var sinceChange = 99.0
    /// 0...1 how much of the effect is showing: it fades with the face rather than vanishing.
    var presence = 1.0
    /// The lens clock, in seconds.
    var time = 0.0
}

// MARK: - What a move is given

/// Everything a move may read, for one frame.
struct SaiyanMoveContext {
    /// The hands in view, steadied by the lens (up to two). Joints are in `HandJoint` order. A hand lost for a moment is held by the tracker.
    var hands: [HandState]
    /// The lens's own gesture recogniser, already updated for this frame: `gestures.pose(of:)`, `.heldFor(_:)`, `.isTowardCamera(_:)`.
    var gestures: HandGestureRecognizer
    /// What happened this frame: poses started or ended, swipes, taps, pinches.
    var events: [HandGesture]
    var face: FaceState?
    /// Where the person is, from the cutout (or the face when there is none). Nil when nobody is in view.
    var personCenter: CGPoint?
    var form: SaiyanForm
    /// The current strength, 0...1 (`SaiyanBodyState.level`).
    var power: Double
    var dt: Double
    var time: Double
    /// The picture, in output pixels.
    var rect: CGRect

    var palette: SaiyanPalette { form.palette }

    /// Which way a beam should go from `point`: +1 for toward the right of the picture, -1 for toward the left. Beams fly sideways across the
    /// picture, away from the person, never at the camera. Without a person, toward the side with more room.
    func outward(from point: CGPoint) -> Double {
        if let c = personCenter, abs(point.x - c.x) > 24 { return point.x > c.x ? 1 : -1 }
        return point.x > rect.midX ? -1 : 1
    }

    /// How big a unit of the picture is for the effects: 1 at 1280 by 720.
    var scale: Double { rect.width / 1280 }
}

// MARK: - What a move gives back

/// A big soft light made on the graphics chip (`WorldKit.wash`): the glow round a charging orb or the length of a beam.
struct SaiyanWash {
    var center: CGPoint
    var radius: Double
    var colour: SIMD3<Double>
    var alpha: Double
}

/// A copy of the person left behind or drawn beside them: Zanzoken's afterimages, Instant Transmission's ghosts.
struct SaiyanEcho {
    /// How far to slide the copy, in pixels.
    var offset: CGVector
    var alpha: Double
    /// Colour to tint the copy toward, and how far (0 leaves it as it is, 1 makes it a flat silhouette of the colour).
    var tint: SIMD3<Double> = SIMD3(0.6, 0.85, 1)
    var tintAmount = 0.6
    /// Grow or shrink the copy about the middle of the picture's bottom edge. 1 leaves it.
    var scale = 1.0
}

/// What a move does to the whole picture.
struct SaiyanScreenEffect {
    /// A white (or `flashTint`) wash over everything, 0...1.
    var flash = 0.0
    var flashTint = SIMD3<Double>(1, 1, 1)
    /// Shaking, 0...1: the picture jitters by up to about 14 pixels at 1.
    var shake = 0.0
    /// Darkens the room and the person, 0...1, to make a light stand out (the Spirit Bomb darkening the sky).
    var darken = 0.0
    /// How much of the person shows, 0...1. Instant Transmission dips it to 0 so you vanish and the room shows through.
    var personOpacity = 1.0
    var echoes: [SaiyanEcho] = []

    static let none = SaiyanScreenEffect()

    var isNone: Bool { flash <= 0.002 && shake <= 0.002 && darken <= 0.002 && personOpacity >= 0.998 && echoes.isEmpty }

    /// Several moves at once (a beam still fading while a flash plays): the strongest of each.
    static func merged(_ effects: [SaiyanScreenEffect]) -> SaiyanScreenEffect {
        var out = SaiyanScreenEffect()
        var strongest = 0.0
        for e in effects {
            if e.flash > strongest { strongest = e.flash; out.flashTint = e.flashTint }
            out.flash = max(out.flash, e.flash)
            out.shake = max(out.shake, e.shake)
            out.darken = max(out.darken, e.darken)
            out.personOpacity = min(out.personOpacity, e.personOpacity)
            out.echoes += e.echoes
        }
        return out
    }
}

// MARK: - A move

/// One move of the lens. It reads the hands, keeps its own charge and shots, and draws light. It never touches the camera picture
/// itself: it hands back washes, solid bodies, light and screen effects, and the lens composes them (see `SaiyanMoveSet`).
///
/// Rules every move keeps:
/// - Only one move is "engaged" at a time. `update` is told `mayBegin`; when it is false the move must not start posing or charging, but it
///   must carry on anything already going.
/// - A move begins only on a pose held deliberately (a fraction of a second), never on a single frame, and it must be hard to set off by
///   accident: waving, a hand resting by the face, one fist, a hand held up while talking.
/// - A hand that the tracker loses for a moment (`HandState.unseenFor > 0`) must not make a charge pop or a beam vanish: ease out.
/// - Cheap: no per-pixel CPU work, big soft light through `washes`, details through `drawLight`.
protocol SaiyanMove: AnyObject {
    /// A stable id, for tests ("kamehameha").
    var id: String { get }
    /// What the status line calls it ("Kamehameha").
    var name: String { get }
    /// What to do, in a short plain sentence ("Cup both hands at your side and hold.").
    var hint: String { get }
    /// Posing, charging or firing: while one move is engaged no other may begin.
    var isEngaged: Bool { get }
    /// Anything of the move still on screen (a beam fading, sparks falling), even once it is no longer engaged.
    var hasLight: Bool { get }
    /// One line for the status bar while the move is engaged.
    var status: LensStatus? { get }
    var screenEffect: SaiyanScreenEffect { get }

    func update(_ c: SaiyanMoveContext, mayBegin: Bool)
    func reset()

    /// Big soft lights made on the graphics chip, in the order to add them.
    func washes() -> [SaiyanWash]
    /// Opaque bodies painted over the picture: the solid ball of an energy orb, a disc. Drawn normally, not added.
    func drawSolids(in ctx: CGContext)
    /// Light, drawn with additive blending: beams, sparks, arcs, rings. The lens adds this layer to the picture with a bloom.
    func drawLight(in ctx: CGContext)
}

extension SaiyanMove {
    var status: LensStatus? { nil }
    var screenEffect: SaiyanScreenEffect { .none }
    func washes() -> [SaiyanWash] { [] }
    func drawSolids(in ctx: CGContext) {}
    func drawLight(in ctx: CGContext) {}
}

/// The moves, in priority order: when two could begin on the same frame the earlier one wins, so the more specific poses come first.
enum SaiyanMoves {
    static func all() -> [SaiyanMove] {
        [
            SpecialBeamCannonMove(), InstantTransmissionMove(),   // two fingers at the forehead
            SolarFlareMove(),                                     // both hands in front of the face
            SpiritBombMove(), DestructoDiscMove(),                // hands above the head
            KamehamehaMove(), FinalFlashMove(),                   // two hands together
            KiBlastMove(), FingerBeamMove(),                      // one hand
            ZanzokenMove(),                                       // a swipe
        ]
    }
}

// MARK: - The router

/// Runs every move, lets only one begin at a time, and merges what they draw.
final class SaiyanMoveSet {
    let moves: [SaiyanMove]
    /// The move that is engaged now, if any.
    private(set) var engaged: SaiyanMove?

    init(moves: [SaiyanMove] = SaiyanMoves.all()) {
        self.moves = moves
    }

    /// `blocked` stops any move beginning (both fists held for a power-up, no face in view for a move that needs one is the move's own business).
    func update(_ c: SaiyanMoveContext, blocked: Bool) {
        var claimed: Int? = moves.firstIndex { $0.isEngaged }
        for (i, move) in moves.enumerated() {
            let mayBegin = !blocked && (claimed == nil || claimed == i)
            move.update(c, mayBegin: mayBegin)
            if claimed == nil, move.isEngaged { claimed = i }
        }
        engaged = moves.first { $0.isEngaged }
    }

    func reset() {
        for move in moves { move.reset() }
        engaged = nil
    }

    var hasLight: Bool { moves.contains { $0.hasLight || $0.isEngaged } }
    var status: LensStatus? { engaged?.status }
    var screenEffect: SaiyanScreenEffect { SaiyanScreenEffect.merged(moves.map(\.screenEffect)) }
    func washes() -> [SaiyanWash] { moves.flatMap { $0.washes() } }
    func drawSolids(in ctx: CGContext) { for move in moves { move.drawSolids(in: ctx) } }
    func drawLight(in ctx: CGContext) { for move in moves { move.drawLight(in: ctx) } }
}
