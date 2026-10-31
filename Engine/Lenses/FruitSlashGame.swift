import AppKit
import CoreGraphics
import simd

/// Fruit flies up from below. Swing your hand through it: your hand is the sword. Bombs cost a life, and so does every fruit you let fall.
///
/// The blade is the fingertip that reaches furthest from the wrist. Hand tracking only looks about 30 times a second and
/// loses a hand that is moving fast, so a slice is judged on the whole path the tip travelled since the last look, not on where it is,
/// and the hit area is a little bigger than the fruit. When no hand is in view at all, a strong movement of the body through a fruit
/// cuts it instead, so a blur doesn't stop the game.
struct FruitSlashGame: HandGameScreens {
    static let title = "Fruit Slash"
    static let hint = "Swing your hand through the fruit. Don't touch the bombs!"
    static let presenceHint = "Hold up your hand to play"
    static let onboarding = ["Swing your hand through the fruit", "Several in one swipe make a combo", "Leave the bombs alone"]
    static let accent = SIMD3<Double>(1.0, 0.56, 0.45)
    static let icon = GameUIIcon.hand(.open)

    enum Kind: Equatable {
        case fruit(Int)
        case bomb
    }

    struct Fruit {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var radius: Double
        var angle: Double
        var spin: Double
        var kind: Kind
        /// Whether it has been up in the air, so that one falling out of the bottom counts as a miss.
        var flew = false
        var age = 0.0
    }

    /// One side of a sliced fruit.
    struct Half {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var angle: Double
        var spin: Double
        var radius: Double
        /// Which fruit it was.
        var kind: Int
        /// The direction of the cut, in the fruit's own frame, so it turns with the fruit.
        var cut: Double
        var side: Double
        var age = 0.0
    }

    struct Streak { var from: SIMD2<Double>; var to: SIMD2<Double>; var age = 0.0 }
    /// A juice stain where a fruit was cut, or a cross where one fell.
    struct Mark { var position: SIMD2<Double>; var kind: Int; var angle: Double; var age = 0.0 }

    private struct Blade {
        var last: SIMD2<Double>?
        var trail: [(point: SIMD2<Double>, age: Double)] = []
        var unseenFor = 0.0
    }

    /// The fruit, in the order `Kind.fruit(n)` names them.
    static let kinds = FruitSlashArt.all.map(\.name)
    static let gravity = 1150.0
    static let startingLives = 3
    /// A hand moving slower than this (pixels a second) is resting, not slashing. Scaled up a little for a hand near the camera.
    static let minSlashSpeed = 380.0
    /// Slices closer together than this count as one swipe.
    static let comboWindow = 0.32
    /// How much bigger than a fruit its hit area is, in pixels: a near miss on a noisy camera still cuts.
    static let reach = 18.0

    let size: CGSize
    private(set) var fruit: [Fruit] = []
    private(set) var halves: [Half] = []
    private(set) var score = 0
    private(set) var lives = FruitSlashGame.startingLives
    private(set) var sliced = 0
    private(set) var missed = 0
    private(set) var elapsed = 0.0
    private(set) var combo = 0
    private(set) var bestCombo = 0
    private(set) var bombsHit = 0
    private var sinceSlice = 99.0
    private var blades: [Int: Blade] = [:]
    private var streaks: [Streak] = []
    private var splats: [Mark] = []
    private var crosses: [Mark] = []
    private var spray = ParticleSystem(capacity: 520)
    private var smoke = ParticleSystem(capacity: 60)
    private var rng: SplitMix64
    private var nextWave = 0.6
    private var boom = 0.0
    private var boomAt = SIMD2<Double>(0, 0)
    private var waves = 0
    private var comboShown = (count: 0, at: SIMD2<Double>(0, 0), age: 99.0)

    var isOver: Bool { lives <= 0 }
    var summary: String { "\(max(0, lives)) of \(Self.startingLives) lives" }

    var readout: GameUIReadout {
        GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), combo: sinceSlice < 1.2 && combo >= 2 ? combo : 0)
    }

    var result: GameUIResult {
        let line: String
        switch sliced {
        case 0: line = "Swing right through them next time"
        case 1..<15: line = "A good start. Try slicing a few at once"
        case 15..<40: line = "Sharp work!"
        default: line = "A true fruit ninja"
        }
        let seconds = Int(elapsed)
        return GameUIResult(headline: "Out of lives", line: line,
                            stats: [("\(sliced)", "sliced"), (bestCombo >= 2 ? "x\(bestCombo)" : "-", "best combo"),
                                    (String(format: "%d:%02d", seconds / 60, seconds % 60), "time")])
    }

    static func warmUp(_ step: Int) -> Bool {
        let n = FruitSlashArt.all.count
        switch step {
        case 0..<n: _ = FruitSlashArt.whole(step)
        case n..<(2 * n): _ = FruitSlashArt.half(step - n)
        case (2 * n)..<(3 * n): _ = FruitSlashArt.splat(step - 2 * n)
        case 3 * n: _ = HandGamePieces.bomb()
        case 3 * n + 1: _ = FruitSlashArt.missMark()
        default: return false
        }
        return true
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        spray.gravity = SIMD2(0, -900)
        smoke.gravity = SIMD2(0, 60)
        smoke.drag = 1.2
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.25)
        elapsed += dt
        sinceSlice += dt
        boom = max(0, boom - dt * 1.6)
        comboShown.age += dt

        nextWave -= dt
        if nextWave <= 0 { launchWave() }

        for i in fruit.indices {
            fruit[i].velocity.y -= Self.gravity * dt
            fruit[i].position += fruit[i].velocity * dt
            fruit[i].angle += fruit[i].spin * dt
            fruit[i].age += dt
            if fruit[i].position.y > 40 { fruit[i].flew = true }
        }
        for i in halves.indices {
            halves[i].velocity.y -= Self.gravity * dt
            halves[i].position += halves[i].velocity * dt
            halves[i].angle += halves[i].spin * dt
            halves[i].age += dt
        }
        halves.removeAll { $0.position.y < -$0.radius * 2 || $0.age > 3 }

        slash(world: world, dt: dt)

        // Whatever fell out of the bottom: a fruit is a miss, a bomb is a good thing to have missed.
        for f in fruit where f.position.y < -f.radius * 1.4 && f.velocity.y < 0 {
            if case .fruit = f.kind, f.flew {
                lives -= 1
                missed += 1
                combo = 0
                crosses.append(Mark(position: SIMD2(min(Double(size.width) - 90, max(90, f.position.x)), 78), kind: 0, angle: 0))
            }
        }
        fruit.removeAll { $0.position.y < -$0.radius * 1.4 && $0.velocity.y < 0 }

        spray.step(dt)
        smoke.step(dt)
        for i in streaks.indices { streaks[i].age += dt }
        streaks.removeAll { $0.age > 0.22 }
        for i in splats.indices { splats[i].age += dt }
        splats.removeAll { $0.age > 0.7 }
        for i in crosses.indices { crosses[i].age += dt }
        crosses.removeAll { $0.age > 1.3 }
    }

    /// Launches a handful of fruit (and sometimes a bomb) from below the picture, each arcing up to a height of its own.
    mutating func launchWave() {
        waves += 1
        let ease = min(1, elapsed / 60)
        let count = 1 + Int(Double.random(in: 0..<1, using: &rng) * (2 + 3 * ease)) + (waves > 3 && Double.random(in: 0..<1, using: &rng) < 0.25 ? 1 : 0)
        var bombs = 0
        for _ in 0..<min(count, 6) {
            let bomb = elapsed > 5 && bombs == 0 && Double.random(in: 0..<1, using: &rng) < 0.12 + 0.12 * ease
            if bomb { bombs += 1 }
            launch(bomb ? .bomb : .fruit(Int.random(in: 0..<Self.kinds.count, using: &rng)))
        }
        nextWave = (1.7 - 0.9 * ease) * Double.random(in: 0.8...1.2, using: &rng)
    }

    /// One fruit from a random place along the bottom, thrown so that it peaks at a chosen height and drifts toward the middle.
    mutating func launch(_ kind: Kind, from x: Double? = nil, apex: Double? = nil) {
        var radius = Double.random(in: 46...58, using: &rng)
        if case .fruit(let n) = kind { radius *= FruitSlashArt.art(n).scale }
        let startX = x ?? Double.random(in: size.width * 0.12...size.width * 0.88, using: &rng)
        let top = apex ?? Double.random(in: size.height * 0.55...size.height * 0.9, using: &rng)
        let rise = max(80, top + radius)
        let vy = (2 * Self.gravity * rise).squareRoot()
        let flight = 2 * vy / Self.gravity
        let aimX = size.width / 2 + Double.random(in: -size.width * 0.3...size.width * 0.3, using: &rng)
        let vx = (aimX - startX) / flight
        fruit.append(Fruit(position: SIMD2(startX, -radius), velocity: SIMD2(vx, vy), radius: radius,
                           angle: Double.random(in: 0..<(2 * .pi), using: &rng), spin: Double.random(in: -3...3, using: &rng), kind: kind))
    }

    // MARK: Slashing

    private mutating func slash(world: GameWorld, dt: Double) {
        var seen = Set<Int>()
        for hand in world.hands {
            seen.insert(hand.id)
            swing(hand, dt: dt)
        }
        for id in Array(blades.keys) where !seen.contains(id) {
            blades[id]?.unseenFor += dt
            if let b = blades[id], b.last != nil, b.unseenFor > 0.15 { blades[id]?.last = nil }
        }
        for id in Array(blades.keys) {
            guard var blade = blades[id] else { continue }
            for i in blade.trail.indices { blade.trail[i].age += dt }
            blade.trail.removeAll { $0.age > 0.2 }
            blades[id] = blade.trail.isEmpty && blade.unseenFor > 0.3 ? nil : blade
        }

        // No hand at all: a strong movement through a fruit is still a cut.
        if world.hands.isEmpty, let motion = world.motion {
            for i in fruit.indices.reversed() where motion.coverage(x: fruit[i].position.x, y: fruit[i].position.y) > 0.65 {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                cut(at: i, direction: SIMD2(cos(a), sin(a)))
            }
        }
    }

    private mutating func swing(_ hand: HandState, dt: Double) {
        var blade = blades[hand.id] ?? Blade()
        blade.unseenFor = 0
        let tip = SIMD2(Double(hand.leadTip.x), Double(hand.leadTip.y))
        let previous = blade.last
        blade.last = tip
        blade.trail.append((tip, 0))
        blades[hand.id] = blade

        let moved = previous.map { simd_distance($0, tip) } ?? 0
        let speed = max(hypot(Double(hand.tipVelocity.dx), Double(hand.tipVelocity.dy)),
                        hypot(Double(hand.velocity.dx), Double(hand.velocity.dy)), moved / max(dt, 1e-3))
        guard speed > max(Self.minSlashSpeed, hand.size * 3.2) else { return }

        var heading = previous.map { tip - $0 } ?? SIMD2<Double>.zero
        if simd_length(heading) < 2 { heading = SIMD2(Double(hand.velocity.dx), Double(hand.velocity.dy)) }
        heading = simd_length(heading) > 1e-6 ? simd_normalize(heading) : SIMD2(1, 0)

        let palm = SIMD2(Double(hand.palm.x), Double(hand.palm.y))
        for i in fruit.indices.reversed() {
            let f = fruit[i]
            // The path the tip took, and the hand itself laid along it like the flat of a sword.
            let hit = previous.map { HandGeometry.segment(from: $0, to: tip, hits: f.position, radius: f.radius + Self.reach) } ?? false
            let bar = HandGeometry.segment(from: palm, to: tip, hits: f.position, radius: f.radius * 0.85)
            if hit || bar {
                streaks.append(Streak(from: f.position - heading * f.radius * 1.5, to: f.position + heading * f.radius * 1.5))
                cut(at: i, direction: heading)
            }
        }
    }

    /// Slices or detonates the fruit at `index`, cutting along `direction`.
    mutating func cut(at index: Int, direction: SIMD2<Double>) {
        guard fruit.indices.contains(index) else { return }
        let f = fruit.remove(at: index)
        switch f.kind {
        case .bomb:
            lives -= 1
            bombsHit += 1
            combo = 0
            boom = 1
            boomAt = f.position
            for _ in 0..<46 {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 150...640, using: &rng)
                spray.emit(Particle(position: f.position, velocity: SIMD2(cos(a), sin(a)) * s, life: Double.random(in: 0.35...0.8, using: &rng),
                                    size: Double.random(in: 3...9, using: &rng), hue: 0, kind: -1))
            }
            for _ in 0..<14 {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 40...160, using: &rng)
                smoke.emit(Particle(position: f.position, velocity: SIMD2(cos(a), sin(a)) * s, life: Double.random(in: 0.7...1.3, using: &rng),
                                    size: Double.random(in: 22...44, using: &rng)))
            }
        case .fruit(let which):
            sliced += 1
            combo = sinceSlice < Self.comboWindow ? combo + 1 : 1
            bestCombo = max(bestCombo, combo)
            sinceSlice = 0
            let bonus = combo >= 3 ? combo - 2 : 0
            score += 1 + bonus
            if bonus > 0 { comboShown = (combo, f.position, 0) }
            separate(f, along: direction, which: which)
        }
    }

    private mutating func separate(_ f: Fruit, along direction: SIMD2<Double>, which: Int) {
        let worldCut = atan2(direction.y, direction.x)
        let normal = SIMD2(-direction.y, direction.x)
        for side in [-1.0, 1.0] {
            halves.append(Half(position: f.position + normal * side * 4, velocity: f.velocity * 0.55 + normal * side * Double.random(in: 150...260, using: &rng)
                                + direction * 60, angle: f.angle, spin: f.spin + side * Double.random(in: 1.5...3.5, using: &rng), radius: f.radius,
                               kind: which, cut: worldCut - f.angle, side: side))
        }
        splats.append(Mark(position: f.position, kind: which, angle: Double.random(in: 0..<(2 * .pi), using: &rng)))
        for n in 0..<26 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 80...460, using: &rng)
            // Most of the juice flies out along the cut.
            let along = direction * Double.random(in: -1...1, using: &rng) * 220
            spray.emit(Particle(position: f.position, velocity: SIMD2(cos(a), sin(a)) * s * 0.7 + along + normal * Double.random(in: -120...120, using: &rng),
                                life: Double.random(in: 0.35...0.85, using: &rng), size: Double.random(in: n % 5 == 0 ? 7...11 : 2.5...6.5, using: &rng),
                                hue: Double.random(in: 0.85...1.15, using: &rng), kind: which))
        }
    }

    // MARK: Test hooks

    /// Replaces everything in the air with `kinds`, all at `point`, not moving.
    mutating func setFruit(_ kinds: [Kind], at point: CGPoint, radius: Double = 50) {
        fruit = kinds.map { Fruit(position: SIMD2(Double(point.x), Double(point.y)), velocity: .zero, radius: radius, angle: 0, spin: 0, kind: $0, flew: true) }
        nextWave = 1000
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        // A bomb gives the picture a short, soft jolt rather than a flash.
        let shake = boom > 0 ? 7 * boom * boom : 0
        ctx.saveGState()
        if shake > 0 { ctx.translateBy(x: CGFloat(sin(time * 71) * shake), y: CGFloat(cos(time * 53) * shake)) }
        if boom > 0 {
            // A warm bloom and a ring of air pushed out from where the bomb went off.
            let at = CGPoint(x: boomAt.x, y: boomAt.y)
            let t = 1 - boom
            HandGameArt.halo(ctx, at: at, radius: CGFloat(110 + 90 * t), red: 1, green: 0.72, blue: 0.4, alpha: 0.7 * boom)
            let ring = CGFloat(60 + 260 * HandGameEase.outCubic(t))
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.9, blue: 0.75, alpha: CGFloat(0.55 * boom)))
            ctx.setLineWidth(CGFloat(3 + 10 * boom))
            ctx.strokeEllipse(in: CGRect(x: at.x - ring, y: at.y - ring, width: ring * 2, height: ring * 2))
        }
        drawSplats(ctx)
        for h in halves { Self.drawHalf(h, in: ctx) }
        for f in fruit { Self.drawFruit(f, in: ctx, time: time) }
        drawSpray(ctx)
        drawStreaks(ctx)
        ctx.restoreGState()
        if !isOver { drawBlades(ctx) }
        drawCrosses(ctx)
        if comboShown.age < 0.9 {
            let rise = HandGameEase.outCubic(comboShown.age / 0.9)
            let p = CGPoint(x: comboShown.at.x, y: comboShown.at.y + 40 + 50 * rise)
            HandGameType.draw(ctx, "+\(comboShown.count - 2) combo", at: p, size: 30, color: HandGamePalette.color(HandGamePalette.gold),
                              alpha: CGFloat(min(1, (0.9 - comboShown.age) / 0.3)), scale: CGFloat(HandGameEase.outBack(comboShown.age / 0.25)))
        }
    }

    private func drawSplats(_ ctx: CGContext) {
        for s in splats {
            guard let sprite = FruitSlashArt.splat(s.kind) else { continue }
            let grow = 0.55 + 0.45 * HandGameEase.outCubic(s.age / 0.15)
            let fade = max(0, 1 - max(0, s.age - 0.25) / 0.45)
            ctx.draw(sprite, center: CGPoint(x: s.position.x, y: s.position.y), height: CGFloat(150 * grow), rotation: CGFloat(s.angle), alpha: CGFloat(0.55 * fade))
        }
    }

    private func drawSpray(_ ctx: CGContext) {
        for p in spray.particles {
            let at = CGPoint(x: p.position.x, y: p.position.y)
            if p.kind < 0 {
                // Bomb sparks: hot white turning orange as they cool.
                let cool = p.progress
                HandGameArt.halo(ctx, at: at, radius: CGFloat(p.size * (2.2 - cool)), red: 1, green: 0.85 - 0.4 * cool, blue: 0.5 - 0.4 * cool, alpha: 1 - cool)
                continue
            }
            let juice = FruitSlashArt.art(p.kind).juice * p.hue
            let fade = 1 - p.progress * p.progress
            let r = CGFloat(p.size * (1 - 0.3 * p.progress))
            ctx.fillCircle(center: at, radius: r, color: CGColor(srgbRed: juice.x, green: juice.y, blue: juice.z, alpha: fade))
            if r > 4 {
                ctx.fillCircle(center: CGPoint(x: at.x - r * 0.35, y: at.y + r * 0.35), radius: r * 0.3, color: CGColor(gray: 1, alpha: 0.55 * fade))
            }
        }
        for p in smoke.particles {
            let a = 0.35 * (1 - p.progress)
            HandGameArt.halo(ctx, at: CGPoint(x: p.position.x, y: p.position.y), radius: CGFloat(p.size * (1 + p.progress)), red: 0.32, green: 0.3, blue: 0.36, alpha: a)
        }
    }

    private func drawStreaks(_ ctx: CGContext) {
        for s in streaks {
            let t = s.age / 0.22
            let fade = 1 - t
            let a = CGPoint(x: s.from.x, y: s.from.y), b = CGPoint(x: s.to.x, y: s.to.y)
            // The cut line opens out from the middle and fades.
            let open = HandGameEase.outCubic(t / 0.4)
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let p0 = CGPoint(x: mid.x + (a.x - mid.x) * CGFloat(open), y: mid.y + (a.y - mid.y) * CGFloat(open))
            let p1 = CGPoint(x: mid.x + (b.x - mid.x) * CGFloat(open), y: mid.y + (b.y - mid.y) * CGFloat(open))
            FruitSlashArt.ribbon(ctx, [p0, mid, p1], widths: [0.5, 9 * fade, 0.5], color: CGColor(gray: 1, alpha: 0.95 * fade))
        }
    }

    private func drawBlades(_ ctx: CGContext) {
        for blade in blades.values where blade.trail.count > 1 {
            let points = blade.trail.map { CGPoint(x: $0.point.x, y: $0.point.y) }
            let smooth = FruitSlashArt.smoothed(points)
            guard smooth.count > 1 else { continue }
            let head = blade.trail.last?.age ?? 1
            let life = max(0, 1 - head / 0.2)
            let widths = smooth.indices.map { i -> Double in
                let t = Double(i) / Double(smooth.count - 1)
                return 15 * pow(t, 0.9) * life
            }
            FruitSlashArt.ribbon(ctx, smooth, widths: widths.map { $0 * 2.4 }, color: HandGamePalette.color(HandGamePalette.sky, 0.28))
            FruitSlashArt.ribbon(ctx, smooth, widths: widths.map { $0 * 1.35 }, color: CGColor(srgbRed: 0.72, green: 0.9, blue: 1, alpha: 0.75))
            FruitSlashArt.ribbon(ctx, smooth, widths: widths.map { $0 * 0.6 }, color: CGColor(gray: 1, alpha: 1))
        }
        // A small glow on each blade tip, so you can see where your sword is even when it is still.
        for blade in blades.values where blade.unseenFor < 0.12 {
            guard let tip = blade.last else { continue }
            HandGameArt.halo(ctx, at: CGPoint(x: tip.x, y: tip.y), radius: 22, red: 0.75, green: 0.92, blue: 1, alpha: 0.85)
            HandGameArt.halo(ctx, at: CGPoint(x: tip.x, y: tip.y), radius: 7, red: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    private func drawCrosses(_ ctx: CGContext) {
        guard let sprite = FruitSlashArt.missMark() else { return }
        for c in crosses {
            let pop = HandGameEase.outBack(c.age / 0.3)
            let fade = max(0, 1 - max(0, c.age - 0.8) / 0.5)
            ctx.draw(sprite, center: CGPoint(x: c.position.x, y: c.position.y + 20 * HandGameEase.outCubic(c.age)), height: CGFloat(58 * pop), alpha: CGFloat(fade))
        }
    }

    static func drawFruit(_ f: Fruit, in ctx: CGContext, time: Double) {
        let c = CGPoint(x: f.position.x, y: f.position.y)
        switch f.kind {
        case .bomb:
            let pulse = 0.5 + 0.5 * sin(time * 9)
            HandGameArt.halo(ctx, at: c, radius: CGFloat(f.radius * (1.9 + 0.2 * pulse)), red: 1, green: 0.22, blue: 0.18, alpha: 0.35 + 0.25 * pulse)
            guard let sprite = HandGamePieces.bomb() else { return }
            let height = CGFloat(f.radius * 2.9)
            let turn = CGFloat(sin(f.angle) * 0.35)
            ctx.draw(sprite, center: c, height: height, rotation: turn)
            let fuse = HandGamePieces.bombFuseTip
            let tip = CGPoint(x: fuse.x * height, y: fuse.y * height).applying(CGAffineTransform(rotationAngle: turn))
            HandGamePieces.spark(ctx, at: CGPoint(x: c.x + tip.x, y: c.y + tip.y), size: CGFloat(f.radius * 0.32), time: time)
        case .fruit(let which):
            guard let sprite = FruitSlashArt.whole(which) else { return }
            // Squashed a touch along its flight and stretched at speed, so it feels thrown.
            let speed = simd_length(f.velocity)
            let stretch = CGFloat(min(0.08, speed / 18000))
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: CGFloat(atan2(f.velocity.y, f.velocity.x)))
            ctx.scaleBy(x: 1 + stretch, y: 1 - stretch)
            ctx.rotate(by: -CGFloat(atan2(f.velocity.y, f.velocity.x)))
            let h = CGFloat(f.radius / FruitSlashArt.bodyRadius) * FruitSlashArt.box
            ctx.draw(sprite, center: .zero, height: h, rotation: CGFloat(f.angle * 0.35))
            ctx.restoreGState()
        }
    }

    static func drawHalf(_ h: Half, in ctx: CGContext) {
        guard let sprite = FruitSlashArt.half(h.kind) else { return }
        let alpha = CGFloat(max(0, 1 - max(0, h.age - 1.5) / 1.5))
        ctx.saveGState()
        ctx.translateBy(x: h.position.x, y: h.position.y)
        ctx.rotate(by: CGFloat(h.angle + h.cut))
        // The flat cut faces the other half: one half is the sprite as drawn, the other upside down.
        if h.side < 0 { ctx.scaleBy(x: 1, y: -1) }
        let height = CGFloat(h.radius / FruitSlashArt.bodyRadius) * FruitSlashArt.box
        ctx.draw(sprite, center: .zero, height: height, alpha: alpha)
        ctx.restoreGState()
    }
}

// MARK: - The fruit

/// The look of each fruit: drawn once as a whole fruit and as a cut half, in layered vector shapes lit from the top left.
enum FruitSlashArt {
    struct Art {
        let name: String
        let skin: SIMD3<Double>
        let skinDark: SIMD3<Double>
        let flesh: SIMD3<Double>
        let juice: SIMD3<Double>
        /// How big it is next to the others.
        let scale: Double
    }

    static let all: [Art] = [
        Art(name: "watermelon", skin: SIMD3(0.36, 0.66, 0.30), skinDark: SIMD3(0.11, 0.33, 0.14), flesh: SIMD3(0.95, 0.30, 0.36), juice: SIMD3(0.93, 0.26, 0.36), scale: 1.15),
        Art(name: "orange", skin: SIMD3(1.0, 0.66, 0.2), skinDark: SIMD3(0.9, 0.38, 0.06), flesh: SIMD3(1.0, 0.62, 0.18), juice: SIMD3(1.0, 0.62, 0.15), scale: 0.95),
        Art(name: "lemon", skin: SIMD3(1.0, 0.92, 0.34), skinDark: SIMD3(0.88, 0.7, 0.1), flesh: SIMD3(1.0, 0.93, 0.5), juice: SIMD3(1.0, 0.9, 0.35), scale: 0.88),
        Art(name: "apple", skin: SIMD3(0.92, 0.2, 0.2), skinDark: SIMD3(0.55, 0.06, 0.1), flesh: SIMD3(1.0, 0.95, 0.8), juice: SIMD3(1.0, 0.93, 0.72), scale: 0.95),
        Art(name: "kiwi", skin: SIMD3(0.62, 0.45, 0.27), skinDark: SIMD3(0.36, 0.24, 0.13), flesh: SIMD3(0.55, 0.8, 0.22), juice: SIMD3(0.58, 0.82, 0.25), scale: 0.85),
        Art(name: "peach", skin: SIMD3(1.0, 0.72, 0.45), skinDark: SIMD3(0.92, 0.36, 0.36), flesh: SIMD3(1.0, 0.76, 0.38), juice: SIMD3(1.0, 0.7, 0.35), scale: 0.95),
        Art(name: "plum", skin: SIMD3(0.56, 0.27, 0.62), skinDark: SIMD3(0.24, 0.07, 0.3), flesh: SIMD3(1.0, 0.8, 0.36), juice: SIMD3(0.72, 0.18, 0.42), scale: 0.85),
        Art(name: "strawberry", skin: SIMD3(0.97, 0.24, 0.27), skinDark: SIMD3(0.62, 0.05, 0.14), flesh: SIMD3(1.0, 0.75, 0.75), juice: SIMD3(0.95, 0.2, 0.3), scale: 0.9),
    ]

    static func art(_ n: Int) -> Art { all[((n % all.count) + all.count) % all.count] }

    /// Sprites are drawn in a square this many points across, with the fruit's body this big, so they can be scaled by radius.
    static let box: CGFloat = 170
    static let bodyRadius = 56.0

    static func whole(_ n: Int) -> CGImage? {
        let a = art(n)
        return HandGameSprites.image("fruit.whole.\(a.name)", size: CGSize(width: box, height: box), scale: 1.3) { ctx in
            drawWhole(a, ctx)
        }
    }

    static func half(_ n: Int) -> CGImage? {
        let a = art(n)
        return HandGameSprites.image("fruit.half.\(a.name)", size: CGSize(width: box, height: box), scale: 1.3) { ctx in
            drawHalf(a, ctx)
        }
    }

    /// A splash of juice: a round body with drops thrown off it, in the fruit's own colour.
    static func splat(_ n: Int) -> CGImage? {
        let a = art(n)
        return HandGameSprites.image("fruit.splat.\(a.name)", size: CGSize(width: 160, height: 160), scale: 1) { ctx in
            var rng = SplitMix64(seed: UInt64(n + 7) &* 977)
            let deep = HandGameSprites.shade(a.juice, 0.8, alpha: 0.9), light = HandGameSprites.shade(a.juice, 1.15, alpha: 0.85)
            ctx.setFillColor(deep)
            ctx.fillEllipse(in: CGRect(x: -30, y: -27, width: 60, height: 54))
            for _ in 0..<13 {
                let ang = Double.random(in: 0..<(2 * .pi), using: &rng), d = Double.random(in: 26...66, using: &rng)
                let r = CGFloat(Double.random(in: 3...12, using: &rng) * (1.1 - d / 90))
                let p = CGPoint(x: cos(ang) * d, y: sin(ang) * d)
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                // A trail of juice back toward the middle.
                ctx.setStrokeColor(deep)
                ctx.setLineWidth(r * 0.9)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: p.x * 0.5, y: p.y * 0.5))
                ctx.addLine(to: p)
                ctx.strokePath()
            }
            ctx.setFillColor(light)
            ctx.fillEllipse(in: CGRect(x: -20, y: -16, width: 34, height: 30))
        }
    }

    /// A rounded cross where a fruit fell: a missed fruit costs a life.
    static func missMark() -> CGImage? {
        HandGameSprites.image("fruit.miss", size: CGSize(width: 70, height: 70)) { ctx in
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 5, color: HandGamePalette.color(HandGamePalette.ink, 0.5))
            ctx.setFillColor(HandGamePalette.color(HandGamePalette.ink, 0.7))
            ctx.fillEllipse(in: CGRect(x: -28, y: -28, width: 56, height: 56))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.coral))
            ctx.setLineWidth(9)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: -11, y: -11)); ctx.addLine(to: CGPoint(x: 11, y: 11))
            ctx.move(to: CGPoint(x: -11, y: 11)); ctx.addLine(to: CGPoint(x: 11, y: -11))
            ctx.strokePath()
        }
    }

    // MARK: Blade geometry

    /// A Catmull-Rom curve through the points, a few steps per span, so a trail sampled 30 times a second still reads as one sweep.
    static func smoothed(_ points: [CGPoint], steps: Int = 4) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var out: [CGPoint] = []
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(points.count - 1, i + 2)]
            for s in 0..<steps {
                let t = CGFloat(s) / CGFloat(steps), t2 = t * t, t3 = t2 * t
                let x = 0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                out.append(CGPoint(x: x, y: y))
            }
        }
        out.append(points[points.count - 1])
        return out
    }

    /// A filled ribbon along `points`, `widths[i]` wide at each, with round ends: a blade trail that tapers to nothing at its tail.
    static func ribbon(_ ctx: CGContext, _ points: [CGPoint], widths: [Double], color: CGColor) {
        guard points.count > 1, widths.count == points.count else { return }
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in points.indices {
            let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
            var dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let l = max(hypot(dx, dy), 1e-6)
            dx /= l; dy /= l
            let w = widths[i] / 2
            left.append(CGPoint(x: Double(points[i].x) - dy * w, y: Double(points[i].y) + dx * w))
            right.append(CGPoint(x: Double(points[i].x) + dy * w, y: Double(points[i].y) - dx * w))
        }
        let path = CGMutablePath()
        path.move(to: left[0])
        for p in left.dropFirst() { path.addLine(to: p) }
        for p in right.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        if let last = points.last, let w = widths.last, w > 1 {
            path.addEllipse(in: CGRect(x: Double(last.x) - w / 2, y: Double(last.y) - w / 2, width: w, height: w))
        }
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    // MARK: Drawing a fruit

    private static func c(_ v: SIMD3<Double>, _ light: Double = 1, _ alpha: Double = 1) -> CGColor { HandGameSprites.shade(v, light, alpha: alpha) }

    /// The outline of each fruit's body, centred on the origin.
    static func body(_ a: Art) -> CGPath {
        let r = CGFloat(bodyRadius)
        switch a.name {
        case "watermelon": return CGPath(ellipseIn: CGRect(x: -r * 1.12, y: -r * 0.94, width: r * 2.24, height: r * 1.88), transform: nil)
        case "lemon":
            // An oval drawn to a little point at each end.
            let p = CGMutablePath()
            p.move(to: CGPoint(x: r * 1.16, y: 0))
            p.addCurve(to: CGPoint(x: 0, y: r * 0.8), control1: CGPoint(x: r * 0.95, y: r * 0.32), control2: CGPoint(x: r * 0.62, y: r * 0.8))
            p.addCurve(to: CGPoint(x: -r * 1.16, y: 0), control1: CGPoint(x: -r * 0.62, y: r * 0.8), control2: CGPoint(x: -r * 0.95, y: r * 0.32))
            p.addCurve(to: CGPoint(x: 0, y: -r * 0.8), control1: CGPoint(x: -r * 0.95, y: -r * 0.32), control2: CGPoint(x: -r * 0.62, y: -r * 0.8))
            p.addCurve(to: CGPoint(x: r * 1.16, y: 0), control1: CGPoint(x: r * 0.62, y: -r * 0.8), control2: CGPoint(x: r * 0.95, y: -r * 0.32))
            p.closeSubpath()
            return p
        case "kiwi": return CGPath(ellipseIn: CGRect(x: -r * 1.05, y: -r * 0.86, width: r * 2.1, height: r * 1.72), transform: nil)
        case "apple":
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: r * 0.72))
            p.addCurve(to: CGPoint(x: r * 1.02, y: r * 0.18), control1: CGPoint(x: r * 0.4, y: r * 1.08), control2: CGPoint(x: r * 1.02, y: r * 0.95))
            p.addCurve(to: CGPoint(x: r * 0.12, y: -r * 0.98), control1: CGPoint(x: r * 1.02, y: -r * 0.55), control2: CGPoint(x: r * 0.55, y: -r * 1.0))
            p.addQuadCurve(to: CGPoint(x: -r * 0.12, y: -r * 0.98), control: CGPoint(x: 0, y: -r * 0.9))
            p.addCurve(to: CGPoint(x: -r * 1.02, y: r * 0.18), control1: CGPoint(x: -r * 0.55, y: -r * 1.0), control2: CGPoint(x: -r * 1.02, y: -r * 0.55))
            p.addCurve(to: CGPoint(x: 0, y: r * 0.72), control1: CGPoint(x: -r * 1.02, y: r * 0.95), control2: CGPoint(x: -r * 0.4, y: r * 1.08))
            p.closeSubpath()
            return p
        case "strawberry":
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: -r * 1.05))
            p.addCurve(to: CGPoint(x: r * 0.95, y: r * 0.45), control1: CGPoint(x: r * 0.55, y: -r * 0.85), control2: CGPoint(x: r * 1.05, y: -r * 0.1))
            p.addCurve(to: CGPoint(x: -r * 0.95, y: r * 0.45), control1: CGPoint(x: r * 0.8, y: r * 1.05), control2: CGPoint(x: -r * 0.8, y: r * 1.05))
            p.addCurve(to: CGPoint(x: 0, y: -r * 1.05), control1: CGPoint(x: -r * 1.05, y: -r * 0.1), control2: CGPoint(x: -r * 0.55, y: -r * 0.85))
            p.closeSubpath()
            return p
        case "plum": return CGPath(ellipseIn: CGRect(x: -r * 0.9, y: -r * 0.98, width: r * 1.8, height: r * 1.96), transform: nil)
        default: return CGPath(ellipseIn: CGRect(x: -r * 0.97, y: -r * 0.97, width: r * 1.94, height: r * 1.94), transform: nil)
        }
    }

    private static func drawWhole(_ a: Art, _ ctx: CGContext) {
        let r = CGFloat(bodyRadius)
        let shape = body(a)
        // A soft shadow, then the skin lit from the top left.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 2, height: -4), blur: 7, color: HandGamePalette.color(HandGamePalette.ink, 0.4))
        ctx.addPath(shape)
        ctx.setFillColor(c(a.skinDark))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        HandGameSprites.radial(ctx, [c(a.skin, 1.2), c(a.skin), c(a.skinDark)], locations: [0, 0.45, 1], center: CGPoint(x: r * 0.1, y: -r * 0.1),
                               radius: r * 1.25, focus: CGPoint(x: -r * 0.4, y: r * 0.42))
        surface(a, ctx)
        // Reflected light along the lower right edge, and a soft dark rim, so it reads on a dark room and a light one.
        var nudge = CGAffineTransform(translationX: -3.5, y: 3.5)
        if let moved = shape.copy(using: &nudge) {
            ctx.addPath(moved)
            ctx.setStrokeColor(c(a.skin, 1.3, 0.4))
            ctx.setLineWidth(5)
            ctx.strokePath()
        }
        ctx.restoreGState()
        ctx.addPath(shape)
        ctx.setStrokeColor(c(a.skinDark, 0.7, 0.85))
        ctx.setLineWidth(2.2)
        ctx.strokePath()
        // The shine.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.28))
        ctx.fillEllipse(in: CGRect(x: -r * 0.72, y: r * 0.12, width: r * 0.62, height: r * 0.44))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.75))
        ctx.fillEllipse(in: CGRect(x: -r * 0.55, y: r * 0.36, width: r * 0.2, height: r * 0.13))
        ctx.restoreGState()
        topping(a, ctx)
    }

    /// What is on the skin: stripes, dimples, seeds, fuzz, a crease, a bloom.
    private static func surface(_ a: Art, _ ctx: CGContext) {
        let r = CGFloat(bodyRadius)
        var rng = SplitMix64(seed: UInt64(a.name.count) &* 7919)
        switch a.name {
        case "watermelon":
            ctx.setStrokeColor(c(a.skinDark, 1, 0.85))
            ctx.setLineCap(.round)
            for k in -3...3 {
                let x0 = CGFloat(k) * r * 0.33
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x0 * 0.8, y: r))
                for s in 1...12 {
                    let t = CGFloat(s) / 12
                    let y = r - t * r * 2
                    let bulge = x0 * (1 + 0.25 * sin(t * .pi))
                    p.addLine(to: CGPoint(x: bulge + sin(t * 18 + CGFloat(k)) * r * 0.05, y: y))
                }
                ctx.addPath(p)
                ctx.setLineWidth(r * 0.15)
                ctx.strokePath()
            }
        case "orange", "lemon":
            for _ in 0..<70 {
                let x = Double.random(in: -1.1...1.1, using: &rng), y = Double.random(in: -1...1, using: &rng)
                let d = CGFloat(Double.random(in: 1.2...2.4, using: &rng))
                ctx.setFillColor(Bool.random(using: &rng) ? c(a.skinDark, 1, 0.22) : c(a.skin, 1.3, 0.3))
                ctx.fillEllipse(in: CGRect(x: CGFloat(x) * r - d, y: CGFloat(y) * r - d, width: d * 2, height: d * 2))
            }
        case "kiwi":
            ctx.setLineWidth(1.1)
            for _ in 0..<160 {
                let x = Double.random(in: -1.1...1.1, using: &rng), y = Double.random(in: -0.9...0.9, using: &rng)
                let ang = Double.random(in: 0..<(2 * .pi), using: &rng)
                ctx.setStrokeColor(Bool.random(using: &rng) ? c(a.skinDark, 0.8, 0.35) : c(a.skin, 1.35, 0.3))
                let p = CGPoint(x: CGFloat(x) * r, y: CGFloat(y) * r)
                ctx.move(to: p)
                ctx.addLine(to: CGPoint(x: p.x + CGFloat(cos(ang)) * 3.5, y: p.y + CGFloat(sin(ang)) * 3.5))
                ctx.strokePath()
            }
        case "peach":
            ctx.setStrokeColor(c(a.skinDark, 0.8, 0.45))
            ctx.setLineWidth(3)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: r * 0.05, y: r * 0.9))
            ctx.addCurve(to: CGPoint(x: r * 0.15, y: -r * 0.85), control1: CGPoint(x: r * 0.55, y: r * 0.4), control2: CGPoint(x: r * 0.5, y: -r * 0.4))
            ctx.strokePath()
        case "plum":
            HandGameSprites.radial(ctx, [CGColor(srgbRed: 0.85, green: 0.8, blue: 0.95, alpha: 0.32), CGColor(srgbRed: 0.85, green: 0.8, blue: 0.95, alpha: 0)],
                                   center: CGPoint(x: -r * 0.35, y: r * 0.3), radius: r * 0.8)
        case "strawberry":
            for row in 0..<7 {
                for col in 0..<7 {
                    let x = (CGFloat(col) - 3 + (row % 2 == 0 ? 0 : 0.5)) * r * 0.3
                    let y = r * 0.45 - CGFloat(row) * r * 0.24
                    let seed = CGRect(x: x - 2.2, y: y - 3.4, width: 4.4, height: 6.8)
                    ctx.setFillColor(c(a.skinDark, 0.75, 0.55))
                    ctx.fillEllipse(in: seed.insetBy(dx: -1.4, dy: -1.4))
                    ctx.setFillColor(CGColor(srgbRed: 1, green: 0.88, blue: 0.45, alpha: 1))
                    ctx.fillEllipse(in: seed)
                }
            }
        case "apple":
            HandGameSprites.radial(ctx, [CGColor(srgbRed: 1, green: 0.82, blue: 0.35, alpha: 0.45), CGColor(srgbRed: 1, green: 0.82, blue: 0.35, alpha: 0)],
                                   center: CGPoint(x: -r * 0.45, y: r * 0.05), radius: r * 0.65)
        default: break
        }
    }

    /// Stems, leaves and the strawberry's green cap.
    private static func topping(_ a: Art, _ ctx: CGContext) {
        let r = CGFloat(bodyRadius)
        let leafGreen = SIMD3<Double>(0.38, 0.72, 0.28)
        func leaf(at p: CGPoint, angle: CGFloat, length: CGFloat) {
            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: angle)
            let leaf = CGMutablePath()
            leaf.move(to: .zero)
            leaf.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.5, y: length * 0.42))
            leaf.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.5, y: -length * 0.42))
            ctx.setShadow(offset: CGSize(width: 0.5, height: -1.5), blur: 2, color: HandGamePalette.color(HandGamePalette.ink, 0.35))
            ctx.addPath(leaf)
            ctx.setFillColor(c(leafGreen))
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.addPath(leaf)
            ctx.clip()
            HandGameSprites.linear(ctx, [c(leafGreen, 1.3), c(leafGreen, 0.7)], from: CGPoint(x: 0, y: length * 0.3), to: CGPoint(x: length, y: -length * 0.3))
            ctx.setStrokeColor(c(leafGreen, 0.55, 0.7))
            ctx.setLineWidth(1.4)
            ctx.move(to: CGPoint(x: 2, y: 0))
            ctx.addLine(to: CGPoint(x: length * 0.85, y: 0))
            ctx.strokePath()
            ctx.restoreGState()
        }
        func stem(from p: CGPoint, to q: CGPoint) {
            ctx.setStrokeColor(CGColor(srgbRed: 0.42, green: 0.27, blue: 0.14, alpha: 1))
            ctx.setLineWidth(5)
            ctx.setLineCap(.round)
            ctx.move(to: p)
            ctx.addQuadCurve(to: q, control: CGPoint(x: (p.x + q.x) / 2 - 4, y: (p.y + q.y) / 2 + 3))
            ctx.strokePath()
        }
        switch a.name {
        case "apple":
            stem(from: CGPoint(x: 0, y: r * 0.62), to: CGPoint(x: r * 0.12, y: r * 1.05))
            leaf(at: CGPoint(x: r * 0.1, y: r * 0.85), angle: 0.45, length: r * 0.62)
        case "orange":
            leaf(at: CGPoint(x: 0, y: r * 0.9), angle: 0.7, length: r * 0.55)
            ctx.setFillColor(c(leafGreen, 0.7))
            ctx.fillEllipse(in: CGRect(x: -5, y: r * 0.86, width: 10, height: 8))
        case "peach":
            stem(from: CGPoint(x: r * 0.02, y: r * 0.86), to: CGPoint(x: r * 0.05, y: r * 1.05))
            leaf(at: CGPoint(x: r * 0.05, y: r * 0.98), angle: 2.6, length: r * 0.58)
        case "plum":
            stem(from: CGPoint(x: 0, y: r * 0.88), to: CGPoint(x: -r * 0.1, y: r * 1.12))
        case "strawberry":
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 3, color: HandGamePalette.color(HandGamePalette.ink, 0.35))
            for k in 0..<6 {
                let ang = CGFloat(k) / 6 * 2 * .pi + 0.3
                leaf(at: CGPoint(x: 0, y: r * 0.62), angle: ang * 0.55 - 0.9 + (k % 2 == 0 ? 0 : .pi), length: r * 0.48)
            }
            ctx.restoreGState()
            stem(from: CGPoint(x: 0, y: r * 0.66), to: CGPoint(x: r * 0.06, y: r * 0.95))
        case "watermelon":
            stem(from: CGPoint(x: -r * 0.05, y: r * 0.9), to: CGPoint(x: -r * 0.12, y: r * 1.05))
        default: break
        }
    }

    /// Half a fruit, the cut face up: the rounded skin below the cut and the flesh in an oval along it, as if tipped toward you.
    private static func drawHalf(_ a: Art, _ ctx: CGContext) {
        let r = CGFloat(bodyRadius)
        let shape = body(a)
        let box = shape.boundingBox
        let face = CGRect(x: box.minX + 1.5, y: -box.width * 0.2, width: box.width - 3, height: box.width * 0.4)
        // The skin: the part of the fruit below the cut.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 2, height: -4), blur: 7, color: HandGamePalette.color(HandGamePalette.ink, 0.4))
        let below = CGMutablePath()
        below.addRect(CGRect(x: -box.width, y: -box.height * 2, width: box.width * 2, height: box.height * 2))
        below.addEllipse(in: face)
        ctx.addPath(below)
        ctx.clip()
        ctx.addPath(shape)
        ctx.setFillColor(c(a.skinDark))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.clip(to: CGRect(x: -box.width, y: -box.height * 2, width: box.width * 2, height: box.height * 2))
        ctx.addPath(shape)
        ctx.clip()
        HandGameSprites.radial(ctx, [c(a.skin, 1.15), c(a.skin), c(a.skinDark)], locations: [0, 0.4, 1], center: CGPoint(x: 0, y: -r * 0.2),
                               radius: r * 1.2, focus: CGPoint(x: -r * 0.45, y: -r * 0.1))
        surface(a, ctx)
        ctx.restoreGState()
        // The cut face.
        let faceShape = CGPath(ellipseIn: face, transform: nil)
        ctx.saveGState()
        ctx.addPath(faceShape)
        ctx.clip()
        let rind: SIMD3<Double>
        switch a.name {
        case "watermelon": rind = SIMD3(0.88, 0.95, 0.8)
        case "orange", "lemon": rind = SIMD3(1, 0.97, 0.88)
        case "kiwi": rind = a.skin
        default: rind = a.skin
        }
        ctx.setFillColor(c(a.skinDark))
        ctx.fill(face)
        ctx.setFillColor(c(rind))
        ctx.fillEllipse(in: face.insetBy(dx: face.width * 0.03, dy: face.height * 0.06))
        let flesh = face.insetBy(dx: face.width * (a.name == "watermelon" ? 0.08 : 0.06), dy: face.height * (a.name == "watermelon" ? 0.16 : 0.12))
        ctx.addEllipse(in: flesh)
        ctx.clip()
        HandGameSprites.radial(ctx, [c(a.flesh, 1.12), c(a.flesh), c(a.flesh, 0.85)], locations: [0, 0.6, 1],
                               center: CGPoint(x: flesh.midX, y: flesh.midY), radius: flesh.width / 2)
        let mid = CGPoint(x: flesh.midX, y: flesh.midY)
        let sx = flesh.width / 2, sy = flesh.height / 2
        switch a.name {
        case "watermelon":
            for k in 0..<12 {
                let ang = CGFloat(k) / 12 * 2 * .pi
                let p = CGPoint(x: mid.x + cos(ang) * sx * 0.55, y: mid.y + sin(ang) * sy * 0.55)
                ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.08, blue: 0.08, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 3.2, width: 5, height: 6.4))
            }
        case "orange", "lemon":
            ctx.setStrokeColor(c(rind, 1, 0.9))
            ctx.setLineWidth(2)
            for k in 0..<10 {
                let ang = CGFloat(k) / 10 * 2 * .pi
                ctx.move(to: mid)
                ctx.addLine(to: CGPoint(x: mid.x + cos(ang) * sx, y: mid.y + sin(ang) * sy))
            }
            ctx.strokePath()
            ctx.setFillColor(c(rind))
            ctx.fillEllipse(in: CGRect(x: mid.x - 5, y: mid.y - 2.5, width: 10, height: 5))
        case "kiwi":
            ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.96, blue: 0.82, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: mid.x - sx * 0.32, y: mid.y - sy * 0.3, width: sx * 0.64, height: sy * 0.6))
            ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.08, blue: 0.06, alpha: 1))
            for k in 0..<18 {
                let ang = CGFloat(k) / 18 * 2 * .pi
                let p = CGPoint(x: mid.x + cos(ang) * sx * 0.44, y: mid.y + sin(ang) * sy * 0.44)
                ctx.fillEllipse(in: CGRect(x: p.x - 1.8, y: p.y - 1.4, width: 3.6, height: 2.8))
            }
        case "apple":
            ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.85, blue: 0.6, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: mid.x - sx * 0.3, y: mid.y - sy * 0.35, width: sx * 0.6, height: sy * 0.7))
            ctx.setFillColor(CGColor(srgbRed: 0.35, green: 0.2, blue: 0.1, alpha: 1))
            for dx in [-1.0, 1.0] { ctx.fillEllipse(in: CGRect(x: mid.x + CGFloat(dx) * 6 - 2.5, y: mid.y - 3, width: 5, height: 6)) }
        case "peach", "plum":
            ctx.setFillColor(CGColor(srgbRed: 0.85, green: 0.35, blue: 0.25, alpha: 0.5))
            ctx.fillEllipse(in: CGRect(x: mid.x - sx * 0.42, y: mid.y - sy * 0.46, width: sx * 0.84, height: sy * 0.92))
            ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.25, blue: 0.14, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: mid.x - sx * 0.3, y: mid.y - sy * 0.34, width: sx * 0.6, height: sy * 0.68))
            ctx.setFillColor(CGColor(srgbRed: 0.68, green: 0.4, blue: 0.24, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: mid.x - sx * 0.22, y: mid.y - sy * 0.18, width: sx * 0.3, height: sy * 0.3))
        case "strawberry":
            ctx.setFillColor(c(a.skin, 1, 0.6))
            ctx.fillEllipse(in: CGRect(x: mid.x - sx * 0.7, y: mid.y - sy * 0.7, width: sx * 1.4, height: sy * 1.4))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.92, blue: 0.9, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: mid.x - sx * 0.45, y: mid.y - sy * 0.4, width: sx * 0.9, height: sy * 0.8))
        default: break
        }
        // Wet shine on the flesh.
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.35))
        ctx.fillEllipse(in: CGRect(x: flesh.minX + flesh.width * 0.18, y: flesh.midY + flesh.height * 0.12, width: flesh.width * 0.22, height: flesh.height * 0.18))
        ctx.restoreGState()
        ctx.addPath(faceShape)
        ctx.setStrokeColor(c(a.skinDark, 0.7, 0.8))
        ctx.setLineWidth(1.6)
        ctx.strokePath()
    }
}
