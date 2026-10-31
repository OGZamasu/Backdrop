import AppKit
import CoreGraphics
import simd

/// Turns a pointing hand into a gun: where it aims, and when it fires.
enum FingerGun {
    /// Whether this hand is held like a gun: the index finger out and the other three curled. The thumb may be up or down.
    ///
    /// Pointed straight at the camera the finger is foreshortened to almost nothing and no longer looks "extended", so a finger that
    /// reaches clearly further than the curled ones also counts.
    static func isAimed(_ hand: HandState) -> Bool {
        let others: [Finger] = [.middle, .ring, .little]
        guard others.allSatisfy({ !hand.isExtended($0) }) else { return false }
        if hand.isExtended(.index) { return true }
        let curled = others.map { hand.reach(of: $0) }.max() ?? 1
        return hand.reach(of: .index) > curled + foreshortenedMargin
    }

    /// How much further than the curled fingers an index finger must reach to count as pointing when it is foreshortened.
    static let foreshortenedMargin = 0.2

    /// Where the gun points on the picture. Seen from the front a pointing finger is foreshortened, and people watch their own hand and
    /// line the fingertip up with what they want, so the aim is the fingertip. Held across the picture, it carries on a little way
    /// past the tip along the finger.
    static func crosshair(_ hand: HandState) -> SIMD2<Double> {
        let along = min(1, hand.aimLength / 0.6)
        let reach = hand.size * 1.1 * along
        return hand.indexTip.simd + SIMD2(Double(hand.aim.dx), Double(hand.aim.dy)) * reach
    }
}

/// Watches one hand for the moments it fires: the thumb dropping like a hammer, or a flick of the finger like recoil.
struct FingerGunTrigger {
    /// The thumb counts as "up" above this and "down" below the lower one, so a wobbling thumb doesn't fire by itself.
    static let thumbUp = 0.7, thumbDown = 0.35
    /// A hammer drop must follow the thumb being up this closely (seconds).
    static let hammerWindow = 0.45
    /// How fast the fingertip must move relative to the palm, in palm lengths a second, to count as a flick.
    static let flickSpeed = 5.0
    /// Seconds between shots.
    static let cooldown = 0.2

    private var thumbWasUp = false
    private var sinceThumbUp = 99.0
    private var cooling = 0.0

    /// Call every frame with the hand while it is aimed. True on the frame it fires.
    mutating func update(_ hand: HandState, dt: Double) -> Bool {
        cooling = max(0, cooling - dt)
        sinceThumbUp += dt
        var fire = false
        if hand.thumbOpen > Self.thumbUp {
            thumbWasUp = true
            sinceThumbUp = 0
        } else if hand.thumbOpen < Self.thumbDown, thumbWasUp {
            thumbWasUp = false
            fire = sinceThumbUp < Self.hammerWindow
        }
        // Recoil is the fingertip moving while the rest of the hand doesn't: the difference between the two speeds.
        let relative = hypot(Double(hand.tipVelocity.dx - hand.velocity.dx), Double(hand.tipVelocity.dy - hand.velocity.dy))
        if relative > Self.flickSpeed * hand.size { fire = true }
        guard fire, cooling == 0 else { return false }
        cooling = Self.cooldown
        return true
    }

    /// Fires on demand: a shot from holding the aim steady counts against the same cooldown.
    mutating func fireNow() -> Bool {
        guard cooling == 0 else { return false }
        cooling = Self.cooldown
        return true
    }
}

/// Targets glide across the picture like a fairground shooting gallery. Point at them like a gun and drop your thumb to shoot, or
/// just hold your aim on one to lock on.
///
/// Real tracking trembles and a finger pointed at the screen is foreshortened, so the sight is steadied with a one-euro filter, is
/// drawn gently toward a target it is nearly on, and keeps aiming for half a second if the hand briefly reads as a fist (which is how
/// Vision sees a finger pointed straight at the camera).
struct FingerGunsGame: HandGameScreens {
    static let title = "Finger Guns"
    static let hint = "Point at the targets. Drop your thumb to shoot, or hold your aim to lock on."
    static let presenceHint = "Hold up your hand like a gun"
    static let onboarding = ["Point at a target like a gun", "Drop your thumb to shoot", "Or hold your aim on one to lock on"]
    static let accent = SIMD3<Double>(1.0, 0.8, 0.3)
    static let icon = GameUIIcon.hand(.point)
    static let roundSeconds = 45.0
    /// How long the crosshair must sit on a target to shoot it by itself.
    static let lockSeconds = 0.75
    /// How far outside a target the sight still counts as on it, in pixels.
    static let slack = 20.0

    enum Kind: Equatable, CaseIterable {
        case board, duck, ufo, balloon, star, bunny

        var points: Int {
            switch self {
            case .board, .balloon: return 1
            case .duck: return 2
            case .ufo: return 3
            case .star: return 5
            case .bunny: return -3
            }
        }
        var radius: Double {
            switch self {
            case .board: return 46
            case .duck: return 42
            case .ufo: return 48
            case .balloon: return 42
            case .star: return 36
            case .bunny: return 46
            }
        }
    }

    struct Target {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var kind: Kind
        var phase: Double
        var age = 0.0
        var radius: Double { kind.radius }
    }

    struct Tracer { var from: SIMD2<Double>; var to: SIMD2<Double>; var age = 0.0; var hit: Bool }
    struct Floater { var text: String; var position: SIMD2<Double>; var age = 0.0; var good: Bool }
    struct Sight { var origin: SIMD2<Double>; var point: SIMD2<Double>; var lock: Double; var onTarget: Bool; var hand: Int }
    /// A target knocked off its rail, tumbling away.
    struct Tumble { var kind: Kind; var position: SIMD2<Double>; var velocity: SIMD2<Double>; var angle = 0.0; var spin: Double; var phase: Double; var age = 0.0 }
    /// The flash at a fingertip when it fires.
    struct Flash { var at: SIMD2<Double>; var angle: Double; var age = 0.0 }

    let size: CGSize
    private(set) var targets: [Target] = []
    private(set) var score = 0
    private(set) var timeLeft = FingerGunsGame.roundSeconds
    private(set) var elapsed = 0.0
    private(set) var hits = 0
    private(set) var shots = 0
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private var triggers: [Int: FingerGunTrigger] = [:]
    private var locks: [Int: Double] = [:]
    private var steady: [Int: HandSmoother.OneEuro] = [:]
    private var gestures = HandGestureRecognizer()
    private(set) var sights: [Sight] = []
    private var tracers: [Tracer] = []
    private var floaters: [Floater] = []
    private var tumbles: [Tumble] = []
    private var flashes: [Flash] = []
    private var sparks = ParticleSystem(capacity: 400)
    private var smoke = ParticleSystem(capacity: 80)
    private var rng: SplitMix64
    private var nextSpawn = 0.2

    var isOver: Bool { timeLeft <= 0 }
    var multiplier: Int { 1 + min(3, streak / 3) }
    var summary: String { (streak >= 3 ? "x\(multiplier) · " : "") + "\(Int(timeLeft.rounded(.up)))s" }

    var readout: GameUIReadout {
        GameUIReadout(score: score, time: (timeLeft, Self.roundSeconds), combo: multiplier > 1 ? multiplier : 0)
    }

    var result: GameUIResult {
        let accuracy = shots > 0 ? Int((Double(hits) / Double(shots) * 100).rounded()) : 0
        let line: String
        switch (hits, accuracy) {
        case (0, _): line = "Point, then drop your thumb to fire"
        case (_, 80...): line = "Dead eye! Hardly a shot wasted"
        case (25..., _): line = "Fastest finger in the west"
        default: line = "Nice shooting. Hold steady for more hits"
        }
        return GameUIResult(headline: "Time's up!", line: line,
                            stats: [("\(hits)", "hits"), ("\(accuracy)%", "accuracy"), (bestStreak > 0 ? "\(bestStreak)" : "-", "best streak")], kind: .timeUp)
    }

    static func warmUp(_ step: Int) -> Bool {
        let kinds = Kind.allCases
        if step < kinds.count { _ = FingerGunsArt.sprite(kinds[step], phase: 0); return true }
        let balloons = FingerGunsArt.balloonColors.count
        if step < kinds.count + balloons { _ = FingerGunsArt.sprite(.balloon, phase: Double(step - kinds.count) / 10 + 0.01); return true }
        if step == kinds.count + balloons { _ = FingerGunsArt.flashSprite(); return true }
        return false
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        sparks.gravity = SIMD2(0, -700)
        smoke.gravity = SIMD2(0, 50)
        smoke.drag = 1.5
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.25)
        elapsed += dt
        timeLeft = max(0, timeLeft - dt)

        nextSpawn -= dt
        if nextSpawn <= 0 && targets.count < 8 { spawn(); nextSpawn = max(0.35, 1.0 - elapsed * 0.012) * Double.random(in: 0.7...1.3, using: &rng) }

        for i in targets.indices {
            targets[i].age += dt
            targets[i].position += targets[i].velocity * dt
            switch targets[i].kind {
            case .ufo: targets[i].position.y += cos(targets[i].phase + targets[i].age * 2.4) * 70 * dt
            case .balloon: targets[i].position.y += sin(targets[i].phase + targets[i].age * 1.6) * 24 * dt
            case .bunny: targets[i].position.y += abs(sin(targets[i].age * 3.2)) * 90 * dt - 40 * dt
            default: break
            }
        }
        let margin = 140.0
        targets.removeAll { $0.position.x < -margin || $0.position.x > size.width + margin || $0.position.y < -margin || $0.position.y > size.height + margin }

        _ = gestures.update(world.hands, dt: dt)
        aim(world.hands, dt: dt)

        sparks.step(dt)
        smoke.step(dt)
        for i in tracers.indices { tracers[i].age += dt }
        tracers.removeAll { $0.age > 0.18 }
        for i in floaters.indices { floaters[i].age += dt; floaters[i].position.y += 60 * dt }
        floaters.removeAll { $0.age > 0.8 }
        for i in flashes.indices { flashes[i].age += dt }
        flashes.removeAll { $0.age > 0.1 }
        for i in tumbles.indices {
            tumbles[i].velocity.y -= 1400 * dt
            tumbles[i].position += tumbles[i].velocity * dt
            tumbles[i].angle += tumbles[i].spin * dt
            tumbles[i].age += dt
        }
        tumbles.removeAll { $0.age > 1.2 || $0.position.y < -120 }
    }

    private mutating func spawn() {
        let roll = Double.random(in: 0..<1, using: &rng)
        let kind: Kind
        if elapsed > 6 && roll < 0.1 { kind = .bunny } else if roll < 0.18 { kind = .star } else if roll < 0.36 { kind = .ufo }
        else if roll < 0.6 { kind = .duck } else if roll < 0.8 { kind = .balloon } else { kind = .board }
        let fromLeft = Bool.random(using: &rng)
        let speed: Double
        switch kind {
        case .duck: speed = Double.random(in: 230...340, using: &rng)
        case .star: speed = Double.random(in: 330...460, using: &rng)
        case .ufo: speed = Double.random(in: 150...230, using: &rng)
        case .bunny: speed = Double.random(in: 110...170, using: &rng)
        default: speed = Double.random(in: 120...210, using: &rng)
        }
        let y = Double.random(in: size.height * 0.22...size.height * 0.86, using: &rng)
        targets.append(Target(position: SIMD2(fromLeft ? -kind.radius * 1.5 : size.width + kind.radius * 1.5, kind == .bunny ? size.height * 0.2 : y),
                              velocity: SIMD2(fromLeft ? speed : -speed, 0), kind: kind, phase: Double.random(in: 0..<6.28, using: &rng)))
    }

    /// Whether a hand is aiming: held like a gun now, or a moment ago and now perhaps pointing down the lens.
    private func isAiming(_ hand: HandState) -> Bool {
        if FingerGun.isAimed(hand) { return true }
        let pose = gestures.pose(of: hand.id)
        return pose.isPointing && hand.gesturePose == .fist
    }

    private mutating func aim(_ hands: [HandState], dt: Double) {
        sights = []
        var live = Set<Int>()
        for hand in hands where isAiming(hand) {
            live.insert(hand.id)
            let raw = FingerGun.crosshair(hand)
            var filter = steady[hand.id] ?? HandSmoother.OneEuro(minCutoff: 1.3, beta: 1.2)
            var point = filter.filter(raw, dt: max(dt, 1e-3), scale: hand.size)
            steady[hand.id] = filter
            point = assisted(point)
            let under = nearestTarget(to: point)

            var trigger = triggers[hand.id] ?? FingerGunTrigger()
            var fired = trigger.update(hand, dt: dt)

            // Holding steady on a target (never on a decoy) shoots it.
            var lock = locks[hand.id] ?? 0
            if let u = under, targets[u].kind != .bunny { lock += dt } else { lock = max(0, lock - dt * 2) }
            if lock >= Self.lockSeconds {
                lock = 0
                if !fired { fired = trigger.fireNow() }
            }
            locks[hand.id] = lock
            triggers[hand.id] = trigger

            sights.append(Sight(origin: SIMD2(Double(hand.indexTip.x), Double(hand.indexTip.y)), point: point, lock: lock / Self.lockSeconds,
                                onTarget: under != nil, hand: hand.id))
            if fired { fire(from: SIMD2(Double(hand.indexTip.x), Double(hand.indexTip.y)), at: point) }
        }
        // A hand that isn't aimed or isn't there stops charging.
        for id in Array(locks.keys) where !live.contains(id) { locks[id] = nil; triggers[id] = nil }
        for id in Array(steady.keys) where !hands.contains(where: { $0.id == id }) { steady[id] = nil }
    }

    /// Aim assist: a sight close to a target is drawn a little way toward its middle, more the closer it is.
    private func assisted(_ point: SIMD2<Double>) -> SIMD2<Double> {
        guard let i = nearestTarget(to: point, slack: 46) else { return point }
        let t = targets[i]
        let d = simd_distance(point, t.position)
        let pull = 0.35 * max(0, 1 - d / (t.radius + 46))
        return point + (t.position - point) * pull
    }

    /// The target the crosshair is on, or nearest to it within a little slack.
    private func nearestTarget(to point: SIMD2<Double>, slack: Double = FingerGunsGame.slack) -> Int? {
        var best: (index: Int, distance: Double)?
        for (i, t) in targets.enumerated() {
            let d = simd_distance(t.position, point)
            if d <= t.radius + slack, d < (best?.distance ?? .infinity) { best = (i, d) }
        }
        return best?.index
    }

    /// One shot from the fingertip to the crosshair.
    mutating func fire(from origin: SIMD2<Double>, at point: SIMD2<Double>) {
        shots += 1
        flashes.append(Flash(at: origin, angle: Double.random(in: 0..<(2 * .pi), using: &rng)))
        for _ in 0..<5 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            smoke.emit(Particle(position: origin, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 20...70, using: &rng),
                                life: Double.random(in: 0.4...0.7, using: &rng), size: Double.random(in: 8...16, using: &rng)))
        }
        guard let index = nearestTarget(to: point) else {
            streak = 0
            tracers.append(Tracer(from: origin, to: point, hit: false))
            puff(at: point, count: 6, warm: false)
            return
        }
        let target = targets.remove(at: index)
        tracers.append(Tracer(from: origin, to: target.position, hit: true))
        // Knocked off the rail: it flips and tumbles away (a balloon just pops).
        if target.kind != .balloon {
            let away = point.x < target.position.x ? 1.0 : -1.0
            tumbles.append(Tumble(kind: target.kind, position: target.position, velocity: SIMD2(away * Double.random(in: 120...260, using: &rng), Double.random(in: 280...420, using: &rng)),
                                  spin: away * Double.random(in: -9 ... -5, using: &rng), phase: target.phase))
        }
        if target.kind == .bunny {
            streak = 0
            score = max(0, score + target.kind.points)
            floaters.append(Floater(text: "\(target.kind.points)", position: target.position, good: false))
            puff(at: target.position, count: 16, warm: false)
        } else {
            hits += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            let earned = target.kind.points * multiplier
            score += earned
            floaters.append(Floater(text: "+\(earned)", position: target.position, good: true))
            puff(at: target.position, count: target.kind == .star ? 30 : target.kind == .balloon ? 22 : 16, warm: true, balloon: target.kind == .balloon ? target.phase : nil)
        }
    }

    private mutating func puff(at p: SIMD2<Double>, count: Int, warm: Bool, balloon: Double? = nil) {
        for _ in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 90...420, using: &rng)
            sparks.emit(Particle(position: p, velocity: SIMD2(cos(a), sin(a)) * s, life: Double.random(in: 0.3...0.7, using: &rng),
                                 size: Double.random(in: 3...8, using: &rng), hue: balloon ?? (warm ? -1 : -2), kind: balloon == nil ? 0 : 1))
        }
    }

    // MARK: Test hooks

    /// Replaces the targets with one of each of `kinds`, standing still at `point`.
    mutating func setTargets(_ kinds: [Kind], at point: CGPoint) {
        targets = kinds.map { Target(position: SIMD2(Double(point.x), Double(point.y)), velocity: .zero, kind: $0, phase: 0) }
        nextSpawn = 1000
    }

    /// Replaces the targets with the given ones, each standing still where it is told.
    mutating func setTargets(_ placed: [(Kind, CGPoint)]) {
        targets = placed.map { Target(position: SIMD2(Double($0.1.x), Double($0.1.y)), velocity: .zero, kind: $0.0, phase: 0) }
        nextSpawn = 1000
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        for t in targets { Self.drawTarget(t, in: ctx, time: time) }
        for t in tumbles {
            let fade = CGFloat(max(0, 1 - max(0, t.age - 0.5) / 0.7))
            Self.drawTarget(Target(position: t.position, velocity: .zero, kind: t.kind, phase: t.phase, age: 0), in: ctx, time: time,
                            angle: t.angle, alpha: fade, flipped: t.age * 7)
        }
        for p in smoke.particles {
            HandGameArt.halo(ctx, at: CGPoint(x: p.position.x, y: p.position.y), radius: CGFloat(p.size * (1 + p.progress)), red: 0.85, green: 0.84, blue: 0.82,
                             alpha: 0.3 * (1 - p.progress))
        }
        drawTracers(ctx)
        for p in sparks.particles {
            let at = CGPoint(x: p.position.x, y: p.position.y)
            if p.kind == 1 {
                // Balloon rubber.
                let c = FingerGunsArt.balloonColor(p.hue)
                ctx.setFillColor(CGColor(srgbRed: c.x, green: c.y, blue: c.z, alpha: 1 - p.progress))
                ctx.saveGState()
                ctx.translateBy(x: at.x, y: at.y)
                ctx.rotate(by: CGFloat(p.age * 9 + p.size))
                ctx.fill(CGRect(x: -p.size, y: -p.size * 0.4, width: p.size * 2, height: p.size * 0.8))
                ctx.restoreGState()
            } else {
                let warm = p.hue == -1
                HandGameArt.halo(ctx, at: at, radius: CGFloat(p.size * 2.2), red: 1, green: warm ? 0.82 : 0.9, blue: warm ? 0.4 : 0.9, alpha: 1 - p.progress)
            }
        }
        for f in flashes { FingerGunsArt.muzzleFlash(ctx, at: CGPoint(x: f.at.x, y: f.at.y), angle: f.angle, age: f.age) }
        for s in sights { Self.drawSight(s, in: ctx, time: time) }
        for f in floaters {
            let pop = HandGameEase.outBack(f.age / 0.2)
            HandGameType.draw(ctx, f.text, at: CGPoint(x: f.position.x, y: f.position.y + 30), size: 34,
                              color: HandGamePalette.color(f.good ? HandGamePalette.gold : HandGamePalette.coral),
                              alpha: CGFloat(min(1, (0.8 - f.age) / 0.25)), scale: CGFloat(pop))
        }
    }

    private func drawTracers(_ ctx: CGContext) {
        for tr in tracers {
            let t = tr.age / 0.18
            let fade = CGFloat(1 - t)
            // A bright streak that races from the gun to the target and is gone.
            let head = min(1, t * 3)
            let from = CGPoint(x: tr.from.x + (tr.to.x - tr.from.x) * max(0, head - 0.5), y: tr.from.y + (tr.to.y - tr.from.y) * max(0, head - 0.5))
            let to = CGPoint(x: tr.from.x + (tr.to.x - tr.from.x) * head, y: tr.from.y + (tr.to.y - tr.from.y) * head)
            ctx.setLineCap(.round)
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.78, blue: 0.4, alpha: 0.45 * fade))
            ctx.setLineWidth(8 * fade)
            ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.98, blue: 0.9, alpha: fade))
            ctx.setLineWidth(2.5)
            ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
            if tr.hit || t > 0.3 {
                // The ring where it landed.
                let r = CGFloat(10 + 40 * HandGameEase.outCubic(t))
                ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.95, blue: 0.8, alpha: 0.8 * fade))
                ctx.setLineWidth(3 * fade + 1)
                ctx.strokeEllipse(in: CGRect(x: tr.to.x - r, y: tr.to.y - r, width: r * 2, height: r * 2))
            }
        }
    }

    static func drawTarget(_ t: Target, in ctx: CGContext, time: Double, angle: Double = 0, alpha: CGFloat = 1, flipped: Double = 0) {
        let c = CGPoint(x: t.position.x, y: t.position.y)
        if t.kind == .star { HandGameArt.halo(ctx, at: c, radius: CGFloat(t.radius * 2.1), red: 1, green: 0.82, blue: 0.3, alpha: Double(alpha) * (0.45 + 0.15 * sin(time * 5))) }
        if t.kind == .bunny { HandGameArt.halo(ctx, at: c, radius: CGFloat(t.radius * 1.9), red: 1, green: 0.55, blue: 0.75, alpha: Double(alpha) * 0.35) }
        if t.kind == .balloon { FingerGunsArt.string(ctx, from: CGPoint(x: c.x, y: c.y - CGFloat(t.radius) * 1.05), time: time + t.phase, alpha: alpha) }
        guard let sprite = FingerGunsArt.sprite(t.kind, phase: t.phase) else { return }
        // Things bob and sway on their rail; a duck faces the way it is going.
        let sway = sin(t.phase + t.age * 3) * (t.kind == .balloon ? 0.12 : t.kind == .star ? 0.25 : 0.05)
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(sway + angle))
        if t.kind == .duck && t.velocity.x < 0 { ctx.scaleBy(x: -1, y: 1) }
        // Knocked targets flip over edge on, like a tin target on a pivot.
        if flipped > 0 { ctx.scaleBy(x: 1, y: CGFloat(cos(min(flipped, .pi)))) }
        ctx.draw(sprite, center: .zero, height: CGFloat(t.radius * 2.5), alpha: alpha)
        ctx.restoreGState()
        if t.kind == .ufo {
            // Running lights round the rim.
            for k in 0..<5 {
                let on = (Int(time * 6) + k) % 5 == 0
                let x = c.x + CGFloat(Double(k - 2) * t.radius * 0.36), y = c.y - CGFloat(t.radius * 0.18)
                HandGameArt.halo(ctx, at: CGPoint(x: x, y: y), radius: on ? 9 : 5, red: 1, green: on ? 0.95 : 0.6, blue: on ? 0.5 : 0.35, alpha: Double(alpha) * (on ? 1 : 0.6))
            }
        }
    }

    static func drawSight(_ s: Sight, in ctx: CGContext, time: Double) {
        let p = CGPoint(x: s.point.x, y: s.point.y), o = CGPoint(x: s.origin.x, y: s.origin.y)
        // A faint line of aim from the fingertip.
        ctx.setLineCap(.round)
        ctx.setStrokeColor(HandGamePalette.color(s.onTarget ? HandGamePalette.coral : HandGamePalette.cream, 0.28))
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: CGFloat(-time * 60), lengths: [6, 10])
        ctx.move(to: o); ctx.addLine(to: p); ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        FingerGunsArt.reticle(ctx, at: p, onTarget: s.onTarget, lock: s.lock, time: time)
    }
}

// MARK: - The gallery

/// The look of the shooting gallery: tin targets with rims and rivets, a glossy balloon, a saucer with a pilot, a decoy bunny, the
/// sight, and the flash at the muzzle. Lit from the top left like everything else in the hand games.
enum FingerGunsArt {
    static let balloonColors: [SIMD3<Double>] = [HandGamePalette.coral, HandGamePalette.sky, HandGamePalette.mint, SIMD3(0.98, 0.72, 0.3), SIMD3(0.72, 0.5, 0.95)]

    static func balloonColor(_ phase: Double) -> SIMD3<Double> {
        balloonColors[Int(abs(phase) * 10) % balloonColors.count]
    }

    static func sprite(_ kind: FingerGunsGame.Kind, phase: Double) -> CGImage? {
        let box = CGSize(width: 120, height: 120)
        switch kind {
        case .board: return HandGameSprites.image("guns.board", size: box) { board($0) }
        case .duck: return HandGameSprites.image("guns.duck", size: box) { duck($0) }
        case .ufo: return HandGameSprites.image("guns.ufo", size: box) { ufo($0) }
        case .star: return HandGameSprites.image("guns.star", size: box) { ctx in
            guard let star = HandGamePieces.star() else { return }
            ctx.draw(star, in: CGRect(x: -50, y: -50, width: 100, height: 100))
        }
        case .bunny: return HandGameSprites.image("guns.bunny", size: box) { bunny($0) }
        case .balloon:
            let i = Int(abs(phase) * 10) % balloonColors.count
            return HandGameSprites.image("guns.balloon.\(i)", size: box) { balloon($0, balloonColors[i]) }
        }
    }

    private static func ink(_ a: Double = 1) -> CGColor { HandGamePalette.color(HandGamePalette.ink, a) }

    private static func shadowed(_ ctx: CGContext, _ body: () -> Void) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 2, height: -4), blur: 6, color: ink(0.45))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// A round tin bullseye with a bevelled rim.
    private static func board(_ ctx: CGContext) {
        shadowed(ctx) {
            let rings: [(CGFloat, SIMD3<Double>)] = [(44, SIMD3(0.92, 0.9, 0.86)), (38, HandGamePalette.coral), (29, SIMD3(0.98, 0.96, 0.9)),
                                                     (20, HandGamePalette.coral), (11, SIMD3(0.98, 0.96, 0.9)), (5, HandGamePalette.coral)]
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: -47, y: -47, width: 94, height: 94))
            ctx.clip()
            HandGameSprites.radial(ctx, [CGColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1), CGColor(srgbRed: 0.55, green: 0.55, blue: 0.62, alpha: 1)],
                                   center: .zero, radius: 47, focus: CGPoint(x: -16, y: 16))
            ctx.restoreGState()
            for (r, c) in rings {
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
                ctx.clip()
                HandGameSprites.linear(ctx, [HandGameSprites.shade(c, 1.12), HandGameSprites.shade(c, 0.82)], from: CGPoint(x: -r, y: r), to: CGPoint(x: r, y: -r))
                ctx.restoreGState()
            }
            ctx.setStrokeColor(ink(0.5))
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: -47, y: -47, width: 94, height: 94))
            // Rivets and a shine.
            for k in 0..<4 {
                let a = CGFloat(k) * .pi / 2 + .pi / 4
                ctx.setFillColor(CGColor(srgbRed: 0.7, green: 0.7, blue: 0.76, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: cos(a) * 41 - 2.5, y: sin(a) * 41 - 2.5, width: 5, height: 5))
            }
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.35))
            ctx.fillEllipse(in: CGRect(x: -30, y: 12, width: 24, height: 14))
        }
    }

    /// A tin duck, side on, facing left.
    private static func duck(_ ctx: CGContext) {
        shadowed(ctx) {
            let yellow = SIMD3<Double>(1.0, 0.82, 0.25)
            let body = CGMutablePath()
            body.move(to: CGPoint(x: -24, y: -6))
            body.addCurve(to: CGPoint(x: 44, y: 4), control1: CGPoint(x: -18, y: -36), control2: CGPoint(x: 30, y: -34))
            body.addCurve(to: CGPoint(x: 48, y: 22), control1: CGPoint(x: 50, y: 10), control2: CGPoint(x: 54, y: 20))
            body.addCurve(to: CGPoint(x: 6, y: 6), control1: CGPoint(x: 34, y: 16), control2: CGPoint(x: 20, y: 6))
            body.addLine(to: CGPoint(x: -14, y: 10))
            body.closeSubpath()
            let head = CGRect(x: -38, y: 2, width: 36, height: 34)
            for (path, light) in [(CGPath(ellipseIn: head, transform: nil), 1.05), (body as CGPath, 1.0)] {
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                HandGameSprites.linear(ctx, [HandGameSprites.shade(yellow, 1.18 * light), HandGameSprites.shade(yellow, 0.78)], from: CGPoint(x: -30, y: 34), to: CGPoint(x: 30, y: -30))
                ctx.restoreGState()
                ctx.addPath(path)
                ctx.setStrokeColor(HandGameSprites.shade(yellow, 0.5))
                ctx.setLineWidth(2)
                ctx.strokePath()
            }
            // Wing.
            let wing = CGMutablePath()
            wing.move(to: CGPoint(x: 4, y: -2))
            wing.addCurve(to: CGPoint(x: 36, y: 2), control1: CGPoint(x: 10, y: -22), control2: CGPoint(x: 30, y: -18))
            wing.addCurve(to: CGPoint(x: 4, y: -2), control1: CGPoint(x: 26, y: 6), control2: CGPoint(x: 12, y: 4))
            ctx.addPath(wing)
            ctx.setFillColor(HandGameSprites.shade(yellow, 0.82))
            ctx.fillPath()
            // Beak and eye.
            let beak = CGMutablePath()
            beak.move(to: CGPoint(x: -36, y: 20)); beak.addLine(to: CGPoint(x: -54, y: 15)); beak.addLine(to: CGPoint(x: -36, y: 10)); beak.closeSubpath()
            ctx.addPath(beak)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.5, blue: 0.2, alpha: 1))
            ctx.fillPath()
            ctx.setFillColor(ink())
            ctx.fillEllipse(in: CGRect(x: -26, y: 20, width: 7, height: 8))
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
            ctx.fillEllipse(in: CGRect(x: -25, y: 24, width: 2.5, height: 2.5))
            // The stick it rides on.
            ctx.setFillColor(CGColor(srgbRed: 0.55, green: 0.38, blue: 0.24, alpha: 1))
            ctx.fill(CGRect(x: 6, y: -44, width: 6, height: 26))
        }
    }

    /// A silver saucer with a glass dome and a little green pilot.
    private static func ufo(_ ctx: CGContext) {
        shadowed(ctx) {
            let dome = CGRect(x: -22, y: -2, width: 44, height: 40)
            ctx.saveGState()
            ctx.addEllipse(in: dome)
            ctx.clip()
            HandGameSprites.radial(ctx, [CGColor(srgbRed: 0.7, green: 0.95, blue: 1, alpha: 0.95), CGColor(srgbRed: 0.25, green: 0.6, blue: 0.85, alpha: 0.95)],
                                   center: CGPoint(x: 0, y: 14), radius: 26, focus: CGPoint(x: -8, y: 26))
            // The pilot.
            ctx.setFillColor(CGColor(srgbRed: 0.45, green: 0.85, blue: 0.4, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: -10, y: 4, width: 20, height: 22))
            ctx.setFillColor(ink())
            ctx.fillEllipse(in: CGRect(x: -7, y: 13, width: 5, height: 7))
            ctx.fillEllipse(in: CGRect(x: 2, y: 13, width: 5, height: 7))
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.55))
            ctx.fillEllipse(in: CGRect(x: -14, y: 22, width: 10, height: 7))
            ctx.restoreGState()
            let saucer = CGRect(x: -54, y: -18, width: 108, height: 32)
            ctx.saveGState()
            ctx.addEllipse(in: saucer)
            ctx.clip()
            HandGameSprites.linear(ctx, [CGColor(srgbRed: 0.95, green: 0.96, blue: 1, alpha: 1), CGColor(srgbRed: 0.6, green: 0.62, blue: 0.72, alpha: 1),
                                         CGColor(srgbRed: 0.36, green: 0.36, blue: 0.46, alpha: 1)], locations: [0, 0.55, 1],
                                   from: CGPoint(x: 0, y: 14), to: CGPoint(x: 0, y: -18))
            ctx.restoreGState()
            ctx.setStrokeColor(ink(0.55))
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: saucer)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.6))
            ctx.setLineWidth(1.5)
            ctx.addArc(center: CGPoint(x: 0, y: -2), radius: 50, startAngle: 2.6, endAngle: 2.0, clockwise: true)
            ctx.strokePath()
        }
    }

    /// A glossy balloon with a knot.
    private static func balloon(_ ctx: CGContext, _ color: SIMD3<Double>) {
        shadowed(ctx) {
            let shape = CGMutablePath()
            shape.move(to: CGPoint(x: 0, y: -44))
            shape.addCurve(to: CGPoint(x: 0, y: 50), control1: CGPoint(x: 52, y: -26), control2: CGPoint(x: 46, y: 50))
            shape.addCurve(to: CGPoint(x: 0, y: -44), control1: CGPoint(x: -46, y: 50), control2: CGPoint(x: -52, y: -26))
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            HandGameSprites.radial(ctx, [HandGameSprites.shade(color, 1.3), HandGameSprites.shade(color, 1.0), HandGameSprites.shade(color, 0.62)], locations: [0, 0.4, 1],
                                   center: CGPoint(x: 4, y: 0), radius: 56, focus: CGPoint(x: -14, y: 22))
            ctx.restoreGState()
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.7))
            ctx.fillEllipse(in: CGRect(x: -24, y: 18, width: 12, height: 18))
            let knot = CGMutablePath()
            knot.move(to: CGPoint(x: -6, y: -50)); knot.addLine(to: CGPoint(x: 6, y: -50)); knot.addLine(to: CGPoint(x: 0, y: -42)); knot.closeSubpath()
            ctx.addPath(knot)
            ctx.setFillColor(HandGameSprites.shade(color, 0.7))
            ctx.fillPath()
        }
    }

    /// The decoy: a white bunny that must not be shot.
    private static func bunny(_ ctx: CGContext) {
        shadowed(ctx) {
            let fur = SIMD3<Double>(0.98, 0.96, 0.97), pink = SIMD3<Double>(1, 0.68, 0.78)
            for side in [-1.0, 1.0] {
                let ear = CGRect(x: CGFloat(side) * 17 - 9, y: 6, width: 18, height: 50)
                ctx.saveGState()
                ctx.translateBy(x: ear.midX, y: ear.minY)
                ctx.rotate(by: CGFloat(-side * 0.18))
                ctx.translateBy(x: -ear.midX, y: -ear.minY)
                ctx.addEllipse(in: ear)
                ctx.setFillColor(HandGameSprites.shade(fur, 0.97))
                ctx.fillPath()
                ctx.setStrokeColor(HandGameSprites.shade(pink, 0.7))
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: ear)
                ctx.setFillColor(HandGameSprites.shade(pink, 1))
                ctx.fillEllipse(in: ear.insetBy(dx: 5, dy: 8))
                ctx.restoreGState()
            }
            let head = CGRect(x: -34, y: -36, width: 68, height: 60)
            ctx.saveGState()
            ctx.addEllipse(in: head)
            ctx.clip()
            HandGameSprites.radial(ctx, [HandGameSprites.shade(fur, 1.0), HandGameSprites.shade(fur, 0.88)], center: CGPoint(x: 0, y: -6), radius: 38, focus: CGPoint(x: -10, y: 8))
            ctx.restoreGState()
            ctx.setStrokeColor(HandGameSprites.shade(pink, 0.6))
            ctx.setLineWidth(1.6)
            ctx.strokeEllipse(in: head)
            for side in [-1.0, 1.0] {
                ctx.setFillColor(ink())
                ctx.fillEllipse(in: CGRect(x: CGFloat(side) * 13 - 4.5, y: -4, width: 9, height: 11))
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
                ctx.fillEllipse(in: CGRect(x: CGFloat(side) * 13 - 2, y: 2, width: 3.5, height: 3.5))
                ctx.setFillColor(HandGameSprites.shade(pink, 1, alpha: 0.55))
                ctx.fillEllipse(in: CGRect(x: CGFloat(side) * 22 - 6, y: -18, width: 12, height: 7))
            }
            ctx.setFillColor(HandGameSprites.shade(pink, 0.9))
            ctx.fillEllipse(in: CGRect(x: -5, y: -15, width: 10, height: 7))
            ctx.setStrokeColor(ink(0.6))
            ctx.setLineWidth(1.4)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 0, y: -15)); ctx.addLine(to: CGPoint(x: 0, y: -20))
            ctx.addArc(center: CGPoint(x: -4, y: -20), radius: 4, startAngle: 0, endAngle: -.pi * 0.8, clockwise: true)
            ctx.move(to: CGPoint(x: 0, y: -20))
            ctx.addArc(center: CGPoint(x: 4, y: -20), radius: 4, startAngle: .pi, endAngle: .pi * 1.8, clockwise: false)
            ctx.strokePath()
        }
    }

    /// A balloon's string, swaying.
    static func string(_ ctx: CGContext, from p: CGPoint, time: Double, alpha: CGFloat) {
        ctx.setStrokeColor(CGColor(gray: 0.95, alpha: 0.75 * alpha))
        ctx.setLineWidth(1.5)
        ctx.move(to: p)
        ctx.addCurve(to: CGPoint(x: p.x + CGFloat(sin(time * 2) * 8), y: p.y - 70),
                     control1: CGPoint(x: p.x + CGFloat(sin(time * 2 + 1) * 12), y: p.y - 25),
                     control2: CGPoint(x: p.x - CGFloat(sin(time * 2 + 2) * 12), y: p.y - 50))
        ctx.strokePath()
    }

    /// The sight: a ring broken into four with a centre dot and a turning outer bezel. It tightens and turns coral on a target, and a
    /// gold arc fills as the lock-on charges.
    static func reticle(_ ctx: CGContext, at p: CGPoint, onTarget: Bool, lock: Double, time: Double) {
        let color = HandGamePalette.color(onTarget ? HandGamePalette.coral : HandGamePalette.cream)
        let tight: CGFloat = onTarget ? 0.82 : 1
        let r: CGFloat = 26 * tight
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.setLineCap(.round)
        for (width, stroke) in [(CGFloat(7), ink(0.55)), (3, color)] {
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(width)
            for k in 0..<4 {
                let a = CGFloat(k) * .pi / 2 + .pi / 4
                ctx.addArc(center: .zero, radius: r, startAngle: a - 0.55, endAngle: a + 0.55, clockwise: false)
                ctx.strokePath()
            }
            for k in 0..<4 {
                let a = CGFloat(k) * .pi / 2
                ctx.move(to: CGPoint(x: cos(a) * r * 0.45, y: sin(a) * r * 0.45))
                ctx.addLine(to: CGPoint(x: cos(a) * r * 1.35, y: sin(a) * r * 1.35))
                ctx.strokePath()
            }
        }
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: -3.5, y: -3.5, width: 7, height: 7))
        // The bezel: little notches that turn slowly, a touch faster on a target.
        ctx.rotate(by: CGFloat(time * (onTarget ? 1.8 : 0.6)))
        ctx.setStrokeColor(HandGamePalette.color(onTarget ? HandGamePalette.coral : HandGamePalette.cream, 0.55))
        ctx.setLineWidth(2)
        for k in 0..<12 {
            let a = CGFloat(k) * .pi / 6
            ctx.move(to: CGPoint(x: cos(a) * (r + 10), y: sin(a) * (r + 10)))
            ctx.addLine(to: CGPoint(x: cos(a) * (r + 15), y: sin(a) * (r + 15)))
        }
        ctx.strokePath()
        ctx.restoreGState()
        if lock > 0.02 {
            ctx.setStrokeColor(ink(0.5))
            ctx.setLineWidth(9)
            ctx.addArc(center: p, radius: r + 22, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * CGFloat(lock), clockwise: true)
            ctx.strokePath()
            ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.gold))
            ctx.setLineWidth(5)
            ctx.addArc(center: p, radius: r + 22, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * CGFloat(lock), clockwise: true)
            ctx.strokePath()
        }
    }

    /// The flash at the muzzle: a hot white core in a star of yellow and orange spikes, over in a few frames.
    static func muzzleFlash(_ ctx: CGContext, at p: CGPoint, angle: Double, age: Double) {
        let t = age / 0.1
        let scale = CGFloat(0.6 + 0.6 * HandGameEase.outCubic(t * 2)) * CGFloat(1 - t * 0.5)
        let alpha = CGFloat(1 - t)
        HandGameArt.halo(ctx, at: p, radius: 70 * scale, red: 1, green: 0.8, blue: 0.4, alpha: Double(alpha) * 0.8)
        guard let flash = flashSprite() else { return }
        ctx.draw(flash, center: p, height: 100 * scale, rotation: CGFloat(angle), alpha: alpha)
    }

    /// The muzzle flash as a sprite: three stars of spikes, hottest in the middle.
    static func flashSprite() -> CGImage? {
        HandGameSprites.image("guns.flash", size: CGSize(width: 120, height: 120)) { ctx in
            for (r, c) in [(CGFloat(56), CGColor(srgbRed: 1, green: 0.6, blue: 0.18, alpha: 0.9)), (40, CGColor(srgbRed: 1, green: 0.88, blue: 0.4, alpha: 1)),
                           (22, CGColor(srgbRed: 1, green: 1, blue: 0.92, alpha: 1))] {
                let path = CGMutablePath()
                for i in 0..<16 {
                    let a = CGFloat(i) * .pi / 8
                    let rr = i % 2 == 0 ? r : r * 0.38
                    let q = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
                    if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
                }
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(c)
                ctx.fillPath()
            }
        }
    }
}
