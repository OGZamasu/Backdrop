import CoreGraphics
import CoreImage
import simd

/// Soap bubbles blown from a ring made of your finger and thumb. Touch the tips together to make an "O" and a film of soap fills it;
/// wave it through the air and bubbles stream out, more the faster you sweep. They float, drift and wobble, and pop when a fingertip
/// pokes them, or on their own after a while.
struct BubbleWandRig {
    struct Wand {
        var ring = HandFXLatch(on: 0.6, off: 0.3, holdOn: 0.08, holdOff: 0.2)
        /// 0...1: how much of the soap film shows in the ring.
        var film = HandFXLevel(rise: 0.15, fall: 0.18)
        var centre = HandFXSteady(calm: 2.0, eager: 0.03)
        /// How fast the ring is moving, pixels a second, smoothed.
        var speed = 0.0
        var velocity = SIMD2<Double>(0, 0)
        var owed = 0.0
    }

    struct Bubble {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var radius: Double
        var age = 0.0
        var life: Double
        var seed: Double
        var variant: Int
    }

    struct Pop {
        var position: SIMD2<Double>
        var radius: Double
        var variant: Int
        var age = 0.0
    }

    static let maxBubbles = 36
    /// A newly blown bubble cannot be popped by the hand that blew it straight away.
    static let grace = 0.7

    private(set) var memory = HandFXMemory<Wand>()
    private(set) var bubbles: [Bubble] = []
    private(set) var pops: [Pop] = []
    private(set) var droplets = ParticleSystem(capacity: 160)
    private(set) var blown = 0
    private(set) var popped = 0
    private(set) var time = 0.0
    private var steadier = HandFXSteadier()
    private var rng = SplitMix64(seed: 0xB0B)
    let size: CGSize

    init(size: CGSize) {
        self.size = size
        droplets.gravity = SIMD2(0, -520)
    }

    mutating func removeAll() {
        memory.removeAll()
        bubbles.removeAll()
        pops.removeAll()
        droplets.removeAll()
        steadier.removeAll()
    }

    /// How much a hand makes a ring: thumb and index tips together, with the index finger reaching out rather than curled into a fist.
    static func ringness(of hand: HandState) -> Double {
        (1 - WorldKit.smoothstep(0.24, 0.48, hand.pinch)) * WorldKit.smoothstep(1.02, 1.28, hand.reach(of: .index))
    }

    /// The middle of the ring and its radius.
    static func ring(of hand: HandState) -> (centre: CGPoint, radius: Double) {
        let points = [hand[.thumbIP], hand[.thumbTip], hand[.indexPIP], hand[.indexDIP], hand[.indexTip]]
        let c = CGPoint(x: points.reduce(0) { $0 + $1.x } / 5, y: points.reduce(0) { $0 + $1.y } / 5)
        return (c, hand.size * 0.24)
    }

    mutating func update(hands raw: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        let hands = steadier.update(raw, dt: dt)
        memory.update(hands, dt: dt, fade: 0.25) { _ in Wand() }
        for i in memory.entries.indices {
            var entry = memory.entries[i]
            if entry.visible {
                let ring = Self.ring(of: entry.hand)
                let before = entry.state.centre.point
                let now = entry.state.centre.update(ring.centre, dt: dt, snap: max(160, entry.hand.size * 2.5))
                if let before, dt > 0 {
                    let v = (HandFXKit.vector(now) - HandFXKit.vector(before)) / dt
                    entry.state.velocity += (v - entry.state.velocity) * min(1, dt / 0.07)
                    entry.state.speed = simd_length(entry.state.velocity)
                }
                let on = entry.state.ring.update(Self.ringness(of: entry.hand), dt: entry.age < 1e-9 ? 1 : dt)
                entry.state.film.approach(on ? 1 : 0, dt: dt)
                if on, entry.state.film.value > 0.6 { blow(from: &entry.state, at: now, hand: entry.hand, dt: dt) }
            } else {
                entry.state.film.approach(0, dt: dt)
            }
            memory.modify(i) { $0 = entry }
        }
        stepBubbles(dt: dt, hands: hands)
        for i in pops.indices { pops[i].age += dt }
        pops.removeAll { $0.age > 0.2 }
        droplets.step(dt)
    }

    /// A sweep blows a stream of bubbles; a ring held still lets one go now and then.
    private mutating func blow(from wand: inout Wand, at centre: CGPoint, hand: HandState, dt: Double) {
        let sweep = WorldKit.smoothstep(140, 700, wand.speed)
        wand.owed += dt * (0.9 + 6 * sweep)
        let scale = min(1.5, max(0.6, hand.size / 110))
        while wand.owed >= 1 {
            wand.owed -= 1
            if bubbles.count >= Self.maxBubbles { bubbles.removeFirst() }
            // Bubbles from a slow sweep are big; a fast one throws out smaller ones.
            let radius = Double.random(in: 24...58, using: &rng) * scale * (1 - 0.3 * sweep)
            let push = wand.velocity * Double.random(in: 0.2...0.4, using: &rng)
            bubbles.append(Bubble(position: HandFXKit.vector(centre), velocity: push + SIMD2(Double.random(in: -20...20, using: &rng), 30),
                                  radius: radius, life: Double.random(in: 6...10, using: &rng), seed: Double.random(in: 0..<100, using: &rng),
                                  variant: Int.random(in: 0..<3, using: &rng)))
            blown += 1
        }
    }

    private mutating func stepBubbles(dt: Double, hands: [HandState]) {
        let area = CGRect(origin: .zero, size: size)
        let pokers = hands.flatMap { h in [h.indexTip, h[.middleTip], h[.thumbTip]].map(HandFXKit.vector) }
        var burst: [Int] = []
        for i in bubbles.indices {
            var b = bubbles[i]
            b.age += dt
            // Bubbles rise a little, wander on the air and slow down.
            let wander = SIMD2(sin(time * 0.9 + b.seed), cos(time * 0.7 + b.seed * 1.3)) * 34
            b.velocity += (SIMD2(0, 18) + wander) * dt
            b.velocity *= max(0, 1 - 0.85 * dt)
            b.position += b.velocity * dt
            // A soft bounce off the edges of the picture.
            let r = b.radius
            if b.position.x < r { b.position.x = r; b.velocity.x = abs(b.velocity.x) * 0.5 }
            if b.position.x > Double(area.maxX) - r { b.position.x = Double(area.maxX) - r; b.velocity.x = -abs(b.velocity.x) * 0.5 }
            if b.position.y < r { b.position.y = r; b.velocity.y = abs(b.velocity.y) * 0.5 }
            if b.position.y > Double(area.maxY) - r { b.position.y = Double(area.maxY) - r; b.velocity.y = -abs(b.velocity.y) * 0.5 }
            bubbles[i] = b
            let poked = b.age > Self.grace && pokers.contains { simd_distance($0, b.position) < b.radius * 0.9 }
            if poked || b.age >= b.life { burst.append(i) }
        }
        for i in burst.reversed() { pop(i) }
    }

    /// Pops a bubble: a quick flash of its rim and a spray of droplets.
    mutating func pop(_ index: Int) {
        guard bubbles.indices.contains(index) else { return }
        let b = bubbles.remove(at: index)
        popped += 1
        pops.append(Pop(position: b.position, radius: b.radius, variant: b.variant))
        let count = 6 + Int(b.radius / 8)
        for k in 0..<count {
            let a = Double(k) / Double(count) * 2 * .pi + Double.random(in: -0.2...0.2, using: &rng)
            let d = SIMD2(cos(a), sin(a))
            droplets.emit(Particle(position: b.position + d * b.radius * 0.9, velocity: d * Double.random(in: 90...220, using: &rng) + b.velocity, age: 0,
                                   life: Double.random(in: 0.25...0.45, using: &rng), size: Double.random(in: 1.5...3, using: &rng),
                                   hue: Double(k) / Double(count), kind: b.variant))
        }
    }

    /// For tests: puts a bubble exactly where wanted.
    mutating func place(_ bubble: Bubble) {
        bubbles.append(bubble)
    }
}

final class BubbleWandLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig: BubbleWandRig
    private var hint = HandFXHint()
    private let published = StatusBox()

    var status: LensStatus? { published.value }

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        rig = BubbleWandRig(size: size)
        published.value = LensStatus("Hold up your hand", detail: "Touch finger and thumb to make a bubble ring")
    }

    func restart() {
        rig.removeAll()
        hint.reset()
    }

    var bubbles: [BubbleWandRig.Bubble] { rig.bubbles }
    var blown: Int { rig.blown }
    var popped: Int { rig.popped }
    var film: Double { rig.memory.entries.map { $0.state.film.value * $0.presence }.max() ?? 0 }
    var isHinting: Bool { hint.isShowing }

    /// For tests: a bubble at a place, already old enough to pop.
    func addBubble(at p: CGPoint, radius: Double) {
        rig.place(BubbleWandRig.Bubble(position: HandFXKit.vector(p), velocity: .zero, radius: radius, age: 1, life: 30, seed: 1, variant: 0))
    }

    func render(_ input: LensInput) -> CIImage {
        rig.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        published.value = currentStatus(input.hands)
        var out = input.composed
        if !rig.bubbles.isEmpty || !rig.pops.isEmpty || !rig.droplets.particles.isEmpty || film > 0.01,
           let layer = input.services.overlay({ ctx in draw(in: ctx) }) {
            out = layer.composited(over: out)
            if !rig.droplets.particles.isEmpty || !rig.pops.isEmpty,
               let light = input.services.overlay({ ctx in drawSparkle(in: ctx) }) {
                out = HandFXLight.add(light, to: out, rect: input.rect, bloom: 0.5)
            }
        }
        return hint.compose(over: out.cropped(to: input.rect), services: input.services, rect: input.rect, accent: SIMD3(0.6, 0.85, 1))
    }

    private func currentStatus(_ hands: [HandState]) -> LensStatus {
        if hands.isEmpty { return LensStatus("Hold up your hand", detail: "Touch finger and thumb to make a bubble ring") }
        if film > 0.5 { return LensStatus("Wave the ring", detail: "Then poke the bubbles to pop them") }
        if !rig.bubbles.isEmpty { return LensStatus("Pop them!", detail: "Poke a bubble with a fingertip") }
        return LensStatus("Make a ring", detail: "Touch your index finger to your thumb")
    }

    // MARK: Drawing

    /// Three soap bubbles, each with its own run of film colours: clear in the middle, a rainbow sheen toward the rim, a fine edge, and the
    /// reflection of a bright window at the top left. Drawn once.
    private static func sprite(_ variant: Int) -> CGImage? {
        HandFXSprites.named("bubble-\(variant % 3)") { bake(variant % 3) }
    }

    private static func bake(_ variant: Int) -> CGImage? {
        HandFXKit.sprite(width: 96, height: 96) { u, v in
            let x = (u - 0.5) * 2, y = (v - 0.5) * 2
            let d = (x * x + y * y).squareRoot()
            guard d < 1 else { return (0, 0, 0, 0) }
            let angle = atan2(y, x)
            let film = HandFXKit.hsb(angle / (2 * .pi) + 0.5 + Double(variant) * 0.31 + d * 0.25, 0.5, 1)
            let sheen = pow(WorldKit.smoothstep(0.55, 1, d), 1.6) * 0.62
            let edge = exp(-pow((d - 0.965) / 0.03, 2)) * 0.45
            let window = exp(-(pow((x + 0.42) / 0.2, 2) + pow((y - 0.44) / 0.13, 2))) * 0.85
            let glint = exp(-(pow((x - 0.42) / 0.07, 2) + pow((y + 0.48) / 0.07, 2))) * 0.6
            let body = 0.035
            var c = film * sheen + SIMD3(0.35, 0.45, 0.6) * edge + SIMD3(1, 1, 1) * (window + glint + body)
            let a = min(1, sheen + edge + window + glint + body)
            c /= max(a, 1e-4)
            return (min(1, c.x), min(1, c.y), min(1, c.z), a)
        }
    }

    private static let dropletColours: [SIMD3<Double>] = [SIMD3(0.8, 0.9, 1.0), SIMD3(1.0, 0.85, 0.95), SIMD3(0.85, 1.0, 0.9)]
    private static func droplet(_ k: Int) -> CGImage? { HandFXSprites.named("bubble-drop-\(k % 3)") { HandFXKit.speckSprite(dropletColours[k % 3]) } }

    private func draw(in ctx: CGContext) {
        ctx.interpolationQuality = .high
        // The soap film in each ring.
        for entry in rig.memory.entries {
            let show = entry.state.film.value * entry.presence
            guard show > 0.01, let c = entry.state.centre.point, let sprite = Self.sprite(entry.hand.id) else { continue }
            let r = BubbleWandRig.ring(of: entry.hand).radius * (0.7 + 0.3 * show)
            let shimmer = 1 + 0.04 * sin(rig.time * 5)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(show))
            ctx.draw(sprite, in: CGRect(x: c.x - r * shimmer, y: c.y - r / shimmer, width: 2 * r * shimmer, height: 2 * r / shimmer))
            ctx.restoreGState()
        }
        for b in rig.bubbles {
            guard let sprite = Self.sprite(b.variant) else { continue }
            // Newly blown bubbles swell to size; all of them wobble gently.
            let grow = HandFXKit.easeOutBack(min(1, b.age / 0.3), overshoot: 1.2)
            let wobble = sin(b.age * 6 + b.seed) * 0.045 * (1 + 2 * max(0, 1 - b.age))
            let r = b.radius * (0.3 + 0.7 * grow)
            let fade = min(1, (b.life - b.age) / 0.3)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(min(1, fade)))
            ctx.draw(sprite, in: CGRect(x: b.position.x - r * (1 + wobble), y: b.position.y - r * (1 - wobble), width: 2 * r * (1 + wobble), height: 2 * r * (1 - wobble)))
            ctx.restoreGState()
        }
        // A popping bubble's rim flies outward and is gone.
        for p in rig.pops {
            guard let sprite = Self.sprite(p.variant) else { continue }
            let k = p.age / 0.2, r = p.radius * (1 + 0.4 * k)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(0.8 * (1 - k)))
            ctx.draw(sprite, in: CGRect(x: p.position.x - r, y: p.position.y - r, width: 2 * r, height: 2 * r))
            ctx.restoreGState()
        }
    }

    private func drawSparkle(in ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        for p in rig.droplets.particles {
            guard let speck = Self.droplet(p.kind) else { continue }
            ctx.stampDot(speck, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * 2.2, alpha: 1 - p.progress)
        }
        ctx.interpolationQuality = .high
    }
}
