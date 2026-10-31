import AppKit
import CoreGraphics
import simd

/// Magic Duel. Shadow monsters drift in from the edges toward you. Hold up an open hand and a fireball gathers in your palm; push the hand
/// toward a monster and the fireball flies that way. Brutes throw hexes at you; close your hand into a fist and a shield goes up round you,
/// but it only holds for a few seconds before it needs to recharge. A monster or a hex that reaches you costs a heart.
///
/// Aim comes from the direction the palm moves, not the angle of a finger (the noisiest thing a camera sees), with a generous cone of help
/// toward the monster nearest that line, and the fireball steers a little on its way. If a ready fireball is held for over a second without
/// a push (or the push was lost in a blur), it flies at the monster nearest the hand by itself, which the reticle shows.
struct HandPlayMagicDuel: Game {
    static let title = "Magic Duel"
    static let hint = "Push an open hand to throw fire. Make a fist to shield."
    static let presenceHint = "Hold up your hand to play"
    static let onboarding = ["Push an open hand to throw fire", "Make a fist to put up a shield"]
    static let accent = SIMD3<Double>(0.74, 0.5, 1.0)
    static let icon = GameUIIcon.hand(.open)
    static let startingHearts = 3

    /// The colours of the duel: warm fire against cold violet shadow.
    enum Colours {
        static let fireCore = HandPlayTone(1.0, 0.98, 0.86)
        static let fire = HandPlayPalette.gold
        static let flame = HandPlayTone(1.0, 0.62, 0.2)
        static let ember = HandPlayPalette.ember
        static let soot = HandPlayTone(0.32, 0.12, 0.08)
        static let shadowTop = HandPlayTone(0.38, 0.26, 0.66)
        static let shadowMid = HandPlayTone(0.17, 0.11, 0.34)
        static let shadowDeep = HandPlayTone(0.08, 0.05, 0.17)
        static let aura = HandPlayTone(0.72, 0.34, 1.0)
        static let hex = HandPlayTone(0.86, 0.3, 0.95)
        static let shield = HandPlayTone(0.42, 0.88, 1.0)
        static let shieldRim = HandPlayPalette.ice
    }

    enum Kind: Int, CaseIterable {
        /// Drifts in and wobbles. One fireball.
        case wisp
        /// Quick and zig-zagging. One fireball.
        case bat
        /// Big and slow, takes three fireballs, and throws hexes on its way in.
        case brute

        var hitPoints: Int { self == .brute ? 3 : 1 }
        var radius: Double { [44.0, 34, 64][rawValue] }
        var speed: Double { [80.0, 138, 44][rawValue] }
        var points: Int { [1, 2, 5][rawValue] }
    }

    struct Monster: Equatable {
        var id: Int
        var kind: Kind
        var position: SIMD2<Double>
        var hitPoints: Int
        var age = 0.0
        var phase: Double
        /// A shove from a fireball or the shield, fading.
        var knock = SIMD2<Double>.zero
        var flash = 0.0
        var stunned = 0.0
        /// Seconds since it was banished, or nil while it is about.
        var dying: Double? = nil
        /// Seconds until a brute throws its next hex.
        var castIn = 3.0

        var isAlive: Bool { dying == nil }
    }

    struct Fireball: Equatable {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var target: Int?
        var age = 0.0
    }

    struct Hex: Equatable {
        var position: SIMD2<Double>
        var age = 0.0
    }

    /// One hand's spell: how full the fireball in its palm is and what it is aimed at.
    struct Caster: Equatable {
        var hand: Int
        var palm: CGPoint
        var charge = 0.0
        var target: Int?
        var open = false
        var closed = false
        var presence = 0.0
        /// Seconds since this hand last threw, for the recoil.
        var sinceCast = 9.0
        /// Seconds the fireball has been ready without being thrown.
        var readyFor = 0.0
    }

    struct Ripple { var at: SIMD2<Double>; var age = 0.0 }

    // Tuning, for a 1280-wide picture; distances scale with the width.
    static let chargeTime = 0.42
    /// A ready fireball held this long without a push goes by itself.
    static let autoRelease = 1.2
    /// How far off the line of a push a monster can be and still be the one aimed at.
    static let aimCone = 0.7
    static let fireballSpeed = 980.0
    static let fireballRadius = 20.0
    static let hexSpeed = 230.0
    static let hexRadius = 19.0
    static let homeRadius = 130.0
    static let shieldRadius = 212.0
    /// Seconds of shield in a full charge, and how fast it comes back.
    static let shieldDrain = 0.3
    static let shieldRecharge = 0.2
    /// A broken shield has to come back this far before it can go up again.
    static let shieldRestart = 0.45

    let size: CGSize
    /// Where you are: the middle of the picture, a little low, where a person on a call sits.
    let home: SIMD2<Double>
    private(set) var monsters: [Monster] = []
    private(set) var fireballs: [Fireball] = []
    private(set) var hexes: [Hex] = []
    private(set) var casters: [Caster] = []
    private(set) var score = 0
    private(set) var hearts = HandPlayMagicDuel.startingHearts
    private(set) var elapsed = 0.0
    private(set) var banished = 0
    private(set) var blocked = 0
    private(set) var shieldUp = false
    private(set) var shieldEnergy = 1.0
    private(set) var shieldBroken = false
    private(set) var spawnsPaused = false
    private var shieldShown = 0.0
    private var hurt = 0.0
    private var nextSpawn = 0.8
    private var nextID = 1
    private var roster = HandPlayRoster()
    private var rng: SplitMix64
    private var fx: SplitMix64
    private var particles = ParticleSystem(capacity: 520)
    private var floaters: [HandPlayFloater] = []
    private var ripples: [Ripple] = []

    var isOver: Bool { hearts <= 0 }
    var summary: String {
        String(repeating: "❤️", count: max(0, hearts)) + String(repeating: "🖤", count: max(0, Self.startingHearts - hearts))
    }
    private var unit: Double { Double(size.width) / 1280 }
    private var progress: Double { min(1, elapsed / 100) }

    var readout: GameUIReadout { GameUIReadout(score: score, lives: (max(0, hearts), Self.startingHearts)) }

    var result: GameUIResult {
        let line: String
        switch banished {
        case 0: line = "Push your open hand at a shadow to throw fire"
        case 1..<10: line = "The shadows are learning to fear you"
        default: line = "A true duelling wizard"
        }
        let seconds = Int(elapsed)
        return GameUIResult(headline: "Out of hearts", line: line,
                            stats: [("\(banished)", "banished"), ("\(blocked)", "hexes blocked"), (String(format: "%d:%02d", seconds / 60, seconds % 60), "time")])
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        home = SIMD2(Double(size.width) / 2, Double(size.height) * 0.45)
        rng = SplitMix64(seed: seed)
        fx = SplitMix64(seed: seed ^ 0xD1CE_F00D)
        particles.gravity = .zero
    }

    // MARK: Step

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.25)
        guard !isOver else { return }
        elapsed += dt
        hurt = max(0, hurt - dt)
        roster.update(world.hands, dt: dt, now: elapsed)

        if !spawnsPaused {
            nextSpawn -= dt
            if nextSpawn <= 0 { spawn() }
        }
        updateCasters(dt)
        updateShield(dt)
        moveMonsters(dt)
        moveFireballs(dt)
        moveHexes(dt)
        stepEffects(dt)

        if isOver {
            // Nothing moves once it is over, so leave a quiet picture rather than a battle frozen mid-air.
            monsters.removeAll()
            fireballs.removeAll()
            hexes.removeAll()
            particles.removeAll()
            floaters.removeAll()
            ripples.removeAll()
            shieldUp = false
            shieldShown = 0
            hurt = 0
        }
    }

    private mutating func spawn() {
        let alive = monsters.filter(\.isAlive)
        let limit = min(7, 2 + Int(elapsed / 14))
        guard alive.count < limit else { nextSpawn = 0.3; return }
        let roll = Double.random(in: 0..<1, using: &rng)
        let brutes = alive.filter { $0.kind == .brute }.count
        let kind: Kind
        if elapsed < 10 { kind = .wisp }
        else if roll < 0.2 && brutes < 2 { kind = .brute }
        else if roll < 0.48 && elapsed > 18 { kind = .bat }
        else { kind = .wisp }

        let w = Double(size.width), h = Double(size.height)
        let side = Int.random(in: 0..<5, using: &rng)
        let margin = kind.radius * unit + 30
        let position: SIMD2<Double>
        switch side {
        case 0, 1: position = SIMD2(-margin, h * Double.random(in: 0.3...0.88, using: &rng))
        case 2, 3: position = SIMD2(w + margin, h * Double.random(in: 0.3...0.88, using: &rng))
        default: position = SIMD2(w * Double.random(in: 0.2...0.8, using: &rng), h + margin)
        }
        monsters.append(Monster(id: nextID, kind: kind, position: position, hitPoints: kind.hitPoints,
                                phase: Double.random(in: 0..<(2 * .pi), using: &rng), castIn: Double.random(in: 2.2...3.4, using: &rng)))
        nextID += 1
        nextSpawn = HandPlayEase.lerp(2.3, 0.85, progress) * Double.random(in: 0.8...1.2, using: &rng)
    }

    // MARK: Hands

    private mutating func updateCasters(_ dt: Double) {
        var next: [Caster] = []
        for entry in roster.entries {
            var caster = casters.first { $0.hand == entry.id } ?? Caster(hand: entry.id, palm: entry.palm)
            caster.palm = entry.palm
            caster.presence = entry.presence
            caster.sinceCast += dt
            caster.open = entry.isHeld && entry.isOpen
            caster.closed = entry.isHeld && entry.isClosed
            if caster.open {
                caster.charge = min(1, caster.charge + dt / Self.chargeTime)
                caster.target = target(for: entry.palm)
                caster.readyFor = caster.charge >= 1 ? caster.readyFor + dt : 0
                let pushSpeed = max(280 * unit, entry.size * 2.2)
                if caster.charge >= 1 && entry.speed >= pushSpeed {
                    // Thrown: along the push, toward whatever lies nearest that line.
                    let direction = entry.velocity / entry.speed
                    cast(from: entry.palm, toward: direction, target: aimed(from: entry.palm, along: direction))
                    caster.charge = 0
                    caster.readyFor = 0
                    caster.sinceCast = 0
                } else if caster.readyFor >= Self.autoRelease, let id = caster.target, let monster = monsters.first(where: { $0.id == id }) {
                    let offset = monster.position - entry.palm.handPlayVector
                    let length = simd_length(offset)
                    cast(from: entry.palm, toward: length > 1e-6 ? offset / length : SIMD2(0, 1), target: id)
                    caster.charge = 0
                    caster.readyFor = 0
                    caster.sinceCast = 0
                }
            } else {
                caster.charge = max(0, caster.charge - dt / 0.25)
                caster.readyFor = 0
                if !entry.visible { caster.target = nil }
            }
            next.append(caster)
        }
        casters = next
    }

    /// The monster a hand is aimed at: the nearest one to the palm, passing over any that already have enough fire on its way to finish it.
    func target(for palm: CGPoint) -> Int? {
        let p = palm.handPlayVector
        var best: (id: Int, cost: Double)?
        for m in monsters where m.isAlive && onScreen(m.position, margin: -10 * unit) {
            let incoming = fireballs.filter { $0.target == m.id }.count
            let cost = simd_distance(p, m.position) + (incoming >= m.hitPoints ? 700 : 0)
            if best.map({ cost < $0.cost }) ?? true { best = (m.id, cost) }
        }
        return best?.id
    }

    /// The monster a push along `direction` is aimed at: the one closest to that line, within a generous cone, passing over any that are
    /// already done for. Nil if nothing lies that way.
    func aimed(from palm: CGPoint, along direction: SIMD2<Double>) -> Int? {
        let p = palm.handPlayVector
        var best: (id: Int, cost: Double)?
        for m in monsters where m.isAlive && onScreen(m.position, margin: -10 * unit) {
            let offset = m.position - p
            let distance = simd_length(offset)
            guard distance > 1e-6 else { continue }
            let off = acos(min(1, max(-1, simd_dot(offset / distance, direction))))
            guard off <= Self.aimCone else { continue }
            let incoming = fireballs.filter { $0.target == m.id }.count
            let cost = off + distance / 4000 + (incoming >= m.hitPoints ? 2 : 0)
            if best.map({ cost < $0.cost }) ?? true { best = (m.id, cost) }
        }
        return best?.id
    }

    private func onScreen(_ p: SIMD2<Double>, margin: Double) -> Bool {
        p.x > -margin && p.x < Double(size.width) + margin && p.y > -margin && p.y < Double(size.height) + margin
    }

    private mutating func cast(from palm: CGPoint, toward heading: SIMD2<Double>, target: Int?) {
        let from = palm.handPlayVector
        fireballs.append(Fireball(position: from, velocity: heading * Self.fireballSpeed * unit, target: target))
        for _ in 0..<10 {
            let a = atan2(heading.y, heading.x) + .pi + Double.random(in: -0.9...0.9, using: &fx)
            emit(.spark, at: from, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 120...320, using: &fx), life: 0.3, size: 4)
        }
    }

    private mutating func updateShield(_ dt: Double) {
        let wants = casters.contains { $0.closed }
        if shieldBroken && shieldEnergy >= Self.shieldRestart { shieldBroken = false }
        shieldUp = wants && !shieldBroken && shieldEnergy > 0
        if shieldUp {
            shieldEnergy = max(0, shieldEnergy - dt * Self.shieldDrain)
            if shieldEnergy <= 0 { breakShield() }
        } else {
            shieldEnergy = min(1, shieldEnergy + dt * Self.shieldRecharge)
        }
        shieldShown += (shieldUp ? 1 - shieldShown : -shieldShown) * HandPlayEase.follow(dt, tau: shieldUp ? 0.05 : 0.09)
    }

    private mutating func breakShield() {
        shieldBroken = true
        shieldUp = false
        floaters.append(HandPlayFloater(text: "SHIELD DOWN", origin: home + SIMD2(0, (Self.shieldRadius + 40) * unit), tone: Colours.shield, size: 34))
        for k in 0..<26 {
            let a = Double(k) / 26 * 2 * .pi
            let at = home + SIMD2(cos(a), sin(a)) * Self.shieldRadius * unit
            emit(.shard, at: at, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 80...240, using: &fx), life: 0.6, size: 7)
        }
    }

    // MARK: Monsters

    private mutating func moveMonsters(_ dt: Double) {
        let reach = Self.homeRadius * unit
        for i in monsters.indices {
            monsters[i].age += dt
            monsters[i].flash = max(0, monsters[i].flash - dt)
            if let d = monsters[i].dying { monsters[i].dying = d + dt; continue }
            let m = monsters[i]
            let offset = home - m.position
            let distance = max(1e-6, simd_length(offset))
            let dir = offset / distance, side = SIMD2(-dir.y, dir.x)
            var speed = m.kind.speed * unit * (1 + 0.45 * progress)
            if m.kind == .brute && distance < 430 * unit { speed *= 0.4 }
            let (frequency, sway): (Double, Double) = m.kind == .bat ? (5.2, 150) : m.kind == .brute ? (1.3, 22) : (2.1, 52)
            var velocity = side * sin(m.age * frequency + m.phase) * sway * unit
            if m.stunned <= 0 { velocity += dir * speed }
            monsters[i].stunned = max(0, m.stunned - dt)
            monsters[i].position += (velocity + m.knock) * dt
            monsters[i].knock *= exp(-dt / 0.22)

            if m.kind == .brute && m.stunned <= 0 && onScreen(m.position, margin: -m.kind.radius * unit) {
                monsters[i].castIn -= dt
                if monsters[i].castIn <= 0 {
                    hexes.append(Hex(position: m.position + dir * m.kind.radius * 0.6 * unit))
                    monsters[i].castIn = Double.random(in: 2.6...3.6, using: &rng) * HandPlayEase.lerp(1, 0.7, progress)
                }
            }

            let gap = simd_distance(monsters[i].position, home)
            if shieldShown > 0.5 && shieldUp && gap < (Self.shieldRadius + m.kind.radius * 0.5) * unit {
                // The shield throws it back and holds it for a moment.
                monsters[i].knock = -dir * 620 * unit
                monsters[i].stunned = 0.7
                shieldEnergy = max(0, shieldEnergy - 0.1)
                ripples.append(Ripple(at: home - dir * Self.shieldRadius * unit))
                if shieldEnergy <= 0 { breakShield() }
            } else if gap < reach + m.kind.radius * 0.4 * unit {
                monsters[i].dying = 0
                hit(at: monsters[i].position)
            }
        }
        let w = Double(size.width), h = Double(size.height), margin = 400 * unit
        monsters.removeAll { m in
            (m.dying ?? 0) > 0.5 || m.position.x < -margin || m.position.x > w + margin || m.position.y < -margin || m.position.y > h + margin
        }
    }

    private mutating func hit(at point: SIMD2<Double>) {
        hearts -= 1
        hurt = 0.7
        floaters.append(HandPlayFloater(text: "OUCH!", origin: point + SIMD2(0, 40 * unit), tone: HandPlayPalette.coral, size: 46))
        for _ in 0..<18 {
            let a = Double.random(in: 0..<(2 * .pi), using: &fx)
            emit(.smoke, at: point, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 40...160, using: &fx), life: 0.7, size: 16)
        }
    }

    private mutating func damage(_ index: Int, push: SIMD2<Double>) {
        guard monsters[index].isAlive else { return }
        monsters[index].hitPoints -= 1
        monsters[index].flash = 0.14
        monsters[index].knock += push * 260 * unit
        let at = monsters[index].position
        for _ in 0..<14 {
            let a = Double.random(in: 0..<(2 * .pi), using: &fx)
            emit(.spark, at: at, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 150...460, using: &fx), life: Double.random(in: 0.25...0.5, using: &fx),
                 size: Double.random(in: 3...6, using: &fx))
        }
        guard monsters[index].hitPoints <= 0 else { return }
        monsters[index].dying = 0
        let kind = monsters[index].kind
        score += kind.points
        banished += 1
        floaters.append(HandPlayFloater(text: "+\(kind.points)", origin: at + SIMD2(0, kind.radius * unit), tone: HandPlayPalette.gold,
                                        size: kind == .brute ? 58 : 46))
        for _ in 0..<(kind == .brute ? 26 : 14) {
            let a = Double.random(in: 0..<(2 * .pi), using: &fx)
            emit(.smoke, at: at + SIMD2(cos(a), sin(a)) * kind.radius * 0.4 * unit, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 30...140, using: &fx),
                 life: Double.random(in: 0.5...0.9, using: &fx), size: Double.random(in: 10...22, using: &fx) * (kind == .brute ? 1.4 : 1))
        }
        for _ in 0..<12 {
            let a = Double.random(in: 0..<(2 * .pi), using: &fx)
            emit(.dust, at: at, velocity: SIMD2(cos(a), sin(a) + 0.4) * Double.random(in: 60...220, using: &fx), life: Double.random(in: 0.6...1.1, using: &fx),
                 size: Double.random(in: 4...8, using: &fx))
        }
    }

    // MARK: Fire and hexes

    private mutating func moveFireballs(_ dt: Double) {
        let r = Self.fireballRadius * unit
        for i in fireballs.indices {
            fireballs[i].age += dt
            let speed = Self.fireballSpeed * unit
            if let id = fireballs[i].target, let m = monsters.first(where: { $0.id == id && $0.isAlive }) {
                // Steer toward the target, but only so fast: a fireball curves, it does not snap.
                let want = m.position - fireballs[i].position
                let heading = atan2(fireballs[i].velocity.y, fireballs[i].velocity.x)
                var turn = atan2(want.y, want.x) - heading
                while turn > .pi { turn -= 2 * .pi }
                while turn < -.pi { turn += 2 * .pi }
                let limited = heading + min(7 * dt, max(-7 * dt, turn))
                fireballs[i].velocity = SIMD2(cos(limited), sin(limited)) * speed
            }
            fireballs[i].position += fireballs[i].velocity * dt
            let at = fireballs[i].position
            for _ in 0..<3 {
                let back = -fireballs[i].velocity * 0.12 + SIMD2(Double.random(in: -60...60, using: &fx), Double.random(in: -60...60, using: &fx))
                emit(.flame, at: at + SIMD2(Double.random(in: -6...6, using: &fx), Double.random(in: -6...6, using: &fx)) * unit, velocity: back,
                     life: Double.random(in: 0.2...0.42, using: &fx), size: Double.random(in: 11...21, using: &fx) * unit)
            }

            for j in monsters.indices where monsters[j].isAlive {
                if simd_distance(at, monsters[j].position) < monsters[j].kind.radius * 0.85 * unit + r {
                    let push = simd_length(fireballs[i].velocity) > 0 ? simd_normalize(fireballs[i].velocity) : SIMD2(0, 1)
                    damage(j, push: push)
                    fireballs[i].age = 99
                    explode(at: at)
                    break
                }
            }
            guard fireballs[i].age < 99 else { continue }
            if let k = hexes.firstIndex(where: { simd_distance($0.position, at) < Self.hexRadius * unit + r }) {
                let spot = hexes[k].position
                hexes.remove(at: k)
                fireballs[i].age = 99
                score += 1
                blocked += 1
                explode(at: spot)
                floaters.append(HandPlayFloater(text: "+1", origin: spot + SIMD2(0, 30 * unit), tone: HandPlayPalette.gold, size: 38))
            }
        }
        let w = Double(size.width), h = Double(size.height), margin = 60 * unit
        fireballs.removeAll { b in
            b.age > 1.8 || b.position.x < -margin || b.position.x > w + margin || b.position.y < -margin || b.position.y > h + margin
        }
    }

    private mutating func explode(at point: SIMD2<Double>) {
        for _ in 0..<12 {
            let a = Double.random(in: 0..<(2 * .pi), using: &fx)
            emit(.flame, at: point, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 60...260, using: &fx), life: Double.random(in: 0.2...0.45, using: &fx),
                 size: Double.random(in: 12...24, using: &fx) * unit)
        }
    }

    private mutating func moveHexes(_ dt: Double) {
        let shieldReach = Self.shieldRadius * unit, reach = Self.homeRadius * 0.8 * unit
        var kept: [Hex] = []
        for var hex in hexes {
            hex.age += dt
            let offset = home - hex.position
            let distance = max(1e-6, simd_length(offset))
            hex.position += offset / distance * Self.hexSpeed * unit * (1 + 0.3 * progress) * dt
            let gap = simd_distance(hex.position, home)
            if shieldUp && shieldShown > 0.5 && gap < shieldReach + Self.hexRadius * unit {
                score += 1
                blocked += 1
                shieldEnergy = max(0, shieldEnergy - 0.06)
                ripples.append(Ripple(at: home - offset / distance * shieldReach))
                floaters.append(HandPlayFloater(text: "BLOCKED", origin: hex.position + SIMD2(0, 30 * unit), tone: Colours.shield, size: 34))
                for _ in 0..<10 {
                    let a = atan2(-offset.y, -offset.x) + Double.random(in: -1.2...1.2, using: &fx)
                    emit(.dust, at: hex.position, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 120...300, using: &fx), life: 0.5, size: 5)
                }
                if shieldEnergy <= 0 { breakShield() }
                continue
            }
            if gap < reach {
                hit(at: hex.position)
                continue
            }
            kept.append(hex)
        }
        hexes = kept
    }

    // MARK: Effects

    private enum Bit: Int { case flame, spark, smoke, dust, shard }

    private mutating func emit(_ bit: Bit, at p: SIMD2<Double>, velocity: SIMD2<Double>, life: Double, size: Double) {
        particles.emit(Particle(position: p, velocity: velocity, life: life, size: size, hue: Double.random(in: 0..<1, using: &fx), kind: bit.rawValue))
    }

    private mutating func stepEffects(_ dt: Double) {
        particles.step(dt) { p in
            switch Bit(rawValue: p.kind) ?? .spark {
            case .flame: p.velocity.y += 140 * dt; p.velocity *= exp(-dt * 3)
            case .smoke: p.velocity *= exp(-dt * 2.2); p.velocity.y += 30 * dt
            case .spark, .shard: p.velocity.y -= 420 * dt
            case .dust: p.velocity *= exp(-dt * 1.6); p.velocity.y += 40 * dt
            }
        }
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll(where: \.isDone)
        for i in ripples.indices { ripples[i].age += dt }
        ripples.removeAll { $0.age > 0.5 }
    }

    // MARK: Test hooks

    mutating func pauseSpawns(_ paused: Bool = true) { spawnsPaused = paused }

    /// Puts a monster somewhere, and returns its id.
    @discardableResult
    mutating func place(_ kind: Kind, at position: SIMD2<Double>, castIn: Double = 99) -> Int {
        monsters.append(Monster(id: nextID, kind: kind, position: position, hitPoints: kind.hitPoints, phase: 0, castIn: castIn))
        nextID += 1
        return nextID - 1
    }

    mutating func placeHex(at position: SIMD2<Double>) { hexes.append(Hex(position: position)) }
    mutating func clearMonsters() { monsters.removeAll() }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        if hurt > 0 { HandPlayDraw.vignette(ctx, size: size, tone: HandPlayPalette.coral, alpha: 0.55 * HandPlayEase.outCubic(hurt / 0.7)) }
        guard !isOver else { return }

        drawDanger(ctx)
        drawParticles(ctx, behind: true)
        for m in monsters.sorted(by: { $0.position.y > $1.position.y }) { drawMonster(ctx, m) }
        for hex in hexes { drawHex(ctx, hex) }
        drawShield(ctx, time: time)
        for caster in casters { drawCaster(ctx, caster) }
        for ball in fireballs { drawFireball(ctx, ball) }
        drawParticles(ctx, behind: false)
        for f in floaters { f.draw(ctx) }
    }

    /// A faint warning ring round you while something is close and the shield is down.
    private func drawDanger(_ ctx: CGContext) {
        let reach = Self.homeRadius * unit
        let closest = (monsters.filter(\.isAlive).map { simd_distance($0.position, home) } + hexes.map { simd_distance($0.position, home) }).min() ?? .infinity
        let near = HandPlayEase.clamp(1 - (closest - reach) / (260 * unit))
        guard near > 0.3, !shieldUp else { return }
        let pulse = 0.6 + 0.4 * sin(elapsed * 9)
        ctx.saveGState()
        ctx.setLineDash(phase: CGFloat(elapsed * 30), lengths: [CGFloat(14 * unit), CGFloat(12 * unit)])
        HandPlayDraw.ring(ctx, at: home.handPlayPoint, radius: reach + 10 * unit, width: 4 * unit, tone: HandPlayPalette.coral, alpha: 0.65 * near * pulse)
        ctx.restoreGState()
    }

    private func drawMonster(_ ctx: CGContext, _ m: Monster) {
        let u = unit
        let r = m.kind.radius * u
        var alpha = 1.0, sx = 1.0, sy = 1.0
        // Entrance: it seeps in rather than appearing.
        let enter = HandPlayEase.outCubic(m.age / 0.5)
        alpha *= enter
        if let d = m.dying {
            let t = d / 0.5
            alpha *= max(0, 1 - t * t)
            sx = 1 + 0.35 * HandPlayEase.outCubic(t)
            sy = 1 - 0.3 * HandPlayEase.outCubic(t)
        } else if m.flash > 0 {
            // A squash when struck. (Otherwise it is drawn at its own size: the hem ripples and it bobs, which is life enough.)
            sx = 1 + m.flash * 1.2
            sy = 1 - m.flash * 0.9
        }
        let p = CGPoint(x: m.position.x, y: m.position.y + sin(m.age * 2.4 + m.phase) * 6 * u)
        let frame = Int((m.age * (m.kind == .bat ? 12 : 7)).rounded(.down)) % HandPlayMagicDuelArt.frames
        HandPlayDraw.shadow(ctx, at: CGPoint(x: p.x + r * 0.15, y: p.y - r * 1.15), width: r * 1.7, height: r * 0.45, alpha: 0.35 * alpha)
        HandPlayDraw.stamp(ctx, HandPlayMagicDuelArt.monster(m.kind, frame: frame, unit: u), at: p, sx: CGFloat(sx), sy: CGFloat(sy), alpha: CGFloat(alpha))
        if m.flash > 0 {
            HandPlayDraw.stamp(ctx, HandPlayMagicDuelArt.monster(m.kind, frame: frame, unit: u, flash: true), at: p, sx: CGFloat(sx), sy: CGFloat(sy),
                               alpha: CGFloat(alpha * min(1, m.flash / 0.08)))
        }
        guard m.isAlive else { return }
        drawEyes(ctx, m, at: p, scale: (sx, sy), alpha: alpha)
        if m.kind == .brute && m.hitPoints < m.kind.hitPoints {
            // Pips for the hits it can still take.
            for k in 0..<m.hitPoints {
                let x = p.x + (Double(k) - Double(m.hitPoints - 1) / 2) * 18 * u
                HandPlayDraw.glow(ctx, at: CGPoint(x: x, y: p.y + r * 1.25), radius: 10 * u, tone: Colours.aura, alpha: 0.8 * alpha)
                ctx.fillCircle(center: CGPoint(x: x, y: p.y + r * 1.25), radius: 4.5 * u, color: HandPlayPalette.cream.cg(alpha))
            }
        }
        if m.kind == .brute && m.castIn < 0.45 {
            // Anticipation: its mouth glows before it throws.
            let k = 1 - m.castIn / 0.45
            HandPlayDraw.glow(ctx, at: CGPoint(x: p.x, y: p.y - r * 0.28), radius: r * (0.4 + 0.5 * k), tone: Colours.hex, alpha: 0.9 * k * alpha)
        }
    }

    /// Glowing eyes that look toward you, and blink now and then.
    private func drawEyes(_ ctx: CGContext, _ m: Monster, at p: CGPoint, scale: (Double, Double), alpha: Double) {
        let u = unit, r = m.kind.radius * u
        let look = simd_length(home - m.position) > 1 ? simd_normalize(home - m.position) : SIMD2(0, -1)
        let blink = (m.age + m.phase * 3).truncatingRemainder(dividingBy: 3.4) < 0.12 ? 0.15 : 1.0
        let (spread, height, eyeW, eyeH): (Double, Double, Double, Double)
        let tone: HandPlayTone
        switch m.kind {
        case .wisp: (spread, height, eyeW, eyeH) = (0.34, 0.16, 0.22, 0.3); tone = HandPlayPalette.gold
        case .bat: (spread, height, eyeW, eyeH) = (0.3, 0.12, 0.24, 0.26); tone = HandPlayPalette.mint
        case .brute: (spread, height, eyeW, eyeH) = (0.3, 0.2, 0.2, 0.17); tone = HandPlayPalette.coral
        }
        for s in [-1.0, 1.0] {
            let c = CGPoint(x: p.x + s * spread * r * scale.0, y: p.y + height * r * scale.1)
            HandPlayDraw.glow(ctx, at: c, radius: eyeW * r * 2.2, tone: tone, alpha: 0.55 * alpha)
            let w = eyeW * r, h = eyeH * r * blink
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            if m.kind == .brute { ctx.rotate(by: CGFloat(-s * 0.35)) }
            ctx.setFillColor(tone.lighter(0.55).cg(alpha))
            ctx.fillEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            if blink > 0.5 {
                let pw = w * 0.45, ph = h * 0.6
                ctx.setFillColor(HandPlayPalette.ink.cg(alpha))
                ctx.fillEllipse(in: CGRect(x: look.x * w * 0.18 - pw / 2, y: look.y * h * 0.15 - ph / 2, width: pw, height: ph))
            }
            ctx.restoreGState()
        }
    }

    private func drawHex(_ ctx: CGContext, _ hex: Hex) {
        let p = hex.position.handPlayPoint
        let grow = HandPlayEase.outBack(hex.age / 0.25)
        HandPlayDraw.glow(ctx, at: p, radius: Self.hexRadius * 2.6 * unit, tone: Colours.hex, alpha: 0.5)
        let orb = HandPlayDraw.turned(HandPlayMagicDuelArt.hexOrb(unit: CGFloat(unit)), key: "md.hex|\(Int(unit * 100))", angle: hex.age * 5, steps: 16)
        HandPlayDraw.stamp(ctx, orb, at: p, scale: CGFloat(grow))
    }

    private func drawShield(_ ctx: CGContext, time: Double) {
        let p = home.handPlayPoint
        if shieldShown > 0.01 {
            let scale = 0.6 + 0.4 * HandPlayEase.outBack(shieldShown, overshoot: 2)
            let flicker = shieldEnergy < 0.25 ? 0.75 + 0.25 * sin(elapsed * 40) : 1
            HandPlayDraw.stamp(ctx, HandPlayMagicDuelArt.shield(unit: CGFloat(unit)), at: p, scale: CGFloat(scale), alpha: CGFloat(shieldShown * flicker))
            // A bright sweep running round the rim.
            let r = Self.shieldRadius * unit * scale
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setStrokeColor(Colours.shieldRim.cg(0.8 * shieldShown))
            ctx.setLineWidth(CGFloat(5 * unit))
            let a = CGFloat(elapsed * 2.2)
            ctx.addArc(center: p, radius: CGFloat(r - 3 * unit), startAngle: a, endAngle: a + 0.7, clockwise: false)
            ctx.strokePath()
            ctx.restoreGState()
            // How much shield is left, as an arc just outside it.
            let tone = shieldEnergy < 0.3 ? HandPlayPalette.coral : HandPlayPalette.gold
            HandPlayDraw.arc(ctx, at: p, radius: r + 14 * unit, width: 6 * unit, fraction: shieldEnergy, tone: tone, alpha: 0.9 * shieldShown)
        }
        for ripple in ripples {
            let t = ripple.age / 0.5
            HandPlayDraw.ring(ctx, at: ripple.at.handPlayPoint, radius: (12 + 70 * HandPlayEase.outCubic(t)) * unit, width: 5 * unit * (1 - t),
                              tone: Colours.shieldRim, alpha: 1 - t)
        }
        if shieldBroken {
            let r = Self.shieldRadius * unit
            HandPlayDraw.arc(ctx, at: p, radius: r + 14 * unit, width: 5 * unit, fraction: shieldEnergy / Self.shieldRestart, tone: Colours.shield,
                             alpha: 0.35)
        }
    }

    /// The spell in a palm: a turning rune circle that grows with the charge, with the fireball gathering in the middle. A fist shows a
    /// small blue charm instead.
    private func drawCaster(_ ctx: CGContext, _ caster: Caster) {
        let u = CGFloat(unit)
        let p = caster.palm
        let alpha = caster.presence
        guard alpha > 0.01 else { return }
        if caster.open {
            let k = HandPlayEase.outCubic(caster.charge)
            let recoil = 1 + 0.25 * max(0, 1 - caster.sinceCast / 0.2)
            HandPlayDraw.glow(ctx, at: p, radius: Double(110 * u) * (0.6 + 0.5 * k), tone: Colours.flame, alpha: 0.35 * alpha)
            HandPlayDraw.stamp(ctx, HandPlayMagicDuelArt.runeCircle(unit: u), at: p, scale: CGFloat(recoil), alpha: CGFloat(alpha))
            // Sparks circling the rim, quicker as the spell fills.
            for s in 0..<3 {
                let a = elapsed * (1.5 + 3 * k) + Double(s) * 2 * .pi / 3
                let q = CGPoint(x: p.x + cos(a) * 70 * unit, y: p.y + sin(a) * 70 * unit)
                HandPlayDraw.glint(ctx, at: q, radius: 9 * unit * (0.6 + 0.6 * k), alpha: alpha * (0.5 + 0.5 * k), tone: Colours.fire.lighter(0.4))
            }
            HandPlayDraw.arc(ctx, at: p, radius: Double(64 * u), width: Double(6 * u), fraction: caster.charge, tone: HandPlayPalette.gold, alpha: alpha)
            HandPlayDraw.stamp(ctx, HandPlayMagicDuelArt.fireball(unit: u), at: p, scale: CGFloat(0.25 + 0.75 * k), alpha: CGFloat(alpha * k))
            if let id = caster.target, let m = monsters.first(where: { $0.id == id && $0.isAlive }) {
                drawReticle(ctx, at: m.position.handPlayPoint, radius: m.kind.radius * unit * 1.25, alpha: alpha * (0.5 + 0.5 * k))
            }
        } else if caster.closed {
            HandPlayDraw.glow(ctx, at: p, radius: Double(70 * u), tone: Colours.shield, alpha: 0.45 * alpha)
            HandPlayDraw.ring(ctx, at: p, radius: Double(48 * u), width: Double(4 * u), tone: Colours.shieldRim, alpha: 0.8 * alpha)
        }
    }

    private func drawReticle(_ ctx: CGContext, at p: CGPoint, radius: Double, alpha: Double) {
        let spin = elapsed * 2.5
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setStrokeColor(HandPlayPalette.gold.cg(0.9 * alpha))
        ctx.setLineWidth(CGFloat(4 * unit))
        for k in 0..<4 {
            let a = spin + Double(k) * .pi / 2
            ctx.addArc(center: p, radius: CGFloat(radius), startAngle: CGFloat(a), endAngle: CGFloat(a + 0.75), clockwise: false)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private func drawFireball(_ ctx: CGContext, _ ball: Fireball) {
        let p = ball.position.handPlayPoint
        HandPlayDraw.glow(ctx, at: p, radius: Self.fireballRadius * 3.2 * unit, tone: Colours.flame, alpha: 0.55)
        let stretch = 1 + 0.25 * HandPlayEase.clamp(ball.age / 0.15)
        HandPlayDraw.stamp(ctx, HandPlayMagicDuelArt.fireball(unit: CGFloat(unit)), at: p, sx: CGFloat(stretch), sy: CGFloat(1 / stretch),
                           rotation: CGFloat(atan2(ball.velocity.y, ball.velocity.x)))
    }

    private func drawParticles(_ ctx: CGContext, behind: Bool) {
        for p in particles.particles {
            guard let bit = Bit(rawValue: p.kind) else { continue }
            let isBehind = bit == .smoke
            guard isBehind == behind else { continue }
            let t = p.progress, at = p.position.handPlayPoint
            switch bit {
            case .flame:
                let tone = t < 0.3 ? Colours.fire : t < 0.6 ? Colours.flame : t < 0.85 ? Colours.ember : Colours.soot
                HandPlayDraw.glow(ctx, at: at, radius: p.size * (1 - 0.5 * t), tone: tone, alpha: (1 - t) * 0.9)
            case .spark:
                ctx.fillCircle(center: at, radius: CGFloat(p.size * (1 - t * 0.6) * unit), color: Colours.fire.lighter(0.4).cg(1 - t))
            case .smoke:
                HandPlayDraw.glow(ctx, at: at, radius: p.size * unit * (0.8 + 1.4 * t), tone: Colours.shadowMid, alpha: 0.55 * (1 - t))
            case .dust:
                HandPlayDraw.glint(ctx, at: at, radius: p.size * unit * (1 - 0.5 * t), alpha: 1 - t, tone: Colours.aura.lighter(0.5))
            case .shard:
                ctx.fillCircle(center: at, radius: CGFloat(p.size * unit * (1 - t)), color: Colours.shieldRim.cg(1 - t))
            }
        }
    }
}

/// The baked pictures for Magic Duel.
enum HandPlayMagicDuelArt {
    typealias C = HandPlayMagicDuel.Colours
    static let frames = 4

    // MARK: Monsters

    /// A shadow monster, in one of a few frames of its rippling hem or flapping wings. `flash` gives the same shape in solid light, laid
    /// over the monster for a moment when a fireball lands.
    static func monster(_ kind: HandPlayMagicDuel.Kind, frame: Int, unit: CGFloat, flash: Bool = false) -> CGImage? {
        let r = CGFloat(kind.radius) * unit
        let side = Int(ceil(r * 3.6))
        return HandPlaySprites.image("md.monster|\(kind.rawValue)|\(frame)|\(Int(unit * 100))|\(flash)", side: side) { ctx in
            ctx.scaleBy(x: r, y: r)
            let phase = CGFloat(frame) / CGFloat(frames)
            switch kind {
            case .wisp: paintGhost(ctx, phase: phase, horns: false, flash: flash, unitPixels: r)
            case .brute: paintGhost(ctx, phase: phase, horns: true, flash: flash, unitPixels: r)
            case .bat: paintBat(ctx, phase: phase, flash: flash, unitPixels: r)
            }
        }
    }

    /// A ghost's outline: a domed head and a hem that ripples into tendrils. `phase` moves the ripples along.
    private static func ghostPath(phase: CGFloat, wide: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let half = 0.92 * wide
        path.move(to: CGPoint(x: -half, y: -0.62))
        path.addCurve(to: CGPoint(x: 0, y: 1.02), control1: CGPoint(x: -half * 1.08, y: 0.45), control2: CGPoint(x: -half * 0.62, y: 1.02))
        path.addCurve(to: CGPoint(x: half, y: -0.62), control1: CGPoint(x: half * 0.62, y: 1.02), control2: CGPoint(x: half * 1.08, y: 0.45))
        let steps = 48
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = half - 2 * half * t
            let wave = 0.5 + 0.5 * cos((3 * t + phase) * 2 * .pi)
            let taper = sin(t * .pi)
            let y = -0.62 - (0.12 + 0.3 * wave) * (0.55 + 0.45 * taper) - 0.06 * sin((5 * t - phase) * 2 * .pi)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }

    private static func paintGhost(_ ctx: CGContext, phase: CGFloat, horns: Bool, flash: Bool, unitPixels r: CGFloat) {
        let body = ghostPath(phase: phase, wide: horns ? 1.06 : 1)
        if horns {
            for s in [CGFloat(-1), 1] {
                let horn = CGMutablePath()
                horn.move(to: CGPoint(x: s * 0.32, y: 0.78))
                horn.addQuadCurve(to: CGPoint(x: s * 0.86, y: 1.42), control: CGPoint(x: s * 0.42, y: 1.32))
                horn.addQuadCurve(to: CGPoint(x: s * 0.66, y: 0.6), control: CGPoint(x: s * 0.9, y: 0.9))
                horn.closeSubpath()
                if flash {
                    ctx.addPath(horn)
                    ctx.setFillColor(HandPlayPalette.cream.cg())
                    ctx.fillPath()
                } else {
                    ctx.saveGState()
                    ctx.addPath(horn)
                    ctx.clip()
                    HandPlayDraw.fill(ctx, [(HandPlayTone(0.98, 0.9, 0.78), 1), (HandPlayTone(0.72, 0.58, 0.5), 1)], from: CGPoint(x: s * 0.4, y: 1.3),
                                      to: CGPoint(x: s * 0.7, y: 0.6))
                    ctx.restoreGState()
                    ctx.addPath(horn)
                    ctx.setStrokeColor(C.shadowDeep.cg(0.9))
                    ctx.setLineWidth(0.05)
                    ctx.strokePath()
                }
            }
        }
        if flash {
            ctx.addPath(body)
            ctx.setFillColor(HandPlayPalette.cream.cg(0.9))
            ctx.fillPath()
            return
        }
        // An aura round the edge, so a dark monster still reads on a dark room.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: r * 0.55, color: C.aura.cg(0.85))
        ctx.addPath(body)
        ctx.setFillColor(C.shadowMid.cg())
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        HandPlayDraw.fill(ctx, [(C.shadowTop, 1), (C.shadowMid, 1), (C.shadowDeep, 0.92)], from: CGPoint(x: -0.3, y: 1.0), to: CGPoint(x: 0.2, y: -1.0),
                          locations: [0, 0.5, 1])
        // Light from the top left, and a cool bounce along the right.
        HandPlayDraw.radial(ctx, [(HandPlayTone(0.78, 0.66, 1), 0.55), (C.shadowTop, 0)], center: CGPoint(x: -0.42, y: 0.55), radius: 0.85)
        HandPlayDraw.radial(ctx, [(C.aura, 0.4), (C.aura, 0)], center: CGPoint(x: 0.95, y: -0.2), radius: 0.7)
        ctx.addPath(body)
        ctx.setStrokeColor(HandPlayTone(0.85, 0.75, 1).cg(0.35))
        ctx.setLineWidth(0.09)
        ctx.strokePath()
        if horns {
            // A heavy brow and a jagged mouth.
            let brow = CGMutablePath()
            brow.move(to: CGPoint(x: -0.56, y: 0.42))
            brow.addQuadCurve(to: CGPoint(x: 0, y: 0.3), control: CGPoint(x: -0.28, y: 0.48))
            brow.addQuadCurve(to: CGPoint(x: 0.56, y: 0.42), control: CGPoint(x: 0.28, y: 0.48))
            ctx.addPath(brow)
            ctx.setStrokeColor(C.shadowDeep.cg(0.9))
            ctx.setLineWidth(0.1)
            ctx.setLineCap(.round)
            ctx.strokePath()
            let mouth = CGMutablePath()
            mouth.move(to: CGPoint(x: -0.42, y: -0.2))
            for k in 0..<7 {
                let x = -0.42 + CGFloat(k + 1) * 0.12
                mouth.addLine(to: CGPoint(x: x - 0.06, y: k % 2 == 0 ? -0.3 : -0.2))
            }
            mouth.addLine(to: CGPoint(x: 0.42, y: -0.2))
            mouth.addQuadCurve(to: CGPoint(x: -0.42, y: -0.2), control: CGPoint(x: 0, y: -0.62))
            ctx.addPath(mouth)
            ctx.setFillColor(HandPlayTone(0.04, 0.02, 0.08).cg())
            ctx.fillPath()
            for s in [CGFloat(-1), 1] {
                let fang = CGMutablePath()
                fang.move(to: CGPoint(x: s * 0.28, y: -0.22))
                fang.addLine(to: CGPoint(x: s * 0.2, y: -0.42))
                fang.addLine(to: CGPoint(x: s * 0.13, y: -0.24))
                fang.closeSubpath()
                ctx.addPath(fang)
                ctx.setFillColor(HandPlayTone(0.96, 0.92, 0.86).cg())
                ctx.fillPath()
            }
        } else {
            // A small round mouth, open in a moan.
            ctx.setFillColor(HandPlayTone(0.04, 0.02, 0.08).cg(0.9))
            ctx.fillEllipse(in: CGRect(x: -0.11, y: -0.36, width: 0.22, height: 0.26))
        }
        ctx.restoreGState()
    }

    private static func paintBat(_ ctx: CGContext, phase: CGFloat, flash: Bool, unitPixels r: CGFloat) {
        let flap = sin(phase * 2 * .pi)
        func wing(_ s: CGFloat) -> CGPath {
            let tipY = 0.55 + 0.55 * flap
            let path = CGMutablePath()
            path.move(to: CGPoint(x: s * 0.6, y: 0.3))
            path.addQuadCurve(to: CGPoint(x: s * 1.62, y: tipY), control: CGPoint(x: s * 1.1, y: 0.7 + 0.3 * flap))
            path.addQuadCurve(to: CGPoint(x: s * 1.28, y: tipY - 0.62), control: CGPoint(x: s * 1.55, y: tipY - 0.3))
            path.addQuadCurve(to: CGPoint(x: s * 0.98, y: -0.3 + 0.2 * flap), control: CGPoint(x: s * 1.2, y: -0.15 + 0.2 * flap))
            path.addQuadCurve(to: CGPoint(x: s * 0.66, y: -0.42 + 0.1 * flap), control: CGPoint(x: s * 0.86, y: -0.2 + 0.1 * flap))
            path.addQuadCurve(to: CGPoint(x: s * 0.55, y: -0.25), control: CGPoint(x: s * 0.6, y: -0.3))
            path.closeSubpath()
            return path
        }
        let body = CGMutablePath()
        body.addEllipse(in: CGRect(x: -0.72, y: -0.7, width: 1.44, height: 1.4))
        for s in [CGFloat(-1), 1] {
            body.move(to: CGPoint(x: s * 0.2, y: 0.55))
            body.addLine(to: CGPoint(x: s * 0.62, y: 1.18))
            body.addLine(to: CGPoint(x: s * 0.66, y: 0.42))
            body.closeSubpath()
        }
        if flash {
            for s in [CGFloat(-1), 1] { ctx.addPath(wing(s)) }
            ctx.addPath(body)
            ctx.setFillColor(HandPlayPalette.cream.cg(0.9))
            ctx.fillPath()
            return
        }
        for s in [CGFloat(-1), 1] {
            let path = wing(s)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: r * 0.4, color: C.aura.cg(0.7))
            ctx.addPath(path)
            ctx.setFillColor(C.shadowDeep.cg())
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            HandPlayDraw.fill(ctx, [(C.shadowTop, 1), (C.shadowDeep, 1)], from: CGPoint(x: s * 0.8, y: 1.0), to: CGPoint(x: s * 1.2, y: -0.5))
            // The bones of the wing.
            ctx.setStrokeColor(HandPlayTone(0.62, 0.5, 0.9).cg(0.55))
            ctx.setLineWidth(0.05)
            ctx.setLineCap(.round)
            for (x, y) in [(1.28, 0.55 + 0.55 * flap - 0.62), (0.98, -0.3 + 0.2 * flap)] as [(CGFloat, CGFloat)] {
                ctx.move(to: CGPoint(x: s * 0.62, y: 0.28))
                ctx.addLine(to: CGPoint(x: s * x, y: y))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: r * 0.5, color: C.aura.cg(0.85))
        ctx.addPath(body)
        ctx.setFillColor(C.shadowMid.cg())
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        HandPlayDraw.fill(ctx, [(C.shadowTop, 1), (C.shadowMid, 1), (C.shadowDeep, 1)], from: CGPoint(x: -0.3, y: 1.1), to: CGPoint(x: 0.3, y: -0.7),
                          locations: [0, 0.5, 1])
        HandPlayDraw.radial(ctx, [(HandPlayTone(0.78, 0.66, 1), 0.5), (C.shadowTop, 0)], center: CGPoint(x: -0.35, y: 0.42), radius: 0.7)
        ctx.restoreGState()
        // Two tiny fangs.
        for s in [CGFloat(-1), 1] {
            let fang = CGMutablePath()
            fang.move(to: CGPoint(x: s * 0.16, y: -0.3))
            fang.addLine(to: CGPoint(x: s * 0.1, y: -0.48))
            fang.addLine(to: CGPoint(x: s * 0.04, y: -0.3))
            fang.closeSubpath()
            ctx.addPath(fang)
            ctx.setFillColor(HandPlayTone(0.96, 0.92, 0.86).cg())
            ctx.fillPath()
        }
    }

    // MARK: Spells

    /// A ball of fire: white-hot in the middle, through gold and orange to a soft edge.
    static func fireball(unit: CGFloat) -> CGImage? {
        let r = CGFloat(HandPlayMagicDuel.fireballRadius) * unit
        let side = Int(ceil(r * 3))
        return HandPlaySprites.image("md.fireball|\(Int(unit * 100))", side: side) { ctx in
            HandPlayDraw.radial(ctx, [(C.fireCore, 1), (C.fireCore, 1), (C.fire, 1), (C.flame, 0.9), (C.ember, 0.45), (C.ember, 0)], center: .zero,
                                radius: r * 1.45, from: CGPoint(x: -r * 0.2, y: r * 0.2), locations: [0, 0.22, 0.42, 0.6, 0.8, 1])
        }
    }

    /// A hex: a dark orb with a hot violet rim and a pale swirl.
    static func hexOrb(unit: CGFloat) -> CGImage? {
        let r = CGFloat(HandPlayMagicDuel.hexRadius) * unit
        let side = Int(ceil(r * 3.2))
        return HandPlaySprites.image("md.hex|\(Int(unit * 100))", side: side) { ctx in
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: r * 0.8, color: C.hex.cg(0.9))
            ctx.fillCircle(center: .zero, radius: r, color: HandPlayTone(0.14, 0.04, 0.2).cg())
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            ctx.clip()
            HandPlayDraw.radial(ctx, [(HandPlayTone(0.12, 0.02, 0.18), 1), (HandPlayTone(0.3, 0.06, 0.4), 1), (C.hex, 1)], center: .zero, radius: r,
                                locations: [0, 0.65, 1])
            ctx.setStrokeColor(HandPlayTone(1, 0.75, 1).cg(0.85))
            ctx.setLineWidth(r * 0.14)
            ctx.setLineCap(.round)
            ctx.addArc(center: .zero, radius: r * 0.55, startAngle: 0.3, endAngle: 2.4, clockwise: false)
            ctx.strokePath()
            ctx.addArc(center: .zero, radius: r * 0.3, startAngle: 3.4, endAngle: 5.2, clockwise: false)
            ctx.strokePath()
            ctx.restoreGState()
            ctx.fillCircle(center: CGPoint(x: -r * 0.35, y: r * 0.4), radius: r * 0.16, color: HandPlayTone(1, 0.9, 1).cg(0.8))
        }
    }

    /// The rune circle that turns in a casting palm.
    static func runeCircle(unit: CGFloat) -> CGImage? {
        let r = 70 * unit
        let side = Int(ceil(r * 2.4))
        return HandPlaySprites.image("md.runes|\(Int(unit * 100))", side: side) { ctx in
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: r * 0.12, color: C.flame.cg(0.9))
            ctx.setStrokeColor(C.fire.cg(0.95))
            ctx.setLineWidth(r * 0.05)
            ctx.strokeEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            ctx.setLineWidth(r * 0.025)
            ctx.strokeEllipse(in: CGRect(x: -r * 0.84, y: -r * 0.84, width: r * 1.68, height: r * 1.68))
            // A six-pointed star of two triangles.
            for flip in [CGFloat(0), .pi] {
                let tri = CGMutablePath()
                for k in 0..<3 {
                    let a = flip + .pi / 2 + CGFloat(k) * 2 * .pi / 3
                    let p = CGPoint(x: cos(a) * r * 0.84, y: sin(a) * r * 0.84)
                    if k == 0 { tri.move(to: p) } else { tri.addLine(to: p) }
                }
                tri.closeSubpath()
                ctx.addPath(tri)
                ctx.setStrokeColor(C.flame.cg(0.7))
                ctx.setLineWidth(r * 0.02)
                ctx.strokePath()
            }
            // Rune marks between the two rings.
            ctx.setFillColor(C.fire.lighter(0.3).cg())
            for k in 0..<12 {
                let a = CGFloat(k) * .pi / 6
                ctx.saveGState()
                ctx.translateBy(x: cos(a) * r * 0.92, y: sin(a) * r * 0.92)
                ctx.rotate(by: a)
                let w = r * (k % 3 == 0 ? 0.09 : 0.05)
                ctx.fill(CGRect(x: -w / 2, y: -r * 0.035, width: w, height: r * 0.07))
                ctx.restoreGState()
            }
            ctx.restoreGState()
        }
    }

    /// The shield round you: a glassy bubble with a honeycomb in it and a bright rim, lit from the top left.
    static func shield(unit: CGFloat) -> CGImage? {
        let r = CGFloat(HandPlayMagicDuel.shieldRadius) * unit
        let side = Int(ceil(r * 2.3))
        return HandPlaySprites.image("md.shield|\(Int(unit * 100))", side: side) { ctx in
            let disc = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
            ctx.saveGState()
            ctx.addEllipse(in: disc)
            ctx.clip()
            HandPlayDraw.radial(ctx, [(C.shield, 0.04), (C.shield, 0.1), (C.shield, 0.34)], center: .zero, radius: r, locations: [0, 0.6, 1])
            // The honeycomb.
            let cell = r * 0.17
            let hexW = cell * sqrt(3)
            ctx.setStrokeColor(C.shieldRim.cg(0.16))
            ctx.setLineWidth(max(1, r * 0.008))
            var row = 0
            var y = -r
            while y < r + cell {
                var x = -r + (row % 2 == 0 ? 0 : hexW / 2)
                while x < r + hexW {
                    let path = CGMutablePath()
                    for k in 0..<6 {
                        let a = CGFloat.pi / 6 + CGFloat(k) * .pi / 3
                        let p = CGPoint(x: x + cos(a) * cell, y: y + sin(a) * cell)
                        if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath()
                    ctx.addPath(path)
                    x += hexW
                }
                ctx.strokePath()
                y += cell * 1.5
                row += 1
            }
            HandPlayDraw.radial(ctx, [(HandPlayPalette.cream, 0.3), (HandPlayPalette.cream, 0)], center: CGPoint(x: -r * 0.45, y: r * 0.5), radius: r * 0.55)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: r * 0.08, color: C.shield.cg(0.9))
            ctx.setStrokeColor(C.shieldRim.cg(0.9))
            ctx.setLineWidth(r * 0.018)
            ctx.strokeEllipse(in: disc.insetBy(dx: r * 0.01, dy: r * 0.01))
            ctx.restoreGState()
            ctx.setStrokeColor(HandPlayPalette.cream.cg(0.75))
            ctx.setLineWidth(r * 0.03)
            ctx.setLineCap(.round)
            ctx.addArc(center: .zero, radius: r * 0.9, startAngle: 1.95, endAngle: 2.75, clockwise: false)
            ctx.strokePath()
        }
    }
}
