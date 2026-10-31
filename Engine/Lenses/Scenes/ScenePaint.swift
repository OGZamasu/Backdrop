import AppKit
import CoreGraphics
import Foundation

/// A picture painted once, with the place in the frame where it goes.
struct SceneLayer {
    var image: CGImage
    /// Where its lower left corner sits in the frame.
    var origin: CGPoint
    /// How far it slides, in pixels, as the person moves from the middle to the edge of the picture.
    var parallax: Double

    /// Copies the layer onto the picture. Drawing with a fade is several times slower than a plain copy, so a layer that should be
    /// see-through is made so once, with `faded`.
    func draw(in ctx: CGContext, shift: CGPoint) {
        ctx.draw(image, in: CGRect(x: (origin.x + shift.x * parallax).rounded(), y: (origin.y + shift.y * parallax * 0.4).rounded(),
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
    }

    /// The same layer, made see-through once and for all.
    func faded(_ alpha: Double) -> SceneLayer {
        let image = ScenePaint.picture(width: self.image.width, height: self.image.height) { ctx in
            ctx.setAlpha(CGFloat(alpha))
            ctx.draw(self.image, in: CGRect(x: 0, y: 0, width: self.image.width, height: self.image.height))
        } ?? self.image
        return SceneLayer(image: image, origin: origin, parallax: parallax)
    }
}

/// Work done a piece at a time on the video queue before a scene's first frame, so that making a scene is instant and no single frame
/// waits long for it.
final class SceneBakery {
    private var steps: [() -> Void]

    init(_ steps: [() -> Void]) { self.steps = steps.reversed() }

    var isDone: Bool { steps.isEmpty }

    /// Runs steps until `deadline` (a `CFAbsoluteTimeGetCurrent` time) has passed, at least one. True once nothing is left.
    func run(until deadline: Double) -> Bool {
        while let step = steps.popLast() {
            step()
            if CFAbsoluteTimeGetCurrent() >= deadline { break }
        }
        return steps.isEmpty
    }
}

/// One big opaque picture painted over several steps: the sky in one, the hills in the next, and so on.
final class SceneCanvas {
    private var context: CGContext?
    private let rect: CGRect

    init(_ rect: CGRect) {
        self.rect = rect
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        context = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height), bitsPerComponent: 8, bytesPerRow: 0, space: ScenePaint.space, bitmapInfo: info)
        context?.setAllowsAntialiasing(true)
        context?.interpolationQuality = .high
        context?.translateBy(x: -rect.minX, y: -rect.minY)
    }

    func paint(_ draw: (CGContext) -> Void) {
        guard let context else { return }
        context.saveGState()
        draw(context)
        context.restoreGState()
    }

    /// The finished picture, as a layer; the canvas is let go.
    func finish(parallax: Double) -> SceneLayer? {
        guard let image = context?.makeImage() else { return nil }
        context = nil
        return SceneLayer(image: image, origin: rect.origin, parallax: parallax)
    }
}

/// Small tools for painting scenery with Core Graphics: gradients, soft blobs, ridges, trees. Everything is drawn once at set-up
/// into cached pictures, so none of this runs per frame.
enum ScenePaint {
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func color(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, CGFloat(alpha)])!
    }

    /// A mix of two colours, 0 for `a` and 1 for `b`.
    static func mix(_ a: UInt32, _ b: UInt32, _ k: Double, alpha: Double = 1) -> CGColor {
        func channel(_ shift: UInt32) -> CGFloat {
            let x = Double((a >> shift) & 255), y = Double((b >> shift) & 255)
            return CGFloat((x + (y - x) * k) / 255)
        }
        return CGColor(colorSpace: space, components: [channel(16), channel(8), channel(0), CGFloat(alpha)])!
    }

    /// A bitmap in the canvas's own pixel layout, painted in frame coordinates: `rect` is the part of the frame it covers.
    static func layer(_ rect: CGRect, parallax: Double = 0, opaque: Bool = false, _ draw: (CGContext) -> Void) -> SceneLayer? {
        guard let image = picture(width: Int(rect.width), height: Int(rect.height), opaque: opaque, { ctx in
            ctx.translateBy(x: -rect.minX, y: -rect.minY)
            draw(ctx)
        }) else { return nil }
        return SceneLayer(image: image, origin: rect.origin, parallax: parallax)
    }

    /// A bitmap in the canvas's own pixel layout. An `opaque` one has no alpha at all, which Core Graphics copies onto the canvas much faster.
    static func picture(width: Int, height: Int, opaque: Bool = false, _ draw: (CGContext) -> Void) -> CGImage? {
        let info = opaque ? CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue : Sprites.bitmapInfo
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
        else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()
    }

    static func gradient(_ stops: [(Double, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map { CGFloat($0.0) })!
    }

    /// Fills a rectangle with a gradient from `from` to `to` (frame points).
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

    /// A soft elliptical glow: `color` in the middle, fading to nothing at the edge.
    static func blob(_ ctx: CGContext, _ centre: CGPoint, rx: Double, ry: Double, _ color: CGColor, inner: Double = 0, alpha: Double = 1) {
        guard rx > 0.5, ry > 0.5 else { return }
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

    /// A hard-edged ellipse.
    static func oval(_ ctx: CGContext, _ centre: CGPoint, rx: Double, ry: Double, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: centre.x - rx, y: centre.y - ry, width: rx * 2, height: ry * 2))
    }

    /// The hex colour between two hex colours.
    static func mixHex(_ a: UInt32, _ b: UInt32, _ k: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 255), y = Double((b >> shift) & 255)
            return UInt32(max(0, min(255, (x + (y - x) * k).rounded())))
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }

    /// Smooth one-dimensional noise, 0...1, the same for the same `x` and `seed`.
    static func noise(_ x: Double, _ seed: Double = 0) -> Double {
        func hash(_ n: Int) -> Double {
            var h = UInt64(bitPattern: Int64(n)) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(bitPattern: Int64(max(-9e15, min(9e15, seed * 1000 + 7))))
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

    /// The outline of a ridge line across `rect`, closed along the bottom.
    static func ridgePath(width: Double, left: Double, baseY: Double, bottom: Double, amplitude: Double, wavelength: Double, seed: Double) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left, y: bottom))
        var x = left
        while x <= left + width + 8 {
            path.addLine(to: CGPoint(x: x, y: baseY + (hills((x - left) / wavelength, seed: seed) - 0.5) * 2 * amplitude))
            x += 8
        }
        path.addLine(to: CGPoint(x: left + width + 8, y: bottom))
        path.closeSubpath()
        return path
    }

    /// A random-number generator that gives the same scenery every time.
    static func generator(_ seed: UInt64) -> SceneRandom { SceneRandom(seed: seed) }

    // MARK: Plants

    /// One blade of grass: a thin curved stroke.
    static func blade(_ ctx: CGContext, at base: CGPoint, height: Double, lean: Double, width: Double, color: CGColor) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(CGFloat(width))
        ctx.setLineCap(.round)
        ctx.move(to: base)
        ctx.addQuadCurve(to: CGPoint(x: base.x + lean, y: base.y + height), control: CGPoint(x: base.x + lean * 0.1, y: base.y + height * 0.6))
        ctx.strokePath()
    }

    /// A tapered leaf: pointed at both ends, bowed. `angle` is the direction of its tip, in radians.
    static func leaf(_ ctx: CGContext, from base: CGPoint, angle: Double, length: Double, width: Double, bend: Double = 0.0, color: CGColor) {
        let tip = CGPoint(x: base.x + cos(angle) * length, y: base.y + sin(angle) * length)
        let normal = CGPoint(x: -sin(angle), y: cos(angle))
        let mid = CGPoint(x: (base.x + tip.x) / 2 + normal.x * bend * length, y: (base.y + tip.y) / 2 + normal.y * bend * length)
        let path = CGMutablePath()
        path.move(to: base)
        path.addQuadCurve(to: tip, control: CGPoint(x: mid.x + normal.x * width, y: mid.y + normal.y * width))
        path.addQuadCurve(to: base, control: CGPoint(x: mid.x - normal.x * width, y: mid.y - normal.y * width))
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }

    /// A palm or fern frond: a curved stem with leaflets down both sides.
    static func frond(_ ctx: CGContext, base: CGPoint, angle: Double, length: Double, droop: Double, leaflets: Int, leafLength: Double,
                      stem: CGColor, leafColor: CGColor, highlight: CGColor? = nil) {
        // The stem starts at `angle` and bends toward the ground by `droop`, whichever way it points.
        let bend = droop * (cos(angle) >= 0 ? 1 : -1)
        // Where the stem is a fraction `k` of the way along, and which way it points there.
        func point(_ k: Double) -> (p: CGPoint, a: Double) {
            let steps = 14
            var p = base
            for i in 0..<steps {
                let along = Double(i) / Double(steps) * k
                let heading = angle - bend * along * along
                p.x += cos(heading) * length * k / Double(steps)
                p.y += sin(heading) * length * k / Double(steps)
            }
            return (p, angle - bend * k * k)
        }
        ctx.setStrokeColor(stem)
        ctx.setLineWidth(max(1.5, length * 0.012))
        ctx.setLineCap(.round)
        ctx.move(to: base)
        for i in 1...16 { ctx.addLine(to: point(Double(i) / 16).p) }
        ctx.strokePath()
        for i in 1...leaflets {
            let k = Double(i) / Double(leaflets + 1) * 0.97 + 0.03
            let (p, a) = point(k)
            let size = leafLength * (1 - 0.6 * abs(k - 0.45)) * (1 - 0.35 * k)
            for side in [-1.0, 1.0] {
                let la = a + side * (1.15 - 0.35 * k)
                leaf(ctx, from: p, angle: la, length: size, width: size * 0.17, bend: side * 0.06, color: leafColor)
                if let highlight, side > 0 { leaf(ctx, from: p, angle: la, length: size * 0.7, width: size * 0.07, bend: side * 0.06, color: highlight) }
            }
        }
    }
}
