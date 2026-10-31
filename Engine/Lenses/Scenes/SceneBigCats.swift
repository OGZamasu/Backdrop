import CoreGraphics
import Foundation

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// The big cats: a lion with a mane, a striped tiger, a spotted cheetah. One body plan, three coats.
final class SceneBigCat: SceneQuadruped {
    enum Kind { case lion, tiger, cheetah }
    private let kind: Kind

    /// The coat, named.
    private struct Coat {
        var fur: UInt32
        var belly: UInt32
        var mark: UInt32
        var mane: UInt32 = 0
        var maneLight: UInt32 = 0
        var eye: UInt32
        var nose: UInt32
    }
    private let coat: Coat

    init(_ kind: Kind) {
        self.kind = kind
        switch kind {
        case .lion: coat = Coat(fur: 0xD6A05A, belly: 0xF1D6A6, mark: 0x5A3016, mane: 0x6A3214, maneLight: 0xB0622C, eye: 0xD9982A, nose: 0x6A2E24)
        case .tiger: coat = Coat(fur: 0xE27A28, belly: 0xF7EEDF, mark: 0x1E140E, eye: 0xE8B030, nose: 0xC8746A)
        case .cheetah: coat = Coat(fur: 0xDDAE58, belly: 0xF6E6C2, mark: 0x241A12, eye: 0xD9A030, nose: 0x3A2620)
        }
        super.init()
        var b = SceneQuadBuild()
        switch kind {
        case .lion, .tiger:
            b.hip = pt(-0.47, 0.47); b.shoulder = pt(0.20, 0.47)
            b.hindUpper = 0.25; b.hindLower = 0.24; b.foreUpper = 0.24; b.foreLower = 0.245
            b.hindWidths = (0.12, 0.062, 0.042); b.foreWidths = (0.10, 0.06, 0.046)
            b.neck = pt(0.33, 0.62); b.tailRoot = pt(-0.67, 0.6); b.middle = pt(-0.14, 0.5)
            b.footLift = 0.075
        case .cheetah:
            b.hip = pt(-0.44, 0.55); b.shoulder = pt(0.16, 0.55)
            b.hindUpper = 0.29; b.hindLower = 0.29; b.foreUpper = 0.29; b.foreLower = 0.285
            b.hindWidths = (0.095, 0.045, 0.03); b.foreWidths = (0.08, 0.042, 0.032)
            b.neck = pt(0.30, 0.70); b.tailRoot = pt(-0.62, 0.66); b.middle = pt(-0.13, 0.58)
            b.strideScale = 1.15
        }
        build = b
    }

    override func legColour(hind: Bool) -> UInt32 { coat.fur }

    // MARK: Body

    private var bodyOutline: [CGPoint] {
        switch kind {
        case .lion, .tiger:
            return [pt(0.39, 0.52), pt(0.33, 0.37), pt(0.19, 0.30), pt(-0.10, 0.31), pt(-0.34, 0.33), pt(-0.53, 0.33), pt(-0.68, 0.42),
                    pt(-0.73, 0.56), pt(-0.64, 0.68), pt(-0.38, 0.69), pt(-0.10, 0.68), pt(0.12, 0.72), pt(0.33, 0.70)]
        case .cheetah:
            return [pt(0.34, 0.62), pt(0.27, 0.48), pt(0.12, 0.43), pt(-0.12, 0.44), pt(-0.34, 0.47), pt(-0.52, 0.47), pt(-0.64, 0.58),
                    pt(-0.58, 0.71), pt(-0.38, 0.72), pt(-0.12, 0.70), pt(0.08, 0.745), pt(0.28, 0.73)]
        }
    }

    override func drawBody(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let body = bodyPath(bodyOutline, p)
        ink.volume(ctx, body, coat.fur, rim: 1.1)
        let y0 = kind == .cheetah ? 0.44 : 0.31
        ink.inside(ctx, body) {
            // The pale underside and a soft shade where the haunch and shoulder bulge.
            let belly = SceneShape.blob([pt(0.30, y0 + 0.02), pt(-0.1, y0 - 0.02), pt(-0.5, y0 + 0.03), pt(-0.3, y0 + 0.08), pt(0.05, y0 + 0.08)].map { $0.applying(p.body) })
            ink.flat(ctx, belly, coat.belly, alpha: 0.85)
            switch kind {
            case .tiger: stripes(ctx, p, ink)
            case .cheetah: spots(ctx, p, ink, from: -0.66, to: 0.34, low: 0.47, high: 0.73)
            case .lion: break
            }
            if !ink.rough {
                let swing = Double(p.knees[0].x - p.roots[0].x) * 0.6
                let haunch = SceneShape.curve([pt(-0.34, 0.64), pt(-0.38 + swing * 0.3, 0.52), pt(-0.47 + swing, 0.36)].map { $0.applying(p.body) })
                ink.line(ctx, haunch, ink.dark(coat.fur, 0.35), width: Double(ink.px(2.2)), alpha: 0.5)
                let reach = Double(p.knees[1].x - p.roots[1].x) * 0.6
                let blade = SceneShape.curve([pt(0.06, 0.68), pt(0.12 + reach * 0.3, 0.55), pt(0.14 + reach, 0.36)].map { $0.applying(p.body) })
                ink.line(ctx, blade, ink.dark(coat.fur, 0.35), width: Double(ink.px(2)), alpha: 0.4)
            }
        }
        if kind == .lion, !ink.rough {
            // The fringe of longer fur along the belly.
            let fringe = stride(from: -0.42, through: 0.16, by: 0.05).map { pt($0, 0.315 + 0.015 * cos($0 * 5)).applying(p.body) }
            ink.tufts(ctx, along: fringe, length: 0.035, angle: -.pi / 2 - 0.3, hex: ink.dark(coat.fur, 0.3), width: Double(ink.px(2)), seed: 2)
        }
    }

    private func stripes(_ ctx: CGContext, _ p: SceneQuadPose, _ ink: SceneInk) {
        // Separate small fills: Core Graphics fills many small shapes faster than one shape made of them all.
        ctx.setFillColor(ink.tone(coat.mark))
        func mark(_ path: CGPath) { ctx.addPath(path); ctx.fillPath() }
        for i in 0..<13 {
            let x = -0.64 + Double(i) * 0.075 + (ScenePaint.noise(Double(i) * 1.9, 3) - 0.5) * 0.03
            let len = 0.13 + 0.12 * ScenePaint.noise(Double(i) * 2.7, 5)
            let w = 0.016 + 0.01 * ScenePaint.noise(Double(i) * 3.1, 7)
            let top = 0.70, lean = 0.03 * sin(Double(i))
            mark(SceneShape.tube([pt(x - lean, top + 0.02), pt(x + lean * 0.5, top - len * 0.5), pt(x + lean, top - len)].map { $0.applying(p.body) }, [w, w * 0.8, w * 0.15]))
            if i % 2 == 0 {
                // A shorter stripe coming up from the belly.
                mark(SceneShape.tube([pt(x + 0.03, 0.34), pt(x + 0.035, 0.40), pt(x + 0.04, 0.45)].map { $0.applying(p.body) }, [w * 0.8, w * 0.6, w * 0.1]))
            }
        }
    }

    private func spots(_ ctx: CGContext, _ p: SceneQuadPose, _ ink: SceneInk, from: Double, to: Double, low: Double, high: Double) {
        ctx.setFillColor(ink.tone(coat.mark, 0.9))
        let step = ink.rough ? 0.075 : 0.05
        var row = 0
        var y = low
        while y < high {
            var x = from + (row % 2 == 0 ? 0 : step * 0.5)
            while x < to {
                let j = ScenePaint.noise(x * 13 + y * 7, 11)
                let c = pt(x + (j - 0.5) * step * 0.5, y + (ScenePaint.noise(x * 7 + y * 13, 3) - 0.5) * step * 0.4).applying(p.body)
                let r = 0.011 + 0.006 * j
                ctx.fillEllipse(in: CGRect(x: Double(c.x) - r, y: Double(c.y) - r * 0.85, width: r * 2, height: r * 1.7))
                x += step
            }
            y += step * 0.8
            row += 1
        }
    }

    // MARK: Feet and tail

    override func drawFoot(_ ctx: CGContext, _ p: SceneQuadPose, _ i: Int, _ ink: SceneInk, near: Bool) {
        let r = kind == .cheetah ? 0.042 : 0.052
        paw(ctx, p.feet[i], r, i % 2 == 0 ? coat.fur : ScenePaint.mixHex(coat.fur, coat.belly, 0.3), ink, near: near)
    }

    override func drawTail(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        // A long tail hanging down and curling up at the end; it swings, and lifts when the cat runs.
        let n = 9
        let length = kind == .cheetah ? 0.58 : 0.5
        let seg = length / Double(n - 1)
        var spine: [CGPoint] = [p.tailRoot]
        var radii: [Double] = []
        var angle = .pi + 1.05 - p.tail * 0.3 - (a.phase == .fleeing ? 0.7 : 0) + p.crouch * 0.15
        var point = p.tailRoot
        for i in 1..<n {
            let k = Double(i) / Double(n - 1)
            angle -= (kind == .lion ? 0.24 : 0.2) * k + p.tail * 0.05 * k
            point = point.sceneMoved(cos(angle) * seg, sin(angle) * seg)
            spine.append(point)
        }
        for i in 0..<n { radii.append((kind == .cheetah ? 0.024 : 0.026) * (1 - 0.45 * Double(i) / Double(n - 1))) }
        let path = SceneShape.tube(spine, radii)
        ink.volume(ctx, path, coat.fur, rim: 0.6)
        guard let end = spine.last else { return }
        switch kind {
        case .lion:
            let tuft = SceneShape.blob([end.sceneMoved(0.03, 0.02), end.sceneMoved(-0.01, 0.045), end.sceneMoved(-0.05, 0.02), end.sceneMoved(-0.075, -0.03),
                                        end.sceneMoved(-0.04, -0.02), end.sceneMoved(-0.05, -0.06), end.sceneMoved(-0.01, -0.03), end.sceneMoved(0.025, -0.02)], tension: 0.8)
            ink.volume(ctx, tuft, coat.mane, rim: 0.4)
        case .tiger, .cheetah:
            ink.inside(ctx, path) {
                for k in stride(from: kind == .tiger ? 2 : 5, to: n, by: 1) {
                    let c = spine[k]
                    ctx.setFillColor(ink.tone(coat.mark))
                    ctx.fillEllipse(in: CGRect(x: Double(c.x) - 0.02, y: Double(c.y) - 0.012, width: 0.04, height: 0.024))
                }
            }
            if kind == .cheetah { ink.flat(ctx, SceneShape.ellipse(end, 0.016, 0.016), 0xF6F0E4) }
        }
    }

    // MARK: Head

    override func drawHead(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let s = kind == .cheetah ? 0.82 : 1.08
        inHead(ctx, p) {
            ctx.scaleBy(x: CGFloat(s), y: CGFloat(s))
            if kind == .lion { mane(ctx, p, a, ink, back: true) }
            if kind == .tiger { ruff(ctx, ink) }
            ear(ctx, ink, at: pt(kind == .lion ? 0.09 : 0.07, 0.15), p: p, which: 0)
            face(ctx, p, a, ink)
            if kind == .lion { mane(ctx, p, a, ink, back: false) }
        }
    }

    private func mane(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk, back: Bool) {
        let sway = sin(a.time * 2.1 + a.quirk * 5) * 0.012 + a.walk * 0.01 * sin(a.stride * 2)
        if back {
            // The big mane behind the head: dark outside, warmer toward the face; it falls down over the chest.
            let outer = SceneShape.scallop(pt(0.02 + sway, -0.05), rx: 0.29, ry: 0.33, count: 15, depth: 0.12, seed: 7, twist: 0.15)
            ink.volume(ctx, outer, coat.mane, rim: 1.3)
            let mid = SceneShape.scallop(pt(0.06 + sway * 0.7, -0.03), rx: 0.225, ry: 0.26, count: 13, depth: 0.14, seed: 3, twist: 0.2, start: 0.2)
            ink.volume(ctx, mid, ScenePaint.mixHex(coat.mane, coat.maneLight, 0.5), rim: 0.8, edge: 0.4, light: false)
            let inner = SceneShape.scallop(pt(0.10 + sway * 0.4, -0.01), rx: 0.16, ry: 0.19, count: 11, depth: 0.15, seed: 9, twist: 0.25, start: 0.4)
            ink.volume(ctx, inner, coat.maneLight, rim: 0.5, edge: 0.3, light: false)
            if !ink.rough {
                // Strands combed out from the face: two tones, each one stroke of many lines.
                ctx.saveGState()
                ctx.addPath(outer)
                ctx.clip()
                for tone in 0..<2 {
                    let strands = CGMutablePath()
                    for i in stride(from: tone, to: 26, by: 2) {
                        let ang = -0.5 + Double(i) / 26 * 2 * .pi
                        let r0 = 0.15 + 0.03 * ScenePaint.noise(Double(i), 2), r1 = 0.29 + 0.03 * ScenePaint.noise(Double(i), 6)
                        strands.move(to: pt(0.04 + cos(ang) * r0, -0.03 + sin(ang) * r0 * 1.1))
                        strands.addQuadCurve(to: pt(0.04 + cos(ang + 0.12) * r1, -0.03 + sin(ang + 0.12) * r1 * 1.1),
                                             control: pt(0.05 + cos(ang + 0.06) * (r0 + r1) / 2, -0.03 + sin(ang + 0.06) * (r0 + r1) / 2 * 1.1))
                    }
                    ink.line(ctx, strands, tone == 0 ? ink.dark(coat.mane, 0.4) : coat.maneLight, width: Double(ink.px(1.6)), alpha: 0.55)
                }
                ctx.restoreGState()
            }
        } else if !ink.rough {
            // A few locks that fall in front, along the cheek.
            let locks = (0..<7).map { i in pt(0.06 + Double(i) * 0.012, 0.12 - Double(i) * 0.045) }
            ink.tufts(ctx, along: locks, length: 0.06, angle: -2.3, hex: ScenePaint.mixHex(coat.mane, coat.maneLight, 0.4), width: Double(ink.px(3)), alpha: 0.85, seed: 3)
        }
    }

    /// The tiger's white cheek ruff.
    private func ruff(_ ctx: CGContext, _ ink: SceneInk) {
        let path = SceneShape.blob(SceneShape.shaggy(pt(0.12, -0.02), rx: 0.15, ry: 0.12, count: 14, depth: 0.25, seed: 2, start: 2.6, sweep: 4))
        ink.volume(ctx, path, coat.belly, rim: 0.5)
    }

    private func ear(_ ctx: CGContext, _ ink: SceneInk, at base: CGPoint, p: SceneQuadPose, which: Double) {
        let lay = p.ears < 0 ? -0.9 * -p.ears : 0.15 * p.ears
        ctx.saveGState()
        ctx.translateBy(x: base.x, y: base.y)
        ctx.rotate(by: CGFloat(lay - 0.25 * p.earTwitch))
        let r = kind == .cheetah ? 0.05 : 0.055
        let path = SceneShape.blob([pt(-r, 0), pt(-r * 0.9, r * 1.1), pt(0, r * 1.7), pt(r * 0.9, r * 1.1), pt(r, 0)])
        ink.volume(ctx, path, coat.fur, rim: 0.8)
        ink.flat(ctx, SceneShape.blob([pt(-r * 0.5, r * 0.2), pt(-r * 0.4, r * 0.9), pt(0, r * 1.25), pt(r * 0.45, r * 0.9), pt(r * 0.5, r * 0.2)]),
                 kind == .lion ? 0x5A3018 : 0x2A1A14, alpha: 0.85)
        ctx.restoreGState()
    }

    private func face(_ ctx: CGContext, _ p: SceneQuadPose, _ a: SceneActor, _ ink: SceneInk) {
        let open = p.mouth
        // The lower jaw drops open, about the hinge below the ear.
        let hinge = pt(0.13, -0.03)
        let jaw = SceneShape.blob([pt(0.10, -0.03), pt(0.33, -0.045), pt(0.37, -0.075), pt(0.30, -0.115), pt(0.14, -0.10)].map { $0.sceneTurned(about: hinge, by: -0.55 * open) })
        if open > 0.04 {
            // Inside the mouth.
            let lip = pt(0.40, -0.03)
            let chin = pt(0.37, -0.075).sceneTurned(about: hinge, by: -0.55 * open)
            ink.flat(ctx, SceneShape.blob([hinge.sceneMoved(0.02, 0), lip, pt(Double(chin.x) + 0.01, Double(chin.y) + 0.01), pt(0.2, -0.08).sceneTurned(about: hinge, by: -0.5 * open)]), 0x4A0E14)
            ink.flat(ctx, SceneShape.ellipse(pt(0.26, -0.06).sceneTurned(about: hinge, by: -0.4 * open), 0.07, 0.025), 0xD8606E)
        }
        ink.volume(ctx, jaw, ScenePaint.mixHex(coat.fur, coat.belly, 0.5), rim: 0.3)
        // The skull and muzzle.
        let skull = SceneShape.blob([pt(-0.01, 0.05), pt(0.05, 0.145), pt(0.17, 0.17), pt(0.28, 0.135), pt(0.36, 0.085), pt(0.425, 0.045), pt(0.425, -0.015),
                                     pt(0.37, -0.045), pt(0.24, -0.06), pt(0.10, -0.05)])
        ink.volume(ctx, skull, coat.fur, rim: 1)
        ink.inside(ctx, skull) {
            ink.flat(ctx, SceneShape.ellipse(pt(0.37, -0.005), 0.085, 0.055), coat.belly, alpha: 0.9)
            if kind == .tiger {
                for (i, x) in [0.12, 0.17, 0.22].enumerated() {
                    ink.flat(ctx, SceneShape.tube([pt(x, 0.18), pt(x + 0.01, 0.13), pt(x + 0.03, 0.10 - Double(i) * 0.01)], [0.012, 0.009, 0.002]), coat.mark)
                }
                ink.flat(ctx, SceneShape.tube([pt(0.02, 0.0), pt(0.08, 0.03), pt(0.14, 0.03)], [0.002, 0.012, 0.002]), coat.mark)
            }
            if kind == .cheetah {
                // The tear line from the eye to the mouth.
                ink.flat(ctx, SceneShape.tube([pt(0.27, 0.07), pt(0.30, 0.02), pt(0.345, -0.03)], [0.011, 0.011, 0.007]), coat.mark)
            }
        }
        // Brow, eye and the pale patch below it.
        ink.flat(ctx, SceneShape.ellipse(pt(0.265, 0.055), 0.04, 0.02), coat.belly, alpha: 0.7)
        ink.eye(ctx, at: pt(0.255, 0.085), r: 0.021, iris: coat.eye, skin: coat.fur, blink: p.blink, pupil: 0.45, look: pt(0.4, 0))
        if !ink.rough {
            ink.line(ctx, SceneShape.curve([pt(0.22, 0.105), pt(0.26, 0.112), pt(0.30, 0.10)]), ink.dark(coat.fur, 0.6), width: Double(ink.px(2)), alpha: 0.7)
        }
        // The nose and the line of the mouth.
        let nose = SceneShape.blob([pt(0.385, 0.065), pt(0.43, 0.055), pt(0.435, 0.02), pt(0.405, 0.012)])
        ink.volume(ctx, nose, coat.nose, rim: 0.4, edge: 0.6)
        if !ink.rough {
            ink.line(ctx, SceneShape.curve([pt(0.42, 0.012), pt(0.41, -0.012), pt(0.37, -0.03), pt(0.31, -0.035)]), ink.dark(coat.fur, 0.7), width: Double(ink.px(1.6)), alpha: 0.85)
            ctx.setFillColor(ink.tone(ink.dark(coat.fur, 0.6), 0.7))
            for (x, y) in [(0.34, -0.005), (0.365, -0.015), (0.35, 0.012), (0.375, 0.003)] {
                ctx.fillEllipse(in: CGRect(x: x - 0.004, y: y - 0.004, width: 0.008, height: 0.008))
            }
        }
        if open > 0.1 {
            // Fangs.
            ctx.setFillColor(ink.tone(0xFBF6EA))
            for x in [0.36, 0.40] {
                let f = CGMutablePath()
                f.addLines(between: [pt(x - 0.012, -0.035), pt(x + 0.012, -0.035), pt(x, -0.035 - 0.05 * min(1, open * 1.4))])
                f.closeSubpath()
                ctx.addPath(f)
                ctx.fillPath()
            }
            let tip = pt(0.35, -0.08).sceneTurned(about: hinge, by: -0.55 * open)
            let f = CGMutablePath()
            f.addLines(between: [tip.sceneMoved(-0.012, 0), tip.sceneMoved(0.012, 0), tip.sceneMoved(0.0, 0.04 * open)])
            f.closeSubpath()
            ctx.addPath(f)
            ctx.fillPath()
        }
    }
}
