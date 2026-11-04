import CoreGraphics
import Foundation
import simd

// Tools shared by the face half of the Dragon Ball lens (`SaiyanFace`, `SaiyanHair`, `SaiyanEyes`): the colours of a form's hair, a lock
// of hair shaped like a blade and painted once with cel shading, rim light and lit tips, the pictures those paintings are kept in, soft
// masks for covering the real eyebrows, and the springs and noise that keep it all alive. Lengths are in face units (see
// `HeadwearFrame`): the eye spacing is 1, the origin is between the eyes, y runs up the face.

enum SaiyanFaceKit {
    /// A palette colour as a pen colour.
    static func colour(_ c: SIMD3<Double>, _ alpha: Double = 1) -> HeadwearColor { HeadwearColor(c.x, c.y, c.z, alpha) }

    /// The key light, from above and to the left of the picture. Every lock is shaded for it, so the hair reads as one lit shape.
    static let light = CGVector(dx: -0.55, dy: 0.835)

    /// A damped spring let go from 0 toward 1, `seconds` later: it shoots past 1 once (by about 15% at the usual damping) and settles.
    static func spring(_ seconds: Double, omega: Double = 13, damping: Double = 0.52) -> Double {
        guard seconds > 0 else { return 0 }
        let d = min(0.95, max(0.05, damping)), wd = omega * sqrt(1 - d * d)
        return 1 - exp(-d * omega * seconds) * (cos(wd * seconds) + d * omega / wd * sin(wd * seconds))
    }

    /// Smooth noise in -1...1 that is the same for the same seed: two sines at unrelated rates. Enough for a flicker or a tremble.
    static func wobble(_ t: Double, _ seed: Int) -> Double {
        let a = 0.8 + 0.5 * HeadwearNoise.unit(seed, 31), b = 1.9 + 0.7 * HeadwearNoise.unit(seed, 32)
        let pa = HeadwearNoise.unit(seed, 33) * 6.283, pb = HeadwearNoise.unit(seed, 34) * 6.283
        return 0.62 * sin(t * a + pa) + 0.38 * sin(t * b + pb)
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    // MARK: Curves

    /// A smooth open curve through the points (Catmull-Rom as Béziers), from the path's current point, which must be `points[0]`.
    static func addCurve(through points: [CGPoint], to path: CGMutablePath) {
        let n = points.count
        guard n >= 2 else { return }
        func at(_ i: Int) -> CGPoint { points[min(max(i, 0), n - 1)] }
        for i in 0..<(n - 1) {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
    }

    static func openCurve(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        addCurve(through: points, to: path)
        return path
    }

    /// A blade along a centre line: two smooth edges that meet in a sharp tip, closed straight across the root.
    struct Blade {
        let path: CGPath
        let spine: [CGPoint]
        let left: [CGPoint]
        let right: [CGPoint]
        /// The left-hand normal of the centre line at each point.
        let normals: [CGVector]
        let widths: [Double]

        /// A point `offset` half-widths to the left of the centre line at point `i` (negative is to the right).
        func across(_ i: Int, _ offset: Double) -> CGPoint {
            CGPoint(x: spine[i].x + normals[i].dx * widths[i] * offset, y: spine[i].y + normals[i].dy * widths[i] * offset)
        }

        /// The fraction of the way along at point `i`.
        func t(_ i: Int) -> Double { Double(i) / Double(max(1, spine.count - 1)) }

        /// A strip between two lines across the blade, `outer(t)` and `inner(t)` in half-widths, from `t0` to the tip end `t1`.
        func band(from t0: Double, to t1: Double, outer: (Double) -> Double, inner: (Double) -> Double) -> CGPath {
            let n = spine.count
            let i0 = max(0, min(n - 2, Int((t0 * Double(n - 1)).rounded(.down))))
            let i1 = max(i0 + 1, min(n - 1, Int((t1 * Double(n - 1)).rounded(.up))))
            let a = (i0...i1).map { across($0, outer(t($0))) }
            let b = (i0...i1).reversed().map { across($0, inner(t($0))) }
            let path = CGMutablePath()
            path.move(to: a[0])
            SaiyanFaceKit.addCurve(through: a, to: path)
            path.addLine(to: b[0])
            SaiyanFaceKit.addCurve(through: b, to: path)
            path.closeSubpath()
            return path
        }

        /// One edge (+1 the left, -1 the right) from `t0` to the tip.
        func edge(_ side: Double, from t0: Double) -> [CGPoint] {
            let i0 = max(0, min(spine.count - 2, Int(t0 * Double(spine.count - 1))))
            return Array((side > 0 ? left : right)[i0...])
        }
    }

    static func blade(_ spine: [CGPoint], heel: Double = 1.6, width: (Double) -> Double) -> Blade {
        let n = spine.count
        var left: [CGPoint] = [], right: [CGPoint] = [], normals: [CGVector] = [], widths: [Double] = []
        for i in 0..<n {
            let a = spine[max(0, i - 1)], b = spine[min(n - 1, i + 1)]
            let len = max(hypot(b.x - a.x, b.y - a.y), 1e-9)
            let nx = -(b.y - a.y) / len, ny = (b.x - a.x) / len
            let w = max(0, width(Double(i) / Double(max(1, n - 1))))
            normals.append(CGVector(dx: nx, dy: ny))
            widths.append(w)
            left.append(CGPoint(x: spine[i].x + nx * w, y: spine[i].y + ny * w))
            right.append(CGPoint(x: spine[i].x - nx * w, y: spine[i].y - ny * w))
        }
        let path = CGMutablePath()
        path.move(to: left[0])
        addCurve(through: left, to: path)
        path.addLine(to: right[n - 1])
        addCurve(through: Array(right.reversed()), to: path)
        // A rounded heel at the root, so where a root shows it reads as a lock tucked under the others rather than a cut.
        let back = CGVector(dx: normals[0].dy, dy: -normals[0].dx)
        path.addQuadCurve(to: left[0], control: CGPoint(x: spine[0].x - back.dx * widths[0] * heel, y: spine[0].y - back.dy * widths[0] * heel))
        path.closeSubpath()
        return Blade(path: path, spine: spine, left: left, right: right, normals: normals, widths: widths)
    }

    // MARK: Soft masks

    private static let maskLock = NSLock()
    private static var oval: CGImage?

    /// A grey oval, solid in the middle and fading over its outer 35%: filled through it, a shape gets a soft edge with no visible rim.
    private static func ovalMask() -> CGImage? {
        maskLock.lock(); defer { maskLock.unlock() }
        if let oval { return oval }
        let w = 96, h = 64
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue), let data = c.data else { return nil }
        let row = c.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: row * h)
        for y in 0..<h {
            for x in 0..<w {
                let u = (Double(x) + 0.5) / Double(w) * 2 - 1, v = (Double(y) + 0.5) / Double(h) * 2 - 1
                let r = sqrt(u * u + v * v)
                bytes[y * row + x] = UInt8(255 * HeadwearEase.smoothstep((1 - r) / 0.35))
            }
        }
        oval = c.makeImage()
        return oval
    }

    /// A soft-edged oval of colour, `turn` radians about its centre.
    static func softOval(_ ctx: CGContext, at c: CGPoint, rx: Double, ry: Double, turn: Double = 0, _ colour: HeadwearColor) {
        guard rx > 0, ry > 0, colour.a > 0.004, let mask = ovalMask() else { return }
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        if turn != 0 { ctx.rotate(by: CGFloat(turn)) }
        let box = CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)
        ctx.clip(to: box, mask: mask)
        ctx.setFillColor(colour.cg)
        ctx.fill(box)
        ctx.restoreGState()
    }
}

// MARK: - Colours

/// The colours one painting of the hair is made with, from a form's palette.
struct SaiyanInk: Equatable {
    /// Names the colours in the kept pictures.
    let id: String
    let shade: HeadwearColor
    let base: HeadwearColor
    let light: HeadwearColor
    /// The aura's light catching the edges.
    let rim: HeadwearColor
    /// The fine dark line round each lock.
    let line: HeadwearColor
    /// Ultra Instinct Sign: dark at the roots with silver streaks running to the tips.
    let streaked: Bool

    init(_ form: SaiyanForm) {
        let p = form.palette
        id = "\(form)"
        shade = SaiyanFaceKit.colour(p.hairShade)
        base = SaiyanFaceKit.colour(p.hairBase)
        light = SaiyanFaceKit.colour(p.hairHighlight)
        // Base hair has no aura behind it, so only a faint sheen on the edges.
        rim = light.mixed(with: SaiyanFaceKit.colour(p.auraCore), form.isBase ? 0.15 : 0.6)
        line = shade.darker(form.isBase ? 0.2 : 0.55)
        streaked = form == .ultraInstinctSign
    }

    private init(id: String, shade: HeadwearColor, base: HeadwearColor, light: HeadwearColor, rim: HeadwearColor, line: HeadwearColor) {
        self.id = id; self.shade = shade; self.base = base; self.light = light; self.rim = rim; self.line = line; streaked = false
    }

    /// The colour deep in the hair mass, in its own shadow: the mass is painted in it and every lock's root fades from it.
    static func massColour(_ ink: SaiyanInk) -> HeadwearColor {
        ink.streaked ? ink.shade.darker(0.15) : ink.base.mixed(with: ink.shade, 0.62)
    }

    /// The hair at the instant of a change: lit almost white from within, still tinted by the form.
    static func blaze(_ form: SaiyanForm) -> SaiyanInk {
        let hair = SaiyanInk(form)
        let core = SaiyanFaceKit.colour(form.palette.auraCore)
        return SaiyanInk(id: "blaze-\(form)", shade: hair.base.mixed(with: hair.light, 0.45), base: hair.light.mixed(with: core, 0.55),
                         light: .white, rim: .white, line: hair.base.mixed(with: hair.shade, 0.4))
    }
}

// MARK: - A lock of hair

/// One lock: a tapering blade along a curved centre line, rooted in the hair mass. Painted once per colour and kept (see `SaiyanSprites`),
/// then moved each frame by its own spring.
struct SaiyanLock {
    /// The order locks are drawn in: behind the mass, out of the crown, rising off the front of the head, and the fringe over it all.
    enum Tier: Int, CaseIterable { case back, crown, front, fringe }

    var tier: Tier
    /// Where it grows from, on the test head.
    var root: CGPoint
    /// Its direction at the root, radians counter-clockwise from +x (pi/2 is straight up).
    var heading: Double
    /// How far it turns by the tip.
    var bend: Double
    /// A sideways S along its length.
    var wave = 0.0
    var length: Double
    /// Half its width at the root.
    var width: Double
    /// How quickly it narrows to the tip: 1 is straight-sided, more is a finer point.
    var sharp = 1.0
    /// How much it swells a little way out from the root.
    var belly = 0.25
    /// Bangs and sideburns hang (and fall a little when the head tilts); spikes stand.
    var hangs = false
    /// 0 for a lock in the light, 1 for one deep in the shadow behind the others.
    var depth = 0.0
    var seed = 0

    // How it moves.
    /// Spring rate, radians a second: long locks swing slower.
    var omega = 9.0
    /// How readily it swings when the head moves.
    var sway = 1.0
    /// When it springs up in a change, as a fraction of the change.
    var delay = 0.0

    // Worked out once by `finished()`.
    private(set) var blade = SaiyanFaceKit.Blade(path: CGMutablePath(), spine: [], left: [], right: [], normals: [], widths: [])
    /// The box the painting fills, from the root, with room for its edges.
    private(set) var window = CGRect.zero
    /// The tip, from the root, at rest.
    private(set) var tip = CGPoint.zero
    /// Which way a swing moves the middle of the lock (across it, to the left).
    private(set) var across = CGVector(dx: -1, dy: 0)
    /// The direction from the root to the tip.
    private(set) var direction = CGVector(dx: 0, dy: 1)

    init(tier: Tier, root: CGPoint, heading: Double, bend: Double, length: Double, width: Double) {
        self.tier = tier; self.root = root; self.heading = heading; self.bend = bend; self.length = length; self.width = width
    }

    func angle(at t: Double) -> Double { heading + bend * pow(t, 1.3) + wave * sin(2 * .pi * t) }

    func halfWidth(_ t: Double) -> Double {
        let u = min(1, max(0, t))
        // Narrower at the heel, swelling a little way out, then tapering to the point.
        return width * pow(1 - u, sharp) * (1 + belly * 4 * u * (1 - u)) * (0.6 + 0.4 * HeadwearEase.smoothstep(u / 0.16))
    }

    /// The same lock with its shape and box worked out.
    func finished() -> SaiyanLock {
        var out = self
        let spine = HeadwearShape.spine(from: .zero, length: length, steps: 16, heading: angle)
        out.blade = SaiyanFaceKit.blade(spine, width: halfWidth)
        out.tip = spine[spine.count - 1]
        let box = out.blade.path.boundingBoxOfPath
        out.window = box.insetBy(dx: -0.06, dy: -0.06)
        out.across = out.blade.normals[out.blade.normals.count / 2]
        let len = max(hypot(out.tip.x, out.tip.y), 1e-9)
        out.direction = CGVector(dx: out.tip.x / len, dy: out.tip.y / len)
        return out
    }

    /// The same lock seen in a mirror, its seed changed so its wobble differs from its twin.
    func mirrored() -> SaiyanLock {
        var out = self
        out.root.x = -root.x
        out.heading = .pi - heading
        out.bend = -bend
        out.wave = -wave
        out.seed = seed + 101
        return out
    }

    /// Paints the lock at rest, its root at the origin: the hair's colour shaded from the root, a crisp shadow down the side away from
    /// the light, sharp highlights, a lit tip, the aura's light on its edges, and a fine dark line.
    func paint(_ pen: HeadwearPen, _ ink: SaiyanInk) {
        let b = blade
        guard b.spine.count > 2 else { return }
        let ctx = pen.ctx
        let len = max(hypot(tip.x, tip.y), 1e-6)
        let axis = CGVector(dx: tip.x / len, dy: tip.y / len)
        let lightSide = (across.dx * SaiyanFaceKit.light.dx + across.dy * SaiyanFaceKit.light.dy) >= 0
        let lit = lightSide ? 1.0 : -1.0
        let s = Double(seed)
        func along(_ f: Double) -> CGPoint { CGPoint(x: axis.dx * len * f, y: axis.dy * len * f) }

        ctx.saveGState()
        let body = ink.streaked ? [ink.shade.darker(0.3), ink.shade, ink.base, ink.base.mixed(with: ink.light, 0.55)]
                                : [ink.shade, ink.base, ink.base, ink.base.mixed(with: ink.light, 0.5)]
        pen.paint(b.path, body, direction: axis)
        pen.clipped(to: b.path) {
            // The shadow side, its edge drawn with a little waver like a brush.
            let shadow = b.band(from: 0, to: 1, outer: { _ in -lit * 1.3 }, inner: { t in lit * (0.12 + 0.1 * sin(t * 7.3 + s)) })
            pen.fill(shadow, ink.shade.faded(ink.streaked ? 0.85 : 0.72))
            if ink.streaked {
                // Silver streaks from the dark roots out to the tips.
                for (offset, t0, colour) in [(0.5 * lit, 0.22, ink.light.faded(0.9)), (-0.05 * lit, 0.38, ink.base.mixed(with: ink.light, 0.6).faded(0.75)),
                                             (-0.55 * lit, 0.45, ink.light.faded(0.55))] {
                    let streak = b.band(from: t0, to: 0.97, outer: { t in offset + 0.14 * sin(.pi * min(1, max(0, (t - t0) / (1 - t0)))) },
                                        inner: { t in offset - 0.14 * sin(.pi * min(1, max(0, (t - t0) / (1 - t0)))) })
                    pen.fill(streak, colour)
                }
            } else {
                // Two hard highlights on the lit side, the longer one down the body and a short one near the tip.
                let long = b.band(from: 0.12, to: 0.8, outer: { t in lit * (0.5 + 0.2 * sin(.pi * min(1, max(0, (t - 0.12) / 0.68)))) },
                                  inner: { t in lit * (0.5 - 0.2 * sin(.pi * min(1, max(0, (t - 0.12) / 0.68)))) })
                pen.fill(long, ink.light.faded(0.88))
                let short = b.band(from: 0.6, to: 0.93, outer: { t in lit * (0.3 + 0.13 * sin(.pi * min(1, max(0, (t - 0.6) / 0.33)))) },
                                   inner: { t in lit * (0.3 - 0.13 * sin(.pi * min(1, max(0, (t - 0.6) / 0.33)))) })
                pen.fill(short, ink.light.faded(0.7))
            }
            // At the root it takes on the shadowed colour of the mass it grows out of, so it rises from the hair with no seam; bright at the tip.
            let mass = SaiyanInk.massColour(ink)
            if let g = HeadwearPen.gradient([mass, mass.faded(0.75), mass.faded(0)], at: [0, 0.35, 1]) {
                ctx.drawLinearGradient(g, start: .zero, end: along(tier == .fringe ? 0.36 : 0.44), options: [.drawsBeforeStartLocation])
            }
            if let g = HeadwearPen.gradient([ink.light.faded(0), ink.light.faded(0.6)]) {
                ctx.drawLinearGradient(g, start: along(0.6), end: along(1), options: [.drawsAfterEndLocation])
            }
            if depth > 0.01 { pen.fill(b.path, ink.shade.darker(0.45).faded(0.55 * depth)) }
            // The aura behind lights both edges toward the tip, the lit one more.
            pen.stroke(SaiyanFaceKit.openCurve(b.edge(lit, from: 0.25)), ink.rim.faded(0.9 * (1 - 0.5 * depth)), width: 0.07)
            pen.stroke(SaiyanFaceKit.openCurve(b.edge(-lit, from: 0.42)), ink.rim.faded(0.55 * (1 - 0.6 * depth)), width: 0.05)
        }
        // The fine line runs down both sides to the tip, but not round the heel, which disappears into the hair.
        let outline = CGMutablePath()
        let heel = max(1, b.spine.count / 8)
        outline.move(to: b.left[heel])
        SaiyanFaceKit.addCurve(through: Array(b.left[heel...]), to: outline)
        outline.addLine(to: b.right[b.right.count - 1])
        SaiyanFaceKit.addCurve(through: Array(b.right[heel...].reversed()), to: outline)
        pen.stroke(outline, ink.line.faded(0.9), width: 0.024)
        ctx.restoreGState()
    }
}

// MARK: - Kept pictures

/// The face's paintings, kept: each lock and mass is painted once per colour and size, then only copied each frame. Unlike
/// `HeadwearSprites`, a picture can be asked for without making it (`peek`), so a frame can use what is ready and make the rest a few
/// at a time instead of stalling.
enum SaiyanSprites {
    /// How much memory the kept pictures may take before the oldest are let go.
    static let budget = 40 << 20

    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]
    private static var order: [String] = []
    private static var bytes = 0

    static func key(_ name: String, density: Double) -> String { "\(name)@\(Int(density.rounded()))" }

    /// The picture if it has been made.
    static func peek(_ name: String, density: Double) -> CGImage? {
        let k = key(name, density: density)
        lock.lock(); defer { lock.unlock() }
        return cache[k]
    }

    /// The picture of `window` (in units) painted by `paint` at `density` pixels to a unit, made now if it has not been.
    static func image(_ name: String, window: CGRect, density: Double, _ paint: (HeadwearPen) -> Void) -> CGImage? {
        if let hit = peek(name, density: density) { return hit }
        let width = Int(ceil(window.width * density)), height = Int(ceil(window.height * density))
        guard width > 0, height > 0, width * height <= 4_000_000,
              let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: Sprites.bitmapInfo)
        else { return nil }
        c.setAllowsAntialiasing(true)
        c.interpolationQuality = .high
        c.scaleBy(x: CGFloat(density), y: CGFloat(density))
        c.translateBy(x: -window.minX, y: -window.minY)
        paint(HeadwearPen(ctx: c))
        guard let made = c.makeImage() else { return nil }
        let k = key(name, density: density)
        lock.lock(); defer { lock.unlock() }
        if cache[k] == nil {
            cache[k] = made
            order.append(k)
            bytes += made.bytesPerRow * made.height
            while bytes > budget, order.count > 1 {
                let old = order.removeFirst()
                if let gone = cache.removeValue(forKey: old) { bytes -= gone.bytesPerRow * gone.height }
            }
        }
        return cache[k]
    }

    /// Forgets everything (tests use it to time a cold start).
    static func clear() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll(); order.removeAll(); bytes = 0
    }
}
