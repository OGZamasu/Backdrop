import CoreGraphics
import Foundation

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// A ghost: a soft sheet with a rippling hem and little waving arms, see-through, with a face that stretches into a great BOO.
final class SceneGhost: ScenePuppet {
    var facesViewer: Bool { true }
    private let sheet: UInt32 = 0xEEF2FF
    private let shade: UInt32 = 0x9AA8E0

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let boo = a.phase == .acting ? a.acting(rise: 0.25, fall: 0.5) : 0
        let scared = a.isScared ? 1.0 : 0
        let lean = max(-0.25, min(0.25, -a.velocity.x * 0.25))
        ink.glass = 0.86
        ctx.saveGState()
        ctx.rotate(by: CGFloat(lean * 0.5))
        ctx.scaleBy(x: CGFloat(1 + 0.06 * boo), y: CGFloat(1 + 0.12 * boo))
        // The sheet: a dome that flows down to a hem of lobes that ripple as it drifts.
        var outline: [CGPoint] = [pt(-0.34, 0.06), pt(-0.32, 0.28), pt(-0.2, 0.44), pt(0.0, 0.5), pt(0.2, 0.44), pt(0.32, 0.28), pt(0.34, 0.06)]
        let lobes = 5
        for i in 0...lobes {
            let k = Double(i) / Double(lobes)
            let x = 0.36 - k * 0.74
            let ripple = sin(a.time * 4 + k * 7 + a.quirk * 5) * 0.04
            let trail = lean * k * 0.3
            outline.append(pt(x + trail, (i % 2 == 0 ? -0.46 : -0.36) + ripple))
        }
        let body = SceneShape.blob(outline, tension: 0.85)
        ink.volume(ctx, body, sheet, rim: 1.4)
        ink.inside(ctx, body) {
            ink.flat(ctx, SceneShape.ellipse(pt(0.08, -0.3), 0.36, 0.18), shade, alpha: 0.35)
        }
        // Arms flap.
        for side in [-1.0, 1.0] {
            let flap = sin(a.time * 5 + side + a.quirk * 3) * 0.25 + boo * 0.6 + scared * 0.8
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(side * 0.3), y: 0.05)
            ctx.rotate(by: CGFloat(side * (0.5 + flap)))
            ink.volume(ctx, SceneShape.blob([pt(0, 0.05), pt(side * 0.16, 0.03), pt(side * 0.2, -0.04), pt(side * 0.1, -0.05), pt(0, -0.05)]), sheet, rim: 0.8)
            ctx.restoreGState()
        }
        // The face: big dark eyes, a mouth that opens to a great O.
        let eyeH = 0.07 + 0.03 * boo - 0.05 * a.blink
        for x in [0.02, 0.17] {
            ink.flat(ctx, SceneShape.ellipse(pt(x, 0.22), 0.045 + 0.01 * scared, max(0.008, eyeH)), 0x1A1830)
            if eyeH > 0.03 { ink.flat(ctx, SceneShape.ellipse(pt(x - 0.012, 0.24), 0.014, 0.016), 0xFFFFFF, alpha: 0.9) }
        }
        let mouth = 0.03 + 0.11 * boo + 0.04 * scared
        ink.flat(ctx, SceneShape.ellipse(pt(0.1, 0.06 - mouth * 0.4), 0.04 + 0.05 * boo, mouth), 0x1A1830)
        if !ink.rough {
            ink.flat(ctx, SceneShape.ellipse(pt(-0.06, 0.13), 0.035, 0.018), 0xF4A0C0, alpha: 0.45)
            ink.flat(ctx, SceneShape.ellipse(pt(0.26, 0.13), 0.03, 0.016), 0xF4A0C0, alpha: 0.45)
        }
        ctx.restoreGState()
        ink.glass = 1
    }
}

/// A spider on a thread: a round abdomen, eight jointed legs that pedal in the air, and a cluster of glinting eyes.
final class SceneSpider: ScenePuppet {
    var facesViewer: Bool { true }

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let t = a.time
        let busy = a.phase == .acting ? 1.0 : 0.4
        // Legs: four a side, each with a knee that bends up and a foot that hangs.
        for side in [-1.0, 1.0] {
            for i in 0..<4 {
                let far = side < 0
                let root = pt(side * 0.05, 0.02 - Double(i) * 0.03)
                let spread = 0.5 + Double(i) * 0.32
                let pedal = sin(t * 7 * busy + Double(i) * 1.7 + (far ? 1 : 0)) * 0.12 * busy
                let knee = root.sceneMoved(side * cos(spread - 0.9) * 0.2, 0.12 + sin(spread) * 0.04 + pedal)
                let foot = knee.sceneMoved(side * 0.12, -0.26 + Double(i) * 0.04 - pedal)
                let colour: UInt32 = far ? 0x241A2E : 0x3A2A48
                ink.line(ctx, SceneShape.curve([root, knee]), colour, width: 0.04)
                ink.line(ctx, SceneShape.curve([knee, foot]), colour, width: 0.03)
            }
        }
        let abdomen = SceneShape.ellipse(pt(0, 0.12), 0.2, 0.22)
        ink.volume(ctx, abdomen, 0x3A2A48, rim: 1.2)
        ink.inside(ctx, abdomen) {
            ink.flat(ctx, SceneShape.blob([pt(0, 0.22), pt(0.05, 0.14), pt(0, 0.06), pt(-0.05, 0.14)]), 0xC8303A, alpha: 0.9)
        }
        let head = SceneShape.ellipse(pt(0, -0.12), 0.11, 0.1)
        ink.volume(ctx, head, 0x2E2238, rim: 1)
        for (x, y, r) in [(-0.04, -0.12, 0.03), (0.04, -0.12, 0.03), (-0.075, -0.09, 0.017), (0.075, -0.09, 0.017)] {
            ink.flat(ctx, SceneShape.ellipse(pt(x, y), r, r), 0xD02838)
            ink.glint(ctx, at: pt(x, y), r: r)
        }
        ink.flat(ctx, SceneShape.blob([pt(-0.03, -0.2), pt(-0.015, -0.25), pt(0.0, -0.21), pt(0.015, -0.25), pt(0.03, -0.2)]), 0x1A1420)
    }
}

/// A jack-o'-lantern that hops about, its carved face lit from inside, a flicker in the candle.
final class ScenePumpkin: ScenePuppet {
    var facesViewer: Bool { true }

    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk) {
        let grin = a.phase == .acting ? a.acting(rise: 0.2, fall: 0.4) : 0
        let flicker = 0.75 + 0.25 * sin(a.time * 13 + a.quirk * 7) * sin(a.time * 7.3 + a.quirk)
        // The stem and a curling leaf.
        ink.volume(ctx, SceneShape.limb(pt(0.0, 0.78), pt(0.05, 0.96), 0.045, 0.03), 0x5A6A2A, rim: 0.6)
        ink.line(ctx, SceneShape.curve([pt(0.03, 0.86), pt(0.14, 0.92), pt(0.18, 0.84), pt(0.12, 0.8)]), 0x4A7A2A, width: 0.02)
        // Ribs: overlapping lobes, the outer ones darker.
        let lobes: [(Double, Double, UInt32)] = [(-0.32, 0.22, 0xC8601C), (0.32, 0.22, 0xC8601C), (-0.17, 0.3, 0xE47A24), (0.17, 0.3, 0xE47A24), (0.0, 0.32, 0xF08A2A)]
        for (x, w, colour) in lobes {
            ink.volume(ctx, SceneShape.ellipse(pt(x, 0.42), w, 0.42), colour, rim: 0.9)
        }
        // The carved face, glowing.
        let light: UInt32 = ScenePaint.mixHex(0xFF9A20, 0xFFE070, flicker)
        let eyes = [[pt(-0.2, 0.52), pt(-0.06, 0.52), pt(-0.13, 0.66)], [pt(0.06, 0.52), pt(0.2, 0.52), pt(0.13, 0.66)]]
        for tri in eyes {
            let path = CGMutablePath()
            path.addLines(between: tri)
            path.closeSubpath()
            ink.flat(ctx, path, 0x3A1404)
            ink.flat(ctx, SceneShape.ellipse(pt(Double(tri[2].x), 0.56), 0.04, 0.035), light, alpha: 0.95)
        }
        let open = 0.06 + 0.08 * grin
        let mouth = CGMutablePath()
        mouth.move(to: pt(-0.26, 0.34))
        for i in 0...6 {
            let x = -0.26 + Double(i) * 0.52 / 6
            mouth.addLine(to: pt(x, 0.34 - (i % 2 == 0 ? 0 : 0.04) + 0.02 * sin(Double(i))))
        }
        mouth.addQuadCurve(to: pt(-0.26, 0.34), control: pt(0, 0.34 - open * 3.2))
        mouth.closeSubpath()
        ink.flat(ctx, mouth, 0x3A1404)
        ink.inside(ctx, mouth) { ink.flat(ctx, SceneShape.ellipse(pt(0, 0.26), 0.2, 0.1), light, alpha: 0.95) }
    }
}
