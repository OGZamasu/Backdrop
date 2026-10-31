import CoreGraphics
import Foundation

// The four classic props, redrawn: a cat-ear headband, pixel shades, a jewelled crown and a party hat.

// MARK: - Cat ears

/// A velvet cat-ear headband, a little pink nose and whiskers. Blink and the ears flick; now and then one twitches by itself.
final class HeadwearCatEars: HeadwearCostume {
    let hint = "Blink and your ears flick"

    private var flick = [HeadwearSwing(omega: 24, damping: 0.16, gain: 0, limit: 0.7), HeadwearSwing(omega: 21, damping: 0.18, gain: 0, limit: 0.7)]
    private var sway = HeadwearSwing(omega: 11, damping: 0.2, gain: 0.02, limit: 0.25)
    private var untilTwitch = 3.0
    private var twitches = 0

    /// How many times the ears have flicked for a blink.
    private(set) var flicks = 0
    /// How far each ear is turned off its rest, in radians.
    var earTurn: [Double] { flick.map(\.x) }

    func reset() { flick[0].reset(); flick[1].reset(); sway.reset(); untilTwitch = 3; flicks = 0 }

    func advance(_ f: HeadwearFrame) {
        sway.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.08)
        if f.signals.blinkGate.rose {
            flicks += 1
            flick[0].shove(-11); flick[1].shove(9)
        }
        untilTwitch -= f.dt
        if untilTwitch <= 0 {
            twitches += 1
            let ear = twitches % 2
            flick[ear].shove(ear == 0 ? -6 : 6)
            untilTwitch = 2.5 + 4 * HeadwearNoise.unit(twitches, 3)
        }
        for i in 0..<2 { flick[i].step(dt: f.dt, accel: 0, rest: 0) }
    }

    private static let fur = [HeadwearColor(hex: 0x4A4256), HeadwearColor(hex: 0x231E2B), HeadwearColor(hex: 0x16121B)]
    private static let ink = HeadwearColor(hex: 0x0E0B12)

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            drawFace(pen, f)
            let fall = HeadwearEase.drop(f.seen, height: 1.8, duration: 0.6)
            pen.placed(at: hwp(0, fall), turn: sway.x) { drawBand(pen, f) }
        }
    }

    /// The headband's arc: centre, radii, and the point at an angle along it (radians, pi/2 at the top).
    private func band(_ f: HeadwearFrame) -> (centre: CGPoint, rx: Double, ry: Double) {
        let c = hwp(0, f.head.up(0.42))
        return (c, f.head.side(1.06), f.head.up(1.38) - c.y)
    }

    private func drawBand(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let (c, rx, ry) = band(f)
        let arc = CGMutablePath()
        arc.addArc(center: .zero, radius: 1, startAngle: .pi * 1.1, endAngle: -.pi * 0.1, clockwise: true,
                   transform: CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: rx, y: ry))
        let grow = HeadwearEase.smoothstep(f.seen / 0.25)
        // A soft shadow where the band presses on the hair, then the band, then a satin sheen along its top.
        pen.placed(at: hwp(0.02, -0.05)) { pen.stroke(arc, HeadwearColor(0.05, 0.02, 0.08, 0.28 * grow), width: 0.2) }
        for (i, side) in [-1.0, 1.0].enumerated() {
            let a = .pi / 2 - side * 0.64
            let base = hwp(c.x + cos(a) * rx * 0.98, c.y + sin(a) * ry * 0.98)
            let pop = HeadwearEase.pop(f.seen, delay: 0.18 + 0.08 * Double(i), duration: 0.45)
            guard pop > 0.001 else { continue }
            pen.placed(at: base, turn: -side * 0.42 + flick[i].x, scale: pop) {
                HeadwearEars.paint(pen, width: 0.66, height: 0.78, style: .pointed, side: side, fur: Self.fur, ink: Self.ink,
                                   inner: [HeadwearPalette.pinkLight, HeadwearPalette.pink], tuft: HeadwearPalette.cream.faded(0.7),
                                   lean: side * 0.05, bake: "cat-ear", pixelsPerUnit: f.io)
            }
        }
        pen.stroke(arc, Self.ink, width: 0.13 * grow)
        pen.stroke(arc, HeadwearColor(hex: 0x2E2738), width: 0.095 * grow)
        pen.placed(at: hwp(-0.006, 0.022)) { pen.stroke(arc, HeadwearColor(hex: 0x8C7FA0, alpha: 0.55), width: 0.022 * grow) }
    }

    private func drawFace(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let reveal = HeadwearEase.smoothstep((f.seen - 0.35) / 0.35)
        guard reveal > 0.01 else { return }
        let n = hwp(f.nose.x, f.nose.y + 0.03)
        HeadwearWhiskers.draw(pen, nose: n, length: 0.72, color: HeadwearPalette.night.faded(0.85), edge: HeadwearPalette.cream.faded(0.5),
                              lift: 0.4 * f.signals.grin, spread: f.signals.grin, clock: f.clock, reveal: reveal)
        let pop = HeadwearEase.pop(f.seen, delay: 0.35, duration: 0.4)
        pen.placed(at: n, scale: pop) {
            let nose = HeadwearShape.smooth([hwp(-0.11, 0.05), hwp(0, 0.075), hwp(0.11, 0.05), hwp(0.05, -0.04), hwp(0, -0.07), hwp(-0.05, -0.04)])
            pen.paintRound(nose, center: hwp(-0.03, 0.04), radius: 0.16, [HeadwearPalette.pinkLight, HeadwearPalette.pink],
                           ink: HeadwearPalette.pinkInk, inkWidth: 0.025)
            pen.fill(HeadwearShape.ellipse(hwp(-0.035, 0.035), rx: 0.035, ry: 0.015, turn: 0.2), HeadwearColor(1, 1, 1, 0.8))
            let mouth = CGMutablePath()
            mouth.move(to: hwp(0, -0.07)); mouth.addLine(to: hwp(0, -0.13))
            mouth.move(to: hwp(-0.08, -0.15)); mouth.addQuadCurve(to: hwp(0, -0.13), control: hwp(-0.045, -0.19))
            mouth.addQuadCurve(to: hwp(0.08, -0.15), control: hwp(0.045, -0.19))
            pen.stroke(mouth, HeadwearPalette.night.faded(0.75), width: 0.022)
        }
    }
}

// MARK: - Shades

/// Chunky pixel-art sunglasses that slide down from out of the picture and land with a bump and a glint.
/// Raise your eyebrows and they slip down your nose so you can peek over them.
final class HeadwearShades: HeadwearCostume {
    let hint = "Deal with it. Raise your brows to peek over"

    private var slip = HeadwearSwing(omega: 13, damping: 0.3, gain: 0, limit: 0.6)

    /// How far the shades have slipped down the nose, in eye-spacings.
    var peek: Double { slip.x }

    /// Seconds before they start down, and how long the slide takes.
    static let delay = 0.15, slide = 0.9

    func reset() { slip.reset() }

    func advance(_ f: HeadwearFrame) {
        slip.step(dt: f.dt, accel: 0, rest: f.signals.browsAreUp ? 0.34 : 0)
    }

    /// The cells of the shades, 26 across and 5 down from the top; 1 is black glass and frame, 2 is a glint.
    private static let rows: [String] = [
        "11111111111111111111111111",
        "00111111111100111111111100",
        "00122111111100122111111100",
        "00021111111000002111111000",
        "00001111110000000111111000",
    ]
    private static let cell = 0.09

    private static var frame: CGPath { cells.frame }
    private static var glints: CGPath { cells.glints }
    private static let cells: (frame: CGPath, glints: CGPath) = {
        let body = CGMutablePath(), shine = CGMutablePath()
        for (r, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() where ch != "0" {
                let rect = CGRect(x: (Double(i) - 13) * cell, y: 0.225 - Double(r + 1) * cell, width: cell, height: cell)
                body.addRect(rect)
                if ch == "2" { shine.addRect(rect) }
            }
        }
        return (body, shine)
    }()

    /// How far above their resting place the shades are, in eye-spacings, `t` seconds after the face appeared; `from` is where
    /// they start (out of the picture). They ease in, land, and dip once.
    static func height(_ t: Double, from: Double) -> Double {
        let p = (t - delay) / slide
        if p <= 0 { return from }
        if p < 1 { let e = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2; return from * (1 - e) }
        let after = (p - 1) * slide
        return -0.05 * sin(min(1, after / 0.28) * .pi) * exp(-after * 3)
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        // Start just out of the top of the picture, however far the head is from it.
        let room = (Double(f.bounds.maxY) - Double(f.center.y)) / f.io / max(0.5, cos(f.roll))
        let from = max(2.5, room + 0.8)
        let y = Self.height(f.seen, from: from) - slip.x
        f.inFace(pen.ctx) {
            pen.placed(at: hwp(0, y)) {
                // A soft shadow on the cheeks, then the glass, then the glints.
                let landed = HeadwearEase.smoothstep((f.seen - Self.delay - Self.slide * 0.8) / 0.3)
                pen.placed(at: hwp(0.03, -0.06)) { pen.fill(Self.frame, HeadwearColor(0.05, 0.02, 0.08, 0.22 * landed)) }
                pen.fill(Self.frame, HeadwearColor(hex: 0x111015))
                pen.fill(Self.glints, HeadwearPalette.cream)
                let box = Self.frame.boundingBoxOfPath
                let since = f.seen - Self.delay - Self.slide
                if since > 0, since < 0.7 {
                    HeadwearGlint.sweep(pen, over: Self.frame, box: box, phase: since / 0.7, strength: 0.35)
                } else if let g = HeadwearGlint.phase(f.clock, period: 5.5, offset: 1.1, length: 0.8) {
                    HeadwearGlint.sweep(pen, over: Self.frame, box: box, phase: g, strength: 0.28)
                }
                if since > 0.15, since < 0.75 {
                    let s = sin((since - 0.15) / 0.6 * .pi)
                    pen.sparkle(at: hwp(-0.78, 0.2), radius: 0.2 * s, HeadwearColor(1, 1, 0.92, 0.95), turn: since, additive: true)
                }
            }
        }
    }
}

// MARK: - Crown

/// A jewelled gold crown over a velvet cap that lands on your head. A glint runs across the gold now and then;
/// smile and the gems sparkle.
final class HeadwearCrown: HeadwearCostume {
    let hint = "Smile and the jewels sparkle"

    private var sway = HeadwearSwing(omega: 9, damping: 0.16, gain: 0.025, limit: 0.25)

    /// How hard the gems sparkle, 0...1.
    private(set) var dazzle = 0.0

    func reset() { sway.reset(); dazzle = 0 }

    func advance(_ f: HeadwearFrame) {
        sway.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.06)
        dazzle = f.signals.grin
    }

    /// The gold outline, base centre at the origin.
    static let body: CGPath = {
        let p = CGMutablePath()
        p.move(to: hwp(-0.84, -0.02))
        p.addLine(to: hwp(-0.92, 0.86))
        p.addQuadCurve(to: hwp(-0.42, 1.0), control: hwp(-0.6, 0.42))
        p.addQuadCurve(to: hwp(0, 1.18), control: hwp(-0.2, 0.48))
        p.addQuadCurve(to: hwp(0.42, 1.0), control: hwp(0.2, 0.48))
        p.addQuadCurve(to: hwp(0.92, 0.86), control: hwp(0.6, 0.42))
        p.addLine(to: hwp(0.84, -0.02))
        p.addQuadCurve(to: hwp(-0.84, -0.02), control: hwp(0, -0.14))
        p.closeSubpath()
        return p
    }()

    static let band: CGPath = {
        let p = CGMutablePath()
        p.move(to: hwp(-0.85, -0.02))
        p.addQuadCurve(to: hwp(0.85, -0.02), control: hwp(0, -0.14))
        p.addLine(to: hwp(0.87, 0.3))
        p.addQuadCurve(to: hwp(-0.87, 0.3), control: hwp(0, 0.2))
        p.closeSubpath()
        return p
    }()

    /// Where the gems sit, with their size and colours (light, deep).
    private static let gems: [(at: CGPoint, r: Double, light: HeadwearColor, deep: HeadwearColor)] = [
        (hwp(0, 0.12), 0.12, HeadwearColor(hex: 0xFF8A9A), HeadwearColor(hex: 0xA3122E)),
        (hwp(-0.5, 0.15), 0.085, HeadwearColor(hex: 0x8FC2FF), HeadwearColor(hex: 0x1F45A8)),
        (hwp(0.5, 0.15), 0.085, HeadwearColor(hex: 0x8FC2FF), HeadwearColor(hex: 0x1F45A8)),
        (hwp(0, 0.72), 0.075, HeadwearColor(hex: 0x9BF0C0), HeadwearColor(hex: 0x12795A)),
        (hwp(-0.47, 0.6), 0.06, HeadwearColor(hex: 0xFF8A9A), HeadwearColor(hex: 0xA3122E)),
        (hwp(0.47, 0.6), 0.06, HeadwearColor(hex: 0xFF8A9A), HeadwearColor(hex: 0xA3122E)),
    ]
    private static let pearls: [CGPoint] = [hwp(-0.92, 0.9), hwp(-0.42, 1.04), hwp(0.42, 1.04), hwp(0.92, 0.9)]

    static func paintGem(_ pen: HeadwearPen, at c: CGPoint, r: Double, light: HeadwearColor, deep: HeadwearColor) {
        let stone = HeadwearShape.ellipse(c, rx: r, ry: r * 0.82)
        pen.paintRound(stone, center: hwp(c.x - r * 0.35, c.y + r * 0.35), radius: r * 1.5, [light, deep, deep.darker(0.35)],
                       ink: HeadwearPalette.goldInk, inkWidth: 0.03)
        let table = HeadwearShape.polygon([hwp(c.x - r * 0.45, c.y + r * 0.1), hwp(c.x, c.y + r * 0.42), hwp(c.x + r * 0.45, c.y + r * 0.1),
                                           hwp(c.x + r * 0.25, c.y - r * 0.35), hwp(c.x - r * 0.25, c.y - r * 0.35)])
        pen.fill(table, light.faded(0.35))
        pen.stroke(table, deep.darker(0.3).faded(0.5), width: 0.012)
        pen.fill(HeadwearShape.ellipse(hwp(c.x - r * 0.38, c.y + r * 0.3), rx: r * 0.22, ry: r * 0.13, turn: 0.6), HeadwearColor(1, 1, 1, 0.85))
    }

    /// Everything that doesn't move, painted once.
    private static func paintCrown(_ pen: HeadwearPen) {
        let ink = HeadwearPalette.goldInk
        // The velvet cap showing between the points.
        let cap = HeadwearShape.smooth([hwp(-0.78, 0.2), hwp(-0.72, 0.72), hwp(-0.36, 1.02), hwp(0, 1.08), hwp(0.36, 1.02), hwp(0.72, 0.72),
                                        hwp(0.78, 0.2)])
        pen.paintRound(cap, center: hwp(-0.3, 0.9), radius: 1.2, [HeadwearColor(hex: 0xE2425E), HeadwearColor(hex: 0xA3172F), HeadwearColor(hex: 0x5E0919)],
                       ink: HeadwearColor(hex: 0x40050F), inkWidth: 0.04)
        pen.clipped(to: cap) {
            for k in -2...2 {
                let x = Double(k) * 0.3
                pen.stroke(HeadwearShape.smooth([hwp(x * 0.9, 0.2), hwp(x * 0.95, 0.6), hwp(x * 0.6, 1.05)], closed: false),
                           HeadwearColor(hex: 0x40050F, alpha: 0.35), width: 0.03)
            }
        }
        // The gold.
        pen.paint(body, [HeadwearPalette.goldLight, HeadwearPalette.gold, HeadwearPalette.goldDeep], ink: ink, inkWidth: 0.05,
                  direction: CGVector(dx: 0.45, dy: -1))
        pen.clipped(to: body) {
            pen.placed(at: hwp(0.03, -0.035)) { pen.stroke(body, HeadwearColor(1, 1, 0.9, 0.55), width: 0.05) }
            pen.placed(at: hwp(-0.03, 0.035)) { pen.stroke(body, ink.faded(0.3), width: 0.05) }
        }
        pen.paint(band, [HeadwearPalette.gold, HeadwearPalette.goldDeep], ink: ink, inkWidth: 0.035, direction: CGVector(dx: 0.3, dy: -1))
        pen.clipped(to: band) {
            pen.placed(at: hwp(0, -0.03)) { pen.stroke(band, HeadwearColor(1, 1, 0.85, 0.5), width: 0.035) }
        }
        // Little beads along the band.
        for k in 0..<12 {
            let x = -0.8 + Double(k) * 1.6 / 11
            guard abs(x) > 0.2, abs(abs(x) - 0.5) > 0.12 else { continue }
            let y = 0.2 - 0.06 * (1 - pow(x / 0.85, 2)) - 0.04
            pen.paintRound(HeadwearShape.ellipse(hwp(x, y), rx: 0.03, ry: 0.03), center: hwp(x - 0.01, y + 0.01), radius: 0.04,
                           [HeadwearPalette.goldLight, HeadwearPalette.goldDeep], ink: ink.faded(0.7), inkWidth: 0.012)
        }
        for g in gems { paintGem(pen, at: g.at, r: g.r, light: g.light, deep: g.deep) }
        for p in pearls {
            pen.paintRound(HeadwearShape.ellipse(p, rx: 0.075, ry: 0.075), center: hwp(p.x - 0.025, p.y + 0.03), radius: 0.1,
                           [HeadwearColor.white, HeadwearPalette.cream, HeadwearColor(hex: 0xC9BFD6)], ink: HeadwearPalette.whiteInk, inkWidth: 0.02)
        }
        // A small cross on the top point.
        let cross = CGMutablePath()
        cross.addPath(HeadwearShape.rounded(CGRect(x: -0.035, y: 1.12, width: 0.07, height: 0.24), radius: 0.02))
        cross.addPath(HeadwearShape.rounded(CGRect(x: -0.09, y: 1.22, width: 0.18, height: 0.065), radius: 0.02))
        pen.paint(cross, [HeadwearPalette.goldLight, HeadwearPalette.goldDeep], ink: ink, inkWidth: 0.025)
    }

    private static let window = CGRect(x: -1.05, y: -0.22, width: 2.1, height: 1.62)

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 2.8, duration: 0.75)
        let scale = f.head.wide
        f.inFace(pen.ctx) {
            pen.placed(at: hwp(0, f.head.up(1.1) + fall), turn: sway.x, scale: scale) {
                let landed = HeadwearEase.smoothstep(1 - fall / 0.6)
                pen.shadow(at: hwp(0, 0.0), rx: 0.95, ry: 0.2, alpha: 0.45 * landed)
                pen.sprite("crown", window: Self.window, pixelsPerUnit: f.io * scale) { Self.paintCrown($0) }
                if let g = HeadwearGlint.phase(f.clock, period: 4.5, offset: 0.4) {
                    HeadwearGlint.sweep(pen, over: Self.body, box: Self.body.boundingBoxOfPath, phase: g, strength: 0.45)
                }
                drawSparkles(pen, f)
            }
        }
    }

    private func drawSparkles(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let lit = dazzle
        guard lit > 0.02 else { return }
        pen.ctx.saveGState()
        pen.ctx.setBlendMode(.plusLighter)
        pen.fill(Self.body, HeadwearColor(1, 0.85, 0.4, 0.12 * lit))
        pen.ctx.restoreGState()
        for (k, g) in (Self.gems.map { ($0.at, $0.r) } + Self.pearls.map { ($0, 0.07) }).enumerated() {
            let beat = pow(max(0, sin(f.clock * (3.1 + 0.7 * HeadwearNoise.unit(k, 1)) + HeadwearNoise.unit(k, 2) * 6.28)), 4)
            let r = (g.1 * 2.2 + 0.08) * beat * lit
            guard r > 0.01 else { continue }
            let at = hwp(g.0.x - g.1 * 0.3, g.0.y + g.1 * 0.3)
            pen.glow(at: at, radius: r * 1.6, HeadwearColor(1, 0.95, 0.75, 0.45 * lit), additive: true)
            pen.sparkle(at: at, radius: r, HeadwearColor(1, 1, 0.95, 0.95), turn: 0.3 * Double(k), additive: true)
        }
    }
}

// MARK: - Party hat

/// A striped party hat with a fluffy pom-pom on a spring. Open your mouth and a party horn unrolls, with a puff of confetti.
final class HeadwearPartyHat: HeadwearCostume {
    let hint = "Open your mouth to blow the party horn"

    private var pom = HeadwearSwing(omega: 9, damping: 0.12, gain: 0.05, limit: 0.8)
    private var lean = HeadwearSwing(omega: 8, damping: 0.18, gain: 0.02, limit: 0.3)
    private var horn = HeadwearSwing(omega: 15, damping: 0.42, gain: 0, limit: 1.25)
    private var confetti = HeadwearFloaters(capacity: 60)
    private var tooted = false

    /// How far the party horn has unrolled, 0 rolled up to 1 straight out.
    var hornOut: Double { min(1, max(0, horn.x)) }
    /// How many bits of confetti are in the air.
    var confettiCount: Int { confetti.bits.count }

    private static let palette = [HeadwearColor(hex: 0xFF5D73), HeadwearColor(hex: 0xFFD166), HeadwearColor(hex: 0x3EC9B6),
                                  HeadwearColor(hex: 0x8C7CF0), HeadwearColor(hex: 0x5BB8FF)]

    init() { confetti.lift = -900; confetti.drag = 1.4 }

    func reset() { pom.reset(); lean.reset(); horn.reset(); confetti.removeAll(); tooted = false }

    func advance(_ f: HeadwearFrame) {
        pom.step(dt: f.dt, accel: f.accel.x * 1.4, rest: f.hang * 0.4)
        lean.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.05)
        horn.step(dt: f.dt, accel: 0, rest: f.signals.mouthIsOpen ? 1 : 0)
        if horn.x > 0.85, !tooted {
            tooted = true
            let tip = f.toScreen(hornTip(f, out: 1))
            for _ in 0..<16 {
                let a = (confetti.random(1) - 0.5) * 2.2 + 0.4, speed = 1.6 + 2.2 * confetti.random(2)
                confetti.emit(at: tip, velocity: SIMD2(cos(a + f.roll), sin(a + f.roll)) * speed, io: f.io,
                              life: 1.1 + 0.8 * confetti.random(3), size: 0.05 + 0.04 * confetti.random(4), spin: (confetti.random(5) - 0.5) * 14)
            }
        }
        if horn.x < 0.3 { tooted = false }
        confetti.step(dt: f.dt, io: f.io)
    }

    /// The cone, base centre at the origin.
    private static let cone: CGPath = {
        let p = CGMutablePath()
        p.move(to: hwp(-0.64, 0))
        p.addLine(to: hwp(-0.03, 1.74))
        p.addQuadCurve(to: hwp(0.03, 1.74), control: hwp(0, 1.77))
        p.addLine(to: hwp(0.64, 0))
        p.addQuadCurve(to: hwp(-0.64, 0), control: hwp(0, -0.16))
        p.closeSubpath()
        return p
    }()

    private static func paintHat(_ pen: HeadwearPen) {
        let ink = HeadwearColor(hex: 0x6B1F3A)
        pen.paint(cone, [HeadwearColor(hex: 0xFF8597), HeadwearColor(hex: 0xF0506A)], ink: nil)
        pen.clipped(to: cone) {
            // Cream stripes winding round, with gold dots between.
            for k in -4...6 {
                let y = Double(k) * 0.34
                let stripe = HeadwearShape.polygon([hwp(-0.8, y), hwp(0.8, y + 0.46), hwp(0.8, y + 0.6), hwp(-0.8, y + 0.14)])
                pen.fill(stripe, HeadwearColor(hex: 0xFFF3DC))
                for d in 0..<4 {
                    let x = -0.6 + Double(d) * 0.4
                    pen.dot(at: hwp(x, y + 0.29 + (x + 0.8) * 0.2875 - 0.02), radius: 0.04, HeadwearColor(hex: 0xFFC94A))
                }
            }
            // Round shading: light down the left, shade down the right.
            pen.paint(cone, [HeadwearColor(1, 1, 1, 0.28), HeadwearColor(1, 1, 1, 0), HeadwearColor(0.25, 0.02, 0.12, 0.0), HeadwearColor(0.25, 0.02, 0.12, 0.38)],
                      direction: CGVector(dx: 1, dy: 0))
            pen.stroke(HeadwearShape.smooth([hwp(-0.36, 0.1), hwp(-0.2, 0.8), hwp(-0.06, 1.5)], closed: false), HeadwearColor(1, 1, 1, 0.35), width: 0.05)
        }
        pen.stroke(cone, ink, width: 0.045)
        // Gold foil round the bottom.
        var scallops: [CGPoint] = []
        for k in 0...10 {
            let u = Double(k) / 10, x = -0.64 + 1.28 * u
            scallops.append(hwp(x, -0.08 * (1 - pow(x / 0.64, 2)) + 0.02))
        }
        let trim = CGMutablePath()
        for p in scallops { trim.addPath(HeadwearShape.ellipse(p, rx: 0.085, ry: 0.07)) }
        pen.fill(trim, HeadwearPalette.goldInk)
        pen.placed(at: hwp(0, 0.012)) {
            let inner = CGMutablePath()
            for p in scallops { inner.addPath(HeadwearShape.ellipse(p, rx: 0.068, ry: 0.054)) }
            pen.paint(inner, [HeadwearPalette.goldLight, HeadwearPalette.gold, HeadwearPalette.goldDeep], ink: nil)
        }
    }

    private static let window = CGRect(x: -0.8, y: -0.2, width: 1.6, height: 2.05)

    /// Where the horn ends, in face units, when it is `out` of the way unrolled.
    private func hornTip(_ f: HeadwearFrame, out: Double) -> CGPoint {
        hornSpine(f, out: out).last ?? f.mouth
    }

    /// The horn's centre line from the mouth: straight for the unrolled part, curling into a tight spiral for the rest.
    private func hornSpine(_ f: HeadwearFrame, out: Double, wobble: Double = 0) -> [CGPoint] {
        let length = 1.45
        let start = hwp(f.mouth.x + 0.16, f.mouth.y - 0.02)
        let straight = max(0.0, min(1.0, out)) * length
        return HeadwearShape.spine(from: start, length: length, steps: 40) { t in
            let s = t * length
            let base = -0.18 + wobble * t
            guard s > straight else { return base }
            let rolled = s - straight, rest = max(length - straight, 0.01)
            // Curvature grows toward the end of the paper, so it rolls up tight.
            return base + 5.5 * (rolled + 1.6 * rolled * rolled / rest)
        }
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 2.6, duration: 0.7)
        f.inFace(pen.ctx) {
            drawHorn(pen, f)
            pen.placed(at: hwp(f.head.side(0.18), f.head.up(1.12) + fall), turn: -0.16 + lean.x, scale: f.head.wide) {
                let landed = HeadwearEase.smoothstep(1 - fall / 0.6)
                pen.shadow(at: hwp(0, -0.02), rx: 0.75, ry: 0.17, alpha: 0.4 * landed)
                pen.sprite("party-hat", window: Self.window, pixelsPerUnit: f.io * f.head.wide) { Self.paintHat($0) }
                drawPom(pen, f)
            }
        }
        drawConfetti(pen, f)
    }

    private func drawPom(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let swing = pom.x
        let c = hwp(swing * 0.22, 1.82 - abs(swing) * 0.05)
        var puffs: [(centre: CGPoint, radius: Double)] = [(c, 0.13)]
        for k in 0..<9 {
            let a = Double(k) / 9 * 2 * .pi + swing
            puffs.append((hwp(c.x + cos(a) * 0.12, c.y + sin(a) * 0.11), 0.075 + 0.015 * HeadwearNoise.unit(k, 9)))
        }
        HeadwearFacialHair.cloud(pen, body: CGMutablePath(), puffs: puffs, colors: [HeadwearColor(hex: 0xFFF2B0), HeadwearColor(hex: 0xFFC94A), HeadwearColor(hex: 0xE89A1C)],
                                 ink: HeadwearColor(hex: 0x8A5A0A), outline: 0.03, shade: (hwp(c.x + 0.08, c.y - 0.12), 0.25, HeadwearColor(hex: 0x9A5A08, alpha: 0.35)))
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi + 0.4 + swing * 0.5
            pen.line(hwp(c.x + cos(a) * 0.06, c.y + sin(a) * 0.06), hwp(c.x + cos(a) * 0.2, c.y + sin(a) * 0.19), HeadwearColor(1, 1, 0.85, 0.55), width: 0.014)
        }
    }

    private func drawHorn(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let out = horn.x
        guard out > 0.02 else { return }
        let appear = min(1, out / 0.15)
        let flutter = f.signals.mouthIsOpen ? 0.05 * sin(f.clock * 26) * min(1, out) : 0
        let spine = hornSpine(f, out: out, wobble: flutter)
        let path = HeadwearShape.smooth(spine, closed: false)
        // The mouthpiece, then the paper: a coral strip with cream bands across it.
        let mouthpiece = hwp(f.mouth.x + 0.06, f.mouth.y - 0.01)
        pen.line(mouthpiece, spine[0], HeadwearPalette.goldInk.scaled(appear), width: 0.1)
        pen.line(mouthpiece, spine[0], HeadwearPalette.gold.scaled(appear), width: 0.07)
        pen.stroke(path, HeadwearColor(hex: 0x7A1F36, alpha: appear), width: 0.15, cap: .round)
        pen.stroke(path, HeadwearColor(hex: 0xFF5D73, alpha: appear), width: 0.115, cap: .round)
        pen.ctx.saveGState()
        pen.ctx.setLineDash(phase: 0, lengths: [0.07, 0.09])
        pen.stroke(path, HeadwearColor(hex: 0xFFF3DC, alpha: appear), width: 0.115, cap: .butt)
        pen.ctx.restoreGState()
        pen.stroke(path, HeadwearColor(1, 1, 1, 0.3 * appear), width: 0.025)
        // A little fringe of streamers at the end once it is out.
        if out > 0.75, let tip = spine.last, spine.count > 2 {
            let before = spine[spine.count - 2]
            let a = atan2(tip.y - before.y, tip.x - before.x)
            let k = min(1, (out - 0.75) / 0.2)
            for (i, c) in Self.palette.prefix(4).enumerated() {
                let fan = a + (Double(i) - 1.5) * 0.35 + 0.08 * sin(f.clock * 18 + Double(i))
                pen.line(tip, hwp(tip.x + cos(fan) * 0.22 * k, tip.y + sin(fan) * 0.22 * k), c, width: 0.03)
            }
        }
    }

    private func drawConfetti(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        for b in confetti.bits {
            let fade = min(1, (b.life - b.age) / 0.4) * min(1, b.age / 0.05)
            let c = Self.palette[b.seed % Self.palette.count]
            let w = b.size * f.io, flip = abs(cos(b.age * 9 + Double(b.seed)))
            pen.placed(at: CGPoint(x: b.position.x, y: b.position.y), turn: b.turn) {
                pen.fill(HeadwearShape.rounded(CGRect(x: -w / 2, y: -w * 0.3 * flip, width: w, height: max(0.5, w * 0.6 * flip)), radius: w * 0.12),
                         c.mixed(with: .black, (1 - flip) * 0.25).scaled(fade))
            }
        }
    }
}
