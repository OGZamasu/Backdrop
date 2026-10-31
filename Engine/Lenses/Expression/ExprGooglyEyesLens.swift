import CoreGraphics
import CoreImage
import simd

/// Big googly eyes stuck over yours. The pupils are loose: they slosh about when you move your head and sink when you hold still.
final class ExprGooglyEyesLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    /// Eye white radius and pupil radius, in eye-spacings.
    static let whiteRadius = 0.37, pupilRadius = 0.17

    /// A pupil rolling about inside its eye. Positions are in eye-spacings from the middle of the eye, y up.
    struct Pupil {
        var position = SIMD2<Double>(0, 0)
        var velocity = SIMD2<Double>(0, 0)
    }

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var pupils = [Pupil(), Pupil()]
    private var lastCentre: CGPoint?
    private var lastVelocity = SIMD2<Double>(0, 0)
    private var shake = SIMD2<Double>(0, 0)
    private var visibleFor = 0.0

    var pupilPositions: [SIMD2<Double>] { pupils.map(\.position) }

    func restart() {
        pupils = [Pupil(), Pupil()]
        lastCentre = nil; lastVelocity = .zero; shake = .zero; visibleFor = 0
    }

    /// Moves a pupil for `dt` seconds. `push` is how hard the head is shoving the eye, in eye-spacings per second squared.
    static func step(_ pupil: inout Pupil, push: SIMD2<Double>, dt: Double) {
        let room = whiteRadius - pupilRadius - 0.015
        let gravity = SIMD2<Double>(0, -16)
        let steps = max(1, Int((dt / 0.008).rounded(.up)))
        let h = dt / Double(steps)
        for _ in 0..<steps {
            pupil.velocity += (gravity - push) * h
            pupil.velocity *= max(0, 1 - 2.2 * h)
            pupil.position += pupil.velocity * h
            let distance = simd_length(pupil.position)
            if distance > room {
                let normal = pupil.position / distance
                pupil.position = normal * room
                let into = simd_dot(pupil.velocity, normal)
                if into > 0 { pupil.velocity -= normal * into * 1.55 }       // bounce, losing some energy
            }
        }
    }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Shake your head")
        guard let face = input.face else {
            lastCentre = nil; visibleFor = 0
            return input.composed
        }
        let dt = min(input.dt, 1.0 / 20)
        visibleFor += dt
        let io = face.interocular

        // How hard the head is being shoved about, from the eye line's own movement.
        let centre = face.eyeCenter
        if let last = lastCentre {
            let velocity = SIMD2(Double(centre.x - last.x), Double(centre.y - last.y)) / max(dt, 1e-3) / io
            let accel = (velocity - lastVelocity) / max(dt, 1e-3)
            lastVelocity = velocity
            let limited = simd_length(accel) > 70 ? accel / simd_length(accel) * 70 : accel
            shake = SIMD2(exprEase(shake.x, toward: limited.x, dt: dt, tau: 0.05), exprEase(shake.y, toward: limited.y, dt: dt, tau: 0.05))
        }
        lastCentre = centre
        for i in pupils.indices { Self.step(&pupils[i], push: shake, dt: dt) }

        guard let layer = input.services.exprOverlay({ ctx in draw(ctx, face: face) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    private func draw(_ ctx: CGContext, face: FaceState) {
        let pop = 1 - pow(1 - min(1, visibleFor / 0.3), 3)
        let io = face.interocular
        let open = max(0.08, 1 - 0.92 * face.blink)
        for (i, eye) in [face.leftEye, face.rightEye].enumerated() {
            let radius = io * Self.whiteRadius * pop
            ctx.saveGState()
            ctx.translateBy(x: eye.x, y: eye.y)
            ctx.scaleBy(x: 1, y: open)

            ctx.glow(center: CGPoint(x: 0, y: -radius * 0.25), radius: radius * 1.5, red: 0, green: 0, blue: 0, alpha: 0.25)
            let disc = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
            if let g = ExprShapes.gradient([((1, 1, 1), 0), ((0.96, 0.97, 1.0), 0.6), ((0.78, 0.8, 0.88), 1)]) {
                ctx.saveGState()
                ctx.addEllipse(in: disc); ctx.clip()
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: -radius * 0.25, y: radius * 0.3), startRadius: 0, endCenter: .zero, endRadius: radius * 1.15, options: [])
                ctx.restoreGState()
            }
            ctx.setStrokeColor(exprColor(ExprPalette.ink))
            ctx.setLineWidth(max(1.5, io * 0.042))
            ctx.strokeEllipse(in: disc)

            let spot = CGPoint(x: pupils[i].position.x * io * pop, y: pupils[i].position.y * io * pop)
            let pr = io * Self.pupilRadius * pop
            ctx.fillCircle(center: spot, radius: pr, color: exprColor((0.04, 0.04, 0.06)))
            ctx.fillCircle(center: CGPoint(x: spot.x - pr * 0.35, y: spot.y + pr * 0.4), radius: pr * 0.28, color: exprColor((1, 1, 1), 0.9))
            // The plastic dome: a curved window of light at the top left that stays put while the pupil rolls under it.
            ctx.saveGState()
            ctx.translateBy(x: -radius * 0.38, y: radius * 0.42)
            ctx.rotate(by: 0.7)
            ctx.setFillColor(exprColor((1, 1, 1), 0.55))
            ctx.fillEllipse(in: CGRect(x: -radius * 0.32, y: -radius * 0.13, width: radius * 0.64, height: radius * 0.26))
            ctx.restoreGState()
            ctx.restoreGState()
        }
    }
}
