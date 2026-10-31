import AppKit
import CoreGraphics
import Foundation

// The painting kit of the Vista scenes. One house style for every creature: a gradient lit from the top left, a soft core shadow
// toward the bottom right, a thin rim of the scene's own light along the back edge, a touch of gloss and a fine outline a shade
// darker than the part itself. Everything heavy is drawn once into cached pictures; only the small, cheap parts (eyes, a mouth)
// are drawn per frame.

/// Three tones of one colour: lit, middle and in shade.
struct VistaTone {
    var light: UInt32
    var base: UInt32
    var dark: UInt32

    init(_ light: UInt32, _ base: UInt32, _ dark: UInt32) {
        self.light = light
        self.base = base
        self.dark = dark
    }
}

/// How a scene lights its creatures.
struct VistaInkStyle {
    /// The colour of the light behind everything (the aurora, the sunset), caught along the back edge of each part.
    var rim: UInt32
    var rimAmount = 0.7
    /// The outline, in pixels at full size, and how dark it is next to the part's own shade colour (0 none, 1 nearly black).
    var line = 2.0
    var ink = 0.45
    /// How much shine the top left of a part gets.
    var gloss = 0.22
}

/// A picture painted once, with the place in the frame where it goes.
struct VistaLayer {
    var image: CGImage
    /// Where its lower left corner sits in the frame.
    var origin: CGPoint
    /// How far it slides, in pixels, as the person moves from the middle to the edge of the picture.
    var parallax: Double

    func draw(in ctx: CGContext, shift: CGPoint, dx: Double = 0, dy: Double = 0) {
        ctx.draw(image, in: CGRect(x: (origin.x + shift.x * parallax + dx).rounded(), y: (origin.y + shift.y * parallax * 0.4 + dy).rounded(),
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
    }
}

/// A big picture painted over several frames, so that no one frame has to do it all: made, painted in pieces, then finished.
final class VistaPainting {
    private let ctx: CGContext
    private let rect: CGRect

    /// A canvas covering `rect` of the frame. An `opaque` one has no alpha, which is much faster to copy every frame.
    init?(_ rect: CGRect, opaque: Bool = true) {
        let info = opaque ? CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue : Sprites.bitmapInfo
        guard let ctx = CGContext(data: nil, width: Int(rect.width.rounded(.up)), height: Int(rect.height.rounded(.up)), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: VistaInk.space, bitmapInfo: info) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        self.ctx = ctx
        self.rect = rect
    }

    /// Paints more of it, in frame coordinates.
    func paint(_ draw: (CGContext) -> Void) {
        ctx.saveGState()
        draw(ctx)
        ctx.restoreGState()
    }

    func finish(parallax: Double) -> VistaLayer? {
        ctx.makeImage().map { VistaLayer(image: $0, origin: rect.origin, parallax: parallax) }
    }
}

/// A body part drawn once, at full size, with the point it turns about at its origin. Placed in a creature's own units
/// (its height is 1), so the same part serves at every distance.
struct VistaPart {
    let image: CGImage
    /// The rectangle it fills, in units, around its pivot.
    let rect: CGRect

    /// Paints a part. `box` is the area it covers in units, around the pivot at (0, 0); `u` is pixels to a unit.
    static func bake(u: Double, box: CGRect, _ draw: (CGContext) -> Void) -> VistaPart? {
        let pad = 3.0 / u
        let r = box.insetBy(dx: -pad, dy: -pad)
        let w = Int((r.width * u).rounded(.up)), h = Int((r.height * u).rounded(.up))
        guard let image = VistaInk.picture(width: w, height: h, { ctx in
            ctx.scaleBy(x: CGFloat(u), y: CGFloat(u))
            ctx.translateBy(x: -r.minX, y: -r.minY)
            draw(ctx)
        }) else { return nil }
        return VistaPart(image: image, rect: CGRect(x: r.minX, y: r.minY, width: Double(w) / u, height: Double(h) / u))
    }
}

extension VistaPart {
    /// The same part seen far off, through the air: washed with the colour of the haze. Made once, so that far creatures
    /// cost no more to draw than near ones.
    func hazed(_ haze: UInt32, _ amount: Double) -> VistaPart {
        guard let image = VistaInk.picture(width: image.width, height: image.height, { ctx in
            let rect = CGRect(x: 0, y: 0, width: self.image.width, height: self.image.height)
            ctx.draw(self.image, in: rect)
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(VistaInk.color(haze, amount))
            ctx.fill(rect)
        }) else { return self }
        return VistaPart(image: image, rect: rect)
    }
}

/// The parts of one kind of creature, as painted for close up and as seen far away.
struct VistaFigure {
    let near: [VistaPart?]
    let far: [VistaPart?]

    init(_ parts: [VistaPart?], haze: UInt32, amount: Double) {
        near = parts
        far = parts.map { $0?.hazed(haze, amount) }
    }

    /// The set to draw a creature with.
    func parts(for rig: VistaRig) -> [VistaPart?] { rig.hazed ? far : near }
}

extension VistaPart {
    /// Paints a part in the creature's own units, turning about `pivot`; `box` is the area it covers, in the same units.
    /// Placed at `pivot`, it lands exactly where it was painted.
    static func bake(u: Double, pivot: CGPoint, box: CGRect, _ draw: (CGContext) -> Void) -> VistaPart? {
        bake(u: u, box: box.offsetBy(dx: -pivot.x, dy: -pivot.y)) { ctx in
            ctx.translateBy(x: -pivot.x, y: -pivot.y)
            draw(ctx)
        }
    }
}

/// Turns a point about another, for parts that hang off parts.
func vistaTurn(_ p: CGPoint, about o: CGPoint, by angle: Double) -> CGPoint {
    let c = cos(angle), s = sin(angle)
    let dx = Double(p.x - o.x), dy = Double(p.y - o.y)
    return CGPoint(x: Double(o.x) + dx * c - dy * s, y: Double(o.y) + dx * s + dy * c)
}

extension CGContext {
    /// Draws a part with its pivot at `p`, turned by `angle` (radians, counter-clockwise) and scaled.
    func place(_ part: VistaPart?, at p: CGPoint, angle: Double = 0, sx: Double = 1, sy: Double = 1) {
        guard let part else { return }
        saveGState()
        translateBy(x: p.x, y: p.y)
        if angle != 0 { rotate(by: CGFloat(angle)) }
        if sx != 1 || sy != 1 { scaleBy(x: CGFloat(sx), y: CGFloat(sy)) }
        draw(part.image, in: part.rect)
        restoreGState()
    }

    /// Runs `body` with the origin moved to `p` and turned: for drawing eyes and mouths on a part that has been placed there.
    func local(at p: CGPoint, angle: Double = 0, sx: Double = 1, sy: Double = 1, _ body: () -> Void) {
        saveGState()
        translateBy(x: p.x, y: p.y)
        if angle != 0 { rotate(by: CGFloat(angle)) }
        if sx != 1 || sy != 1 { scaleBy(x: CGFloat(sx), y: CGFloat(sy)) }
        body()
        restoreGState()
    }
}

enum VistaInk {
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: Colour

    static func color(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, CGFloat(alpha)])!
    }

    /// The hex colour between two hex colours, 0 for `a` and 1 for `b`.
    static func mixHex(_ a: UInt32, _ b: UInt32, _ k: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 255), y = Double((b >> shift) & 255)
            return UInt32(max(0, min(255, (x + (y - x) * k).rounded())))
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ k: Double, alpha: Double = 1) -> CGColor { color(mixHex(a, b, k), alpha) }

    static func components(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255)
    }

    static func gradient(_ stops: [(Double, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map { CGFloat($0.0) })!
    }

    // MARK: Pictures

    /// A bitmap in the canvas's own pixel layout. An `opaque` one has no alpha at all, which Core Graphics copies much faster.
    static func picture(width: Int, height: Int, opaque: Bool = false, _ draw: (CGContext) -> Void) -> CGImage? {
        let info = opaque ? CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue : Sprites.bitmapInfo
        guard width > 0, height > 0, width < 4096, height < 4096,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
        else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()
    }

    /// A picture painted in frame coordinates: `rect` is the part of the frame it covers.
    static func layer(_ rect: CGRect, parallax: Double = 0, opaque: Bool = false, _ draw: (CGContext) -> Void) -> VistaLayer? {
        guard let image = picture(width: Int(rect.width.rounded(.up)), height: Int(rect.height.rounded(.up)), opaque: opaque, { ctx in
            ctx.translateBy(x: -rect.minX, y: -rect.minY)
            draw(ctx)
        }) else { return nil }
        return VistaLayer(image: image, origin: rect.origin, parallax: parallax)
    }

    // MARK: Fills

    /// Fills a rectangle with a gradient from `from` to `to`.
    static func fill(_ ctx: CGContext, _ rect: CGRect, _ stops: [(Double, CGColor)], from: CGPoint, to: CGPoint) {
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient(stops), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// Top-to-bottom gradient over a rectangle; stops run from the top (0) to the bottom (1).
    static func fillDown(_ ctx: CGContext, _ rect: CGRect, _ stops: [(Double, CGColor)]) {
        fill(ctx, rect, stops, from: CGPoint(x: 0, y: rect.maxY), to: CGPoint(x: 0, y: rect.minY))
    }

    /// Fills a path with a gradient running from `from` to `to`.
    static func fill(_ ctx: CGContext, _ path: CGPath, _ stops: [(Double, CGColor)], from: CGPoint, to: CGPoint) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(gradient(stops), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// A soft elliptical glow: `color` in the middle, fading to nothing at the edge.
    static func blob(_ ctx: CGContext, _ centre: CGPoint, rx: Double, ry: Double, _ color: CGColor, inner: Double = 0, alpha: Double = 1) {
        guard rx > 0.0001, ry > 0.0001 else { return }
        let c = color.components ?? [1, 1, 1, 1]
        let a = Double(c.count > 3 ? c[3] : 1) * alpha
        let solid = CGColor(colorSpace: space, components: [c[0], c[1], c[2], CGFloat(a)])!
        let clear = CGColor(colorSpace: space, components: [c[0], c[1], c[2], 0])!
        ctx.saveGState()
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.scaleBy(x: CGFloat(rx), y: CGFloat(ry))
        let g = gradient([(0, solid), (max(0.01, inner), solid), (1, clear)])
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        ctx.restoreGState()
    }

    static func oval(_ ctx: CGContext, _ centre: CGPoint, rx: Double, ry: Double, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: centre.x - rx, y: centre.y - ry, width: rx * 2, height: ry * 2))
    }

    // MARK: The house style

    /// Paints one part of a creature in the house style. `u` is pixels to a unit (shadows are measured in pixels).
    static func shade(_ ctx: CGContext, _ path: CGPath, _ tone: VistaTone, _ style: VistaInkStyle, u: Double,
                      rim: Double = 1, gloss: Double? = nil, core: Double = 1, line: Bool = true) {
        let box = path.boundingBox
        guard box.width > 0, box.height > 0 else { return }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        // The body: lit from the top left.
        ctx.drawLinearGradient(gradient([(0, color(tone.light)), (0.48, color(tone.base)), (1, color(tone.dark))]),
                               start: CGPoint(x: box.minX + box.width * 0.22, y: box.maxY), end: CGPoint(x: box.maxX - box.width * 0.18, y: box.minY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // The core shadow: a soft darkening inside the lower right edge.
        if core > 0 {
            let reach = max(2, min(box.width, box.height) * u * 0.16)
            let far = box.insetBy(dx: -box.width - 1, dy: -box.height - 1)
            ctx.setShadow(offset: CGSize(width: -reach * 0.55, height: reach * 0.65), blur: reach * 1.3, color: color(mixHex(tone.dark, 0x000000, 0.35), 0.55 * core))
            ctx.addRect(far)
            ctx.addPath(path)
            ctx.setFillColor(color(tone.dark))
            ctx.fillPath(using: .evenOdd)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
        // The rim: the scene's light catching the back edge.
        if rim > 0, style.rimAmount > 0 {
            let r = max(1.6 / u, min(box.width, box.height) * 0.07)
            var shift = CGAffineTransform(translationX: -r, y: -r * 0.35)
            if let moved = path.copy(using: &shift) {
                ctx.addRect(box.insetBy(dx: -box.width - 1, dy: -box.height - 1))
                ctx.addPath(moved)
                ctx.setFillColor(color(style.rim, style.rimAmount * rim))
                ctx.fillPath(using: .evenOdd)
            }
        }
        // A little shine.
        let shine = gloss ?? style.gloss
        if shine > 0 {
            blob(ctx, CGPoint(x: box.minX + box.width * 0.34, y: box.maxY - box.height * 0.26), rx: box.width * 0.34, ry: box.height * 0.24,
                 color(0xFFFFFF, shine))
        }
        ctx.restoreGState()
        if line, style.line > 0 {
            ctx.addPath(path)
            ctx.setStrokeColor(color(mixHex(tone.dark, 0x0A0612, style.ink), 0.92))
            ctx.setLineWidth(CGFloat(style.line / u))
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
    }

    /// A flat patch of colour inside a part (a belly, a mask), soft at the edge, clipped to `clip`.
    static func patch(_ ctx: CGContext, clip: CGPath, _ path: CGPath, _ color: CGColor, soft: Double = 0, u: Double) {
        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()
        if soft > 0 { ctx.setShadow(offset: .zero, blur: CGFloat(soft * u), color: color) }
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// A stroke for fur, scales and stitches, clipped to `clip`.
    static func strokes(_ ctx: CGContext, clip: CGPath?, width: Double, _ color: CGColor, _ lines: [(CGPoint, CGPoint, CGPoint)]) {
        ctx.saveGState()
        if let clip { ctx.addPath(clip); ctx.clip() }
        ctx.setStrokeColor(color)
        ctx.setLineWidth(CGFloat(width))
        ctx.setLineCap(.round)
        for (a, control, b) in lines {
            ctx.move(to: a)
            ctx.addQuadCurve(to: b, control: control)
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Paths

    /// A smooth closed outline through the points (a Catmull-Rom curve), the way an illustrator would draw a body.
    static func smooth(_ points: [CGPoint], closed: Bool = true, tension: Double = 0.5) -> CGPath {
        let path = CGMutablePath()
        let n = points.count
        guard n > 2 else { return path }
        func p(_ i: Int) -> CGPoint { closed ? points[(i % n + n) % n] : points[max(0, min(n - 1, i))] }
        path.move(to: points[0])
        let last = closed ? n : n - 1
        let k = CGFloat(tension / 3 * 2)
        for i in 0..<last {
            let p0 = p(i - 1), p1 = p(i), p2 = p(i + 1), p3 = p(i + 2)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * k / 2, y: p1.y + (p2.y - p0.y) * k / 2)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * k / 2, y: p2.y - (p3.y - p1.y) * k / 2)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        if closed { path.closeSubpath() }
        return path
    }

    /// `smooth` with the points given as pairs of numbers.
    static func smooth(_ xy: [(Double, Double)], closed: Bool = true, tension: Double = 0.5) -> CGPath {
        smooth(xy.map { CGPoint(x: $0.0, y: $0.1) }, closed: closed, tension: tension)
    }

    static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> CGPath {
        CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    /// A limb: two circles and the skin stretched between them.
    static func capsule(_ a: CGPoint, _ b: CGPoint, _ ra: Double, _ rb: Double) -> CGPath {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let d = max(1e-6, hypot(dx, dy))
        let angle = atan2(dy, dx)
        let spread = acos(max(-1, min(1, (ra - rb) / d)))
        let path = CGMutablePath()
        path.addArc(center: a, radius: CGFloat(ra), startAngle: CGFloat(angle + spread), endAngle: CGFloat(angle + 2 * .pi - spread), clockwise: false)
        path.addArc(center: b, radius: CGFloat(rb), startAngle: CGFloat(angle - spread), endAngle: CGFloat(angle + spread), clockwise: false)
        path.closeSubpath()
        return path
    }

    static func capsule(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ ra: Double, _ rb: Double) -> CGPath {
        capsule(CGPoint(x: ax, y: ay), CGPoint(x: bx, y: by), ra, rb)
    }

    static func rounded(_ rect: CGRect, _ radius: Double) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: CGFloat(min(radius, Double(rect.width) / 2)), cornerHeight: CGFloat(min(radius, Double(rect.height) / 2)), transform: nil)
    }

    /// Several shapes as one outline (they must not cross, or the overlap is left out).
    static func union(_ paths: [CGPath]) -> CGPath {
        let path = CGMutablePath()
        for p in paths { path.addPath(p) }
        return path
    }

    /// A star with `points` tips.
    static func star(_ cx: Double, _ cy: Double, outer: Double, inner: Double, points: Int = 5, turn: Double = .pi / 2) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let a = turn + Double(i) * .pi / Double(points)
            let p = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: Noise and scenery

    /// Smooth one-dimensional noise, 0...1, the same for the same `x` and `seed`.
    static func noise(_ x: Double, _ seed: Double = 0) -> Double {
        func hash(_ n: Int) -> Double {
            var h = UInt64(bitPattern: Int64(n)) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(seed * 1000 + 7)
            h = (h ^ (h >> 30)) &* 0xBF58_476D_1CE4_E5B9
            h = (h ^ (h >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((h ^ (h >> 31)) % 10_000) / 10_000
        }
        let i = Int(floor(x)), f = x - floor(x)
        let s = f * f * (3 - 2 * f)
        return hash(i) * (1 - s) + hash(i + 1) * s
    }

    /// Layered noise: rolling hills.
    static func hills(_ x: Double, seed: Double, octaves: Int = 3) -> Double {
        var total = 0.0, amp = 1.0, norm = 0.0, f = 1.0
        for o in 0..<octaves {
            total += noise(x * f, seed + Double(o) * 11) * amp
            norm += amp
            amp *= 0.5
            f *= 2.1
        }
        return total / norm
    }

    /// The outline of a ridge line, closed along the bottom.
    static func ridge(left: Double, width: Double, base: Double, bottom: Double, amplitude: Double, wavelength: Double, seed: Double, step: Double = 8) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left, y: bottom))
        var x = left
        while x <= left + width + step {
            path.addLine(to: CGPoint(x: x, y: base + (hills((x - left) / wavelength, seed: seed) - 0.5) * 2 * amplitude))
            x += step
        }
        path.addLine(to: CGPoint(x: left + width + step, y: bottom))
        path.closeSubpath()
        return path
    }

    /// The height of `ridge` at `x`, for putting things on it.
    static func ridgeHeight(at x: Double, left: Double, base: Double, amplitude: Double, wavelength: Double, seed: Double) -> Double {
        base + (hills((x - left) / wavelength, seed: seed) - 0.5) * 2 * amplitude
    }

    static func generator(_ seed: UInt64) -> VistaRandom { VistaRandom(seed: seed) }

    /// A thin curved stroke: a blade of grass, a reed.
    static func blade(_ ctx: CGContext, at base: CGPoint, height: Double, lean: Double, width: Double, color: CGColor) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(CGFloat(width))
        ctx.setLineCap(.round)
        ctx.move(to: base)
        ctx.addQuadCurve(to: CGPoint(x: base.x + lean, y: base.y + height), control: CGPoint(x: base.x + lean * 0.1, y: base.y + height * 0.6))
        ctx.strokePath()
    }

    /// A soft cloud: a cluster of overlapping glows, lit along its top.
    static func cloud(_ ctx: CGContext, centre: CGPoint, width: Double, height: Double, body: UInt32, lit: UInt32, alpha: Double, seed: UInt64) {
        var rng = generator(seed)
        for _ in 0..<12 {
            let c = CGPoint(x: Double(centre.x) + rng.range(-0.38, 0.38) * width, y: Double(centre.y) + rng.range(-0.18, 0.2) * height)
            let rx = rng.range(0.14, 0.26) * width, ry = rng.range(0.3, 0.5) * height
            blob(ctx, c, rx: rx, ry: ry, color(body, alpha), inner: 0.35)
            blob(ctx, CGPoint(x: c.x - rx * 0.1, y: c.y + ry * 0.35), rx: rx * 0.7, ry: ry * 0.45, color(lit, alpha * 0.8), inner: 0.2)
        }
    }
}

// MARK: - Sprites drawn once and shared

/// Small pictures every scene uses: the soft shadow under a creature, twinkles, glows, coins, notes. Made once, on first use.
enum VistaSprites {
    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]

    private static func cached(_ key: String, _ make: () -> CGImage?) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        guard let image = make() else { return nil }
        if cache.count > 160 { cache.removeAll() }
        cache[key] = image
        return image
    }

    /// The shadow on the ground under a creature: dark in the middle, fading softly.
    static var shadow: CGImage? {
        cached("shadow") {
            VistaInk.picture(width: 128, height: 48) { ctx in
                VistaInk.blob(ctx, CGPoint(x: 64, y: 24), rx: 62, ry: 22, VistaInk.color(0x000000, 0.75), inner: 0.25)
            }
        }
    }

    /// A soft round glow in a colour.
    static func glow(_ hex: UInt32) -> CGImage? {
        cached("glow\(hex)") {
            VistaInk.picture(width: 96, height: 96) { ctx in
                VistaInk.blob(ctx, CGPoint(x: 48, y: 48), rx: 47, ry: 47, VistaInk.color(hex, 0.9), inner: 0.06)
                VistaInk.blob(ctx, CGPoint(x: 48, y: 48), rx: 16, ry: 16, VistaInk.color(VistaInk.mixHex(hex, 0xFFFFFF, 0.6), 0.9), inner: 0.2)
            }
        }
    }

    /// A four-pointed twinkle with a glow round it.
    static func twinkle(_ hex: UInt32) -> CGImage? {
        cached("twinkle\(hex)") {
            VistaInk.picture(width: 64, height: 64) { ctx in
                VistaInk.blob(ctx, CGPoint(x: 32, y: 32), rx: 20, ry: 20, VistaInk.color(hex, 0.45))
                let star = VistaInk.star(32, 32, outer: 30, inner: 4.2, points: 4)
                ctx.addPath(star)
                ctx.setFillColor(VistaInk.color(VistaInk.mixHex(hex, 0xFFFFFF, 0.55)))
                ctx.fillPath()
                VistaInk.oval(ctx, CGPoint(x: 32, y: 32), rx: 4.5, ry: 4.5, VistaInk.color(0xFFFFFF))
            }
        }
    }

    /// A gold coin, seen face on; drawn squashed sideways, it spins.
    static var coin: CGImage? {
        cached("coin") {
            VistaInk.picture(width: 48, height: 48) { ctx in
                VistaInk.oval(ctx, CGPoint(x: 24, y: 24), rx: 22, ry: 22, VistaInk.color(0x8A5A10))
                VistaInk.fill(ctx, VistaInk.ellipse(24, 25, 20, 20), [(0, VistaInk.color(0xFFF2A8)), (0.5, VistaInk.color(0xF4C23C)), (1, VistaInk.color(0xC08418))],
                              from: CGPoint(x: 12, y: 44), to: CGPoint(x: 36, y: 6))
                ctx.setStrokeColor(VistaInk.color(0xB07A14, 0.9)); ctx.setLineWidth(2.2)
                ctx.strokeEllipse(in: CGRect(x: 10, y: 11, width: 28, height: 28))
                VistaInk.blob(ctx, CGPoint(x: 17, y: 32), rx: 7, ry: 5, VistaInk.color(0xFFFFFF, 0.7))
            }
        }
    }

    /// A music note.
    static func note(_ hex: UInt32) -> CGImage? {
        cached("note\(hex)") {
            VistaInk.picture(width: 48, height: 64) { ctx in
                ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: VistaInk.color(0x000000, 0.35))
                ctx.setFillColor(VistaInk.color(hex))
                ctx.saveGState()
                ctx.translateBy(x: 16, y: 14); ctx.rotate(by: 0.35)
                ctx.fillEllipse(in: CGRect(x: -10, y: -7, width: 20, height: 14))
                ctx.restoreGState()
                ctx.fill(CGRect(x: 23, y: 15, width: 4.5, height: 40))
                let flag = CGMutablePath()
                flag.move(to: CGPoint(x: 23, y: 55)); flag.addCurve(to: CGPoint(x: 40, y: 36), control1: CGPoint(x: 34, y: 52), control2: CGPoint(x: 44, y: 46))
                flag.addCurve(to: CGPoint(x: 27, y: 44), control1: CGPoint(x: 36, y: 42), control2: CGPoint(x: 31, y: 44))
                flag.closeSubpath()
                ctx.addPath(flag); ctx.fillPath()
            }
        }
    }

    /// A heart.
    static func heart(_ hex: UInt32) -> CGImage? {
        cached("heart\(hex)") {
            VistaInk.picture(width: 48, height: 44) { ctx in
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 24, y: 4))
                p.addCurve(to: CGPoint(x: 4, y: 28), control1: CGPoint(x: 14, y: 12), control2: CGPoint(x: 4, y: 18))
                p.addCurve(to: CGPoint(x: 24, y: 32), control1: CGPoint(x: 4, y: 42), control2: CGPoint(x: 22, y: 44))
                p.addCurve(to: CGPoint(x: 44, y: 28), control1: CGPoint(x: 26, y: 44), control2: CGPoint(x: 44, y: 42))
                p.addCurve(to: CGPoint(x: 24, y: 4), control1: CGPoint(x: 44, y: 18), control2: CGPoint(x: 34, y: 12))
                VistaInk.fill(ctx, p, [(0, VistaInk.color(VistaInk.mixHex(hex, 0xFFFFFF, 0.4))), (1, VistaInk.color(VistaInk.mixHex(hex, 0x400010, 0.3)))],
                              from: CGPoint(x: 10, y: 40), to: CGPoint(x: 38, y: 6))
                VistaInk.blob(ctx, CGPoint(x: 15, y: 31), rx: 6, ry: 4, VistaInk.color(0xFFFFFF, 0.75))
            }
        }
    }
}

// MARK: - Speech bubbles

/// The speech bubbles: a soft white balloon with a coloured edge, the word set in a heavy rounded face. Drawn once per thing said.
enum VistaBubbleArt {
    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]

    static func font(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .heavy)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: size) ?? base
    }

    /// The bubble, with its pointer at the bottom middle. `accent` is the scene's colour for the edge.
    static func image(_ text: String, accent: UInt32) -> CGImage? {
        let key = "\(text)#\(accent)"
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let alarm = text.hasPrefix("!") || text.hasPrefix("?")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(alarm ? 40 : 30),
            .foregroundColor: alarm ? NSColor(srgbRed: 0.88, green: 0.30, blue: 0.22, alpha: 1) : NSColor(srgbRed: 0.16, green: 0.13, blue: 0.24, alpha: 1),
            .kern: alarm ? 0 : 0.6,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let box = string.size()
        let padX: CGFloat = alarm ? 16 : 20, padY: CGFloat = alarm ? 4 : 8, tail: CGFloat = 15, edge: CGFloat = 9
        let body = CGSize(width: max(box.width + padX * 2, 56), height: box.height + padY * 2)
        let width = Int(ceil(body.width + edge * 2)), height = Int(ceil(body.height + tail + edge * 2))
        let image = VistaInk.picture(width: width, height: height) { ctx in
            let rect = CGRect(x: edge, y: tail + edge, width: body.width, height: body.height)
            let radius = rect.height / 2
            let path = CGMutablePath()
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
            // The pointer: a soft rounded wedge under the middle.
            path.move(to: CGPoint(x: rect.midX - 12, y: rect.minY + 2))
            path.addQuadCurve(to: CGPoint(x: rect.midX - 2, y: edge + 1), control: CGPoint(x: rect.midX - 4, y: rect.minY - 4))
            path.addQuadCurve(to: CGPoint(x: rect.midX + 10, y: rect.minY + 2), control: CGPoint(x: rect.midX + 2, y: rect.minY - 2))
            path.closeSubpath()
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 7, color: VistaInk.color(0x0A0618, 0.4))
            ctx.addPath(path)
            ctx.setFillColor(VistaInk.color(0xFFFFFF))
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            // A faint cool shade along the bottom, and the scene's colour round the edge.
            VistaInk.fill(ctx, path, [(0, VistaInk.color(0xFFFFFF, 0)), (1, VistaInk.color(VistaInk.mixHex(accent, 0xE8ECF4, 0.75), 0.9))],
                          from: CGPoint(x: 0, y: rect.midY + 4), to: CGPoint(x: 0, y: rect.minY))
            ctx.addPath(path)
            ctx.setStrokeColor(VistaInk.color(accent, 0.95))
            ctx.setLineWidth(2.6)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            string.draw(at: NSPoint(x: rect.midX - box.width / 2, y: rect.midY - box.height / 2 + 1))
            NSGraphicsContext.restoreGraphicsState()
        }
        if let image {
            if cache.count > 120 { cache.removeAll() }
            cache[key] = image
        }
        return image
    }
}

// MARK: - Eyes, drawn live

/// Eyes drawn every frame, in a creature's own units: cheap, and alive. They blink, and they look where the creature looks.
enum VistaFace {
    /// A glossy cartoon bead of an eye: dark, with a catchlight. `look` moves it a touch; `blink` closes it.
    static func bead(_ ctx: CGContext, _ x: Double, _ y: Double, r: Double, look: SIMD2<Double>, blink: Double, color: UInt32 = 0x16111E) {
        let open = 1 - blink
        if open < 0.3 {
            // Shut: a soft curved line.
            ctx.setStrokeColor(VistaInk.color(color, 0.9))
            ctx.setLineWidth(CGFloat(r * 0.5))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: x - r, y: y))
            ctx.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y - r * 0.55))
            ctx.strokePath()
            return
        }
        let cx = x + look.x * r * 0.2, cy = y + look.y * r * 0.2
        ctx.setFillColor(VistaInk.color(color))
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r * 1.08 * open, width: r * 2, height: r * 2.16 * open))
        ctx.setFillColor(VistaInk.color(0xFFFFFF, 0.95))
        ctx.fillEllipse(in: CGRect(x: cx - r * 0.5, y: cy + r * 0.12 * open, width: r * 0.62, height: r * 0.62 * open))
        ctx.setFillColor(VistaInk.color(0xFFFFFF, 0.55))
        ctx.fillEllipse(in: CGRect(x: cx + r * 0.22, y: cy - r * 0.55 * open, width: r * 0.3, height: r * 0.3 * open))
    }

    /// An eye with a coloured iris and a pupil (round, or a slit), on white or straight on the face. `lid` is the colour of the
    /// eyelid that comes down when it blinks.
    static func iris(_ ctx: CGContext, _ x: Double, _ y: Double, r: Double, look: SIMD2<Double>, blink: Double, iris: UInt32,
                     sclera: UInt32? = 0xFFFFFF, slit: Bool = false, lid: UInt32, pupil: UInt32 = 0x0C0912, rest: Double = 0.2) {
        let eye = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.addEllipse(in: eye)
        ctx.clip()
        if let sclera { ctx.setFillColor(VistaInk.color(sclera)); ctx.fill(eye) }
        let ir = sclera == nil ? r : r * 0.66
        let ix = x + look.x * (r - ir) * 0.9, iy = y + look.y * (r - ir) * 0.9
        ctx.setFillColor(VistaInk.color(iris))
        ctx.fillEllipse(in: CGRect(x: ix - ir, y: iy - ir, width: ir * 2, height: ir * 2))
        ctx.setFillColor(VistaInk.color(VistaInk.mixHex(iris, 0xFFFFFF, 0.35), 0.8))
        ctx.fillEllipse(in: CGRect(x: ix - ir * 0.55, y: iy - ir * 0.75, width: ir * 1.1, height: ir * 0.6))
        ctx.setFillColor(VistaInk.color(pupil))
        let pw = slit ? ir * 0.28 : ir * 0.5, ph = slit ? ir * 0.9 : ir * 0.5
        ctx.fillEllipse(in: CGRect(x: ix - pw, y: iy - ph, width: pw * 2, height: ph * 2))
        ctx.setFillColor(VistaInk.color(0xFFFFFF, 0.95))
        ctx.fillEllipse(in: CGRect(x: ix - ir * 0.62, y: iy + ir * 0.18, width: ir * 0.5, height: ir * 0.5))
        // The upper lid: a little shade always, and all of it in a blink.
        let drop = rest + (1 - rest) * blink
        ctx.setFillColor(VistaInk.color(lid))
        ctx.fill(CGRect(x: x - r, y: y + r - r * 2 * drop, width: r * 2, height: r * 2 * drop))
        ctx.restoreGState()
        ctx.setStrokeColor(VistaInk.color(VistaInk.mixHex(lid, 0x000000, 0.55), 0.8))
        ctx.setLineWidth(CGFloat(r * 0.18))
        ctx.strokeEllipse(in: eye)
    }
}
