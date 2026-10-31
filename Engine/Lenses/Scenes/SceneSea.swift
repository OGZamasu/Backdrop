import CoreGraphics
import Foundation

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// Fish of the reef, side on: a body that flexes in a travelling wave, a tail that sweeps, fins that paddle. A blue chromis, a
/// clownfish, a silver minnow, a reef shark and a dolphin are all this one plan in different shapes and colours.
final class SceneFish: ScenePuppet {
    enum Kind { case chromis, clown, minnow, shark, dolphin }
    private let kind: Kind
    private let back: UInt32, belly: UInt32, fin: UInt32
    /// Length over height of the body, and how deep the body is (units).
    private let length: Double, depth: Double

    init(_ kind: Kind) {
        self.kind = kind
        switch kind {
        case .chromis: back = 0x2A62D0; belly = 0x8CC8F4; fin = 0x3A78E0; length = 1.15; depth = 0.62
        case .clown: back = 0xF2701E; belly = 0xF8A04A; fin = 0xF2701E; length = 1.0; depth = 0.62
        case .minnow: back = 0x6E8EA4; belly = 0xE4ECF0; fin = 0xB8C8D4; length = 1.2; depth = 0.48
        case .shark: back = 0x6A7C8A; belly = 0xEEF2F2; fin = 0x5E707E; length = 2.2; depth = 0.64
        case .dolphin: back = 0x6E8496; belly = 0xE6EEF2; fin = 0x5E7486; length = 2.1; depth = 0.54
        }
    }

    /// The body's centre line, nose (k = 0) to tail (k = 1), flexing in a wave that grows toward the tail.
    private func spine(_ a: SceneActor, _ k: Double, beat: Double) -> CGPoint {
        let x = length * (0.5 - k)
        let amp = kind == .dolphin ? 0.07 : 0.03
        let y = sin(beat - k * 3.2) * amp * k * k
        return pt(x, y)
    }

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let fast = a.run > 0.5 || a.phase == .fleeing ? 1.8 : 1
        let beat = a.stride * (kind == .shark ? 0.55 : 0.9) * fast + a.quirk * 6
        let lunge = kind == .shark && a.phase == .acting && a.act == .lunge ? a.phaseTime : -1
        let bite = lunge > 0 ? max(0, min(1, (lunge - a.actSeconds * 0.6) / 0.35)) * max(0, 1 - (lunge - a.actSeconds * 0.6 - 0.7) / 0.4) : 0
        // Outline: points along the top from nose to tail, then back along the belly.
        let n = 9
        var top: [CGPoint] = [], under: [CGPoint] = []
        for i in 0..<n {
            let k = Double(i) / Double(n - 1)
            let c = spine(a, k, beat: beat)
            let girth = profile(k) * depth * 0.5
            let lean = kind == .shark || kind == .dolphin ? 0.25 : 0.05
            top.append(c.sceneMoved(0, girth * (1 + lean)))
            under.append(c.sceneMoved(0, -girth * (1 - lean)))
        }
        let tail = spine(a, 1, beat: beat)
        let tailAngle = cos(beat - 3.2) * 0.35
        let nose = spine(a, 0, beat: beat)

        // The far pectoral fin and the tail fin go behind the body.
        pectoral(ctx, a, ink, at: spine(a, 0.32, beat: beat).sceneMoved(-0.02, -depth * 0.12), far: true, beat: beat)
        tailFin(ctx, ink, at: tail, angle: tailAngle, beat: beat)
        dorsal(ctx, ink, a, beat: beat)

        let body = SceneShape.blob([nose.sceneMoved(0.02, 0)] + top.dropFirst().dropLast() + [tail.sceneMoved(0.0, depth * 0.05), tail.sceneMoved(0.0, -depth * 0.05)]
                                   + under.dropFirst().dropLast().reversed(), tension: 0.9)
        ink.volume(ctx, body, back, rim: 1)
        ink.inside(ctx, body) {
            // Countershading: pale underneath.
            let belly = SceneShape.blob(under.map { $0.sceneMoved(0, depth * 0.02) } + under.reversed().map { $0.sceneMoved(0, depth * (kind == .shark ? 0.17 : 0.24)) }, tension: 0.8)
            ink.flat(ctx, belly, self.belly, alpha: kind == .shark ? 0.8 : 0.95)
            markings(ctx, ink, a, beat: beat)
        }
        if bite > 0.02 { jaws(ctx, ink, nose: nose, open: bite) }
        eye(ctx, ink, a, nose: nose)
        pectoral(ctx, a, ink, at: spine(a, 0.3, beat: beat).sceneMoved(0, -depth * 0.15), far: false, beat: beat)
    }

    /// How deep the body is along its length (0 nose, 1 tail), as a share of the full depth.
    private func profile(_ k: Double) -> Double {
        switch kind {
        case .shark: return k < 0.3 ? 0.45 + 1.8 * k : max(0.12, 1 - (k - 0.3) * 1.25)
        case .dolphin: return k < 0.25 ? 0.4 + 2.4 * k : max(0.1, 1 - (k - 0.25) * 1.2)
        case .clown: return max(0.25, sin(min(1, 0.12 + k * 0.92) * .pi))
        default: return max(0.18, sin(min(1, 0.1 + k * 0.95) * .pi) * (1 - 0.2 * k))
        }
    }

    private func tailFin(_ ctx: CGContext, _ ink: SceneInk, at p: CGPoint, angle: Double, beat: Double) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: CGFloat(angle))
        // The fin turns as it sweeps: it narrows when it is edge-on.
        ctx.scaleBy(x: CGFloat(0.7 + 0.3 * abs(cos(beat))), y: 1)
        let h = depth * (kind == .shark ? 1.1 : kind == .dolphin ? 0.6 : 0.7)
        let path: CGPath
        switch kind {
        case .shark:
            path = SceneShape.blob([pt(0.04, 0.03), pt(-0.22, h * 0.78), pt(-0.28, h * 0.82), pt(-0.12, 0.0), pt(-0.2, -h * 0.5), pt(0.04, -0.04)], tension: 0.5)
        case .dolphin:
            path = SceneShape.blob([pt(0.03, 0.02), pt(-0.1, h * 0.5), pt(-0.2, h * 0.55), pt(-0.12, 0.0), pt(-0.2, -h * 0.55), pt(-0.1, -h * 0.5), pt(0.03, -0.02)], tension: 0.6)
        case .clown:
            path = SceneShape.blob([pt(0.02, 0.02), pt(-0.12, h * 0.5), pt(-0.2, h * 0.3), pt(-0.21, -h * 0.3), pt(-0.12, -h * 0.5), pt(0.02, -0.02)], tension: 0.8)
        default:
            path = SceneShape.blob([pt(0.02, 0.02), pt(-0.16, h * 0.55), pt(-0.12, 0.0), pt(-0.16, -h * 0.55), pt(0.02, -0.02)], tension: 0.6)
        }
        ink.volume(ctx, path, fin, rim: 0.5)
        if kind == .clown { ink.outline(ctx, path, 0x101010, width: 1.6) }
        ctx.restoreGState()
    }

    private func dorsal(_ ctx: CGContext, _ ink: SceneInk, _ a: SceneActor, beat: Double) {
        let base = spine(a, 0.42, beat: beat).sceneMoved(0, profile(0.42) * depth * 0.5 * 1.1)
        let path: CGPath
        switch kind {
        case .shark:
            path = SceneShape.blob([base.sceneMoved(0.16, -0.03), base.sceneMoved(0.0, depth * 0.62), base.sceneMoved(-0.08, depth * 0.58), base.sceneMoved(-0.12, -0.03)], tension: 0.5)
        case .dolphin:
            path = SceneShape.blob([base.sceneMoved(0.08, -0.02), base.sceneMoved(-0.02, depth * 0.45), base.sceneMoved(-0.07, depth * 0.42), base.sceneMoved(-0.08, -0.02)], tension: 0.55)
        case .clown:
            path = SceneShape.blob([base.sceneMoved(0.18, -0.03), base.sceneMoved(0.08, depth * 0.28), base.sceneMoved(-0.08, depth * 0.24), base.sceneMoved(-0.2, -0.03)], tension: 0.9)
        default:
            path = SceneShape.blob([base.sceneMoved(0.14, -0.03), base.sceneMoved(0.0, depth * 0.26), base.sceneMoved(-0.18, depth * 0.12), base.sceneMoved(-0.22, -0.03)], tension: 0.8)
        }
        ink.volume(ctx, path, fin, rim: 0.6)
        if kind == .clown { ink.outline(ctx, path, 0x101010, width: 1.6) }
    }

    private func pectoral(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk, at p: CGPoint, far: Bool, beat: Double) {
        let paddle = sin(beat * 1.3 + (far ? 1.5 : 0)) * 0.35
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: CGFloat(-2.5 + paddle))
        let l = kind == .shark ? depth * 0.85 : kind == .dolphin ? depth * 0.55 : depth * 0.45
        let w = kind == .shark || kind == .dolphin ? depth * 0.16 : 0.03
        let path = SceneShape.blob([pt(0, w), pt(l * 0.7, w * 0.6), pt(l, -w * 0.2), pt(l * 0.5, -w * 0.5), pt(0, -w)], tension: 0.7)
        ink.volume(ctx, path, far ? ink.dark(fin, 0.3) : ScenePaint.mixHex(fin, belly, 0.25), rim: far ? 0 : 0.4, light: !far)
        if kind == .clown, !far { ink.outline(ctx, path, 0x101010, width: 1.4) }
        ctx.restoreGState()
    }

    private func markings(_ ctx: CGContext, _ ink: SceneInk, _ a: SceneActor, beat: Double) {
        switch kind {
        case .clown:
            for (k, w) in [(0.2, 0.08), (0.5, 0.09), (0.86, 0.05)] {
                let c = spine(a, k, beat: beat)
                let band = SceneShape.blob([c.sceneMoved(w * 0.6, depth * 0.6), c.sceneMoved(w * 0.9, 0), c.sceneMoved(w * 0.6, -depth * 0.6), c.sceneMoved(-w * 0.6, -depth * 0.6),
                                            c.sceneMoved(-w * 0.9, 0), c.sceneMoved(-w * 0.6, depth * 0.6)], tension: 0.8)
                ink.flat(ctx, band, 0x101010)
                ink.flat(ctx, SceneShape.blob([c.sceneMoved(w * 0.35, depth * 0.6), c.sceneMoved(w * 0.6, 0), c.sceneMoved(w * 0.35, -depth * 0.6), c.sceneMoved(-w * 0.35, -depth * 0.6),
                                               c.sceneMoved(-w * 0.6, 0), c.sceneMoved(-w * 0.35, depth * 0.6)], tension: 0.8), 0xF8F6F0)
            }
        case .minnow:
            let line = (0...6).map { i -> CGPoint in let k = 0.15 + Double(i) * 0.12; return spine(a, k, beat: beat).sceneMoved(0, 0.02) }
            ink.line(ctx, SceneShape.curve(line), 0x3A4E5E, width: depth * 0.08, alpha: 0.7)
            ink.line(ctx, SceneShape.curve(line.map { $0.sceneMoved(0, depth * 0.1) }), 0xF4F8FA, width: depth * 0.05, alpha: 0.8)
        case .shark:
            guard !ink.rough else { return }
            ink.lines(ctx, (0..<5).map { i -> [CGPoint] in
                let c = spine(a, 0.2 + Double(i) * 0.025, beat: beat)
                return [c.sceneMoved(0, depth * 0.12), c.sceneMoved(-0.012, -depth * 0.04)]
            }, 0x3A4652, width: Double(ink.px(1.6)), alpha: 0.7)
        case .chromis:
            ink.flat(ctx, SceneShape.ellipse(spine(a, 0.3, beat: beat).sceneMoved(0, depth * 0.18), 0.16, 0.05), 0xA8E0FF, alpha: 0.35)
        case .dolphin:
            ink.flat(ctx, SceneShape.ellipse(spine(a, 0.18, beat: beat).sceneMoved(0, -depth * 0.05), 0.12, 0.04), 0xB8C8D4, alpha: 0.5)
        }
    }

    private func eye(_ ctx: CGContext, _ ink: SceneInk, _ a: SceneActor, nose: CGPoint) {
        switch kind {
        case .shark:
            ink.eye(ctx, at: nose.sceneMoved(-length * 0.075, depth * 0.1), r: depth * 0.05, iris: 0x101418, skin: back, blink: 0, pupil: 0.7)
        case .dolphin:
            // The beak and a friendly eye, with a smile line.
            ink.eye(ctx, at: nose.sceneMoved(-length * 0.1, depth * 0.06), r: depth * 0.055, iris: 0x1A1A20, skin: back, blink: a.blink, pupil: 0.65)
            if !ink.rough {
                ink.line(ctx, SceneShape.curve([nose.sceneMoved(-0.0, -depth * 0.04), nose.sceneMoved(-length * 0.04, -depth * 0.1), nose.sceneMoved(-length * 0.075, -depth * 0.03)]), 0x3A4652, width: Double(ink.px(1.6)))
            }
        default:
            let r = depth * (kind == .minnow ? 0.12 : 0.13)
            ink.eye(ctx, at: nose.sceneMoved(-length * 0.16, depth * 0.1), r: r, iris: kind == .clown ? 0x2A1A10 : 0x101418, skin: back, blink: 0, pupil: 0.55, white: kind != .minnow)
            if !ink.rough {
                ink.line(ctx, SceneShape.curve([nose.sceneMoved(0.0, -depth * 0.05), nose.sceneMoved(-0.04, -depth * 0.07)]), ink.dark(back, 0.6), width: Double(ink.px(1.4)))
            }
        }
    }

    /// The shark opens wide at the end of its rush.
    private func jaws(_ ctx: CGContext, _ ink: SceneInk, nose: CGPoint, open: Double) {
        let hinge = nose.sceneMoved(-length * 0.16, -depth * 0.12)
        let mouth = SceneShape.blob([hinge, nose.sceneMoved(-length * 0.03, -depth * 0.16), nose.sceneMoved(-length * 0.02, -depth * (0.16 + 0.55 * open)), hinge.sceneMoved(0.02, -depth * 0.3 * open)])
        ink.flat(ctx, mouth, 0x5A1A24)
        ctx.setFillColor(ink.tone(0xF8F4EC))
        for i in 0..<6 {
            let x = Double(nose.x) - length * 0.035 - Double(i) * length * 0.018
            let y = Double(nose.y) - depth * 0.16
            ctx.move(to: pt(x - 0.016, y)); ctx.addLine(to: pt(x + 0.016, y)); ctx.addLine(to: pt(x, y - depth * 0.09)); ctx.fillPath()
            let y2 = y - depth * 0.5 * open
            ctx.move(to: pt(x - 0.016, y2)); ctx.addLine(to: pt(x + 0.016, y2)); ctx.addLine(to: pt(x, y2 + depth * 0.09)); ctx.fillPath()
        }
    }
}

/// A green sea turtle: rows with its long front flippers, waves one at you.
final class SceneTurtle: ScenePuppet {
    private let shell: UInt32 = 0x7A6A38
    private let skin: UInt32 = 0x8AA06E

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let stroke = sin(a.time * 1.6 + a.quirk * 7)
        let wave = a.phase == .acting ? a.acting() : 0
        func flipper(_ root: CGPoint, length: Double, angle: Double, far: Bool) {
            ctx.saveGState()
            ctx.translateBy(x: root.x, y: root.y)
            ctx.rotate(by: CGFloat(angle))
            let path = SceneShape.blob([pt(0, 0.04), pt(length * 0.5, 0.06), pt(length, 0.01), pt(length * 0.6, -0.04), pt(0, -0.04)], tension: 0.8)
            ink.volume(ctx, path, far ? ink.dark(skin, 0.3) : skin, rim: far ? 0 : 0.6, light: !far)
            ctx.restoreGState()
        }
        flipper(pt(0.12, 0.0), length: 0.42, angle: -2.4 + stroke * 0.5, far: true)
        flipper(pt(-0.28, -0.04), length: 0.16, angle: -2.6 + stroke * 0.3, far: true)
        // Head on a stout neck.
        ctx.saveGState()
        ctx.translateBy(x: 0.30, y: 0.02)
        ctx.rotate(by: CGFloat(0.1 * sin(a.time * 0.9) + a.look * 0.3))
        let head = SceneShape.blob([pt(-0.06, 0.06), pt(0.06, 0.08), pt(0.16, 0.04), pt(0.17, -0.02), pt(0.08, -0.06), pt(-0.06, -0.05)])
        ink.volume(ctx, head, skin, rim: 1)
        ink.inside(ctx, head) {
            for (x, y, r) in [(0.06, 0.04, 0.02), (0.1, 0.0, 0.016), (0.02, 0.0, 0.02)] { ink.flat(ctx, SceneShape.ellipse(pt(x, y), r, r * 0.8), 0x6A8050, alpha: 0.8) }
        }
        ink.eye(ctx, at: pt(0.11, 0.03), r: 0.016, iris: 0x2A1A10, skin: skin, blink: a.blink, pupil: 0.6)
        ctx.restoreGState()
        // The shell: a domed carapace with plates.
        let carapace = SceneShape.blob([pt(0.30, 0.02), pt(0.22, 0.18), pt(0.0, 0.26), pt(-0.24, 0.20), pt(-0.36, 0.04), pt(-0.30, -0.06), pt(0.0, -0.08), pt(0.24, -0.05)])
        ink.volume(ctx, carapace, shell, rim: 1.1)
        ink.inside(ctx, carapace) {
            ink.flat(ctx, SceneShape.blob([pt(0.3, -0.02), pt(0.0, -0.04), pt(-0.32, -0.02), pt(-0.32, -0.1), pt(0.3, -0.1)]), 0xD8C890)
            guard !ink.rough else { return }
            for (x, y) in [(-0.16, 0.12), (0.0, 0.16), (0.14, 0.10), (-0.08, 0.04), (0.08, 0.03), (-0.24, 0.05)] {
                let plate = SceneShape.blob((0..<6).map { i -> CGPoint in let ang = Double(i) / 6 * 2 * .pi; return pt(x + cos(ang) * 0.075, y + sin(ang) * 0.055) }, tension: 0.4)
                ink.flat(ctx, plate, 0x9A8A4A, alpha: 0.8)
                ink.outline(ctx, plate, 0x5A4A22, width: 1)
            }
        }
        flipper(pt(-0.26, -0.05), length: 0.16, angle: -2.9 + stroke * 0.3, far: false)
        // The near front flipper rows, or lifts to wave.
        let rowAngle = -2.2 + stroke * 0.6
        flipper(pt(0.16, -0.02), length: 0.44, angle: rowAngle * (1 - wave) + (0.9 + 0.35 * sin(a.time * 9)) * wave, far: false)
    }
}

/// An octopus: a soft mantle, big eyes, and arms that curl and uncurl; it waves one.
final class SceneOctopus: ScenePuppet {
    private let skin: UInt32 = 0xD8583A

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let wave = a.phase == .acting ? a.acting() : 0
        let swim = a.walk
        // Arms: tubes that hang and curl, rippling.
        for i in 0..<6 {
            let far = i % 2 == 0
            let base = pt(-0.05 + Double(i) * 0.05, -0.08)
            var angle = -.pi / 2 - 0.9 + Double(i) * 0.36 - swim * 0.5
            var p = base
            var spine = [p]
            let curl = 0.25 + 0.15 * sin(a.time * 1.7 + Double(i) * 1.3 + a.quirk * 5)
            let waving = i == 5 && wave > 0
            for k in 1..<9 {
                let kk = Double(k) / 8
                angle += waving ? (0.45 * wave + 0.25 * sin(a.time * 8 - kk * 4)) : curl * kk * (i < 3 ? -1 : 1) + 0.1 * sin(a.time * 2.2 - kk * 4 + Double(i))
                p = p.sceneMoved(cos(angle) * 0.06, sin(angle) * 0.06)
                spine.append(p)
            }
            let path = SceneShape.tube(spine, (0..<9).map { 0.05 * (1 - 0.8 * Double($0) / 8) })
            ink.volume(ctx, path, far ? ink.dark(skin, 0.3) : skin, rim: far ? 0 : 0.6, light: !far)
            if !far, !ink.rough {
                ctx.setFillColor(ink.tone(0xF2C0A8))
                for k in stride(from: 1, to: 8, by: 2) { ctx.fillEllipse(in: CGRect(x: Double(spine[k].x) - 0.01, y: Double(spine[k].y) - 0.012, width: 0.02, height: 0.016)) }
            }
        }
        // Mantle: a big soft bag that breathes.
        let breathe = 1 + 0.04 * sin(a.time * 2.4 + a.quirk * 5)
        let mantle = SceneShape.blob([pt(0.18, -0.05), pt(0.18, 0.12), pt(0.06, 0.34 * breathe), pt(-0.12, 0.38 * breathe), pt(-0.24, 0.24), pt(-0.18, 0.02), pt(-0.02, -0.1)])
        ink.volume(ctx, mantle, skin, rim: 1.1)
        if !ink.rough {
            ink.inside(ctx, mantle) {
                for (x, y, r) in [(-0.1, 0.25, 0.025), (-0.02, 0.3, 0.018), (-0.16, 0.15, 0.02), (0.05, 0.2, 0.015)] { ink.flat(ctx, SceneShape.ellipse(pt(x, y), r, r), 0xB0402A, alpha: 0.7) }
            }
        }
        for (x, r) in [(0.06, 0.05), (0.15, 0.045)] {
            ink.volume(ctx, SceneShape.ellipse(pt(x, 0.04), r * 1.2, r * 1.2), skin, rim: 0.5)
            ink.eye(ctx, at: pt(x + 0.005, 0.04), r: r * 0.85, iris: 0xF0C850, skin: skin, blink: a.blink, pupil: 0.5, white: false)
        }
    }
}

/// A pufferfish: a plump, spotted swimmer that blows up into a spiky ball when it means it.
final class ScenePuffer: ScenePuppet {
    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let puff = a.phase == .acting ? a.acting(rise: 0.18, fall: 0.5) : (a.phase == .fleeing ? 0.6 : 0)
        let r = 0.32 + 0.16 * puff
        let fin = sin(a.time * 9 + a.quirk * 4) * 0.4
        ctx.saveGState()
        ctx.translateBy(x: -r * 0.95, y: 0)
        ctx.rotate(by: CGFloat(fin * 0.4))
        ink.volume(ctx, SceneShape.blob([pt(0.02, 0.03), pt(-0.12, 0.1), pt(-0.16, 0.0), pt(-0.12, -0.1), pt(0.02, -0.03)]), 0xD8B048, rim: 0.4)
        ctx.restoreGState()
        if puff > 0.1 {
            // Spines stand up all over.
            ctx.setFillColor(ink.tone(0xC89A3A))
            for i in 0..<18 {
                let ang = Double(i) / 18 * 2 * .pi
                let base = pt(cos(ang) * r * 0.95, sin(ang) * r * 0.95)
                let tip = pt(cos(ang) * (r + 0.07 * puff), sin(ang) * (r + 0.07 * puff))
                let side = pt(-sin(ang) * 0.02, cos(ang) * 0.02)
                ctx.move(to: base.sceneMoved(Double(side.x), Double(side.y))); ctx.addLine(to: tip); ctx.addLine(to: base.sceneMoved(-Double(side.x), -Double(side.y))); ctx.fillPath()
            }
        }
        let body = SceneShape.ellipse(.zero, r, r * (0.82 + 0.18 * puff))
        ink.volume(ctx, body, 0xE8C860, rim: 1.1)
        ink.inside(ctx, body) {
            ink.flat(ctx, SceneShape.ellipse(pt(0, -r * 0.55), r * 0.95, r * 0.5), 0xF8F0D8)
            if !ink.rough {
                for i in 0..<10 {
                    let x = (ScenePaint.noise(Double(i) * 3.1, 2) - 0.5) * r * 1.6, y = ScenePaint.noise(Double(i) * 2.3, 5) * r * 0.8
                    ink.flat(ctx, SceneShape.ellipse(pt(x, y), 0.018, 0.018), 0x6A4A1A, alpha: 0.8)
                }
            }
        }
        ctx.saveGState()
        ctx.translateBy(x: r * 0.2, y: -r * 0.3)
        ctx.rotate(by: CGFloat(-1.2 - fin))
        ink.volume(ctx, SceneShape.blob([pt(0, 0.02), pt(0.1, 0.04), pt(0.12, 0.0), pt(0, -0.02)]), 0xD8B048, rim: 0.4)
        ctx.restoreGState()
        ink.eye(ctx, at: pt(r * 0.45, r * 0.3), r: 0.06, iris: 0x2A3A20, skin: 0xE8C860, blink: a.blink, pupil: 0.55, white: true)
        ink.flat(ctx, SceneShape.ellipse(pt(r * 0.98, -r * 0.05), 0.03, 0.025 + 0.02 * puff), 0xC86A4A)
    }
}

/// A jellyfish: a see-through bell that pulses, frilly arms and long trailing threads, and a glow.
final class SceneJelly: ScenePuppet {
    var facesViewer: Bool { true }

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let pulse = sin(a.time * 2.2 + a.quirk * 6)
        let flash = a.phase == .acting ? a.acting() : 0
        ink.glass = 0.78
        // Long threads trailing below, swaying in the current.
        ink.lines(ctx, (0..<7).map { i -> [CGPoint] in
            let x0 = -0.2 + Double(i) * 0.066
            return (0..<8).map { k -> CGPoint in
                let kk = Double(k) / 7
                return pt(x0 * (1 - 0.3 * kk) + sin(a.time * 1.5 + kk * 3 + Double(i)) * 0.04 * kk, 0.02 - kk * 0.62)
            }
        }, 0xF2B8E8, width: Double(ink.px(1.6)), alpha: 0.55)
        // Frilly mouth arms.
        for i in 0..<3 {
            let x0 = -0.06 + Double(i) * 0.06
            let spine = (0..<6).map { k -> CGPoint in let kk = Double(k) / 5; return pt(x0 + sin(a.time * 1.8 + kk * 4 + Double(i) * 2) * 0.04 * kk, 0.0 - kk * 0.36) }
            ink.flat(ctx, SceneShape.tube(spine, [0.03, 0.035, 0.03, 0.025, 0.018, 0.008]), 0xE890D8, alpha: 0.75)
        }
        // The bell, with the glow inside it.
        let w = 0.3 * (1 + 0.08 * pulse), h = 0.26 * (1 - 0.08 * pulse)
        let bell = SceneShape.blob([pt(-w, 0.0), pt(-w * 0.95, h * 0.55), pt(-w * 0.55, h * 0.95), pt(0, h), pt(w * 0.55, h * 0.95), pt(w * 0.95, h * 0.55), pt(w, 0.0),
                                    pt(w * 0.5, 0.04), pt(0, 0.02), pt(-w * 0.5, 0.04)])
        ink.volume(ctx, bell, 0xF0A0E0, rim: 1.2)
        ink.inside(ctx, bell) {
            ink.flat(ctx, SceneShape.ellipse(pt(0, h * 0.35), w * 0.5, h * 0.35), 0xFFE0F8, alpha: 0.5 + 0.4 * flash)
            for k in 0..<4 {
                let x = -w * 0.5 + Double(k) * w * 0.33
                ink.flat(ctx, SceneShape.ellipse(pt(x, h * 0.3), w * 0.09, h * 0.18), 0xC860C0, alpha: 0.5)
            }
        }
        ink.glass = 1
    }
}
