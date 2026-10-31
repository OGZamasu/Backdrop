import CoreGraphics
import CoreImage

// Funhouse warps of the whole head, built on the smooth warp kernel: a head that blows up like a balloon, one that shrinks
// to a pea, a face that stretches long, and one that melts.

/// Smile and your head blows up like a balloon, bobbing up and wobbling as it fills.
final class ExprBalloonHeadLens: ExprWarpLens {
    static let startAt = 0.5, stopAt = 0.3

    private var smiling = ExprLatch()
    private var inflate = ExprSpring()

    var isInflated: Bool { smiling.isOn }
    /// How far it has blown up beyond its resting size, 0...1 (a little more as it wobbles).
    var inflation: Double { inflate.value }

    override var hintText: String { "Smile to blow up" }

    override func restart() { super.restart(); smiling.reset(); inflate.reset() }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        if let face { smiling.update(face.smile, on: Self.startAt, off: Self.stopAt) } else { smiling.reset() }
        // Slow to fill, quick to let go, and wobbly both ways, like rubber.
        inflate.step(toward: smiling.isOn ? 1 : 0, dt: dt, frequency: smiling.isOn ? 1.4 : 2.2, damping: 0.32)
    }

    override func terms(for f: FaceState, strength s: Double, time: Double) -> [ExprWarpTerm] {
        let swell = 0.24 + 0.32 * inflate.value
        var head = ExprWarpTerm.face(f, 0, -0.3, across: 1.75, along: 2.05)
        head.magnify = swell * s
        // It floats up as it fills, with a gentle bob.
        let lift = f.interocular * (0.06 + 0.24 * max(0, inflate.value) + 0.03 * sin(time * 2.2)) * s
        head.push = CGVector(dx: Double(f.up.dx) * lift, dy: Double(f.up.dy) * lift)
        return [head]
    }
}

/// Your head shrinks to a pea on your shoulders. Raise your eyebrows and it shrinks even more.
final class ExprTinyHeadLens: ExprWarpLens {
    static let startAt = 0.5, stopAt = 0.3

    private var raised = ExprLatch()
    private var shrink = ExprSpring()

    var isTinier: Bool { raised.isOn }

    override var hintText: String { "Raise your eyebrows to shrink more" }

    override func restart() { super.restart(); raised.reset(); shrink.reset() }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        if let face { raised.update(face.browRaise, on: Self.startAt, off: Self.stopAt) } else { raised.reset() }
        shrink.step(toward: raised.isOn ? 1 : 0, dt: dt, frequency: 2.4, damping: 0.4)
    }

    override func terms(for f: FaceState, strength s: Double, time: Double) -> [ExprWarpTerm] {
        var head = ExprWarpTerm.face(f, 0, -0.35, across: 1.85, along: 2.25)
        head.magnify = -(0.55 + 0.4 * shrink.value) * s
        // Sinks a little into the collar.
        let sink = f.interocular * 0.12 * s
        head.push = CGVector(dx: -Double(f.up.dx) * sink, dy: -Double(f.up.dy) * sink)
        return [head]
    }
}

/// A long face: open your mouth and your chin stretches down, boinging back when you close it.
final class ExprLongFaceLens: ExprWarpLens {
    static let startAt = 0.35, stopAt = 0.2

    private var open = ExprLatch()
    private var stretch = ExprSpring(0.15)

    var isStretching: Bool { open.isOn }
    /// How far the chin is pulled, 0 to about 1.
    var stretchAmount: Double { stretch.value }

    override var hintText: String { "Open your mouth" }

    override func restart() { super.restart(); open.reset(); stretch.reset(0.15) }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        var target = 0.15
        if let face {
            open.update(face.mouthOpen, on: Self.startAt, off: Self.stopAt)
            if open.isOn { target = 0.4 + 0.6 * exprSmoothstep(0.2, 0.9, face.mouthOpen) }
        } else {
            open.reset()
        }
        stretch.step(toward: target, dt: dt, frequency: 2.2, damping: 0.3)
    }

    override func terms(for f: FaceState, strength s: Double, time: Double) -> [ExprWarpTerm] {
        let io = f.interocular
        var jaw = ExprWarpTerm.face(f, 0, -1.45, across: 1.25, along: 1.4)
        let pull = min(0.78, 0.8 * max(0, stretch.value)) * io * s
        jaw.push = CGVector(dx: -Double(f.up.dx) * pull, dy: -Double(f.up.dy) * pull)
        // And a touch narrower, so it reads as long rather than just low.
        var narrow = ExprWarpTerm.face(f, 0, -0.9, across: 1.35, along: 1.1)
        narrow.magnify = -0.12 * max(0, stretch.value) * s
        return [jaw, narrow]
    }
}

/// Melt: open your mouth and your face sags and drips like wax in the sun; close it and it slowly firms up again.
final class ExprMeltingLens: ExprWarpLens {
    static let startAt = 0.4, stopAt = 0.25
    /// Where the drips hang across the face, how long each can get, and how fast it wobbles.
    private static let drips: [(x: Double, length: Double, wobble: Double)] = [(-0.64, 0.75, 1.3), (-0.22, 1.0, 1.0), (0.2, 0.85, 1.6), (0.62, 0.65, 1.2)]

    private var mouth = ExprLatch()
    private var melt = Ramp()

    var isMelting: Bool { mouth.isOn }
    /// How melted, 0 to 1.
    var meltAmount: Double { melt.value }

    override var hintText: String { "Open your mouth to melt" }

    override func restart() { super.restart(); mouth.reset(); melt = Ramp() }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        if let face { mouth.update(face.mouthOpen, on: Self.startAt, off: Self.stopAt) } else { mouth.reset() }
        melt.move(toward: mouth.isOn ? 1 : 0, dt: dt, rate: mouth.isOn ? 0.4 : (face == nil ? 2 : 0.6))
    }

    private func dripLength(_ i: Int, time: Double) -> Double {
        let d = Self.drips[i]
        let m = exprSmoothstep(0, 1, melt.value)
        return m * d.length * (1 + 0.06 * sin(time * d.wobble + Double(i) * 1.7))
    }

    override func terms(for f: FaceState, strength s: Double, time: Double) -> [ExprWarpTerm] {
        let io = f.interocular
        let m = exprSmoothstep(0, 1, melt.value) * s
        let down = SIMD2(-Double(f.up.dx), -Double(f.up.dy))
        var sag = ExprWarpTerm.face(f, 0, -0.55, across: 1.35, along: 1.55)
        let sagBy = 0.42 * m * io
        sag.push = CGVector(dx: down.x * sagBy, dy: down.y * sagBy)
        sag.magnify = -0.06 * m
        var out = [sag]
        for i in Self.drips.indices {
            let length = dripLength(i, time: time) * s
            var t = ExprWarpTerm.face(f, Self.drips[i].x, -1.15 - length * 0.4, across: 0.2 + 0.04 * Double(i % 2), along: 0.45 + length * 0.6)
            let by = length * 0.55 * io
            t.push = CGVector(dx: down.x * by, dy: down.y * by)
            out.append(t)
        }
        return out
    }

    /// A wet sheen down each drip, so the melt reads as liquid.
    override func overlay(_ input: LensInput, face: FaceState, time: Double) -> CIImage? {
        let m = exprSmoothstep(0, 1, melt.value) * max(0, amount.value)
        guard m > 0.05 else { return nil }
        return input.services.exprOverlay { ctx in
            ctx.inFaceSpace(face) {
                ctx.setLineCap(.round)
                for i in Self.drips.indices {
                    let length = dripLength(i, time: time)
                    let x = Self.drips[i].x + 0.05
                    let top = -0.95, bottom = -1.15 - length * 0.95
                    for (width, alpha) in [(0.06, 0.08), (0.02, 0.26)] {
                        ctx.setStrokeColor(exprColor((1, 1, 1), alpha * m)); ctx.setLineWidth(width)
                        ctx.move(to: CGPoint(x: x, y: top)); ctx.addQuadCurve(to: CGPoint(x: x - 0.02, y: bottom), control: CGPoint(x: x + 0.03, y: (top + bottom) / 2))
                        ctx.strokePath()
                    }
                    ctx.fillCircle(center: CGPoint(x: x - 0.03, y: bottom + 0.06), radius: 0.03, color: exprColor((1, 1, 1), 0.6 * m))
                }
            }
        }
    }
}
