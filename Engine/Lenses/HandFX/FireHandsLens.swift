import CoreGraphics
import CoreImage
import simd

/// Flames that rise off an open hand. Open the hand and it catches with a whoosh; close it into a fist and the fire dies down to a few
/// embers and a puff of smoke.
///
/// The fire burns from the fingertips and the palm in the picture's "up", not along the hand, so it looks like real flame whichever way
/// the hand is turned. How much it burns follows how open the hand is as a smooth amount, so a hand the tracker is unsure of burns a
/// little lower instead of flickering on and off.
struct FireHandsRig {
    /// What the rig remembers about one hand.
    struct Burner {
        /// 0...1: how hard the hand is burning, eased.
        var burn = HandFXLevel(rise: 0.22, fall: 0.32)
        /// Flames owed to each emitter, carried between frames.
        var owed = 0.0
        /// Whether the hand has caught (for the whoosh) and been put out (for the smoke).
        var lit = HandFXLatch(on: 0.55, off: 0.25, holdOn: 0.0, holdOff: 0.1)
    }

    /// Kinds of particle.
    enum Kind: Int {
        case flame = 0, ember = 1, smoke = 2
    }

    static let capacity = 200
    /// Flames a second from a fully burning hand.
    static let rate = 100.0

    private(set) var memory = HandFXMemory<Burner>()
    private(set) var particles = ParticleSystem(capacity: FireHandsRig.capacity)
    private(set) var ignitions = 0
    private(set) var time = 0.0
    private var steadier = HandFXSteadier()
    private var rng = SplitMix64(seed: 0xF12E)

    init() {
        particles.gravity = SIMD2(0, 0)
        particles.drag = 1.1
    }

    mutating func removeAll() {
        memory.removeAll()
        particles.removeAll()
        steadier.removeAll()
    }

    /// How hard the hand burns for a pose: an open hand fully, a fist not at all.
    static func fuel(of hand: HandState) -> Double { WorldKit.smoothstep(0.2, 0.8, HandFXPose.openness(hand)) }

    var strongestBurn: Double { memory.entries.map { $0.state.burn.value * $0.presence }.max() ?? 0 }

    mutating func update(hands raw: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        let hands = steadier.update(raw, dt: dt)
        memory.update(hands, dt: dt, fade: 0.35) { _ in Burner() }
        for i in memory.entries.indices {
            var entry = memory.entries[i]
            let target = entry.visible ? Self.fuel(of: entry.hand) : 0
            entry.state.burn.approach(target, dt: dt)
            let was = entry.state.lit.isOn
            let now = entry.state.lit.update(entry.state.burn.value, dt: dt)
            if now, !was { whoosh(entry.hand) }
            if !now, was, entry.visible { snuff(entry.hand) }
            emit(from: entry.hand, burn: entry.state.burn.value * entry.presence, owed: &entry.state.owed, dt: dt)
            memory.modify(i) { $0 = entry }
        }
        step(dt: dt)
    }

    /// The points fire comes from: each fingertip (as far as the finger is out) and the knuckles, each with a share of the flame.
    private static func emitters(of hand: HandState) -> [(point: CGPoint, weight: Double)] {
        var out: [(CGPoint, Double)] = []
        for finger in Finger.allCases {
            let out1 = HandFXPose.extended(finger, in: hand)
            out.append((hand[finger.tip], 0.35 + 0.65 * out1))
        }
        for joint in [HandJoint.indexMCP, .middleMCP, .ringMCP, .littleMCP] { out.append((hand[joint], 0.3)) }
        out.append((hand.palm, 0.35))
        return out
    }

    private mutating func emit(from hand: HandState, burn: Double, owed: inout Double, dt: Double) {
        guard burn > 0.02 else { return }
        owed += Self.rate * burn * dt
        let count = min(14, Int(owed))
        owed -= Double(count)
        let sources = Self.emitters(of: hand)
        let total = sources.reduce(0) { $0 + $1.weight }
        let scale = min(1.6, max(0.6, hand.size / 110))
        for _ in 0..<count {
            // Pick an emitter by its share.
            var pick = Double.random(in: 0..<total, using: &rng)
            var source = sources[0].point
            for s in sources {
                pick -= s.weight
                if pick <= 0 { source = s.point; break }
            }
            let jitter = SIMD2(Double.random(in: -1...1, using: &rng), Double.random(in: -1...1, using: &rng)) * 6 * scale
            let rise = Double.random(in: 120...260, using: &rng) * scale
            let carried = SIMD2(Double(hand.velocity.dx), Double(hand.velocity.dy)) * 0.18
            particles.emit(Particle(position: HandFXKit.vector(source) + jitter,
                                    velocity: SIMD2(Double.random(in: -30...30, using: &rng), rise) + carried, age: 0,
                                    life: Double.random(in: 0.38...0.75, using: &rng) * (0.75 + 0.25 * burn),
                                    size: Double.random(in: 27...44, using: &rng) * scale * (0.7 + 0.3 * burn),
                                    hue: Double.random(in: 0..<1, using: &rng), kind: Kind.flame.rawValue))
        }
        // Now and then an ember drifts up out of the fire.
        if Double.random(in: 0..<1, using: &rng) < dt * 7 * burn {
            let s = sources[Int.random(in: 0..<sources.count, using: &rng)].point
            particles.emit(Particle(position: HandFXKit.vector(s), velocity: SIMD2(Double.random(in: -40...40, using: &rng), Double.random(in: 120...220, using: &rng)),
                                    age: 0, life: Double.random(in: 1.0...1.8, using: &rng), size: Double.random(in: 2...3.5, using: &rng),
                                    hue: Double.random(in: 0..<1, using: &rng), kind: Kind.ember.rawValue))
        }
    }

    /// The hand catches: a burst of flame up and out.
    private mutating func whoosh(_ hand: HandState) {
        ignitions += 1
        let scale = min(1.6, max(0.6, hand.size / 110))
        for _ in 0..<26 {
            let a = Double.random(in: 0.15...(.pi - 0.15), using: &rng)
            let speed = Double.random(in: 160...420, using: &rng) * scale
            particles.emit(Particle(position: HandFXKit.vector(hand.palm) + SIMD2(Double.random(in: -1...1, using: &rng), Double.random(in: -1...1, using: &rng)) * hand.size * 0.5,
                                    velocity: SIMD2(cos(a), sin(a)) * speed, age: 0, life: Double.random(in: 0.35...0.6, using: &rng),
                                    size: Double.random(in: 18...30, using: &rng) * scale, hue: Double.random(in: 0..<1, using: &rng), kind: Kind.flame.rawValue))
        }
    }

    /// The fire is put out: a soft puff of smoke where it was.
    private mutating func snuff(_ hand: HandState) {
        let scale = min(1.6, max(0.6, hand.size / 110))
        for _ in 0..<9 {
            particles.emit(Particle(position: HandFXKit.vector(hand.palm) + SIMD2(Double.random(in: -1...1, using: &rng), Double.random(in: 0...1.5, using: &rng)) * hand.size * 0.4,
                                    velocity: SIMD2(Double.random(in: -25...25, using: &rng), Double.random(in: 50...110, using: &rng)), age: 0,
                                    life: Double.random(in: 1.0...1.6, using: &rng), size: Double.random(in: 22...40, using: &rng) * scale,
                                    hue: Double.random(in: 0..<1, using: &rng), kind: Kind.smoke.rawValue))
        }
    }

    private mutating func step(dt: Double) {
        let t = time
        particles.step(dt) { p in
            // Flames lick from side to side as they rise, and speed up as hot air does; smoke slows and spreads.
            let wobble = sin(t * 9 + p.hue * 40 + p.position.y * 0.03) * 160
            switch Kind(rawValue: p.kind) ?? .flame {
            case .flame: p.velocity += SIMD2(wobble * dt, 260 * dt)
            case .ember: p.velocity += SIMD2(wobble * 0.6 * dt, 40 * dt)
            case .smoke: p.velocity += SIMD2(wobble * 0.15 * dt, 10 * dt)
            }
        }
    }
}

final class FireHandsLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig = FireHandsRig()
    private var hint = HandFXHint()
    private let published = StatusBox()

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hand", detail: "Open it to light the fire") }

    func restart() {
        rig.removeAll()
        hint.reset()
    }

    var burn: Double { rig.strongestBurn }
    var particleCount: Int { rig.particles.particles.count }
    var ignitions: Int { rig.ignitions }
    var presence: Double { rig.memory.strongest }
    var isHinting: Bool { hint.isShowing }

    func render(_ input: LensInput) -> CIImage {
        rig.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        published.value = currentStatus(input.hands)

        var out = input.composed
        if !rig.particles.particles.isEmpty || !rig.memory.isEmpty {
            // The fire lights up the hand and whatever is near it, warmly, on the graphics chip.
            for entry in rig.memory.entries {
                let glow = entry.state.burn.value * entry.presence
                guard glow > 0.02 else { continue }
                let flicker = 0.9 + 0.1 * sin(rig.time * 11 + Double(entry.hand.id)) * sin(rig.time * 7.3)
                let c = HandFXKit.vector(entry.hand.palm) + SIMD2(0, entry.hand.size * 0.6)
                out = WorldKit.adding(WorldKit.wash(center: HandFXKit.point(c), radius: entry.hand.size * 1.8, red: 1, green: 0.5, blue: 0.16,
                                                    alpha: 0.32 * glow * flicker, in: input.rect), to: out)
            }
            if rig.particles.particles.contains(where: { $0.kind == FireHandsRig.Kind.smoke.rawValue }),
               let smoke = input.services.overlay({ ctx in drawSmoke(in: ctx) }) {
                out = smoke.composited(over: out)
            }
            if let layer = input.services.overlay({ ctx in drawFire(in: ctx) }) {
                out = HandFXLight.add(layer, to: out, rect: input.rect, bloom: 0.55)
            }
        }
        return hint.compose(over: out, services: input.services, rect: input.rect, accent: HandFXPalette.ember.flame)
    }

    private func currentStatus(_ hands: [HandState]) -> LensStatus {
        if hands.isEmpty { return LensStatus("Hold up your hand", detail: "Open it to light the fire") }
        if rig.strongestBurn > 0.4 { return LensStatus("On fire!", detail: "Make a fist to put it out") }
        return LensStatus("Open your hand", detail: "Spread your fingers to light the fire")
    }

    // MARK: Drawing

    /// Flame colours from hottest to coolest: white-gold at first, then orange, then a deep red that fades.
    private static let stages: [SIMD3<Double>] = [
        SIMD3(1.0, 0.86, 0.5), SIMD3(1.0, 0.66, 0.26), HandFXPalette.ember.flame, SIMD3(0.9, 0.3, 0.08), SIMD3(0.66, 0.13, 0.06),
    ]

    /// A flame sprite for a stage: a teardrop of light, round at the bottom and drawn out to a point at the top.
    private static func flame(_ index: Int) -> CGImage? {
        let colour = stages[index]
        return HandFXSprites.named("fire-flame-\(index)") {
            HandFXKit.sprite(width: 40, height: 64) { u, v in
                let x = (u - 0.5) * 2, y = v
                let half = 0.95 * pow(max(0, 1 - y), 0.55) * min(1, y * 3.2 + 0.25)
                let across = half > 1e-3 ? abs(x) / half : 2
                let body = exp(-1.6 * across * across) * (1 - WorldKit.smoothstep(0.78, 1.0, y)) * WorldKit.smoothstep(0, 0.14, y)
                let hot = exp(-6 * across * across) * exp(-pow((y - 0.3) / 0.2, 2)) * (index == 0 ? 0.55 : 0.15)
                let c = colour + (SIMD3(1, 1, 1) - colour) * hot
                return (c.x, c.y, c.z, min(1, body))
            }
        }
    }

    private static let smokeSprite: CGImage? = HandFXKit.sprite(width: 48, height: 48) { u, v in
        let d = ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)).squareRoot() * 2
        return (0.16, 0.14, 0.14, exp(-3.5 * d * d) * (1 - WorldKit.smoothstep(0.8, 1, d)))
    }

    private func drawFire(in ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        defer { ctx.interpolationQuality = .high }
        for p in rig.particles.particles {
            let k = p.progress
            switch FireHandsRig.Kind(rawValue: p.kind) ?? .flame {
            case .flame:
                // Hot and small at the base, swelling, then thinning to nothing as it cools and climbs.
                let stage = min(FireHandsLens.stages.count - 1, Int(k * Double(FireHandsLens.stages.count)))
                guard let sprite = FireHandsLens.flame(stage) else { continue }
                let grow = sin(min(1, k * 1.25) * .pi * 0.9) * 0.75 + 0.35
                let w = p.size * grow * 0.85, h = p.size * grow * (1.5 + 0.8 * k)
                // A flame drifting sideways is shifted the way it drifts rather than turned, which costs far less to draw.
                ctx.setAlpha(CGFloat(pow(1 - k, 1.4) * 0.8))
                ctx.draw(sprite, in: CGRect(x: p.position.x - w / 2 + max(-0.4, min(0.4, p.velocity.x / 400)) * h * 0.2, y: p.position.y - h * 0.3, width: w, height: h))
            case .ember:
                let twinkle = 0.7 + 0.3 * sin(p.age * 20 + p.hue * 30)
                let c = HandFXKit.mix(HandFXPalette.ember.core, HandFXPalette.ember.flame, k)
                HandFXKit.glow(ctx, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * 3, colour: c, alpha: (1 - k) * twinkle)
            case .smoke:
                continue
            }
        }
        ctx.setAlpha(1)
    }

    /// Smoke darkens a little rather than adding light, so it is painted on its own layer.
    private func drawSmoke(in ctx: CGContext) {
        guard let sprite = FireHandsLens.smokeSprite else { return }
        for p in rig.particles.particles where p.kind == FireHandsRig.Kind.smoke.rawValue {
            let k = p.progress
            let r = p.size * (1 + 1.4 * k)
            ctx.stampDot(sprite, at: CGPoint(x: p.position.x, y: p.position.y), radius: r, alpha: 0.5 * sin(.pi * min(1, k * 1.2 + 0.1)))
        }
    }
}
