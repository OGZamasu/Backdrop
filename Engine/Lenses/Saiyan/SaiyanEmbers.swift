import CoreGraphics
import CoreImage
import Foundation
import simd

/// Everything small that sits behind the person: embers rising off the head and shoulders (glints for Blue, slow motes for Ultra
/// Instinct), the radial burst of a change, and while a power-up charges, streaks of light rushing up, ripples running out along the floor
/// and debris lifting off it and trembling. A plain simulation; `SaiyanAura` decides the rates and colours, and draws it all into one layer
/// behind the person (the debris goes through the graphics chip, so it can cover the glow instead of adding to it).
final class SaiyanEmbers {
    enum Kind: Int { case ember, glint, mote, burst }

    struct Streak {
        var x: Double
        var y: Double
        var speed: Double
        var length: Double
        var age = 0.0
        var life: Double
    }

    struct Ripple {
        var age = 0.0
        var strength: Double
    }

    struct Rock {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var angle: Double
        var spin: Double
        var size: Double
        var variant: Int
        var age = 0.0
        var life: Double
        var seed: Double
    }

    private(set) var sparks = ParticleSystem(capacity: 300)
    private(set) var streaks: [Streak] = []
    private(set) var ripples: [Ripple] = []
    private(set) var rocks: [Rock] = []
    private var owed = 0.0, streakOwed = 0.0, rockOwed = 0.0, rippleClock = 0.0
    private var rng = SplitMix64(seed: 0xE3B5)
    private var clock = 0.0

    init() {
        sparks.gravity = SIMD2(0, 30)   // heat rises
    }

    func reset() {
        sparks.removeAll()
        streaks.removeAll()
        ripples.removeAll()
        rocks.removeAll()
        owed = 0; streakOwed = 0; rockOwed = 0; rippleClock = 0
    }

    var isIdle: Bool { sparks.particles.isEmpty && streaks.isEmpty && ripples.isEmpty && rocks.isEmpty }
    var count: Int { sparks.particles.count }

    // MARK: Simulation

    /// One frame. `rate` is embers a second, `charge` how full a power-up is (0 when not powering up).
    func step(dt: Double, outline: SaiyanOutline, rate: Double, look: SaiyanAuraLook, charge: Double, rect: CGRect) {
        clock += dt
        let u = outline.unit
        emitEmbers(dt: dt, outline: outline, rate: rate, look: look)
        sparks.step(dt) { p in
            switch Kind(rawValue: p.kind) ?? .ember {
            case .ember:
                // A lazy side-to-side drift, and the air slowing it.
                p.velocity.x += sin(p.age * 4.2 + p.hue * 40) * 70 * u * dt
                p.velocity *= exp(-0.5 * dt)
            case .glint:
                p.velocity.x += sin(p.age * 2.4 + p.hue * 30) * 26 * u * dt
                p.velocity *= exp(-1.2 * dt)
            case .mote:
                p.velocity.x += sin(p.age * 1.6 + p.hue * 30) * 34 * u * dt
                p.velocity.y -= 26 * dt   // they hardly rise: they float
                p.velocity *= exp(-0.9 * dt)
            case .burst:
                p.velocity *= exp(-2.6 * dt)
            }
        }

        // While charging: light rushing up, ripples along the floor, rocks lifting.
        let c = min(1, max(0, charge))
        if c > 0.04, !outline.isEmpty {
            streakOwed += dt * (6 + 26 * c)
            while streakOwed >= 1 {
                streakOwed -= 1
                // Either side of the person, not behind them, where they would be hidden.
                let side: Double = Bool.random(using: &rng) ? 1 : -1
                let x = Double(outline.centre.x) + side * outline.width * Double.random(in: 0.5...0.95, using: &rng)
                streaks.append(Streak(x: x, y: Double(rect.minY) - 40 + Double.random(in: 0...(Double(rect.height) * 0.5), using: &rng),
                                      speed: Double.random(in: 700...1300, using: &rng) * u, length: Double.random(in: 50...150, using: &rng) * u,
                                      life: Double.random(in: 0.3...0.6, using: &rng)))
            }
            rippleClock += dt * (0.8 + 2.2 * c)
            if rippleClock >= 1 {
                rippleClock = 0
                ripples.append(Ripple(strength: 0.4 + 0.6 * c))
            }
            if c > 0.1 {
                rockOwed += dt * 16 * c
                while rockOwed >= 1, rocks.count < 16 {
                    rockOwed -= 1
                    let side: Double = Bool.random(using: &rng) ? 1 : -1
                    let x = Double(outline.centre.x) + side * outline.width * Double.random(in: 0.52...0.9, using: &rng)
                    rocks.append(Rock(position: SIMD2(x, Double(rect.minY) - 12), velocity: SIMD2(Double.random(in: -12...12, using: &rng), Double.random(in: 160...300, using: &rng) * u),
                                      angle: Double.random(in: 0..<(2 * .pi), using: &rng), spin: Double.random(in: -1.6...1.6, using: &rng),
                                      size: pow(Double.random(in: 0...1, using: &rng), 1.4) * 34 * u + 18 * u, variant: Int.random(in: 0..<4, using: &rng),
                                      life: Double.random(in: 1.8...2.8, using: &rng), seed: Double.random(in: 0..<100, using: &rng)))
                }
                rockOwed = min(rockOwed, 1)
            }
        }
        for i in streaks.indices {
            streaks[i].age += dt
            streaks[i].y += streaks[i].speed * dt
        }
        streaks.removeAll { $0.age >= $0.life || $0.y > Double(rect.maxY) + $0.length }
        for i in ripples.indices { ripples[i].age += dt }
        ripples.removeAll { $0.age >= 1.0 }
        for i in rocks.indices {
            rocks[i].age += dt
            // Thrown up off the floor, then held hovering and trembling while the power-up lasts; once it stops they drop.
            if c > 0.05 {
                rocks[i].velocity.y += (30 * u - rocks[i].velocity.y) * min(1, dt * 2.2)
            } else {
                rocks[i].velocity.y -= 900 * u * dt
            }
            rocks[i].position += rocks[i].velocity * dt
            rocks[i].angle += rocks[i].spin * dt
        }
        rocks.removeAll { $0.age >= $0.life || $0.position.y < Double(rect.minY) - 60 || $0.position.y > Double(rect.maxY) + 40 }
    }

    private func emitEmbers(dt: Double, outline: SaiyanOutline, rate: Double, look: SaiyanAuraLook) {
        guard rate > 0.5, !outline.crown.isEmpty else {
            owed = 0
            return
        }
        owed += dt * rate
        let u = outline.unit
        while owed >= 1 {
            owed -= 1
            let at = outline.crown[Int.random(in: 0..<outline.crown.count, using: &rng)]
            let pick = Double.random(in: 0..<1, using: &rng)
            let kind: Kind = pick < look.motes ? .mote : pick < look.motes + look.sparkles ? .glint : .ember
            let start = SIMD2(Double(at.x) + Double.random(in: -6...6, using: &rng), Double(at.y) + Double.random(in: 2...14, using: &rng) * u)
            switch kind {
            case .ember, .burst:
                sparks.emit(Particle(position: start,
                                     velocity: SIMD2(Double.random(in: -50...50, using: &rng) * u, Double.random(in: 70...210, using: &rng) * u * look.emberSpeed),
                                     life: Double.random(in: 0.6...1.2, using: &rng),
                                     size: (pow(Double.random(in: 0...1, using: &rng), 2) * 3.6 + 1.4) * u.squareRoot() * look.emberSize,
                                     hue: Double.random(in: 0..<1, using: &rng), kind: Kind.ember.rawValue))
            case .glint:
                sparks.emit(Particle(position: start + SIMD2(Double.random(in: -20...20, using: &rng), Double.random(in: 0...50, using: &rng)) * u,
                                     velocity: SIMD2(Double.random(in: -20...20, using: &rng) * u, Double.random(in: 40...110, using: &rng) * u),
                                     life: Double.random(in: 0.6...1.2, using: &rng), size: Double.random(in: 4...8, using: &rng) * u.squareRoot(),
                                     hue: Double.random(in: 0..<1, using: &rng), kind: Kind.glint.rawValue))
            case .mote:
                sparks.emit(Particle(position: start + SIMD2(Double.random(in: -30...30, using: &rng), Double.random(in: 0...60, using: &rng)) * u,
                                     velocity: SIMD2(Double.random(in: -14...14, using: &rng) * u, Double.random(in: 30...80, using: &rng) * u),
                                     life: Double.random(in: 1.4...2.6, using: &rng), size: Double.random(in: 1.1...2.6, using: &rng) * u.squareRoot(),
                                     hue: Double.random(in: 0..<1, using: &rng), kind: Kind.mote.rawValue))
            }
        }
        owed = min(owed, 4)
    }

    /// A radial burst of embers off the outline, for a change of form. The debris in the air is blown up and away before it falls.
    func burst(outline: SaiyanOutline, count: Int) {
        let u = outline.unit
        for i in rocks.indices {
            let away: Double = rocks[i].position.x > Double(outline.centre.x) ? 1 : -1
            rocks[i].velocity += SIMD2(away * Double.random(in: 80...220, using: &rng), Double.random(in: 380...620, using: &rng)) * u
            rocks[i].spin *= 3
            rocks[i].life = max(rocks[i].life, rocks[i].age + 1.6)
        }
        let c = SIMD2(Double(outline.centre.x), Double(outline.centre.y))
        let sources = outline.rim.filter { !$0.clipped }
        for _ in 0..<count {
            let start: SIMD2<Double>
            var direction: SIMD2<Double>
            if let r = sources.isEmpty ? nil : sources[Int.random(in: 0..<sources.count, using: &rng)] {
                start = SIMD2(Double(r.point.x), Double(r.point.y))
                direction = simd_normalize(r.normal * 0.6 + simd_normalize(start - c + SIMD2(0, 1e-3)) * 0.4)
            } else {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                direction = SIMD2(cos(a), sin(a))
                start = c + direction * outline.width * 0.3
            }
            direction += SIMD2(Double.random(in: -0.25...0.25, using: &rng), Double.random(in: -0.1...0.35, using: &rng))
            sparks.emit(Particle(position: start, velocity: direction * Double.random(in: 380...900, using: &rng) * u,
                                 life: Double.random(in: 0.5...1.1, using: &rng), size: (pow(Double.random(in: 0...1, using: &rng), 2) * 3 + 1.8) * u.squareRoot(),
                                 hue: Double.random(in: 0..<1, using: &rng), kind: Kind.burst.rawValue))
        }
    }

    // MARK: Drawing

    /// The aura's colours for this frame, from faint to hot, and the next form's while charging.
    struct Colours {
        var core: SIMD3<Double>
        var mid: SIMD3<Double>
        var rim: SIMD3<Double>
        var charge: SIMD3<Double>
    }

    /// The light: embers, glints, motes, streaks and floor ripples, drawn additively. Call with a fresh layer.
    func drawLight(in ctx: CGContext, outline: SaiyanOutline, colours: Colours, charge: Double, presence: Double, rect: CGRect) {
        guard presence > 0.004 else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        let u = outline.unit
        let white = HandFXPalette.white
        // An ember's colour as it ages, in six steps, and the speck for each (baked once per colour and kept).
        let steps: [SIMD3<Double>] = (0..<6).map { i in
            let k = (Double(i) + 0.5) / 6
            return k < 0.35 ? SaiyanAuraKit.mix(colours.core, colours.mid, k / 0.35) : SaiyanAuraKit.mix(colours.mid, colours.rim, (k - 0.35) / 0.65)
        }
        let specks = steps.map(Self.speck)

        // Ripples running out along the floor round the person: wide flat rings, mostly hidden behind them, showing either side.
        for ring in ripples {
            let k = ring.age / 1.0
            let e = HandFXKit.easeOutCubic(k)
            let rx = outline.width * (0.32 + 0.75 * e), ry = rx * 0.17
            let alpha = pow(1 - k, 1.5) * WorldKit.smoothstep(0, 0.08, k) * ring.strength * presence
            let centre = CGPoint(x: outline.centre.x, y: rect.minY + 22 * u)
            let box = CGRect(x: centre.x - rx, y: centre.y - ry, width: rx * 2, height: ry * 2)
            for (w, c, a) in [(16.0 * u, colours.charge, 0.16), (6.0 * u, SaiyanAuraKit.mix(colours.charge, white, 0.4), 0.42), (2.0, white, 0.7)] {
                ctx.setLineWidth(max(1, w * (1 - 0.5 * k)))
                ctx.setStrokeColor(HandFXKit.cgColor(c, a * alpha))
                ctx.strokeEllipse(in: box)
            }
        }

        // The debris catches the light of the power-up: a soft glow of its colour round each rock (the rock itself is laid under this layer).
        for r in rocks {
            let fade = WorldKit.smoothstep(0, 0.25, r.age) * (1 - WorldKit.smoothstep(r.life - 0.4, r.life, r.age)) * presence * min(1, charge * 2)
            HandFXKit.glow(ctx, at: CGPoint(x: r.position.x, y: r.position.y), radius: r.size * 1.05, colour: colours.charge, alpha: 0.2 * fade)
        }

        // Streaks of light rushing up past the person: a coloured trail with a hot thread inside it.
        if let tail = WorldKit.comet(colours.charge.x, colours.charge.y, colours.charge.z), let hot = WorldKit.comet(1, 1, 0.95) {
            for s in streaks {
                let k = s.age / s.life
                let alpha = WorldKit.smoothstep(0, 0.15, k) * (1 - k) * min(1, charge * 1.6) * presence
                guard alpha > 0.01 else { continue }
                ctx.saveGState()
                ctx.translateBy(x: s.x, y: s.y)
                ctx.rotate(by: .pi / 2)
                ctx.setAlpha(CGFloat(alpha))
                ctx.draw(tail, in: CGRect(x: -s.length, y: -5 * u, width: s.length, height: 10 * u))
                ctx.setAlpha(CGFloat(alpha * 0.8))
                ctx.draw(hot, in: CGRect(x: -s.length * 0.7, y: -1.6 * u, width: s.length * 0.7, height: 3.2 * u))
                ctx.restoreGState()
            }
        }

        for p in sparks.particles {
            let k = p.progress
            let at = CGPoint(x: p.position.x, y: p.position.y)
            switch Kind(rawValue: p.kind) ?? .ember {
            case .ember, .burst:
                let fade = (1 - k * k) * min(1, p.age / 0.1) * presence
                // White-hot when new, cooling through the body colour to the rim: one stamp, a white point in a coloured halo, from one of
                // six sprites along the way.
                let step = min(5, Int(k * 6))
                let radius = p.size * (1.25 - 0.55 * k) * 2.6
                let speed = simd_length(p.velocity)
                let kind = Kind(rawValue: p.kind)
                if (kind == .burst || p.size > 3.2) && speed > 140 * u, let tail = WorldKit.comet(steps[step].x, steps[step].y, steps[step].z) {
                    let length = min(40 * u, speed * 0.07) + radius
                    ctx.saveGState()
                    ctx.translateBy(x: at.x, y: at.y)
                    ctx.rotate(by: atan2(p.velocity.y, p.velocity.x))
                    ctx.setAlpha(CGFloat(fade * 0.75))
                    ctx.draw(tail, in: CGRect(x: -length, y: -radius * 0.45, width: length + radius * 0.2, height: radius * 0.9))
                    ctx.restoreGState()
                }
                if let speck = specks[step] { ctx.stampDot(speck, at: at, radius: radius, alpha: fade) }
            case .glint:
                // A four-pointed glint that twinkles as it drifts.
                let twinkle = 0.55 + 0.45 * sin(p.age * 15 + p.hue * 30)
                let fade = sin(min(1, k) * .pi) * presence
                let colour = SaiyanAuraKit.mix(colours.mid, white, 0.55)
                if let star = WorldKit.star(colour.x, colour.y, colour.z) {
                    let r = p.size * (0.6 + 0.6 * twinkle)
                    ctx.saveGState()
                    ctx.translateBy(x: at.x, y: at.y)
                    ctx.rotate(by: CGFloat(p.hue * 0.8))
                    ctx.setAlpha(CGFloat(fade * twinkle))
                    ctx.draw(star, in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
                    ctx.restoreGState()
                }
            case .mote:
                let twinkle = 0.6 + 0.4 * sin(p.age * 5 + p.hue * 30)
                let fade = sin(min(1, k) * .pi) * presence * twinkle
                let colour = SaiyanAuraKit.mix(colours.mid, white, 0.7)
                HandFXKit.glow(ctx, at: at, radius: p.size * 3.2, colour: colour, alpha: fade * 0.5)
                HandFXKit.glow(ctx, at: at, radius: p.size, colour: white, alpha: fade)
            }
        }
        ctx.restoreGState()
    }

    /// A speck of light in a colour (rounded to twelfths, so a blend of forms reuses a few dozen): a white-hot point in a soft halo.
    private static func speck(_ c: SIMD3<Double>) -> CGImage? {
        let q = { (v: Double) in Int((min(1, max(0, v)) * 12).rounded()) }
        let (r, g, b) = (q(c.x), q(c.y), q(c.z))
        return HandFXSprites.named("saiyan-speck-\(r)-\(g)-\(b)") {
            HandFXKit.speckSprite(SIMD3(Double(r), Double(g), Double(b)) / 12)
        }
    }

    /// The debris, laid over `base` on the graphics chip: solid rocks, dark against the glow, each with a little shake.
    func compositeRocks(over base: CIImage, presence: Double, rect: CGRect) -> CIImage {
        guard !rocks.isEmpty, presence > 0.01 else { return base }
        var out = base
        let sprites = SaiyanAuraKit.rocks
        guard !sprites.isEmpty else { return base }
        for r in rocks {
            let fade = WorldKit.smoothstep(0, 0.25, r.age) * (1 - WorldKit.smoothstep(r.life - 0.4, r.life, r.age)) * presence
            guard fade > 0.01 else { continue }
            let jitter = SIMD2(sin(clock * 53 + r.seed), cos(clock * 47 + r.seed * 1.7)) * 1.4
            let at = CGPoint(x: r.position.x + jitter.x, y: r.position.y + jitter.y)
            let sprite = sprites[r.variant % sprites.count]
            out = WorldKit.placed(sprite, size: CGSize(width: r.size, height: r.size), anchor: CGPoint(x: r.size / 2, y: r.size / 2),
                                  angle: r.angle, at: at, alpha: fade).composited(over: out)
        }
        return out.cropped(to: rect)
    }
}
