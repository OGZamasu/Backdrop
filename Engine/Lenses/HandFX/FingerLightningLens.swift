import CoreGraphics
import CoreImage
import simd

/// Which fingertips are joined by lightning, and the jagged shape of each bolt.
///
/// Between the fingers of a spread hand, arcs jump from tip to tip. With two hands in view, bolts leap from one hand to the other.
enum FingerLightningArcs {
    /// One bolt to draw: its two ends, how strong it is, and a number that names it so it keeps its shape between re-rolls.
    struct Arc: Equatable {
        var from: CGPoint
        var to: CGPoint
        /// 1 for an ordinary arc, more for the thick one between two palms.
        var weight: Double
        var key: Int
    }

    /// The fingertips that are held out, thumb first, as (finger, position).
    static func extendedTips(of hand: HandState) -> [(finger: Finger, point: CGPoint)] {
        Finger.allCases.filter { hand.isExtended($0) }.map { ($0, hand[$0.tip]) }
    }

    /// Arcs between the fingers of one hand: each held-out fingertip to the next one along. A fist, or one finger pointing, has none.
    static func arcs(within hand: HandState, salt: Int) -> [Arc] {
        arcs(within: hand, fingers: Finger.allCases.filter { hand.isExtended($0) }, salt: salt)
    }

    /// The same, for a chosen set of held-out fingers. Each arc is named by the two fingers it joins, so it keeps its name when a
    /// finger between others comes and goes.
    static func arcs(within hand: HandState, fingers: [Finger], salt: Int) -> [Arc] {
        let tips = fingers.sorted { $0.rawValue < $1.rawValue }.map { (finger: $0, point: hand[$0.tip]) }
        guard tips.count >= 2 else { return [] }
        func key(_ a: Finger, _ b: Finger, _ extra: Int = 0) -> Int { hand.id * 1000 + extra + a.rawValue * 10 + b.rawValue }
        var out: [Arc] = []
        for i in 0..<(tips.count - 1) {
            out.append(Arc(from: tips[i].point, to: tips[i + 1].point, weight: 1, key: key(tips[i].finger, tips[i + 1].finger)))
        }
        // Now and then one leaps over a neighbour.
        if tips.count >= 3, salt % 3 == 0 {
            let i = (salt / 3) % (tips.count - 2)
            out.append(Arc(from: tips[i].point, to: tips[i + 2].point, weight: 0.7, key: key(tips[i].finger, tips[i + 2].finger, 50)))
        }
        return out
    }

    /// Arcs from each held-out fingertip of one hand to the same finger of the other, like the rungs of a ladder, and a thick one between the palms.
    /// Whether an arc joins two hands rather than two fingers of one: those are named with negative numbers.
    static func isBetweenHands(_ key: Int) -> Bool { key < 0 }

    static func arcs(between a: HandState, and b: HandState) -> [Arc] {
        arcs(between: a, and: b, fingers: Finger.allCases.filter { a.isExtended($0) && b.isExtended($0) })
    }

    /// The same, for a chosen set of fingers held out on both hands.
    static func arcs(between a: HandState, and b: HandState, fingers: [Finger]) -> [Arc] {
        var out: [Arc] = []
        for finger in fingers {
            out.append(Arc(from: a[finger.tip], to: b[finger.tip], weight: 1, key: -(a.id * 1000 + finger.rawValue + 1)))
        }
        out.append(Arc(from: a.palm, to: b.palm, weight: 1.6, key: -(a.id * 1000 + 500)))
        return out
    }

    /// A bolt's wobble: how far along the arc each bend is (0 at the start, 1 at the end) and how far to the side it sits, in pixels.
    /// Kept apart from the ends so that the same shape can be laid between ends that have since moved with the hand.
    typealias Shape = [(along: Double, side: Double)]

    /// The shape of a bolt for a beat. It changes whenever `beat` does, which is every few frames, and holds still between.
    static func shape(of arc: Arc, beat: Int) -> Shape {
        let length = max(1, HandFXKit.distance(arc.from, arc.to))
        let segments = min(28, max(4, Int(length / 20)))
        let seed = UInt64(truncatingIfNeeded: beat &* 2_654_435_761 &+ arc.key &* 40_503)
        let line = HandFXKit.zigzag(from: .zero, to: CGPoint(x: length, y: 0), seed: seed, amplitude: min(56, max(6, length * 0.14)), segments: segments)
        return line.map { (Double($0.x) / length, Double($0.y)) }
    }

    /// A shape laid along an arc, as a polyline from one end to the other.
    static func place(_ shape: Shape, on arc: Arc) -> [CGPoint] {
        let dx = Double(arc.to.x - arc.from.x), dy = Double(arc.to.y - arc.from.y)
        let length = max(1e-6, (dx * dx + dy * dy).squareRoot())
        let nx = -dy / length, ny = dx / length
        var points = shape.map { CGPoint(x: Double(arc.from.x) + dx * $0.along + nx * $0.side, y: Double(arc.from.y) + dy * $0.along + ny * $0.side) }
        if !points.isEmpty {
            points[0] = arc.from
            points[points.count - 1] = arc.to
        }
        return points
    }

    /// The bolt as a polyline.
    static func points(of arc: Arc, beat: Int) -> [CGPoint] { place(shape(of: arc, beat: beat), on: arc) }

    /// How many frames a bolt keeps its shape before it is thrown again.
    static let framesPerBeat = 3
}

final class FingerLightningLens: Lens {
    let needs: LensNeeds = [.hands]

    /// For each hand, which fingers count as held out. A finger has to be clearly out to start an arc and clearly curled to stop one, so a
    /// finger the tracker is unsure of does not make its arcs blink.
    struct Fingers {
        var latches = [HandFXLatch](repeating: HandFXLatch(on: 0.62, off: 0.32, holdOn: 0.05, holdOff: 0.12), count: 5)
        var out: [Finger] { Finger.allCases.filter { latches[$0.rawValue].isOn } }
    }

    private var memory = HandFXMemory<Fingers>()
    private var frame = 0
    private var clock = 0.0
    /// The shape each bolt has this beat, so that it is worked out once, not every frame.
    private var shapes: [Int: (beat: Int, shape: FingerLightningArcs.Shape)] = [:]
    /// How much each arc is showing, so arcs swell in and die away instead of blinking, and where each was last.
    private var levels: [Int: (level: HandFXLevel, arc: FingerLightningArcs.Arc)] = [:]
    private var hint = HandFXHint()
    private let published = StatusBox()

    static let colour = SIMD3<Double>(0.38, 0.62, 1.0)

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hand", detail: "Spread your fingers") }

    func restart() {
        memory.removeAll()
        shapes.removeAll()
        levels.removeAll()
        hint.reset()
    }

    /// The arcs showing now, fading ones included. For tests.
    private(set) var arcs: [FingerLightningArcs.Arc] = []
    var presence: Double { memory.strongest }
    var isHinting: Bool { hint.isShowing }

    func render(_ input: LensInput) -> CIImage {
        let dt = WorldKit.clamped(input.dt)
        frame += 1
        clock += dt
        memory.update(input.hands, dt: dt, fade: 0.2) { _ in Fingers() }
        for i in memory.entries.indices where memory.entries[i].visible {
            memory.modify(i) { entry in
                for finger in Finger.allCases {
                    // The first look decides at once; after that the latch waits to be sure.
                    let amount = HandFXPose.extended(finger, in: entry.hand)
                    entry.state.latches[finger.rawValue].update(amount, dt: entry.age < 1e-9 ? 1 : dt)
                }
            }
        }
        updateArcs(dt: dt)
        if shapes.count > 60 { shapes = shapes.filter { $0.value.beat >= frame / FingerLightningArcs.framesPerBeat - 1 } }
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        published.value = currentStatus(input.hands)

        var out = input.composed
        if !memory.isEmpty, !arcs.isEmpty {
            // A faint blue light on and around each hand that has lightning on it.
            for entry in memory.entries {
                let lit = levels.values.filter { $0.arc.key / 1000 == entry.hand.id || FingerLightningArcs.isBetweenHands($0.arc.key) }
                    .map(\.level.value).max() ?? 0
                guard lit > 0.01 else { continue }
                out = WorldKit.adding(WorldKit.wash(center: entry.hand.palm, radius: entry.hand.size * 1.5, red: 0.3, green: 0.45, blue: 1,
                                                    alpha: 0.2 * lit * entry.presence, in: input.rect), to: out)
            }
            if let layer = input.services.overlay({ ctx in draw(in: ctx) }) {
                out = HandFXLight.add(layer, to: out, rect: input.rect, bloom: 0.85)
            }
        }
        return hint.compose(over: out, services: input.services, rect: input.rect, accent: Self.colour)
    }

    private func updateArcs(dt: Double) {
        let beat = frame / FingerLightningArcs.framesPerBeat
        let entries = memory.entries
        var wanted: [FingerLightningArcs.Arc] = []
        // Only hands in view make arcs; those of a hand just lost die away on their own.
        let seen = entries.filter(\.visible)
        for entry in seen { wanted += FingerLightningArcs.arcs(within: entry.hand, fingers: entry.state.out, salt: beat) }
        if seen.count >= 2 {
            let a = seen[0], b = seen[1]
            let both = Finger.allCases.filter { a.state.latches[$0.rawValue].isOn && b.state.latches[$0.rawValue].isOn }
            wanted += FingerLightningArcs.arcs(between: a.hand, and: b.hand, fingers: both)
        }
        let keys = Set(wanted.map(\.key))
        for arc in wanted {
            if levels[arc.key] == nil { levels[arc.key] = (HandFXLevel(rise: 0.05, fall: 0.09), arc) } else { levels[arc.key]?.arc = arc }
        }
        for key in Array(levels.keys) {
            levels[key]?.level.approach(keys.contains(key) ? 1 : 0, dt: dt)
            if !keys.contains(key), (levels[key]?.level.value ?? 0) < 0.03 { levels[key] = nil }
        }
        arcs = levels.values.map(\.arc).sorted { $0.key < $1.key }
    }

    private func currentStatus(_ hands: [HandState]) -> LensStatus {
        if hands.isEmpty { return LensStatus("Hold up your hand", detail: "Spread your fingers") }
        if hands.count >= 2 { return LensStatus("Zap!", detail: "Move your hands apart and together") }
        return arcs.isEmpty ? LensStatus("Spread your fingers", detail: "Or bring the other hand in") : LensStatus("Zap!", detail: "Bring the other hand in")
    }

    // MARK: Drawing

    private func shape(of arc: FingerLightningArcs.Arc, beat: Int) -> FingerLightningArcs.Shape {
        if let hit = shapes[arc.key], hit.beat == beat { return hit.shape }
        let made = FingerLightningArcs.shape(of: arc, beat: beat)
        shapes[arc.key] = (beat, made)
        return made
    }

    private func draw(in ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        defer { ctx.interpolationQuality = .high }

        let beat = frame / FingerLightningArcs.framesPerBeat
        // Strength is the weaker of the two hands an arc joins, so a hand that is going takes its arcs with it.
        func strength(at p: CGPoint) -> Double {
            memory.entries.min(by: { HandFXKit.distance($0.hand.palm, p) < HandFXKit.distance($1.hand.palm, p) })?.presence ?? 0
        }
        var lit: [(CGPoint, Double)] = []
        for arc in arcs {
            let level = levels[arc.key]?.level.value ?? 0
            let s = min(strength(at: arc.from), strength(at: arc.to)) * level
            guard s > 0.01 else { continue }
            // The brightness wavers a little with each new bolt, as a real arc does, but never blinks.
            var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: beat &* 9973 &+ arc.key))
            let flicker = Double.random(in: 0.86...1.0, using: &rng)
            let points = FingerLightningArcs.place(shape(of: arc, beat: beat), on: arc)
            HandFXKit.drawBolt(points, in: ctx, colour: Self.colour, strength: s * flicker, width: arc.weight)

            // Now and then a short fork leaves the bolt.
            var fork = SplitMix64(seed: UInt64(truncatingIfNeeded: beat &* 131 &+ arc.key))
            if points.count > 5, Double.random(in: 0..<1, using: &fork) < 0.45 {
                let at = points[Int.random(in: 2..<(points.count - 2), using: &fork)]
                let angle = Double.random(in: 0..<(2 * .pi), using: &fork)
                let length = HandFXKit.distance(arc.from, arc.to) * Double.random(in: 0.18...0.34, using: &fork) + 14
                let end = CGPoint(x: Double(at.x) + cos(angle) * length, y: Double(at.y) + sin(angle) * length)
                HandFXKit.drawBolt(HandFXKit.zigzag(from: at, to: end, seed: UInt64(truncatingIfNeeded: beat &* 7 &+ arc.key), amplitude: length * 0.3, segments: 8),
                                   in: ctx, colour: Self.colour, strength: s * flicker * 0.6, width: 0.55)
            }
            lit.append((arc.from, s))
            lit.append((arc.to, s))
        }
        // A glow at every fingertip an arc touches, breathing gently: once for each fingertip, however many arcs meet there.
        var glows: [(CGPoint, Double)] = []
        for (p, s) in lit {
            if let i = glows.firstIndex(where: { HandFXKit.distance($0.0, p) < 3 }) { glows[i].1 = max(glows[i].1, s) } else { glows.append((p, s)) }
        }
        for (p, s) in glows {
            let breathe = 0.9 + 0.1 * sin(clock * 13 + Double(p.x) * 0.05)
            HandFXKit.glow(ctx, at: p, radius: 30, colour: SIMD3(0.5, 0.7, 1), alpha: 0.75 * s * breathe)
            HandFXKit.glow(ctx, at: p, radius: 9, colour: HandFXPalette.white, alpha: s)
        }
    }
}
