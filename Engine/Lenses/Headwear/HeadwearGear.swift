import CoreGraphics
import Foundation

// Things you put on: studio headphones, a space helmet, robot gear and a mermaid's tiara.

// MARK: - Headphones

/// Big studio headphones. Smile and the music starts: the cups pulse to the beat and notes drift out.
final class HeadwearHeadphones: HeadwearCostume {
    let hint = "Smile and the music starts"

    private var groove = HeadwearFollower()
    private var notes = HeadwearFloaters(capacity: 24)
    private var lastBeat = -1
    private var sway = HeadwearSwing(omega: 9, damping: 0.2, gain: 0.02, limit: 0.2)

    /// How loud the music is, 0...1.
    var volume: Double { groove.value }
    var noteCount: Int { notes.bits.count }
    /// Beats a second.
    static let tempo = 2.0

    init() { notes.lift = 60; notes.drag = 0.9 }

    func reset() { groove = HeadwearFollower(); notes.removeAll(); lastBeat = -1; sway.reset() }

    /// How hard the beat is hitting, 0...1, sharp on the beat and quick to fade.
    func beat(_ clock: Double) -> Double { pow(max(0, cos(clock * 2 * .pi * Self.tempo)), 8) }

    func advance(_ f: HeadwearFrame) {
        groove.follow(f.signals.isSmiling ? 1 : 0, dt: f.dt, rise: 5, fall: 1.8)
        sway.step(dt: f.dt, accel: f.accel.x, rest: 0)
        let count = Int(floor(f.clock * Self.tempo))
        if count != lastBeat {
            lastBeat = count
            // A note on every beat while the music plays, from alternate sides.
            if groove.value > 0.5 {
                let side = count % 2 == 0 ? 1.0 : -1.0
                let from = f.toScreen(hwp(f.head.side(side * 1.35), 0.2))
                let a = .pi / 2 + side * (-0.5 - 0.4 * notes.random(1)) + f.roll
                notes.emit(at: from, velocity: SIMD2(cos(a), sin(a)) * (1.0 + 0.6 * notes.random(2)), io: f.io, life: 1.6 + 0.6 * notes.random(3),
                           size: 0.24 + 0.1 * notes.random(4), spin: (notes.random(5) - 0.5) * 1.2)
            }
        }
        notes.step(dt: f.dt, io: f.io)
    }

    private static let shell = [HeadwearColor(hex: 0x5E6380), HeadwearColor(hex: 0x363A50), HeadwearColor(hex: 0x1B1D2A)]
    private static let ink = HeadwearColor(hex: 0x0C0D14)
    private static let accent = HeadwearColor(hex: 0xFF6B5A)
    private static let noteColours = [HeadwearColor(hex: 0xFF6B6B), HeadwearColor(hex: 0xFFD166), HeadwearColor(hex: 0x4EA8F0), HeadwearColor(hex: 0x3CC9A0),
                                      HeadwearColor(hex: 0xB59CFF)]

    /// The right-hand cup, centred on the origin; the left is its mirror image.
    private static func paintCup(_ pen: HeadwearPen) {
        // The cushion against the head, then the shell, then the yoke that holds it.
        let cushion = HeadwearShape.rounded(CGRect(x: -0.26, y: -0.5, width: 0.3, height: 1.0), radius: 0.15)
        pen.paint(cushion, [HeadwearColor(hex: 0x4A4A56), HeadwearColor(hex: 0x24242C)], ink: ink, inkWidth: 0.035, direction: CGVector(dx: 1, dy: 0))
        let shell = HeadwearShape.rounded(CGRect(x: -0.12, y: -0.46, width: 0.38, height: 0.92), radius: 0.18)
        pen.paint(shell, Self.shell, ink: ink, inkWidth: 0.045, direction: CGVector(dx: 0.6, dy: -1))
        pen.clipped(to: shell) {
            pen.stroke(HeadwearShape.smooth([hwp(-0.06, 0.32), hwp(0.0, 0.42), hwp(0.12, 0.43)], closed: false), HeadwearColor(1, 1, 1, 0.45), width: 0.04)
            pen.stroke(HeadwearShape.smooth([hwp(-0.07, -0.25), hwp(-0.07, 0.25)], closed: false), HeadwearColor(1, 1, 1, 0.18), width: 0.05)
        }
        let ring = HeadwearShape.rounded(CGRect(x: -0.02, y: -0.3, width: 0.2, height: 0.6), radius: 0.1)
        pen.stroke(ring, accent.darker(0.4), width: 0.06)
        pen.stroke(ring, accent, width: 0.035)
        pen.fill(HeadwearShape.ellipse(hwp(0.08, 0.0), rx: 0.035, ry: 0.035), HeadwearColor(1, 1, 1, 0.6))
        let yoke = HeadwearShape.rounded(CGRect(x: -0.06, y: 0.38, width: 0.12, height: 0.36), radius: 0.05)
        pen.paint(yoke, [HeadwearPalette.steelLight, HeadwearPalette.steel, HeadwearPalette.steelDeep], ink: HeadwearPalette.steelInk, inkWidth: 0.025,
                  direction: CGVector(dx: 1, dy: 0))
    }

    private static let cupWindow = CGRect(x: -0.32, y: -0.56, width: 0.66, height: 1.34)

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let drop = HeadwearEase.drop(f.seen, height: 2.4, duration: 0.7)
        let pulse = 1 + 0.045 * beat(f.clock) * groove.value
        let cupX = f.head.side(1.2), cupY = -0.22
        let topY = f.head.crown + 0.14
        f.inFace(pen.ctx) {
            pen.placed(at: hwp(0, drop), turn: sway.x) {
                // The band over the top: padded underneath, a sheen along the top.
                let band = CGMutablePath()
                band.addArc(center: .zero, radius: 1, startAngle: .pi * 0.98, endAngle: .pi * 0.02, clockwise: true,
                            transform: CGAffineTransform(translationX: 0, y: cupY + 0.5).scaledBy(x: cupX - 0.02, y: topY - cupY - 0.5))
                pen.placed(at: hwp(0.02, -0.06)) { pen.stroke(band, HeadwearColor(0.05, 0.02, 0.08, 0.25), width: 0.22) }
                pen.stroke(band, Self.ink, width: 0.19)
                pen.stroke(band, Self.shell[1], width: 0.15)
                pen.placed(at: hwp(0, -0.05)) { pen.stroke(band, HeadwearColor(hex: 0x24242C), width: 0.07) }
                pen.placed(at: hwp(-0.01, 0.04)) { pen.stroke(band, HeadwearColor(1, 1, 1, 0.3), width: 0.03) }
                for side in [-1.0, 1.0] {
                    pen.placed(at: hwp(side * cupX, cupY), stretch: CGSize(width: side * pulse, height: pulse)) {
                        if groove.value > 0.01 {
                            pen.glow(at: hwp(0.08, 0), radius: 0.55, Self.accent.faded(0.35 * groove.value * (0.5 + 0.5 * beat(f.clock))), additive: true)
                        }
                        pen.sprite("headphone-cup", window: Self.cupWindow, pixelsPerUnit: f.io) { Self.paintCup($0) }
                    }
                }
            }
        }
        drawNotes(pen, f)
    }

    private func drawNotes(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        for b in notes.bits {
            let t = b.age / b.life
            let fade = min(1, t / 0.15) * min(1, (1 - t) / 0.3)
            let c = Self.noteColours[b.seed % Self.noteColours.count]
            let s = b.size * f.io
            let wobble = 0.25 * sin(b.age * 4 + Double(b.seed))
            pen.placed(at: CGPoint(x: b.position.x, y: b.position.y), turn: b.turn * 0.3 + wobble + f.roll, scale: s) {
                let ink = c.darker(0.5).scaled(fade)
                if b.seed % 3 == 0 {
                    // Two notes joined by a beam.
                    let beam = HeadwearShape.polygon([hwp(-0.12, 0.62), hwp(0.42, 0.72), hwp(0.42, 0.58), hwp(-0.12, 0.48)])
                    for x in [-0.12, 0.42] { pen.line(hwp(x, 0.0), hwp(x, 0.6), ink, width: 0.09); pen.line(hwp(x, 0.0), hwp(x, 0.6), c.scaled(fade), width: 0.05) }
                    pen.fill(beam, c.scaled(fade)); pen.stroke(beam, ink, width: 0.03)
                    for x in [-0.12, 0.42] {
                        let head = HeadwearShape.ellipse(hwp(x - 0.12, -0.02), rx: 0.15, ry: 0.11, turn: 0.4)
                        pen.paint(head, [c.lighter(0.3).scaled(fade), c.scaled(fade)], ink: ink, inkWidth: 0.04)
                    }
                } else {
                    pen.line(hwp(0.12, 0.0), hwp(0.12, 0.66), ink, width: 0.09)
                    pen.line(hwp(0.12, 0.0), hwp(0.12, 0.66), c.scaled(fade), width: 0.05)
                    let flag = HeadwearShape.smooth([hwp(0.12, 0.66), hwp(0.34, 0.48), hwp(0.3, 0.24), hwp(0.36, 0.36), hwp(0.14, 0.5)], smoothness: 0.6)
                    pen.paint(flag, [c.scaled(fade)], ink: ink, inkWidth: 0.03)
                    let head = HeadwearShape.ellipse(hwp(0.0, -0.02), rx: 0.17, ry: 0.12, turn: 0.4)
                    pen.paint(head, [c.lighter(0.3).scaled(fade), c.scaled(fade)], ink: ink, inkWidth: 0.04)
                }
            }
        }
    }
}

// MARK: - Astronaut

/// A glass space helmet with a white neck ring. The light on the glass stays put as you tilt; open your mouth and your breath
/// fogs the visor.
final class HeadwearAstronaut: HeadwearCostume {
    let hint = "Open your mouth to fog up the glass"

    private var fogging = HeadwearFollower()

    /// How fogged the glass is in front of the mouth, 0...1.
    var fog: Double { fogging.value }

    func reset() { fogging = HeadwearFollower() }

    func advance(_ f: HeadwearFrame) {
        fogging.follow(f.signals.mouthIsOpen ? 1 : 0, dt: f.dt, rise: 2.5, fall: 0.7)
    }

    /// The bubble's centre and radius in face units.
    static func bubble(_ f: HeadwearFrame) -> (centre: CGPoint, radius: Double) {
        let top = f.head.crown + 0.2, bottom = f.chinY
        return (hwp(0, (top + bottom) / 2), max(f.head.side(1.25) + 0.45, (top - bottom) / 2 + 0.42))
    }

    /// The glass, for a bubble of radius 1 at the origin, lit from the top left.
    private static func paintGlass(_ pen: HeadwearPen) {
        let disc = HeadwearShape.ellipse(.zero, rx: 1, ry: 1)
        pen.fill(disc, HeadwearColor(0.85, 0.93, 1, 0.06))
        pen.paintRound(disc, center: hwp(-0.05, 0.05), radius: 1.0, [HeadwearColor(0.8, 0.9, 1, 0), HeadwearColor(0.8, 0.9, 1, 0), HeadwearColor(0.85, 0.94, 1, 0.42)])
        // A big curved window reflection, top left, and a smaller one bottom right.
        let band = CGMutablePath()
        band.addArc(center: .zero, radius: 0.9, startAngle: .pi * 0.58, endAngle: .pi * 0.98, clockwise: false)
        band.addArc(center: hwp(0.08, -0.06), radius: 0.8, startAngle: .pi * 0.98, endAngle: .pi * 0.58, clockwise: true)
        band.closeSubpath()
        pen.paint(band, [HeadwearColor(1, 1, 1, 0.55), HeadwearColor(1, 1, 1, 0.12)], direction: CGVector(dx: 0.7, dy: -1))
        let small = CGMutablePath()
        small.addArc(center: .zero, radius: 0.92, startAngle: -.pi * 0.42, endAngle: -.pi * 0.2, clockwise: false)
        small.addArc(center: hwp(-0.04, 0.03), radius: 0.86, startAngle: -.pi * 0.2, endAngle: -.pi * 0.42, clockwise: true)
        small.closeSubpath()
        pen.fill(small, HeadwearColor(1, 1, 1, 0.22))
        pen.fill(HeadwearShape.ellipse(hwp(-0.42, 0.6), rx: 0.07, ry: 0.045, turn: 0.6), HeadwearColor(1, 1, 1, 0.75))
        pen.fill(HeadwearShape.ellipse(hwp(-0.3, 0.7), rx: 0.03, ry: 0.02, turn: 0.6), HeadwearColor(1, 1, 1, 0.6))
        pen.stroke(disc, HeadwearColor(hex: 0x2A3346, alpha: 0.45), width: 0.03)
        pen.stroke(HeadwearShape.ellipse(.zero, rx: 0.985, ry: 0.985), HeadwearColor(1, 1, 1, 0.55), width: 0.012)
    }

    /// The front half of the neck ring, for a bubble of radius 1: the middle of its top edge is at the origin. The back half is
    /// behind the neck, so only a faint line of it shows.
    private static func paintRing(_ pen: HeadwearPen) {
        func arc(_ dy: Double, from a0: Double, to a1: Double) -> [CGPoint] {
            (0...24).map { k in let a = a0 + (a1 - a0) * Double(k) / 24; return hwp(cos(a) * 0.86, dy + sin(a) * 0.2) }
        }
        let suit = [HeadwearColor(hex: 0xFFFFFF), HeadwearColor(hex: 0xE4E8F0), HeadwearColor(hex: 0xA9B3C6)]
        pen.stroke(HeadwearShape.smooth(arc(0, from: 0, to: .pi), closed: false), HeadwearColor(hex: 0xC9D0DE, alpha: 0.55), width: 0.035)
        let band = HeadwearShape.polygon(arc(0, from: .pi, to: 2 * .pi) + arc(-0.2, from: 2 * .pi, to: .pi))
        pen.paint(band, suit, ink: HeadwearPalette.steelInk, inkWidth: 0.025, direction: CGVector(dx: 0.5, dy: -1))
        pen.clipped(to: band) {
            pen.stroke(HeadwearShape.smooth(arc(-0.1, from: .pi, to: 2 * .pi), closed: false), HeadwearColor(hex: 0xFF8A3D), width: 0.05)
            pen.stroke(HeadwearShape.smooth(arc(-0.02, from: .pi * 1.05, to: .pi * 1.4), closed: false), HeadwearColor(1, 1, 1, 0.9), width: 0.025)
        }
        pen.stroke(HeadwearShape.smooth(arc(0, from: .pi, to: 2 * .pi), closed: false), HeadwearColor(hex: 0x5A6478), width: 0.03)
        for k in 0..<5 {
            let a = .pi * (1.15 + 0.175 * Double(k))
            let p = hwp(cos(a) * 0.86, -0.17 + sin(a) * 0.2)
            pen.paintRound(HeadwearShape.ellipse(p, rx: 0.022, ry: 0.018), center: hwp(p.x - 0.006, p.y + 0.006), radius: 0.03, [HeadwearColor.white, HeadwearPalette.steelDeep], ink: nil)
        }
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let (c, r) = Self.bubble(f)
        let appear = HeadwearEase.pop(f.seen, delay: 0.05, duration: 0.6)
        guard appear > 0.001 else { return }
        let ringY = c.y - r * 0.88
        f.inFace(pen.ctx) {
            pen.placed(at: c, scale: r * appear) {
                // The glass stops where it meets the ring. Its reflections stay where the light is, not turning with the head.
                let cut = CGMutablePath()
                cut.addRect(CGRect(x: -1.2, y: -0.86, width: 2.4, height: 2.1))
                pen.clipped(to: cut) {
                    pen.placed(at: .zero, turn: -f.roll) {
                        pen.sprite("astronaut-glass", window: CGRect(x: -1.02, y: -1.02, width: 2.04, height: 2.04), pixelsPerUnit: f.io * r) { Self.paintGlass($0) }
                    }
                }
                if let g = HeadwearGlint.phase(f.clock, period: 6, offset: 2, length: 1.1) {
                    pen.placed(at: .zero, turn: -f.roll) {
                        let rim = HeadwearShape.ellipse(.zero, rx: 0.98, ry: 0.98)
                        let inner = HeadwearShape.ellipse(.zero, rx: 0.9, ry: 0.9, hole: true)
                        let edge = CGMutablePath(); edge.addPath(rim); edge.addPath(inner)
                        HeadwearGlint.sweep(pen, over: edge, box: CGRect(x: -1, y: -1, width: 2, height: 2), phase: g, strength: 0.5)
                    }
                }
            }
            drawFog(pen, f)
            pen.placed(at: hwp(0, ringY), scale: r * appear) {
                pen.sprite("astronaut-ring", window: CGRect(x: -0.92, y: -0.46, width: 1.84, height: 0.7), pixelsPerUnit: f.io * r) { Self.paintRing($0) }
            }
        }
    }

    private func drawFog(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fog = fogging.value
        guard fog > 0.01 else { return }
        let m = hwp(f.mouth.x, f.mouth.y - 0.05)
        pen.glow(at: m, radius: 0.35 + 0.5 * fog, HeadwearColor(0.94, 0.97, 1, 0.55 * fog))
        pen.glow(at: hwp(m.x + 0.2, m.y + 0.1), radius: 0.3 + 0.3 * fog, HeadwearColor(0.94, 0.97, 1, 0.3 * fog))
        for k in 0..<10 {
            let a = HeadwearNoise.unit(k, 51) * 2 * .pi, d = sqrt(HeadwearNoise.unit(k, 52)) * 0.55 * fog
            pen.dot(at: hwp(m.x + cos(a) * d, m.y + sin(a) * d * 0.8), radius: 0.012 + 0.012 * HeadwearNoise.unit(k, 53), HeadwearColor(1, 1, 1, 0.6 * fog))
        }
    }
}

// MARK: - Robot

/// Robot gear: a riveted metal cap with an antenna, bolts at the ears and a light strip across the forehead. The strip scans
/// back and forth; talk and it turns into a voice meter.
final class HeadwearRobot: HeadwearCostume {
    let hint = "Talk and the lights follow your voice"

    private var antenna = HeadwearSwing(omega: 8, damping: 0.1, gain: 0.05, limit: 0.7)
    private var voice = HeadwearFollower()
    private var levels = [Double](repeating: 0, count: 9)

    /// How much the meter shows a voice, 0...1.
    var talking: Double { voice.value }

    func reset() { antenna.reset(); voice = HeadwearFollower(); levels = [Double](repeating: 0, count: 9) }

    func advance(_ f: HeadwearFrame) {
        antenna.step(dt: f.dt, accel: f.accel.x * 1.3, rest: f.hang * 0.3)
        voice.follow(f.signals.mouthIsOpen ? 1 : 0, dt: f.dt, rise: 10, fall: 3)
        // Each bar of the meter chases its own wobbling share of how open the mouth is.
        for i in levels.indices {
            let wobble = 0.55 + 0.45 * sin(f.clock * (9 + Double(i) * 1.7) + Double(i) * 2.1)
            let shape = 1 - pow((Double(i) - 4) / 5, 2) * 0.6
            let target = voice.value * min(1, f.face.mouthOpen * 1.3 + 0.2) * wobble * shape
            levels[i] += (target - levels[i]) * (1 - exp(-f.dt * (target > levels[i] ? 30 : 10)))
        }
    }

    private static let metal = [HeadwearColor(hex: 0xF0F4FA), HeadwearColor(hex: 0xB4BFD2), HeadwearColor(hex: 0x6E7B96)]
    private static let ink = HeadwearColor(hex: 0x252B3A)
    private static let cyan = HeadwearColor(hex: 0x4DF0FF)

    private static func paintCap(_ pen: HeadwearPen) {
        let dome = CGMutablePath()
        dome.addArc(center: .zero, radius: 1, startAngle: 0, endAngle: .pi, clockwise: false, transform: CGAffineTransform(scaleX: 1.12, y: 0.74))
        dome.closeSubpath()
        pen.paint(dome, metal, ink: ink, inkWidth: 0.05, direction: CGVector(dx: 0.6, dy: -1))
        pen.clipped(to: dome) {
            pen.paintRound(dome, center: hwp(-0.45, 0.62), radius: 1.5, [HeadwearColor(1, 1, 1, 0.55), HeadwearColor(1, 1, 1, 0), HeadwearColor(0.1, 0.12, 0.25, 0.3)])
            // Panel seams and rivets.
            for x in [-0.55, 0.55] {
                pen.stroke(HeadwearShape.smooth([hwp(x, 0), hwp(x * 0.92, 0.5), hwp(x * 0.6, 0.78)], closed: false), ink.faded(0.5), width: 0.025)
                for k in 0..<3 { pen.dot(at: hwp(x * (1 - 0.1 * Double(k)) + (x < 0 ? 0.08 : -0.08), 0.14 + 0.2 * Double(k)), radius: 0.028, HeadwearColor(hex: 0x8A96AE)) }
            }
            pen.stroke(HeadwearShape.smooth([hwp(-0.9, 0.3), hwp(-0.65, 0.6), hwp(-0.3, 0.76)], closed: false), HeadwearColor(1, 1, 1, 0.8), width: 0.045)
        }
        // The rim, with the dark glass strip the lights sit behind.
        let rim = HeadwearShape.rounded(CGRect(x: -1.14, y: -0.12, width: 2.28, height: 0.2), radius: 0.08)
        pen.paint(rim, [HeadwearColor(hex: 0x9AA6BC), HeadwearColor(hex: 0x5C6880)], ink: ink, inkWidth: 0.035)
        let strip = HeadwearShape.rounded(CGRect(x: -0.78, y: -0.38, width: 1.56, height: 0.26), radius: 0.11)
        pen.paint(strip, [HeadwearColor(hex: 0x2A3346), HeadwearColor(hex: 0x0E1220)], ink: ink, inkWidth: 0.04)
        pen.stroke(HeadwearShape.smooth([hwp(-0.66, -0.17), hwp(0.6, -0.17)], closed: false), HeadwearColor(1, 1, 1, 0.18), width: 0.025)
    }

    private static func paintBolt(_ pen: HeadwearPen) {
        let disc = HeadwearShape.ellipse(.zero, rx: 0.26, ry: 0.3)
        pen.paintRound(disc, center: hwp(-0.08, 0.1), radius: 0.4, metal, ink: ink, inkWidth: 0.04)
        for r in [0.2, 0.14] { pen.stroke(HeadwearShape.ellipse(.zero, rx: r * 0.87, ry: r), ink.faded(0.35), width: 0.02) }
        pen.paintRound(HeadwearShape.ellipse(.zero, rx: 0.08, ry: 0.09), center: hwp(-0.02, 0.03), radius: 0.1, [HeadwearColor.white, HeadwearPalette.steelDeep], ink: ink, inkWidth: 0.02)
        pen.line(hwp(-0.05, -0.05), hwp(0.05, 0.05), ink.faded(0.7), width: 0.02)
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 2.6, duration: 0.75)
        f.inFace(pen.ctx) {
            for (i, side) in [-1.0, 1.0].enumerated() {
                let pop = HeadwearEase.pop(f.seen, delay: 0.35 + 0.08 * Double(i), duration: 0.4)
                guard pop > 0.001 else { continue }
                pen.placed(at: hwp(f.head.side(side * 1.14), -0.2), stretch: CGSize(width: side * pop, height: pop)) {
                    pen.sprite("robot-bolt", window: CGRect(x: -0.32, y: -0.36, width: 0.64, height: 0.72), pixelsPerUnit: f.io) { Self.paintBolt($0) }
                    let ring = HeadwearShape.ellipse(.zero, rx: 0.2 * 0.87, ry: 0.2)
                    let lit = 0.25 + 0.75 * voice.value
                    pen.glow(at: .zero, radius: 0.4, Self.cyan.faded(0.3 * lit), additive: true)
                    pen.stroke(ring, Self.cyan.faded(0.5 + 0.5 * lit), width: 0.025)
                }
            }
            pen.placed(at: hwp(0, f.head.up(0.9) + fall), scale: f.head.wide) {
                let landed = HeadwearEase.smoothstep(1 - fall / 0.6)
                pen.shadow(at: hwp(0, -0.36), rx: 1.0, ry: 0.15, alpha: 0.35 * landed)
                drawAntenna(pen, f)
                pen.sprite("robot-cap", window: CGRect(x: -1.2, y: -0.46, width: 2.4, height: 1.36), pixelsPerUnit: f.io * f.head.wide) { Self.paintCap($0) }
                drawLights(pen, f)
            }
        }
    }

    private func drawAntenna(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let a = antenna.x
        let base = hwp(0.3, 0.66)
        let tip = hwp(base.x + sin(a) * 0.62 + 0.08, base.y + cos(a) * 0.62)
        let rod = CGMutablePath()
        rod.move(to: base)
        rod.addQuadCurve(to: tip, control: hwp(base.x + 0.05 + sin(a) * 0.2, base.y + 0.35))
        pen.stroke(rod, Self.ink, width: 0.06)
        pen.stroke(rod, HeadwearPalette.steel, width: 0.035)
        let blink = (f.clock * 0.7).truncatingRemainder(dividingBy: 1) < 0.12 ? 1.0 : 0.0
        let on = max(blink, voice.value)
        let red = HeadwearColor(hex: 0xFF4D5E)
        pen.glow(at: tip, radius: 0.18 + 0.25 * on, red.faded(0.25 + 0.5 * on), additive: true)
        pen.paintRound(HeadwearShape.ellipse(tip, rx: 0.09, ry: 0.09), center: hwp(tip.x - 0.03, tip.y + 0.03), radius: 0.12,
                       [HeadwearColor(hex: 0xFFB0B8).mixed(with: .white, on * 0.4), red, red.darker(0.4)], ink: Self.ink, inkWidth: 0.02)
        pen.paint(HeadwearShape.rounded(CGRect(x: base.x - 0.09, y: base.y - 0.05, width: 0.18, height: 0.1), radius: 0.03), [HeadwearPalette.steelLight, HeadwearPalette.steelDeep],
                  ink: Self.ink, inkWidth: 0.02)
    }

    /// The light strip: a dot sweeping to and fro while quiet, bars that bounce with your voice while you talk.
    private func drawLights(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let appear = HeadwearEase.smoothstep((f.seen - 0.5) / 0.3)
        guard appear > 0.01 else { return }
        let y0 = -0.25
        let talk = voice.value
        pen.ctx.saveGState()
        pen.ctx.setBlendMode(.plusLighter)
        if talk < 0.99 {
            let sweep = sin(f.clock * 2.4)
            for k in 0..<5 {
                let x = sweep * 0.62 - Double(k) * 0.07 * (cos(f.clock * 2.4) >= 0 ? 1 : -1)
                let a = (1 - talk) * appear * (1 - Double(k) * 0.2)
                pen.glow(at: hwp(x, y0), radius: 0.14, HeadwearColor(hex: 0xFF4D5E, alpha: 0.55 * a))
                pen.fill(HeadwearShape.rounded(CGRect(x: x - 0.035, y: y0 - 0.05, width: 0.07, height: 0.1), radius: 0.02), HeadwearColor(1, 0.45, 0.5, 0.9 * a))
            }
        }
        if talk > 0.01 {
            for (i, level) in levels.enumerated() {
                let x = -0.64 + Double(i) * 0.16
                let h = 0.03 + 0.17 * min(1, level)
                pen.fill(HeadwearShape.rounded(CGRect(x: x - 0.045, y: y0 - h / 2, width: 0.09, height: h), radius: 0.02), Self.cyan.faded(0.9 * talk * appear))
                pen.glow(at: hwp(x, y0), radius: 0.12 + 0.1 * level, Self.cyan.faded(0.35 * talk * appear))
            }
        }
        pen.ctx.restoreGState()
    }
}

// MARK: - Mermaid

/// A mermaid's tiara of shells, pearls and sea glass, with a few gems at the eyes. Smile and bubbles float up.
final class HeadwearMermaid: HeadwearCostume {
    let hint = "Smile and bubbles float up"

    private var bubbles = HeadwearFloaters(capacity: 40)
    private var bubbling = HeadwearFollower()
    private var owed = 0.0
    private var sway = HeadwearSwing(omega: 7, damping: 0.18, gain: 0.03, limit: 0.3)

    var bubbleCount: Int { bubbles.bits.count }

    init() { bubbles.lift = 260; bubbles.drag = 1.6 }

    func reset() { bubbles.removeAll(); bubbling = HeadwearFollower(); owed = 0; sway.reset() }

    func advance(_ f: HeadwearFrame) {
        sway.step(dt: f.dt, accel: f.accel.x, rest: 0)
        bubbling.follow(f.signals.isSmiling ? 1 : 0, dt: f.dt, rise: 6, fall: 3)
        owed += f.dt * 9 * bubbling.value
        while owed >= 1 {
            owed -= 1
            let side = bubbles.random(1) < 0.5 ? -1.0 : 1.0
            let from = f.toScreen(hwp(f.head.side(side * (1.0 + 0.5 * bubbles.random(2))), -0.4 + 1.4 * bubbles.random(3)))
            bubbles.emit(at: from, velocity: SIMD2(side * 0.3 * bubbles.random(4), 0.6 + 0.4 * bubbles.random(5)), io: f.io,
                         life: 1.4 + 1.0 * bubbles.random(6), size: 0.05 + 0.1 * pow(bubbles.random(7), 2))
        }
        bubbles.step(dt: f.dt, io: f.io)
    }

    private static let shellLight = HeadwearColor(hex: 0xFFE6DA), shellMid = HeadwearColor(hex: 0xFFB3A0), shellDeep = HeadwearColor(hex: 0xE07A74)
    private static let shellInk = HeadwearColor(hex: 0x8A3A42)

    /// A scallop shell standing on its hinge at the origin, `r` tall.
    private static func scallop(_ pen: HeadwearPen, r: Double) {
        var pts: [CGPoint] = [hwp(-0.16 * r, 0.02 * r)]
        let ribs = 7
        for k in 0...ribs {
            let a = .pi * (0.92 - 0.84 * Double(k) / Double(ribs))
            pts.append(hwp(cos(a) * r * 0.78, 0.18 * r + sin(a) * r * 0.82))
            if k < ribs {
                let m = .pi * (0.92 - 0.84 * (Double(k) + 0.5) / Double(ribs))
                pts.append(hwp(cos(m) * r * 0.86, 0.18 * r + sin(m) * r * 0.9))
            }
        }
        pts.append(hwp(0.16 * r, 0.02 * r))
        let shell = HeadwearShape.smooth(pts, smoothness: 0.7)
        pen.paint(shell, [shellLight, shellMid, shellDeep], ink: shellInk, inkWidth: 0.035, direction: CGVector(dx: 0.3, dy: -1))
        pen.clipped(to: shell) {
            for k in 0..<ribs {
                let a = .pi * (0.92 - 0.84 * (Double(k) + 0.5) / Double(ribs))
                pen.line(hwp(0, 0.05 * r), hwp(cos(a) * r * 0.9, 0.18 * r + sin(a) * r * 0.95), shellInk.faded(0.35), width: 0.02)
                let b = .pi * (0.92 - 0.84 * (Double(k) + 0.3) / Double(ribs))
                pen.line(hwp(0, 0.05 * r), hwp(cos(b) * r * 0.9, 0.18 * r + sin(b) * r * 0.95), HeadwearColor(1, 1, 1, 0.35), width: 0.015)
            }
        }
        let hinge = HeadwearShape.smooth([hwp(-0.2 * r, 0.06 * r), hwp(-0.22 * r, -0.05 * r), hwp(0, -0.08 * r), hwp(0.22 * r, -0.05 * r), hwp(0.2 * r, 0.06 * r), hwp(0, 0.12 * r)])
        pen.paint(hinge, [shellMid, shellDeep], ink: shellInk, inkWidth: 0.025)
    }

    private static func pearl(_ pen: HeadwearPen, at p: CGPoint, r: Double) {
        pen.paintRound(HeadwearShape.ellipse(p, rx: r, ry: r), center: hwp(p.x - r * 0.35, p.y + r * 0.35), radius: r * 1.4,
                       [HeadwearColor.white, HeadwearColor(hex: 0xF2E8F4), HeadwearColor(hex: 0xC4B4D6)], ink: HeadwearColor(hex: 0x8C7AA8, alpha: 0.8), inkWidth: 0.012)
    }

    private static func starfish(_ pen: HeadwearPen, r: Double) {
        let star = HeadwearShape.smooth((0..<10).map { i -> CGPoint in
            let a = .pi / 2 + Double(i) * .pi / 5, d = i % 2 == 0 ? r : r * 0.45
            return hwp(cos(a) * d, sin(a) * d)
        }, smoothness: 0.45)
        pen.paintRound(star, center: hwp(-r * 0.2, r * 0.2), radius: r * 1.2, [HeadwearColor(hex: 0xFFC27A), HeadwearColor(hex: 0xF58A3C), HeadwearColor(hex: 0xC85A1E)],
                       ink: HeadwearColor(hex: 0x7A3010), inkWidth: 0.03)
        for i in 0..<5 {
            let a = .pi / 2 + Double(i) * 2 * .pi / 5
            for k in 1...3 { pen.dot(at: hwp(cos(a) * r * 0.22 * Double(k), sin(a) * r * 0.22 * Double(k)), radius: 0.016, HeadwearColor(hex: 0xFFE2B8)) }
        }
    }

    /// The tiara, centred on the middle of the forehead at the origin.
    private static func paintTiara(_ pen: HeadwearPen) {
        // Kelp behind it all.
        for (x, lean, length) in [(-0.5, 0.35, 0.8), (0.42, -0.3, 0.7), (-0.15, 0.1, 0.62), (0.75, -0.55, 0.55)] as [(Double, Double, Double)] {
            let spine = HeadwearShape.spine(from: hwp(x, 0.0), length: length, steps: 10) { t in .pi / 2 + lean + 0.5 * sin(t * 5) * t }
            let frond = HeadwearShape.ribbon(spine, tip: 0.6) { t in 0.08 * sin(min(1, t * 1.2 + 0.1) * .pi) + 0.01 }
            pen.paint(frond, [HeadwearColor(hex: 0x8FE3B0), HeadwearColor(hex: 0x2FA46E)], ink: HeadwearColor(hex: 0x15603C), inkWidth: 0.025)
        }
        // A string of pearls round the head.
        let arc: [CGPoint] = (0...16).map { k in
            let a = .pi * (1.08 - 1.16 * Double(k) / 16)
            return hwp(cos(a) * 1.08, -0.62 + sin(a) * 0.68)
        }
        for (k, p) in arc.enumerated() {
            pearl(pen, at: p, r: 0.055 + 0.012 * (k % 2 == 0 ? 1 : 0))
        }
        // Sea glass drops between the shells.
        for x in [-0.32, 0.32] {
            let drop = HeadwearShape.smooth([hwp(x, 0.02), hwp(x + 0.07, -0.12), hwp(x, -0.2), hwp(x - 0.07, -0.12)], smoothness: 0.8)
            pen.paintRound(drop, center: hwp(x - 0.02, -0.08), radius: 0.15, [HeadwearColor(hex: 0xD8FFF6), HeadwearColor(hex: 0x5ED6C8), HeadwearColor(hex: 0x1E8A8E)],
                           ink: HeadwearColor(hex: 0x0E5458), inkWidth: 0.02)
            pen.fill(HeadwearShape.ellipse(hwp(x - 0.02, -0.07), rx: 0.018, ry: 0.035), HeadwearColor(1, 1, 1, 0.8))
        }
        pen.placed(at: hwp(-0.62, -0.06), turn: 0.45) { scallop(pen, r: 0.36) }
        pen.placed(at: hwp(0.62, -0.06), turn: -0.45) { scallop(pen, r: 0.36) }
        pen.placed(at: hwp(-0.98, -0.36), turn: 0.3) { starfish(pen, r: 0.2) }
        pen.placed(at: hwp(0, -0.02)) { scallop(pen, r: 0.56) }
        pearl(pen, at: hwp(0, 0.04), r: 0.075)
        pearl(pen, at: hwp(0.9, -0.3), r: 0.07)
        pearl(pen, at: hwp(0.98, -0.42), r: 0.05)
    }

    private static let window = CGRect(x: -1.25, y: -0.75, width: 2.5, height: 1.65)

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 2.2, duration: 0.7)
        f.inFace(pen.ctx) {
            drawGems(pen, f)
            pen.placed(at: hwp(0, f.head.up(1.08) + fall), turn: sway.x * 0.4, scale: f.head.wide * 1.12) {
                pen.sprite("mermaid-tiara", window: Self.window, pixelsPerUnit: f.io * f.head.wide * 1.12) { Self.paintTiara($0) }
                if let g = HeadwearGlint.phase(f.clock, period: 4.4, offset: 1.3) {
                    let s = sin(g * .pi)
                    pen.sparkle(at: hwp(-0.12, 0.38), radius: 0.16 * s, HeadwearColor(1, 1, 0.95, 0.9), turn: g, additive: true)
                }
            }
        }
        drawBubbles(pen, f)
    }

    /// A few gems along each cheekbone, catching the light in turn.
    private func drawGems(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let a = HeadwearEase.smoothstep((f.seen - 0.5) / 0.4)
        guard a > 0.01 else { return }
        let colours = [HeadwearColor(hex: 0x7DE8E0), HeadwearColor(hex: 0xC6B4FF), HeadwearColor(hex: 0xFFFFFF)]
        for side in [-1.0, 1.0] {
            for (k, (x, y, r)) in [(0.86, -0.08, 0.04), (0.92, -0.22, 0.032), (0.84, -0.33, 0.026), (0.98, -0.06, 0.024)].enumerated() {
                let c = colours[k % colours.count]
                let p = hwp(side * x, y)
                pen.paintRound(HeadwearShape.ellipse(p, rx: r, ry: r), center: hwp(p.x - r * 0.3, p.y + r * 0.3), radius: r * 1.3, [HeadwearColor.white.scaled(a), c.scaled(a), c.darker(0.3).scaled(a)],
                               ink: c.darker(0.55).scaled(0.6 * a), inkWidth: 0.008)
                let twinkle = pow(max(0, sin(f.clock * 2.2 + Double(k) * 1.9 + side)), 12)
                if twinkle > 0.05 { pen.sparkle(at: hwp(p.x - r * 0.3, p.y + r * 0.3), radius: 0.08 * twinkle * a, HeadwearColor(1, 1, 1, 0.9), additive: true) }
            }
        }
    }

    private func drawBubbles(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        for b in bubbles.bits {
            let t = b.age / b.life
            let fade = min(1, t / 0.1) * min(1, (1 - t) / 0.15)
            let r = b.size * f.io * (1 + 0.15 * t)
            let wobble = sin(b.age * 5 + Double(b.seed)) * r * 0.4
            let p = CGPoint(x: b.position.x + wobble, y: b.position.y)
            let disc = HeadwearShape.ellipse(p, rx: r, ry: r * (1 + 0.05 * sin(b.age * 9)))
            pen.paintRound(disc, center: p, radius: r, [HeadwearColor(0.7, 0.95, 1, 0.04 * fade), HeadwearColor(0.7, 0.95, 1, 0.12 * fade), HeadwearColor(0.85, 1, 1, 0.5 * fade)])
            pen.stroke(disc, HeadwearColor(1, 1, 1, 0.55 * fade), width: max(0.8, r * 0.07))
            pen.fill(HeadwearShape.ellipse(CGPoint(x: p.x - r * 0.38, y: p.y + r * 0.38), rx: r * 0.22, ry: r * 0.14, turn: 0.7), HeadwearColor(1, 1, 1, 0.8 * fade))
        }
    }
}
