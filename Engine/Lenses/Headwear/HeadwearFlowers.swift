import CoreGraphics
import Foundation

/// A flower crown: a leafy vine of blossoms round the top of your head. Every so often a petal lets go and drifts down.
final class HeadwearFlowerCrown: HeadwearCostume {
    let hint = "Hold still and petals drift off"

    private enum Bloom { case daisy, blossom, peony, poppy, cluster }

    /// One blossom on the vine: where along it, which kind, how big and what colour.
    private struct Slot {
        var along: Double
        var bloom: Bloom
        var size: Double
        var colours: (light: HeadwearColor, deep: HeadwearColor)
    }

    private static let slots: [Slot] = [
        Slot(along: 0.02, bloom: .cluster, size: 0.17, colours: (HeadwearColor(hex: 0xD9C2FF), HeadwearColor(hex: 0x8E63E0))),
        Slot(along: 0.12, bloom: .blossom, size: 0.2, colours: (HeadwearColor(hex: 0xFFE0EA), HeadwearColor(hex: 0xF4719F))),
        Slot(along: 0.23, bloom: .daisy, size: 0.24, colours: (HeadwearColor.white, HeadwearColor(hex: 0xE9E9F4))),
        Slot(along: 0.34, bloom: .poppy, size: 0.22, colours: (HeadwearColor(hex: 0xFFC27A), HeadwearColor(hex: 0xF2762B))),
        Slot(along: 0.45, bloom: .peony, size: 0.31, colours: (HeadwearColor(hex: 0xFFC9DB), HeadwearColor(hex: 0xE8457E))),
        Slot(along: 0.55, bloom: .daisy, size: 0.27, colours: (HeadwearColor.white, HeadwearColor(hex: 0xE4E6F6))),
        Slot(along: 0.66, bloom: .blossom, size: 0.22, colours: (HeadwearColor(hex: 0xCFE3FF), HeadwearColor(hex: 0x5C93F0))),
        Slot(along: 0.77, bloom: .peony, size: 0.25, colours: (HeadwearColor(hex: 0xFFE9A6), HeadwearColor(hex: 0xF5B820))),
        Slot(along: 0.88, bloom: .daisy, size: 0.2, colours: (HeadwearColor(hex: 0xFFE3F0), HeadwearColor(hex: 0xF9A9CB))),
        Slot(along: 0.98, bloom: .cluster, size: 0.16, colours: (HeadwearColor(hex: 0xFFD2E4), HeadwearColor(hex: 0xEC5F96))),
    ]

    /// A petal in the air, in output pixels.
    private struct Petal {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var turn: Double
        var spin: Double
        var age = 0.0
        var life: Double
        var phase: Double
        var tint: Int
    }

    private var petals: [Petal] = []
    private var untilNext = 1.4
    private var spawned = 0
    private var wobble = HeadwearSwing(omega: 10, damping: 0.2, gain: 0.03, limit: 0.25)

    /// How many petals are drifting down at the moment.
    var petalCount: Int { petals.count }
    /// Where they are, in output pixels.
    var petalPositions: [CGPoint] { petals.map { CGPoint(x: $0.position.x, y: $0.position.y) } }

    func reset() { petals.removeAll(); untilNext = 1.4; spawned = 0; wobble.reset() }

    /// The vine through the points, from the left temple over the top to the right.
    private static let vinePoints: [CGPoint] = [hwp(-1.2, 0.32), hwp(-1.12, 0.72), hwp(-0.8, 1.04), hwp(-0.4, 1.2), hwp(0, 1.25),
                                                hwp(0.4, 1.2), hwp(0.8, 1.04), hwp(1.12, 0.72), hwp(1.2, 0.32)]

    /// A point on the vine, `s` of the way from one end to the other, and which way the vine is heading there.
    private static func vine(at s: Double) -> (point: CGPoint, heading: Double) {
        let pts = vinePoints
        let x = min(0.9999, max(0, s)) * Double(pts.count - 1)
        let i = Int(x), t = x - Double(i)
        func at(_ k: Int) -> CGPoint { pts[min(max(k, 0), pts.count - 1)] }
        let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
        // The same Catmull-Rom spline the vine is drawn with.
        func point(_ t: Double) -> CGPoint {
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            let u = 1 - t
            return CGPoint(x: u * u * u * p1.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p2.x,
                           y: u * u * u * p1.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p2.y)
        }
        let a = point(max(0, t - 0.02)), b = point(min(1, t + 0.02))
        return (point(t), atan2(b.y - a.y, b.x - a.x))
    }

    func advance(_ f: HeadwearFrame) {
        wobble.step(dt: f.dt, accel: f.accel.x, rest: 0)
        // Petals fall with gravity (down the picture, not down the face), sway as they go and turn over.
        let scale = f.io / 84
        for i in petals.indices {
            petals[i].age += f.dt
            petals[i].velocity.y -= 150 * scale * f.dt
            petals[i].velocity *= max(0, 1 - 1.6 * f.dt)
            let flutter = 38 * scale * cos(petals[i].age * 3.4 + petals[i].phase)
            petals[i].position += (petals[i].velocity + SIMD2(flutter, 0)) * f.dt
            petals[i].turn += petals[i].spin * f.dt
        }
        petals.removeAll { $0.age >= $0.life }
        guard f.seen > 1.2 else { return }
        untilNext -= f.dt
        if untilNext <= 0 {
            spawn(f)
            untilNext = 1.1 + 2.2 * HeadwearNoise.unit(spawned, 5)
        }
    }

    private func spawn(_ f: HeadwearFrame) {
        let k = spawned
        spawned += 1
        guard petals.count < 14 else { return }
        let slot = Self.slots[Int(HeadwearNoise.unit(k, 1) * Double(Self.slots.count)) % Self.slots.count]
        let along = Self.vine(at: slot.along).point
        let spot = hwp(along.x * f.head.wide, along.y + f.head.up(1.0) - 1.0)
        let position = f.toScreen(spot)
        let scale = f.io / 84
        petals.append(Petal(position: SIMD2(Double(position.x), Double(position.y)),
                            velocity: SIMD2((HeadwearNoise.unit(k, 2) - 0.5) * 40 * scale, 20 * scale),
                            turn: HeadwearNoise.unit(k, 3) * 6.28, spin: (HeadwearNoise.unit(k, 4) - 0.5) * 5,
                            life: 3.2 + 1.4 * HeadwearNoise.unit(k, 6), phase: HeadwearNoise.unit(k, 7) * 6.28,
                            tint: Int(HeadwearNoise.unit(k, 8) * 100)))
    }

    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        f.inFace(pen.ctx) { drawCrown(pen, f) }
        drawPetals(pen, f)
    }

    private func drawCrown(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let fall = HeadwearEase.drop(f.seen, height: 1.4, duration: 0.55)
        pen.placed(at: hwp(0, fall + f.head.up(1.0) - 1.0), stretch: CGSize(width: f.head.wide, height: 1)) {
            let vine = HeadwearShape.smooth(Self.vinePoints, closed: false)
            let grow = HeadwearEase.smoothstep(f.seen / 0.45)
            pen.stroke(vine, HeadwearColor(hex: 0x1E6B34), width: 0.12 * grow)
            pen.stroke(vine, HeadwearColor(hex: 0x3FA35A), width: 0.075 * grow)
            pen.placed(at: hwp(-0.01, 0.015)) { pen.stroke(vine, HeadwearColor(hex: 0xA8E6A0, alpha: 0.5), width: 0.02 * grow) }
            // Leaves: a pair at each gap between blossoms, one pointing out and one in.
            for (k, s) in stride(from: 0.07, through: 0.93, by: 0.1).enumerated() {
                drawLeaf(pen, f, at: s, side: 1, index: k)
                drawLeaf(pen, f, at: s + 0.015, side: -1, index: k + 20)
            }
            for (k, slot) in Self.slots.enumerated() {
                drawBloom(pen, f, slot, index: k)
            }
        }
    }

    private func drawLeaf(_ pen: HeadwearPen, _ f: HeadwearFrame, at s: Double, side: Double, index: Int) {
        let grow = HeadwearEase.pop(f.seen, delay: 0.1 + 0.015 * Double(index % 20), duration: 0.45)
        guard grow > 0.01 else { return }
        let (p, heading) = Self.vine(at: s)
        let length = (0.42 + 0.14 * HeadwearNoise.unit(index, 21)) * grow
        let angle = heading + side * (0.9 + 0.35 * HeadwearNoise.unit(index, 22)) + 0.08 * sin(f.clock * 1.8 + Double(index))
        let tone = Int(HeadwearNoise.unit(index, 23) * 3)
        // One leaf of unit length per side and shade, painted once and kept, then laid along the vine at its own length and angle.
        pen.placed(at: p, turn: angle, scale: length) {
            pen.sprite("leaf-\(side < 0 ? "l" : "r")-\(tone)", window: CGRect(x: -0.08, y: -0.4, width: 1.25, height: 0.8), pixelsPerUnit: f.io * 0.5) { pen in
                let spine = HeadwearShape.spine(from: .zero, length: 1, steps: 8) { t in side * -0.35 * t }
                let leaf = HeadwearShape.ribbon(spine, tip: 0.3) { t in 0.24 * sin(min(1, t * 1.05 + 0.08) * .pi) + 0.008 }
                pen.paint(leaf, [HeadwearColor(hex: 0x7BDB6F).mixed(with: HeadwearColor(hex: 0xA8E35C), Double(tone) / 2), HeadwearColor(hex: 0x2B9448)],
                          ink: HeadwearColor(hex: 0x1C6A33), inkWidth: 0.05, direction: CGVector(dx: 1, dy: 0))
                pen.stroke(HeadwearShape.smooth(Array(spine.dropFirst().dropLast()), closed: false), HeadwearColor(hex: 0xC9F2B0, alpha: 0.7), width: 0.03)
            }
        }
    }

    private func drawBloom(_ pen: HeadwearPen, _ f: HeadwearFrame, _ slot: Slot, index k: Int) {
        let reveal = HeadwearEase.pop(f.seen, delay: 0.12 + 0.045 * abs(Double(k) - 4.5), duration: 0.55)
        guard reveal > 0.01 else { return }
        let (p, _) = Self.vine(at: slot.along)
        let bob = 1 + 0.035 * sin(f.clock * 2.1 + Double(k) * 1.3)
        let turn = 0.12 * sin(f.clock * 1.3 + Double(k)) + wobble.x * 0.6 + Double(k) * 0.7
        let r = slot.size
        pen.shadow(at: hwp(p.x + 0.03, p.y - 0.05), rx: r * 1.5 * reveal, ry: r * 1.2 * reveal, alpha: 0.35)
        pen.placed(at: hwp(p.x, p.y + 0.02), turn: turn, scale: reveal * bob * 1.4) {
            // Each blossom is painted once and kept; only where it sits and how it turns change from frame to frame.
            pen.sprite("flower-\(k)", window: CGRect(x: -r * 1.5, y: -r * 1.5, width: r * 3, height: r * 3), pixelsPerUnit: f.io * 1.4 * f.head.wide) { pen in
                switch slot.bloom {
                case .daisy: daisy(pen, r, slot.colours, count: 9)
                case .blossom: blossom(pen, r, slot.colours)
                case .peony: peony(pen, r, slot.colours)
                case .poppy: poppy(pen, r, slot.colours)
                case .cluster: cluster(pen, r, slot.colours)
                }
            }
        }
    }

    // MARK: Blooms

    private func daisy(_ pen: HeadwearPen, _ r: Double, _ c: (light: HeadwearColor, deep: HeadwearColor), count: Int) {
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi
            let petal = HeadwearShape.ellipse(hwp(cos(a) * r * 0.62, sin(a) * r * 0.62), rx: r * 0.4, ry: r * 0.16, turn: a)
            pen.paint(petal, [c.light, c.deep], ink: c.deep.darker(0.25), inkWidth: 0.02, direction: CGVector(dx: -cos(a), dy: -sin(a)))
        }
        let heart = HeadwearShape.ellipse(hwp(0, 0), rx: r * 0.3, ry: r * 0.3)
        pen.paintRound(heart, center: hwp(-r * 0.08, r * 0.08), radius: r * 0.4, [HeadwearColor(hex: 0xFFE66B), HeadwearColor(hex: 0xF0A820)],
                       ink: HeadwearColor(hex: 0xB87410), inkWidth: 0.02)
    }

    private func blossom(_ pen: HeadwearPen, _ r: Double, _ c: (light: HeadwearColor, deep: HeadwearColor)) {
        for i in 0..<5 {
            let a = Double(i) / 5 * 2 * .pi + .pi / 2
            let petal = HeadwearShape.ellipse(hwp(cos(a) * r * 0.5, sin(a) * r * 0.5), rx: r * 0.5, ry: r * 0.37, turn: a)
            pen.paint(petal, [c.light, c.deep], ink: c.deep.darker(0.3), inkWidth: 0.022, direction: CGVector(dx: -cos(a), dy: -sin(a)))
        }
        pen.paintRound(HeadwearShape.ellipse(hwp(0, 0), rx: r * 0.22, ry: r * 0.22), center: hwp(-0.01, 0.01), radius: r * 0.3,
                       [HeadwearColor(hex: 0xFFF0A0), HeadwearColor(hex: 0xF2B21E)], ink: HeadwearColor(hex: 0xB87410), inkWidth: 0.015)
    }

    private func peony(_ pen: HeadwearPen, _ r: Double, _ c: (light: HeadwearColor, deep: HeadwearColor)) {
        for (layer, (count, size, turn)) in [(6, 1.0, 0.0), (5, 0.74, 0.5), (4, 0.5, 0.2)].enumerated() {
            for i in 0..<count {
                let a = Double(i) / Double(count) * 2 * .pi + turn
                let d = r * size * 0.45
                let petal = HeadwearShape.ellipse(hwp(cos(a) * d, sin(a) * d), rx: r * size * 0.5, ry: r * size * 0.4, turn: a)
                let shade = Double(layer) * 0.18
                pen.paint(petal, [c.light.mixed(with: c.deep, shade), c.deep.mixed(with: .black, shade * 0.6)], ink: c.deep.darker(0.35), inkWidth: 0.02,
                          direction: CGVector(dx: -cos(a), dy: -sin(a)))
            }
        }
        pen.stroke(HeadwearShape.smooth((0...12).map { k in
            let t = Double(k) / 12, a = t * 5.2
            return hwp(cos(a) * r * 0.2 * t * 1.4, sin(a) * r * 0.2 * t * 1.4)
        }, closed: false), c.deep.darker(0.4).faded(0.8), width: 0.02)
    }

    private func poppy(_ pen: HeadwearPen, _ r: Double, _ c: (light: HeadwearColor, deep: HeadwearColor)) {
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi + 0.3
            let petal = HeadwearShape.ellipse(hwp(cos(a) * r * 0.45, sin(a) * r * 0.45), rx: r * 0.55, ry: r * 0.44, turn: a)
            pen.paint(petal, [c.light, c.deep], ink: c.deep.darker(0.35), inkWidth: 0.022, direction: CGVector(dx: -cos(a), dy: -sin(a)))
        }
        pen.fill(HeadwearShape.ellipse(hwp(0, 0), rx: r * 0.2, ry: r * 0.2), HeadwearColor(hex: 0x4A2A1C))
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi
            pen.dot(at: hwp(cos(a) * r * 0.3, sin(a) * r * 0.3), radius: r * 0.045, HeadwearColor(hex: 0x4A2A1C))
        }
    }

    private func cluster(_ pen: HeadwearPen, _ r: Double, _ c: (light: HeadwearColor, deep: HeadwearColor)) {
        for (dx, dy, k) in [(-0.45, -0.25, 0.55), (0.45, -0.2, 0.5), (0, 0.4, 0.6), (0.05, -0.05, 0.62)] as [(Double, Double, Double)] {
            pen.placed(at: hwp(dx * r, dy * r), turn: dx * 2) { blossom(pen, r * k * 1.5, c) }
        }
    }

    // MARK: Falling petals

    private func drawPetals(_ pen: HeadwearPen, _ f: HeadwearFrame) {
        let colours: [(HeadwearColor, HeadwearColor)] = [(HeadwearColor.white, HeadwearColor(hex: 0xE4E6F6)), (HeadwearColor(hex: 0xFFE0EA), HeadwearColor(hex: 0xF4719F)),
                                                         (HeadwearColor(hex: 0xFFE9A6), HeadwearColor(hex: 0xF5B820)), (HeadwearColor(hex: 0xFFC9DB), HeadwearColor(hex: 0xE8457E))]
        for p in petals {
            let fadeIn = min(1, p.age / 0.2), fadeOut = min(1, (p.life - p.age) / 0.8)
            let c = colours[p.tint % colours.count]
            // Turning over as it falls: the petal narrows and widens.
            let flip = 0.35 + 0.65 * abs(cos(p.age * 2.6 + p.phase))
            let r = 0.12 * f.io
            pen.placed(at: CGPoint(x: p.position.x, y: p.position.y), turn: p.turn) {
                let shape = HeadwearShape.ellipse(hwp(0, 0), rx: r, ry: r * 0.55 * flip)
                pen.paint(shape, [c.0.scaled(fadeIn * fadeOut), c.1.scaled(fadeIn * fadeOut)], ink: c.1.darker(0.25).scaled(fadeIn * fadeOut), inkWidth: max(0.8, r * 0.1), direction: CGVector(dx: -1, dy: 0))
            }
        }
    }
}
