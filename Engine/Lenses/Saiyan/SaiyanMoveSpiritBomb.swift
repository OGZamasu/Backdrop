import CoreGraphics
import Foundation
import simd

/// Spirit Bomb. Hold both open hands up above your head and the room dims while a huge sphere of blue-white energy gathers over you,
/// fed by streams of light pouring in from the edges of the picture. Swing both hands down hard and it drops, speeding up, and slams
/// into the bottom of the picture in a blinding flash with rings of shock rolling out; lower your hands slowly and it melts away.
///
/// It needs the face: "above your head" means nothing without one.
final class SpiritBombMove: SaiyanMove {
    let id = "spirit-bomb"
    let name = "Spirit Bomb"
    let hint = "Raise both open hands above your head and hold, then swing them down."

    enum Phase: Equatable { case idle, posing, gathering, falling, impact, fading }

    /// Blue-white, the move's own colour; the form's tint leans it red, cyan, violet or silver.
    static let signature = SIMD3<Double>(0.6, 0.84, 1.0)
    static let gold = SIMD3<Double>(1.0, 0.85, 0.52)

    /// The pose is claimed after this long, and the sphere starts once it has been held for `holdSeconds`.
    static let claimSeconds = 0.1
    static let holdSeconds = 0.5
    /// Seconds from nothing to the full sphere.
    static let gatherSeconds = 4.0
    /// The least charge worth throwing.
    static let minimumThrow = 0.2
    /// Both palms must swing down at least this fast, in palm lengths a second (a wave moves at 3 to 6, but sideways).
    static let throwSpeed = 4.5
    /// And each must have dropped at least this many palm lengths over the last 0.3 s.
    static let throwDrop = 0.6
    /// While posing, each hand must be calmer than this, in palm lengths a second over the last 0.3 s, so two hands waving above the head
    /// do not count (a friendly wave averages about 3; hands held up still, under 0.5).
    static let calmSpeed = 2.2
    /// How long the pose may be broken before the sphere lets go (time enough to read a swing that blurred the tracker).
    static let graceSeconds = 0.4
    static let darkest = 0.55
    static let fallSeconds = 0.42
    static let impactSeconds = 1.4
    static let fadeSeconds = 1.1
    /// The sphere at its biggest, across, in head heights, at full power (a little smaller at base).
    static let headHeights = 1.6
    /// At most this many streams of light in flight at once.
    static let streamLimit = 32

    private(set) var phase = Phase.idle
    /// 0...1: how much energy is gathered.
    private(set) var charge = 0.0
    private(set) var center = CGPoint.zero
    private(set) var radius = 0.0
    /// 0...1: how much of the sphere is showing.
    private(set) var shown = 0.0
    private(set) var thrown = 0

    private var poseFor = 0.0
    private var brokenFor = 0.0
    private var faceLostFor = 0.0
    private var phaseTime = 0.0
    private var cooldown = 0.0
    private var pairIDs: [Int] = []
    private var palms = CGPoint.zero
    private var handSize = 100.0
    private var io = 84.0
    private var up = CGVector(dx: 0, dy: 1)
    private var rect = CGRect(x: 0, y: 0, width: 1280, height: 720)
    private var trail = SaiyanHandTrail()
    private var spring = SaiyanSpring(omega: 6.5)
    private var darkness = HandFXLevel(rise: 0.5, fall: 0.4)
    private var fallFrom = CGPoint.zero, fallTo = CGPoint.zero
    private var fallRadius = 0.0
    private var streams: [Stream] = []
    private var owed = 0.0
    private var sparks = ParticleSystem(capacity: 220)
    private var rng = SplitMix64(seed: 0x5B0B)
    private var colour = SpiritBombMove.signature
    private var power = 0.0
    private var time = 0.0
    private var frame = 0

    /// A thread of energy flying in from the edge of the picture toward the sphere.
    private struct Stream {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var age = 0.0
        var gold: Bool
        var width: Double
        var fade = 1.0
    }

    init() {
        sparks.gravity = .zero
    }

    var isEngaged: Bool { phase == .posing || phase == .gathering || phase == .falling || phase == .impact }

    var hasLight: Bool {
        phase != .idle || shown > 0.004 || !streams.isEmpty || !sparks.particles.isEmpty || darkness.value > 0.002
    }

    var status: LensStatus? {
        switch phase {
        case .posing: return LensStatus("Spirit Bomb", detail: "Keep both hands up")
        case .gathering:
            return LensStatus("Gathering energy...", detail: charge >= Self.minimumThrow ? "Swing both hands down to throw it" : "Keep both hands up")
        case .falling, .impact: return LensStatus("Spirit Bomb!")
        default: return nil
        }
    }

    var screenEffect: SaiyanScreenEffect {
        var e = SaiyanScreenEffect()
        e.darken = darkness.value
        if phase == .impact {
            let t = phaseTime
            let settle = 1 - SaiyanOrbKit.smooth((t - 0.85) / 0.5)
            e.flash = 0.92 * (t < 0.04 ? t / 0.04 : exp(-(t - 0.04) / 0.32)) * settle
            e.flashTint = SaiyanOrbKit.lift(colour, 0.72)
            e.shake = min(1, 0.7 + 0.3 * power) * exp(-t / 0.3) * settle
        }
        return e
    }

    func reset() {
        phase = .idle
        charge = 0
        shown = 0
        radius = 0
        poseFor = 0
        brokenFor = 0
        faceLostFor = 0
        phaseTime = 0
        cooldown = 0
        pairIDs = []
        trail.reset()
        spring.reset()
        darkness = HandFXLevel(rise: 0.5, fall: 0.4)
        streams.removeAll()
        sparks.removeAll()
        owed = 0
    }

    // MARK: Update

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) {
        let dt = WorldKit.clamped(c.dt)
        time = c.time
        frame += 1
        rect = c.rect
        power = c.power
        colour = c.palette.tinting(Self.signature, amount: 0.55)
        trail.update(c.hands, time: c.time)
        cooldown = max(0, cooldown - dt)
        phaseTime += dt
        if let face = c.face {
            io = max(face.interocular, 1)
            up = face.up
            faceLostFor = 0
        } else {
            faceLostFor += dt
        }
        let pair = overheadPair(c)
        if let pair {
            palms = SaiyanOrbKit.midpoint(pair.0.palm, pair.1.palm)
            handSize = max(pair.0.size, pair.1.size)
        }

        switch phase {
        case .idle:
            if mayBegin, cooldown <= 0, let pair, isCalm(pair) {
                poseFor += dt
                if poseFor >= Self.claimSeconds {
                    enter(.posing)
                    pairIDs = [pair.0.id, pair.1.id]
                }
            } else {
                poseFor = 0
            }
        case .posing:
            if let pair, isCalm(pair) {
                poseFor += dt
                brokenFor = 0
                pairIDs = [pair.0.id, pair.1.id]
                if poseFor >= Self.holdSeconds { enter(.gathering) }
            } else {
                brokenFor += dt
                if brokenFor > 0.25 { enter(.idle) }
            }
        case .gathering:
            if let pair {
                brokenFor = 0
                pairIDs = [pair.0.id, pair.1.id]
                charge = min(1, charge + dt / Self.gatherSeconds)
            } else {
                brokenFor += dt
            }
            if charge >= Self.minimumThrow, isSwungDown(c) {
                launch()
            } else if brokenFor > Self.graceSeconds || faceLostFor > 0.6 {
                enter(.fading)
            }
        case .falling:
            if phaseTime >= Self.fallSeconds { slam() }
        case .impact:
            if phaseTime >= Self.impactSeconds {
                enter(.idle)
                cooldown = 0.8
            }
        case .fading:
            if phaseTime >= Self.fadeSeconds {
                enter(.idle)
                cooldown = 0.4
            }
        }

        advanceSphere(dt: dt)
        advanceStreams(dt: dt)
        sparks.step(dt) { p in
            if p.kind == 1 {
                p.velocity.y -= 1100 * dt
                p.velocity *= exp(-0.6 * dt)
            } else {
                p.velocity *= exp(-1.8 * dt)
            }
        }
        darkness.approach(darknessTarget, dt: dt)
    }

    private func enter(_ next: Phase) {
        phase = next
        phaseTime = 0
        brokenFor = 0
        if next == .idle {
            poseFor = 0
            charge = 0
            pairIDs = []
        }
        if next == .gathering { charge = 0 }
    }

    /// Both hands up over the head, open, not far apart and roughly over the middle of the head.
    private func overheadPair(_ c: SaiyanMoveContext) -> (HandState, HandState)? {
        guard let face = c.face, c.hands.count >= 2 else { return nil }
        let raised = c.hands.filter { SaiyanZones.isOverhead($0, face) && c.gestures.pose(of: $0.id) == .openPalm }
        guard raised.count >= 2 else { return nil }
        let a = raised[0], b = raised[1]
        let io = max(face.interocular, 1)
        guard HandState.distance(a.palm, b.palm) < io * 5.2 else { return nil }
        let mid = SaiyanZones.local(SaiyanOrbKit.midpoint(a.palm, b.palm), face)
        guard abs(mid.x) < 2.4 else { return nil }
        return (a, b)
    }

    private func isCalm(_ pair: (HandState, HandState)) -> Bool {
        trail.meanSpeed(pair.0.id, over: 0.3) < Self.calmSpeed && trail.meanSpeed(pair.1.id, over: 0.3) < Self.calmSpeed
    }

    /// Both palms swung down hard within the last moment, and kept going: one jumpy frame of the tracker is not a throw.
    private func isSwungDown(_ c: SaiyanMoveContext) -> Bool {
        let ids = pairIDs.count == 2 ? pairIDs : Array(c.hands.prefix(2).map(\.id))
        guard ids.count == 2 else { return false }
        let down = CGVector(dx: 0, dy: -1)
        return ids.allSatisfy { id in
            trail.peak(id, along: down, within: 0.3) >= Self.throwSpeed && -Double(trail.travel(id, over: 0.3, guessed: true).dy) >= handSize * Self.throwDrop
        }
    }

    private func launch() {
        // A swing that also goes sideways throws the sphere a little that way.
        let ids = pairIDs
        let sideways = ids.map { Double(trail.velocity($0, over: 0.15).dx) }.reduce(0, +) / Double(max(1, ids.count))
        let drift = max(-rect.width * 0.22, min(rect.width * 0.22, sideways * 0.18))
        fallFrom = center
        fallRadius = radius
        fallTo = CGPoint(x: max(rect.minX + 40, min(rect.maxX - 40, center.x + drift)), y: rect.minY + radius * 0.16)
        thrown += 1
        enter(.falling)
    }

    private func slam() {
        enter(.impact)
        // Debris and sparks thrown up and out from where it hit.
        for _ in 0..<(28 + Int(16 * power)) {
            let a = Double.random(in: 0.12...(Double.pi - 0.12), using: &rng)
            let s = Double.random(in: 380...1250, using: &rng) * (rect.width / 1280)
            sparks.emit(Particle(position: SIMD2(Double(fallTo.x) + cos(a) * fallRadius * 0.5, Double(fallTo.y) + 8), velocity: SIMD2(cos(a), sin(a)) * s,
                                 life: Double.random(in: 0.5...1.1, using: &rng), size: Double.random(in: 2.2...5.5, using: &rng),
                                 hue: Double.random(in: 0..<1, using: &rng), kind: 1))
        }
        for i in streams.indices { streams[i].fade = min(streams[i].fade, 0.6) }
    }

    private var darknessTarget: Double {
        switch phase {
        case .posing: return Self.darkest * 0.22 * SaiyanOrbKit.smooth(poseFor / Self.holdSeconds)
        case .gathering: return Self.darkest * (0.22 + 0.78 * SaiyanOrbKit.smooth(charge / 0.3))
        case .falling: return Self.darkest
        default: return 0
        }
    }

    /// The largest the sphere grows for this face and form.
    private var maxRadius: Double {
        let across = io * 3.0 * Self.headHeights * (0.78 + 0.22 * power)
        return min(across / 2, rect.height * 0.4)
    }

    private func advanceSphere(dt: Double) {
        let breathe = 1 + 0.022 * sin(time * 2 * .pi * 1.3) + 0.01 * sin(time * 2 * .pi * 3.1)
        switch phase {
        case .idle:
            shown = max(0, shown - dt / 0.25)
        case .posing:
            radius = maxRadius * 0.06 * SaiyanOrbKit.smooth(poseFor / Self.holdSeconds)
            follow(dt: dt)
            shown = min(1, shown + dt / 0.2)
        case .gathering:
            let growth = 1 - pow(1 - charge, 2.2)
            let wanted = maxRadius * (0.06 + 0.94 * growth) * breathe
            radius += (wanted - radius) * (1 - exp(-dt / 0.12))
            follow(dt: dt)
            shown = min(1, shown + dt / 0.2)
        case .falling:
            let k = SaiyanOrbKit.clamp01(phaseTime / Self.fallSeconds)
            let e = k * k
            center = CGPoint(x: fallFrom.x + (fallTo.x - fallFrom.x) * e, y: fallFrom.y + (fallTo.y - fallFrom.y) * e)
            radius = fallRadius * (1 + 0.14 * e)
            shown = 1
        case .impact:
            center = fallTo
            radius = fallRadius * 1.14 * (1 + 0.85 * SaiyanOrbKit.easeOut(phaseTime / 0.35))
            shown = 1 - SaiyanOrbKit.smooth(phaseTime / 0.42)
        case .fading:
            radius *= exp(-dt / 2.2)
            shown = 1 - SaiyanOrbKit.smooth(phaseTime / Self.fadeSeconds)
            // The energy goes back where it came from: motes drift off the surface.
            if shown > 0.1 {
                let wanted = dt * 70 * shown
                var count = Int(wanted)
                if Double.random(in: 0..<1, using: &rng) < wanted - Double(count) { count += 1 }
                for _ in 0..<count {
                    let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                    let at = SIMD2(Double(center.x) + cos(a) * radius, Double(center.y) + sin(a) * radius)
                    sparks.emit(Particle(position: at, velocity: SIMD2(cos(a), sin(a) + 0.4) * Double.random(in: 60...190, using: &rng),
                                         life: Double.random(in: 0.6...1.2, using: &rng), size: Double.random(in: 1.8...3.6, using: &rng),
                                         hue: Double.random(in: 0..<1, using: &rng), kind: 0))
                }
            }
        }
    }

    /// The sphere floats above the hands, its lower edge among the fingers. A webcam leaves little room above the head, so it is kept
    /// low enough that its white-hot heart and most of it stay in the picture, settling over the hair if it must.
    private func follow(dt: Double) {
        var target = SaiyanOrbKit.point(palms, up, handSize * 0.2 + radius * 0.9)
        target.y = min(target.y, rect.maxY - radius * 0.3)
        target.x = max(rect.minX + radius * 0.3, min(rect.maxX - radius * 0.3, target.x))
        center = spring.update(target, dt: dt)
    }

    // MARK: Streams of energy

    private func advanceStreams(dt: Double) {
        let gathering = phase == .gathering || phase == .posing
        if gathering {
            let rate = (phase == .posing ? 6 : 12 + 22 * charge) * (0.75 + 0.5 * power)
            owed += dt * rate
            while owed >= 1, streams.count < Self.streamLimit {
                owed -= 1
                spawnStream()
            }
            if streams.count >= Self.streamLimit { owed = 0 }
        }
        let target = SIMD2(Double(center.x), Double(center.y))
        let pull = 900 + 1700 * charge
        for i in streams.indices {
            var s = streams[i]
            s.age += dt
            let to = target - s.position
            let d = max(simd_length(to), 1)
            s.velocity += to / d * pull * dt
            s.velocity *= exp(-1.1 * dt)
            let speed = simd_length(s.velocity)
            if speed > 1700 { s.velocity *= 1700 / speed }
            s.position += s.velocity * dt
            if !gathering, phase != .falling { s.fade -= dt / 0.35 }
            streams[i] = s
        }
        // Into the sphere: a glint where each lands.
        streams.removeAll { s in
            let d = simd_length(target - s.position)
            if d < radius * 0.92, phase == .gathering || phase == .falling {
                sparks.emit(Particle(position: s.position, velocity: .zero, life: 0.22, size: s.width * 0.8, hue: s.gold ? 1 : 0, kind: 2))
                return true
            }
            return s.fade <= 0 || s.age > 3.2 || (d < 8)
        }
    }

    private func spawnStream() {
        // Mostly from the top and the sides, as if drawn from the whole world around.
        let pick = Double.random(in: 0..<1, using: &rng)
        let along = Double.random(in: 0..<1, using: &rng)
        let margin = 30.0
        var p: SIMD2<Double>
        if pick < 0.45 {
            p = SIMD2(rect.minX + rect.width * along, rect.maxY + margin)
        } else if pick < 0.72 {
            p = SIMD2(rect.minX - margin, rect.minY + rect.height * (0.25 + 0.75 * along))
        } else if pick < 0.99 {
            p = SIMD2(rect.maxX + margin, rect.minY + rect.height * (0.25 + 0.75 * along))
        } else {
            p = SIMD2(rect.minX + rect.width * along, rect.minY - margin)
        }
        let to = SIMD2(Double(center.x), Double(center.y)) - p
        let d = max(simd_length(to), 1)
        let toward = to / d
        let side = SIMD2(-toward.y, toward.x) * (Double.random(in: 0..<1, using: &rng) < 0.5 ? -1 : 1)
        let speed = Double.random(in: 180...360, using: &rng)
        streams.append(Stream(position: p, velocity: (toward + side * Double.random(in: 0.3...0.9, using: &rng)) * speed,
                              gold: Double.random(in: 0..<1, using: &rng) < 0.3, width: Double.random(in: 7...12, using: &rng)))
    }

    // MARK: Drawing

    func washes() -> [SaiyanWash] {
        var out: [SaiyanWash] = []
        let pulse = 0.92 + 0.08 * sin(time * 2 * .pi * 1.3)
        if shown > 0.004, radius > 1 {
            let body = shown * (phase == .impact ? 0.5 : 1)
            // The light it throws on the room, a corona hugging the rim, and a far halo of soft gold.
            out.append(SaiyanWash(center: center, radius: radius * 2.7 + 30, colour: colour, alpha: 0.32 * body * (0.5 + 0.5 * charge)))
            out.append(SaiyanWash(center: center, radius: radius * 1.5 + 8, colour: SaiyanOrbKit.lift(colour, 0.35), alpha: 0.32 * body * pulse))
            out.append(SaiyanWash(center: center, radius: radius * 3.8 + 40, colour: Self.gold, alpha: 0.09 * body * charge))
        }
        if phase == .falling {
            // Its wake: the glow stretched back up the way it came.
            let k = SaiyanOrbKit.clamp01(phaseTime / Self.fallSeconds)
            for (i, f) in [0.9, 1.9, 3.0].enumerated() {
                let p = SaiyanOrbKit.point(center, SaiyanOrbKit.unit(fallFrom - fallTo), radius * f * (0.4 + k))
                out.append(SaiyanWash(center: p, radius: radius * (1.3 - 0.25 * Double(i)), colour: SaiyanOrbKit.lift(colour, 0.3), alpha: 0.32 * (1 - 0.28 * Double(i))))
            }
        }
        if phase == .impact {
            let t = phaseTime
            out.append(SaiyanWash(center: fallTo, radius: rect.width * (0.22 + 0.4 * SaiyanOrbKit.easeOut(t / 0.5)), colour: SaiyanOrbKit.lift(colour, 0.5),
                                  alpha: 0.85 * exp(-t / 0.38)))
            // The dome of the blast swelling off the floor.
            out.append(SaiyanWash(center: fallTo, radius: fallRadius * 2 * (1 + 1.2 * SaiyanOrbKit.easeOut(t / 0.6)), colour: SaiyanOrbKit.lift(colour, 0.8),
                                  alpha: 0.9 * (1 - SaiyanOrbKit.smooth(t / 0.7))))
        }
        return out
    }

    func drawSolids(in ctx: CGContext) {
        // In the blast the ball bursts into light: the solid only lasts the first instant.
        let alpha = phase == .impact ? shown * (1 - SaiyanOrbKit.smooth(phaseTime / 0.16)) : shown
        guard alpha > 0.004, radius > 2 else { return }
        // A shell of the deep colour that hides what is behind the ball, so the light added over it reads as a dense sphere and not a
        // haze. The brightness itself is light (see `drawSphere`), so it blooms and stays white-hot when the room is darkened.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func stop(_ k: Double, _ shade: Double, _ a: Double) -> CGColor {
            let rgb = SaiyanOrbKit.lift(colour, k) * shade
            return CGColor(colorSpace: space, components: [rgb.x, rgb.y, rgb.z, a * alpha])!
        }
        let stops = [stop(0.3, 1, 0.92), stop(0.02, 0.88, 0.9), stop(0, 0.68, 0.82), stop(0, 0.55, 0)] as CFArray
        guard let shell = CGGradient(colorsSpace: space, colors: stops, locations: [0, 0.6, 0.9, 1]) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.drawRadialGradient(shell, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius * 1.02, options: [])
        ctx.restoreGState()
    }

    func drawLight(in ctx: CGContext) {
        guard hasLight else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        drawStreams(ctx)
        if shown > 0.004, radius > 2, phase != .impact { drawSphere(ctx) }
        if phase == .impact { drawImpact(ctx) }
        drawSparks(ctx)
        ctx.restoreGState()
    }

    private func drawSphere(_ ctx: CGContext) {
        let r = radius, c = center, s = shown
        let pulse = 0.9 + 0.1 * sin(time * 2 * .pi * 1.3)
        // The body of light: a white-hot heart, the colour through the body, and the limb brightening again at the edge where a
        // glowing ball is seen through the most of itself.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func stop(_ k: Double, _ a: Double) -> CGColor {
            let rgb = SaiyanOrbKit.lift(colour, k)
            return CGColor(colorSpace: space, components: [rgb.x, rgb.y, rgb.z, min(1, a * s)])!
        }
        let stops = [stop(1, 0.8 * pulse), stop(0.65, 0.5 * pulse), stop(0.28, 0.3), stop(0.08, 0.24), stop(0.45, 0.42), stop(0, 0)] as CFArray
        if let body = CGGradient(colorsSpace: space, colors: stops, locations: [0, 0.22, 0.55, 0.84, 0.95, 1]) {
            ctx.drawRadialGradient(body, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        }
        // Energy churning over the surface: motes riding round the ball on a tilted spin, bright on the near side and dim behind,
        // sliding along the rim where the ball turns away.
        let tilt = 0.42, ct = cos(tilt), st = sin(tilt)
        let motes = 12 + Int(14 * charge)
        let hot = SaiyanOrbKit.lift(colour, 0.75)
        for k in 0..<motes {
            let h1 = WorldKit.hash(k &* 97 &+ 13), h2 = WorldKit.hash(k &* 31 &+ 7), h3 = WorldKit.hash(k &* 57 &+ 3)
            let lat = (h1 * 2 - 1) * 1.2
            let theta = h2 * 2 * .pi + time * (0.6 + 0.8 * h3) * (k % 3 == 0 ? -1 : 1)
            let x = cos(lat) * cos(theta), y = sin(lat), z = cos(lat) * sin(theta)
            let y2 = y * ct - z * st, z2 = y * st + z * ct
            let near = max(0, z2)
            let p = CGPoint(x: c.x + x * r * 0.93, y: c.y + y2 * r * 0.93)
            SaiyanOrbKit.glow(ctx, at: p, radius: max(3, r * (0.03 + 0.035 * h3)) * (0.7 + 0.5 * near), colour: hot, alpha: (0.15 + 0.6 * near) * s)
        }
        // A soft rim, and a pulse of gold-touched corona leaving it.
        SaiyanOrbKit.ring(ctx, center: c, radius: r * 0.975, width: max(1.5, r * 0.02), colour: colour, alpha: 0.4 * s, thread: false)
        let p = (time * 0.65).truncatingRemainder(dividingBy: 1)
        SaiyanOrbKit.ring(ctx, center: c, radius: r * (1.02 + 0.22 * p), width: max(1.2, r * 0.016), colour: SaiyanOrbKit.mix(colour, Self.gold, 0.45),
                          alpha: 0.45 * (1 - p) * (1 - p) * s * min(1, charge * 3 + 0.3), thread: false)
        let arcs = phase == .gathering || phase == .falling ? Int((1 + 3 * power) * charge + 0.5) : 0
        SaiyanOrbKit.crackle(ctx, around: c, radius: r, count: arcs, beat: frame / 2, salt: 41, colour: colour, strength: 0.8 * s)
    }

    private func drawStreams(_ ctx: CGContext) {
        let blue = SaiyanOrbKit.lift(colour, 0.35)
        let scale = rect.width / 1280
        for s in streams {
            let speed = simd_length(s.velocity)
            guard speed > 1 else { continue }
            // A soft comet's tail, brightest at the head: no hard dot, no hard edge.
            let tone = s.gold ? Self.gold : blue
            guard let tail = WorldKit.comet(tone.x, tone.y, tone.z) else { continue }
            let alpha = min(1, s.age / 0.3) * max(0, s.fade) * 0.9
            let length = min(190, max(50, speed * 0.11)) * scale
            ctx.saveGState()
            ctx.translateBy(x: s.position.x, y: s.position.y)
            ctx.rotate(by: CGFloat(atan2(s.velocity.y, s.velocity.x)))
            ctx.setAlpha(CGFloat(alpha))
            ctx.draw(tail, in: CGRect(x: -length, y: -s.width / 2, width: length * 1.04, height: s.width))
            ctx.restoreGState()
        }
    }

    private func drawImpact(_ ctx: CGContext) {
        let t = phaseTime
        let scale = rect.width / 1280
        // The shock rolling out along the floor: a broad soft ring with a bright edge, and a thinner one chasing it.
        for (k, delay) in [0.0, 0.16].enumerated() {
            let u = (t - delay) / 0.95
            guard u > 0, u < 1 else { continue }
            let r = fallRadius * 0.6 + SaiyanOrbKit.easeOut(u) * rect.width * (0.64 + 0.1 * Double(k))
            let fade = (1 - u) * (1 - u)
            if k == 0 {
                SaiyanOrbKit.ring(ctx, center: fallTo, radius: r, squash: 0.26, width: 22 * scale * (1 - 0.4 * u), colour: colour, alpha: 0.35 * fade, thread: false)
            }
            SaiyanOrbKit.ring(ctx, center: fallTo, radius: r, squash: 0.26, width: (3 - Double(k)) * scale, colour: k == 1 ? SaiyanOrbKit.mix(colour, Self.gold, 0.5) : SaiyanOrbKit.lift(colour, 0.6),
                              alpha: fade, thread: false)
        }
        // Slim shafts of light thrown up out of the blast.
        let rise = SaiyanOrbKit.easeOut(t / 0.2), fade = 1 - SaiyanOrbKit.smooth(t / 0.65)
        guard fade > 0.004 else { return }
        for k in 0..<7 {
            let a = 0.5 + (Double.pi - 1.0) * Double(k) / 6 + 0.1 * sin(Double(k) * 7.3)
            let length = (240 + 420 * WorldKit.hash(k &* 31 &+ thrown)) * scale * rise * (0.8 + 0.4 * power)
            SaiyanOrbKit.ray(ctx, from: fallTo, angle: a, length: length, width: (7 + 5 * WorldKit.hash(k &+ 9)) * scale, colour: SaiyanOrbKit.lift(colour, 0.4),
                             alpha: 0.85 * fade)
        }
    }

    private func drawSparks(_ ctx: CGContext) {
        guard !sparks.particles.isEmpty else { return }
        let blue = SaiyanOrbKit.lift(colour, 0.5)
        for p in sparks.particles {
            let k = p.progress
            let at = CGPoint(x: p.position.x, y: p.position.y)
            switch p.kind {
            case 2:
                // A glint where a stream landed on the sphere.
                SaiyanOrbKit.glint(ctx, at: at, radius: p.size * 2.4 * (1 - 0.5 * k), colour: p.hue > 0.5 ? Self.gold : blue, alpha: (1 - k) * shown)
            default:
                let tone = p.hue < 0.25 ? Self.gold : blue
                let fade = (1 - k * k) * min(1, p.age / 0.06)
                let speed = simd_length(p.velocity)
                if p.kind == 1, speed > 220 {
                    SaiyanOrbKit.streak(ctx, head: at, angle: atan2(p.velocity.y, p.velocity.x), length: min(30, speed * 0.03), width: p.size * 1.8, colour: tone,
                                        alpha: fade, core: 1)
                }
                SaiyanOrbKit.glow(ctx, at: at, radius: p.size * 2.2 * (0.6 + 0.4 * (1 - k)), colour: tone, alpha: fade)
            }
        }
    }
}
