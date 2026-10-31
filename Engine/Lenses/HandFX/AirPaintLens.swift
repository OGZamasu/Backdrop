import CoreGraphics
import CoreImage
import simd

/// Neon strokes drawn in the air by the tip of a pointing finger. They hold for a few seconds, then fade slowly; an open palm wipes them away.
///
/// Tracking arrives about 25 times a second and drops out in fast motion, so the line is a smooth curve through the tip positions
/// rather than straight segments between them, a fast stroke is joined up across the gaps, and the pen lifts only when the finger
/// really stops pointing or the hand is gone.
struct AirPaintCanvas {
    struct Point {
        var position: CGPoint
        var time: Double
        var hue: Double
    }

    struct Stroke {
        /// The hand that drew it.
        var hand: Int
        var points: [Point]
        /// Whether the pen is still down on it.
        var isOpen: Bool
        /// 0...1: how far the palm's wave has swept out across the picture.
        var erased = 0.0
        /// Set once a wipe has begun; it then runs to the end even if the palm closes.
        var erasing = false
        /// Where the wave that wipes it started.
        var wipeCenter: CGPoint?
        /// Line thickness: bigger for a hand close to the camera.
        var width: Double
        /// The smooth curve through the points, sampled every few pixels, and for each sample the segment it lies on and how far along it.
        /// Worked out once as points arrive, because bending a long line into a curve every frame would cost too much.
        private(set) var curve: [CGPoint] = []
        private(set) var curveSegment: [Int] = []
        private(set) var curveFraction: [Double] = []
        /// How many segments of the curve will not change again: those with a point after the next one.
        private var settled = 0

        init(hand: Int, points: [Point], isOpen: Bool, width: Double) {
            self.hand = hand
            self.points = points
            self.isOpen = isOpen
            self.width = width
            refreshCurve()
        }

        /// Brings the curve up to date after points were added at the end.
        mutating func refreshCurve() {
            let n = points.count
            guard n > 0 else { curve = []; curveSegment = []; curveFraction = []; return }
            while let last = curveSegment.last, last >= settled, curve.count > 1 {
                curve.removeLast(); curveSegment.removeLast(); curveFraction.removeLast()
            }
            if curve.isEmpty {
                curve = [points[0].position]; curveSegment = [0]; curveFraction = [0]
            }
            guard n > 1 else { return }
            for i in settled..<(n - 1) {
                let a = points[i].position, b = points[i + 1].position
                // Beyond the ends, carry on in the same direction so the curve leaves and arrives smoothly.
                let before = i > 0 ? points[i - 1].position : CGPoint(x: 2 * a.x - b.x, y: 2 * a.y - b.y)
                let after = i + 2 < n ? points[i + 2].position : CGPoint(x: 2 * b.x - a.x, y: 2 * b.y - a.y)
                let steps = max(1, min(24, Int((HandFXKit.distance(a, b) / 7).rounded(.up))))
                for step in 1...steps {
                    let t = Double(step) / Double(steps)
                    curve.append(AirPaintCanvas.curve(before, a, b, after, t))
                    curveSegment.append(i)
                    curveFraction.append(t)
                }
            }
            settled = max(0, n - 2)
        }

        /// Forgets the oldest `count` points.
        mutating func dropFront(_ count: Int) {
            guard count > 0, count < points.count else { return }
            points.removeFirst(count)
            let cut = curveSegment.firstIndex { $0 >= count } ?? curveSegment.count
            curve.removeFirst(cut); curveSegment.removeFirst(cut); curveFraction.removeFirst(cut)
            for i in curveSegment.indices { curveSegment[i] -= count }
            settled = max(0, settled - count)
            if curveSegment.first.map({ $0 > 0 || curveFraction[0] > 0 }) ?? true {
                curve.insert(points[0].position, at: 0); curveSegment.insert(0, at: 0); curveFraction.insert(0, at: 0)
            }
        }
    }

    /// A shock ring from the palm that wipes the page.
    struct Ripple {
        var center: CGPoint
        var age = 0.0
        /// How far out the wave has gone, in pixels.
        var radius: Double { AirPaintCanvas.wipeRadius(progress: age / AirPaintCanvas.wipeSeconds) }
        /// 0...1: how strongly the ring shows; it fades as it reaches the edges.
        var strength: Double { 1 - WorldKit.smoothstep(0.55, 1.15, age / AirPaintCanvas.wipeSeconds) }
    }

    /// How far a wipe's wave has spread when it is `progress` of the way through: fast at first, then easing, and past every corner at the end.
    static func wipeRadius(progress: Double) -> Double { 30 + 1550 * HandFXKit.easeOutCubic(progress) }

    /// What the canvas knows about each hand's pen.
    private struct Pen {
        var smoothed: CGPoint?
        /// Seconds since the finger was last seen pointing.
        var sinceAiming = 99.0
        var openPalmFor = 0.0
        var wiping = false
        var hue = 0.0
    }

    /// Seconds a stroke stays at full strength, and the seconds after that over which it fades away.
    static let holdSeconds = 3.0
    static let fadeSeconds = 4.0
    /// How long the finger may stop looking like a point before the pen lifts. Tracking flickers; a real lift lasts longer.
    static let liftGrace = 0.12
    /// How long the palm must stay open before it wipes, and how long the wipe takes.
    static let wipeDelay = 0.15
    static let wipeSeconds = 0.5
    /// A jump bigger than this in one look is a tracking glitch, not a stroke, and starts a new line.
    static let maxJump = 420.0
    /// Points closer than this to the last are dropped, which also hides the shiver of tracking noise.
    static let spacing = 4.0
    static let maxPoints = 1400

    private(set) var strokes: [Stroke] = []
    private(set) var ripples: [Ripple] = []
    private(set) var time = 0.0
    private var pens: [Int: Pen] = [:]
    private var strokesStarted = 0
    private var sparks = ParticleSystem(capacity: 160)
    private var rng = SplitMix64(seed: 0xA1B9)

    var sparkParticles: [Particle] { sparks.particles }
    var totalPoints: Int { strokes.reduce(0) { $0 + $1.points.count } }
    /// Whether a pen is down right now.
    var isDrawing: Bool { strokes.contains { $0.isOpen } }
    /// Whether the page is being wiped.
    var isWiping: Bool { pens.values.contains { $0.wiping } || strokes.contains { $0.erasing } }

    init() { sparks.gravity = SIMD2(0, -120) }

    mutating func removeAll() {
        strokes.removeAll()
        ripples.removeAll()
        pens.removeAll()
        sparks.removeAll()
    }

    /// Where the pen tip is for a hand, or nil if its pen is up.
    func penTip(for hand: Int) -> CGPoint? {
        guard let stroke = strokes.last(where: { $0.hand == hand && $0.isOpen }) else { return nil }
        return stroke.points.last?.position
    }

    /// Whether this hand is drawing now: the index finger is out and the rest are curled.
    static func isAiming(_ hand: HandState) -> Bool { hand.pose == .point || hand.pose == .fingerGun }

    mutating func update(hands: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        time += dt

        let seen = Set(hands.map(\.id))
        // A hand that has gone takes its pen with it.
        for i in strokes.indices where strokes[i].isOpen && !seen.contains(strokes[i].hand) { strokes[i].isOpen = false }
        pens = pens.filter { seen.contains($0.key) }

        for hand in hands {
            var pen = pens[hand.id] ?? Pen(hue: Double(strokesStarted) * 0.381966 + Double(hand.id) * 0.17)
            let aiming = Self.isAiming(hand)
            pen.sinceAiming = aiming ? 0 : pen.sinceAiming + dt

            // The pen stays down through a flicker of the pose as long as the index finger is still out.
            let holding = aiming || (pen.sinceAiming < Self.liftGrace && hand.isExtended(.index))
            if holding {
                extend(hand: hand, pen: &pen, dt: dt)
            } else if pen.sinceAiming >= Self.liftGrace {
                lift(hand: hand.id)
                pen.smoothed = nil
            }

            // An open palm, held, wipes the page.
            pen.openPalmFor = hand.pose == .openPalm ? pen.openPalmFor + dt : 0
            let wasWiping = pen.wiping
            pen.wiping = pen.openPalmFor >= Self.wipeDelay
            if pen.wiping, !wasWiping, strokes.contains(where: { !$0.erasing }) {
                ripples.append(Ripple(center: hand.palm))
                for i in strokes.indices where !strokes[i].erasing {
                    strokes[i].erasing = true
                    strokes[i].isOpen = false
                    strokes[i].wipeCenter = hand.palm
                }
            }
            pens[hand.id] = pen
        }

        for i in strokes.indices where strokes[i].erasing {
            let before = Self.wipeRadius(progress: strokes[i].erased)
            strokes[i].erased += dt / Self.wipeSeconds
            burst(strokes[i], from: before, to: Self.wipeRadius(progress: strokes[i].erased))
        }
        for i in ripples.indices { ripples[i].age += dt }
        ripples.removeAll { $0.age > Self.wipeSeconds * 1.15 }

        sparks.step(dt)
        let gone = Self.holdSeconds + Self.fadeSeconds
        for i in strokes.indices {
            // Points are in the order they were drawn, so the old ones are all at the front.
            let old = strokes[i].points.prefix { time - $0.time > gone }.count
            if old >= strokes[i].points.count { strokes[i].points.removeAll(); strokes[i].refreshCurve() } else { strokes[i].dropFront(old) }
        }
        strokes.removeAll { $0.erased >= 1 || $0.points.isEmpty }
        trimToBudget()
    }

    private mutating func lift(hand id: Int) {
        for i in strokes.indices where strokes[i].hand == id { strokes[i].isOpen = false }
    }

    private mutating func extend(hand: HandState, pen: inout Pen, dt: Double) {
        let raw = hand.indexTip
        var tip = raw
        if let previous = pen.smoothed {
            // Follow closely when the finger really moves, and steadily when it only shivers.
            let off = HandFXKit.distance(previous, raw)
            let follow = min(1, 0.4 + off / 40)
            tip = HandFXKit.lerp(previous, raw, follow)
        }
        pen.smoothed = tip

        if let i = strokes.lastIndex(where: { $0.hand == hand.id && $0.isOpen }) {
            guard let last = strokes[i].points.last else { return }
            let gap = HandFXKit.distance(last.position, tip)
            if gap > Self.maxJump {
                strokes[i].isOpen = false
                begin(hand: hand, at: tip, pen: &pen)
            } else if gap >= Self.spacing {
                strokes[i].points.append(Point(position: tip, time: time, hue: last.hue + gap * 0.00035))
                strokes[i].refreshCurve()
                strokes[i].width = strokes[i].width + (Self.width(for: hand) - strokes[i].width) * 0.1
                emitSparks(at: tip, hue: last.hue)
            }
        } else {
            begin(hand: hand, at: tip, pen: &pen)
        }
    }

    private mutating func begin(hand: HandState, at tip: CGPoint, pen: inout Pen) {
        pen.hue = Double(strokesStarted) * 0.381966 + Double(hand.id) * 0.17
        strokesStarted += 1
        strokes.append(Stroke(hand: hand.id, points: [Point(position: tip, time: time, hue: pen.hue)], isOpen: true, width: Self.width(for: hand)))
    }

    private static func width(for hand: HandState) -> Double { min(1.5, max(0.75, hand.size / 110)) }

    /// Where the wiping wave passes over a line this frame, the line bursts into a few sparks of its own colour.
    private mutating func burst(_ stroke: Stroke, from inner: Double, to outer: Double) {
        guard let c = stroke.wipeCenter else { return }
        var made = 0
        for (k, p) in stroke.points.enumerated() where k % 3 == 0 && made < 10 {
            let d = HandFXKit.distance(p.position, c)
            guard d >= inner, d < outer else { continue }
            let away = SIMD2(Double(p.position.x - c.x), Double(p.position.y - c.y)) / max(d, 1)
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            sparks.emit(Particle(position: SIMD2(Double(p.position.x), Double(p.position.y)),
                                 velocity: away * Double.random(in: 80...260, using: &rng) + SIMD2(cos(a), sin(a)) * 40, age: 0,
                                 life: Double.random(in: 0.35...0.7, using: &rng), size: Double.random(in: 2...4, using: &rng), hue: p.hue))
            made += 1
        }
    }

    private mutating func emitSparks(at p: CGPoint, hue: Double) {
        for _ in 0..<2 {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng), speed = Double.random(in: 30...140, using: &rng)
            sparks.emit(Particle(position: SIMD2(Double(p.x), Double(p.y)), velocity: SIMD2(cos(angle), sin(angle)) * speed, age: 0,
                                 life: Double.random(in: 0.3...0.7, using: &rng), size: Double.random(in: 2...4.5, using: &rng), hue: hue))
        }
    }

    /// Keeps the work per frame bounded however long someone has been drawing: the oldest points go first.
    private mutating func trimToBudget() {
        var extra = totalPoints - Self.maxPoints
        guard extra > 0 else { return }
        for i in strokes.indices where extra > 0 {
            let drop = min(extra, max(0, strokes[i].points.count - 2))
            strokes[i].dropFront(drop)
            extra -= drop
        }
    }

    /// How strongly a point shows: full, then fading away, and gone once the wiping wave has passed over it.
    func strength(of point: Point, in stroke: Stroke) -> Double {
        let age = time - point.time
        let fade = 1 - WorldKit.smoothstep(Self.holdSeconds, Self.holdSeconds + Self.fadeSeconds, age)
        guard stroke.erasing else { return fade }
        guard let c = stroke.wipeCenter else { return fade * max(0, 1 - stroke.erased) }
        let edge = Self.wipeRadius(progress: stroke.erased)
        return fade * WorldKit.smoothstep(edge - 60, edge, HandFXKit.distance(point.position, c))
    }

    // MARK: Smooth curves

    /// A point on the curve through four points, `t` of the way between the middle two. Centripetal, so a fast jump between two
    /// looks never loops or overshoots.
    static func curve(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
        func knot(_ a: CGPoint, _ b: CGPoint) -> Double { max(1e-3, HandFXKit.distance(a, b)).squareRoot() }
        let t0 = 0.0, t1 = t0 + knot(p0, p1), t2 = t1 + knot(p1, p2), t3 = t2 + knot(p2, p3)
        let u = t1 + (t2 - t1) * t
        func mix(_ a: CGPoint, _ b: CGPoint, _ ta: Double, _ tb: Double) -> CGPoint {
            let k = (u - ta) / (tb - ta)
            return CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
        }
        let a1 = mix(p0, p1, t0, t1), a2 = mix(p1, p2, t1, t2), a3 = mix(p2, p3, t2, t3)
        let b1 = mix(a1, a2, t0, t2), b2 = mix(a2, a3, t1, t3)
        return mix(b1, b2, t1, t2)
    }

    typealias Sample = (position: CGPoint, strength: Double, hue: Double)

    /// A stroke as a smooth line, with the strength and hue at each sample along it.
    func smoothLine(of stroke: Stroke) -> [Sample] {
        let pts = stroke.points
        guard !pts.isEmpty else { return [] }
        var strengths: [Double] = []
        strengths.reserveCapacity(pts.count)
        for p in pts { strengths.append(strength(of: p, in: stroke)) }
        var out: [Sample] = []
        out.reserveCapacity(stroke.curve.count)
        for (k, position) in stroke.curve.enumerated() {
            let i = min(stroke.curveSegment[k], pts.count - 1), t = stroke.curveFraction[k]
            let j = min(i + 1, pts.count - 1)
            out.append((position, strengths[i] + (strengths[j] - strengths[i]) * t, pts[i].hue + (pts[j].hue - pts[i].hue) * t))
        }
        return out
    }
}

final class AirPaintLens: Lens {
    let needs: LensNeeds = [.hands]

    private var canvas = AirPaintCanvas()
    /// For each hand, its fingertip steadied, for the hover ring that shows where the pen is while it is up.
    private var memory = HandFXMemory<HandFXSteady>()
    private var hint = HandFXHint()
    private var clock = 0.0
    private let published = StatusBox()

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hand", detail: "Point a finger to draw") }

    func restart() {
        canvas.removeAll()
        memory.removeAll()
        hint.reset()
    }

    var strokes: [AirPaintCanvas.Stroke] { canvas.strokes }
    var isDrawing: Bool { canvas.isDrawing }
    var pointCount: Int { canvas.totalPoints }
    var presence: Double { memory.strongest }
    var isHinting: Bool { hint.isShowing }

    func render(_ input: LensInput) -> CIImage {
        let dt = WorldKit.clamped(input.dt)
        clock += dt
        canvas.update(hands: input.hands, dt: input.dt)
        memory.update(input.hands, dt: dt, fade: 0.25) { _ in HandFXSteady(calm: 2.2, eager: 0.03) }
        for i in memory.entries.indices where memory.entries[i].visible {
            memory.modify(i) { $0.state.update($0.hand.indexTip, dt: dt, snap: 200) }
        }
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        published.value = currentStatus(input.hands)

        var out = input.composed
        if !canvas.strokes.isEmpty || !memory.isEmpty || !canvas.ripples.isEmpty || !canvas.sparkParticles.isEmpty,
           let layer = input.services.overlay({ ctx in draw(in: ctx) }) {
            out = HandFXLight.add(layer, to: out, rect: input.rect, bloom: 0.9)
        }
        return hint.compose(over: out, services: input.services, rect: input.rect, accent: AirPaintLens.accent)
    }

    static let accent = SIMD3<Double>(0.95, 0.4, 0.85)

    private func currentStatus(_ hands: [HandState]) -> LensStatus {
        if hands.isEmpty { return LensStatus("Hold up your hand", detail: "Point a finger to draw") }
        if canvas.isWiping { return LensStatus("Wiping…", detail: "Point a finger to draw again") }
        if canvas.isDrawing { return LensStatus("Drawing", detail: "Open your palm to wipe") }
        return LensStatus("Point a finger to draw", detail: "Open your palm to wipe")
    }

    // MARK: Drawing

    /// The neon tube, from the outside in: a coloured body, a hotter middle and a white core. Each is painted opaque in the colour of all
    /// the light inside it added up, so where two runs of one line overlap they cover each other instead of doubling up: no beads, no seams.
    /// The wide soft halo comes from the bloom.
    private static let tube: [(width: Double, colour: Double, hot: Double, white: Double)] = [
        (17, 0.42, 0, 0), (9, 0.55, 0.55, 0), (3.4, 0.55, 0.55, 0.95),
    ]

    private static func tubeColour(_ pass: (width: Double, colour: Double, hot: Double, white: Double), hue: Double, strength: Double) -> CGColor {
        let c = HandFXKit.neon(hue: hue)
        let hot = c + (SIMD3(1, 1, 1) - c) * 0.55
        let sum = (c * pass.colour + hot * pass.hot + SIMD3(1, 1, 1) * pass.white) * strength
        return CGColor(red: min(1, sum.x), green: min(1, sum.y), blue: min(1, sum.z), alpha: 1)
    }

    private func draw(in ctx: CGContext) {
        ctx.setBlendMode(.normal)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in canvas.strokes { drawLine(of: stroke, in: ctx) }

        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        for ripple in canvas.ripples { drawRipple(ripple, in: ctx) }
        // Sparks flying off the pen.
        for p in canvas.sparkParticles {
            let c = HandFXKit.neon(hue: p.hue)
            let fade = 1 - p.progress
            HandFXKit.glow(ctx, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * 2.6 * (1 - 0.4 * p.progress),
                           colour: c + (SIMD3(1, 1, 1) - c) * 0.35, alpha: fade)
        }
        for entry in memory.entries { drawPenTip(for: entry, in: ctx) }
        ctx.interpolationQuality = .high
    }

    private typealias Run = (points: [CGPoint], strength: Double, hue: Double)

    /// One stroke, in runs of the same colour and strength so that a long line costs a handful of strokes, not hundreds.
    private func drawLine(of stroke: AirPaintCanvas.Stroke, in ctx: CGContext) {
        let line = canvas.smoothLine(of: stroke)
        guard let first = line.first else { return }
        guard line.count > 1 else {
            // A single dot: the pen was put down and lifted again at once.
            guard first.strength > 0.02 else { return }
            for pass in Self.tube {
                ctx.fillCircle(center: first.position, radius: pass.width * stroke.width / 2,
                               color: Self.tubeColour(pass, hue: first.hue, strength: first.strength))
            }
            return
        }
        func level(_ s: Double) -> Int { Int((min(1, max(0, s)) * 20).rounded(.up)) }
        func bucket(_ p: AirPaintCanvas.Sample) -> Int { level(p.strength) * 64 + Int((p.hue - p.hue.rounded(.down)) * 36) }
        var runs: [Run] = []
        var run: [CGPoint] = [first.position]
        var key = bucket(first), runStart = first
        for k in 1..<line.count {
            run.append(line[k].position)
            let next = bucket(line[k])
            if next != key || k == line.count - 1 {
                runs.append((run, Double(level(runStart.strength)) / 20, runStart.hue))
                // The next run starts one sample back, so neighbouring runs overlap and no gap can open between them.
                run = [line[k - 1].position, line[k].position]
                key = next
                runStart = line[k]
            }
        }
        // Passes outermost first across the whole line, so a run's body never covers its neighbour's core.
        for pass in Self.tube {
            ctx.setLineWidth(pass.width * stroke.width)
            for r in runs where r.strength > 0.02 {
                ctx.setStrokeColor(Self.tubeColour(pass, hue: r.hue, strength: r.strength))
                HandFXKit.stroke(r.points, in: ctx)
            }
        }
    }

    /// The pen: a bright bead where it draws, or, while the hand is up but not drawing, a faint ring that shows where it would.
    private func drawPenTip(for entry: HandFXMemory<HandFXSteady>.Entry, in ctx: CGContext) {
        if let tip = canvas.penTip(for: entry.hand.id) {
            let hue = canvas.strokes.last(where: { $0.hand == entry.hand.id && $0.isOpen })?.points.last?.hue ?? 0
            let c = HandFXKit.neon(hue: hue)
            let pulse = 1 + 0.08 * sin(clock * 9)
            HandFXKit.glow(ctx, at: tip, radius: 30 * pulse, colour: c, alpha: 0.85 * entry.presence)
            HandFXKit.glow(ctx, at: tip, radius: 10, colour: HandFXPalette.white, alpha: entry.presence)
            return
        }
        guard let tip = entry.state.point else { return }
        let alpha = 0.55 * entry.presence * (0.6 + 0.4 * HandFXPose.extended(.index, in: entry.hand))
        let r = 15 + 2 * sin(clock * 3)
        ctx.setLineWidth(2.2)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        ctx.strokeEllipse(in: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2))
        HandFXKit.glow(ctx, at: tip, radius: 9, colour: AirPaintLens.accent, alpha: alpha)
    }

    /// The wave from an open palm: a bright band that sweeps out and takes the lines with it.
    private func drawRipple(_ ripple: AirPaintCanvas.Ripple, in ctx: CGContext) {
        let r = ripple.radius, s = ripple.strength
        guard s > 0.01 else { return }
        let rect = CGRect(x: ripple.center.x - r, y: ripple.center.y - r, width: r * 2, height: r * 2)
        for (w, c, a) in [(46.0, SIMD3(0.55, 0.45, 1.0), 0.12), (20.0, SIMD3(0.75, 0.75, 1.0), 0.22), (5.0, SIMD3(0.95, 0.95, 1.0), 0.7)] {
            ctx.setLineWidth(w)
            ctx.setStrokeColor(HandFXKit.cgColor(c, a * s))
            ctx.strokeEllipse(in: rect)
        }
    }
}
