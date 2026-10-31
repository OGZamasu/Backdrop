import CoreGraphics
import CoreImage
import simd

/// Glitter streaming off the fingertips of every hand: a little when you hold still, a thick shower when you wave.
struct SparkleTrailStream {
    /// How a hand's fingertips moved: where each was last frame, and how fast, smoothed.
    struct Tracks {
        var tips: [CGPoint?] = Array(repeating: nil, count: 5)
        var speeds: [Double] = Array(repeating: 0, count: 5)
        /// Where each fingertip has been over the last few frames, newest last.
        var history: [[CGPoint]] = Array(repeating: [], count: 5)
    }

    /// Colours of the glitter: gold, ice, pink, aqua, violet.
    static let palette: [SIMD3<Double>] = [
        SIMD3(1.0, 0.8, 0.3), SIMD3(0.85, 0.95, 1.0), SIMD3(1.0, 0.45, 0.8), SIMD3(0.3, 0.95, 1.0), SIMD3(0.7, 0.5, 1.0),
    ]

    /// Sparkles a second a fingertip gives off at a speed in pixels a second: a few while still, many while it sweeps.
    static func rate(atSpeed speed: Double) -> Double { min(100, 8 + speed * 0.14) }

    /// How far a sparkle is scattered either side of the path, in pixels: wider for a faster hand, so the stream thickens.
    static func spread(atSpeed speed: Double) -> Double { 3 + min(34, speed * 0.016) }

    /// A jump bigger than this in one look is a tracking glitch, not movement, and leaves no streak.
    static let maxJump = 380.0

    private(set) var hands = HandFXMemory<Tracks>()
    private(set) var particles = ParticleSystem(capacity: 260)
    private(set) var emitted = 0
    private var rng = SplitMix64(seed: 0x57A9)
    private var owed: [Double] = Array(repeating: 0, count: 16)

    init() {
        particles.gravity = SIMD2(0, -55)
        particles.drag = 1.3
    }

    mutating func removeAll() {
        hands.removeAll()
        particles.removeAll()
    }

    /// How fast the fastest fingertip is going, pixels a second.
    var fastest: Double { hands.entries.flatMap(\.state.speeds).max() ?? 0 }

    mutating func update(hands incoming: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        hands.update(incoming, dt: dt, fade: 0.2) { _ in Tracks() }
        for i in hands.entries.indices {
            let entry = hands.entries[i]
            guard entry.visible else { continue }
            var tracks = entry.state
            for finger in Finger.allCases {
                let k = finger.rawValue
                let now = entry.hand[finger.tip]
                defer {
                    tracks.tips[k] = now
                    tracks.history[k].append(now)
                    if tracks.history[k].count > 9 { tracks.history[k].removeFirst() }
                }
                guard let before = tracks.tips[k] else { continue }
                let moved = HandFXKit.distance(before, now)
                guard moved < Self.maxJump else { tracks.speeds[k] = 0; continue }
                // Looks arrive about 25 times a second but frames at 30: a frame with no new look has no movement, so smooth the speed.
                tracks.speeds[k] += (moved / max(dt, 1e-3) - tracks.speeds[k]) * 0.4
                emit(from: before, to: now, speed: tracks.speeds[k], dt: dt, slot: i * 5 + k)
            }
            hands.modify(i) { $0.state = tracks }
        }
        particles.step(dt)
    }

    /// Sparkles along the path a fingertip took this frame, so even a fast sweep is a continuous stream.
    private mutating func emit(from a: CGPoint, to b: CGPoint, speed: Double, dt: Double, slot: Int) {
        let slot = min(slot, owed.count - 1)
        owed[slot] += Self.rate(atSpeed: speed) * dt
        let count = Int(owed[slot])
        owed[slot] -= Double(count)
        let spread = Self.spread(atSpeed: speed)
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let length = max(1e-6, (dx * dx + dy * dy).squareRoot())
        let side = SIMD2(-dy / length, dx / length)
        for _ in 0..<min(count, 14) {
            let along = Double.random(in: 0...1, using: &rng)
            let across = (Double.random(in: -1...1, using: &rng) + Double.random(in: -1...1, using: &rng)) * 0.5 * spread
            let at = SIMD2(Double(a.x) + dx * along, Double(a.y) + dy * along) + side * across
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng), drift = Double.random(in: 15...70, using: &rng)
            let big = Double.random(in: 0..<1, using: &rng) < 0.22
            particles.emit(Particle(position: at,
                                    velocity: SIMD2(cos(angle), sin(angle)) * drift + SIMD2(dx, dy) / max(dt, 1e-3) * 0.08, age: 0,
                                    life: Double.random(in: 0.5...1.05, using: &rng),
                                    size: big ? Double.random(in: 6...11, using: &rng) : Double.random(in: 2.5...5, using: &rng),
                                    hue: Double(Int.random(in: 0..<Self.palette.count, using: &rng)) + Double.random(in: 0..<0.99, using: &rng),
                                    kind: big ? 1 : 0))
            emitted += 1
        }
    }
}

final class SparkleTrailLens: Lens {
    let needs: LensNeeds = [.hands]

    private var stream = SparkleTrailStream()
    private var hint = HandFXHint()
    private let published = StatusBox()
    /// One sprite per glitter colour, with a white-hot point already in it, so each speck is a single stamp.
    private static func speck(_ k: Int) -> CGImage? {
        HandFXSprites.named("sparkle-speck-\(k)") { HandFXKit.speckSprite(SparkleTrailStream.palette[k]) }
    }

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hand", detail: "Wave it around") }

    func restart() {
        stream.removeAll()
        hint.reset()
    }

    var particleCount: Int { stream.particles.particles.count }
    var emittedCount: Int { stream.emitted }
    var fastestFingertip: Double { stream.fastest }
    var presence: Double { stream.hands.strongest }
    var isHinting: Bool { hint.isShowing }

    func render(_ input: LensInput) -> CIImage {
        stream.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        published.value = input.hands.isEmpty ? LensStatus("Hold up your hand", detail: "Wave it around")
                                              : LensStatus("Sparkle!", detail: "The faster you move, the more it flows")
        var out = input.composed
        if !stream.particles.particles.isEmpty || !stream.hands.isEmpty,
           let layer = input.services.overlay({ ctx in draw(in: ctx, time: input.time) }) {
            out = HandFXLight.add(layer, to: out, rect: input.rect, bloom: 0.6)
        }
        return hint.compose(over: out, services: input.services, rect: input.rect, accent: SparkleTrailStream.palette[0])
    }

    // MARK: Drawing

    private func draw(in ctx: CGContext, time: Double) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        defer { ctx.interpolationQuality = .high }

        // A streak of light behind each fingertip that is moving: longer and brighter the faster it goes.
        for entry in stream.hands.entries {
            for finger in Finger.allCases {
                let speed = entry.state.speeds[finger.rawValue]
                let path = entry.state.history[finger.rawValue]
                guard speed > 80, path.count > 3, let head = path.last else { continue }
                let back = path[max(0, path.count - 4)]
                let dx = Double(head.x - back.x), dy = Double(head.y - back.y)
                let moved = (dx * dx + dy * dy).squareRoot()
                guard moved > 4 else { continue }
                let c = SparkleTrailStream.palette[finger.rawValue % SparkleTrailStream.palette.count]
                guard let tail = WorldKit.comet(c.x, c.y, c.z) else { continue }
                let k = min(1, (speed - 80) / 900)
                let length = min(170, 30 + moved * 1.6), width = 10 + 12 * k
                ctx.saveGState()
                ctx.translateBy(x: head.x, y: head.y)
                ctx.rotate(by: atan2(dy, dx))
                ctx.setAlpha(CGFloat((0.35 + 0.55 * k) * entry.presence))
                ctx.draw(tail, in: CGRect(x: -length, y: -width / 2, width: length, height: width))
                ctx.restoreGState()
            }
        }

        // Glints are star sprites; the many small specks are soft dots with a white-hot point baked in, one stamp each.
        let stars = SparkleTrailStream.palette.map { WorldKit.star($0.x, $0.y, $0.z) }
        for p in stream.particles.particles {
            let colour = Int(p.hue) % SparkleTrailStream.palette.count
            let fade = pow(1 - p.progress, 0.8)
            // Each speck twinkles on its own rhythm.
            let twinkle = 0.65 + 0.35 * sin(p.age * (14 + p.size * 2.5) + (p.hue - p.hue.rounded(.down)) * 40)
            let alpha = fade * twinkle
            guard alpha > 0.03 else { continue }
            let at = CGPoint(x: p.position.x, y: p.position.y)
            if p.kind == 1 {
                if let star = stars[colour] { ctx.stampDot(star, at: at, radius: p.size * 1.9, alpha: alpha) }
            } else if let speck = Self.speck(colour) {
                ctx.stampDot(speck, at: at, radius: p.size * 1.6, alpha: alpha)
            }
        }
        // A soft light on every fingertip, brighter while it moves.
        for entry in stream.hands.entries {
            for finger in Finger.allCases {
                let k = min(1, entry.state.speeds[finger.rawValue] / 900)
                HandFXKit.glow(ctx, at: entry.hand[finger.tip], radius: 12 + 14 * k, colour: SIMD3(1, 0.9, 0.7), alpha: (0.3 + 0.45 * k) * entry.presence)
            }
        }
    }
}
