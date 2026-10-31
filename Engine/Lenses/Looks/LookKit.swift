import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

typealias LookColour = (r: Double, g: Double, b: Double)

/// Pieces the look filters share: grain, vignettes, colour ramps, a camcorder clock and the little bits of on-screen text.
///
/// Nothing here keeps per-frame state, so every lens can use it freely.
enum LookKit {
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: Sizes

    /// `image` (which covers `rect`) moved to the origin and scaled down smoothly. Working small is the cheapest way to blur.
    static func shrink(_ image: CIImage, rect: CGRect, by factor: Double) -> CIImage {
        let moved = image.clampedToExtent().transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = moved
        lanczos.scale = Float(factor)
        lanczos.aspectRatio = 1
        let scaled = lanczos.outputImage ?? moved.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        return scaled.cropped(to: CGRect(x: 0, y: 0, width: (rect.width * factor).rounded(), height: (rect.height * factor).rounded()))
    }

    /// A small picture (origin at zero, `small` big) stretched back over `rect`.
    static func enlarge(_ image: CIImage, to rect: CGRect, from small: CGRect) -> CIImage {
        image.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: rect.width / small.width, y: rect.height / small.height))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            .cropped(to: rect)
    }

    static func size(of rect: CGRect, scaledBy factor: Double) -> CGRect {
        CGRect(x: 0, y: 0, width: (rect.width * factor).rounded(), height: (rect.height * factor).rounded())
    }

    // MARK: Colour

    /// Straight-line brightness change on all three channels: `gain * value + bias`, kept in range.
    static func levels(_ image: CIImage, gain: Double, bias: Double = 0) -> CIImage {
        let g = CGFloat(gain), b = CGFloat(bias)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: g, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: g, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: b, y: b, z: b, w: 0),
        ]).applyingFilter("CIColorClamp")
    }

    /// Every channel multiplied by its own factor, and a little colour added: the way to tint a grey picture.
    static func tint(_ image: CIImage, by c: LookColour, add: LookColour = (0, 0, 0)) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(c.r), y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: CGFloat(c.g), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(c.b), w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: CGFloat(add.r), y: CGFloat(add.g), z: CGFloat(add.b), w: 0),
        ]).applyingFilter("CIColorClamp")
    }

    /// Brightness of the picture in all three channels.
    static func grey(_ image: CIImage) -> CIImage {
        let weights = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": weights, "inputGVector": weights, "inputBVector": weights, "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
    }

    /// Core Image does its sums on light, which crushes the darks. Brightness as the eye sees it is `value ^ (1/2.2)`.
    static func perceptual(_ image: CIImage) -> CIImage { image.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 1 / 2.2]) }
    static func linear(_ image: CIImage) -> CIImage { image.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 2.2]) }

    static func screen(_ top: CIImage, over bottom: CIImage) -> CIImage {
        top.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: bottom])
    }

    static func multiply(_ top: CIImage, over bottom: CIImage) -> CIImage {
        top.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: bottom])
    }

    static func mix(_ a: LookColour, _ b: LookColour, _ f: Double) -> LookColour {
        (a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f)
    }

    static func ciColour(_ c: LookColour) -> CIColor { CIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), colorSpace: space) ?? .white }

    /// The light (what Core Image calculates with) that a brightness on the eye's scale stands for. 0.5 to the eye is only 0.21 of the light.
    static func lin(_ eye: Double) -> Double { eye <= 0.04045 ? eye / 12.92 : pow((eye + 0.055) / 1.055, 2.4) }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    // MARK: Noise

    private static let whiteNoise: CIImage = CIFilter.randomGenerator().outputImage ?? CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))

    /// Grey noise over `rect`, a different pattern for each `frame`. Each pixel is spread evenly between `mean - spread / 2` and
    /// `mean + spread / 2`. `size` is how many pixels a speck covers and `stretch` makes the specks wider than they are tall.
    static func noise(_ rect: CGRect, frame: Int, size: Double = 1, stretch: Double = 1, mean: Double = 0.5, spread: Double = 1) -> CIImage {
        let step = Double(((frame % 509) + 509) % 509)
        var image = whiteNoise.transformed(by: CGAffineTransform(translationX: CGFloat((step * 83.7).truncatingRemainder(dividingBy: 1021)),
                                                                 y: CGFloat((step * 47.3).truncatingRemainder(dividingBy: 1013))))
        if size != 1 || stretch != 1 { image = image.transformed(by: CGAffineTransform(scaleX: CGFloat(size * stretch), y: CGFloat(size))) }
        let k = CGFloat(spread), bias = CGFloat(mean - spread / 2)
        // The green channel only. The generator's alpha is random too and its colours aren't premultiplied by it, so make the
        // picture opaque first (without dividing by it) or the noise comes out lopsided.
        let pick = CIVector(x: 0, y: k, z: 0, w: 0)
        return image.cropped(to: rect).settingAlphaOne(in: rect).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": pick, "inputGVector": pick, "inputBVector": pick, "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1),
        ]).applyingFilter("CIColorClamp")
    }

    /// Scattered dots of one colour on a clear layer, for snow, dust and sparkle. `coverage` is the share of pixels that are lit.
    static func speckle(_ rect: CGRect, frame: Int, coverage: Double, strength: Double, size: Double = 1, stretch: Double = 1,
                        colour: LookColour = (1, 1, 1)) -> CIImage {
        let field = noise(rect, frame: frame, size: size, stretch: stretch)
        let k = CGFloat(strength / coverage)
        let pick = CIVector(x: 0, y: 0, z: 0, w: 0)
        return field.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": pick, "inputGVector": pick, "inputBVector": pick, "inputAVector": CIVector(x: k, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: CGFloat(colour.r), y: CGFloat(colour.g), z: CGFloat(colour.b), w: -k * CGFloat(1 - coverage)),
        ]).applyingFilter("CIColorClamp").cropped(to: rect)
    }

    /// Film grain: noise laid over the picture so it lightens and darkens it and changes nothing on average.
    static func grained(_ image: CIImage, frame: Int, rect: CGRect, amount: Double, size: Double = 1.4) -> CIImage {
        noise(rect, frame: frame, size: size, spread: amount)
            .applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }

    /// Grain the way film has it: worked on the eye's scale, so it shows most in the middle tones and the shadows and fades out in
    /// pure black and white, with soft clumps rather than single pixels. `chroma` (0...1) lets each colour layer of the film have
    /// grain of its own, as colour stock does.
    static func filmGrain(_ image: CIImage, frame: Int, rect: CGRect, amount: Double, size: Double = 1.3, chroma: Double = 0) -> CIImage {
        var grain = noise(rect, frame: frame, size: size, spread: amount)
        if chroma > 0 {
            let step = Double(((frame % 499) + 499) % 499)
            let raw = whiteNoise.transformed(by: CGAffineTransform(translationX: CGFloat((step * 61.3).truncatingRemainder(dividingBy: 997)),
                                                                   y: CGFloat((step * 29.9).truncatingRemainder(dividingBy: 991))))
                .transformed(by: CGAffineTransform(scaleX: CGFloat(size), y: CGFloat(size)))
                .cropped(to: rect).settingAlphaOne(in: rect)
            let k = CGFloat(amount * chroma), bias = CGFloat(0.5 - amount * chroma / 2)
            let colour = raw.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1),
            ])
            grain = mixImages(grain, colour, 0.5)
        }
        let eye = perceptual(image)
        return linear(grain.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: eye])).cropped(to: rect)
    }

    /// `a` and `b` mixed: 0 is all `a`, 1 all `b`.
    static func mixImages(_ a: CIImage, _ b: CIImage, _ f: Double) -> CIImage {
        a.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: b, kCIInputTimeKey: f])
    }

    /// `top` where the mask is white, `bottom` where it is black.
    static func blend(_ top: CIImage, over bottom: CIImage, mask: CIImage) -> CIImage {
        let blend = CIFilter.blendWithMask()
        blend.inputImage = top
        blend.backgroundImage = bottom
        blend.maskImage = mask
        return blend.outputImage ?? top
    }

    // MARK: Light

    /// A round falloff to multiply over a picture: 1 in the middle, `edge` at the corners. `inner` and `outer` are fractions of the half-diagonal.
    static func vignette(_ rect: CGRect, inner: Double, outer: Double, edge: Double) -> CIImage {
        let reach = (rect.width * rect.width + rect.height * rect.height).squareRoot() / 2
        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: rect.midX, y: rect.midY)
        gradient.radius0 = Float(reach * inner)
        gradient.radius1 = Float(reach * outer)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
        gradient.color1 = CIColor(red: CGFloat(edge), green: CGFloat(edge), blue: CGFloat(edge))
        return (gradient.outputImage ?? CIImage(color: .white)).cropped(to: rect)
    }

    /// An oval falloff to multiply over a picture, shaped to the frame rather than a circle: 1 in the middle and `edge` in the
    /// corners, reached smoothly. `reach` (0...1) is how far out the darkening starts.
    static func ovalVignette(_ rect: CGRect, reach: Double, edge: Double) -> CIImage {
        let squash = rect.height / rect.width
        let gradient = CIFilter.radialGradient()
        gradient.center = .zero
        let r = rect.width / 2 * 1.42
        gradient.radius0 = Float(r * reach)
        gradient.radius1 = Float(r)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
        gradient.color1 = CIColor(red: CGFloat(edge), green: CGFloat(edge), blue: CGFloat(edge))
        return (gradient.outputImage ?? CIImage(color: .white))
            .transformed(by: CGAffineTransform(scaleX: 1, y: squash).concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY)))
            .cropped(to: rect)
    }

    /// The bright parts of a picture, spread into a soft glow: worked out at `scale` of the size, where blurring is cheap. Returns
    /// the glow alone, tinted, to screen over the picture. `threshold` is in light (0.5 light is about 0.73 to the eye).
    static func glow(_ image: CIImage, rect: CGRect, threshold: Double, sigma: Double, tint: LookColour = (1, 1, 1), scale: Double = 0.25) -> CIImage {
        let small = size(of: rect, scaledBy: scale)
        let bright = levels(shrink(image, rect: rect, by: scale), gain: 1 / max(0.05, 1 - threshold), bias: -threshold / max(0.05, 1 - threshold))
        let soft = bright.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: small)
        return LookKit.tint(enlarge(soft, to: rect, from: small), by: tint)
    }

    /// Colour fringes towards the edges, as a cheap lens gives: red spreads outwards and blue inwards, `pixels` apart in the corners.
    static func fringe(_ image: CIImage, rect: CGRect, pixels: Double) -> CIImage {
        let reach = (rect.width * rect.width + rect.height * rect.height).squareRoot() / 2
        func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, scale: Double) -> CIImage {
            let only = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            guard scale != 1 else { return only }
            let around = CGAffineTransform(translationX: -rect.midX, y: -rect.midY).concatenating(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
                .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
            return only.clampedToExtent().transformed(by: around).cropped(to: rect)
        }
        let k = pixels / reach
        return screen(channel(1, 0, 0, scale: 1 + k), over: screen(channel(0, 1, 0, scale: 1), over: channel(0, 0, 1, scale: 1 - k))).cropped(to: rect)
    }

    /// Dark lines across the picture, `period` pixels apart.
    static func scanlines(_ rect: CGRect, period: Double, darkness: Double) -> CIImage {
        let lines = CIFilter.stripesGenerator()
        lines.center = .zero
        lines.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(darkness))
        lines.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        lines.width = Float(period / 2)
        lines.sharpness = 1
        return (lines.outputImage ?? CIImage(color: .clear)).transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: rect)
    }

    // MARK: Colour ramps

    /// A strip of colour, left to right, for looking a brightness up in. `stops` are positions 0...1 and sRGB colours.
    static func ramp(_ stops: [(Double, LookColour)], width: Int = 256) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let colours = stops.compactMap { CGColor(colorSpace: space, components: [CGFloat($0.1.r), CGFloat($0.1.g), CGFloat($0.1.b), 1]) } as CFArray
        let places = stops.map { CGFloat($0.0) }
        guard let gradient = CGGradient(colorsSpace: space, colors: colours, locations: places) else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        return context.makeImage()
    }

    /// The picture's brightness (0 black ... 1 white) turned into the colours of `ramp`.
    static func colourise(_ brightness: CIImage, with ramp: CIImage) -> CIImage {
        brightness.applyingFilter("CIColorMap", parameters: ["inputGradientImage": ramp])
    }

    // MARK: On-screen display

    enum Anchor { case leading, centre, trailing }

    /// Monospaced text with an optional glow, in the way of a camera's on-screen display. `point` is the lower edge of the text.
    static func text(_ string: String, in ctx: CGContext, at point: CGPoint, size: CGFloat, colour: NSColor, weight: NSFont.Weight = .semibold,
                     tracking: CGFloat = 0, glow: NSColor? = nil, edge: NSColor? = nil, anchor: Anchor = .leading) {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: colour, .kern: tracking])
        let width = attributed.size().width
        let x: CGFloat
        switch anchor {
        case .leading: x = point.x
        case .centre: x = point.x - width / 2
        case .trailing: x = point.x - width
        }
        ctx.saveGState()
        if let glow { ctx.setShadow(offset: .zero, blur: size * 0.3, color: glow.cgColor) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        if let edge {
            // A dark copy just below and to the right, so the text reads on any picture.
            let shadow = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: edge, .kern: tracking])
            shadow.draw(at: NSPoint(x: x + size * 0.07, y: point.y - size * 0.07))
        }
        attributed.draw(at: NSPoint(x: x, y: point.y))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    /// Draws into a fresh full-size layer of its own (not one of the shared overlay buffers) and keeps it as a picture, for things
    /// that only change now and then.
    static func render(size: CGSize, _ draw: (CGContext) -> Void) -> CIImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: Sprites.bitmapInfo) else { return nil }
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }

    /// Four corner marks, like a viewfinder.
    static func cornerMarks(in ctx: CGContext, rect: CGRect, length: CGFloat, width: CGFloat, colour: CGColor) {
        ctx.saveGState()
        ctx.setStrokeColor(colour)
        ctx.setLineWidth(width)
        ctx.setLineCap(.butt)
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            ctx.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
            ctx.addLine(to: corner)
            ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * length))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// A small solid triangle pointing right: "play".
    static func playMark(in ctx: CGContext, at point: CGPoint, height: CGFloat, colour: CGColor, glow: CGColor? = nil) {
        ctx.saveGState()
        if let glow { ctx.setShadow(offset: .zero, blur: height * 0.3, color: glow) }
        ctx.setFillColor(colour)
        ctx.move(to: point)
        ctx.addLine(to: CGPoint(x: point.x, y: point.y + height))
        ctx.addLine(to: CGPoint(x: point.x + height * 0.9, y: point.y + height / 2))
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }
}

/// Counts seconds from when a look first draws, and turns that into what a camera would stamp on the picture.
struct LookClock {
    let startDate: Date
    private var first: Double?

    init(startDate: Date = Date()) { self.startDate = startDate }

    /// Seconds since the first call. The pipeline's own clock counts from when the Mac started, which is no use on screen.
    mutating func elapsed(at time: Double) -> Double {
        if first == nil { first = time }
        return max(0, time - (first ?? time))
    }

    mutating func restart() { first = nil }

    func date(after elapsed: Double) -> Date { startDate.addingTimeInterval(elapsed) }

    private static let timeFormat = format("h:mm:ss a")
    private static let dayFormat = format("MMM. d yyyy")

    private static func format(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter
    }

    /// "11:42:07 PM"
    static func time(_ date: Date) -> String { timeFormat.string(from: date) }

    /// "OCT. 30 2026"
    static func day(_ date: Date) -> String { dayFormat.string(from: date).uppercased() }

    /// "0:01:23", a tape counter.
    static func counter(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds))
        return String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
    }

    /// "00:01:23:07", hours, minutes, seconds and frames.
    static func timecode(_ seconds: Double, fps: Int = 30) -> String {
        let whole = Int(max(0, seconds))
        let frames = Int((max(0, seconds) - Double(whole)) * Double(fps))
        return String(format: "%02d:%02d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60, min(frames, fps - 1))
    }
}

/// Keeps an on-screen display as a picture until what it says changes, so the words are not redrawn thirty times a second.
final class LookDisplayCache {
    private var key: String?
    private var image: CIImage?

    /// The display for `key`: the same picture again if the key is unchanged, otherwise drawn afresh.
    func layer(_ key: String, size: CGSize, draw: (CGContext) -> Void) -> CIImage? {
        if key != self.key || image == nil {
            image = LookKit.render(size: size, draw)
            self.key = key
        }
        return image
    }

    func reset() { key = nil; image = nil }
}

/// A colour grade written as a plain function on the eye's scale (sRGB, 0...1 in and out), baked into a lookup cube the first
/// time it is used, which is on the video queue rather than while the lens is being made.
final class LookGrade {
    let size: Int
    private let function: (SIMD3<Float>) -> SIMD3<Float>
    private var table: Data?
    private let lock = NSLock()

    init(size: Int = 32, _ function: @escaping (SIMD3<Float>) -> SIMD3<Float>) {
        self.size = size
        self.function = function
    }

    /// The cube, baked on first use.
    var data: Data {
        lock.lock(); defer { lock.unlock() }
        if let table { return table }
        let n = size
        var values = [Float](repeating: 1, count: n * n * n * 4)
        var i = 0
        let step = 1 / Float(n - 1)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let out = simd_clamp(function(SIMD3<Float>(Float(r) * step, Float(g) * step, Float(b) * step)), SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
                    values[i] = out.x; values[i + 1] = out.y; values[i + 2] = out.z
                    i += 4
                }
            }
        }
        let made = values.withUnsafeBufferPointer { Data(buffer: $0) }
        table = made
        return made
    }

    func apply(_ image: CIImage) -> CIImage {
        image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": size, "inputCubeData": data, "inputColorSpace": LookKit.space,
        ])
    }

    /// `inside` where the mask is white and `self` where it is black, in one pass: one grade for you and another for the room.
    func apply(_ image: CIImage, inside: LookGrade, mask: CIImage) -> CIImage {
        guard inside.size == size else { return LookKit.blend(inside.apply(image), over: apply(image), mask: mask) }
        return image.applyingFilter("CIColorCubesMixedWithMask", parameters: [
            "inputMaskImage": mask, "inputCubeDimension": size, "inputCube0Data": data, "inputCube1Data": inside.data, "inputColorSpace": LookKit.space,
        ])
    }
}

/// Small sums for writing grades, all on the eye's scale.
enum LookTone {
    static let weights = SIMD3<Float>(0.2126, 0.7152, 0.0722)

    static func luma(_ c: SIMD3<Float>) -> Float { simd_dot(c, weights) }

    static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ f: Float) -> SIMD3<Float> { a + (b - a) * f }

    /// More or less colourful around the colour's own brightness. 1 leaves it alone, 0 is grey.
    static func saturate(_ c: SIMD3<Float>, _ amount: Float) -> SIMD3<Float> {
        let grey = SIMD3<Float>(repeating: luma(c))
        return grey + (c - grey) * amount
    }

    /// A film-like curve: a soft toe that keeps detail in the shadows, a firm middle and a shoulder that rolls the whites off
    /// gently instead of clipping. `contrast` around 1...1.6; `black` and `white` are where the curve starts and ends.
    static func filmic(_ x: Float, contrast: Float, black: Float = 0, white: Float = 1, pivot: Float = 0.45) -> Float {
        let t = min(1, max(0, x))
        let s: Float
        if t < pivot {
            let u = t / pivot
            s = pivot * powf(u, contrast)
        } else {
            let u = (1 - t) / (1 - pivot)
            s = 1 - (1 - pivot) * powf(u, contrast)
        }
        return black + (white - black) * s
    }

    static func filmic(_ c: SIMD3<Float>, contrast: Float, black: Float = 0, white: Float = 1, pivot: Float = 0.45) -> SIMD3<Float> {
        SIMD3<Float>(filmic(c.x, contrast: contrast, black: black, white: white, pivot: pivot),
                     filmic(c.y, contrast: contrast, black: black, white: white, pivot: pivot),
                     filmic(c.z, contrast: contrast, black: black, white: white, pivot: pivot))
    }

    /// Hue (0..<1), saturation and value.
    static func hsv(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let maxC = max(c.x, max(c.y, c.z)), minC = min(c.x, min(c.y, c.z))
        let d = maxC - minC
        var h: Float = 0
        if d > 1e-5 {
            if maxC == c.x { h = (c.y - c.z) / d } else if maxC == c.y { h = 2 + (c.z - c.x) / d } else { h = 4 + (c.x - c.y) / d }
            h /= 6
            if h < 0 { h += 1 }
        }
        return SIMD3<Float>(h, maxC > 1e-5 ? d / maxC : 0, maxC)
    }

    static func rgb(hsv: SIMD3<Float>) -> SIMD3<Float> {
        let h = (hsv.x - floorf(hsv.x)) * 6, s = hsv.y, v = hsv.z
        let i = Int(h) % 6, f = h - floorf(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return SIMD3(v, t, p)
        case 1: return SIMD3(q, v, p)
        case 2: return SIMD3(p, v, t)
        case 3: return SIMD3(p, q, v)
        case 4: return SIMD3(t, p, v)
        default: return SIMD3(v, p, q)
        }
    }

    /// How much a colour looks like skin, 0...1, from its hue and how colourful it is, so it works for every skin tone.
    static func skinness(_ c: SIMD3<Float>) -> Float {
        let hsv = hsv(c)
        let hue = hsv.x > 0.5 ? hsv.x - 1 : hsv.x
        let inHue = smooth(-0.06, -0.01, hue) * (1 - smooth(0.10, 0.15, hue))
        let inSat = smooth(0.12, 0.22, hsv.y) * (1 - smooth(0.70, 0.85, hsv.y))
        let inValue = smooth(0.12, 0.25, hsv.z)
        return inHue * inSat * inValue
    }

    static func colour(_ c: LookColour) -> SIMD3<Float> { SIMD3<Float>(Float(c.r), Float(c.g), Float(c.b)) }
}

/// A texture that takes a while to work out (paper, canvas, lead), made once on a background queue so the first frame of a look
/// never waits for it. Until it is ready the look carries on with the slow recipe itself, which Core Image works out on the fly.
final class LookBake {
    /// Tests set this so pictures are judged with the finished texture, not the stand-in.
    static var waitsInline = false

    private let lock = NSLock()
    private var made: CIImage?
    private var key: String?
    private var busy = false

    /// The finished texture for `key`, or `recipe` itself while it is being made.
    func image(_ key: String, rect: CGRect, context: CIContext, recipe: @escaping () -> CIImage) -> CIImage {
        lock.lock()
        if self.key == key, let made { lock.unlock(); return made }
        let start = !busy
        if start { busy = true; self.key = key; made = nil }
        lock.unlock()
        let bake = { [weak self] in
            let image = recipe()
            let flat = context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: LookKit.space).map { CIImage(cgImage: $0) }
            guard let self else { return }
            self.lock.lock()
            self.made = flat ?? image
            self.busy = false
            self.lock.unlock()
        }
        if start {
            if Self.waitsInline { bake(); return image(key, rect: rect, context: context, recipe: recipe) }
            DispatchQueue.global(qos: .userInitiated).async(execute: bake)
        }
        return recipe()
    }

    func reset() { lock.lock(); if !busy { made = nil; key = nil }; lock.unlock() }
}
