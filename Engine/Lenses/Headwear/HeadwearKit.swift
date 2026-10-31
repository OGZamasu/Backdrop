import CoreGraphics
import Foundation
import simd

// Shared tools for the dress-up costumes: colours, paths, a pen that paints with gradients and outlines, and the
// springs that make a beard sway and an ear flop. Everything is drawn in face units (see `HeadwearFrame`).

/// A point, quickly.
func hwp(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

// MARK: - Colour

/// An sRGB colour that is easy to write down and to lighten, darken and fade.
struct HeadwearColor: Hashable {
    var r: Double, g: Double, b: Double, a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    /// From 0xRRGGBB.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha)
    }

    var cg: CGColor { CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }

    func mixed(with other: HeadwearColor, _ t: Double) -> HeadwearColor {
        HeadwearColor(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }
    func lighter(_ t: Double) -> HeadwearColor { mixed(with: HeadwearColor(1, 1, 1, a), t) }
    func darker(_ t: Double) -> HeadwearColor { mixed(with: HeadwearColor(0, 0, 0, a), t) }
    /// The same colour with a different opacity.
    func faded(_ alpha: Double) -> HeadwearColor { HeadwearColor(r, g, b, alpha) }
    /// The same colour, its opacity multiplied.
    func scaled(_ k: Double) -> HeadwearColor { HeadwearColor(r, g, b, a * k) }

    static let white = HeadwearColor(1, 1, 1)
    static let black = HeadwearColor(0, 0, 0)
}

// MARK: - Shapes

/// Builders for the outlines costumes are made of. All in face units.
enum HeadwearShape {
    static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    /// A smooth curve through the points (Catmull-Rom turned into Béziers). `smoothness` 1 is the usual, 0 is straight lines.
    static func smooth(_ points: [CGPoint], closed: Bool = true, smoothness: Double = 1) -> CGPath {
        let path = CGMutablePath()
        let n = points.count
        guard n >= 2 else { return path }
        func at(_ i: Int) -> CGPoint { closed ? points[((i % n) + n) % n] : points[min(max(i, 0), n - 1)] }
        path.move(to: points[0])
        let k = smoothness / 6
        for i in 0..<(closed ? n : n - 1) {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) * k, y: p1.y + (p2.y - p0.y) * k),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) * k, y: p2.y - (p3.y - p1.y) * k))
        }
        if closed { path.closeSubpath() }
        return path
    }

    /// `hole` draws it the other way round, so that inside a bigger shape filled with the usual rule it is cut out.
    static func ellipse(_ c: CGPoint, rx: Double, ry: Double, turn: Double = 0, hole: Bool = false) -> CGPath {
        let path = CGMutablePath()
        var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: turn)
        if hole { t = t.scaledBy(x: -1, y: 1) }
        path.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: t)
        return path
    }

    static func rounded(_ rect: CGRect, radius: Double) -> CGPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    /// Points along a centre line, started at `start`, whose direction at fraction `t` of the way along is `heading(t)` (radians,
    /// counter-clockwise from the +x axis, so pi/2 is straight up).
    static func spine(from start: CGPoint, length: Double, steps: Int = 12, heading: (Double) -> Double) -> [CGPoint] {
        var p = start
        var points = [p]
        let h = length / Double(steps)
        for i in 0..<steps {
            let a = heading((Double(i) + 0.5) / Double(steps))
            p = CGPoint(x: p.x + cos(a) * h, y: p.y + sin(a) * h)
            points.append(p)
        }
        return points
    }

    /// A tapering ribbon along a spine: ears, horns, leaves, locks of hair. `width(t)` is the half-width at fraction `t`.
    /// `tip` rounds the far end off beyond the last point, `base` the near end (both in half-widths).
    static func ribbon(_ spine: [CGPoint], tip: Double = 0.7, base: Double = 0, width: (Double) -> Double) -> CGPath {
        guard spine.count >= 2 else { return CGMutablePath() }
        var left: [CGPoint] = [], right: [CGPoint] = []
        var tangents: [CGPoint] = []
        for i in spine.indices {
            let a = spine[max(0, i - 1)], b = spine[min(spine.count - 1, i + 1)]
            let len = max(hypot(b.x - a.x, b.y - a.y), 1e-9)
            let tx = (b.x - a.x) / len, ty = (b.y - a.y) / len
            tangents.append(CGPoint(x: tx, y: ty))
            let w = width(Double(i) / Double(spine.count - 1))
            left.append(CGPoint(x: spine[i].x - ty * w, y: spine[i].y + tx * w))
            right.append(CGPoint(x: spine[i].x + ty * w, y: spine[i].y - tx * w))
        }
        var loop = left
        if tip > 0, let end = spine.last, let t = tangents.last {
            let w = width(1)
            loop.append(CGPoint(x: end.x + t.x * max(w, 0.02) * tip, y: end.y + t.y * max(w, 0.02) * tip))
        }
        loop += right.reversed()
        if base > 0, let start = spine.first, let t = tangents.first {
            let w = width(0)
            loop.append(CGPoint(x: start.x - t.x * w * base, y: start.y - t.y * w * base))
        }
        return smooth(loop, closed: true)
    }

    /// Points along the smooth curve through `points`, about `spacing` apart, for placing things along an edge.
    static func along(_ points: [CGPoint], spacing: Double) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        var dense: [CGPoint] = []
        func at(_ i: Int) -> CGPoint { points[min(max(i, 0), points.count - 1)] }
        for i in 0..<(points.count - 1) {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            for k in 0..<10 {
                let t = Double(k) / 10, u = 1 - t
                dense.append(CGPoint(x: u * u * u * p1.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p2.x,
                                     y: u * u * u * p1.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p2.y))
            }
        }
        dense.append(points[points.count - 1])
        var out = [dense[0]]
        var travelled = 0.0
        for i in 1..<dense.count {
            travelled += hypot(dense[i].x - dense[i - 1].x, dense[i].y - dense[i - 1].y)
            if travelled >= spacing { out.append(dense[i]); travelled = 0 }
        }
        return out
    }

    /// A pointed four-armed sparkle.
    static func sparkle(_ c: CGPoint, radius: Double, pinch: Double = 0.2, turn: Double = 0) -> CGPath {
        let path = CGMutablePath()
        let tips = (0..<4).map { CGPoint(x: c.x + cos(turn + Double($0) * .pi / 2) * radius, y: c.y + sin(turn + Double($0) * .pi / 2) * radius) }
        path.move(to: tips[0])
        for i in 0..<4 {
            let a = turn + (Double(i) + 0.5) * .pi / 2
            path.addQuadCurve(to: tips[(i + 1) % 4], control: CGPoint(x: c.x + cos(a) * radius * pinch, y: c.y + sin(a) * radius * pinch))
        }
        path.closeSubpath()
        return path
    }

    /// A star with `points` tips.
    static func star(_ c: CGPoint, points: Int = 5, outer: Double, inner: Double, turn: Double = .pi / 2) -> CGPath {
        var pts: [CGPoint] = []
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let a = turn + Double(i) * .pi / Double(points)
            pts.append(CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
        }
        return polygon(pts)
    }
}

// MARK: - Pen

/// Paints shapes with gradients, outlines and glows.
struct HeadwearPen {
    let ctx: CGContext

    private static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private static let cacheLock = NSLock()
    private static var glows: [UInt32: CGImage] = [:]

    /// A gradient through the colours, evenly spaced unless `stops` say otherwise.
    static func gradient(_ colors: [HeadwearColor], at stops: [Double]? = nil) -> CGGradient? {
        let locations: [CGFloat] = stops?.map { CGFloat($0) }
            ?? colors.indices.map { colors.count > 1 ? CGFloat($0) / CGFloat(colors.count - 1) : 0 }
        return CGGradient(colorsSpace: space, colors: colors.map(\.cg) as CFArray, locations: locations)
    }

    /// A soft round glow, drawn once in a colour and then just stamped: much cheaper than working a gradient out for every pixel
    /// of a big halo each frame. Colours are rounded to sixteen levels a channel.
    private static func glowSprite(_ r: Double, _ g: Double, _ b: Double) -> CGImage? {
        func level(_ v: Double) -> UInt32 { UInt32(min(15, max(0, (v * 15).rounded()))) }
        let key = level(r) << 8 | level(g) << 4 | level(b)
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = glows[key] { return hit }
        let side = 96
        guard let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let (cr, cg, cb) = (Double(level(r)) / 15, Double(level(g)) / 15, Double(level(b)) / 15)
        let stops = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
        let colors = stops.map { CGColor(srgbRed: CGFloat(cr), green: CGFloat(cg), blue: CGFloat(cb), alpha: CGFloat(pow(1 - $0, 2))) }
        guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops.map { CGFloat($0) }) else { return nil }
        let mid = CGPoint(x: side / 2, y: side / 2)
        c.drawRadialGradient(gradient, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: CGFloat(side / 2), options: [])
        let made = c.makeImage()
        if let made { glows[key] = made }
        return made
    }

    func fill(_ path: CGPath, _ color: HeadwearColor, evenOdd: Bool = false) {
        guard color.a > 0.002 else { return }
        ctx.addPath(path)
        ctx.setFillColor(color.cg)
        ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
    }

    func stroke(_ path: CGPath, _ color: HeadwearColor, width: Double, cap: CGLineCap = .round, join: CGLineJoin = .round) {
        guard color.a > 0.002 else { return }
        ctx.addPath(path)
        ctx.setStrokeColor(color.cg)
        ctx.setLineWidth(CGFloat(width))
        ctx.setLineCap(cap)
        ctx.setLineJoin(join)
        ctx.strokePath()
    }

    func line(_ a: CGPoint, _ b: CGPoint, _ color: HeadwearColor, width: Double) {
        let p = CGMutablePath()
        p.move(to: a); p.addLine(to: b)
        stroke(p, color, width: width)
    }

    /// Fills a path with a gradient running across its bounding box in `direction` (default: top to bottom), then inks its edge.
    func paint(_ path: CGPath, _ colors: [HeadwearColor], ink: HeadwearColor? = nil, inkWidth: Double = 0.045,
               direction: CGVector = CGVector(dx: 0, dy: -1), evenOdd: Bool = false) {
        let box = path.boundingBoxOfPath
        if box.width > 0 || box.height > 0, let gradient = Self.gradient(colors) {
            let len = max(hypot(direction.dx, direction.dy), 1e-9)
            let d = CGVector(dx: direction.dx / len, dy: direction.dy / len)
            let reach = (abs(d.dx) * box.width + abs(d.dy) * box.height) / 2
            let mid = CGPoint(x: box.midX, y: box.midY)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip(using: evenOdd ? .evenOdd : .winding)
            ctx.drawLinearGradient(gradient, start: CGPoint(x: mid.x - d.dx * reach, y: mid.y - d.dy * reach),
                                   end: CGPoint(x: mid.x + d.dx * reach, y: mid.y + d.dy * reach),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
        if let ink { stroke(path, ink, width: inkWidth) }
    }

    /// A round gradient clipped to a path: bright at `center`, darker at `radius`.
    func paintRound(_ path: CGPath, center: CGPoint, radius: Double, _ colors: [HeadwearColor], ink: HeadwearColor? = nil, inkWidth: Double = 0.045) {
        if let gradient = Self.gradient(colors) {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(radius),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
        if let ink { stroke(path, ink, width: inkWidth) }
    }

    /// Draws inside a path only.
    func clipped(to path: CGPath, evenOdd: Bool = false, _ draw: () -> Void) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip(using: evenOdd ? .evenOdd : .winding)
        draw()
        ctx.restoreGState()
    }

    /// Moves, turns and scales everything drawn inside.
    func placed(at p: CGPoint, turn: Double = 0, scale: Double = 1, stretch: CGSize? = nil, _ draw: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        if turn != 0 { ctx.rotate(by: CGFloat(turn)) }
        if let stretch { ctx.scaleBy(x: stretch.width * scale, y: stretch.height * scale) } else if scale != 1 { ctx.scaleBy(x: scale, y: scale) }
        draw()
        ctx.restoreGState()
    }

    /// A soft round glow; `color.a` is its strength at the centre. It fades smoothly to nothing at `radius`, with no visible edge.
    func glow(at c: CGPoint, radius: Double, _ color: HeadwearColor, additive: Bool = false) {
        guard radius > 0, color.a > 0.004, let sprite = Self.glowSprite(color.r, color.g, color.b) else { return }
        ctx.saveGState()
        if additive { ctx.setBlendMode(.plusLighter) }
        ctx.setAlpha(CGFloat(min(1, color.a)))
        ctx.interpolationQuality = .low
        ctx.draw(sprite, in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        ctx.restoreGState()
    }

    /// A glowing dot with a hard bright core.
    func dot(at c: CGPoint, radius: Double, _ color: HeadwearColor) {
        fill(HeadwearShape.ellipse(c, rx: radius, ry: radius), color)
    }

    func sparkle(at c: CGPoint, radius: Double, _ color: HeadwearColor, turn: Double = 0, additive: Bool = false) {
        guard radius > 0.001, color.a > 0.004 else { return }
        ctx.saveGState()
        if additive { ctx.setBlendMode(.plusLighter) }
        fill(HeadwearShape.sparkle(c, radius: radius, pinch: 0.16, turn: turn), color)
        ctx.restoreGState()
    }

    /// A soft oval shadow, darkest in the middle: where a hat or a band presses on the head. Same sprite as `glow`, squashed.
    func shadow(at c: CGPoint, rx: Double, ry: Double, alpha: Double = 0.35, turn: Double = 0) {
        guard rx > 0, ry > 0, alpha > 0.004, let sprite = Self.glowSprite(0.06, 0.03, 0.08) else { return }
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        if turn != 0 { ctx.rotate(by: CGFloat(turn)) }
        ctx.setAlpha(CGFloat(min(1, alpha)))
        ctx.interpolationQuality = .low
        ctx.draw(sprite, in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
        ctx.restoreGState()
    }

    /// How many output pixels one unit of the current drawing space covers, whatever it has been moved, turned or scaled by.
    var pixelsPerUnit: Double {
        let t = ctx.userSpaceToDeviceSpaceTransform
        return Double(hypot(t.a, t.b))
    }

    /// The same art, drawn once at a resolution to suit the face and kept (see `HeadwearSprites`). `window` is the box the art
    /// fills, in the current units; `pixelsPerUnit` is how many output pixels one of those units covers. The art must not depend on
    /// anything that changes from frame to frame.
    func sprite(_ name: String, window: CGRect, pixelsPerUnit: Double, alpha: Double = 1, _ paint: (HeadwearPen) -> Void) {
        guard alpha > 0.004 else { return }
        guard let image = HeadwearSprites.image(name, window: window, density: HeadwearSprites.density(for: pixelsPerUnit), paint) else {
            paint(self)
            return
        }
        ctx.saveGState()
        if alpha < 1 { ctx.setAlpha(CGFloat(alpha)) }
        // Baked a little sharper than it is shown, so a plain smooth resample is enough.
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: window)
        ctx.restoreGState()
    }
}

// MARK: - Baked art

/// Rigid parts of a costume (a crown, a helmet, a hat) drawn once into a picture and kept, then stamped every frame: filling a few
/// dozen gradient paths thirty times a second is wasted work when nothing about them changes. Each is baked at a pixel density a
/// little above the face's own, from a few fixed steps, so it stays crisp near and far and is baked again only when the face
/// moves a long way nearer.
enum HeadwearSprites {
    /// Pixels to a unit the art is baked at. A face 84 pixels across the eyes uses the 90 step.
    static let densities: [Double] = [40, 60, 90, 135, 200, 300]
    /// How much memory the kept pictures may take before the oldest are let go.
    static let budget = 48 << 20

    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]
    private static var order: [String] = []
    private static var bytes = 0

    /// The baking density for art that covers `pixelsPerUnit` output pixels to a unit.
    static func density(for pixelsPerUnit: Double) -> Double {
        densities.first { $0 >= pixelsPerUnit * 1.05 } ?? densities[densities.count - 1]
    }

    /// The picture of `window` painted by `paint`, from the cache when it has been made before.
    static func image(_ name: String, window: CGRect, density: Double, _ paint: (HeadwearPen) -> Void) -> CGImage? {
        let key = "\(name)@\(Int(density))"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let width = Int(ceil(window.width * density)), height = Int(ceil(window.height * density))
        guard width > 0, height > 0, width * height <= 3_000_000,
              let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: Sprites.bitmapInfo)
        else { return nil }
        c.setAllowsAntialiasing(true)
        c.interpolationQuality = .high
        c.scaleBy(x: CGFloat(Double(width) / window.width), y: CGFloat(Double(height) / window.height))
        c.translateBy(x: -window.minX, y: -window.minY)
        paint(HeadwearPen(ctx: c))
        guard let made = c.makeImage() else { return nil }
        lock.lock(); defer { lock.unlock() }
        if cache[key] == nil {
            cache[key] = made
            order.append(key)
            bytes += made.bytesPerRow * made.height
            while bytes > budget, order.count > 1 {
                let old = order.removeFirst()
                if let gone = cache.removeValue(forKey: old) { bytes -= gone.bytesPerRow * gone.height }
            }
        }
        return cache[key]
    }
}

// MARK: - Noise

/// Repeatable pseudo-random numbers from a pair of integers, for scattering sparkles and freckles that stay where they are.
enum HeadwearNoise {
    /// A value in 0...1 that is always the same for the same `index` and `salt`.
    static func unit(_ index: Int, _ salt: Int = 0) -> Double {
        var z = UInt64(truncatingIfNeeded: index &* 0x9E3779B1 &+ salt &* 0x85EBCA6B &+ 0x1234567)
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

// MARK: - Easing

enum HeadwearEase {
    static func clamp01(_ t: Double) -> Double { min(1, max(0, t)) }

    static func smoothstep(_ t: Double) -> Double { let x = clamp01(t); return x * x * (3 - 2 * x) }

    /// 0 to 1 with a little overshoot, like something popping into place.
    static func outBack(_ t: Double) -> Double {
        let x = clamp01(t) - 1, c = 1.9
        return 1 + (c + 1) * x * x * x + c * x * x
    }

    /// 0 to 1 with bounces at the end, like something landing.
    static func outBounce(_ t: Double) -> Double {
        var x = clamp01(t)
        let n = 7.5625, d = 2.75
        if x < 1 / d { return n * x * x }
        if x < 2 / d { x -= 1.5 / d; return n * x * x + 0.75 }
        if x < 2.5 / d { x -= 2.25 / d; return n * x * x + 0.9375 }
        x -= 2.625 / d
        return n * x * x + 0.984375
    }

    /// How far above its resting place something that falls onto your head starts, in eye-spacings, `seconds` after the face
    /// appeared. Zero once it has landed (with a bounce or two on the way).
    static func drop(_ seconds: Double, delay: Double = 0, height: Double = 2.8, duration: Double = 0.7) -> Double {
        height * (1 - outBounce((seconds - delay) / duration))
    }

    /// 0 until `delay`, then up to 1 with a little overshoot over `duration`.
    static func pop(_ seconds: Double, delay: Double = 0, duration: Double = 0.5) -> Double {
        outBack((seconds - delay) / duration)
    }
}

// MARK: - Signals

/// A yes/no with a gap between saying yes and saying no, so a reading that hovers at the threshold doesn't flicker.
struct HeadwearGate {
    let on: Double
    let off: Double
    private(set) var isOn = false
    /// True only in the frame the gate switched on.
    private(set) var rose = false

    init(on: Double, off: Double) { self.on = on; self.off = off }

    mutating func update(_ value: Double) {
        let was = isOn
        isOn = value > (isOn ? off : on)
        rose = isOn && !was
    }
}

/// Eases toward a target, faster one way than the other.
struct HeadwearFollower {
    private(set) var value = 0.0

    mutating func follow(_ target: Double, dt: Double, rise: Double, fall: Double) {
        let rate = target > value ? rise : fall
        value += (target - value) * (1 - exp(-rate * dt))
    }
}

/// What the face is doing, steadied: a yes/no for each expression (with hysteresis) and a smooth 0...1 that follows it.
struct HeadwearSignals {
    var mouthGate = HeadwearGate(on: 0.4, off: 0.22)
    var browGate = HeadwearGate(on: 0.5, off: 0.3)
    var smileGate = HeadwearGate(on: 0.42, off: 0.24)
    var blinkGate = HeadwearGate(on: 0.55, off: 0.3)

    private var mouthEase = HeadwearFollower()
    private var browEase = HeadwearFollower()
    private var smileEase = HeadwearFollower()

    var mouthIsOpen: Bool { mouthGate.isOn }
    var browsAreUp: Bool { browGate.isOn }
    var isSmiling: Bool { smileGate.isOn }
    var isBlinking: Bool { blinkGate.isOn }

    /// Smooth 0...1 versions: 1 while the expression is held, easing in quickly and out more slowly.
    var open: Double { mouthEase.value }
    var raised: Double { browEase.value }
    var grin: Double { smileEase.value }

    mutating func update(_ face: FaceState, dt: Double) {
        mouthGate.update(face.mouthOpen)
        browGate.update(face.browRaise)
        smileGate.update(face.smile)
        blinkGate.update(face.blink)
        mouthEase.follow(mouthIsOpen ? 1 : 0, dt: dt, rise: 14, fall: 7)
        browEase.follow(browsAreUp ? 1 : 0, dt: dt, rise: 12, fall: 5)
        smileEase.follow(isSmiling ? 1 : 0, dt: dt, rise: 9, fall: 4)
    }
}

// MARK: - Motion

/// How the head is moving, in eye-spacings so it means the same near and far.
struct HeadwearMotion {
    private var last: (x: Double, y: Double, roll: Double, io: Double)?
    /// Eye-spacings per second, in the picture's axes, smoothed.
    private(set) var velocity = SIMD2<Double>(0, 0)
    /// Eye-spacings per second squared, in the picture's axes, smoothed.
    private(set) var acceleration = SIMD2<Double>(0, 0)
    /// Radians per second, counter-clockwise.
    private(set) var spin = 0.0

    mutating func forget() { self = HeadwearMotion() }

    mutating func update(_ face: FaceState, dt: Double) {
        let c = face.eyeCenter
        let now = (x: Double(c.x), y: Double(c.y), roll: face.roll, io: max(face.interocular, 1))
        defer { last = now }
        guard let before = last, dt > 1e-4 else { return }
        let raw = SIMD2((now.x - before.x), (now.y - before.y)) / (before.io * dt)
        let v = velocity + (raw - velocity) * (1 - exp(-dt / 0.06))
        let a = (v - velocity) / dt
        var smoothed = acceleration + (a - acceleration) * (1 - exp(-dt / 0.09))
        // Tracking jitter is not a shake: ignore the small stuff, and cap the big.
        let size = simd_length(smoothed)
        if size > 0 { smoothed *= max(0, min(size - 2.5, 70)) / size }
        acceleration = smoothed
        velocity = v
        var turn = now.roll - before.roll
        while turn > .pi { turn -= 2 * .pi }
        while turn < -.pi { turn += 2 * .pi }
        spin += (turn / dt - spin) * (1 - exp(-dt / 0.08))
    }

    /// The acceleration along the face's own axes: x across it, y up it.
    func local(roll: Double) -> SIMD2<Double> {
        let c = cos(roll), s = sin(roll)
        return SIMD2(acceleration.x * c + acceleration.y * s, -acceleration.x * s + acceleration.y * c)
    }
}

/// A spring that something hangs from or springs back on: an ear, a beard, a tassel. `x` is an angle or an offset, as the
/// costume likes. Head acceleration pushes it and it settles back with a wobble.
struct HeadwearSwing {
    var x = 0.0
    var v = 0.0
    let omega: Double
    let damping: Double
    /// How far a unit of head acceleration (eye-spacings per second squared) pushes it at rest.
    let gain: Double
    let limit: Double

    init(omega: Double, damping: Double = 0.18, gain: Double = 0.03, limit: Double = 1.2) {
        self.omega = omega; self.damping = damping; self.gain = gain; self.limit = limit
    }

    /// `accel` is the head's acceleration across the face; `rest` is where it hangs when nothing moves; `kick` is any extra force.
    mutating func step(dt: Double, accel: Double, rest: Double = 0, kick: Double = 0) {
        let total = min(dt, 0.1)
        let n = max(1, Int(ceil(total * 120)))
        let h = total / Double(n)
        for _ in 0..<n {
            let target = rest - gain * accel
            let a = omega * omega * (target - x) - 2 * damping * omega * v + kick
            v += a * h
            x += v * h
            if abs(x) > limit { x = limit * (x < 0 ? -1 : 1); v *= -0.3 }
        }
    }

    mutating func reset() { x = 0; v = 0 }

    /// A sudden shove, as a flick of the wrist.
    mutating func shove(_ speed: Double) { v += speed }
}

// MARK: - Head

/// The shape of this head, in eye-spacings, read from the tracked landmarks (eyes, mouth, brows, face box) and steadied over a
/// second or so, so a nod or a noisy frame doesn't shift a hat about.
///
/// Costumes are drawn for the cartoon test face, whose mouth sits 0.95 eye-spacings below the eyes. A real face is longer (about
/// 1.1 to 1.25) and its skull higher, so hats, crowns and ears are lifted by `tall`, and things worn at the sides of the head move
/// out by `wide`.
struct HeadwearHead: Equatable {
    /// How far below the eyes the middle of the mouth is when it is shut.
    var mouthDrop = 0.95
    /// Half the width of the head, from the face box.
    var halfWidth = 1.13
    /// How high the eyebrows sit above the eyes at rest.
    var brow = 0.4

    /// The test face's numbers, which every costume is drawn for.
    static let reference = HeadwearHead()

    /// How much longer than the test face this one is.
    var tall: Double { min(1.3, max(0.9, mouthDrop / Self.reference.mouthDrop)) }
    /// How much wider.
    var wide: Double { min(1.15, max(0.92, halfWidth / Self.reference.halfWidth)) }
    /// A height above the eyes on the test face, moved to the same place on this head.
    func up(_ y: Double) -> Double { y * tall }
    /// A point beside the head on the test face, moved out to the same place on this head.
    func side(_ x: Double) -> Double { x * wide }
    /// A point on the head of the test face, on this head.
    func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * wide, y: y > 0 ? y * tall : y) }
    /// The top of the skull.
    var crown: Double { up(1.42) }
    /// The middle of the forehead, where a hat's band rests.
    var brim: Double { up(1.05) }
}

/// Learns `HeadwearHead` from a stream of faces.
struct HeadwearHeadReader {
    private(set) var head = HeadwearHead()
    private var started = false

    mutating func forget() { head = HeadwearHead(); started = false }

    /// `mouth` is the mouth in face units. Only learnt while the mouth is mostly shut, since an open jaw pulls the middle of the lips down.
    mutating func update(_ face: FaceState, mouth: CGPoint, dt: Double) {
        let io = max(face.interocular, 1)
        let c = cos(face.roll), s = sin(face.roll)
        let b = SIMD2(Double(face.browCenter.x - face.eyeCenter.x), Double(face.browCenter.y - face.eyeCenter.y)) / io
        let brow = min(0.9, max(0.15, -b.x * s + b.y * c))
        let drop = min(1.45, max(0.7, -Double(mouth.y) - 0.2 * face.mouthOpen))
        let half = min(1.45, max(0.85, Double(face.rect.width) / io / 2))
        guard started else {
            head = HeadwearHead(mouthDrop: drop, halfWidth: half, brow: brow - 0.28 * face.browRaise)
            started = true
            return
        }
        let k = 1 - exp(-dt / 0.8)
        if face.mouthOpen < 0.3 { head.mouthDrop += (drop - head.mouthDrop) * k }
        head.halfWidth += (half - head.halfWidth) * k
        // The brows at rest: a raise doesn't count.
        let rest = brow - 0.28 * face.browRaise
        head.brow += (rest - head.brow) * (1 - exp(-dt / (rest < head.brow ? 0.3 : 1.5)))
    }
}

// MARK: - Frame and costume

/// Everything a costume knows about the head this frame. Lengths are in eye-spacings, drawn from the point between the eyes.
struct HeadwearFrame {
    let face: FaceState
    let center: CGPoint
    /// The eye spacing in output pixels.
    let io: Double
    let roll: Double
    /// Where the mouth is, in face units.
    let mouth: CGPoint
    /// How wide the mouth is, in face units.
    let mouthWidth: Double
    let signals: HeadwearSignals
    /// Head acceleration along the face's axes, in eye-spacings per second squared.
    let accel: SIMD2<Double>
    /// Seconds on a steady clock, for things that idle.
    let clock: Double
    /// Seconds since this face appeared (restarted when it comes back after a while away).
    let seen: Double
    let dt: Double
    /// The picture this is drawn on, in output pixels.
    let bounds: CGRect
    /// The shape of this head.
    let head: HeadwearHead

    init(face: FaceState, signals: HeadwearSignals, motion: HeadwearMotion, clock: Double, seen: Double, dt: Double, bounds: CGRect,
         head: HeadwearHead? = nil) {
        self.face = face
        center = face.eyeCenter
        io = max(face.interocular, 1)
        roll = face.roll
        mouth = Self.local(face.mouth, of: face)
        mouthWidth = max(0.35, face.mouthWidth / io)
        self.signals = signals
        accel = motion.local(roll: face.roll)
        self.clock = clock
        self.seen = seen
        self.dt = dt
        self.bounds = bounds
        self.head = head ?? HeadwearHead()
    }

    /// A point in output pixels, in this face's units.
    static func local(_ p: CGPoint, of face: FaceState) -> CGPoint {
        let io = max(face.interocular, 1)
        let d = SIMD2(Double(p.x - face.eyeCenter.x), Double(p.y - face.eyeCenter.y)) / io
        let c = cos(face.roll), s = sin(face.roll)
        return CGPoint(x: d.x * c + d.y * s, y: -d.x * s + d.y * c)
    }

    /// A point in output pixels, in face units.
    func local(_ p: CGPoint) -> CGPoint { Self.local(p, of: face) }

    /// The tip of the chin, a little below the mouth.
    var chinY: Double { mouth.y - 0.72 }
    /// The lip line on the top of the mouth, which rises as it opens.
    var upperLipY: Double { mouth.y + 0.04 + 0.27 * face.mouthOpen }
    var lowerLipY: Double { mouth.y - 0.04 - 0.27 * face.mouthOpen }
    /// The tip of the nose.
    var nose: CGPoint { CGPoint(x: mouth.x * 0.62, y: mouth.y * 0.62) }
    /// Which way a hanging thing leans because of gravity when the head is tilted, as an angle across the face.
    var hang: Double { -max(-1.1, min(1.1, roll)) }

    /// Draws in face units: the origin is between the eyes, x along the eyes, y up the face, 1 is the eye spacing.
    func inFace(_ ctx: CGContext, _ draw: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: CGFloat(roll))
        ctx.scaleBy(x: CGFloat(io), y: CGFloat(io))
        draw()
        ctx.restoreGState()
    }

    /// A point in face units, in output pixels.
    func toScreen(_ p: CGPoint) -> CGPoint {
        let c = cos(roll), s = sin(roll)
        return CGPoint(x: center.x + (p.x * c - p.y * s) * io, y: center.y + (p.x * s + p.y * c) * io)
    }
}

/// One costume: it keeps its own springs and states, and paints itself in face units.
protocol HeadwearCostume: AnyObject {
    /// What to tell the user to do.
    var hint: String { get }
    /// Whether it also has something to paint behind the person (wings, say).
    var hasBackLayer: Bool { get }
    /// Forget everything: a new person is in front of the camera.
    func reset()
    /// Moves the springs and animations on by one frame.
    func advance(_ frame: HeadwearFrame)
    /// Paints behind the person, in output pixels. `behindPerson` is false when there is no cutout to put the person in front of
    /// it, and the picture is drawn over them instead: skip anything that would cover the face.
    func drawBack(_ pen: HeadwearPen, _ frame: HeadwearFrame, behindPerson: Bool)
    /// Paints in front of everything, in output pixels. Use `frame.inFace` to paint in face units.
    func draw(_ pen: HeadwearPen, _ frame: HeadwearFrame)
}

extension HeadwearCostume {
    var hasBackLayer: Bool { false }
    func drawBack(_ pen: HeadwearPen, _ frame: HeadwearFrame, behindPerson: Bool) {}
}

// MARK: - Rig

/// Turns a stream of faces into steady frames for a costume: eases the expressions, tracks the head's motion, and keeps time.
final class HeadwearRig {
    /// How long a face may be gone before the entrance plays again when it comes back.
    static let forgiveness = 0.6

    private(set) var signals = HeadwearSignals()
    private(set) var motion = HeadwearMotion()
    private(set) var clock = 0.0
    private(set) var seen = 0.0
    private var absent = 0.0
    private var reader = HeadwearHeadReader()

    /// The shape of the head being dressed.
    var head: HeadwearHead { reader.head }

    func reset() {
        signals = HeadwearSignals()
        motion.forget()
        reader.forget()
        seen = 0
        absent = 0
    }

    /// Whether the face has been gone long enough that the costume starts over when it returns.
    var hasForgotten: Bool { seen == 0 }

    /// The frame for this face, or nil when there is none.
    func update(_ face: FaceState?, dt rawDt: Double, bounds: CGRect = CGRect(x: 0, y: 0, width: 1280, height: 720)) -> HeadwearFrame? {
        let dt = min(0.1, max(0, rawDt))
        clock += dt
        guard let face else {
            absent += dt
            if absent > 0.15 { motion.forget() }
            if absent > Self.forgiveness { signals = HeadwearSignals(); seen = 0; reader.forget() }
            return nil
        }
        if absent > 0.15 { motion.forget() }
        absent = 0
        seen += dt
        signals.update(face, dt: dt)
        motion.update(face, dt: dt)
        reader.update(face, mouth: HeadwearFrame.local(face.mouth, of: face), dt: dt)
        return HeadwearFrame(face: face, signals: signals, motion: motion, clock: clock, seen: seen, dt: dt, bounds: bounds, head: reader.head)
    }
}
