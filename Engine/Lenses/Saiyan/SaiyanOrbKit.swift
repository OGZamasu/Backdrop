import CoreGraphics
import Foundation
import simd

/// What the five moves that are not beams share (Spirit Bomb, Destructo Disc, Solar Flare, Instant Transmission, Zanzoken): easing,
/// a baked disc, slim shapes of light (rings, slivers, rays, bolts), a short memory of where each palm has been, and a spring that
/// makes a big orb float after the hands instead of sticking to them.
///
/// Everything wide and soft goes out as a `SaiyanWash` (made on the graphics chip); what is drawn here is the detail: thin strokes,
/// slim shapes and small stamps, which the lens blooms.
enum SaiyanOrbKit {
    // MARK: Easing

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    static func smooth(_ x: Double) -> Double { let t = clamp01(x); return t * t * (3 - 2 * t) }
    static func easeIn(_ x: Double) -> Double { let t = clamp01(x); return t * t }
    static func easeOut(_ x: Double) -> Double { HandFXKit.easeOutCubic(x) }
    static func easeOutBack(_ x: Double, overshoot: Double = 1.7) -> Double { HandFXKit.easeOutBack(x, overshoot: overshoot) }
    /// 0 at both ends and 1 in the middle, smoothly: a swell that comes and goes.
    static func swell(_ x: Double) -> Double { let t = clamp01(x); return sin(t * .pi) }

    // MARK: Colour

    static let white = SIMD3<Double>(1, 1, 1)

    /// A colour pushed toward white by `k`.
    static func lift(_ c: SIMD3<Double>, _ k: Double) -> SIMD3<Double> { c + (white - c) * clamp01(k) }

    static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ k: Double) -> SIMD3<Double> { a + (b - a) * clamp01(k) }

    static func cg(_ c: SIMD3<Double>, _ alpha: Double = 1) -> CGColor { HandFXKit.cgColor(c, alpha) }

    /// A colour rounded to a coarse step, so the few colours a form can tint a move to share a handful of baked sprites.
    static func snapped(_ c: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3((clamp01(c.x) * 16).rounded() / 16, (clamp01(c.y) * 16).rounded() / 16, (clamp01(c.z) * 16).rounded() / 16)
    }

    private static func key(_ name: String, _ c: SIMD3<Double>) -> String {
        let s = snapped(c)
        return "saiyan-orb-\(name)-\(Int(s.x * 16))-\(Int(s.y * 16))-\(Int(s.z * 16))"
    }

    // MARK: Sprites

    /// A flat saw of light seen from straight above: a glassy body with faint rings, a white-hot band inside the rim, and a serrated edge
    /// whose teeth lean the way it spins. Drawn squashed into an ellipse it reads as a disc held flat.
    static func disc(_ colour: SIMD3<Double>, teeth: Int = 22) -> CGImage? {
        let c = snapped(colour)
        return HandFXSprites.named(key("disc\(teeth)", c)) {
            HandFXKit.sprite(width: 256, height: 256) { u, v in
                let x = u * 2 - 1, y = v * 2 - 1
                let r = (x * x + y * y).squareRoot()
                guard r < 1 else { return (0, 0, 0, 0) }
                let turn = (atan2(y, x) / (2 * .pi) + 1) * Double(teeth)
                let saw = turn - turn.rounded(.down)
                // Each tooth ramps out and drops back sharply: a saw blade, not a cog.
                let rim = 0.885 + 0.11 * pow(saw, 1.3)
                let px = 1.6 / 128
                let inside = WorldKit.smoothstep(-px, px, rim - r)
                guard inside > 0.001 else { return (0, 0, 0, 0) }
                let ripples = 0.5 + 0.5 * cos(r * 46)
                let body = 0.2 + 0.34 * WorldKit.smoothstep(0.15, 0.86, r) + 0.07 * ripples * WorldKit.smoothstep(0.2, 0.7, r)
                let band = exp(-pow((r - (rim - 0.045)) / 0.032, 2))
                let toothGlow = WorldKit.smoothstep(0.86, 0.97, r) * (0.45 + 0.55 * saw)
                let core = exp(-pow(r / 0.16, 2)) * 0.35
                // Only the band inside the rim runs white-hot; the glassy body and the teeth keep the colour.
                let light = body + band * 0.9 + toothGlow * 0.55 + core
                let rgb = lift(c, 0.04 + 0.72 * min(1, band + core))
                return (rgb.x, rgb.y, rgb.z, min(1, light) * inside)
            }
        }
    }

    /// A long thin wisp for a beam of light standing on end or lying across the picture: white down the middle, coloured, soft-edged.
    static func beam(_ colour: SIMD3<Double>) -> CGImage? {
        let c = snapped(colour)
        return HandFXSprites.named(key("beam", c)) { HandFXKit.beamSprite(c, core: 0.07, body: 0.2) }
    }

    /// The glowing ball itself, painted solid: white-hot in the middle, the colour through the body, a deeper rim and a soft edge.
    static func drawBody(_ ctx: CGContext, at c: CGPoint, radius r: Double, colour: SIMD3<Double>, alpha: Double, core: Double = 0.9) {
        guard r > 1, alpha > 0.004 else { return }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func stop(_ k: Double, _ shade: Double, _ a: Double) -> CGColor {
            let rgb = lift(colour, k) * shade
            return CGColor(colorSpace: space, components: [rgb.x, rgb.y, rgb.z, a * alpha])!
        }
        // A wide white-hot heart, the colour deepening through the body, and a darker band just inside the rim so the ball has an edge
        // before it melts into its own glow.
        let colours = [stop(core, 1, 0.97), stop(0.6, 1, 0.94), stop(0.2, 1, 0.9), stop(0, 0.9, 0.86), stop(0, 0.66, 0.6), stop(0, 0.5, 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.3, 0.62, 0.86, 0.96, 1]) else { return }
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * 1.04, options: [])
    }

    // MARK: Drawing light (call with additive blending on)
    //
    // Core Graphics pays for every pixel of a sprite and, above all, for every row an anti-aliased slanting edge crosses (a diagonal line
    // across the picture costs thirty times the same line laid level). So the light here is thin: single strokes and slim shapes, short
    // where they slant. The lens blooms this layer, which gives each thread its soft glow for nothing; anything wide and soft is a
    // `SaiyanWash` instead.

    /// A ring of light: one coloured stroke with a white thread inside it. `squash` flattens it into an ellipse seen at an angle (1 is a
    /// circle), turned by `angle`; the stroke flattens with it, as a ring lying in a plane would.
    static func ring(_ ctx: CGContext, center: CGPoint, radius: Double, squash: Double = 1, angle: Double = 0, width: Double,
                     colour: SIMD3<Double>, alpha: Double, thread: Bool = true) {
        guard radius > 0.5, alpha > 0.004, width > 0.05 else { return }
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: CGFloat(angle))
        ctx.scaleBy(x: 1, y: CGFloat(max(0.05, squash)))
        let box = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        ctx.setLineWidth(CGFloat(width))
        ctx.setStrokeColor(cg(lift(colour, 0.3), 0.75 * alpha))
        ctx.strokeEllipse(in: box)
        if thread {
            ctx.setLineWidth(CGFloat(max(0.8, width * 0.3)))
            ctx.setStrokeColor(cg(white, 0.9 * alpha))
            ctx.strokeEllipse(in: box)
        }
        ctx.restoreGState()
    }

    /// A short arc of a ring, for a glint running round a rim. Angles in radians, counter-clockwise.
    static func arc(_ ctx: CGContext, center: CGPoint, radius: Double, from a0: Double, to a1: Double, squash: Double = 1, angle: Double = 0,
                    width: Double, colour: SIMD3<Double>, alpha: Double) {
        guard radius > 0.5, alpha > 0.004 else { return }
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: CGFloat(angle))
        ctx.scaleBy(x: 1, y: CGFloat(max(0.05, squash)))
        ctx.setLineCap(.round)
        for (w, c, a) in [(width, lift(colour, 0.5), 0.8), (width * 0.4, white, 1.0)] {
            ctx.setLineWidth(CGFloat(w))
            ctx.setStrokeColor(cg(c, a * alpha))
            ctx.beginPath()
            ctx.addArc(center: .zero, radius: CGFloat(radius), startAngle: CGFloat(a0), endAngle: CGFloat(a1), clockwise: false)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func fill(_ ctx: CGContext, _ points: [CGPoint], _ c: SIMD3<Double>, _ alpha: Double) {
        guard alpha > 0.004, let first = points.first else { return }
        ctx.setFillColor(cg(c, alpha))
        ctx.beginPath()
        ctx.move(to: first)
        for p in points.dropFirst() { ctx.addLine(to: p) }
        ctx.closePath()
        ctx.fillPath()
    }

    /// A sliver of light from `tail` to `head`: a spindle pointed at both ends and fullest near the head, with a white-hot core along its
    /// front half. Streams, sparks in flight and speed lines are all slivers.
    static func sliver(_ ctx: CGContext, from tail: CGPoint, to head: CGPoint, width: Double, colour: SIMD3<Double>, alpha: Double, core: Double = 0.85) {
        let d = head - tail
        let l = length(d)
        guard l > 0.5, alpha > 0.004, width > 0.1 else { return }
        let u = CGVector(dx: d.dx / l, dy: d.dy / l), n = CGVector(dx: -u.dy, dy: u.dx)
        let w = width / 2
        let full = point(tail, u, l * 0.74)
        fill(ctx, [tail, point(full, n, w), head, point(full, n, -w)], colour, alpha * 0.75)
        guard core > 0.01 else { return }
        let hot = point(tail, u, l * 0.82), from = point(tail, u, l * 0.45)
        fill(ctx, [from, point(hot, n, w * 0.34), head, point(hot, n, -w * 0.34)], lift(colour, 0.75), alpha * core)
    }

    /// A streak with its bright head at `head`, trailing back the way it came (`angle` is the way it is going).
    static func streak(_ ctx: CGContext, head: CGPoint, angle: Double, length: Double, width: Double, colour: SIMD3<Double>, alpha: Double,
                       core: Double = 0.85) {
        sliver(ctx, from: CGPoint(x: head.x - cos(angle) * length, y: head.y - sin(angle) * length), to: head, width: width, colour: colour,
               alpha: alpha, core: core)
    }

    /// A ray from `origin` going `angle`: a long slender wedge, `width` across where it starts, with a white-hot inner wedge.
    static func ray(_ ctx: CGContext, from origin: CGPoint, angle: Double, length: Double, width: Double, colour: SIMD3<Double>, alpha: Double) {
        guard length > 1, alpha > 0.004 else { return }
        let u = CGVector(dx: cos(angle), dy: sin(angle)), n = CGVector(dx: -u.dy, dy: u.dx)
        fill(ctx, [point(origin, n, width / 2), point(origin, u, length), point(origin, n, -width / 2)], colour, alpha * 0.5)
        fill(ctx, [point(origin, n, width * 0.16), point(origin, u, length * 0.6), point(origin, n, -width * 0.16)], lift(colour, 0.8), alpha * 0.95)
    }

    /// A sprite centred on a point, turned, at a size, faded.
    static func stamp(_ ctx: CGContext, _ sprite: CGImage?, at p: CGPoint, size: CGSize, angle: Double = 0, alpha: Double) {
        guard let sprite, alpha > 0.004, size.width > 0.5, size.height > 0.5 else { return }
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        if angle != 0 { ctx.rotate(by: CGFloat(angle)) }
        ctx.setAlpha(CGFloat(min(1, alpha)))
        ctx.draw(sprite, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        ctx.restoreGState()
    }

    /// A soft glow dot (see `WorldKit.softGlow`). Keep these small: a big one is a `SaiyanWash`.
    static func glow(_ ctx: CGContext, at p: CGPoint, radius: Double, colour: SIMD3<Double>, alpha: Double) {
        guard alpha > 0.004, radius > 0.5, let dot = WorldKit.softGlow(colour.x, colour.y, colour.z) else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(min(1, alpha)))
        ctx.draw(dot, in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        ctx.restoreGState()
    }

    /// A four-pointed glint (see `WorldKit.star`).
    static func glint(_ ctx: CGContext, at p: CGPoint, radius: Double, angle: Double = 0, colour: SIMD3<Double>, alpha: Double) {
        stamp(ctx, WorldKit.star(colour.x, colour.y, colour.z), at: p, size: CGSize(width: radius * 2, height: radius * 2), angle: angle, alpha: alpha)
    }

    /// A jagged thread of electricity: a coloured stroke with a white core. The bloom gives it its glow.
    static func bolt(_ ctx: CGContext, _ points: [CGPoint], colour: SIMD3<Double>, strength: Double, width: Double = 1) {
        guard points.count > 1, strength > 0.01 else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for (w, c, a) in [(3.4 * width, lift(colour, 0.3), 0.6), (1.2 * width, white, 1.0)] {
            ctx.setLineWidth(CGFloat(w))
            ctx.setStrokeColor(cg(c, min(1, a * strength)))
            HandFXKit.stroke(points, in: ctx)
        }
    }

    /// Arcs of electricity leaping off a sphere. `beat` changes every couple of frames so they strobe and crackle.
    static func crackle(_ ctx: CGContext, around c: CGPoint, radius r: Double, count: Int, beat: Int, salt: Int, reach: ClosedRange<Double> = 1.2...1.55,
                        colour: SIMD3<Double>, strength: Double) {
        guard count > 0, strength > 0.01 else { return }
        for k in 0..<count {
            var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: beat &* 7919 &+ k &* 104_729 &+ salt &* 31))
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let out = r * Double.random(in: reach, using: &rng)
            let drift = Double.random(in: -0.3...0.3, using: &rng)
            let start = CGPoint(x: c.x + cos(angle) * r * 0.96, y: c.y + sin(angle) * r * 0.96)
            let end = CGPoint(x: c.x + cos(angle + drift) * out, y: c.y + sin(angle + drift) * out)
            let points = HandFXKit.zigzag(from: start, to: end, seed: UInt64(truncatingIfNeeded: beat &* 31 &+ k &* 977 &+ salt), amplitude: max(4, r * 0.1),
                                          segments: 6)
            bolt(ctx, points, colour: colour, strength: strength, width: 0.8 + 0.3 * min(1, r / 90))
        }
    }

    /// A beam standing on end, `width` across, from `bottom` to `top` (same x): drawn without turning, which is far cheaper.
    static func column(_ ctx: CGContext, x: Double, bottom: Double, top: Double, width: Double, colour: SIMD3<Double>, alpha: Double) {
        guard width > 0.5, top > bottom, alpha > 0.004, let sprite = columnSprite(colour) else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(min(1, alpha)))
        ctx.draw(sprite, in: CGRect(x: x - width / 2, y: bottom, width: width, height: top - bottom))
        ctx.restoreGState()
    }

    /// The cross-section of a beam standing on end: white down the middle, coloured, soft-edged, left to right.
    static func columnSprite(_ colour: SIMD3<Double>) -> CGImage? {
        let c = snapped(colour)
        return HandFXSprites.named(key("column", c)) {
            HandFXKit.sprite(width: 64, height: 2) { u, _ in
                let d = abs(u - 0.5) * 2
                let white = exp(-pow(d / 0.12, 2)), body = 0.6 * exp(-pow(d / 0.42, 2)) * (1 - WorldKit.smoothstep(0.8, 1, d))
                let sum = SIMD3<Double>(1, 1, 1) * white + c * body
                let a = min(1, max(sum.x, max(sum.y, sum.z)))
                return a < 1e-4 ? (0, 0, 0, 0) : (sum.x / a, sum.y / a, sum.z / a, a)
            }
        }
    }

    // MARK: Small pieces of geometry

    static func point(_ p: CGPoint, _ v: CGVector, _ k: Double) -> CGPoint { CGPoint(x: p.x + v.dx * k, y: p.y + v.dy * k) }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    static func length(_ v: CGVector) -> Double { hypot(Double(v.dx), Double(v.dy)) }

    static func unit(_ v: CGVector, or fallback: CGVector = CGVector(dx: 0, dy: 1)) -> CGVector {
        let l = length(v)
        return l > 1e-6 ? CGVector(dx: v.dx / l, dy: v.dy / l) : fallback
    }
}

// MARK: - Where each palm has been

/// The last half second of each hand's palm, so a move can tell a deliberate swing from a wave: how far the palm went over a window,
/// how fast it went, and whether it turned back. Hands the tracker is only bridging through a gap (`unseenFor > 0`) are guessed, so
/// their positions are not counted as travel, but the speed the tracker last measured for them still is.
struct SaiyanHandTrail {
    private struct Mark {
        var time: Double
        var palm: CGPoint
        var size: Double
        var velocity: CGVector
        var seen: Bool
    }

    private var marks: [Int: [Mark]] = [:]
    private(set) var time = 0.0
    /// How long a hand's history is kept.
    static let memory = 0.8

    mutating func reset() {
        marks.removeAll()
        time = 0
    }

    mutating func update(_ hands: [HandState], time: Double) {
        self.time = time
        for hand in hands {
            marks[hand.id, default: []].append(Mark(time: time, palm: hand.palm, size: hand.size, velocity: hand.velocity, seen: hand.unseenFor <= 0))
        }
        for id in Array(marks.keys) {
            marks[id]?.removeAll { time - $0.time > Self.memory }
            if marks[id]?.isEmpty ?? true { marks[id] = nil }
        }
    }

    private func seen(_ id: Int, within window: Double) -> [Mark] {
        (marks[id] ?? []).filter { $0.seen && time - $0.time <= window + 1e-6 }
    }

    /// Where the palm was `window` seconds ago, as near as the history goes, and how long ago that really was.
    func origin(_ id: Int, within window: Double) -> (palm: CGPoint, age: Double)? {
        guard let first = seen(id, within: window).first else { return nil }
        return (first.palm, time - first.time)
    }

    /// How far the palm moved over the last `window` seconds, in pixels. With `guessed`, the places the tracker carried a blurred hand to
    /// count as well: a hard swing is often a blur.
    func travel(_ id: Int, over window: Double, guessed: Bool = false) -> CGVector {
        let recent = guessed ? (marks[id] ?? []).filter { time - $0.time <= window + 1e-6 } : seen(id, within: window)
        guard let a = recent.first, let b = recent.last else { return .zero }
        return b.palm - a.palm
    }

    /// The travel between `from` and `to` seconds ago (from > to), in pixels.
    func travel(_ id: Int, from: Double, to: Double) -> CGVector {
        let span = (marks[id] ?? []).filter { $0.seen && time - $0.time <= from + 1e-6 && time - $0.time >= to - 1e-6 }
        guard let a = span.first, let b = span.last else { return .zero }
        return b.palm - a.palm
    }

    /// The palm's speed over the last `window` seconds, pixels a second, from its own path. Falls back to the tracker's speed when the
    /// path is too short to measure.
    func velocity(_ id: Int, over window: Double, fallback: CGVector = .zero) -> CGVector {
        let recent = seen(id, within: window)
        guard let a = recent.first, let b = recent.last, b.time - a.time > 1e-3 else { return fallback }
        let dt = b.time - a.time
        return CGVector(dx: (b.palm.x - a.palm.x) / dt, dy: (b.palm.y - a.palm.y) / dt)
    }

    /// How far ahead of `point`, along `direction` (a unit vector), the palm was at any moment between `from` and `to` seconds ago, in
    /// pixels (zero or less if it was never ahead). A sweep starts from rest or from behind; a wave was just over there and came back.
    func excursion(_ id: Int, from: Double, to: Double, along direction: CGVector, beyond point: CGPoint) -> Double {
        let span = (marks[id] ?? []).filter { $0.seen && time - $0.time <= from + 1e-6 && time - $0.time >= to - 1e-6 }
        return span.map { m in Double((m.palm.x - point.x) * direction.dx + (m.palm.y - point.y) * direction.dy) }.max() ?? 0
    }

    /// The fastest the palm went in `direction` (a unit vector) over the last `window` seconds, in palm lengths a second: the larger of
    /// its own path frame to frame and the speed the tracker measured (which carries through a blur where the path cannot).
    func peak(_ id: Int, along direction: CGVector, within window: Double) -> Double {
        let recent = (marks[id] ?? []).filter { time - $0.time <= window + 1e-6 }
        var best = 0.0
        var previous: Mark?
        for m in recent {
            let size = max(m.size, 1)
            best = max(best, Double(m.velocity.dx * direction.dx + m.velocity.dy * direction.dy) / size)
            if let p = previous, p.seen, m.seen, m.time - p.time > 1e-3 {
                let d = m.palm - p.palm
                best = max(best, Double(d.dx * direction.dx + d.dy * direction.dy) / (m.time - p.time) / size)
            }
            previous = m
        }
        return best
    }

    /// The mean speed of the palm over the last `window` seconds, in palm lengths a second, from its path (zero with no path).
    func meanSpeed(_ id: Int, over window: Double) -> Double {
        let recent = seen(id, within: window)
        guard recent.count >= 2 else { return 0 }
        var path = 0.0
        for i in 1..<recent.count { path += HandState.distance(recent[i - 1].palm, recent[i].palm) }
        let dt = max(recent[recent.count - 1].time - recent[0].time, 1e-3)
        return path / dt / max(recent[recent.count - 1].size, 1)
    }

    /// Whether this hand has been followed for at least `seconds`.
    func known(_ id: Int, for seconds: Double) -> Bool {
        guard let first = marks[id]?.first else { return false }
        return time - first.time >= seconds - 1e-6
    }
}

// MARK: - A floating point

/// A point that follows its target like a weight on a spring, critically damped: it lags a little and settles without wobbling,
/// so a big orb floats after the hands rather than being nailed to them.
struct SaiyanSpring {
    /// How briskly it follows, in radians a second. About 1/omega seconds of lag.
    var omega: Double
    private(set) var value: SIMD2<Double>?
    private var speed = SIMD2<Double>(0, 0)

    init(omega: Double) { self.omega = omega }

    mutating func reset() {
        value = nil
        speed = .zero
    }

    @discardableResult
    mutating func update(_ target: CGPoint, dt: Double) -> CGPoint {
        let x = SIMD2(Double(target.x), Double(target.y))
        guard let v = value else {
            value = x
            return target
        }
        // Small steps, so a long frame cannot make it overshoot.
        var p = v, s = speed
        let steps = max(1, Int((dt * omega / 0.25).rounded(.up)))
        let h = dt / Double(steps)
        for _ in 0..<steps {
            let a = (x - p) * (omega * omega) - s * (2 * omega)
            s += a * h
            p += s * h
        }
        value = p
        speed = s
        return CGPoint(x: p.x, y: p.y)
    }

    var point: CGPoint? { value.map { CGPoint(x: $0.x, y: $0.y) } }
}
