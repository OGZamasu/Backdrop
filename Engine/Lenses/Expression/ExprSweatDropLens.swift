import CoreGraphics
import CoreImage

/// The anime "uh-oh": raise your eyebrows and a big glossy sweat drop pops onto your temple, slides, wobbles and drips off,
/// with nervous lines on your forehead and a few drops flicked off the other side. At rest a small bead glistens there.
final class ExprSweatDropLens: ExprOverlayLens {
    static let startAt = 0.5, stopAt = 0.3
    /// Seconds a drop hangs on before it drips off and another forms.
    static let hangTime = 2.6

    private var raised = ExprLatch()
    /// How long the current drop has been on the temple; nil when there isn't one.
    private var dropAge: Double?
    private var nerves = ExprSpring()
    private var falling = ParticleSystem(capacity: 40)
    private var rng = SplitMix64(seed: 0x5EA7)
    private(set) var dropsShed = 0

    var isNervous: Bool { raised.isOn }
    var hasDrop: Bool { dropAge != nil }
    var fallingCount: Int { falling.particles.count }

    override var hintText: String { "Raise your eyebrows" }
    override var isFinished: Bool { presence.face == nil && falling.particles.isEmpty }

    override init() {
        super.init()
        falling.gravity = SIMD2(0, -1300)
    }

    override func restart() {
        super.restart()
        raised.reset(); dropAge = nil; nerves.reset(); falling.removeAll(); dropsShed = 0
    }

    /// Where the hanging drop sits, in face units, `age` seconds after it formed: it creeps down the temple.
    static func dropSpot(age: Double) -> CGPoint {
        let slide = exprSmoothstep(0.25, hangTime, age)
        return CGPoint(x: 1.1 + 0.06 * slide, y: 0.95 - 0.42 * slide)
    }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        if let face {
            let was = raised.isOn
            raised.update(face.browRaise, on: Self.startAt, off: Self.stopAt)
            if raised.isOn && !was {
                if dropAge == nil { dropAge = 0 }
                flick(face)
            }
            if var age = dropAge {
                age += dt
                // Let go when the brows come down, or after hanging a while; a new one forms if they are still up.
                if !raised.isOn || age > Self.hangTime {
                    shed(face, age: age)
                    dropAge = raised.isOn ? -0.45 : nil
                } else {
                    dropAge = age
                }
            }
        } else {
            raised.reset()
            dropAge = nil
        }
        nerves.step(toward: raised.isOn ? 1 : 0, dt: dt, frequency: 2.4, damping: 0.6)
        falling.step(dt)
    }

    /// The drop lets go and falls down the picture.
    private func shed(_ face: FaceState, age: Double) {
        guard age > 0.15 else { return }
        dropsShed += 1
        let spot = Self.dropSpot(age: age)
        let at = face.exprPoint(spot.x, spot.y)
        falling.emit(Particle(position: at.simd, velocity: SIMD2(face.acrossVector.x, face.acrossVector.y) * 60 * face.exprScale,
                              life: 1.2, size: face.interocular * 0.7, hue: face.roll, kind: 0))
    }

    /// A few small drops flicked off the other temple.
    private func flick(_ face: FaceState) {
        let scale = face.exprScale
        for i in 0..<3 {
            let at = face.exprPoint(-1.0, 0.75 + Double(i) * 0.1)
            let angle = Double.pi * (0.62 + 0.12 * Double(i)) + face.roll
            falling.emit(Particle(position: at.simd, velocity: SIMD2(cos(angle), sin(angle)) * Double.random(in: 260...380, using: &rng) * scale,
                                  life: 0.7, size: face.interocular * Double.random(in: 0.16...0.24, using: &rng), hue: angle, kind: 1))
        }
    }

    override func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        for p in falling.particles {
            let at = CGPoint(x: p.position.x, y: p.position.y)
            let fade = 1 - exprSmoothstep(0.55, 1, p.progress)
            // Pointing the way it falls, stretched a little by speed.
            let heading = atan2(p.velocity.y, p.velocity.x)
            ctx.saveGState()
            ctx.translateBy(x: at.x, y: at.y)
            ctx.rotate(by: heading + .pi)
            ctx.scaleBy(x: 1 + min(0.5, hypot(p.velocity.x, p.velocity.y) / 3000), y: 1)
            ctx.exprStamp(ExprSprites.tear(), at: .zero, height: p.size, alpha: fade)
            ctx.restoreGState()
        }
        guard let face else { return }
        let fade = presence.alpha
        ctx.saveGState()
        ctx.setAlpha(CGFloat(fade))
        ctx.inFaceSpace(face) {
            drawNerves(ctx, amount: nerves.value, time: time)
            if let age = dropAge, age >= 0 {
                // Pops in fat and round, stretches as it settles, then wobbles as it creeps.
                let pop = exprOutElastic(min(1, age / 0.55))
                let wobble = 1 + 0.05 * sin(age * 9) * exp(-age * 0.6)
                let spot = Self.dropSpot(age: age)
                ctx.saveGState()
                ctx.translateBy(x: spot.x, y: spot.y)
                ctx.scaleBy(x: pop / wobble, y: pop * wobble)
                ctx.exprPlace(ExprSprites.tear(), at: .zero, height: 1.0, rotation: -.pi / 2)
                ctx.restoreGState()
            } else {
                // At rest, a small bead that catches the light now and then.
                let bead = CGPoint(x: 1.04, y: 0.72)
                ctx.exprPlace(ExprSprites.tear(), at: bead, height: 0.3 * popIn, rotation: -.pi / 2, alpha: 0.95)
                let glint = pow(max(0, sin(time * 2.1)), 12)
                ctx.exprPlace(ExprSprites.twinkle(variant: 0), at: CGPoint(x: bead.x - 0.05, y: bead.y + 0.02), height: 0.34 * glint, rotation: time, alpha: glint)
            }
        }
        ctx.restoreGState()
    }

    /// Three blue-violet lines down the forehead that shiver.
    private func drawNerves(_ ctx: CGContext, amount: Double, time: Double) {
        guard amount > 0.02 else { return }
        ctx.setLineCap(.round)
        for i in 0..<3 {
            let x = -0.32 + Double(i) * 0.32
            let shiver = sin(time * 31 + Double(i) * 2) * 0.012
            let top = 1.18, bottom = 1.18 - 0.5 * min(1, amount)
            for (width, colour, alpha) in [(0.075, (1.0, 1.0, 1.0), 0.6), (0.045, (0.36, 0.34, 0.86), 0.95)] as [(Double, ExprRGB, Double)] {
                ctx.setStrokeColor(exprColor(colour, alpha * min(1, amount)))
                ctx.setLineWidth(width)
                ctx.move(to: CGPoint(x: x + shiver, y: top)); ctx.addLine(to: CGPoint(x: x - shiver, y: bottom)); ctx.strokePath()
            }
        }
    }
}
