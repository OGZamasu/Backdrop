import CoreGraphics
import CoreImage

/// Cartoon dizzy: a ring of stars circles your head. Tip your head over or wobble it side to side and they whirl faster
/// and faster until your eyes turn into spirals; hold still and it all slows back down.
final class ExprDizzyLens: ExprOverlayLens {
    /// Dizziness needed for spiral eyes, and (lower) to lose them.
    static let spiralAt = 0.6, clearAt = 0.35
    static let starCount = 5

    private var dizzy = 0.0
    private var lastRoll: Double?
    private var spin = 0.0
    private var spiralLatch = ExprLatch()
    private var spiral = ExprSpring()

    /// How dizzy, 0 to 1.
    var dizziness: Double { dizzy }
    var hasSpiralEyes: Bool { spiralLatch.isOn }

    override var hintText: String { "Tip your head side to side" }

    override func restart() {
        super.restart()
        dizzy = 0; lastRoll = nil; spin = 0; spiralLatch.reset(); spiral.reset()
    }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        if let face {
            let speed = lastRoll.map { min(6, abs(face.roll - $0) / max(dt, 1e-3)) } ?? 0
            lastRoll = face.roll
            let tipped = max(0, abs(face.roll) - 0.15)
            dizzy = min(1, max(0, dizzy + (speed * 0.25 + tipped * 2.6 - 0.18) * dt))
        } else {
            lastRoll = nil
            dizzy = max(0, dizzy - dt * 0.5)
        }
        spiralLatch.update(dizzy, on: Self.spiralAt, off: Self.clearAt)
        spiral.step(toward: spiralLatch.isOn ? 1 : 0, dt: dt, frequency: 3, damping: 0.5)
        spin += dt * (1.1 + 6 * dizzy * dizzy)
    }

    override func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        guard let face else { return }
        let fade = presence.alpha
        ctx.saveGState()
        ctx.setAlpha(CGFloat(fade))
        ctx.inFaceSpace(face) {
            let wobble = sin(time * 1.9) * 0.1 * (0.3 + dizzy)
            let rx = 1.15 * popIn, ry = 0.3 + 0.06 * dizzy
            let centre = CGPoint(x: 0, y: 1.32)
            // A faint orbit line, so the ring reads as a ring.
            ctx.saveGState()
            ctx.translateBy(x: centre.x, y: centre.y)
            ctx.rotate(by: wobble)
            ctx.setStrokeColor(exprColor((1, 0.96, 0.8), 0.28))
            ctx.setLineWidth(0.025)
            ctx.setLineDash(phase: CGFloat(spin * 0.3), lengths: [0.06, 0.08])
            ctx.strokeEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            ctx.setLineDash(phase: 0, lengths: [])
            // Back half first, smaller and dimmer, then the front half over the head.
            let items = (0..<Self.starCount).map { i -> (CGPoint, Double, Double) in
                let a = spin + Double(i) * 2 * .pi / Double(Self.starCount)
                return (CGPoint(x: cos(a) * rx, y: sin(a) * ry), sin(a), a)
            }
            for front in [false, true] {
                for (i, item) in items.enumerated() where (item.1 < 0) == front {
                    let near = 0.5 - 0.5 * item.1          // 1 in front, 0 at the back
                    let size = (0.26 + 0.18 * near) * (i % 2 == 0 ? 1 : 0.78)
                    let image = i % 2 == 0 ? ExprSprites.star() : ExprSprites.twinkle(variant: 1)
                    ctx.exprPlace(image, at: item.0, height: i % 2 == 0 ? size : size * 1.6, rotation: item.2 * 1.5, alpha: 0.55 + 0.45 * near)
                }
            }
            ctx.restoreGState()
            if spiral.value > 0.02 { drawSpiralEyes(ctx, amount: spiral.value, time: time) }
        }
        ctx.restoreGState()
    }

    /// White eyes with ink spirals turning in them.
    private func drawSpiralEyes(_ ctx: CGContext, amount: Double, time: Double) {
        let r = 0.27 * min(1.2, amount)
        for side in [-1.0, 1.0] {
            let c = CGPoint(x: side * 0.5, y: 0.02)
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            let disc = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
            ctx.glow(center: CGPoint(x: 0.02, y: -0.04), radius: r * 1.35, red: 0.05, green: 0.02, blue: 0.1, alpha: 0.3 * min(1, amount))
            ctx.setFillColor(exprColor((1, 1, 1), min(1, amount)))
            ctx.fillEllipse(in: disc)
            ctx.rotate(by: -time * 5 * side)
            let path = CGMutablePath()
            let turns = 2.6
            for k in 0...60 {
                let t = Double(k) / 60
                let a = t * turns * 2 * .pi
                let p = CGPoint(x: cos(a) * r * 0.9 * t, y: sin(a) * r * 0.9 * t)
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.setStrokeColor(exprColor(ExprPalette.ink, min(1, amount)))
            ctx.setLineWidth(r * 0.17); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.addPath(path); ctx.strokePath()
            ctx.rotate(by: time * 5 * side)
            ctx.setLineWidth(r * 0.12)
            ctx.strokeEllipse(in: disc)
            ctx.restoreGState()
        }
    }
}
