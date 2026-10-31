import CoreGraphics
import Foundation

// Animal faces: fox, panda, tabby cat, reindeer and unicorn.

/// Where an animal's ears sit on the test face, and the springs that make them flick.
private struct HeadwearEarPair {
    var flick = [HeadwearSwing(omega: 22, damping: 0.17, gain: 0.015, limit: 0.7), HeadwearSwing(omega: 20, damping: 0.19, gain: 0.015, limit: 0.7)]

    mutating func reset() { flick[0].reset(); flick[1].reset() }

    mutating func step(_ f: HeadwearFrame) {
        for i in 0..<2 { flick[i].step(dt: f.dt, accel: f.accel.x, rest: 0) }
    }

    mutating func twitch(_ strength: Double) { flick[0].shove(-strength); flick[1].shove(strength * 0.85) }
}

// MARK: - Fox

/// A fox: tall pointed ears with dark tips, a glossy black nose, cream cheek fluff and whiskers. Blink and the ears flick.
final class HeadwearFox: HeadwearCostume {
    let hint = "Blink and your ears flick"

    private var ears = HeadwearEarPair()
    private var untilTwitch = 2.5, twitches = 0

    /// How far each ear is turned off its rest, in radians.
    var earTurn: [Double] { ears.flick.map(\.x) }

    func reset() { ears.reset(); untilTwitch = 2.5; twitches = 0 }

    func advance(_ f: HeadwearFrame) {
        if f.signals.blinkGate.rose { ears.twitch(10) }
        untilTwitch -= f.dt
        if untilTwitch <= 0 {
            twitches += 1
            ears.flick[twitches % 2].shove(twitches % 2 == 0 ? -6 : 6)
            untilTwitch = 3 + 3 * HeadwearNoise.unit(twitches, 4)
        }
        ears.step(f)
    }

    static let fur = [HeadwearColor(hex: 0xFFB06A), HeadwearColor(hex: 0xF07A2A), HeadwearColor(hex: 0xBD4E16)]
    static let ink = HeadwearColor(hex: 0x5A2208)

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            for (i, side) in [-1.0, 1.0].enumerated() {
                let pop = HeadwearEase.pop(f.seen, delay: 0.05 + 0.1 * Double(i), duration: 0.5)
                guard pop > 0.001 else { continue }
                pen.placed(at: f.head.at(side * 0.66, 1.12), turn: -side * 0.36 + ears.flick[i].x, scale: pop) {
                    HeadwearEars.paint(pen, width: 0.78, height: 0.98, style: .pointed, side: side, fur: Self.fur, ink: Self.ink,
                                       inner: [HeadwearColor(hex: 0xFFF5E8), HeadwearColor(hex: 0xF2D2B4)], tip: HeadwearColor(hex: 0x3A2218, alpha: 0.92),
                                       tuft: HeadwearPalette.cream.faded(0.9), lean: side * 0.06, bake: "fox-ear", pixelsPerUnit: f.io)
                }
            }
            drawCheeks(pen, f)
            let reveal = HeadwearEase.smoothstep((f.seen - 0.35) / 0.35)
            HeadwearWhiskers.draw(pen, nose: hwp(f.nose.x, f.nose.y + 0.02), length: 0.55, color: HeadwearColor(hex: 0x2A1810, alpha: 0.85),
                                  edge: HeadwearPalette.cream.faded(0.45), lift: 0.3 * f.signals.grin, clock: f.clock, reveal: reveal)
            HeadwearAnimalNose.dark(pen, f, at: hwp(f.nose.x, f.nose.y + 0.02), size: 0.85)
        }
    }

    /// Ruffs of cream fur sticking out from the cheeks, orange at the roots.
    private func drawCheeks(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.3, duration: 0.5)
        let y = (f.nose.y + f.mouth.y) / 2 - 0.08
        for side in [-1.0, 1.0] {
            HeadwearFur.ruff(pen, at: hwp(f.head.side(side * 0.98), y), side: side, scale: grow * 1.05,
                             colors: [Self.fur[1], HeadwearPalette.cream, HeadwearColor.white], ink: HeadwearColor(hex: 0x9A6A48), sway: 0.08 * sin(f.clock * 1.5 + side),
                             bake: "fox-ruff", pixelsPerUnit: f.io * 1.05)
        }
    }
}

/// Animal noses shared by the fox, panda and reindeer.
enum HeadwearAnimalNose {
    /// A glossy dark nose, pushed in with a pop.
    static func dark(_ pen: HeadwearPen, _ f: HeadwearFrame, at c: CGPoint, size s: Double) {
        let boop = HeadwearEase.pop(f.seen, delay: 0.25, duration: 0.4)
        guard boop > 0.001 else { return }
        pen.placed(at: c, scale: boop * s) {
            let shape = HeadwearShape.smooth([hwp(-0.19, 0.08), hwp(0, 0.13), hwp(0.19, 0.08), hwp(0.14, -0.03), hwp(0.06, -0.11), hwp(0, -0.13),
                                              hwp(-0.06, -0.11), hwp(-0.14, -0.03)])
            pen.paintRound(shape, center: hwp(-0.05, 0.06), radius: 0.28, [HeadwearColor(hex: 0x5E5868), HeadwearColor(hex: 0x1E1A24), HeadwearColor(hex: 0x0C0A10)],
                           ink: HeadwearColor(hex: 0x050407), inkWidth: 0.028)
            pen.fill(HeadwearShape.ellipse(hwp(-0.06, 0.075), rx: 0.07, ry: 0.03, turn: 0.25), HeadwearColor(1, 1, 1, 0.75))
            for side in [-1.0, 1.0] {
                pen.fill(HeadwearShape.ellipse(hwp(side * 0.07, -0.035), rx: 0.03, ry: 0.016, turn: side * 0.6), HeadwearColor(hex: 0x3A3644, alpha: 0.9))
            }
        }
    }
}

// MARK: - Panda

/// A panda: round fuzzy ears, black patches round the eyes and a button nose. Smile and you blush and your ears wiggle.
final class HeadwearPanda: HeadwearCostume {
    let hint = "Smile and you blush"

    private var ears = HeadwearEarPair()
    private var blushing = HeadwearFollower()

    /// How pink the cheeks are, 0...1.
    var blush: Double { blushing.value }

    func reset() { ears.reset(); blushing = HeadwearFollower() }

    func advance(_ f: HeadwearFrame) {
        if f.signals.smileGate.rose { ears.twitch(7) }
        blushing.follow(f.signals.isSmiling ? 1 : 0, dt: f.dt, rise: 4, fall: 1.5)
        ears.step(f)
    }

    private static let black = [HeadwearColor(hex: 0x4A4552), HeadwearColor(hex: 0x24202A), HeadwearColor(hex: 0x141118)]

    private static func paintEar(_ pen: HeadwearPen) {
        var puffs: [(centre: CGPoint, radius: Double)] = [(hwp(0, 0.3), 0.3)]
        for k in 0..<14 {
            let a = Double(k) / 14 * 2 * .pi
            puffs.append((hwp(cos(a) * 0.3, 0.3 + sin(a) * 0.28), 0.06 + 0.015 * HeadwearNoise.unit(k, 5)))
        }
        // A soft grey rim round the fur, so a black ear still reads against a dark backdrop.
        HeadwearFacialHair.cloud(pen, body: CGMutablePath(), puffs: puffs, colors: black, ink: HeadwearColor(hex: 0x7A7286), outline: 0.03,
                                 shade: (hwp(-0.1, 0.42), 0.35, HeadwearColor(hex: 0x8A8496, alpha: 0.4)))
        pen.fill(HeadwearShape.ellipse(hwp(0.02, 0.26), rx: 0.15, ry: 0.13), HeadwearColor(hex: 0x3C3644, alpha: 0.9))
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            for (i, side) in [-1.0, 1.0].enumerated() {
                let pop = HeadwearEase.pop(f.seen, delay: 0.05 + 0.1 * Double(i), duration: 0.5)
                guard pop > 0.001 else { continue }
                pen.placed(at: f.head.at(side * 0.84, 0.9), turn: -side * 0.5 + ears.flick[i].x, scale: pop * 1.25) {
                    pen.sprite("panda-ear", window: CGRect(x: -0.45, y: -0.12, width: 0.9, height: 0.86), pixelsPerUnit: f.io * 1.25) { Self.paintEar($0) }
                }
            }
            drawPatches(pen, f)
            let b = blushing.value * HeadwearEase.smoothstep((f.seen - 0.3) / 0.3)
            for side in [-1.0, 1.0] {
                pen.glow(at: hwp(side * 0.72, f.nose.y - 0.1), radius: 0.36, HeadwearColor(hex: 0xFF6F91, alpha: 0.12 + 0.45 * b))
            }
            HeadwearAnimalNose.dark(pen, f, at: hwp(f.nose.x, f.nose.y + 0.02), size: 0.9)
        }
    }

    /// The black patches: drooping ovals round each eye, with the eye itself left clear.
    private func drawPatches(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.25, duration: 0.45)
        guard grow > 0.01 else { return }
        for side in [-1.0, 1.0] {
            let eye = hwp(side * 0.5, 0)
            pen.placed(at: eye, stretch: CGSize(width: side * grow, height: grow)) {
                // Drawn for the right eye; the left one is the mirror image. The outer, lower corner droops.
                let patch = HeadwearShape.smooth([hwp(-0.3, 0.12), hwp(-0.05, 0.25), hwp(0.24, 0.2), hwp(0.38, 0.0), hwp(0.36, -0.26), hwp(0.18, -0.42),
                                                  hwp(-0.06, -0.36), hwp(-0.28, -0.16)])
                let body = CGMutablePath()
                body.addPath(patch)
                body.addPath(HeadwearShape.ellipse(hwp(0, 0), rx: 0.235, ry: 0.13, hole: true))
                pen.stroke(patch, HeadwearColor(hex: 0x1C1820, alpha: 0.25), width: 0.07)
                pen.placed(at: .zero, scale: 0.95) { pen.paint(body, Self.black, ink: nil, evenOdd: true) }
                pen.clipped(to: body, evenOdd: true) {
                    pen.glow(at: hwp(-0.1, 0.14), radius: 0.3, HeadwearColor(hex: 0x8A8496, alpha: 0.3))
                }
            }
        }
    }
}

// MARK: - Tabby

/// A ginger tabby: striped ears, tabby marks on the forehead, white whisker pads, a pink nose, long whiskers and cheek fur.
/// Smile and the whiskers lift and spread.
final class HeadwearTabby: HeadwearCostume {
    let hint = "Smile and your whiskers lift"

    private var ears = HeadwearEarPair()
    private var grinning = HeadwearFollower()

    /// How far the whiskers are lifted, 0...1.
    var whiskerLift: Double { grinning.value }

    func reset() { ears.reset(); grinning = HeadwearFollower() }

    func advance(_ f: HeadwearFrame) {
        grinning.follow(f.signals.grin, dt: f.dt, rise: 8, fall: 4)
        if f.signals.blinkGate.rose { ears.twitch(6) }
        ears.step(f)
    }

    private static let fur = [HeadwearColor(hex: 0xFFBE7A), HeadwearColor(hex: 0xF0913E), HeadwearColor(hex: 0xC2641E)]
    private static let ink = HeadwearColor(hex: 0x5E2A0A)
    private static let stripe = HeadwearColor(hex: 0xA44E14)

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            for (i, side) in [-1.0, 1.0].enumerated() {
                let pop = HeadwearEase.pop(f.seen, delay: 0.05 + 0.1 * Double(i), duration: 0.5)
                guard pop > 0.001 else { continue }
                pen.placed(at: f.head.at(side * 0.7, 1.1), turn: -side * 0.32 + ears.flick[i].x, scale: pop) {
                    HeadwearEars.paint(pen, width: 0.72, height: 0.82, style: .pointed, side: side, fur: Self.fur, ink: Self.ink,
                                       inner: [HeadwearPalette.pinkLight, HeadwearPalette.pink], tuft: HeadwearPalette.cream.faded(0.9),
                                       stripes: Self.stripe.faded(0.7), lean: side * 0.04, bake: "tabby-ear", pixelsPerUnit: f.io)
                }
            }
            drawMarks(pen, f)
            drawCheekFur(pen, f)
            drawMuzzle(pen, f)
        }
    }

    /// The tabby "M" on the forehead and a pair of stripes at each temple.
    private func drawMarks(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let a = HeadwearEase.smoothstep((f.seen - 0.3) / 0.4)
        guard a > 0.01 else { return }
        let b = f.head.brow + 0.16
        let marks: [[CGPoint]] = [
            [hwp(0, b), hwp(0.01, b + 0.2), hwp(0, b + 0.38)],
            [hwp(-0.15, b + 0.03), hwp(-0.2, b + 0.18), hwp(-0.27, b + 0.32)],
            [hwp(0.15, b + 0.03), hwp(0.2, b + 0.18), hwp(0.27, b + 0.32)],
        ]
        for m in marks {
            let shape = HeadwearShape.ribbon(m.reversed(), tip: 0.6, base: 0.5) { t in 0.012 + 0.024 * sin(t * .pi) }
            pen.fill(shape, Self.stripe.faded(0.55 * a))
        }
        for side in [-1.0, 1.0] {
            for k in 0..<2 {
                let y = 0.22 - Double(k) * 0.16
                let from = hwp(f.head.side(side * 1.1), y), to = hwp(side * 0.84, y - 0.03)
                let shape = HeadwearShape.ribbon([from, hwp((from.x + to.x) / 2, y + 0.02), to], tip: 0.6) { t in 0.04 * (1 - t) + 0.006 }
                pen.fill(shape, Self.stripe.faded(0.6 * a))
            }
        }
    }

    private func drawCheekFur(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.3, duration: 0.5)
        let y = f.nose.y - 0.12
        for side in [-1.0, 1.0] {
            HeadwearFur.ruff(pen, at: hwp(f.head.side(side * 1.0), y), side: side, scale: grow * 0.95, colors: [Self.fur[2], Self.fur[1], Self.fur[0]],
                             ink: Self.ink, sway: 0.08 * sin(f.clock * 1.5 + side), stripes: Self.stripe.faded(0.55),
                             bake: "tabby-ruff", pixelsPerUnit: f.io)
        }
    }

    private func drawMuzzle(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let pop = HeadwearEase.pop(f.seen, delay: 0.35, duration: 0.45)
        guard pop > 0.01 else { return }
        let lift = grinning.value
        let n = hwp(f.nose.x, f.nose.y + 0.02)
        // The pads sit under the nose but never over the lip.
        let padY = max(n.y - 0.13, f.upperLipY + 0.17)
        HeadwearWhiskers.draw(pen, nose: hwp(n.x, padY + 0.08), length: 0.8, color: HeadwearPalette.cream.faded(0.95), edge: HeadwearColor(hex: 0x5E3A20, alpha: 0.7),
                              lift: 0.5 * lift, spread: lift, clock: f.clock, reveal: pop)
        pen.placed(at: hwp(n.x, padY), scale: pop * (1 + 0.06 * lift)) {
            for side in [-1.0, 1.0] {
                let pad = HeadwearShape.ellipse(hwp(side * 0.15, 0), rx: 0.19, ry: 0.13, turn: -side * 0.15)
                pen.paintRound(pad, center: hwp(side * 0.1 - 0.05, 0.06), radius: 0.28, [HeadwearColor.white, HeadwearPalette.cream, HeadwearPalette.creamShade],
                               ink: HeadwearColor(hex: 0xB89C80, alpha: 0.8), inkWidth: 0.022)
                for k in 0..<4 {
                    pen.dot(at: hwp(side * (0.09 + 0.065 * Double(k % 2) + 0.03 * Double(k / 2)), -0.01 - 0.045 * Double(k / 2) + 0.03 * Double(k % 2)),
                            radius: 0.014, HeadwearColor(hex: 0x6E4A30, alpha: 0.8))
                }
            }
        }
        pen.placed(at: hwp(n.x, padY + 0.12), scale: pop) {
            let nose = HeadwearShape.smooth([hwp(-0.1, 0.04), hwp(-0.05, 0.065), hwp(0, 0.05), hwp(0.05, 0.065), hwp(0.1, 0.04), hwp(0.04, -0.05), hwp(0, -0.065),
                                             hwp(-0.04, -0.05)])
            pen.paintRound(nose, center: hwp(-0.03, 0.03), radius: 0.14, [HeadwearPalette.pinkLight, HeadwearPalette.pink], ink: HeadwearPalette.pinkInk, inkWidth: 0.022)
            pen.fill(HeadwearShape.ellipse(hwp(-0.035, 0.03), rx: 0.03, ry: 0.013, turn: 0.2), HeadwearColor(1, 1, 1, 0.8))
        }
    }
}

// MARK: - Reindeer

/// A reindeer: velvet antlers, soft ears and a round red nose that glows. Smile and it lights right up.
final class HeadwearReindeer: HeadwearCostume {
    let hint = "Smile to light up your nose"

    private var ears = HeadwearEarPair()
    private var shine = HeadwearFollower()
    private var antlers = HeadwearSwing(omega: 12, damping: 0.2, gain: 0.015, limit: 0.2)

    /// How brightly the nose glows, 0.2 at rest up to 1.
    var glow: Double { 0.2 + 0.8 * shine.value }

    func reset() { ears.reset(); shine = HeadwearFollower(); antlers.reset() }

    func advance(_ f: HeadwearFrame) {
        shine.follow(f.signals.isSmiling ? 1 : 0, dt: f.dt, rise: 5, fall: 2)
        if f.signals.blinkGate.rose { ears.twitch(5) }
        ears.step(f)
        antlers.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.05)
    }

    private static let velvet = [HeadwearColor(hex: 0xC48A58), HeadwearColor(hex: 0x8E5832), HeadwearColor(hex: 0x5E3418)]
    private static let ink = HeadwearColor(hex: 0x36190A)

    private static func paintAntler(_ pen: HeadwearPen) {
        // Drawn for the right side, rooted at the origin.
        func branch(from: CGPoint, length: Double, width: Double, heading: @escaping (Double) -> Double) -> CGPath {
            let spine = HeadwearShape.spine(from: from, length: length, steps: 12, heading: heading)
            return HeadwearShape.ribbon(spine, tip: 0.6, base: 0.3) { t in width * (1 - 0.55 * t) + 0.01 }
        }
        let beam = HeadwearShape.spine(from: hwp(0, 0), length: 1.3, steps: 16) { t in 1.2 - 0.9 * t + 0.6 * t * t }
        let parts: [CGPath] = [
            branch(from: beam[5], length: 0.5, width: 0.06) { t in 1.75 - 0.3 * t },
            branch(from: beam[9], length: 0.48, width: 0.055) { t in 1.35 - 0.2 * t },
            branch(from: beam[3], length: 0.32, width: 0.05) { t in 0.5 + 0.5 * t },
            HeadwearShape.ribbon(beam, tip: 0.6, base: 0.3) { t in 0.11 * (1 - 0.5 * t) + 0.01 },
        ]
        let all = CGMutablePath()
        for p in parts { all.addPath(p) }
        for p in parts { pen.stroke(p, ink, width: 0.09) }
        for p in parts { pen.paint(p, velvet, ink: nil, direction: CGVector(dx: 0.4, dy: -1)) }
        pen.clipped(to: all) {
            pen.stroke(HeadwearShape.smooth(beam.map { hwp($0.x - 0.035, $0.y + 0.03) }, closed: false), HeadwearColor(1, 0.92, 0.8, 0.4), width: 0.03)
        }
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            for (i, side) in [-1.0, 1.0].enumerated() {
                let grow = HeadwearEase.pop(f.seen, delay: 0.05 + 0.1 * Double(i), duration: 0.6)
                guard grow > 0.001 else { continue }
                pen.placed(at: f.head.at(side * 0.42, 1.18), turn: antlers.x, stretch: CGSize(width: side * grow, height: grow)) {
                    pen.sprite("reindeer-antler", window: CGRect(x: -0.35, y: -0.15, width: 1.55, height: 1.55), pixelsPerUnit: f.io) { Self.paintAntler($0) }
                }
                let pop = HeadwearEase.pop(f.seen, delay: 0.25 + 0.08 * Double(i), duration: 0.45)
                pen.placed(at: f.head.at(side * 0.95, 0.9), turn: -side * (1.1 + ears.flick[i].x), scale: pop) {
                    HeadwearEars.paint(pen, width: 0.36, height: 0.66, style: .pointed, side: side, fur: Self.velvet, ink: Self.ink,
                                       inner: [HeadwearColor(hex: 0xFFE8D2), HeadwearColor(hex: 0xEAC2A0)], lean: side * 0.03,
                                       bake: "reindeer-ear", pixelsPerUnit: f.io)
                }
            }
            drawNose(pen, f)
        }
    }

    private func drawNose(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let pop = HeadwearEase.pop(f.seen, delay: 0.4, duration: 0.45)
        guard pop > 0.001 else { return }
        let c = hwp(f.nose.x, f.nose.y + 0.04)
        let g = glow
        let pulse = 1 + 0.06 * sin(f.clock * 3.2) * (0.3 + 0.7 * shine.value)
        pen.glow(at: c, radius: (0.45 + 0.65 * g) * pulse * pop, HeadwearColor(1, 0.25, 0.25, 0.25 + 0.5 * g), additive: true)
        pen.placed(at: c, scale: pop) {
            let ball = HeadwearShape.ellipse(.zero, rx: 0.17, ry: 0.15)
            let hot = HeadwearColor(hex: 0xFF4A4A).mixed(with: HeadwearColor(hex: 0xFFB0A0), g * 0.6)
            pen.paintRound(ball, center: hwp(-0.05, 0.05), radius: 0.28, [HeadwearColor(hex: 0xFF9A90).mixed(with: .white, g * 0.4), hot, HeadwearColor(hex: 0xA3101C)],
                           ink: HeadwearColor(hex: 0x5E0810), inkWidth: 0.025)
            pen.fill(HeadwearShape.ellipse(hwp(-0.06, 0.06), rx: 0.06, ry: 0.03, turn: 0.5), HeadwearColor(1, 1, 1, 0.85))
        }
        if shine.value > 0.3 {
            let s = (shine.value - 0.3) / 0.7
            pen.sparkle(at: hwp(c.x + 0.16, c.y + 0.14), radius: 0.12 * s * (0.7 + 0.3 * sin(f.clock * 5)), HeadwearColor(1, 0.95, 0.9, 0.9), turn: f.clock, additive: true)
        }
    }
}

// MARK: - Unicorn

/// A unicorn: a pearly spiral horn, little ears and a flowing pastel mane. Smile and the horn glows and sheds sparkles.
final class HeadwearUnicorn: HeadwearCostume {
    let hint = "Smile and your horn glows"

    private var locks = [HeadwearSwing(omega: 4.5, damping: 0.15, gain: 0.05, limit: 0.7), HeadwearSwing(omega: 4.1, damping: 0.16, gain: 0.05, limit: 0.7)]
    private var magic = HeadwearFollower()
    private var sparkles = HeadwearFloaters(capacity: 40)
    private var owed = 0.0

    /// How brightly the horn glows, 0...1.
    var hornGlow: Double { magic.value }
    var sparkleCount: Int { sparkles.bits.count }

    init() { sparkles.lift = 120; sparkles.drag = 0.8 }

    func reset() { locks[0].reset(); locks[1].reset(); magic = HeadwearFollower(); sparkles.removeAll(); owed = 0 }

    func advance(_ f: HeadwearFrame) {
        for i in 0..<2 { locks[i].step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.8) }
        magic.follow(f.signals.isSmiling ? 1 : 0, dt: f.dt, rise: 5, fall: 2)
        owed += f.dt * 14 * magic.value
        let tip = f.toScreen(hwp(0, f.head.up(1.08) + 1.35))
        while owed >= 1 {
            owed -= 1
            let a = .pi / 2 + (sparkles.random(1) - 0.5) * 2.2 + f.roll
            sparkles.emit(at: tip, velocity: SIMD2(cos(a), sin(a)) * (0.8 + 1.2 * sparkles.random(2)), io: f.io,
                          life: 0.8 + 0.7 * sparkles.random(3), size: 0.06 + 0.07 * sparkles.random(4), spin: (sparkles.random(5) - 0.5) * 4)
        }
        sparkles.step(dt: f.dt, io: f.io)
    }

    private static let pastels = [HeadwearColor(hex: 0xFFB3D9), HeadwearColor(hex: 0xC9A7FF), HeadwearColor(hex: 0x9FE8D2), HeadwearColor(hex: 0x9FCFFF),
                                  HeadwearColor(hex: 0xFFD1A8)]

    private static let horn: CGPath = HeadwearShape.smooth([hwp(-0.21, 0), hwp(-0.13, 0.6), hwp(-0.03, 1.28), hwp(0, 1.36), hwp(0.03, 1.28),
                                                            hwp(0.13, 0.6), hwp(0.21, 0), hwp(0, -0.04)], smoothness: 0.5)

    private static func paintHorn(_ pen: HeadwearPen) {
        pen.paint(horn, [HeadwearColor(hex: 0xFFFDF5), HeadwearColor(hex: 0xFFE3F1), HeadwearColor(hex: 0xE2D4FF), HeadwearColor(hex: 0xC8F2E6)],
                  ink: HeadwearColor(hex: 0x9C86C8), inkWidth: 0.035, direction: CGVector(dx: 0.2, dy: 1))
        pen.clipped(to: horn) {
            // The spiral: grooves winding up, each with a light edge above it.
            for k in 0..<8 {
                let y = 0.04 + Double(k) * 0.17
                let w = 0.24 * (1 - y / 1.4)
                pen.stroke(HeadwearShape.smooth([hwp(-w, y - 0.02), hwp(0, y + 0.06), hwp(w, y + 0.13)], closed: false), HeadwearColor(hex: 0xA08ACC, alpha: 0.55), width: 0.025)
                pen.stroke(HeadwearShape.smooth([hwp(-w, y + 0.01), hwp(0, y + 0.09), hwp(w, y + 0.16)], closed: false), HeadwearColor(1, 1, 1, 0.7), width: 0.018)
            }
            pen.paint(horn, [HeadwearColor(1, 1, 1, 0.35), HeadwearColor(1, 1, 1, 0), HeadwearColor(0.4, 0.3, 0.6, 0.25)], direction: CGVector(dx: 1, dy: 0))
        }
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            for (i, side) in [-1.0, 1.0].enumerated() { drawMane(pen, f, side: side, swing: locks[i].x) }
            for (i, side) in [-1.0, 1.0].enumerated() {
                let pop = HeadwearEase.pop(f.seen, delay: 0.2 + 0.08 * Double(i), duration: 0.45)
                guard pop > 0.001 else { continue }
                pen.placed(at: f.head.at(side * 0.72, 1.06), turn: -side * 0.5, scale: pop) {
                    HeadwearEars.paint(pen, width: 0.36, height: 0.58, style: .pointed, side: side, fur: [HeadwearColor.white, HeadwearPalette.cream, HeadwearPalette.creamShade],
                                       ink: HeadwearPalette.whiteInk, inner: [HeadwearPalette.pinkLight, HeadwearPalette.pink],
                                       bake: "unicorn-ear", pixelsPerUnit: f.io)
                }
            }
            drawHorn(pen, f)
            drawForelock(pen, f)
        }
        drawSparkles(pen, f)
    }

    private func drawHorn(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.1, duration: 0.6)
        guard grow > 0.001 else { return }
        let base = hwp(0, f.head.up(1.08))
        let m = magic.value
        if m > 0.01 {
            pen.glow(at: hwp(base.x, base.y + 0.7), radius: 1.1 * m, HeadwearColor(1, 0.8, 0.95, 0.55 * m), additive: true)
        }
        pen.placed(at: base, stretch: CGSize(width: grow, height: grow)) {
            pen.shadow(at: hwp(0, 0.02), rx: 0.32, ry: 0.1, alpha: 0.35)
            pen.sprite("unicorn-horn", window: CGRect(x: -0.3, y: -0.1, width: 0.6, height: 1.55), pixelsPerUnit: f.io) { Self.paintHorn($0) }
            if m > 0.01 {
                pen.ctx.saveGState()
                pen.ctx.setBlendMode(.plusLighter)
                pen.fill(Self.horn, HeadwearColor(1, 0.75, 0.9, 0.3 * m))
                pen.ctx.restoreGState()
            }
            if let g = HeadwearGlint.phase(f.clock, period: 3.8, offset: 0.6) {
                HeadwearGlint.sweep(pen, over: Self.horn, box: Self.horn.boundingBoxOfPath, phase: g, strength: 0.4)
            }
        }
    }

    /// Pastel locks combed out from the crown, falling down past the ears and curling at the ends, swinging as you move.
    private func drawMane(_ pen: HeadwearPen, _ f: HeadwearFrame, side: Double, swing: Double) {
        let grow = HeadwearEase.smoothstep((f.seen - 0.15) / 0.6)
        guard grow > 0.01 else { return }
        for k in 0..<3 {
            let u = Double(k) / 2
            let theta = (76 - 50 * u) * .pi / 180
            let root = f.head.at(1.04 * cos(theta), 0.5 + 0.92 * sin(theta))
            let length = (2.5 - 0.7 * u) * grow
            let start = theta - .pi / 2
            let spine = HeadwearShape.spine(from: root, length: length, steps: 22) { t in
                // Built for the right-hand side: out along the head, then down, a lazy wave, and a curl inward at the end.
                let fall = start + (-.pi / 2 + 0.12 - start) * HeadwearEase.smoothstep(t / (0.3 - 0.12 * u))
                let wave = 0.16 * sin(t * 7 + f.clock * 1.3 + Double(k) * 1.7) * t
                let curl = -1.6 * HeadwearEase.smoothstep((t - 0.8) / 0.2)
                return fall + wave + curl + swing * side * t * 1.2
            }.map { hwp($0.x * side, $0.y) }
            let c = Self.pastels[(k * 2 + (side > 0 ? 1 : 0)) % Self.pastels.count]
            let lock = HeadwearShape.ribbon(spine, tip: 0.8, base: 0.5) { t in (0.17 - 0.02 * u) * (1 - 0.45 * t) * (1 - 0.7 * HeadwearEase.smoothstep((t - 0.75) / 0.25)) + 0.01 }
            pen.paint(lock, [c.lighter(0.45), c, c.darker(0.14)], ink: c.darker(0.42), inkWidth: 0.03, direction: CGVector(dx: -side * 0.5, dy: -1))
            pen.clipped(to: lock) {
                pen.stroke(HeadwearShape.smooth(spine.prefix(16).map { hwp($0.x - side * 0.05, $0.y + 0.03) }, closed: false), HeadwearColor(1, 1, 1, 0.55), width: 0.03)
            }
        }
    }

    private func drawForelock(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.35, duration: 0.5)
        guard grow > 0.01 else { return }
        let root = hwp(-0.12, f.head.up(1.12))
        let spine = HeadwearShape.spine(from: root, length: 0.75 * grow, steps: 12) { t in -.pi / 2 - 0.9 + 2.6 * t * t + 0.06 * sin(f.clock * 1.4) }
        let lock = HeadwearShape.ribbon(spine, tip: 0.8, base: 0.4) { t in 0.13 * (1 - 0.8 * t) + 0.01 }
        let c = Self.pastels[1]
        pen.paint(lock, [c.lighter(0.4), c, c.darker(0.12)], ink: c.darker(0.4), inkWidth: 0.03)
        pen.clipped(to: lock) {
            pen.stroke(HeadwearShape.smooth(spine.prefix(8).map { hwp($0.x + 0.03, $0.y + 0.02) }, closed: false), HeadwearColor(1, 1, 1, 0.5), width: 0.022)
        }
    }

    private func drawSparkles(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        for b in sparkles.bits {
            let t = b.age / b.life
            let fade = sin(min(1, t) * .pi)
            let c = Self.pastels[b.seed % Self.pastels.count].lighter(0.35)
            let r = b.size * f.io * (1 - 0.4 * t)
            let p = CGPoint(x: b.position.x, y: b.position.y)
            pen.glow(at: p, radius: r * 2.2, c.faded(0.5 * fade), additive: true)
            pen.sparkle(at: p, radius: r, HeadwearColor(1, 1, 1, 0.95 * fade), turn: b.turn, additive: true)
        }
    }
}
