import CoreGraphics
import CoreImage

/// Tell a whopper: a long wooden nose grows while your mouth is open, sprouting leaves, and shrinks back when you shut up.
final class ExprPinocchioLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    /// Mouth opening that counts as talking, and (lower) as still talking, so the nose doesn't twitch with every syllable.
    static let startAt = 0.3, stopAt = 0.15
    /// How fast the nose grows and shrinks, as a fraction of its full length per second.
    static let growRate = 0.45, shrinkRate = 0.7
    /// Length of the nose in eye-spacings: a stub at rest, a long way out at full length.
    static let stubLength = 0.34, fullLength = 3.2

    private struct Sprout { var along: Double; var growsAt: Double; var side: Double; var size: Double }
    /// Where the leaves come out: how far along the nose, how long it must be first, which side, how big.
    private static let sprouts = [Sprout(along: 0.34, growsAt: 0.18, side: 1, size: 0.55), Sprout(along: 0.5, growsAt: 0.32, side: -1, size: 0.62),
                                  Sprout(along: 0.63, growsAt: 0.46, side: 1, size: 0.7), Sprout(along: 0.76, growsAt: 0.6, side: -1, size: 0.66),
                                  Sprout(along: 0.88, growsAt: 0.76, side: 1, size: 0.6)]

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var talking = ExprLatch()
    private var growth = Ramp()
    private var visibleFor = 0.0

    /// How far the nose has grown, 0 (a stub) to 1 (the full length).
    var noseLength: Double { growth.value }
    var isLying: Bool { talking.isOn }
    /// How many leaves have started to sprout.
    var leafCount: Int { Self.sprouts.filter { growth.value > $0.growsAt }.count }

    func restart() {
        talking.reset()
        growth = Ramp()
        visibleFor = 0
    }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Open your mouth and tell a fib")
        let dt = input.dt
        guard let face = input.face else {
            talking.reset()
            visibleFor = 0
            growth.move(toward: 0, dt: dt, rate: Self.shrinkRate)
            return input.composed
        }
        visibleFor += dt
        talking.update(face.mouthOpen, on: Self.startAt, off: Self.stopAt)
        growth.move(toward: talking.isOn ? 1 : 0, dt: dt, rate: talking.isOn ? Self.growRate : Self.shrinkRate)

        guard let layer = input.services.exprOverlay({ ctx in draw(ctx, face: face, time: input.time) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    // MARK: Drawing

    /// Eased growth, so the nose speeds up out of the stub.
    private var grown: Double { growth.value * growth.value * (3 - 2 * growth.value) }

    private func draw(_ ctx: CGContext, face: FaceState, time: Double) {
        let pop = 1 - pow(1 - min(1, visibleFor / 0.3), 3)
        let len = (Self.stubLength + (Self.fullLength - Self.stubLength) * grown) * pop
        let quiver = talking.isOn ? sin(time * 23) * 0.012 : 0
        let angle = 0.12 - 0.3 * grown + sin(time * 1.6) * 0.025 * grown + quiver

        // The nose in the face's own units, starting at the tip of the real one.
        let tip = face.nose
        let dx = Double(tip.x - face.eyeCenter.x), dy = Double(tip.y - face.eyeCenter.y)
        let c = cos(-face.roll), s = sin(-face.roll)
        let base = CGPoint(x: (dx * c - dy * s) / face.interocular, y: (dx * s + dy * c) / face.interocular)

        ctx.inFaceSpace(face) {
            ctx.translateBy(x: base.x, y: base.y)
            ctx.rotate(by: angle)
            drawNose(ctx, length: len)
            drawLeaves(ctx, length: len, time: time)
        }
    }

    /// Half the thickness of the nose at `x` along it: fat at the root, thinner toward the tip.
    private func halfWidth(_ x: Double, length: Double) -> Double {
        let t = min(1, x / max(length, 1e-6))
        return 0.21 - 0.1 * t * (0.25 + 0.75 * grown)
    }

    /// How far the nose sags at `x` along it.
    private func sag(_ x: Double, length: Double) -> Double {
        let t = min(1, x / max(length, 1e-6))
        return -0.1 * grown * t * t * length
    }

    private func drawNose(_ ctx: CGContext, length: Double) {
        let steps = 14
        let outline = CGMutablePath()
        for i in 0...steps {
            let x = length * Double(i) / Double(steps)
            let pt = CGPoint(x: x, y: sag(x, length: length) + halfWidth(x, length: length))
            if i == 0 { outline.move(to: pt) } else { outline.addLine(to: pt) }
        }
        let tipHalf = halfWidth(length, length: length), tipY = sag(length, length: length)
        outline.addArc(center: CGPoint(x: length, y: tipY), radius: CGFloat(tipHalf), startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        for i in stride(from: steps, through: 0, by: -1) {
            let x = length * Double(i) / Double(steps)
            outline.addLine(to: CGPoint(x: x, y: sag(x, length: length) - halfWidth(x, length: length)))
        }
        outline.closeSubpath()

        ctx.saveGState()
        ctx.addPath(outline); ctx.clip()
        if let g = ExprShapes.gradient([((0.98, 0.78, 0.5), 0), ((0.84, 0.57, 0.3), 0.45), ((0.56, 0.34, 0.16), 1)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0.25), end: CGPoint(x: 0, y: -0.25), options: [])
        }
        // Rings, like a branch.
        ctx.setLineCap(.round)
        ctx.setStrokeColor(exprColor((0.4, 0.22, 0.08), 0.35))
        ctx.setLineWidth(0.022)
        var x = 0.17
        while x < length {
            let h = halfWidth(x, length: length), y = sag(x, length: length)
            ctx.move(to: CGPoint(x: x, y: y + h)); ctx.addQuadCurve(to: CGPoint(x: x, y: y - h), control: CGPoint(x: x + 0.04, y: y)); ctx.strokePath()
            x += 0.2
        }
        // Grain along it.
        ctx.setLineWidth(0.016)
        ctx.setStrokeColor(exprColor((0.4, 0.22, 0.08), 0.25))
        for offset in [-0.45, 0.1] {
            ctx.move(to: CGPoint(x: 0.05, y: halfWidth(0, length: length) * offset))
            for i in 1...steps {
                let px = length * Double(i) / Double(steps)
                ctx.addLine(to: CGPoint(x: px, y: sag(px, length: length) + halfWidth(px, length: length) * offset))
            }
            ctx.strokePath()
        }
        // A highlight along the top.
        ctx.setStrokeColor(exprColor((1, 0.95, 0.8), 0.45))
        ctx.setLineWidth(0.03)
        ctx.move(to: CGPoint(x: 0.06, y: halfWidth(0, length: length) * 0.55))
        for i in 1...steps {
            let px = length * Double(i) / Double(steps)
            ctx.addLine(to: CGPoint(x: px, y: sag(px, length: length) + halfWidth(px, length: length) * 0.55))
        }
        ctx.strokePath()
        ctx.restoreGState()

        ctx.setLineJoin(.round)
        ctx.setStrokeColor(exprColor((0.38, 0.2, 0.07)))
        ctx.setLineWidth(0.03)
        ctx.addPath(outline); ctx.strokePath()
    }

    private func drawLeaves(_ ctx: CGContext, length: Double, time: Double) {
        guard let leaf = ExprSprites.leaf() else { return }
        for (i, sprout) in Self.sprouts.enumerated() {
            let size = exprSmoothstep(sprout.growsAt, sprout.growsAt + 0.14, growth.value)
            guard size > 0.01 else { continue }
            let x = length * sprout.along
            let stalk = CGPoint(x: x, y: sag(x, length: length) + sprout.side * halfWidth(x, length: length) * 0.7)
            // Leaves point out and forward, and flutter a little.
            let heading = sprout.side * (0.95 + 0.08 * sin(time * 2.4 + Double(i) * 1.7))
            let leafLength = sprout.size * size
            let centre = CGPoint(x: stalk.x + cos(heading) * leafLength / 2, y: stalk.y + sin(heading) * leafLength / 2)
            ctx.exprStamp(leaf, at: centre, height: leafLength / 0.95, rotation: heading)
        }
    }
}
