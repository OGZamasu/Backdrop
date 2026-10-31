import AppKit
import CoreGraphics

/// The colours every body game draws its words and meters in, so the eleven of them read as one family.
/// Warm, soft and never a pure primary: they hold up over skin, a white shirt, a dark hoodie and any backdrop.
enum BodyGamePalette {
    /// Words and numbers.
    static let cream = NSColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1)
    /// The dark behind words: pills, outlines, shadows.
    static let ink = NSColor(red: 0.07, green: 0.07, blue: 0.13, alpha: 1)
    /// Points, records, treasure.
    static let gold = NSColor(red: 1.0, green: 0.83, blue: 0.33, alpha: 1)
    /// Good news: a pass, a save, a fit.
    static let mint = NSColor(red: 0.45, green: 0.94, blue: 0.68, alpha: 1)
    /// Bad news: a hit, a miss, a life gone.
    static let coral = NSColor(red: 1.0, green: 0.45, blue: 0.42, alpha: 1)
    /// Calm information and shields.
    static let sky = NSColor(red: 0.45, green: 0.84, blue: 1.0, alpha: 1)
    static let violet = NSColor(red: 0.72, green: 0.58, blue: 1.0, alpha: 1)
    static let tangerine = NSColor(red: 1.0, green: 0.64, blue: 0.28, alpha: 1)

    /// The same colour as Core Graphics wants it, with an alpha.
    static func cg(_ colour: NSColor, _ alpha: CGFloat = 1) -> CGColor {
        let c = colour.usingColorSpace(.sRGB) ?? colour
        return CGColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: alpha * c.alphaComponent)
    }

    /// Red, green and blue of a palette colour, 0...1.
    static func rgb(_ colour: NSColor) -> (Double, Double, Double) {
        let c = colour.usingColorSpace(.sRGB) ?? colour
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }
}

/// Easing curves for the body games. Nothing in them moves in a straight line or pops.
enum BodyEase {
    static func outCubic(_ t: Double) -> Double { let u = 1 - bodyClamp(t, 0, 1); return 1 - u * u * u }
    static func inOutSine(_ t: Double) -> Double { 0.5 - 0.5 * cos(.pi * bodyClamp(t, 0, 1)) }
    /// Overshoots a little and settles back: for things arriving.
    static func outBack(_ t: Double, overshoot s: Double = 1.70158) -> Double {
        let u = bodyClamp(t, 0, 1) - 1
        return 1 + (s + 1) * u * u * u + s * u * u
    }
    /// A springy settle: for a jolt that rings out.
    static func outElastic(_ t: Double) -> Double {
        let t = bodyClamp(t, 0, 1)
        guard t > 0, t < 1 else { return t }
        return pow(2, -10 * t) * sin((t * 10 - 0.75) * (2 * .pi / 3)) + 1
    }
}

/// The words, meters and flashes the body games draw in their own worlds, in the shared game look (`GameUIType`, `GameUIPlate`).
///
/// The score, hearts, clock and combo are not here: every game shows those on the shared plates (`GameScreens`), from its `readout`.
/// What is left is unique to a game: a prompt at the top middle ("CROUCH!"), a meter for how well a pose fits, words that pop out of
/// the world, a soft wash of colour when something hurts.
enum BodyGameHUD {
    /// Where a prompt sits: top middle, between the plates.
    static func promptCenter(_ size: CGSize) -> CGPoint { GameScreens.calloutCenter(size) }
    /// Where a game's own meter sits: low in the middle, above the band the hints use.
    static func meterCenter(_ size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: GameScreens.margin.height + GameScreens.pillHeight + 54) }

    // MARK: Words

    /// The rounded heavy system face.
    static func font(_ size: CGFloat, weight: NSFont.Weight = .heavy) -> NSFont { GameUIType.font(size, weight: weight) }

    /// How wide a line comes out.
    static func width(of string: String, size: CGFloat, weight: NSFont.Weight = .heavy) -> CGFloat { GameUIType.width(string, size: size, weight: weight) }

    private static func tone(_ colour: NSColor) -> SIMD3<Double> {
        let (r, g, b) = BodyGamePalette.rgb(colour)
        return SIMD3(r, g, b)
    }

    /// A line of text centred on a point, in the shared game type. Sizes snap to whole points, so words that grow as they pop in reuse a
    /// handful of baked pictures.
    static func text(_ ctx: CGContext, _ string: String, center: CGPoint, size: CGFloat, color: NSColor = BodyGamePalette.cream,
                     weight: NSFont.Weight = .heavy, alpha: CGFloat = 1) {
        guard alpha > 0.01, size > 2, !string.isEmpty else { return }
        let base = (size / 4).rounded(.up) * 4
        GameUIType.draw(ctx, string, at: center, size: base, color: tone(color), weight: weight, alpha: alpha, scale: size / base)
    }

    /// Text on a plate, for a prompt or a reading that sits over a busy picture. `accent` rims the plate in a colour. Numbers in the
    /// text are put together from single characters, so a reading that changes every frame ("FIT 72%") never bakes a new picture.
    static func pill(_ ctx: CGContext, _ string: String, center: CGPoint, size: CGFloat, color: NSColor = BodyGamePalette.cream,
                     accent: NSColor? = nil, alpha: CGFloat = 1) {
        guard alpha > 0.01 else { return }
        let base = (size / 4).rounded(.up) * 4
        let textWidth = GameUIType.mixedWidth(string, size: base)
        let w = textWidth + base * 1.2, h = base * 1.6
        ctx.saveGState()
        if alpha < 0.995 { ctx.setAlpha(alpha) }
        if abs(size / base - 1) > 0.004 {
            ctx.translateBy(x: center.x, y: center.y)
            ctx.scaleBy(x: size / base, y: size / base)
            ctx.translateBy(x: -center.x, y: -center.y)
        }
        GameUIPlate.draw(ctx, CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h), radius: h / 2, opacity: 0.8, rim: accent.map(tone))
        GameUIType.mixed(ctx, string, at: CGPoint(x: center.x - textWidth / 2, y: center.y), size: base, color: tone(color))
        ctx.restoreGState()
    }

    /// A big word that springs in, holds and fades in the band at the top middle: "PERFECT!", "LEVEL 2". `age` is seconds since it
    /// appeared.
    static func banner(_ ctx: CGContext, _ string: String, age: Double, size: CGSize, color: NSColor = BodyGamePalette.gold, life: Double = 1.2) {
        GameScreens.callout(ctx, size: size, text: string, age: age, tone: tone(color), life: life, textSize: 52)
    }

    // MARK: Meters

    /// A rounded bar, filled to `fraction`, with an optional mark (0...1) for "good enough".
    static func meter(_ ctx: CGContext, center: CGPoint, width: CGFloat, fraction: Double, color: NSColor, mark: Double? = nil,
                      height: CGFloat = 14, alpha: CGFloat = 1) {
        guard alpha > 0.01 else { return }
        let track = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.addPath(CGPath(roundedRect: track.insetBy(dx: -4, dy: -4), cornerWidth: height / 2 + 4, cornerHeight: height / 2 + 4, transform: nil))
        ctx.setFillColor(BodyGamePalette.cg(BodyGamePalette.ink, 0.62))
        ctx.fillPath()
        let f = bodyClamp(fraction, 0, 1)
        if f > 0.005 {
            let filled = CGRect(x: track.minX, y: track.minY, width: max(height, track.width * CGFloat(f)), height: height)
            let path = CGPath(roundedRect: filled, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let (r, g, b) = BodyGamePalette.rgb(color)
            let colors = [CGColor(red: min(1, r + 0.25), green: min(1, g + 0.25), blue: min(1, b + 0.25), alpha: 1),
                          CGColor(red: r, green: g, blue: b, alpha: 1), CGColor(red: r * 0.72, green: g * 0.72, blue: b * 0.72, alpha: 1)] as CFArray
            if let gradient = CGGradient(colorsSpace: GameUISprites.space, colors: colors, locations: [0, 0.45, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: filled.maxY), end: CGPoint(x: 0, y: filled.minY), options: [])
            }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.3))
            ctx.fill(CGRect(x: filled.minX + height * 0.4, y: filled.maxY - height * 0.38, width: max(0, filled.width - height * 0.8), height: height * 0.18))
            ctx.restoreGState()
        }
        if let mark {
            let x = track.minX + track.width * CGFloat(bodyClamp(mark, 0, 1))
            ctx.addPath(CGPath(roundedRect: CGRect(x: x - 2, y: track.minY - 6, width: 4, height: height + 12), cornerWidth: 2, cornerHeight: 2, transform: nil))
            ctx.setFillColor(BodyGamePalette.cg(BodyGamePalette.cream, 0.95))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    // MARK: Flashes and shakes

    /// A soft wash of colour round the edges of the picture: the "ouch". Kept gentle: other people are watching the video.
    static func flash(_ ctx: CGContext, size: CGSize, color: NSColor = BodyGamePalette.coral, strength: Double) {
        let a = bodyClamp(strength, 0, 1) * 0.3
        guard a > 0.01 else { return }
        let (r, g, b) = BodyGamePalette.rgb(color)
        let colors = [CGColor(red: r, green: g, blue: b, alpha: 0), CGColor(red: r, green: g, blue: b, alpha: CGFloat(a))] as CFArray
        guard let gradient = CGGradient(colorsSpace: GameUISprites.space, colors: colors, locations: [0, 1]) else { return }
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        ctx.drawRadialGradient(gradient, startCenter: middle, startRadius: min(size.width, size.height) * 0.36,
                               endCenter: middle, endRadius: hypot(size.width, size.height) / 2, options: [.drawsAfterEndLocation])
    }

    /// How far to nudge the picture for a shake that rings out smoothly over `left` of `total` seconds.
    static func shake(left: Double, total: Double, time: Double, amplitude: Double = 9) -> CGSize {
        guard left > 0, total > 0 else { return .zero }
        let k = bodyClamp(left / total, 0, 1)
        let s = amplitude * k * k
        return CGSize(width: sin(time * 47) * s, height: cos(time * 39) * s * 0.7)
    }
}

/// Soft light for the body games.
enum BodyGlow {
    /// A soft round glow stamped from a cached sprite, far cheaper than a fresh gradient each frame. A big one is drawn as a real
    /// gradient instead, since a small sprite blown up that far shows its steps.
    static func stamp(_ ctx: CGContext, at center: CGPoint, radius: CGFloat, red: Double, green: Double, blue: Double, alpha: Double) {
        guard radius > 0.5, alpha > 0.004 else { return }
        if radius > 160 {
            ctx.glow(center: center, radius: radius, red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(min(1, alpha * 0.8)))
            return
        }
        guard let dot = Sprites.dot(red: (red * 20).rounded() / 20, green: (green * 20).rounded() / 20, blue: (blue * 20).rounded() / 20) else { return }
        ctx.stampDot(dot, at: center, radius: Double(radius), alpha: alpha)
    }

    static func stamp(_ ctx: CGContext, at center: CGPoint, radius: CGFloat, color: NSColor, alpha: Double) {
        let (r, g, b) = BodyGamePalette.rgb(color)
        stamp(ctx, at: center, radius: radius, red: r, green: g, blue: b, alpha: alpha)
    }
}

/// Shapes the body games build their art from.
enum BodyShapes {
    /// A five-pointed star, point up.
    static func star(center: CGPoint, radius: CGFloat, rotation: CGFloat = 0, inner: CGFloat = 0.45) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<10 {
            let r = i % 2 == 0 ? radius : radius * inner
            let a = rotation + .pi / 2 + CGFloat(i) * .pi / 5
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// A linear gradient from three colours, top to bottom of `rect`.
    static func fillVertical(_ ctx: CGContext, _ rect: CGRect, top: CGColor, middle: CGColor, bottom: CGColor) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let g = CGGradient(colorsSpace: space, colors: [top, middle, bottom] as CFArray, locations: [0, 0.5, 1]) else { return }
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// A radial gradient lit from the top left of `rect`: highlight, body, shade.
    static func fillLit(_ ctx: CGContext, _ rect: CGRect, light: CGColor, body: CGColor, shade: CGColor, lightAt: CGPoint? = nil) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let g = CGGradient(colorsSpace: space, colors: [light, body, shade] as CFArray, locations: [0, 0.48, 1]) else { return }
        let from = lightAt ?? CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.7)
        ctx.drawRadialGradient(g, startCenter: from, startRadius: 0, endCenter: CGPoint(x: rect.midX, y: rect.midY),
                               endRadius: max(rect.width, rect.height) * 0.62, options: [.drawsAfterEndLocation])
    }
}

extension NSColor {
    /// This colour mixed toward white (positive) or black (negative) by `amount`, 0...1.
    func bodyShade(_ amount: Double) -> CGColor {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Double(c.redComponent), g = Double(c.greenComponent), b = Double(c.blueComponent)
        if amount >= 0 {
            return CGColor(red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount, alpha: 1)
        }
        let k = 1 + amount
        return CGColor(red: r * k, green: g * k, blue: b * k, alpha: 1)
    }
}
