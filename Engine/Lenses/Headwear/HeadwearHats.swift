import CoreGraphics
import Foundation

// Hats: cowboy, propeller cap, chef, witch and viking.

// MARK: - Cowboy

/// A felt cowboy hat with a stitched band and a silver concho, and a red bandana at the neck. Raise your brows to tip the hat.
final class HeadwearCowboy: HeadwearCostume {
    let hint = "Raise your brows to tip your hat"

    private var tip = HeadwearSwing(omega: 10, damping: 0.3, gain: 0, limit: 1.3)
    private var sway = HeadwearSwing(omega: 8, damping: 0.18, gain: 0.025, limit: 0.25)
    private var scarf = HeadwearSwing(omega: 6, damping: 0.2, gain: 0.05, limit: 0.5)

    /// How far the hat is tipped, 0 on the head to 1 raised.
    var tipped: Double { tip.x }

    func reset() { tip.reset(); sway.reset(); scarf.reset() }

    func advance(_ f: HeadwearFrame) {
        tip.step(dt: f.dt, accel: 0, rest: f.signals.browsAreUp ? 1 : 0)
        sway.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.05)
        scarf.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.5)
    }

    private static let felt = [HeadwearColor(hex: 0xE2AD72), HeadwearColor(hex: 0xB9793C), HeadwearColor(hex: 0x7E4A21)]
    private static let ink = HeadwearColor(hex: 0x3E2410)

    private static let crown = HeadwearShape.smooth([hwp(-0.72, 0.04), hwp(-0.7, 0.62), hwp(-0.6, 1.08), hwp(-0.32, 1.24), hwp(0, 1.12),
                                                     hwp(0.32, 1.24), hwp(0.6, 1.08), hwp(0.7, 0.62), hwp(0.72, 0.04), hwp(0, -0.04)], smoothness: 0.9)
    private static let brim: CGPath = {
        let p = CGMutablePath()
        p.move(to: hwp(-1.78, 0.42))
        p.addCurve(to: hwp(0, -0.16), control1: hwp(-1.62, 0.02), control2: hwp(-0.9, -0.16))
        p.addCurve(to: hwp(1.78, 0.42), control1: hwp(0.9, -0.16), control2: hwp(1.62, 0.02))
        p.addCurve(to: hwp(0, 0.08), control1: hwp(1.5, 0.2), control2: hwp(0.85, 0.08))
        p.addCurve(to: hwp(-1.78, 0.42), control1: hwp(-0.85, 0.08), control2: hwp(-1.5, 0.2))
        p.closeSubpath()
        return p
    }()

    private static func paintHat(_ pen: HeadwearPen) {
        // The crown, its front pinch, and the band.
        pen.paint(crown, felt, ink: ink, inkWidth: 0.05, direction: CGVector(dx: 0.5, dy: -1))
        pen.clipped(to: crown) {
            for side in [-1.0, 1.0] {
                let dent = HeadwearShape.smooth([hwp(side * 0.12, 1.1), hwp(side * 0.3, 0.8), hwp(side * 0.26, 0.4), hwp(side * 0.1, 0.5), hwp(side * 0.06, 0.9)])
                pen.fill(dent, HeadwearColor(hex: 0x5A3214, alpha: side < 0 ? 0.18 : 0.32))
            }
            pen.stroke(HeadwearShape.smooth([hwp(-0.56, 0.3), hwp(-0.55, 0.8), hwp(-0.42, 1.1)], closed: false), HeadwearColor(1, 0.95, 0.85, 0.35), width: 0.06)
            pen.stroke(HeadwearShape.smooth([hwp(-0.3, 1.2), hwp(-0.12, 1.12), hwp(0, 1.1)], closed: false), HeadwearColor(hex: 0x5A3214, alpha: 0.5), width: 0.03)
        }
        let band = HeadwearShape.smooth([hwp(-0.72, 0.06), hwp(0, 0.0), hwp(0.72, 0.06), hwp(0.71, 0.3), hwp(0, 0.25), hwp(-0.71, 0.3)], smoothness: 0.5)
        pen.paint(band, [HeadwearColor(hex: 0x5C3820), HeadwearColor(hex: 0x2E190C)], ink: HeadwearColor(hex: 0x1E0F06), inkWidth: 0.03)
        pen.ctx.saveGState()
        pen.ctx.setLineDash(phase: 0, lengths: [0.05, 0.04])
        for y in [0.08, 0.22] {
            pen.stroke(HeadwearShape.smooth([hwp(-0.68, y + 0.04), hwp(0, y - 0.01), hwp(0.68, y + 0.04)], closed: false), HeadwearColor(hex: 0xF0D9B0, alpha: 0.8), width: 0.016, cap: .butt)
        }
        pen.ctx.restoreGState()
        // The concho: a silver disc with a star.
        let concho = HeadwearShape.ellipse(hwp(0.42, 0.15), rx: 0.12, ry: 0.11)
        pen.paintRound(concho, center: hwp(0.38, 0.19), radius: 0.16, [HeadwearPalette.steelLight, HeadwearPalette.steel, HeadwearPalette.steelDeep],
                       ink: HeadwearPalette.steelInk, inkWidth: 0.02)
        pen.fill(HeadwearShape.star(hwp(0.42, 0.15), points: 5, outer: 0.075, inner: 0.032), HeadwearPalette.steelDeep)
        pen.fill(HeadwearShape.star(hwp(0.415, 0.155), points: 5, outer: 0.06, inner: 0.025), HeadwearPalette.steelLight)
        // The brim, curling up at the sides, lit along its top edge.
        pen.paint(brim, [HeadwearColor(hex: 0xD49A5E), HeadwearColor(hex: 0x9E6230), HeadwearColor(hex: 0x6A3C18)], ink: ink, inkWidth: 0.05,
                  direction: CGVector(dx: 0.2, dy: -1))
        pen.clipped(to: brim) {
            pen.stroke(HeadwearShape.smooth([hwp(-1.7, 0.42), hwp(-0.9, 0.1), hwp(0, 0.06), hwp(0.9, 0.1), hwp(1.7, 0.42)], closed: false),
                       HeadwearColor(1, 0.93, 0.8, 0.45), width: 0.06)
            pen.stroke(HeadwearShape.smooth([hwp(-1.5, 0.1), hwp(-0.8, -0.1), hwp(0, -0.14), hwp(0.8, -0.1), hwp(1.5, 0.1)], closed: false),
                       HeadwearColor(hex: 0x4A2810, alpha: 0.4), width: 0.05)
        }
    }

    private static let window = CGRect(x: -1.9, y: -0.3, width: 3.8, height: 1.65)

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            drawBandana(pen, f)
            let fall = HeadwearEase.drop(f.seen, height: 2.8, duration: 0.8)
            let t = tip.x
            pen.placed(at: hwp(0, f.head.up(0.98) + fall), turn: sway.x, scale: f.head.wide) {
                let landed = HeadwearEase.smoothstep(1 - fall / 0.6)
                pen.shadow(at: hwp(0, -0.14), rx: 1.15, ry: 0.22, alpha: 0.42 * landed * (1 - 0.6 * min(1, t)))
                // Tipped: lifted off the head and turned back about the left of the brim.
                pen.placed(at: hwp(-1.2 * t * 0.25, 0.34 * t), turn: -0.2 * t) {
                    pen.sprite("cowboy-hat", window: Self.window, pixelsPerUnit: f.io * f.head.wide) { Self.paintHat($0) }
                }
            }
        }
    }

    /// A red neckerchief knotted round the neck, its point hanging down the front.
    private func drawBandana(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.45, duration: 0.45)
        guard grow > 0.01 else { return }
        let swing = scarf.x
        let red = [HeadwearColor(hex: 0xE5505A), HeadwearColor(hex: 0xC02E3C), HeadwearColor(hex: 0x8A1826)]
        let ink = HeadwearColor(hex: 0x4E0A12)
        pen.placed(at: hwp(f.mouth.x * 0.5, f.chinY - 0.12), scale: grow * f.head.wide) {
            // The point hanging down the front, then the rolled band round the neck over it.
            let tip = hwp(0.08 + swing * 0.3, -0.98)
            let point = HeadwearShape.smooth([hwp(-0.62, -0.08), hwp(-0.3, -0.5), tip, hwp(0.42, -0.46), hwp(0.66, -0.08), hwp(0, -0.16)], smoothness: 0.55)
            pen.paint(point, red, ink: ink, inkWidth: 0.04, direction: CGVector(dx: 0.35, dy: -1))
            pen.clipped(to: point) {
                for k in 0..<22 {
                    let x = -0.6 + 1.25 * HeadwearNoise.unit(k, 31), y = -0.12 - 0.85 * HeadwearNoise.unit(k, 32)
                    let p = hwp(x + swing * 0.3 * (-y), y)
                    pen.dot(at: p, radius: 0.028, HeadwearColor(hex: 0xFFF1E0, alpha: 0.85))
                    for j in 0..<3 {
                        let a = Double(j) * 2.1 + Double(k)
                        pen.dot(at: hwp(p.x + cos(a) * 0.06, p.y + sin(a) * 0.06), radius: 0.011, HeadwearColor(hex: 0xFFF1E0, alpha: 0.7))
                    }
                }
                // Folds running down to the point.
                for x in [-0.25, 0.15] {
                    pen.stroke(HeadwearShape.smooth([hwp(x, -0.14), hwp(x * 0.6 + tip.x * 0.4, -0.5), hwp(tip.x * 0.8, -0.85)], closed: false),
                               ink.faded(0.35), width: 0.04)
                }
                pen.stroke(HeadwearShape.smooth([hwp(-0.45, -0.16), hwp(-0.2, -0.5), hwp(tip.x - 0.05, -0.85)], closed: false), HeadwearColor(1, 1, 1, 0.22), width: 0.05)
            }
            let band = HeadwearShape.smooth([hwp(-0.78, 0.1), hwp(-0.4, -0.04), hwp(0, -0.08), hwp(0.4, -0.04), hwp(0.78, 0.1), hwp(0.76, -0.1),
                                             hwp(0.4, -0.24), hwp(0, -0.28), hwp(-0.4, -0.24), hwp(-0.76, -0.1)], smoothness: 0.7)
            pen.paint(band, red, ink: ink, inkWidth: 0.04, direction: CGVector(dx: 0.2, dy: -1))
            pen.clipped(to: band) {
                pen.stroke(HeadwearShape.smooth([hwp(-0.7, 0.02), hwp(0, -0.14), hwp(0.7, 0.02)], closed: false), HeadwearColor(1, 1, 1, 0.25), width: 0.04)
                pen.stroke(HeadwearShape.smooth([hwp(-0.6, -0.12), hwp(0, -0.24), hwp(0.6, -0.12)], closed: false), ink.faded(0.3), width: 0.03)
            }
        }
    }
}

// MARK: - Propeller cap

/// A patchwork beanie with a propeller on top. It turns lazily in the breeze; smile and it whirs up and the cap lifts a little.
final class HeadwearPropeller: HeadwearCostume {
    let hint = "Smile to spin the propeller"

    private var angle = 0.0
    private(set) var speed = 1.2
    private var hover = HeadwearFollower()
    private var wobble = HeadwearSwing(omega: 10, damping: 0.18, gain: 0.03, limit: 0.3)

    /// Turns a second the propeller makes when idle and flat out.
    static let idle = 1.0, flatOut = 6.5

    func reset() { angle = 0; speed = Self.idle; hover = HeadwearFollower(); wobble.reset() }

    func advance(_ f: HeadwearFrame) {
        let target = Self.idle + (Self.flatOut - Self.idle) * f.signals.grin + min(2, abs(f.accel.x) * 0.04)
        speed += (target - speed) * (1 - exp(-f.dt * (target > speed ? 2.5 : 1.2)))
        angle = (angle + speed * 2 * .pi * f.dt).truncatingRemainder(dividingBy: 2 * .pi)
        hover.follow(f.signals.grin, dt: f.dt, rise: 3, fall: 2.5)
        wobble.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.04)
    }

    private static let panels = [HeadwearColor(hex: 0xFF6B6B), HeadwearColor(hex: 0xFFD166), HeadwearColor(hex: 0x4EA8F0), HeadwearColor(hex: 0x3CC9A0)]

    private static func paintCap(_ pen: HeadwearPen) {
        let rx = 1.12, ry = 0.8
        let dome = CGMutablePath()
        dome.addArc(center: .zero, radius: 1, startAngle: 0, endAngle: .pi, clockwise: false, transform: CGAffineTransform(scaleX: rx, y: ry))
        dome.closeSubpath()
        pen.clipped(to: dome) {
            // Six gores, seen from the front: their seams are meridians.
            let seams = [-90.0, -58, -26, 6, 38, 70, 90].map { $0 * .pi / 180 }
            for i in 0..<(seams.count - 1) {
                var pts: [CGPoint] = []
                for k in 0...12 { let y = ry * Double(k) / 12; pts.append(hwp(sin(seams[i]) * rx * sqrt(max(0, 1 - pow(y / ry, 2))), y)) }
                for k in (0...12).reversed() { let y = ry * Double(k) / 12; pts.append(hwp(sin(seams[i + 1]) * rx * sqrt(max(0, 1 - pow(y / ry, 2))), y)) }
                let gore = HeadwearShape.polygon(pts)
                let c = panels[i % panels.count]
                pen.paint(gore, [c.lighter(0.25), c, c.darker(0.2)], ink: nil, direction: CGVector(dx: 0.4, dy: -1))
                pen.stroke(HeadwearShape.smooth(Array(pts.prefix(13)), closed: false), c.darker(0.45).faded(0.6), width: 0.025)
            }
            // Round shading: lit from the top left.
            pen.paintRound(dome, center: hwp(-0.45, 0.62), radius: 1.6, [HeadwearColor(1, 1, 1, 0.32), HeadwearColor(1, 1, 1, 0), HeadwearColor(0.1, 0.05, 0.2, 0.35)])
        }
        pen.stroke(dome, HeadwearColor(hex: 0x2A2440), width: 0.045)
        // The ribbed band.
        let band = HeadwearShape.smooth([hwp(-1.17, 0.06), hwp(0, -0.1), hwp(1.17, 0.06), hwp(1.15, 0.28), hwp(0, 0.13), hwp(-1.15, 0.28)], smoothness: 0.55)
        pen.paint(band, [HeadwearColor(hex: 0x5C6CD8), HeadwearColor(hex: 0x3A47A8)], ink: HeadwearColor(hex: 0x1E2462), inkWidth: 0.035)
        pen.clipped(to: band) {
            for k in 0..<24 {
                let x = -1.12 + Double(k) * 0.097
                let sag = 0.16 * (1 - pow(x / 1.17, 2))
                pen.line(hwp(x, 0.08 - sag), hwp(x, 0.3 - sag), HeadwearColor(hex: 0x1E2462, alpha: 0.3), width: 0.018)
            }
            pen.stroke(HeadwearShape.smooth([hwp(-1.1, 0.24), hwp(0, 0.1), hwp(1.1, 0.24)], closed: false), HeadwearColor(1, 1, 1, 0.25), width: 0.03)
        }
        // The button and the stem the propeller turns on.
        pen.paint(HeadwearShape.rounded(CGRect(x: -0.035, y: 0.74, width: 0.07, height: 0.3), radius: 0.03), [HeadwearPalette.steelLight, HeadwearPalette.steelDeep],
                  ink: HeadwearPalette.steelInk, inkWidth: 0.02, direction: CGVector(dx: 1, dy: 0))
        pen.paintRound(HeadwearShape.ellipse(hwp(0, 0.78), rx: 0.11, ry: 0.07), center: hwp(-0.03, 0.81), radius: 0.14,
                       [HeadwearPalette.panelsLight, HeadwearColor(hex: 0xFF6B6B), HeadwearColor(hex: 0xB33A3A)], ink: HeadwearColor(hex: 0x6A1A1A), inkWidth: 0.02)
    }

    private static let window = CGRect(x: -1.25, y: -0.18, width: 2.5, height: 1.26)

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 2.6, duration: 0.7)
        let lift = 0.16 * hover.value + 0.03 * hover.value * sin(f.clock * 7)
        f.inFace(pen.ctx) {
            pen.placed(at: hwp(0, f.head.up(0.84) + fall + lift), turn: wobble.x, scale: f.head.wide) {
                let landed = HeadwearEase.smoothstep(1 - fall / 0.6)
                pen.shadow(at: hwp(0, -0.06 - lift), rx: 1.15, ry: 0.2, alpha: 0.4 * landed * (1 - 0.5 * hover.value))
                pen.sprite("propeller-cap", window: Self.window, pixelsPerUnit: f.io * f.head.wide) { Self.paintCap($0) }
                drawPropeller(pen, f, hub: hwp(0, 1.04))
            }
        }
    }

    private func drawPropeller(_ pen: HeadwearPen, _ f: HeadwearFrame, hub: CGPoint) {
        let pop = HeadwearEase.pop(f.seen, delay: 0.5, duration: 0.4)
        guard pop > 0.01 else { return }
        let length = 0.72 * pop
        // Faster than about three turns a second it blurs into a disc.
        let blur = HeadwearEase.smoothstep((speed - 2.5) / 3)
        if blur > 0.01 {
            let disc = HeadwearShape.ellipse(hub, rx: length, ry: 0.13)
            pen.paintRound(disc, center: hub, radius: length, [HeadwearColor(1, 0.95, 0.85, 0.05), HeadwearColor(1, 0.85, 0.6, 0.32 * blur)])
            pen.stroke(disc, HeadwearColor(1, 1, 1, 0.25 * blur), width: 0.02)
        }
        let colours = [HeadwearColor(hex: 0xFF6B6B), HeadwearColor(hex: 0xFFD166)]
        // Each blade is drawn back to front, so the one nearer the camera covers the other.
        let blades = [(angle, 0), (angle + .pi, 1)].sorted { sin($0.0) > sin($1.0) }
        for (a, i) in blades {
            let reach = cos(a) * length
            let depth = sin(a)
            let tipPoint = hwp(hub.x + reach, hub.y - 0.1 * depth)
            let width = 0.1 + 0.05 * abs(depth)
            let shape = HeadwearShape.smooth([hub, hwp(hub.x + reach * 0.3, hub.y + width * 0.6 - 0.03 * depth), hwp(tipPoint.x, tipPoint.y + width * 0.5),
                                              hwp(tipPoint.x + 0.04 * (reach >= 0 ? 1 : -1), tipPoint.y), hwp(tipPoint.x, tipPoint.y - width * 0.5),
                                              hwp(hub.x + reach * 0.3, hub.y - width * 0.6 - 0.03 * depth)], smoothness: 0.8)
            let c = colours[i]
            pen.ctx.saveGState()
            pen.ctx.setAlpha(CGFloat(1 - 0.55 * blur))
            pen.paint(shape, [c.lighter(0.3), c, c.darker(0.25)], ink: c.darker(0.55), inkWidth: 0.025)
            pen.ctx.restoreGState()
        }
        pen.paintRound(HeadwearShape.ellipse(hub, rx: 0.07, ry: 0.06), center: hwp(hub.x - 0.02, hub.y + 0.02), radius: 0.09,
                       [HeadwearPalette.goldLight, HeadwearPalette.goldDeep], ink: HeadwearPalette.goldInk, inkWidth: 0.02)
    }
}

extension HeadwearPalette {
    static let panelsLight = HeadwearColor(hex: 0xFFC2B8)
}

// MARK: - Chef

/// A tall chef's hat that puffs up when you raise your brows, and a dark curly moustache.
final class HeadwearChef: HeadwearCostume {
    let hint = "Raise your brows and the hat puffs up"

    private var puff = HeadwearSwing(omega: 11, damping: 0.22, gain: 0, limit: 1.4)
    private var wobble = HeadwearSwing(omega: 7, damping: 0.16, gain: 0.03, limit: 0.3)

    /// How puffed up the top of the hat is, 0 at rest to 1.
    var puffed: Double { puff.x }

    func reset() { puff.reset(); wobble.reset() }

    func advance(_ f: HeadwearFrame) {
        puff.step(dt: f.dt, accel: 0, rest: f.signals.browsAreUp ? 1 : 0)
        wobble.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.12)
    }

    private static let white = [HeadwearPalette.cream, HeadwearColor(hex: 0xF4F1EC), HeadwearColor(hex: 0xD3D8E6)]

    private static func paintBand(_ pen: HeadwearPen) {
        let band = HeadwearShape.smooth([hwp(-1.08, 0.06), hwp(0, -0.1), hwp(1.08, 0.06), hwp(1.0, 0.62), hwp(0, 0.54), hwp(-1.0, 0.62)], smoothness: 0.45)
        pen.paint(band, white, ink: HeadwearPalette.whiteInk, inkWidth: 0.045, direction: CGVector(dx: 1, dy: -0.25))
        pen.clipped(to: band) {
            for k in 0..<11 {
                let x = -1.0 + Double(k) * 0.2
                pen.stroke(HeadwearShape.smooth([hwp(x, -0.1), hwp(x * 1.02 + 0.015, 0.3), hwp(x * 1.04, 0.66)], closed: false),
                           HeadwearColor(hex: 0xA9B1CC, alpha: 0.55), width: 0.026)
                pen.stroke(HeadwearShape.smooth([hwp(x - 0.05, -0.1), hwp(x * 1.02 - 0.035, 0.3), hwp(x * 1.04 - 0.05, 0.66)], closed: false),
                           HeadwearColor(1, 1, 1, 0.6), width: 0.02)
            }
        }
    }

    private static let puffs: [(centre: CGPoint, radius: Double)] = [
        (hwp(-0.78, 0.34), 0.34), (hwp(-0.5, 0.66), 0.4), (hwp(-0.08, 0.8), 0.44), (hwp(0.38, 0.72), 0.42), (hwp(0.76, 0.38), 0.34),
        (hwp(0.02, 0.38), 0.5), (hwp(-0.42, 0.28), 0.36), (hwp(0.44, 0.28), 0.36),
    ]

    private static func paintTop(_ pen: HeadwearPen) {
        let body = HeadwearShape.rounded(CGRect(x: -0.92, y: -0.05, width: 1.84, height: 0.6), radius: 0.25)
        HeadwearFacialHair.cloud(pen, body: body, puffs: puffs, colors: white, ink: HeadwearPalette.whiteInk, outline: 0.04,
                                 shade: (hwp(0.4, 0.05), 1.0, HeadwearColor(hex: 0x8C98C4, alpha: 0.32)))
        // Soft folds between the puffs, and light on the top left.
        for (a, b) in [(hwp(-0.32, 0.18), hwp(-0.42, 0.68)), (hwp(0.24, 0.16), hwp(0.18, 0.74))] {
            pen.stroke(HeadwearShape.smooth([a, hwp((a.x + b.x) / 2 + 0.06, (a.y + b.y) / 2), b], closed: false), HeadwearColor(hex: 0xA9B1CC, alpha: 0.5), width: 0.03)
        }
        pen.glow(at: hwp(-0.4, 0.85), radius: 0.5, HeadwearColor(1, 1, 1, 0.6))
    }

    private static let bandWindow = CGRect(x: -1.16, y: -0.18, width: 2.32, height: 0.88)
    private static let topWindow = CGRect(x: -1.18, y: -0.16, width: 2.36, height: 1.42)

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            drawMoustache(pen, f)
            let fall = HeadwearEase.drop(f.seen, height: 3.0, duration: 0.8)
            pen.placed(at: hwp(0, f.head.up(0.76) + fall), turn: wobble.x * 0.4, scale: f.head.wide) {
                let landed = HeadwearEase.smoothstep(1 - fall / 0.6)
                pen.shadow(at: hwp(0, -0.06), rx: 1.15, ry: 0.18, alpha: 0.38 * landed)
                let p = puff.x
                // The puff swells taller than it widens, with a little lean as the head moves.
                pen.placed(at: hwp(0, 0.5), turn: wobble.x * 0.6, stretch: CGSize(width: 1.1 + 0.08 * p, height: 1 + 0.24 * p)) {
                    pen.sprite("chef-top", window: Self.topWindow, pixelsPerUnit: f.io * f.head.wide * (1 + 0.24 * max(0, p))) { Self.paintTop($0) }
                }
                pen.sprite("chef-band", window: Self.bandWindow, pixelsPerUnit: f.io * f.head.wide) { Self.paintBand($0) }
            }
        }
    }

    private func drawMoustache(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.4, duration: 0.45)
        let y = f.nose.y - (f.nose.y - f.upperLipY) * 0.58
        let style = HeadwearFacialHair.Moustache(colors: [HeadwearColor(hex: 0x4A3426), HeadwearColor(hex: 0x1A120D)], ink: HeadwearColor(hex: 0x0D0806),
                                                 reach: 0.92, thickness: 0.15, drop: 0.32, curl: 3.6, curlStart: 0.55, taper: 0.6,
                                                 highlight: HeadwearColor(1, 0.9, 0.75, 0.35))
        HeadwearFacialHair.moustache(pen, at: hwp(f.mouth.x, y), style, lift: 0.25 * f.signals.grin, scale: grow)
    }
}

// MARK: - Witch

/// A crooked witch's hat with a buckle and a patch, and a little spider on a thread. Open your mouth and down it drops.
final class HeadwearWitch: HeadwearCostume {
    let hint = "Open your mouth and the spider drops"

    private var bend = HeadwearSwing(omega: 5.5, damping: 0.15, gain: 0.04, limit: 0.8)
    private var thread = HeadwearSwing(omega: 9, damping: 0.16, gain: 0, limit: 3.5)
    private var pendulum = HeadwearSwing(omega: 5, damping: 0.1, gain: 0.05, limit: 0.7)

    /// How far below the brim the spider hangs, in eye-spacings.
    var drop: Double { thread.x }
    static let shortThread = 0.42

    func reset() { bend.reset(); thread.reset(); pendulum.reset() }

    func advance(_ f: HeadwearFrame) {
        bend.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.25)
        let brim = f.head.up(1.0) - 0.08
        let low = brim - (f.mouth.y + 0.05)
        thread.step(dt: f.dt, accel: 0, rest: f.signals.mouthIsOpen ? low : Self.shortThread + 0.04 * sin(f.clock * 1.7))
        pendulum.step(dt: f.dt, accel: f.accel.x, rest: f.hang)
    }

    private static let felt = [HeadwearColor(hex: 0x4B3864), HeadwearColor(hex: 0x2C2040), HeadwearColor(hex: 0x16101F)]
    private static let ink = HeadwearColor(hex: 0x0C0812)

    private static func paintBrim(_ pen: HeadwearPen) {
        let brim = HeadwearShape.ellipse(hwp(0, 0), rx: 1.9, ry: 0.3)
        pen.paint(brim, [HeadwearColor(hex: 0x56426F), HeadwearColor(hex: 0x271C38), HeadwearColor(hex: 0x120C1B)], ink: ink, inkWidth: 0.05,
                  direction: CGVector(dx: 0.3, dy: -1))
        pen.clipped(to: brim) {
            pen.stroke(HeadwearShape.smooth([hwp(-1.75, 0.04), hwp(-0.9, 0.24), hwp(0, 0.27), hwp(0.9, 0.24), hwp(1.75, 0.04)], closed: false),
                       HeadwearColor(hex: 0xB9A3E0, alpha: 0.5), width: 0.04)
            pen.fill(HeadwearShape.ellipse(hwp(0, -0.08), rx: 1.0, ry: 0.18), HeadwearColor(0, 0, 0, 0.25))
        }
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 3.2, duration: 0.85)
        let base = hwp(0, f.head.up(1.0) + fall)
        f.inFace(pen.ctx) {
            pen.placed(at: base, scale: f.head.wide) {
                let landed = HeadwearEase.smoothstep(1 - fall / 0.6)
                pen.shadow(at: hwp(0, -0.12), rx: 1.2, ry: 0.22, alpha: 0.45 * landed)
                drawCone(pen, f)
                pen.sprite("witch-brim", window: CGRect(x: -2.0, y: -0.38, width: 4.0, height: 0.76), pixelsPerUnit: f.io * f.head.wide) { Self.paintBrim($0) }
                drawBand(pen)
                drawSpider(pen, f)
            }
        }
    }

    private func drawCone(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let b = bend.x
        func heading(_ t: Double) -> Double {
            // Up, a kink back to the left, then the tip flops over to the right.
            .pi / 2 + 0.28 * HeadwearEase.smoothstep((t - 0.35) / 0.15) - 1.25 * HeadwearEase.smoothstep((t - 0.66) / 0.22) - b * t * t * 1.4
        }
        func width(_ t: Double) -> Double { 0.8 * pow(1 - t, 0.95) + 0.006 }
        let spine = HeadwearShape.spine(from: hwp(0, 0.05), length: 2.5, steps: 24, heading: heading)
        let cone = HeadwearShape.ribbon(spine, tip: 0.3, width: width)
        pen.paint(cone, Self.felt, ink: Self.ink, inkWidth: 0.05, direction: CGVector(dx: 1, dy: -0.4))
        pen.clipped(to: cone) {
            // Creases where it kinks, light down the left, and a stitched patch.
            for t in [0.45, 0.74] {
                let i = Int(t * Double(spine.count - 1))
                let p = spine[i], a = heading(t) + .pi / 2, w = width(t) * 1.1
                pen.stroke(HeadwearShape.smooth([hwp(p.x + cos(a) * w, p.y + sin(a) * w), hwp(p.x + 0.04, p.y - 0.05), hwp(p.x - cos(a) * w, p.y - sin(a) * w)], closed: false),
                           HeadwearColor(0, 0, 0, 0.45), width: 0.05)
            }
            let sheen = spine.prefix(15).enumerated().map { i, p -> CGPoint in
                let t = Double(i) / Double(spine.count - 1), a = heading(t) + .pi / 2
                return hwp(p.x + cos(a) * width(t) * 0.55, p.y + sin(a) * width(t) * 0.55)
            }
            pen.stroke(HeadwearShape.smooth(sheen, closed: false), HeadwearColor(hex: 0xC9B4F0, alpha: 0.3), width: 0.06)
            let patchAt = spine[7]
            pen.placed(at: hwp(patchAt.x + 0.18, patchAt.y), turn: 0.15) {
                let patch = HeadwearShape.rounded(CGRect(x: -0.17, y: -0.15, width: 0.34, height: 0.3), radius: 0.03)
                pen.paint(patch, [HeadwearColor(hex: 0x8F7A5A), HeadwearColor(hex: 0x5E4C34)], ink: HeadwearColor(hex: 0x2A2014), inkWidth: 0.02)
                pen.ctx.saveGState()
                pen.ctx.setLineDash(phase: 0, lengths: [0.035, 0.03])
                pen.stroke(HeadwearShape.rounded(CGRect(x: -0.13, y: -0.11, width: 0.26, height: 0.22), radius: 0.02), HeadwearColor(hex: 0xE8D9B8, alpha: 0.85), width: 0.015, cap: .butt)
                pen.ctx.restoreGState()
            }
        }
    }

    private func drawBand(_ pen: HeadwearPen) {
        let band = HeadwearShape.smooth([hwp(-0.8, 0.06), hwp(0, -0.02), hwp(0.8, 0.06), hwp(0.77, 0.3), hwp(0, 0.24), hwp(-0.77, 0.3)], smoothness: 0.5)
        pen.paint(band, [HeadwearColor(hex: 0x9A5CC8), HeadwearColor(hex: 0x5E2A88)], ink: HeadwearColor(hex: 0x2A0E42), inkWidth: 0.03)
        pen.clipped(to: band) { pen.line(hwp(-0.8, 0.22), hwp(0.8, 0.22), HeadwearColor(1, 1, 1, 0.22), width: 0.03) }
        let buckle = HeadwearShape.rounded(CGRect(x: -0.17, y: -0.02, width: 0.34, height: 0.32), radius: 0.03)
        let hole = HeadwearShape.rounded(CGRect(x: -0.09, y: 0.06, width: 0.18, height: 0.16), radius: 0.02)
        let frame = CGMutablePath(); frame.addPath(buckle); frame.addPath(hole)
        pen.paint(frame, [HeadwearColor(hex: 0xD4F58A), HeadwearColor(hex: 0x7CC23E), HeadwearColor(hex: 0x4A8A22)], ink: HeadwearColor(hex: 0x1E3E0C),
                  inkWidth: 0.022, evenOdd: true)
        pen.line(hwp(-0.13, 0.25), hwp(0.0, 0.27), HeadwearColor(1, 1, 1, 0.6), width: 0.02)
    }

    private func drawSpider(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let appear = HeadwearEase.pop(f.seen, delay: 0.7, duration: 0.4)
        guard appear > 0.01 else { return }
        let anchor = hwp(1.3, -0.12)
        let length = max(0.1, thread.x) * appear / f.head.wide
        let a = pendulum.x
        let body = hwp(anchor.x + sin(a) * length, anchor.y - cos(a) * length)
        pen.line(anchor, body, HeadwearColor(1, 1, 1, 0.55), width: 0.012)
        let wiggle = sin(f.clock * 9) * 0.12 * (abs(thread.v) > 0.3 ? 1 : 0.35)
        pen.placed(at: body, turn: a) {
            for side in [-1.0, 1.0] {
                for k in 0..<4 {
                    let root = hwp(side * 0.05, 0.03 - Double(k) * 0.035)
                    let knee = hwp(side * (0.16 + 0.02 * Double(k)), 0.1 - Double(k) * 0.07 + wiggle * (k % 2 == 0 ? 1 : -1) * 0.3)
                    let foot = hwp(side * (0.24 + 0.02 * Double(k)), -0.06 - Double(k) * 0.07)
                    let leg = CGMutablePath(); leg.move(to: root); leg.addQuadCurve(to: foot, control: knee)
                    pen.stroke(leg, HeadwearColor(hex: 0x15101C), width: 0.022)
                }
            }
            pen.paintRound(HeadwearShape.ellipse(hwp(0, -0.06), rx: 0.1, ry: 0.12), center: hwp(-0.03, -0.02), radius: 0.15,
                           [HeadwearColor(hex: 0x5A4A6A), HeadwearColor(hex: 0x1A1420)], ink: HeadwearColor(hex: 0x0A070D), inkWidth: 0.015)
            pen.paintRound(HeadwearShape.ellipse(hwp(0, 0.06), rx: 0.065, ry: 0.06), center: hwp(-0.02, 0.08), radius: 0.09,
                           [HeadwearColor(hex: 0x4A3C58), HeadwearColor(hex: 0x1A1420)], ink: HeadwearColor(hex: 0x0A070D), inkWidth: 0.012)
            for side in [-1.0, 1.0] {
                pen.dot(at: hwp(side * 0.028, 0.05), radius: 0.022, HeadwearColor.white)
                pen.dot(at: hwp(side * 0.028 + 0.004, 0.045), radius: 0.011, HeadwearColor(hex: 0x15101C))
            }
        }
    }
}

// MARK: - Viking

/// A horned steel helmet with long golden braids that swing as you move. Open wide for a battle roar: the helmet jumps and
/// the braids fly.
final class HeadwearViking: HeadwearCostume {
    let hint = "Open wide for a battle roar"

    private var braids = [HeadwearSwing(omega: 5.2, damping: 0.14, gain: 0.06, limit: 0.9), HeadwearSwing(omega: 4.8, damping: 0.15, gain: 0.06, limit: 0.9)]
    private var jolt = HeadwearSwing(omega: 16, damping: 0.25, gain: 0, limit: 1)
    private var roar = HeadwearFollower()

    /// How far the helmet has jumped, in eye-spacings.
    var hop: Double { max(0, jolt.x) * 0.22 }
    /// How far each braid is swung.
    var braidSwing: [Double] { braids.map(\.x) }

    func reset() { braids[0].reset(); braids[1].reset(); jolt.reset(); roar = HeadwearFollower() }

    func advance(_ f: HeadwearFrame) {
        if f.signals.mouthGate.rose {
            jolt.shove(14)
            braids[0].shove(-2.5); braids[1].shove(2.5)
        }
        jolt.step(dt: f.dt, accel: 0, rest: 0)
        roar.follow(f.signals.mouthIsOpen ? 1 : 0, dt: f.dt, rise: 10, fall: 4)
        for i in 0..<2 { braids[i].step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.9) }
    }

    private static func paintHelmet(_ pen: HeadwearPen) {
        // Horns behind the helmet's edge.
        for side in [-1.0, 1.0] {
            func heading(_ t: Double) -> Double { side > 0 ? 0.25 + 1.6 * pow(t, 1.2) : .pi - 0.25 - 1.6 * pow(t, 1.2) }
            let spine = HeadwearShape.spine(from: hwp(side * 0.86, 0.38), length: 1.12, steps: 16, heading: heading)
            let horn = HeadwearShape.ribbon(spine, tip: 0.2, base: 0.3) { t in 0.2 * pow(1 - t, 0.8) + 0.005 }
            pen.paint(horn, [HeadwearColor(hex: 0xFFF7E4), HeadwearColor(hex: 0xEAD5AA), HeadwearColor(hex: 0xB89766)], ink: HeadwearColor(hex: 0x5E4626),
                      inkWidth: 0.045, direction: CGVector(dx: side * 0.3, dy: -1))
            pen.clipped(to: horn) {
                for k in 1...5 {
                    let t = Double(k) * 0.15
                    let i = Int(t * Double(spine.count - 1)), p = spine[i], a = heading(t) + .pi / 2, w = (0.2 * pow(1 - t, 0.8)) * 1.2
                    pen.line(hwp(p.x + cos(a) * w, p.y + sin(a) * w), hwp(p.x - cos(a) * w, p.y - sin(a) * w), HeadwearColor(hex: 0x8A6E44, alpha: 0.35), width: 0.022)
                }
                let shine = spine.prefix(12).enumerated().map { i, p -> CGPoint in
                    let t = Double(i) / 16, a = heading(t) + .pi / 2
                    return hwp(p.x + cos(a) * 0.08 * (1 - t) * side, p.y + sin(a) * 0.08 * (1 - t) * side)
                }
                pen.stroke(HeadwearShape.smooth(shine, closed: false), HeadwearColor(1, 1, 1, 0.55), width: 0.03)
            }
            // A bronze ring where each horn meets the helmet.
            let ring = HeadwearShape.ribbon(Array(spine.prefix(3)), tip: 0, width: { _ in 0.23 })
            pen.paint(ring, [HeadwearColor(hex: 0xF0B864), HeadwearColor(hex: 0xA8642A)], ink: HeadwearColor(hex: 0x5A2E0E), inkWidth: 0.03)
        }
        // The dome.
        let dome = CGMutablePath()
        dome.addArc(center: hwp(0, 0.06), radius: 1, startAngle: 0, endAngle: .pi, clockwise: false, transform: CGAffineTransform(scaleX: 1.04, y: 0.98))
        dome.closeSubpath()
        pen.paint(dome, [HeadwearPalette.steelLight, HeadwearPalette.steel, HeadwearPalette.steelDeep], ink: HeadwearPalette.steelInk, inkWidth: 0.05,
                  direction: CGVector(dx: 0.6, dy: -1))
        pen.clipped(to: dome) {
            pen.paintRound(dome, center: hwp(-0.4, 0.75), radius: 1.5, [HeadwearColor(1, 1, 1, 0.5), HeadwearColor(1, 1, 1, 0), HeadwearColor(0.1, 0.12, 0.2, 0.3)])
            // A raised ridge front to back, with rivets down it.
            let ridge = HeadwearShape.smooth([hwp(-0.13, 0.1), hwp(-0.11, 0.7), hwp(0, 1.03), hwp(0.11, 0.7), hwp(0.13, 0.1)], closed: true, smoothness: 0.6)
            pen.paint(ridge, [HeadwearColor(hex: 0xF0B864), HeadwearColor(hex: 0xC27E36), HeadwearColor(hex: 0x8A4E1C)], ink: HeadwearColor(hex: 0x5A2E0E), inkWidth: 0.025)
            for k in 0..<4 { pen.dot(at: hwp(0, 0.24 + Double(k) * 0.19), radius: 0.032, HeadwearColor(hex: 0xFFE2A8)) }
            pen.stroke(HeadwearShape.smooth([hwp(-0.86, 0.3), hwp(-0.62, 0.72), hwp(-0.3, 0.92)], closed: false), HeadwearColor(1, 1, 1, 0.7), width: 0.05)
        }
        // The bronze rim with rivets.
        let rim = HeadwearShape.smooth([hwp(-1.1, 0.02), hwp(0, -0.08), hwp(1.1, 0.02), hwp(1.08, 0.26), hwp(0, 0.18), hwp(-1.08, 0.26)], smoothness: 0.5)
        pen.paint(rim, [HeadwearColor(hex: 0xF6C676), HeadwearColor(hex: 0xC27E36), HeadwearColor(hex: 0x7E4418)], ink: HeadwearColor(hex: 0x4A2408), inkWidth: 0.035)
        for k in 0..<9 {
            let x = -0.92 + Double(k) * 0.23
            let y = 0.09 - 0.06 * (1 - pow(x / 1.1, 2))
            pen.paintRound(HeadwearShape.ellipse(hwp(x, y), rx: 0.035, ry: 0.035), center: hwp(x - 0.01, y + 0.012), radius: 0.05,
                           [HeadwearColor(hex: 0xFFF0C8), HeadwearColor(hex: 0x9A5A22)], ink: HeadwearColor(hex: 0x4A2408), inkWidth: 0.01)
        }
    }

    private static let window = CGRect(x: -2.0, y: -0.2, width: 4.0, height: 1.6)

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 2.8, duration: 0.8)
        let rattle = roar.value * 0.035 * sin(f.clock * 47)
        f.inFace(pen.ctx) {
            for (i, side) in [-1.0, 1.0].enumerated() { drawBraid(pen, f, side: side, swing: braids[i].x) }
            pen.placed(at: hwp(0, f.head.up(0.92) + fall + hop), turn: rattle, scale: f.head.wide) {
                let landed = HeadwearEase.smoothstep(1 - fall / 0.6)
                pen.shadow(at: hwp(0, -0.04 - hop), rx: 1.15, ry: 0.2, alpha: 0.42 * landed)
                pen.sprite("viking-helmet", window: Self.window, pixelsPerUnit: f.io * f.head.wide) { Self.paintHelmet($0) }
            }
        }
    }

    private func drawBraid(_ pen: HeadwearPen, _ f: HeadwearFrame, side: Double, swing: Double) {
        let grow = HeadwearEase.smoothstep((f.seen - 0.4) / 0.5)
        guard grow > 0.01 else { return }
        let gold = [HeadwearColor(hex: 0xFCE29A), HeadwearColor(hex: 0xE6AE4E), HeadwearColor(hex: 0xA86E24)]
        let ink = HeadwearColor(hex: 0x6A4214)
        // Hair from under the helmet's rim, gathered down into the plait.
        let rim = f.head.up(0.92)
        let x = f.head.side(side * 1.0)
        let hair = HeadwearShape.ribbon([hwp(x - side * 0.04, rim + 0.08), hwp(x, rim - 0.25), hwp(x + side * 0.02, rim - 0.55)], tip: 0, base: 0) { t in 0.2 - 0.07 * t }
        pen.paint(hair, gold, ink: ink, inkWidth: 0.035, direction: CGVector(dx: side * 0.4, dy: -1))
        pen.clipped(to: hair) {
            for k in -1...1 {
                pen.stroke(HeadwearShape.smooth([hwp(x + Double(k) * 0.08, rim + 0.08), hwp(x + Double(k) * 0.05, rim - 0.3), hwp(x + Double(k) * 0.02, rim - 0.6)], closed: false),
                           Double(k) == -side ? HeadwearColor(1, 1, 0.9, 0.45) : ink.faded(0.3), width: 0.02)
            }
        }
        let root = hwp(x + side * 0.02, rim - 0.5)
        let length = 1.7 * grow
        let spine = HeadwearShape.spine(from: root, length: length, steps: 11) { t in -.pi / 2 + side * 0.04 + swing * t * 1.1 }
        // The plait: lobes that lean in turn to one side and the other, each overlapping the one above.
        for k in 0..<(spine.count - 2) {
            let p = spine[k], q = spine[k + 1]
            let a = atan2(q.y - p.y, q.x - p.x)
            let w = 0.15 - 0.04 * Double(k) / Double(spine.count)
            let lean = k % 2 == 0 ? 1.0 : -1.0
            let n = hwp(-sin(a), cos(a))
            let centre = hwp((p.x + q.x) / 2 + n.x * lean * w * 0.35, (p.y + q.y) / 2 + n.y * lean * w * 0.35)
            let lobe = HeadwearShape.ellipse(centre, rx: hypot(q.x - p.x, q.y - p.y) * 0.8, ry: w * 0.85, turn: a + lean * 0.62)
            pen.paint(lobe, gold, ink: ink, inkWidth: 0.028, direction: CGVector(dx: -sin(a + lean * 0.6) * 0.5 + 0.3, dy: cos(a + lean * 0.6)))
            pen.stroke(HeadwearShape.ellipse(hwp(centre.x - 0.015, centre.y + 0.02), rx: hypot(q.x - p.x, q.y - p.y) * 0.45, ry: w * 0.28, turn: a + lean * 0.62),
                       HeadwearColor(1, 1, 0.92, 0.45), width: 0.018)
        }
        // A leather tie and the loose end.
        if spine.count > 2 {
            let end = spine[spine.count - 1], before = spine[spine.count - 2]
            let a = atan2(end.y - before.y, end.x - before.x)
            let tuftSpine = HeadwearShape.spine(from: before, length: 0.38, steps: 6) { t in a + 0.15 * sin(f.clock * 2 + t * 3) }
            let tuft = HeadwearShape.ribbon(tuftSpine, tip: 0.5) { t in 0.07 + 0.07 * t * (1 - t) * 4 - 0.06 * t }
            pen.paint(tuft, gold, ink: ink, inkWidth: 0.03)
            pen.paint(HeadwearShape.ellipse(before, rx: 0.075, ry: 0.11, turn: a), [HeadwearColor(hex: 0x9A6A40), HeadwearColor(hex: 0x4A2A14)],
                      ink: HeadwearColor(hex: 0x2A160A), inkWidth: 0.02)
        }
    }
}
