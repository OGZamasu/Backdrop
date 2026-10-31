import AppKit
import CoreGraphics
import simd

/// A space shooter flown with your face. Your face is the pilot; move your head left and right to steer the ship and open your
/// mouth to fire. Big rocks split in two, saucers are worth the most, and anything that hits the ship costs a heart.
struct SpaceBlasterGame: FaceGame {
    static let title = "Space Blaster"
    static let hint = "Move your head to steer. Open your mouth to fire!"
    static let presenceHint = "Look into the camera to play"
    static let wantsFaceCrop = true
    static let move = FaceGameMove.moveHead
    static let accent = FaceGamePalette.teal
    static let scoreLabel = "POINTS"

    struct Rock: Equatable {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var radius: Double
        var angle = 0.0
        var spin = 0.0
        var variant = 0
        var big: Bool { radius > 34 }
    }

    struct Saucer: Equatable {
        var position: SIMD2<Double>
        var direction: Double
        var age = 0.0
    }

    static let lives = 3
    static let shipY = 118.0
    /// The part of the ship that counts for a hit: a little smaller than it looks.
    static let shipRadius = 40.0
    static let boltSpeed = 980.0
    static let fireInterval = 0.17
    /// One eye-spacing of head movement moves the ship this far.
    static let reach = 230.0
    static let bigRadius = 46.0
    static let smallRadius = 26.0

    let size: CGSize
    private(set) var shipX: Double
    private(set) var rocks: [Rock] = []
    private(set) var saucers: [Saucer] = []
    private(set) var bolts: [SIMD2<Double>] = []
    private(set) var score = 0
    private(set) var hearts = SpaceBlasterGame.lives
    private(set) var destroyed = 0
    private(set) var shots = 0
    private(set) var elapsed = 0.0
    private(set) var invulnerable = 0.0
    private var steer: FaceGameSteer
    private var mouth = FaceGameTrigger(on: 0.3, off: 0.16, offDelay: 0.1)
    private var fireTimer = 0.0
    private var spawnTimer = 1.0
    private var saucerTimer = 14.0
    private var spawning = true
    private var bank = 0.0
    private var muzzle = 0.0
    private var shake = 0.0
    private var crop: CGImage?
    private var rng: SplitMix64
    private var debris = ParticleSystem(capacity: 360)
    private var rings: [(x: Double, y: Double, age: Double, size: Double)] = []
    private var floaters: [FaceGameFloater] = []

    var isOver: Bool { hearts <= 0 }
    var summary: String { "Lives \(hearts)" }
    var firing: Bool { mouth.isOn }

    var chips: [FaceGameChip] { [.hearts(hearts, of: Self.lives)] }
    var ending: FaceGameEnding { .lost("SHIP DOWN!") }
    var endLine: String { destroyed == 1 ? "You blasted 1 rock" : "You blasted \(destroyed) rocks" }
    var tip: String? {
        if elapsed < 4 { return "Open your mouth to fire!" }
        if elapsed < 12, shots == 0 { return "Open wide to shoot!" }
        return nil
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        shipX = size.width / 2
        steer = FaceGameSteer(reach: Self.reach, start: SIMD2(size.width / 2, Self.shipY), rate: 11)
        debris.gravity = .zero
        debris.drag = 1.6
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.1)
        if let crop = world.faceCrop { self.crop = crop }
        debris.step(dt)
        for i in rings.indices { rings[i].age += dt }
        rings.removeAll { $0.age > 0.5 }
        FaceGamePaint.advance(&floaters, by: dt)
        muzzle = max(0, muzzle - dt * 8)
        shake = max(0, shake - dt * 3)
        guard !isOver else { return }
        // Space holds still while there is no pilot to steer.
        guard let face = world.face else { return }
        elapsed += dt
        invulnerable = max(0, invulnerable - dt)

        let before = shipX
        steer.update(face, middle: SIMD2(size.width / 2, Self.shipY), bounds: CGRect(x: 90, y: Self.shipY, width: size.width - 180, height: 0), dt: dt)
        shipX = steer.spot.x
        bank = FaceGameEase.approach(bank, (shipX - before) / max(dt, 1e-3), rate: 8, dt: dt)

        mouth.update(face.mouthOpen, dt: dt)
        if mouth.isOn {
            fireTimer -= dt
            if fireTimer <= 0 {
                bolts.append(SIMD2(shipX, Self.shipY + 70))
                shots += 1
                muzzle = 1
                fireTimer = Self.fireInterval
            }
        } else {
            fireTimer = 0
        }

        var h = dt
        while h > 1e-9 {
            let part = min(h, 1.0 / 60)
            advance(part)
            h -= part
        }
    }

    private mutating func advance(_ dt: Double) {
        for i in bolts.indices { bolts[i].y += Self.boltSpeed * dt }
        bolts.removeAll { $0.y > size.height + 40 }

        if spawning {
            spawnTimer -= dt
            if spawnTimer <= 0 {
                spawnRock()
                spawnTimer = FaceGamePaint.lerp(1.5, 0.55, elapsed / 75) * Double.random(in: 0.75...1.25, using: &rng)
            }
            saucerTimer -= dt
            if saucerTimer <= 0 {
                let fromLeft = Bool.random(using: &rng)
                saucers.append(Saucer(position: SIMD2(fromLeft ? -80 : size.width + 80, Double.random(in: 470...560, using: &rng)), direction: fromLeft ? 1 : -1))
                saucerTimer = Double.random(in: 8...12, using: &rng)
            }
        }
        for i in rocks.indices {
            rocks[i].position += rocks[i].velocity * dt
            rocks[i].angle += rocks[i].spin * dt
            if rocks[i].position.x < rocks[i].radius || rocks[i].position.x > size.width - rocks[i].radius { rocks[i].velocity.x *= -1 }
        }
        rocks.removeAll { $0.position.y < -90 }
        for i in saucers.indices {
            saucers[i].age += dt
            saucers[i].position.x += saucers[i].direction * 170 * dt
            saucers[i].position.y += cos(saucers[i].age * 3) * 50 * dt
        }
        saucers.removeAll { $0.position.x < -120 || $0.position.x > size.width + 120 }

        resolveShots()
        if invulnerable == 0 { checkShip() }
    }

    private mutating func spawnRock() {
        let big = Double.random(in: 0..<1, using: &rng) < 0.45
        let fall = 120 + 2.2 * min(elapsed, 90) + Double.random(in: 0...80, using: &rng)
        rocks.append(Rock(position: SIMD2(Double.random(in: 90...(size.width - 90), using: &rng), size.height + 70),
                          velocity: SIMD2(Double.random(in: -50...50, using: &rng), -fall), radius: big ? Self.bigRadius : Self.smallRadius,
                          spin: Double.random(in: -1.6...1.6, using: &rng), variant: Int.random(in: 0..<3, using: &rng)))
    }

    private mutating func resolveShots() {
        var spent = Set<Int>()
        var kept: [Rock] = []
        var born: [Rock] = []
        for rock in rocks {
            if let b = bolts.indices.first(where: { !spent.contains($0) && simd_distance(bolts[$0], rock.position) < rock.radius + 12 }) {
                spent.insert(b)
                destroyed += 1
                let points = rock.big ? 10 : 15
                score += points
                floaters.append(FaceGameFloater(text: "+\(points)", position: rock.position + SIMD2(0, 30), tone: FaceGamePalette.mint, size: 44, life: 0.7))
                explode(at: rock.position, size: rock.radius)
                if rock.big {
                    for side in [-1.0, 1.0] {
                        born.append(Rock(position: rock.position + SIMD2(side * 18, 0), velocity: SIMD2(side * 140 + rock.velocity.x * 0.5, rock.velocity.y * 0.9 + 40),
                                         radius: Self.smallRadius, spin: side * 2.2, variant: (rock.variant + 1) % 3))
                    }
                }
            } else {
                kept.append(rock)
            }
        }
        rocks = kept + born
        var flying: [Saucer] = []
        for saucer in saucers {
            if let b = bolts.indices.first(where: { !spent.contains($0) && abs(bolts[$0].x - saucer.position.x) < 66 && abs(bolts[$0].y - saucer.position.y) < 34 }) {
                spent.insert(b)
                destroyed += 1
                score += 25
                floaters.append(FaceGameFloater(text: "+25", position: saucer.position + SIMD2(0, 40), tone: FaceGamePalette.sun, size: 56))
                explode(at: saucer.position, size: 60)
            } else {
                flying.append(saucer)
            }
        }
        saucers = flying
        if !spent.isEmpty { bolts = bolts.enumerated().filter { !spent.contains($0.offset) }.map(\.element) }
    }

    private mutating func checkShip() {
        let ship = SIMD2(shipX, Self.shipY)
        if let i = rocks.firstIndex(where: { simd_distance($0.position, ship) < $0.radius + Self.shipRadius * 0.8 }) {
            explode(at: rocks[i].position, size: rocks[i].radius)
            rocks.remove(at: i)
            hit()
        } else if let i = saucers.firstIndex(where: { abs($0.position.x - ship.x) < 70 && abs($0.position.y - ship.y) < 50 }) {
            explode(at: saucers[i].position, size: 60)
            saucers.remove(at: i)
            hit()
        }
    }

    private mutating func hit() {
        hearts -= 1
        invulnerable = 1.6
        shake = 1
        explode(at: SIMD2(shipX, Self.shipY), size: 50)
    }

    private mutating func explode(at p: SIMD2<Double>, size: Double) {
        rings.append((p.x, p.y, 0, size))
        for _ in 0..<Int(10 + size * 0.4) {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), v = Double.random(in: 80...420, using: &rng)
            debris.emit(Particle(position: p, velocity: SIMD2(cos(a), sin(a)) * v, life: Double.random(in: 0.3...0.7, using: &rng),
                                 size: Double.random(in: 6...16, using: &rng), hue: Double.random(in: 0...1, using: &rng), kind: 0))
        }
        for _ in 0..<8 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), v = Double.random(in: 60...240, using: &rng)
            debris.emit(Particle(position: p, velocity: SIMD2(cos(a), sin(a)) * v, life: Double.random(in: 0.6...1.1, using: &rng),
                                 size: Double.random(in: 4...9, using: &rng), hue: Double.random(in: 0..<(2 * .pi), using: &rng), kind: 1))
        }
    }

    /// After the round only the particles and words carry on; with no face, nothing in the rules moves.
    mutating func settle(_ dt: Double) {
        step(dt, world: GameWorld(size: size, matte: nil, motion: nil, face: nil))
    }

    // MARK: Test hooks

    /// Replaces everything in space with these rocks and stops new ones from coming.
    mutating func place(rocks: [Rock]) {
        self.rocks = rocks
        saucers = []
        spawning = false
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        drawSpace(ctx, time: time)
        ctx.saveGState()
        let wobble = shake * shake * 9
        ctx.translateBy(x: CGFloat(sin(time * 57) * wobble), y: CGFloat(cos(time * 49) * wobble))
        for saucer in saucers { drawSaucer(saucer, ctx, time: time) }
        for rock in rocks {
            FaceGameArt.stamp(ctx, SpaceBlasterArt.rock(rock.variant), at: CGPoint(x: rock.position.x, y: rock.position.y), height: rock.radius * 2.45, rotation: rock.angle)
        }
        for bolt in bolts { drawBolt(bolt, ctx) }
        drawShip(ctx, time: time)
        for ring in rings {
            let t = ring.age / 0.5
            let r = ring.size * (0.6 + 1.6 * FaceGameEase.cubicOut(t))
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.sun, 0.8 * (1 - t)))
            ctx.setLineWidth(CGFloat(8 * (1 - t) + 1))
            ctx.strokeEllipse(in: CGRect(x: ring.x - r, y: ring.y - r, width: r * 2, height: r * 2))
        }
        for p in debris.particles {
            let point = CGPoint(x: p.position.x, y: p.position.y)
            if p.kind == 0 {
                FaceGamePaint.spark(ctx, at: point, radius: p.size * (1.3 - p.progress),
                                    tone: FaceGamePaint.mix(FaceGamePalette.cream, FaceGamePaint.mix(FaceGamePalette.sun, FaceGamePalette.tangerine, p.hue), p.progress * 1.5),
                                    alpha: 1 - p.progress)
            } else {
                ctx.saveGState()
                ctx.translateBy(x: point.x, y: point.y)
                ctx.rotate(by: CGFloat(p.hue + p.age * 6))
                ctx.setFillColor(FaceGamePaint.cg(SpaceBlasterArt.rockTone, 1 - p.progress))
                ctx.fill(CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size * 0.7))
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
        FaceGamePaint.draw(floaters, in: ctx)
    }

    /// A dark veil over the room so space reads as space, with stars sliding by at three depths and a planet far off.
    private func drawSpace(_ ctx: CGContext, time: Double) {
        // One flat veil: a gradient this big would cost several times as much for a difference no one would see behind the stars.
        ctx.setFillColor(FaceGamePaint.cg(FaceGamePaint.mix(FaceGamePalette.ink, FaceGamePalette.dusk, 0.3), 0.58))
        ctx.fill(CGRect(origin: .zero, size: size))
        FaceGameArt.stamp(ctx, SpaceBlasterArt.planet, at: CGPoint(x: size.width - 190, y: size.height * 0.62 + 10 * sin(time * 0.2)), height: 200, rotation: -0.25, alpha: 0.9)
        let travel = elapsed
        for layer in 0..<3 {
            let speed = [18.0, 46.0, 110.0][layer]
            let r = [2.5, 3.5, 5.0][layer]
            for i in 0..<26 {
                let x = FaceGamePaint.hash(i + layer * 100, 1) * size.width
                let y = FaceGamePaint.wrap(FaceGamePaint.hash(i + layer * 100, 2) * size.height - travel * speed, size.height)
                let twinkle = 0.6 + 0.4 * sin(time * (2 + FaceGamePaint.hash(i, 3) * 3) + Double(i))
                FaceGamePaint.spark(ctx, at: CGPoint(x: x, y: y), radius: r * 2.2, tone: layer == 2 ? FaceGamePalette.cream : FaceGamePalette.sky, alpha: twinkle * (0.5 + 0.2 * Double(layer)))
                if layer == 2 {
                    ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.cream, 0.3 * twinkle))
                    ctx.fill(CGRect(x: x - 1, y: y, width: 2, height: 16))
                }
            }
        }
    }

    private func drawBolt(_ p: SIMD2<Double>, _ ctx: CGContext) {
        let c = CGPoint(x: p.x, y: p.y)
        FaceGamePaint.spark(ctx, at: c, radius: 26, tone: FaceGamePalette.mint, alpha: 0.6)
        FaceGamePaint.fill(ctx, rounded: CGRect(x: c.x - 5, y: c.y - 26, width: 10, height: 52), radius: 5, color: FaceGamePaint.cg(FaceGamePalette.mint))
        FaceGamePaint.fill(ctx, rounded: CGRect(x: c.x - 2.5, y: c.y - 20, width: 5, height: 40), radius: 2.5, color: FaceGamePaint.cg(FaceGamePalette.cream))
    }

    private func drawSaucer(_ saucer: Saucer, _ ctx: CGContext, time: Double) {
        let c = CGPoint(x: saucer.position.x, y: saucer.position.y)
        FaceGamePaint.spark(ctx, at: CGPoint(x: c.x, y: c.y - 40), radius: 60, tone: FaceGamePalette.mint, alpha: 0.25 + 0.15 * sin(time * 8))
        FaceGameArt.stamp(ctx, SpaceBlasterArt.saucer, at: c, height: 100, rotation: sin(saucer.age * 3) * 0.08)
        for k in 0..<5 {
            let lit = Int(time * 8 + Double(k)) % 5 == 0
            let p = CGPoint(x: c.x - 48 + Double(k) * 24, y: c.y - 8)
            FaceGamePaint.spark(ctx, at: p, radius: lit ? 12 : 6, tone: lit ? FaceGamePalette.sun : FaceGamePalette.tangerine, alpha: 1)
        }
    }

    private func drawShip(_ ctx: CGContext, time: Double) {
        let pulse = invulnerable > 0 ? 0.5 + 0.5 * (0.5 + 0.5 * cos(invulnerable * 2 * .pi * 2.5)) : 1
        let lean = max(-0.32, min(0.32, -bank / 1600))
        ctx.saveGState()
        ctx.translateBy(x: shipX, y: Self.shipY)
        ctx.rotate(by: CGFloat(lean))
        ctx.setAlpha(CGFloat(pulse))
        // The engine flame: three soft layers that flicker.
        let flicker = 0.8 + 0.2 * sin(time * 47) + 0.1 * sin(time * 31)
        for (len, r, tone) in [(58.0, 30.0, FaceGamePalette.tangerine), (44.0, 20.0, FaceGamePalette.sun), (30.0, 11.0, FaceGamePalette.cream)] {
            FaceGamePaint.spark(ctx, at: CGPoint(x: 0, y: -62 - len * 0.45 * flicker), radius: r * flicker, tone: tone, alpha: 0.9)
            FaceGamePaint.spark(ctx, at: CGPoint(x: 0, y: -62 - len * 0.8 * flicker), radius: r * 0.6 * flicker, tone: tone, alpha: 0.7)
        }
        FaceGameArt.stamp(ctx, SpaceBlasterArt.ship, at: .zero, height: 200)
        let pit = SpaceBlasterArt.cockpit, r = SpaceBlasterArt.cockpitRadius
        FaceGamePaint.drawFace(ctx, crop: crop, in: CGRect(x: pit.x - r, y: pit.y - r, width: r * 2, height: r * 2), corner: r)
        FaceGameArt.stamp(ctx, SpaceBlasterArt.glass, at: pit, height: 64)
        if firing {
            FaceGamePaint.spark(ctx, at: CGPoint(x: 0, y: 92), radius: 30 + 16 * muzzle, tone: FaceGamePalette.mint, alpha: 0.5 + 0.5 * muzzle)
        }
        ctx.restoreGState()
    }
}
