import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// A night sky of fireworks. Rockets climb trailing embers, burst into one of a few shells, and the sparks hang in the air, fade
/// through orange and drift down.
struct FireworkSkySim {
    enum Shell: CaseIterable {
        /// A round ball of sparks.
        case peony
        /// A tilted ring, with a smaller one inside it.
        case ring
        /// Gold sparks that droop like a willow tree.
        case willow
        /// Two balls, one inside the other, in different colours.
        case chrysanthemum
        case heart
    }

    struct Rocket {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var shell: Shell
        var hue: Double
        var age = 0.0
    }

    struct Flash {
        var position: SIMD2<Double>
        var hue: Double
        var age = 0.0
    }

    /// What a spark is, which sets how it slows and how it looks.
    enum Kind: Int {
        case star = 0, ember, willow
    }

    let size: CGSize
    private(set) var rockets: [Rocket] = []
    private(set) var flashes: [Flash] = []
    private(set) var sparks = ParticleSystem(capacity: 560)
    private(set) var time = 0.0
    private(set) var bursts = 0
    private var rng: SplitMix64
    private var untilLaunch = 0.15
    /// Whether rockets go up by themselves. Tests switch it off to burst a shell exactly where they want it.
    var launchesByItself = true

    init(size: CGSize, seed: UInt64 = 0xF1AE) {
        self.size = size
        rng = SplitMix64(seed: seed)
        sparks.gravity = SIMD2(0, -55)
    }

    mutating func removeAll() {
        rockets.removeAll()
        flashes.removeAll()
        sparks.removeAll()
        untilLaunch = 0.15
        time = 0
    }

    /// The colours of a hue wheel, worked out once.
    static let hueTable: [SIMD3<Double>] = (0..<36).map { i in
        let c = Palette.rgb(hue: Double(i) / 36, saturation: 0.85)
        return SIMD3(c.r, c.g, c.b)
    }

    static func colour(hue: Double) -> SIMD3<Double> {
        let wrapped = hue - hue.rounded(.down)
        return hueTable[min(hueTable.count - 1, Int(wrapped * Double(hueTable.count)))]
    }

    /// Light a flash throws on the people in front of it, as red, green and blue to add.
    var skyLight: SIMD3<Double> {
        flashes.reduce(SIMD3<Double>.zero) { $0 + Self.colour(hue: $1.hue) * exp(-$1.age / 0.28) }
    }

    // MARK: Launching and bursting

    mutating func launch(x: Double, topY: Double, hue: Double, shell: Shell) {
        let g = 430.0
        let v = (2 * g * (topY + 10)).squareRoot()
        rockets.append(Rocket(position: SIMD2(x, -10), velocity: SIMD2(Double.random(in: -26...26, using: &rng), v), shell: shell, hue: hue))
    }

    private mutating func launchRandom() {
        let shell = Self.pick(&rng)
        launch(x: Double.random(in: size.width * 0.12...size.width * 0.88, using: &rng),
               topY: Double.random(in: size.height * 0.52...size.height * 0.86, using: &rng),
               hue: Double.random(in: 0..<1, using: &rng), shell: shell)
    }

    private static func pick(_ rng: inout SplitMix64) -> Shell {
        let r = Double.random(in: 0..<1, using: &rng)
        return r < 0.30 ? .peony : r < 0.52 ? .ring : r < 0.70 ? .willow : r < 0.90 ? .chrysanthemum : .heart
    }

    private mutating func spark(_ at: SIMD2<Double>, _ velocity: SIMD2<Double>, hue: Double, kind: Kind, life: ClosedRange<Double>, size s: ClosedRange<Double>) {
        // A negative hue means white; any other is wrapped onto the colour wheel.
        sparks.emit(Particle(position: at, velocity: velocity, age: 0, life: Double.random(in: life, using: &rng),
                             size: Double.random(in: s, using: &rng), hue: hue < -0.5 ? -1 : hue - hue.rounded(.down), kind: kind.rawValue))
    }

    /// Bursts a shell where `at` is.
    mutating func detonate(at: SIMD2<Double>, hue: Double, shell: Shell) {
        bursts += 1
        flashes.append(Flash(position: at, hue: hue))
        let reach = Double.random(in: 220...330, using: &rng)
        switch shell {
        case .peony:
            for _ in 0..<100 {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                let v = reach * 1.7 * Double.random(in: 0.7...1.0, using: &rng)
                let white = Double.random(in: 0...1, using: &rng) < 0.12
                spark(at, SIMD2(cos(a), sin(a)) * v, hue: white ? -1 : hue + Double.random(in: -0.025...0.025, using: &rng),
                      kind: .star, life: 1.9...2.8, size: 3.2...5.2)
            }
        case .ring:
            let tilt = Double.random(in: 0.3...0.95, using: &rng), turn = Double.random(in: 0..<(2 * .pi), using: &rng)
            for ring in 0..<2 {
                let n = ring == 0 ? 64 : 30, scale = ring == 0 ? 1.0 : 0.5
                let inner = hue + 0.5
                for k in 0..<n {
                    let a = Double(k) / Double(n) * 2 * .pi
                    // A circle squashed by the tilt and turned: a ring seen at an angle.
                    let x = cos(a), y = sin(a) * tilt
                    let v = SIMD2(x * cos(turn) - y * sin(turn), x * sin(turn) + y * cos(turn)) * reach * 1.7 * scale
                    spark(at, v, hue: ring == 0 ? hue : inner, kind: .star, life: 1.9...2.6, size: 3.4...5)
                }
            }
        case .willow:
            for _ in 0..<64 {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                spark(at, SIMD2(cos(a), sin(a)) * reach * 0.95 * Double.random(in: 0.5...1.0, using: &rng), hue: 0.11 + Double.random(in: -0.015...0.02, using: &rng),
                      kind: .willow, life: 3.0...4.4, size: 2.8...4.4)
            }
        case .chrysanthemum:
            for layer in 0..<2 {
                for _ in 0..<(layer == 0 ? 70 : 40) {
                    let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                    let v = reach * (layer == 0 ? 1.75 : 0.95) * Double.random(in: 0.8...1.0, using: &rng)
                    spark(at, SIMD2(cos(a), sin(a)) * v, hue: layer == 0 ? hue : hue + 0.33, kind: .star, life: 1.9...2.7, size: 3...5)
                }
            }
        case .heart:
            for k in 0..<56 {
                let t = Double(k) / 56 * 2 * .pi
                let x = 16 * pow(sin(t), 3)
                let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
                let scale = reach * 1.2 / 16
                spark(at, SIMD2(x, y) * scale * 1.55, hue: 0.96 + Double.random(in: -0.03...0.03, using: &rng), kind: .star, life: 2.0...2.7, size: 3.6...5)
            }
        }
    }

    // MARK: Time

    mutating func step(_ rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        time += dt

        untilLaunch -= dt
        if untilLaunch <= 0, rockets.count < 4, launchesByItself {
            launchRandom()
            // Sometimes a second one follows close behind.
            if Double.random(in: 0..<1, using: &rng) < 0.3 { untilLaunch = 0.28 } else { untilLaunch = Double.random(in: 0.8...1.9, using: &rng) }
        }

        var finished: [Rocket] = []
        for i in rockets.indices {
            rockets[i].velocity.y -= 430 * dt
            rockets[i].position += rockets[i].velocity * dt
            rockets[i].age += dt
            let r = rockets[i]
            for _ in 0..<2 {
                spark(r.position + SIMD2(Double.random(in: -2...2, using: &rng), 0), SIMD2(Double.random(in: -22...22, using: &rng), Double.random(in: (-90)...(-20), using: &rng)),
                      hue: 0.1, kind: .ember, life: 0.35...0.7, size: 2...3.2)
            }
            if r.velocity.y <= 30 { finished.append(r) }
        }
        rockets.removeAll { $0.velocity.y <= 30 }
        for r in finished { detonate(at: r.position, hue: r.hue, shell: r.shell) }

        sparks.step(dt) { p in
            let k: Double
            switch Kind(rawValue: p.kind) ?? .star {
            case .star: k = 1.55
            case .ember: k = 2.5
            case .willow:
                k = 0.95
                p.velocity.y -= 150 * dt        // droops
            }
            p.velocity *= exp(-k * dt)
        }
        for i in flashes.indices { flashes[i].age += dt }
        flashes.removeAll { $0.age > 0.9 }
    }
}

final class FireworkSkyLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private var show: FireworkSkySim
    private let stars: [(x: Double, y: Double, rate: Double, phase: Double, size: Double)]

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        show = FireworkSkySim(size: size)
        stars = (0..<60).map { i in
            (x: WorldKit.hash(i * 7 + 1) * size.width, y: size.height * (0.28 + 0.72 * WorldKit.hash(i * 7 + 2)),
             rate: 0.8 + 2.4 * WorldKit.hash(i * 7 + 3), phase: 6.28 * WorldKit.hash(i * 7 + 4), size: 1.3 + 1.7 * WorldKit.hash(i * 7 + 5))
        }
    }

    func restart() {
        show.removeAll()
        puffs.removeAll()
        presence.reset()
    }

    var sparkCount: Int { show.sparks.particles.count }
    var rocketCount: Int { show.rockets.count }
    var burstCount: Int { show.bursts }
    /// Whether rockets go up by themselves. Tests switch it off to place a burst exactly.
    var launchesByItself: Bool {
        get { show.launchesByItself }
        set { show.launchesByItself = newValue }
    }
    /// Bursts a shell straight away. For tests and previews.
    func burst(at p: CGPoint, hue: Double, shell: FireworkSkySim.Shell = .peony) { show.detonate(at: SIMD2(p.x, p.y), hue: hue, shell: shell) }

    func render(_ input: LensInput) -> CIImage {
        show.step(input.dt)
        stepSmoke(WorldKit.clamped(input.dt))
        presence.update(grid: input.matteGrid, dt: input.dt)
        let rect = input.rect

        // The room goes dark; the person keeps their colour and catches the light of each burst on the side facing it.
        let sky = WorldKit.grade(input.scenery, saturation: 0.5, tint: (0.09, 0.12, 0.22), lift: (0.001, 0.002, 0.008))
        let glow = show.skyLight
        let person = WorldKit.grade(input.composed, saturation: 0.9, tint: (0.55, 0.58, 0.75),
                                    lift: (0.003 + 0.025 * glow.x, 0.003 + 0.025 * glow.y, 0.006 + 0.025 * glow.z))
        // The skyline and the drifting smoke sit in the sky; the bursts light them, then the sparks are added on top.
        var lit = sky
        if let skyline = skylineImage { lit = skyline.composited(over: lit) }
        if let smoke = softSmoke.draw(rect: rect, { ctx in drawSmoke(in: ctx) }) { lit = smoke.composited(over: lit) }
        for f in show.flashes {
            let k = exp(-f.age / 0.24), c = FireworkSkySim.colour(hue: f.hue) * 0.65 + SIMD3(0.35, 0.35, 0.35)
            let at = CGPoint(x: f.position.x, y: f.position.y)
            lit = WorldKit.adding(WorldKit.wash(center: at, radius: 380, red: c.x, green: c.y, blue: c.z, alpha: 0.1 * k, in: rect), to: lit)
            lit = WorldKit.adding(WorldKit.wash(center: at, radius: 110, red: 1, green: 0.97, blue: 0.9, alpha: 0.45 * k * k, in: rect), to: lit)
        }
        var behind = lit
        if let layer = input.services.overlay({ ctx in draw(in: ctx, time: input.time) }) { behind = WorldKit.adding(layer, to: lit) }
        var body = WorldKit.place(person: person, over: behind, matte: input.matte, rect: rect)

        // The brightest burst right now lights the edge of you that faces it.
        if let key = show.flashes.max(by: { $0.age > $1.age }), key.age < 0.9 {
            let k = exp(-key.age / 0.3)
            let c = FireworkSkySim.colour(hue: key.hue)
            let toward = key.position - presence.centre
            if simd_length(toward) > 1, let rim = WorldKit.rimLight(matte: input.matte, rect: rect, toward: simd_normalize(toward), width: 14,
                                                                   colour: c * 0.7 + SIMD3(0.3, 0.3, 0.3), strength: 0.9 * k) {
                body = WorldKit.adding(rim, to: body)
            }
        }
        return body
    }

    // MARK: Smoke and skyline

    private var presence = WorldPresence()
    private var puffs: [(position: SIMD2<Double>, velocity: SIMD2<Double>, age: Double, size: Double)] = []
    private var seenBursts = 0
    private var rng = SplitMix64(seed: 0x5307E)

    private func stepSmoke(_ dt: Double) {
        if show.bursts != seenBursts {
            for f in show.flashes where f.age < 0.05 {
                for _ in 0..<5 {
                    let offset = SIMD2(Double.random(in: -110...110, using: &rng), Double.random(in: -90...70, using: &rng))
                    puffs.append((f.position + offset, SIMD2(Double.random(in: -14...14, using: &rng), Double.random(in: -6...10, using: &rng)),
                                  0, Double.random(in: 70...130, using: &rng)))
                }
            }
            seenBursts = show.bursts
            if puffs.count > 60 { puffs.removeFirst(puffs.count - 60) }
        }
        for i in puffs.indices {
            puffs[i].age += dt
            puffs[i].position += (puffs[i].velocity + SIMD2(9, 0)) * dt
        }
        puffs.removeAll { $0.age > 7 }
    }

    private lazy var skylineImage = WorldKit.ciSprite(Self.skyline)
    private let softSmoke = WorldSoftCanvas()

    /// The smoke of earlier bursts hanging in the sky, painted small and scaled up.
    private func drawSmoke(in ctx: CGContext) {
        guard let smoke = WorldKit.softGlow(0.42, 0.44, 0.56) else { return }
        ctx.interpolationQuality = .low
        for p in puffs {
            let k = p.age / 7
            let swell = 1 + 0.6 * k
            let alpha = 0.16 * min(1, p.age / 0.6) * (1 - k) * (1 - k)
            ctx.stampDot(smoke, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * swell, alpha: alpha)
        }
        ctx.interpolationQuality = .high
    }

    /// "Harbour night": far hills, then a row of buildings with a few warm windows lit, drawn once.
    private static let skyline: CGImage? = {
        let w = 1280, h = 170
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        // Far hills, a little lighter than the night above them where they meet it.
        let hills = CGMutablePath()
        hills.move(to: CGPoint(x: 0, y: 0))
        for x in stride(from: 0, through: w, by: 16) {
            let u = Double(x) / Double(w)
            hills.addLine(to: CGPoint(x: Double(x), y: 92 + 22 * sin(u * 7.1 + 0.4) + 12 * sin(u * 17.3 + 1.2)))
        }
        hills.addLine(to: CGPoint(x: w, y: 0))
        hills.closeSubpath()
        ctx.addPath(hills)
        ctx.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.15, alpha: 1))
        ctx.fillPath()
        // Buildings of varied height, darker, with lit windows.
        var x = -10.0
        var i = 0
        while x < Double(w) {
            let width = 34 + 46 * WorldKit.hash(i * 3 + 1)
            let height = 34 + 74 * pow(WorldKit.hash(i * 3 + 2), 1.6)
            let rect = CGRect(x: x, y: 0, width: width, height: height)
            ctx.setFillColor(CGColor(red: 0.035, green: 0.035, blue: 0.08, alpha: 1))
            ctx.fill(rect)
            // A faint edge of sky light on the roof.
            ctx.setFillColor(CGColor(red: 0.16, green: 0.16, blue: 0.3, alpha: 1))
            ctx.fill(CGRect(x: x, y: height - 1.5, width: width, height: 1.5))
            for row in stride(from: 8.0, to: height - 8, by: 11) {
                for col in stride(from: 6.0, to: width - 6, by: 9) where WorldKit.hash(Int(x * 7 + row * 131 + col * 17)) < 0.16 {
                    let warm = WorldKit.hash(Int(x + row * 3 + col)) < 0.7
                    ctx.setFillColor(warm ? CGColor(red: 1, green: 0.78, blue: 0.42, alpha: 0.75) : CGColor(red: 0.7, green: 0.85, blue: 1, alpha: 0.6))
                    ctx.fill(CGRect(x: x + col, y: row, width: 4, height: 5))
                }
            }
            x += width + 2 + 10 * WorldKit.hash(i * 3 + 3)
            i += 1
        }
        return ctx.makeImage()
    }()

    // MARK: Drawing

    /// A spark's tail and glow in one colour, made once.
    private struct Look {
        var tail: CGImage?
        var glow: CGImage?
    }

    private enum Stage: Int {
        /// White-hot just after the burst.
        case hot = 0
        case normal, ember
        /// The warm gold of a willow.
        case willow
        /// What a rocket leaves behind.
        case trail
    }

    private var looks = [Look?](repeating: nil, count: 37 * 5)

    /// The sprites for a hue (negative for white) at one stage of a spark's life.
    private func look(hue: Double, stage: Stage) -> Look {
        let h = hue < 0 ? 36 : min(35, Int(hue * 36))
        let key = h * 5 + stage.rawValue
        if let made = looks[key] { return made }
        var c = h == 36 ? SIMD3<Double>(1, 1, 1) : FireworkSkySim.hueTable[h]
        switch stage {
        case .hot: c += (SIMD3<Double>(1, 1, 1) - c) * 0.75
        case .normal: break
        case .ember: c += (SIMD3<Double>(1, 0.42, 0.1) - c) * 0.55
        case .willow: c = SIMD3(1, 0.68, 0.26)
        case .trail: c = SIMD3(1, 0.7, 0.22)
        }
        let made = Look(tail: WorldKit.comet(c.x, c.y, c.z), glow: WorldKit.softGlow(c.x, c.y, c.z))
        looks[key] = made
        return made
    }

    private func draw(in ctx: CGContext, time: Double) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        defer {
            ctx.setBlendMode(.normal)
            ctx.interpolationQuality = .high
        }
        let white = WorldKit.softGlow(1, 1, 1)
        if let dot = WorldKit.softGlow(0.85, 0.9, 1) {
            for s in stars {
                let twinkle = 0.5 + 0.5 * sin(time * s.rate + s.phase)
                ctx.stampDot(dot, at: CGPoint(x: s.x, y: s.y), radius: s.size * 1.7, alpha: 0.2 + 0.7 * twinkle)
            }
        }
        for r in show.rockets {
            let p = CGPoint(x: r.position.x, y: r.position.y)
            let head = look(hue: -1, stage: .trail)
            if let glow = head.glow {
                ctx.stampDot(glow, at: p, radius: 22, alpha: 0.9)
                ctx.stampDot(glow, at: p, radius: 7, alpha: 1)
            }
        }
        for s in show.sparks.particles { drawSpark(s, in: ctx, core: white) }
    }

    private func drawSpark(_ s: Particle, in ctx: CGContext, core: CGImage?) {
        let kind = FireworkSkySim.Kind(rawValue: s.kind) ?? .star
        let p = s.progress
        // A spark burns steadily for most of its life, then dies away quickly.
        var alpha = p < 0.55 ? 1 : pow(1 - (p - 0.55) / 0.45, 1.3)
        var radius = s.size * (1.15 - 0.45 * p)
        var tailLength = 0.12
        let stage: Stage
        switch kind {
        case .star:
            stage = p < 0.14 ? .hot : p < 0.6 ? .normal : .ember
            if p > 0.3 { alpha *= 0.82 + 0.18 * sin(s.age * 47 + s.size * 11) }
        case .ember:
            stage = .trail
            radius = s.size * (1 - 0.5 * p)
            alpha = 1 - p
            tailLength = 0
        case .willow:
            stage = .willow
            tailLength = 0.14
            if p > 0.3 { alpha *= 0.75 + 0.25 * sin(s.age * 40 + s.size * 13) }
        }
        guard alpha > 0.03 else { return }
        let look = look(hue: kind == .star ? s.hue : 0.1, stage: stage)
        let at = CGPoint(x: s.position.x, y: s.position.y)

        let speed = (s.velocity.x * s.velocity.x + s.velocity.y * s.velocity.y).squareRoot()
        let length = min(90, speed * tailLength)
        if length > 5, let tail = look.tail {
            let thickness = radius * 2.2
            ctx.saveGState()
            ctx.translateBy(x: at.x, y: at.y)
            ctx.rotate(by: atan2(s.velocity.y, s.velocity.x))
            ctx.setAlpha(min(1, alpha))
            ctx.draw(tail, in: CGRect(x: -length, y: -thickness / 2, width: length, height: thickness))
            ctx.restoreGState()
        }
        if let glow = look.glow { ctx.stampDot(glow, at: at, radius: radius * 2.6, alpha: alpha) }
        if kind != .ember, p < 0.5, let core { ctx.stampDot(core, at: at, radius: radius * 1.1, alpha: alpha) }
        // Late in its life a star crackles: tiny glints that wink on and off.
        if kind == .star, p > 0.5, p < 0.9, sin(s.age * 53 + s.size * 37) > 0.86, let glint = WorldKit.star(1, 0.96, 0.85) {
            ctx.stampDot(glint, at: at, radius: radius * 3.2, alpha: alpha)
        }
    }
}
