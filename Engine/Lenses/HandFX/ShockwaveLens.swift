import CoreGraphics
import CoreImage
import simd

/// A shockwave you set off with a clap, or by pushing an open palm at the camera. A ring rushes out across the picture, bending it like a
/// lens as it passes, with a soft flash where it started and dust thrown outward. As two hands come together, light gathers between them.
///
/// Hands that meet often vanish from the tracker just before they touch, so a clap counts when two hands that were closing in fast get
/// close, or when one of them disappears while they were close and closing. A push is a palm that quickly looks a quarter bigger.
struct ShockwaveRig {
    struct Wave {
        var centre: CGPoint
        var age = 0.0
        /// 1 for a clap, a little less for a push.
        var strength: Double
    }

    /// What the rig remembers about one hand: how big it has looked lately, for spotting a push.
    struct Pusher {
        var sizes: [(time: Double, size: Double)] = []
        var cooldown = 0.0
    }

    /// Seconds a wave takes to cross the picture.
    static let life = 1.4
    static let maxWaves = 3

    private(set) var waves: [Wave] = []
    private(set) var memory = HandFXMemory<Pusher>()
    private(set) var dust = ParticleSystem(capacity: 180)
    private(set) var time = 0.0
    private(set) var claps = 0
    private(set) var pushes = 0
    /// How close two hands are, 0 far apart to 1 almost touching, eased: the light that gathers before a clap.
    private(set) var gathering = HandFXLevel(rise: 0.08, fall: 0.2)
    private(set) var gatherPoint: CGPoint?
    /// The gap between the two hands lately, in palm lengths, with where they met.
    private var gaps: [(time: Double, gap: Double, middle: CGPoint)] = []
    private var cooldown = 0.0
    private var lastFired = -9.0
    private var steadier = HandFXSteadier()
    private var rng = SplitMix64(seed: 0x5A0C)

    init() {
        dust.gravity = .zero
        dust.drag = 1.6
    }

    mutating func removeAll() {
        self = ShockwaveRig()
    }

    /// How far out a wave has gone, in pixels, `progress` of the way through its life.
    static func radius(progress: Double) -> Double { 30 + 1250 * (1 - pow(1 - min(1, max(0, progress)), 1.6)) }

    mutating func update(hands raw: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        cooldown = max(0, cooldown - dt)
        let hands = steadier.update(raw, dt: dt)
        memory.update(hands, dt: dt, fade: 0.2) { _ in Pusher() }
        detectClap(hands, dt: dt)
        detectPush(dt: dt)
        for i in waves.indices { waves[i].age += dt }
        waves.removeAll { $0.age > Self.life }
        dust.step(dt)
    }

    private mutating func detectClap(_ hands: [HandState], dt: Double) {
        gaps.removeAll { time - $0.time > 0.45 }
        if hands.count >= 2 {
            let a = hands[0], b = hands[1]
            let size = (a.size + b.size) / 2
            let gap = HandFXKit.distance(a.palm, b.palm) / size
            let middle = HandFXKit.lerp(a.palm, b.palm, 0.5)
            gaps.append((time, gap, middle))
            let widest = gaps.map(\.gap).max() ?? gap
            // Right after a clap the light has been spent; it gathers again as the hands part and meet once more.
            let spent = min(1, time - lastFired) / 0.9
            gathering.approach((1 - WorldKit.smoothstep(1.3, 4.2, gap)) * min(1, spent), dt: dt)
            gatherPoint = middle
            if gap < 1.7, widest - gap > 1.1, cooldown <= 0 {
                fire(at: middle, strength: 1)
                claps += 1
            }
        } else {
            // One of the two vanished: if they were close and closing in, they met.
            if let last = gaps.last, time - last.time < 0.1, last.gap < 2.8, (gaps.map(\.gap).max() ?? 0) - last.gap > 0.9, cooldown <= 0 {
                fire(at: last.middle, strength: 1)
                claps += 1
            }
            gaps.removeAll()
            gathering.approach(0, dt: dt)
        }
    }

    /// A palm pushed at the camera grows quickly in the picture.
    private mutating func detectPush(dt: Double) {
        for i in memory.entries.indices {
            var entry = memory.entries[i]
            entry.state.cooldown = max(0, entry.state.cooldown - dt)
            guard entry.visible else { memory.modify(i) { $0 = entry }; continue }
            entry.state.sizes.append((time, entry.hand.size))
            entry.state.sizes.removeAll { time - $0.time > 0.35 }
            let smallest = entry.state.sizes.map(\.size).min() ?? entry.hand.size
            let open = HandFXPose.openness(entry.hand)
            if open > 0.6, entry.hand.size > smallest * 1.25, entry.state.cooldown <= 0, cooldown <= 0, entry.age > 0.2 {
                fire(at: entry.hand.palm, strength: 0.8)
                pushes += 1
                entry.state.cooldown = 0.8
                entry.state.sizes.removeAll()
            }
            memory.modify(i) { $0 = entry }
        }
    }

    private mutating func fire(at centre: CGPoint, strength: Double) {
        cooldown = 0.45
        lastFired = time
        gathering.value = 0
        waves.append(Wave(centre: centre, strength: strength))
        if waves.count > Self.maxWaves { waves.removeFirst() }
        gaps.removeAll()
        for _ in 0..<44 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            let d = SIMD2(cos(a), sin(a))
            dust.emit(Particle(position: HandFXKit.vector(centre) + d * Double.random(in: 10...40, using: &rng),
                               velocity: d * Double.random(in: 500...1300, using: &rng), age: 0, life: Double.random(in: 0.5...0.9, using: &rng),
                               size: Double.random(in: 2...4, using: &rng), hue: Double.random(in: 0..<1, using: &rng)))
        }
    }
}

final class ShockwaveLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig = ShockwaveRig()
    private var hint = HandFXHint()
    private let published = StatusBox()

    static let colour = SIMD3<Double>(0.72, 0.86, 1.0)
    static let accent = SIMD3<Double>(0.62, 0.5, 1.0)

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hands", detail: "Clap to send a shockwave") }

    func restart() {
        rig.removeAll()
        hint.reset()
    }

    var waves: [ShockwaveRig.Wave] { rig.waves }
    var claps: Int { rig.claps }
    var pushes: Int { rig.pushes }
    var isHinting: Bool { hint.isShowing }

    func render(_ input: LensInput) -> CIImage {
        rig.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        published.value = currentStatus(input.hands)

        var out = input.composed
        // Each ring bends the picture as it passes, like a lens. Clamped first, so the edges never pull in emptiness.
        for wave in rig.waves {
            let k = wave.age / ShockwaveRig.life
            out = out.clampedToExtent().applyingFilter("CITorusLensDistortion", parameters: [
                kCIInputCenterKey: CIVector(cgPoint: wave.centre),
                kCIInputRadiusKey: ShockwaveRig.radius(progress: k),
                kCIInputWidthKey: (46 + 80 * k) * wave.strength,
                "inputRefraction": 1.6 * pow(1 - k, 1.3) * wave.strength,
            ]).cropped(to: input.rect)
        }
        if !rig.waves.isEmpty || !rig.dust.particles.isEmpty || rig.gathering.value > 0.01,
           let layer = input.services.overlay({ ctx in draw(in: ctx) }) {
            out = HandFXLight.add(layer, to: out, rect: input.rect, bloom: 0.8)
        }
        return hint.compose(over: out, services: input.services, rect: input.rect, accent: Self.accent)
    }

    private func currentStatus(_ hands: [HandState]) -> LensStatus {
        if let last = rig.waves.last, last.age < 0.8 { return LensStatus("Boom!", detail: "Clap again, or push your palm at the camera") }
        if hands.isEmpty { return LensStatus("Hold up your hands", detail: "Clap to send a shockwave") }
        return LensStatus("Clap your hands", detail: "Or push your palm at the camera")
    }

    // MARK: Drawing

    private static let speck = HandFXKit.speckSprite(colour)

    private func draw(in ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        // Light gathering between two hands as they close in.
        let g = rig.gathering.value
        if g > 0.01, let p = rig.gatherPoint {
            let pulse = 1 + 0.08 * sin(rig.time * 14)
            HandFXKit.glow(ctx, at: p, radius: (40 + 90 * g) * pulse, colour: Self.accent, alpha: 0.4 * g)
            HandFXKit.glow(ctx, at: p, radius: (10 + 22 * g) * pulse, colour: HandFXPalette.white, alpha: 0.45 * g * g)
            for entry in rig.memory.entries where entry.visible {
                HandFXKit.glow(ctx, at: entry.hand.palm, radius: entry.hand.size * 0.9, colour: Self.colour, alpha: 0.35 * g * entry.presence)
            }
        }
        for wave in rig.waves {
            let k = wave.age / ShockwaveRig.life
            let r = ShockwaveRig.radius(progress: k)
            let fade = pow(1 - k, 1.2) * wave.strength
            let rect = CGRect(x: wave.centre.x - r, y: wave.centre.y - r, width: r * 2, height: r * 2)
            // The ring: a broad faint band with a bright thin edge on the outside.
            ctx.setLineWidth(CGFloat(30 + 50 * k))
            ctx.setStrokeColor(HandFXKit.cgColor(Self.accent, 0.12 * fade))
            ctx.strokeEllipse(in: rect.insetBy(dx: 10, dy: 10))
            ctx.setLineWidth(3)
            ctx.setStrokeColor(HandFXKit.cgColor(Self.colour, 0.7 * fade))
            ctx.strokeEllipse(in: rect)
            // A soft flash where it began, gone in a quarter of a second.
            let flash = max(0, 1 - wave.age / 0.25)
            if flash > 0 {
                HandFXKit.glow(ctx, at: wave.centre, radius: 120 + 260 * (1 - flash), colour: Self.colour, alpha: 0.32 * flash * flash * wave.strength)
            }
        }
        if let speck = Self.speck {
            for p in rig.dust.particles {
                ctx.stampDot(speck, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * 2.2, alpha: 1 - p.progress)
            }
        }
        ctx.interpolationQuality = .high
    }
}
