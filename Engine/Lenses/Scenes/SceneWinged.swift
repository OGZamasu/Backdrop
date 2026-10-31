import CoreGraphics
import Foundation

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// How high the wings are raised in the beat (radians above level). Seen from the side and a little from below, the near wing then
/// shows as `sin(e - view)` of its length and the far one as `sin(e + view)`: held level they spread one down and one up, which reads
/// as a bird gliding overhead; beating, they sweep up and down together.
private func sceneWingElevation(_ a: SceneActor, rate: Double, soar: Bool) -> Double {
    if soar { return 0.1 + 0.07 * sin(a.time * 1.3 + a.quirk * 5) }
    let s = sin(a.stride * rate + a.quirk * 6)
    return 0.25 + 0.95 * s
}

/// Birds: a soaring vulture and a scarlet macaw. Side on, with the wings raised and lowered in the beat, folded when they sit.
final class SceneBird: ScenePuppet {
    enum Kind { case vulture, parrot }
    private let kind: Kind
    private struct Plumage {
        var body: UInt32
        var belly: UInt32
        var covert: UInt32
        var flight: UInt32
        var band: UInt32
        var head: UInt32
        var beak: UInt32
        var beakTip: UInt32
        var eye: UInt32
        var leg: UInt32
        var tail: UInt32
    }
    private let plumage: Plumage

    init(_ kind: Kind) {
        self.kind = kind
        switch kind {
        case .vulture:
            plumage = Plumage(body: 0x5A4232, belly: 0x7A6048, covert: 0x5E4634, flight: 0x2A201A, band: 0xC8B8A0, head: 0xC9A090, beak: 0x4A4440,
                              beakTip: 0xD8D0C0, eye: 0x6A2A18, leg: 0x8A8078, tail: 0x2E241C)
        case .parrot:
            plumage = Plumage(body: 0xD82A26, belly: 0xE8402E, covert: 0xF2C230, flight: 0x2756C4, band: 0x3DA04A, head: 0xE0302A, beak: 0xEDE4D2,
                              beakTip: 0x2A2420, eye: 0xF2E8A0, leg: 0x8A7A70, tail: 0xC8282A)
        }
    }

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let perched = a.landed && a.act == .perch && a.phase == .acting
        if perched { drawPerched(ctx, a, ink) } else { drawFlying(ctx, a, ink) }
    }

    // MARK: Flying

    private func drawFlying(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let soar = kind == .vulture && a.phase != .fleeing && a.phase != .approaching
        var e = sceneWingElevation(a, rate: kind == .vulture ? 0.55 : 1.0, soar: soar)
        // Landing: the wings flare up and the feet come forward.
        let flare = a.phase == .acting && a.act == .perch && !a.landed && a.phaseTime > 1.3 ? 1.0 : 0
        if flare > 0 { e = 0.9 + 0.2 * sin(a.time * 14) }
        // Seen from below as it soars, the wings spread one down toward us and one up and away; beating, they sweep together.
        let view = soar ? 0.85 : 0.45
        wing(ctx, a, ink, lift: sin(e + view), far: true)
        tail(ctx, a, ink, spread: flare)
        if flare > 0 { legs(ctx, ink, perched: false) }
        body(ctx, a, ink, upright: 0.15 * flare)
        head(ctx, a, ink, at: pt(0.27, 0.11), upright: 0)
        wing(ctx, a, ink, lift: sin(e - view), far: false)
    }

    private func body(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk, upright: Double) {
        let path = SceneShape.blob([pt(0.24, 0.06), pt(0.18, -0.07), pt(0.04, -0.12), pt(-0.14, -0.10), pt(-0.28, -0.03), pt(-0.20, 0.05),
                                    pt(-0.04, 0.10), pt(0.12, 0.13)])
        ink.volume(ctx, path, plumage.body, rim: 1)
        ink.inside(ctx, path) {
            ink.flat(ctx, SceneShape.ellipse(pt(0.06, -0.09), 0.17, 0.06), plumage.belly, alpha: 0.8)
        }
    }

    private func tail(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk, spread: Double) {
        let long = kind == .parrot
        let length = long ? 0.42 : 0.2
        let droop = long ? -0.12 : -0.04
        let fan = 0.03 + spread * 0.05 + (long ? 0 : 0.02)
        let sway = sin(a.time * 2 + a.quirk * 4) * 0.02
        let root = pt(-0.22, -0.02)
        let tip = root.sceneMoved(-length, droop + sway)
        let path = SceneShape.blob([root.sceneMoved(0.02, 0.04), tip.sceneMoved(0, fan), tip.sceneMoved(-0.02, -fan * 0.2), tip.sceneMoved(0.0, -fan), root.sceneMoved(0.02, -0.05)], tension: 0.7)
        ink.volume(ctx, path, plumage.tail, rim: 0.6)
        if long, !ink.rough {
            ink.inside(ctx, path) {
                ink.flat(ctx, SceneShape.blob([root.sceneMoved(-0.1, 0.0), tip.sceneMoved(0.04, 0.0), tip.sceneMoved(0.0, -fan), root.sceneMoved(-0.1, -0.04)]), plumage.flight, alpha: 0.9)
            }
        }
    }

    /// A wing: coverts at the root, a band, then the long flight feathers fingering out at the tip.
    private func wing(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk, lift: Double, far: Bool) {
        let length = kind == .vulture ? 0.72 : 0.5
        let flex = sin(a.time * 2.1 + a.quirk) * 0.03
        ctx.saveGState()
        ctx.translateBy(x: far ? -0.04 : 0.02, y: far ? 0.1 : 0.07)
        ctx.rotate(by: CGFloat(0.3 - 0.1 * lift))
        ctx.scaleBy(x: 1, y: CGFloat(max(-0.85, min(1, lift))))
        let shade: (UInt32) -> UInt32 = { far ? ink.dark($0, 0.3) : $0 }
        let chord = kind == .vulture ? 0.24 : 0.16
        let lead = [pt(0.06, 0.0), pt(0.09, length * 0.35), pt(0.05 + flex, length * 0.8), pt(-0.01 + flex, length)]
        let trail = [pt(-chord * 0.9 + flex, length * 0.86), pt(-chord, length * 0.55), pt(-chord * 0.85, length * 0.25), pt(-chord * 0.7, 0.0)]
        let wing = SceneShape.blob(lead + trail, tension: 0.8)
        ink.volume(ctx, wing, shade(plumage.flight), rim: far ? 0 : 0.8, light: !far)
        // Flight feathers: separate fingers at the tip.
        if !ink.rough {
            let fingers = kind == .vulture ? 6 : 4
            for i in 0..<fingers {
                let k = Double(i) / Double(fingers - 1)
                let base = pt(-chord * 0.4 * k + 0.02, length * (0.78 - 0.18 * k))
                let tip = base.sceneMoved(-0.05 - 0.04 * k + flex, length * (0.26 - 0.1 * k))
                ink.flat(ctx, SceneShape.limb(base, tip, 0.022, 0.006), shade(plumage.flight))
            }
        }
        // Coverts and the coloured band.
        let covert = SceneShape.blob([pt(0.06, 0.0), pt(0.09, length * 0.35), pt(0.06, length * 0.55), pt(-chord * 0.4, length * 0.5), pt(-chord * 0.75, length * 0.25), pt(-chord * 0.65, 0.0)], tension: 0.8)
        ink.inside(ctx, wing) {
            let band = SceneShape.blob([pt(0.06, length * 0.2), pt(0.08, length * 0.6), pt(-chord * 0.6, length * 0.62), pt(-chord * 0.9, length * 0.3)], tension: 0.8)
            ink.flat(ctx, band, shade(plumage.band), alpha: kind == .vulture ? 0.85 : 1)
            ink.flat(ctx, covert, shade(plumage.covert))
            if !ink.rough {
                ink.lines(ctx, (0..<4).map { k -> [CGPoint] in
                    let y = length * (0.12 + Double(k) * 0.1)
                    return [pt(0.06, y), pt(-chord * 0.3, y + 0.02), pt(-chord * 0.7, y - 0.01)]
                }, ink.dark(plumage.covert, 0.35), width: Double(ink.px(1.1)), alpha: 0.5)
            }
        }
        ctx.restoreGState()
    }

    // MARK: Sitting

    private func drawPerched(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        legs(ctx, ink, perched: true)
        let upright = kind == .parrot
        // The tail hangs below the perch.
        let tailRoot = upright ? pt(-0.05, -0.2) : pt(-0.18, -0.14)
        let tailEnd = upright ? pt(-0.16, -0.78) : pt(-0.32, -0.42)
        let tailPath = SceneShape.blob([tailRoot.sceneMoved(0.05, 0.02), tailEnd.sceneMoved(0.03, 0), tailEnd.sceneMoved(-0.03, 0.02), tailRoot.sceneMoved(-0.06, 0.03)], tension: 0.6)
        ink.volume(ctx, tailPath, plumage.tail, rim: 0.6)
        if upright { ink.inside(ctx, tailPath) { ink.flat(ctx, SceneShape.ellipse(tailEnd.sceneMoved(0, 0.12), 0.05, 0.22), plumage.flight) } }
        let body = upright
            ? SceneShape.blob([pt(0.12, 0.16), pt(0.13, 0.0), pt(0.08, -0.16), pt(-0.02, -0.25), pt(-0.10, -0.16), pt(-0.12, 0.04), pt(-0.06, 0.2), pt(0.04, 0.24)])
            : SceneShape.blob([pt(0.17, 0.12), pt(0.20, -0.04), pt(0.08, -0.22), pt(-0.10, -0.23), pt(-0.22, -0.14), pt(-0.25, 0.03), pt(-0.12, 0.17), pt(0.04, 0.2)])
        ink.volume(ctx, body, plumage.body, rim: 1)
        ink.inside(ctx, body) { ink.flat(ctx, SceneShape.ellipse(upright ? pt(0.08, -0.05) : pt(0.1, -0.08), 0.09, 0.16), plumage.belly, alpha: 0.85) }
        // The folded wing along the side, flight feathers crossing at the back.
        let fold = upright
            ? SceneShape.blob([pt(0.04, 0.2), pt(-0.10, 0.12), pt(-0.16, -0.12), pt(-0.18, -0.42), pt(-0.10, -0.30), pt(0.02, -0.08), pt(0.08, 0.1)], tension: 0.8)
            : SceneShape.blob([pt(0.10, 0.16), pt(-0.06, 0.19), pt(-0.24, 0.08), pt(-0.42, -0.30), pt(-0.30, -0.25), pt(-0.10, -0.12), pt(0.10, 0.0)], tension: 0.8)
        ink.volume(ctx, fold, plumage.flight, rim: 0.7)
        ink.inside(ctx, fold) {
            ink.flat(ctx, SceneShape.ellipse(upright ? pt(-0.02, 0.08) : pt(-0.02, 0.1), upright ? 0.1 : 0.15, upright ? 0.14 : 0.09), plumage.covert)
            ink.flat(ctx, SceneShape.ellipse(upright ? pt(-0.06, -0.06) : pt(-0.16, 0.0), upright ? 0.08 : 0.09, upright ? 0.06 : 0.07), plumage.band, alpha: 0.9)
            if !ink.rough {
                ink.lines(ctx, (0..<3).map { k -> [CGPoint] in
                    let y = upright ? -0.14 - Double(k) * 0.07 : -0.02 - Double(k) * 0.06
                    return [pt(upright ? 0.0 : -0.04, y), pt(upright ? -0.12 : -0.3, y - 0.05)]
                }, ink.dark(plumage.flight, 0.4), width: Double(ink.px(1.2)), alpha: 0.6)
            }
        }
        // Head up, turning to look about, bobbing as it chatters.
        let bob = a.phaseTime < 3 ? 0.015 * sin(a.time * 9) : 0
        head(ctx, a, ink, at: upright ? pt(0.06, 0.3 + bob) : pt(0.17, 0.2 + bob), upright: (upright ? 0.15 : -0.1) + 0.2 * a.drift(0.6, 2))
    }

    private func legs(_ ctx: CGContext, _ ink: SceneInk, perched: Bool) {
        let top = perched ? pt(0.0, -0.18) : pt(-0.08, -0.08)
        let foot = perched ? pt(0.02, -0.48) : pt(0.04, -0.3)
        for dx in [-0.03, 0.03] {
            ink.line(ctx, SceneShape.curve([top.sceneMoved(dx, 0), foot.sceneMoved(dx, 0)]), plumage.leg, width: 0.022)
            ink.line(ctx, SceneShape.curve([foot.sceneMoved(dx - 0.04, 0.01), foot.sceneMoved(dx + 0.05, -0.01)]), plumage.leg, width: 0.016)
        }
    }

    private func head(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk, at c: CGPoint, upright: Double) {
        let open = a.phase == .acting || a.phase == .noticing ? max(0, sin(a.time * 11)) * (a.phaseTime < 1.5 ? 1 : 0) : 0
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(upright + a.look * 0.5 * a.alert))
        switch kind {
        case .vulture:
            // The pale ruff, a bare neck and a heavy hooked beak.
            ink.volume(ctx, SceneShape.scallop(pt(-0.06, -0.04), rx: 0.08, ry: 0.06, count: 9, depth: 0.2, seed: 3), 0xEDE4D6, rim: 0.6)
            ink.volume(ctx, SceneShape.blob([pt(-0.04, -0.03), pt(-0.02, 0.05), pt(0.05, 0.07), pt(0.09, 0.03), pt(0.06, -0.03)]), plumage.head, rim: 0.8)
            ink.volume(ctx, SceneShape.blob([pt(0.07, 0.04), pt(0.15, 0.035), pt(0.17, 0.0), pt(0.15, -0.02), pt(0.13, 0.0), pt(0.07, -0.01)], tension: 0.7), plumage.beak, rim: 0.5)
            ink.flat(ctx, SceneShape.ellipse(pt(0.155, 0.0), 0.014, 0.014), plumage.beakTip)
            ink.eye(ctx, at: pt(0.045, 0.035), r: 0.011, iris: plumage.eye, skin: plumage.head, blink: a.blink, pupil: 0.5)
        case .parrot:
            ink.volume(ctx, SceneShape.ellipse(pt(0.0, 0.0), 0.085, 0.075), plumage.head, rim: 1)
            ink.flat(ctx, SceneShape.blob([pt(0.0, 0.02), pt(0.04, 0.045), pt(0.08, 0.02), pt(0.075, -0.03), pt(0.02, -0.035)]), 0xF4EEE8)
            if !ink.rough {
                ink.lines(ctx, (0..<3).map { k in [pt(0.03, 0.01 - Double(k) * 0.015), pt(0.07, 0.005 - Double(k) * 0.012)] }, 0x8A2A26, width: Double(ink.px(1)), alpha: 0.7)
            }
            // The great curved beak: pale above, dark below; it opens to squawk.
            ctx.saveGState()
            ctx.translateBy(x: 0.06, y: -0.02)
            ctx.rotate(by: CGFloat(-0.35 * open))
            ink.volume(ctx, SceneShape.blob([pt(0.0, -0.005), pt(0.06, -0.01), pt(0.07, -0.04), pt(0.03, -0.05), pt(0.0, -0.035)]), plumage.beakTip, rim: 0.3)
            ctx.restoreGState()
            ink.volume(ctx, SceneShape.blob([pt(0.05, 0.03), pt(0.11, 0.035), pt(0.145, 0.0), pt(0.14, -0.06), pt(0.12, -0.04), pt(0.1, -0.01), pt(0.06, -0.02)], tension: 0.8),
                       plumage.beak, rim: 0.7)
            ink.eye(ctx, at: pt(0.035, 0.02), r: 0.013, iris: plumage.eye, skin: 0xF4EEE8, blink: a.blink, pupil: 0.45)
        }
        ctx.restoreGState()
    }
}

/// Fliers on skin wings: a pterodactyl with a long crested head, and a bat with big ears. The wing is stretched between long fingers.
final class SceneMembrane: ScenePuppet {
    enum Kind { case pterodactyl, bat }
    private let kind: Kind
    private let skin: UInt32
    private let membrane: UInt32

    init(_ kind: Kind) {
        self.kind = kind
        switch kind {
        case .pterodactyl: skin = 0x8A5A44; membrane = 0xB0705A
        case .bat: skin = 0x1E1824; membrane = 0x2E2236
        }
    }

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let glide = kind == .pterodactyl && a.phase == .wandering && sin(a.time * 0.4 + a.quirk * 9) > 0
        let e = glide ? 0.15 + 0.05 * sin(a.time * 2) : sceneWingElevation(a, rate: kind == .bat ? 1.6 : 0.8, soar: false)
        let view = glide ? 0.45 : 0.3
        wing(ctx, a, ink, lift: sin(e + view), far: true)
        body(ctx, a, ink)
        wing(ctx, a, ink, lift: sin(e - view), far: false)
    }

    private func body(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        switch kind {
        case .pterodactyl:
            ink.volume(ctx, SceneShape.blob([pt(0.12, 0.03), pt(0.04, -0.06), pt(-0.12, -0.05), pt(-0.18, 0.0), pt(-0.06, 0.05)]), skin, rim: 0.8)
            ink.line(ctx, SceneShape.curve([pt(-0.16, 0.0), pt(-0.26, -0.04)]), skin, width: 0.018)
            // The head on a short neck: a long beak forward, a crest back.
            ctx.saveGState()
            ctx.translateBy(x: 0.12, y: 0.04)
            let open = a.phase == .acting ? max(0, sin(a.time * 7)) * 0.3 : 0
            ctx.rotate(by: CGFloat(a.look * 0.4 * a.alert))
            ink.volume(ctx, SceneShape.blob([pt(0.0, 0.03), pt(-0.16, 0.10), pt(-0.12, 0.05), pt(-0.02, -0.01)], tension: 0.6), 0xC8503A, rim: 0.6)
            ctx.saveGState()
            ctx.rotate(by: CGFloat(-open))
            ink.volume(ctx, SceneShape.blob([pt(0.02, -0.005), pt(0.28, -0.03), pt(0.02, -0.03)], tension: 0.4), 0xD8B090, rim: 0.3)
            ctx.restoreGState()
            ink.volume(ctx, SceneShape.blob([pt(-0.03, 0.03), pt(0.06, 0.04), pt(0.30, 0.0), pt(0.06, -0.015), pt(-0.03, -0.02)], tension: 0.5), 0xD8B090, rim: 0.6)
            ink.eye(ctx, at: pt(0.03, 0.015), r: 0.012, iris: 0xE8B020, skin: skin, blink: a.blink, pupil: 0.4, slit: true)
            ctx.restoreGState()
        case .bat:
            ink.volume(ctx, SceneShape.ellipse(pt(0.0, 0.0), 0.1, 0.08), skin, rim: 0.8)
            ink.inside(ctx, SceneShape.ellipse(pt(0.0, 0.0), 0.1, 0.08)) { ink.flat(ctx, SceneShape.ellipse(pt(0.02, 0.03), 0.08, 0.05), 0x6A5244, alpha: 0.7) }
            // Big ears, a pug nose, two tiny fangs.
            for (x, tilt) in [(0.05, -0.2), (0.11, -0.45)] {
                ink.volume(ctx, SceneShape.blob([pt(x - 0.03, 0.07), pt(x - 0.02, 0.17), pt(x + 0.02, 0.2), pt(x + 0.04, 0.07)].map { $0.sceneTurned(about: pt(x, 0.07), by: tilt * 0.3) }), skin, rim: 0.6)
            }
            let face = SceneShape.ellipse(pt(0.11, 0.035), 0.06, 0.05)
            ink.volume(ctx, face, skin, rim: 0.8)
            ink.flat(ctx, SceneShape.ellipse(pt(0.165, 0.03), 0.018, 0.014), 0x8A6070)
            ink.eye(ctx, at: pt(0.12, 0.05), r: 0.011, iris: 0xE04030, skin: skin, blink: a.blink, pupil: 0.4)
            if a.phase == .acting || a.phase == .noticing {
                ctx.setFillColor(ink.tone(0xF8F0E8))
                for x in [0.13, 0.155] {
                    ctx.move(to: pt(x - 0.006, 0.0)); ctx.addLine(to: pt(x + 0.006, 0.0)); ctx.addLine(to: pt(x, -0.022)); ctx.fillPath()
                }
            }
        }
    }

    private func wing(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk, lift: Double, far: Bool) {
        let length = kind == .bat ? 0.7 : 0.6
        ctx.saveGState()
        ctx.translateBy(x: far ? -0.03 : 0.02, y: far ? 0.04 : 0.02)
        ctx.rotate(by: CGFloat(0.25))
        ctx.scaleBy(x: 1, y: CGFloat(max(-0.85, min(1, lift))))
        let colour = far ? ink.dark(membrane, 0.3) : membrane
        // The arm and the finger bones, with skin stretched between them and scalloped at the trailing edge.
        let wrist = pt(0.05, length * 0.45)
        let tips = kind == .bat ? [pt(0.02, length), pt(-0.12, length * 0.9), pt(-0.2, length * 0.6), pt(-0.18, length * 0.25)]
                                : [pt(-0.02, length), pt(-0.16, length * 0.62), pt(-0.14, length * 0.25)]
        var edge: [CGPoint] = [pt(0.06, 0.0), wrist, tips[0]]
        for i in 1..<tips.count {
            let a0 = tips[i - 1], a1 = tips[i]
            edge.append(pt((Double(a0.x) + Double(a1.x)) / 2 + 0.03, (Double(a0.y) + Double(a1.y)) / 2 - 0.02))
            edge.append(a1)
        }
        edge.append(pt(-0.10, 0.0))
        let path = SceneShape.blob(edge, tension: 0.55)
        ink.volume(ctx, path, colour, rim: far ? 0 : 0.6, light: !far)
        if !ink.rough {
            let bone = far ? ink.dark(skin, 0.3) : skin
            ink.line(ctx, SceneShape.curve([pt(0.04, 0.0), wrist]), bone, width: 0.022)
            ink.lines(ctx, tips.map { [wrist, $0] }, bone, width: 0.01, alpha: 0.9)
        }
        ctx.restoreGState()
    }
}

/// A blue morpho butterfly: wings that clap open and shut, flashing blue, with a slow flutter when it rests.
final class SceneButterfly: ScenePuppet {
    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let resting = a.landed
        let rate = resting ? 1.2 : 5.5
        let beat = resting ? 0.75 + 0.25 * sin(a.time * rate + a.quirk * 7) : 0.5 + 0.5 * sin(a.stride * 1.6 + a.quirk * 7)
        // Seen a little from above: the near pair of wings opens toward us, the far pair away.
        for far in [true, false] {
            ctx.saveGState()
            ctx.translateBy(x: far ? -0.04 : 0.0, y: far ? 0.03 : 0)
            ctx.scaleBy(x: 1, y: CGFloat(far ? 0.35 + 0.65 * beat : -(0.15 + 0.85 * beat)))
            let shade: (UInt32) -> UInt32 = { far ? ink.dark($0, 0.25) : $0 }
            let fore = SceneShape.blob([pt(0.02, 0.0), pt(0.12, 0.30), pt(0.02, 0.48), pt(-0.18, 0.40), pt(-0.12, 0.05)], tension: 0.8)
            let hind = SceneShape.blob([pt(-0.02, 0.0), pt(-0.08, 0.26), pt(-0.26, 0.30), pt(-0.32, 0.12), pt(-0.2, -0.02)], tension: 0.8)
            for wing in [hind, fore] {
                ink.volume(ctx, wing, shade(0x14102A), rim: 0.4, light: false)
                ink.inside(ctx, wing) {
                    ink.flat(ctx, SceneShape.ellipse(pt(-0.06, 0.16), 0.17, 0.2), shade(0x1E62E8))
                    ink.flat(ctx, SceneShape.ellipse(pt(-0.03, 0.12), 0.1, 0.12), shade(0x3FA8FF), alpha: 0.9)
                    if !ink.rough { ink.flat(ctx, SceneShape.ellipse(pt(-0.07, 0.2), 0.05, 0.04), 0xB8F0FF, alpha: 0.5) }
                }
            }
            if !ink.rough {
                ctx.setFillColor(ink.tone(0xF4F0E8, 0.9))
                for (x, y) in [(0.0, 0.43), (-0.1, 0.40), (-0.27, 0.22)] { ctx.fillEllipse(in: CGRect(x: x - 0.012, y: y - 0.012, width: 0.024, height: 0.024)) }
            }
            ctx.restoreGState()
        }
        ink.volume(ctx, SceneShape.blob([pt(0.12, 0.02), pt(0.06, 0.03), pt(-0.16, 0.0), pt(0.06, -0.02)], tension: 0.6), 0x2A2420, rim: 0.4)
        ink.line(ctx, SceneShape.curve([pt(0.1, 0.03), pt(0.16, 0.12), pt(0.2, 0.15)]), 0x2A2420, width: 0.008)
        ink.line(ctx, SceneShape.curve([pt(0.1, 0.03), pt(0.18, 0.09), pt(0.23, 0.1)]), 0x2A2420, width: 0.008)
    }
}
