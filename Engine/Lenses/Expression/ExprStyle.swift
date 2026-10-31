import AppKit
import CoreGraphics
import CoreText

// The house style of the expression lenses, so they look like one family: named palettes, one way of painting a hero
// object (light from the top left, a soft shadow down and right, a rim of light on the far edge, an edge a shade darker than
// the fill), one typeface treatment, and the motion helpers everything moves with.

// MARK: - Palettes

enum ExprPalette {
    /// Four tones of one colour, for the glossy recipe: highlight, body, shade, and the edge line.
    struct Ramp {
        var light: ExprRGB, base: ExprRGB, dark: ExprRGB, edge: ExprRGB
    }

    static let rose = Ramp(light: (1.0, 0.64, 0.72), base: (0.96, 0.24, 0.40), dark: (0.74, 0.06, 0.24), edge: (0.46, 0.03, 0.16))
    static let blush = Ramp(light: (1.0, 0.82, 0.88), base: (1.0, 0.55, 0.70), dark: (0.90, 0.30, 0.52), edge: (0.62, 0.14, 0.34))
    static let gold = Ramp(light: (1.0, 0.97, 0.70), base: (1.0, 0.80, 0.20), dark: (0.95, 0.52, 0.06), edge: (0.62, 0.31, 0.03))
    static let aqua = Ramp(light: (0.88, 0.98, 1.0), base: (0.42, 0.78, 1.0), dark: (0.16, 0.47, 0.93), edge: (0.07, 0.27, 0.64))
    static let mint = Ramp(light: (0.82, 1.0, 0.86), base: (0.36, 0.88, 0.56), dark: (0.10, 0.62, 0.40), edge: (0.04, 0.36, 0.24))
    static let violet = Ramp(light: (0.90, 0.80, 1.0), base: (0.64, 0.42, 1.0), dark: (0.42, 0.18, 0.86), edge: (0.24, 0.08, 0.52))
    static let ember = Ramp(light: (1.0, 0.86, 0.56), base: (1.0, 0.50, 0.18), dark: (0.86, 0.20, 0.08), edge: (0.50, 0.08, 0.04))
    static let cloud = Ramp(light: (1.0, 1.0, 1.0), base: (0.90, 0.92, 0.97), dark: (0.68, 0.72, 0.84), edge: (0.42, 0.46, 0.60))
    static let slate = Ramp(light: (0.56, 0.60, 0.72), base: (0.36, 0.39, 0.52), dark: (0.17, 0.18, 0.28), edge: (0.08, 0.09, 0.16))
    static let snow = Ramp(light: (1.0, 1.0, 1.0), base: (0.97, 0.97, 0.99), dark: (0.84, 0.86, 0.92), edge: (0.30, 0.30, 0.40))
    static let lilac = Ramp(light: (0.95, 0.90, 1.0), base: (0.82, 0.74, 0.98), dark: (0.62, 0.52, 0.88), edge: (0.32, 0.24, 0.56))
    static let wood = Ramp(light: (0.99, 0.82, 0.56), base: (0.86, 0.58, 0.31), dark: (0.58, 0.35, 0.16), edge: (0.36, 0.19, 0.07))

    /// The ink for outlines and words: a deep plum rather than black, so it sits well on skin and on colour.
    static let ink: ExprRGB = (0.16, 0.09, 0.22)
    /// Neon tones for the sci-fi lenses.
    static let neonCyan: ExprRGB = (0.30, 0.95, 1.0)
    static let neonPink: ExprRGB = (1.0, 0.32, 0.78)
    static let neonLime: ExprRGB = (0.70, 1.0, 0.36)
    static let neonAmber: ExprRGB = (1.0, 0.74, 0.22)
}

// MARK: - Painting

enum ExprPaint {
    /// Paints a hero shape in the house style. Meant for baking sprites (it uses a real shadow blur), not for every frame.
    /// `shadow` is the shadow's opacity, `shine` the specular highlight's.
    static func glossy(_ ctx: CGContext, _ path: CGPath, _ ramp: ExprPalette.Ramp, edgeWidth: CGFloat = 0.06, shadow: Double = 0.32,
                       shine: Double = 0.75, rim: Double = 0.45) {
        let px = max(ctx.ctm.a, 1)              // pixels per unit, for the shadow, which is set in pixels
        let box = path.boundingBox
        if shadow > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0.03 * px, height: -0.055 * px), blur: 0.08 * px, color: exprColor((0.05, 0.02, 0.1), shadow))
            ctx.addPath(path); ctx.setFillColor(exprColor(ramp.base)); ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        if let g = ExprShapes.gradient([(ramp.light, 0), (ramp.base, 0.42), (ramp.dark, 1)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: box.minX + box.width * 0.2, y: box.maxY), end: CGPoint(x: box.maxX - box.width * 0.15, y: box.minY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        if rim > 0 {
            // Light catching the lower right edge: the outline nudged up and left, seen only inside the shape.
            ctx.saveGState()
            ctx.translateBy(x: -box.width * 0.045, y: box.height * 0.045)
            ctx.addPath(path)
            ctx.setStrokeColor(exprColor(ramp.light, rim))
            ctx.setLineWidth(max(box.width, box.height) * 0.05)
            ctx.strokePath()
            ctx.restoreGState()
        }
        if shine > 0 {
            ctx.saveGState()
            ctx.translateBy(x: box.minX + box.width * 0.3, y: box.maxY - box.height * 0.27)
            ctx.rotate(by: 0.6)
            let w = box.width * 0.26, h = box.height * 0.12
            ctx.setFillColor(exprColor((1, 1, 1), shine))
            ctx.fillEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            ctx.restoreGState()
            ctx.setFillColor(exprColor((1, 1, 1), shine * 0.9))
            let d = max(box.width, box.height) * 0.05
            ctx.fillEllipse(in: CGRect(x: box.minX + box.width * 0.16 - d / 2, y: box.maxY - box.height * 0.42 - d / 2, width: d, height: d))
        }
        ctx.restoreGState()
        if edgeWidth > 0 {
            ctx.setLineJoin(.round); ctx.setLineCap(.round)
            ctx.setLineWidth(edgeWidth)
            ctx.setStrokeColor(exprColor(ramp.edge))
            ctx.addPath(path); ctx.strokePath()
        }
    }

    /// A circle, as a path.
    static func circle(_ c: CGPoint, _ r: Double) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
    }
}

// MARK: - Type

/// Words on the picture: a heavy rounded face, a fill that runs light to dark, a thick soft-cornered outline and a shadow,
/// baked once per word and look.
enum ExprType {
    struct Look: Hashable {
        var top: ExprRGBKey
        var bottom: ExprRGBKey
        var edge: ExprRGBKey
        /// Outline width as a fraction of the font size.
        var edgeWidth: Double = 0.16
        /// A second, white outline outside the coloured one, for the comic look.
        var halo = false
    }

    static let white = Look(top: .init((1, 1, 1)), bottom: .init((0.86, 0.9, 1)), edge: .init(ExprPalette.ink))
    static let gold = Look(top: .init((1, 0.98, 0.7)), bottom: .init((1, 0.68, 0.12)), edge: .init((0.42, 0.16, 0.04)))
    static let comic = Look(top: .init((1, 0.95, 0.35)), bottom: .init((1, 0.55, 0.1)), edge: .init((0.25, 0.05, 0.12)), edgeWidth: 0.14, halo: true)

    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]

    static func font(size: CGFloat, weight: NSFont.Weight = .black) -> NSFont {
        let plain = NSFont.systemFont(ofSize: size, weight: weight)
        return plain.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? plain
    }

    /// The outline of a line of text, its baseline at y = 0 and its left end at x = 0.
    static func path(_ text: String, size: CGFloat, weight: NSFont.Weight = .black) -> CGPath {
        let font = font(size: size, weight: weight)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let path = CGMutablePath()
        let runs = (CTLineGetGlyphRuns(line) as NSArray) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for i in 0..<count {
                if let glyph = CTFontCreatePathForGlyph(font, glyphs[i], nil) {
                    path.addPath(glyph, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
                }
            }
        }
        return path
    }

    /// The word baked into a picture about `size` pixels tall per line of type, with room for its outline and shadow.
    static func label(_ text: String, look: Look, size: CGFloat = 96) -> CGImage? {
        let key = "\(text)|\(look.hashValue)|\(Int(size))"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let glyphs = path(text, size: size)
        let box = glyphs.boundingBoxOfPath
        guard !box.isNull, box.width > 0 else { return nil }
        let pad = size * CGFloat(look.edgeWidth * (look.halo ? 2.2 : 1.2) + 0.12)
        let width = Int(ceil(box.width + pad * 2)), height = Int(ceil(box.height + pad * 2))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: Sprites.bitmapInfo) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.translateBy(x: pad - box.minX, y: pad - box.minY)
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        let edge = size * CGFloat(look.edgeWidth)
        // The shadow goes under everything, cast by the outline.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: size * 0.03, height: -size * 0.06), blur: size * 0.08, color: exprColor((0.04, 0.02, 0.08), 0.5))
        if look.halo {
            ctx.addPath(glyphs); ctx.setLineWidth(edge * 2.4); ctx.setStrokeColor(exprColor((1, 1, 1))); ctx.strokePath()
        }
        ctx.addPath(glyphs); ctx.setLineWidth(edge); ctx.setStrokeColor(exprColor(look.edge.rgb)); ctx.strokePath()
        ctx.restoreGState()
        if look.halo {
            ctx.addPath(glyphs); ctx.setLineWidth(edge); ctx.setStrokeColor(exprColor(look.edge.rgb)); ctx.strokePath()
        }
        ctx.saveGState()
        ctx.addPath(glyphs); ctx.clip()
        if let g = ExprShapes.gradient([(look.top.rgb, 0), (look.bottom.rgb, 1)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: 0, y: box.minY), options: [])
        }
        // A thin band of light along the tops of the letters.
        ctx.translateBy(x: 0, y: -size * 0.035)
        ctx.addPath(glyphs)
        ctx.setStrokeColor(exprColor((1, 1, 1), 0.35)); ctx.setLineWidth(size * 0.03); ctx.strokePath()
        ctx.restoreGState()
        guard let image = ctx.makeImage() else { return nil }
        lock.lock(); defer { lock.unlock() }
        if cache.count > 64 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

/// A colour that can be a dictionary key.
struct ExprRGBKey: Hashable {
    var r: Double, g: Double, b: Double
    init(_ c: ExprRGB) { r = c.r; g = c.g; b = c.b }
    var rgb: ExprRGB { (r, g, b) }
}

// MARK: - Motion

/// Eases out with a small overshoot past 1 before settling: for things that pop into place.
func exprOutBack(_ t: Double, overshoot: Double = 1.7) -> Double {
    let x = min(1, max(0, t)) - 1
    return 1 + x * x * ((overshoot + 1) * x + overshoot)
}

/// Eases out with a few springy wobbles.
func exprOutElastic(_ t: Double) -> Double {
    let x = min(1, max(0, t))
    if x == 0 || x == 1 { return x }
    return pow(2, -10 * x) * sin((x * 10 - 0.75) * (2 * .pi / 3)) + 1
}

func exprOutCubic(_ t: Double) -> Double { let x = 1 - min(1, max(0, t)); return 1 - x * x * x }

/// A value on a spring: it chases its target, overshoots a little and settles, the way real things do.
struct ExprSpring {
    var value: Double
    var velocity = 0.0

    init(_ value: Double = 0) { self.value = value }

    /// `frequency` in cycles a second; `damping` 1 settles with no bounce, lower bounces more.
    mutating func step(toward target: Double, dt: Double, frequency: Double = 3, damping: Double = 0.45) {
        let total = min(max(dt, 0), 0.25)
        let steps = max(1, Int((total / (1.0 / 240)).rounded(.up)))
        let h = total / Double(steps)
        let w = 2 * Double.pi * frequency
        for _ in 0..<steps {
            velocity += (w * w * (target - value) - 2 * damping * w * velocity) * h
            value += velocity * h
        }
    }

    mutating func reset(_ to: Double = 0) { value = to; velocity = 0 }
}

/// Whether a face is here, eased: fades in when one turns up and out when it is lost, keeping the last one to draw with
/// while it goes, so nothing blinks off.
struct ExprPresence {
    private(set) var face: FaceState?
    private(set) var alpha = 0.0
    /// Seconds since the face turned up (0 when there is none).
    private(set) var visibleFor = 0.0

    mutating func update(_ seen: FaceState?, dt: Double, fadeIn: Double = 0.2, fadeOut: Double = 0.3) {
        if let seen {
            face = seen
            visibleFor += dt
            alpha = min(1, alpha + dt / fadeIn)
        } else {
            visibleFor = 0
            alpha = max(0, alpha - dt / fadeOut)
            if alpha <= 0 { face = nil }
        }
    }

    mutating func reset() { face = nil; alpha = 0; visibleFor = 0 }
}

// MARK: - Layout

extension FaceState {
    /// Moves a box of half-size `half` (pixels) centred at `p` so it sits inside `rect` with a 5% border, as gently as possible.
    func exprKeepInside(_ p: CGPoint, half: CGSize, in rect: CGRect) -> CGPoint {
        let inset = rect.insetBy(dx: rect.width * 0.05, dy: rect.height * 0.05)
        var x = p.x, y = p.y
        if inset.width > half.width * 2 { x = min(max(x, inset.minX + half.width), inset.maxX - half.width) }
        if inset.height > half.height * 2 { y = min(max(y, inset.minY + half.height), inset.maxY - half.height) }
        return CGPoint(x: x, y: y)
    }
}

extension LensServices {
    /// An overlay drawn with plain rather than the best image filtering: sprites are drawn near their own size, where the two
    /// look the same, and the best costs several times more. The canvas's own setting is put back afterwards.
    func exprOverlay(_ draw: (CGContext) -> Void) -> CIImage? {
        overlay { ctx in
            ctx.saveGState()
            ctx.interpolationQuality = .medium
            draw(ctx)
            ctx.restoreGState()
        }
    }
}

extension CGContext {
    /// Stamps a sprite at any size, face units included (`exprStamp` skips anything under half a pixel).
    func exprPlace(_ image: CGImage?, at p: CGPoint, height: Double, rotation: Double = 0, alpha: Double = 1) {
        guard let image, height > 0, alpha > 0.004 else { return }
        draw(image, center: p, height: CGFloat(height), rotation: CGFloat(rotation), alpha: CGFloat(min(1, alpha)))
    }

    /// Draws a label baked by `ExprType.label` centred on a point, its type `fontSize` pixels tall, turned and faded.
    func exprLabel(_ image: CGImage?, at p: CGPoint, fontSize: Double, bakedAt: Double = 96, rotation: Double = 0, alpha: Double = 1) {
        guard let image, fontSize > 1, alpha > 0.004 else { return }
        draw(image, center: p, height: CGFloat(Double(image.height) * fontSize / bakedAt), rotation: CGFloat(rotation), alpha: CGFloat(min(1, alpha)))
    }
}
