import AppKit
import CoreGraphics
import simd

/// Flaming rocks rain down at angles. Each one shows a shadow where it will land and gives you time to get out of the way
/// before it arrives; your silhouette must not touch it. Shields and stars fall too, and those you *do* want to touch.
///
/// Score is the seconds you survive plus bonuses for close calls and pick-ups. Three lives, and the rain gets heavier.
struct MeteorDodgeGame: Game {
    static let title = "Meteor Dodge"
    static let hint = "Dodge the meteors! Touch the shields and stars."
    static let accent = SIMD3<Double>(1.0, 0.6, 0.3)

    static let startingLives = 3
    /// Seconds nothing can hurt you after a hit.
    static let graceSeconds = 1.8
    static let shieldSeconds = 5.0
    /// How long the rain takes to reach full strength.
    static let rampSeconds = 100.0
    static let pickupRadius = 48.0
    /// How close (in pixels, beyond the rock's edge) your body must come to count as a near miss.
    static let nearMissReach = 60.0
    static let rockVariants = 6

    enum PickupKind: Equatable { case shield, star }

    struct Meteor {
        var target: SIMD2<Double>
        var start: SIMD2<Double>
        var radius: Double
        /// Seconds of warning, shadow only, before the rock appears.
        var telegraph: Double
        /// Seconds from appearing to landing.
        var flight: Double
        var rock: Int
        var spin: Double
        var age = 0.0
        var nearMiss = false

        var landsAt: Double { telegraph + flight }
        /// Whether it can hurt. Never during the warning, so a new rock can't hit you before you have seen it.
        var isLethal: Bool { age >= telegraph && age < landsAt }
        var progress: Double { bodyClamp((age - telegraph) / flight, 0, 1) }
        var position: SIMD2<Double> { position(at: age) }
        var heading: SIMD2<Double> { simd_normalize(target - start) }

        func position(at time: Double) -> SIMD2<Double> {
            start + (target - start) * bodyClamp((time - telegraph) / flight, 0, 1)
        }
    }

    struct Pickup {
        var kind: PickupKind
        var position: SIMD2<Double>
        var phase: Double
        var age = 0.0
    }

    struct Impact {
        var position: SIMD2<Double>
        var radius: Double
        var struck: Bool
        var age = 0.0
    }

    let size: CGSize
    private(set) var meteors: [Meteor] = []
    private(set) var pickups: [Pickup] = []
    private(set) var lives = MeteorDodgeGame.startingLives
    private(set) var bonus = 0
    private(set) var elapsed = 0.0
    private(set) var graceLeft = 0.0
    private(set) var shieldLeft = 0.0
    private(set) var nearMisses = 0
    private(set) var hits = 0
    private(set) var pickupsTaken = 0
    private(set) var meteorsLaunched = 0
    /// When (in game seconds) you were hit.
    private(set) var hitTimes: [Double] = []

    private var impacts: [Impact] = []
    private var sparks = ParticleSystem(capacity: 500)
    private var floaters: [BodyFloater] = []
    private var rng: SplitMix64
    private var flash = 0.0
    private var shake = 0.0
    private var spawning = true
    private var nextMeteor = 1.3
    private var nextPickup = 7.0
    private var scanClock = 0.0
    private var bodyBox: CGRect?
    private var bodyPoints: [CGPoint] = []
    /// Points round the edge of the person, for the shield's glow.
    private var bodyOutline: [CGPoint] = []
    private var head: CGRect?
    private var sinceHit = 99.0
    /// How much of the picture the person fills. A very big person can't dodge much, so the rain is aimed at them less.
    private var bodyFraction = 0.0

    var score: Int { Int(elapsed) + bonus }
    var isOver: Bool { lives <= 0 }
    var invulnerable: Bool { graceLeft > 0 || shieldLeft > 0 }
    var summary: String {
        shieldLeft > 0 ? "Lives \(lives) · Shield \(Int(shieldLeft.rounded(.up)))s" : "Lives \(lives)"
    }

    /// Hearts in the status plate, with the shield's seconds beside them while it is up.
    var readout: GameUIReadout {
        GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), label: shieldLeft > 0 ? "Shield \(Int(shieldLeft.rounded(.up)))s" : nil)
    }

    var result: GameUIResult {
        let line: String
        switch elapsed {
        case ..<20: line = "Watch the shadows: they show where rocks land"
        case ..<60: line = "Light on your feet!"
        default: line = "You out-ran a meteor shower"
        }
        return GameUIResult(headline: "Out of lives", line: line,
                            stats: [(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60), "survived"), ("\(nearMisses)", "close calls"), ("\(pickupsTaken)", "pick-ups")])
    }

    /// 0 at the start, 1 once the rain is at full strength.
    var difficulty: Double { min(1, elapsed / Self.rampSeconds) }
    /// The warning every meteor gets, now: it only shrinks as far as this.
    var currentTelegraph: Double { 1.35 - 0.55 * difficulty }
    var currentFlight: Double { 0.95 - 0.4 * difficulty }
    var maxActive: Int { 2 + Int(difficulty * 4) }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        sparks.gravity = SIMD2(0, -650)
        sparks.drag = 0.6
        BodyArtCache.warm("meteor") {
            for i in 0..<Self.rockVariants { _ = MeteorRockArt.sprite(i) }
            _ = MeteorPickupArt.sprite(.shield)
            _ = MeteorPickupArt.sprite(.star)
        }
    }

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = bodyClamp(dt, 0, 0.1)
        elapsed += dt
        flash = max(0, flash - dt)
        shake = max(0, shake - dt)
        sinceHit += dt
        graceLeft = max(0, graceLeft - dt)
        shieldLeft = max(0, shieldLeft - dt)
        look(at: world.matte, dt)

        if spawning {
            nextMeteor -= dt
            if nextMeteor <= 0 {
                if meteors.count < maxActive, spawnMeteor() {
                    nextMeteor = (1.5 - 1.05 * difficulty) * Double.random(in: 0.75...1.25, using: &rng)
                } else {
                    nextMeteor = 0.2
                }
            }
            nextPickup -= dt
            if nextPickup <= 0 {
                spawnPickup()
                nextPickup = Double.random(in: 10...16, using: &rng)
            }
        }

        advanceMeteors(dt, matte: world.matte)
        advancePickups(dt, matte: world.matte)
        sparks.step(dt)
        for i in impacts.indices { impacts[i].age += dt }
        impacts.removeAll { $0.age > 1.3 }
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll { $0.isDone }
    }

    // MARK: Watching the player

    /// Every so often, notes where the person is: the rain is aimed at them, and the shield is drawn around them.
    private mutating func look(at matte: MatteQuery?, _ dt: Double) {
        scanClock -= dt
        guard scanClock <= 0 else { return }
        scanClock = 0.12
        let scan = BodyScan(matte: matte, size: size, step: 24)
        bodyBox = scan.present ? scan.box : nil
        bodyPoints = scan.present ? scan.solidPoints(every: 2) : []
        bodyFraction = scan.fraction
        bodyOutline = scan.present ? Self.outline(of: scan) : []
        head = scan.headZone
    }

    // MARK: Meteors

    @discardableResult
    private mutating func spawnMeteor() -> Bool {
        let radius = Double.random(in: 34...50, using: &rng) + difficulty * 14
        for _ in 0..<8 {
            var target: SIMD2<Double>
            let aim = 0.55 * bodyClamp(1 - (bodyFraction - 0.25) / 0.35, 0.3, 1)
            if !bodyPoints.isEmpty, Double.random(in: 0..<1, using: &rng) < aim {
                // Aimed at you, so there is something to dodge. The warning still gives you time to leave.
                let p = bodyPoints[Int.random(in: 0..<bodyPoints.count, using: &rng)]
                target = SIMD2(Double(p.x) + Double.random(in: -50...50, using: &rng), Double(p.y) + Double.random(in: -50...50, using: &rng))
            } else {
                target = SIMD2(Double.random(in: 0..<size.width, using: &rng), Double.random(in: 0..<size.height, using: &rng))
            }
            target.x = bodyClamp(target.x, radius + 30, size.width - radius - 30)
            target.y = bodyClamp(target.y, radius + 60, size.height - radius - 130)
            // Keep the landing spots apart so there is always somewhere to stand.
            if meteors.contains(where: { simd_distance($0.target, target) < ($0.radius + radius) * 1.5 + 60 }) { continue }

            let lean = Double.random(in: -0.55...0.55, using: &rng)
            let way = SIMD2(sin(lean), -cos(lean))
            let reach = (size.height + 170 - target.y) / cos(lean)
            meteors.append(Meteor(target: target, start: target - way * reach, radius: radius,
                                  telegraph: currentTelegraph, flight: currentFlight,
                                  rock: Int.random(in: 0..<Self.rockVariants, using: &rng),
                                  spin: Double.random(in: -3...3, using: &rng)))
            meteorsLaunched += 1
            return true
        }
        return false
    }

    private mutating func advanceMeteors(_ dt: Double, matte: MatteQuery?) {
        var kept: [Meteor] = []
        for var meteor in meteors {
            let before = meteor.age
            meteor.age += dt
            var removed = false

            if meteor.age > meteor.telegraph, let matte {
                // Look along the stretch covered this frame, so a fast rock can't skip over you.
                let from = max(before, meteor.telegraph), to = min(meteor.age, meteor.landsAt)
                let travelled = simd_distance(meteor.position(at: from), meteor.position(at: to))
                let looks = max(1, Int((travelled / (meteor.radius * 0.6)).rounded(.up)))
                for i in 1...looks {
                    let at = meteor.position(at: from + (to - from) * Double(i) / Double(looks))
                    let probe = Self.probe(at: at, radius: meteor.radius, in: matte)
                    if probe.touching {
                        if shieldLeft > 0 {
                            deflect(meteor, at: at)
                            removed = true
                        } else if graceLeft <= 0 {
                            strike(meteor, at: at)
                            removed = true
                        }
                        // In the grace period the rock passes through harmlessly.
                    } else if probe.close, graceLeft <= 0 {
                        meteor.nearMiss = true
                    }
                    if removed { break }
                }
            }
            if removed { continue }
            if meteor.age >= meteor.landsAt {
                land(meteor)
                continue
            }
            kept.append(meteor)
        }
        meteors = kept
    }

    private mutating func land(_ meteor: Meteor) {
        impacts.append(Impact(position: meteor.target, radius: meteor.radius, struck: false))
        burst(at: meteor.target, count: 22, speed: 120...460, kind: 0)
        if meteor.nearMiss {
            nearMisses += 1
            bonus += 3
            floaters.append(BodyFloater.placed("CLOSE CALL +3", at: aside(meteor.target, by: meteor.radius + 40), size: size,
                                               color: BodyFloater.cool, fontSize: 40, avoiding: head))
        }
    }

    private mutating func strike(_ meteor: Meteor, at point: SIMD2<Double>) {
        lives = max(0, lives - 1)
        hits += 1
        hitTimes.append(elapsed)
        graceLeft = Self.graceSeconds
        flash = 0.6
        shake = 0.45
        sinceHit = 0
        impacts.append(Impact(position: point, radius: meteor.radius * 1.3, struck: true))
        burst(at: point, count: 44, speed: 160...620, kind: 1)
        floaters.append(BodyFloater.placed("OUCH!", at: aside(point, by: meteor.radius + 70), size: size, color: BodyFloater.bad, fontSize: 64, avoiding: head))
    }

    private mutating func deflect(_ meteor: Meteor, at point: SIMD2<Double>) {
        bonus += 2
        impacts.append(Impact(position: point, radius: meteor.radius, struck: false))
        burst(at: point, count: 26, speed: 140...480, kind: 3)
        floaters.append(BodyFloater.placed("+2", at: aside(point, by: meteor.radius + 30), size: size, color: BodyFloater.cool, avoiding: head))
    }

    private mutating func burst(at point: SIMD2<Double>, count: Int, speed: ClosedRange<Double>, kind: Int) {
        for _ in 0..<count {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng), v = Double.random(in: speed, using: &rng)
            sparks.emit(Particle(position: point, velocity: SIMD2(cos(angle), sin(angle) * 0.9 + 0.35) * v,
                                 life: Double.random(in: 0.4...1.0, using: &rng), size: Double.random(in: 3...8, using: &rng), kind: kind))
        }
    }

    // MARK: Pick-ups

    private mutating func spawnPickup() {
        let kind: PickupKind = Double.random(in: 0..<1, using: &rng) < 0.55 ? .shield : .star
        // Near where you are, so it is something you can reach.
        let around = bodyBox.map { Double($0.midX) } ?? size.width / 2
        let x = bodyClamp(around + Double.random(in: -280...280, using: &rng), 100, size.width - 100)
        pickups.append(Pickup(kind: kind, position: SIMD2(x, size.height + 60), phase: Double.random(in: 0..<6.28, using: &rng)))
    }

    private mutating func advancePickups(_ dt: Double, matte: MatteQuery?) {
        var kept: [Pickup] = []
        for var pickup in pickups {
            pickup.age += dt
            pickup.position.y -= 150 * dt
            pickup.position.x += sin(pickup.phase + pickup.age * 1.6) * 40 * dt
            if let matte, Self.probe(at: pickup.position, radius: Self.pickupRadius, in: matte).touching {
                collect(pickup)
            } else if pickup.position.y > -80 {
                kept.append(pickup)
            }
        }
        pickups = kept
    }

    private mutating func collect(_ pickup: Pickup) {
        pickupsTaken += 1
        switch pickup.kind {
        case .shield:
            shieldLeft = Self.shieldSeconds
            bonus += 3
            floaters.append(BodyFloater.placed("SHIELD!", at: aside(pickup.position, by: 90), size: size, color: BodyFloater.cool, fontSize: 56, avoiding: head))
            burst(at: pickup.position, count: 30, speed: 120...420, kind: 3)
        case .star:
            bonus += 10
            floaters.append(BodyFloater.placed("+10", at: aside(pickup.position, by: 70), size: size, fontSize: 64, avoiding: head))
            burst(at: pickup.position, count: 36, speed: 140...520, kind: 2)
        }
    }

    /// A spot for words about something at `p`: just above it. `placed(avoiding:)` then moves it off the player's head.
    private func aside(_ p: SIMD2<Double>, by reach: Double) -> SIMD2<Double> { p + SIMD2(0, reach * 0.7) }

    /// Sample points with an empty neighbour: the person's outline, coarse.
    private static func outline(of scan: BodyScan) -> [CGPoint] {
        var found: [CGPoint] = []
        for gy in 0..<scan.rows {
            for gx in 0..<scan.columns where scan.weight(gx, gy) > 0.5 {
                let open = gx == 0 || gx == scan.columns - 1 || gy == scan.rows - 1
                    || scan.weight(gx - 1, gy) <= 0.5 || scan.weight(gx + 1, gy) <= 0.5 || (gy > 0 && scan.weight(gx, gy - 1) <= 0.5)
                    || scan.weight(gx, gy + 1) <= 0.5
                // The bottom of the picture is where the person is cut off, not an edge of them.
                if open, gy > 0, !(gx == 0 || gx == scan.columns - 1) || gy > 1 { found.append(scan.center(gx, gy)) }
            }
        }
        return found
    }

    // MARK: Touching

    /// Samples around a circle. `touching` when the silhouette is inside it, `close` when the silhouette is just outside its edge.
    static func probe(at p: SIMD2<Double>, radius r: Double, in matte: MatteQuery) -> (touching: Bool, close: Bool) {
        func covered(_ x: Double, _ y: Double) -> Bool { matte.coverage(x: x, y: y) > 0.5 }
        var inside = covered(p.x, p.y) ? 1 : 0
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi
            if covered(p.x + cos(a) * r * 0.5, p.y + sin(a) * r * 0.5) { inside += 1 }
        }
        for i in 0..<10 {
            let a = (Double(i) + 0.5) / 10 * 2 * .pi
            if covered(p.x + cos(a) * r * 0.9, p.y + sin(a) * r * 0.9) { inside += 1 }
        }
        if inside >= 2 { return (true, false) }
        var close = false
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi
            if covered(p.x + cos(a) * (r + nearMissReach), p.y + sin(a) * (r + nearMissReach)) { close = true; break }
        }
        return (false, close)
    }

    // MARK: Test hooks

    /// Sends a meteor now, landing at `target`, instead of waiting for the next one.
    mutating func launch(at target: SIMD2<Double>, lean: Double = 0.25, radius: Double = 44, telegraph: Double = 1.0, flight: Double = 0.7) {
        let way = SIMD2(sin(lean), -cos(lean))
        let reach = (size.height + 170 - target.y) / cos(lean)
        meteors.append(Meteor(target: target, start: target - way * reach, radius: radius, telegraph: telegraph, flight: max(0.05, flight), rock: 0, spin: 1))
        meteorsLaunched += 1
    }

    /// Stops new meteors and pick-ups from starting, so a test can control exactly what is falling.
    mutating func holdSpawning() { spawning = false }

    /// Puts a pick-up somewhere now.
    mutating func drop(_ kind: PickupKind, at point: SIMD2<Double>) {
        pickups.append(Pickup(kind: kind, position: point, phase: 0))
    }

    /// Sets how long the game has been running, which sets how hard it is.
    mutating func fastForward(to seconds: Double) { elapsed = seconds }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        ctx.saveGState()
        let nudge = BodyGameHUD.shake(left: shake, total: 0.45, time: time)
        ctx.translateBy(x: nudge.width, y: nudge.height)
        for meteor in meteors { drawShadow(meteor, in: ctx, time: time) }
        for impact in impacts { drawImpact(impact, in: ctx) }
        drawProtection(in: ctx, time: time)
        for pickup in pickups { drawPickup(pickup, in: ctx, time: time) }
        for meteor in meteors where meteor.age >= meteor.telegraph { drawMeteor(meteor, in: ctx, time: time) }
        for p in sparks.particles { drawSpark(p, in: ctx) }
        ctx.restoreGState()
        for floater in floaters { floater.draw(in: ctx) }

        BodyGameHUD.flash(ctx, size: size, strength: flash / 0.6)
    }

    /// The warning: a shadow on the ground that darkens, ringed by a marker that closes in on it, and a dashed line from where it comes.
    private func drawShadow(_ meteor: Meteor, in ctx: CGContext, time: Double) {
        let c = CGPoint(x: meteor.target.x, y: meteor.target.y), r = meteor.radius
        let warning = bodyClamp(meteor.age / meteor.telegraph, 0, 1)
        let falling = meteor.age >= meteor.telegraph
        let pulse = 0.5 + 0.5 * sin(time * (6 + warning * 8))
        let appear = BodyEase.outBack(meteor.age / 0.3)

        // A hot glow on the ground, and a shadow that darkens as the rock gets nearer.
        BodyGlow.stamp(ctx, at: c, radius: r * 2.4, red: 1, green: 0.36, blue: 0.12, alpha: 0.22 + 0.3 * warning)
        ctx.fillCircle(center: c, radius: r * 1.05 * CGFloat(appear), color: CGColor(red: 0.08, green: 0.02, blue: 0.04, alpha: 0.18 + 0.34 * warning))

        if !falling {
            // Which way it is coming from.
            let back = meteor.heading * -1
            ctx.saveGState()
            ctx.setLineDash(phase: CGFloat(-time * 70), lengths: [12, 12])
            ctx.setLineWidth(4)
            ctx.setLineCap(.round)
            ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.tangerine, 0.65))
            ctx.move(to: CGPoint(x: c.x + back.x * r * 1.35, y: c.y + back.y * r * 1.35))
            ctx.addLine(to: CGPoint(x: c.x + back.x * (r * 1.35 + 200), y: c.y + back.y * (r * 1.35 + 200)))
            ctx.strokePath()
            ctx.restoreGState()
        }

        // The marker closing in, then the ring of the danger zone.
        let closing = r * (1.1 + 1.1 * (1 - BodyEase.inOutSine(warning))) * appear
        ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.tangerine, CGFloat(0.55 + 0.4 * pulse)))
        ctx.setLineWidth(5)
        ctx.strokeEllipse(in: CGRect(x: c.x - closing, y: c.y - closing, width: closing * 2, height: closing * 2))
        let edge = r * 1.1 * appear
        ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.cream, 0.9))
        ctx.setLineWidth(2.5)
        ctx.strokeEllipse(in: CGRect(x: c.x - edge, y: c.y - edge, width: edge * 2, height: edge * 2))
        // Four ticks pointing in, turning slowly.
        ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.gold, 0.95))
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        for i in 0..<4 {
            let a = Double(i) * .pi / 2 + .pi / 4 + time * 0.8
            ctx.move(to: CGPoint(x: c.x + cos(a) * r * 0.62 * appear, y: c.y + sin(a) * r * 0.62 * appear))
            ctx.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.88 * appear, y: c.y + sin(a) * r * 0.88 * appear))
        }
        ctx.strokePath()
    }

    private func drawMeteor(_ meteor: Meteor, in ctx: CGContext, time: Double) {
        let p = meteor.position, heading = meteor.heading, r = meteor.radius
        let tail = 300 + r * 2.5
        // The trail: glowing puffs, white-hot at the rock and dull red at the end, wavering a little.
        for k in 0..<24 {
            let t = Double(k) / 23
            let wobble = sin(time * 30 + Double(k) * 1.7) * r * 0.12 * t
            let at = CGPoint(x: p.x - heading.x * t * tail + heading.y * wobble, y: p.y - heading.y * t * tail - heading.x * wobble)
            let (red, green, blue): (Double, Double, Double) = t < 0.18 ? (1, 0.9, 0.62) : t < 0.5 ? (1, 0.56, 0.2) : (0.86, 0.26, 0.16)
            guard let dot = Sprites.dot(red: red, green: green, blue: blue) else { continue }
            ctx.stampDot(dot, at: at, radius: r * (1.45 - 1.05 * t), alpha: 0.9 * pow(1 - t, 1.3))
        }
        BodyGlow.stamp(ctx, at: CGPoint(x: p.x, y: p.y), radius: r * 2.6, red: 1, green: 0.52, blue: 0.18, alpha: 0.55)
        if let rock = MeteorRockArt.sprite(meteor.rock) {
            ctx.draw(rock, center: CGPoint(x: p.x, y: p.y), height: r * 2.7, rotation: CGFloat(meteor.spin * meteor.age))
        }
        let flicker = 0.5 + 0.5 * sin(time * 31 + Double(meteor.rock))
        BodyGlow.stamp(ctx, at: CGPoint(x: p.x + heading.x * r * 0.4, y: p.y + heading.y * r * 0.4), radius: r * 1.1,
                       red: 1, green: 0.95, blue: 0.75, alpha: 0.22 + 0.2 * flicker)
    }

    private func drawImpact(_ impact: Impact, in ctx: CGContext) {
        let c = CGPoint(x: impact.position.x, y: impact.position.y), r = impact.radius
        let wave = bodyClamp(impact.age / 0.5, 0, 1)
        let scorch = bodyClamp(1 - impact.age / 1.3, 0, 1)
        BodyGlow.stamp(ctx, at: c, radius: r * 2.2, red: 1, green: impact.struck ? 0.36 : 0.55, blue: impact.struck ? 0.3 : 0.18,
                       alpha: 0.65 * scorch * scorch)
        if !impact.struck { ctx.fillCircle(center: c, radius: r * 0.9, color: CGColor(red: 0.08, green: 0.03, blue: 0.04, alpha: 0.32 * scorch)) }
        let burst = bodyClamp(1 - impact.age / 0.22, 0, 1)
        if burst > 0 { BodyGlow.stamp(ctx, at: c, radius: r * (1.4 + 1.4 * (1 - burst)), red: 1, green: 0.95, blue: 0.8, alpha: 0.9 * burst) }
        if wave < 1 {
            let ring = r * (0.7 + 2.6 * BodyEase.outCubic(wave))
            ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.gold, CGFloat(1 - wave)))
            ctx.setLineWidth(CGFloat(12 * (1 - wave) + 2))
            ctx.strokeEllipse(in: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2))
        }
    }

    private func drawPickup(_ pickup: Pickup, in ctx: CGContext, time: Double) {
        let c = CGPoint(x: pickup.position.x, y: pickup.position.y)
        let bob = 1 + 0.06 * sin(time * 5 + pickup.phase)
        let grow = BodyEase.outBack(pickup.age / 0.4)
        let (red, green, blue) = BodyGamePalette.rgb(pickup.kind == .shield ? BodyGamePalette.sky : BodyGamePalette.gold)
        BodyGlow.stamp(ctx, at: c, radius: Self.pickupRadius * 2.2 * grow, red: red, green: green, blue: blue, alpha: 0.6)
        // A ring that breathes, so it reads as "touch me".
        let ring = Self.pickupRadius * (1.02 + 0.08 * sin(time * 4 + pickup.phase)) * grow
        ctx.setStrokeColor(CGColor(red: red, green: green, blue: blue, alpha: 0.85))
        ctx.setLineWidth(3)
        ctx.setLineDash(phase: CGFloat(time * 30), lengths: [10, 8])
        ctx.strokeEllipse(in: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2))
        ctx.setLineDash(phase: 0, lengths: [])
        if let sprite = MeteorPickupArt.sprite(pickup.kind) {
            ctx.draw(sprite, center: c, height: 84 * CGFloat(bob * grow), rotation: CGFloat(sin(time * 2.6 + pickup.phase) * 0.14))
        }
    }

    /// Glow round the person's outline while nothing can hurt them: cyan for a shield, a soft white pulse after a hit.
    private func drawProtection(in ctx: CGContext, time: Double) {
        guard invulnerable, !bodyOutline.isEmpty else { return }
        let shielded = shieldLeft > 0
        let ending = shielded ? bodyClamp(shieldLeft / 1.5, 0, 1) : bodyClamp(graceLeft / 0.5, 0, 1)
        let breathe = shielded ? 0.75 + 0.25 * sin(time * 5) : 0.4 + 0.3 * sin(time * 9)
        let alpha = breathe * (shielded ? 0.35 + 0.65 * ending : ending)
        let (red, green, blue) = shielded ? BodyGamePalette.rgb(BodyGamePalette.sky) : (1.0, 0.96, 0.9)
        guard let dot = Sprites.dot(red: red, green: green, blue: blue) else { return }
        for (i, p) in bodyOutline.enumerated() {
            let shimmer = 0.75 + 0.25 * sin(time * 6 + Double(i) * 0.9)
            ctx.stampDot(dot, at: p, radius: 30 * shimmer, alpha: 0.42 * alpha)
        }
        if shielded {
            // Sparks running round the edge.
            for k in 0..<6 {
                let index = (Int(time * 40) + k * bodyOutline.count / 6) % bodyOutline.count
                ctx.stampDot(dot, at: bodyOutline[index], radius: 16, alpha: 0.9 * alpha)
            }
        }
    }

    private func drawSpark(_ p: Particle, in ctx: CGContext) {
        let (r, g, b): (Double, Double, Double)
        switch p.kind {
        case 1: (r, g, b) = (1, 0.92 - 0.45 * p.progress, 0.7 - 0.45 * p.progress)
        case 2: (r, g, b) = BodyGamePalette.rgb(BodyGamePalette.gold)
        case 3: (r, g, b) = BodyGamePalette.rgb(BodyGamePalette.sky)
        default: (r, g, b) = (1, 0.68 - 0.35 * p.progress, 0.22)
        }
        let at = CGPoint(x: p.position.x, y: p.position.y)
        ctx.setAlpha(CGFloat(1 - p.progress))
        ctx.fillCircle(center: at, radius: p.size * (1 - 0.5 * p.progress), color: CGColor(red: r, green: g, blue: b, alpha: 1))
        ctx.setAlpha(1)
    }
}

/// The two things worth catching, drawn once: a blue heater shield with a silver rim, and a faceted gold star.
enum MeteorPickupArt {
    static func sprite(_ kind: MeteorDodgeGame.PickupKind) -> CGImage? {
        switch kind {
        case .shield: return BodyArtCache.image("meteor-pickup-shield", width: 160, height: 176) { drawShield($0) }
        case .star: return BodyArtCache.image("meteor-pickup-star", width: 176, height: 168) { drawStar($0) }
        }
    }

    private static func shieldPath(_ r: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - r.height * 0.2), control1: CGPoint(x: r.midX - r.width * 0.32, y: r.minY + r.height * 0.12),
                   control2: CGPoint(x: r.minX, y: r.minY + r.height * 0.42))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - r.height * 0.1))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.minX + r.width * 0.25, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.1), control: CGPoint(x: r.maxX - r.width * 0.25, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.2))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.maxX, y: r.minY + r.height * 0.42),
                   control2: CGPoint(x: r.midX + r.width * 0.32, y: r.minY + r.height * 0.12))
        p.closeSubpath()
        return p
    }

    private static func drawShield(_ ctx: CGContext) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let outer = shieldPath(CGRect(x: 16, y: 14, width: 128, height: 148))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 8, color: CGColor(red: 0, green: 0.05, blue: 0.15, alpha: 0.5))
        ctx.addPath(outer)
        ctx.setFillColor(CGColor(red: 0.62, green: 0.68, blue: 0.78, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        // The silver rim, lit from the top left.
        ctx.saveGState()
        ctx.addPath(outer)
        ctx.clip()
        let rim = [CGColor(red: 0.98, green: 0.99, blue: 1, alpha: 1), CGColor(red: 0.66, green: 0.72, blue: 0.82, alpha: 1),
                   CGColor(red: 0.36, green: 0.4, blue: 0.52, alpha: 1)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: rim, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 20, y: 160), end: CGPoint(x: 140, y: 20), options: [])
        }
        ctx.restoreGState()
        // The blue face.
        let face = shieldPath(CGRect(x: 28, y: 28, width: 104, height: 122))
        ctx.saveGState()
        ctx.addPath(face)
        ctx.clip()
        let blue = [CGColor(red: 0.55, green: 0.86, blue: 1, alpha: 1), CGColor(red: 0.18, green: 0.5, blue: 0.92, alpha: 1),
                    CGColor(red: 0.08, green: 0.2, blue: 0.5, alpha: 1)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: blue, locations: [0, 0.5, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: 56, y: 128), startRadius: 4, endCenter: CGPoint(x: 80, y: 88), endRadius: 92,
                                   options: [.drawsAfterEndLocation])
        }
        // A darker right half, as if the face were bent.
        ctx.setFillColor(CGColor(red: 0, green: 0.05, blue: 0.2, alpha: 0.18))
        ctx.fill(CGRect(x: 80, y: 0, width: 80, height: 176))
        ctx.restoreGState()
        // A silver star in the middle.
        let star = BodyShapes.star(center: CGPoint(x: 80, y: 92), radius: 30)
        ctx.addPath(star)
        ctx.setFillColor(CGColor(red: 0.95, green: 0.97, blue: 1, alpha: 1))
        ctx.fillPath()
        ctx.addPath(star)
        ctx.setStrokeColor(CGColor(red: 0.3, green: 0.4, blue: 0.6, alpha: 0.6))
        ctx.setLineWidth(2)
        ctx.strokePath()
        // A shine along the top left.
        ctx.saveGState()
        ctx.translateBy(x: 50, y: 128)
        ctx.rotate(by: 0.5)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
        ctx.fillEllipse(in: CGRect(x: -16, y: -6, width: 32, height: 12))
        ctx.restoreGState()
    }

    private static func drawStar(_ ctx: CGContext) {
        let c = CGPoint(x: 88, y: 82), R: CGFloat = 74
        let star = BodyShapes.star(center: c, radius: R)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 8, color: CGColor(red: 0.3, green: 0.15, blue: 0, alpha: 0.5))
        ctx.addPath(star)
        ctx.setFillColor(CGColor(red: 0.95, green: 0.62, blue: 0.1, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        // Facets: each point is split into a lit half and a shaded half, lit from the top left.
        for i in 0..<5 {
            let a = CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / 5
            let tip = CGPoint(x: c.x + cos(a) * R, y: c.y + sin(a) * R)
            for side in [-1.0, 1.0] {
                let b = a + CGFloat(side) * .pi / 5
                let valley = CGPoint(x: c.x + cos(b) * R * 0.45, y: c.y + sin(b) * R * 0.45)
                let mid = CGPoint(x: (tip.x + valley.x) / 2 - c.x, y: (tip.y + valley.y) / 2 - c.y)
                let light = max(0, (-mid.x * 0.7 + mid.y * 0.7) / R) // towards the top left is bright
                ctx.move(to: c)
                ctx.addLine(to: tip)
                ctx.addLine(to: valley)
                ctx.closePath()
                ctx.setFillColor(CGColor(red: 1, green: 0.72 + 0.24 * light, blue: 0.18 + 0.5 * light, alpha: 1))
                ctx.fillPath()
            }
        }
        ctx.addPath(star)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.97, blue: 0.82, alpha: 0.95))
        ctx.setLineWidth(4)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.glow(center: CGPoint(x: c.x - 18, y: c.y + 22), radius: 22, red: 1, green: 1, blue: 1, alpha: 0.7)
    }
}

/// Lumpy burning rocks, drawn once each and turned as they fall.
enum MeteorRockArt {
    static func sprite(_ variant: Int) -> CGImage? {
        let which = ((variant % MeteorDodgeGame.rockVariants) + MeteorDodgeGame.rockVariants) % MeteorDodgeGame.rockVariants
        return BodyArtCache.image("meteor-rock-\(which)", width: 192, height: 192) { draw($0, variant: which) }
    }

    private static func draw(_ ctx: CGContext, variant: Int) {
        var rng = SplitMix64(seed: UInt64(variant) &* 7919 &+ 17)
        let c = CGPoint(x: 96, y: 96)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!

        let count = 11
        var outline: [CGPoint] = []
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi, r = 70 * Double.random(in: 0.84...1.0, using: &rng)
            outline.append(CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
        }
        let path = CGMutablePath()
        path.addLines(between: outline)
        path.closeSubpath()

        ctx.glow(center: c, radius: 95, red: 1, green: 0.45, blue: 0.08, alpha: 0.5)

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let colors = [CGColor(red: 0.66, green: 0.32, blue: 0.13, alpha: 1), CGColor(red: 0.28, green: 0.14, blue: 0.09, alpha: 1),
                      CGColor(red: 0.08, green: 0.05, blue: 0.05, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: c.x + 16, y: c.y + 16), startRadius: 0, endCenter: c, endRadius: 82,
                                   options: [.drawsAfterEndLocation])
        }
        // Craters.
        for _ in 0..<3 {
            let at = CGPoint(x: c.x + Double.random(in: -36...36, using: &rng), y: c.y + Double.random(in: -36...36, using: &rng))
            let r = Double.random(in: 8...16, using: &rng)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
            ctx.fillEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2))
            ctx.setStrokeColor(CGColor(red: 1, green: 0.55, blue: 0.2, alpha: 0.4))
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: at.x - r, y: at.y - r - 1.5, width: r * 2, height: r * 2))
        }
        // Glowing cracks.
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for _ in 0..<5 {
            var at = CGPoint(x: c.x + Double.random(in: -18...18, using: &rng), y: c.y + Double.random(in: -18...18, using: &rng))
            var heading = Double.random(in: 0..<(2 * .pi), using: &rng)
            let crack = CGMutablePath()
            crack.move(to: at)
            for _ in 0..<4 {
                heading += Double.random(in: -0.7...0.7, using: &rng)
                at = CGPoint(x: at.x + cos(heading) * 22, y: at.y + sin(heading) * 22)
                crack.addLine(to: at)
            }
            ctx.addPath(crack)
            ctx.setStrokeColor(CGColor(red: 1, green: 0.4, blue: 0.08, alpha: 0.4))
            ctx.setLineWidth(8)
            ctx.strokePath()
            ctx.addPath(crack)
            ctx.setStrokeColor(CGColor(red: 1, green: 0.78, blue: 0.3, alpha: 1))
            ctx.setLineWidth(3)
            ctx.strokePath()
        }
        ctx.restoreGState()

        // The burning edge.
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.5, blue: 0.1, alpha: 0.95))
        ctx.setLineWidth(5)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.88, blue: 0.5, alpha: 0.6))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
    }
}
