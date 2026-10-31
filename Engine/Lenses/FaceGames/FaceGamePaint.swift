import AppKit
import CoreGraphics
import simd

/// Colours, shapes and bold text shared by the face games, so each game file is only its rules and its look.
enum FaceGamePaint {
    typealias Tone = SIMD3<Double>

    static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    // MARK: Colour and numbers

    static func cg(_ tone: Tone, _ alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat(tone.x), CGFloat(tone.y), CGFloat(tone.z), CGFloat(alpha)])
            ?? CGColor(gray: 1, alpha: CGFloat(alpha))
    }

    static func mix(_ a: Tone, _ b: Tone, _ t: Double) -> Tone { a + (b - a) * min(1, max(0, t)) }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * min(1, max(0, t)) }

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// 0 below `a`, 1 above `b`, an S-shaped ramp between (also works when `a` is the larger).
    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard a != b else { return x < a ? 0 : 1 }
        let t = clamp01((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }

    /// A colour for a hue in 0...1 (wraps around).
    static func hsv(_ hue: Double, _ saturation: Double = 0.85, _ value: Double = 1) -> Tone {
        guard hue.isFinite else { return Tone(value, value, value) }
        let h = (hue - hue.rounded(.down)) * 6
        let i = Int(h) % 6
        let f = h - h.rounded(.down)
        let p = value * (1 - saturation), q = value * (1 - saturation * f), t = value * (1 - saturation * (1 - f))
        switch i {
        case 0: return Tone(value, t, p)
        case 1: return Tone(q, value, p)
        case 2: return Tone(p, value, t)
        case 3: return Tone(p, q, value)
        case 4: return Tone(t, p, value)
        default: return Tone(value, p, q)
        }
    }

    /// A repeatable "random" number in 0..<1 for an index, so scenery can vary without keeping any state.
    static func hash(_ n: Int, _ salt: Double = 0) -> Double {
        let x = sin(Double(n) * 12.9898 + salt * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    static func wrap(_ x: Double, _ period: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: period)
        return r < 0 ? r + period : r
    }

    // MARK: Shapes

    static func roundedPath(_ rect: CGRect, radius: Double) -> CGPath {
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    static func fill(_ ctx: CGContext, rounded rect: CGRect, radius: Double, color: CGColor) {
        ctx.addPath(roundedPath(rect, radius: radius))
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    static func stroke(_ ctx: CGContext, rounded rect: CGRect, radius: Double, color: CGColor, width: Double) {
        ctx.addPath(roundedPath(rect, radius: radius))
        ctx.setStrokeColor(color)
        ctx.setLineWidth(CGFloat(width))
        ctx.strokePath()
    }

    /// A shape with an edge: the edge is drawn first, wide, then the colour on top, so the outline has no seams.
    static func outlined(_ ctx: CGContext, path: CGPath, fill: CGColor, edge: CGColor, edgeWidth: Double = 8) {
        ctx.saveGState()
        ctx.setLineJoin(.round)
        ctx.setLineWidth(CGFloat(edgeWidth))
        ctx.setStrokeColor(edge)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.setFillColor(fill)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// The player's face picture inside a circle or rounded square. Before there is a picture, a drawn stand-in face is used.
    static func drawFace(_ ctx: CGContext, crop: CGImage?, in rect: CGRect, corner: Double, fallback: String = "") {
        ctx.saveGState()
        ctx.addPath(roundedPath(rect, radius: corner))
        ctx.clip()
        if let crop {
            ctx.interpolationQuality = .low
            ctx.draw(crop, in: rect)
            // A little light from the top left and shade to the bottom right, so the picture sits in the art instead of on it.
            if let g = CGGradient(colorsSpace: space, colors: [cg(Tone(1, 1, 1), 0.16), cg(Tone(1, 1, 1), 0), cg(FaceGamePalette.ink, 0.28)] as CFArray,
                                  locations: [0, 0.45, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
            }
        } else {
            FaceGameMascot.draw(ctx, in: rect, mood: fallback == "😵" ? .dizzy : .happy)
        }
        ctx.restoreGState()
    }

    /// A soft coloured dot, for sparks and bulbs.
    static func spark(_ ctx: CGContext, at p: CGPoint, radius: Double, tone: Tone, alpha: Double) {
        guard let dot = Sprites.dot(red: (tone.x * 10).rounded() / 10, green: (tone.y * 10).rounded() / 10, blue: (tone.z * 10).rounded() / 10) else { return }
        let quality = ctx.interpolationQuality
        ctx.interpolationQuality = .low
        ctx.stampDot(dot, at: p, radius: radius, alpha: alpha)
        ctx.interpolationQuality = quality
    }

    // MARK: Text

    /// The face games' one typeface: the system font in its rounded design, so every word in every game reads as one family.
    static func roundedFont(size: CGFloat, weight: NSFont.Weight = .heavy, monospacedDigits: Bool = false) -> NSFont {
        let base = monospacedDigits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: size) ?? base
    }

    /// Big text with a dark edge and a soft shadow, readable over any picture and after a video call has squashed it.
    ///
    /// Words are drawn once into a small picture and kept, because laying out text is slow next to stamping a picture. Pass
    /// `cached: false` for text that changes every frame, like a clock.
    static func sticker(_ ctx: CGContext, _ string: String, center: CGPoint, size: CGFloat, fill: NSColor = .white,
                        edge: NSColor = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.16, alpha: 1), edgeWidth: CGFloat = 10, rotation: CGFloat = 0,
                        scale: CGFloat = 1, cached: Bool = true) {
        guard let picture = stickerPicture(string, size: size, fill: fill, edge: edge, edgeWidth: edgeWidth, cached: cached) else { return }
        if abs(scale - 1) < 0.01, rotation == 0 {
            FaceGameArt.blit(ctx, picture, at: CGPoint(x: center.x - CGFloat(picture.width) / 2, y: center.y - CGFloat(picture.height) / 2))
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: rotation)
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .low
        ctx.draw(picture, in: CGRect(x: -CGFloat(picture.width) / 2, y: -CGFloat(picture.height) / 2, width: CGFloat(picture.width), height: CGFloat(picture.height)))
        ctx.restoreGState()
    }

    enum Align { case left, center, right }

    /// A line of text placed by its left edge, middle or right edge at `point` (vertically centred). Returns how wide the words are.
    @discardableResult
    static func label(_ ctx: CGContext, _ string: String, at point: CGPoint, align: Align = .left, size: CGFloat, fill: NSColor = .white,
                      edge: NSColor = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.16, alpha: 1), edgeWidth: CGFloat = 0, scale: CGFloat = 1,
                      cached: Bool = true) -> CGFloat {
        guard let picture = stickerPicture(string, size: size, fill: fill, edge: edge, edgeWidth: edgeWidth, cached: cached) else { return 0 }
        let pad = ceil(size * edgeWidth / 100) + ceil(size * 0.16) + 4
        let wordWidth = (CGFloat(picture.width) - pad * 2) * scale
        let x: CGFloat
        switch align {
        case .left: x = point.x + wordWidth / 2
        case .center: x = point.x
        case .right: x = point.x - wordWidth / 2
        }
        if abs(scale - 1) < 0.01 {
            FaceGameArt.blit(ctx, picture, at: CGPoint(x: x - CGFloat(picture.width) / 2, y: point.y - CGFloat(picture.height) / 2))
            return wordWidth
        }
        ctx.saveGState()
        ctx.translateBy(x: x, y: point.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .low
        ctx.draw(picture, in: CGRect(x: -CGFloat(picture.width) / 2, y: -CGFloat(picture.height) / 2, width: CGFloat(picture.width), height: CGFloat(picture.height)))
        ctx.restoreGState()
        return wordWidth
    }

    /// How wide a line of text comes out, without the edge or shadow.
    static func textWidth(_ string: String, size: CGFloat) -> CGFloat {
        NSAttributedString(string: string, attributes: [.font: roundedFont(size: size, weight: .black)]).size().width
    }

    private static let stickerLock = NSLock()
    private static var stickerCache: [String: CGImage] = [:]

    private static func stickerPicture(_ string: String, size: CGFloat, fill: NSColor, edge: NSColor, edgeWidth: CGFloat, cached: Bool) -> CGImage? {
        func code(_ color: NSColor) -> String {
            let c = color.usingColorSpace(.sRGB) ?? color
            return String(format: "%02x%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255), Int(c.alphaComponent * 255))
        }
        let key = "\(string)|\(Int(size))|\(code(fill))|\(code(edge))|\(Int(edgeWidth))"
        if cached {
            stickerLock.lock(); defer { stickerLock.unlock() }
            if let hit = stickerCache[key] { return hit }
        }
        let font = roundedFont(size: size, weight: .black)
        let body = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: fill])
        let outline = NSAttributedString(string: string, attributes: [.font: font, .strokeColor: edge, .strokeWidth: edgeWidth])
        let box = body.size()
        // Room for the edge and for a soft shadow that falls down and to the right, away from the light.
        let pad = ceil(size * edgeWidth / 100) + ceil(size * 0.16) + 4
        let width = Int(ceil(box.width + pad * 2)), height = Int(ceil(box.height + pad * 2))
        guard width > 0, height > 0, let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                         space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ctx.setShadow(offset: CGSize(width: size * 0.03, height: -size * 0.06), blur: size * 0.14,
                      color: CGColor(colorSpace: space, components: [0.02, 0.02, 0.08, 0.6]))
        if edgeWidth > 0 { outline.draw(at: NSPoint(x: pad, y: pad)) } else { body.draw(at: NSPoint(x: pad, y: pad)) }
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        body.draw(at: NSPoint(x: pad, y: pad))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return nil }
        if cached {
            stickerLock.lock(); defer { stickerLock.unlock() }
            if stickerCache.count > 240 { stickerCache.removeAll() }
            stickerCache[key] = image
        }
        return image
    }

    static func nsColor(_ tone: Tone, _ alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(tone.x), green: CGFloat(tone.y), blue: CGFloat(tone.z), alpha: CGFloat(alpha))
    }

    // MARK: Meters

    /// A horizontal meter: a dark rounded track with a lit fill that shifts colour as it fills, and a glossy top half.
    static func meter(_ ctx: CGContext, in rect: CGRect, fill amount: Double, from: Tone, to: Tone) {
        fill(ctx, rounded: rect.insetBy(dx: -5, dy: -5), radius: rect.height, color: cg(FaceGamePalette.ink, 0.78))
        stroke(ctx, rounded: rect.insetBy(dx: -5, dy: -5), radius: rect.height, color: cg(Tone(1, 1, 1), 0.14), width: 1.5)
        let width = max(rect.height, rect.width * clamp01(amount))
        let bar = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        guard amount > 0.001 else { return }
        ctx.saveGState()
        ctx.addPath(roundedPath(bar, radius: rect.height / 2))
        ctx.clip()
        if let g = CGGradient(colorsSpace: space, colors: [cg(from), cg(mix(from, to, clamp01(amount)))] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.minX + max(1, width), y: 0), options: [])
        }
        ctx.setFillColor(cg(Tone(1, 1, 1), 0.26))
        ctx.fill(CGRect(x: bar.minX, y: bar.midY + bar.height * 0.08, width: bar.width, height: bar.height * 0.32))
        ctx.restoreGState()
    }

    // MARK: Floating words

    static func advance(_ floaters: inout [FaceGameFloater], by dt: Double) {
        for i in floaters.indices {
            floaters[i].age += dt
            // Quick off the mark, then easing to a stop: the word pops up rather than sliding at a steady speed.
            floaters[i].position.y += floaters[i].rise * dt * 2.2 * exp(-3 * floaters[i].age)
        }
        floaters.removeAll { $0.age >= $0.life }
    }

    static func draw(_ floaters: [FaceGameFloater], in ctx: CGContext) {
        for f in floaters {
            let t = f.age / max(f.life, 1e-6)
            ctx.setAlpha(CGFloat(1 - smoothstep(0.6, 1, t)))
            let pop = FaceGameEase.backOut(min(1, f.age / 0.22), overshoot: 2.6)
            sticker(ctx, f.text, center: CGPoint(x: f.position.x, y: f.position.y), size: f.size, fill: nsColor(f.tone),
                    edgeWidth: 9, scale: CGFloat(0.4 + 0.6 * pop))
        }
        ctx.setAlpha(1)
    }
}

/// A word that pops up where something happened, drifts up and fades.
struct FaceGameFloater {
    var text: String
    var position: SIMD2<Double>
    var tone: FaceGamePaint.Tone
    var size: CGFloat = 52
    var life = 0.9
    var rise = 90.0
    var age = 0.0
}
