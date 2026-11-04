import CoreGraphics
import Foundation
import simd

/// The lightning of the aura: short-lived arcs that crawl along the outline, bolts that jump out from it and fork, and the odd arc across
/// the shoulders. Each bolt lives a few frames, re-forks every other frame and skips a frame now and then, so it strobes; how many there
/// are follows the form's `lightning` (Super Saiyan 2 crackles all the time, Super Saiyan 3 heaviest). Bolts are tied to places on the
/// rim, not to pixels, so they move with the person. Drawn as light (`HandFXKit.drawBolt`); the bloom round them is the aura's.
final class SaiyanLightning {
    enum Kind { case crawl, jump, across }

    struct Bolt {
        var kind: Kind
        /// Where on the rim it starts and ends, as a fraction of the way round.
        var from: Double
        var to: Double
        /// How far it lifts off the outline (crawl) or reaches out from it (jump), at a unit person.
        var reach: Double
        var seed: UInt64
        var age = 0.0
        var life: Double
        var strength: Double
        var width: Double
        var forks: Bool
    }

    private(set) var bolts: [Bolt] = []
    private var owed = 0.0
    private var rng = SplitMix64(seed: 0x5A17)
    private var frame = 0

    func reset() {
        bolts.removeAll()
        owed = 0
    }

    var isIdle: Bool { bolts.isEmpty }

    /// One frame. `amount` is the form's lightning (0...1, a little over while charging); `heavy` makes bolts longer, wider and forked.
    func step(dt: Double, amount: Double, heavy: Double, outline: SaiyanOutline) {
        frame += 1
        for i in bolts.indices { bolts[i].age += dt }
        bolts.removeAll { $0.age >= $0.life }
        guard amount > 0.01, outline.rim.count > 6 else {
            owed = 0
            return
        }
        // Steeply more with the form's lightning: a spark every few seconds for Super Saiyan (0.14), about 30 a second for Super Saiyan 2
        // (0.72), which keeps four or five alive at any moment, and more for Super Saiyan 3.
        owed += dt * pow(amount, 1.3) * 45
        while owed >= 1 {
            owed -= 1
            guard bolts.count < 7 else { continue }
            let pick = Double.random(in: 0..<1, using: &rng)
            let kind: Kind = pick < 0.55 ? .crawl : pick < 0.9 ? .jump : .across
            let start = Double.random(in: 0.02...0.98, using: &rng)
            let span: Double
            switch kind {
            case .crawl: span = Double.random(in: 0.12...0.3, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
            case .jump: span = 0
            case .across: span = Double.random(in: 0.12...0.22, using: &rng) * (start > 0.5 ? -1 : 1)
            }
            let reach: Double
            switch kind {
            // Crawling arcs ride out in the coloured body of the flame: right on the outline the aura is white-hot and white light added
            // to it would not show.
            case .crawl: reach = Double.random(in: 20...50, using: &rng)
            case .jump: reach = Double.random(in: 70...180, using: &rng) * (1 + 0.5 * heavy)
            case .across: reach = 0
            }
            bolts.append(Bolt(kind: kind, from: start, to: min(1, max(0, start + span)), reach: reach, seed: rng.next(),
                              life: Double.random(in: 0.07...0.17, using: &rng) * (1 + 0.4 * heavy), strength: Double.random(in: 0.65...1, using: &rng),
                              width: (1.05 + 0.4 * heavy) * Double.random(in: 0.85...1.15, using: &rng), forks: kind == .jump && Double.random(in: 0..<1, using: &rng) < 0.55 + 0.4 * heavy))
        }
        owed = min(owed, 2)
    }

    /// Draws every live bolt as light. `avoid` is the face: no bolt is ever drawn across it.
    func draw(in ctx: CGContext, outline: SaiyanOutline, colour: SIMD3<Double>, strength: Double, avoid: CGRect?) {
        guard strength > 0.01, !bolts.isEmpty, outline.rim.count > 6 else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let u = outline.unit
        // The bolt's coloured body in a richer version of its colour, so a pale blue-white arc still reads against a gold flame. (The wide
        // glow round it is the layer's bloom: stroking it here would cost far more.)
        let mean = (colour.x + colour.y + colour.z) / 3
        let rich = simd_clamp(SIMD3(repeating: mean) + (colour - SIMD3(repeating: mean)) * 2.4, SIMD3(repeating: 0), SIMD3(repeating: 1))
        for bolt in bolts {
            // Strobing: each bolt skips about one frame in five and changes brightness every frame.
            var flick = SplitMix64(seed: bolt.seed &+ UInt64(frame) &* 0x9E37)
            let on = Double.random(in: 0..<1, using: &flick)
            guard on > 0.2 else { continue }
            let k = bolt.age / bolt.life
            let s = strength * bolt.strength * (1 - k * k) * (0.6 + 0.4 * on)
            let seed = bolt.seed &+ UInt64(frame / 2) &* 7919
            guard let path = path(of: bolt, outline: outline, seed: seed, avoid: avoid), !crosses(path, avoid) else { continue }
            let width = bolt.width * min(1.3, max(0.55, u.squareRoot()))
            HandFXKit.drawBolt(path, in: ctx, colour: SaiyanAuraKit.mix(rich, colour, 0.3), strength: s, width: width)
            if bolt.forks, path.count > 6 {
                // A fork off the middle, shorter and fainter, bending away.
                var r = SplitMix64(seed: seed ^ 0xF0F0)
                let at = path[path.count * 2 / 5]
                let main = SIMD2(Double(path[path.count - 1].x - path[0].x), Double(path[path.count - 1].y - path[0].y))
                let turn = Double.random(in: 0.45...0.9, using: &r) * (Bool.random(using: &r) ? 1 : -1)
                let d = SIMD2(main.x * cos(turn) - main.y * sin(turn), main.x * sin(turn) + main.y * cos(turn)) * 0.45
                let end = CGPoint(x: Double(at.x) + d.x, y: Double(at.y) + d.y)
                let fork = HandFXKit.zigzag(from: at, to: end, seed: seed ^ 0xABCD, amplitude: simd_length(d) * 0.22, segments: 8)
                HandFXKit.drawBolt(fork, in: ctx, colour: colour, strength: s * 0.7, width: width * 0.7)
            }
        }
        ctx.restoreGState()
    }

    /// Whether a bolt passes over the face (the ellipse inside its box). Where the outline turns a sharp corner (the neck meeting a
    /// shoulder) an arc lifted off it can swing inward, and lightning across the eyes would be the worst place for it.
    private func crosses(_ path: [CGPoint], _ face: CGRect?) -> Bool {
        guard let face, face.width > 1, face.height > 1 else { return false }
        let c = CGPoint(x: face.midX, y: face.midY), rx = Double(face.width) / 2, ry = Double(face.height) / 2
        return path.contains { p in
            let dx = Double(p.x - c.x) / rx, dy = Double(p.y - c.y) / ry
            return dx * dx + dy * dy < 1
        }
    }

    private func path(of bolt: Bolt, outline: SaiyanOutline, seed: UInt64, avoid: CGRect?) -> [CGPoint]? {
        let u = outline.unit
        let rim = outline.rim
        let n = rim.count
        func index(_ f: Double) -> Int { min(n - 1, max(0, Int((f * Double(n - 1)).rounded()))) }
        switch bolt.kind {
        case .crawl:
            // Along the rim, lifted a little off it, jagged between rim points.
            let a = index(min(bolt.from, bolt.to)), b = index(max(bolt.from, bolt.to))
            guard b > a, !(a...b).contains(where: { rim[$0].clipped }) else { return nil }
            var r = SplitMix64(seed: seed)
            var knots: [CGPoint] = []
            for i in a...b {
                let lift = (bolt.reach + Double.random(in: -4...6, using: &r)) * u
                knots.append(CGPoint(x: Double(rim[i].point.x) + rim[i].normal.x * lift, y: Double(rim[i].point.y) + rim[i].normal.y * lift))
            }
            var out: [CGPoint] = [knots[0]]
            for i in 1..<knots.count {
                let piece = HandFXKit.zigzag(from: knots[i - 1], to: knots[i], seed: seed &+ UInt64(i), amplitude: 8 * u, segments: 4)
                out.append(contentsOf: piece.dropFirst())
            }
            return out
        case .jump:
            let p = rim[index(bolt.from)]
            guard !p.clipped else { return nil }
            var r = SplitMix64(seed: bolt.seed)
            let turn = Double.random(in: -0.55...0.55, using: &r)
            let d = SIMD2(p.normal.x * cos(turn) - p.normal.y * sin(turn), p.normal.x * sin(turn) + p.normal.y * cos(turn))
            let start = CGPoint(x: Double(p.point.x) + p.normal.x * 8 * u, y: Double(p.point.y) + p.normal.y * 8 * u)
            let reach = bolt.reach * u
            let end = CGPoint(x: Double(start.x) + d.x * reach, y: Double(start.y) + d.y * reach)
            return HandFXKit.zigzag(from: start, to: end, seed: seed, amplitude: reach * 0.17, segments: 16)
        case .across:
            // A short arc over the body between two rim points on the same side, below the face.
            let a = rim[index(bolt.from)], b = rim[index(bolt.to)]
            guard !a.clipped, !b.clipped else { return nil }
            if let face = avoid, max(a.point.y, b.point.y) > face.minY { return nil }
            let length = HandFXKit.distance(a.point, b.point)
            guard length > 20 * u else { return nil }
            return HandFXKit.zigzag(from: a.point, to: b.point, seed: seed, amplitude: length * 0.14, segments: 12)
        }
    }
}
