import AppKit
import CoreGraphics
import CoreText

/// The shapes, colours and lettering Present draws with, so the panel, the bubble, the cards, the preview's chrome and the
/// how-to demo all share one corner, one shadow and one type style.
enum StageArt {
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The accent of the chrome: a clear, luminous blue.
    static let accent = SIMD3<Double>(0.27, 0.62, 1.0)
    /// The near-black of a screen's bezel, behind content that does not fill the panel.
    static let bezel = SIMD3<Double>(0.055, 0.06, 0.07)
    /// Slate for the cards: a cool dark that is not quite black.
    static let slateTop = SIMD3<Double>(0.15, 0.165, 0.2)
    static let slateBottom = SIMD3<Double>(0.075, 0.08, 0.1)

    static func color(_ c: SIMD3<Double>, _ alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat(c.x), CGFloat(c.y), CGFloat(c.z), CGFloat(min(1, max(0, alpha)))])!
    }

    static func white(_ alpha: Double) -> CGColor { color(SIMD3(1, 1, 1), alpha) }
    static func black(_ alpha: Double) -> CGColor { color(SIMD3(0, 0, 0), alpha) }

    /// A bitmap in the overlay canvas's own layout, for baking art once.
    static func bitmap(width: Int, height: Int) -> CGContext? {
        let ctx = CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: Sprites.bitmapInfo)
        ctx?.setAllowsAntialiasing(true)
        ctx?.setShouldAntialias(true)
        ctx?.interpolationQuality = .high
        return ctx
    }

    // MARK: Continuous corners

    /// A rectangle with continuous ("squircle") corners, the way Apple draws icons and windows: the curve eases into each straight
    /// edge instead of meeting it at a sharp change of curvature, which is what makes a plain rounded rectangle look stamped out.
    ///
    /// Each corner is a superellipse quadrant spanning 1.7 times `radius`, which reads as about the same roundness as a circular
    /// corner of that radius.
    static func continuousRect(_ r: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard r.width > 0, r.height > 0 else { return path }
        let extent = min(radius * 1.7, min(r.width, r.height) / 2)
        guard extent > 0.5 else { path.addRect(r); return path }
        let n = 4.6
        let steps = 14
        // Corner centres, starting lower right and going counter-clockwise (y up).
        let corners: [(CGPoint, Double)] = [
            (CGPoint(x: r.maxX - extent, y: r.minY + extent), -Double.pi / 2),
            (CGPoint(x: r.maxX - extent, y: r.maxY - extent), 0),
            (CGPoint(x: r.minX + extent, y: r.maxY - extent), Double.pi / 2),
            (CGPoint(x: r.minX + extent, y: r.minY + extent), Double.pi),
        ]
        path.move(to: CGPoint(x: r.minX + extent, y: r.minY))
        for (c, start) in corners {
            for i in 0...steps {
                let t = start + Double(i) / Double(steps) * Double.pi / 2
                let cs = cos(t), sn = sin(t)
                let x = (cs < 0 ? -1.0 : 1.0) * pow(abs(cs), 2 / n)
                let y = (sn < 0 ? -1.0 : 1.0) * pow(abs(sn), 2 / n)
                path.addLine(to: CGPoint(x: Double(c.x) + x * Double(extent), y: Double(c.y) + y * Double(extent)))
            }
        }
        path.closeSubpath()
        return path
    }

    /// A convex four-sided outline (lower left, lower right, upper right, upper left) with rounded corners, grown outward by `grow`.
    /// The panel's turned outline and the chrome around it are drawn with this.
    static func roundedQuad(_ quad: [CGPoint], radius: CGFloat, grow: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        guard quad.count == 4 else { return path }
        let cx = quad.map(\.x).reduce(0, +) / 4, cy = quad.map(\.y).reduce(0, +) / 4
        // Push each corner out along its bisector so the edges move out by `grow`.
        let pts: [CGPoint] = quad.indices.map { i in
            let p = quad[i], prev = quad[(i + 3) % 4], next = quad[(i + 1) % 4]
            func unit(_ v: CGVector) -> CGVector { let l = max(hypot(v.dx, v.dy), 1e-6); return CGVector(dx: v.dx / l, dy: v.dy / l) }
            let a = unit(CGVector(dx: p.x - prev.x, dy: p.y - prev.y)), b = unit(CGVector(dx: next.x - p.x, dy: next.y - p.y))
            // Outward normals of the two edges (the quad runs counter-clockwise).
            let na = CGVector(dx: a.dy, dy: -a.dx), nb = CGVector(dx: b.dy, dy: -b.dx)
            var bis = CGVector(dx: na.dx + nb.dx, dy: na.dy + nb.dy)
            let bl = max(hypot(bis.dx, bis.dy), 1e-6)
            bis = CGVector(dx: bis.dx / bl, dy: bis.dy / bl)
            let cosHalf = max(0.3, bis.dx * na.dx + bis.dy * na.dy)
            var out = CGPoint(x: p.x + bis.dx * grow / cosHalf, y: p.y + bis.dy * grow / cosHalf)
            // Make sure "out" really is away from the middle, whatever the winding.
            if hypot(out.x - cx, out.y - cy) < hypot(p.x - cx, p.y - cy) - 0.01, grow > 0 {
                out = CGPoint(x: p.x - bis.dx * grow / cosHalf, y: p.y - bis.dy * grow / cosHalf)
            }
            return out
        }
        var shortest = CGFloat.infinity
        for i in 0..<4 {
            let a = pts[i], b = pts[(i + 1) % 4]
            shortest = min(shortest, hypot(a.x - b.x, a.y - b.y))
        }
        let r = max(0, min(radius + grow, shortest / 2 - 0.5))
        let mid = CGPoint(x: (pts[3].x + pts[0].x) / 2, y: (pts[3].y + pts[0].y) / 2)
        path.move(to: mid)
        for i in 0..<4 {
            path.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % 4], radius: r)
        }
        path.closeSubpath()
        return path
    }

    // MARK: Lettering

    /// One line of text, `size` pixels, in the system typeface.
    static func line(_ text: String, size: CGFloat, weight: NSFont.Weight = .semibold, color: CGColor, tracking: CGFloat = 0) -> CTLine {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if tracking != 0 { attributes[.kern] = tracking }
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    static func width(of line: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }

    /// Draws a line of text centred on `center`.
    static func draw(_ line: CTLine, centeredAt center: CGPoint, in ctx: CGContext) {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let w = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: center.x - w / 2, y: center.y - (ascent - descent) / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// Text shortened with an ellipsis to fit `maxWidth`.
    static func fitted(_ text: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, maxWidth: CGFloat) -> CTLine {
        let full = line(text, size: size, weight: weight, color: color)
        guard width(of: full) > maxWidth else { return full }
        let ellipsis = line("…", size: size, weight: weight, color: color)
        return CTLineCreateTruncatedLine(full, Double(maxWidth), .end, ellipsis) ?? full
    }

    // MARK: Pills

    /// A small frosted capsule with text in it, as used for the size readout and the panel's label.
    static func pill(_ text: String, at center: CGPoint, size: CGFloat, in ctx: CGContext, fill: CGColor = black(0.58),
                     textColor: CGColor = white(0.95), rim: CGColor? = white(0.16), maxWidth: CGFloat = 900) {
        let l = fitted(text, size: size, weight: .semibold, color: textColor, maxWidth: maxWidth)
        let w = width(of: l) + size * 1.3, h = size * 1.85
        let r = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        let path = CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.08), blur: size * 0.5, color: black(0.3))
        ctx.addPath(path)
        ctx.setFillColor(fill)
        ctx.fillPath()
        ctx.restoreGState()
        if let rim {
            ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: h / 2 - 0.5, cornerHeight: h / 2 - 0.5, transform: nil))
            ctx.setStrokeColor(rim)
            ctx.setLineWidth(1)
            ctx.strokePath()
        }
        draw(l, centeredAt: CGPoint(x: center.x, y: center.y + size * 0.02), in: ctx)
    }

    // MARK: Glyphs for the cards

    /// Two rounded bars.
    static func pauseGlyph(at c: CGPoint, height h: CGFloat, in ctx: CGContext, color: CGColor) {
        let w = h * 0.26, gap = h * 0.24
        ctx.setFillColor(color)
        for side in [-1.0, 1.0] {
            let x = c.x + CGFloat(side) * (gap / 2 + w / 2) - w / 2
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: c.y - h / 2, width: w, height: h), cornerWidth: w * 0.42, cornerHeight: w * 0.42, transform: nil))
            ctx.fillPath()
        }
    }

    /// A window outline with a line through it.
    static func lostWindowGlyph(at c: CGPoint, width w: CGFloat, in ctx: CGContext, color: CGColor) {
        let h = w * 0.72
        let r = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        let line = max(1.5, w * 0.06)
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(line)
        ctx.setLineCap(.round)
        ctx.addPath(continuousRect(r, radius: w * 0.12))
        ctx.strokePath()
        // The title bar.
        ctx.move(to: CGPoint(x: r.minX + line, y: r.maxY - h * 0.24))
        ctx.addLine(to: CGPoint(x: r.maxX - line, y: r.maxY - h * 0.24))
        ctx.strokePath()
        for k in 0..<3 {
            ctx.setFillColor(color)
            let d = w * 0.06
            ctx.fillEllipse(in: CGRect(x: r.minX + w * 0.09 + CGFloat(k) * d * 1.7, y: r.maxY - h * 0.12 - d / 2, width: d, height: d))
        }
        // The slash, with a gap cut either side of it so it reads against the outline.
        ctx.setBlendMode(.clear)
        ctx.setLineWidth(line * 3)
        ctx.move(to: CGPoint(x: r.minX - w * 0.04, y: r.maxY + h * 0.08))
        ctx.addLine(to: CGPoint(x: r.maxX + w * 0.04, y: r.minY - h * 0.08))
        ctx.strokePath()
        ctx.setBlendMode(.normal)
        ctx.setLineWidth(line)
        ctx.move(to: CGPoint(x: r.minX - w * 0.04, y: r.maxY + h * 0.08))
        ctx.addLine(to: CGPoint(x: r.maxX + w * 0.04, y: r.minY - h * 0.08))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// A screen with a lock-like eye closed: Screen Recording is not allowed.
    static func blockedGlyph(at c: CGPoint, width w: CGFloat, in ctx: CGContext, color: CGColor) {
        let h = w * 0.64
        let r = CGRect(x: c.x - w / 2, y: c.y - h / 2 + w * 0.06, width: w, height: h)
        let line = max(1.5, w * 0.06)
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(line)
        ctx.setLineCap(.round)
        ctx.addPath(continuousRect(r, radius: w * 0.1))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: c.x - w * 0.18, y: r.minY - w * 0.16))
        ctx.addLine(to: CGPoint(x: c.x + w * 0.18, y: r.minY - w * 0.16))
        ctx.strokePath()
        // A closed eye: an arc with lashes.
        let eye = CGPoint(x: c.x, y: r.midY + h * 0.06)
        ctx.addArc(center: CGPoint(x: eye.x, y: eye.y + w * 0.16), radius: w * 0.24, startAngle: -.pi * 0.78, endAngle: -.pi * 0.22, clockwise: false)
        ctx.strokePath()
        for k in -1...1 {
            let a = -Double.pi / 2 + Double(k) * 0.42
            let p0 = CGPoint(x: eye.x + CGFloat(cos(a)) * w * 0.24, y: eye.y + w * 0.16 + CGFloat(sin(a)) * w * 0.24)
            let p1 = CGPoint(x: eye.x + CGFloat(cos(a)) * w * 0.33, y: eye.y + w * 0.16 + CGFloat(sin(a)) * w * 0.33)
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}

/// What the shared screen is doing, when it is not simply showing.
enum StageContentStatus: Equatable {
    /// Frames are arriving.
    case live
    /// Waiting for the first frame.
    case starting
    /// You paused sharing.
    case paused
    /// The window closed or the screen went away.
    case lost
    /// Screen Recording is not allowed.
    case denied
}

/// The calm cards shown in place of the screen when it is paused, gone, or not allowed. Viewers see these, so they say what is
/// happening in a few plain words and never show anything of the screen itself beyond a heavy blur of its colours.
enum StageCards {
    /// Draws the card for `status` filling `size`. `frozen` is a blurred picture of the screen as it was, for the paused card.
    static func draw(_ status: StageContentStatus, size: CGSize, title: String?, frozen: CGImage?, in ctx: CGContext) {
        let rect = CGRect(origin: .zero, size: size)
        let h = size.height
        let colors = [StageArt.color(StageArt.slateTop), StageArt.color(StageArt.slateBottom)] as CFArray
        if let g = CGGradient(colorsSpace: StageArt.space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: size.width * 0.3, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        if status == .paused, let frozen {
            // Dark frosted glass with only a breath of the screen's colours behind it: calm, and nothing on it can be read.
            ctx.saveGState()
            ctx.interpolationQuality = .high
            ctx.setAlpha(0.16)
            ctx.draw(frozen, in: rect)
            ctx.restoreGState()
        }
        // A soft pool of light behind the glyph.
        let glow = [StageArt.white(0.07), StageArt.white(0)] as CFArray
        if let g = CGGradient(colorsSpace: StageArt.space, colors: glow, locations: [0, 1]) {
            let c = CGPoint(x: size.width / 2, y: h * 0.56)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: min(size.width, h) * 0.6, options: [])
        }
        guard status != .live else { return }

        let unit = min(h, size.width * 0.6)
        let titleSize = max(11, min(34, unit * 0.068))
        let subtitleSize = titleSize * 0.62
        let glyphCenter = CGPoint(x: size.width / 2, y: h * 0.56)
        let ink = StageArt.white(0.94)

        switch status {
        case .paused:
            let r = unit * 0.11
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -r * 0.08), blur: r * 0.5, color: StageArt.black(0.35))
            ctx.setFillColor(StageArt.white(0.16))
            ctx.fillEllipse(in: CGRect(x: glyphCenter.x - r, y: glyphCenter.y - r, width: r * 2, height: r * 2))
            ctx.restoreGState()
            ctx.setStrokeColor(StageArt.white(0.38))
            ctx.setLineWidth(max(1, r * 0.035))
            ctx.strokeEllipse(in: CGRect(x: glyphCenter.x - r, y: glyphCenter.y - r, width: r * 2, height: r * 2).insetBy(dx: 0.5, dy: 0.5))
            StageArt.pauseGlyph(at: glyphCenter, height: r * 0.78, in: ctx, color: ink)
        case .lost:
            StageArt.lostWindowGlyph(at: glyphCenter, width: unit * 0.2, in: ctx, color: StageArt.white(0.78))
        case .denied:
            StageArt.blockedGlyph(at: glyphCenter, width: unit * 0.2, in: ctx, color: StageArt.white(0.78))
        case .starting:
            // Three soft dots: on its way.
            for k in -1...1 {
                let d = unit * 0.022
                ctx.setFillColor(StageArt.white(k == 0 ? 0.55 : 0.32))
                ctx.fillEllipse(in: CGRect(x: glyphCenter.x + CGFloat(k) * d * 2.6 - d / 2, y: glyphCenter.y - d / 2, width: d, height: d))
            }
        case .live:
            break
        }

        let words: (String, String?) = {
            switch status {
            case .paused: return ("Paused", "Back in a moment")
            case .lost: return (title.map { "\($0) closed" } ?? "The window closed", "It will appear here again when it’s open")
            case .denied: return ("Screen sharing is off", "Allow Backdrop under Screen Recording in System Settings")
            case .starting: return ("Starting…", nil)
            case .live: return ("", nil)
            }
        }()
        let baseline = glyphCenter.y - unit * (status == .starting ? 0.08 : 0.2)
        let maxWidth = size.width * 0.86
        StageArt.draw(StageArt.fitted(words.0, size: titleSize, weight: .semibold, color: ink, maxWidth: maxWidth),
                      centeredAt: CGPoint(x: size.width / 2, y: baseline), in: ctx)
        if let sub = words.1 {
            StageArt.draw(StageArt.fitted(sub, size: subtitleSize, weight: .regular, color: StageArt.white(0.62), maxWidth: maxWidth),
                          centeredAt: CGPoint(x: size.width / 2, y: baseline - titleSize * 1.25), in: ctx)
        }
    }
}
