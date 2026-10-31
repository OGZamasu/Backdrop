import CoreGraphics
import Foundation

// MARK: - Dog

/// A dog: floppy ears that flap with your head, a glossy black nose, and a tongue that rolls out when you open wide.
/// Raise your eyebrows and the ears prick up.
final class HeadwearDog: HeadwearCostume {
    let hint = "Open wide for a tongue, raise your brows to perk your ears"

    private var ears = [HeadwearSwing(omega: 8.5, damping: 0.2, gain: 0.05, limit: 1.1), HeadwearSwing(omega: 8, damping: 0.22, gain: 0.05, limit: 1.1)]
    /// How far the tongue is out: 0 in, 1 hanging, a little more as it rolls out.
    private var tongue = HeadwearSwing(omega: 19, damping: 0.32, gain: 0, limit: 1.8)

    /// How far out the tongue is right now.
    var tongueOut: Double { tongue.x }
    /// How far the ears have lifted, 0 hanging to 1 pricked up.
    private(set) var perk = 0.0

    private static let fur = [HeadwearColor(hex: 0xA8683B), HeadwearColor(hex: 0x74401F)]
    private static let ink = HeadwearColor(hex: 0x35190A)

    func reset() { ears[0].reset(); ears[1].reset(); tongue.reset(); perk = 0 }

    func advance(_ f: HeadwearFrame) {
        perk = f.signals.raised
        let rest = f.hang * 0.5 * (1 - perk)
        for i in ears.indices {
            ears[i].step(dt: f.dt, accel: f.accel.x, rest: rest)
        }
        tongue.step(dt: f.dt, accel: 0, rest: f.signals.mouthIsOpen ? 1 : 0)
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            for (i, side) in [-1.0, 1.0].enumerated() { drawEar(pen, f, side: side, swing: ears[i].x) }
            drawMarkings(pen, f)
            drawNose(pen, f)
            drawTongue(pen, f)
        }
    }

    private func drawEar(_ pen: HeadwearPen, _ f: HeadwearFrame, side: Double, swing: Double) {
        let grow = HeadwearEase.pop(f.seen, delay: side < 0 ? 0.05 : 0.14, duration: 0.5)
        guard grow > 0.001 else { return }
        // A floppy ear never swings across the face, only away from it.
        let loose = side > 0 ? max(swing, -0.12) : min(swing, 0.12)
        let turn = side * perk * 2.1 + loose + 0.06 * sin(f.clock * 1.7 + side) * (1 - perk)
        let outline: [CGPoint] = [hwp(-0.13, 0.03), hwp(0.12, 0.10), hwp(0.34, 0.04), hwp(0.52, -0.30), hwp(0.55, -0.72), hwp(0.45, -1.12),
                                  hwp(0.20, -1.40), hwp(-0.02, -1.32), hwp(-0.12, -0.96), hwp(-0.14, -0.50), hwp(-0.13, -0.2)]
        let shape = HeadwearShape.smooth(outline)
        pen.placed(at: f.head.at(side * 1.02, 0.95), turn: turn, stretch: CGSize(width: side * grow, height: grow * (1 - 0.18 * perk))) {
            pen.paint(shape, Self.fur, ink: Self.ink, inkWidth: 0.05)
            pen.clipped(to: shape) {
                // A darker patch toward the tip, the inside of the ear showing as it lifts, and the crease where it folds.
                pen.fill(HeadwearShape.ellipse(hwp(0.26, -1.05), rx: 0.26, ry: 0.36, turn: 0.2), HeadwearColor(hex: 0x4A2610, alpha: 0.55))
                pen.fill(HeadwearShape.ellipse(hwp(0.2, -0.55), rx: 0.2, ry: 0.5, turn: 0.1), HeadwearColor(hex: 0xF2A9A0, alpha: 0.9 * min(1, perk * 1.4)))
                pen.stroke(HeadwearShape.smooth([hwp(-0.05, 0.1), hwp(0.2, -0.15), hwp(0.44, -0.5)], closed: false),
                           HeadwearColor(hex: 0x4A2610, alpha: 0.5), width: 0.035)
                pen.stroke(HeadwearShape.smooth([hwp(-0.1, -0.2), hwp(-0.1, -0.55), hwp(-0.03, -0.95)], closed: false),
                           HeadwearColor(hex: 0xE0A670, alpha: 0.55), width: 0.03)
                // Fur: soft strands running down the ear, and a light edge on the side toward the light.
                for k in 0..<5 {
                    let x = 0.0 + Double(k) * 0.1
                    pen.stroke(HeadwearShape.smooth([hwp(x, -0.05), hwp(x + 0.04, -0.5), hwp(x * 0.8 + 0.05, -1.0 - 0.05 * Double(k % 2))], closed: false),
                               HeadwearColor(hex: 0x4A2610, alpha: 0.28), width: 0.02)
                }
                pen.stroke(shape, HeadwearColor(1, 0.9, 0.75, 0.22), width: 0.06)
            }
        }
    }

    private func drawMarkings(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let appear = HeadwearEase.smoothstep((f.seen - 0.3) / 0.25)
        guard appear > 0.01 else { return }
        // Tan eyebrow dots and freckles on the muzzle.
        for side in [-1.0, 1.0] {
            pen.fill(HeadwearShape.ellipse(hwp(side * 0.5, f.head.brow + 0.42), rx: 0.09, ry: 0.055, turn: side * 0.12), HeadwearColor(hex: 0xE2B07A, alpha: 0.75 * appear))
            let n = f.nose
            for (dx, dy) in [(0.30, 0.0), (0.42, -0.1), (0.27, -0.13)] {
                pen.dot(at: hwp(n.x + side * dx, n.y + dy), radius: 0.024, HeadwearColor(hex: 0x3B2112, alpha: 0.7 * appear))
            }
        }
    }

    private func drawNose(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let boop = HeadwearEase.pop(f.seen, delay: 0.25, duration: 0.4)
        guard boop > 0.001 else { return }
        let c = f.nose
        let outline: [CGPoint] = [hwp(-0.19, 0.09), hwp(0, 0.14), hwp(0.19, 0.09), hwp(0.15, -0.03), hwp(0.07, -0.12), hwp(0, -0.14),
                                  hwp(-0.07, -0.12), hwp(-0.15, -0.03)]
        pen.placed(at: hwp(c.x, c.y + 0.02), scale: boop) {
            let shape = HeadwearShape.smooth(outline)
            pen.paintRound(shape, center: hwp(-0.05, 0.07), radius: 0.28, [HeadwearColor(hex: 0x5C5C6A), HeadwearColor(hex: 0x1A1A20), HeadwearColor(hex: 0x0A0A0D)],
                           ink: HeadwearColor(hex: 0x050507), inkWidth: 0.03)
            pen.fill(HeadwearShape.ellipse(hwp(-0.06, 0.085), rx: 0.075, ry: 0.032, turn: 0.25), HeadwearColor(1, 1, 1, 0.8))
            for side in [-1.0, 1.0] {
                pen.fill(HeadwearShape.ellipse(hwp(side * 0.07, -0.035), rx: 0.03, ry: 0.016, turn: side * 0.6), HeadwearColor(hex: 0x3A3A44, alpha: 0.9))
            }
        }
    }

    private func drawTongue(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let out = tongue.x
        guard out > 0.03 else { return }
        let panting = f.signals.mouthIsOpen ? 1 + 0.05 * sin(f.clock * 11) : 1
        let length = (0.14 + 0.62 * out) * panting
        let lateral = 0.06 * sin(f.clock * 5.5) * min(1, out) + f.accel.x * -0.004
        let top = hwp(f.mouth.x, f.mouth.y - 0.02)
        let w = 0.2 + 0.03 * min(1, out)
        var pts: [CGPoint] = []
        let profile: [(Double, Double)] = [(0, 1), (0.3, 1.05), (0.7, 0.96), (0.92, 0.6), (1, 0)]
        for (t, k) in profile { pts.append(hwp(-w * k + lateral * t * t, -length * t)) }
        for (t, k) in profile.dropLast().reversed() { pts.append(hwp(w * k + lateral * t * t, -length * t)) }
        let shape = HeadwearShape.smooth(pts)
        pen.placed(at: top) {
            pen.paint(shape, [HeadwearColor(hex: 0xFF8FA6), HeadwearColor(hex: 0xEF5278)], ink: HeadwearColor(hex: 0xA52B4B), inkWidth: 0.035)
            pen.stroke(HeadwearShape.smooth([hwp(lateral * 0.1, -0.02), hwp(lateral * 0.4, -length * 0.45), hwp(lateral * 0.8, -length * 0.8)], closed: false),
                       HeadwearColor(hex: 0xC23A5E, alpha: 0.75), width: 0.03)
            pen.clipped(to: shape) {
                pen.fill(HeadwearShape.ellipse(hwp(-w * 0.45, -length * 0.3), rx: 0.04, ry: length * 0.18, turn: 0.05), HeadwearColor(1, 1, 1, 0.3))
            }
        }
    }
}

// MARK: - Bunny

/// A bunny: tall ears that wobble, flop and fall about with your head, a pink nose, buck teeth and whiskers.
/// Raise your eyebrows and the ears stand to attention.
final class HeadwearBunny: HeadwearCostume {
    let hint = "Raise your brows to make your ears stand tall"

    private var sway = [HeadwearSwing(omega: 7.5, damping: 0.16, gain: 0.035, limit: 0.9), HeadwearSwing(omega: 6.8, damping: 0.15, gain: 0.035, limit: 0.9)]
    private var fold = [HeadwearSwing(omega: 6, damping: 0.3, gain: 0, limit: 1.4), HeadwearSwing(omega: 5.4, damping: 0.3, gain: 0, limit: 1.4)]

    /// How flopped over each ear is, 0 upright to 1 hanging.
    var floppiness: [Double] { fold.map(\.x) }

    func reset() { for i in 0..<2 { sway[i].reset(); fold[i].reset() } }

    /// How far an ear is slumped when left alone: a lazy droop that comes and goes, with a proper flop now and then.
    static func restingFold(ear: Int, clock: Double) -> Double {
        let lazy = 0.2 + 0.14 * sin(clock * (0.8 + 0.15 * Double(ear)) + Double(ear) * 2)
        let period = ear == 0 ? 6.3 : 7.9
        let phase = (clock + Double(ear) * 2.4).truncatingRemainder(dividingBy: period) / period
        let flop = HeadwearEase.smoothstep((phase - 0.55) / 0.08) * (1 - HeadwearEase.smoothstep((phase - 0.7) / 0.1))
        return lazy + 0.7 * flop
    }

    func advance(_ f: HeadwearFrame) {
        for i in 0..<2 {
            sway[i].step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.25)
            fold[i].step(dt: f.dt, accel: 0, rest: f.signals.browsAreUp ? -0.04 : Self.restingFold(ear: i, clock: f.clock))
        }
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            for (i, side) in [-1.0, 1.0].enumerated() { drawEar(pen, f, side: side, index: i) }
            drawCheeks(pen, f)
            drawWhiskers(pen, f)
            drawTeeth(pen, f)
            drawNose(pen, f)
        }
    }

    private func drawEar(_ pen: HeadwearPen, _ f: HeadwearFrame, side: Double, index: Int) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.06 + 0.1 * Double(index), duration: 0.55)
        guard grow > 0.001 else { return }
        let stand = f.signals.raised
        let length = 2.05 * (1 + 0.08 * stand) * grow
        let swing = sway[index].x, folded = fold[index].x
        let splay = 0.16 * (1 - stand * 0.7)
        let base = f.head.at(side * 0.42, 1.02)
        func heading(_ t: Double) -> Double {
            let flop = folded * 2.4 * HeadwearEase.smoothstep((t - 0.3) / 0.65)
            let bend = swing * (0.35 + 0.9 * t)
            // Positive angles lean toward +x.
            return .pi / 2 - (side * (splay + flop) + bend)
        }
        func width(_ t: Double) -> Double {
            t < 0.4 ? 0.23 + 0.1 * sin(t / 0.4 * .pi / 2) : 0.33 * sqrt(max(0, 1 - pow((t - 0.4) / 0.6, 2)))
        }
        let spine = HeadwearShape.spine(from: base, length: length, steps: 16, heading: heading)
        let outer = HeadwearShape.ribbon(spine, tip: 0, base: 0.3, width: width)
        pen.paint(outer, [HeadwearColor.white, HeadwearColor(hex: 0xE9E3F1)], ink: HeadwearColor(hex: 0x7D6C8E), inkWidth: 0.045, direction: CGVector(dx: side * 0.3, dy: -1))
        let inner = Array(spine[1..<(spine.count - 2)])
        let pink = HeadwearShape.ribbon(inner, tip: 0, base: 0.2) { t in width(0.1 + t * 0.78) * 0.62 }
        pen.paint(pink, [HeadwearColor(hex: 0xFFC7D8), HeadwearColor(hex: 0xF68FB1)], ink: HeadwearColor(hex: 0xD86A92, alpha: 0.7), inkWidth: 0.025)
        pen.clipped(to: outer) {
            pen.stroke(HeadwearShape.smooth(inner.map { hwp($0.x - side * 0.22, $0.y) }, closed: false), HeadwearColor(1, 1, 1, 0.55), width: 0.03)
        }
    }

    private func drawCheeks(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let a = HeadwearEase.smoothstep((f.seen - 0.3) / 0.3)
        for side in [-1.0, 1.0] {
            pen.glow(at: hwp(f.mouth.x * 0.5 + side * 0.68, f.nose.y - 0.08), radius: 0.32, HeadwearColor(hex: 0xFF5C8C, alpha: 0.5 * a))
        }
    }

    private func drawWhiskers(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let reveal = HeadwearEase.smoothstep((f.seen - 0.35) / 0.3)
        guard reveal > 0.01 else { return }
        let n = f.nose
        for side in [-1.0, 1.0] {
            for i in 0..<3 {
                let tilt = Double(i - 1) * 0.16
                let wag = 0.03 * sin(f.clock * 2.3 + Double(i) + side)
                let from = hwp(n.x + side * 0.34, n.y - 0.03 - Double(i) * 0.06)
                let to = hwp(n.x + side * (1.05 + 0.05 * reveal), n.y - 0.03 - Double(i) * 0.1 - tilt * 0.8 + wag)
                let path = CGMutablePath()
                path.move(to: from)
                path.addQuadCurve(to: to, control: hwp((from.x + to.x) / 2, (from.y + to.y) / 2 + 0.1))
                pen.stroke(path, HeadwearColor(hex: 0x4A3F5C, alpha: 0.95 * reveal), width: 0.05)
                pen.stroke(path, HeadwearColor(1, 1, 1, 0.95 * reveal), width: 0.026)
            }
        }
    }

    private func drawTeeth(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let appear = HeadwearEase.pop(f.seen, delay: 0.5, duration: 0.3)
        guard appear > 0.01 else { return }
        let top = min(f.upperLipY + 0.03, f.nose.y - 0.14)
        for side in [-1.0, 1.0] {
            let rect = CGRect(x: f.mouth.x + (side < 0 ? -0.115 : 0.005), y: top - 0.2 * appear, width: 0.11, height: 0.2 * appear)
            let tooth = HeadwearShape.rounded(rect, radius: 0.035)
            pen.paint(tooth, [HeadwearColor.white, HeadwearColor(hex: 0xEDE8F4)], ink: HeadwearColor(hex: 0x8C7C9C), inkWidth: 0.025)
        }
    }

    private func drawNose(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let boop = HeadwearEase.pop(f.seen, delay: 0.3, duration: 0.4)
        guard boop > 0.001 else { return }
        let c = f.nose
        let twitch = 1 + 0.04 * sin(f.clock * 7) * (sin(f.clock * 0.9) > 0.6 ? 1 : 0)
        pen.placed(at: hwp(c.x, c.y + 0.03), scale: boop * twitch) {
            let shape = HeadwearShape.smooth([hwp(-0.12, 0.07), hwp(0, 0.1), hwp(0.12, 0.07), hwp(0.07, -0.02), hwp(0, -0.09), hwp(-0.07, -0.02)])
            pen.paintRound(shape, center: hwp(-0.03, 0.05), radius: 0.2, [HeadwearColor(hex: 0xFFB9CE), HeadwearColor(hex: 0xF06C94)],
                           ink: HeadwearColor(hex: 0xA83F66), inkWidth: 0.03)
            pen.fill(HeadwearShape.ellipse(hwp(-0.04, 0.06), rx: 0.04, ry: 0.016, turn: 0.2), HeadwearColor(1, 1, 1, 0.75))
            let mouth = CGMutablePath()
            mouth.move(to: hwp(0, -0.09)); mouth.addLine(to: hwp(0, -0.17))
            mouth.move(to: hwp(-0.09, -0.2)); mouth.addQuadCurve(to: hwp(0, -0.17), control: hwp(-0.05, -0.24))
            mouth.addQuadCurve(to: hwp(0.09, -0.2), control: hwp(0.05, -0.24))
            pen.stroke(mouth, HeadwearColor(hex: 0x7D3A55, alpha: 0.85), width: 0.025)
        }
    }
}
