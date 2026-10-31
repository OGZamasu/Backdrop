import CoreGraphics
import Foundation

/// Moustaches and beards, shared by the wizard, Santa, the gentleman and the devil.
enum HeadwearFacialHair {
    // MARK: Moustache

    struct Moustache {
        var colors: [HeadwearColor]
        var ink: HeadwearColor?
        /// How far each side reaches from the middle, in eye-spacings.
        var reach = 0.9
        /// Half the thickness at the middle.
        var thickness = 0.11
        /// How steeply each side first heads downward, in radians.
        var drop = 0.2
        /// How far the end turns upward (negative: downward) over its last stretch, in radians. Over 4 or so it curls into a spiral.
        var curl = 0.0
        /// Where along it (0...1) the curl begins.
        var curlStart = 0.5
        /// How quickly it thins toward the end: small for a moustache that stays thick.
        var taper = 0.8
        var highlight = HeadwearColor(1, 1, 1, 0.25)
    }

    /// Draws the moustache centred on `center`. `flick` twitches the ends, `lift` raises them, both in radians.
    static func moustache(_ pen: HeadwearPen, at center: CGPoint, _ m: Moustache, flick: Double = 0, lift: Double = 0, scale: Double = 1) {
        pen.placed(at: center, stretch: CGSize(width: scale, height: scale)) {
            for side in [-1.0, 1.0] {
                // Built for the right-hand side and mirrored for the left.
                let spine = HeadwearShape.spine(from: hwp(0, 0), length: m.reach, steps: 28) { t in
                    -m.drop + lift * t + (m.curl + flick) * HeadwearEase.smoothstep((t - m.curlStart) / (1 - m.curlStart)) * 1.0
                }.map { hwp($0.x * side, $0.y) }
                let shape = HeadwearShape.ribbon(spine, tip: 0.5) { t in
                    m.thickness * pow(1 - t, m.taper) * (0.75 + 0.25 * sin(min(1, t * 4) * .pi / 2)) + 0.012
                }
                pen.paint(shape, m.colors, ink: m.ink, inkWidth: 0.03)
                pen.clipped(to: shape) {
                    let ridge = spine.prefix(20).enumerated().map { hwp($0.element.x, $0.element.y + m.thickness * 0.35 * (1 - Double($0.offset) / 24)) }
                    pen.stroke(HeadwearShape.smooth(ridge, closed: false), m.highlight, width: 0.022)
                }
            }
        }
    }

    // MARK: Cloud

    /// A white puffy shape: a body with a ring of round puffs, inked on the outside only. Filling slightly bigger circles in the
    /// ink colour is much cheaper than stroking every puff, and looks the same.
    static func cloud(_ pen: HeadwearPen, body: CGPath, puffs: [(centre: CGPoint, radius: Double)], colors: [HeadwearColor],
                      ink: HeadwearColor, outline: Double = 0.035, shade: (centre: CGPoint, radius: Double, color: HeadwearColor)? = nil) {
        let outer = CGMutablePath(), inner = CGMutablePath()
        for p in puffs {
            outer.addPath(HeadwearShape.ellipse(p.centre, rx: p.radius + outline, ry: p.radius + outline))
            inner.addPath(HeadwearShape.ellipse(p.centre, rx: p.radius, ry: p.radius))
        }
        if !body.isEmpty { pen.stroke(body, ink, width: outline * 2) }
        pen.fill(outer, ink)
        let all = CGMutablePath()
        all.addPath(body)
        all.addPath(inner)
        pen.paint(all, colors, ink: nil)
        if let shade { pen.clipped(to: all) { pen.glow(at: shade.centre, radius: shade.radius, shade.color) } }
    }

    // MARK: Beard

    struct Beard {
        /// How far below the chin it hangs.
        var length = 1.0
        /// How far it spreads past the cheeks, 0...1.
        var bulge = 0.3
        /// 1 comes to a point; 0 ends round.
        var taper = 0.5
        /// How far the tip is swung to the side, in eye-spacings.
        var sway = 0.0
        var colors: [HeadwearColor]
        var ink: HeadwearColor?
        var strands = HeadwearColor(0, 0, 0, 0.18)
    }

    /// The points round the edge of a beard: down the left side, round the tip and up the right (`outer`), then back across
    /// the upper lip (`top`).
    static func beardEdge(_ f: HeadwearFrame, _ b: Beard) -> (outer: [CGPoint], top: [CGPoint]) {
        let chin = f.chinY
        let width = 0.9 + 0.3 * b.bulge
        func hw(_ u: Double) -> Double { width * pow(max(0, 1 - u), 0.5 + 0.55 * b.taper) }
        func offset(_ u: Double) -> Double { b.sway * pow(u, 1.5) + 0.05 * b.taper * sin(u * 5) * b.length * 0.5 }
        var left: [CGPoint] = [hwp(-1.07, -0.04), hwp(-(1.15 + 0.5 * b.bulge), -0.62), hwp(-(1.05 + 0.6 * b.bulge), chin + 0.5)]
        for u in [0.0, 0.2, 0.42, 0.66, 0.86] { left.append(hwp(-hw(u) + offset(u), chin - b.length * u)) }
        let tip = hwp(b.sway, chin - b.length)
        var right: [CGPoint] = [hwp(1.07, -0.04), hwp(1.15 + 0.5 * b.bulge, -0.62), hwp(1.05 + 0.6 * b.bulge, chin + 0.5)]
        for u in [0.0, 0.2, 0.42, 0.66, 0.86] { right.append(hwp(hw(u) + offset(u), chin - b.length * u)) }
        let narrow = b.taper > 0.5 ? 0.04 : 0
        let outer = left + [hwp(b.sway - narrow, tip.y + 0.1 * b.taper), tip, hwp(b.sway + narrow, tip.y + 0.1 * b.taper)] + right.reversed()
        let lip = f.mouth.y + 0.2
        let top = [hwp(0.95, -0.34), hwp(0.62, lip - 0.02), hwp(f.mouth.x, lip + 0.04), hwp(-0.62, lip - 0.02), hwp(-0.95, -0.34)]
        return (outer, top)
    }

    /// Draws a beard that leaves the mouth clear.
    static func beard(_ pen: HeadwearPen, _ f: HeadwearFrame, _ b: Beard, fluffy: Bool = false, grow: Double = 1) {
        guard grow > 0.001 else { return }
        let edge = beardEdge(f, b)
        let hole = HeadwearShape.ellipse(hwp(f.mouth.x, f.mouth.y - 0.02),
                                         rx: f.mouthWidth / 2 + 0.08 + 0.04 * f.signals.grin,
                                         ry: 0.1 + 0.3 * f.face.mouthOpen)
        let body = CGMutablePath()
        body.addPath(HeadwearShape.smooth(edge.outer + edge.top, closed: true))
        body.addPath(hole)
        let chinPoint = hwp(0, f.chinY + 0.6)
        pen.placed(at: chinPoint, stretch: CGSize(width: 1, height: grow)) {
            pen.ctx.translateBy(x: -chinPoint.x, y: -chinPoint.y)
            if fluffy {
                // Cloud-white: a ring of puffs round the edge.
                var puffs: [(centre: CGPoint, radius: Double)] = []
                for (i, p) in HeadwearShape.along(edge.outer, spacing: 0.3).enumerated() where p.y < f.mouth.y - 0.5 {
                    puffs.append((p, 0.18 + 0.04 * HeadwearNoise.unit(i, 7)))
                }
                let shape = CGMutablePath()
                shape.addPath(HeadwearShape.smooth(edge.outer + edge.top, closed: true))
                shape.addPath(HeadwearShape.ellipse(hwp(f.mouth.x, f.mouth.y - 0.02), rx: f.mouthWidth / 2 + 0.08 + 0.04 * f.signals.grin,
                                                    ry: 0.1 + 0.3 * f.face.mouthOpen, hole: true))
                cloud(pen, body: shape, puffs: puffs, colors: b.colors, ink: b.ink ?? .black, outline: 0.037,
                      shade: (hwp(0, f.chinY - 0.5), 0.9, HeadwearColor(hex: 0x8C98C4, alpha: 0.22)))
            } else {
                pen.paint(body, b.colors, ink: b.ink, inkWidth: 0.04, evenOdd: true)
                pen.clipped(to: body, evenOdd: true) {
                    for k in -4...4 {
                        let x0 = Double(k) * 0.24
                        let u = 0.6 + 0.35 * HeadwearNoise.unit(k + 20, 3)
                        let from = hwp(x0 * 1.1, f.mouth.y - 0.35 - 0.1 * abs(Double(k)) * 0.3)
                        let to = hwp(x0 * (1 - u) * 0.9 + b.sway * pow(u, 1.5), f.chinY - b.length * u)
                        let path = CGMutablePath()
                        path.move(to: from)
                        path.addCurve(to: to, control1: hwp(from.x + 0.14 * sin(Double(k)), (from.y + to.y) / 2 + 0.2),
                                      control2: hwp(to.x - 0.18 * sin(Double(k) * 1.7), (from.y + to.y) / 2 - 0.1))
                        pen.stroke(path, b.strands, width: 0.026)
                    }
                }
            }
        }
    }
}
