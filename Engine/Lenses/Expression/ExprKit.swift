import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

// Shared pieces for the expression lenses (hearts, stars, tears, the storm cloud, the emoji mask and so on):
// a latch for noisy signals, face-space geometry, shapes and cached sprites, and a way to warp only the
// part of the picture around the face.

/// An sRGB colour as three numbers, to keep palettes short.
typealias ExprRGB = (r: Double, g: Double, b: Double)

func exprColor(_ c: ExprRGB, _ alpha: Double = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(alpha))
}

func exprMix(_ a: ExprRGB, _ b: ExprRGB, _ t: Double) -> ExprRGB {
    let k = min(1, max(0, t))
    return (a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k)
}

func exprSmoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - a) / max(b - a, 1e-9)))
    return t * t * (3 - 2 * t)
}

/// Moves `value` toward `target` the way a smoothed signal would, whatever the frame time.
func exprEase(_ value: Double, toward target: Double, dt: Double, tau: Double) -> Double {
    value + (target - value) * (1 - exp(-dt / max(tau, 1e-6)))
}

/// Says whether a noisy 0...1 signal is "on": it must climb past `on` to switch on and drop below `off` to switch off,
/// so a jaw or an eyebrow wobbling around one number doesn't make an effect flicker.
struct ExprLatch {
    private(set) var isOn = false

    @discardableResult
    mutating func update(_ value: Double, on: Double, off: Double) -> Bool {
        isOn = value > (isOn ? off : on)
        return isOn
    }

    mutating func reset() { isOn = false }
}

extension FaceState {
    /// How big this face is next to the 84 px eye spacing of the test scene. Effects scale by it, with a floor so a face far
    /// from the camera still gets sprites you can see.
    var exprScale: Double { max(0.3, interocular / 84) }

    /// A point given in face units (origin between the eyes, x along the eyes, y up the face, 1 = eye spacing) as output pixels.
    func exprPoint(_ x: Double, _ y: Double) -> CGPoint {
        let c = cos(roll), s = sin(roll), io = interocular
        return CGPoint(x: eyeCenter.x + (x * c - y * s) * io, y: eyeCenter.y + (x * s + y * c) * io)
    }

    /// Where the middle of the face is: between the eyes and the mouth, a little nearer the eyes.
    var exprFaceCenter: CGPoint { exprPoint(0, -0.45) }

    /// A square (output pixels) that holds a circle of `radius` eye-spacings around a face-space point.
    func exprRegion(around p: CGPoint, radius: Double) -> CGRect {
        let r = radius * interocular
        return CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
    }
}

// MARK: - Shapes

/// Outlines in a box from -1 to 1 each way (y up), drawn into sprites.
enum ExprShapes {
    static func heart() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -0.9))
        p.addCurve(to: CGPoint(x: -0.96, y: 0.2), control1: CGPoint(x: -0.4, y: -0.55), control2: CGPoint(x: -0.96, y: -0.2))
        p.addCurve(to: CGPoint(x: 0, y: 0.5), control1: CGPoint(x: -0.96, y: 0.8), control2: CGPoint(x: -0.32, y: 0.98))
        p.addCurve(to: CGPoint(x: 0.96, y: 0.2), control1: CGPoint(x: 0.32, y: 0.98), control2: CGPoint(x: 0.96, y: 0.8))
        p.addCurve(to: CGPoint(x: 0, y: -0.9), control1: CGPoint(x: 0.96, y: -0.2), control2: CGPoint(x: 0.4, y: -0.55))
        p.closeSubpath()
        return p
    }

    /// A star with `points` tips: tips at radius `outer`, notches at radius `inner`, one tip pointing straight up.
    static func star(points: Int = 5, outer: Double, inner: Double) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let a = Double.pi / 2 + Double(i) * Double.pi / Double(points)
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// The same star with softened corners.
    static func roundedStar(points: Int = 5, outer: Double, inner: Double, rounding: Double) -> CGPath {
        var v: [CGPoint] = []
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let a = Double.pi / 2 + Double(i) * Double.pi / Double(points)
            v.append(CGPoint(x: cos(a) * r, y: sin(a) * r))
        }
        let n = v.count
        let p = CGMutablePath()
        p.move(to: CGPoint(x: (v[0].x + v[n - 1].x) / 2, y: (v[0].y + v[n - 1].y) / 2))
        for i in 0..<n {
            p.addArc(tangent1End: v[i], tangent2End: v[(i + 1) % n], radius: CGFloat(i % 2 == 0 ? rounding : rounding * 0.5))
        }
        p.closeSubpath()
        return p
    }

    /// A twinkle: four long thin points with curved sides.
    static func sparkle(pinch: Double = 0.1) -> CGPath {
        let p = CGMutablePath()
        let tips = [CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -1)]
        let k = CGFloat(pinch)
        p.move(to: tips[0])
        for i in 1...4 {
            let next = tips[i % 4]
            let mid = tips[i - 1]
            // The control point sits near the middle, pulled toward the corner between the two tips.
            p.addQuadCurve(to: next, control: CGPoint(x: (mid.x + next.x) * k, y: (mid.y + next.y) * k))
        }
        p.closeSubpath()
        return p
    }

    /// A drop of water. The round head faces +x and the tail trails off toward -x.
    static func teardrop() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -0.96, y: 0))
        p.addCurve(to: CGPoint(x: 0.3, y: 0.5), control1: CGPoint(x: -0.4, y: 0.04), control2: CGPoint(x: -0.1, y: 0.5))
        p.addArc(center: CGPoint(x: 0.3, y: 0), radius: 0.5, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        p.addCurve(to: CGPoint(x: -0.96, y: 0), control1: CGPoint(x: -0.1, y: -0.5), control2: CGPoint(x: -0.4, y: -0.04))
        p.closeSubpath()
        return p
    }

    /// A pointed leaf lying along +x, its stalk at the origin and its tip at x = 1.
    static func leaf() -> CGPath {
        let p = CGMutablePath()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: 1, y: 0), control1: CGPoint(x: 0.25, y: 0.5), control2: CGPoint(x: 0.75, y: 0.45))
        p.addCurve(to: .zero, control1: CGPoint(x: 0.75, y: -0.45), control2: CGPoint(x: 0.25, y: -0.5))
        p.closeSubpath()
        return p
    }

    /// A fluffy cloud: puffs on a flat-bottomed base.
    static func cloud() -> CGPath {
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: -0.88, y: -0.52, width: 1.76, height: 0.5), cornerWidth: 0.25, cornerHeight: 0.25)
        for (x, y, r) in [(-0.58, -0.12, 0.38), (-0.2, 0.14, 0.5), (0.3, 0.1, 0.46), (0.62, -0.14, 0.34)] as [(Double, Double, Double)] {
            p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        return p
    }

    static func gradient(_ colors: [(ExprRGB, Double)], alphas: [Double]? = nil) -> CGGradient? {
        let cg = colors.enumerated().map { exprColor($0.element.0, alphas?[$0.offset] ?? 1) }
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cg as CFArray, locations: colors.map { CGFloat($0.1) })
    }
}

// MARK: - Sprites

/// Small pictures drawn once and kept, then stamped as often as needed.
enum ExprSprites {
    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]

    /// Paints `draw` into a square canvas whose coordinates run from -1 to 1 each way, once per `key`.
    static func make(_ key: String, side: Int = 192, _ draw: (CGContext) -> Void) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: Sprites.bitmapInfo) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        ctx.scaleBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        draw(ctx)
        guard let image = ctx.makeImage() else { return nil }
        cache[key] = image
        return image
    }

    /// Fills a path with a vertical gradient (top to bottom) and edges it.
    private static func paint(_ ctx: CGContext, _ path: CGPath, top: ExprRGB, bottom: ExprRGB, edge: ExprRGB, edgeWidth: CGFloat) {
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let box = path.boundingBox
        if let g = ExprShapes.gradient([(top, 0), (bottom, 1)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: 0, y: box.minY), options: [])
        }
        ctx.restoreGState()
        ctx.setLineJoin(.round)
        ctx.setLineWidth(edgeWidth)
        ctx.setStrokeColor(exprColor(edge))
        ctx.addPath(path); ctx.strokePath()
    }

    private static func shine(_ ctx: CGContext, at c: CGPoint, size: CGSize, angle: CGFloat, alpha: Double) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        ctx.setFillColor(exprColor((1, 1, 1), alpha))
        ctx.fillEllipse(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        ctx.restoreGState()
    }

    /// A glossy heart in the house style. Variants: 0 red, 1 pink, 2 raspberry.
    static func heart(variant: Int) -> CGImage? {
        let ramps = [ExprPalette.rose, ExprPalette.blush,
                     ExprPalette.Ramp(light: (1.0, 0.6, 0.8), base: (0.86, 0.2, 0.52), dark: (0.6, 0.06, 0.34), edge: (0.4, 0.02, 0.24))]
        let ramp = ramps[abs(variant) % ramps.count]
        return make("expr-heart-v2-\(abs(variant) % ramps.count)") { ctx in
            ctx.scaleBy(x: 0.92, y: 0.92)
            ctx.translateBy(x: -0.02, y: 0.06)
            ExprPaint.glossy(ctx, ExprShapes.heart(), ramp, edgeWidth: 0.07, shadow: 0.35, shine: 0.8)
        }
    }

    /// A rounded golden star in the house style, with a paler facet in the middle.
    static func star() -> CGImage? {
        make("expr-star-v2") { ctx in
            ctx.scaleBy(x: 0.94, y: 0.94)
            ctx.translateBy(x: -0.02, y: 0.03)
            let path = ExprShapes.roundedStar(outer: 0.9, inner: 0.47, rounding: 0.14)
            ExprPaint.glossy(ctx, path, ExprPalette.gold, edgeWidth: 0.07, shadow: 0.35, shine: 0.0, rim: 0.5)
            ctx.setFillColor(exprColor((1.0, 0.99, 0.84), 0.55))
            ctx.addPath(ExprShapes.roundedStar(outer: 0.48, inner: 0.26, rounding: 0.07)); ctx.fillPath()
            ctx.setFillColor(exprColor((1, 1, 1), 0.9))
            ctx.fillEllipse(in: CGRect(x: -0.36, y: 0.2, width: 0.16, height: 0.16))
        }
    }

    /// A four-pointed twinkle with a soft halo, in one of a few colours.
    static func twinkle(variant: Int) -> CGImage? {
        let tints: [ExprRGB] = [(1.0, 0.97, 0.8), (1.0, 0.86, 0.3), (1.0, 0.6, 0.85), (0.6, 0.9, 1.0)]
        let tint = tints[abs(variant) % tints.count]
        return make("expr-twinkle-\(abs(variant) % tints.count)") { ctx in
            if let g = ExprShapes.gradient([(tint, 0), (tint, 1)], alphas: [0.5, 0]) {
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 0.75, options: [])
            }
            ctx.setFillColor(exprColor(tint))
            ctx.addPath(ExprShapes.sparkle(pinch: 0.07)); ctx.fillPath()
            ctx.setFillColor(exprColor((1, 1, 1)))
            ctx.saveGState()
            ctx.scaleBy(x: 0.55, y: 0.55)
            ctx.addPath(ExprShapes.sparkle(pinch: 0.07)); ctx.fillPath()
            ctx.restoreGState()
        }
    }

    /// A shiny drop of water, round end toward +x.
    static func tear() -> CGImage? {
        make("expr-tear-v2") { ctx in
            ctx.scaleBy(x: 0.9, y: 0.9)
            ExprPaint.glossy(ctx, ExprShapes.teardrop(), ExprPalette.aqua, edgeWidth: 0.06, shadow: 0.25, shine: 0.0, rim: 0.6)
            shine(ctx, at: CGPoint(x: 0.32, y: 0.22), size: CGSize(width: 0.32, height: 0.14), angle: 0.25, alpha: 0.9)
            ctx.setFillColor(exprColor((1, 1, 1), 0.7))
            ctx.fillEllipse(in: CGRect(x: 0.5, y: -0.2, width: 0.08, height: 0.08))
        }
    }

    /// A fluffy cloud, calm (soft white) or stormy (slate), lit from the top left with a soft shadow under its belly.
    static func cloud(stormy: Bool) -> CGImage? {
        let ramp = stormy ? ExprPalette.slate : ExprPalette.cloud
        return make(stormy ? "expr-cloud-storm-v2" : "expr-cloud-calm-v2", side: 256) { ctx in
            ctx.translateBy(x: 0, y: 0.15)
            ctx.scaleBy(x: 0.95, y: 0.95)
            let path = ExprShapes.cloud()
            let px = max(ctx.ctm.a, 1)
            // The edge goes down first, wide, and the fill covers its inner half, so only the outline of the whole cloud
            // shows and not the circles it is built from.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0.03 * px, height: -0.06 * px), blur: 0.1 * px, color: exprColor((0.05, 0.03, 0.12), 0.35))
            ctx.setLineJoin(.round)
            ctx.setLineWidth(0.09)
            ctx.setStrokeColor(exprColor(ramp.edge))
            ctx.addPath(path); ctx.strokePath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(path); ctx.clip(using: .winding)
            if let g = ExprShapes.gradient([(ramp.light, 0), (ramp.base, 0.45), (ramp.dark, 1)]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: -0.3, y: 0.65), end: CGPoint(x: 0.25, y: -0.52), options: [])
            }
            // Each puff's own soft top light, so it reads as a heap of puffs rather than a flat shape.
            for (x, y, r) in [(-0.58, -0.12, 0.38), (-0.2, 0.14, 0.5), (0.3, 0.1, 0.46), (0.62, -0.14, 0.34)] as [(Double, Double, Double)] {
                if let g = ExprShapes.gradient([(ramp.light, 0), (ramp.light, 1)], alphas: [stormy ? 0.35 : 0.8, 0]) {
                    let c = CGPoint(x: x - r * 0.3, y: y + r * 0.35)
                    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * 0.75, options: [])
                }
            }
            // A darker belly along the flat bottom.
            if let g = ExprShapes.gradient([(ramp.dark, 0), (ramp.dark, 1)], alphas: [0, 0.6]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: -0.15), end: CGPoint(x: 0, y: -0.52), options: [])
            }
            ctx.restoreGState()
        }
    }

    /// A leaf with a midrib, stalk at the left of the picture and tip at the right.
    static func leaf() -> CGImage? {
        make("expr-leaf") { ctx in
            ctx.translateBy(x: -0.95, y: 0)
            ctx.scaleBy(x: 1.9, y: 1.9)
            let path = ExprShapes.leaf()
            paint(ctx, path, top: (0.52, 0.86, 0.3), bottom: (0.2, 0.6, 0.18), edge: (0.1, 0.38, 0.1), edgeWidth: 0.04)
            ctx.setStrokeColor(exprColor((0.12, 0.42, 0.12), 0.8))
            ctx.setLineWidth(0.025)
            ctx.move(to: CGPoint(x: 0.02, y: 0)); ctx.addLine(to: CGPoint(x: 0.85, y: 0)); ctx.strokePath()
        }
    }
}

extension CGContext {
    /// Stamps a cached sprite centred on a point at a height in pixels (the sprite's whole -1...1 box), turned by `rotation`.
    func exprStamp(_ image: CGImage?, at p: CGPoint, height: Double, rotation: Double = 0, alpha: Double = 1) {
        guard let image, height > 0.5, alpha > 0.004 else { return }
        draw(image, center: p, height: CGFloat(height), rotation: CGFloat(rotation), alpha: CGFloat(min(1, alpha)))
    }
}

// MARK: - Emoji

/// System emoji, trimmed to the picture itself so a face can be sized and centred exactly.
enum ExprEmoji {
    private static let lock = NSLock()
    private static var trimmed: [String: CGImage] = [:]

    /// The emoji if it has been drawn already, without drawing it: for a frame that mustn't wait.
    static func cached(_ character: String, size: CGFloat = 300) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        return trimmed["\(character)@\(Int(size))"]
    }

    /// Draws emoji off to the side so they are ready by the time a frame wants them.
    static func prepare(_ characters: [String], size: CGFloat = 300) {
        DispatchQueue.global(qos: .userInitiated).async { for c in characters { _ = image(c, size: size) } }
    }

    static func image(_ character: String, size: CGFloat = 300) -> CGImage? {
        let key = "\(character)@\(Int(size))"
        lock.lock()
        if let hit = trimmed[key] { lock.unlock(); return hit }
        lock.unlock()
        guard let raw = Sprites.emoji(character, size: size) else { return nil }
        let box = opaqueBounds(of: raw)
        let made = box.flatMap { raw.cropping(to: $0) } ?? raw
        lock.lock(); defer { lock.unlock() }
        if trimmed.count > 24 { trimmed.removeAll() }
        trimmed[key] = made
        return made
    }

    /// The smallest rectangle (image pixels, origin top left) that holds everything not transparent.
    private static func opaqueBounds(of image: CGImage) -> CGRect? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data), image.bitsPerPixel == 32 else { return nil }
        let w = image.width, h = image.height, stride = image.bytesPerRow
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = bytes + y * stride
            for x in 0..<w where row[x * 4 + 3] > 12 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

// MARK: - Warping

/// Core Image distortions limited to the neighbourhood of the face. The filters see the whole picture (edges extended, so
/// nothing goes transparent at the border) but only the pixels inside `region` are ever worked out.
enum ExprWarp {
    static func apply(to image: CIImage, in region: CGRect, bounds: CGRect, _ filters: (CIImage) -> CIImage) -> CIImage {
        let area = region.integral.intersection(bounds)
        guard !area.isNull, area.width > 2, area.height > 2 else { return image }
        return filters(image.clampedToExtent()).cropped(to: area).composited(over: image).cropped(to: bounds)
    }

    /// Positive `scale` swells what is under `center`; negative shrinks it.
    static func bump(_ image: CIImage, center: CGPoint, radius: Double, scale: Double) -> CIImage {
        let f = CIFilter.bumpDistortion()
        f.inputImage = image
        f.center = center
        f.radius = Float(radius)
        f.scale = Float(scale)
        return f.outputImage ?? image
    }

    static func twirl(_ image: CIImage, center: CGPoint, radius: Double, angle: Double) -> CIImage {
        let f = CIFilter.twirlDistortion()
        f.inputImage = image
        f.center = center
        f.radius = Float(radius)
        f.angle = Float(angle)
        return f.outputImage ?? image
    }

    /// The smallest rectangle holding every circle given as (centre, radius).
    static func union(of circles: [(CGPoint, Double)]) -> CGRect {
        circles.map { CGRect(x: $0.0.x - $0.1, y: $0.0.y - $0.1, width: $0.1 * 2, height: $0.1 * 2) }
            .reduce(CGRect.null) { $0.union($1) }
    }
}
