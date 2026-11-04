import CoreGraphics
import Foundation
import simd

/// Ki Blast. Push one open palm at the camera and a round yellow burst leaves it, flying across the picture with a trail and bursting at the
/// edge. Push again and again to fire them off quickly, up to four in the air at once.
final class KiBlastMove: SaiyanMove {
    let id = "ki-blast"
    let name = "Ki Blast"
    let hint = "Push an open palm at the camera."
    private(set) var isEngaged = false

    // Thresholds, measured on `HandFixtures` and `HandState` readings (see `SaiyanBeamMoveTests`).

    /// A push: the palm this much bigger than its smallest over `pushWindow` (about 30 percent in a quarter of a second). A palm held up
    /// while talking varies by a few percent; a wave turns the hand in the picture and keeps its size.
    static let pushGrowth = 1.28
    static let pushWindow = 0.28
    /// The smallest reading must be at least this old, so one odd frame is not a push.
    static let settledFor = 0.05
    /// The palm open and read as open for this long first.
    static let openFor = 0.1
    /// Pushed, not swept: the palm travels less than this many palm lengths across the picture during the push.
    static let sweepBelow = 1.6
    /// The other hand at least this many palm lengths away (two hands together are Kamehameha or Final Flash), and the palm clear of the
    /// face (a hand by the face is not a push).
    static let aloneBeyond = 2.5
    static let faceClear = 1.6
    /// A push across the picture faster than this many palm lengths a second sends the blast that way; otherwise it flies away from you.
    static let sideways = 1.5
    static let between = 0.16
    static let most = 4

    static let signature = SIMD3<Double>(1.0, 0.78, 0.22)

    /// One blast in flight.
    struct Blast {
        var position: CGPoint
        var direction: SIMD2<Double>
        var speed: Double
        var radius: Double
        var ki: SaiyanKi
        var seed: Int
        var age = 0.0
        /// Where it has been, newest last.
        var trail: [CGPoint] = []
        /// Where it left the palm.
        var from: CGPoint
    }

    private struct Mark {
        var size: Double
        var palm: CGPoint
    }

    private var marks: [Int: SaiyanTrail<Mark>] = [:]
    private(set) var blasts: [Blast] = []
    private var impacts: [SaiyanImpact] = []
    private var sparks = SaiyanSparks(seed: 0xB1A5, capacity: 110, gravity: -380, drag: 1.6)
    private var engagedFor = 0.0
    private var sinceShot = 9.0
    private var sinceImpact = 9.0
    private var face: FaceState?
    private var faceLost = 9.0
    private var ki = SaiyanKi(KiBlastMove.signature, palette: SaiyanForm.base.palette)
    private var power = 0.0
    private var time = 0.0
    private var rect = CGRect(x: 0, y: 0, width: 1280, height: 720)
    private(set) var fired = 0
    private(set) var landed = 0

    init() {}

    var hasLight: Bool { !blasts.isEmpty || !impacts.isEmpty || !sparks.isEmpty }

    var status: LensStatus? { isEngaged ? LensStatus("Ki Blast!", detail: "Push again to fire another") : nil }

    var screenEffect: SaiyanScreenEffect {
        var e = SaiyanScreenEffect()
        let v = 0.14 * exp(-sinceShot / 0.12) + 0.1 * exp(-sinceImpact / 0.14)
        e.shake = v < 0.003 ? 0 : v
        return e
    }

    func reset() {
        marks.removeAll()
        blasts.removeAll()
        impacts.removeAll()
        sparks.removeAll()
        engagedFor = 0
        isEngaged = false
        sinceShot = 9
        sinceImpact = 9
        face = nil
        faceLost = 9
    }

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) {
        let dt = WorldKit.clamped(c.dt)
        time = c.time
        power = c.power
        rect = c.rect
        ki = SaiyanKi(Self.signature, palette: c.palette, tint: 0.6)
        if let f = c.face { face = f; faceLost = 0 } else { faceLost += dt }
        let usable = faceLost < 0.5 ? face : nil
        sinceShot += dt
        sinceImpact += dt
        engagedFor = max(0, engagedFor - dt)

        for hand in c.hands where hand.unseenFor <= 0 {
            var trail = marks[hand.id] ?? SaiyanTrail<Mark>(span: 0.5)
            trail.add(Mark(size: hand.size, palm: hand.palm), at: time)
            marks[hand.id] = trail
            if let f = usable, mayBegin || isEngaged, sinceShot >= Self.between, blasts.count < Self.most,
               let direction = push(hand, c, face: f) {
                fire(from: hand, direction: direction)
                marks[hand.id]?.removeAll()
            }
        }
        let seen = Set(c.hands.map(\.id))
        for id in marks.keys where !seen.contains(id) { marks[id] = nil }
        isEngaged = engagedFor > 0

        fly(dt: dt)
        for i in impacts.indices { impacts[i].update(dt: dt, pouring: false) }
        impacts.removeAll { !$0.isAlive }
        sparks.step(dt)
    }

    /// Which way to send a blast, if this hand has just pushed one out.
    private func push(_ hand: HandState, _ c: SaiyanMoveContext, face: FaceState) -> SIMD2<Double>? {
        guard HandGesture.Pose.classify(hand) == .openPalm, c.gestures.pose(of: hand.id) == .openPalm, c.gestures.heldFor(hand.id) >= Self.openFor,
              let trail = marks[hand.id], let last = trail.last else { return nil }
        let window = trail.marks.filter { time - $0.time <= Self.pushWindow + 1e-9 && time - $0.time >= Self.settledFor - 1e-9 }
        guard let smallest = window.min(by: { $0.value.size < $1.value.size }), last.size > smallest.value.size * Self.pushGrowth else { return nil }
        let travel = HandState.distance(last.palm, smallest.value.palm) / last.size
        guard travel < Self.sweepBelow, SaiyanZones.distanceToFace(hand, face) > Self.faceClear else { return nil }
        guard !c.hands.contains(where: { $0.id != hand.id && HandState.distance($0.palm, hand.palm) < Self.aloneBeyond * max($0.size, hand.size) }) else { return nil }
        // Sent the way the palm moved across the picture during the push, if it moved clearly; otherwise away from you.
        let elapsed = max(1e-3, time - smallest.time)
        let across = Double(last.palm.x - smallest.value.palm.x) / last.size / elapsed
        let side = abs(across) > Self.sideways ? (across > 0 ? 1.0 : -1.0) : c.outward(from: hand.palm)
        let rise = Double(last.palm.y - smallest.value.palm.y) / last.size / elapsed
        let slope = min(0.22, max(-0.22, rise * 0.05))
        return simd_normalize(SIMD2(side, slope))
    }

    private func fire(from hand: HandState, direction: SIMD2<Double>) {
        let radius = 110 * SaiyanBeamKit.handScale(hand.size) * 0.3 * (1 + 0.6 * power)
        let start = SaiyanBeamHands.offset(hand.palm, direction, by: hand.size * 0.25)
        fired += 1
        blasts.append(Blast(position: start, direction: direction, speed: 650, radius: radius, ki: ki, seed: fired * 131, from: hand.palm))
        sparks.burst(at: start, count: 14, direction: direction, spread: 1.0, speed: 160...520, life: 0.18...0.4)
        sinceShot = 0
        engagedFor = 0.35
    }

    private func fly(dt: Double) {
        let top = 2200 + 500 * power
        for i in blasts.indices {
            var b = blasts[i]
            b.age += dt
            // A kick out of the palm, then it streaks away.
            b.speed += (top - b.speed) * min(1, dt / 0.16)
            b.position = SaiyanBeamHands.offset(b.position, b.direction, by: b.speed * dt)
            b.trail.append(b.position)
            if b.trail.count > 10 { b.trail.removeFirst() }
            sparks.stream(at: b.position, rate: 40, dt: dt, direction: -b.direction, spread: 0.5, speed: 60...220, life: 0.18...0.4, size: 1.2...2.8)
            blasts[i] = b
        }
        // A blast whose middle has reached the edge bursts there.
        let inside = rect.insetBy(dx: 2, dy: 2)
        for b in blasts where !inside.contains(b.position) {
            let hit = HandGeometry.exit(from: SIMD2(Double(b.from.x), Double(b.from.y)), direction: b.direction, rect: rect)
            let point = CGPoint(x: hit.x, y: hit.y)
            let normal = SaiyanBeamRig.normal(at: point, rect, fallback: -b.direction)
            impacts.append(SaiyanImpact(point: point, normal: normal, size: b.radius * 1.5, ki: b.ki, seed: b.seed, pour: 0))
            sparks.burst(at: point, count: 16, direction: normal, spread: 1.3, speed: 160...560, life: 0.25...0.6, size: 1.6...3.6)
            sinceImpact = 0
            landed += 1
        }
        blasts.removeAll { !inside.contains($0.position) }
    }

    /// How big a blast is right now: it springs out of the palm.
    private func radius(_ b: Blast) -> Double { b.radius * (0.35 + 0.65 * HandFXKit.easeOutBack(b.age / 0.14, overshoot: 2.2)) }

    // MARK: Drawing

    func washes() -> [SaiyanWash] {
        var out: [SaiyanWash] = []
        for b in blasts { out.append(SaiyanWash(center: b.position, radius: radius(b) * 3.2, colour: b.ki.body, alpha: 0.4)) }
        for i in impacts { out += i.washes() }
        return out
    }

    func drawSolids(in ctx: CGContext) {
        for b in blasts { SaiyanBeamKit.drawOrbSolid(at: b.position, radius: radius(b), ki: b.ki, alpha: 1, in: ctx) }
    }

    func drawLight(in ctx: CGContext) {
        guard hasLight else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        for b in blasts {
            let r = radius(b)
            let angle = atan2(b.direction.y, b.direction.x)
            // A comet's tail behind it, in three bands like the beams (coloured, pale, white-hot), growing as it speeds up.
            // Never longer than the way it has come, so it does not trail back over the hand that threw it.
            let length = min(320, r * 2.5 + b.speed * 0.1, HandState.distance(b.position, b.from) + r * 0.5)
            for (k, colour, a) in [(1.0, b.ki.body, 0.5), (0.62, b.ki.lit(0.4), 0.6), (0.3, SaiyanBeamKit.white, 0.9)] {
                let tail = CGMutablePath()
                SaiyanBeamKit.teardrop(tail, head: b.position, angle: angle, length: length * (0.45 + 0.55 * k), width: r * 1.9 * k)
                SaiyanBeamKit.fill(tail, colour: colour, alpha: a, in: ctx)
            }
            SaiyanBeamKit.drawOrbLight(at: b.position, radius: r, ki: b.ki, alpha: 1, time: time + Double(b.seed), seed: b.seed,
                                       crackle: 1 + Int(power * 2), in: ctx)
            // The palm flares as it lets go.
            let flare = 1 - b.age / 0.22
            if flare > 0 {
                SaiyanBeamKit.drawMuzzle(at: b.from, angle: angle, width: r * 1.3, ki: b.ki, alpha: flare, burst: b.age / 0.22, time: time, in: ctx)
            }
        }
        for i in impacts { i.draw(time: time, in: ctx) }
        sparks.draw(colour: ki.body, in: ctx)
        ctx.restoreGState()
    }
}
