import CoreGraphics
import Foundation

// Pieces several costumes share: named palettes, animal ears, whiskers, a glint that sweeps across metal, and a small pool of
// floating bits (bubbles, notes, confetti) that live in the picture rather than on the face.

// MARK: - Palettes

/// The colours the costumes are painted in, named so the whole wardrobe stays one family.
enum HeadwearPalette {
    // Gold, for crowns, buckles and trims: a warm highlight, a body and a deep shade, and the ink round it.
    static let goldLight = HeadwearColor(hex: 0xFFF1A8)
    static let gold = HeadwearColor(hex: 0xF4C542)
    static let goldDeep = HeadwearColor(hex: 0xC4861A)
    static let goldInk = HeadwearColor(hex: 0x6E4A0A)
    // Silver and steel.
    static let steelLight = HeadwearColor(hex: 0xF2F5FA)
    static let steel = HeadwearColor(hex: 0xB7C0CE)
    static let steelDeep = HeadwearColor(hex: 0x6C7689)
    static let steelInk = HeadwearColor(hex: 0x2E3442)
    // Pinks for noses and the insides of ears.
    static let pinkLight = HeadwearColor(hex: 0xFFC4D4)
    static let pink = HeadwearColor(hex: 0xF5859F)
    static let pinkInk = HeadwearColor(hex: 0xB04466)
    // A soft near-black with a little violet in it, never pure black.
    static let night = HeadwearColor(hex: 0x1D1924)
    static let nightLight = HeadwearColor(hex: 0x3C3546)
    // White that is never pure white: fur, feathers, cream.
    static let cream = HeadwearColor(hex: 0xFFF8EE)
    static let creamShade = HeadwearColor(hex: 0xE6DCCF)
    // A cool shade for white things, so they read on a white shirt.
    static let whiteInk = HeadwearColor(hex: 0x8E97B5)
}

// MARK: - Ears

enum HeadwearEarStyle {
    case pointed, rounded
}

/// An animal ear standing up from its base at the origin, `height` tall and `width` across at the base.
enum HeadwearEars {
    static func outline(width w: Double, height h: Double, style: HeadwearEarStyle, lean: Double = 0) -> CGPath {
        switch style {
        case .pointed:
            // A leaf-like triangle with a slightly rounded tip and a fuller outer edge.
            return HeadwearShape.smooth([hwp(-w * 0.5, 0), hwp(-w * 0.48, h * 0.3), hwp(-w * 0.26 + lean * 0.4, h * 0.72),
                                         hwp(lean, h), hwp(w * 0.2 + lean * 0.5, h * 0.74), hwp(w * 0.46, h * 0.36), hwp(w * 0.5, 0),
                                         hwp(0, -h * 0.08)], smoothness: 0.8)
        case .rounded:
            return HeadwearShape.smooth([hwp(-w * 0.5, 0), hwp(-w * 0.52, h * 0.5), hwp(-w * 0.3, h * 0.9), hwp(lean * 0.5, h),
                                         hwp(w * 0.3, h * 0.9), hwp(w * 0.52, h * 0.5), hwp(w * 0.5, 0), hwp(0, -h * 0.1)])
        }
    }

    /// Paints a furry ear: outer fur with a light rim on the side toward the light, a darker tip, the inside in `inner`, and
    /// a few tufts of `tuft` fur at its base. `side` is -1 for an ear on the left of the picture, so the light stays top left.
    /// With `bake` (a name for this ear) and `pixelsPerUnit`, the ear is painted once and kept as a picture (see `HeadwearSprites`).
    static func paint(_ pen: HeadwearPen, width w: Double, height h: Double, style: HeadwearEarStyle, side: Double,
                      fur: [HeadwearColor], ink: HeadwearColor, inner: [HeadwearColor]?, tip: HeadwearColor? = nil,
                      tuft: HeadwearColor? = nil, stripes: HeadwearColor? = nil, lean: Double = 0, bake: String? = nil, pixelsPerUnit: Double = 0) {
        if let bake, pixelsPerUnit > 0 {
            let window = CGRect(x: -w * 0.62 - abs(lean), y: -h * 0.16, width: w * 1.24 + 2 * abs(lean), height: h * 1.24)
            pen.sprite("\(bake)-\(side < 0 ? "l" : "r")", window: window, pixelsPerUnit: pixelsPerUnit) { p in
                paint(p, width: w, height: h, style: style, side: side, fur: fur, ink: ink, inner: inner, tip: tip, tuft: tuft, stripes: stripes, lean: lean)
            }
            return
        }
        let outer = outline(width: w, height: h, style: style, lean: lean)
        pen.paint(outer, fur, ink: ink, inkWidth: 0.045, direction: CGVector(dx: 0.35, dy: -1))
        pen.clipped(to: outer) {
            if let tip { pen.fill(HeadwearShape.ellipse(hwp(lean, h * 0.98), rx: w * 0.42, ry: h * 0.36), tip) }
            if let stripes {
                for k in 0..<3 {
                    let y = h * (0.2 + 0.18 * Double(k))
                    let stripe = HeadwearShape.smooth([hwp(w * 0.55, y + 0.05), hwp(w * 0.2, y - 0.01), hwp(w * 0.05, y + 0.02)], closed: false)
                    pen.stroke(stripe, stripes, width: 0.06 - 0.012 * Double(k))
                }
            }
            // Light on the edge facing the top left, shade on the other.
            pen.stroke(outer, HeadwearColor(1, 1, 1, 0.22), width: 0.05)
            pen.placed(at: hwp(-side * 0.025, -0.02)) { pen.stroke(outer, ink.faded(0.25), width: 0.05) }
        }
        if let inner {
            let inside = outline(width: w * 0.56, height: h * 0.7, style: style, lean: lean * 0.7)
            pen.placed(at: hwp(lean * 0.12, h * 0.1)) {
                pen.paint(inside, inner, ink: inner.last?.darker(0.25).faded(0.7), inkWidth: 0.025, direction: CGVector(dx: 0, dy: 1))
            }
        }
        if let tuft {
            // Three soft wisps of fur curling up out of the ear.
            for k in 0..<3 {
                let u = Double(k) / 2 - 0.5
                let spine = HeadwearShape.spine(from: hwp(u * w * 0.36, h * 0.04), length: h * (0.36 - 0.08 * abs(u)), steps: 6) { t in
                    .pi / 2 - u * 0.9 + 0.5 * t * (u == 0 ? -1 : u)
                }
                pen.fill(HeadwearShape.ribbon(spine, tip: 0.6, base: 0.3) { t in 0.035 * (1 - t) + 0.004 }, tuft)
            }
        }
    }
}

// MARK: - Fur

enum HeadwearFur {
    /// A ruff of fur sticking out from the cheek: five tapered locks fanning outward and down from `root`, darker at the root and
    /// lighter at the tips. `side` is -1 for the left cheek.
    /// `bake` names the ruff so it is painted once and kept; `sway` then turns it as a whole.
    static func ruff(_ pen: HeadwearPen, at root: CGPoint, side: Double, scale: Double, colors: [HeadwearColor], ink: HeadwearColor,
                     sway: Double = 0, stripes: HeadwearColor? = nil, bake: String? = nil, pixelsPerUnit: Double = 0) {
        guard scale > 0.01 else { return }
        if let bake, pixelsPerUnit > 0 {
            pen.placed(at: root, turn: sway * side * 0.5, stretch: CGSize(width: side * scale, height: scale)) {
                pen.sprite(bake, window: CGRect(x: -0.3, y: -0.8, width: 0.95, height: 1.32), pixelsPerUnit: pixelsPerUnit) { p in
                    ruff(p, at: .zero, side: 1, scale: 1, colors: colors, ink: ink, stripes: stripes)
                }
            }
            return
        }
        let locks: [(y: Double, a: Double, length: Double)] = [(0.16, 0.5, 0.32), (0.02, 0.08, 0.4), (-0.13, -0.3, 0.4), (-0.27, -0.72, 0.32)]
        pen.placed(at: root, stretch: CGSize(width: side * scale, height: scale)) {
            for (k, l) in locks.enumerated() {
                let spine = HeadwearShape.spine(from: hwp(-0.1, l.y), length: l.length, steps: 8) { t in l.a - 0.75 * t * t + sway * t }
                let shape = HeadwearShape.ribbon(spine, tip: 0.45, base: 0.5) { t in 0.14 * pow(1 - t, 0.8) * (0.75 + 0.25 * sin(min(1, t * 2.5) * .pi / 2)) + 0.004 }
                pen.paint(shape, colors, ink: ink, inkWidth: 0.022, direction: CGVector(dx: cos(l.a - 0.25), dy: sin(l.a - 0.25)))
                pen.clipped(to: shape) {
                    if let stripes, k % 2 == 1 { pen.stroke(HeadwearShape.smooth(Array(spine.prefix(4)), closed: false), stripes, width: 0.05) }
                    pen.stroke(HeadwearShape.smooth(spine.dropFirst(2).map { hwp($0.x, $0.y + 0.025) }, closed: false), HeadwearColor(1, 1, 1, 0.35), width: 0.02)
                }
            }
        }
    }
}

// MARK: - Whiskers

enum HeadwearWhiskers {
    /// Three tapered whiskers a side from beside the nose. `lift` turns them up (a smile), `spread` fans them apart.
    static func draw(_ pen: HeadwearPen, nose: CGPoint, length: Double, color: HeadwearColor, edge: HeadwearColor?,
                     lift: Double = 0, spread: Double = 0, clock: Double = 0, reveal: Double = 1) {
        guard reveal > 0.01 else { return }
        for side in [-1.0, 1.0] {
            for i in 0..<3 {
                let fan = (Double(i) - 1) * (0.2 + 0.1 * spread)
                let wag = 0.025 * sin(clock * 2.1 + Double(i) * 1.3 + side)
                let angle = fan + 0.1 + lift * 0.25 + wag
                let root = hwp(nose.x + side * 0.24, nose.y - 0.12 - Double(i) * 0.05)
                let spine = HeadwearShape.spine(from: root, length: length * reveal * (1 - 0.1 * abs(Double(i) - 1)), steps: 8) { t in
                    let a = angle - 0.35 * t * t
                    return side > 0 ? a : .pi - a
                }
                let shape = HeadwearShape.ribbon(spine, tip: 0.6) { t in 0.017 * (1 - t) + 0.004 }
                if let edge { pen.stroke(shape, edge.scaled(reveal), width: 0.022) }
                pen.fill(shape, color.scaled(reveal))
            }
            for k in 0..<3 {
                pen.dot(at: hwp(nose.x + side * (0.2 + 0.06 * Double(k)), nose.y - 0.11 - 0.05 * Double(k % 2)), radius: 0.018,
                        color.faded(0.6 * reveal))
            }
        }
    }
}

// MARK: - Glint

enum HeadwearGlint {
    /// How far a glint is across, 0...1, every `period` seconds, or nil between glints.
    static func phase(_ clock: Double, period: Double = 4.2, offset: Double = 0, length: Double = 0.75) -> Double? {
        let p = (clock + offset).truncatingRemainder(dividingBy: period) / length
        return p >= 0 && p < 1 ? p : nil
    }

    /// A soft diagonal band of light crossing `box`, clipped to `shape`.
    static func sweep(_ pen: HeadwearPen, over shape: CGPath, box: CGRect, phase t: Double, strength: Double = 0.55) {
        let x = box.minX - box.height * 0.6 + (box.width + box.height * 1.2) * HeadwearEase.smoothstep(t)
        let fade = sin(t * .pi) * strength
        pen.clipped(to: shape) {
            pen.ctx.saveGState()
            pen.ctx.setBlendMode(.plusLighter)
            pen.fill(HeadwearShape.polygon([hwp(x, box.maxY), hwp(x + box.height * 0.22, box.maxY),
                                            hwp(x - box.height * 0.38, box.minY), hwp(x - box.height * 0.6, box.minY)]), HeadwearColor(1, 0.98, 0.9, fade))
            pen.fill(HeadwearShape.polygon([hwp(x + box.height * 0.3, box.maxY), hwp(x + box.height * 0.36, box.maxY),
                                            hwp(x - box.height * 0.24, box.minY), hwp(x - box.height * 0.3, box.minY)]), HeadwearColor(1, 0.98, 0.9, fade * 0.6))
            pen.ctx.restoreGState()
        }
    }
}

// MARK: - Floating bits

/// Bubbles, notes, sparkles and confetti that float about the picture. Positions are in output pixels so that, once let go,
/// they drift up or fall down the picture whichever way the head is tilted; sizes are in eye-spacings so they suit the face.
struct HeadwearFloaters {
    struct Bit {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var age = 0.0
        var life: Double
        var size: Double
        var spin = 0.0
        var turn = 0.0
        var seed: Int
    }

    private(set) var bits: [Bit] = []
    let capacity: Int
    /// Pixels per second squared, scaled by the face size: negative falls, positive rises.
    var lift = 0.0
    /// How quickly they slow, per second.
    var drag = 0.6
    private var count = 0

    init(capacity: Int) { self.capacity = capacity }

    mutating func removeAll() { bits.removeAll() }

    /// Lets one go at `p` (output pixels) with `v` (eye-spacings per second), `size` in eye-spacings.
    mutating func emit(at p: CGPoint, velocity v: SIMD2<Double>, io: Double, life: Double, size: Double, spin: Double = 0) {
        count += 1
        guard bits.count < capacity else { return }
        bits.append(Bit(position: SIMD2(Double(p.x), Double(p.y)), velocity: v * io, life: life, size: size, spin: spin,
                        turn: HeadwearNoise.unit(count, 41) * 6.28, seed: count))
    }

    /// The next number in a repeatable sequence, for the costume to vary what it lets go.
    mutating func random(_ salt: Int) -> Double { count += 1; return HeadwearNoise.unit(count, salt) }

    mutating func step(dt: Double, io: Double) {
        for i in bits.indices {
            bits[i].age += dt
            bits[i].velocity.y += lift * io / 84 * dt
            bits[i].velocity *= max(0, 1 - drag * dt)
            bits[i].position += bits[i].velocity * dt
            bits[i].turn += bits[i].spin * dt
        }
        bits.removeAll { $0.age >= $0.life }
    }
}
