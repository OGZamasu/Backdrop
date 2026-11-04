import CoreGraphics
import Foundation
import simd

/// Destructo Disc. Hold one flat hand up above your head and a big saw blade of light spins up over it: a solid pale-gold disc with
/// serrated teeth turning at its rim, humming and throwing sparks. Flick the hand and it takes off that way, speeding up and spinning
/// faster, trailing rings, and slices a bright cut across the picture that lingers and fades. It flashes where it leaves the picture.
/// A new disc can be raised a second later.
final class DestructoDiscMove: SaiyanMove {
    let id = "destructo-disc"
    let name = "Destructo Disc"
    let hint = "Raise one flat hand above your head and hold, then flick it."

    enum Phase: Equatable { case idle, posing, holding, flying, dissolving }

    /// Pale gold with a blush of pink: the move's own colour. The rim leans further into the pink.
    static let signature = SIMD3<Double>(1.0, 0.84, 0.66)
    static let blush = SIMD3<Double>(1.0, 0.56, 0.62)

    static let claimSeconds = 0.12
    static let holdSeconds = 0.5
    /// Seconds for the disc to spin up to full size once the pose is held.
    static let growSeconds = 0.55
    /// The disc's radius at full size, in palm lengths, at base power: about two palm lengths across, a little more as the form grows.
    static let size = 0.95
    /// The disc is seen nearly face-on, tipped back a little so it still reads as a spinning blade: its height over its width.
    static let squash = 0.7
    static let teeth = 18
    /// A throw: the palm moving at least this fast, in palm lengths a second (and at least `flickPixels` pixels a second at 1280 wide).
    static let flickSpeed = 8.0
    static let flickPixels = 650.0
    static let minimumCharge = 0.45
    /// While posing the hand must be calmer than this, in palm lengths a second over the last 0.4 s, so a hand waving hello up high does
    /// not count (a friendly wave averages about 3; a hand held up still, under 0.5).
    static let calmSpeed = 1.8
    /// How long the pose may be lost before the disc fades out.
    static let graceSeconds = 0.4
    static let cooldownSeconds = 1.0
    /// How long the cut left in the air takes to fade.
    static let cutLife = 0.8
    /// Space kept between the disc and the edge of the picture, in pixels at 1280 wide.
    static let margin = 12.0

    private(set) var phase = Phase.idle
    /// 0...1: how far the disc has spun up.
    private(set) var charge = 0.0
    private(set) var center = CGPoint.zero
    private(set) var radius = 0.0
    private(set) var thrown = 0
    /// Where a thrown disc is heading, as a unit vector.
    private(set) var heading = CGVector(dx: 1, dy: 0)
    /// How flat the disc looks right now (`squash` while held, flatter as it banks in flight).
    private(set) var flatness = DestructoDiscMove.squash

    private var poseFor = 0.0
    private var brokenFor = 0.0
    private var phaseTime = 0.0
    private var cooldown = 0.0
    private var handID: Int?
    private var hand: HandState?
    private var fullRadius = 90.0
    private var shown = 0.0
    private var spin = 0.0
    private var spinRate = 3.6
    private var tilt = 0.0
    private var speed = 0.0
    private var topSpeed = 1800.0
    private var cut: [(point: CGPoint, time: Double)] = []
    /// Rings left behind in flight, fading: where, how big, at what bank, and when.
    private var wake: [(center: CGPoint, radius: Double, tilt: Double, time: Double)] = []
    private var lastWake = -9.0
    /// Where and when a thrown disc left the picture.
    private var exit: (point: CGPoint, time: Double)?
    private var trail = SaiyanHandTrail()
    private var spring = SaiyanSpring(omega: 14)
    private var sparks = ParticleSystem(capacity: 200)
    private var rng = SplitMix64(seed: 0xD15C)
    private var owed = 0.0
    private var colour = DestructoDiscMove.signature
    private var power = 0.0
    private var time = 0.0
    private var rect = CGRect(x: 0, y: 0, width: 1280, height: 720)

    init() {
        sparks.gravity = SIMD2(0, -380)
    }

    var isEngaged: Bool { phase == .posing || phase == .holding || phase == .flying }

    var hasLight: Bool {
        phase != .idle || shown > 0.004 || !sparks.particles.isEmpty || cut.contains { time - $0.time < Self.cutLife } || !wake.isEmpty
            || exit.map { time - $0.time < 0.4 } ?? false
    }

    var status: LensStatus? {
        switch phase {
        case .posing: return LensStatus("Destructo Disc", detail: "Keep your hand up")
        case .holding: return LensStatus("Destructo Disc", detail: charge >= Self.minimumCharge ? "Flick your hand to throw it" : "Keep your hand up")
        case .flying: return LensStatus("Destructo Disc!")
        default: return nil
        }
    }

    func reset() {
        phase = .idle
        charge = 0
        shown = 0
        poseFor = 0
        brokenFor = 0
        phaseTime = 0
        cooldown = 0
        handID = nil
        hand = nil
        cut.removeAll()
        wake.removeAll()
        exit = nil
        trail.reset()
        spring.reset()
        sparks.removeAll()
    }

    // MARK: Update

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) {
        let dt = WorldKit.clamped(c.dt)
        time = c.time
        rect = c.rect
        power = c.power
        colour = c.palette.tinting(Self.signature, amount: 0.5)
        trail.update(c.hands, time: c.time)
        cooldown = max(0, cooldown - dt)
        phaseTime += dt
        let raised = raisedHand(c)
        let calm = raised.map { trail.meanSpeed($0.id, over: 0.4) < Self.calmSpeed } ?? false

        switch phase {
        case .idle:
            if mayBegin, cooldown <= 0, let raised, calm {
                poseFor += dt
                if poseFor >= Self.claimSeconds {
                    phase = .posing
                    phaseTime = 0
                    handID = raised.id
                    hand = raised
                    spring.reset()
                }
            } else {
                poseFor = 0
            }
        case .posing:
            if let raised, calm, isSameHand(raised) {
                hand = raised
                poseFor += dt
                brokenFor = 0
                if poseFor >= Self.holdSeconds {
                    phase = .holding
                    phaseTime = 0
                    charge = 0
                }
            } else {
                brokenFor += dt
                if brokenFor > 0.2 { settle() }
            }
        case .holding:
            if let id = handID, let now = c.hands.first(where: { $0.id == id }) {
                hand = now
                if let flick = flick(now) {
                    launch(flick)
                    break
                }
            }
            if let raised, isSameHand(raised) {
                brokenFor = 0
                charge = min(1, charge + dt / Self.growSeconds)
            } else {
                brokenFor += dt
                // Long enough to ride out a tracker dropout and the gesture reader confirming the open hand again afterwards.
                if brokenFor > Self.graceSeconds {
                    phase = .dissolving
                    phaseTime = 0
                }
            }
        case .flying:
            fly(dt: dt)
        case .dissolving:
            if phaseTime > 0.45 { settle() }
        }

        advanceDisc(dt: dt)
        cut.removeAll { time - $0.time > Self.cutLife }
        wake.removeAll { time - $0.time > 0.26 }
        sparks.step(dt) { p in p.velocity *= exp(-1.4 * dt) }
    }

    private func settle() {
        phase = .idle
        phaseTime = 0
        poseFor = 0
        brokenFor = 0
        charge = 0
        handID = nil
    }

    /// The hand holding the disc, or the same hand back under a new id after the tracker lost it: one close to where it was.
    private func isSameHand(_ raised: HandState) -> Bool {
        if raised.id == handID { return true }
        guard let last = hand, HandState.distance(last.palm, raised.palm) < last.size * 2 else { return false }
        handID = raised.id
        return true
    }

    /// The one open hand held up over the head, the other hand (if any) not up there with it: two hands up is the Spirit Bomb.
    private func raisedHand(_ c: SaiyanMoveContext) -> HandState? {
        guard let face = c.face else { return nil }
        let overhead = c.hands.filter { SaiyanZones.isOverhead($0, face) }
        guard overhead.count == 1, let hand = overhead.first, c.gestures.pose(of: hand.id) == .openPalm else { return nil }
        return hand
    }

    /// The direction and speed of a flick, if the palm is moving fast enough to be one.
    private func flick(_ hand: HandState) -> (direction: CGVector, speed: Double)? {
        let own = trail.velocity(hand.id, over: 0.1, fallback: hand.velocity)
        let v = SaiyanOrbKit.length(hand.velocity) > SaiyanOrbKit.length(own) ? hand.velocity : own
        let speed = SaiyanOrbKit.length(v)
        guard charge >= Self.minimumCharge, speed / hand.size >= Self.flickSpeed, speed >= Self.flickPixels * rect.width / 1280 else { return nil }
        return (SaiyanOrbKit.unit(v), speed)
    }

    private func launch(_ flick: (direction: CGVector, speed: Double)) {
        // The disc starts up by the top edge, so a sideways flick with a little lift in the wrist is levelled out rather than throwing it
        // straight out of view. A throw forward and down keeps its line and cuts across the picture.
        let d = flick.direction
        heading = d.dy > 0 && d.dy < abs(d.dx) * 2 ? SaiyanOrbKit.unit(CGVector(dx: d.dx, dy: d.dy * 0.35)) : d
        // It leaves the hand briskly and speeds up from there.
        topSpeed = max(1900 * rect.width / 1280, flick.speed * 1.5)
        speed = topSpeed * 0.3
        cut = [(center, time)]
        wake.removeAll()
        exit = nil
        radius = fullRadius * (0.85 + 0.15 * charge)
        phase = .flying
        phaseTime = 0
        cooldown = Self.cooldownSeconds
        thrown += 1
        burst(at: center, count: 16, speed: 120...420)
    }

    private func fly(dt: Double) {
        speed += (topSpeed - speed) * (1 - exp(-dt / 0.13))
        center.x += heading.dx * speed * dt
        center.y += heading.dy * speed * dt
        cut.append((center, time))
        if time - lastWake > 0.055 {
            wake.append((center, radius, tilt, time))
            lastWake = time
        }
        spawnSparks(dt: dt, rate: 110)
        // A flash where it crosses the edge of the picture.
        if exit == nil, !rect.contains(center) {
            let p = CGPoint(x: min(rect.maxX, max(rect.minX, center.x)), y: min(rect.maxY, max(rect.minY, center.y)))
            exit = (p, time)
            burst(at: p, count: 22, speed: 160...520)
        }
        let margin = radius * 1.2 + 20
        if !rect.insetBy(dx: -margin, dy: -margin).contains(center) {
            phase = .idle
            phaseTime = 0
            poseFor = 0
            charge = 0
            handID = nil
        }
    }

    private func burst(at p: CGPoint, count: Int, speed: ClosedRange<Double>) {
        for _ in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: speed, using: &rng)
            sparks.emit(Particle(position: SIMD2(Double(p.x), Double(p.y)), velocity: SIMD2(cos(a), sin(a)) * s,
                                 life: Double.random(in: 0.22...0.5, using: &rng), size: Double.random(in: 1.8...3.6, using: &rng)))
        }
    }

    private func advanceDisc(dt: Double) {
        spin += dt * spinRate
        switch phase {
        case .idle:
            shown = max(0, shown - dt / 0.2)
        case .posing, .holding:
            guard let hand else { break }
            fullRadius = hand.size * Self.size * (1 + 0.15 * power)
            // A small seed of light while the pose is held, then the disc spins up out of it with a little overshoot.
            let seed = 0.12 * SaiyanOrbKit.smooth(poseFor / Self.holdSeconds)
            let grow = phase == .holding ? 0.12 + 0.88 * SaiyanOrbKit.easeOutBack(charge, overshoot: 1.25) : seed
            radius = fullRadius * max(0, grow)
            center = spring.update(place(over: hand), dt: dt)
            // The disc stays nearly level, leaning a little with the hand.
            let axis = hand.axis
            let lean = atan2(Double(axis.dy), Double(axis.dx)) - .pi / 2
            tilt += (lean * 0.3 - tilt) * (1 - exp(-dt / 0.15))
            flatness += (Self.squash - flatness) * (1 - exp(-dt / 0.1))
            shown = min(1, shown + dt / 0.15)
            spinRate = 3.4 + 1.6 * charge
            if phase == .holding { spawnSparks(dt: dt, rate: (30 + 50 * power) * charge) }
        case .flying:
            // It banks toward the way it is going, like a thrown plate, and spins harder.
            var bank = atan2(Double(heading.dy), Double(heading.dx))
            if bank > .pi / 2 { bank -= .pi } else if bank < -.pi / 2 { bank += .pi }
            tilt += (bank * 0.55 - tilt) * (1 - exp(-dt / 0.08))
            flatness += (Self.squash * 0.78 - flatness) * (1 - exp(-dt / 0.1))
            spinRate += (5.2 - spinRate) * (1 - exp(-dt / 0.1))
            shown = 1
        case .dissolving:
            radius *= exp(-dt / 0.35)
            shown = 1 - SaiyanOrbKit.smooth(phaseTime / 0.45)
            spinRate = 6
        }
    }

    /// Where the full-size disc sits for a raised hand: over the fingertips along the hand when there is room, and otherwise brought down
    /// and in until the whole disc is in the picture, in front of the fingers (a raised hand often reaches the top edge of a webcam).
    private func place(over hand: HandState) -> CGPoint {
        let r = fullRadius, half = fullRadius * Self.squash
        let gap = Self.margin * rect.width / 1280
        var p = SaiyanOrbKit.point(hand.palm, hand.axis, hand.size * 1.2 + half * 0.95)
        p.y = min(p.y, rect.maxY - half - gap)
        p.y = max(p.y, rect.minY + half + gap)
        p.x = max(rect.minX + r + gap, min(rect.maxX - r - gap, p.x))
        return p
    }

    /// Sparks thrown off the turning edge.
    private func spawnSparks(dt: Double, rate: Double) {
        owed += dt * rate
        while owed >= 1 {
            owed -= 1
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            // A point on the rim of the tipped disc, and the way the rim is moving there.
            let local = SIMD2(cos(a) * radius, sin(a) * radius * flatness)
            let along = SIMD2(-sin(a), cos(a) * flatness)
            let c = cos(tilt), s = sin(tilt)
            let p = SIMD2(local.x * c - local.y * s, local.x * s + local.y * c)
            let t = SIMD2(along.x * c - along.y * s, along.x * s + along.y * c)
            let speed = Double.random(in: 180...480, using: &rng)
            sparks.emit(Particle(position: SIMD2(Double(center.x), Double(center.y)) + p, velocity: t * speed + SIMD2(0, 40),
                                 life: Double.random(in: 0.15...0.38, using: &rng), size: Double.random(in: 1.4...3.0, using: &rng)))
        }
    }

    // MARK: Drawing

    /// The serrated outline of the disc in its own plane, `r` across, turned by `turn`: each tooth ramps out and drops back sharply, its
    /// cutting face leading the way it spins.
    private func outline(radius r: Double, turn: Double) -> CGPath {
        let n = Self.teeth, step = 2 * Double.pi / Double(n)
        var points: [CGPoint] = []
        points.reserveCapacity(n * 2)
        for i in 0..<n {
            let a = turn + Double(i) * step, b = a + step * 0.8
            points.append(CGPoint(x: cos(a) * r * 0.84, y: sin(a) * r * 0.84))
            points.append(CGPoint(x: cos(b) * r, y: sin(b) * r))
        }
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    /// Moves the context into the disc's own plane: centred on it, banked by `tilt` and tipped back by `flatness`.
    private func enterPlane(_ ctx: CGContext, at c: CGPoint, tilt: Double, flatness: Double) {
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(tilt))
        ctx.scaleBy(x: 1, y: CGFloat(flatness))
    }

    func washes() -> [SaiyanWash] {
        var out: [SaiyanWash] = []
        if shown > 0.004, radius > 1 {
            // The hum: a glow round the disc that shivers with the spin.
            let hum = 0.9 + 0.1 * sin(time * 47)
            let k = shown * (phase == .flying ? 1 : 0.35 + 0.65 * charge)
            out.append(SaiyanWash(center: center, radius: radius * 1.9 + 16, colour: colour, alpha: 0.3 * k * hum))
        }
        if let exit, time - exit.time < 0.4 {
            let t = (time - exit.time) / 0.4
            out.append(SaiyanWash(center: exit.point, radius: (120 + 120 * t) * rect.width / 1280, colour: SaiyanOrbKit.lift(colour, 0.5),
                                  alpha: 0.75 * (1 - t) * (1 - t)))
        }
        return out
    }

    /// The body of the disc, painted solid: pale gold in the middle shading to pink at the teeth, with turned grooves and a bright hub.
    func drawSolids(in ctx: CGContext) {
        guard shown > 0.004, radius > 2 else { return }
        let r = radius, s = shown
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let rim = SaiyanOrbKit.mix(colour, Self.blush, 0.55)
        func stop(_ c: SIMD3<Double>, _ a: Double) -> CGColor { CGColor(colorSpace: space, components: [c.x, c.y, c.z, a * s])! }
        let stops = [stop(SaiyanOrbKit.lift(colour, 0.7), 0.92), stop(SaiyanOrbKit.lift(colour, 0.25), 0.92), stop(colour, 0.94),
                     stop(rim, 0.96), stop(rim * 0.92, 0.96)] as CFArray
        guard let body = CGGradient(colorsSpace: space, colors: stops, locations: [0, 0.3, 0.62, 0.86, 1]) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        enterPlane(ctx, at: center, tilt: tilt, flatness: flatness)
        ctx.saveGState()
        ctx.addPath(outline(radius: r, turn: spin))
        ctx.clip()
        ctx.drawRadialGradient(body, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
        ctx.restoreGState()
        // Turned grooves and the hub: machined, not a flat token.
        ctx.setLineWidth(CGFloat(max(1, r * 0.014)))
        ctx.setStrokeColor(SaiyanOrbKit.cg(rim * 0.85, 0.55 * s))
        for k in [0.36, 0.6] { ctx.strokeEllipse(in: CGRect(x: -r * k, y: -r * k, width: r * k * 2, height: r * k * 2)) }
        ctx.setFillColor(SaiyanOrbKit.cg(SaiyanOrbKit.lift(colour, 0.85), 0.95 * s))
        ctx.fillEllipse(in: CGRect(x: -r * 0.1, y: -r * 0.1, width: r * 0.2, height: r * 0.2))
        ctx.restoreGState()
    }

    func drawLight(in ctx: CGContext) {
        guard hasLight else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        drawCut(ctx)
        drawWake(ctx)
        if shown > 0.004, radius > 1 {
            if phase == .holding || phase == .posing, let hand { drawStem(ctx, hand) }
            drawDisc(ctx)
        }
        drawExit(ctx)
        drawSparks(ctx)
        ctx.restoreGState()
    }

    /// A thin thread of light from the fingertips up to the disc it holds, when it floats clear above them (not when it has been brought
    /// down in front of the hand).
    private func drawStem(_ ctx: CGContext, _ hand: HandState) {
        let tip = hand[.middleTip]
        let ahead = Double((center.x - tip.x) * hand.axis.dx + (center.y - tip.y) * hand.axis.dy)
        guard ahead - radius * flatness > 12 else { return }
        SaiyanOrbKit.sliver(ctx, from: tip, to: center, width: max(6, radius * 0.08), colour: colour, alpha: 0.5 * shown * charge, core: 0.6)
    }

    private func drawDisc(_ ctx: CGContext) {
        let r = radius, s = shown
        let hot = SaiyanOrbKit.lift(colour, 0.7)
        ctx.saveGState()
        enterPlane(ctx, at: center, tilt: tilt, flatness: flatness)
        ctx.setLineJoin(.miter)
        // The teeth catch the light: a rim-lit edge, with a fainter copy a little behind in the turn so they blur like a blade spinning.
        ctx.setLineWidth(CGFloat(max(2, r * 0.032)))
        ctx.setStrokeColor(SaiyanOrbKit.cg(SaiyanOrbKit.mix(colour, Self.blush, 0.4), 0.22 * s))
        ctx.addPath(outline(radius: r, turn: spin - 0.09))
        ctx.strokePath()
        ctx.setLineWidth(CGFloat(max(1.5, r * 0.018)))
        ctx.setStrokeColor(SaiyanOrbKit.cg(hot, 0.85 * s))
        ctx.addPath(outline(radius: r, turn: spin))
        ctx.strokePath()
        // The white-hot cutting edge inside the teeth.
        ctx.setLineWidth(CGFloat(max(1.2, r * 0.014)))
        ctx.setStrokeColor(SaiyanOrbKit.cg(SaiyanOrbKit.white, 0.8 * s))
        ctx.strokeEllipse(in: CGRect(x: -r * 0.8, y: -r * 0.8, width: r * 1.6, height: r * 1.6))
        // Motion arcs just outside the rim, sweeping round faster than the teeth.
        ctx.setLineCap(.round)
        let sweep = spin * 1.7
        for k in 0..<3 {
            let a0 = sweep - Double(k) * 2.1
            let rr = r * (1.07 + 0.04 * Double(k))
            for (from, to, alpha) in [(a0 - 0.95, a0 - 0.45, 0.25), (a0 - 0.45, a0, 0.6)] {
                ctx.setLineWidth(CGFloat(max(1.2, r * 0.016)))
                ctx.setStrokeColor(SaiyanOrbKit.cg(hot, alpha * s))
                ctx.beginPath()
                ctx.addArc(center: .zero, radius: CGFloat(rr), startAngle: CGFloat(from), endAngle: CGFloat(to), clockwise: false)
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
        // A glint where the light catches the front of the blade.
        let c = cos(tilt), sn = sin(tilt)
        let fx = -0.5 * r, fy = -0.55 * r * flatness
        SaiyanOrbKit.glint(ctx, at: CGPoint(x: center.x + fx * c - fy * sn, y: center.y + fx * sn + fy * c), radius: max(10, r * 0.3), colour: hot,
                           alpha: (0.6 + 0.3 * sin(time * 13)) * s)
    }

    /// Rings left behind as it flies, each fading and opening out a little.
    private func drawWake(_ ctx: CGContext) {
        for w in wake {
            let k = (time - w.time) / 0.26
            guard k < 1 else { continue }
            SaiyanOrbKit.ring(ctx, center: w.center, radius: w.radius * (0.95 + 0.25 * k), squash: flatness, angle: w.tilt, width: max(1.5, w.radius * 0.03),
                              colour: colour, alpha: 0.7 * (1 - k) * (1 - k), thread: k < 0.4)
        }
    }

    /// A flash and a ring where the disc leaves the picture.
    private func drawExit(_ ctx: CGContext) {
        guard let exit, time - exit.time < 0.4 else { return }
        let k = (time - exit.time) / 0.4
        let scale = rect.width / 1280
        SaiyanOrbKit.glint(ctx, at: exit.point, radius: (70 + 50 * k) * scale, colour: SaiyanOrbKit.lift(colour, 0.6), alpha: 1 - SaiyanOrbKit.smooth(k))
        SaiyanOrbKit.ring(ctx, center: exit.point, radius: (30 + 150 * SaiyanOrbKit.easeOut(k)) * scale, width: 4 * scale, colour: colour,
                          alpha: (1 - k) * (1 - k))
    }

    /// The cut through the air: a bold white-hot line along the disc's path, pointed where it leaves the hand and where it runs into the
    /// disc, thinning from its oldest end and fading as a whole once the disc has gone. One slim shape for the glow and one for the core,
    /// so a long cut costs no more than a short one.
    private func drawCut(_ ctx: CGContext) {
        guard cut.count > 1, let first = cut.first, let last = cut.last else { return }
        let fresh = 1 - SaiyanOrbKit.clamp01((time - last.time) / Self.cutLife)
        guard fresh > 0.004 else { return }
        let n = SaiyanOrbKit.unit(CGVector(dx: -(last.point.y - first.point.y), dy: last.point.x - first.point.x))
        let width = (26 + 12 * power) * rect.width / 1280
        let total = HandState.distance(first.point, last.point)
        // While the disc flies the cut stops at its trailing rim rather than running across its face.
        let behind = phase == .flying ? radius * 0.8 : 0, headRun = phase == .flying ? radius * 0.6 : 1, tailRun = 36 * rect.width / 1280
        let shape = cut.map { p -> Double in
            let along = HandState.distance(first.point, p.point)
            return SaiyanOrbKit.smooth(along / tailRun) * SaiyanOrbKit.smooth((total - along - behind) / headRun)
        }
        func band(_ w: Double) -> [CGPoint] {
            let widths = zip(cut, shape).map { w * $0.1 * pow(1 - SaiyanOrbKit.clamp01((time - $0.0.time) / Self.cutLife), 0.7) }
            let left = zip(cut, widths).map { SaiyanOrbKit.point($0.0.point, n, $0.1 / 2) }
            let right = zip(cut, widths).map { SaiyanOrbKit.point($0.0.point, n, -$0.1 / 2) }
            return left + right.reversed()
        }
        let alpha = pow(fresh, 1.1)
        for (w, c, a) in [(width, SaiyanOrbKit.mix(colour, Self.blush, 0.25), 0.7), (width * 0.42, SaiyanOrbKit.lift(colour, 0.6), 0.85),
                          (width * 0.16, SaiyanOrbKit.white, 1.0)] {
            ctx.setFillColor(SaiyanOrbKit.cg(c, a * alpha))
            ctx.beginPath()
            ctx.addLines(between: band(w))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    private func drawSparks(_ ctx: CGContext) {
        guard !sparks.particles.isEmpty else { return }
        let hot = SaiyanOrbKit.lift(colour, 0.5)
        for p in sparks.particles {
            let fade = 1 - p.progress
            let at = CGPoint(x: p.position.x, y: p.position.y)
            let speed = simd_length(p.velocity)
            if speed > 220 {
                SaiyanOrbKit.streak(ctx, head: at, angle: atan2(p.velocity.y, p.velocity.x), length: min(20, speed * 0.04), width: p.size * 2, colour: hot,
                                    alpha: fade, core: 1)
            }
            SaiyanOrbKit.glow(ctx, at: at, radius: p.size * 2.2 * (0.6 + 0.4 * fade), colour: hot, alpha: fade)
        }
    }
}
