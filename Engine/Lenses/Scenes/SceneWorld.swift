import CoreGraphics
import Foundation
import simd

/// The scenes' source of chance: seeded, so a scene plays out the same way every time it is given the same seed and the same view.
struct SceneRandom: RandomNumberGenerator {
    private var base: SplitMix64

    init(seed: UInt64) { base = SplitMix64(seed: seed) }

    mutating func next() -> UInt64 { base.next() }
    /// 0 up to, but not including, 1.
    mutating func unit() -> Double { Double.random(in: 0..<1, using: &self) }
    mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
    /// -1 or 1.
    mutating func sign() -> Double { chance(0.5) ? 1 : -1 }
}

/// An open hand held up, which birds and butterflies like to land on.
struct SceneOffer: Equatable {
    var point: CGPoint
    var handID: Int
}

/// The numbers that decide when animals take an interest and when they bolt.
enum SceneTuning {
    /// How much arm-waving, near an animal, scares it (a count of lattice points that moved).
    static let scareLevel = 9.0
    /// How close the waving has to be, in pixels.
    static let scareRadius = 420.0
    /// Waving this big, anywhere, scatters everything.
    static let scatterLevel = 26.0
    /// How long somebody has to be in view before the animals notice them. Their moving about, while they step into the picture and
    /// settle down, does not count as waving.
    static let settleSeconds = 0.8
    static let arrivalSeconds = 1.3
    /// At most this many animals are busy with you at once.
    static let busyLimit = 2
    /// Spacing of the lattice the motion is read on.
    static let motionStep = 32.0
}

/// A living scene with no drawing in it: a handful of animals that wander, notice you, come after you, do their thing,
/// and run off when you wave. Stepped with a time and what the camera sees; given the same seed and the same inputs it
/// always does the same.
struct SceneWorld {
    let cast: SceneCast
    private(set) var creatures: [SceneCreature] = []
    /// Dust, water and bubbles that go in front of the person, and behind them.
    private(set) var effects = ParticleSystem(capacity: 360)
    private(set) var effectsBehind = ParticleSystem(capacity: 160)
    private(set) var time = 0.0
    /// How hard the picture is shaking, in pixels. Dies away on its own.
    private(set) var shake = 0.0
    /// The person, smoothed, or nil when nobody has been there for a moment.
    private(set) var person: ScenePerson?
    private(set) var personSeenFor = 0.0
    private(set) var offer: SceneOffer?
    /// How much of the silhouette is moving, overall: a count of lattice points.
    private(set) var motionEnergy = 0.0
    private var personAbsentFor = 0.0
    private var offerLostFor = 0.0
    private var moving: [SIMD3<Double>] = []
    /// The silhouette, only while a step is under way.
    private var matte: MatteQuery?
    private var rng: SceneRandom

    var layout: SceneLayout { cast.layout }
    var size: CGSize { cast.layout.size }

    init(cast: SceneCast, seed: UInt64) {
        self.cast = cast
        rng = SceneRandom(seed: seed)
        var order = Array(cast.roster.indices)
        for i in order.indices.reversed() { order.swapAt(i, Int(rng.unit() * Double(i + 1))) }
        let visible = Set(order.prefix(min(cast.visibleAtStart, cast.cap)))
        // The one that notices you first: a visible animal that does something worth seeing.
        let greeter = order.first { visible.contains($0) && cast.species[cast.roster[$0]].interest >= 1 && !cast.species[cast.roster[$0]].farOnly
            && cast.species[cast.roster[$0]].act != .orbit && cast.species[cast.roster[$0]].act != .drop }

        var slot = 0
        for (i, s) in cast.roster.enumerated() {
            var c = SceneCreature(id: i, species: s)
            let sp = cast.species[s]
            c.quirk = rng.unit()
            c.depth = Self.homeDepth(sp, cast.layout, quirk: c.quirk)
            c.cooldown = rng.range(6, 16) / max(0.3, sp.interest)
            c.side = rng.sign()
            if visible.contains(i) {
                // Spread the first ones across the picture so it is alive from the first frame.
                let x = size.width * (0.12 + 0.76 * (Double(slot) + rng.range(0.1, 0.9)) / Double(max(1, visible.count)))
                slot += 1
                place(&c, sp, x: x)
                c.phase = .wandering
                c.wait = rng.range(0.2, 2.5)
            } else {
                c.phase = .away
                c.wait = rng.range(3, 12)
            }
            if i == greeter { c.cooldown = 0.9 }
            creatures.append(c)
        }
    }

    // MARK: Stepping

    /// Advances the world. A long stall is taken in small steps so nothing leaps through anything.
    mutating func step(_ dt: Double, context: SceneContext) {
        var left = min(max(0, dt), 0.5)
        while left > 1e-6 {
            let h = min(left, 1.0 / 30)
            left -= h
            advance(h, context)
        }
    }

    private mutating func advance(_ dt: Double, _ ctx: SceneContext) {
        time += dt
        matte = ctx.matte
        defer { matte = nil }
        sensePerson(ctx, dt)
        senseHands(ctx, dt)
        senseMotion(ctx, dt)
        for i in creatures.indices {
            var c = creatures[i]
            update(&c, dt, ctx)
            creatures[i] = c
        }
        effects.step(dt, adjust: { Self.adjust(&$0, dt) })
        effectsBehind.step(dt, adjust: { Self.adjust(&$0, dt) })
        shake *= exp(-dt * 7)
        if shake < 0.05 { shake = 0 }
    }

    // MARK: Senses

    private mutating func sensePerson(_ ctx: SceneContext, _ dt: Double) {
        if let seen = ctx.person {
            if var old = person {
                let k = 1 - exp(-dt * 10)
                old.box = CGRect(x: old.box.minX + (seen.box.minX - old.box.minX) * k, y: old.box.minY + (seen.box.minY - old.box.minY) * k,
                                 width: old.box.width + (seen.box.width - old.box.width) * k, height: old.box.height + (seen.box.height - old.box.height) * k)
                old.head = CGPoint(x: old.head.x + (seen.head.x - old.head.x) * k, y: old.head.y + (seen.head.y - old.head.y) * k)
                old.headRadius += (seen.headRadius - old.headRadius) * k
                person = old
            } else {
                person = seen
            }
            personSeenFor += dt
            personAbsentFor = 0
        } else {
            personAbsentFor += dt
            if personAbsentFor > SceneTuning.settleSeconds { person = nil; personSeenFor = 0 }
        }
    }

    private mutating func senseHands(_ ctx: SceneContext, _ dt: Double) {
        var found: SceneOffer?
        for hand in ctx.hands where hand.pose == .openPalm && hand.size >= 22 {
            let tip = hand[.middleTip], knuckle = hand[.middleMCP]
            // Held up or out, not hanging down, and held still enough to land on.
            guard tip.y >= hand.wrist.y - hand.size * 0.3, hypot(hand.velocity.dx, hand.velocity.dy) < 450 else { continue }
            found = SceneOffer(point: CGPoint(x: knuckle.x + (tip.x - knuckle.x) * 0.55, y: knuckle.y + (tip.y - knuckle.y) * 0.55), handID: hand.id)
            break
        }
        if let found {
            offer = found
            offerLostFor = 0
        } else {
            offerLostFor += dt
            if offerLostFor > 0.7 { offer = nil }
        }
    }

    private mutating func senseMotion(_ ctx: SceneContext, _ dt: Double) {
        moving.removeAll(keepingCapacity: true)
        var total = 0.0
        if let motion = ctx.motion, personSeenFor > SceneTuning.arrivalSeconds, let box = person?.box.insetBy(dx: -90, dy: -90) {
            let s = SceneTuning.motionStep
            var y = (floor(max(0, box.minY) / s) + 0.5) * s
            while y < min(size.height, box.maxY) {
                var x = (floor(max(0, box.minX) / s) + 0.5) * s
                while x < min(size.width, box.maxX) {
                    let v = motion.coverage(x: x, y: y)
                    if v > 0.4 { moving.append(SIMD3(x, y, v)); total += v }
                    x += s
                }
                y += s
            }
        }
        motionEnergy += (total - motionEnergy) * min(1, dt / 0.12)
    }

    /// How much is moving within `radius` of a point.
    private func movement(near p: SIMD2<Double>, radius: Double) -> (energy: Double, centre: Double) {
        var energy = 0.0, x = 0.0
        for m in moving where simd_distance(SIMD2(m.x, m.y), p) < radius { energy += m.z; x += m.x * m.z }
        return (energy, energy > 0 ? x / energy : p.x)
    }

    /// For tests and previews: makes one creature notice the person now, as if its time had come.
    mutating func attract(_ id: Int) {
        guard creatures.indices.contains(id), person != nil else { return }
        creatures[id].cooldown = 0
        if creatures[id].phase == .away { creatures[id].wait = 0 }
    }

    /// For tests and previews: puts a creature at rest in its lane, as if it had just stopped there.
    mutating func stage(_ id: Int, x: Double, depth: Double? = nil) {
        guard creatures.indices.contains(id) else { return }
        var c = creatures[id]
        let sp = cast.species[c.species]
        c.phase = .wandering
        c.phaseTime = 0
        c.pos.x = x
        c.depth = depth ?? c.depth
        if sp.body == .walker { c.pos.y = layout.ground(c.depth) }
        c.wait = 600
        c.cooldown = 600
        c.vel = .zero
        c.target = SIMD2(x, sp.body == .walker ? 0 : c.pos.y)
        c.leaving = false
        creatures[id] = c
    }

    // MARK: Geometry

    /// The size of one animal as it is drawn.
    func spriteHeight(_ c: SceneCreature) -> Double { cast.species[c.species].height * layout.scale(c.depth) }
    func spriteWidth(_ c: SceneCreature) -> Double { spriteHeight(c) * cast.species[c.species].aspect }
    /// The room it takes up: a school of fish is a good deal bigger than any one fish in it.
    func height(_ c: SceneCreature) -> Double { spriteHeight(c) * (cast.species[c.species].group > 1 ? 2.2 : 1) }
    func width(_ c: SceneCreature) -> Double { spriteWidth(c) * (cast.species[c.species].group > 1 ? 2.8 : 1) }

    /// The rectangle a creature fills on the screen, standing. (Fliers and swimmers are centred on `pos`.)
    func bounds(of c: SceneCreature) -> CGRect {
        let h = height(c), w = width(c)
        if cast.species[c.species].isGroundBound {
            return CGRect(x: c.pos.x - w / 2, y: c.pos.y + c.lift, width: w, height: h)
        }
        return CGRect(x: c.pos.x - w / 2, y: c.pos.y - h / 2, width: w, height: h)
    }

    private static func homeDepth(_ sp: SceneSpecies, _ layout: SceneLayout, quirk: Double) -> Double {
        sp.home + (quirk - 0.5) * 0.05
    }

    private var busy: Int {
        creatures.filter { $0.phase == .noticing || $0.phase == .approaching || $0.phase == .acting }.count
    }

    private var onScreen: Int { creatures.filter { $0.phase != .away }.count }

    private func onScreenWidth(of c: SceneCreature) -> Bool {
        c.pos.x > -width(c) * 0.3 && c.pos.x < size.width + width(c) * 0.3
    }

    /// Puts a creature somewhere in its home lane.
    private mutating func place(_ c: inout SceneCreature, _ sp: SceneSpecies, x: Double) {
        c.pos.x = x
        c.depth = Self.homeDepth(sp, layout, quirk: c.quirk)
        switch sp.body {
        case .walker:
            c.pos.y = layout.ground(c.depth)
        case .soarer:
            c.origin = SIMD2(x, layout.roamHigh - 40 + rng.range(-30, 30))
            c.stride = rng.range(0, 2 * .pi)
            c.pos = c.origin
        case .flier, .swimmer, .floater:
            c.pos.y = rng.range(sp.band?.lowerBound ?? layout.roamLow, sp.band?.upperBound ?? layout.roamHigh)
        }
        c.dir = rng.sign()
        c.turn = c.dir
        c.target = SIMD2(x, c.pos.y)
        pickWanderTarget(&c, sp)
    }

    // MARK: One creature

    private mutating func update(_ c: inout SceneCreature, _ dt: Double, _ ctx: SceneContext) {
        let sp = cast.species[c.species]
        c.phaseTime += dt
        c.cooldown = max(0, c.cooldown - dt)
        if var bubble = c.bubble {
            bubble.age += dt
            c.bubble = bubble.age >= bubble.life ? nil : bubble
        }
        c.turn += (c.dir - c.turn) * min(1, dt * 9)

        if c.phase == .away {
            c.wait -= dt
            if c.wait <= 0, onScreen < cast.cap { enter(&c, sp) }
            return
        }

        feel(&c, sp, dt)

        switch c.phase {
        case .away: break
        case .entering, .wandering: wander(&c, sp, dt)
        case .noticing: notice(&c, sp, dt)
        case .approaching: approach(&c, sp, dt)
        case .acting: act(&c, sp, dt)
        case .retreating: retreat(&c, sp, dt)
        case .fleeing: flee(&c, sp, dt)
        case .backingOff: backOff(&c, sp, dt)
        }

        if sp.isGroundBound { c.pos.y = layout.ground(c.depth) }
        if c.lift > 0, !(c.phase == .acting && (sp.act == .climb || sp.act == .perch)) {
            c.vel.y -= 1500 * dt
            c.lift = max(0, c.lift + c.vel.y * dt)
            if c.lift == 0 { c.vel.y = 0 }
        }
        keepClear(&c, sp)
    }

    private mutating func enter(_ c: inout SceneCreature, _ sp: SceneSpecies) {
        let side = c.id % 2 == 0 ? 1.0 : -1.0
        let from = rng.chance(0.5) ? side : -side
        c.depth = Self.homeDepth(sp, layout, quirk: c.quirk)
        let w = width(c)
        c.pos.x = from < 0 ? -w * 0.6 : size.width + w * 0.6
        switch sp.body {
        case .walker: c.pos.y = layout.ground(c.depth)
        case .soarer:
            c.origin = SIMD2(size.width * rng.range(0.3, 0.7), layout.roamHigh - 40 + rng.range(-30, 30))
            c.stride = from < 0 ? .pi : 0
            c.pos = SIMD2(c.pos.x, c.origin.y)
        default: c.pos.y = rng.range(sp.band?.lowerBound ?? layout.roamLow, sp.band?.upperBound ?? layout.roamHigh)
        }
        c.dir = -from
        c.turn = c.dir
        c.lift = 0
        c.phase = .entering
        c.phaseTime = 0
        c.wait = 0
        c.leaving = false
        c.target = SIMD2(size.width * rng.range(0.15, 0.85), sp.isGroundBound ? 0 : c.pos.y)
        c.cooldown = max(c.cooldown, rng.range(2, 6))
    }

    // MARK: Being scared

    private mutating func feel(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double) {
        guard c.phase != .fleeing, c.phase != .backingOff, c.phase != .entering else { c.fear = 0; return }
        let centre = sp.isGroundBound ? SIMD2(c.pos.x, c.pos.y + c.lift + height(c) / 2) : c.pos
        let near = movement(near: centre, radius: SceneTuning.scareRadius + height(c) * 0.4)
        c.fear += (near.energy - c.fear) * min(1, dt / 0.1)
        let scattered = motionEnergy > SceneTuning.scatterLevel && onScreenWidth(of: c)
        guard c.fear > SceneTuning.scareLevel || scattered else { return }
        c.fear = 0
        startle(&c, sp, awayFrom: scattered ? (person.map { Double($0.box.midX) } ?? near.centre) : near.centre)
    }

    private mutating func startle(_ c: inout SceneCreature, _ sp: SceneSpecies, awayFrom x: Double) {
        c.phaseTime = 0
        c.landedAt = nil
        let away = c.pos.x == x ? c.dir : (c.pos.x > x ? 1.0 : -1.0)
        c.side = away
        switch sp.temper {
        case .brute:
            c.phase = .backingOff
            say(&c, "?!", life: 1.0)
            c.dir = -away                  // keeps its eyes on you
            c.vel.y = 260
            c.lift = c.lift > 0 ? c.lift : 0.01
        case .prey, .curious:
            c.phase = .fleeing
            say(&c, "!!", life: 1.1)
            c.dir = away
            c.vel.y = c.lift > 0 ? 0 : 340
            c.lift = max(c.lift, 0.01)
            let w = width(c)
            c.target = SIMD2(away > 0 ? size.width + w : -w, sp.isGroundBound ? 0 : c.pos.y + rng.range(40, 160))
        }
        dust(&c, count: 5, strength: 0.6)
    }

    // MARK: Wandering

    private mutating func wander(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double) {
        let scale = layout.scale(c.depth)
        switch sp.body {
        case .walker:
            if c.wait > 0 {
                c.wait -= dt
                c.vel.x = 0
                if c.wait <= 0 { pickWanderTarget(&c, sp) }
            } else {
                let arrived = walk(&c, sp, toward: c.target.x, speed: sp.speed * scale, dt: dt)
                if arrived {
                    c.beats += 1
                    if c.leaving {                              // it was heading for the edge
                        c.leaving = false
                        c.phase = .away
                        c.wait = rng.range(5, 12)
                        return
                    }
                    c.phase = .wandering
                    c.wait = rng.range(1.2, 4.5) * (sp.gait == .hop ? 0.6 : 1)
                    // Every so often an animal wanders off the edge and another comes in, and sooner if one is waiting for room.
                    let crowded = creatures.contains { $0.phase == .away && $0.wait <= 0 }
                    if (c.beats % 4 == 3 && rng.chance(0.4)) || (crowded && c.beats >= 2 && rng.chance(0.7)) { leaveByTheNearestEdge(&c) }
                }
            }
        case .soarer:
            let rx = 250 + c.quirk * 170, ry = 32 + c.quirk * 26
            let omega = sp.speed / rx
            c.stride += omega * dt
            c.origin.x += sin(time * 0.07 + c.quirk * 6) * 6 * dt
            let old = c.pos
            c.pos = SIMD2(c.origin.x + rx * cos(c.stride), c.origin.y + ry * sin(c.stride) + sin(time * 0.9 + c.quirk * 9) * 6)
            c.dir = c.pos.x - old.x >= 0 ? 1 : -1
            if c.phase == .entering, c.pos.x > 40, c.pos.x < size.width - 40 { c.phase = .wandering }
        case .flier, .swimmer, .floater:
            let speed = sp.speed * (sp.body == .flier ? 1 : 0.8)
            c.wait -= dt
            let toTarget = c.target - c.pos
            if simd_length(toTarget) < 30 || c.wait <= 0 { pickWanderTarget(&c, sp) }
            seek(&c, toward: c.target, speed: speed, dt: dt, sharpness: sp.body == .flier ? 2.6 : 1.6)
            if c.phase == .entering, c.pos.x > 30, c.pos.x < size.width - 30 { c.phase = .wandering }
            if c.beats > 6, c.pos.x < -width(c) || c.pos.x > size.width + width(c) { c.phase = .away; c.wait = rng.range(5, 10); c.beats = 0 }
        }
        if c.phase == .entering, sp.body == .walker, c.pos.x > 0, c.pos.x < size.width { c.phase = .wandering }
        considerNoticing(&c, sp)
    }

    private mutating func leaveByTheNearestEdge(_ c: inout SceneCreature) {
        c.target.x = c.pos.x < size.width / 2 ? -width(c) * 0.8 : size.width + width(c) * 0.8
        c.leaving = true
    }

    private mutating func pickWanderTarget(_ c: inout SceneCreature, _ sp: SceneSpecies) {
        switch sp.body {
        case .walker:
            // Somewhere new: not on top of another animal in the same lane, and not hidden behind the person.
            var best = c.pos.x, bestScore = -Double.infinity
            for _ in 0..<8 {
                let x = size.width * rng.range(0.07, 0.93)
                var score = min(abs(x - c.pos.x), 320)
                for other in creatures where other.id != c.id && other.phase != .away && cast.species[other.species].isGroundBound && abs(other.depth - c.depth) < 0.3 {
                    let room = (width(c) + width(other)) * 0.5 + 30
                    for spot in [other.pos.x, other.target.x] where abs(x - spot) < room { score -= (room - abs(x - spot)) * 2 }
                }
                if let person, c.depth < layout.frontDepth, x > person.box.minX + 60, x < person.box.maxX - 60 { score -= 150 }
                if score > bestScore { best = x; bestScore = score }
            }
            c.target = SIMD2(best, 0)
        case .soarer:
            break
        case .flier:
            c.target = freeTarget(for: c, sp)
            c.wait = sp.speed > 150 ? rng.range(0.5, 1.4) : rng.range(1.5, 3.5)
        case .swimmer, .floater:
            c.target = freeTarget(for: c, sp)
            c.wait = rng.range(3, 7)
        }
    }

    /// Somewhere new for a flier or swimmer to head. In front of the person it must be a trip that does not go through their face.
    private mutating func freeTarget(for c: SceneCreature, _ sp: SceneSpecies) -> SIMD2<Double> {
        let low = sp.band?.lowerBound ?? layout.roamLow, high = sp.band?.upperBound ?? layout.roamHigh
        var target = SIMD2(size.width * rng.range(-0.05, 1.05), rng.range(low, high))
        guard c.depth >= layout.frontDepth, let person else { return target }
        let zone = person.faceZone.insetBy(dx: -4, dy: -4)
        let w = width(c), h = height(c)
        for _ in 0..<10 {
            var clear = true
            for k in 0...8 {
                let p = c.pos + (target - c.pos) * (Double(k) / 8)
                if CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h).intersects(zone) { clear = false; break }
            }
            if clear { return target }
            target = SIMD2(size.width * rng.range(-0.05, 1.05), rng.range(low, high))
        }
        return c.pos
    }

    // MARK: Moving

    /// Walks along the ground toward `x`. Returns true once it is there.
    private mutating func walk(_ c: inout SceneCreature, _ sp: SceneSpecies, toward x: Double, speed: Double, dt: Double, keepFacing: Bool = false) -> Bool {
        let dx = x - c.pos.x
        if abs(dx) < 3 { c.vel.x = 0; return true }
        let heading = dx > 0 ? 1.0 : -1.0
        if !keepFacing { c.dir = heading }
        var pace = speed
        switch sp.gait {
        case .hop:
            // Hops: it only travels while it is in the air.
            let air = max(0, sin(c.stride))
            pace = speed * 1.9 * air
            c.stride += dt * 6.5
        case .walk, .slither:
            c.stride += abs(speed) * dt / max(14, height(c) * 0.42) * 2 * .pi / 2
        }
        let move = min(abs(dx), pace * dt)
        c.pos.x += heading * move
        c.vel.x = heading * pace
        return false
    }

    /// Flies or swims toward a point, easing into the speed.
    private mutating func seek(_ c: inout SceneCreature, toward p: SIMD2<Double>, speed: Double, dt: Double, sharpness: Double) {
        let delta = p - c.pos
        let distance = simd_length(delta)
        let wanted = distance > 1 ? delta / distance * min(speed, distance * 3 + 30) : .zero
        c.vel += (wanted - c.vel) * min(1, dt * sharpness)
        c.pos += c.vel * dt
        if abs(c.vel.x) > 12 { c.dir = c.vel.x > 0 ? 1 : -1 }
        c.stride += dt * 9
    }

    // MARK: Noticing

    private mutating func considerNoticing(_ c: inout SceneCreature, _ sp: SceneSpecies) {
        guard c.phase == .wandering, let person, personSeenFor > SceneTuning.settleSeconds, busy < SceneTuning.busyLimit,
              onScreenWidth(of: c), !c.leaving else { return }
        // One bird to a hand.
        let handTaken = creatures.contains { $0.id != c.id && $0.onHand && ($0.phase == .noticing || $0.phase == .approaching || $0.phase == .acting) }
        let wantsHand = sp.perchesOnHand && offer != nil && !handTaken
        guard c.cooldown <= 0 || (wantsHand && c.cooldown < 9) else { return }
        c.phase = .noticing
        c.phaseTime = 0
        c.onHand = wantsHand
        c.dir = person.box.midX >= c.pos.x ? 1 : -1
        c.vel.x = 0
        c.vel.y = 240
        c.lift = sp.isGroundBound ? 0.01 : 0
        say(&c, "!", life: 0.95)
    }

    private mutating func notice(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double) {
        guard let person else { giveUp(&c, sp); return }
        if sp.body != .walker { hover(&c, sp, dt) }
        c.dir = person.box.midX >= c.pos.x ? 1 : -1
        if c.phaseTime >= 0.85 {
            c.phase = .approaching
            c.phaseTime = 0
            c.origin = c.pos
            c.side = chooseSide(for: c, sp, person)
        }
    }

    /// Stays roughly where it is, bobbing: for fliers and swimmers while they look at you.
    private mutating func hover(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double) {
        c.vel *= exp(-dt * 4)
        c.pos += c.vel * dt
        c.stride += dt * 8
    }

    private mutating func giveUp(_ c: inout SceneCreature, _ sp: SceneSpecies) {
        c.phase = .wandering
        c.phaseTime = 0
        c.wait = rng.range(0.5, 2)
        c.cooldown = rng.range(6, 12)
        c.onHand = false
        c.landedAt = nil
        c.leaving = false
        if sp.body == .walker { pickWanderTarget(&c, sp) }
        if c.depth > layout.frontDepth - 0.01 || c.lift > 0 { c.phase = .retreating; c.target = sp.body == .walker ? SIMD2(c.pos.x, 0) : c.pos }
    }

    // MARK: Coming after you

    /// Which side of the person it should go to: the side it is on, unless another animal already has that one.
    private func chooseSide(for c: SceneCreature, _ sp: SceneSpecies, _ person: ScenePerson) -> Double {
        var side = c.pos.x >= person.box.midX ? 1.0 : -1.0
        let taken = creatures.first { other in
            other.id != c.id && (other.phase == .approaching || other.phase == .acting) && other.side == side
        }
        if taken != nil { side = -side }
        // If there is no room on that side, use the other.
        let w = sp.height * sp.aspect * layout.scale(layout.nearDepth)
        if side < 0, person.box.minX < w * 0.5 + 40 { side = 1 }
        if side > 0, person.box.maxX > size.width - w * 0.5 - 40 { side = -1 }
        return side
    }

    /// Where a walker comes to rest to do its thing: beside the person, in the near lane, with its whole body clear of the silhouette.
    private func standingSpot(for c: SceneCreature, _ sp: SceneSpecies, _ person: ScenePerson) -> (x: Double, depth: Double) {
        let depth = sp.farOnly ? sp.home : layout.nearDepth
        let w = sp.height * layout.scale(depth) * sp.aspect
        let x = c.side < 0 ? person.box.minX - w / 2 - 24 : person.box.maxX + w / 2 + 24
        if x >= w * 0.34, x <= size.width - w * 0.34 { return (x, depth) }
        // No room beside them (they fill the picture): peek out from behind them, at the edge.
        let edge = c.side < 0 ? w * 0.3 : size.width - w * 0.3
        return (edge, min(depth, layout.frontDepth - 0.04))
    }

    /// Where a flier or swimmer heads for before it starts its act.
    private func flyingSpot(for c: SceneCreature, _ sp: SceneSpecies, _ person: ScenePerson) -> SIMD2<Double> {
        let w = sp.height * sp.aspect * layout.scale(0.8)
        switch sp.act {
        case .perch:
            return perchCircle(for: c, person)
        case .orbit, .lunge:
            let ring = ringShape(for: c, sp, person)
            let angle = atan2((c.pos.y - ring.centre.y) / ring.ry, (c.pos.x - ring.centre.x) / ring.rx)
            return SIMD2(ring.centre.x + ring.rx * cos(angle), ring.centre.y + ring.ry * sin(angle))
        case .drop:
            return SIMD2(person.head.x + c.side * (person.headRadius * 1.12 + 10 + w), size.height - 30)
        default:
            let x = person.head.x + c.side * (person.headRadius * 1.12 + 10 + w / 2 + 30)
            return SIMD2(min(max(x, w * 0.3), size.width - w * 0.3), person.head.y + person.headRadius * 0.2)
        }
    }

    /// How high the silhouette reaches at a column: read off the matte when there is one.
    private func silhouetteTop(at x: Double, _ person: ScenePerson) -> Double {
        guard let matte else { return person.estimatedTop(at: x) }
        var y = min(size.height - 1, person.top + 6)
        while y > person.box.minY {
            if matte.coverage(x: x, y: y) > 0.5 { return y }
            y -= 5
        }
        return person.estimatedTop(at: x)
    }

    private func perchSeat(for c: SceneCreature, _ person: ScenePerson) -> SIMD2<Double> {
        if c.onHand, let offer { return SIMD2(Double(offer.point.x), Double(offer.point.y)) }
        let birdWidth = cast.species[c.species].height * cast.species[c.species].aspect * layout.scale(0.85)
        let x = person.head.x + c.side * max(person.headRadius * 1.85, person.headRadius * 1.12 + 20 + birdWidth / 2)
        return SIMD2(x, silhouetteTop(at: x, person))
    }

    /// The point above the seat that a bird loops around before it lands.
    private func perchCircle(for c: SceneCreature, _ person: ScenePerson) -> SIMD2<Double> {
        let seat = perchSeat(for: c, person)
        return SIMD2(seat.x + c.side * 20, seat.y + 130)
    }

    private func ringShape(for c: SceneCreature, _ sp: SceneSpecies, _ person: ScenePerson) -> (centre: SIMD2<Double>, rx: Double, ry: Double) {
        let w = sp.height * sp.aspect * layout.scale(0.8)
        if sp.act == .orbit && sp.group == 1 {
            // Around the head, wide enough to stay off the face.
            let rx = person.headRadius * 1.12 + 10 + w * 0.6 + 40
            return (SIMD2(person.head.x, person.head.y), rx, rx * 0.5 + 20)
        }
        // Around the whole person.
        let rx = person.box.width / 2 + w * 0.6 + 70
        return (SIMD2(person.box.midX, person.box.midY + 40), rx, min(190, person.box.height * 0.32))
    }

    private mutating func approach(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double) {
        guard let person else { giveUp(&c, sp); return }
        if c.phaseTime > 14 { giveUp(&c, sp); return }
        if c.onHand, offer == nil { c.onHand = false }       // the hand went away on the way: the shoulder will do

        if sp.body == .walker {
            let spot = standingSpot(for: c, sp, person)
            let dx = spot.x - c.pos.x
            var pace = sp.speed * layout.scale(c.depth) * sp.charge
            c.vel.y = 0
            if sp.stalks {
                // Creeps while it is far, then bursts.
                pace *= abs(dx) > 360 ? 0.42 : 1.7
            }
            let time = max(0.25, abs(dx) / max(pace, 1))
            if abs(dx) > 2 { c.dir = dx > 0 ? 1 : -1 }
            let arrived = walk(&c, sp, toward: spot.x, speed: pace, dt: dt, keepFacing: false)
            moveDepth(&c, toward: spot.depth, rate: abs(spot.depth - c.depth) / time, dt: dt, person: person)
            if arrived, abs(c.depth - spot.depth) < 0.02 {
                begin(&c, sp, person)
            }
        } else if sp.body == .soarer {
            let spot = flyingSpot(for: c, sp, person)
            seek(&c, toward: spot, speed: sp.speed * 2.4, dt: dt, sharpness: 2.2)
            c.depth += (0.3 - c.depth) * min(1, dt * 2)
            if simd_distance(c.pos, spot) < 40 { begin(&c, sp, person) }
        } else {
            let spot = flyingSpot(for: c, sp, person)
            seek(&c, toward: spot, speed: sp.speed * sp.charge, dt: dt, sharpness: 2.4)
            if simd_distance(c.pos, spot) < 28 { begin(&c, sp, person) }
        }
    }

    /// Changes depth, but never lets an animal pop from behind the person to in front of them (or back) while they overlap.
    private mutating func moveDepth(_ c: inout SceneCreature, toward target: Double, rate: Double, dt: Double, person: ScenePerson?) {
        let step = min(abs(target - c.depth), max(rate, 0.08) * dt)
        var next = c.depth + (target > c.depth ? step : -step)
        let crossing = (c.depth < layout.frontDepth) != (next < layout.frontDepth)
        if crossing, let person {
            var rect = bounds(of: c)
            rect.origin.y -= c.lift
            if rect.intersects(person.box.insetBy(dx: 12, dy: 0)) { next = c.depth < layout.frontDepth ? layout.frontDepth - 0.01 : layout.frontDepth + 0.01 }
        }
        c.depth = next
    }

    private mutating func begin(_ c: inout SceneCreature, _ sp: SceneSpecies, _ person: ScenePerson) {
        c.phase = .acting
        c.phaseTime = 0
        c.beats = 0
        c.landedAt = nil
        c.stay = rng.range(4.2, 6.2)
        c.origin = c.pos
        if sp.body == .walker { c.dir = person.head.x >= c.pos.x ? 1 : -1 }
        if sp.act == .orbit || sp.act == .lunge {
            let ring = ringShape(for: c, sp, person)
            c.stride = atan2((c.pos.y - ring.centre.y) / ring.ry, (c.pos.x - ring.centre.x) / ring.rx)
        }
        if sp.act == .perch {
            let circle = perchCircle(for: c, person)
            c.stride = atan2(c.pos.y - circle.y, c.pos.x - circle.x)
        }
        if sp.act == .drop { c.origin = SIMD2(c.pos.x, size.height + 40) }
    }

    // MARK: Doing its thing

    /// Whether the time `t` into the act was passed during this step.
    private func crossed(_ t: Double, _ c: SceneCreature, _ dt: Double) -> Bool { c.phaseTime - dt < t && c.phaseTime >= t }

    private mutating func act(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double) {
        guard let person else {
            // Nobody to do it for any more. A monkey on a head falls off.
            giveUp(&c, sp)
            return
        }
        switch sp.act {
        case .climb: climb(&c, sp, dt, person)
        case .perch: perch(&c, sp, dt, person)
        case .orbit: orbit(&c, sp, dt, person)
        case .lunge: lunge(&c, sp, dt, person)
        case .drop: dropDown(&c, sp, dt, person)
        default: show(&c, sp, dt, person)
        }
    }

    /// The acts where it stays where it is and puts on a display.
    private mutating func show(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double, _ person: ScenePerson) {
        c.vel.x = 0
        c.dir = person.head.x >= c.pos.x ? 1 : -1
        if !sp.isGroundBound { hover(&c, sp, dt) }
        let front = c.depth >= layout.frontDepth
        let w = width(c), h = height(c)
        let mouth = SIMD2(c.pos.x + c.dir * w * 0.45, c.pos.y + c.lift + h * (sp.act == .trumpet ? 0.8 : 0.55))
        switch sp.act {
        case .roar:
            if crossed(0.30, c, dt) { say(&c, sp.cry, life: 1.5); shake = max(shake, 13); dust(&c, count: 9, strength: 1, front: front) }
        case .trumpet:
            if crossed(0.35, c, dt) { say(&c, sp.cry, life: 1.5); shake = max(shake, 4) }
            if c.phaseTime > 0.35, c.phaseTime < 1.5 { spray(from: mouth, dir: c.dir, dt: dt, front: front) }
        case .stomp:
            for t in [0.45, 0.95, 1.45] where crossed(t, c, dt) { dust(&c, count: 6, strength: 0.9, front: front); shake = max(shake, 5); c.vel.y = 220; c.lift = 0.01 }
            if crossed(0.5, c, dt) { say(&c, sp.cry, life: 1.3) }
        case .chestBeat:
            if crossed(0.45, c, dt) { say(&c, sp.cry, life: 1.6) }
            if c.phaseTime > 0.5, c.phaseTime < 2.1, Int((c.phaseTime) / 0.26) != Int((c.phaseTime - dt) / 0.26) { shake = max(shake, 4); c.beats += 1 }
        case .snap:
            if crossed(0.4, c, dt) { say(&c, sp.cry, life: 1.2) }
            for t in [0.4, 0.95, 1.5] where crossed(t, c, dt) { shake = max(shake, 3); dust(&c, count: 4, strength: 0.6, front: front) }
        case .rear:
            if crossed(0.45, c, dt) { say(&c, sp.cry, life: 1.5) }
        case .lean:
            if crossed(0.7, c, dt) { say(&c, sp.cry, life: 1.8) }
        case .hop:
            if crossed(0.25, c, dt) { say(&c, sp.cry, life: 1.3) }
            for t in [0.4, 0.9, 1.4] where crossed(t, c, dt) { dust(&c, count: 3, strength: 0.5, front: front); c.vel.y = 300; c.lift = 0.01 }
        case .boo:
            if crossed(0.35, c, dt) { say(&c, sp.cry, life: 1.5); shake = max(shake, 7) }
        default: break
        }
        if c.phaseTime >= sp.actSeconds { finishAct(&c, sp, person) }
    }

    private mutating func finishAct(_ c: inout SceneCreature, _ sp: SceneSpecies, _ person: ScenePerson?) {
        c.phase = .retreating
        c.phaseTime = 0
        c.landedAt = nil
        c.cooldown = rng.range(14, 26) / max(0.3, sp.interest)
        c.onHand = false
        let w = width(c)
        let away = c.side
        if sp.body == .walker {
            c.target.x = min(max(c.pos.x + away * rng.range(260, 460), w * 0.5), size.width - w * 0.5)
        } else {
            c.target = SIMD2(away > 0 ? size.width + w : -w, rng.range(layout.roamLow, layout.roamHigh))
        }
    }

    // MARK: Acts that travel

    /// The monkey: scrambles up to your shoulder, up the side of your head (never across your face) and onto the top of it, sits there
    /// bouncing, and hops down again.
    private mutating func climb(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double, _ person: ScenePerson) {
        let h = height(c), w = width(c)
        let zoneHalf = person.headRadius * 1.12 + 16
        let shoulderX = person.head.x + c.side * max(person.headRadius * 1.9, zoneHalf + w / 2)
        let shoulder = SIMD2(shoulderX, silhouetteTop(at: shoulderX, person))
        // Sits on the head unless that would put it off the top of the picture.
        let onHead = person.top + h * 0.8 < size.height
        let sideTop = SIMD2(shoulderX, max(shoulder.y, person.top - 6))
        let crown = onHead ? SIMD2(person.head.x, person.top - 6) : shoulder
        let ground = SIMD2(c.origin.x, layout.ground(c.depth))
        let t = c.phaseTime
        let sit = c.stay
        func arc(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ k: Double, _ peak: Double) -> SIMD2<Double> {
            let e = k * k * (3 - 2 * k)
            return SIMD2(a.x + (b.x - a.x) * e, a.y + (b.y - a.y) * e + peak * 4 * k * (1 - k))
        }
        // The times at which each leg ends.
        let toShoulder = 0.8, toSide = onHead ? 1.5 : 0.8, toCrown = onHead ? 2.0 : 0.8
        let downStart = toCrown + sit
        let position: SIMD2<Double>
        if t < toShoulder {
            position = arc(ground, shoulder, t / toShoulder, 90)
        } else if t < toSide {
            position = arc(shoulder, sideTop, (t - toShoulder) / (toSide - toShoulder), 20)
        } else if t < toCrown {
            position = arc(sideTop, crown, (t - toSide) / (toCrown - toSide), 40)
        } else if t < downStart {
            let sway = sin(t * 2.3) * 3
            let bounce = abs(sin(t * 7.5)) * 9 * (t > toCrown + 0.4 ? 1 : 0)
            position = SIMD2(crown.x + sway, crown.y + bounce)
        } else if t < downStart + (onHead ? 0.5 : 0) {
            position = arc(crown, sideTop, (t - downStart) / 0.5, 40)
        } else if t < downStart + (onHead ? 1.3 : 0.8) {
            let from = onHead ? sideTop : shoulder
            let start = downStart + (onHead ? 0.5 : 0)
            position = arc(from, ground, (t - start) / (downStart + (onHead ? 1.3 : 0.8) - start), 70)
        } else {
            c.lift = 0
            finishAct(&c, sp, person)
            c.pos.x = ground.x
            return
        }
        c.pos.x = position.x
        c.lift = max(0.01, position.y - layout.ground(c.depth))
        c.dir = position.x < person.head.x ? 1 : -1
        if t >= toCrown, c.landedAt == nil { c.landedAt = t; say(&c, sp.cry, life: 1.8) }
        if crossed(toShoulder, c, dt) || crossed(toCrown, c, dt) { dust(&c, count: 2, strength: 0.3, front: true) }
    }

    /// The bird: circles beside your shoulder (or above the hand you hold up), lands, and stays for a while.
    private mutating func perch(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double, _ person: ScenePerson) {
        let t = c.phaseTime
        var seat = perchSeat(for: c, person)
        let circle = perchCircle(for: c, person)
        if c.onHand, offer == nil {
            // The hand went away.
            finishAct(&c, sp, person)
            return
        }
        seat.y += height(c) * 0.5
        let landStart = 1.3, landSeconds = 0.55
        if t < landStart {
            // A loop or two above the seat.
            let spin = 2 * .pi / 0.95
            let angle = c.stride + spin * t * (c.dir >= 0 ? 1 : -1)
            let radius = 48 + 16 * sin(t * 5)
            let p = SIMD2(circle.x + cos(angle) * radius * 1.6, circle.y + sin(angle) * radius * 0.8)
            let k = min(1, t / 0.35)
            c.pos += (p - c.pos) * min(1, dt * (4 + 10 * k))
            c.vel = SIMD2(-sin(angle) * (c.dir >= 0 ? 1 : -1), 0) * 100
            c.depth = c.depth + ((sin(angle) > 0 ? 0.3 : 0.8) - c.depth) * min(1, dt * 8)
        } else if t < landStart + landSeconds {
            let k = (t - landStart) / landSeconds
            let e = k * k * (3 - 2 * k)
            c.pos += (seat - c.pos) * min(1, dt * (6 + 18 * e))
            c.depth += (0.85 - c.depth) * min(1, dt * 8)
            c.vel *= 0.8
        } else {
            if c.landedAt == nil { c.landedAt = t; say(&c, sp.cry, life: 1.6); dust(&c, count: 3, strength: 0.25, front: true) }
            c.pos += (seat - c.pos) * min(1, dt * 14)
            c.depth = 0.85
            c.vel = .zero
            let stayed = t - (c.landedAt ?? t)
            if !c.onHand, stayed > c.stay { finishAct(&c, sp, person) }
            if c.onHand, stayed > 14 { finishAct(&c, sp, person) }
        }
        c.dir = c.landedAt == nil ? (c.vel.x >= 0 ? 1 : -1) : (person.head.x >= c.pos.x ? 1 : -1)
        c.stride += dt * 12
    }

    /// A wide ring around you (or just your head), crossing behind you and in front, then off.
    private mutating func orbit(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double, _ person: ScenePerson) {
        let ring = ringShape(for: c, sp, person)
        let omega = 2 * .pi / (sp.actSeconds / 1.25) * (c.side >= 0 ? 1 : -1)
        c.stride += omega * dt
        let target = SIMD2(ring.centre.x + ring.rx * cos(c.stride), ring.centre.y + ring.ry * sin(c.stride))
        c.vel = (target - c.pos) / max(dt, 1e-3)
        c.pos += (target - c.pos) * min(1, dt * 9)
        c.dir = c.vel.x >= 0 ? 1 : -1
        // The back half of the ring is behind you.
        c.depth += ((sin(c.stride) > 0 ? 0.3 : 0.8) - c.depth) * min(1, dt * 10)
        if c.phaseTime > 0.3, c.bubble == nil, c.beats == 0 { c.beats = 1; say(&c, sp.cry, life: 1.2) }
        if c.phaseTime >= sp.actSeconds { finishAct(&c, sp, person) }
    }

    /// The shark: swims around you, then comes straight at you, stops short, and veers away.
    private mutating func lunge(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double, _ person: ScenePerson) {
        let ring = ringShape(for: c, sp, person)
        let circling = sp.actSeconds * 0.6, rush = 0.7
        let t = c.phaseTime
        if t < circling {
            let omega = 2 * .pi / 3.4 * (c.side >= 0 ? 1 : -1)
            c.stride += omega * dt
            let target = SIMD2(ring.centre.x + ring.rx * cos(c.stride), ring.centre.y + ring.ry * sin(c.stride))
            c.vel = (target - c.pos) / max(dt, 1e-3)
            c.pos += (target - c.pos) * min(1, dt * 7)
            c.depth += ((sin(c.stride) > 0 ? 0.3 : 0.8) - c.depth) * min(1, dt * 10)
            c.origin = c.pos
        } else if t < circling + rush {
            // Straight at you, ending beside your head and well clear of it.
            let w = width(c)
            let stopX = person.head.x + c.side * (person.headRadius * 1.12 + 10 + w * 0.5 + 24)
            let stop = SIMD2(min(max(stopX, w * 0.3), size.width - w * 0.3), person.head.y - person.headRadius * 0.4)
            let k = (t - circling) / rush
            let e = k * k
            let from = c.origin
            let next = from + (stop - from) * e
            c.vel = (next - c.pos) / max(dt, 1e-3)
            c.pos = next
            c.depth += (0.85 - c.depth) * min(1, dt * 8)
            if crossed(circling + 0.05, c, dt) { say(&c, "!", life: 0.7) }
        } else {
            if c.beats == 0 {
                c.beats = 1
                say(&c, sp.cry, life: 1.2)
                shake = max(shake, 8)
                dust(&c, count: 8, strength: 1, front: true)
            }
            if c.phaseTime > circling + rush + 0.45 { finishAct(&c, sp, person) }
        }
        c.dir = c.vel.x >= 0 ? 1 : -1
        if abs(c.vel.x) < 20 { c.dir = person.head.x >= c.pos.x ? 1 : -1 }
    }

    /// The spider: lowers itself on a thread beside your head, dangles, and climbs back up.
    private mutating func dropDown(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double, _ person: ScenePerson) {
        let t = c.phaseTime
        let x = person.head.x + c.side * (person.headRadius * 1.12 + 10 + width(c) * 0.6 + 26)
        let low = person.head.y + person.headRadius * 0.4
        let down = 0.9, hold = sp.actSeconds - 1.8
        c.vel = .zero
        let y: Double
        if t < down {
            let k = t / down
            y = c.origin.y + (low - c.origin.y) * (1 - (1 - k) * (1 - k))
        } else if t < down + hold {
            y = low + sin((t - down) * 6) * 10 * exp(-(t - down))
            if crossed(down + 0.1, c, dt) { say(&c, sp.cry, life: 1.2) }
        } else {
            let k = min(1, (t - down - hold) / 0.9)
            y = low + (c.origin.y - low) * k * k
        }
        c.pos = SIMD2(x + sin(t * 3) * 4, y)
        c.depth = 0.85
        if t >= sp.actSeconds { finishAct(&c, sp, person) }
    }

    // MARK: Leaving

    private mutating func retreat(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double) {
        switch sp.body {
        case .walker:
            c.vel.y = 0
            let arrivedX = walk(&c, sp, toward: c.target.x, speed: sp.speed * layout.scale(c.depth) * 0.9, dt: dt)
            let home = Self.homeDepth(sp, layout, quirk: c.quirk)
            moveDepth(&c, toward: home, rate: 0.45, dt: dt, person: person)
            if arrivedX, abs(c.depth - home) < 0.03 { c.phase = .wandering; c.wait = rng.range(0.5, 2); pickWanderTarget(&c, sp) }
        case .soarer, .flier, .swimmer, .floater:
            let t = c.target
            seek(&c, toward: t, speed: sp.speed * 1.6, dt: dt, sharpness: 2.4)
            let home = Self.homeDepth(sp, layout, quirk: c.quirk)
            c.depth += (home - c.depth) * min(1, dt * 1.5)
            if simd_distance(c.pos, t) < 60 || c.phaseTime > 5 {
                c.phase = .wandering
                c.wait = rng.range(0.5, 2)
                if sp.body == .soarer { c.origin = SIMD2(min(max(c.pos.x, 200), size.width - 200), layout.roamHigh - 40) }
            }
            if c.pos.x < -width(c) * 1.1 || c.pos.x > size.width + width(c) * 1.1 { c.phase = .away; c.wait = rng.range(4, 9) }
        }
        if c.phaseTime > 14 { c.phase = .wandering }
    }

    /// Bolts for the edge of the picture and is gone; comes back a few seconds later from somewhere.
    private mutating func flee(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double) {
        let w = width(c)
        let run = sp.speed * layout.scale(c.depth) * 2.7
        switch sp.body {
        case .walker:
            let gone = walk(&c, sp, toward: c.target.x, speed: run, dt: dt)
            moveDepth(&c, toward: Self.homeDepth(sp, layout, quirk: c.quirk), rate: 0.4, dt: dt, person: person)
            if gone { c.phase = .away; c.wait = rng.range(5, 9) }
        default:
            seek(&c, toward: c.target, speed: sp.speed * 2.6, dt: dt, sharpness: 4)
            c.depth += (Self.homeDepth(sp, layout, quirk: c.quirk) - c.depth) * min(1, dt * 2)
            if c.pos.x < -w || c.pos.x > size.width + w { c.phase = .away; c.wait = rng.range(5, 9) }
        }
        if c.phase == .fleeing, c.phaseTime > 3.2 {
            c.phase = .wandering
            c.cooldown = rng.range(8, 14)
            c.wait = 0.5
            pickWanderTarget(&c, sp)
        }
        c.cooldown = max(c.cooldown, 6)
    }

    private mutating func backOff(_ c: inout SceneCreature, _ sp: SceneSpecies, _ dt: Double) {
        let step = sp.speed * layout.scale(c.depth) * 0.9
        if sp.body == .walker {
            c.pos.x += c.side * step * dt * (c.phaseTime < 0.9 ? 1 : 0)
            c.stride += dt * 7
        } else {
            seek(&c, toward: c.pos + SIMD2(c.side * 200, 40), speed: sp.speed * 1.4, dt: dt, sharpness: 3)
        }
        if c.phaseTime > 1.1 {
            c.phase = .retreating
            c.phaseTime = 0
            c.cooldown = rng.range(5, 9)
            c.target = SIMD2(min(max(c.pos.x + c.side * 160, 60), size.width - 60), 0)
            if sp.body != .walker { c.target = SIMD2(c.pos.x + c.side * 400, rng.range(layout.roamLow, layout.roamHigh)) }
        }
    }

    // MARK: Staying off your face

    /// Nothing in front of the person covers their face. A walker is stopped at the edge of the keep-out area; anything else is moved out.
    private mutating func keepClear(_ c: inout SceneCreature, _ sp: SceneSpecies) {
        guard let person, c.depth >= layout.frontDepth, c.phase != .away else { return }
        if c.phase == .acting, sp.act == .climb || sp.act == .drop { return }
        if c.phase == .acting, sp.act == .perch, c.onHand { return }      // a hand is where it is, and the bird goes with it
        let zone = person.faceZone.insetBy(dx: -4, dy: -4)
        var rect = bounds(of: c)
        guard rect.intersects(zone) else { return }
        let w = rect.width, h = rect.height
        if sp.isGroundBound {
            if c.lift > 0.5 && rect.minY > zone.maxY { return }
            let left = zone.minX - w / 2, right = zone.maxX + w / 2
            c.pos.x = abs(c.pos.x - left) < abs(c.pos.x - right) ? left : right
            c.vel.x = 0
            if c.phase == .wandering { c.wait = max(c.wait, 0.2); c.target.x = c.pos.x }
        } else {
            let options = [SIMD2(c.pos.x, zone.minY - h / 2), SIMD2(c.pos.x, zone.maxY + h / 2), SIMD2(zone.minX - w / 2, c.pos.y), SIMD2(zone.maxX + w / 2, c.pos.y)]
            if let best = options.min(by: { simd_distance($0, c.pos) < simd_distance($1, c.pos) }) { c.pos = best }
        }
        rect = bounds(of: c)
    }

    // MARK: Effects

    private mutating func say(_ c: inout SceneCreature, _ text: String, life: Double) {
        guard !text.isEmpty else { return }
        c.bubble = SceneBubble(text: text, age: 0, life: life)
    }

    /// Kinds of particle.
    static let dustKind = 0, dropKind = 1, bubbleKind = 4

    private mutating func dust(_ c: inout SceneCreature, count: Int, strength: Double, front: Bool? = nil) {
        let isFront = front ?? (c.depth >= layout.frontDepth)
        let sp = cast.species[c.species]
        let foot = sp.isGroundBound ? SIMD2(c.pos.x, c.pos.y) : c.pos
        for _ in 0..<count {
            let side = rng.sign()
            let kind = cast.underwater ? Self.bubbleKind : Self.dustKind
            let p = Particle(position: foot + SIMD2(side * rng.range(0, width(c) * 0.4), rng.range(0, 8)),
                             velocity: SIMD2(side * rng.range(20, 110) * strength, rng.range(10, 60) * strength),
                             age: 0, life: rng.range(0.6, 1.3), size: rng.range(10, 24) * (0.55 + 0.45 * layout.scale(c.depth)) * strength,
                             hue: rng.unit(), kind: kind)
            if isFront { effects.emit(p) } else { effectsBehind.emit(p) }
        }
    }

    private mutating func spray(from point: SIMD2<Double>, dir: Double, dt: Double, front: Bool) {
        let count = Int(dt * 170 + rng.unit())
        for _ in 0..<count {
            let up = rng.range(430, 640), out = dir * rng.range(120, 330)
            let p = Particle(position: point + SIMD2(rng.range(-4, 4), rng.range(-4, 4)), velocity: SIMD2(out, up), age: 0, life: 1.5, size: rng.range(3, 6.5), hue: rng.unit(), kind: Self.dropKind)
            if front { effects.emit(p) } else { effectsBehind.emit(p) }
        }
    }

    private static func adjust(_ p: inout Particle, _ dt: Double) {
        switch p.kind {
        case dropKind:
            p.velocity.y -= 1150 * dt
        case bubbleKind:
            p.velocity.y += 60 * dt
            p.velocity.x *= exp(-dt * 0.9)
        default:
            p.velocity *= exp(-dt * 3.5)
            p.velocity.y += 25 * dt
        }
    }
}

extension SceneSpecies {
    /// What the creature says when it does its thing.
    var cry: String {
        if let shout { return shout }
        switch act {
        case .roar: return "ROAR!"
        case .trumpet: return "TOOT!"
        case .stomp: return "SNORT!"
        case .chestBeat: return "OO-OO-AH!"
        case .snap: return "SNAP!"
        case .rear: return "SSSSS!"
        case .lean: return "💛"
        case .hop: return "♪"
        case .climb: return "OOH OOH!"
        case .perch: return "♪"
        case .orbit: return "!"
        case .lunge: return "CHOMP!"
        case .boo: return "BOO!"
        case .drop: return "!"
        }
    }
}
