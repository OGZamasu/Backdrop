import CoreGraphics
import Foundation

// The painting kit for the hand-drawn creatures. Every creature is drawn live as vector shapes (so it can bend any way and stay
// crisp at any size) in one house style: a base colour, a rim of light along the edges that face the sky, the scene's key light
// and shade laid over each part, and a thin edge in a darker tone of the part's own colour. The light always comes from the
// upper left of the picture, whichever way the creature faces.
//
// Measured on this machine: an opaque vector fill costs a few microseconds, a clipped copy of a ready-made picture costs about as
// much, but a gradient or a scaled or turned picture costs ten to a hundred times more. So the shading is done with small light
// pictures, painted once per size, copied unscaled at whole pixels through the shape of each part.

/// Soft light pictures, one for each size of part, painted once: the scene's light at the upper left fading to its shade at the
/// lower right.
final class SceneLightBox {
    private var cache: [Int: CGImage] = [:]
    private let highlight: UInt32
    private let shadow: UInt32
    private static let buckets: [Int] = [8, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96, 128, 160, 192, 256, 320, 384, 512]

    init(look: SceneLook) {
        highlight = ScenePaint.mixHex(look.warm, 0xFFFFFF, 0.5)
        shadow = look.dusk
    }

    private static func bucket(_ v: Double) -> Int { buckets.first { Double($0) >= v } ?? buckets[buckets.count - 1] }

    /// The light for a part that covers `size` pixels. A `dim` light is for dark fur and skin, where a bright sheen looks like plastic.
    func light(for size: CGSize, dim: Bool = false) -> CGImage? {
        let w = Self.bucket(Double(size.width)), h = Self.bucket(Double(size.height))
        let key = w << 16 | h | (dim ? 1 << 30 : 0)
        if let hit = cache[key] { return hit }
        let k = dim ? 0.45 : 1
        let image = ScenePaint.picture(width: w, height: h) { ctx in
            ctx.translateBy(x: CGFloat(w) * 0.5, y: CGFloat(h) * 0.5)
            ctx.scaleBy(x: CGFloat(w) * 0.5, y: CGFloat(h) * 0.5)
            let g = ScenePaint.gradient([(0, ScenePaint.color(highlight, 0.26 * k)), (0.32, ScenePaint.color(highlight, 0.07 * k)), (0.62, ScenePaint.color(shadow, 0)),
                                         (0.95, ScenePaint.color(shadow, 0.30)), (1.35, ScenePaint.color(shadow, 0.5))].map { ($0.0 / 1.35, $0.1) })
            let centre = CGPoint(x: -0.42, y: 0.46)
            ctx.drawRadialGradient(g, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 2.0, options: [.drawsAfterEndLocation])
        }
        if cache.count > 300 { cache.removeAll() }
        if let image { cache[key] = image }
        return image
    }
}

/// How one creature is painted at one moment: its colours pushed into the scene's air by how far away it is, and the tools to paint
/// its parts. The context it paints in is already in the creature's own units: 1 is its full height, it faces right, its feet (or
/// its middle) are at the origin.
final class SceneInk {
    let look: SceneLook
    let lights: SceneLightBox
    /// 0 close up, 1 in the far lane: far things take on the haze and lose contrast.
    private(set) var far = 0.0
    /// Pixels to one unit, for line widths that stay the same on the screen.
    private(set) var pixels = 100.0
    /// Draws with less detail: far away, or small.
    private(set) var rough = false
    /// See-through, for ghosts and jellies: colours are made lighter and the edges softer.
    var glass = 1.0

    init(look: SceneLook, lights: SceneLightBox) {
        self.look = look
        self.lights = lights
    }

    /// Gets ready for the next creature.
    func begin(_ ctx: CGContext, far: Double) {
        self.far = far
        let m = ctx.ctm
        pixels = max(1, Double(hypot(m.c, m.d)))
        rough = pixels < 70 || far > 0.6
        glass = 1
    }

    // MARK: Colour

    /// A colour as it looks here: far away it is darker in its shade and hazier.
    func hex(_ hex: UInt32) -> UInt32 {
        guard far > 0.01 else { return hex }
        return ScenePaint.mixHex(ScenePaint.mixHex(hex, look.dusk, far * look.duskAmount * 0.9), look.haze, far * look.hazeAmount)
    }

    func tone(_ hex: UInt32, _ alpha: Double = 1) -> CGColor { ScenePaint.color(self.hex(hex), alpha * glass) }

    /// A darker, cooler version of a colour, for the shaded side and the edge line.
    func dark(_ hex: UInt32, _ k: Double = 0.45) -> UInt32 { ScenePaint.mixHex(hex, ScenePaint.mixHex(look.dusk, 0x000000, 0.5), k) }

    /// A lighter, warmer version, for the lit edge.
    func lit(_ hex: UInt32, _ k: Double = 0.45) -> UInt32 { ScenePaint.mixHex(hex, ScenePaint.mixHex(look.warm, 0xFFFFFF, 0.45), k) }

    /// A length in pixels on the screen, in the creature's units.
    func px(_ pixels: Double) -> CGFloat { CGFloat(pixels / self.pixels) }

    /// A direction on the screen (pixels, y up) as a vector in the current drawing units.
    private func local(_ ctx: CGContext, dx: Double, dy: Double) -> CGPoint {
        let inv = ctx.ctm.inverted()
        let a = CGPoint.zero.applying(inv), b = CGPoint(x: dx, y: dy).applying(inv)
        return CGPoint(x: b.x - a.x, y: b.y - a.y)
    }

    // MARK: Painting parts

    /// A rounded part of a body: base colour, the sky's rim light along its upper left edges, key light and shade across it,
    /// and a thin darker edge. The workhorse of every creature.
    /// A rounded part of a body, the workhorse of every creature. A sliver of the part's own dark tone shows along its lower right
    /// edges (the side away from the light), a rim of the sky's light along its upper left, and the scene's key light and shade lie
    /// across it. Stroking an outline costs several fills, so the edge is a fill of the same shape nudged down and right.
    func volume(_ ctx: CGContext, _ path: CGPath, _ base: UInt32, rim: Double = 1, edge: Double = 1, light: Bool = true) {
        if edge > 0 {
            let e = (rough ? 1.1 : 1.5) * edge
            let shift = local(ctx, dx: e * 0.8, dy: -e)
            ctx.translateBy(x: shift.x, y: shift.y)
            ctx.addPath(path)
            ctx.translateBy(x: -shift.x, y: -shift.y)
            ctx.setFillColor(tone(dark(base, 0.62), 0.92))
            ctx.fillPath()
        }
        // Small parts (an ear, a nose, a toe) get no light picture and only a thin rim: at that size the shading would not show.
        let size = rough ? 0 : Double(max(path.boundingBoxOfPath.width, path.boundingBoxOfPath.height)) * pixels
        let light = light && size > 26
        let rimWidth = rough || size < 10 ? 0 : 2.6 * rim * (1 - far * 0.6) * min(1, size / 40)
        if rimWidth > 0.4 {
            ctx.addPath(path)
            ctx.setFillColor(tone(lit(base, 0.55)))
            ctx.fillPath()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let shift = local(ctx, dx: rimWidth * 0.75, dy: -rimWidth)
            ctx.translateBy(x: shift.x, y: shift.y)
            ctx.addPath(path)
            ctx.translateBy(x: -shift.x, y: -shift.y)
            ctx.setFillColor(tone(base))
            ctx.fillPath()
            if light { shine(ctx, path, dim: Self.isDark(base)) }
            ctx.restoreGState()
        } else {
            ctx.addPath(path)
            ctx.setFillColor(tone(base))
            ctx.fillPath()
            if light, !rough {
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                shine(ctx, path, dim: Self.isDark(base))
                ctx.restoreGState()
            }
        }
    }

    /// The light picture laid over a part, copied at whole pixels. The context must already be clipped to the part.
    private static func isDark(_ hex: UInt32) -> Bool {
        let r = Double((hex >> 16) & 255), g = Double((hex >> 8) & 255), b = Double(hex & 255)
        return 0.3 * r + 0.59 * g + 0.11 * b < 80
    }

    private func shine(_ ctx: CGContext, _ path: CGPath, dim: Bool) {
        let box = path.boundingBoxOfPath.applying(ctx.ctm)
        guard box.width >= 3, box.height >= 3, let image = lights.light(for: box.size, dim: dim) else { return }
        ctx.saveGState()
        ctx.concatenate(ctx.ctm.inverted())
        let w = CGFloat(image.width), h = CGFloat(image.height)
        ctx.draw(image, in: CGRect(x: (box.midX - w / 2).rounded(), y: (box.midY - h / 2).rounded(), width: w, height: h))
        ctx.restoreGState()
    }

    /// A part in plain colour, no light: small things, things in shadow.
    func flat(_ ctx: CGContext, _ path: CGPath, _ base: UInt32, alpha: Double = 1) {
        ctx.addPath(path)
        ctx.setFillColor(tone(base, alpha))
        ctx.fillPath()
    }

    /// The thin edge round a part, in a dark tone of its own colour.
    func outline(_ ctx: CGContext, _ path: CGPath, _ base: UInt32, width: Double = 1) {
        ctx.addPath(path)
        ctx.setStrokeColor(tone(dark(base, 0.62), 0.9))
        ctx.setLineWidth(px((rough ? 1.1 : 1.6) * width))
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    /// A line in a colour, `width` in units.
    func line(_ ctx: CGContext, _ path: CGPath, _ hex: UInt32, width: Double, alpha: Double = 1, cap: CGLineCap = .round) {
        ctx.addPath(path)
        ctx.setStrokeColor(tone(hex, alpha))
        ctx.setLineWidth(CGFloat(width))
        ctx.setLineCap(cap)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    /// Several lines in one colour, stroked together: one stroke of many lines costs about the same as one line.
    func lines(_ ctx: CGContext, _ polylines: [[CGPoint]], _ hex: UInt32, width: Double, alpha: Double = 1) {
        let path = CGMutablePath()
        for points in polylines where points.count > 1 {
            if points.count == 2 {
                path.move(to: points[0])
                path.addLine(to: points[1])
            } else {
                path.addPath(SceneShape.curve(points))
            }
        }
        line(ctx, path, hex, width: width, alpha: alpha)
    }

    /// Marks inside a part (stripes, spots, scales): `marks` is drawn clipped to `path`.
    func inside(_ ctx: CGContext, _ path: CGPath, _ marks: () -> Void) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        marks()
        ctx.restoreGState()
    }

    /// A glint of light where the sky catches a wet or shiny part (an eye, a nose, a beak): always up and to the left on the screen.
    func glint(_ ctx: CGContext, at p: CGPoint, r: Double, alpha: Double = 0.95) {
        let d = local(ctx, dx: -1, dy: 1)
        let len = max(1e-6, hypot(d.x, d.y))
        let c = CGPoint(x: p.x + d.x / len * r * 0.45, y: p.y + d.y / len * r * 0.45)
        ctx.setFillColor(CGColor(gray: 1, alpha: CGFloat(alpha * (1 - far * 0.5) * glass)))
        ctx.fillEllipse(in: CGRect(x: c.x - r * 0.32, y: c.y - r * 0.32, width: r * 0.64, height: r * 0.64))
    }

    /// An eye: a dark rim, a coloured iris, a pupil, a glint, and a lid that closes for a blink.
    func eye(_ ctx: CGContext, at p: CGPoint, r: Double, iris: UInt32, skin: UInt32, blink: Double = 0, pupil: Double = 0.55, slit: Bool = false,
             white: Bool = false, look: CGPoint = .zero) {
        let rim = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        if r * pixels < 3 {
            // Too small to show more than a bright dot with a dark middle.
            ctx.setFillColor(tone(white ? 0xF4F0E6 : iris))
            ctx.fillEllipse(in: rim.insetBy(dx: -r * 0.1, dy: -r * 0.1))
            ctx.setFillColor(tone(0x080606))
            ctx.fillEllipse(in: rim.insetBy(dx: r * 0.4, dy: r * 0.4))
            return
        }
        ctx.setFillColor(tone(0x1A120E))
        ctx.fillEllipse(in: rim.insetBy(dx: -r * 0.18, dy: -r * 0.18))
        if white {
            ctx.setFillColor(tone(0xF4F0E6))
            ctx.fillEllipse(in: rim)
        }
        let ir = white ? r * 0.62 : r
        let ic = CGPoint(x: p.x + look.x * r * 0.3, y: p.y + look.y * r * 0.25)
        ctx.setFillColor(tone(iris))
        ctx.fillEllipse(in: CGRect(x: ic.x - ir, y: ic.y - ir, width: ir * 2, height: ir * 2))
        if !rough {
            // A darker ring at the top of the iris, in the shadow of the brow.
            ctx.setFillColor(tone(dark(iris, 0.5), 0.6))
            ctx.fillEllipse(in: CGRect(x: ic.x - ir, y: ic.y, width: ir * 2, height: ir))
            ctx.setFillColor(tone(iris))
            ctx.fillEllipse(in: CGRect(x: ic.x - ir * 0.8, y: ic.y - ir * 0.8, width: ir * 1.6, height: ir * 1.35))
        }
        ctx.setFillColor(tone(0x080606))
        if slit {
            ctx.fillEllipse(in: CGRect(x: ic.x - ir * 0.16, y: ic.y - ir * 0.8, width: ir * 0.32, height: ir * 1.6))
        } else {
            ctx.fillEllipse(in: CGRect(x: ic.x - ir * pupil, y: ic.y - ir * pupil, width: ir * pupil * 2, height: ir * pupil * 2))
        }
        glint(ctx, at: ic, r: ir)
        if blink > 0.02 {
            // The lid comes down from the top.
            let lid = CGMutablePath()
            let top = p.y + r * 1.25, bottom = p.y + r * 1.25 - r * 2.5 * min(1, blink)
            lid.addRect(CGRect(x: p.x - r * 1.3, y: bottom, width: r * 2.6, height: top - bottom))
            ctx.saveGState()
            ctx.addEllipse(in: rim.insetBy(dx: -r * 0.2, dy: -r * 0.2))
            ctx.clip()
            ctx.addPath(lid)
            ctx.setFillColor(tone(skin))
            ctx.fillPath()
            ctx.setStrokeColor(tone(dark(skin, 0.6)))
            ctx.setLineWidth(px(1.4))
            ctx.move(to: CGPoint(x: p.x - r * 1.2, y: bottom))
            ctx.addLine(to: CGPoint(x: p.x + r * 1.2, y: bottom))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Fur, feathers or grass along an edge: short strokes, for texture.
    func tufts(_ ctx: CGContext, along points: [CGPoint], length: Double, angle: Double, hex: UInt32, width: Double, alpha: Double = 0.6, seed: Double = 0) {
        guard !rough else { return }
        ctx.setStrokeColor(tone(hex, alpha))
        ctx.setLineWidth(CGFloat(width))
        ctx.setLineCap(.round)
        for (i, p) in points.enumerated() {
            let a = angle + (ScenePaint.noise(Double(i) * 1.7, seed) - 0.5) * 0.7
            let l = length * (0.6 + 0.6 * ScenePaint.noise(Double(i) * 2.3, seed + 3))
            ctx.move(to: p)
            ctx.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l))
        }
        ctx.strokePath()
    }
}

// MARK: - Shapes

/// Path builders for organic shapes.
enum SceneShape {
    /// A smooth closed shape through `points` (a Catmull-Rom spline), for bodies and heads.
    static func blob(_ points: [CGPoint], tension: Double = 1) -> CGPath {
        let path = CGMutablePath()
        let n = points.count
        guard n > 2 else { return path }
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            let k = CGFloat(tension / 6)
            path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) * k, y: p1.y + (p2.y - p0.y) * k),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) * k, y: p2.y - (p3.y - p1.y) * k))
        }
        path.closeSubpath()
        return path
    }

    /// A smooth open line through `points`.
    static func curve(_ points: [CGPoint], tension: Double = 1) -> CGPath {
        let path = CGMutablePath()
        let n = points.count
        guard n > 1 else { return path }
        path.move(to: points[0])
        for i in 0..<(n - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(n - 1, i + 2)]
            let k = CGFloat(tension / 6)
            path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) * k, y: p1.y + (p2.y - p0.y) * k),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) * k, y: p2.y - (p3.y - p1.y) * k))
        }
        return path
    }

    /// A tube along a line of points, `radii` thick at each (a tail, a neck, a trunk, a snake), rounded at both ends.
    static func tube(_ spine: [CGPoint], _ radii: [Double]) -> CGPath {
        let n = spine.count
        guard n > 1, radii.count == n else { return CGMutablePath() }
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0..<n {
            let a = spine[max(0, i - 1)], b = spine[min(n - 1, i + 1)]
            var dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let len = max(1e-9, hypot(dx, dy))
            dx /= len; dy /= len
            let r = radii[i]
            left.append(CGPoint(x: Double(spine[i].x) - dy * r, y: Double(spine[i].y) + dx * r))
            right.append(CGPoint(x: Double(spine[i].x) + dy * r, y: Double(spine[i].y) - dx * r))
        }
        // Round caps: a point beyond each end.
        func cap(_ i: Int, _ j: Int) -> CGPoint {
            let dx = Double(spine[i].x - spine[j].x), dy = Double(spine[i].y - spine[j].y)
            let len = max(1e-9, hypot(dx, dy))
            return CGPoint(x: Double(spine[i].x) + dx / len * radii[i] * 0.9, y: Double(spine[i].y) + dy / len * radii[i] * 0.9)
        }
        return blob(left + [cap(n - 1, n - 2)] + right.reversed() + [cap(0, 1)], tension: 0.9)
    }

    /// A tapered limb from `a` (radius `ra`) to `b` (radius `rb`), with round ends.
    static func limb(_ a: CGPoint, _ b: CGPoint, _ ra: Double, _ rb: Double) -> CGPath {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let len = max(1e-9, hypot(dx, dy))
        let angle = atan2(dy, dx)
        let path = CGMutablePath()
        // Tangent lines between two circles.
        let s = max(-1, min(1, (ra - rb) / len))
        let phi = acos(s)
        path.addArc(center: a, radius: CGFloat(ra), startAngle: CGFloat(angle + phi), endAngle: CGFloat(angle - phi + 2 * .pi), clockwise: false)
        path.addArc(center: b, radius: CGFloat(rb), startAngle: CGFloat(angle - phi), endAngle: CGFloat(angle + phi), clockwise: false)
        path.closeSubpath()
        return path
    }

    static func ellipse(_ c: CGPoint, _ rx: Double, _ ry: Double) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    /// Points around an ellipse, pushed in and out by `bumps`, for manes, clouds of fur and leafy masses.
    static func shaggy(_ c: CGPoint, rx: Double, ry: Double, count: Int, depth: Double, seed: Double, start: Double = 0, sweep: Double = 2 * .pi) -> [CGPoint] {
        (0..<count).map { i in
            let jitter = (ScenePaint.noise(Double(i) * 2.9, seed + 5) - 0.5) * 0.6
            let a = start + sweep * (Double(i) + jitter * (i % 2 == 0 ? 1 : 0.3)) / Double(count)
            let tip = 1 + 0.16 * (ScenePaint.noise(Double(i) * 1.7, seed + 9) - 0.5)
            let k = i % 2 == 0 ? tip : 1 - depth * (0.55 + 0.7 * ScenePaint.noise(Double(i) * 1.3, seed))
            return CGPoint(x: Double(c.x) + cos(a) * rx * k, y: Double(c.y) + sin(a) * ry * k)
        }
    }

    /// A fluffy outline: rounded lumps all round an ellipse, like a mane, a cloud or a bush. `twist` sweeps each lump round a little,
    /// like combed fur.
    static func scallop(_ c: CGPoint, rx: Double, ry: Double, count: Int, depth: Double = 0.14, seed: Double, twist: Double = 0, start: Double = 0) -> CGPath {
        let path = CGMutablePath()
        let n = max(3, count)
        func valley(_ i: Int) -> CGPoint {
            let a = start + 2 * .pi * (Double(i) + (ScenePaint.noise(Double(i % n) * 2.3, seed) - 0.5) * 0.35) / Double(n)
            let k = 1 - depth * (0.8 + 0.5 * ScenePaint.noise(Double(i % n) * 1.9, seed + 4))
            return CGPoint(x: Double(c.x) + cos(a) * rx * k, y: Double(c.y) + sin(a) * ry * k)
        }
        path.move(to: valley(0))
        for i in 0..<n {
            let a = start + 2 * .pi * (Double(i) + 0.5 + twist) / Double(n)
            let peak = 1 + depth * (0.6 + 0.7 * ScenePaint.noise(Double(i) * 3.1, seed + 8))
            path.addQuadCurve(to: valley(i + 1), control: CGPoint(x: Double(c.x) + cos(a) * rx * peak, y: Double(c.y) + sin(a) * ry * peak))
        }
        path.closeSubpath()
        return path
    }

    /// The same points turned about `pivot` by `angle` radians.
    static func turned(_ points: [CGPoint], about pivot: CGPoint, by angle: Double) -> [CGPoint] {
        let c = cos(angle), s = sin(angle)
        return points.map { p in
            let x = Double(p.x - pivot.x), y = Double(p.y - pivot.y)
            return CGPoint(x: Double(pivot.x) + x * c - y * s, y: Double(pivot.y) + x * s + y * c)
        }
    }
}

extension CGPoint {
    /// This point turned about `pivot` by `angle` radians.
    func sceneTurned(about pivot: CGPoint, by angle: Double) -> CGPoint {
        let c = cos(angle), s = sin(angle)
        let x = Double(self.x - pivot.x), y = Double(self.y - pivot.y)
        return CGPoint(x: Double(pivot.x) + x * c - y * s, y: Double(pivot.y) + x * s + y * c)
    }

    func sceneMoved(_ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: Double(x) + dx, y: Double(y) + dy) }
}
