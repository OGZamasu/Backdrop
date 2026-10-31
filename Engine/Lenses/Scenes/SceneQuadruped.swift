import CoreGraphics
import Foundation

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// Where a four-legged animal's joints are at rest, in units of its full height, facing right with its feet at the origin.
struct SceneQuadBuild {
    var hip = CGPoint(x: -0.42, y: 0.50)
    var shoulder = CGPoint(x: 0.16, y: 0.52)
    var hindUpper = 0.27, hindLower = 0.27
    var foreUpper = 0.26, foreLower = 0.27
    /// Leg thickness: at the top, at the middle joint and at the ankle (radii).
    var hindWidths = (0.10, 0.05, 0.035)
    var foreWidths = (0.08, 0.045, 0.035)
    /// How far the far legs sit from the near ones, so that both pairs read.
    var farShift = -0.035
    /// Where the head turns, at rest.
    var neck = CGPoint(x: 0.30, y: 0.64)
    var tailRoot = CGPoint(x: -0.62, y: 0.60)
    /// The middle of the body, which the body tips and breathes about.
    var middle = CGPoint(x: -0.12, y: 0.52)
    /// How high a foot lifts in a walking step, and the length of the step, as a share of what the walk speed asks for.
    var footLift = 0.08
    var strideScale = 1.0
    /// Plantigrade heavy feet (elephants) bend less.
    var stiffness = 0.0
}

/// One frame's pose for a four-legged animal: everything a species needs to draw itself.
struct SceneQuadPose {
    /// Body-attached points go through this: bob, tip, breathing.
    var body = CGAffineTransform.identity
    /// The leg roots, middle joints and feet, in the order near hind, near fore, far hind, far fore.
    var roots: [CGPoint] = []
    var knees: [CGPoint] = []
    var feet: [CGPoint] = []
    /// How much each foot is off the ground (0...1), to tip hooves and paws.
    var lifts: [Double] = []
    var neck = CGPoint.zero
    /// Radians, positive tips the nose up.
    var headAngle = 0.0
    var mouth = 0.0
    var blink = 0.0
    /// Ears: 0 relaxed, 1 pricked; negative laid back in fear.
    var ears = 0.0
    var earTwitch = 0.0
    /// The tail's swing, -1...1 (up), and how alarmed it is (raised).
    var tail = 0.0
    var crouch = 0.0
    var tailRoot = CGPoint.zero
}

/// The shared bones and motion of every four-legged animal: walk and gallop, standing about, looking at you, flinching. Species
/// draw their own body, head, tail and feet on top of this pose.
class SceneQuadruped: ScenePuppet {
    var build = SceneQuadBuild()

    // MARK: Motion

    func solve(_ a: SceneActor) -> SceneQuadPose {
        let b = build
        var p = SceneQuadPose()
        let cycle = (a.backwards ? -1 : 1) * a.stride / (2 * .pi)
        let walk = a.walk, run = a.run
        let act = a.acting()

        // Stalking: low and slow. Fear: low and fast.
        var crouch = 0.0
        if a.phase == .approaching, a.walk > 0.3, a.run < 0.2, a.alert > 0.5 { crouch = 0.35 }
        if a.phase == .backingOff { crouch = 0.4 }
        if a.act == .lean, a.phase == .acting { crouch = max(crouch, 0.5 * act) }
        p.crouch = crouch

        // The body: a bob with each step, a rock in the gallop, breathing at rest.
        let bob = walk * (1 - run) * 0.012 * cos(4 * .pi * cycle) + run * 0.035 * sin(2 * .pi * cycle) - crouch * 0.06
        let pitch = run * 0.06 * sin(2 * .pi * cycle + 0.6) + roarPitch(a, act) + stompPitch(a)
        let breathe = 1 + 0.012 * a.breath * (1 - walk * 0.7)
        p.body = CGAffineTransform(translationX: 0, y: bob)
            .translatedBy(x: b.middle.x, y: b.middle.y)
            .rotated(by: pitch)
            .scaledBy(x: 1, y: breathe)
            .translatedBy(x: -b.middle.x, y: -b.middle.y)

        // Feet: a lateral walk (hind, fore, other hind, other fore), or a rotary gallop.
        let walkPhases = [0.0, 0.25, 0.5, 0.75], runPhases = [0.0, 0.44, 0.1, 0.56]
        let walkStride = 0.84 * 0.62 * b.strideScale, runStride = 0.84 * 0.4 * b.strideScale
        let roots = [b.hip, b.shoulder, b.hip.sceneMoved(b.farShift, 0.01), b.shoulder.sceneMoved(b.farShift, 0.01)]
        let uppers = [b.hindUpper, b.foreUpper, b.hindUpper, b.foreUpper]
        let lowers = [b.hindLower, b.foreLower, b.hindLower, b.foreLower]
        for i in 0..<4 {
            let w = SceneRig.foot(cycle + walkPhases[i], duty: 0.62), r = SceneRig.foot(cycle + runPhases[i], duty: 0.38)
            var dx = (w.forward * walkStride * (1 - run) + r.forward * runStride * run) * walk
            var up = (w.up * b.footLift * (1 - run) + r.up * b.footLift * 2.2 * run) * walk
            // In the air (a hop, a scramble): the feet tuck up under it.
            if a.lift > 0.01 {
                let tuck = min(1, a.lift * 6)
                up += tuck * 0.07
                dx += (i % 2 == 0 ? -0.05 : 0.06) * tuck
            }
            if i == 1, a.act == .stomp, a.phase == .acting { up = max(up, stompLift(a)); dx += stompLift(a) * 0.25 }
            let root = roots[i].applying(p.body)
            let rest = CGPoint(x: roots[i].x + (i % 2 == 0 ? 0.025 : 0.02), y: 0)
            let foot = CGPoint(x: Double(rest.x) + dx, y: up)
            let knee = SceneRig.knee(root, foot, upper: uppers[i], lower: lowers[i], bend: i % 2 == 0 ? -1 : 1)
            p.roots.append(root)
            p.knees.append(knee)
            p.feet.append(SceneRig.reach(knee, foot, lower: lowers[i]))
            p.lifts.append(min(1, up / max(0.01, b.footLift)))
        }

        // The head: nods with the steps, glances about at rest, turns to you when it is interested, roars.
        let nod = walk * (1 - run) * 0.035 * sin(4 * .pi * cycle + 1) + run * 0.06 * sin(2 * .pi * cycle)
        let idle = (1 - a.alert) * (1 - walk) * 0.16 * a.drift(0.25, 4)
        var head = nod + idle + a.look * 0.7 * a.alert - crouch * 0.25
        if a.phase == .fleeing { head -= 0.12 }
        head += headForAct(a, act)
        p.headAngle = head
        p.neck = b.neck.applying(p.body).sceneMoved(0, -crouch * 0.03)
        p.mouth = a.act == .roar || a.act == .snap || a.act == .trumpet ? a.pose.open : (a.act == .stomp && a.phase == .acting ? 0.25 * act : 0)
        p.blink = a.act == .lean && a.phase == .acting ? max(a.blink, 0.85 * act) : a.blink
        p.ears = a.phase == .fleeing || a.phase == .backingOff ? -1 : a.alert
        p.earTwitch = a.twitch()
        p.tail = a.tail + (a.phase == .fleeing ? 0.8 : 0)
        p.tailRoot = b.tailRoot.applying(p.body)
        return p
    }

    private func roarPitch(_ a: SceneActor, _ act: Double) -> Double {
        guard a.phase == .acting else { return 0 }
        switch a.act {
        case .roar: return 0.05 * act
        case .trumpet: return 0.04 * act
        case .hop: return a.lift > 0.01 ? 0.08 : 0
        default: return 0
        }
    }

    /// Pawing the ground: the front foot comes up and stamps down, three times.
    private func stompLift(_ a: SceneActor) -> Double {
        let t = a.phaseTime - 0.2
        guard t > 0, t < 1.5 else { return 0 }
        return 0.11 * pow(max(0, sin(t * 2 * .pi / 0.5)), 0.8)
    }

    private func stompPitch(_ a: SceneActor) -> Double {
        guard a.act == .stomp, a.phase == .acting else { return 0 }
        return a.phaseTime > 1.7 ? -0.05 * sin(min(1, (a.phaseTime - 1.7) / 0.5) * .pi) : 0.02 * stompLift(a) / 0.11
    }

    /// How the head moves in an act: anticipation down, then up and out.
    func headForAct(_ a: SceneActor, _ act: Double) -> Double {
        guard a.phase == .acting else { return a.phase == .noticing ? 0.1 * max(0, 1 - a.phaseTime / 0.5) : 0 }
        let t = a.phaseTime
        switch a.act {
        case .roar:
            let wind = t < 0.3 ? -0.18 * sin(t / 0.3 * .pi * 0.5) : 0
            return wind + 0.22 * a.pose.open + 0.02 * sin(t * 40) * a.pose.open
        case .trumpet: return 0.35 * act
        case .stomp: return -0.3 * act
        case .lean: return -0.25 * act + 0.06 * sin(t * 2.4)
        case .hop: return 0.15 * act * sin(t * 6)
        default: return 0
        }
    }

    // MARK: Drawing

    /// Near legs drawn over the body (a thin-legged animal whose thighs show) or tucked under it (a heavy one whose body hides them).
    var legsOverBody = false

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let p = solve(a)
        drawLegs(ctx, p, ink, near: false)
        drawTail(ctx, p, a, ink)
        if !legsOverBody { drawLegs(ctx, p, ink, near: true) }
        drawBody(ctx, p, a, ink)
        if legsOverBody { drawLegs(ctx, p, ink, near: true) }
        drawHead(ctx, p, a, ink)
    }

    func drawLegs(_ ctx: CGContext, _ p: SceneQuadPose, _ ink: SceneInk, near: Bool) {
        for i in (near ? [0, 1] : [2, 3]) { drawLeg(ctx, p, i, ink, near: near) }
    }

    /// One leg, made of a thigh, a shin and a foot. Species set the colours and the foot.
    func drawLeg(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {
        let hind = i % 2 == 0
        let w = hind ? build.hindWidths : build.foreWidths
        let colour = near ? legColour(hind: hind) : ink.dark(legColour(hind: hind), 0.28)
        let thigh = SceneShape.limb(p.roots[i], p.knees[i], w.0, w.1)
        let shin = SceneShape.limb(p.knees[i], p.feet[i], w.1 * 0.92, w.2)
        if near {
            ink.volume(ctx, shin, colour, rim: 0.6, light: false)
            ink.volume(ctx, thigh, colour, rim: 0.8)
        } else {
            // In the shade of the body: flat, and cheap.
            ink.volume(ctx, shin, colour, rim: 0, edge: 0.7, light: false)
            ink.volume(ctx, thigh, colour, rim: 0, edge: 0.7, light: false)
        }
        drawFoot(ctx, p, i, ink, near: near)
    }

    func legColour(hind: Bool) -> UInt32 { 0xC08040 }
    func drawFoot(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {}
    func drawTail(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {}
    func drawBody(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {}
    func drawHead(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {}

    // MARK: Helpers for species

    /// Points of the body at rest, moved with the body this frame.
    func bodyPath(_ points: [CGPoint], _ p: SceneQuadPose, tension: Double = 1) -> CGPath {
        SceneShape.blob(points.map { $0.applying(p.body) }, tension: tension)
    }

    /// Runs `draw` in the head's own frame: origin at the neck joint, turned by the head angle.
    func inHead(_ ctx: CGContext, _ p: SceneQuadPose, angle extra: Double = 0, _ draw: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: p.neck.x, y: p.neck.y)
        ctx.rotate(by: CGFloat(p.headAngle + extra))
        draw()
        ctx.restoreGState()
    }

    /// A paw: a soft rounded foot with toes.
    func paw(_ ctx: CGContext, _ foot: CGPoint, _ r: Double, _ colour: UInt32, _ ink: SceneInk, near: Bool) {
        let path = SceneShape.blob([pt(-r * 0.9, r * 0.2), pt(-r * 0.6, r * 0.75), pt(r * 0.4, r * 0.8), pt(r * 1.35, r * 0.25), pt(r * 1.3, -r * 0.35),
                                    pt(r * 0.3, -r * 0.42), pt(-r * 0.8, -r * 0.35)].map { $0.sceneMoved(Double(foot.x), Double(foot.y) + r * 0.4) })
        ink.volume(ctx, path, near ? colour : ink.dark(colour, 0.28), rim: near ? 0.5 : 0, light: false)
        if near, !ink.rough {
            let toes = (0..<2).map { k -> [CGPoint] in
                let x = Double(foot.x) + r * (0.45 + Double(k) * 0.45)
                return [pt(x, Double(foot.y) + r * 0.05), pt(x - r * 0.05, Double(foot.y) + r * 0.45)]
            }
            ink.lines(ctx, toes, ink.dark(colour, 0.5), width: Double(ink.px(1.2)), alpha: 0.7)
        }
    }

    /// A hoof: a dark keratin cap, tipping up as the foot lifts.
    func hoof(_ ctx: CGContext, _ foot: CGPoint, _ r: Double, _ colour: UInt32, _ ink: SceneInk, near: Bool, tip: Double = 0) {
        let x = Double(foot.x), y = Double(foot.y)
        let pts = [pt(-r * 0.75, r * 1.1), pt(r * 0.75, r * 1.1), pt(r * 1.05, -0.0), pt(-r * 0.95, 0)].map { $0.sceneTurned(about: .zero, by: tip * 0.4).sceneMoved(x, y) }
        let path = CGMutablePath()
        path.addLines(between: pts)
        path.closeSubpath()
        ink.volume(ctx, path, near ? colour : ink.dark(colour, 0.3), rim: near ? 0.4 : 0, edge: 1, light: near)
    }
}
