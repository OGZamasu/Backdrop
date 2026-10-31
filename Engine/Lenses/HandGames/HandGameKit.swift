import AppKit
import CoreGraphics
import CoreImage
import Foundation
import simd

/// Drawing pieces that the hand games share: glows, stars and text widths. Their screens and words come from `GameScreens`.
enum HandGameArt {
    static let gold = NSColor(red: 1, green: 0.82, blue: 0.3, alpha: 1)
    static let bad = NSColor(red: 1, green: 0.45, blue: 0.42, alpha: 1)

    /// How wide a line of text comes out in the games' type.
    static func width(of string: String, size: CGFloat, weight: NSFont.Weight = .heavy) -> CGFloat {
        GameUIType.width(string, size: size, weight: weight)
    }

    /// A soft glow stamped from a cached sprite, which costs far less to draw than a fresh gradient every frame. A big one is drawn as a
    /// real gradient instead, because a small sprite blown up that far shows its steps.
    static func halo(_ ctx: CGContext, at center: CGPoint, radius: CGFloat, red: Double, green: Double, blue: Double, alpha: Double) {
        if radius > 150 {
            ctx.glow(center: center, radius: radius, red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(min(1, alpha * 0.8)))
            return
        }
        guard let dot = Sprites.dot(red: red, green: green, blue: blue) else { return }
        ctx.stampDot(dot, at: center, radius: Double(radius), alpha: alpha)
    }

    /// The same glow stretched over a rectangle: a soft light behind something long, like a paddle.
    static func halo(_ ctx: CGContext, in rect: CGRect, red: Double, green: Double, blue: Double, alpha: Double) {
        guard let dot = Sprites.dot(red: red, green: green, blue: blue), alpha > 0.004 else { return }
        ctx.setAlpha(CGFloat(min(1, alpha)))
        ctx.draw(dot, in: rect)
        ctx.setAlpha(1)
    }

    /// A five-pointed star.
    static func starPath(center: CGPoint, radius: CGFloat, rotation: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<10 {
            let r = i % 2 == 0 ? radius : radius * 0.45
            let a = rotation + .pi / 2 + CGFloat(i) * .pi / 5
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// A chunky gold star with a bevel, stamped from a sprite.
    static func star(_ ctx: CGContext, at center: CGPoint, radius: CGFloat, rotation: CGFloat = 0, alpha: CGFloat = 1) {
        guard let sprite = HandGamePieces.star() else { return }
        ctx.draw(sprite, center: center, height: radius * 2.2, rotation: rotation, alpha: alpha)
    }

    /// Where a number is between two values, kept in range.
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * min(1, max(0, t)) }
}

// MARK: - Palette, easing and type

/// The colours every hand game is drawn in, so the five look like one family. Warm and slightly soft: nothing is a pure primary,
/// and everything that must be read sits on an ink card.
enum HandGamePalette {
    /// Deep plum-navy: cards, outlines, shadows.
    static let ink = SIMD3<Double>(0.11, 0.08, 0.19)
    /// Warm white for words.
    static let cream = SIMD3<Double>(1.0, 0.97, 0.92)
    /// Scores, stars, rewards.
    static let gold = SIMD3<Double>(1.0, 0.80, 0.28)
    /// Good things: a hit, a win.
    static let mint = SIMD3<Double>(0.36, 0.89, 0.62)
    /// Bad things: a miss, a bomb, a lost life.
    static let coral = SIMD3<Double>(1.0, 0.43, 0.41)
    /// The player's side.
    static let sky = SIMD3<Double>(0.36, 0.74, 1.0)
    /// Banners and streaks.
    static let berry = SIMD3<Double>(0.78, 0.26, 0.62)

    static func color(_ c: SIMD3<Double>, _ alpha: Double = 1) -> CGColor { CGColor(srgbRed: c.x, green: c.y, blue: c.z, alpha: alpha) }
    static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> { a + (b - a) * min(1, max(0, t)) }
}

/// Easing curves, so nothing moves in a straight line or pops.
enum HandGameEase {
    static func clamp(_ t: Double) -> Double { min(1, max(0, t)) }
    static func outCubic(_ t: Double) -> Double { let u = 1 - clamp(t); return 1 - u * u * u }
    static func inOut(_ t: Double) -> Double { let t = clamp(t); return t * t * (3 - 2 * t) }
    /// Overshoots a little and settles: for things that arrive.
    static func outBack(_ t: Double, _ s: Double = 1.7) -> Double { let u = clamp(t) - 1; return 1 + u * u * ((s + 1) * u + s) }
    /// A damped wobble from 1 down to 0: for a squash or a shake.
    static func wobble(_ t: Double, frequency: Double = 3, damping: Double = 6) -> Double { exp(-damping * max(0, t)) * cos(2 * .pi * frequency * max(0, t)) }
}

/// The hand games' words, in the shared game type (`GameUIType`): rounded, heavy, on a thin ink edge with a soft shadow.
enum HandGameType {
    enum Align { case center, left, right }

    /// Draws words centred on `point` (or with their left or right end on it), `size` points tall in the font.
    static func draw(_ ctx: CGContext, _ string: String, at point: CGPoint, size: CGFloat, color: CGColor = HandGamePalette.color(HandGamePalette.cream),
                     weight: NSFont.Weight = .heavy, align: Align = .center, alpha: CGFloat = 1, scale: CGFloat = 1) {
        let c = color.converted(to: GameUISprites.space, intent: .defaultIntent, options: nil)?.components ?? [1, 1, 1, 1]
        let tone = SIMD3<Double>(Double(c[0]), Double(c.count > 2 ? c[1] : c[0]), Double(c.count > 2 ? c[2] : c[0]))
        let shared: GameUIType.Align = align == .center ? .center : (align == .left ? .left : .right)
        GameUIType.draw(ctx, string, at: point, size: size, color: tone, weight: weight, align: shared, alpha: alpha * (c.last ?? 1), scale: scale)
    }

    /// How wide words come out, without the edge around them.
    static func width(_ string: String, size: CGFloat, weight: NSFont.Weight = .heavy) -> CGFloat { GameUIType.width(string, size: size, weight: weight) }
}

// MARK: - Sprites

/// Art drawn once and kept: every hero object in the hand games is baked into a picture the first time it is needed (on the video
/// queue, never while a lens is being made) and stamped from then on.
enum HandGameSprites {
    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]

    /// The picture for `key`, drawing it with `draw` the first time. The context is `size` points with the origin in the middle and y
    /// up, at `scale` pixels a point, so the art stays crisp when it is turned or grown a little.
    static func image(_ key: String, size: CGSize, scale: CGFloat = 1.5, draw: (CGContext) -> Void) -> CGImage? {
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        if cache.count > 400 { cache = cache.filter { !$0.key.hasPrefix("hg.card.") } }
        lock.unlock()
        let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
        guard width > 0, height > 0, let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                         space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                                         bitmapInfo: Sprites.bitmapInfo) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        draw(ctx)
        guard let image = ctx.makeImage() else { return nil }
        lock.lock()
        cache[key] = image
        lock.unlock()
        return image
    }

    /// A gradient between two colours along a line, the light coming from the top left.
    static func linear(_ ctx: CGContext, _ colors: [CGColor], locations: [CGFloat]? = nil, from a: CGPoint, to b: CGPoint) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations) else { return }
        ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    static func radial(_ ctx: CGContext, _ colors: [CGColor], locations: [CGFloat]? = nil, center: CGPoint, radius: CGFloat,
                       focus: CGPoint? = nil) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations) else { return }
        ctx.drawRadialGradient(g, startCenter: focus ?? center, startRadius: 0, endCenter: center, endRadius: radius,
                               options: [.drawsAfterEndLocation])
    }

    /// A colour as a CGColor, with each channel scaled by `light` (above 1 lightens toward white).
    static func shade(_ c: SIMD3<Double>, _ light: Double, alpha: Double = 1) -> CGColor {
        let v = light >= 1 ? c + (SIMD3(1, 1, 1) - c) * min(1, light - 1) : c * max(0, light)
        return CGColor(srgbRed: v.x, green: v.y, blue: v.z, alpha: alpha)
    }

    /// A soft oval shadow on the ground under something.
    static func contactShadow(_ ctx: CGContext, center: CGPoint, width: CGFloat, height: CGFloat, alpha: CGFloat = 0.35) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: 1, y: height / max(width, 1))
        radial(ctx, [HandGamePalette.color(HandGamePalette.ink, Double(alpha)), HandGamePalette.color(HandGamePalette.ink, 0)], center: .zero, radius: width / 2)
        ctx.restoreGState()
    }
}

/// Small drawn pieces the games share: a star and the bomb.
enum HandGamePieces {
    /// A gold star with a bevel: light faces toward the top left, darker ones away.
    static func star() -> CGImage? {
        HandGameSprites.image("hg.star", size: CGSize(width: 64, height: 64)) { ctx in
            let r: CGFloat = 28
            let outer = HandGameArt.starPath(center: .zero, radius: r)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: HandGamePalette.color(HandGamePalette.ink, 0.45))
            ctx.addPath(outer)
            ctx.setFillColor(HandGameSprites.shade(HandGamePalette.gold, 0.8))
            ctx.fillPath()
            ctx.restoreGState()
            // Each point is two facets meeting along a ridge; the facets facing the light are lighter.
            for i in 0..<10 {
                let a0 = CGFloat.pi / 2 + CGFloat(i) * .pi / 5, a1 = CGFloat.pi / 2 + CGFloat(i + 1) * .pi / 5
                let r0 = i % 2 == 0 ? r : r * 0.45, r1 = i % 2 == 0 ? r * 0.45 : r
                let facet = CGMutablePath()
                facet.move(to: .zero)
                facet.addLine(to: CGPoint(x: cos(a0) * r0, y: sin(a0) * r0))
                facet.addLine(to: CGPoint(x: cos(a1) * r1, y: sin(a1) * r1))
                facet.closeSubpath()
                let mid = (a0 + a1) / 2
                let light = 0.5 + 0.5 * Double(cos(mid - 2.3))
                ctx.addPath(facet)
                ctx.setFillColor(HandGameSprites.shade(HandGamePalette.gold, 0.78 + light * 0.45))
                ctx.fillPath()
            }
            ctx.addPath(outer)
            ctx.setStrokeColor(HandGameSprites.shade(HandGamePalette.gold, 0.55))
            ctx.setLineWidth(1.5)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
    }

    /// The bomb that turns up in Fruit Slash and Whack-a-Mole: a dark glossy ball, a brass cap and a fuse. The spark is drawn live.
    static func bomb() -> CGImage? {
        HandGameSprites.image("hg.bomb", size: CGSize(width: 150, height: 150)) { ctx in
            let r: CGFloat = 52
            let c = CGPoint(x: -4, y: -10)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 3, height: -5), blur: 8, color: HandGamePalette.color(HandGamePalette.ink, 0.5))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.clip()
            HandGameSprites.radial(ctx, [CGColor(srgbRed: 0.36, green: 0.36, blue: 0.48, alpha: 1), CGColor(srgbRed: 0.13, green: 0.12, blue: 0.2, alpha: 1),
                                         CGColor(srgbRed: 0.05, green: 0.04, blue: 0.09, alpha: 1)], locations: [0, 0.55, 1],
                                   center: c, radius: r * 1.05, focus: CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.4))
            // Rim light along the lower right, so it stands off a dark room.
            ctx.setStrokeColor(CGColor(srgbRed: 0.55, green: 0.6, blue: 0.85, alpha: 0.5))
            ctx.setLineWidth(5)
            ctx.addArc(center: CGPoint(x: c.x - 3, y: c.y + 3), radius: r, startAngle: -1.9, endAngle: 0.1, clockwise: false)
            ctx.strokePath()
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.75))
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y + r * 0.28, width: r * 0.36, height: r * 0.24))
            ctx.restoreGState()
            // The brass cap and the fuse.
            ctx.saveGState()
            ctx.translateBy(x: c.x + r * 0.5, y: c.y + r * 0.72)
            ctx.rotate(by: -0.6)
            let cap = CGRect(x: -15, y: -6, width: 30, height: 18)
            ctx.addPath(CGPath(roundedRect: cap, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.clip()
            HandGameSprites.linear(ctx, [CGColor(srgbRed: 0.98, green: 0.82, blue: 0.45, alpha: 1), CGColor(srgbRed: 0.62, green: 0.42, blue: 0.16, alpha: 1)],
                                   from: CGPoint(x: -15, y: 12), to: CGPoint(x: 15, y: -6))
            ctx.restoreGState()
            ctx.setStrokeColor(CGColor(srgbRed: 0.55, green: 0.42, blue: 0.3, alpha: 1))
            ctx.setLineWidth(5)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: c.x + r * 0.62, y: c.y + r * 0.95))
            ctx.addCurve(to: CGPoint(x: 52, y: 58), control1: CGPoint(x: 44, y: 62), control2: CGPoint(x: 36, y: 40))
            ctx.strokePath()
        }
    }

    /// Where the fuse ends on the bomb sprite, as a fraction of the sprite's height from its centre.
    static let bombFuseTip = CGPoint(x: 52.0 / 150, y: 58.0 / 150)

    /// A fizzing spark at the end of a fuse, drawn live so it flickers.
    static func spark(_ ctx: CGContext, at p: CGPoint, size: CGFloat, time: Double) {
        let flicker = 0.75 + 0.25 * sin(time * 47) * sin(time * 29)
        HandGameArt.halo(ctx, at: p, radius: size * 1.6 * CGFloat(flicker), red: 1, green: 0.62, blue: 0.2, alpha: 0.9)
        HandGameArt.halo(ctx, at: p, radius: size * 0.7, red: 1, green: 0.95, blue: 0.7, alpha: 1)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.9, blue: 0.55, alpha: 0.9))
        ctx.setLineWidth(max(1, size * 0.08))
        ctx.setLineCap(.round)
        for k in 0..<6 {
            let a = Double(k) * .pi / 3 + time * 9
            let l = size * CGFloat(0.6 + 0.5 * abs(sin(time * 31 + Double(k))))
            ctx.move(to: CGPoint(x: p.x + cos(a) * size * 0.3, y: p.y + sin(a) * size * 0.3))
            ctx.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l))
        }
        ctx.strokePath()
    }
}

// MARK: - Running a hand game

/// The hand games used to declare their own screens; every game now does, through `Game`'s hooks (`readout`, `result`,
/// `onboarding`, `accent`, `warmUp`). The name stays for the games and tests that use it.
typealias HandGameScreens = Game

/// Runs a hand game: the shared runner and screens (`GameLens`), waiting for a hand rather than a body because its `needs` list
/// `.hands`. It keeps playing through a short loss of tracking and pauses, low in the picture, when the hands have been gone a while.
final class HandGameLens<G: Game>: GameLens<G> {}

/// Follows the palm and the five fingertips of each hand and says how fast each is moving. Tracking arrives about 25 times a second,
/// sometimes repeats a look, and trembles a little, so the speed is measured over a short window, not from one frame to the next:
/// a hand resting on the spot reads as still, and a quick poke reads as quick.
struct HandPokeTracker {
    /// One part of a hand that can touch something.
    struct Hitter: Equatable {
        var position: CGPoint
        /// Where it was a frame ago, so a quick poke that crosses a target between two frames still lands.
        var previous: CGPoint
        /// Pixels a second.
        var speed: Double
        /// How big the touching part is, in pixels: a fingertip is small and the palm is big.
        var radius: Double
        /// The palm length of the hand it belongs to, the yardstick for how fast is fast.
        var handSize: Double
        var hand: Int
        var isPalm: Bool

        /// The speed that counts as a poke, scaled to the hand so it reads the same near the camera and far from it.
        var pokeSpeed: Double { max(130, handSize * 1.3) }
        var isPoking: Bool { speed >= pokeSpeed }
    }

    /// How far back, in seconds, speed is measured.
    static let window = 0.16

    private struct Key: Hashable { var hand: Int; var slot: Int }
    private struct Sample { var time: Double; var point: CGPoint }
    private var trails: [Key: [Sample]] = [:]

    mutating func reset() { trails.removeAll() }

    /// The touching parts of every hand now in view. `now` is game time in seconds.
    mutating func update(_ hands: [HandState], now: Double) -> [Hitter] {
        var out: [Hitter] = []
        for hand in hands {
            let size = hand.size
            let parts: [(slot: Int, point: CGPoint, radius: Double, given: Double)] = [
                (0, hand.palm, size * 0.5, hypot(Double(hand.velocity.dx), Double(hand.velocity.dy))),
                (1, hand[.thumbTip], size * 0.2, 0),
                (2, hand[.indexTip], size * 0.22, hypot(Double(hand.tipVelocity.dx), Double(hand.tipVelocity.dy))),
                (3, hand[.middleTip], size * 0.22, 0),
                (4, hand[.ringTip], size * 0.2, 0),
                (5, hand[.littleTip], size * 0.18, 0),
            ]
            for part in parts {
                let key = Key(hand: hand.id, slot: part.slot)
                var trail = trails[key] ?? []
                // A hand that was lost for a moment, or jumped, starts a new trail: what happened in between is anyone's guess.
                if let last = trail.last, now - last.time > 0.25 || HandState.distance(last.point, part.point) > max(300, size * 3.5) {
                    trail.removeAll()
                }
                let previous = trail.last?.point ?? part.point
                trail.append(Sample(time: now, point: part.point))
                trail.removeAll { now - $0.time > Self.window + 0.1 }
                trails[key] = trail

                // Never over less than a tenth of a second, so a tremble between two neighbouring frames cannot pass for a poke.
                var own = 0.0
                if let reference = trail.first(where: { now - $0.time <= Self.window }), reference.time < now {
                    own = HandState.distance(reference.point, part.point) / max(0.1, now - reference.time)
                }
                out.append(Hitter(position: part.point, previous: previous, speed: max(own, part.given), radius: part.radius,
                                  handSize: size, hand: hand.id, isPalm: part.slot == 0))
            }
        }
        trails = trails.filter { ($0.value.last?.time ?? -1) > now - 0.5 }
        return out
    }
}
