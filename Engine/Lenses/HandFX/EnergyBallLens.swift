import CoreGraphics
import CoreImage
import simd

/// A ball of energy that charges above an open palm and is thrown with a flick.
///
/// Hold a palm open and an orb swells above it, crackling. Flick the hand and the orb flies off in that direction, leaving a glowing trail, until it
/// has left the picture; then a new one starts charging.
struct EnergyBallRig {
    /// One orb, charging over one hand.
    struct Orb {
        /// 0...1: how much energy it holds.
        var charge = 0.0
        /// Seconds since the palm was last seen open.
        var sinceOpen = 9.0
        var openFor = 0.0
        /// After a throw, seconds before the next orb may start.
        var cooldown = 0.0
    }

    /// A thrown orb in flight.
    struct Shot {
        var position: CGPoint
        var velocity: CGVector
        var radius: Double
        var age = 0.0
        /// Where it has been, newest last.
        var trail: [CGPoint] = []
    }

    /// A speck of energy being drawn into an orb, found by its angle and how far out it still is.
    struct Mote {
        var hand: Int
        var angle: Double
        var distance: Double
        var age = 0.0
        var life: Double
    }

    /// Seconds of open palm to reach full charge.
    static let chargeSeconds = 2.2
    /// Charge needed to throw anything at all.
    static let minimumCharge = 0.2
    /// Palm speed that counts as a flick, in palm lengths a second, and never less than this many pixels a second.
    static let flickPalmLengths = 9.0
    static let flickMinimum = 800.0

    private(set) var orbs = HandFXMemory<Orb>()
    private(set) var shots: [Shot] = []
    private(set) var motes: [Mote] = []
    private(set) var sparks = ParticleSystem(capacity: 140)
    private(set) var thrown = 0
    private(set) var frame = 0
    private(set) var time = 0.0
    private var rng = SplitMix64(seed: 0xE1E7)
    /// Steadies the joints, so the orb floats calmly over a hand that trembles.
    private var steadier = HandFXSteadier()
    let size: CGSize

    init(size: CGSize) {
        self.size = size
        sparks.gravity = SIMD2(0, -240)
    }

    mutating func removeAll() {
        orbs.removeAll()
        steadier.removeAll()
        shots.removeAll()
        motes.removeAll()
        sparks.removeAll()
    }

    /// The orb's size for a charge, in pixels, for a hand of a given size.
    static func radius(charge: Double, handSize: Double) -> Double {
        let eased = charge * charge * (3 - 2 * charge)
        return handSize * (0.1 + 0.68 * eased)
    }

    /// Where the orb floats: over the middle of the palm, toward the fingers.
    static func center(of hand: HandState, radius: Double) -> CGPoint {
        let up = HandFXKit.up(of: hand), palm = hand.palm
        let lift = hand.size * 0.3 + radius * 0.3
        return CGPoint(x: Double(palm.x) + up.x * lift, y: Double(palm.y) + up.y * lift)
    }

    mutating func update(hands raw: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        frame += 1
        time += dt
        let hands = steadier.update(raw, dt: dt)

        orbs.update(hands, dt: dt, fade: 0.35) { _ in Orb() }
        for i in orbs.entries.indices {
            let entry = orbs.entries[i]
            let hand = entry.hand
            var orb = entry.state
            // Out of sight, the orb stays where it was and shrinks away with the presence.
            guard entry.visible else { continue }
            orb.cooldown = max(0, orb.cooldown - dt)
            let open = hand.pose == .openPalm
            orb.openFor = open ? orb.openFor + dt : 0
            orb.sinceOpen = open ? 0 : orb.sinceOpen + dt
            if open, orb.openFor > 0.1, orb.cooldown <= 0 {
                orb.charge = min(1, orb.charge + dt / Self.chargeSeconds)
            } else if orb.sinceOpen > 0.3 {
                // The palm closed or turned away: the energy leaks out, but not at the first flicker of the tracker.
                orb.charge = max(0, orb.charge - dt * 0.8)
            }

            let speed = hypot(hand.velocity.dx, hand.velocity.dy)
            let flick = max(Self.flickMinimum, Self.flickPalmLengths * hand.size)
            if orb.charge >= Self.minimumCharge, speed > flick {
                throwOrb(from: hand, charge: orb.charge, speed: speed)
                orb.charge = 0
                orb.cooldown = 0.55
            }
            orbs.modify(i) { $0.state = orb }
        }

        stepMotes(dt: dt)
        stepShots(dt: dt)
        sparks.step(dt)
    }

    private mutating func throwOrb(from hand: HandState, charge: Double, speed: Double) {
        let radius = Self.radius(charge: charge, handSize: hand.size)
        let origin = Self.center(of: hand, radius: radius)
        let direction = CGVector(dx: hand.velocity.dx / speed, dy: hand.velocity.dy / speed)
        let v = min(2600, max(1500, speed * 1.1))
        shots.append(Shot(position: origin, velocity: CGVector(dx: direction.dx * v, dy: direction.dy * v), radius: max(12, radius)))
        if shots.count > 4 { shots.removeFirst() }
        thrown += 1
        for _ in 0..<14 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 120...420, using: &rng)
            sparks.emit(Particle(position: SIMD2(Double(origin.x), Double(origin.y)), velocity: SIMD2(cos(a), sin(a)) * s, age: 0,
                                 life: Double.random(in: 0.25...0.55, using: &rng), size: Double.random(in: 2...4.5, using: &rng), hue: 0.55))
        }
    }

    private mutating func stepMotes(dt: Double) {
        for i in motes.indices { motes[i].age += dt }
        motes.removeAll { $0.age >= $0.life }
        for entry in orbs.entries where entry.visible && entry.state.charge > 0.05 {
            // The fuller the orb, the more it pulls in.
            let wanted = dt * (30 + 90 * entry.state.charge) * entry.presence
            var count = Int(wanted)
            if Double.random(in: 0..<1, using: &rng) < wanted - Double(count) { count += 1 }
            let radius = Self.radius(charge: entry.state.charge, handSize: entry.hand.size)
            for _ in 0..<count where motes.count < 48 {
                motes.append(Mote(hand: entry.hand.id, angle: Double.random(in: 0..<(2 * .pi), using: &rng), distance: radius * Double.random(in: 1.5...2.5, using: &rng) + 24,
                                  life: Double.random(in: 0.35...0.6, using: &rng)))
            }
        }
    }

    private mutating func stepShots(dt: Double) {
        let area = CGRect(origin: .zero, size: size)
        for i in shots.indices {
            shots[i].age += dt
            shots[i].position.x += shots[i].velocity.dx * dt
            shots[i].position.y += shots[i].velocity.dy * dt
            shots[i].trail.append(shots[i].position)
            if shots[i].trail.count > 18 { shots[i].trail.removeFirst() }
            // A glowing wake of sparks.
            if Double.random(in: 0..<1, using: &rng) < 0.9 {
                let spread = Double.random(in: -1...1, using: &rng) * shots[i].radius * 0.6
                sparks.emit(Particle(position: SIMD2(Double(shots[i].position.x) - Double(shots[i].velocity.dx) * 0.012 + spread, Double(shots[i].position.y) + spread),
                                     velocity: SIMD2(Double.random(in: -60...60, using: &rng), Double.random(in: -60...60, using: &rng)), age: 0,
                                     life: Double.random(in: 0.25...0.5, using: &rng), size: Double.random(in: 1.5...3.5, using: &rng), hue: 0.55))
            }
        }
        // Gone once it is well clear of the picture, with a flash where it left.
        let margin = 80.0
        func isGone(_ shot: Shot) -> Bool { !area.insetBy(dx: -(margin + shot.radius), dy: -(margin + shot.radius)).contains(shot.position) }
        for shot in shots where isGone(shot) {
            guard let inside = shot.trail.last(where: { area.contains($0) }) else { continue }
            let speed = hypot(shot.velocity.dx, shot.velocity.dy)
            guard speed > 1e-6 else { continue }
            let hit = HandGeometry.exit(from: SIMD2(Double(inside.x), Double(inside.y)),
                                        direction: SIMD2(Double(shot.velocity.dx / speed), Double(shot.velocity.dy / speed)), rect: area)
            for _ in 0..<18 {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 100...380, using: &rng)
                sparks.emit(Particle(position: hit, velocity: SIMD2(cos(a), sin(a)) * s, age: 0, life: Double.random(in: 0.3...0.6, using: &rng),
                                     size: Double.random(in: 2...5, using: &rng), hue: 0.55))
            }
        }
        shots.removeAll { isGone($0) }
    }
}

final class EnergyBallLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig: EnergyBallRig
    private var hint = HandFXHint()
    private let published = StatusBox()

    var status: LensStatus? { published.value }

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        rig = EnergyBallRig(size: size)
        published.value = LensStatus("Hold up your hand", detail: "Open palm to charge, flick to throw")
    }

    func restart() {
        rig.removeAll()
        hint.reset()
    }

    var isHinting: Bool { hint.isShowing }
    var charge: Double { rig.orbs.entries.map(\.state.charge).max() ?? 0 }
    var shots: [EnergyBallRig.Shot] { rig.shots }
    var thrownCount: Int { rig.thrown }
    var presence: Double { rig.orbs.entries.map(\.presence).max() ?? 0 }

    func render(_ input: LensInput) -> CIImage {
        rig.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        published.value = currentStatus(input.hands)

        var lit = input.composed
        if !rig.orbs.isEmpty || !rig.shots.isEmpty || !rig.sparks.particles.isEmpty {
            // The big soft light of each orb and shot is made on the graphics chip; the details are painted over it.
            for entry in rig.orbs.entries where entry.state.charge > 0.01 {
                let radius = EnergyBallRig.radius(charge: entry.state.charge, handSize: entry.hand.size)
                let c = EnergyBallRig.center(of: entry.hand, radius: radius)
                let colour = Self.colour(charge: entry.state.charge)
                lit = WorldKit.adding(WorldKit.wash(center: c, radius: radius * 2.4 + 20, red: colour.x, green: colour.y, blue: colour.z,
                                                    alpha: 0.36 * entry.presence, in: input.rect), to: lit)
            }
            for shot in rig.shots {
                let colour = Self.colour(charge: 0.7)
                lit = WorldKit.adding(WorldKit.wash(center: shot.position, radius: shot.radius * 2.6 + 20, red: colour.x, green: colour.y, blue: colour.z,
                                                    alpha: 0.4, in: input.rect), to: lit)
            }
            // The bodies of the orbs are solid, so they read as balls even over a bright face; the light and the lightning are added on top.
            if let solid = input.services.overlay({ ctx in drawSolids(in: ctx) }) { lit = solid.composited(over: lit) }
            if let layer = input.services.overlay({ ctx in drawLight(in: ctx) }) {
                lit = HandFXLight.add(layer, to: lit, rect: input.rect, bloom: 0.7)
            }
        }
        return hint.compose(over: lit, services: input.services, rect: input.rect, accent: HandFXPalette.plasma.cyan)
    }

    private func currentStatus(_ hands: [HandState]) -> LensStatus {
        if hands.isEmpty { return LensStatus("Hold up your hand", detail: "Open palm to charge, flick to throw") }
        let charge = self.charge
        if charge >= 0.9 { return LensStatus("Fully charged!", detail: "Flick your hand to throw it") }
        if charge > 0.1 { return LensStatus("Charging…", detail: "Flick your hand to throw it") }
        return LensStatus("Open your palm to charge", detail: "Then flick to throw")
    }

    private static let speck = HandFXKit.speckSprite(SIMD3(0.5, 0.8, 1))

    /// Cyan when it is small, shading toward violet as it fills.
    private static func colour(charge: Double) -> SIMD3<Double> {
        let a = SIMD3<Double>(0.25, 0.75, 1.0), b = SIMD3<Double>(0.6, 0.4, 1.0)
        return a + (b - a) * min(1, max(0, charge * charge))
    }

    // MARK: Drawing

    private func drawSolids(in ctx: CGContext) {
        for entry in rig.orbs.entries where entry.state.charge > 0.01 {
            let radius = EnergyBallRig.radius(charge: entry.state.charge, handSize: entry.hand.size)
            drawBody(at: EnergyBallRig.center(of: entry.hand, radius: radius), radius: radius, colour: Self.colour(charge: entry.state.charge), strength: entry.presence, in: ctx)
        }
        for shot in rig.shots { drawBody(at: shot.position, radius: shot.radius, colour: Self.colour(charge: 0.7), strength: 1, in: ctx) }
    }

    private func drawLight(in ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        defer { ctx.interpolationQuality = .high }

        let white = WorldKit.softGlow(1, 1, 1)
        for entry in rig.orbs.entries where entry.state.charge > 0.01 { drawOrbLight(entry, white: white, in: ctx) }
        for shot in rig.shots { drawShotLight(shot, in: ctx) }

        if let speck = Self.speck {
            for p in rig.sparks.particles {
                let fade = 1 - p.progress
                ctx.stampDot(speck, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * 2.2 * (0.6 + 0.4 * fade), alpha: fade)
            }
        }
    }

    /// The ball itself: white-hot in the middle, shading through the colour to a deeper rim and a soft edge. Painted solid, not added.
    private func drawBody(at c: CGPoint, radius r: Double, colour: SIMD3<Double>, strength: Double, in ctx: CGContext) {
        guard r > 1, strength > 0.01 else { return }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func stop(_ k: Double, _ shade: Double, _ alpha: Double) -> CGColor {
            CGColor(red: (colour.x + (1 - colour.x) * k) * shade, green: (colour.y + (1 - colour.y) * k) * shade,
                    blue: (colour.z + (1 - colour.z) * k) * shade, alpha: alpha * strength)
        }
        let colors = [stop(0.9, 1, 1), stop(0.4, 1, 1), stop(0, 1, 0.97), stop(0, 0.55, 0.85), stop(0, 0.4, 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.3, 0.68, 0.93, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * 1.06, options: [])
        }
    }

    /// The glow of the ball: a hot core, swirls turning inside, and a bright rim.
    private func drawSphereLight(at c: CGPoint, radius r: Double, colour: SIMD3<Double>, strength: Double, spin: Double, white: CGImage?, in ctx: CGContext) {
        guard r > 1, strength > 0.01 else { return }
        if let white { ctx.stampDot(white, at: c, radius: r * 0.7, alpha: 0.85 * strength) }
        ctx.setLineCap(.round)
        for k in 0..<3 {
            let ring = r * (0.35 + 0.17 * Double(k)), start = spin * (1.4 + Double(k) * 0.7) * (k % 2 == 0 ? 1 : -1) + Double(k) * 2.1
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.6 * strength))
            ctx.setLineWidth(max(1.5, r * 0.05))
            ctx.beginPath()
            ctx.addArc(center: c, radius: ring, startAngle: start, endAngle: start + 1.5, clockwise: false)
            ctx.strokePath()
        }
        ctx.setStrokeColor(CGColor(red: min(1, colour.x + 0.4), green: min(1, colour.y + 0.3), blue: 1, alpha: 0.5 * strength))
        ctx.setLineWidth(max(1.5, r * 0.035))
        ctx.strokeEllipse(in: CGRect(x: c.x - r * 0.97, y: c.y - r * 0.97, width: r * 1.94, height: r * 1.94))
    }

    /// Arcs of electricity leaping off a sphere. `beat` changes every couple of frames, so they crackle.
    private func drawCrackle(around c: CGPoint, radius r: Double, count: Int, beat: Int, salt: Int, colour: SIMD3<Double>, strength: Double, in ctx: CGContext) {
        for k in 0..<count {
            var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: beat &* 7919 &+ k &* 104_729 &+ salt &* 31))
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let reach = r * Double.random(in: 1.35...2.0, using: &rng) + 10
            let drift = Double.random(in: -0.4...0.4, using: &rng)
            let start = CGPoint(x: Double(c.x) + cos(angle) * r * 0.92, y: Double(c.y) + sin(angle) * r * 0.92)
            let end = CGPoint(x: Double(c.x) + cos(angle + drift) * reach, y: Double(c.y) + sin(angle + drift) * reach)
            let bolt = HandFXKit.zigzag(from: start, to: end, seed: UInt64(truncatingIfNeeded: beat &* 31 &+ k &* 977 &+ salt), amplitude: max(5, r * 0.2), segments: 9)
            HandFXKit.drawBolt(bolt, in: ctx, colour: colour, strength: strength, width: 0.8 + 0.4 * min(1, r / 70))
        }
    }

    private func drawOrbLight(_ entry: HandFXMemory<EnergyBallRig.Orb>.Entry, white: CGImage?, in ctx: CGContext) {
        let charge = entry.state.charge, presence = entry.presence
        let radius = EnergyBallRig.radius(charge: charge, handSize: entry.hand.size)
        let c = EnergyBallRig.center(of: entry.hand, radius: radius)
        let colour = Self.colour(charge: charge)

        drawSphereLight(at: c, radius: radius, colour: colour, strength: presence, spin: rig.time * (1 + 2 * charge), white: white, in: ctx)
        // Crackling arcs: more of them as it fills.
        drawCrackle(around: c, radius: radius, count: 2 + Int(charge * 6), beat: rig.frame / 2, salt: entry.hand.id, colour: colour,
                    strength: presence * (0.6 + 0.4 * charge), in: ctx)

        // Energy streaming in from around: short streaks rushing toward the middle, quickening as they arrive.
        if let streak = WorldKit.comet(colour.x, colour.y, colour.z) {
            for m in rig.motes where m.hand == entry.hand.id {
                let k = m.age / m.life, d = m.distance * (1 - k * k)
                guard d > radius * 0.9 else { continue }
                let p = CGPoint(x: Double(c.x) + cos(m.angle) * d, y: Double(c.y) + sin(m.angle) * d)
                let alpha = min(1, k * 3) * presence
                let length = 14 + 40 * k
                ctx.saveGState()
                ctx.translateBy(x: p.x, y: p.y)
                ctx.rotate(by: CGFloat(m.angle + .pi))
                ctx.setAlpha(CGFloat(alpha))
                ctx.draw(streak, in: CGRect(x: -length, y: -4, width: length, height: 8))
                ctx.restoreGState()
                if let white { ctx.stampDot(white, at: p, radius: 3.5, alpha: alpha) }
            }
        }
    }

    private func drawShotLight(_ shot: EnergyBallRig.Shot, in ctx: CGContext) {
        let colour = Self.colour(charge: 0.7)
        let speed = hypot(shot.velocity.dx, shot.velocity.dy)
        // A comet's tail behind it: wide and coloured, with a narrower white-hot one inside.
        if speed > 1, let wide = WorldKit.comet(colour.x, colour.y, colour.z), let hot = WorldKit.comet(0.85, 0.95, 1) {
            let length = min(560, speed * 0.22)
            ctx.saveGState()
            ctx.translateBy(x: shot.position.x, y: shot.position.y)
            ctx.rotate(by: atan2(shot.velocity.dy, shot.velocity.dx))
            ctx.draw(wide, in: CGRect(x: -length, y: -shot.radius * 1.25, width: length, height: shot.radius * 2.5))
            ctx.draw(hot, in: CGRect(x: -length * 0.7, y: -shot.radius * 0.5, width: length * 0.7, height: shot.radius))
            ctx.restoreGState()
        }
        drawSphereLight(at: shot.position, radius: shot.radius, colour: colour, strength: 1, spin: shot.age * 6, white: WorldKit.softGlow(1, 1, 1), in: ctx)
        drawCrackle(around: shot.position, radius: shot.radius, count: 4, beat: rig.frame / 2, salt: 77, colour: colour, strength: 0.9, in: ctx)
    }
}
