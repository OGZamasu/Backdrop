import AppKit
import CoreGraphics
import simd

// MARK: - Colour

/// A colour in the HandPlay family, kept as plain sRGB numbers so it can be mixed, lightened and handed to any drawing call.
struct HandPlayTone: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func cg(_ alpha: Double = 1) -> CGColor { CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(alpha)) }
    func ns(_ alpha: Double = 1) -> NSColor { NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(alpha)) }

    func mixed(with other: HandPlayTone, _ t: Double) -> HandPlayTone {
        let k = min(1, max(0, t))
        return HandPlayTone(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }

    func lighter(_ t: Double) -> HandPlayTone { mixed(with: HandPlayTone(1, 1, 1), t) }
    func darker(_ t: Double) -> HandPlayTone { mixed(with: HandPlayPalette.ink, t) }

    /// A short name for sprite caches.
    var key: String { String(format: "%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255)) }
}

/// The palette the HandPlay games are painted from. Each game names its own colours from these, so side by side they read as one family.
/// Nothing is a pure primary, and the dark is a deep blue-violet rather than black, so shadows sit softly on any picture.
enum HandPlayPalette {
    /// Outlines, shadows and the dark of a banner.
    static let ink = HandPlayTone(0.07, 0.06, 0.16)
    static let dusk = HandPlayTone(0.19, 0.14, 0.38)
    static let cream = HandPlayTone(1.0, 0.97, 0.9)
    static let gold = HandPlayTone(1.0, 0.8, 0.27)
    static let ember = HandPlayTone(1.0, 0.47, 0.17)
    static let coral = HandPlayTone(1.0, 0.4, 0.42)
    static let rose = HandPlayTone(0.98, 0.42, 0.68)
    static let violet = HandPlayTone(0.6, 0.43, 1.0)
    static let sky = HandPlayTone(0.3, 0.7, 1.0)
    static let mint = HandPlayTone(0.27, 0.87, 0.66)
    static let ice = HandPlayTone(0.78, 0.93, 1.0)
}

// MARK: - Easing

/// The curves every HandPlay animation is timed with, so nothing moves in a straight line or pops.
enum HandPlayEase {
    static func clamp(_ t: Double) -> Double { min(1, max(0, t)) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * clamp(t) }

    static func outCubic(_ t: Double) -> Double {
        let u = 1 - clamp(t)
        return 1 - u * u * u
    }

    static func inOutCubic(_ t: Double) -> Double {
        let x = clamp(t)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// Runs a little past the end and settles back: for things that arrive.
    static func outBack(_ t: Double, overshoot s: Double = 1.70158) -> Double {
        let u = clamp(t) - 1
        return 1 + (s + 1) * u * u * u + s * u * u
    }

    /// A damped spring from 0 to 1: overshoots, wobbles once or twice, settles.
    static func spring(_ t: Double, frequency: Double = 16, damping: Double = 7) -> Double {
        t <= 0 ? 0 : 1 - exp(-damping * t) * cos(frequency * t)
    }

    /// Rises to 1 over `rise` seconds, holds, and falls back to 0 over the last `fall` seconds of `life`.
    static func envelope(_ age: Double, life: Double, rise: Double, fall: Double) -> Double {
        guard age >= 0, age <= life else { return 0 }
        return min(outCubic(age / max(rise, 1e-6)), clamp((life - age) / max(fall, 1e-6)))
    }

    /// How far a value moves toward a target this frame when it follows with time constant `tau`.
    static func follow(_ dt: Double, tau: Double) -> Double { 1 - exp(-max(0, dt) / max(tau, 1e-6)) }
}

// MARK: - Baked pictures

/// Pictures the HandPlay games draw once and stamp every frame after, keyed by what they show and the size they were drawn at.
enum HandPlaySprites {
    private static let lock = NSLock()
    private struct Entry { var image: CGImage; var used: Int }
    private static var cache: [String: Entry] = [:]
    private static var pixels = 0
    private static var clock = 0
    /// How many pictures have been painted, and how long that took in all, in seconds: for tests that watch for hitches.
    private(set) static var baked = 0
    private(set) static var bakeTime = 0.0
    /// The last few pictures that took more than 4 ms to paint, for diagnosing a hitch.
    private(set) static var slowest: [(key: String, seconds: Double)] = []
    /// Roughly 64 MB of pictures. Past that, the ones that have gone unused longest are let go (they can always be painted again).
    static let budget = 16_000_000

    static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// The picture for `key`, painted by `paint` the first time it is asked for. `paint` gets a context whose origin is the middle of
    /// the picture, y up, one unit a pixel.
    static func image(_ key: String, width: Int, height: Int, paint: (CGContext) -> Void) -> CGImage? {
        lock.lock()
        clock += 1
        if let hit = cache[key] {
            cache[key]?.used = clock
            lock.unlock()
            return hit.image
        }
        lock.unlock()
        let started = CFAbsoluteTimeGetCurrent()
        guard width > 0, height > 0, width < 4096, height < 4096,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: Sprites.bitmapInfo) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        paint(ctx)
        guard let image = ctx.makeImage() else { return nil }
        lock.lock()
        baked += 1
        let took = CFAbsoluteTimeGetCurrent() - started
        bakeTime += took
        if took > 0.004 {
            slowest.append((key, took))
            if slowest.count > 24 { slowest.removeFirst() }
        }
        pixels += width * height
        cache[key] = Entry(image: image, used: clock)
        if pixels > budget { trim() }
        lock.unlock()
        return image
    }

    /// A square picture `side` pixels across.
    static func image(_ key: String, side: Int, paint: (CGContext) -> Void) -> CGImage? { image(key, width: side, height: side, paint: paint) }

    /// Forgets every picture, so the next frame paints from scratch: for tests that measure a cold start.
    static func removeAll() {
        lock.lock()
        cache.removeAll()
        pixels = 0
        lock.unlock()
    }

    /// Lets go of the least recently used pictures until the cache is down to three quarters of its budget. Called with the lock held.
    private static func trim() {
        for (key, entry) in cache.sorted(by: { $0.value.used < $1.value.used }) {
            guard pixels > budget * 3 / 4 else { break }
            pixels -= entry.image.width * entry.image.height
            cache.removeValue(forKey: key)
        }
    }
}

/// Small drawing pieces the HandPlay games share.
///
/// Core Graphics draws a picture at its own size, on whole pixels and at full opacity almost for free (a 300-pixel glow in about 0.04 ms),
/// but anything scaled, turned, placed between pixels or faded with a global alpha goes down a path ten to thirty times slower. So
/// everything steady is baked as it is shown and stamped 1:1: glows and shadows by size and strength, turning things by angle steps, and
/// scale, turn and fade are only used for brief moments (a pop, a squash, a fade-out) and snapped away once they settle.
enum HandPlayDraw {
    /// Stamps a baked picture centred on a point at its own pixel size times `scale`, stretched by `sx`/`sy` along its own axes and turned by
    /// `rotation` radians (counter-clockwise). Unscaled and unturned, it lands on whole pixels, which is the fast path.
    static func stamp(_ ctx: CGContext, _ image: CGImage?, at p: CGPoint, scale: CGFloat = 1, sx: CGFloat = 1, sy: CGFloat = 1,
                      rotation: CGFloat = 0, alpha: CGFloat = 1) {
        guard let image, alpha > 0.003, scale > 0.001 else { return }
        let alpha = alpha > 0.985 ? 1 : alpha
        let settledScale = abs(scale - 1) < 0.006 ? 1 : scale
        let settledX = abs(sx - 1) < 0.006 ? 1 : sx, settledY = abs(sy - 1) < 0.006 ? 1 : sy
        let turn = abs(rotation) < 0.003 ? 0 : rotation
        let w = CGFloat(image.width) * settledScale, h = CGFloat(image.height) * settledScale
        ctx.saveGState()
        if alpha < 1 { ctx.setAlpha(alpha) }
        if settledScale == 1 && settledX == 1 && settledY == 1 && turn == 0 {
            ctx.draw(image, in: CGRect(x: (p.x - w / 2).rounded(), y: (p.y - h / 2).rounded(), width: w, height: h))
        } else {
            ctx.translateBy(x: p.x, y: p.y)
            if turn != 0 { ctx.rotate(by: turn) }
            if settledX != 1 || settledY != 1 { ctx.scaleBy(x: settledX, y: settledY) }
            ctx.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        }
        ctx.restoreGState()
    }

    /// A picture turned to the nearest of `steps` angles over `period` radians, baked the first time each angle is needed, so a spinning
    /// thing is still a 1:1 stamp. `key` names the picture being turned.
    static func turned(_ image: CGImage?, key: String, angle: Double, steps: Int, period: Double = 2 * .pi) -> CGImage? {
        guard let image, steps > 1, period > 0 else { return image }
        var a = angle.truncatingRemainder(dividingBy: period)
        if a < 0 { a += period }
        let index = Int((a / period * Double(steps)).rounded()) % steps
        guard index != 0 else { return image }
        let turn = CGFloat(Double(index) / Double(steps) * period)
        let w = CGFloat(image.width), h = CGFloat(image.height)
        return HandPlaySprites.image("\(key)|turn\(index)/\(steps)", width: image.width, height: image.height) { ctx in
            ctx.rotate(by: turn)
            ctx.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        }
    }

    /// Glow radii are rounded to a few sizes so they can be baked: finely when small, coarsely when large.
    private static func bucket(_ radius: Double) -> Int {
        if radius < 32 { return max(2, Int((radius / 2).rounded()) * 2) }
        if radius < 100 { return Int((radius / 6).rounded()) * 6 }
        return Int((radius / 16).rounded()) * 16
    }

    /// Strength is rounded to twelfths, so a glow can be baked at the strength it is drawn and stamped at full opacity.
    private static func level(_ alpha: Double) -> Int { max(1, min(12, Int((alpha * 12).rounded()))) }

    /// A soft round glow: bright in the middle and fading to nothing, baked at its size and strength. A small one (a spark, a flame) is
    /// baked at full strength and faded as it is drawn, which costs little at that size and saves baking every strength of every spark.
    static func glow(_ ctx: CGContext, at p: CGPoint, radius: Double, tone: HandPlayTone, alpha: Double) {
        guard alpha > 0.04, radius > 0.5 else { return }
        if radius < 24 {
            let r = bucket(radius)
            let image = HandPlaySprites.image("hp.spark|\(tone.key)|\(r)", side: r * 2) { ctx in
                HandPlayDraw.radial(ctx, [(tone, 1), (tone, 0.55), (tone, 0)], center: .zero, radius: CGFloat(r), locations: [0, 0.3, 1])
            }
            stamp(ctx, image, at: p, alpha: CGFloat(min(1, alpha)))
            return
        }
        let r = bucket(radius), k = level(alpha)
        let peak = Double(k) / 12
        let image = HandPlaySprites.image("hp.glow|\(tone.key)|\(r)|\(k)", side: r * 2) { ctx in
            HandPlayDraw.radial(ctx, [(tone, peak), (tone, 0.55 * peak), (tone, 0)], center: .zero, radius: CGFloat(r), locations: [0, 0.3, 1])
        }
        stamp(ctx, image, at: p)
    }

    /// A glow in the shape of an ellipse filling `rect`.
    static func glow(_ ctx: CGContext, in rect: CGRect, tone: HandPlayTone, alpha: Double) {
        guard alpha > 0.04, rect.width > 1, rect.height > 1 else { return }
        let w = Int((rect.width / 4).rounded()) * 4, h = Int((rect.height / 4).rounded()) * 4, k = level(alpha)
        let peak = Double(k) / 12
        let image = HandPlaySprites.image("hp.oval|\(tone.key)|\(w)x\(h)|\(k)", width: w, height: h) { ctx in
            ctx.scaleBy(x: 1, y: CGFloat(h) / CGFloat(w))
            HandPlayDraw.radial(ctx, [(tone, peak), (tone, 0.55 * peak), (tone, 0)], center: .zero, radius: CGFloat(w) / 2, locations: [0, 0.3, 1])
        }
        stamp(ctx, image, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// A soft contact shadow: an ellipse of shade with no hard edge, baked at its size.
    static func shadow(_ ctx: CGContext, at p: CGPoint, width: Double, height: Double, alpha: Double) {
        guard alpha > 0.04, width > 1, height > 1 else { return }
        let w = Int((width / 4).rounded()) * 4, h = Int((height / 4).rounded()) * 4, k = level(alpha)
        guard w > 0, h > 0 else { return }
        let peak = Double(k) / 12
        let image = HandPlaySprites.image("hp.shadow|\(w)x\(h)|\(k)", width: w, height: h) { ctx in
            ctx.scaleBy(x: 1, y: CGFloat(h) / CGFloat(w))
            HandPlayDraw.radial(ctx, [(HandPlayPalette.ink, 0.55 * peak), (HandPlayPalette.ink, 0.28 * peak), (HandPlayPalette.ink, 0)], center: .zero,
                                radius: CGFloat(w) / 2, locations: [0, 0.45, 1])
        }
        stamp(ctx, image, at: p)
    }

    /// A ring stroked round a point.
    /// `outlined` lays a thin dark edge under it, so a pale ring still reads on a white wall or a white shirt.
    static func ring(_ ctx: CGContext, at p: CGPoint, radius: Double, width: Double, tone: HandPlayTone, alpha: Double, outlined: Bool = false) {
        guard alpha > 0.004, radius > 0.5 else { return }
        if outlined {
            ctx.setStrokeColor(HandPlayPalette.ink.cg(0.3 * min(1, alpha)))
            ctx.setLineWidth(CGFloat(width + 3))
            ctx.strokeEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        }
        ctx.setStrokeColor(tone.cg(min(1, alpha)))
        ctx.setLineWidth(CGFloat(width))
        ctx.strokeEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
    }

    /// An arc stroked with round caps, from the top going clockwise, `fraction` of the way round.
    static func arc(_ ctx: CGContext, at p: CGPoint, radius: Double, width: Double, fraction: Double, tone: HandPlayTone, alpha: Double) {
        guard fraction > 0.001, alpha > 0.004 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(tone.cg(min(1, alpha)))
        ctx.setLineWidth(CGFloat(width))
        ctx.setLineCap(.round)
        let start = CGFloat.pi / 2
        ctx.addArc(center: p, radius: CGFloat(radius), startAngle: start, endAngle: start - CGFloat(min(1, fraction)) * 2 * .pi, clockwise: true)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// A linear gradient through `tones` filling whatever the context is clipped to, from `start` to `end`.
    static func fill(_ ctx: CGContext, _ tones: [(HandPlayTone, Double)], from start: CGPoint, to end: CGPoint, locations: [CGFloat]? = nil) {
        let colours = tones.map { $0.0.cg($0.1) } as CFArray
        guard let g = CGGradient(colorsSpace: HandPlaySprites.space, colors: colours, locations: locations) else { return }
        ctx.drawLinearGradient(g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// A radial gradient through `tones`.
    static func radial(_ ctx: CGContext, _ tones: [(HandPlayTone, Double)], center: CGPoint, radius: CGFloat, from inner: CGPoint? = nil,
                       locations: [CGFloat]? = nil) {
        let colours = tones.map { $0.0.cg($0.1) } as CFArray
        guard let g = CGGradient(colorsSpace: HandPlaySprites.space, colors: colours, locations: locations) else { return }
        ctx.drawRadialGradient(g, startCenter: inner ?? center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
    }

    /// A five-pointed star path.
    static func starPath(center: CGPoint = .zero, radius: CGFloat, inner: CGFloat = 0.46, rotation: CGFloat = 0) -> CGPath {
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

    /// A little four-pointed glint, the twinkle on anything shiny.
    static func glint(_ ctx: CGContext, at p: CGPoint, radius: Double, alpha: Double, tone: HandPlayTone = HandPlayPalette.cream) {
        guard alpha > 0.01, radius > 0.5 else { return }
        glow(ctx, at: p, radius: radius * 0.9, tone: tone, alpha: alpha * 0.6)
        let r = CGFloat(radius), w = r * 0.16
        let path = CGMutablePath()
        path.move(to: CGPoint(x: p.x, y: p.y + r))
        path.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: CGPoint(x: p.x + w, y: p.y + w))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: CGPoint(x: p.x + w, y: p.y - w))
        path.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: CGPoint(x: p.x - w, y: p.y - w))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: CGPoint(x: p.x - w, y: p.y + w))
        ctx.addPath(path)
        ctx.setFillColor(tone.cg(min(1, alpha)))
        ctx.fillPath()
    }

    /// A soft wash of colour round the edges of the picture: "you got hit", without a strobe. Four baked strips, stamped 1:1.
    static func vignette(_ ctx: CGContext, size: CGSize, tone: HandPlayTone, alpha: Double) {
        guard alpha > 0.005 else { return }
        let w = Int(size.width), h = Int(size.height), depth = max(8, Int(size.height * 0.1))
        func strip(_ name: String, _ sw: Int, _ sh: Int, from: CGPoint, to: CGPoint) -> CGImage? {
            HandPlaySprites.image("hp.edge|\(name)|\(tone.key)|\(sw)x\(sh)", width: sw, height: sh) { ctx in
                HandPlayDraw.fill(ctx, [(tone, 0.85), (tone, 0.3), (tone, 0)], from: from, to: to, locations: [0, 0.4, 1])
            }
        }
        let d = CGFloat(depth) / 2
        let a = CGFloat(min(1, alpha))
        stamp(ctx, strip("top", w, depth, from: CGPoint(x: 0, y: d), to: CGPoint(x: 0, y: -d)), at: CGPoint(x: size.width / 2, y: size.height - d), alpha: a)
        stamp(ctx, strip("bottom", w, depth, from: CGPoint(x: 0, y: -d), to: CGPoint(x: 0, y: d)), at: CGPoint(x: size.width / 2, y: d), alpha: a)
        stamp(ctx, strip("left", depth, h, from: CGPoint(x: -d, y: 0), to: CGPoint(x: d, y: 0)), at: CGPoint(x: d, y: size.height / 2), alpha: a)
        stamp(ctx, strip("right", depth, h, from: CGPoint(x: d, y: 0), to: CGPoint(x: -d, y: 0)), at: CGPoint(x: size.width - d, y: size.height / 2), alpha: a)
    }
}

// MARK: - Type

/// Words on the picture, all in one voice: the rounded heavy system font with a dark outline and a soft shadow, baked once per line.
enum HandPlayText {
    static func font(size: CGFloat, weight: NSFont.Weight = .heavy) -> NSFont {
        let plain = NSFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = plain.fontDescriptor.withDesign(.rounded), let font = NSFont(descriptor: rounded, size: size) else { return plain }
        return font
    }

    static func width(of string: String, size: CGFloat, weight: NSFont.Weight = .heavy) -> CGFloat {
        NSAttributedString(string: string, attributes: [.font: font(size: size, weight: weight)]).size().width
    }

    /// A line of text as a picture: filled with `color`, outlined in ink, with a soft shadow below and to the right.
    static func image(_ string: String, size: CGFloat, color: HandPlayTone = HandPlayPalette.cream, weight: NSFont.Weight = .heavy,
                      outline: Double = 1) -> CGImage? {
        let px = max(8, size.rounded())
        let key = "hp.text|\(string)|\(Int(px))|\(color.key)|\(weight.rawValue)|\(outline)"
        let f = font(size: px, weight: weight)
        let box = NSAttributedString(string: string, attributes: [.font: f]).size()
        let edge = px * 0.085 * CGFloat(outline)
        let pad = edge + px * 0.3
        let width = Int(ceil(box.width + pad * 2)), height = Int(ceil(box.height + pad * 2))
        return HandPlaySprites.image(key, width: width, height: height) { ctx in
            let origin = NSPoint(x: -box.width / 2, y: -box.height / 2)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            ctx.setLineJoin(.round)
            if edge > 0 {
                let shadow = NSShadow()
                shadow.shadowOffset = NSSize(width: px * 0.03, height: -px * 0.06)
                shadow.shadowBlurRadius = px * 0.14
                shadow.shadowColor = HandPlayPalette.ink.ns(0.6)
                // Positive stroke width strokes without filling, so the outline sits outside the letters once the fill goes on top.
                let stroke = NSAttributedString(string: string, attributes: [
                    .font: f, .strokeColor: HandPlayPalette.ink.ns(0.92), .strokeWidth: Double(edge * 2 / px * 100), .shadow: shadow,
                ])
                stroke.draw(at: origin)
            }
            let fill = NSAttributedString(string: string, attributes: [.font: f, .foregroundColor: color.ns()])
            fill.draw(at: origin)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func draw(_ ctx: CGContext, _ string: String, at center: CGPoint, size: CGFloat, color: HandPlayTone = HandPlayPalette.cream,
                     alpha: CGFloat = 1, scale: CGFloat = 1, rotation: CGFloat = 0, weight: NSFont.Weight = .heavy) {
        HandPlayDraw.stamp(ctx, image(string, size: size, color: color, weight: weight), at: center, scale: scale, rotation: rotation, alpha: alpha)
    }
}

// MARK: - Words in the world

/// A word or number that pops up where something happened, rises and fades: "+3", "PERFECT".
struct HandPlayFloater {
    var text: String
    var origin: SIMD2<Double>
    var tone: HandPlayTone
    var size: CGFloat = 46
    var life = 0.9
    var rise = 80.0
    var age = 0.0

    var isDone: Bool { age >= life }
    var position: SIMD2<Double> { origin + SIMD2(0, rise * HandPlayEase.outCubic(age / life)) }

    mutating func advance(_ dt: Double) { age += dt }

    func draw(_ ctx: CGContext) {
        let pop = 0.55 + 0.45 * HandPlayEase.outBack(age / 0.2, overshoot: 2.4)
        let fade = HandPlayEase.clamp((life - age) / (life * 0.4))
        let p = position
        HandPlayText.draw(ctx, text, at: CGPoint(x: p.x, y: p.y), size: size, color: tone, alpha: CGFloat(fade), scale: CGFloat(pop))
    }
}

// MARK: - Poses and gloves

/// The hand shapes the HandPlay games ask for.
enum HandPlayPose: Int, CaseIterable {
    case fist, open, peace, point, thumbsUp

    var name: String {
        switch self {
        case .fist: return "FIST"
        case .open: return "OPEN HAND"
        case .peace: return "PEACE"
        case .point: return "POINT"
        case .thumbsUp: return "THUMBS UP"
        }
    }

    /// The colour that stands for the pose wherever it appears.
    var tone: HandPlayTone {
        switch self {
        case .fist: return HandPlayPalette.coral
        case .open: return HandPlayPalette.sky
        case .peace: return HandPlayPalette.mint
        case .point: return HandPlayPalette.gold
        case .thumbsUp: return HandPlayPalette.violet
        }
    }
}

/// Reads a hand as the HandPlay games understand it. Tracking is noisy, so these are deliberately broad: three fingers out is an open
/// hand, and a thumb only counts as up when it is well clear of the fist.
enum HandPlayReading {
    static func pose(of hand: HandState) -> HandPlayPose? {
        let up = hand.fingersUp
        if up == 4 || (up == 3 && hand.thumbOpen > 0.5) { return .open }
        if up == 0 {
            if hand.thumbOpen >= 0.62 { return .thumbsUp }
            if hand.thumbOpen <= 0.42 { return .fist }
            return nil
        }
        let index = hand.isExtended(.index), middle = hand.isExtended(.middle)
        if up == 1 && index { return .point }
        if up == 2 && index && middle { return .peace }
        return nil
    }

    /// Open enough to catch or cast with.
    static func isOpen(_ hand: HandState) -> Bool { hand.fingersUp >= 3 }
    /// Closed: no long finger out, whatever the thumb is doing.
    static func isClosed(_ hand: HandState) -> Bool { hand.fingersUp == 0 }
}

/// Cartoon gloves for each pose: the icon on every hint, tile and card in the HandPlay games. Drawn as vector art (outline, a lit white
/// glove, a coloured cuff) and baked once per pose and size.
enum HandPlayGlove {
    /// A glove `height` pixels tall, with a cuff in the pose's colour unless another is given.
    static func image(_ pose: HandPlayPose, height: CGFloat, cuff: HandPlayTone? = nil) -> CGImage? {
        let tone = cuff ?? pose.tone
        let px = max(12, height.rounded())
        let unit = px / 2.45
        let side = Int(ceil(px * 1.18))
        return HandPlaySprites.image("hp.glove|\(pose.rawValue)|\(Int(px))|\(tone.key)", side: side) { ctx in
            ctx.scaleBy(x: unit, y: unit)
            ctx.translateBy(x: 0, y: 0.05)
            paint(ctx, pose: pose, cuff: tone, unit: unit)
        }
    }

    private struct Part {
        var path: CGPath
        /// Parts in front are drawn with their own outline over the rest.
        var front = false
    }

    private static func capsule(from a: CGPoint, to b: CGPoint, width: CGFloat) -> CGPath {
        let stroke = CGMutablePath()
        stroke.move(to: a)
        stroke.addLine(to: b)
        return stroke.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
    }

    private static func finger(base: CGPoint, length: CGFloat, width: CGFloat, lean: CGFloat) -> CGPath {
        capsule(from: base, to: CGPoint(x: base.x - sin(lean) * length, y: base.y + cos(lean) * length), width: width)
    }

    private static func parts(for pose: HandPlayPose) -> [Part] {
        var parts: [Part] = []
        let curled: (CGFloat, CGFloat) -> Part = { x, w in
            Part(path: CGPath(roundedRect: CGRect(x: x - w / 2, y: -0.02, width: w, height: 0.5), cornerWidth: w / 2, cornerHeight: w / 2,
                              transform: nil), front: true)
        }
        let tuckedThumb = Part(path: capsule(from: CGPoint(x: -0.5, y: -0.18), to: CGPoint(x: 0.08, y: -0.04), width: 0.27), front: true)
        let palm = Part(path: CGPath(roundedRect: CGRect(x: -0.52, y: -0.6, width: 1.04, height: 1.0), cornerWidth: 0.36, cornerHeight: 0.36,
                                     transform: nil))
        // Index on the thumb side (left), little finger on the right.
        let bases: [CGFloat] = [-0.32, -0.1, 0.12, 0.34]
        let lengths: [CGFloat] = [0.82, 0.92, 0.85, 0.66]
        let widths: [CGFloat] = [0.25, 0.26, 0.25, 0.22]
        switch pose {
        case .open:
            let leans: [CGFloat] = [0.16, 0.04, -0.08, -0.22]
            for i in 0..<4 { parts.append(Part(path: finger(base: CGPoint(x: bases[i], y: 0.22), length: lengths[i], width: widths[i], lean: leans[i]))) }
            parts.append(palm)
            parts.append(Part(path: capsule(from: CGPoint(x: -0.42, y: -0.18), to: CGPoint(x: -0.86, y: 0.3), width: 0.27)))
        case .fist:
            parts.append(palm)
            for i in 0..<4 { parts.append(curled(bases[i] * 1.02, 0.24)) }
            parts.append(tuckedThumb)
        case .point:
            parts.append(Part(path: finger(base: CGPoint(x: bases[0], y: 0.22), length: lengths[0] * 1.05, width: widths[0], lean: 0.04)))
            parts.append(palm)
            for i in 1..<4 { parts.append(curled(bases[i] * 1.02, 0.24)) }
            parts.append(tuckedThumb)
        case .peace:
            parts.append(Part(path: finger(base: CGPoint(x: bases[0] + 0.02, y: 0.22), length: lengths[0], width: widths[0], lean: 0.26)))
            parts.append(Part(path: finger(base: CGPoint(x: bases[1] + 0.02, y: 0.22), length: lengths[1], width: widths[1], lean: -0.16)))
            parts.append(palm)
            for i in 2..<4 { parts.append(curled(bases[i] * 1.02, 0.24)) }
            parts.append(tuckedThumb)
        case .thumbsUp:
            // A fist turned side on: the curled fingers stacked down the front and the thumb standing up out of the top.
            let thumb = CGMutablePath()
            thumb.move(to: CGPoint(x: -0.4, y: 0.12))
            thumb.addCurve(to: CGPoint(x: -0.36, y: 0.86), control1: CGPoint(x: -0.46, y: 0.42), control2: CGPoint(x: -0.5, y: 0.78))
            thumb.addCurve(to: CGPoint(x: 0.02, y: 0.78), control1: CGPoint(x: -0.26, y: 0.98), control2: CGPoint(x: -0.02, y: 0.98))
            thumb.addCurve(to: CGPoint(x: 0.04, y: 0.12), control1: CGPoint(x: 0.08, y: 0.56), control2: CGPoint(x: 0.04, y: 0.36))
            thumb.closeSubpath()
            parts.append(Part(path: thumb))
            parts.append(Part(path: CGPath(roundedRect: CGRect(x: -0.52, y: -0.62, width: 1.0, height: 0.92), cornerWidth: 0.34, cornerHeight: 0.34,
                                           transform: nil)))
            for k in 0..<4 {
                let y = 0.16 - CGFloat(k) * 0.21
                parts.append(Part(path: CGPath(roundedRect: CGRect(x: -0.08, y: y - 0.1, width: 0.66 - CGFloat(k) * 0.05, height: 0.21),
                                               cornerWidth: 0.1, cornerHeight: 0.1, transform: nil), front: true))
            }
        }
        return parts
    }

    private static func paint(_ ctx: CGContext, pose: HandPlayPose, cuff: HandPlayTone, unit: CGFloat) {
        let all = parts(for: pose)
        let line: CGFloat = 0.075
        let back = all.filter { !$0.front }, front = all.filter(\.front)
        let cuffRect = CGRect(x: -0.4, y: -1.02, width: 0.8, height: 0.46)
        let cuffPath = CGPath(roundedRect: cuffRect, cornerWidth: 0.14, cornerHeight: 0.14, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: unit * 0.04, height: -unit * 0.08), blur: unit * 0.16, color: HandPlayPalette.ink.cg(0.5))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setLineJoin(.round)

        // The cuff first, behind the glove.
        ctx.addPath(cuffPath)
        ctx.setStrokeColor(HandPlayPalette.ink.cg())
        ctx.setLineWidth(line * 2)
        ctx.strokePath()
        ctx.saveGState()
        ctx.addPath(cuffPath)
        ctx.clip()
        HandPlayDraw.fill(ctx, [(cuff.lighter(0.25), 1), (cuff, 1), (cuff.darker(0.3), 1)], from: CGPoint(x: -0.3, y: -0.56), to: CGPoint(x: 0.3, y: -1.02),
                          locations: [0, 0.45, 1])
        ctx.setStrokeColor(cuff.darker(0.45).cg(0.6))
        ctx.setLineWidth(0.05)
        ctx.move(to: CGPoint(x: -0.4, y: -0.8))
        ctx.addLine(to: CGPoint(x: 0.4, y: -0.8))
        ctx.strokePath()
        ctx.restoreGState()

        // The glove: every back part outlined thick, then all filled, so the outline runs round the whole shape and not across it.
        for part in back {
            ctx.addPath(part.path)
            ctx.setStrokeColor(HandPlayPalette.ink.cg())
            ctx.setLineWidth(line * 2)
            ctx.strokePath()
        }
        // Each part is filled on its own (a combined path would cancel where parts overlap), with one light across the whole glove.
        let box = back.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
        for part in back { fillGlove(ctx, part.path, box: box) }
        if pose == .open {
            // The three stitched lines on the back of a cartoon glove.
            ctx.setStrokeColor(HandPlayTone(0.55, 0.58, 0.72).cg(0.7))
            ctx.setLineWidth(0.04)
            ctx.setLineCap(.round)
            for x in [-0.18, 0.0, 0.18] as [CGFloat] {
                ctx.move(to: CGPoint(x: x, y: -0.22))
                ctx.addLine(to: CGPoint(x: x * 1.1, y: 0.06))
            }
            ctx.strokePath()
        }
        // Parts in front (curled fingers, a tucked thumb) each get their own outline.
        for part in front {
            ctx.addPath(part.path)
            ctx.setStrokeColor(HandPlayPalette.ink.cg())
            ctx.setLineWidth(line * 1.6)
            ctx.strokePath()
            fillGlove(ctx, part.path, box: part.path.boundingBoxOfPath.insetBy(dx: -0.3, dy: -0.3))
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// White cloth lit from the top left: bright, cooling to a soft blue-grey at the bottom right, with a highlight on the top-left edge.
    private static func fillGlove(_ ctx: CGContext, _ path: CGPath, box: CGRect) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        HandPlayDraw.fill(ctx, [(HandPlayTone(1, 1, 1), 1), (HandPlayTone(0.95, 0.95, 0.98), 1), (HandPlayTone(0.78, 0.8, 0.9), 1)],
                          from: CGPoint(x: box.minX, y: box.maxY), to: CGPoint(x: box.maxX, y: box.minY), locations: [0, 0.5, 1])
        ctx.restoreGState()
    }
}

// MARK: - Following hands

/// Debounces whether a hand is open or closed: a new shape has to hold for a moment before it counts, so a flicker of the tracker does not
/// cast, catch or bank anything.
struct HandPlayGrip: Equatable {
    enum State: Equatable { case open, closed, other }

    /// How long a new shape must hold.
    static let settle = 0.08

    private(set) var state = State.other
    private var candidate = State.other
    private var candidateFor = 0.0
    private var started = false

    static func reading(of hand: HandState) -> State {
        if HandPlayReading.isOpen(hand) { return .open }
        if HandPlayReading.isClosed(hand) { return .closed }
        return .other
    }

    /// Takes this frame's look at the hand. Returns the change, if the shape just changed.
    mutating func update(_ hand: HandState, dt: Double) -> (from: State, to: State)? {
        let now = Self.reading(of: hand)
        guard started else {
            started = true
            state = now
            candidate = now
            return nil
        }
        if now == state {
            candidate = now
            candidateFor = 0
            return nil
        }
        if now == candidate { candidateFor += max(0, dt) } else { candidate = now; candidateFor = max(0, dt) }
        guard candidateFor >= Self.settle else { return nil }
        let from = state
        state = now
        candidateFor = 0
        return (from, now)
    }
}

/// Every hand in view, followed by id from frame to frame: where its palm is, how fast it is going (measured over a short window, so a
/// look repeated between two tracker updates does not read as a stop), whether it is open or closed, and for how long it has been lost.
struct HandPlayRoster {
    struct Entry {
        var id: Int
        var hand: HandState
        var palm: CGPoint
        /// Pixels a second.
        var velocity = SIMD2<Double>.zero
        var grip = HandPlayGrip()
        /// What the grip changed to this frame, if it changed.
        var change: (from: HandPlayGrip.State, to: HandPlayGrip.State)?
        var visible = true
        /// Seconds since it was last seen.
        var missing = 0.0
        /// 0...1: rises while the hand is in view and fades after it is lost, for drawing.
        var presence = 0.0
        /// Seconds since it was first seen.
        var age = 0.0

        var speed: Double { simd_length(velocity) }
        /// In view, or lost for no more than a few frames: tracking drops out in a blur or a fast move, and a game should carry on as if the
        /// hand were still there rather than flicker.
        var isHeld: Bool { missing < HandPlayRoster.dropout }
        var size: Double { hand.size }
        var isOpen: Bool { grip.state == .open }
        var isClosed: Bool { grip.state == .closed }
    }

    /// How long a lost hand is remembered.
    static let memory = 0.6
    /// How long a hand can drop out and still be treated as there.
    static let dropout = 0.25
    /// How far back speed is measured.
    static let window = 0.12

    private(set) var entries: [Entry] = []
    private var trails: [Int: [(time: Double, point: CGPoint)]] = [:]

    mutating func reset() {
        entries.removeAll()
        trails.removeAll()
    }

    var visible: [Entry] { entries.filter(\.visible) }

    func entry(_ id: Int) -> Entry? { entries.first { $0.id == id } }

    mutating func update(_ hands: [HandState], dt: Double, now: Double) {
        let dt = max(0, dt)
        for i in entries.indices {
            entries[i].visible = false
            entries[i].change = nil
        }
        for hand in hands {
            let palm = hand.palm
            var trail = trails[hand.id] ?? []
            // A hand that was lost for a while, or jumped across the picture, starts afresh: nothing is known about the gap.
            if let last = trail.last, now - last.time > 0.25 || HandState.distance(last.point, palm) > max(300, hand.size * 3.5) { trail.removeAll() }
            trail.append((now, palm))
            trail.removeAll { now - $0.time > Self.window + 0.08 }
            trails[hand.id] = trail
            var velocity = SIMD2<Double>.zero
            if let reference = trail.first(where: { now - $0.time <= Self.window }), now - reference.time > 1e-6 {
                let span = max(0.05, now - reference.time)
                velocity = SIMD2(Double(palm.x - reference.point.x), Double(palm.y - reference.point.y)) / span
            }

            if let i = entries.firstIndex(where: { $0.id == hand.id }) {
                entries[i].hand = hand
                entries[i].palm = palm
                entries[i].velocity = velocity
                entries[i].change = entries[i].grip.update(hand, dt: dt)
                entries[i].visible = true
                entries[i].missing = 0
                entries[i].presence = min(1, entries[i].presence + dt / 0.12)
                entries[i].age += dt
            } else {
                var entry = Entry(id: hand.id, hand: hand, palm: palm, velocity: velocity)
                _ = entry.grip.update(hand, dt: dt)
                entry.presence = min(1, dt / 0.12)
                entries.append(entry)
            }
        }
        for i in entries.indices where !entries[i].visible {
            entries[i].missing += dt
            entries[i].velocity *= exp(-dt / 0.1)
            entries[i].presence = max(0, entries[i].presence - dt / 0.3)
        }
        entries.removeAll { $0.missing > Self.memory }
        entries.sort { $0.id < $1.id }
        trails = trails.filter { id, trail in entries.contains { $0.id == id } || (trail.last?.time ?? -1) > now - 0.5 }
    }
}

/// The palm and fingertips of every hand, with where each was a frame ago and how fast it is going, for games that are played by touching
/// things. The same idea as the shared poke tracker, kept here so the HandPlay games can tune it on their own.
struct HandPlayTouches {
    struct Touch: Equatable {
        var position: CGPoint
        var previous: CGPoint
        var speed: Double
        var radius: Double
        var handSize: Double
        var hand: Int
        /// 0 the palm, 1...5 thumb to little finger.
        var slot: Int

        var isPalm: Bool { slot == 0 }
        /// Fast enough to be a deliberate tap, scaled to the hand so it reads the same near the camera and far from it.
        var isQuick: Bool { speed >= max(150, handSize * 1.4) }
    }

    static let window = 0.15

    private struct Key: Hashable { var hand: Int; var slot: Int }
    private var trails: [Key: [(time: Double, point: CGPoint)]] = [:]

    mutating func reset() { trails.removeAll() }

    mutating func update(_ hands: [HandState], now: Double) -> [Touch] {
        var out: [Touch] = []
        for hand in hands {
            let size = hand.size
            let parts: [(Int, CGPoint, Double)] = [
                (0, hand.palm, size * 0.5), (1, hand[.thumbTip], size * 0.2), (2, hand[.indexTip], size * 0.22),
                (3, hand[.middleTip], size * 0.22), (4, hand[.ringTip], size * 0.2), (5, hand[.littleTip], size * 0.18),
            ]
            for (slot, point, radius) in parts {
                let key = Key(hand: hand.id, slot: slot)
                var trail = trails[key] ?? []
                if let last = trail.last, now - last.time > 0.25 || HandState.distance(last.point, point) > max(300, size * 3.5) { trail.removeAll() }
                let previous = trail.last?.point ?? point
                trail.append((now, point))
                trail.removeAll { now - $0.time > Self.window + 0.1 }
                trails[key] = trail
                var speed = 0.0
                if let reference = trail.first(where: { now - $0.time <= Self.window }), reference.time < now {
                    speed = HandState.distance(reference.point, point) / max(0.1, now - reference.time)
                }
                out.append(Touch(position: point, previous: previous, speed: speed, radius: radius, handSize: size, hand: hand.id, slot: slot))
            }
        }
        trails = trails.filter { ($0.value.last?.time ?? -1) > now - 0.5 }
        return out
    }
}

extension SIMD2 where Scalar == Double {
    /// As a point in the picture.
    var handPlayPoint: CGPoint { CGPoint(x: x, y: y) }
}

extension CGPoint {
    /// As a vector, for the maths.
    var handPlayVector: SIMD2<Double> { SIMD2(Double(x), Double(y)) }
}
