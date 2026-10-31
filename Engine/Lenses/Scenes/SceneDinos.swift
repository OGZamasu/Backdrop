import CoreGraphics
import Foundation

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// Two-legged dinosaurs balanced over their hips: a T-rex, a feathered raptor, a big-headed baby rex and a tiny hopping compy.
/// The tail swings to balance each step, the head bobs, the jaw drops to roar.
final class SceneTheropod: ScenePuppet {
    enum Kind { case trex, raptor, baby, compy }
    private let kind: Kind
    private struct Look {
        var skin: UInt32
        var back: UInt32
        var belly: UInt32
        var stripe: UInt32
        var eye: UInt32
        var head: Double
        var hip: CGPoint
        var thigh: Double, shin: Double, foot: Double
        var legWidth: Double
        var tail: Double
    }
    private let look: Look

    init(_ kind: Kind) {
        self.kind = kind
        switch kind {
        case .trex: look = Look(skin: 0x5E7A3A, back: 0x445C2A, belly: 0xCCBC86, stripe: 0x34481E, eye: 0xE8A020, head: 1.0, hip: pt(-0.06, 0.52),
                                thigh: 0.26, shin: 0.24, foot: 0.1, legWidth: 0.11, tail: 0.95)
        case .raptor: look = Look(skin: 0xB8682E, back: 0x8A4A22, belly: 0xE8C898, stripe: 0x4A2A16, eye: 0xF0C020, head: 0.95, hip: pt(-0.04, 0.5),
                                  thigh: 0.24, shin: 0.25, foot: 0.12, legWidth: 0.1, tail: 0.72)
        case .baby: look = Look(skin: 0x84B44E, back: 0x6A9A3A, belly: 0xF0E2A8, stripe: 0x557E2E, eye: 0x6A3A14, head: 1.5, hip: pt(-0.06, 0.4),
                                thigh: 0.19, shin: 0.17, foot: 0.08, legWidth: 0.1, tail: 0.6)
        case .compy: look = Look(skin: 0xA2B84A, back: 0x7A9238, belly: 0xF0E8B8, stripe: 0x5A7228, eye: 0xD87A20, head: 0.8, hip: pt(-0.04, 0.48),
                                 thigh: 0.22, shin: 0.22, foot: 0.1, legWidth: 0.07, tail: 0.85)
        }
    }

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let cycle = (a.backwards ? -1 : 1) * a.stride / (2 * .pi) * (kind == .compy ? 0.5 : 1)
        let walk = a.walk, run = a.run
        let roar = a.phase == .acting && (a.act == .roar) ? a.acting(rise: 0.3, fall: 0.5) : 0
        let hopping = a.lift > 0.01
        let bob = walk * 0.02 * cos(4 * .pi * cycle) * (1 + run) - roar * 0.02
        let lean = run * 0.12 + roar * 0.1 - (a.phase == .noticing ? 0.06 : 0)
        let hip = look.hip.sceneMoved(0, bob)
        func body(_ q: CGPoint) -> CGPoint { q.sceneTurned(about: look.hip, by: -lean + roar * 0.12).sceneMoved(0, bob) }

        // Legs: far one first. Each foot plants and swings like a bird's.
        var feet: [(CGPoint, CGPoint, CGPoint)] = []
        for i in 0..<2 {
            let w = SceneRig.foot(cycle + Double(i) * 0.5, duty: run > 0.5 ? 0.4 : 0.6)
            let stride = 0.84 * (run > 0.5 ? 0.42 : 0.6) * 0.9
            var foot = pt(Double(hip.x) + 0.04 + w.forward * stride * walk, w.up * 0.1 * walk * (1 + run))
            if hopping { foot = pt(Double(hip.x) + (i == 0 ? -0.06 : 0.08), max(0, Double(hip.y) - look.thigh - look.shin - 0.02) + 0.06) }
            let ankleTarget = foot.sceneMoved(-look.foot * 0.55, look.foot * 0.85)
            let root = hip.sceneMoved(i == 0 ? -0.03 : 0, i == 0 ? 0.01 : 0)
            let knee = SceneRig.knee(root, ankleTarget, upper: look.thigh, lower: look.shin, bend: 1)
            let ankle = SceneRig.reach(knee, ankleTarget, lower: look.shin)
            feet.append((root, knee, ankle))
            _ = foot
        }
        func leg(_ i: Int, near: Bool) {
            let (root, knee, ankle) = feet[i]
            let colour = near ? look.skin : ink.dark(look.skin, 0.3)
            let w = look.legWidth
            let toe = ankle.sceneMoved(look.foot * 0.62, -look.foot * 0.85)
            ink.volume(ctx, SceneShape.limb(ankle, toe, w * 0.32, w * 0.24), colour, rim: near ? 0.4 : 0, light: near)
            ink.volume(ctx, SceneShape.limb(knee, ankle, w * 0.5, w * 0.32), colour, rim: near ? 0.5 : 0, light: near)
            ink.volume(ctx, SceneShape.limb(root, knee, w * 1.15, w * 0.5), colour, rim: near ? 0.8 : 0, light: near)
            // Toes and claws.
            let claw = near ? 0x2A241E : ink.dark(0x2A241E, 0.2)
            let foot = SceneShape.blob([toe.sceneMoved(-w * 0.35, w * 0.12), toe.sceneMoved(w * 0.75, w * 0.08), toe.sceneMoved(w * 0.95, -w * 0.18), toe.sceneMoved(-w * 0.3, -w * 0.2)])
            ink.volume(ctx, foot, colour, rim: 0.3, light: near)
            ink.flat(ctx, SceneShape.blob([toe.sceneMoved(w * 0.8, -w * 0.02), toe.sceneMoved(w * 1.1, -w * 0.2), toe.sceneMoved(w * 0.85, -w * 0.18)]), claw)
            if kind == .raptor {
                ink.flat(ctx, SceneShape.blob([toe.sceneMoved(w * 0.1, w * 0.05), toe.sceneMoved(w * 0.5, w * 0.35), toe.sceneMoved(w * 0.25, w * 0.02)]), claw)
            }
        }
        leg(0, near: false)

        // The tail: a long tapering tube that sways to balance the steps.
        let n = 9
        var spine: [CGPoint] = []
        var radii: [Double] = []
        let sway = sin(4 * .pi * cycle + 1) * 0.04 * walk + a.tail * 0.05
        for i in 0..<n {
            let k = Double(i) / Double(n - 1)
            let x = -0.12 - k * look.tail
            let y = 0.58 - k * 0.1 + sway * k * k + (kind == .raptor ? k * 0.06 : 0) + roar * 0.08 * k
            spine.append(body(pt(x, y + Double(look.hip.y) - 0.5)))
            radii.append((kind == .trex ? 0.13 : kind == .baby ? 0.11 : kind == .raptor ? 0.1 : 0.08) * (1 - 0.88 * k))
        }
        let tail = SceneShape.tube(spine, radii)
        ink.volume(ctx, tail, look.skin, rim: 0.9)

        // The body, egg-shaped, tipped forward.
        let y0 = Double(look.hip.y) - 0.5
        let torso: [CGPoint]
        switch kind {
        case .trex: torso = [pt(0.34, 0.66), pt(0.26, 0.48), pt(0.08, 0.40), pt(-0.12, 0.42), pt(-0.22, 0.56), pt(-0.12, 0.72), pt(0.08, 0.80), pt(0.28, 0.80)]
        case .raptor, .compy: torso = [pt(0.28, 0.66), pt(0.22, 0.49), pt(0.04, 0.42), pt(-0.14, 0.44), pt(-0.21, 0.56), pt(-0.1, 0.68), pt(0.1, 0.71), pt(0.24, 0.72)]
        case .baby: torso = [pt(0.24, 0.6), pt(0.2, 0.42), pt(0.04, 0.34), pt(-0.14, 0.36), pt(-0.22, 0.5), pt(-0.12, 0.64), pt(0.06, 0.7), pt(0.2, 0.7)]
        }
        let torsoPath = SceneShape.blob(torso.map { body($0.sceneMoved(0, y0)) })
        ink.volume(ctx, torsoPath, look.skin, rim: 1.1)
        ink.inside(ctx, torsoPath) {
            ink.flat(ctx, SceneShape.ellipse(body(pt(0.14, 0.46 + y0)), 0.2, 0.08), look.belly, alpha: 0.9)
            stripes(ctx, ink, along: [pt(-0.16, 0.66), pt(0.0, 0.74), pt(0.18, 0.76)].map { body($0.sceneMoved(0, y0)) })
        }
        ink.inside(ctx, tail) {
            ink.flat(ctx, SceneShape.tube(spine.map { $0.sceneMoved(0, -0.05) }, radii.map { $0 * 0.6 }), look.belly, alpha: 0.7)
            stripes(ctx, ink, along: Array(spine.prefix(6)))
        }
        if kind == .raptor, !ink.rough { feathers(ctx, ink, a, along: Array(spine.suffix(4))) }
        arms(ctx, ink, a, at: body(pt(kind == .baby ? 0.2 : 0.24, (kind == .trex ? 0.56 : 0.52) + y0)), far: false, roar: roar)
        leg(1, near: true)

        // The head on its neck, nodding with the steps, thrown up and open to roar.
        let neck = body(pt(kind == .trex ? 0.34 : 0.24, (kind == .trex ? 0.78 : 0.68) + y0))
        let nod = walk * 0.05 * sin(4 * .pi * cycle) + (1 - walk) * (1 - a.alert) * 0.08 * a.drift(0.3, 3)
        let headUp = roar * (0.35 + 0.03 * sin(a.time * 40)) + a.look * 0.5 * a.alert + nod - (kind == .raptor ? 0.1 : 0)
        ctx.saveGState()
        ctx.translateBy(x: neck.x, y: neck.y)
        ctx.rotate(by: CGFloat(headUp))
        ctx.scaleBy(x: CGFloat(look.head), y: CGFloat(look.head))
        head(ctx, ink, a, open: max(roar, a.act == .hop && a.phase == .acting ? 0.6 * max(0, sin(a.phaseTime * 6)) : 0))
        ctx.restoreGState()
    }

    private func stripes(_ ctx: CGContext, _ ink: SceneInk, along points: [CGPoint]) {
        guard !ink.rough, kind != .compy else { return }
        for (i, p) in points.enumerated() where i % 1 == 0 {
            let w = kind == .raptor ? 0.014 : 0.02
            ink.flat(ctx, SceneShape.tube([p.sceneMoved(0, 0.06), p.sceneMoved(-0.01, 0.0), p.sceneMoved(0.0, -0.06)], [w, w * 0.8, w * 0.1]), look.stripe, alpha: 0.75)
        }
    }

    /// A short crest of dark feathers along the end of the raptor's tail.
    private func feathers(_ ctx: CGContext, _ ink: SceneInk, _ a: SceneActor, along points: [CGPoint]) {
        ink.lines(ctx, points.map { [$0, $0.sceneMoved(-0.05, 0.05)] } + points.map { [$0, $0.sceneMoved(-0.05, -0.035)] }, 0x5A3A22, width: 0.016, alpha: 0.9)
    }

    private func arms(_ ctx: CGContext, _ ink: SceneInk, _ a: SceneActor, at shoulder: CGPoint, far: Bool, roar: Double) {
        let size = kind == .trex ? 0.07 : kind == .baby ? 0.07 : 0.11
        let wave = roar * 0.6 + sin(a.time * 3 + a.quirk * 4) * 0.1
        let elbow = shoulder.sceneMoved(size * 0.6, -size * 0.7 + wave * size * 0.4)
        let hand = elbow.sceneMoved(size * 0.9, size * 0.1 + wave * size * 0.6)
        ink.volume(ctx, SceneShape.limb(shoulder, elbow, size * 0.32, size * 0.22), look.skin, rim: 0.5)
        ink.volume(ctx, SceneShape.limb(elbow, hand, size * 0.22, size * 0.16), look.skin, rim: 0.4)
        if kind == .raptor {
            ink.volume(ctx, SceneShape.blob([shoulder.sceneMoved(0, -0.01), elbow.sceneMoved(0.0, -0.05), hand.sceneMoved(-0.02, -0.08), hand.sceneMoved(0.0, -0.01)]), 0x5A3A22, rim: 0.3)
        }
        ctx.setFillColor(ink.tone(0x2A241E))
        for k in 0..<2 { ctx.fillEllipse(in: CGRect(x: Double(hand.x) + 0.004, y: Double(hand.y) - 0.012 - Double(k) * 0.014, width: 0.016, height: 0.01)) }
    }

    /// The head, in its own frame: origin at the neck, facing right. The lower jaw hinges open.
    private func head(_ ctx: CGContext, _ ink: SceneInk, _ a: SceneActor, open: Double) {
        let hinge = pt(0.04, -0.03)
        let drop = -0.55 * open
        let cute = kind == .baby
        let jaw = SceneShape.blob([pt(0.02, -0.04), pt(0.30, -0.06), pt(0.32, -0.09), pt(0.22, -0.13), pt(0.06, -0.11)].map { $0.sceneTurned(about: hinge, by: drop) })
        if open > 0.04 {
            ink.flat(ctx, SceneShape.blob([hinge.sceneMoved(0.02, 0.01), pt(0.34, -0.03), pt(0.30, -0.08).sceneTurned(about: hinge, by: drop), pt(0.08, -0.1).sceneTurned(about: hinge, by: drop)]), 0x5A1A20)
            ink.flat(ctx, SceneShape.ellipse(pt(0.18, -0.08).sceneTurned(about: hinge, by: drop * 0.7), 0.08, 0.02), 0xC85A68)
        }
        ink.volume(ctx, jaw, ScenePaint.mixHex(look.skin, look.belly, 0.4), rim: 0.4)
        if open > 0.1, !cute {
            ctx.setFillColor(ink.tone(0xF4EEDC))
            for i in 0..<5 {
                let x = 0.10 + Double(i) * 0.045
                let t = pt(x, -0.065).sceneTurned(about: hinge, by: drop)
                ctx.move(to: t.sceneMoved(-0.01, 0)); ctx.addLine(to: t.sceneMoved(0.01, 0)); ctx.addLine(to: t.sceneMoved(0, 0.03)); ctx.fillPath()
            }
        }
        let skull: [CGPoint]
        switch kind {
        case .trex: skull = [pt(-0.04, 0.02), pt(0.0, 0.12), pt(0.12, 0.15), pt(0.22, 0.12), pt(0.34, 0.06), pt(0.38, 0.0), pt(0.36, -0.045), pt(0.18, -0.06), pt(0.02, -0.05)]
        case .raptor, .compy: skull = [pt(-0.04, 0.02), pt(0.02, 0.1), pt(0.12, 0.1), pt(0.26, 0.05), pt(0.36, 0.0), pt(0.35, -0.04), pt(0.18, -0.06), pt(0.02, -0.05)]
        case .baby: skull = [pt(-0.06, 0.02), pt(-0.02, 0.14), pt(0.1, 0.18), pt(0.22, 0.14), pt(0.30, 0.06), pt(0.31, -0.02), pt(0.2, -0.06), pt(0.02, -0.06)]
        }
        let skullPath = SceneShape.blob(skull)
        ink.volume(ctx, skullPath, look.skin, rim: 1)
        ink.inside(ctx, skullPath) {
            ink.flat(ctx, SceneShape.ellipse(pt(0.16, -0.05), 0.2, 0.03), look.belly, alpha: 0.6)
            if !ink.rough, !cute {
                for k in 0..<3 { ink.flat(ctx, SceneShape.ellipse(pt(0.05 + Double(k) * 0.07, 0.11), 0.025, 0.015), look.stripe, alpha: 0.6) }
            }
        }
        if open < 0.1, !ink.rough, !cute {
            // Teeth peeking out along the closed mouth.
            ctx.setFillColor(ink.tone(0xF4EEDC))
            for i in 0..<4 {
                let x = 0.14 + Double(i) * 0.05
                ctx.move(to: pt(x - 0.008, -0.045)); ctx.addLine(to: pt(x + 0.008, -0.045)); ctx.addLine(to: pt(x, -0.065)); ctx.fillPath()
            }
            ink.line(ctx, SceneShape.curve([pt(0.04, -0.045), pt(0.2, -0.05), pt(0.35, -0.04)]), ink.dark(look.skin, 0.6), width: Double(ink.px(1.4)))
        }
        if cute {
            ink.eye(ctx, at: pt(0.14, 0.07), r: 0.045, iris: look.eye, skin: look.skin, blink: a.blink, pupil: 0.55, white: true, look: pt(0.3, 0.1))
        } else {
            ink.eye(ctx, at: pt(0.13, 0.065), r: kind == .trex ? 0.022 : 0.026, iris: look.eye, skin: look.skin, blink: a.blink, pupil: 0.45, slit: true)
            ink.flat(ctx, SceneShape.blob([pt(0.08, 0.09), pt(0.14, 0.11), pt(0.19, 0.09), pt(0.14, 0.085)]), look.back)
        }
        ink.flat(ctx, SceneShape.ellipse(pt(kind == .baby ? 0.28 : 0.33, 0.035), 0.01, 0.006), 0x1A1410)
        if kind == .raptor {
            ink.volume(ctx, SceneShape.blob([pt(-0.04, 0.06), pt(0.0, 0.14), pt(-0.06, 0.18), pt(-0.1, 0.1)]), 0x5A3A22, rim: 0.4)
        }
    }
}

/// A triceratops: a heavy four-legged grazer with a bony frill and three horns, which paws the ground and lowers them at you.
final class SceneTriceratops: SceneQuadruped {
    private let skin: UInt32 = 0x7A8A48
    private let dark: UInt32 = 0x55623A

    override init() {
        super.init()
        var b = SceneQuadBuild()
        b.hip = pt(-0.30, 0.44); b.shoulder = pt(0.12, 0.40)
        b.hindUpper = 0.22; b.hindLower = 0.23; b.foreUpper = 0.19; b.foreLower = 0.21
        b.hindWidths = (0.12, 0.08, 0.065); b.foreWidths = (0.10, 0.07, 0.06)
        b.neck = pt(0.26, 0.50); b.tailRoot = pt(-0.48, 0.58); b.middle = pt(-0.1, 0.5)
        b.footLift = 0.06; b.strideScale = 0.8
        build = b
    }

    override func legColour(hind: Bool) -> UInt32 { skin }

    override func drawFoot(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {
        SceneElephant.pad(ctx, p.feet[i], i % 2 == 0 ? 0.07 : 0.062, skin, ink, near: near)
    }

    override func drawTail(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let r = p.tailRoot
        let s = p.tail * 0.04
        ink.volume(ctx, SceneShape.tube([r, r.sceneMoved(-0.16, -0.06 + s), r.sceneMoved(-0.32, -0.12 + s * 2), r.sceneMoved(-0.42, -0.14 + s * 3)], [0.08, 0.055, 0.03, 0.01]), skin, rim: 0.8)
    }

    override func drawBody(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let body = bodyPath([pt(0.26, 0.52), pt(0.20, 0.34), pt(0.0, 0.28), pt(-0.24, 0.29), pt(-0.44, 0.38), pt(-0.52, 0.54), pt(-0.40, 0.70),
                             pt(-0.18, 0.76), pt(0.04, 0.72), pt(0.22, 0.62)], p)
        ink.volume(ctx, body, skin, rim: 1.1)
        ink.inside(ctx, body) {
            ink.flat(ctx, SceneShape.ellipse(pt(-0.1, 0.30).applying(p.body), 0.32, 0.06), 0xC8C08A, alpha: 0.6)
            guard !ink.rough else { return }
            for i in 0..<9 {
                let c = pt(-0.42 + Double(i) * 0.08, 0.62 + 0.06 * sin(Double(i) * 0.9)).applying(p.body)
                ink.flat(ctx, SceneShape.ellipse(c, 0.035, 0.05), dark, alpha: 0.55)
            }
        }
    }

    override func drawHead(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        inHead(ctx, p, angle: -0.15) {
            // The frill, edged with knobs, rising behind the head.
            let frill = SceneShape.blob([pt(0.02, -0.02), pt(-0.06, 0.18), pt(-0.02, 0.36), pt(0.08, 0.40), pt(0.16, 0.30), pt(0.14, 0.08)])
            ink.volume(ctx, frill, 0xC8603E, rim: 1)
            ink.inside(ctx, frill) {
                ink.flat(ctx, SceneShape.blob([pt(0.04, 0.02), pt(-0.01, 0.18), pt(0.02, 0.3), pt(0.08, 0.32), pt(0.12, 0.24), pt(0.1, 0.06)]), 0xE8A050, alpha: 0.9)
            }
            ctx.setFillColor(ink.tone(0xF0E2B0))
            for i in 0..<8 {
                let ang = 1.75 + Double(i) * 0.3
                let c = pt(0.06 + cos(ang) * 0.12, 0.18 + sin(ang) * 0.21)
                ctx.fillEllipse(in: CGRect(x: Double(c.x) - 0.016, y: Double(c.y) - 0.016, width: 0.032, height: 0.032))
            }
            let head = SceneShape.blob([pt(0.0, 0.02), pt(0.06, 0.1), pt(0.18, 0.08), pt(0.30, 0.0), pt(0.36, -0.08), pt(0.30, -0.13), pt(0.14, -0.12), pt(0.02, -0.08)])
            ink.volume(ctx, head, skin, rim: 1)
            // The beak.
            ink.volume(ctx, SceneShape.blob([pt(0.28, 0.0), pt(0.39, -0.08), pt(0.36, -0.15), pt(0.28, -0.12)], tension: 0.6), 0xD8C890, rim: 0.4)
            // Horns: two long brow horns and a short nose horn.
            for (base, tip, w) in [(pt(0.13, 0.08), pt(0.36, 0.26), 0.028), (pt(0.09, 0.08), pt(0.30, 0.28), 0.024), (pt(0.27, 0.0), pt(0.33, 0.08), 0.02)] {
                ink.volume(ctx, SceneShape.limb(base, tip, w, 0.004), 0xF2EACA, rim: 0.6, edge: 0.8)
            }
            ink.eye(ctx, at: pt(0.15, 0.03), r: 0.018, iris: 0x3A2010, skin: skin, blink: p.blink, pupil: 0.6)
            if p.mouth > 0.05 { ink.flat(ctx, SceneShape.ellipse(pt(0.28, -0.12), 0.04, 0.012 + 0.02 * p.mouth), 0x5A2028) }
        }
    }
}

/// A brontosaurus: an enormous slow walker with a long neck it lowers to look at you, and a long tail behind.
final class SceneSauropod: SceneQuadruped {
    private let skin: UInt32 = 0x6E8A94
    private let belly: UInt32 = 0xC8D0C0

    override init() {
        super.init()
        var b = SceneQuadBuild()
        b.hip = pt(-0.16, 0.30); b.shoulder = pt(0.10, 0.32)
        b.hindUpper = 0.155; b.hindLower = 0.16; b.foreUpper = 0.165; b.foreLower = 0.17
        b.hindWidths = (0.085, 0.068, 0.06); b.foreWidths = (0.075, 0.062, 0.056)
        b.farShift = -0.03
        b.neck = pt(0.16, 0.44); b.tailRoot = pt(-0.30, 0.42); b.middle = pt(-0.04, 0.38)
        b.footLift = 0.035; b.strideScale = 0.45
        build = b
    }

    override func legColour(hind: Bool) -> UInt32 { skin }

    override func drawFoot(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {
        SceneElephant.pad(ctx, p.feet[i], 0.05, skin, ink, near: near)
    }

    override func drawTail(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let r = p.tailRoot
        var spine: [CGPoint] = []
        for i in 0..<9 {
            let k = Double(i) / 8
            spine.append(r.sceneMoved(-k * 0.6, -k * 0.24 + k * k * 0.1 + sin(a.time * 0.9 + k * 3 + a.quirk * 5) * 0.03 * k))
        }
        ink.volume(ctx, SceneShape.tube(spine, (0..<9).map { 0.07 * (1 - 0.9 * Double($0) / 8) }), skin, rim: 0.8)
    }

    /// The neck: a long tube from the shoulders up to the head, which bows down toward you to look.
    private func neckSpine(_ p: SceneQuadPose, _ a: SceneActor) -> [CGPoint] {
        let lean = a.phase == .acting && a.act == .lean ? a.acting(rise: 0.6, fall: 0.6) : 0
        let base = p.neck
        var spine: [CGPoint] = [base]
        var angle = 0.95 + 0.05 * sin(a.time * 0.7 + a.quirk * 3) + p.headAngle * 0.4
        var q = base
        for i in 1..<9 {
            let k = Double(i) / 8
            angle -= (0.02 + lean * 0.16) * (k > 0.3 ? 1 : 0.3)
            q = q.sceneMoved(cos(angle) * 0.075, sin(angle) * 0.075)
            spine.append(q)
        }
        return spine
    }

    override func drawBody(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let spine = neckSpine(p, a)
        let neck = SceneShape.tube(spine, (0..<9).map { 0.07 * (1 - 0.55 * Double($0) / 8) })
        ink.volume(ctx, neck, skin, rim: 1)
        ink.inside(ctx, neck) { ink.flat(ctx, SceneShape.tube(spine.map { $0.sceneMoved(0.03, -0.03) }, (0..<9).map { 0.035 * (1 - 0.5 * Double($0) / 8) }), belly, alpha: 0.6) }
        let body = bodyPath([pt(0.20, 0.42), pt(0.14, 0.26), pt(-0.04, 0.22), pt(-0.22, 0.24), pt(-0.34, 0.34), pt(-0.32, 0.48), pt(-0.16, 0.56), pt(0.04, 0.56), pt(0.18, 0.5)], p)
        ink.volume(ctx, body, skin, rim: 1.1)
        ink.inside(ctx, body) {
            ink.flat(ctx, SceneShape.ellipse(pt(-0.04, 0.24).applying(p.body), 0.22, 0.05), belly, alpha: 0.7)
            guard !ink.rough else { return }
            for i in 0..<6 {
                ink.flat(ctx, SceneShape.ellipse(pt(-0.26 + Double(i) * 0.08, 0.5 + 0.02 * sin(Double(i))).applying(p.body), 0.022, 0.03), 0x52707A, alpha: 0.7)
            }
        }
    }

    override func drawHead(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let spine = neckSpine(p, a)
        guard let top = spine.last else { return }
        let dir = atan2(Double(spine[8].y - spine[7].y), Double(spine[8].x - spine[7].x))
        ctx.saveGState()
        ctx.translateBy(x: top.x, y: top.y)
        ctx.rotate(by: CGFloat(dir * 0.35 - 0.2))
        ctx.scaleBy(x: 1.5, y: 1.5)
        let head = SceneShape.blob([pt(-0.03, 0.02), pt(0.02, 0.06), pt(0.1, 0.05), pt(0.14, 0.0), pt(0.12, -0.03), pt(0.0, -0.035)])
        ink.volume(ctx, head, skin, rim: 1)
        ink.eye(ctx, at: pt(0.045, 0.025), r: 0.011, iris: 0x2A1A10, skin: skin, blink: p.blink, pupil: 0.6)
        if !ink.rough { ink.line(ctx, SceneShape.curve([pt(0.06, -0.01), pt(0.1, -0.012), pt(0.13, -0.004)]), ink.dark(skin, 0.6), width: Double(ink.px(1.4))) }
        ctx.restoreGState()
    }
}
