import CoreGraphics
import CoreImage

/// A funhouse that never stops: your features slowly shrink to pinpricks, then swell to giants, with a quick pulse riding on top.
final class ExprSqueezeLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    /// Seconds for one slow trip from tiny to giant and back.
    static let period = 7.0
    /// Pulses a second riding on the slow swing.
    static let beatRate = 1.7

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var visibleFor = 0.0

    /// How squeezed the face is at a moment: -1 for tiny features, +1 for giant ones. Depends on nothing but the time.
    static func amount(at time: Double) -> Double {
        let slow = sin(2 * .pi * time / period)
        let beat = sin(2 * .pi * time * beatRate)
        return max(-1, min(1, 0.82 * slow + 0.14 * beat))
    }

    init() { ExprWarpKernel.warmUp() }

    func restart() { visibleFor = 0 }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Watch your face change")
        guard let face = input.face else { visibleFor = 0; return input.composed }
        visibleFor += input.dt

        let squeeze = Self.amount(at: input.time) * exprSmoothstep(0, 0.5, visibleFor)
        let io = face.interocular
        let middle = face.exprFaceCenter
        let faceReach = io * 1.6, eyeReach = io * 0.78
        let eyes = [face.leftEye, face.rightEye]
        // The eyes first, where they really are; then the whole face, which carries the swollen (or shrunken) eyes along with it.
        let eyeTerms = eyes.map { eye -> ExprWarpTerm in
            var t = ExprWarpTerm(center: eye, across: eyeReach, along: eyeReach * 0.85, angle: face.roll)
            t.magnify = 0.6 * squeeze
            return t
        }
        var whole = ExprWarpTerm(center: middle, across: faceReach * 0.92, along: faceReach, angle: face.roll)
        whole.magnify = 0.5 * squeeze
        return ExprWarp.warp(ExprWarp.warp(input.composed, terms: eyeTerms, bounds: input.rect), terms: [whole], bounds: input.rect)
    }
}
