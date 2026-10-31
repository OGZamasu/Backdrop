import AppKit
import CoreGraphics
import CoreImage
import simd

/// What a hand effect remembers about each hand between frames, and how it lets go of one that has vanished.
///
/// Tracking drops out for a few frames in fast motion, so an effect must never pop. Every hand it has seen keeps an entry with a
/// `presence` that rises quickly while the hand is in view and drains away over `fade` seconds after it is lost; the entry holds
/// the last place the hand was, so the effect can shrink away where it was instead of vanishing.
///
/// A hand that is lost for longer than the tracker's hold comes back with a new id. If it reappears close to where an entry was
/// last seen, it takes that entry over, so the effect carries on instead of one copy fading out while a fresh one fades in.
struct HandFXMemory<State> {
    struct Entry {
        /// The hand as it was last seen.
        var hand: HandState
        /// 0...1: how much of the effect to show.
        var presence: Double
        /// Whether the hand was in view this frame.
        var visible: Bool
        /// Seconds since the hand was first seen.
        var age = 0.0
        /// Seconds since it was last seen; 0 while it is in view.
        var lost = 0.0
        var state: State
    }

    private(set) var entries: [Entry] = []

    /// How fast an effect fades in, in seconds.
    static var attack: Double { 0.1 }

    var isEmpty: Bool { entries.isEmpty }

    /// The strongest presence of any hand: how much of the effect is showing at all.
    var strongest: Double { entries.map(\.presence).max() ?? 0 }

    mutating func removeAll() { entries.removeAll() }

    /// Takes this frame's hands. A hand seen for the first time gets a fresh state from `make`.
    mutating func update(_ hands: [HandState], dt: Double, fade: Double, make: (HandState) -> State) {
        for i in entries.indices { entries[i].visible = false }
        let incoming = Set(hands.map(\.id))
        var fresh: [HandState] = []
        for hand in hands {
            if let i = entries.firstIndex(where: { $0.hand.id == hand.id }) { take(hand, into: i, dt: dt) } else { fresh.append(hand) }
        }
        for hand in fresh {
            // The same hand back under a new id: a lost entry close by, whose own id is not in view.
            let reach = max(150, hand.size * 2.5)
            let lost = entries.indices.filter { !entries[$0].visible && !incoming.contains(entries[$0].hand.id) }
                .filter { HandFXKit.distance(entries[$0].hand.palm, hand.palm) < reach }
            if let i = lost.min(by: { HandFXKit.distance(entries[$0].hand.palm, hand.palm) < HandFXKit.distance(entries[$1].hand.palm, hand.palm) }) {
                take(hand, into: i, dt: dt)
            } else {
                entries.append(Entry(hand: hand, presence: min(1, dt / Self.attack), visible: true, state: make(hand)))
            }
        }
        for i in entries.indices where !entries[i].visible {
            entries[i].presence -= dt / max(fade, 1e-3)
            entries[i].lost += dt
        }
        entries.removeAll { $0.presence <= 0 }
        entries.sort { $0.hand.id < $1.hand.id }
    }

    private mutating func take(_ hand: HandState, into i: Int, dt: Double) {
        entries[i].hand = hand
        entries[i].visible = true
        entries[i].lost = 0
        entries[i].age += dt
        entries[i].presence = min(1, entries[i].presence + dt / Self.attack)
    }

    /// Changes an entry's state in place.
    mutating func modify(_ index: Int, _ change: (inout Entry) -> Void) { change(&entries[index]) }
}

/// Small pieces the hand effects share.
enum HandFXKit {
    /// Fully saturated neon colours around the colour wheel, worked out once.
    static let neon: [SIMD3<Double>] = (0..<48).map { i in
        let c = Palette.rgb(hue: Double(i) / 48, saturation: 0.9)
        return SIMD3(c.r, c.g, c.b)
    }

    /// A neon colour for a hue in any range; it wraps round the wheel.
    static func neon(hue: Double) -> SIMD3<Double> {
        let wrapped = hue - hue.rounded(.down)
        return neon[min(neon.count - 1, Int(wrapped * Double(neon.count)))]
    }

    /// The point `fraction` of the way from `a` to `b`.
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ fraction: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }

    static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> { a + (b - a) * min(1, max(0, t)) }

    /// A colour from hue (any range; it wraps), saturation and brightness, worked out directly. Cheap enough to call for every pixel of a
    /// sprite being baked, which going through NSColor is not.
    static func hsb(_ hue: Double, _ saturation: Double, _ brightness: Double) -> SIMD3<Double> {
        let h = (hue - hue.rounded(.down)) * 6
        let channel = { (n: Double) -> Double in
            let k = (n + h).truncatingRemainder(dividingBy: 6)
            return brightness * (1 - saturation * max(0, min(1, min(k, 4 - k))))
        }
        return SIMD3(channel(5), channel(3), channel(1))
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double { HandState.distance(a, b) }

    static func vector(_ p: CGPoint) -> SIMD2<Double> { SIMD2(Double(p.x), Double(p.y)) }
    static func point(_ v: SIMD2<Double>) -> CGPoint { CGPoint(x: v.x, y: v.y) }

    /// The way the fingers point, as a unit vector, from the wrist to the middle knuckle.
    static func up(of hand: HandState) -> SIMD2<Double> {
        let d = hand[.middleMCP] - hand.wrist
        let l = max(hypot(d.dx, d.dy), 1e-6)
        return SIMD2(Double(d.dx) / Double(l), Double(d.dy) / Double(l))
    }

    /// Eases from 0 to 1 and a little past before settling, like something springing into place.
    static func easeOutBack(_ t: Double, overshoot: Double = 1.7) -> Double {
        let x = min(1, max(0, t)) - 1
        return 1 + x * x * ((overshoot + 1) * x + overshoot)
    }

    static func easeOutCubic(_ t: Double) -> Double { let x = 1 - min(1, max(0, t)); return 1 - x * x * x }

    /// A jagged line between two points, made the way real lightning forks: push the middle sideways, then push the middle of each half, and so
    /// on with smaller and smaller pushes. The ends stay put, and the same `seed` always gives the same bolt. `amplitude` is the size of the
    /// first push in pixels and `segments` roughly how many pieces to end up with.
    static func zigzag(from a: CGPoint, to b: CGPoint, seed: UInt64, amplitude: Double, segments: Int) -> [CGPoint] {
        var rng = SplitMix64(seed: seed)
        let depth = max(1, Int(ceil(log2(Double(max(2, segments))))))
        var points = [a, b]
        var offset = amplitude
        for _ in 0..<depth {
            var next: [CGPoint] = []
            next.reserveCapacity(points.count * 2)
            for i in 0..<(points.count - 1) {
                let p = points[i], q = points[i + 1]
                let dx = Double(q.x - p.x), dy = Double(q.y - p.y)
                let length = max(1e-6, (dx * dx + dy * dy).squareRoot())
                let push = Double.random(in: -1...1, using: &rng) * offset
                next.append(p)
                next.append(CGPoint(x: Double(p.x + q.x) / 2 - dy / length * push, y: Double(p.y + q.y) / 2 + dx / length * push))
            }
            next.append(points[points.count - 1])
            points = next
            offset *= 0.55
        }
        return points
    }

    /// Strokes a polyline in the context's current colour and width.
    static func stroke(_ points: [CGPoint], in ctx: CGContext) {
        guard let first = points.first, points.count > 1 else { return }
        ctx.beginPath()
        ctx.move(to: first)
        for p in points.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }

    /// A jittery electric line: a coloured body and a white-hot core. Call with additive blending on; the wide soft glow around it comes
    /// from the bloom (`HandFXLight.add`), which costs far less than stroking wide lines on the CPU.
    static func drawBolt(_ points: [CGPoint], in ctx: CGContext, colour: SIMD3<Double>, strength: Double, width: Double = 1) {
        guard points.count > 1, strength > 0.01 else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let passes: [(Double, SIMD3<Double>, Double)] = [
            (10, colour, 0.26), (4.6, colour + (SIMD3(1, 1, 1) - colour) * 0.45, 0.6), (2.0, SIMD3(1, 1, 1), 1.0),
        ]
        for (w, c, a) in passes {
            ctx.setLineWidth(w * width)
            ctx.setStrokeColor(CGColor(red: c.x, green: c.y, blue: c.z, alpha: min(1, a * strength)))
            stroke(points, in: ctx)
        }
    }

    /// A soft glow dot in a colour, stamped from a cached sprite.
    static func glow(_ ctx: CGContext, at p: CGPoint, radius: Double, colour: SIMD3<Double>, alpha: Double) {
        guard let dot = WorldKit.softGlow(colour.x, colour.y, colour.z) else { return }
        ctx.stampDot(dot, at: p, radius: radius, alpha: alpha)
    }

    static func cgColor(_ c: SIMD3<Double>, _ alpha: Double = 1) -> CGColor {
        CGColor(red: min(1, max(0, c.x)), green: min(1, max(0, c.y)), blue: min(1, max(0, c.z)), alpha: min(1, max(0, alpha)))
    }

    /// A sprite made pixel by pixel: `colour(u, v)` gives red, green, blue and opacity for a point with u across and v up, both 0...1.
    static func sprite(width: Int, height: Int, _ colour: (Double, Double) -> (Double, Double, Double, Double)) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for x in 0..<width {
                let (r, g, b, a) = colour((Double(x) + 0.5) / Double(width), 1 - (Double(row) + 0.5) / Double(height))
                let i = (row * width + x) * 4
                let alpha = min(1, max(0, a))
                bytes[i] = UInt8(min(255, max(0, b * alpha * 255)))
                bytes[i + 1] = UInt8(min(255, max(0, g * alpha * 255)))
                bytes[i + 2] = UInt8(min(255, max(0, r * alpha * 255)))
                bytes[i + 3] = UInt8(alpha * 255)
            }
        }
        return bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)?.makeImage()
        }
    }

    /// The cross-section of a beam of light: a white-hot core inside a coloured body inside a wide soft glow, all with smooth gaussian edges.
    /// Draw it stretched along the beam with `drawBeam`.
    static func beamSprite(_ colour: SIMD3<Double>, core: Double = 0.05, body: Double = 0.16) -> CGImage? {
        sprite(width: 4, height: 96) { _, v in
            let d = abs(v - 0.5) * 2
            let white = exp(-pow(d / core, 2)), inner = 0.62 * exp(-pow(d / body, 2)), outer = 0.16 * exp(-pow(d / 0.5, 2)) * (1 - WorldKit.smoothstep(0.75, 1, d))
            let sum = SIMD3<Double>(1, 1, 1) * white + colour * (inner + outer)
            let a = min(1, max(sum.x, max(sum.y, sum.z)))
            guard a > 1e-4 else { return (0, 0, 0, 0) }
            return (sum.x / a, sum.y / a, sum.z / a, a)
        }
    }

    /// A soft round speck of light in a colour, with a white-hot point in the middle: one stamp for a spark or a mote.
    static func speckSprite(_ c: SIMD3<Double>) -> CGImage? {
        sprite(width: 40, height: 40) { u, v in
            let d = ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)).squareRoot() * 2
            let halo = 0.75 * exp(-5 * d * d) * (1 - WorldKit.smoothstep(0.75, 1, d)), core = exp(-55 * d * d)
            let sum = c * halo + SIMD3(1, 1, 1) * core
            let a = min(1, max(sum.x, max(sum.y, sum.z)))
            return a < 1e-4 ? (0, 0, 0, 0) : (sum.x / a, sum.y / a, sum.z / a, a)
        }
    }

    /// Lays a beam sprite from `a` to `b`, `width` pixels across.
    static func drawBeam(_ sprite: CGImage, from a: CGPoint, to b: CGPoint, width: Double, alpha: Double, in ctx: CGContext) {
        let length = distance(a, b)
        guard length > 0.5, alpha > 0.004 else { return }
        ctx.saveGState()
        ctx.translateBy(x: a.x, y: a.y)
        ctx.rotate(by: atan2(b.y - a.y, b.x - a.x))
        ctx.setAlpha(CGFloat(min(1, alpha)))
        ctx.draw(sprite, in: CGRect(x: 0, y: -width / 2, width: length, height: width))
        ctx.restoreGState()
    }

    /// A bitmap context in the canvas's own pixel layout, for baking a sprite once.
    static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)
    }
}

/// Sprites baked the first time each one is asked for, and kept. Baking a whole family of sprites at once (every colour, every variant) can
/// take long enough to stall a frame; baking each only when it is first drawn spreads the cost out.
enum HandFXSprites {
    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]

    static func named(_ key: String, _ make: () -> CGImage?) -> CGImage? {
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        guard let made = make() else { return nil }
        lock.lock()
        cache[key] = made
        lock.unlock()
        return made
    }
}

// MARK: - Reading a pose without flicker

/// Poses as smooth amounts instead of yes-or-no answers, so a hand halfway between two poses shows a halfway effect instead of
/// flickering between two. The edges sit either side of the ones `HandState.isExtended` uses.
enum HandFXPose {
    /// 0 for a finger curled into the palm, 1 for one held straight out.
    static func extended(_ finger: Finger, in hand: HandState) -> Double {
        if finger == .thumb { return WorldKit.smoothstep(0.3, 0.75, hand.thumbOpen) }
        return WorldKit.smoothstep(1.2, 1.62, hand.reach(of: finger)) * WorldKit.smoothstep(-0.15, 0.55, hand.straightness(of: finger))
    }

    /// How open the hand is: the four long fingers' extension averaged.
    static func openness(_ hand: HandState) -> Double {
        Finger.long.reduce(0) { $0 + extended($1, in: hand) } / 4
    }

    /// How much the hand is a fist: 1 with every long finger curled.
    static func fist(_ hand: HandState) -> Double {
        1 - (Finger.long.map { extended($0, in: hand) }.max() ?? 0)
    }

    /// How much the hand is pointing: the index finger out and the other three curled. The thumb may do as it likes.
    static func point(_ hand: HandState) -> Double {
        let others = [Finger.middle, .ring, .little].map { extended($0, in: hand) }.max() ?? 0
        return extended(.index, in: hand) * (1 - others)
    }

    /// How much the hand shows a peace sign: index and middle out, ring and little curled.
    static func peace(_ hand: HandState) -> Double {
        let others = max(extended(.ring, in: hand), extended(.little, in: hand))
        return min(extended(.index, in: hand), extended(.middle, in: hand)) * (1 - others)
    }
}

/// A level that moves toward a target at its own pace: quickly up and more slowly down, say, so an effect swells in and lingers out.
struct HandFXLevel {
    var value = 0.0
    /// Seconds for most of a rise, and for most of a fall.
    var rise: Double
    var fall: Double

    init(rise: Double, fall: Double, value: Double = 0) {
        self.rise = rise
        self.fall = fall
        self.value = value
    }

    @discardableResult
    mutating func approach(_ target: Double, dt: Double) -> Double {
        let tau = target > value ? rise : fall
        value += (target - value) * (1 - exp(-max(0, dt) / max(tau, 1e-4)))
        if abs(target - value) < 1e-4 { value = target }
        return value
    }
}

/// A switch with two thresholds and a short hold, so a signal hovering at the edge does not flip it back and forth: it turns on once the
/// signal has stayed above `on` for `holdOn` seconds and off once it has stayed below `off` for `holdOff`.
struct HandFXLatch {
    let on: Double
    let off: Double
    var holdOn = 0.05
    var holdOff = 0.15
    private(set) var isOn = false
    private var waited = 0.0

    init(on: Double, off: Double, holdOn: Double = 0.05, holdOff: Double = 0.15) {
        self.on = on
        self.off = off
        self.holdOn = holdOn
        self.holdOff = holdOff
    }

    @discardableResult
    mutating func update(_ signal: Double, dt: Double) -> Bool {
        let crossing = isOn ? signal < off : signal > on
        if crossing {
            waited += dt
            if waited >= (isOn ? holdOff : holdOn) - 1e-9 {
                isOn.toggle()
                waited = 0
            }
        } else {
            waited = 0
        }
        return isOn
    }

    mutating func reset() {
        isOn = false
        waited = 0
    }
}

/// Steadies a point that trembles: the "one euro" filter. Held still, it follows slowly and the shiver of tracking disappears; moved fast,
/// it follows almost at once, so nothing lags behind a quick hand.
struct HandFXSteady {
    /// How much it steadies a point at rest (lower is steadier) and how much faster it follows a point that moves, per pixel a second.
    var calm = 1.4
    var eager = 0.012
    private(set) var value: SIMD2<Double>?
    private var speed = SIMD2<Double>(0, 0)

    init(calm: Double = 1.4, eager: Double = 0.012) {
        self.calm = calm
        self.eager = eager
    }

    mutating func reset() {
        value = nil
        speed = .zero
    }

    /// Takes the newest measurement and returns the steadied point. A jump further than `snap` is taken at once.
    @discardableResult
    mutating func update(_ p: CGPoint, dt: Double, snap: Double = .infinity) -> CGPoint {
        let x = HandFXKit.vector(p)
        guard let last = value, simd_distance(last, x) < snap else {
            value = x
            speed = .zero
            return p
        }
        guard dt > 1e-5 else { return HandFXKit.point(last) }
        let moved = (x - last) / dt
        speed += (moved - speed) * Self.alpha(2.5, dt)
        let next = last + (x - last) * Self.alpha(calm + eager * simd_length(speed), dt)
        value = next
        return HandFXKit.point(next)
    }

    var point: CGPoint? { value.map(HandFXKit.point) }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}

/// All 21 joints of a hand steadied, for effects that draw the whole hand.
struct HandFXSteadyHand {
    private var joints = [HandFXSteady](repeating: HandFXSteady(calm: 1.8, eager: 0.03), count: HandJoint.count)

    /// The hand with its joints steadied. A hand that has jumped a long way (a new hand, a glitch) is taken as it is.
    mutating func update(_ hand: HandState, dt: Double) -> HandState {
        var out = hand
        let snap = max(160, hand.size * 2.5)
        for i in 0..<min(HandJoint.count, hand.joints.count) { out.joints[i] = joints[i].update(hand.joints[i], dt: dt, snap: snap) }
        return out
    }
}

/// Steadies every hand in view, each by its own id, and forgets a hand a second after it was last seen.
struct HandFXSteadier {
    private var hands: [Int: (steady: HandFXSteadyHand, unseen: Double)] = [:]

    mutating func update(_ incoming: [HandState], dt: Double) -> [HandState] {
        var out: [HandState] = []
        for hand in incoming {
            var steady = hands[hand.id]?.steady ?? HandFXSteadyHand()
            out.append(steady.update(hand, dt: dt))
            hands[hand.id] = (steady, 0)
        }
        let seen = Set(incoming.map(\.id))
        for id in Array(hands.keys) where !seen.contains(id) {
            hands[id]?.unseen += dt
            if (hands[id]?.unseen ?? 0) > 1 { hands[id] = nil }
        }
        return out
    }

    mutating func removeAll() { hands.removeAll() }
}

// MARK: - Named colours

/// The colours the hand effects are painted in, named so the family stays consistent. None is a pure primary.
enum HandFXPalette {
    static let white = SIMD3<Double>(1, 1, 1)
    /// Warm white for the hottest cores.
    static let hot = SIMD3<Double>(1.0, 0.97, 0.9)
    static let ember = (core: SIMD3<Double>(1.0, 0.93, 0.62), flame: SIMD3<Double>(1.0, 0.56, 0.16), deep: SIMD3<Double>(0.86, 0.2, 0.08))
    static let glacier = (frost: SIMD3<Double>(0.86, 0.96, 1.0), ice: SIMD3<Double>(0.5, 0.82, 1.0), deep: SIMD3<Double>(0.24, 0.5, 0.95))
    static let plasma = (cyan: SIMD3<Double>(0.25, 0.75, 1.0), violet: SIMD3<Double>(0.6, 0.4, 1.0))
    static let holo = (line: SIMD3<Double>(0.35, 0.95, 1.0), node: SIMD3<Double>(0.75, 1.0, 1.0), accent: SIMD3<Double>(1.0, 0.42, 0.78))
    static let wand = (gold: SIMD3<Double>(1.0, 0.84, 0.42), rose: SIMD3<Double>(1.0, 0.55, 0.78), lilac: SIMD3<Double>(0.72, 0.6, 1.0))
    /// The blade colours: one per hand.
    static let blades: [SIMD3<Double>] = [SIMD3(0.3, 0.72, 1.0), SIMD3(1.0, 0.3, 0.36), SIMD3(0.45, 1.0, 0.5), SIMD3(0.75, 0.45, 1.0)]
    /// A soft rainbow for ribbons, warm to cool and back.
    static let ribbon: [SIMD3<Double>] = [
        SIMD3(1.0, 0.36, 0.42), SIMD3(1.0, 0.62, 0.3), SIMD3(1.0, 0.86, 0.36), SIMD3(0.45, 0.9, 0.55),
        SIMD3(0.32, 0.78, 1.0), SIMD3(0.55, 0.5, 1.0), SIMD3(0.9, 0.45, 0.95),
    ]

    /// A colour along a looped list of colours, blended smoothly between neighbours.
    static func along(_ colours: [SIMD3<Double>], _ t: Double) -> SIMD3<Double> {
        guard !colours.isEmpty else { return white }
        let x = (t - t.rounded(.down)) * Double(colours.count)
        let i = Int(x) % colours.count, j = (i + 1) % colours.count
        let f = x - x.rounded(.down)
        let s = f * f * (3 - 2 * f)
        return colours[i] + (colours[j] - colours[i]) * s
    }
}

// MARK: - Light

enum HandFXLight {
    /// Adds a layer of light to the picture, with a soft bloom around everything bright in it, the way a camera lens flares around a lamp.
    static func add(_ layer: CIImage, to base: CIImage, rect: CGRect, bloom: Double = 0.8) -> CIImage {
        var lit = base
        if bloom > 0.01 { lit = WorldKit.adding(self.bloom(of: layer, rect: rect, gain: bloom), to: lit) }
        return WorldKit.adding(layer, to: lit).cropped(to: rect)
    }

    /// The soft light that spills round a layer: the layer shrunk to a quarter, blurred, enlarged again and scaled by `gain`. Working at a
    /// quarter of the size makes a wide blur cost next to nothing. Add it to a picture with `WorldKit.adding`.
    static func bloom(of layer: CIImage, rect: CGRect, gain: Double) -> CIImage {
        let small = layer.transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .applyingFilter("CIBicubicScaleTransform", parameters: [kCIInputScaleKey: 0.25, kCIInputAspectRatioKey: 1])
        let box = CGRect(x: 0, y: 0, width: (rect.width / 4).rounded(.up), height: (rect.height / 4).rounded(.up))
        return small.clampedToExtent().applyingGaussianBlur(sigma: 4.5).cropped(to: box)
            .transformed(by: CGAffineTransform(scaleX: 4, y: 4).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(gain), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(gain), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(gain), w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(gain)),
            ])
            .cropped(to: rect)
    }
}

// MARK: - The idle hint

/// A small glowing hand that waves at the bottom of the picture while no hand has been seen, so it is clear what the effect wants. It is a
/// picture, not words, so it reads the same in a mirrored preview, and it shows only for a few seconds at a time: soon after the effect
/// starts, and again after the hands have been away for a while. The words are in the status line.
struct HandFXHint {
    /// 0...1: how much of the hint is showing.
    private(set) var level = 0.0
    private var absent = 0.0
    private var shown = 0.0
    private var everSeen = false
    private var clock = 0.0

    /// Seconds without a hand before it shows: soon at the start, longer once a hand has been and gone.
    static let firstDelay = 0.6
    static let laterDelay = 4.0
    /// How long one showing lasts.
    static let showSeconds = 4.5
    /// Where it sits: the middle of the bottom, inside the safe margin.
    static func center(in size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.115) }
    /// The part of the picture it may touch.
    static func area(in size: CGSize) -> CGRect {
        let c = center(in: size)
        return CGRect(x: c.x - 100, y: c.y - 84, width: 200, height: 168)
    }

    var isShowing: Bool { level > 0.004 }

    mutating func reset() { self = HandFXHint() }

    mutating func update(handsInView: Bool, dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        clock += dt
        if handsInView {
            absent = 0
            shown = 0
            everSeen = true
        } else {
            absent += dt
        }
        let wanted = !handsInView && absent >= (everSeen ? Self.laterDelay : Self.firstDelay) && shown < Self.showSeconds
        if wanted { shown += dt }
        // In gently, and out briskly the moment a hand appears.
        level = wanted ? level + (1 - level) * (1 - exp(-dt / 0.3)) : max(0, level - dt / 0.25)
    }

    /// Lays the hint over `image` in a layer of its own, when it is showing.
    func compose(over image: CIImage, services: LensServices, rect: CGRect, accent: SIMD3<Double>) -> CIImage {
        guard isShowing, let layer = services.overlay({ ctx in draw(in: ctx, size: rect.size, accent: accent) }) else { return image }
        return layer.composited(over: image).cropped(to: rect)
    }

    func draw(in ctx: CGContext, size: CGSize, accent: SIMD3<Double>) {
        guard isShowing, let glyph = Self.glyph else { return }
        let c = Self.center(in: size)
        let appear = HandFXKit.easeOutBack(level, overshoot: 1.2)
        // A friendly wave: the hand rocks about its wrist, two beats and a rest.
        let beat = clock.truncatingRemainder(dividingBy: 2.4)
        let wave = beat < 1.2 ? sin(beat / 1.2 * 2 * .pi * 2) * 0.16 * sin(beat / 1.2 * .pi) : 0
        let height = 84 * (0.85 + 0.15 * appear)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(min(1, level)))
        // A dark soft pad behind, so the white hand reads over a white shirt, and a glow in the effect's colour.
        if let shade = WorldKit.softGlow(0, 0, 0) { ctx.stampDot(shade, at: c, radius: 78, alpha: 0.38 * level) }
        ctx.setBlendMode(.plusLighter)
        HandFXKit.glow(ctx, at: CGPoint(x: c.x, y: c.y + 4), radius: 64, colour: accent, alpha: 0.55 * level)
        ctx.setBlendMode(.normal)
        // Two little arcs either side, as if it were moving.
        ctx.setLineCap(.round)
        ctx.setLineWidth(3)
        for side in [-1.0, 1.0] {
            let swing = max(0, side * wave) / 0.16
            ctx.setStrokeColor(HandFXKit.cgColor(HandFXKit.mix(accent, HandFXPalette.white, 0.55), (0.35 + 0.5 * swing) * level))
            for k in 0..<2 {
                let r = 44.0 + Double(k) * 11
                ctx.beginPath()
                ctx.addArc(center: CGPoint(x: c.x, y: c.y - 2), radius: r, startAngle: side > 0 ? -0.45 : .pi - 0.45,
                           endAngle: side > 0 ? 0.45 : .pi + 0.45, clockwise: false)
                ctx.strokePath()
            }
        }
        ctx.translateBy(x: c.x, y: c.y - height * 0.5)
        ctx.rotate(by: CGFloat(-wave))
        let width = height * CGFloat(glyph.width) / CGFloat(glyph.height)
        ctx.interpolationQuality = .high
        ctx.draw(glyph, in: CGRect(x: -width / 2, y: 0, width: width, height: height))
        ctx.restoreGState()
    }

    /// The hand picture: a raised open hand in soft white with a light from the top left and a fine outline, drawn once.
    private static let glyph: CGImage? = {
        let scale = 2.0
        let w = Int(124 * scale), h = Int(156 * scale)
        guard let ctx = HandFXKit.bitmap(width: w, height: h) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let path = CGMutablePath()
        // The palm, then a rounded capsule for each finger and the thumb, all filled together.
        path.addRoundedRect(in: CGRect(x: 40, y: 8, width: 56, height: 66), cornerWidth: 24, cornerHeight: 24)
        func finger(_ x: Double, _ base: Double, _ length: Double, _ width: Double, _ angle: Double) {
            let r = CGRect(x: -width / 2, y: 0, width: width, height: length)
            var t = CGAffineTransform(translationX: x, y: base).rotated(by: angle)
            path.addPath(CGPath(roundedRect: r, cornerWidth: width / 2, cornerHeight: width / 2, transform: &t))
        }
        finger(48, 50, 62, 15, 0.12)
        finger(63, 54, 74, 15.5, 0.03)
        finger(78, 52, 68, 15, -0.07)
        finger(91, 46, 52, 13.5, -0.18)
        finger(47, 26, 46, 17, 0.78)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // The outline first, then the fill over it, so only the outside edge of the outline shows: no lines between the fingers and palm.
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.62, 0.7, 0.92, 1])!)
        ctx.setLineWidth(3)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let light = [CGColor(colorSpace: space, components: [1, 1, 1, 1])!, CGColor(colorSpace: space, components: [0.85, 0.9, 1, 1])!] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: light, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 30, y: 150), end: CGPoint(x: 105, y: 8), options: [])
        }
        ctx.restoreGState()
        return ctx.makeImage()
    }()
}
