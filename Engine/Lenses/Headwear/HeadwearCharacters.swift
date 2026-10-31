import CoreGraphics
import Foundation

// MARK: - Santa

/// Santa: a drooping red hat with a fluffy brim and a bobble that swings, a big white beard and moustache, rosy cheeks.
final class HeadwearSanta: HeadwearCostume {
    let hint = "Ho ho ho! Shake your head to swing the bobble"

    private var droop = HeadwearSwing(omega: 5.5, damping: 0.15, gain: 0.05, limit: 1.0)
    private var bobble = HeadwearSwing(omega: 8, damping: 0.12, gain: 0.05, limit: 0.7)
    private var beardSwing = HeadwearSwing(omega: 5, damping: 0.2, gain: 0.04, limit: 0.35)

    /// How far the bobble has swung to one side, in eye-spacings.
    var bobbleSwing: Double { bobble.x }

    func reset() { droop.reset(); bobble.reset(); beardSwing.reset() }

    func advance(_ f: HeadwearFrame) {
        droop.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.2)
        bobble.step(dt: f.dt, accel: f.accel.x * 1.5, rest: f.hang * 0.25)
        beardSwing.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.3)
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            let blush = HeadwearEase.smoothstep((f.seen - 0.3) / 0.3)
            for side in [-1.0, 1.0] { pen.glow(at: hwp(side * 0.72, f.nose.y - 0.02), radius: 0.34, HeadwearColor(hex: 0xFF5D78, alpha: 0.42 * blush)) }
            drawBeard(pen, f)
            drawMoustache(pen, f)
            drawHat(pen, f)
        }
    }

    private func drawBeard(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.outBack((f.seen - 0.3) / 0.6)
        let beard = HeadwearFacialHair.Beard(length: 0.95, bulge: 0.55, taper: 0.1, sway: beardSwing.x,
                                             colors: [HeadwearColor.white, HeadwearColor(hex: 0xEDF0FA), HeadwearColor(hex: 0xD8DEF0)],
                                             ink: HeadwearColor(hex: 0x95A0C6))
        HeadwearFacialHair.beard(pen, f, beard, fluffy: true, grow: grow)
    }

    private func drawMoustache(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.45, duration: 0.4)
        let y = f.nose.y - (f.nose.y - f.upperLipY) * 0.55
        let style = HeadwearFacialHair.Moustache(colors: [HeadwearColor.white, HeadwearColor(hex: 0xE4E8F6)], ink: HeadwearColor(hex: 0x95A0C6),
                                                 reach: 1.02, thickness: 0.24, drop: 0.42, curl: 1.4, curlStart: 0.5, taper: 0.45,
                                                 highlight: HeadwearColor(0.6, 0.66, 0.9, 0.3))
        HeadwearFacialHair.moustache(pen, at: hwp(f.mouth.x, y), style, lift: 0.12 * f.signals.grin, scale: grow)
    }

    private func drawHat(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 3.0, duration: 0.75)
        pen.placed(at: hwp(0, fall + f.head.up(1.15) - 1.15)) {
            pen.shadow(at: hwp(0, 0.92), rx: 1.15, ry: 0.2, alpha: 0.3 * HeadwearEase.smoothstep(1 - fall / 0.6))
            func heading(_ t: Double) -> Double { .pi / 2 - (0.18 + 2.1 * pow(t, 1.5)) - droop.x * t * t }
            func width(_ t: Double) -> Double { 1.0 * (1 - 0.8 * pow(t, 0.9)) }
            let spine = HeadwearShape.spine(from: hwp(0, 1.18), length: 2.0, steps: 22, heading: heading)
            let cone = HeadwearShape.ribbon(spine, tip: 0.3, base: 0, width: width)
            pen.paint(cone, [HeadwearColor(hex: 0xF24A4A), HeadwearColor(hex: 0xD02636), HeadwearColor(hex: 0xA8162A)],
                      ink: HeadwearColor(hex: 0x6A0C1C), inkWidth: 0.05, direction: CGVector(dx: 0.4, dy: -1))
            pen.clipped(to: cone) {
                let sheen = spine.prefix(14).enumerated().map { hwp($0.element.x - width(Double($0.offset) / 22) * 0.45, $0.element.y) }
                pen.stroke(HeadwearShape.smooth(sheen, closed: false), HeadwearColor(1, 0.8, 0.8, 0.28), width: 0.09)
                pen.glow(at: hwp(0, 1.2), radius: 0.8, HeadwearColor(0.3, 0, 0.05, 0.4))
            }
            // The fur band, with its puffy edges, and the bobble at the tip: both painted once and kept.
            let fur = [HeadwearColor.white, HeadwearColor(hex: 0xE5EAF7)]
            let edge = HeadwearColor(hex: 0x95A0C6)
            pen.sprite("santa-band", window: CGRect(x: -1.42, y: 0.68, width: 2.84, height: 0.96), pixelsPerUnit: f.io) { pen in
                let band = HeadwearShape.rounded(CGRect(x: -1.17, y: 0.95, width: 2.34, height: 0.4), radius: 0.2)
                var puffs: [(centre: CGPoint, radius: Double)] = []
                for x in stride(from: -1.08, through: 1.1, by: 0.27) {
                    for (y, salt) in [(0.95, 1), (1.35, 2)] as [(Double, Int)] {
                        puffs.append((hwp(x, y), 0.17 + 0.03 * HeadwearNoise.unit(Int(x * 100), salt)))
                    }
                }
                HeadwearFacialHair.cloud(pen, body: band, puffs: puffs, colors: fur, ink: edge, outline: 0.035,
                                         shade: (hwp(0, 0.93), 1.4, HeadwearColor(hex: 0x8C98C4, alpha: 0.3)))
            }
            if let end = spine.last {
                let centre = hwp(end.x + bobble.x * 0.3, end.y - 0.08 - abs(bobble.x) * 0.05)
                pen.placed(at: centre) {
                    pen.sprite("santa-bobble", window: CGRect(x: -0.36, y: -0.36, width: 0.72, height: 0.72), pixelsPerUnit: f.io) { pen in
                        var ball: [(centre: CGPoint, radius: Double)] = [(.zero, 0.21)]
                        for k in 0..<8 {
                            let a = Double(k) * .pi / 4 + 0.3
                            ball.append((hwp(cos(a) * 0.16, sin(a) * 0.16), 0.11))
                        }
                        HeadwearFacialHair.cloud(pen, body: CGMutablePath(), puffs: ball, colors: fur, ink: edge, outline: 0.035,
                                                 shade: (hwp(0, -0.2), 0.5, HeadwearColor(hex: 0x8C98C4, alpha: 0.3)))
                    }
                }
            }
        }
    }
}

// MARK: - Gentleman

/// A gentleman: a glossy top hat, a monocle that glints and a magnificent curly moustache that twitches when you smile.
final class HeadwearGentleman: HeadwearCostume {
    let hint = "Smile and the moustache twitches"

    private var flick = HeadwearSwing(omega: 26, damping: 0.1, gain: 0, limit: 1.2)
    private var chain = HeadwearSwing(omega: 6, damping: 0.14, gain: 0.05, limit: 0.7)

    /// How far the moustache ends are flicked, in radians.
    var twitch: Double { flick.x }

    func reset() { flick.reset(); chain.reset() }

    func advance(_ f: HeadwearFrame) {
        if f.signals.smileGate.rose { flick.shove(16) }
        flick.step(dt: f.dt, accel: 0, rest: 0)
        chain.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.6)
    }

    /// Where the glint is in its sweep across the glass, 0 at the start to 1 at the end, or nil between glints.
    static func glint(at clock: Double) -> Double? {
        let phase = (clock + 1.2).truncatingRemainder(dividingBy: 3.6) / 0.7
        return phase < 1 ? phase : nil
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            drawMoustache(pen, f)
            drawMonocle(pen, f)
            drawHat(pen, f)
        }
    }

    private func drawMoustache(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.3, duration: 0.5)
        let y = f.nose.y - (f.nose.y - f.upperLipY) * 0.6
        let style = HeadwearFacialHair.Moustache(colors: [HeadwearColor(hex: 0x7A5238), HeadwearColor(hex: 0x4A2C18), HeadwearColor(hex: 0x24130A)], ink: HeadwearColor(hex: 0x120904),
                                                 reach: 1.4, thickness: 0.2, drop: 0.2, curl: 4.4, curlStart: 0.42, taper: 0.55,
                                                 highlight: HeadwearColor(1, 0.88, 0.7, 0.45))
        HeadwearFacialHair.moustache(pen, at: hwp(f.mouth.x, y), style, flick: flick.x, lift: 0.3 * f.signals.grin, scale: grow)
    }

    private func drawMonocle(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let appear = HeadwearEase.pop(f.seen, delay: 0.5, duration: 0.45)
        guard appear > 0.001 else { return }
        let eye = hwp(0.5, 0.0)
        let r = 0.31
        let gold = HeadwearColor(hex: 0xF2C14A), dark = HeadwearColor(hex: 0x7A5412)
        pen.placed(at: eye, scale: appear) {
            let ring = HeadwearShape.ellipse(hwp(0, 0), rx: r, ry: r)
            // The chain, hanging from the rim.
            let sway = chain.x
            let chainPath = CGMutablePath()
            chainPath.move(to: hwp(r * 0.72, -r * 0.72))
            chainPath.addQuadCurve(to: hwp(0.62 + sway * 0.7, -1.55), control: hwp(0.5 + sway * 0.3, -0.7))
            pen.ctx.saveGState()
            pen.ctx.setLineDash(phase: 0, lengths: [0.05, 0.035])
            pen.stroke(chainPath, dark, width: 0.06, cap: .butt)
            pen.stroke(chainPath, gold, width: 0.036, cap: .butt)
            pen.ctx.restoreGState()
            // Glass, then rim.
            pen.fill(ring, HeadwearColor(0.85, 0.93, 1, 0.1))
            if let g = Self.glint(at: f.clock) {
                pen.clipped(to: ring) {
                    let x = -0.5 + g * 1.0
                    pen.fill(HeadwearShape.polygon([hwp(x - 0.07, 0.4), hwp(x + 0.02, 0.4), hwp(x - 0.2, -0.4), hwp(x - 0.29, -0.4)]), HeadwearColor(1, 1, 1, 0.7))
                    pen.fill(HeadwearShape.polygon([hwp(x + 0.1, 0.4), hwp(x + 0.14, 0.4), hwp(x - 0.08, -0.4), hwp(x - 0.12, -0.4)]), HeadwearColor(1, 1, 1, 0.5))
                }
                if g > 0.35 && g < 0.85 {
                    let spark = sin((g - 0.35) / 0.5 * .pi)
                    pen.sparkle(at: hwp(-0.2, 0.24), radius: 0.2 * spark, HeadwearColor(1, 1, 0.9, 0.95), additive: true)
                }
            }
            pen.fill(HeadwearShape.ellipse(hwp(-0.1, 0.12), rx: 0.1, ry: 0.035, turn: 0.7), HeadwearColor(1, 1, 1, 0.45))
            pen.stroke(ring, dark, width: 0.1)
            pen.stroke(ring, gold, width: 0.065)
            pen.stroke(HeadwearShape.smooth([hwp(-0.28, 0.1), hwp(-0.16, 0.24), hwp(0.02, 0.3)], closed: false), HeadwearColor(1, 0.97, 0.8, 0.9), width: 0.03)
        }
    }

    private func drawHat(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 3.0, duration: 0.8)
        // Drawn with its brim at 1.08 and scaled up round that point, so it sits down on the head rather than perching on it.
        pen.placed(at: hwp(0, fall + f.head.up(0.98)), turn: -0.03, scale: 1.16 * f.head.wide) {
            pen.ctx.translateBy(x: 0, y: -1.08)
            pen.shadow(at: hwp(0, 1.0), rx: 1.2, ry: 0.22, alpha: 0.45 * HeadwearEase.smoothstep(1 - fall / 0.6))
            pen.sprite("top-hat", window: CGRect(x: -1.22, y: 0.8, width: 2.44, height: 1.9), pixelsPerUnit: f.io * 1.16 * f.head.wide) { Self.paintHat($0) }
        }
    }

    /// The top hat, its brim at 1.08: painted once and kept.
    private static func paintHat(_ pen: HeadwearPen) {
        let brim = HeadwearShape.ellipse(hwp(0, 1.08), rx: 1.14, ry: 0.21)
        pen.paint(brim, [HeadwearColor(hex: 0x2E2E3A), HeadwearColor(hex: 0x0C0C12)], ink: HeadwearColor(hex: 0x050508), inkWidth: 0.045)
        // The crown, a little flared at the bottom.
        let crown = CGMutablePath()
        crown.move(to: hwp(-0.74, 1.1))
        crown.addLine(to: hwp(-0.66, 2.5))
        crown.addQuadCurve(to: hwp(0.66, 2.5), control: hwp(0, 2.36))
        crown.addLine(to: hwp(0.74, 1.1))
        crown.addQuadCurve(to: hwp(-0.74, 1.1), control: hwp(0, 0.78))
        crown.closeSubpath()
        pen.paint(crown, [HeadwearColor(hex: 0x40404E), HeadwearColor(hex: 0x14141A), HeadwearColor(hex: 0x08080C)],
                  ink: HeadwearColor(hex: 0x050508), inkWidth: 0.05, direction: CGVector(dx: 1, dy: 0))
        // The top face and a streak of light down the side.
        let top = HeadwearShape.ellipse(hwp(0, 2.5), rx: 0.67, ry: 0.15)
        pen.paint(top, [HeadwearColor(hex: 0x4A4A58), HeadwearColor(hex: 0x1B1B22)], ink: HeadwearColor(hex: 0x050508), inkWidth: 0.04)
        pen.clipped(to: crown) {
            pen.fill(HeadwearShape.polygon([hwp(-0.46, 2.35), hwp(-0.36, 2.35), hwp(-0.42, 1.2), hwp(-0.54, 1.2)]), HeadwearColor(1, 1, 1, 0.16))
        }
        // The band.
        let band = CGMutablePath()
        band.move(to: hwp(-0.72, 1.14))
        band.addQuadCurve(to: hwp(0.72, 1.14), control: hwp(0, 0.86))
        band.addLine(to: hwp(0.7, 1.44))
        band.addQuadCurve(to: hwp(-0.7, 1.44), control: hwp(0, 1.16))
        band.closeSubpath()
        pen.paint(band, [HeadwearColor(hex: 0xB02A3C), HeadwearColor(hex: 0x6E1424)], ink: HeadwearColor(hex: 0x3A0A14), inkWidth: 0.03)
        let buckle = HeadwearShape.rounded(CGRect(x: -0.12, y: 1.01, width: 0.24, height: 0.27), radius: 0.03)
        pen.paint(buckle, [HeadwearColor(hex: 0xFFE27A), HeadwearColor(hex: 0xD99A1E)], ink: HeadwearColor(hex: 0x6E4A0A), inkWidth: 0.025)
        pen.stroke(HeadwearShape.rounded(CGRect(x: -0.06, y: 1.07, width: 0.12, height: 0.15), radius: 0.02), HeadwearColor(hex: 0x6E4A0A), width: 0.025)
    }
}

// MARK: - Pirate

/// A pirate: a skull-and-crossbones tricorn, an eye patch, a gold hoop in the ear, stubble and an old scar.
final class HeadwearPirate: HeadwearCostume {
    let hint = "Arr! Tilt your head to swing the earring"

    private var hoop = HeadwearSwing(omega: 9, damping: 0.1, gain: 0.07, limit: 1.3)

    func reset() { hoop.reset() }

    func advance(_ f: HeadwearFrame) {
        hoop.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.9)
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            drawStubble(pen, f)
            drawScar(pen, f)
            drawPatch(pen, f)
            drawEarring(pen, f)
            drawHat(pen, f)
        }
    }

    private func drawStubble(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let a = HeadwearEase.smoothstep((f.seen - 0.4) / 0.4)
        guard a > 0.01 else { return }
        let top = -0.42, bottom = f.chinY + 0.1
        let cy = (top + bottom) / 2, ry = (top - bottom) / 2
        // A five o'clock shadow: a soft cool tint over the jaw, and fine short hairs that leave the lips clear.
        pen.placed(at: hwp(0, cy), stretch: CGSize(width: 0.95, height: ry * 1.25)) {
            pen.glow(at: .zero, radius: 1.0, HeadwearColor(hex: 0x2E2A3A, alpha: 0.3 * a))
        }
        // All the hairs go into one path and are drawn in one go.
        let hairs = CGMutablePath()
        for k in 0..<240 {
            let r = sqrt(HeadwearNoise.unit(k, 11)) * 0.9, angle = HeadwearNoise.unit(k, 12) * 2 * .pi
            let p = hwp(cos(angle) * r * 0.78, cy + sin(angle) * r * ry)
            let dx = (p.x - f.mouth.x) / (f.mouthWidth / 2 + 0.1), dy = (p.y - f.mouth.y) / (0.14 + 0.3 * f.face.mouthOpen)
            if dx * dx + dy * dy < 1 { continue }
            let tilt = -1.4 + 0.5 * (HeadwearNoise.unit(k, 14) - 0.5) + p.x * 0.4
            hairs.move(to: p)
            hairs.addLine(to: hwp(p.x + cos(tilt) * 0.03, p.y + sin(tilt) * 0.03))
        }
        pen.stroke(hairs, HeadwearColor(hex: 0x2A1E1A, alpha: 0.32 * a), width: 0.008)
    }

    private func drawScar(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let a = HeadwearEase.smoothstep((f.seen - 0.5) / 0.4)
        guard a > 0.01 else { return }
        let path = HeadwearShape.smooth([hwp(0.58, -0.3), hwp(0.7, -0.46), hwp(0.82, -0.6), hwp(0.9, -0.78)], closed: false)
        pen.stroke(path, HeadwearColor(hex: 0xF4B3AE, alpha: 0.55 * a), width: 0.07)
        pen.stroke(path, HeadwearColor(hex: 0xB04A52, alpha: 0.95 * a), width: 0.035)
        for (x, y) in [(0.62, -0.35), (0.7, -0.46), (0.78, -0.57), (0.85, -0.69)] {
            pen.line(hwp(x - 0.05, y - 0.025), hwp(x + 0.05, y + 0.03), HeadwearColor(hex: 0x4E1A22, alpha: 0.8 * a), width: 0.02)
        }
    }

    private func drawPatch(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let appear = HeadwearEase.pop(f.seen, delay: 0.3, duration: 0.4)
        guard appear > 0.001 else { return }
        let eye = hwp(-0.5, 0.0)
        let ink = HeadwearColor(hex: 0x050507)
        // Straps first, so the patch sits over them.
        pen.line(hwp(-0.38, 0.2), hwp(0.7, 1.0), ink, width: 0.06 * appear)
        pen.line(hwp(-0.78, 0.02), hwp(-1.14, 0.2), ink, width: 0.06 * appear)
        pen.placed(at: eye, turn: -0.2, scale: appear) {
            let patch = HeadwearShape.smooth([hwp(-0.3, 0.02), hwp(-0.2, 0.2), hwp(0.05, 0.28), hwp(0.27, 0.15), hwp(0.31, -0.06), hwp(0.2, -0.24), hwp(-0.05, -0.28), hwp(-0.24, -0.2)])
            pen.paintRound(patch, center: hwp(-0.08, 0.1), radius: 0.5, [HeadwearColor(hex: 0x3A3A46), HeadwearColor(hex: 0x15151B), HeadwearColor(hex: 0x050507)],
                           ink: ink, inkWidth: 0.03)
            pen.stroke(HeadwearShape.smooth([hwp(-0.18, 0.12), hwp(-0.06, 0.2), hwp(0.1, 0.2)], closed: false), HeadwearColor(1, 1, 1, 0.3), width: 0.03)
        }
    }

    private func drawEarring(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let appear = HeadwearEase.drop(f.seen, delay: 0.4, height: 1.2, duration: 0.6)
        let hook = hwp(f.head.side(1.16), -0.42 + appear)
        let a = hoop.x
        let r = 0.125
        let centre = hwp(hook.x + sin(a) * (r + 0.02), hook.y - cos(a) * (r + 0.02))
        let ring = HeadwearShape.ellipse(centre, rx: r, ry: r)
        pen.stroke(ring, HeadwearColor(hex: 0x7A5412), width: 0.07)
        pen.stroke(ring, HeadwearColor(hex: 0xFFD24A), width: 0.045)
        pen.stroke(HeadwearShape.smooth([hwp(centre.x - r * 0.7, centre.y + r * 0.7), hwp(centre.x - r, centre.y), hwp(centre.x - r * 0.7, centre.y - r * 0.7)], closed: false),
                   HeadwearColor(1, 0.97, 0.8, 0.9), width: 0.018)
        pen.dot(at: hook, radius: 0.025, HeadwearColor(hex: 0xC48A16))
    }

    private func drawHat(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 2.8, duration: 0.75)
        pen.placed(at: hwp(0, fall + f.head.up(1.1) - 1.1)) {
            let ink = HeadwearColor(hex: 0x050507)
            let gold = HeadwearColor(hex: 0xEDBA3C)
            // The whole hat, with its turned-up brim.
            let hat = CGMutablePath()
            hat.move(to: hwp(-1.78, 1.38))
            hat.addQuadCurve(to: hwp(-0.55, 2.16), control: hwp(-1.5, 2.0))
            hat.addQuadCurve(to: hwp(0.55, 2.16), control: hwp(0, 2.36))
            hat.addQuadCurve(to: hwp(1.78, 1.38), control: hwp(1.5, 2.0))
            hat.addQuadCurve(to: hwp(0.98, 0.96), control: hwp(1.36, 0.98))
            hat.addQuadCurve(to: hwp(-0.98, 0.96), control: hwp(0, 0.74))
            hat.addQuadCurve(to: hwp(-1.78, 1.38), control: hwp(-1.36, 0.98))
            hat.closeSubpath()
            pen.glow(at: hwp(0, 0.85), radius: 1.0, HeadwearColor(0, 0, 0.1, 0.22))
            pen.paint(hat, [HeadwearColor(hex: 0x363441), HeadwearColor(hex: 0x15141C), HeadwearColor(hex: 0x09090D)], ink: ink, inkWidth: 0.05)
            // The folded-up front panel, edged in gold.
            let panel = CGMutablePath()
            panel.move(to: hwp(-1.02, 0.98))
            panel.addQuadCurve(to: hwp(-0.66, 1.9), control: hwp(-1.0, 1.55))
            panel.addQuadCurve(to: hwp(0.66, 1.9), control: hwp(0, 2.12))
            panel.addQuadCurve(to: hwp(1.02, 0.98), control: hwp(1.0, 1.55))
            panel.addQuadCurve(to: hwp(-1.02, 0.98), control: hwp(0, 0.78))
            panel.closeSubpath()
            pen.paint(panel, [HeadwearColor(hex: 0x403E4E), HeadwearColor(hex: 0x1A1923)], ink: nil)
            pen.stroke(panel, ink, width: 0.1)
            pen.stroke(panel, gold, width: 0.055)
            drawSkull(pen, at: hwp(0, 1.47))
        }
    }

    private func drawSkull(_ pen: HeadwearPen, at c: CGPoint) {
        let bone = [HeadwearColor.white, HeadwearColor(hex: 0xE2DACB)]
        let edge = HeadwearColor(hex: 0x4A4438)
        pen.placed(at: c) {
            // Crossbones.
            for dir in [-1.0, 1.0] {
                let a = hwp(-0.55, -0.3 * dir), b = hwp(0.55, 0.3 * dir)
                pen.line(a, b, edge, width: 0.14)
                pen.line(a, b, bone[0], width: 0.09)
                for end in [a, b] {
                    for k in [-1.0, 1.0] {
                        let knob = HeadwearShape.ellipse(hwp(end.x + (end.x < 0 ? -0.02 : 0.02), end.y + k * 0.07), rx: 0.075, ry: 0.075)
                        pen.paint(knob, bone, ink: edge, inkWidth: 0.025)
                    }
                }
            }
            for dir in [-1.0, 1.0] {
                let a = hwp(-0.45, -0.24 * dir), b = hwp(0.45, 0.24 * dir)
                pen.line(a, b, bone[0], width: 0.085)
            }
            // The skull.
            let skull = HeadwearShape.smooth([hwp(-0.27, 0.02), hwp(-0.25, 0.2), hwp(-0.1, 0.32), hwp(0.1, 0.32), hwp(0.25, 0.2), hwp(0.27, 0.02),
                                             hwp(0.18, -0.1), hwp(0.17, -0.22), hwp(0.08, -0.26), hwp(-0.08, -0.26), hwp(-0.17, -0.22), hwp(-0.18, -0.1)])
            pen.paint(skull, bone, ink: edge, inkWidth: 0.03)
            for side in [-1.0, 1.0] {
                pen.fill(HeadwearShape.ellipse(hwp(side * 0.105, 0.04), rx: 0.075, ry: 0.085), HeadwearColor(hex: 0x14110E))
            }
            pen.fill(HeadwearShape.polygon([hwp(0, -0.04), hwp(-0.035, -0.11), hwp(0.035, -0.11)]), HeadwearColor(hex: 0x14110E))
            for x in [-0.09, -0.03, 0.03, 0.09] { pen.line(hwp(x, -0.17), hwp(x, -0.25), edge, width: 0.02) }
        }
    }
}

// MARK: - Clown

/// A clown: a rainbow curly wig, a big red nose that squeaks when you blink, and face-paint dots.
final class HeadwearClown: HeadwearCostume {
    let hint = "Blink to squeak the nose"

    private var squash = HeadwearSwing(omega: 17, damping: 0.2, gain: 0, limit: 1.2)
    private var wig = HeadwearSwing(omega: 9, damping: 0.18, gain: 0.04, limit: 0.4)
    private var sinceSqueak = 10.0
    private var lastSqueak = -10.0

    /// How often the nose has squeaked.
    private(set) var squeaks = 0
    /// How squashed the nose is, 0 for round up to 1 flat.
    var squashed: Double { max(0, squash.x) }

    func reset() { squash.reset(); wig.reset(); sinceSqueak = 10; squeaks = 0; lastSqueak = -10 }

    func advance(_ f: HeadwearFrame) {
        wig.step(dt: f.dt, accel: f.accel.x, rest: 0)
        sinceSqueak += f.dt
        // One squeak per blink; a quick second blink right after is part of the same one.
        if f.signals.blinkGate.rose && f.clock - lastSqueak > 0.25 {
            lastSqueak = f.clock
            squeaks += 1
            sinceSqueak = 0
            squash.x = 1
            squash.v = 0
        }
        squash.step(dt: f.dt, accel: 0, rest: 0)
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            drawWig(pen, f)
            drawPaint(pen, f)
            drawNose(pen, f)
        }
    }

    private func drawWig(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 2.4, duration: 0.7)
        let centre = hwp(0, f.head.up(0.28) + fall)
        // Two rows of curls round the top of the head, outer then inner, rainbow from one ear to the other.
        let rows: [(count: Int, rx: Double, ry: Double, from: Double, to: Double, size: Double)] = [
            (13, 1.42, 1.3, 205, -25, 0.36), (9, 1.08, 1.04, 172, 8, 0.32), (5, 0.72, 0.9, 140, 40, 0.28)]
        var n = 0
        for (r, row) in rows.enumerated() {
            for i in 0..<row.count {
                let u = Double(i) / Double(row.count - 1)
                let deg = row.from + (row.to - row.from) * u
                let a = deg * .pi / 180
                let hue = (0.92 * u + Double(r) * 0.07).truncatingRemainder(dividingBy: 1)
                let bounce = 0.025
                let pos = hwp(centre.x + cos(a) * row.rx + bounce * sin(f.clock * 3 + Double(n)) + wig.x * 0.2 * u,
                              centre.y + sin(a) * row.ry + bounce * cos(f.clock * 2.6 + Double(n) * 1.3))
                let grow = HeadwearEase.pop(f.seen, delay: 0.1 + 0.03 * Double(n % 9), duration: 0.45)
                let size = row.size * (0.88 + 0.24 * HeadwearNoise.unit(n, 61)) * f.head.wide
                drawCurl(pen, at: pos, radius: size * grow, hue: hue, turn: Double(n) * 0.9, shade: Double(2 - r) * 0.05)
                n += 1
            }
        }
    }

    /// A soft rainbow, coral round to pink, with no raw primaries in it.
    private static let rainbow = [HeadwearColor(hex: 0xFF6B6B), HeadwearColor(hex: 0xFF9F4A), HeadwearColor(hex: 0xFFD166), HeadwearColor(hex: 0x7ED68C),
                                  HeadwearColor(hex: 0x4FB8E8), HeadwearColor(hex: 0x8C7CF0), HeadwearColor(hex: 0xF27BBD)]

    private static func rainbowColor(_ hue: Double) -> HeadwearColor {
        let x = (hue - floor(hue)) * Double(rainbow.count)
        let i = Int(x) % rainbow.count
        return rainbow[i].mixed(with: rainbow[(i + 1) % rainbow.count], x - floor(x))
    }

    /// How many steps round the rainbow the curls are painted in, each painted once and kept.
    private static let hueSteps = 28
    private static let curlSize = 0.32

    private func drawCurl(_ pen: HeadwearPen, at c: CGPoint, radius r: Double, hue: Double, turn: Double, shade: Double) {
        guard r > 0.01 else { return }
        let step = Int((hue - floor(hue)) * Double(Self.hueSteps)) % Self.hueSteps
        let variant = Int(turn * 10) % 2
        let k = r / Self.curlSize
        pen.placed(at: c, scale: k) {
            let size = Self.curlSize
            pen.sprite("clown-curl-\(step)-\(variant)", window: CGRect(x: -size * 1.15, y: -size * 1.15, width: size * 2.3, height: size * 2.3),
                       pixelsPerUnit: pen.pixelsPerUnit) { pen in
                Self.paintCurl(pen, radius: size, base: Self.rainbowColor(Double(step) / Double(Self.hueSteps)), turn: Double(variant) * .pi)
            }
            if shade > 0.001 { pen.fill(HeadwearShape.ellipse(.zero, rx: size, ry: size), HeadwearColor(0.1, 0.02, 0.15, shade)) }
        }
    }

    private static func paintCurl(_ pen: HeadwearPen, radius r: Double, base: HeadwearColor, turn: Double) {
        let disc = HeadwearShape.ellipse(.zero, rx: r, ry: r)
        pen.paintRound(disc, center: hwp(-r * 0.3, r * 0.35), radius: r * 1.6, [base.lighter(0.4), base, base.darker(0.28)],
                       ink: base.darker(0.55), inkWidth: 0.035)
        // A little spiral in each curl.
        var spiral: [CGPoint] = []
        for k in 0...16 {
            let t = Double(k) / 16
            let a = turn + t * 4.4 * .pi
            spiral.append(hwp(cos(a) * r * 0.7 * (1 - t * 0.85), sin(a) * r * 0.7 * (1 - t * 0.85)))
        }
        pen.stroke(HeadwearShape.smooth(spiral, closed: false), base.darker(0.4).faded(0.55), width: 0.03)
        pen.fill(HeadwearShape.ellipse(hwp(-r * 0.38, r * 0.42), rx: r * 0.2, ry: r * 0.11, turn: 0.7), HeadwearColor(1, 1, 1, 0.5))
    }

    private func drawPaint(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let a = HeadwearEase.pop(f.seen, delay: 0.4, duration: 0.4)
        guard a > 0.001 else { return }
        let cheekY = f.nose.y - 0.05
        for side in [-1.0, 1.0] {
            // Round red cheeks.
            pen.placed(at: hwp(side * 0.74, cheekY), scale: a) {
                let dot = HeadwearShape.ellipse(hwp(0, 0), rx: 0.13, ry: 0.13)
                pen.paintRound(dot, center: hwp(-0.04, 0.04), radius: 0.2, [HeadwearColor(hex: 0xFF6B78), HeadwearColor(hex: 0xE02030)], ink: HeadwearColor(hex: 0x9A1020), inkWidth: 0.025)
                pen.fill(HeadwearShape.ellipse(hwp(-0.05, 0.05), rx: 0.03, ry: 0.02, turn: 0.6), HeadwearColor(1, 1, 1, 0.6))
            }
            // Blue diamonds at the temples, with a pair of white dots.
            pen.placed(at: hwp(side * 1.0, 0.18), scale: a) {
                let diamond = HeadwearShape.smooth([hwp(0, 0.17), hwp(0.09, 0), hwp(0, -0.17), hwp(-0.09, 0)], smoothness: 0.25)
                pen.paint(diamond, [HeadwearColor(hex: 0x4D8BFF), HeadwearColor(hex: 0x2B55D0)], ink: HeadwearColor(hex: 0x1A2E8A), inkWidth: 0.025)
                pen.dot(at: hwp(0, 0.28), radius: 0.03, HeadwearColor.white)
                pen.dot(at: hwp(0, -0.28), radius: 0.03, HeadwearColor.white)
            }
            // Three little dots under each eye.
            for (k, colour) in [HeadwearColor(hex: 0xFFD83A), HeadwearColor(hex: 0x37C86A), HeadwearColor(hex: 0x4D8BFF)].enumerated() {
                let x = side * 0.5 + (Double(k) - 1) * 0.15
                pen.dot(at: hwp(x, -0.27 - 0.03 * (1 - abs(Double(k) - 1))), radius: 0.04 * a, colour)
            }
        }
    }

    private func drawNose(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let appear = HeadwearEase.pop(f.seen, delay: 0.5, duration: 0.4)
        guard appear > 0.001 else { return }
        let q = squashed
        let c = hwp(f.nose.x, f.nose.y + 0.02)
        let r = 0.25
        pen.placed(at: c, stretch: CGSize(width: (1 + 0.32 * q) * appear, height: (1 - 0.3 * q) * appear)) {
            let ball = HeadwearShape.ellipse(hwp(0, 0), rx: r, ry: r)
            pen.glow(at: hwp(0, -0.04), radius: 0.4, HeadwearColor(0.6, 0, 0.05, 0.25))
            pen.paintRound(ball, center: hwp(-0.08, 0.09), radius: 0.46, [HeadwearColor(hex: 0xFF8C80), HeadwearColor(hex: 0xEE2430), HeadwearColor(hex: 0x9E0F1A)],
                           ink: HeadwearColor(hex: 0x6A0810), inkWidth: 0.035)
            pen.fill(HeadwearShape.ellipse(hwp(-0.09, 0.1), rx: 0.08, ry: 0.045, turn: 0.6), HeadwearColor(1, 1, 1, 0.8))
        }
        // Squeak marks fly off the nose for a moment after each blink.
        if sinceSqueak < 0.4 {
            let t = sinceSqueak / 0.4
            for k in 0..<5 {
                let a = .pi / 2 + (Double(k) - 2) * 0.55
                let from = 0.34 + 0.2 * t, to = from + 0.16
                pen.line(hwp(c.x + cos(a) * from, c.y + sin(a) * from * 0.9), hwp(c.x + cos(a) * to, c.y + sin(a) * to * 0.9),
                         HeadwearColor(hex: 0xFFF0A0, alpha: 1 - t), width: 0.04)
            }
        }
    }
}
