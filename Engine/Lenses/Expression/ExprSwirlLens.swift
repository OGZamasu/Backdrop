import CoreGraphics
import CoreImage

/// Your face goes down the plughole: a twirl centred on it that tightens as you open your mouth and turns the other way
/// as you tip your head, with sparkles spiralling in at the centre.
final class ExprSwirlLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    /// The twirl never quite stops, even with a still face.
    static let restingTwist = 0.45
    /// How far the swirl reaches from the middle of the face, in eye-spacings.
    static let reach = 1.75

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var twist = 0.0
    private var spin = 0.0
    private var present = false

    /// The twirl in radians right now, smoothed.
    var currentTwist: Double { twist }

    /// The twirl a face asks for: open your mouth for more, tip your head one way or the other to turn it.
    static func targetTwist(for face: FaceState) -> Double {
        let tilt = max(-0.5, min(0.5, face.roll))
        return max(-6, min(6, restingTwist + 3.2 * face.mouthOpen + 4 * tilt))
    }

    init() { ExprWarpKernel.warmUp() }

    func restart() { twist = 0; spin = 0; present = false }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Open wide, or tip your head")
        guard let face = input.face else { present = false; return input.composed }
        let dt = input.dt

        let want = Self.targetTwist(for: face)
        twist = present ? exprEase(twist, toward: want, dt: dt, tau: 0.12) : want
        present = true
        spin += dt * (1.1 + 0.5 * abs(twist))

        let centre = face.exprFaceCenter
        let radius = face.interocular * Self.reach
        var term = ExprWarpTerm(center: centre, across: radius, along: radius * 1.1, angle: face.roll)
        term.twirl = twist * 0.65
        let warped = ExprWarp.warp(input.composed, terms: [term], bounds: input.rect)

        guard let layer = input.services.exprOverlay({ ctx in draw(ctx, centre: centre, radius: radius, io: face.interocular, time: input.time) }) else { return warped }
        return layer.composited(over: warped).cropped(to: input.rect)
    }

    private func draw(_ ctx: CGContext, centre: CGPoint, radius: Double, io: Double, time: Double) {
        let strength = min(1, 0.4 + abs(twist) / 3)
        ctx.setBlendMode(.plusLighter)
        ctx.glow(center: centre, radius: io * 0.55, red: 0.8, green: 0.75, blue: 1, alpha: 0.3 + 0.12 * abs(twist))
        let arms = 3, perArm = 6
        for arm in 0..<arms {
            for j in 0..<perArm {
                let f = Double(j) / Double(perArm - 1)
                let r = radius * (0.1 + 0.82 * pow(f, 0.9))
                // Curl each arm the way the picture is curling.
                let theta = Double(arm) * 2 * .pi / Double(arms) + spin - twist * pow(1 - r / radius, 2) * 1.5
                let at = CGPoint(x: centre.x + cos(theta) * r, y: centre.y + sin(theta) * r)
                let twinkle = pow(max(0, sin(time * 5 + Double(arm) * 2 + Double(j) * 1.3)), 2)
                ctx.exprStamp(ExprSprites.twinkle(variant: (arm + j) % 4), at: at, height: io * (0.17 + 0.26 * (1 - f)) * (0.7 + 0.5 * twinkle),
                              rotation: spin * 0.7 + Double(j), alpha: strength * (0.4 + 0.6 * twinkle) * (1 - 0.35 * f))
            }
        }
        ctx.setBlendMode(.normal)
    }
}
