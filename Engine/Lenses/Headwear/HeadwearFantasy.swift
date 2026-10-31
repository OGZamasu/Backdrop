import AppKit
import CoreGraphics
import Foundation

// MARK: - Devil

/// A little devil: curved red horns, a pointed goatee and a villain's moustache, and a faint ember glow.
/// Smile and the horns blaze and the grin lights up.
final class HeadwearDevil: HeadwearCostume {
    let hint = "Smile to make your horns glow"

    private var horns = [HeadwearSwing(omega: 15, damping: 0.22, gain: 0.02, limit: 0.3), HeadwearSwing(omega: 13, damping: 0.24, gain: 0.02, limit: 0.3)]
    /// How bright the horns are, 0.3 at rest up to 1 while smiling.
    private(set) var hornGlow = 0.3

    func reset() { horns[0].reset(); horns[1].reset(); hornGlow = 0.3 }

    func advance(_ f: HeadwearFrame) {
        hornGlow = 0.3 + 0.7 * f.signals.grin
        for i in 0..<2 { horns[i].step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.1) }
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            let appear = HeadwearEase.smoothstep(f.seen / 0.5)
            drawEmbers(pen, f, appear)
            drawGoatee(pen, f, appear)
            drawMoustache(pen, f, appear)
            drawGrin(pen, f, appear)
            for (i, side) in [-1.0, 1.0].enumerated() { drawHorn(pen, f, side: side, wobble: horns[i].x, index: i) }
        }
    }

    /// The right-hand horn at rest, rooted at the origin; the left is its mirror image.
    private static func hornSpine() -> [CGPoint] {
        HeadwearShape.spine(from: .zero, length: 1.32, steps: 18) { t in .pi / 2 - (0.62 - 1.35 * pow(t, 1.2)) }
    }
    private static func hornWidth(_ t: Double) -> Double { 0.27 * pow(1 - t, 0.85) + 0.004 }
    private static let hornShape = HeadwearShape.ribbon(hornSpine(), tip: 0.2, base: 0.4, width: hornWidth)

    /// The horn's ridges and shine, painted once.
    private static func paintHorn(_ pen: HeadwearPen) {
        let spine = hornSpine()
        func heading(_ t: Double) -> Double { .pi / 2 - (0.62 - 1.35 * pow(t, 1.2)) }
        pen.paint(hornShape, [HeadwearColor(hex: 0xFFA04A), HeadwearColor(hex: 0xE5322D), HeadwearColor(hex: 0xA0141F), HeadwearColor(hex: 0x5E0A14)],
                  ink: HeadwearColor(hex: 0x3F0610), inkWidth: 0.05)
        pen.clipped(to: hornShape) {
            for k in 1...4 {
                let t = Double(k) * 0.19
                let i = Int(t * Double(spine.count - 1))
                let p = spine[i], w = hornWidth(t) * 1.2
                let a = heading(t) + .pi / 2
                let bow = CGMutablePath()
                bow.move(to: hwp(p.x + cos(a) * w, p.y + sin(a) * w))
                bow.addQuadCurve(to: hwp(p.x - cos(a) * w, p.y - sin(a) * w), control: hwp(p.x + cos(heading(t)) * 0.06, p.y + sin(heading(t)) * 0.06))
                pen.stroke(bow, HeadwearColor(hex: 0x4A0812, alpha: 0.45), width: 0.028)
            }
            let shine = spine.enumerated().prefix(13).map { i, p -> CGPoint in
                let t = Double(i) / Double(spine.count - 1), a = heading(t) + .pi / 2
                return hwp(p.x - cos(a) * hornWidth(t) * 0.4, p.y - sin(a) * hornWidth(t) * 0.4)
            }
            pen.stroke(HeadwearShape.smooth(shine, closed: false), HeadwearColor(1, 0.85, 0.7, 0.4), width: 0.035)
        }
    }

    private func drawHorn(_ pen: HeadwearPen, _ f: HeadwearFrame, side: Double, wobble: Double, index: Int) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.08 + 0.1 * Double(index), duration: 0.55)
        guard grow > 0.001 else { return }
        let lit = (hornGlow - 0.3) / 0.7
        let tip = Self.hornSpine().last ?? hwp(0, 1)
        pen.placed(at: f.head.at(side * 0.6, 0.98), turn: -wobble * 0.6, stretch: CGSize(width: side * grow, height: grow)) {
            // The glow comes first so the horn sits in it; when lit, the whole horn brightens from within.
            pen.glow(at: tip, radius: 0.35 + 0.5 * hornGlow, HeadwearColor(1, 0.45, 0.1, 0.2 + 0.45 * hornGlow), additive: true)
            if lit > 0.02 { pen.glow(at: hwp(0.4, 0.75), radius: 0.7 * lit, HeadwearColor(1, 0.3, 0.1, 0.3 * lit), additive: true) }
            pen.sprite("devil-horn", window: CGRect(x: -0.4, y: -0.25, width: 1.3, height: 1.55), pixelsPerUnit: f.io) { Self.paintHorn($0) }
            if lit > 0.02 {
                pen.ctx.saveGState()
                pen.ctx.setBlendMode(.plusLighter)
                pen.fill(Self.hornShape, HeadwearColor(1, 0.45, 0.12, 0.38 * lit))
                pen.ctx.restoreGState()
            }
        }
    }

    private func drawGoatee(_ pen: HeadwearPen, _ f: HeadwearFrame, _ appear: Double) {
        guard appear > 0.01 else { return }
        let top = f.lowerLipY - 0.12
        let tipY = f.chinY - 0.1
        let h = top - tipY
        let pts: [CGPoint] = [hwp(f.mouth.x - 0.24, top), hwp(f.mouth.x - 0.23, top - h * 0.3), hwp(f.mouth.x - 0.15, top - h * 0.62),
                              hwp(f.mouth.x - 0.03, tipY + 0.03), hwp(f.mouth.x, tipY), hwp(f.mouth.x + 0.03, tipY + 0.03),
                              hwp(f.mouth.x + 0.15, top - h * 0.62), hwp(f.mouth.x + 0.23, top - h * 0.3), hwp(f.mouth.x + 0.24, top)]
        let shape = HeadwearShape.smooth(pts)
        pen.placed(at: hwp(f.mouth.x, top), stretch: CGSize(width: 1, height: appear)) {
            pen.ctx.translateBy(x: -f.mouth.x, y: -top)
            pen.paint(shape, [HeadwearColor(hex: 0x5A2638), HeadwearColor(hex: 0x2A0F1C), HeadwearColor(hex: 0x12060D)], ink: HeadwearColor(hex: 0x0A0408), inkWidth: 0.025,
                      direction: CGVector(dx: 0.4, dy: -1))
            pen.clipped(to: shape) {
                // Strands combed down to the point, and a sheen on the side toward the light.
                for k in -3...3 {
                    let x0 = f.mouth.x + Double(k) * 0.065
                    pen.stroke(HeadwearShape.smooth([hwp(x0, top + 0.02), hwp(x0 * 0.7 + f.mouth.x * 0.3, top - h * 0.5), hwp(f.mouth.x + Double(k) * 0.008, tipY + 0.02)], closed: false),
                               HeadwearColor(hex: 0x0A0408, alpha: 0.45), width: 0.014)
                }
                pen.stroke(HeadwearShape.smooth([hwp(f.mouth.x - 0.13, top - 0.04), hwp(f.mouth.x - 0.1, top - h * 0.45), hwp(f.mouth.x - 0.025, tipY + 0.07)], closed: false),
                           HeadwearColor(1, 0.6, 0.7, 0.3), width: 0.035)
            }
        }
    }

    private func drawMoustache(_ pen: HeadwearPen, _ f: HeadwearFrame, _ appear: Double) {
        guard appear > 0.01 else { return }
        let y = f.nose.y - (f.nose.y - f.upperLipY) * 0.62
        let style = HeadwearFacialHair.Moustache(colors: [HeadwearColor(hex: 0x3D1829), HeadwearColor(hex: 0x12060D)], ink: nil,
                                                 reach: 0.72, thickness: 0.07, drop: 0.12, curl: 1.9, curlStart: 0.4,
                                                 highlight: HeadwearColor(1, 0.5, 0.6, 0.25))
        HeadwearFacialHair.moustache(pen, at: hwp(f.mouth.x, y), style, lift: 0.15 * f.signals.grin, scale: appear)
    }

    /// The smile, lit from inside.
    private func drawGrin(_ pen: HeadwearPen, _ f: HeadwearFrame, _ appear: Double) {
        let g = f.signals.grin * appear
        let half = f.mouthWidth / 2
        for side in [-1.0, 1.0] {
            pen.glow(at: hwp(f.mouth.x + side * half, f.mouth.y + 0.02), radius: 0.32, HeadwearColor(1, 0.25, 0.08, (0.05 + 0.45 * g) * appear), additive: true)
        }
        guard g > 0.02 else { return }
        pen.glow(at: hwp(f.mouth.x, f.mouth.y - 0.04), radius: half + 0.25, HeadwearColor(1, 0.4, 0.12, 0.22 * g), additive: true)
    }

    /// Sparks that rise from the horns and fade. Worked out from the clock, so there is nothing to keep.
    private func drawEmbers(_ pen: HeadwearPen, _ f: HeadwearFrame, _ appear: Double) {
        for k in 0..<12 {
            let speed = 0.28 + 0.3 * HeadwearNoise.unit(k, 1)
            let phase = (f.clock * speed + HeadwearNoise.unit(k, 2)).truncatingRemainder(dividingBy: 1)
            let x = (HeadwearNoise.unit(k, 3) - 0.5) * 2.7 + 0.18 * sin(f.clock * 1.3 + Double(k))
            let y = 0.4 + HeadwearNoise.unit(k, 4) * 1.4 + phase * 1.7
            let fade = sin(phase * .pi) * appear * appear
            let r = (0.025 + 0.03 * HeadwearNoise.unit(k, 5)) * (1 - 0.4 * phase)
            pen.glow(at: hwp(x, y), radius: r * 4, HeadwearColor(1, 0.4, 0.08, 0.5 * fade * (0.5 + 0.5 * hornGlow)), additive: true)
            pen.fill(HeadwearShape.ellipse(hwp(x, y), rx: r, ry: r), HeadwearColor(1, 0.8, 0.4, 0.95 * fade))
        }
    }
}

// MARK: - Angel

/// An angel: a golden halo that bobs and sparkles, soft wings behind your shoulders and a warm glow.
/// Smile and the wings flutter.
final class HeadwearAngel: HeadwearCostume {
    let hint = "Smile and your wings flutter"
    let hasBackLayer = true

    private var halo = HeadwearSwing(omega: 7, damping: 0.18, gain: 0.04, limit: 0.5)
    private var flutter = 0.0
    /// How hard the wings are beating, 0 for a lazy sway to 1.
    private(set) var flapping = 0.0

    func reset() { halo.reset(); flutter = 0; flapping = 0 }

    func advance(_ f: HeadwearFrame) {
        halo.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.15)
        flapping = f.signals.grin
        flutter += f.dt * (2.2 + 9 * flapping)
    }

    /// How much of the wings' full spread fits in the picture beside this head, 0...1.
    static func room(_ f: HeadwearFrame) -> Double {
        let needed = 3.9 * f.io
        let side = min(Double(f.center.x) - Double(f.bounds.minX), Double(f.bounds.maxX) - Double(f.center.x))
        return min(1, max(0, side / needed))
    }

    func drawBack(_ pen: HeadwearPen, _ f: HeadwearFrame, behindPerson: Bool) {
        let appear = HeadwearEase.smoothstep((f.seen - 0.15) / 0.5)
        let room = Self.room(f)
        // Without room they get smaller, then fade away, rather than being cut off by the edge.
        let spread = max(0.55, room)
        let fade = HeadwearEase.smoothstep((room - 0.2) / 0.3)
        f.inFace(pen.ctx) {
            if behindPerson {
                pen.glow(at: hwp(0, 0.3), radius: 2.0, HeadwearColor(1, 0.93, 0.6, 0.55 * appear))
            }
            for side in [-1.0, 1.0] { drawWing(pen, f, side: side, spread: spread, alpha: appear * fade) }
        }
    }

    /// Where a wing joins the body, in face units.
    private static let joint = hwp(0.85, -1.55)

    /// One wing, painted once and kept (about 130 pixels to an eye-spacing, from the shoulder up and out), then stamped each frame:
    /// 30 feathers is too much to draw 30 times a second.
    private static let wingLock = NSLock()
    private static var wingImage: CGImage?
    private static let wingScale = 130.0, wingWindow = CGRect(x: -0.45, y: -0.45, width: 3.5, height: 3.5)

    private static func wing() -> CGImage? {
        wingLock.lock(); defer { wingLock.unlock() }
        if let wingImage { return wingImage }
        let side = Int(wingWindow.width * wingScale)
        guard let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: Sprites.bitmapInfo) else { return nil }
        c.setAllowsAntialiasing(true)
        c.interpolationQuality = .high
        c.scaleBy(x: wingScale, y: wingScale)
        c.translateBy(x: -wingWindow.minX, y: -wingWindow.minY)
        let pen = HeadwearPen(ctx: c)
        let ink = HeadwearColor(hex: 0x9DB1DE, alpha: 0.9)
        // Long feathers at the back, then a row of shorter ones in front, then the downy feathers at the shoulder.
        for (row, count, size, first, last) in [(0, 7, 2.8, 0.1, 1.2), (1, 6, 1.8, 0.3, 1.25), (2, 4, 1.0, 0.5, 1.5)] as [(Int, Int, Double, Double, Double)] {
            for i in 0..<count {
                let u = Double(i) / Double(count - 1)
                let angle = first + (last - first) * u
                let length = size * (1 - 0.24 * u)
                func heading(_ t: Double) -> Double { .pi / 2 - (angle - 0.28 * t * t * (row == 0 ? 1.4 : 0.8)) }
                let spine = HeadwearShape.spine(from: hwp(0, 0), length: length, steps: 10, heading: heading)
                let w = row == 0 ? 0.28 : row == 1 ? 0.23 : 0.17
                let shape = HeadwearShape.ribbon(spine, tip: 0.9) { t in w * (0.55 + 0.45 * sin(min(1, t * 1.3 + 0.1) * .pi / 2)) * (1 - 0.35 * pow(t, 3)) }
                pen.paint(shape, [HeadwearColor.white, HeadwearColor(hex: 0xDCE6FF)], ink: ink, inkWidth: 0.03, direction: CGVector(dx: 0.4, dy: -1))
                pen.clipped(to: shape) {
                    let mid = Array(spine.dropFirst(1).dropLast(2))
                    if mid.count > 2 { pen.stroke(HeadwearShape.smooth(mid, closed: false), HeadwearColor(hex: 0xB7C6EA, alpha: 0.5), width: 0.02) }
                }
            }
        }
        wingImage = c.makeImage()
        return wingImage
    }

    private func drawWing(_ pen: HeadwearPen, _ f: HeadwearFrame, side: Double, spread: Double, alpha: Double) {
        guard alpha > 0.01, let image = Self.wing() else { return }
        let flap = (0.1 + 0.16 * flapping) * sin(flutter + (side < 0 ? 0.3 : 0))
        let unfurl = HeadwearEase.outBack((f.seen - 0.2) / 0.7)
        let size = spread * unfurl
        guard size > 0.01 else { return }
        let joint = hwp(side * Self.joint.x, Self.joint.y)
        pen.ctx.saveGState()
        pen.ctx.translateBy(x: joint.x, y: joint.y)
        // Turned a little about the shoulder with each beat; the left wing is the right one mirrored.
        pen.ctx.rotate(by: CGFloat(-side * flap))
        pen.ctx.scaleBy(x: CGFloat(side * size), y: CGFloat(size))
        pen.ctx.setAlpha(CGFloat(alpha))
        pen.ctx.interpolationQuality = .medium
        pen.ctx.draw(image, in: Self.wingWindow)
        pen.ctx.restoreGState()
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            let fall = HeadwearEase.drop(f.seen, height: 2.2, duration: 0.95)
            let bob = 0.05 * sin(f.clock * 2.3)
            let centre = hwp(halo.x * 0.45, f.head.up(1.88) + bob + fall)
            let turn = halo.x * 0.35 + 0.04 * sin(f.clock * 1.4)
            let ring = HeadwearShape.ellipse(hwp(0, 0), rx: 0.74, ry: 0.2)
            let glowing = HeadwearEase.smoothstep((f.seen - 0.1) / 0.4)
            pen.glow(at: centre, radius: 1.5, HeadwearColor(1, 0.85, 0.35, 0.3 * glowing), additive: true)
            pen.placed(at: centre, turn: turn) {
                pen.sprite("angel-halo", window: CGRect(x: -1.0, y: -0.46, width: 2.0, height: 0.92), pixelsPerUnit: f.io) { pen in
                    pen.stroke(ring, HeadwearColor(1, 0.85, 0.35, 0.07), width: 0.4)
                    pen.stroke(ring, HeadwearColor(1, 0.85, 0.35, 0.1), width: 0.3)
                    pen.stroke(ring, HeadwearColor(1, 0.85, 0.35, 0.14), width: 0.22)
                    pen.stroke(ring, HeadwearColor(hex: 0xC9891A), width: 0.15)
                    pen.stroke(ring, HeadwearColor(hex: 0xFFD23C), width: 0.115)
                    pen.placed(at: hwp(0, 0.02)) { pen.stroke(ring, HeadwearColor(hex: 0xFFF4B8, alpha: 0.9), width: 0.04) }
                }
            }
            drawSparkles(pen, f, around: centre)
        }
    }

    private func drawSparkles(_ pen: HeadwearPen, _ f: HeadwearFrame, around c: CGPoint) {
        // A burst when the halo lands, then a quiet twinkle.
        let burst = max(0, 1 - abs(f.seen - 1.0) / 0.6)
        for k in 0..<9 {
            let angle = HeadwearNoise.unit(k, 1) * 2 * .pi
            let dist = 0.75 + 0.55 * HeadwearNoise.unit(k, 2)
            let spot = hwp(c.x + cos(angle) * dist * 1.15, c.y + sin(angle) * dist * 0.9 + 0.1)
            let beat = pow(max(0, sin(f.clock * (1.8 + HeadwearNoise.unit(k, 3)) + HeadwearNoise.unit(k, 4) * 6.28)), 3)
            let size = (0.08 + 0.1 * HeadwearNoise.unit(k, 5)) * (beat + 0.9 * burst)
            guard size > 0.01 else { continue }
            pen.sparkle(at: spot, radius: size, HeadwearColor(1, 0.97, 0.8, 0.95), turn: f.clock * 0.5 + Double(k), additive: true)
            pen.glow(at: spot, radius: size * 2.2, HeadwearColor(1, 0.9, 0.5, 0.35), additive: true)
        }
    }
}

// MARK: - Wizard

/// A wizard: a tall starry hat with a floppy tip and a long white beard, both swaying as you move.
/// The beard grows with the size of your face.
final class HeadwearWizard: HeadwearCostume {
    let hint = "Shake your head to make the beard sway"

    private var tip = HeadwearSwing(omega: 5.5, damping: 0.16, gain: 0.04, limit: 0.9)
    private var beardSwing = HeadwearSwing(omega: 4.4, damping: 0.17, gain: 0.06, limit: 0.8)

    /// How far the end of the beard is swung to one side, in eye-spacings.
    var beardSway: Double { beardSwing.x }
    /// How long the beard is below the chin, in eye-spacings.
    static let beardLength = 1.9

    func reset() { tip.reset(); beardSwing.reset() }

    func advance(_ f: HeadwearFrame) {
        tip.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 0.2)
        beardSwing.step(dt: f.dt, accel: f.accel.x, rest: f.hang * 1.5)
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) {
            drawBeard(pen, f)
            drawMoustache(pen, f)
            drawHat(pen, f)
        }
    }

    private func drawBeard(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.outBack((f.seen - 0.35) / 0.7)
        let beard = HeadwearFacialHair.Beard(length: Self.beardLength, bulge: 0.25, taper: 1, sway: beardSwing.x,
                                             colors: [HeadwearColor.white, HeadwearColor(hex: 0xF1F2FA), HeadwearColor(hex: 0xD5DAEE)],
                                             ink: HeadwearColor(hex: 0x9298B8), strands: HeadwearColor(hex: 0x8D94BA, alpha: 0.38))
        HeadwearFacialHair.beard(pen, f, beard, grow: grow)
    }

    private func drawMoustache(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.5, duration: 0.4)
        let y = f.nose.y - (f.nose.y - f.upperLipY) * 0.6
        let style = HeadwearFacialHair.Moustache(colors: [HeadwearColor.white, HeadwearColor(hex: 0xE2E6F4)], ink: HeadwearColor(hex: 0x9298B8),
                                                 reach: 0.95, thickness: 0.15, drop: 0.35, curl: 0.9, curlStart: 0.55,
                                                 highlight: HeadwearColor(0.6, 0.65, 0.85, 0.3))
        HeadwearFacialHair.moustache(pen, at: hwp(f.mouth.x, y), style, lift: 0.1 * f.signals.grin, scale: grow)
    }

    private func drawHat(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 3.2, duration: 0.8)
        pen.placed(at: hwp(0, fall + f.head.up(1.0) - 1.0)) {
            let brim = HeadwearShape.ellipse(hwp(0, 1.0), rx: 1.55, ry: 0.28, turn: 0)
            pen.glow(at: hwp(0, 0.88), radius: 0.9, HeadwearColor(0, 0, 0.1, 0.25))
            pen.paint(brim, [HeadwearColor(hex: 0x4A44A8), HeadwearColor(hex: 0x241F66)], ink: HeadwearColor(hex: 0x14114A), inkWidth: 0.05)

            // The cone: it rises from the brim and the top folds over to one side, swinging with the head.
            func heading(_ t: Double) -> Double { .pi / 2 - (0.1 + 3.4 * pow(max(0, t - 0.42), 1.5)) - tip.x * (t * t * 1.3) }
            func width(_ t: Double) -> Double { 0.84 * pow(1 - t, 0.92) + 0.003 }
            let spine = HeadwearShape.spine(from: hwp(0, 1.02), length: 2.45, steps: 22, heading: heading)
            let cone = HeadwearShape.ribbon(spine, tip: 0.3, base: 0.0, width: width)
            pen.paint(cone, [HeadwearColor(hex: 0x5B55C9), HeadwearColor(hex: 0x3A33A0), HeadwearColor(hex: 0x241F70)],
                      ink: HeadwearColor(hex: 0x14114A), inkWidth: 0.05, direction: CGVector(dx: 1, dy: -0.6))
            pen.clipped(to: cone) {
                stars(pen, f, spine: spine, heading: heading, width: width)
                let sheen = spine.prefix(12).enumerated().map { hwp($0.element.x - 0.42 * (1 - Double($0.offset) / 14), $0.element.y) }
                pen.stroke(HeadwearShape.smooth(sheen, closed: false), HeadwearColor(1, 1, 1, 0.16), width: 0.07)
            }

            // The band, hugging the bottom of the cone.
            let band = HeadwearShape.smooth([hwp(-0.86, 1.04), hwp(-0.45, 0.94), hwp(0, 0.91), hwp(0.45, 0.94), hwp(0.86, 1.04),
                                             hwp(0.82, 1.27), hwp(0.42, 1.2), hwp(0, 1.18), hwp(-0.42, 1.2), hwp(-0.82, 1.27)])
            pen.paint(band, [HeadwearColor(hex: 0xF7CF4D), HeadwearColor(hex: 0xC48A16)], ink: HeadwearColor(hex: 0x6E4A0A), inkWidth: 0.035)
            let buckle = HeadwearShape.rounded(CGRect(x: -0.14, y: 0.93, width: 0.28, height: 0.26), radius: 0.04)
            pen.paint(buckle, [HeadwearColor(hex: 0xFFF0A0), HeadwearColor(hex: 0xE4A91F)], ink: HeadwearColor(hex: 0x6E4A0A), inkWidth: 0.03)
            pen.stroke(HeadwearShape.rounded(CGRect(x: -0.07, y: 0.99, width: 0.14, height: 0.14), radius: 0.02), HeadwearColor(hex: 0x6E4A0A), width: 0.03)
        }
    }

    /// Gold stars and a moon sprinkled on the cone, placed by how far up it and how far across.
    private func stars(_ pen: HeadwearPen, _ f: HeadwearFrame, spine: [CGPoint], heading: (Double) -> Double, width: (Double) -> Double) {
        func place(_ t: Double, _ across: Double) -> CGPoint {
            let i = min(spine.count - 1, max(0, Int((t * Double(spine.count - 1)).rounded())))
            let a = heading(t) + .pi / 2
            return hwp(spine[i].x + cos(a) * across * width(t), spine[i].y + sin(a) * across * width(t))
        }
        let gold = HeadwearColor(hex: 0xFFD84A)
        for (k, (t, u, size)) in [(0.16, -0.4, 0.17), (0.3, 0.45, 0.13), (0.42, -0.2, 0.15), (0.56, 0.2, 0.11), (0.7, -0.1, 0.09), (0.22, 0.05, 0.08)].enumerated() {
            let twinkle = 1 + 0.18 * sin(f.clock * 3 + Double(k) * 1.7)
            let p = place(t, u)
            pen.fill(HeadwearShape.star(p, outer: size * twinkle, inner: size * twinkle * 0.42, turn: .pi / 2 + Double(k) * 0.3), gold)
        }
        // A crescent moon.
        let m = place(0.36, -0.55)
        let disc = HeadwearShape.ellipse(m, rx: 0.15, ry: 0.15)
        let bite = CGMutablePath()
        bite.addRect(CGRect(x: m.x - 0.2, y: m.y - 0.2, width: 0.4, height: 0.4))
        bite.addPath(HeadwearShape.ellipse(hwp(m.x + 0.09, m.y + 0.04), rx: 0.14, ry: 0.14))
        pen.clipped(to: disc) { pen.fill(bite, gold, evenOdd: true) }
    }
}
