import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// A storm: streaks of rain in two depths, splashes where drops hit the top of you or the ground, and now and then a flash of lightning.
///
/// Far rain is behind you, near rain in front. A near drop that meets your silhouette breaks into a splash instead of passing through.
struct RainstormSim {
    struct Drop {
        var position: SIMD2<Double>
        /// Pixels a second, straight down.
        var speed: Double
        /// 0.5...1: how bright this one is.
        var strength: Double
        /// Where the ground is for this drop, in pixels up from the bottom of the picture.
        var ground: Double
    }

    struct Ripple {
        var position: SIMD2<Double>
        var age = 0.0
        var life: Double
        var radius: Double
    }

    /// One strike: where, how long ago, and the zig-zag it took from the sky down.
    struct Bolt {
        var points: [SIMD2<Double>]
        var branches: [[SIMD2<Double>]]
        var age: Double
    }

    /// The wind leans the rain over by this much sideways for each unit of speed.
    static let slant = -0.2

    let size: CGSize
    private(set) var far: [Drop] = []
    private(set) var near: [Drop] = []
    private(set) var splashes = ParticleSystem(capacity: 260)
    private(set) var ripples: [Ripple] = []
    private(set) var bolt: Bolt?
    /// Seconds since the last strike began; huge when there has been none.
    private(set) var sinceFlash = 99.0
    private(set) var time = 0.0
    private(set) var splashCount = 0
    private var rng: SplitMix64
    private var untilStrike: Double

    init(size: CGSize, seed: UInt64 = 0x5700A, farCount: Int = 160, nearCount: Int = 100) {
        self.size = size
        rng = SplitMix64(seed: seed)
        splashes.gravity = SIMD2(0, -1700)
        untilStrike = 3.0
        for _ in 0..<farCount { far.append(makeDrop(far: true, anywhere: true)) }
        for _ in 0..<nearCount { near.append(makeDrop(far: false, anywhere: true)) }
    }

    mutating func removeAll() {
        splashes.removeAll()
        ripples.removeAll()
        bolt = nil
        sinceFlash = 99
        untilStrike = 3
    }

    private mutating func makeDrop(far isFar: Bool, anywhere: Bool = false) -> Drop {
        let speed = isFar ? Double.random(in: 880...1100, using: &rng) : Double.random(in: 1500...1950, using: &rng)
        // The wind blows the rain across, so more of it starts off to the right.
        let x = Double.random(in: -60...(size.width + 220), using: &rng)
        let y = anywhere ? Double.random(in: 0...(size.height + 40), using: &rng) : size.height + Double.random(in: 10...80, using: &rng)
        return Drop(position: SIMD2(x, y), speed: speed, strength: Double.random(in: 0.5...1, using: &rng),
                    ground: isFar ? -10 : Double.random(in: 4...42, using: &rng))
    }

    /// How bright the sky is, 0...1: a sharp flash, then a weaker second one a moment later.
    static func flash(sinceStrike age: Double) -> Double {
        func pulse(_ t: Double, rise: Double, fall: Double) -> Double {
            t < 0 ? 0 : t < rise ? t / rise : exp(-(t - rise) / fall)
        }
        return max(pulse(age, rise: 0.025, fall: 0.07), 0.72 * pulse(age - 0.2, rise: 0.025, fall: 0.11))
    }

    /// Lightning now, whatever the schedule says.
    mutating func strike() {
        sinceFlash = 0
        // Off to one side, where the person is not standing in front of it.
        let side = Bool.random(using: &rng) ? 1.0 : -1.0
        let top = SIMD2(size.width * (0.5 + side * Double.random(in: 0.2...0.42, using: &rng)), size.height + 10)
        let bottom = SIMD2(top.x + Double.random(in: -140...140, using: &rng), Double.random(in: size.height * 0.2...size.height * 0.45, using: &rng))
        let main = jag(from: top, to: bottom, depth: 6, spread: 0.2)
        var branches: [[SIMD2<Double>]] = []
        for _ in 0..<Int.random(in: 2...4, using: &rng) {
            let at = main[Int.random(in: 4..<(main.count - 4), using: &rng)]
            let angle = -Double.pi / 2 + Double.random(in: -1.0...1.0, using: &rng)
            let length = Double.random(in: 90...230, using: &rng)
            branches.append(jag(from: at, to: at + SIMD2(cos(angle), sin(angle)) * length, depth: 4, spread: 0.28))
        }
        bolt = Bolt(points: main, branches: branches, age: 0)
        untilStrike = Double.random(in: 5...10, using: &rng)
    }

    /// A zig-zag between two points, made by pushing the middle sideways again and again.
    private mutating func jag(from a: SIMD2<Double>, to b: SIMD2<Double>, depth: Int, spread: Double) -> [SIMD2<Double>] {
        var points = [a, b]
        var offset = simd_length(b - a) * spread
        for _ in 0..<depth {
            var next: [SIMD2<Double>] = []
            for i in 0..<(points.count - 1) {
                let p = points[i], q = points[i + 1]
                let along = q - p
                let normal = SIMD2(-along.y, along.x) / max(1e-6, simd_length(along))
                next.append(p)
                next.append((p + q) / 2 + normal * Double.random(in: -offset...offset, using: &rng))
            }
            next.append(points[points.count - 1])
            points = next
            offset *= 0.55
        }
        return points
    }

    mutating func step(_ rawDt: Double, matte: MatteQuery?) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        sinceFlash += dt
        untilStrike -= dt
        if untilStrike <= 0 { strike() }
        if var current = bolt {
            current.age += dt
            bolt = current.age > 0.34 ? nil : current
        }

        for i in far.indices {
            far[i].position += SIMD2(Self.slant * far[i].speed, -far[i].speed) * dt
            if far[i].position.y < -20 || far[i].position.x < -80 { far[i] = makeDrop(far: true) }
        }
        for i in near.indices {
            let before = near[i].position
            near[i].position += SIMD2(Self.slant * near[i].speed, -near[i].speed) * dt
            let after = near[i].position
            if let hit = firstContact(from: before, to: after, in: matte) {
                splash(at: hit, onPerson: true)
                near[i] = makeDrop(far: false)
            } else if after.y < near[i].ground || after.x < -80 {
                // On the ground: a ripple, unless that spot is hidden behind you.
                let covered = (matte?.coverage(x: after.x, y: near[i].ground) ?? 0) >= 0.5
                if after.y < near[i].ground, after.x > 0, after.x < size.width, !covered {
                    splash(at: SIMD2(after.x, near[i].ground), onPerson: false)
                }
                near[i] = makeDrop(far: false)
            }
        }

        splashes.step(dt)
        for i in ripples.indices { ripples[i].age += dt }
        ripples.removeAll { $0.age >= $0.life }
    }

    /// Where along a drop's move it first lands on someone, sampling every few pixels so a fast drop cannot skip over a head.
    private func firstContact(from a: SIMD2<Double>, to b: SIMD2<Double>, in matte: MatteQuery?) -> SIMD2<Double>? {
        guard let matte else { return nil }
        let steps = max(1, Int(simd_length(b - a) / 14))
        for k in 1...steps {
            let p = a + (b - a) * (Double(k) / Double(steps))
            if matte.coverage(x: p.x, y: p.y) > 0.5 { return p }
        }
        return nil
    }

    private mutating func splash(at p: SIMD2<Double>, onPerson: Bool) {
        splashCount += 1
        if onPerson {
            for _ in 0..<Int.random(in: 3...5, using: &rng) {
                let angle = Double.pi / 2 + Double.random(in: -1.15...1.15, using: &rng)
                let speed = Double.random(in: 180...430, using: &rng)
                splashes.emit(Particle(position: p, velocity: SIMD2(cos(angle), sin(angle)) * speed, life: Double.random(in: 0.22...0.42, using: &rng),
                                       size: Double.random(in: 1.4...2.8, using: &rng)))
            }
        } else {
            for _ in 0..<2 {
                let angle = Double.pi / 2 + Double.random(in: -0.8...0.8, using: &rng)
                splashes.emit(Particle(position: p, velocity: SIMD2(cos(angle), sin(angle)) * Double.random(in: 90...220, using: &rng),
                                       life: Double.random(in: 0.18...0.3, using: &rng), size: Double.random(in: 1.2...2.2, using: &rng)))
            }
            if ripples.count < 40 { ripples.append(Ripple(position: p, life: Double.random(in: 0.35...0.55, using: &rng), radius: Double.random(in: 12...22, using: &rng))) }
        }
    }
}

final class RainstormLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private var storm: RainstormSim

    init(size: CGSize = CGSize(width: 1280, height: 720)) { storm = RainstormSim(size: size) }

    func restart() { storm.removeAll() }

    var splashCount: Int { storm.splashCount }
    var dropCount: Int { storm.far.count + storm.near.count }
    var nearDrops: [RainstormSim.Drop] { storm.near }
    /// Lightning at once. For tests and previews.
    func strike() { storm.strike() }
    /// How bright the lightning has the sky right now, 0...1.
    var flash: Double { RainstormSim.flash(sinceStrike: storm.sinceFlash) }

    func render(_ input: LensInput) -> CIImage {
        storm.step(input.dt, matte: input.matteGrid)
        let flash = self.flash
        let rect = input.rect

        // "Storm": dark, cold and drained, the person a little less so, so faces still read. A strike brings some colour back.
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * flash }
        let sky = WorldKit.grade(input.scenery, saturation: lerp(0.6, 0.9), tint: (lerp(0.30, 0.8), lerp(0.38, 0.88), lerp(0.58, 1.1)),
                                 lift: (0.002 + 0.015 * flash, 0.004 + 0.022 * flash, 0.012 + 0.045 * flash))
        let person = WorldKit.grade(input.composed, saturation: lerp(0.8, 1.0), tint: (lerp(0.52, 0.9), lerp(0.6, 0.96), lerp(0.76, 1.1)),
                                    lift: (0.002 + 0.01 * flash, 0.004 + 0.015 * flash, 0.01 + 0.03 * flash))

        // Low mist rolling along the floor, then the far rain and any lightning, all added as light behind you.
        var behind = WorldKit.adding(mist(rect: rect, time: input.time), to: sky)
        if let layer = input.services.overlay({ ctx in drawBehind(in: ctx) }) {
            behind = WorldKit.adding(layer, to: behind)
        }
        var body = WorldKit.place(person: person, over: behind, matte: input.matte, rect: rect)
        // Wet hair and shoulders catch a cool sheen from above; a strike lights that edge up brightly.
        if let rim = WorldKit.rimLight(matte: input.matte, rect: rect, toward: simd_normalize(SIMD2(-0.3, 1)), width: 9,
                                       colour: SIMD3(0.70, 0.82, 1.0), strength: 0.3 + 0.9 * flash) {
            body = WorldKit.adding(rim, to: body)
        }
        guard let front = input.services.overlay({ ctx in drawFront(in: ctx) }) else { return body }
        return front.composited(over: body).cropped(to: rect)
    }

    /// A band of soft mist along the bottom of the picture, drifting with the wind. Worked out at quarter size.
    private func mist(rect: CGRect, time: Double) -> CIImage {
        let scale = 0.25
        let box = CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale)
        let wisps = WorldKit.levels(WorldKit.clouds(box, grain: 26, offset: CGPoint(x: -time * 9, y: 0), stretch: CGSize(width: 3, height: 1)), low: 0.35, high: 0.75)
        let fall = CIFilter.linearGradient()
        fall.point0 = .zero
        fall.point1 = CGPoint(x: 0, y: box.height * 0.42)
        fall.color0 = CIColor(red: 1, green: 1, blue: 1)
        fall.color1 = CIColor(red: 0, green: 0, blue: 0)
        let band = WorldKit.multiply(wisps, (fall.outputImage ?? CIImage.empty()).cropped(to: box))
        return WorldKit.enlarge(WorldKit.tint(band, SIMD3(0.55, 0.63, 0.78), strength: 0.16).settingAlphaOne(in: box), rect: rect, from: scale)
    }

    // MARK: Drawing

    /// Far rain and the bolt itself, behind the person.
    private func drawBehind(in ctx: CGContext) {
        drawStreaks(storm.far, in: ctx, width: 1.1, length: 0.013, red: 0.78, green: 0.86, blue: 1.0, alpha: 0.24)
        if let bolt = storm.bolt { drawBolt(bolt, in: ctx) }
    }

    /// Near rain, splashes and ripples in front of everything.
    private func drawFront(in ctx: CGContext) {
        // Near drops: longer and brighter than the far ones, so the rain has depth.
        drawStreaks(storm.near, in: ctx, width: 1.7, length: 0.028, red: 0.88, green: 0.94, blue: 1.0, alpha: 0.45)

        ctx.interpolationQuality = .low
        if let tail = WorldKit.comet(0.88, 0.94, 1) {
            // Each droplet of a splash is a short bright streak along its flight.
            for p in storm.splashes.particles {
                let k = p.progress
                let length = min(14, simd_length(p.velocity) * 0.025) + 3
                ctx.saveGState()
                ctx.translateBy(x: p.position.x, y: p.position.y)
                ctx.rotate(by: atan2(p.velocity.y, p.velocity.x))
                ctx.setAlpha(0.95 * (1 - k))
                ctx.draw(tail, in: CGRect(x: -length, y: -p.size * 1.2, width: length + p.size, height: p.size * 2.4))
                ctx.restoreGState()
            }
        }
        ctx.interpolationQuality = .high
        for r in storm.ripples {
            let k = r.age / r.life
            let radius = r.radius * (0.3 + 0.7 * k)
            ctx.setLineWidth(1.2)
            ctx.setStrokeColor(CGColor(red: 0.82, green: 0.9, blue: 1, alpha: 0.42 * (1 - k) * (1 - k)))
            ctx.strokeEllipse(in: CGRect(x: r.position.x - radius, y: r.position.y - radius * 0.22, width: radius * 2, height: radius * 0.44))
        }
    }

    /// Streaks in three strengths, each as one path and one stroke, because a few strokes cost far less than a hundred.
    private func drawStreaks(_ drops: [RainstormSim.Drop], in ctx: CGContext, width: Double, length: Double, red: Double, green: Double, blue: Double, alpha: Double) {
        ctx.setLineCap(.round)
        ctx.setLineWidth(width)
        for band in 0..<3 {
            let path = CGMutablePath()
            for d in drops where min(2, Int((d.strength - 0.5) * 6)) == band {
                let tail = SIMD2(RainstormSim.slant * d.speed, -d.speed) * length
                path.move(to: CGPoint(x: d.position.x, y: d.position.y))
                path.addLine(to: CGPoint(x: d.position.x - tail.x, y: d.position.y - tail.y))
            }
            ctx.setStrokeColor(CGColor(red: red, green: green, blue: blue, alpha: min(1, alpha * (0.6 + 0.25 * Double(band)))))
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private func drawBolt(_ bolt: RainstormSim.Bolt, in ctx: CGContext) {
        let k = max(0, 1 - bolt.age / 0.34)
        let brightness = min(1, 0.35 + RainstormSim.flash(sinceStrike: bolt.age)) * k
        func trace(_ points: [SIMD2<Double>]) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: points[0].x, y: points[0].y))
            for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
            return path
        }
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for (points, scale) in [(bolt.points, 1.0)] + bolt.branches.map({ ($0, 0.55) }) {
            let path = trace(points)
            // Many strokes, each narrower and brighter than the last, make a glow that fades smoothly instead of a hard-edged band.
            for (width, red, green, blue, alpha) in [(46.0, 0.30, 0.42, 1.0, 0.035), (30.0, 0.34, 0.5, 1.0, 0.05), (19.0, 0.42, 0.58, 1.0, 0.08),
                                                     (11.0, 0.55, 0.7, 1.0, 0.14), (6.0, 0.75, 0.85, 1.0, 0.3), (3.2, 0.92, 0.96, 1.0, 0.75), (1.5, 1.0, 1.0, 1.0, 1.0)] {
                ctx.setLineWidth(width * scale)
                ctx.setStrokeColor(CGColor(red: red, green: green, blue: blue, alpha: alpha * brightness))
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        ctx.setBlendMode(.normal)
    }
}
