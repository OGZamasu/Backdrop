import CoreGraphics
import CoreImage
import simd

/// Ice that grows on a hand held still. Crystals creep out from the palm along every finger and a cold mist sinks off the fingertips;
/// shake the hand and the ice shatters into shards that tumble away.
///
/// The crystals sit at fixed places along each finger's bones, worked out from the steadied joints every frame, so they ride with the hand
/// and never swim about with the tracker's tremble.
struct FrostHandsRig {
    /// One spot on the hand where a crystal grows: which bones it sits between, how far along, how far to the side, and when it appears.
    struct Slot {
        var from: HandJoint
        var to: HandJoint
        var along: Double
        var side: Double
        /// How much frost there has to be before it grows.
        var threshold: Double
        var size: Double
        var turn: Double
        var variant: Int
    }

    /// What the rig remembers about one hand.
    struct Cold {
        /// 0...1: how far the ice has spread.
        var frost = 0.0
        /// How fast the palm is moving, in palm lengths a second, smoothed.
        var speed = 0.0
        /// Seconds since the last shatter, so one shake does not shatter twice.
        var sinceShatter = 9.0
        var mistOwed = 0.0
    }

    /// The shards and the mist.
    enum Kind: Int {
        case shard = 0, mist = 1, glint = 2
    }

    /// Frost a second while the hand is still: about three seconds to cover it.
    static let growth = 0.34
    /// Palm lengths a second that count as still, and as a shake.
    static let calmBelow = 3.0
    static let shakeAbove = 8.0

    /// Where the crystals grow on any hand: from the palm outward, so the ice spreads toward the fingertips.
    static let slots: [Slot] = {
        var rng = SplitMix64(seed: 0x1CE)
        var out: [Slot] = []
        func add(_ from: HandJoint, _ to: HandJoint, base: Double, count: Int, size: Double) {
            for k in 0..<count {
                let along = (Double(k) + Double.random(in: 0.2...0.8, using: &rng)) / Double(count)
                out.append(Slot(from: from, to: to, along: along, side: Double.random(in: -0.09...0.09, using: &rng),
                                threshold: min(0.97, base + along * 0.18 + Double.random(in: 0...0.06, using: &rng)),
                                size: size * Double.random(in: 0.75...1.2, using: &rng), turn: Double.random(in: 0..<(.pi / 3), using: &rng),
                                variant: Int.random(in: 0..<3, using: &rng)))
            }
        }
        // The palm: across the knuckles and down to the wrist.
        add(.wrist, .middleMCP, base: 0.0, count: 3, size: 0.34)
        add(.indexMCP, .littleMCP, base: 0.06, count: 3, size: 0.3)
        add(.wrist, .thumbCMC, base: 0.1, count: 1, size: 0.26)
        // Each finger, bone by bone, further out needing more frost.
        for finger in Finger.allCases {
            let joints: [HandJoint] = finger == .thumb ? [.thumbCMC, .thumbMP, .thumbIP, .thumbTip]
                : [finger.knuckle, finger.middleJoint, HandJoint(rawValue: finger.middleJoint.rawValue + 1) ?? finger.tip, finger.tip]
            for (i, pair) in zip(joints, joints.dropFirst()).enumerated() {
                add(pair.0, pair.1, base: 0.2 + Double(i) * 0.24, count: 1, size: 0.26 - Double(i) * 0.03)
            }
        }
        return out
    }()

    private(set) var memory = HandFXMemory<Cold>()
    private(set) var particles = ParticleSystem(capacity: 260)
    private(set) var shatters = 0
    private(set) var time = 0.0
    private var steadier = HandFXSteadier()
    private var rng = SplitMix64(seed: 0xF205)

    init() {
        particles.gravity = SIMD2(0, 0)
    }

    mutating func removeAll() {
        memory.removeAll()
        particles.removeAll()
        steadier.removeAll()
    }

    var strongestFrost: Double { memory.entries.map { $0.state.frost * $0.presence }.max() ?? 0 }

    /// Where a slot's crystal is on a hand, in pixels, and how big.
    static func place(_ slot: Slot, on hand: HandState) -> (point: CGPoint, size: Double) {
        let a = HandFXKit.vector(hand[slot.from]), b = HandFXKit.vector(hand[slot.to])
        let d = b - a, l = max(1e-6, simd_length(d))
        let side = SIMD2(-d.y, d.x) / l
        return (HandFXKit.point(a + d * slot.along + side * slot.side * hand.size), slot.size * hand.size)
    }

    mutating func update(hands raw: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        let hands = steadier.update(raw, dt: dt)
        memory.update(hands, dt: dt, fade: 0.45) { _ in Cold() }
        for i in memory.entries.indices {
            var entry = memory.entries[i]
            guard entry.visible else { continue }
            let hand = entry.hand
            let speed = hypot(Double(hand.velocity.dx), Double(hand.velocity.dy)) / hand.size
            entry.state.speed += (speed - entry.state.speed) * min(1, dt / 0.08)
            entry.state.sinceShatter += dt
            if entry.state.speed < Self.calmBelow {
                entry.state.frost = min(1, entry.state.frost + dt * Self.growth)
            }
            let fast = speed > Self.shakeAbove && hypot(Double(hand.velocity.dx), Double(hand.velocity.dy)) > 700
            if fast, entry.state.frost > 0.22, entry.state.sinceShatter > 0.6 {
                shatter(hand, frost: entry.state.frost)
                entry.state.frost = 0
                entry.state.sinceShatter = 0
            }
            mist(from: hand, cold: &entry.state, dt: dt)
            memory.modify(i) { $0 = entry }
        }
        particles.step(dt) { p in
            switch Kind(rawValue: p.kind) ?? .shard {
            case .shard: p.velocity.y -= 900 * dt
            case .mist: p.velocity *= max(0, 1 - 0.8 * dt)
            case .glint: break
            }
        }
    }

    /// Cold air sinks: pale wisps drift down off the fingertips, more as the ice grows. Now and then a crystal catches the light.
    private mutating func mist(from hand: HandState, cold: inout Cold, dt: Double) {
        guard cold.frost > 0.05 else { return }
        cold.mistOwed += dt * 16 * cold.frost
        while cold.mistOwed >= 1 {
            cold.mistOwed -= 1
            let finger = Finger.allCases[Int.random(in: 0..<5, using: &rng)]
            particles.emit(Particle(position: HandFXKit.vector(hand[finger.tip]) + SIMD2(Double.random(in: -6...6, using: &rng), 0),
                                    velocity: SIMD2(Double.random(in: -14...14, using: &rng), Double.random(in: -60 ... -25, using: &rng)), age: 0,
                                    life: Double.random(in: 1.0...1.8, using: &rng), size: Double.random(in: 10...20, using: &rng) * hand.size / 110,
                                    hue: Double.random(in: 0..<1, using: &rng), kind: Kind.mist.rawValue))
        }
        let grown = Self.slots.filter { cold.frost > $0.threshold }
        if !grown.isEmpty, Double.random(in: 0..<1, using: &rng) < dt * 5 * cold.frost {
            let slot = grown[Int.random(in: 0..<grown.count, using: &rng)]
            let at = Self.place(slot, on: hand)
            particles.emit(Particle(position: HandFXKit.vector(at.point), velocity: .zero, age: 0, life: 0.45, size: at.size * 0.9,
                                    hue: Double.random(in: 0..<1, using: &rng), kind: Kind.glint.rawValue))
        }
    }

    /// The ice breaks: a shard flies off from every crystal that had grown.
    private mutating func shatter(_ hand: HandState, frost: Double) {
        shatters += 1
        let palm = HandFXKit.vector(hand.palm)
        let push = SIMD2(Double(hand.velocity.dx), Double(hand.velocity.dy)) * 0.35
        for slot in Self.slots where frost > slot.threshold {
            let at = Self.place(slot, on: hand)
            let p = HandFXKit.vector(at.point)
            let away = simd_length(p - palm) > 1 ? simd_normalize(p - palm) : SIMD2(0, 1)
            let speed = Double.random(in: 120...320, using: &rng)
            particles.emit(Particle(position: p, velocity: away * speed + push + SIMD2(0, 160), age: 0, life: Double.random(in: 0.7...1.1, using: &rng),
                                    size: at.size * Double.random(in: 0.6...1.0, using: &rng), hue: Double.random(in: 0..<1, using: &rng), kind: Kind.shard.rawValue))
        }
    }
}

final class FrostHandsLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig = FrostHandsRig()
    /// How much each crystal has grown, by hand and slot, so a crystal springs up when its turn comes instead of appearing at full size.
    private var grown: [Int: [Double]] = [:]
    private var hint = HandFXHint()
    private let published = StatusBox()

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hand", detail: "Keep it still and it freezes") }

    func restart() {
        rig.removeAll()
        grown.removeAll()
        hint.reset()
    }

    var frost: Double { rig.strongestFrost }
    var shatters: Int { rig.shatters }
    var shardCount: Int { rig.particles.particles.filter { $0.kind == FrostHandsRig.Kind.shard.rawValue }.count }
    var isHinting: Bool { hint.isShowing }

    func render(_ input: LensInput) -> CIImage {
        let dt = WorldKit.clamped(input.dt)
        rig.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        published.value = currentStatus(input.hands)
        growCrystals(dt: dt)

        var out = input.composed
        if !rig.memory.isEmpty || !rig.particles.particles.isEmpty {
            // A cold blue light on a frozen hand.
            for entry in rig.memory.entries where entry.state.frost > 0.02 {
                let c = HandFXPalette.glacier.ice
                out = WorldKit.adding(WorldKit.wash(center: entry.hand.palm, radius: entry.hand.size * 1.9, red: c.x, green: c.y, blue: c.z,
                                                    alpha: 0.22 * entry.state.frost * entry.presence, in: input.rect), to: out)
            }
            if let ice = input.services.overlay({ ctx in drawIce(in: ctx) }) { out = ice.composited(over: out) }
            if let light = input.services.overlay({ ctx in drawLight(in: ctx) }) {
                out = HandFXLight.add(light, to: out, rect: input.rect, bloom: 0.6)
            }
        }
        return hint.compose(over: out, services: input.services, rect: input.rect, accent: HandFXPalette.glacier.ice)
    }

    private func currentStatus(_ hands: [HandState]) -> LensStatus {
        if hands.isEmpty { return LensStatus("Hold up your hand", detail: "Keep it still and it freezes") }
        if rig.strongestFrost > 0.6 { return LensStatus("Frozen solid", detail: "Shake your hand to shatter the ice") }
        if rig.strongestFrost > 0.05 { return LensStatus("Freezing…", detail: "Hold still") }
        return LensStatus("Hold your hand still", detail: "Ice will creep over it")
    }

    private func growCrystals(dt: Double) {
        let ids = Set(rig.memory.entries.map(\.hand.id))
        grown = grown.filter { ids.contains($0.key) }
        for entry in rig.memory.entries {
            var sizes = grown[entry.hand.id] ?? Array(repeating: 0, count: FrostHandsRig.slots.count)
            for (k, slot) in FrostHandsRig.slots.enumerated() {
                let target = entry.state.frost > slot.threshold ? 1.0 : 0.0
                // Grow in about a third of a second; vanish at once when the ice shatters, because the shards take over.
                sizes[k] = target > 0 ? min(1, sizes[k] + dt / 0.32) : 0
            }
            grown[entry.hand.id] = sizes
        }
    }

    // MARK: Drawing

    /// Three ice crystals, each a six-armed star of branching needles: pale and bright inside, with a fine deep-blue edge so they read on
    /// skin and on a white shirt alike.
    private static let crystals: [CGImage?] = (0..<3).map { variant in
        let side = 112
        guard let ctx = HandFXKit.bitmap(width: side, height: side) else { return nil }
        let c = CGPoint(x: Double(side) / 2, y: Double(side) / 2), r = Double(side) * 0.44
        var rng = SplitMix64(seed: UInt64(77 + variant))
        let branches = (0..<3).map { _ in (Double.random(in: 0.3...0.75, using: &rng), Double.random(in: 0.2...0.42, using: &rng)) }
        let path = CGMutablePath()
        for arm in 0..<6 {
            let a = Double(arm) * .pi / 3 + .pi / 2
            let d = SIMD2(cos(a), sin(a)), n = SIMD2(-d.y, d.x)
            let o = HandFXKit.vector(c)
            path.move(to: c)
            path.addLine(to: HandFXKit.point(o + d * r))
            for (at, length) in branches.prefix(variant == 2 ? 3 : 2) {
                let base = o + d * r * at
                for s in [-1.0, 1.0] {
                    path.move(to: HandFXKit.point(base))
                    path.addLine(to: HandFXKit.point(base + (d * 0.6 + n * s * 0.8) * r * length))
                }
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.16, 0.36, 0.72, 0.55])!)
        ctx.setLineWidth(7)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.62, 0.86, 1.0, 1])!)
        ctx.setLineWidth(4.2)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.97, 0.99, 1.0, 1])!)
        ctx.setLineWidth(1.8)
        ctx.strokePath()
        // A hexagonal heart, lit from the top left.
        let hex = CGMutablePath()
        for k in 0..<6 {
            let a = Double(k) * .pi / 3 + .pi / 6
            let p = CGPoint(x: Double(c.x) + cos(a) * r * 0.2, y: Double(c.y) + sin(a) * r * 0.2)
            if k == 0 { hex.move(to: p) } else { hex.addLine(to: p) }
        }
        hex.closeSubpath()
        ctx.addPath(hex)
        ctx.saveGState()
        ctx.clip()
        let stops = [CGColor(colorSpace: space, components: [1, 1, 1, 1])!, CGColor(colorSpace: space, components: [0.45, 0.72, 0.98, 1])!] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: stops, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x - r * 0.2, y: c.y + r * 0.2), end: CGPoint(x: c.x + r * 0.2, y: c.y - r * 0.2), options: [])
        }
        ctx.restoreGState()
        ctx.addPath(hex)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.2, 0.42, 0.78, 0.8])!)
        ctx.setLineWidth(1.2)
        ctx.strokePath()
        return ctx.makeImage()
    }

    /// A shard of broken ice: a sliver with a bright facet on the lit side and a darker one on the other.
    private static let shards: [CGImage?] = (0..<3).map { variant in
        let w = 48, h = 64
        guard let ctx = HandFXKit.bitmap(width: w, height: h) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let tips: [[CGPoint]] = [
            [CGPoint(x: 24, y: 62), CGPoint(x: 40, y: 20), CGPoint(x: 20, y: 2), CGPoint(x: 8, y: 30)],
            [CGPoint(x: 18, y: 60), CGPoint(x: 44, y: 34), CGPoint(x: 26, y: 4), CGPoint(x: 6, y: 22)],
            [CGPoint(x: 28, y: 62), CGPoint(x: 42, y: 8), CGPoint(x: 6, y: 16)],
        ]
        let pts = tips[variant]
        let centre = CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count), y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count))
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            // Facets facing the top left are bright; the others are a cool shade.
            let normal = SIMD2(Double(b.y - a.y), Double(a.x - b.x))
            let lit = simd_dot(simd_normalize(normal), SIMD2(-0.707, 0.707))
            let shade = 0.62 + 0.38 * max(-0.3, lit)
            ctx.beginPath()
            ctx.move(to: centre); ctx.addLine(to: a); ctx.addLine(to: b); ctx.closePath()
            ctx.setFillColor(CGColor(colorSpace: space, components: [0.62 * shade + 0.3, 0.84 * shade + 0.14, 1.0, 0.85])!)
            ctx.fillPath()
        }
        ctx.beginPath()
        ctx.addLines(between: pts)
        ctx.closePath()
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.95, 0.99, 1, 0.95])!)
        ctx.setLineWidth(1.6)
        ctx.strokePath()
        return ctx.makeImage()
    }

    private static let mistSprite: CGImage? = HandFXKit.sprite(width: 48, height: 48) { u, v in
        let d = ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)).squareRoot() * 2
        return (0.8, 0.92, 1.0, exp(-3.2 * d * d) * (1 - WorldKit.smoothstep(0.8, 1, d)))
    }

    /// The crystals and shards, painted solid.
    private func drawIce(in ctx: CGContext) {
        ctx.interpolationQuality = .medium
        for entry in rig.memory.entries {
            guard let sizes = grown[entry.hand.id] else { continue }
            for (k, slot) in FrostHandsRig.slots.enumerated() where sizes[k] > 0.01 {
                guard let sprite = Self.crystals[slot.variant] else { continue }
                let at = FrostHandsRig.place(slot, on: entry.hand)
                let scale = HandFXKit.easeOutBack(sizes[k], overshoot: 2.2)
                ctx.draw(sprite, center: at.point, height: CGFloat(at.size * 1.25 * scale), rotation: CGFloat(slot.turn), alpha: CGFloat(entry.presence * min(1, sizes[k] * 3)))
            }
        }
        for p in rig.particles.particles where p.kind == FrostHandsRig.Kind.shard.rawValue {
            guard let sprite = Self.shards[Int(p.hue * 3) % 3] else { continue }
            let spin = (p.hue - 0.5) * 14 * p.age + p.hue * 6
            let fade = 1 - WorldKit.smoothstep(0.6, 1, p.progress)
            ctx.draw(sprite, center: CGPoint(x: p.position.x, y: p.position.y), height: CGFloat(p.size * 1.1), rotation: CGFloat(spin), alpha: CGFloat(fade))
        }
        ctx.interpolationQuality = .high
    }

    /// The mist and the glints, added as light.
    private func drawLight(in ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        for p in rig.particles.particles {
            let at = CGPoint(x: p.position.x, y: p.position.y)
            switch FrostHandsRig.Kind(rawValue: p.kind) ?? .shard {
            case .mist:
                guard let sprite = Self.mistSprite else { continue }
                ctx.stampDot(sprite, at: at, radius: p.size * (1 + 1.8 * p.progress), alpha: 0.2 * sin(.pi * p.progress))
            case .glint:
                guard let star = WorldKit.star(0.85, 0.95, 1) else { continue }
                ctx.draw(star, center: at, height: CGFloat(p.size * 1.6 * sin(.pi * p.progress)), rotation: CGFloat(p.hue), alpha: CGFloat(sin(.pi * p.progress)))
            case .shard:
                HandFXKit.glow(ctx, at: at, radius: p.size * 0.7, colour: HandFXPalette.glacier.frost, alpha: 0.35 * (1 - p.progress))
            }
        }
        // The frozen hand gives off a faint cold glow along its fingers.
        for entry in rig.memory.entries where entry.state.frost > 0.05 {
            for finger in Finger.allCases {
                HandFXKit.glow(ctx, at: entry.hand[finger.tip], radius: entry.hand.size * 0.26, colour: HandFXPalette.glacier.deep,
                               alpha: 0.3 * entry.state.frost * entry.presence)
            }
        }
        ctx.interpolationQuality = .high
    }
}
