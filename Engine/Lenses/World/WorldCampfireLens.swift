import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// A campfire just below the picture: embers and sparks swirl up past you on the hot air, cooling from white-gold to red as
/// they rise, and the flickering firelight warms you from below.
struct WorldEmberSim {
    struct Ember {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var age = 0.0
        var life: Double
        var size: Double
        /// 0 far behind you ... 1 right by the camera.
        var depth: Double
        var phase: Double

        /// Drawn behind the person.
        var isBehind: Bool { depth < 0.4 }
        /// So close it is a soft blur.
        var isBlur: Bool { depth > 0.95 }
        /// 1 just out of the fire ... 0 burnt out.
        var heat: Double { max(0, 1 - age / life) }
    }

    let size: CGSize
    private(set) var embers: [Ember] = []
    private(set) var time = 0.0
    private var rng: SplitMix64
    private var owed = 0.0
    var capacity = 320
    var rate = 70.0

    init(size: CGSize, seed: UInt64 = 0xE3B5) {
        self.size = size
        rng = SplitMix64(seed: seed)
    }

    /// How bright the fire is right now, about 0.65...1: a restless flicker made of a few uneven waves.
    static func flicker(at t: Double) -> Double {
        let f = 0.82 + 0.08 * sin(t * 7.3) + 0.05 * sin(t * 13.1 + 1.1) + 0.04 * sin(t * 2.3 + 0.4) + 0.03 * sin(t * 23.7)
        return min(1, max(0.6, f))
    }

    mutating func removeAll() {
        embers.removeAll()
        time = 0
    }

    /// Puts an ember somewhere. For tests.
    mutating func insert(_ ember: Ember) { embers.append(ember) }

    mutating func step(_ rawDt: Double, matte: MatteQuery?) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        owed += rate * dt * (0.7 + 0.5 * Self.flicker(at: time))
        while owed >= 1 {
            owed -= 1
            // Most come up from the middle, where the fire is; a few from further out.
            let spread = (Double.random(in: -1...1, using: &rng) + Double.random(in: -1...1, using: &rng)) * 0.5
            let x = size.width * (0.5 + 0.55 * spread)
            let depth = Double.random(in: 0...1, using: &rng)
            embers.append(Ember(position: SIMD2(x, -12), velocity: SIMD2(Double.random(in: -50...50, using: &rng), Double.random(in: 150...330, using: &rng)),
                                life: Double.random(in: 1.6...3.4, using: &rng), size: Double.random(in: 1.2...3.2, using: &rng) * (0.7 + 0.6 * depth),
                                depth: depth, phase: Double.random(in: 0...(2 * .pi), using: &rng)))
        }
        if embers.count > capacity { embers.removeFirst(embers.count - capacity) }

        let t = time
        for i in embers.indices {
            var e = embers[i]
            e.age += dt
            // Hot air swirls: a few crossing waves push it side to side, and it slows as it cools.
            let swirl = sin(e.position.y * 0.011 + t * 1.7 + e.phase) + 0.6 * sin(e.position.y * 0.027 - t * 2.6 + e.phase * 2)
            e.velocity.x += swirl * 190 * dt
            e.velocity.y += (40 * e.heat - 25) * dt
            e.velocity *= exp(-0.55 * dt)
            // Rising past your head it catches the hot air coming off you and is lifted a little faster.
            if let matte, !e.isBehind, matte.coverage(x: e.position.x, y: e.position.y - 30) > 0.5, matte.coverage(x: e.position.x, y: e.position.y) < 0.5 {
                e.velocity.y += 120 * dt
            }
            e.position += e.velocity * dt
            embers[i] = e
        }
        embers.removeAll { $0.age >= $0.life || $0.position.y > size.height + 30 || $0.position.x < -60 || $0.position.x > size.width + 60 }
    }
}

final class WorldCampfireLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    /// "Hearth": the colours of firelight, from the hottest to the coolest.
    static let fire = SIMD3<Double>(1.0, 0.52, 0.16)
    static let hot = SIMD3<Double>(1.0, 0.86, 0.5)

    private var sim: WorldEmberSim

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        sim = WorldEmberSim(size: size)
        // Start with the air already full of sparks.
        for _ in 0..<70 { sim.step(1.0 / 30, matte: nil) }
    }

    func restart() {
        sim.removeAll()
        for _ in 0..<70 { sim.step(1.0 / 30, matte: nil) }
    }

    var embers: [WorldEmberSim.Ember] { sim.embers }
    var firelight: Double { WorldEmberSim.flicker(at: sim.time) }

    func render(_ input: LensInput) -> CIImage {
        sim.step(input.dt, matte: input.matteGrid)
        let rect = input.rect
        let f = WorldEmberSim.flicker(at: sim.time)

        // Night, warmed from below: a glow rising off the bottom edge where the fire is.
        let night = WorldKit.grade(input.scenery, saturation: 0.6, tint: (0.15, 0.11, 0.13), lift: (0.003, 0.001, 0.002))
        // Two soft round pools of light from below: a wide dim one and a brighter one close to the fire.
        let firelight = WorldKit.adding(
            WorldKit.wash(center: CGPoint(x: rect.midX, y: rect.minY - 300), radius: 820, red: Self.fire.x, green: Self.fire.y, blue: Self.fire.z, alpha: 0.6 * f, in: rect),
            to: WorldKit.wash(center: CGPoint(x: rect.midX, y: rect.minY - 40), radius: 260, red: Self.hot.x, green: Self.hot.y * 0.8, blue: Self.hot.z * 0.6, alpha: 0.35 * f, in: rect))
            .settingAlphaOne(in: rect)
        var room = WorldKit.adding(firelight, to: night)
        if let layer = input.services.overlay({ ctx in draw(in: ctx, behind: true) }) { room = WorldKit.adding(layer, to: room) }

        let person = WorldKit.grade(input.composed, saturation: 0.95, tint: (0.48, 0.38, 0.36), lift: (0.004, 0.002, 0.002))
        var body = WorldKit.place(person: person, over: room, matte: input.matte, rect: rect)
        if let matte = input.matte {
            // Firelight on you: brightest low down and on the edges facing the fire.
            body = WorldKit.adding(WorldKit.multiply(WorldKit.brightened(firelight, 0.55), matte).cropped(to: rect), to: body)
            if let rim = WorldKit.rimLight(matte: matte, rect: rect, toward: SIMD2(0, -1), width: 18, colour: Self.fire * 0.8 + Self.hot * 0.2, strength: 0.75 * f) {
                body = WorldKit.adding(rim, to: body)
            }
        }
        guard let front = input.services.overlay({ ctx in draw(in: ctx, behind: false) }) else { return body }
        return WorldKit.adding(front, to: body).cropped(to: rect)
    }

    private func draw(in ctx: CGContext, behind: Bool) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        defer {
            ctx.setBlendMode(.normal)
            ctx.interpolationQuality = .high
        }
        for e in sim.embers where e.isBehind == behind {
            let h = e.heat
            // White-gold out of the fire, through orange, to a dull red as it dies.
            let c = SIMD3(1.0, 0.25 + 0.7 * h * h, 0.06 + 0.5 * pow(h, 3))
            let twinkle = 0.75 + 0.25 * sin(e.age * 19 + e.phase * 7)
            let fade = min(1, e.age / 0.15) * min(1, h * 3) * twinkle * (behind ? 0.75 : 1)
            let at = CGPoint(x: e.position.x, y: e.position.y)
            if e.isBlur {
                if let blot = WorldKit.softGlow(1, 0.45 + 0.3 * h, 0.12) { ctx.stampDot(blot, at: at, radius: 9 + 6 * e.size, alpha: 0.26 * fade) }
                continue
            }
            let speed = simd_length(e.velocity)
            if speed > 40, let tail = WorldKit.comet(c.x, c.y, c.z) {
                let length = min(46, speed * 0.09) + e.size * 2
                ctx.saveGState()
                ctx.translateBy(x: at.x, y: at.y)
                ctx.rotate(by: atan2(e.velocity.y, e.velocity.x))
                ctx.setAlpha(CGFloat(fade * 0.9))
                ctx.draw(tail, in: CGRect(x: -length, y: -e.size * 1.5, width: length + e.size * 0.5, height: e.size * 3))
                ctx.restoreGState()
            }
            if let glow = WorldKit.softGlow(c.x, c.y, c.z) { ctx.stampDot(glow, at: at, radius: e.size * 3.4, alpha: 0.5 * fade) }
            if let core = WorldKit.softGlow(1, min(1, c.y + 0.25), min(1, c.z + 0.3)) { ctx.stampDot(core, at: at, radius: e.size * 1.1, alpha: fade) }
        }
    }
}
