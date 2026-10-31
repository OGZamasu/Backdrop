import CoreGraphics
import Foundation

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// Long-necked grazers: a zebra and a giraffe. The neck grows out of the shoulders as part of one outline with the body, so it can
/// bow and lift without a seam.
final class SceneGrazer: SceneQuadruped {
    enum Kind { case zebra, giraffe }
    private let kind: Kind
    private let coat: (base: UInt32, mark: UInt32, muzzle: UInt32, hoof: UInt32)
    /// Where the neck leaves the body, and how long it is.
    private let neckBase: CGPoint
    private let neckLength: Double
    private let neckAngle: Double

    init(_ kind: Kind) {
        self.kind = kind
        var b = SceneQuadBuild()
        switch kind {
        case .zebra:
            coat = (0xF3EFE6, 0x1C1917, 0x2A2522, 0x2A2420)
            b.hip = pt(-0.33, 0.53); b.shoulder = pt(0.15, 0.54)
            b.hindUpper = 0.27; b.hindLower = 0.285; b.foreUpper = 0.27; b.foreLower = 0.29
            b.hindWidths = (0.095, 0.042, 0.03); b.foreWidths = (0.08, 0.04, 0.03)
            b.tailRoot = pt(-0.52, 0.72); b.middle = pt(-0.1, 0.6)
            b.footLift = 0.085
            neckBase = pt(0.17, 0.70); neckLength = 0.27; neckAngle = 0.9
        case .giraffe:
            coat = (0xF1DDB0, 0x9A5426, 0x5A3A28, 0x3A2A22)
            b.hip = pt(-0.25, 0.44); b.shoulder = pt(0.09, 0.48)
            b.hindUpper = 0.215; b.hindLower = 0.24; b.foreUpper = 0.235; b.foreLower = 0.26
            b.hindWidths = (0.06, 0.03, 0.021); b.foreWidths = (0.055, 0.03, 0.021)
            b.tailRoot = pt(-0.33, 0.54); b.middle = pt(-0.08, 0.52)
            b.footLift = 0.06; b.strideScale = 0.85
            neckBase = pt(0.11, 0.60); neckLength = 0.34; neckAngle = 1.1
        }
        super.init()
        build = b
    }

    override func legColour(hind: Bool) -> UInt32 { coat.base }

    /// Where the head sits: at the top of the neck, which bows as the head drops.
    private func neckTop(_ p: SceneQuadPose) -> (base: CGPoint, top: CGPoint, bow: Double) {
        let base = neckBase.applying(p.body)
        let bow = max(-0.9, min(0.5, p.headAngle * (kind == .giraffe ? 1.4 : 0.9)))
        let angle = neckAngle + bow
        return (base, base.sceneMoved(cos(angle) * neckLength, sin(angle) * neckLength), bow)
    }

    override func drawBody(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let neck = neckTop(p)
        let along = pt(cos(neckAngle + neck.bow), sin(neckAngle + neck.bow))
        let side = pt(-Double(along.y), Double(along.x))
        func n(_ k: Double, _ w: Double) -> CGPoint {
            neck.base.sceneMoved(Double(along.x) * neckLength * k + Double(side.x) * w, Double(along.y) * neckLength * k + Double(side.y) * w)
        }
        let path: CGPath
        switch kind {
        case .zebra:
            let body = [pt(0.24, 0.50), pt(0.10, 0.43), pt(-0.14, 0.42), pt(-0.36, 0.45), pt(-0.50, 0.55), pt(-0.54, 0.68), pt(-0.47, 0.79),
                        pt(-0.22, 0.79), pt(0.02, 0.80)].map { $0.applying(p.body) }
            path = SceneShape.blob(body + [n(0.35, 0.085), n(0.8, 0.06), n(1.04, 0.045), n(1.0, -0.05), n(0.6, -0.075), n(0.1, -0.1)])
        case .giraffe:
            let body = [pt(0.15, 0.45), pt(-0.02, 0.405), pt(-0.18, 0.41), pt(-0.30, 0.45), pt(-0.345, 0.52), pt(-0.30, 0.585),
                        pt(-0.12, 0.62), pt(0.02, 0.67)].map { $0.applying(p.body) }
            path = SceneShape.blob(body + [n(0.3, 0.05), n(0.75, 0.035), n(1.03, 0.026), n(1.0, -0.03), n(0.55, -0.045), n(0.12, -0.075)])
        }
        ink.volume(ctx, path, coat.base, rim: 1)
        ink.inside(ctx, path) {
            switch kind {
            case .zebra: zebraStripes(ctx, p, ink, neck: n)
            case .giraffe: giraffePatches(ctx, p, ink, neck: n)
            }
        }
        // The mane along the top of the neck.
        let mane = (0...6).map { i -> CGPoint in let k = 0.15 + Double(i) * 0.15; return n(k, kind == .zebra ? 0.06 - 0.02 * k : 0.032) }
        let maneOut = (0...6).reversed().map { i -> CGPoint in let k = 0.15 + Double(i) * 0.15; return n(k, (kind == .zebra ? 0.11 - 0.035 * k : 0.05)) }
        let manePath = SceneShape.blob(mane + maneOut, tension: 0.7)
        ink.volume(ctx, manePath, kind == .zebra ? 0x2A2624 : 0x6A3A1E, rim: 0.6, edge: 0.6)
        if kind == .zebra, !ink.rough {
            ink.inside(ctx, manePath) {
                ink.lines(ctx, (0..<7).map { i -> [CGPoint] in let k = 0.2 + Double(i) * 0.13; return [n(k, 0.04), n(k + 0.02, 0.12)] }, coat.base, width: 0.012)
            }
        }
    }

    private func zebraStripes(_ ctx: CGContext, _ p: SceneQuadPose, _ ink: SceneInk, neck: (Double, Double) -> CGPoint) {
        // Separate small fills: Core Graphics fills many small shapes faster than one shape made of them all.
        ctx.setFillColor(ink.tone(coat.mark))
        func mark(_ path: CGPath) { ctx.addPath(path); ctx.fillPath() }
        // Body: bold stripes down from the back, bending back toward the haunch, which gets its own sweeping bands.
        for i in 0..<10 {
            let x = 0.2 - Double(i) * 0.062
            let w = 0.02 + 0.006 * sin(Double(i) * 1.7)
            let lean = Double(i) * 0.012
            let spine = [pt(x, 0.83), pt(x - lean * 0.6, 0.64), pt(x - lean, 0.44)].map { $0.applying(p.body) }
            mark(SceneShape.tube(spine, [w, w * 1.1, w * 0.4]))
        }
        for i in 0..<4 {
            let r = 0.07 + Double(i) * 0.048
            let c = pt(-0.38, 0.55)
            let arc = (0...5).map { k -> CGPoint in let a = 0.6 + Double(k) * 0.42; return pt(Double(c.x) + cos(a) * r * 1.2, Double(c.y) + sin(a) * r).applying(p.body) }
            mark(SceneShape.tube(arc, [0.006, 0.016, 0.017, 0.017, 0.014, 0.004]))
        }
        for i in 0..<6 {
            let k = 0.12 + Double(i) * 0.16
            mark(SceneShape.tube([neck(k, 0.12), neck(k + 0.03, 0), neck(k + 0.02, -0.1)], [0.016, 0.018, 0.006]))
        }
    }

    private func giraffePatches(_ ctx: CGContext, _ p: SceneQuadPose, _ ink: SceneInk, neck: (Double, Double) -> CGPoint) {
        ctx.setFillColor(ink.tone(coat.mark))
        func mark(_ path: CGPath) { ctx.addPath(path); ctx.fillPath() }
        let step = ink.rough ? 0.085 : 0.06
        var row = 0
        var y = 0.40
        while y < 0.72 {
            var x = -0.38 + (row % 2 == 0 ? 0 : step * 0.5)
            while x < 0.22 {
                let c = pt(x + (ScenePaint.noise(x * 17 + y * 5, 2) - 0.5) * 0.015, y)
                mark(patch(c.applying(p.body), r: step * 0.5, seed: x * 9 + y * 31))
                x += step
            }
            y += step * 0.86
            row += 1
        }
        for i in 0..<9 {
            let k = 0.06 + Double(i) * 0.115
            for w in [-0.022, 0.026] { mark(patch(neck(k + (w > 0 ? 0.05 : 0), w), r: 0.028, seed: Double(i) + w * 40 + 3)) }
        }
    }

    private func patch(_ c: CGPoint, r: Double, seed: Double) -> CGPath {
        let pts = (0..<6).map { i -> CGPoint in
            let a = Double(i) / 6 * 2 * .pi + seed
            let k = 0.8 + 0.3 * ScenePaint.noise(Double(i) * 1.3, seed)
            return c.sceneMoved(cos(a) * r * k, sin(a) * r * k)
        }
        return SceneShape.blob(pts, tension: 0.35)
    }

    override func drawLeg(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {
        super.drawLeg(ctx, p, i, ink, near: near)
        guard !ink.rough, kind == .zebra else { return }
        // Stripes down the legs.
        let colour = near ? coat.mark : ink.dark(coat.mark, 0.2)
        let knee = p.knees[i], foot = p.feet[i]
        let bands = (0..<5).map { k -> [CGPoint] in
            let t = 0.15 + Double(k) * 0.16
            let c = pt(Double(knee.x) + Double(foot.x - knee.x) * t, Double(knee.y) + Double(foot.y - knee.y) * t)
            let half = (i % 2 == 0 ? build.hindWidths.1 : build.foreWidths.1) * (1 - t * 0.3)
            return [c.sceneMoved(-half, 0.005), c.sceneMoved(half, -0.005)]
        }
        ink.lines(ctx, bands, colour, width: 0.013)
    }

    override func drawFoot(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {
        hoof(ctx, p.feet[i], kind == .zebra ? 0.03 : 0.024, coat.hoof, ink, near: near, tip: p.lifts[i])
    }

    override func drawTail(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let swing = p.tail * 0.18 + (a.phase == .fleeing ? 0.35 : 0)
        let length = kind == .zebra ? 0.30 : 0.26
        let root = p.tailRoot
        let mid = root.sceneMoved(-0.05 - swing * 0.15, -length * 0.5)
        let end = root.sceneMoved(-0.04 - swing * 0.4, -length + abs(swing) * 0.08)
        ink.volume(ctx, SceneShape.tube([root, mid, end], [0.018, 0.012, 0.009]), coat.base, rim: 0.4)
        let k = kind == .zebra ? 1.0 : 0.6
        let tuft = SceneShape.blob([end.sceneMoved(0.02 * k, 0.03 * k), end.sceneMoved(0.025 * k, -0.05 * k), end.sceneMoved(0, -0.09 * k), end.sceneMoved(-0.03 * k, -0.05 * k),
                                    end.sceneMoved(-0.02 * k, 0.03 * k)], tension: 0.8)
        ink.volume(ctx, tuft, kind == .zebra ? 0x1C1917 : 0x2A1A12, rim: 0.4)
    }

    override func drawHead(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let neck = neckTop(p)
        ctx.saveGState()
        ctx.translateBy(x: neck.top.x, y: neck.top.y)
        let tilt = p.headAngle - neck.bow * 0.6 - (kind == .zebra ? 0.75 : 0.55)
        ctx.rotate(by: CGFloat(tilt))
        kind == .zebra ? zebraHead(ctx, p, ink) : giraffeHead(ctx, p, ink)
        ctx.restoreGState()
    }

    private func zebraHead(_ ctx: CGContext, _ p: SceneQuadPose, _ ink: SceneInk) {
        let ear = SceneShape.blob([pt(-0.035, 0.03), pt(-0.06, 0.1), pt(-0.045, 0.15), pt(-0.015, 0.1), pt(0.0, 0.035)])
        ctx.saveGState()
        ctx.rotate(by: CGFloat(p.ears < 0 ? 0.7 : -0.1 * p.ears - 0.2 * p.earTwitch))
        ink.volume(ctx, ear, coat.base, rim: 0.6)
        ink.flat(ctx, SceneShape.ellipse(pt(-0.04, 0.11), 0.008, 0.03), coat.mark)
        ctx.restoreGState()
        let mouth = p.mouth
        let head = SceneShape.blob([pt(-0.04, 0.0), pt(-0.02, 0.05), pt(0.06, 0.062), pt(0.17, 0.04), pt(0.245, 0.02), pt(0.27, -0.01),
                                    pt(0.25, -0.045 - mouth * 0.02), pt(0.17, -0.05), pt(0.06, -0.055), pt(-0.02, -0.04)])
        ink.volume(ctx, head, coat.base, rim: 1)
        ink.inside(ctx, head) {
            for i in 0..<6 {
                let x = 0.0 + Double(i) * 0.03
                ink.flat(ctx, SceneShape.tube([pt(x - 0.01, 0.07), pt(x + 0.005, 0.0), pt(x - 0.005, -0.06)], [0.006, 0.008, 0.006]), coat.mark)
            }
            ink.flat(ctx, SceneShape.ellipse(pt(0.25, -0.012), 0.06, 0.05), coat.muzzle)
        }
        ink.flat(ctx, SceneShape.ellipse(pt(0.25, 0.0), 0.009, 0.006), 0x0A0808)
        ink.eye(ctx, at: pt(0.045, 0.02), r: 0.014, iris: 0x2A1A12, skin: coat.base, blink: p.blink, pupil: 0.6)
    }

    private func giraffeHead(_ ctx: CGContext, _ p: SceneQuadPose, _ ink: SceneInk) {
        // Ossicones, ears, the long face with a dark muzzle.
        for x in [-0.005, 0.02] {
            ink.volume(ctx, SceneShape.limb(pt(x, 0.03), pt(x - 0.012, 0.075), 0.007, 0.006), coat.base, rim: 0.4)
            ink.flat(ctx, SceneShape.ellipse(pt(x - 0.012, 0.078), 0.011, 0.01), 0x2A1A14)
        }
        ctx.saveGState()
        ctx.translateBy(x: -0.02, y: 0.02)
        ctx.rotate(by: CGFloat(0.5 - 0.3 * p.earTwitch + (p.ears < 0 ? 0.5 : 0)))
        ink.volume(ctx, SceneShape.blob([pt(0, 0.008), pt(-0.06, 0.012), pt(-0.07, 0.0), pt(-0.06, -0.01), pt(0, -0.008)]), coat.base, rim: 0.4)
        ctx.restoreGState()
        let head = SceneShape.blob([pt(-0.035, 0.0), pt(-0.02, 0.035), pt(0.04, 0.04), pt(0.11, 0.025), pt(0.145, 0.0), pt(0.14, -0.03),
                                    pt(0.09, -0.04), pt(0.02, -0.035), pt(-0.03, -0.025)])
        ink.volume(ctx, head, coat.base, rim: 1)
        ink.inside(ctx, head) {
            ink.flat(ctx, SceneShape.ellipse(pt(0.135, -0.01), 0.04, 0.04), ScenePaint.mixHex(coat.base, coat.muzzle, 0.35))
            ink.flat(ctx, SceneShape.ellipse(pt(0.02, 0.0), 0.02, 0.018), coat.mark, alpha: 0.8)
        }
        ink.flat(ctx, SceneShape.ellipse(pt(0.135, 0.002), 0.006, 0.004), 0x1A1210)
        ink.eye(ctx, at: pt(0.045, 0.012), r: 0.012, iris: 0x24160E, skin: coat.base, blink: p.blink, pupil: 0.6)
        if !ink.rough {
            ink.line(ctx, SceneShape.curve([pt(0.03, 0.03), pt(0.05, 0.034), pt(0.065, 0.028)]), 0x24160E, width: Double(ink.px(1.6)))
        }
    }
}

/// The elephant: pillar legs, a great fanning ear, a trunk that swings, curls and lifts to trumpet.
final class SceneElephant: SceneQuadruped {
    private let skin: UInt32 = 0x8E827C

    override init() {
        super.init()
        var b = SceneQuadBuild()
        b.hip = pt(-0.33, 0.45); b.shoulder = pt(0.15, 0.47)
        b.hindUpper = 0.24; b.hindLower = 0.235; b.foreUpper = 0.245; b.foreLower = 0.24
        b.hindWidths = (0.12, 0.094, 0.088); b.foreWidths = (0.115, 0.092, 0.088)
        b.farShift = -0.05
        b.neck = pt(0.30, 0.70); b.tailRoot = pt(-0.50, 0.70); b.middle = pt(-0.1, 0.6)
        b.footLift = 0.045; b.strideScale = 0.7
        build = b
    }

    override func legColour(hind: Bool) -> UInt32 { skin }

    /// A round heavy foot with three pale nails at the front.
    static func pad(_ ctx: CGContext, _ f: CGPoint, _ r: Double, _ skin: UInt32, _ ink: SceneInk, near: Bool) {
        let path = SceneShape.blob([pt(-r, 0.004), pt(-r * 0.98, r * 0.5), pt(0, r * 0.62), pt(r * 1.02, r * 0.5), pt(r * 1.04, 0.004), pt(0, -r * 0.08)]
            .map { $0.sceneMoved(Double(f.x), Double(f.y)) })
        ink.volume(ctx, path, near ? ink.dark(skin, 0.1) : ink.dark(skin, 0.32), rim: 0, light: near)
        guard near, !ink.rough else { return }
        ctx.setFillColor(ink.tone(0xE4D8C4))
        for k in 0..<3 {
            let x = Double(f.x) + r * (0.05 + Double(k) * 0.36)
            ctx.fillEllipse(in: CGRect(x: x - r * 0.15, y: Double(f.y) + 0.002, width: r * 0.3, height: r * 0.22))
        }
    }

    override func drawLeg(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {
        super.drawLeg(ctx, p, i, ink, near: near)
        guard !ink.rough, near else { return }
        // Wrinkles round the knee.
        let knee = p.knees[i]
        ink.lines(ctx, (0..<3).map { k -> [CGPoint] in
            let y = Double(knee.y) - 0.02 + Double(k) * 0.025
            return [pt(Double(knee.x) - 0.06, y + 0.005), pt(Double(knee.x), y - 0.008), pt(Double(knee.x) + 0.06, y + 0.004)]
        }, ink.dark(skin, 0.4), width: Double(ink.px(1.5)), alpha: 0.6)
    }

    override func drawFoot(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {
        Self.pad(ctx, p.feet[i], 0.092, skin, ink, near: near)
    }

    override func drawTail(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let r = p.tailRoot
        let swing = p.tail * 0.1
        let end = r.sceneMoved(-0.06 - swing, -0.30)
        ink.volume(ctx, SceneShape.tube([r, r.sceneMoved(-0.05 - swing * 0.4, -0.15), end], [0.016, 0.01, 0.008]), skin, rim: 0.3)
        ink.flat(ctx, SceneShape.blob([end.sceneMoved(-0.012, 0.02), end.sceneMoved(0.014, 0.01), end.sceneMoved(0.01, -0.05), end.sceneMoved(-0.016, -0.04)]), 0x3A302C)
    }

    override func drawBody(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let body = bodyPath([pt(0.32, 0.62), pt(0.26, 0.40), pt(0.10, 0.33), pt(-0.12, 0.32), pt(-0.34, 0.35), pt(-0.48, 0.44), pt(-0.53, 0.60),
                             pt(-0.46, 0.76), pt(-0.26, 0.82), pt(-0.02, 0.84), pt(0.16, 0.87), pt(0.30, 0.82)], p)
        ink.volume(ctx, body, skin, rim: 1.1)
        guard !ink.rough else { return }
        ink.inside(ctx, body) {
            ink.lines(ctx, (0..<5).map { k -> [CGPoint] in
                let x = -0.4 + Double(k) * 0.16
                return [pt(x, 0.7), pt(x + 0.02, 0.55), pt(x - 0.01, 0.40)].map { $0.applying(p.body) }
            }, ink.dark(skin, 0.3), width: Double(ink.px(1.3)), alpha: 0.35)
        }
    }

    override func drawHead(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let trumpet = a.phase == .acting && a.act == .trumpet ? a.acting(rise: 0.35, fall: 0.6) : 0
        inHead(ctx, p, angle: -p.headAngle * 0.5) {
            // The head dome, the far tusk, the trunk, the near tusk, then the ear over the top of it all.
            let head = SceneShape.blob([pt(-0.10, 0.10), pt(-0.02, 0.21), pt(0.12, 0.22), pt(0.22, 0.14), pt(0.26, 0.02), pt(0.24, -0.10),
                                        pt(0.14, -0.16), pt(0.02, -0.14), pt(-0.10, -0.04)])
            trunk(ctx, a, p, ink, trumpet: trumpet)
            ink.volume(ctx, head, skin, rim: 1)
            if p.mouth > 0.05 {
                ink.flat(ctx, SceneShape.ellipse(pt(0.15, -0.13), 0.04, 0.02 + 0.03 * p.mouth), 0x5A2028)
            }
            tusk(ctx, ink, near: true)
            ink.eye(ctx, at: pt(0.14, 0.06), r: 0.016, iris: 0x3A2414, skin: skin, blink: p.blink, pupil: 0.6)
            if !ink.rough {
                ink.line(ctx, SceneShape.curve([pt(0.11, 0.085), pt(0.145, 0.095), pt(0.175, 0.08)]), ink.dark(skin, 0.5), width: Double(ink.px(1.6)), alpha: 0.8)
                ink.line(ctx, SceneShape.curve([pt(0.12, 0.035), pt(0.15, 0.03), pt(0.17, 0.04)]), ink.dark(skin, 0.4), width: Double(ink.px(1.2)), alpha: 0.6)
            }
            ear(ctx, a, p, ink, spread: trumpet)
        }
    }

    private func tusk(_ ctx: CGContext, _ ink: SceneInk, near: Bool) {
        let path = SceneShape.tube([pt(0.17, -0.10), pt(0.25, -0.17), pt(0.33, -0.17), pt(0.37, -0.13)], [0.02, 0.017, 0.012, 0.004])
        ink.volume(ctx, path, 0xF4ECD8, rim: 0.6, edge: 0.8)
    }

    private func trunk(_ ctx: CGContext, _ a: SceneActor, _ p: SceneQuadPose, _ ink: SceneInk, trumpet: Double) {
        // A chain of segments: hanging and swaying at rest, curled up and out to trumpet.
        let n = 10
        var spine: [CGPoint] = []
        var radii: [Double] = []
        var point = pt(0.22, -0.02)
        var angle = -1.45 + 0.25 * trumpet
        let sway = sin(a.time * 1.4 + a.quirk * 6) * 0.04 + a.walk * 0.05 * sin(a.stride * 2)
        let length = 0.5
        for i in 0..<n {
            let k = Double(i) / Double(n - 1)
            spine.append(point)
            radii.append(0.06 * (1 - 0.62 * k))
            angle += (0.05 + sway) * (1 - trumpet) + trumpet * 0.36 * (k < 0.75 ? 1 : -0.5) + (1 - trumpet) * (k > 0.7 ? 0.22 : 0)
            point = point.sceneMoved(cos(angle) * length / Double(n - 1), sin(angle) * length / Double(n - 1))
        }
        let path = SceneShape.tube(spine, radii)
        ink.volume(ctx, path, skin, rim: 0.8)
        if !ink.rough {
            ink.inside(ctx, path) {
                ink.lines(ctx, (1..<(n - 1)).map { i -> [CGPoint] in
                    let c = spine[i], r = radii[i]
                    let next = spine[i + 1]
                    let dx = Double(next.x - c.x), dy = Double(next.y - c.y)
                    let len = max(1e-6, hypot(dx, dy))
                    let nx = -dy / len, ny = dx / len
                    return [c.sceneMoved(nx * r, ny * r), c.sceneMoved(nx * r * 0.2 + dx / len * 0.008, ny * r * 0.2 + dy / len * 0.008)]
                }, ink.dark(skin, 0.45), width: Double(ink.px(1.3)), alpha: 0.6)
            }
        }
    }

    private func ear(_ ctx: CGContext, _ a: SceneActor, _ p: SceneQuadPose, _ ink: SceneInk, spread: Double) {
        // The ear fans slowly to keep cool, and flares out wide in a trumpet or a scare.
        let fan = 0.5 + 0.5 * sin(a.time * 1.1 + a.quirk * 4)
        let open = max(spread, a.isScared ? 0.8 : 0, 0.15 * fan)
        ctx.saveGState()
        ctx.translateBy(x: 0.04, y: 0.12)
        ctx.scaleBy(x: CGFloat(1 + 0.25 * open), y: 1)
        ctx.rotate(by: CGFloat(-0.05 * fan - 0.2 * open))
        let path = SceneShape.blob([pt(0.0, 0.02), pt(-0.10, 0.06), pt(-0.20, 0.02), pt(-0.23, -0.12), pt(-0.18, -0.28), pt(-0.10, -0.34),
                                    pt(-0.04, -0.28), pt(0.02, -0.16), pt(0.03, -0.05)])
        ink.volume(ctx, path, ScenePaint.mixHex(skin, 0xB8A098, 0.25), rim: 1.1)
        if !ink.rough {
            ink.inside(ctx, path) {
                ink.flat(ctx, SceneShape.blob([pt(-0.03, -0.02), pt(-0.12, 0.0), pt(-0.18, -0.10), pt(-0.15, -0.24), pt(-0.08, -0.27), pt(-0.02, -0.16)]), 0xC89A92, alpha: 0.35)
                ink.lines(ctx, (0..<3).map { k -> [CGPoint] in
                    [pt(-0.02, -0.05 - Double(k) * 0.07), pt(-0.09, -0.06 - Double(k) * 0.08), pt(-0.15, -0.04 - Double(k) * 0.1)]
                }, ink.dark(skin, 0.3), width: Double(ink.px(1.2)), alpha: 0.4)
            }
        }
        ctx.restoreGState()
    }
}

/// Heavy grazers that lower their heads and charge: a rhino with two horns, a buffalo with a great boss of horn.
final class SceneHeavy: SceneQuadruped {
    enum Kind { case rhino, buffalo }
    private let kind: Kind
    private let skin: UInt32

    init(_ kind: Kind) {
        self.kind = kind
        skin = kind == .rhino ? 0x8C827A : 0x4A3C36
        super.init()
        var b = SceneQuadBuild()
        switch kind {
        case .rhino:
            b.hip = pt(-0.40, 0.43); b.shoulder = pt(0.14, 0.43)
            b.hindUpper = 0.22; b.hindLower = 0.22; b.foreUpper = 0.215; b.foreLower = 0.225
            b.hindWidths = (0.11, 0.075, 0.068); b.foreWidths = (0.1, 0.072, 0.068)
            b.neck = pt(0.28, 0.55); b.tailRoot = pt(-0.60, 0.66); b.middle = pt(-0.15, 0.55)
            b.footLift = 0.06; b.strideScale = 0.85
        case .buffalo:
            b.hip = pt(-0.34, 0.47); b.shoulder = pt(0.12, 0.47)
            b.hindUpper = 0.24; b.hindLower = 0.25; b.foreUpper = 0.24; b.foreLower = 0.25
            b.hindWidths = (0.10, 0.05, 0.04); b.foreWidths = (0.09, 0.05, 0.042)
            b.neck = pt(0.24, 0.62); b.tailRoot = pt(-0.50, 0.70); b.middle = pt(-0.12, 0.6)
            b.footLift = 0.07
        }
        build = b
    }

    override func legColour(hind: Bool) -> UInt32 { skin }

    override func drawFoot(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {
        if kind == .buffalo {
            hoof(ctx, p.feet[i], 0.04, 0x221A16, ink, near: near, tip: p.lifts[i])
        } else {
            SceneElephant.pad(ctx, p.feet[i], 0.072, skin, ink, near: near)
        }
    }

    override func drawTail(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let r = p.tailRoot
        let swing = p.tail * 0.15 + (a.phase == .fleeing ? 0.3 : 0)
        let end = r.sceneMoved(-0.05 - swing * 0.3, -0.28 + abs(swing) * 0.05)
        ink.volume(ctx, SceneShape.tube([r, r.sceneMoved(-0.04 - swing * 0.1, -0.14), end], [0.014, 0.01, 0.008]), skin, rim: 0.3)
        ink.flat(ctx, SceneShape.blob([end.sceneMoved(-0.014, 0.02), end.sceneMoved(0.014, 0.01), end.sceneMoved(0.008, -0.05), end.sceneMoved(-0.016, -0.04)]), 0x221A16)
    }

    override func drawBody(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let outline: [CGPoint]
        switch kind {
        case .rhino:
            outline = [pt(0.34, 0.56), pt(0.28, 0.38), pt(0.12, 0.31), pt(-0.14, 0.30), pt(-0.40, 0.32), pt(-0.58, 0.40), pt(-0.65, 0.56), pt(-0.58, 0.70),
                       pt(-0.38, 0.76), pt(-0.12, 0.74), pt(0.10, 0.78), pt(0.28, 0.72)]
        case .buffalo:
            outline = [pt(0.30, 0.62), pt(0.24, 0.43), pt(0.10, 0.38), pt(-0.14, 0.38), pt(-0.36, 0.40), pt(-0.50, 0.50), pt(-0.53, 0.64), pt(-0.46, 0.75),
                       pt(-0.24, 0.77), pt(-0.02, 0.82), pt(0.12, 0.88), pt(0.26, 0.80)]
        }
        let body = bodyPath(outline, p)
        ink.volume(ctx, body, skin, rim: 1.1)
        guard !ink.rough else { return }
        ink.inside(ctx, body) {
            if kind == .rhino {
                // The folds of armour-like skin at the shoulder and the flank.
                for (x, bend) in [(0.08, 0.03), (-0.36, -0.03)] {
                    ink.line(ctx, SceneShape.curve([pt(x, 0.77), pt(x + bend, 0.6), pt(x - bend * 0.5, 0.42), pt(x + 0.02, 0.32)].map { $0.applying(p.body) }),
                             ink.dark(skin, 0.45), width: Double(ink.px(2)), alpha: 0.7)
                }
                ink.line(ctx, SceneShape.curve([pt(-0.55, 0.5), pt(-0.2, 0.42), pt(0.12, 0.44)].map { $0.applying(p.body) }), ink.dark(skin, 0.4), width: Double(ink.px(1.4)), alpha: 0.4)
            } else {
                ink.lines(ctx, (0..<10).map { i -> [CGPoint] in
                    let x = -0.48 + Double(i) * 0.08
                    return [pt(x, 0.78), pt(x - 0.01, 0.62)].map { $0.applying(p.body) }
                }, ink.lit(skin, 0.25), width: Double(ink.px(1.4)), alpha: 0.35)
            }
        }
    }

    override func drawHead(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        inHead(ctx, p, angle: -0.25) {
            kind == .rhino ? rhinoHead(ctx, p, a, ink) : buffaloHead(ctx, p, a, ink)
        }
    }

    private func rhinoHead(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let earBase = pt(0.02, 0.12)
        ctx.saveGState()
        ctx.translateBy(x: earBase.x, y: earBase.y)
        ctx.rotate(by: CGFloat(0.2 - 0.3 * p.earTwitch + (p.ears < 0 ? 0.6 : -0.1 * p.ears)))
        let ear = SceneShape.blob([pt(-0.02, 0), pt(-0.035, 0.06), pt(-0.01, 0.1), pt(0.02, 0.06), pt(0.02, 0)])
        ink.volume(ctx, ear, skin, rim: 0.6)
        ctx.restoreGState()
        let head = SceneShape.blob([pt(-0.06, 0.06), pt(0.02, 0.13), pt(0.14, 0.10), pt(0.26, 0.04), pt(0.34, -0.04), pt(0.35, -0.10),
                                    pt(0.30, -0.14), pt(0.18, -0.13), pt(0.04, -0.09), pt(-0.06, -0.04)])
        ink.volume(ctx, head, skin, rim: 1)
        // Two horns, the big one at the end of the nose.
        let big = SceneShape.blob([pt(0.25, 0.03), pt(0.30, 0.10), pt(0.33, 0.20), pt(0.335, 0.21), pt(0.34, 0.10), pt(0.345, -0.01)], tension: 0.7)
        ink.volume(ctx, big, 0xC8BAA4, rim: 0.7)
        let small = SceneShape.blob([pt(0.16, 0.08), pt(0.19, 0.13), pt(0.205, 0.16), pt(0.215, 0.11), pt(0.225, 0.065)], tension: 0.7)
        ink.volume(ctx, small, 0xBCAE98, rim: 0.6)
        ink.eye(ctx, at: pt(0.10, 0.05), r: 0.013, iris: 0x2A1A12, skin: skin, blink: p.blink, pupil: 0.6)
        if !ink.rough {
            ink.line(ctx, SceneShape.curve([pt(0.27, -0.10), pt(0.31, -0.115), pt(0.34, -0.10)]), ink.dark(skin, 0.6), width: Double(ink.px(1.5)))
            ink.line(ctx, SceneShape.curve([pt(0.04, -0.02), pt(0.08, -0.06), pt(0.06, -0.10)]), ink.dark(skin, 0.4), width: Double(ink.px(1.5)), alpha: 0.6)
            ink.flat(ctx, SceneShape.ellipse(pt(0.33, -0.065), 0.01, 0.006), 0x2A2220)
        }
    }

    private func buffaloHead(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let head = SceneShape.blob([pt(-0.05, 0.08), pt(0.04, 0.12), pt(0.14, 0.08), pt(0.24, -0.02), pt(0.27, -0.12), pt(0.22, -0.17),
                                    pt(0.12, -0.14), pt(0.02, -0.06)])
        ink.volume(ctx, head, skin, rim: 1)
        ink.inside(ctx, head) { ink.flat(ctx, SceneShape.ellipse(pt(0.24, -0.13), 0.05, 0.05), 0x2A201C) }
        // The ear hangs out under the horn.
        ctx.saveGState()
        ctx.translateBy(x: 0.0, y: 0.04)
        ctx.rotate(by: CGFloat(-0.2 - 0.25 * p.earTwitch))
        ink.volume(ctx, SceneShape.blob([pt(0, 0.015), pt(-0.09, 0.02), pt(-0.12, -0.0), pt(-0.09, -0.02), pt(0, -0.015)]), ScenePaint.mixHex(skin, 0x7A6050, 0.4), rim: 0.5)
        ctx.restoreGState()
        // The boss of horn across the brow, sweeping down, out and up to a point.
        let horn = SceneShape.blob([pt(-0.02, 0.10), pt(0.06, 0.135), pt(0.12, 0.11), pt(0.05, 0.075), pt(-0.06, 0.04), pt(-0.15, 0.0), pt(-0.20, 0.04),
                                    pt(-0.19, 0.12), pt(-0.21, 0.14), pt(-0.235, 0.09), pt(-0.22, -0.01), pt(-0.15, -0.04), pt(-0.06, 0.0)], tension: 0.8)
        ink.volume(ctx, horn, 0x3A322E, rim: 1)
        if !ink.rough {
            ink.inside(ctx, horn) {
                ink.lines(ctx, (0..<4).map { k -> [CGPoint] in let x = -0.02 - Double(k) * 0.045; return [pt(x, 0.13), pt(x - 0.01, 0.0)] },
                          0x7A6E66, width: Double(ink.px(1.2)), alpha: 0.5)
            }
        }
        ink.eye(ctx, at: pt(0.11, 0.0), r: 0.013, iris: 0x3A1A10, skin: skin, blink: p.blink, pupil: 0.6)
    }
}
