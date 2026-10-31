import CoreGraphics
import Foundation

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// A little brown monkey: scampers on all fours, then sits up (on your head, with luck), waves and chatters.
final class SceneMonkey: SceneQuadruped {
    private let fur: UInt32 = 0x7A4E2E
    private let pale: UInt32 = 0xE8C8A0
    private let face: UInt32 = 0xD8A888

    override init() {
        super.init()
        var b = SceneQuadBuild()
        b.hip = pt(-0.22, 0.40); b.shoulder = pt(0.14, 0.42)
        b.hindUpper = 0.21; b.hindLower = 0.21; b.foreUpper = 0.22; b.foreLower = 0.22
        b.hindWidths = (0.06, 0.035, 0.028); b.foreWidths = (0.05, 0.032, 0.026)
        b.neck = pt(0.24, 0.56); b.tailRoot = pt(-0.30, 0.52); b.middle = pt(-0.04, 0.48)
        b.footLift = 0.08; b.strideScale = 0.9
        build = b
    }

    override func legColour(hind: Bool) -> UInt32 { fur }

    override func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        if a.lift > 0.02 || (a.act == .climb && a.phase == .acting) { drawSitting(ctx, a, ink); return }
        super.draw(ctx, a, ink)
    }

    override func drawFoot(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {
        paw(ctx, p.feet[i], 0.03, ScenePaint.mixHex(fur, 0x2A1A12, 0.4), ink, near: near)
    }

    override func drawTail(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        tail(ctx, root: p.tailRoot, a: a, ink: ink, up: 1)
    }

    /// The long tail: up from the rump in an S, curling at the tip.
    private func tail(_ ctx: CGContext, root: CGPoint, a: SceneActor, ink: SceneInk, up: Double) {
        var spine: [CGPoint] = [root]
        var angle = .pi * (up > 0 ? 0.72 : 1.35) + a.tail * 0.2
        var p = root
        let n = 11
        for i in 1..<n {
            let k = Double(i) / Double(n - 1)
            angle += (k < 0.6 ? -0.18 : 0.42) * (up > 0 ? 1 : -1) + sin(a.time * 2 + k * 3 + a.quirk * 5) * 0.06
            p = p.sceneMoved(cos(angle) * 0.065, sin(angle) * 0.065)
            spine.append(p)
        }
        ink.volume(ctx, SceneShape.tube(spine, (0..<n).map { 0.022 * (1 - 0.5 * Double($0) / Double(n - 1)) }), fur, rim: 0.5)
    }

    override func drawBody(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let body = bodyPath([pt(0.26, 0.50), pt(0.20, 0.34), pt(0.0, 0.31), pt(-0.21, 0.33), pt(-0.33, 0.45), pt(-0.29, 0.58), pt(-0.10, 0.61), pt(0.12, 0.63)], p)
        ink.volume(ctx, body, fur, rim: 1)
        ink.inside(ctx, body) { ink.flat(ctx, SceneShape.ellipse(pt(0.08, 0.36).applying(p.body), 0.14, 0.05), pale, alpha: 0.7) }
    }

    override func drawHead(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        inHead(ctx, p) {
            ctx.scaleBy(x: 1.15, y: 1.15)
            head(ctx, a, ink, mouth: p.mouth, blink: p.blink, front: 0.2)
        }
    }

    /// The head: a round dark cap, big ears, a pale heart-shaped face with a muzzle.
    private func head(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk, mouth: Double, blink: Double, front: Double) {
        for x in [-0.03, 0.05] {
            ink.volume(ctx, SceneShape.ellipse(pt(x, 0.08), 0.045, 0.05), face, rim: 0.6)
            ink.flat(ctx, SceneShape.ellipse(pt(x + 0.008, 0.08), 0.022, 0.028), 0xA8705A, alpha: 0.8)
        }
        ink.volume(ctx, SceneShape.ellipse(pt(0.06, 0.08), 0.11, 0.105), fur, rim: 1)
        let mask = SceneShape.blob([pt(0.07, 0.13), pt(0.12, 0.14), pt(0.17, 0.11), pt(0.19, 0.04), pt(0.17, -0.0), pt(0.10, -0.01), pt(0.06, 0.03)])
        ink.volume(ctx, mask, face, rim: 0.4)
        ink.volume(ctx, SceneShape.ellipse(pt(0.17, 0.035), 0.045, 0.035), ScenePaint.mixHex(face, 0xF0D8C0, 0.4), rim: 0.3)
        ink.eye(ctx, at: pt(0.12, 0.095), r: 0.019, iris: 0x4A2A14, skin: face, blink: blink, pupil: 0.55)
        ink.eye(ctx, at: pt(0.165, 0.098), r: 0.015, iris: 0x4A2A14, skin: face, blink: blink, pupil: 0.55)
        ink.flat(ctx, SceneShape.ellipse(pt(0.205, 0.045), 0.008, 0.006), 0x3A2018)
        if mouth > 0.05 {
            ink.flat(ctx, SceneShape.ellipse(pt(0.18, 0.005), 0.025, 0.012 + 0.02 * mouth), 0x5A1A1A)
            ctx.setFillColor(ink.tone(0xF8F4EC))
            ctx.fill(CGRect(x: 0.165, y: 0.012 + 0.012 * mouth, width: 0.03, height: 0.006))
        } else if !ink.rough {
            ink.line(ctx, SceneShape.curve([pt(0.16, 0.012), pt(0.18, 0.004), pt(0.2, 0.012)]), 0x5A3020, width: Double(ink.px(1.4)))
        }
    }

    /// Sitting up: on a shoulder, on a head, or in mid-climb. Arms wave once it has arrived.
    private func drawSitting(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        ctx.scaleBy(x: 1.3, y: 1.3)
        let arrived = a.landed
        let bounce = arrived ? 0.015 * abs(sin(a.time * 7.5)) : 0
        let wave = arrived ? sin(a.time * 6) : sin(a.time * 14) * 0.5
        // The tail curls up behind, never down over your face.
        tail(ctx, root: pt(-0.1, 0.12), a: a, ink: ink, up: 1)
        // Far arm and leg.
        ink.volume(ctx, SceneShape.limb(pt(-0.02, 0.36 + bounce), pt(-0.12, 0.2), 0.04, 0.03), ink.dark(fur, 0.25), rim: 0, light: false)
        ink.volume(ctx, SceneShape.limb(pt(-0.06, 0.12), pt(0.08, 0.06), 0.06, 0.04), ink.dark(fur, 0.25), rim: 0, light: false)
        // Body upright.
        let body = SceneShape.blob([pt(0.04, 0.42 + bounce), pt(0.10, 0.30), pt(0.08, 0.12), pt(-0.02, 0.04), pt(-0.12, 0.10), pt(-0.12, 0.30), pt(-0.06, 0.42 + bounce)])
        ink.volume(ctx, body, fur, rim: 1)
        ink.inside(ctx, body) { ink.flat(ctx, SceneShape.ellipse(pt(0.05, 0.22), 0.05, 0.13), pale, alpha: 0.8) }
        // Near leg folded in front, foot gripping.
        ink.volume(ctx, SceneShape.limb(pt(-0.02, 0.12), pt(0.12, 0.10), 0.065, 0.045), fur, rim: 0.6)
        ink.volume(ctx, SceneShape.limb(pt(0.12, 0.10), pt(0.1, 0.0), 0.045, 0.03), fur, rim: 0.4)
        paw(ctx, pt(0.1, 0.0), 0.03, ScenePaint.mixHex(fur, 0x2A1A12, 0.4), ink, near: true)
        // Near arm: waving high once it is sitting, reaching up as it climbs.
        let shoulder = pt(0.02, 0.38 + bounce)
        let hand = arrived ? pt(0.14 + 0.05 * wave, 0.62 + 0.04 * abs(wave)) : pt(0.16, 0.52 + 0.05 * wave)
        let elbow = SceneRig.knee(shoulder, hand, upper: 0.14, lower: 0.15, bend: -1)
        ink.volume(ctx, SceneShape.limb(shoulder, elbow, 0.04, 0.032), fur, rim: 0.7)
        ink.volume(ctx, SceneShape.limb(elbow, SceneRig.reach(elbow, hand, lower: 0.15), 0.032, 0.025), fur, rim: 0.6)
        ink.volume(ctx, SceneShape.ellipse(SceneRig.reach(elbow, hand, lower: 0.15), 0.03, 0.03), face, rim: 0.4)
        ctx.saveGState()
        ctx.translateBy(x: -0.05, y: 0.42 + bounce)
        ctx.rotate(by: CGFloat(0.1 * sin(a.time * 2.3) + 0.15))
        ctx.scaleBy(x: 1.2, y: 1.2)
        let chatter = arrived && a.phaseTime - 2.0 < 1.8 ? max(0, sin(a.time * 16)) : 0
        head(ctx, a, ink, mouth: chatter, blink: a.blink, front: 0.5)
        ctx.restoreGState()
    }
}

/// A silverback gorilla: knuckle-walks, then rears up to drum on its chest.
final class SceneGorilla: SceneQuadruped {
    private let fur: UInt32 = 0x2C2828
    private let skin: UInt32 = 0x1E1A1A
    private let silver: UInt32 = 0x7E7C80

    override init() {
        super.init()
        var b = SceneQuadBuild()
        b.hip = pt(-0.22, 0.42); b.shoulder = pt(0.14, 0.60)
        b.hindUpper = 0.22; b.hindLower = 0.22; b.foreUpper = 0.31; b.foreLower = 0.31
        b.hindWidths = (0.10, 0.06, 0.05); b.foreWidths = (0.11, 0.075, 0.055)
        b.neck = pt(0.24, 0.78); b.tailRoot = pt(-0.3, 0.5); b.middle = pt(-0.04, 0.55)
        b.footLift = 0.07; b.strideScale = 0.8
        build = b
        legsOverBody = true
    }

    override func legColour(hind: Bool) -> UInt32 { fur }

    override func drawFoot(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {
        let f = p.feet[i]
        let hand = i % 2 == 1
        let path = hand ? SceneShape.blob([pt(-0.04, 0.0), pt(-0.045, 0.05), pt(0.03, 0.06), pt(0.06, 0.03), pt(0.05, 0.0)].map { $0.sceneMoved(Double(f.x), Double(f.y)) })
                        : SceneShape.blob([pt(-0.05, 0.0), pt(-0.05, 0.04), pt(0.05, 0.04), pt(0.09, 0.015), pt(0.08, 0.0)].map { $0.sceneMoved(Double(f.x), Double(f.y)) })
        ink.volume(ctx, path, near ? skin : ink.dark(skin, 0.2), rim: near ? 0.4 : 0, light: near)
    }

    override func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        if a.act == .chestBeat, a.phase == .acting { drawUpright(ctx, a, ink); return }
        super.draw(ctx, a, ink)
    }

    override func drawBody(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let body = bodyPath([pt(0.28, 0.66), pt(0.22, 0.46), pt(0.04, 0.36), pt(-0.18, 0.32), pt(-0.33, 0.40), pt(-0.36, 0.56), pt(-0.26, 0.70),
                             pt(-0.06, 0.80), pt(0.14, 0.88), pt(0.26, 0.84)], p)
        ink.volume(ctx, body, fur, rim: 1.2)
        ink.inside(ctx, body) {
            ink.flat(ctx, SceneShape.blob([pt(-0.32, 0.52), pt(-0.24, 0.70), pt(-0.06, 0.76), pt(-0.02, 0.64), pt(-0.16, 0.56)].map { $0.applying(p.body) }), silver, alpha: 0.5)
            ink.flat(ctx, SceneShape.blob([pt(-0.28, 0.56), pt(-0.21, 0.68), pt(-0.08, 0.72), pt(-0.06, 0.64), pt(-0.16, 0.58)].map { $0.applying(p.body) }), silver, alpha: 0.4)
        }
        furTexture(ctx, ink, along: [pt(-0.3, 0.5), pt(-0.2, 0.68), pt(0.0, 0.8), pt(0.14, 0.86)].map { $0.applying(p.body) })
    }

    private func furTexture(_ ctx: CGContext, _ ink: SceneInk, along points: [CGPoint]) {
        guard !ink.rough, points.count > 1 else { return }
        var tufts: [CGPoint] = []
        for i in 0..<(points.count - 1) {
            for k in 0..<4 {
                let t = Double(k) / 4
                tufts.append(pt(Double(points[i].x) + Double(points[i + 1].x - points[i].x) * t, Double(points[i].y) + Double(points[i + 1].y - points[i].y) * t))
            }
        }
        ink.tufts(ctx, along: tufts, length: 0.03, angle: .pi * 0.75, hex: 0x5A5656, width: Double(ink.px(1.5)), alpha: 0.5, seed: 4)
    }

    override func drawHead(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        inHead(ctx, p) {
            ctx.scaleBy(x: 1.25, y: 1.25)
            head(ctx, a, ink, mouth: p.mouth, blink: p.blink)
        }
    }

    /// The head: a high crest, a heavy brow ridge, a broad black face with deep-set eyes.
    private func head(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk, mouth: Double, blink: Double) {
        ink.volume(ctx, SceneShape.blob([pt(-0.06, -0.02), pt(-0.05, 0.08), pt(0.02, 0.17), pt(0.08, 0.15), pt(0.14, 0.08), pt(0.16, -0.04), pt(0.06, -0.1)]), fur, rim: 1)
        let face = SceneShape.blob([pt(0.07, 0.07), pt(0.15, 0.08), pt(0.19, 0.03), pt(0.2, -0.05), pt(0.16, -0.1), pt(0.08, -0.09), pt(0.05, -0.02)])
        ink.volume(ctx, face, skin, rim: 0.6)
        ink.volume(ctx, SceneShape.blob([pt(0.08, 0.07), pt(0.19, 0.075), pt(0.2, 0.05), pt(0.09, 0.045)]), skin, rim: 0.8)
        ink.eye(ctx, at: pt(0.14, 0.03), r: 0.014, iris: 0x5A3418, skin: skin, blink: blink, pupil: 0.55)
        if mouth > 0.05 {
            ink.flat(ctx, SceneShape.ellipse(pt(0.17, -0.07), 0.03, 0.01 + 0.03 * mouth), 0x5A1418)
            ctx.setFillColor(ink.tone(0xF0E8D8))
            ctx.fill(CGRect(x: 0.15, y: -0.07 + 0.025 * mouth, width: 0.04, height: 0.008))
        }
        ink.flat(ctx, SceneShape.ellipse(pt(0.19, -0.01), 0.018, 0.012), 0x0A0808)
    }

    /// Rearing up to drum: the body tips up about the hips, the arms swing in to beat the chest in turn.
    private func drawUpright(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let rise = a.acting(rise: 0.4, fall: 0.6)
        let t = a.phaseTime
        let beat = t > 0.5 && t < 2.1 ? sin(t * 2 * .pi / 0.26) : 0
        let hip = pt(-0.1, 0.42)
        let tip = 0.85 * rise
        func up(_ q: CGPoint) -> CGPoint { q.sceneTurned(about: hip, by: tip).sceneMoved(0.04 * rise, 0.06 * rise) }
        // Legs stand.
        for (x, near) in [(-0.18, false), (-0.04, true)] {
            let root = pt(x, 0.42 + 0.06 * rise)
            let foot = pt(x + 0.04, 0)
            let knee = SceneRig.knee(root, foot, upper: 0.24, lower: 0.24, bend: 1)
            let colour = near ? fur : ink.dark(fur, 0.25)
            ink.volume(ctx, SceneShape.limb(root, knee, 0.11, 0.07), colour, rim: near ? 0.6 : 0, light: near)
            ink.volume(ctx, SceneShape.limb(knee, foot, 0.07, 0.05), colour, rim: near ? 0.5 : 0, light: near)
            ink.volume(ctx, SceneShape.blob([foot.sceneMoved(-0.05, 0), foot.sceneMoved(-0.05, 0.04), foot.sceneMoved(0.06, 0.04), foot.sceneMoved(0.1, 0.0)]), skin, rim: 0.3)
        }
        let shoulder = up(pt(0.10, 0.74))
        let chest = up(pt(0.24, 0.62))
        /// An arm: out to the side at the top of the swing, fist on the chest at the bottom.
        func arm(_ near: Bool, _ k: Double) {
            let s = shoulder.sceneMoved(near ? 0.03 : -0.05, near ? -0.02 : 0.02)
            let hand = chest.sceneMoved(0.13 - 0.1 * k + (near ? 0 : -0.04), 0.06 - 0.04 * k)
            let elbow = SceneRig.knee(s, hand, upper: 0.2, lower: 0.19, bend: near ? -1 : -1)
            let colour = near ? fur : ink.dark(fur, 0.25)
            ink.volume(ctx, SceneShape.limb(s, elbow, 0.1, 0.075), colour, rim: near ? 0.8 : 0, light: near)
            let h = SceneRig.reach(elbow, hand, lower: 0.19)
            ink.volume(ctx, SceneShape.limb(elbow, h, 0.075, 0.058), colour, rim: near ? 0.6 : 0, light: near)
            ink.volume(ctx, SceneShape.ellipse(h, 0.06, 0.055), near ? skin : ink.dark(skin, 0.2), rim: 0.4)
        }
        arm(false, max(0, -beat))
        let body = SceneShape.blob([pt(0.28, 0.66), pt(0.22, 0.46), pt(0.04, 0.36), pt(-0.18, 0.32), pt(-0.33, 0.40), pt(-0.36, 0.56), pt(-0.26, 0.70),
                                    pt(-0.06, 0.80), pt(0.14, 0.88), pt(0.26, 0.84)].map { up($0) })
        ink.volume(ctx, body, fur, rim: 1.2)
        ink.inside(ctx, body) {
            // The bare, leathery chest he drums on.
            ink.flat(ctx, SceneShape.ellipse(chest.sceneMoved(-0.02, -0.02), 0.09, 0.13), 0x3A3434)
            ink.flat(ctx, SceneShape.blob([pt(-0.32, 0.52), pt(-0.24, 0.70), pt(-0.06, 0.76), pt(-0.02, 0.64), pt(-0.16, 0.56)].map { up($0) }), silver, alpha: 0.5)
        }
        ctx.saveGState()
        let neck = up(pt(0.14, 0.86))
        ctx.translateBy(x: neck.x, y: neck.y)
        ctx.rotate(by: CGFloat(-tip * 0.85 + 0.15 * rise + a.look * 0.3))
        ctx.scaleBy(x: 1.25, y: 1.25)
        head(ctx, a, ink, mouth: a.pose.open, blink: 0)
        ctx.restoreGState()
        arm(true, max(0, beat))
    }
}

/// A red-eyed tree frog: sits, puffs out its throat to call, and leaps with its long legs stretched out behind.
final class SceneFrog: ScenePuppet {
    private let skin: UInt32 = 0x4CC44A
    private let flank: UInt32 = 0x2A6AD0
    private let belly: UInt32 = 0xF4F0D8
    private let toes: UInt32 = 0xF29A2A

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let air = min(1, a.lift * 2.5 + max(0, a.pose.stretch - 1) * 6)
        let call = a.phase == .acting ? max(0, sin(a.phaseTime * 5)) * a.acting(rise: 0.2, fall: 0.3) : 0
        // Hind leg: folded in a Z when sitting, flung out behind in the leap.
        func hindLeg(far: Bool) {
            let hip = pt(-0.28, 0.32)
            let knee = pt(-0.06 - 0.32 * air, 0.40 - 0.18 * air)
            let ankle = pt(-0.36 - 0.28 * air, 0.12 - 0.04 * air)
            let foot = pt(-0.12 - 0.62 * air, 0.03 + 0.06 * air)
            let colour = far ? ink.dark(skin, 0.3) : skin
            let shift = far ? 0.04 : 0.0
            ink.volume(ctx, SceneShape.limb(hip.sceneMoved(shift, 0.03), knee.sceneMoved(shift, 0.03), 0.11, 0.07), colour, rim: far ? 0 : 0.7, light: !far)
            ink.volume(ctx, SceneShape.limb(knee.sceneMoved(shift, 0.03), ankle.sceneMoved(shift, 0.03), 0.07, 0.04), colour, rim: far ? 0 : 0.5, light: !far)
            ink.volume(ctx, SceneShape.limb(ankle.sceneMoved(shift, 0.03), foot.sceneMoved(shift, 0.03), 0.04, 0.03), far ? ink.dark(toes, 0.3) : toes, rim: 0.3)
            ctx.setFillColor(ink.tone(far ? ink.dark(toes, 0.3) : toes))
            for k in 0..<3 {
                let c = foot.sceneMoved(shift + 0.05 + Double(k) * 0.02, 0.03 - Double(k) * 0.03)
                ctx.fillEllipse(in: CGRect(x: Double(c.x) - 0.022, y: Double(c.y) - 0.022, width: 0.044, height: 0.044))
            }
        }
        hindLeg(far: true)
        // Body: a plump teardrop, blue and yellow down the flank, white underneath.
        let body = SceneShape.blob([pt(0.36, 0.30), pt(0.30, 0.16), pt(0.12, 0.10), pt(-0.12, 0.12), pt(-0.34, 0.24), pt(-0.30, 0.42),
                                    pt(-0.08, 0.54), pt(0.16, 0.56), pt(0.32, 0.46)])
        ink.volume(ctx, body, skin, rim: 1)
        ink.inside(ctx, body) {
            ink.flat(ctx, SceneShape.blob([pt(-0.30, 0.26), pt(-0.06, 0.30), pt(0.16, 0.24), pt(0.10, 0.17), pt(-0.16, 0.18)]), flank)
            if !ink.rough {
                ink.lines(ctx, (0..<4).map { k in [pt(-0.22 + Double(k) * 0.09, 0.27), pt(-0.20 + Double(k) * 0.09, 0.19)] }, 0xF2D040, width: 0.016)
            }
            ink.flat(ctx, SceneShape.ellipse(pt(0.18, 0.13), 0.16, 0.07), belly)
        }
        // The throat sac swells to call.
        if call > 0.02 {
            ink.volume(ctx, SceneShape.ellipse(pt(0.26, 0.16), 0.09 * (0.5 + call), 0.08 * (0.5 + call)), 0xF4E8B0, rim: 0.8)
        }
        hindLeg(far: false)
        // Front legs, thin, with orange toe pads.
        for (x, far) in [(0.22, true), (0.16, false)] {
            let colour = far ? ink.dark(skin, 0.3) : skin
            let foot = pt(x + 0.1 + 0.15 * air, 0.0 + 0.1 * air)
            ink.volume(ctx, SceneShape.limb(pt(x, 0.22), foot, 0.04, 0.025), colour, rim: far ? 0 : 0.4, light: !far)
            ctx.setFillColor(ink.tone(far ? ink.dark(toes, 0.3) : toes))
            for k in 0..<3 { ctx.fillEllipse(in: CGRect(x: Double(foot.x) - 0.02 + Double(k) * 0.025, y: Double(foot.y) - 0.015, width: 0.034, height: 0.034)) }
        }
        // Big red eyes on top.
        for (x, far) in [(0.18, true), (0.25, false)] {
            let c = pt(x, 0.52)
            ink.volume(ctx, SceneShape.ellipse(c, 0.085, 0.085), far ? ink.dark(skin, 0.2) : skin, rim: 0.6)
            ink.eye(ctx, at: c.sceneMoved(0.01, 0.01), r: 0.06, iris: 0xE0201C, skin: skin, blink: a.blink, pupil: 0.5, slit: true)
        }
        if !ink.rough { ink.line(ctx, SceneShape.curve([pt(0.24, 0.30), pt(0.32, 0.27), pt(0.37, 0.30)]), ink.dark(skin, 0.6), width: Double(ink.px(1.5))) }
    }
}

/// A green tree snake: a tube that slides in waves, and rears up in an S to hiss with its tongue flicking.
final class SceneSnake: ScenePuppet {
    private let skin: UInt32 = 0x3E9A3A
    private let belly: UInt32 = 0xD8E070
    private let mark: UInt32 = 0xEAF2D0

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        // Units: the full height is the snake's height; it is 3.2 times as long.
        let length = 3.0
        let thick = 0.16
        let open = a.pose.open
        let moving = a.walk > 0.2
        let phase = a.stride * 1.4 + a.time * (moving ? 0 : 0.6)
        let wiggle = thick * (moving ? 0.9 : 0.35)
        let n = 26
        var spine: [CGPoint] = []
        var radii: [Double] = []
        for i in 0..<n {
            let s = Double(i) / Double(n - 1)                // 0 tail, 1 head
            let rise = max(0, (s - 0.45) / 0.55)
            let lift = open * 1.6 * pow(rise, 1.3)
            let fold = open * 0.32 * length * rise
            let x = (s - 0.5) * length * (1 - 0.3 * open) + fold * 0.4 - length * 0.1 * open
            let y = thick * 0.75 + sin(phase - s * 9) * wiggle * (1 - 0.85 * open * min(1, s * 1.3)) * (0.4 + 0.6 * (1 - s)) + lift
                + open * 0.18 * sin(rise * .pi * 1.6) * rise
            spine.append(pt(x, y))
            radii.append(thick * (0.3 + 0.7 * sqrt(sin(min(1, 0.1 + s * 0.9) * .pi * 0.92))) * (s > 0.92 ? 0.9 : 1))
        }
        let body = SceneShape.tube(spine, radii)
        ink.volume(ctx, body, skin, rim: 1)
        ink.inside(ctx, body) {
            // Pale belly scales along the underside, and a chain of light diamonds down the back.
            let under = SceneShape.tube(spine.map { $0.sceneMoved(0, -thick * 0.55) }, radii.map { $0 * 0.55 })
            ink.flat(ctx, under, belly, alpha: 0.9)
            ctx.setFillColor(ink.tone(mark, 0.85))
            for i in stride(from: 3, to: n - 3, by: 2) {
                let c = spine[i], r = radii[i]
                let path = CGMutablePath()
                path.addLines(between: [c.sceneMoved(-r * 0.5, r * 0.45), c.sceneMoved(0, r * 0.85), c.sceneMoved(r * 0.5, r * 0.45), c.sceneMoved(0, r * 0.1)])
                path.closeSubpath()
                ctx.addPath(path)
                ctx.fillPath()
            }
        }
        // The head: wider than the neck, a yellow eye, and a forked tongue that flickers.
        guard let neck = spine.last else { return }
        let dir = atan2(Double(spine[n - 1].y - spine[n - 3].y), Double(spine[n - 1].x - spine[n - 3].x))
        ctx.saveGState()
        ctx.translateBy(x: neck.x, y: neck.y)
        ctx.rotate(by: CGFloat(dir * 0.6 - open * 0.2))
        let r = thick * 0.95
        let jaw = 0.5 * open
        ink.volume(ctx, SceneShape.blob([pt(-r * 0.4, -r * 0.5), pt(r * 1.2, -r * 0.55 - jaw * r), pt(r * 1.5, -r * 0.3 - jaw * r), pt(r * 0.6, -r * 0.2)]), belly, rim: 0.3)
        ink.volume(ctx, SceneShape.blob([pt(-r * 0.5, r * 0.6), pt(r * 0.8, r * 0.75), pt(r * 1.65, r * 0.25), pt(r * 1.6, -r * 0.2), pt(r * 0.6, -r * 0.45), pt(-r * 0.5, -r * 0.5)]), skin, rim: 1)
        ink.eye(ctx, at: pt(r * 0.75, r * 0.3), r: r * 0.24, iris: 0xF0D040, skin: skin, blink: 0, pupil: 0.4, slit: true)
        let flick = max(0, sin(a.time * (open > 0.2 ? 16 : 5) + a.quirk * 9))
        if flick > 0.3 {
            let tip = pt(r * (2.2 + 1.0 * flick + open * 0.6), -r * 0.15)
            ink.line(ctx, SceneShape.curve([pt(r * 1.5, -r * 0.1), tip]), 0xD8304A, width: max(Double(ink.px(1.5)), thick * 0.07))
            ink.line(ctx, SceneShape.curve([tip, tip.sceneMoved(r * 0.3, r * 0.22)]), 0xD8304A, width: max(Double(ink.px(1.5)), thick * 0.06))
            ink.line(ctx, SceneShape.curve([tip, tip.sceneMoved(r * 0.3, -r * 0.22)]), 0xD8304A, width: max(Double(ink.px(1.5)), thick * 0.06))
        }
        if jaw > 0.1 {
            ctx.setFillColor(ink.tone(0xF8F4EC))
            ctx.move(to: pt(r * 1.2, -r * 0.3)); ctx.addLine(to: pt(r * 1.32, -r * 0.3)); ctx.addLine(to: pt(r * 1.25, -r * 0.3 - r * 0.4 * jaw)); ctx.fillPath()
        }
        ctx.restoreGState()
    }
}
