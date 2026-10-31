import CoreGraphics
import Foundation
import simd

/// The numbers that decide when creatures take an interest and when they bolt.
enum VistaTuning {
    /// How much arm-waving, near a creature, scares it (a count of lattice points that moved).
    static let scareLevel = 9.0
    /// How close the waving has to be, in pixels.
    static let scareRadius = 420.0
    /// Waving this big, anywhere, scatters everything.
    static let scatterLevel = 26.0
    /// How long somebody has to be in view before the creatures notice them. Their moving about while they settle does not count as waving.
    static let settleSeconds = 0.8
    static let arrivalSeconds = 1.3
    /// At most this many creatures are busy with you at once.
    static let busyLimit = 2
    /// Spacing of the lattice the motion is read on.
    static let motionStep = 32.0
}

/// A living scene with no drawing in it: a handful of creatures that wander, notice you, come over, do their thing, and run off when
/// you wave. Stepped with a time and what the camera sees; given the same seed and the same inputs it always does the same.
struct VistaWorld {
    let cast: VistaCast
    private(set) var creatures: [VistaCreature] = []
    /// Puffs, sparks and coins in front of the person, and behind them.
    private(set) var effects = ParticleSystem(capacity: 420)
    private(set) var effectsBehind = ParticleSystem(capacity: 300)
    private(set) var time = 0.0
    /// How hard the picture is shaking, in pixels. Dies away on its own.
    private(set) var shake = 0.0
    /// The person, smoothed, or nil when nobody has been there for a moment.
    private(set) var person: VistaPerson?
    private(set) var personSeenFor = 0.0
    private(set) var offer: VistaOffer?
    /// How much of the silhouette is moving, overall: a count of lattice points.
    private(set) var motionEnergy = 0.0
    private var personAbsentFor = 0.0
    private var offerLostFor = 0.0
    private var moving: [SIMD3<Double>] = []
    /// The silhouette, only while a step is under way.
    private var matte: MatteQuery?
    private var rng: VistaRandom

    var layout: VistaLayout { cast.layout }
    var size: CGSize { cast.layout.size }

    init(cast: VistaCast, seed: UInt64) {
        self.cast = cast
        rng = VistaRandom(seed: seed)
        effects.gravity = .zero
        effectsBehind.gravity = .zero
        var order = Array(cast.roster.indices)
        for i in order.indices.reversed() { order.swapAt(i, Int(rng.unit() * Double(i + 1))) }
        let props = Set(cast.roster.indices.filter { cast.species[cast.roster[$0]].body == .prop })
        let movers = order.filter { !props.contains($0) }
        let visible = props.union(movers.prefix(max(0, min(cast.visibleAtStart, cast.cap) - props.count)))
        // The one that notices you first: a visible creature that does something worth seeing, close up.
        let greeter = order.first { i in
            let sp = cast.species[cast.roster[i]]
            return visible.contains(i) && sp.interest >= 1 && !sp.farOnly && sp.act == .show && sp.body != .prop && sp.speed * sp.charge >= 60
        }

        var slot = 0
        let spread = Double(max(1, visible.count - props.count))
        for (i, s) in cast.roster.enumerated() {
            var c = VistaCreature(id: i, species: s)
            let sp = cast.species[s]
            c.quirk = rng.unit()
            c.depth = Self.homeDepth(sp, quirk: c.quirk)
            c.cooldown = rng.range(6, 16) / max(0.3, sp.interest)
            c.side = rng.sign()
            if sp.body == .prop {
                place(&c, sp, x: size.width * sp.anchorX)
                c.phase = .wandering
                c.wait = 600
            } else if visible.contains(i) {
                // Spread the first ones across the picture so it is alive from the first frame.
                let x = size.width * (0.12 + 0.76 * (Double(slot) + rng.range(0.1, 0.9)) / spread)
                slot += 1
                place(&c, sp, x: x)
                c.phase = .wandering
                c.wait = rng.range(0.2, 2.5)
            } else {
                c.phase = .away
                c.wait = rng.range(3, 12)
            }
            if i == greeter {
                // The first to come over starts not far from where people sit, so that something happens in the first few seconds.
                c.cooldown = 0.9
                place(&c, sp, x: size.width * (c.pos.x < size.width / 2 ? 0.27 : 0.73))
            }
            creatures.append(c)
        }
    }

    // MARK: Stepping

    /// Advances the world. A long stall is taken in small steps so nothing leaps through anything.
    mutating func step(_ dt: Double, context: VistaContext) {
        var left = min(max(0, dt), 0.5)
        while left > 1e-6 {
            let h = min(left, 1.0 / 30)
            left -= h
            advance(h, context)
        }
    }

    private mutating func advance(_ dt: Double, _ ctx: VistaContext) {
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
        shake *= exp(-dt * 8)
        if shake < 0.05 { shake = 0 }
    }

    // MARK: Senses

    private mutating func sensePerson(_ ctx: VistaContext, _ dt: Double) {
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
            if personAbsentFor > VistaTuning.settleSeconds { person = nil; personSeenFor = 0 }
        }
    }

    private mutating func senseHands(_ ctx: VistaContext, _ dt: Double) {
        var found: VistaOffer?
        for hand in ctx.hands where hand.pose == .openPalm && hand.size >= 22 {
            let tip = hand[.middleTip], knuckle = hand[.middleMCP]
            // Held up or out, not hanging down, and held still enough to land on.
            guard tip.y >= hand.wrist.y - hand.size * 0.3, hypot(hand.velocity.dx, hand.velocity.dy) < 450 else { continue }
            found = VistaOffer(point: CGPoint(x: knuckle.x + (tip.x - knuckle.x) * 0.55, y: knuckle.y + (tip.y - knuckle.y) * 0.55), handID: hand.id)
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

    private mutating func senseMotion(_ ctx: VistaContext, _ dt: Double) {
        moving.removeAll(keepingCapacity: true)
        var total = 0.0
        if let motion = ctx.motion, personSeenFor > VistaTuning.arrivalSeconds, let box = person?.box.insetBy(dx: -90, dy: -90) {
            let s = VistaTuning.motionStep
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
        if sp.isGroundBound { c.pos.y = layout.ground(c.depth) }
        c.wait = 600
        c.cooldown = 600
        c.vel = .zero
        c.lift = 0
        c.target = SIMD2(x, sp.isGroundBound ? 0 : c.pos.y)
        c.leaving = false
        creatures[id] = c
    }

    // MARK: Geometry

    /// The size of one creature as it is drawn.
    func spriteHeight(_ c: VistaCreature) -> Double { cast.species[c.species].height * layout.scale(c.depth) }
    func spriteWidth(_ c: VistaCreature) -> Double { spriteHeight(c) * cast.species[c.species].aspect }
    func height(_ c: VistaCreature) -> Double { spriteHeight(c) }
    func width(_ c: VistaCreature) -> Double { spriteWidth(c) }

    /// The rectangle a creature fills on the screen. Ground-bound ones stand on `pos`; the rest are centred on it.
    func bounds(of c: VistaCreature) -> CGRect {
        let sp = cast.species[c.species]
        let h = height(c), w = width(c)
        switch sp.body {
        case .emerger:
            return CGRect(x: c.pos.x - w / 2, y: c.pos.y, width: w, height: h * max(0.04, c.rise))
        case .walker, .prop:
            return CGRect(x: c.pos.x - w / 2, y: c.pos.y + c.lift, width: w, height: h)
        case .flier, .floater, .soarer:
            return CGRect(x: c.pos.x - w / 2, y: c.pos.y - h / 2, width: w, height: h)
        }
    }

    private static func homeDepth(_ sp: VistaSpecies, quirk: Double) -> Double {
        sp.body == .prop ? sp.home : min(1, max(0, sp.home + (quirk - 0.5) * 0.05))
    }

    private var busy: Int {
        creatures.filter { $0.phase == .noticing || $0.phase == .approaching || $0.phase == .acting }.count
    }

    private var onScreen: Int { creatures.filter { $0.phase != .away }.count }

    private func onScreenWidth(of c: VistaCreature) -> Bool {
        c.pos.x > -width(c) * 0.3 && c.pos.x < size.width + width(c) * 0.3
    }

    /// Puts a creature somewhere in its home lane.
    private mutating func place(_ c: inout VistaCreature, _ sp: VistaSpecies, x: Double) {
        c.pos.x = x
        c.depth = Self.homeDepth(sp, quirk: c.quirk)
        switch sp.body {
        case .walker, .emerger, .prop:
            c.pos.y = layout.ground(c.depth)
        case .soarer:
            c.origin = SIMD2(x, (sp.band?.upperBound ?? layout.roamHigh) - 40 + rng.range(-30, 30))
            c.stride = rng.range(0, 2 * .pi)
            c.pos = c.origin
        case .flier, .floater:
            c.pos.y = rng.range(sp.band?.lowerBound ?? layout.roamLow, sp.band?.upperBound ?? layout.roamHigh)
        }
        c.dir = sp.body == .prop ? -1 : rng.sign()
        c.turn = c.dir
        c.target = SIMD2(x, c.pos.y)
        if sp.body != .prop { pickWanderTarget(&c, sp) }
    }

    // MARK: One creature

    private mutating func update(_ c: inout VistaCreature, _ dt: Double, _ ctx: VistaContext) {
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
            // A hand held up calls the birds back sooner.
            if sp.perchesOnHand, offer != nil, c.wait > 1.5 { c.wait = 1.5 }
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
        if c.lift > 0, !(c.phase == .acting && sp.act == .perch) {
            c.vel.y -= 1500 * dt
            c.lift = max(0, c.lift + c.vel.y * dt)
            if c.lift == 0 {
                if c.vel.y < -500, sp.isGroundBound { burst(c, sp, .dust, count: 4, strength: 0.5) }
                c.vel.y = 0
            }
        }
        if sp.body == .emerger { surface(&c, sp, dt) }
        if sp.slides {
            c.sliding = c.phase == .approaching || c.phase == .fleeing
            c.slide += ((c.sliding ? 1 : 0) - c.slide) * min(1, dt * 7)
        }
        if c.sliding, abs(c.vel.x) > 20, rng.chance(dt * 14) { burst(c, sp, .snow, count: 1, strength: 0.5) }
        keepClear(&c, sp)
    }

    /// How far out of the water (or over the hill) a creature that lives below it is.
    private mutating func surface(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double) {
        var wanted = 0.0
        switch c.phase {
        case .wandering, .entering:
            // Now and then, while it rests, it peeps out.
            if c.wait > 0, sin(time * 0.55 + c.quirk * 9) > 0.55 { wanted = 0.22 }
        case .noticing: wanted = 0.32
        case .acting:
            let t = c.phaseTime, end = sp.actSeconds
            c.rise = t < end - 0.7 ? Self.ease(t / 0.7) : 1 - Self.ease((t - (end - 0.7)) / 0.7)
            return
        default: wanted = 0
        }
        let rate = c.phase == .fleeing || c.phase == .backingOff ? 9.0 : 3.0
        c.rise += (wanted - c.rise) * min(1, dt * rate)
    }

    private static func ease(_ k: Double) -> Double { let x = min(1, max(0, k)); return x * x * (3 - 2 * x) }

    private mutating func enter(_ c: inout VistaCreature, _ sp: VistaSpecies) {
        guard sp.body != .prop else { place(&c, sp, x: size.width * sp.anchorX); c.phase = .wandering; return }
        let side = c.id % 2 == 0 ? 1.0 : -1.0
        let from = rng.chance(0.5) ? side : -side
        c.depth = Self.homeDepth(sp, quirk: c.quirk)
        let w = width(c)
        c.pos.x = from < 0 ? -w * 0.6 : size.width + w * 0.6
        switch sp.body {
        case .walker, .emerger, .prop: c.pos.y = layout.ground(c.depth)
        case .soarer:
            c.origin = SIMD2(size.width * rng.range(0.3, 0.7), (sp.band?.upperBound ?? layout.roamHigh) - 40 + rng.range(-30, 30))
            c.stride = from < 0 ? .pi : 0
            c.pos = SIMD2(c.pos.x, c.origin.y)
        case .flier, .floater: c.pos.y = rng.range(sp.band?.lowerBound ?? layout.roamLow, sp.band?.upperBound ?? layout.roamHigh)
        }
        c.dir = -from
        c.turn = c.dir
        c.lift = 0
        c.rise = 0
        c.phase = .entering
        c.phaseTime = 0
        c.wait = 0
        c.leaving = false
        c.target = SIMD2(size.width * rng.range(0.15, 0.85), sp.isGroundBound ? 0 : c.pos.y)
        c.cooldown = max(c.cooldown, rng.range(2, 6))
    }

    // MARK: Being scared

    private mutating func feel(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double) {
        guard c.phase != .fleeing, c.phase != .backingOff, c.phase != .entering else { c.fear = 0; return }
        let centre = sp.isGroundBound ? SIMD2(c.pos.x, c.pos.y + c.lift + height(c) * (sp.body == .emerger ? max(0.1, c.rise) : 1) / 2) : c.pos
        let near = movement(near: centre, radius: VistaTuning.scareRadius + height(c) * 0.4)
        c.fear += (near.energy - c.fear) * min(1, dt / 0.1)
        let scattered = motionEnergy > VistaTuning.scatterLevel && onScreenWidth(of: c)
        guard c.fear > VistaTuning.scareLevel || scattered else { return }
        c.fear = 0
        startle(&c, sp, awayFrom: scattered ? (person.map { Double($0.box.midX) } ?? near.centre) : near.centre)
    }

    private mutating func startle(_ c: inout VistaCreature, _ sp: VistaSpecies, awayFrom x: Double) {
        c.phaseTime = 0
        c.landedAt = nil
        c.onHand = false
        let away = c.pos.x == x ? c.dir : (c.pos.x > x ? 1.0 : -1.0)
        c.side = away
        // A few cries of alarm say it all; a whole crowd of them is just noise.
        let alarmed = creatures.filter { $0.id != c.id && ($0.bubble?.text == "!!" || $0.bubble?.text == "?!") }.count
        let cry = alarmed < 3
        switch sp.temper {
        case .steady:
            c.phase = .backingOff
            if cry { say(&c, "!!", life: 1.0) }
        case .brute:
            c.phase = .backingOff
            if cry { say(&c, "?!", life: 1.0) }
            c.dir = -away                  // keeps its eyes on you
            if sp.body == .walker { c.vel.y = 260; c.lift = c.lift > 0 ? c.lift : 0.01 }
        case .prey, .curious:
            c.phase = .fleeing
            if cry { say(&c, "!!", life: 1.1) } else { c.bubble = nil }
            c.dir = away
            if sp.body == .walker {
                c.vel.y = c.lift > 0 ? 0 : 340
                c.lift = max(c.lift, 0.01)
            }
            let w = width(c)
            c.target = SIMD2(away > 0 ? size.width + w : -w, sp.isGroundBound ? 0 : c.pos.y + rng.range(40, 160))
        }
        if sp.body == .walker { burst(c, sp, .dust, count: 5, strength: 0.6) }
        if sp.body == .emerger { burst(c, sp, .splash, count: 10, strength: 1) }
    }

    // MARK: Wandering

    private mutating func wander(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double) {
        let scale = layout.scale(c.depth)
        switch sp.body {
        case .prop:
            c.vel = .zero
            if c.phase == .entering { c.phase = .wandering }
        case .walker, .emerger:
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
                    // Every so often a creature wanders off the edge and another comes in, and sooner if one is waiting for room.
                    let crowded = creatures.contains { $0.phase == .away && $0.wait <= 0 }
                    if (c.beats % 4 == 3 && rng.chance(0.4)) || (crowded && c.beats >= 2 && rng.chance(0.7)) { leaveByTheNearestEdge(&c) }
                }
            }
            if c.phase == .entering, c.pos.x > 0, c.pos.x < size.width { c.phase = .wandering }
        case .soarer:
            let rx = 250 + c.quirk * 170, ry = 32 + c.quirk * 26
            let omega = sp.speed / rx
            c.stride += omega * dt
            c.origin.x += sin(time * 0.07 + c.quirk * 6) * 6 * dt
            let old = c.pos
            c.pos = SIMD2(c.origin.x + rx * cos(c.stride), c.origin.y + ry * sin(c.stride) + sin(time * 0.9 + c.quirk * 9) * 6)
            c.vel = (c.pos - old) / max(dt, 1e-4)
            c.dir = c.pos.x - old.x >= 0 ? 1 : -1
            if c.phase == .entering, c.pos.x > 40, c.pos.x < size.width - 40 { c.phase = .wandering }
        case .flier, .floater:
            let speed = sp.speed * (sp.body == .flier ? 1 : 0.8)
            c.wait -= dt
            let toTarget = c.target - c.pos
            if simd_length(toTarget) < 30 || c.wait <= 0 { pickWanderTarget(&c, sp) }
            seek(&c, toward: c.target, speed: speed, dt: dt, sharpness: sp.body == .flier ? 2.6 : 1.2)
            if c.phase == .entering, c.pos.x > 30, c.pos.x < size.width - 30 { c.phase = .wandering }
            if c.beats > 6, c.pos.x < -width(c) || c.pos.x > size.width + width(c) { c.phase = .away; c.wait = rng.range(5, 10); c.beats = 0 }
        }
        considerNoticing(&c, sp)
    }

    private mutating func leaveByTheNearestEdge(_ c: inout VistaCreature) {
        c.target.x = c.pos.x < size.width / 2 ? -width(c) * 0.8 : size.width + width(c) * 0.8
        c.leaving = true
    }

    private mutating func pickWanderTarget(_ c: inout VistaCreature, _ sp: VistaSpecies) {
        switch sp.body {
        case .prop:
            break
        case .walker, .emerger:
            // Somewhere new: not on top of another creature in the same lane, and not hidden behind the person.
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
            c.wait = sp.speed > 150 ? rng.range(0.6, 1.6) : rng.range(1.5, 3.5)
        case .floater:
            c.target = freeTarget(for: c, sp)
            c.wait = rng.range(4, 8)
        }
    }

    /// Somewhere new for a flier to head. In front of the person it must be a trip that does not go through their face.
    private mutating func freeTarget(for c: VistaCreature, _ sp: VistaSpecies) -> SIMD2<Double> {
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
    private mutating func walk(_ c: inout VistaCreature, _ sp: VistaSpecies, toward x: Double, speed: Double, dt: Double, keepFacing: Bool = false) -> Bool {
        let dx = x - c.pos.x
        if abs(dx) < 3 { c.vel.x = 0; return true }
        let heading = dx > 0 ? 1.0 : -1.0
        if !keepFacing, sp.gait != .scuttle { c.dir = heading }
        var pace = speed
        if c.sliding {
            // On its belly: quick, and smooth.
            pace = speed * 2.3
            c.stride += dt * 2
        } else {
            switch sp.gait {
            case .hop:
                // Hops: it only travels while it is in the air.
                let air = max(0, sin(c.stride))
                pace = speed * 1.9 * air
                c.stride += dt * 6.5
            case .waddle:
                c.stride += abs(speed) * dt / max(10, height(c) * 0.16) * .pi / 2
            case .scuttle:
                c.stride += dt * 16
            case .walk, .roll:
                c.stride += abs(speed) * dt / max(14, height(c) * 0.42) * .pi
            }
        }
        let move = min(abs(dx), pace * dt)
        c.pos.x += heading * move
        c.vel.x = heading * pace
        return false
    }

    /// Flies or drifts toward a point, easing into the speed.
    private mutating func seek(_ c: inout VistaCreature, toward p: SIMD2<Double>, speed: Double, dt: Double, sharpness: Double) {
        let delta = p - c.pos
        let distance = simd_length(delta)
        let wanted = distance > 1 ? delta / distance * min(speed, distance * 3 + 30) : .zero
        c.vel += (wanted - c.vel) * min(1, dt * sharpness)
        c.pos += c.vel * dt
        if abs(c.vel.x) > 12 { c.dir = c.vel.x > 0 ? 1 : -1 }
        c.stride += dt * 9
    }

    // MARK: Noticing

    private mutating func considerNoticing(_ c: inout VistaCreature, _ sp: VistaSpecies) {
        guard c.phase == .wandering, let person, personSeenFor > VistaTuning.settleSeconds, onScreenWidth(of: c), !c.leaving else { return }
        // One bird to a hand. A hand held up is worth coming for even when others are busy with you.
        let handTaken = creatures.contains { $0.id != c.id && $0.onHand && ($0.phase == .noticing || $0.phase == .approaching || $0.phase == .acting) }
        let wantsHand = sp.perchesOnHand && offer != nil && !handTaken
        guard busy < VistaTuning.busyLimit || (wantsHand && busy < VistaTuning.busyLimit + 1) else { return }
        guard c.cooldown <= 0 || wantsHand else { return }
        c.phase = .noticing
        c.phaseTime = 0
        c.onHand = wantsHand
        if sp.body != .prop { c.dir = person.box.midX >= c.pos.x ? 1 : -1 }
        c.vel.x = 0
        if sp.body == .walker { c.vel.y = 240; c.lift = 0.01 }
        say(&c, "!", life: 0.95)
    }

    private mutating func notice(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double) {
        guard let person else { giveUp(&c, sp); return }
        if sp.isAirborne { hover(&c, sp, dt) }
        if sp.body != .prop { c.dir = person.box.midX >= c.pos.x ? 1 : -1 }
        if c.phaseTime >= 0.85 {
            c.phase = .approaching
            c.phaseTime = 0
            c.origin = c.pos
            c.side = chooseSide(for: c, sp, person)
        }
    }

    /// Stays roughly where it is, bobbing: for fliers while they look at you.
    private mutating func hover(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double) {
        c.vel *= exp(-dt * 4)
        c.pos += c.vel * dt
        c.stride += dt * 8
    }

    private mutating func giveUp(_ c: inout VistaCreature, _ sp: VistaSpecies) {
        c.phase = .wandering
        c.phaseTime = 0
        c.wait = rng.range(0.5, 2)
        c.cooldown = rng.range(6, 12)
        c.onHand = false
        c.landedAt = nil
        c.leaving = false
        if sp.body == .prop { c.wait = 600; return }
        if sp.body == .walker || sp.body == .emerger { pickWanderTarget(&c, sp) }
        if c.depth > layout.frontDepth - 0.01 || c.lift > 0 { c.phase = .retreating; c.target = sp.isGroundBound ? SIMD2(c.pos.x, 0) : c.pos }
    }

    // MARK: Coming over to you

    /// Which side of the person it should go to: the side it is on, unless another creature already has that one.
    private func chooseSide(for c: VistaCreature, _ sp: VistaSpecies, _ person: VistaPerson) -> Double {
        if sp.body == .prop { return c.pos.x >= person.box.midX ? 1 : -1 }
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

    /// Where a ground-bound creature comes to rest to do its thing: beside the person, in the near lane, clear of the silhouette.
    private func standingSpot(for c: VistaCreature, _ sp: VistaSpecies, _ person: VistaPerson) -> (x: Double, depth: Double) {
        let depth = sp.farOnly ? Self.homeDepth(sp, quirk: c.quirk) : layout.nearDepth
        let w = sp.height * layout.scale(depth) * sp.aspect
        // Something that rises up behind you comes up close beside your shoulder; the rest stand clear of you.
        let gap = sp.body == .emerger ? -person.box.width * 0.12 : 24
        let x = c.side < 0 ? person.box.minX - w / 2 - gap : person.box.maxX + w / 2 + gap
        if x >= w * 0.34, x <= size.width - w * 0.34 { return (x, depth) }
        // No room beside them (they fill the picture): peek out from behind them, at the edge.
        let edge = c.side < 0 ? w * 0.3 : size.width - w * 0.3
        return (edge, min(depth, layout.frontDepth - 0.04))
    }

    /// Where a flier heads for before it starts its act.
    private func flyingSpot(for c: VistaCreature, _ sp: VistaSpecies, _ person: VistaPerson) -> SIMD2<Double> {
        let w = sp.height * sp.aspect * layout.scale(sp.farOnly ? sp.home : 0.8)
        let h = sp.height * layout.scale(sp.farOnly ? sp.home : 0.8)
        switch sp.act {
        case .perch:
            return perchCircle(for: c, person)
        case .orbit:
            let ring = ringShape(for: c, sp, person)
            let angle = atan2((c.pos.y - ring.centre.y) / ring.ry, (c.pos.x - ring.centre.x) / ring.rx)
            return SIMD2(ring.centre.x + ring.rx * cos(angle), ring.centre.y + ring.ry * sin(angle))
        case .show:
            let clearX = person.headRadius * 1.12 + 10 + w / 2 + 30
            if sp.spot == .flank {
                let x = c.side < 0 ? Double(person.box.minX) - w * 0.32 : Double(person.box.maxX) + w * 0.32
                let y = min(size.height - h / 2 - 12, Double(person.top) + h * 0.2)
                return SIMD2(min(max(x, w * 0.4), size.width - w * 0.4), max(y, Double(person.head.y)))
            }
            if sp.spot == .above {
                // High up beside the head, where a beam or a breath of fire can come down past you.
                let y = person.top + h * 0.5 + 24
                if y + h / 2 < size.height - 8 {
                    let x = person.head.x + c.side * (person.headRadius * 0.7 + w * 0.32)
                    return SIMD2(min(max(x, w * 0.5 + 8), size.width - w * 0.5 - 8), y)
                }
                // No room above them: beside the head, as high as it will go.
                let x = person.head.x + c.side * clearX
                return SIMD2(min(max(x, w * 0.4), size.width - w * 0.4), min(size.height - h / 2 - 8, person.head.y + person.headRadius))
            }
            let x = person.head.x + c.side * clearX
            return SIMD2(min(max(x, w * 0.3), size.width - w * 0.3), person.head.y + person.headRadius * 0.2)
        }
    }

    /// How high the silhouette reaches at a column: read off the matte when there is one.
    private func silhouetteTop(at x: Double, _ person: VistaPerson) -> Double {
        guard let matte else { return person.estimatedTop(at: x) }
        var y = min(size.height - 1, person.top + 6)
        while y > person.box.minY {
            if matte.coverage(x: x, y: y) > 0.5 { return y }
            y -= 5
        }
        return person.estimatedTop(at: x)
    }

    private func perchSeat(for c: VistaCreature, _ person: VistaPerson) -> SIMD2<Double> {
        if c.onHand, let offer { return SIMD2(Double(offer.point.x), Double(offer.point.y)) }
        let sp = cast.species[c.species]
        let birdWidth = sp.height * sp.aspect * layout.scale(0.85)
        let x = person.head.x + c.side * max(person.headRadius * 1.85, person.headRadius * 1.12 + 20 + birdWidth / 2)
        return SIMD2(x, silhouetteTop(at: x, person))
    }

    /// The point above the seat that a bird loops around before it lands.
    private func perchCircle(for c: VistaCreature, _ person: VistaPerson) -> SIMD2<Double> {
        let seat = perchSeat(for: c, person)
        return SIMD2(seat.x + c.side * 20, min(seat.y + 130, size.height - 60))
    }

    private func ringShape(for c: VistaCreature, _ sp: VistaSpecies, _ person: VistaPerson) -> (centre: SIMD2<Double>, rx: Double, ry: Double) {
        let w = sp.height * sp.aspect * layout.scale(0.8)
        if sp.height < 110 {
            // Small things circle the head, wide enough to stay off the face.
            let rx = person.headRadius * 1.12 + 10 + w * 0.6 + 40
            return (SIMD2(person.head.x, person.head.y + person.headRadius * 0.2), rx, rx * 0.45 + 20)
        }
        // Big ones circle the whole person.
        let rx = person.box.width / 2 + w * 0.6 + 70
        return (SIMD2(person.box.midX, person.box.midY + 40), rx, min(190, person.box.height * 0.32))
    }

    private mutating func approach(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double) {
        guard let person else { giveUp(&c, sp); return }
        if c.phaseTime > 14 { giveUp(&c, sp); return }
        if c.onHand, offer == nil { c.onHand = false }       // the hand went away on the way: the shoulder will do

        switch sp.body {
        case .prop:
            begin(&c, sp, person)
        case .walker, .emerger:
            let spot = standingSpot(for: c, sp, person)
            let dx = spot.x - c.pos.x
            var pace = sp.speed * layout.scale(c.depth) * sp.charge
            c.vel.y = 0
            if sp.stalks {
                // Creeps while it is far, then bursts.
                pace *= abs(dx) > 360 ? 0.42 : 1.7
            }
            let time = max(0.25, abs(dx) / max(pace * (c.sliding ? 2.3 : 1), 1))
            if abs(dx) > 2, sp.gait != .scuttle { c.dir = dx > 0 ? 1 : -1 }
            let arrived = walk(&c, sp, toward: spot.x, speed: pace, dt: dt)
            moveDepth(&c, toward: spot.depth, rate: abs(spot.depth - c.depth) / time, dt: dt, person: person)
            if arrived, abs(c.depth - spot.depth) < 0.02 { begin(&c, sp, person) }
        case .soarer:
            let spot = flyingSpot(for: c, sp, person)
            seek(&c, toward: spot, speed: sp.speed * 2.4, dt: dt, sharpness: 2.2)
            if !sp.farOnly { c.depth += (0.3 - c.depth) * min(1, dt * 2) }
            if simd_distance(c.pos, spot) < 40 { begin(&c, sp, person) }
        case .flier, .floater:
            let spot = flyingSpot(for: c, sp, person)
            seek(&c, toward: spot, speed: sp.speed * sp.charge, dt: dt, sharpness: 2.4)
            if simd_distance(c.pos, spot) < 28 { begin(&c, sp, person) }
        }
    }

    /// Changes depth, but never lets a creature pop from behind the person to in front of them (or back) while they overlap.
    private mutating func moveDepth(_ c: inout VistaCreature, toward target: Double, rate: Double, dt: Double, person: VistaPerson?) {
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

    private mutating func begin(_ c: inout VistaCreature, _ sp: VistaSpecies, _ person: VistaPerson) {
        c.phase = .acting
        c.phaseTime = 0
        c.beats = 0
        c.owed = 0
        c.landedAt = nil
        c.stay = rng.range(4.2, 6.2)
        c.origin = c.pos
        if sp.body != .prop { c.dir = person.head.x >= c.pos.x ? 1 : -1 }
        // What a show is aimed at: the ground just beside you on its side, where fire lands.
        let edge = c.side < 0 ? Double(person.box.minX) - 40 : Double(person.box.maxX) + 40
        c.aim = SIMD2(min(max(edge, 40), size.width - 40), layout.ground(0.6))
        if sp.act == .orbit {
            let ring = ringShape(for: c, sp, person)
            c.stride = atan2((c.pos.y - ring.centre.y) / ring.ry, (c.pos.x - ring.centre.x) / ring.rx)
        }
        if sp.act == .perch {
            let circle = perchCircle(for: c, person)
            c.stride = atan2(c.pos.y - circle.y, c.pos.x - circle.x)
        }
    }

    // MARK: Doing its thing

    /// Whether the time `t` into the act was passed during this step.
    private func crossed(_ t: Double, _ c: VistaCreature, _ dt: Double) -> Bool { c.phaseTime - dt < t && c.phaseTime >= t }

    private mutating func act(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double) {
        guard let person else {
            // Nobody to do it for any more.
            giveUp(&c, sp)
            return
        }
        switch sp.act {
        case .perch: perch(&c, sp, dt, person)
        case .orbit: orbit(&c, sp, dt, person)
        case .show: show(&c, sp, dt, person)
        }
        if c.phase == .acting { runEmitters(&c, sp, dt, person) }
    }

    /// Stays where it is (hovering, if it flies) and puts on its show, beat by beat.
    private mutating func show(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double, _ person: VistaPerson) {
        c.vel.x = 0
        if sp.body != .prop, sp.gait != .scuttle { c.dir = person.head.x >= c.pos.x ? 1 : -1 }
        if sp.isAirborne {
            // Holds its place beside you, bobbing a little.
            let spot = flyingSpot(for: c, sp, person)
            c.vel = (spot - c.pos) * min(1, dt * 3) / max(dt, 1e-3) * 0.3
            c.pos += (spot - c.pos) * min(1, dt * 3)
            c.stride += dt * 8
        }
        if !sp.cry.isEmpty, crossed(sp.cryAt, c, dt) { say(&c, sp.cry, life: 1.6) }
        for beat in sp.beats where crossed(beat.at, c, dt) {
            switch beat.event {
            case .say(let text, let life): say(&c, text, life: life)
            case .shake(let amount): shake = max(shake, amount)
            case .burst(let kind, let count, let strength): burst(c, sp, kind, count: count, strength: strength)
            case .jump(let speed):
                if sp.body == .walker { c.vel.y = speed; c.lift = max(c.lift, 0.01) }
            }
        }
        if c.phaseTime >= sp.actSeconds { finishAct(&c, sp, person) }
    }

    private mutating func finishAct(_ c: inout VistaCreature, _ sp: VistaSpecies, _ person: VistaPerson?) {
        c.phase = .retreating
        c.phaseTime = 0
        c.landedAt = nil
        c.cooldown = rng.range(14, 26) / max(0.3, sp.interest)
        c.onHand = false
        let w = width(c)
        let away = c.side
        switch sp.body {
        case .prop:
            c.target = c.pos
        case .walker, .emerger:
            c.target.x = min(max(c.pos.x + away * rng.range(260, 460), w * 0.5), size.width - w * 0.5)
        case .flier, .floater, .soarer:
            c.target = SIMD2(away > 0 ? size.width + w : -w, rng.range(sp.band?.lowerBound ?? layout.roamLow, sp.band?.upperBound ?? layout.roamHigh))
            if sp.body == .floater { c.target.x = min(max(c.pos.x + away * rng.range(320, 520), w * 0.5), size.width - w * 0.5) }
        }
    }

    // MARK: Acts that travel

    /// The bird: circles beside your shoulder (or above the hand you hold up), lands, and stays for a while.
    private mutating func perch(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double, _ person: VistaPerson) {
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
            if c.landedAt == nil { c.landedAt = t; say(&c, sp.cry, life: 1.6); burst(c, sp, .sparkle, count: 4, strength: 0.4, front: true) }
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

    /// A ring around your head (or the whole of you), crossing behind you and in front, then off.
    private mutating func orbit(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double, _ person: VistaPerson) {
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

    // MARK: Leaving

    private mutating func retreat(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double) {
        switch sp.body {
        case .prop:
            c.phase = .wandering
            c.wait = 600
        case .walker, .emerger:
            c.vel.y = 0
            let arrivedX = walk(&c, sp, toward: c.target.x, speed: sp.speed * layout.scale(c.depth) * 0.9, dt: dt)
            let home = Self.homeDepth(sp, quirk: c.quirk)
            moveDepth(&c, toward: home, rate: 0.45, dt: dt, person: person)
            if arrivedX, abs(c.depth - home) < 0.03 { c.phase = .wandering; c.wait = rng.range(0.5, 2); pickWanderTarget(&c, sp) }
        case .soarer, .flier, .floater:
            let t = c.target
            seek(&c, toward: t, speed: sp.speed * 1.6, dt: dt, sharpness: 2.4)
            let home = Self.homeDepth(sp, quirk: c.quirk)
            c.depth += (home - c.depth) * min(1, dt * 1.5)
            if simd_distance(c.pos, t) < 60 || c.phaseTime > 5 {
                c.phase = .wandering
                c.wait = rng.range(0.5, 2)
                if sp.body == .soarer { c.origin = SIMD2(min(max(c.pos.x, 200), size.width - 200), (sp.band?.upperBound ?? layout.roamHigh) - 40) }
            }
            if c.pos.x < -width(c) * 1.1 || c.pos.x > size.width + width(c) * 1.1 { c.phase = .away; c.wait = rng.range(4, 9) }
        }
        if c.phaseTime > 14, c.phase == .retreating { c.phase = .wandering }
    }

    /// Bolts for the edge of the picture and is gone; comes back a few seconds later from somewhere.
    private mutating func flee(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double) {
        let w = width(c)
        let run = sp.speed * layout.scale(c.depth) * 2.7
        switch sp.body {
        case .prop:
            c.phase = .wandering
            c.wait = 600
        case .walker, .emerger:
            let gone = walk(&c, sp, toward: c.target.x, speed: run, dt: dt)
            moveDepth(&c, toward: Self.homeDepth(sp, quirk: c.quirk), rate: 0.4, dt: dt, person: person)
            if gone { c.phase = .away; c.wait = rng.range(5, 9) }
        case .flier, .floater, .soarer:
            seek(&c, toward: c.target, speed: sp.speed * (sp.body == .floater ? 4 : 2.6), dt: dt, sharpness: 4)
            c.depth += (Self.homeDepth(sp, quirk: c.quirk) - c.depth) * min(1, dt * 2)
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

    private mutating func backOff(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double) {
        let step = sp.speed * layout.scale(c.depth) * 0.9
        switch sp.body {
        case .prop:
            c.vel = .zero
        case .walker, .emerger:
            if sp.temper != .steady {
                c.pos.x += c.side * step * dt * (c.phaseTime < 0.9 ? 1 : 0)
                c.stride += dt * 7
            }
        case .flier, .floater, .soarer:
            seek(&c, toward: c.pos + SIMD2(c.side * 200, 40), speed: sp.speed * 1.4, dt: dt, sharpness: 3)
        }
        if c.phaseTime > 1.1 {
            c.phase = .retreating
            c.phaseTime = 0
            c.cooldown = rng.range(5, 9)
            c.target = SIMD2(min(max(c.pos.x + c.side * 160, 60), size.width - 60), 0)
            if sp.isAirborne { c.target = SIMD2(c.pos.x + c.side * 400, rng.range(sp.band?.lowerBound ?? layout.roamLow, sp.band?.upperBound ?? layout.roamHigh)) }
            if sp.body == .prop { c.target = c.pos }
        }
    }

    // MARK: Staying off your face

    /// Nothing in front of the person covers their face. A walker is stopped at the edge of the keep-out area; anything else is moved out.
    private mutating func keepClear(_ c: inout VistaCreature, _ sp: VistaSpecies) {
        guard let person, c.depth >= layout.frontDepth, c.phase != .away else { return }
        if c.phase == .acting, sp.act == .perch, c.onHand { return }      // a hand is where it is, and the bird goes with it
        let zone = person.faceZone.insetBy(dx: -4, dy: -4)
        let rect = bounds(of: c)
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
    }

    // MARK: Effects

    private mutating func say(_ c: inout VistaCreature, _ text: String, life: Double) {
        guard !text.isEmpty else { return }
        c.bubble = VistaBubble(text: text, age: 0, life: life)
    }

    /// The point of a creature, in output pixels, given in its own units: x forward, y up from its feet (or its middle).
    func point(of c: VistaCreature, at local: SIMD2<Double>) -> SIMD2<Double> {
        let h = height(c)
        let base = cast.species[c.species].isGroundBound ? SIMD2(c.pos.x, c.pos.y + c.lift) : c.pos
        return base + SIMD2(local.x * h * c.dir, local.y * h)
    }

    private mutating func runEmitters(_ c: inout VistaCreature, _ sp: VistaSpecies, _ dt: Double, _ person: VistaPerson) {
        for e in sp.emitters where c.phaseTime >= e.from && c.phaseTime < e.to {
            c.owed += e.rate * dt
            while c.owed >= 1 {
                c.owed -= 1
                let position: SIMD2<Double>
                if e.aroundPerson {
                    let x = rng.range(Double(person.box.minX) - 40, Double(person.box.maxX) + 40)
                    position = SIMD2(x, rng.range(Double(person.box.minY), Double(person.box.minY) + 60))
                } else {
                    position = point(of: c, at: e.at) + SIMD2(rng.range(-6, 6), rng.range(-6, 6))
                }
                let velocity = SIMD2(e.velocity.x * c.dir, e.velocity.y) + SIMD2(rng.range(-e.spread, e.spread), rng.range(-e.spread, e.spread))
                emit(Particle(position: position, velocity: velocity, age: 0, life: Self.life(e.kind) * rng.range(0.7, 1.3),
                              size: Self.size(e.kind) * rng.range(0.7, 1.3), hue: rng.unit(), kind: e.kind.rawValue), front: e.front)
            }
        }
    }

    private mutating func burst(_ c: VistaCreature, _ sp: VistaSpecies, _ kind: VistaFX, count: Int, strength: Double, front: Bool? = nil) {
        let isFront = front ?? (c.depth >= layout.frontDepth)
        let base: SIMD2<Double>
        switch sp.body {
        case .walker, .prop: base = SIMD2(c.pos.x, c.pos.y + (kind == .dust || kind == .snow ? 0 : height(c) * 0.5))
        case .emerger: base = SIMD2(c.pos.x, c.pos.y)
        default: base = c.pos
        }
        let scale = 0.55 + 0.45 * layout.scale(c.depth)
        for _ in 0..<count {
            let side = rng.sign()
            var velocity = SIMD2(side * rng.range(20, 120) * strength, rng.range(20, 90) * strength)
            if kind == .coin || kind == .splash { velocity = SIMD2(side * rng.range(30, 170) * strength, rng.range(380, 640) * strength) }
            if kind == .sparkle || kind == .heart || kind == .note { velocity = SIMD2(side * rng.range(10, 80), rng.range(40, 140)) }
            let p = Particle(position: base + SIMD2(side * rng.range(0, width(c) * 0.4), rng.range(0, 10)), velocity: velocity, age: 0,
                             life: Self.life(kind) * rng.range(0.7, 1.3), size: Self.size(kind) * scale * rng.range(0.7, 1.3) * max(0.6, strength),
                             hue: rng.unit(), kind: kind.rawValue)
            emit(p, front: isFront)
        }
    }

    private mutating func emit(_ p: Particle, front: Bool) {
        if front { effects.emit(p) } else { effectsBehind.emit(p) }
    }

    private static func life(_ kind: VistaFX) -> Double {
        switch kind {
        case .dust, .snow: return 1.0
        case .sparkle: return 1.1
        case .ember: return 1.3
        case .smoke: return 1.6
        case .splash: return 1.2
        case .bubble: return 1.8
        case .coin: return 1.5
        case .note: return 1.8
        case .heart: return 1.6
        }
    }

    private static func size(_ kind: VistaFX) -> Double {
        switch kind {
        case .dust, .snow: return 18
        case .sparkle: return 14
        case .ember: return 6
        case .smoke: return 22
        case .splash: return 6
        case .bubble: return 10
        case .coin: return 14
        case .note: return 24
        case .heart: return 20
        }
    }

    private static func adjust(_ p: inout Particle, _ dt: Double) {
        switch VistaFX(rawValue: p.kind) ?? .dust {
        case .dust:
            p.velocity *= exp(-dt * 3.5)
            p.velocity.y += 20 * dt
        case .snow:
            p.velocity *= exp(-dt * 2.5)
            p.velocity.y -= 60 * dt
        case .sparkle, .heart:
            p.velocity *= exp(-dt * 1.6)
            p.velocity.y += 30 * dt
        case .ember:
            p.velocity *= exp(-dt * 1.2)
            p.velocity.y += 90 * dt
            p.velocity.x += sin(p.age * 7 + p.hue * 20) * 60 * dt
        case .smoke:
            p.velocity *= exp(-dt * 2)
            p.velocity.y += 45 * dt
        case .splash, .coin:
            p.velocity.y -= 1150 * dt
        case .bubble:
            p.velocity.y += 60 * dt
            p.velocity.x *= exp(-dt * 0.9)
        case .note:
            p.velocity *= exp(-dt * 0.8)
            p.velocity.x += sin(p.age * 3 + p.hue * 9) * 40 * dt
        }
    }
}
