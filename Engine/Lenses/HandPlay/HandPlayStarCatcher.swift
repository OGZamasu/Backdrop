import AppKit
import CoreGraphics
import simd

/// Star Catcher. Stars drift down from the sky. Hold a hand open and they gather in it, circling your palm; close it into a fist to bank
/// them. The more you hold when you bank, the more each one is worth (the first counts once, the second twice, and so on), but a bomb
/// that lands in an open hand blows the lot away and costs a heart. A fist punches bombs away harmlessly. One minute, three hearts.
///
/// Opening and closing are debounced (`HandPlayGrip`), and a handful waits a moment for a hand that drops out of tracking, so a flicker
/// never banks or spills anything.
struct HandPlayStarCatcher: Game {
    static let title = "Star Catcher"
    static let hint = "Catch stars in an open hand. Make a fist to bank them."
    static let presenceHint = "Hold up your hand to play"
    static let onboarding = ["Catch falling stars in an open hand", "Make a fist to bank them", "Dodge the dark bombs"]
    static let accent = SIMD3<Double>(1.0, 0.82, 0.32)
    static let icon = GameUIIcon.hand(.open)
    static let roundSeconds = 60.0
    static let startingLives = 3
    /// The most stars one hand can hold.
    static let handfulLimit = 8
    /// How long a handful waits for its hand to come back before the stars fall.
    static let handfulGrace = 1.2

    /// The night-sky palette: pale lemon stars, warm amber gold ones, gunmetal bombs.
    enum Colours {
        static let star = HandPlayTone(1.0, 0.86, 0.36)
        static let starLight = HandPlayTone(1.0, 0.97, 0.78)
        static let starDark = HandPlayTone(0.93, 0.56, 0.12)
        static let golden = HandPlayTone(1.0, 0.66, 0.16)
        static let goldenLight = HandPlayTone(1.0, 0.9, 0.55)
        static let goldenDark = HandPlayTone(0.78, 0.3, 0.06)
        static let bomb = HandPlayTone(0.13, 0.13, 0.2)
        static let bombLight = HandPlayTone(0.5, 0.53, 0.66)
        static let net = HandPlayPalette.ice
        static let danger = HandPlayPalette.coral
    }

    enum Kind: Int, CaseIterable {
        case star, golden, bomb

        var value: Int { [1, 3, 0][rawValue] }
        var radius: Double { [30.0, 40, 34][rawValue] }
    }

    struct Item: Equatable {
        var id: Int
        var kind: Kind
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var angle = 0.0
        var spin: Double
        var age = 0.0
        var phase: Double
        /// A bomb a fist knocked away: it flies off and hurts nobody.
        var punched = false
    }

    struct Held: Equatable {
        var kind: Kind
        /// Where it was caught, so it can be seen flying into the hand.
        var from: SIMD2<Double>
        var age = 0.0
        var slot: Double
    }

    struct Handful: Equatable {
        var hand: Int
        var palm: CGPoint
        var size: Double
        var stars: [Held] = []
        /// Seconds the hand has been out of view.
        var lost = 0.0
        var stunned = 0.0
        var open = false
        var closed = false
        var presence = 0.0
        /// Counts down after a bank, for the snap of the fist.
        var banked = 0.0
        var warnedFull = false
    }

    /// A banked star on its way to the score.
    struct Flyer { var kind: Kind; var from: SIMD2<Double>; var delay: Double; var age = 0.0; var bend: Double }
    /// A star that fell out of a hand.
    struct Spill { var kind: Kind; var position: SIMD2<Double>; var velocity: SIMD2<Double>; var angle: Double; var spin: Double; var age = 0.0 }

    let size: CGSize
    private(set) var items: [Item] = []
    private(set) var handfuls: [Handful] = []
    private(set) var score = 0
    private(set) var lives = HandPlayStarCatcher.startingLives
    private(set) var timeLeft = HandPlayStarCatcher.roundSeconds
    private(set) var elapsed = 0.0
    private(set) var caught = 0
    private(set) var banks = 0
    private(set) var bombsHit = 0
    private(set) var spilled = 0
    private(set) var spawnsPaused = false
    private var nextSpawn = 0.6
    private var nextID = 1
    private var roster = HandPlayRoster()
    private var rng: SplitMix64
    private var fx: SplitMix64
    private var particles = ParticleSystem(capacity: 400)
    private var floaters: [HandPlayFloater] = []
    private var flyers: [Flyer] = []
    private var spills: [Spill] = []
    private var hurt = 0.0
    private var scorePulse = 0.0

    var isOver: Bool { timeLeft <= 0 || lives <= 0 }
    var summary: String {
        String(repeating: "❤️", count: max(0, lives)) + String(repeating: "🖤", count: max(0, Self.startingLives - lives))
            + " · \(Int(timeLeft.rounded(.up)))s"
    }
    /// Stars held in all hands, not yet banked.
    var holding: Int { handfuls.reduce(0) { $0 + $1.stars.count } }
    private var unit: Double { Double(size.width) / 1280 }
    private var progress: Double { min(1, elapsed / Self.roundSeconds) }
    /// Where banked stars fly to: the number on the score plate, top left.
    private var scoreSpot: SIMD2<Double> {
        SIMD2(Double(GameScreens.margin.width) + 46, Double(size.height - GameScreens.margin.height - GameScreens.scorePlateHeight) + 34)
    }

    var readout: GameUIReadout {
        GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), time: (max(0, timeLeft), Self.roundSeconds),
                      label: holding > 0 ? "Holding \(holding)" : nil)
    }

    var result: GameUIResult {
        let outOfHearts = lives <= 0
        let line: String
        switch caught {
        case 0: line = "Hold an open hand under a falling star"
        case 1..<12: line = "Bank them often: a fist keeps them safe"
        default: line = "A sky full of stars, safely banked"
        }
        return GameUIResult(headline: outOfHearts ? "Out of hearts" : "Time's up!", line: line,
                            stats: [("\(caught)", "caught"), ("\(banks)", "banked"), ("\(spilled)", "spilled")], kind: outOfHearts ? .lost : .timeUp)
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        fx = SplitMix64(seed: seed ^ 0x5747_4152)
        particles.gravity = SIMD2(0, -260)
    }

    /// What banking `stars` is worth: each star's value times its place in the handful.
    static func worth(of stars: [Kind]) -> Int {
        stars.enumerated().reduce(0) { $0 + $1.element.value * ($1.offset + 1) }
    }

    /// How close to the middle of a palm a falling thing has to come to land in it.
    static func catchRadius(forHandSize size: Double, unit: Double) -> Double { min(150, max(62, size * 0.95)) * unit }

    // MARK: Step

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.25)
        guard !isOver else { return }
        elapsed += dt
        timeLeft = max(0, timeLeft - dt)
        hurt = max(0, hurt - dt)
        scorePulse = max(0, scorePulse - dt)
        roster.update(world.hands, dt: dt, now: elapsed)

        if !spawnsPaused {
            nextSpawn -= dt
            if nextSpawn <= 0 { spawn() }
        }
        updateHandfuls(dt)
        moveItems(dt)
        stepEffects(dt)

        if isOver {
            items.removeAll()
            for i in handfuls.indices { handfuls[i].stars.removeAll() }
            flyers.removeAll()
            spills.removeAll()
            particles.removeAll()
            floaters.removeAll()
            hurt = 0
        }
    }

    private mutating func spawn() {
        let roll = Double.random(in: 0..<1, using: &rng)
        let kind: Kind
        if elapsed > 4 && roll < HandPlayEase.lerp(0.11, 0.24, progress) { kind = .bomb }
        else if roll > 0.88 { kind = .golden }
        else { kind = .star }
        let x = Double(size.width) * Double.random(in: 0.08...0.92, using: &rng)
        let fall = HandPlayEase.lerp(150, 285, progress) * Double.random(in: 0.85...1.15, using: &rng) * (kind == .golden ? 1.2 : 1)
        items.append(Item(id: nextID, kind: kind, position: SIMD2(x, Double(size.height) + kind.radius * unit + 10), velocity: SIMD2(0, -fall * unit),
                          spin: Double.random(in: -1.6...1.6, using: &rng), phase: Double.random(in: 0..<(2 * .pi), using: &rng)))
        nextID += 1
        nextSpawn = HandPlayEase.lerp(0.72, 0.36, progress) * Double.random(in: 0.75...1.25, using: &rng)
    }

    // MARK: Hands

    private mutating func updateHandfuls(_ dt: Double) {
        // Follow every hand in view, and remember the ones that have just dropped out.
        for entry in roster.entries {
            if let i = handfuls.firstIndex(where: { $0.hand == entry.id }) {
                handfuls[i].palm = entry.palm
                handfuls[i].size = entry.size
                handfuls[i].lost = entry.visible ? 0 : handfuls[i].lost + dt
                handfuls[i].open = entry.isHeld && entry.isOpen
                handfuls[i].closed = entry.isHeld && entry.isClosed
                handfuls[i].presence = entry.presence
                if entry.visible, let change = entry.change, change.to == .closed { bank(i) }
            } else if entry.visible {
                var fresh = Handful(hand: entry.id, palm: entry.palm, size: entry.size, open: entry.isOpen, closed: entry.isClosed, presence: entry.presence)
                // A hand that comes back where a lost one was takes over its stars.
                if let orphan = handfuls.firstIndex(where: { h in !roster.entries.contains { $0.id == h.hand } && !h.stars.isEmpty }) {
                    fresh.stars = handfuls[orphan].stars
                    handfuls.remove(at: orphan)
                }
                handfuls.append(fresh)
            }
        }
        for i in handfuls.indices {
            handfuls[i].stunned = max(0, handfuls[i].stunned - dt)
            handfuls[i].banked = max(0, handfuls[i].banked - dt)
            for k in handfuls[i].stars.indices { handfuls[i].stars[k].age += dt }
            if !roster.entries.contains(where: { $0.id == handfuls[i].hand }) {
                handfuls[i].lost += dt
                handfuls[i].presence = max(0, handfuls[i].presence - dt / 0.3)
                handfuls[i].open = false
                handfuls[i].closed = false
            }
        }
        // Stars whose hand never came back fall away.
        for i in handfuls.indices where handfuls[i].lost > Self.handfulGrace && !handfuls[i].stars.isEmpty {
            spill(i, reason: "DROPPED")
        }
        handfuls.removeAll { $0.lost > Self.handfulGrace && $0.stars.isEmpty }
    }

    private mutating func bank(_ index: Int) {
        let stars = handfuls[index].stars
        handfuls[index].banked = 0.35
        guard !stars.isEmpty else { return }
        let points = Self.worth(of: stars.map(\.kind))
        score += points
        banks += 1
        let palm = handfuls[index].palm.handPlayVector
        floaters.append(HandPlayFloater(text: "+\(points)", origin: palm + SIMD2(0, 70 * unit), tone: HandPlayPalette.gold,
                                        size: points >= 15 ? 64 : 50, life: 1.1))
        if stars.count >= 3 {
            floaters.append(HandPlayFloater(text: "\(stars.count) STARS", origin: palm + SIMD2(0, 20 * unit), tone: HandPlayPalette.cream, size: 30, life: 1.0, rise: 60))
        }
        for (k, held) in stars.enumerated() {
            let a = held.slot + elapsed * 2.2
            let r = Self.catchRadius(forHandSize: handfuls[index].size, unit: unit) * 0.55
            let from = palm + SIMD2(cos(a), sin(a)) * r
            flyers.append(Flyer(kind: held.kind, from: from, delay: Double(k) * 0.05, bend: Double.random(in: -1...1, using: &fx)))
        }
        handfuls[index].stars.removeAll()
        handfuls[index].warnedFull = false
        for _ in 0..<16 {
            let a = Double.random(in: 0..<(2 * .pi), using: &fx)
            particles.emit(Particle(position: palm, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 120...340, using: &fx),
                                    life: Double.random(in: 0.35...0.7, using: &fx), size: Double.random(in: 4...9, using: &fx), kind: 0))
        }
    }

    /// Throws a handful's stars out of the hand.
    private mutating func spill(_ index: Int, reason: String) {
        let palm = handfuls[index].palm.handPlayVector
        for held in handfuls[index].stars {
            let a = Double.random(in: 0.3...(.pi - 0.3), using: &fx)
            spills.append(Spill(kind: held.kind, position: palm, velocity: SIMD2(cos(a) * 260, sin(a) * 320) * unit, angle: 0,
                                spin: Double.random(in: -6...6, using: &fx)))
        }
        if !handfuls[index].stars.isEmpty {
            spilled += handfuls[index].stars.count
            floaters.append(HandPlayFloater(text: reason, origin: palm + SIMD2(0, 60 * unit), tone: HandPlayPalette.coral, size: 40))
        }
        handfuls[index].stars.removeAll()
        handfuls[index].warnedFull = false
    }

    // MARK: Falling things

    private mutating func moveItems(_ dt: Double) {
        var kept: [Item] = []
        for var item in items {
            item.age += dt
            item.angle += item.spin * dt
            if item.punched {
                item.velocity.y -= 600 * unit * dt
            } else {
                // A gentle sway as it falls.
                item.velocity.x = cos(item.age * 1.5 + item.phase) * 34 * unit
            }
            item.position += item.velocity * dt
            if item.position.y < -80 * unit || item.position.x < -200 || item.position.x > Double(size.width) + 200 { continue }
            if item.punched && item.position.y > Double(size.height) + 120 * unit { continue }
            if item.punched || !touch(&item) { kept.append(item) }
        }
        items = kept
    }

    /// Whether a hand took the item. A star lands in an open hand; a bomb goes off in an open one and is punched away by a fist.
    private mutating func touch(_ item: inout Item) -> Bool {
        let r = item.kind.radius * unit
        for i in handfuls.indices where handfuls[i].lost == 0 && handfuls[i].stunned <= 0 {
            let palm = handfuls[i].palm.handPlayVector
            let reach = Self.catchRadius(forHandSize: handfuls[i].size, unit: unit)
            let distance = simd_distance(item.position, palm)
            if item.kind == .bomb {
                if handfuls[i].closed && distance < reach * 0.8 + r {
                    let away = distance > 1e-6 ? (item.position - palm) / distance : SIMD2(0, 1)
                    item.velocity = (away + SIMD2(0, 1.1)) * 520 * unit
                    item.spin = away.x >= 0 ? -9 : 9
                    item.punched = true
                    floaters.append(HandPlayFloater(text: "POW!", origin: item.position + SIMD2(0, 50 * unit), tone: HandPlayPalette.sky, size: 42))
                    burst(at: item.position, count: 8, kind: 1)
                    return false
                }
                if handfuls[i].open && distance < reach * 0.75 + r * 0.6 {
                    explode(i, at: item.position)
                    return true
                }
                continue
            }
            guard handfuls[i].open, distance < reach + r * 0.6 else { continue }
            if handfuls[i].stars.count >= Self.handfulLimit {
                if !handfuls[i].warnedFull {
                    handfuls[i].warnedFull = true
                    floaters.append(HandPlayFloater(text: "FULL! MAKE A FIST", origin: palm + SIMD2(0, reach + 30 * unit), tone: HandPlayPalette.cream, size: 34, life: 1.4))
                }
                continue
            }
            let slot = handfuls[i].stars.isEmpty ? 0 : (handfuls[i].stars.last?.slot ?? 0) + 2.4
            handfuls[i].stars.append(Held(kind: item.kind, from: item.position, slot: slot))
            caught += 1
            burst(at: item.position, count: item.kind == .golden ? 12 : 6, kind: 0)
            return true
        }
        return false
    }

    private mutating func explode(_ handful: Int, at point: SIMD2<Double>) {
        lives -= 1
        bombsHit += 1
        hurt = 0.7
        handfuls[handful].stunned = 0.9
        spill(handful, reason: "SPILLED!")
        floaters.append(HandPlayFloater(text: "BOOM!", origin: point + SIMD2(0, 50 * unit), tone: Colours.danger, size: 56))
        for _ in 0..<16 {
            let a = Double.random(in: 0..<(2 * .pi), using: &fx)
            particles.emit(Particle(position: point, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 50...200, using: &fx),
                                    life: Double.random(in: 0.5...0.9, using: &fx), size: Double.random(in: 14...26, using: &fx), kind: 2))
        }
        burst(at: point, count: 20, kind: 1)
    }

    private mutating func burst(at point: SIMD2<Double>, count: Int, kind: Int) {
        for _ in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi), using: &fx)
            particles.emit(Particle(position: point, velocity: SIMD2(cos(a), sin(a) + 0.3) * Double.random(in: 120...380, using: &fx),
                                    life: Double.random(in: 0.3...0.65, using: &fx), size: Double.random(in: 3...8, using: &fx), kind: kind))
        }
    }

    private mutating func stepEffects(_ dt: Double) {
        particles.step(dt) { p in if p.kind == 2 { p.velocity *= exp(-dt * 2.5); p.velocity.y += 300 * dt } }
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll(where: \.isDone)
        var landed = 0
        for i in flyers.indices {
            flyers[i].age += dt
            if flyers[i].age >= flyers[i].delay + 0.55 && flyers[i].age - dt < flyers[i].delay + 0.55 { landed += 1 }
        }
        if landed > 0 { scorePulse = 0.3 }
        flyers.removeAll { $0.age > $0.delay + 0.55 }
        for i in spills.indices {
            spills[i].age += dt
            spills[i].velocity.y -= 900 * unit * dt
            spills[i].position += spills[i].velocity * dt
            spills[i].angle += spills[i].spin * dt
        }
        spills.removeAll { $0.age > 1.2 }
    }

    // MARK: Test hooks

    mutating func pauseSpawns(_ paused: Bool = true) { spawnsPaused = paused }

    @discardableResult
    mutating func drop(_ kind: Kind, at position: SIMD2<Double>, speed: Double = 0) -> Int {
        items.append(Item(id: nextID, kind: kind, position: position, velocity: SIMD2(0, -speed), spin: 0.5, phase: 0))
        nextID += 1
        return nextID - 1
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        let u = CGFloat(unit)
        if hurt > 0 { HandPlayDraw.vignette(ctx, size: size, tone: Colours.danger, alpha: 0.5 * HandPlayEase.outCubic(hurt / 0.7)) }
        guard !isOver else { return }
        for item in items { drawItem(ctx, item) }
        for spill in spills {
            let fade = 1 - spill.age / 1.2
            HandPlayDraw.stamp(ctx, HandPlayStarCatcherArt.star(spill.kind, unit: u), at: spill.position.handPlayPoint, scale: 0.7, rotation: CGFloat(spill.angle),
                               alpha: CGFloat(fade))
        }
        for handful in handfuls { drawHandful(ctx, handful) }
        drawParticles(ctx)
        drawFlyers(ctx)
        if scorePulse > 0 {
            HandPlayDraw.glow(ctx, at: scoreSpot.handPlayPoint, radius: 90 * unit * (1 + scorePulse), tone: Colours.star, alpha: scorePulse / 0.3 * 0.8)
        }
        for f in floaters { f.draw(ctx) }
    }

    private func drawItem(_ ctx: CGContext, _ item: Item) {
        let u = CGFloat(unit)
        let p = item.position.handPlayPoint
        let enter = HandPlayEase.outBack(item.age / 0.35)
        switch item.kind {
        case .bomb:
            if !item.punched {
                let pulse = 0.5 + 0.5 * sin(item.age * 8)
                HandPlayDraw.glow(ctx, at: p, radius: item.kind.radius * 2.4 * unit, tone: Colours.danger, alpha: 0.25 + 0.25 * pulse)
            }
            // A falling bomb hangs upright; one that has been punched tumbles away.
            let turn = item.punched ? item.angle : 0
            let bomb = HandPlayDraw.turned(HandPlayStarCatcherArt.bomb(unit: u), key: "sc.bomb|\(Int(unit * 100))", angle: turn, steps: 24)
            HandPlayDraw.stamp(ctx, bomb, at: p, scale: CGFloat(enter))
            // The fuse spark, flickering, at the tip of the fuse.
            let tipAngle = CGFloat((turn / (2 * .pi) * 24).rounded() / 24 * 2 * .pi)
            let local = CGPoint(x: 26 * u, y: 50 * u)
            let tip = CGPoint(x: p.x + local.x * cos(tipAngle) - local.y * sin(tipAngle), y: p.y + local.x * sin(tipAngle) + local.y * cos(tipAngle))
            let flicker = 0.7 + 0.3 * sin(item.age * 41 + item.phase)
            HandPlayDraw.glow(ctx, at: tip, radius: 22 * unit * flicker, tone: HandPlayPalette.gold, alpha: 0.95)
            HandPlayDraw.glint(ctx, at: tip, radius: 13 * unit * flicker, alpha: 1)
        case .star, .golden:
            let twinkle = 0.5 + 0.5 * sin(item.age * 5 + item.phase)
            HandPlayDraw.glow(ctx, at: p, radius: item.kind.radius * (item.kind == .golden ? 2.8 : 2.0) * unit,
                              tone: item.kind == .golden ? Colours.golden : Colours.star, alpha: 0.35 + 0.2 * twinkle)
            HandPlayDraw.stamp(ctx, HandPlayStarCatcherArt.turnedStar(item.kind, unit: u, angle: item.angle * 0.4), at: p, scale: CGFloat(enter))
            if item.kind == .golden || twinkle > 0.8 {
                let r = item.kind.radius * unit
                HandPlayDraw.glint(ctx, at: CGPoint(x: p.x - r * 0.35, y: p.y + r * 0.4), radius: r * 0.45 * twinkle, alpha: twinkle)
            }
        }
    }

    private func drawHandful(_ ctx: CGContext, _ handful: Handful) {
        let u = unit
        let p = handful.palm
        let alpha = max(handful.presence, handful.stars.isEmpty ? 0 : 0.6)
        guard alpha > 0.01 else { return }
        let reach = Self.catchRadius(forHandSize: handful.size, unit: unit)
        if handful.stunned > 0 {
            let flicker = 0.5 + 0.5 * sin(elapsed * 30)
            HandPlayDraw.ring(ctx, at: p, radius: reach * 0.8, width: 5 * u, tone: Colours.danger, alpha: 0.7 * flicker * alpha)
        } else if handful.open {
            // The net: a soft glow and a dotted ring turning slowly.
            HandPlayDraw.glow(ctx, at: p, radius: reach * 1.15, tone: Colours.star, alpha: 0.16 * alpha)
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setLineDash(phase: CGFloat(elapsed * 24), lengths: [0.1, CGFloat(16 * u)])
            HandPlayDraw.ring(ctx, at: p, radius: reach, width: 7 * u, tone: Colours.net, alpha: 0.9 * alpha, outlined: true)
            ctx.restoreGState()
        } else if handful.closed || handful.banked > 0 {
            let snap = handful.banked > 0 ? HandPlayEase.outCubic(1 - handful.banked / 0.35) : 1
            HandPlayDraw.ring(ctx, at: p, radius: reach * (0.75 - 0.25 * snap) + 0, width: 6 * u, tone: HandPlayPalette.gold, alpha: 0.85 * alpha)
            if handful.banked > 0 {
                HandPlayDraw.ring(ctx, at: p, radius: reach * (0.6 + 0.9 * snap), width: 8 * u * (1 - snap), tone: HandPlayPalette.gold, alpha: 1 - snap)
            }
        }
        // The stars in hand, circling the palm. A new one flies in from where it was caught.
        let orbit = reach * 0.55
        for held in handful.stars {
            let a = held.slot + elapsed * 2.2
            let home = SIMD2(Double(p.x), Double(p.y)) + SIMD2(cos(a), sin(a) * 0.8) * orbit
            let t = HandPlayEase.outCubic(held.age / 0.25)
            let at = held.from + (home - held.from) * t
            // Held stars are baked small, so once they have flown in they are stamped at their own size.
            let scale = 1 + 0.4 * (1 - t)
            HandPlayDraw.stamp(ctx, HandPlayStarCatcherArt.turnedStar(held.kind, unit: CGFloat(unit * 0.62), angle: a * 0.6), at: at.handPlayPoint,
                               scale: CGFloat(scale), alpha: CGFloat(alpha))
        }
        if handful.stars.count >= 2 {
            let worth = Self.worth(of: handful.stars.map(\.kind))
            GameScreens.tag(ctx, "+\(worth)", at: CGPoint(x: p.x + reach * 0.85, y: p.y + reach * 0.85), tone: GameUIPalette.violet, alpha: alpha)
        }
    }

    private func drawFlyers(_ ctx: CGContext) {
        let target = scoreSpot
        for flyer in flyers where flyer.age >= flyer.delay {
            let t = HandPlayEase.inOutCubic((flyer.age - flyer.delay) / 0.55)
            let mid = (flyer.from + target) / 2 + SIMD2(flyer.bend * 120, 160) * unit
            let a = flyer.from + (mid - flyer.from) * t, b = mid + (target - mid) * t
            let at = a + (b - a) * t
            HandPlayDraw.glow(ctx, at: at.handPlayPoint, radius: 40 * unit, tone: Colours.star, alpha: 0.6)
            HandPlayDraw.stamp(ctx, HandPlayStarCatcherArt.star(flyer.kind, unit: CGFloat(unit)), at: at.handPlayPoint, scale: CGFloat(0.65 - 0.3 * t),
                               rotation: CGFloat(t * 6))
        }
    }

    private func drawParticles(_ ctx: CGContext) {
        for p in particles.particles {
            let t = p.progress, at = p.position.handPlayPoint
            switch p.kind {
            case 0: HandPlayDraw.glint(ctx, at: at, radius: p.size * 1.6 * unit * (1 - 0.5 * t), alpha: 1 - t, tone: Colours.starLight)
            case 1: ctx.fillCircle(center: at, radius: CGFloat(p.size * unit * (1 - 0.6 * t)), color: HandPlayPalette.gold.lighter(0.3).cg(1 - t))
            default: HandPlayDraw.glow(ctx, at: at, radius: p.size * unit * (0.8 + 1.5 * t), tone: HandPlayPalette.dusk, alpha: 0.55 * (1 - t))
            }
        }
    }
}

/// The baked pictures for Star Catcher.
enum HandPlayStarCatcherArt {
    typealias C = HandPlayStarCatcher.Colours

    /// A faceted star: each point split into a lit half and a shaded half by a light from the top left, with a thin darker edge.
    static func star(_ kind: HandPlayStarCatcher.Kind, unit: CGFloat) -> CGImage? {
        let r = CGFloat(kind.radius) * unit
        let side = Int(ceil(r * 2.5))
        return HandPlaySprites.image("sc.star|\(kind.rawValue)|\(Int(unit * 100))", side: side) { ctx in
            let golden = kind == .golden
            let base = golden ? C.golden : C.star, light = golden ? C.goldenLight : C.starLight, dark = golden ? C.goldenDark : C.starDark
            let outline = DrawPoints.star(radius: r, inner: 0.48)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: r * 0.05, height: -r * 0.09), blur: r * 0.2, color: HandPlayPalette.ink.cg(0.45))
            ctx.addPath(DrawPoints.path(outline))
            ctx.setFillColor(dark.cg())
            ctx.fillPath()
            ctx.restoreGState()
            let lightDirection = CGVector(dx: -0.6, dy: 0.8)
            for i in 0..<10 {
                let a = outline[i], b = outline[(i + 1) % 10]
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let len = max(1e-6, hypot(mid.x, mid.y))
                let facing = (mid.x / len) * lightDirection.dx + (mid.y / len) * lightDirection.dy
                // Each facet tilts toward its edge; the half of each point that faces the light is bright.
                let k = Double(0.5 + 0.5 * facing)
                let tone = k > 0.5 ? base.mixed(with: light, (k - 0.5) * 2) : dark.mixed(with: base, k * 2)
                let facet = CGMutablePath()
                facet.move(to: .zero)
                facet.addLine(to: a)
                facet.addLine(to: b)
                facet.closeSubpath()
                ctx.addPath(facet)
                ctx.setFillColor(tone.cg())
                ctx.fillPath()
            }
            // A soft hot centre, and the edge.
            HandPlayDraw.radial(ctx, [(HandPlayPalette.cream, golden ? 0.35 : 0.5), (HandPlayPalette.cream, 0)], center: CGPoint(x: -r * 0.08, y: r * 0.08),
                                radius: r * 0.42)
            ctx.addPath(DrawPoints.path(outline))
            ctx.setStrokeColor(dark.darker(0.25).cg(0.8))
            ctx.setLineWidth(max(1, r * 0.06))
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
    }

    /// A star turned to the nearest of a few dozen angles (a star looks the same every fifth of a turn), baked as needed.
    static func turnedStar(_ kind: HandPlayStarCatcher.Kind, unit: CGFloat, angle: Double) -> CGImage? {
        HandPlayDraw.turned(star(kind, unit: unit), key: "sc.star|\(kind.rawValue)|\(Int(unit * 100))", angle: angle, steps: 24, period: 2 * .pi / 5)
    }

    /// A round bomb: gunmetal with a highlight on the top left, a metal cap and a short curled fuse.
    static func bomb(unit: CGFloat) -> CGImage? {
        let r = CGFloat(HandPlayStarCatcher.Kind.bomb.radius) * unit
        let side = Int(ceil(r * 3.4))
        return HandPlaySprites.image("sc.bomb|\(Int(unit * 100))", side: side) { ctx in
            let body = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: r * 0.06, height: -r * 0.1), blur: r * 0.22, color: HandPlayPalette.ink.cg(0.5))
            ctx.fillEllipse(in: body)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addEllipse(in: body)
            ctx.clip()
            HandPlayDraw.radial(ctx, [(C.bombLight, 1), (C.bomb, 1), (HandPlayTone(0.05, 0.05, 0.09), 1)], center: CGPoint(x: r * 0.1, y: -r * 0.1),
                                radius: r * 1.15, from: CGPoint(x: -r * 0.42, y: r * 0.45), locations: [0, 0.55, 1])
            // A cool rim light on the lower right.
            HandPlayDraw.radial(ctx, [(HandPlayPalette.sky, 0.35), (HandPlayPalette.sky, 0)], center: CGPoint(x: r * 0.8, y: -r * 0.75), radius: r * 0.7)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.translateBy(x: -r * 0.38, y: r * 0.44)
            ctx.rotate(by: 0.6)
            ctx.setFillColor(HandPlayPalette.cream.cg(0.75))
            ctx.fillEllipse(in: CGRect(x: -r * 0.22, y: -r * 0.12, width: r * 0.44, height: r * 0.24))
            ctx.restoreGState()
            // The cap.
            ctx.saveGState()
            ctx.translateBy(x: r * 0.42, y: r * 0.78)
            ctx.rotate(by: -0.55)
            let cap = CGRect(x: -r * 0.26, y: -r * 0.1, width: r * 0.52, height: r * 0.32)
            ctx.addPath(CGPath(roundedRect: cap, cornerWidth: r * 0.06, cornerHeight: r * 0.06, transform: nil))
            ctx.clip()
            HandPlayDraw.fill(ctx, [(HandPlayTone(0.82, 0.84, 0.9), 1), (HandPlayTone(0.42, 0.44, 0.52), 1)], from: CGPoint(x: 0, y: cap.maxY), to: CGPoint(x: 0, y: cap.minY))
            ctx.restoreGState()
            // The fuse.
            let fuse = CGMutablePath()
            fuse.move(to: CGPoint(x: r * 0.55, y: r * 0.98))
            fuse.addQuadCurve(to: CGPoint(x: r * 0.76, y: r * 1.47), control: CGPoint(x: r * 0.95, y: r * 1.12))
            ctx.addPath(fuse)
            ctx.setStrokeColor(HandPlayTone(0.62, 0.48, 0.32).cg())
            ctx.setLineWidth(r * 0.13)
            ctx.setLineCap(.round)
            ctx.strokePath()
            ctx.addPath(fuse)
            ctx.setStrokeColor(HandPlayTone(0.86, 0.74, 0.55).cg(0.7))
            ctx.setLineWidth(r * 0.05)
            ctx.setLineDash(phase: 0, lengths: [r * 0.06, r * 0.07])
            ctx.strokePath()
        }
    }
}

/// Point lists for star shapes, shared by the star art.
private enum DrawPoints {
    static func star(radius: CGFloat, inner: CGFloat) -> [CGPoint] {
        (0..<10).map { i in
            let r = i % 2 == 0 ? radius : radius * inner
            let a = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            return CGPoint(x: cos(a) * r, y: sin(a) * r)
        }
    }

    static func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }
}
