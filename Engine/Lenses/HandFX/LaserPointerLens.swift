import CoreGraphics
import CoreImage
import simd

/// A laser beam that shoots from the tip of a pointing finger, along the finger, to the edge of the picture, where it makes a hot dot and
/// a spray of sparks. A finger pointing at the camera has no direction to shoot in, so it gets a glowing dot on the fingertip instead.
struct LaserPointerRig {
    /// What the rig remembers about one hand's aim.
    struct Aim {
        /// Where the finger points, in radians, smoothed so the far end of a long beam does not shake with every tracking error.
        var angle = 0.0
        var known = false
        /// 0...1: how much the hand is pointing. Eases in and out so the beam does not flicker with the pose.
        var pointing = 0.0
    }

    /// A beam ready to draw.
    struct Beam {
        var hand: Int
        var from: CGPoint
        var to: CGPoint
        var direction: SIMD2<Double>
        /// 0...1: how bright, taking the hand's fading into account.
        var strength: Double
    }

    /// The glowing dot that stands in for the beam when the finger points at the camera.
    struct Dot {
        var hand: Int
        var at: CGPoint
        var strength: Double
    }

    /// The finger counts as pointing at the camera when it looks shorter than this part of a palm; across the picture it looks about 0.85.
    /// A finger the tracker still calls extended is never much shorter than 0.47, so the dot takes over just below 0.5.
    static let towardCameraBelow = 0.50
    static let fullBeamAbove = 0.70

    let size: CGSize
    private(set) var memory = HandFXMemory<Aim>()
    private(set) var sparks = ParticleSystem(capacity: 160)
    private var rng = SplitMix64(seed: 0x1A5E2)
    private var rect: CGRect { CGRect(origin: .zero, size: size) }

    init(size: CGSize) {
        self.size = size
        sparks.gravity = SIMD2(0, -650)
    }

    mutating func removeAll() {
        memory.removeAll()
        sparks.removeAll()
    }

    static func isPointing(_ hand: HandState) -> Bool { hand.pose == .point || hand.pose == .fingerGun }

    /// How much a hand's beam shows as a beam rather than a dot, 0...1.
    static func beamShare(of hand: HandState) -> Double { WorldKit.smoothstep(towardCameraBelow, fullBeamAbove, hand.aimLength) }

    mutating func update(hands: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        memory.update(hands, dt: dt, fade: 0.18) { _ in Aim() }
        for i in memory.entries.indices {
            let entry = memory.entries[i]
            guard entry.visible else { continue }
            var aim = entry.state
            let raw = atan2(Double(entry.hand.aim.dy), Double(entry.hand.aim.dx))
            if aim.known {
                var delta = raw - aim.angle
                delta = atan2(sin(delta), cos(delta))
                aim.angle += delta * (1 - exp(-dt / 0.05))
            } else {
                aim.angle = raw
                aim.known = true
            }
            let target = Self.isPointing(entry.hand) ? 1.0 : 0.0
            let rate = target > aim.pointing ? 1 / 0.08 : 1 / 0.12
            aim.pointing += (target - aim.pointing) * min(1, dt * rate)
            memory.modify(i) { $0.state = aim }
        }

        for beam in beams where beam.strength > 0.3 { emitSparks(for: beam, dt: dt) }
        sparks.step(dt)
    }

    /// Every beam showing now.
    var beams: [Beam] {
        memory.entries.compactMap { entry in
            let share = Self.beamShare(of: entry.hand)
            let strength = entry.state.pointing * entry.presence * share
            guard entry.state.known, strength > 0.01 else { return nil }
            let direction = SIMD2(cos(entry.state.angle), sin(entry.state.angle))
            let tip = entry.hand.indexTip
            let start = SIMD2(Double(tip.x), Double(tip.y)) + direction * entry.hand.size * 0.06
            let end = HandGeometry.exit(from: start, direction: direction, rect: rect)
            guard simd_distance(start, end) > 6 else { return nil }
            return Beam(hand: entry.hand.id, from: CGPoint(x: start.x, y: start.y), to: CGPoint(x: end.x, y: end.y), direction: direction, strength: strength)
        }
    }

    /// Every fingertip dot showing now.
    var dots: [Dot] {
        memory.entries.compactMap { entry in
            let strength = entry.state.pointing * entry.presence * (1 - Self.beamShare(of: entry.hand))
            guard strength > 0.01 else { return nil }
            return Dot(hand: entry.hand.id, at: entry.hand.indexTip, strength: strength)
        }
    }

    /// Where a beam going `direction` meets the edge, as the way back into the picture: the beam bouncing off.
    static func bounce(of direction: SIMD2<Double>, at hit: CGPoint, in rect: CGRect) -> SIMD2<Double> {
        var normal = SIMD2<Double>(0, 0)
        if abs(hit.x - rect.maxX) < 1.5 { normal.x -= 1 }
        if abs(hit.x - rect.minX) < 1.5 { normal.x += 1 }
        if abs(hit.y - rect.maxY) < 1.5 { normal.y -= 1 }
        if abs(hit.y - rect.minY) < 1.5 { normal.y += 1 }
        guard simd_length(normal) > 0 else { return -direction }
        normal = simd_normalize(normal)
        return direction - 2 * simd_dot(direction, normal) * normal
    }

    private mutating func emitSparks(for beam: Beam, dt: Double) {
        let back = Self.bounce(of: beam.direction, at: beam.to, in: rect)
        let count = Int(dt * 260 * beam.strength + Double.random(in: 0..<1, using: &rng))
        for _ in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            let v = (back * 0.7 + SIMD2(cos(a), sin(a)) * 0.9) * Double.random(in: 140...480, using: &rng)
            sparks.emit(Particle(position: SIMD2(Double(beam.to.x), Double(beam.to.y)) - beam.direction * 3, velocity: v, age: 0,
                                 life: Double.random(in: 0.2...0.55, using: &rng), size: Double.random(in: 1.6...3.6, using: &rng)))
        }
    }
}

final class LaserPointerLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig: LaserPointerRig
    private var hint = HandFXHint()
    private let published = StatusBox()
    /// The beam's cross-section, made once.
    private static let beamSprite = HandFXKit.beamSprite(SIMD3(1, 0.12, 0.2), core: 0.045, body: 0.15)

    var status: LensStatus? { published.value }

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        rig = LaserPointerRig(size: size)
        published.value = LensStatus("Hold up your hand", detail: "Point your finger")
    }

    func restart() {
        rig.removeAll()
        hint.reset()
    }

    var isHinting: Bool { hint.isShowing }
    var beams: [LaserPointerRig.Beam] { rig.beams }
    var dots: [LaserPointerRig.Dot] { rig.dots }
    var sparkCount: Int { rig.sparks.particles.count }

    func render(_ input: LensInput) -> CIImage {
        rig.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        let beams = rig.beams, dots = rig.dots
        published.value = currentStatus(input.hands, beams: beams, dots: dots)
        var out = input.composed
        if !beams.isEmpty || !dots.isEmpty || !rig.sparks.particles.isEmpty {
            // The glow where the beam lands spills softly over the picture: made on the graphics chip.
            for beam in beams {
                out = WorldKit.adding(WorldKit.wash(center: beam.to, radius: 80, red: 1, green: 0.2, blue: 0.25, alpha: 0.5 * beam.strength, in: input.rect), to: out)
            }
            if let layer = input.services.overlay({ ctx in draw(in: ctx, beams: beams, dots: dots, time: input.time) }) {
                out = HandFXLight.add(layer, to: out, rect: input.rect, bloom: 0.75)
            }
        }
        return hint.compose(over: out, services: input.services, rect: input.rect, accent: SIMD3(1, 0.3, 0.35))
    }

    private func currentStatus(_ hands: [HandState], beams: [LaserPointerRig.Beam], dots: [LaserPointerRig.Dot]) -> LensStatus {
        if hands.isEmpty { return LensStatus("Hold up your hand", detail: "Point your finger") }
        if !beams.isEmpty { return LensStatus("Laser on", detail: "Point at the edge of the picture") }
        if !dots.isEmpty { return LensStatus("Pointing at the camera", detail: "Turn your finger to aim") }
        return LensStatus("Point your finger", detail: "Index out, other fingers curled")
    }

    // MARK: Drawing

    private func draw(in ctx: CGContext, beams: [LaserPointerRig.Beam], dots: [LaserPointerRig.Dot], time: Double) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        defer { ctx.interpolationQuality = .high }
        ctx.setLineCap(.round)

        for beam in beams { drawBeam(beam, in: ctx, time: time) }
        for dot in dots { drawDot(dot, in: ctx, time: time) }

        for p in rig.sparks.particles {
            let fade = 1 - p.progress
            // White-hot, then yellow, then red as it cools, in four steps so only four sprites are ever needed.
            let k = (p.progress * 4).rounded(.down) / 4
            let r = 1.0, g = 1 - 0.65 * k, b = max(0, 0.85 - 1.3 * k)
            let at = CGPoint(x: p.position.x, y: p.position.y)
            let speed = (p.velocity.x * p.velocity.x + p.velocity.y * p.velocity.y).squareRoot()
            if speed > 120, let tail = WorldKit.comet(r, g, b) {
                let length = min(40, speed * 0.05)
                ctx.saveGState()
                ctx.translateBy(x: at.x, y: at.y)
                ctx.rotate(by: atan2(p.velocity.y, p.velocity.x))
                ctx.setAlpha(fade)
                ctx.draw(tail, in: CGRect(x: -length, y: -p.size, width: length, height: p.size * 2))
                ctx.restoreGState()
            }
            if let dot = WorldKit.softGlow(r, g, b) { ctx.stampDot(dot, at: at, radius: p.size * 2.6, alpha: fade) }
        }
    }

    private func drawBeam(_ beam: LaserPointerRig.Beam, in ctx: CGContext, time: Double) {
        let s = beam.strength
        let shimmer = 1 + 0.05 * sin(time * 71 + Double(beam.hand)) + 0.03 * sin(time * 23)
        // A tube of red light with a white-hot core, soft at every edge.
        if let sprite = Self.beamSprite {
            HandFXKit.drawBeam(sprite, from: beam.from, to: beam.to, width: 64 * shimmer, alpha: s, in: ctx)
        }

        // Dust floating in the air, lit up only where the beam passes through it.
        if let mote = WorldKit.softGlow(1, 0.6, 0.6) {
            let a = HandFXKit.vector(beam.from), b = HandFXKit.vector(beam.to)
            for k in 0..<160 {
                let x = WorldKit.hash(k) * 1300 - 10 + 14 * sin(time * 0.31 + Double(k))
                let rise = (WorldKit.hash(k + 7919) * 760 + time * (5 + 6 * WorldKit.hash(k + 31))).truncatingRemainder(dividingBy: 760) - 20
                let p = SIMD2(x, rise)
                let d = HandGeometry.distance(from: p, toSegmentFrom: a, to: b)
                guard d < 14 else { continue }
                let lit = pow(1 - d / 14, 2) * (0.6 + 0.4 * sin(time * 3 + Double(k)))
                ctx.stampDot(mote, at: HandFXKit.point(p), radius: 2.5 + 3 * WorldKit.hash(k + 3), alpha: lit * s)
            }
        }

        // The source of the beam, and the hot spot where it lands.
        if let red = WorldKit.softGlow(1, 0.15, 0.2), let white = WorldKit.softGlow(1, 0.9, 0.9) {
            ctx.stampDot(red, at: beam.from, radius: 30, alpha: 0.9 * s)
            ctx.stampDot(white, at: beam.from, radius: 9, alpha: s)
            let land = CGPoint(x: Double(beam.to.x) - beam.direction.x * 3, y: Double(beam.to.y) - beam.direction.y * 3)
            ctx.stampDot(red, at: land, radius: 46 * shimmer, alpha: s)
            ctx.stampDot(white, at: land, radius: 17, alpha: s)
            // A little star of rays round the dot, slowly turning.
            ctx.setLineWidth(2)
            ctx.setStrokeColor(CGColor(red: 1, green: 0.7, blue: 0.7, alpha: 0.7 * s))
            for k in 0..<6 {
                let a = time * 1.4 + Double(k) * .pi / 3
                let length = k % 2 == 0 ? 46.0 : 30.0
                ctx.beginPath()
                ctx.move(to: land)
                ctx.addLine(to: CGPoint(x: Double(land.x) + cos(a) * length, y: Double(land.y) + sin(a) * length))
                ctx.strokePath()
            }
        }
    }

    private func drawDot(_ dot: LaserPointerRig.Dot, in ctx: CGContext, time: Double) {
        let pulse = 1 + 0.12 * sin(time * 7)
        if let red = WorldKit.softGlow(1, 0.15, 0.2), let white = WorldKit.softGlow(1, 0.92, 0.92) {
            ctx.stampDot(red, at: dot.at, radius: 52 * pulse, alpha: dot.strength)
            ctx.stampDot(red, at: dot.at, radius: 24, alpha: dot.strength)
            ctx.stampDot(white, at: dot.at, radius: 14, alpha: dot.strength)
        }
        if let star = WorldKit.star(1, 0.55, 0.6) {
            ctx.draw(star, center: dot.at, height: 70 * pulse, rotation: CGFloat(time * 0.6), alpha: CGFloat(0.8 * dot.strength))
        }
        // A ring of dashes turning round it, like a sight.
        ctx.setLineWidth(2.5)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.6, blue: 0.62, alpha: 0.75 * dot.strength))
        let ring = 30.0
        for k in 0..<4 {
            let a = time * 1.8 + Double(k) * .pi / 2
            ctx.beginPath()
            ctx.addArc(center: dot.at, radius: ring, startAngle: a, endAngle: a + 1.0, clockwise: false)
            ctx.strokePath()
        }
    }
}
