import AppKit
import CoreGraphics
import simd

/// The face games' named colours. Every game paints from this one box so the set looks like one family.
enum FaceGamePalette {
    typealias Tone = FaceGamePaint.Tone
    /// Plates behind the score and the outline of type: a deep blue-black, never pure black.
    static let ink = Tone(0.07, 0.08, 0.16)
    static let dusk = Tone(0.16, 0.13, 0.32)
    static let cream = Tone(1.0, 0.97, 0.9)
    /// Gold: best scores, wins, bonuses.
    static let sun = Tone(1.0, 0.8, 0.26)
    static let tangerine = Tone(1.0, 0.58, 0.24)
    /// Danger, losses, hearts.
    static let coral = Tone(1.0, 0.4, 0.4)
    static let berry = Tone(0.86, 0.24, 0.44)
    static let bubblegum = Tone(1.0, 0.56, 0.76)
    static let grape = Tone(0.56, 0.38, 0.92)
    static let sky = Tone(0.38, 0.72, 1.0)
    static let teal = Tone(0.2, 0.78, 0.76)
    /// Success and "go".
    static let mint = Tone(0.4, 0.9, 0.62)
    static let leaf = Tone(0.34, 0.72, 0.32)
    static let skin = Tone(1.0, 0.86, 0.62)
}

/// Pictures the face games draw once and keep, and the shading every hero object shares.
///
/// The light always comes from the top left: a lit object is lighter there and darker at the bottom right, has a soft white
/// highlight up and to the left of its middle, and a darker edge of its own colour instead of a black outline.
enum FaceGameArt {
    typealias Tone = FaceGamePaint.Tone

    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]

    /// A picture drawn once at `width` x `height` pixels and kept under `key`. The drawing is handed a context whose origin is the
    /// lower left. Never call it with a key that changes every frame.
    static func sprite(_ key: String, width: Int, height: Int, draw: (CGContext, CGSize) -> Void) -> CGImage? {
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        guard width > 0, height > 0, let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                         space: FaceGamePaint.space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        draw(ctx, CGSize(width: width, height: height))
        guard let image = ctx.makeImage() else { return nil }
        lock.lock()
        if cache.count > 400 { cache.removeAll() }
        cache[key] = image
        lock.unlock()
        return image
    }

    /// Forgets every kept picture, so a test can see what drawing them the first time costs.
    static func forgetAll() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    /// Draws a kept picture centred on a point, `height` tall, turned and squashed: `stretch` above 1 makes it taller and thinner.
    ///
    /// The overlay asks for the slowest, finest resampling; a sprite drawn smaller or turned looks the same with the quick kind, at a
    /// fraction of the cost, so that is used here. A sprite drawn at its own size, upright, lands on whole pixels and isn't resampled.
    static func stamp(_ ctx: CGContext, _ image: CGImage?, at p: CGPoint, height: Double, rotation: Double = 0, stretch: Double = 1, alpha: Double = 1) {
        guard let image, alpha > 0.004, height > 0.5 else { return }
        let h = height * stretch, w = height * Double(image.width) / Double(image.height) / stretch
        if rotation == 0, abs(h - Double(image.height)) < 0.5, abs(w - Double(image.width)) < 0.5 {
            blit(ctx, image, at: CGPoint(x: p.x - w / 2, y: p.y - h / 2), alpha: alpha)
            return
        }
        ctx.saveGState()
        ctx.interpolationQuality = .low
        ctx.translateBy(x: p.x, y: p.y)
        if rotation != 0 { ctx.rotate(by: CGFloat(rotation)) }
        if alpha < 1 { ctx.setAlpha(CGFloat(alpha)) }
        ctx.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        ctx.restoreGState()
    }

    /// Draws a picture at its own size with its lower left corner on the nearest whole pixel: the fastest way to put it down.
    static func blit(_ ctx: CGContext, _ image: CGImage?, at origin: CGPoint, alpha: Double = 1) {
        guard let image, alpha > 0.004 else { return }
        ctx.saveGState()
        // Only skip resampling when nothing above has turned or scaled the drawing.
        let m = ctx.ctm
        let plain = abs(abs(m.a) - 1) < 1e-6 && abs(abs(m.d) - 1) < 1e-6 && abs(m.b) < 1e-6 && abs(m.c) < 1e-6
        ctx.interpolationQuality = plain ? .none : .low
        if alpha < 1 { ctx.setAlpha(CGFloat(alpha)) }
        ctx.draw(image, in: CGRect(x: origin.x.rounded(), y: origin.y.rounded(), width: CGFloat(image.width), height: CGFloat(image.height)))
        ctx.restoreGState()
    }

    // MARK: Colour

    /// The darker edge of a colour: the same hue, deeper.
    static func edge(of tone: Tone) -> Tone { FaceGamePaint.mix(tone * 0.52, FaceGamePalette.ink, 0.25) }
    static func lighter(_ tone: Tone, _ amount: Double = 0.35) -> Tone { FaceGamePaint.mix(tone, Tone(1, 1, 1), amount) }
    static func darker(_ tone: Tone, _ amount: Double = 0.3) -> Tone { tone * (1 - amount) }

    // MARK: Lit shapes

    /// Fills a path lit from the top left: lighter there, deeper to the bottom right, then a darker rim of its own colour.
    static func fillLit(_ ctx: CGContext, _ path: CGPath, tone: Tone, edgeWidth: Double = 0, edgeTone: Tone? = nil, contrast: Double = 1) {
        // The edge goes down first, twice as wide, and the fill covers its inner half: a path made of overlapping pieces gets one
        // clean outline instead of seams where the pieces cross.
        if edgeWidth > 0 {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(CGFloat(edgeWidth * 2))
            ctx.setStrokeColor(FaceGamePaint.cg(edgeTone ?? edge(of: tone)))
            ctx.strokePath()
            ctx.restoreGState()
        }
        let box = path.boundingBoxOfPath
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let top = lighter(tone, 0.3 * contrast), bottom = FaceGamePaint.mix(tone, tone * 0.62, contrast)
        if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: [FaceGamePaint.cg(top), FaceGamePaint.cg(tone), FaceGamePaint.cg(bottom)] as CFArray,
                              locations: [0, 0.45, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: box.minX + box.width * 0.2, y: box.maxY), end: CGPoint(x: box.maxX - box.width * 0.2, y: box.minY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }

    /// A ball lit from the top left: a bright spot, a body colour, a shadowed lower right and a thin rim.
    static func litBall(_ ctx: CGContext, center c: CGPoint, radius r: Double, tone: Tone, edgeWidth: Double = 0, gloss: Double = 0.55) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        let hot = CGPoint(x: c.x - r * 0.38, y: c.y + r * 0.42)
        let colors = [FaceGamePaint.cg(lighter(tone, 0.45)), FaceGamePaint.cg(tone), FaceGamePaint.cg(FaceGamePaint.mix(tone, tone * 0.5, 0.9))] as CFArray
        if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: colors, locations: [0, 0.5, 1]) {
            ctx.drawRadialGradient(g, startCenter: hot, startRadius: 0, endCenter: c, endRadius: r * 1.08, options: [.drawsAfterEndLocation])
        }
        // A cool bounce light along the lower right edge keeps the dark side from going flat.
        ctx.setStrokeColor(FaceGamePaint.cg(lighter(tone, 0.5), 0.22))
        ctx.setLineWidth(CGFloat(r * 0.14))
        ctx.addArc(center: c, radius: CGFloat(r * 0.93), startAngle: -.pi * 0.62, endAngle: .pi * 0.02, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
        if edgeWidth > 0 {
            ctx.setStrokeColor(FaceGamePaint.cg(edge(of: tone)))
            ctx.setLineWidth(CGFloat(edgeWidth))
            ctx.strokeEllipse(in: rect.insetBy(dx: edgeWidth / 2, dy: edgeWidth / 2))
        }
        if gloss > 0 { highlight(ctx, center: CGPoint(x: c.x - r * 0.36, y: c.y + r * 0.42), width: r * 0.62, height: r * 0.36, rotation: 0.6, alpha: gloss) }
    }

    /// A soft white highlight: the glint of the light on a shiny surface.
    static func highlight(_ ctx: CGContext, center c: CGPoint, width: Double, height: Double, rotation: Double = 0, alpha: Double = 0.6) {
        guard let dot = Sprites.dot(red: 1, green: 1, blue: 1) else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .low
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(rotation))
        ctx.setAlpha(CGFloat(alpha))
        ctx.draw(dot, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        ctx.restoreGState()
    }

    /// A soft dark ellipse under something, where it meets the ground or casts on what is behind it.
    static func contactShadow(_ ctx: CGContext, center c: CGPoint, width: Double, height: Double, alpha: Double = 0.35) {
        guard let dot = Sprites.dot(red: 0.02, green: 0.02, blue: 0.08), alpha > 0.004 else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .low
        ctx.setAlpha(CGFloat(min(1, alpha)))
        ctx.draw(dot, in: CGRect(x: c.x - width / 2, y: c.y - height / 2, width: width, height: height))
        ctx.restoreGState()
    }

    // MARK: Paths

    static func star(center c: CGPoint, radius: Double, inner: Double = 0.48, points: Int = 5, rotation: Double = 0, round: Bool = false) -> CGPath {
        let path = CGMutablePath()
        let count = points * 2
        var corners: [CGPoint] = []
        for i in 0..<count {
            let r = i % 2 == 0 ? radius : radius * inner
            let a = rotation + .pi / 2 + Double(i) * .pi / Double(points)
            corners.append(CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
        }
        if round {
            // Rounded tips: go between midpoints, curving through each corner.
            func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
            path.move(to: mid(corners[count - 1], corners[0]))
            for i in 0..<count { path.addQuadCurve(to: mid(corners[i], corners[(i + 1) % count]), control: corners[i]) }
        } else {
            path.addLines(between: corners)
        }
        path.closeSubpath()
        return path
    }

    /// A closed blob through points around a centre, smoothed: for rocks, clouds of smoke, splats.
    static func blob(center c: CGPoint, radii: [Double], rotation: Double = 0) -> CGPath {
        let n = radii.count
        let points = (0..<n).map { i -> CGPoint in
            let a = rotation + Double(i) / Double(n) * 2 * .pi
            return CGPoint(x: c.x + cos(a) * radii[i], y: c.y + sin(a) * radii[i])
        }
        let path = CGMutablePath()
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: mid(points[n - 1], points[0]))
        for i in 0..<n { path.addQuadCurve(to: mid(points[i], points[(i + 1) % n]), control: points[i]) }
        path.closeSubpath()
        return path
    }

    // MARK: Small pieces shared by several games

    /// A five-pointed gold star with rounded tips.
    static func starSprite(tone: Tone = FaceGamePalette.sun) -> CGImage? {
        let key = String(format: "star-%.2f-%.2f-%.2f", tone.x, tone.y, tone.z)
        return sprite(key, width: 96, height: 96) { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2 - 2)
            fillLit(ctx, star(center: c, radius: 42, inner: 0.5, round: true), tone: tone, edgeWidth: 4)
            highlight(ctx, center: CGPoint(x: c.x - 10, y: c.y + 14), width: 22, height: 12, rotation: 0.6, alpha: 0.8)
        }
    }
}

/// Springy numbers for motion that settles instead of stopping dead.
enum FaceGameEase {
    /// 0 to 1 with a little overshoot past 1 before settling: for things popping in.
    static func backOut(_ t: Double, overshoot s: Double = 1.70158) -> Double {
        let x = FaceGamePaint.clamp01(t) - 1
        return x * x * ((s + 1) * x + s) + 1
    }

    /// 0 to 1, fast then gently arriving.
    static func cubicOut(_ t: Double) -> Double {
        let x = 1 - FaceGamePaint.clamp01(t)
        return 1 - x * x * x
    }

    /// A wobble that dies away: 1 at the start, swinging either side of 0, settled by t = 1.
    static func wobble(_ t: Double, swings: Double = 3) -> Double {
        guard t >= 0, t < 1 else { return 0 }
        return cos(t * swings * 2 * .pi) * (1 - t) * (1 - t)
    }

    /// A smooth step towards a goal that takes the same time whatever the frame rate: `rate` is how fast, per second.
    static func approach(_ value: Double, _ goal: Double, rate: Double, dt: Double) -> Double {
        value + (goal - value) * (1 - exp(-rate * max(0, dt)))
    }
}
