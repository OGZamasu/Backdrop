import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

// The shared toolkit every built-in backdrop is made with, so they look like one family:
// - `BackdropFinish`: grain and dither, the last step of every backdrop, so gradients never band in an 8-bit video frame.
// - `BackdropNoise`: smooth noise, ready made, for clouds, marble, mist, water and the like (worked on by the GPU).
// - `BackdropInk`: colour helpers (Oklab mixing, colour tables for Core Image).
// - `BackdropPainter`: Core Graphics helpers for painting stills: deep (16-bit) canvases, soft light, soft shadows.
// - `BackdropStillSource`: a backdrop that is painted once and then shown as it is, at no cost per frame.

// MARK: - Finish: grain and dither

enum BackdropFinish {
    /// A 128 x 128 tile of noise. Red, green and blue hold independent triangular noise (for dither); alpha is 1.
    /// A second tile holds the same noise in all three channels (for grain, which should not be coloured).
    private static let tiles: (dither: CIImage, grain: CIImage) = {
        let side = 128
        var rng = SplitMix64(seed: 0xD17E_A11)
        var colour = [UInt8](repeating: 255, count: side * side * 4)
        var grey = [UInt8](repeating: 255, count: side * side * 4)
        for i in 0..<(side * side) {
            for c in 0..<3 {
                // Two uniform draws added: triangular noise, which hides 8-bit steps without adding a hiss of its own.
                let t = (Double.random(in: 0..<1, using: &rng) + Double.random(in: 0..<1, using: &rng)) * 0.5
                colour[i * 4 + c] = UInt8(min(255, max(0, (t * 255).rounded())))
            }
            let g = (Double.random(in: 0..<1, using: &rng) + Double.random(in: 0..<1, using: &rng)) * 0.5
            let byte = UInt8(min(255, max(0, (g * 255).rounded())))
            grey[i * 4] = byte; grey[i * 4 + 1] = byte; grey[i * 4 + 2] = byte
        }
        func image(_ bytes: [UInt8]) -> CIImage {
            let tile = CIImage(bitmapData: Data(bytes), bytesPerRow: side * 4, size: CGSize(width: side, height: side), format: .RGBA8, colorSpace: nil)
            let repeated = CIFilter.affineTile()
            repeated.inputImage = tile
            repeated.transform = .identity
            return repeated.outputImage ?? tile
        }
        return (image(colour), image(grey))
    }()

    /// The last step for every backdrop. Adds `grain` (0 none, 1 a fine film grain, up to 3 for a heavy one) and one step of
    /// 8-bit dither, both measured in steps of the output picture so they are as strong in the shadows as in the highlights.
    /// The noise is fixed in place, so a still backdrop stays perfectly still and costs a video encoder nothing extra.
    static func finish(_ image: CIImage, grain: Double = 0) -> CIImage {
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite, !extent.isEmpty else { return image }
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        let step = 1.0 / 255.0
        // Dither: plus or minus one output step. Grain: a few steps of grey.
        let dither = 2 * step
        let grainSpan = 4 * step * grain
        var noise = tiles.dither.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: dither, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: dither, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: dither, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        if grain > 0 {
            let grey = tiles.grain.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: grainSpan, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: grainSpan, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: grainSpan, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            noise = grey.applyingFilter("CILinearDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: noise])
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        }
        let centre = -(dither + (grain > 0 ? grainSpan : 0)) / 2
        let noisy = noise.cropped(to: extent)
            .applyingFilter("CILinearDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: encoded])
            .applyingFilter("CIColorMatrix", parameters: ["inputBiasVector": CIVector(x: centre, y: centre, z: centre, w: 0)])
        return noisy.applyingFilter("CISRGBToneCurveToLinear").cropped(to: extent)
    }

    /// Corners darkened by up to `strength` (0...1), the way a lens darkens them. Centred a little above the middle,
    /// where a head usually is, so the eye is drawn there.
    static func vignette(_ image: CIImage, strength: Double, centre: CGPoint = CGPoint(x: 640, y: 400)) -> CIImage {
        let extent = image.extent
        let shade = CIFilter.radialGradient()
        shade.center = centre
        shade.radius0 = Float(extent.height * 0.42)
        shade.radius1 = Float(extent.width * 0.78)
        shade.color0 = CIColor(red: 1, green: 1, blue: 1)
        shade.color1 = CIColor(red: 1 - strength, green: 1 - strength, blue: 1 - strength)
        guard let mask = shade.outputImage?.cropped(to: extent) else { return image }
        return image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask]).cropped(to: extent)
    }
}

// MARK: - Noise

/// Smooth noise for the GPU: three independent fields (red, green, blue), each spread over 0...1 around 0.5, in a tile that
/// repeats seamlessly every `period` pixels in both directions. Made once, in a few milliseconds, and shared by every backdrop.
enum BackdropNoise {
    static let period = 256

    /// The repeating tile, of infinite extent. Values are measurements, not colours: they are never colour-converted.
    static let tile: CIImage = {
        let repeated = CIFilter.affineTile()
        repeated.inputImage = baked
        repeated.transform = .identity
        return repeated.outputImage ?? baked
    }()

    /// One field (`channel` 0, 1 or 2) as a grey picture covering `extent`: `scale` enlarges the noise (bigger, softer
    /// shapes) and `offset` slides it, in output pixels. Offsets wrap around the tile, so a clock weeks old works.
    static func field(_ channel: Int, scale: CGFloat, offset: CGPoint = .zero, stretch: CGFloat = 1, extent: CGRect) -> CIImage {
        let span = CGFloat(period) * scale
        let ox = CGFloat(BackdropMath.fract(Double(offset.x / span))) * span
        let oy = CGFloat(BackdropMath.fract(Double(offset.y / (span * stretch)))) * span * stretch
        let pick = [CIVector(x: 1, y: 0, z: 0, w: 0), CIVector(x: 0, y: 1, z: 0, w: 0), CIVector(x: 0, y: 0, z: 1, w: 0)][max(0, min(2, channel))]
        return tile
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale * stretch).concatenating(CGAffineTransform(translationX: -ox, y: -oy)))
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": pick, "inputGVector": pick, "inputBVector": pick,
                                                          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
            .cropped(to: extent)
    }

    /// The tile itself, period x period, as 32-bit floats.
    private static let baked: CIImage = {
        let P = period
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var rng = SplitMix64(seed: 0x5EED_0F_A1)
        // Octaves: a coarse lattice of random values, enlarged smoothly; finer lattices add detail at lower strength.
        let octaves: [(cells: Int, weight: CGFloat)] = [(4, 0.52), (8, 0.27), (16, 0.13), (32, 0.06), (64, 0.03)]
        var total: CIImage?
        for octave in octaves {
            let cells = octave.cells, pad = 3, side = cells + 2 * pad
            var lattice = [Float](repeating: 0, count: cells * cells * 3)
            for i in lattice.indices { lattice[i] = Float.random(in: 0...1, using: &rng) }
            var pixels = [Float](repeating: 1, count: side * side * 4)
            for y in 0..<side {
                for x in 0..<side {
                    // Wrapped, so the enlarged lattice joins up with itself at the tile's edges.
                    let lx = ((x - pad) % cells + cells) % cells, ly = ((y - pad) % cells + cells) % cells
                    for c in 0..<3 { pixels[(y * side + x) * 4 + c] = lattice[(ly * cells + lx) * 3 + c] }
                }
            }
            let small = CIImage(bitmapData: Data(bytes: pixels, count: pixels.count * 4), bytesPerRow: side * 16,
                                size: CGSize(width: side, height: side), format: .RGBAf, colorSpace: nil)
            let s = CGFloat(P) / CGFloat(cells)
            let enlarge = CIFilter.bicubicScaleTransform()
            enlarge.inputImage = small
            enlarge.scale = Float(s)
            enlarge.aspectRatio = 1
            enlarge.parameterB = 0
            enlarge.parameterC = 0.5
            guard let big = enlarge.outputImage else { continue }
            let window = big.cropped(to: CGRect(x: CGFloat(pad) * s, y: CGFloat(pad) * s, width: CGFloat(P), height: CGFloat(P)))
                .transformed(by: CGAffineTransform(translationX: -CGFloat(pad) * s, y: -CGFloat(pad) * s))
            let w = octave.weight
            let weighted = window.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: w, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: w, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: w, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            total = total.map { weighted.applyingFilter("CILinearDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: $0]) } ?? weighted
        }
        var values = [Float](repeating: 0.5, count: P * P * 4)
        if let total {
            context.render(total, toBitmap: &values, rowBytes: P * 16, bounds: CGRect(x: 0, y: 0, width: P, height: P), format: .RGBAf, colorSpace: nil)
        }
        // Spread each field so most of it covers 0...1 around 0.5: a sum of octaves bunches up in the middle.
        values.withUnsafeMutableBufferPointer { v in
            for c in 0..<3 {
                var sum: Float = 0, squares: Float = 0
                var i = c
                while i < v.count { sum += v[i]; squares += v[i] * v[i]; i += 4 }
                let n = Float(P * P)
                let mean = sum / n
                let spread = max(0.0001, (squares / n - mean * mean).squareRoot())
                i = c
                while i < v.count { v[i] = min(1, max(0, 0.5 + (v[i] - mean) / spread * 0.19)); i += 4 }
            }
            var i = 3
            while i < v.count { v[i] = 1; i += 4 }
        }
        return CIImage(bitmapData: Data(bytes: values, count: values.count * 4), bytesPerRow: P * 16,
                       size: CGSize(width: P, height: P), format: .RGBAf, colorSpace: nil)
    }()

    /// Cheap one-dimensional noise for outlines (ridges, skylines, dunes): a sum of sines at unrelated rates, -1...1.
    static func ridge(_ x: Double, seed: Double, octaves: Int = 5) -> Double {
        var total = 0.0, amplitude = 1.0, frequency = 1.0, norm = 0.0
        for k in 0..<octaves {
            let p = seed * (1.37 + Double(k) * 0.61)
            total += amplitude * (sin(x * frequency + p) * 0.6 + sin(x * frequency * 1.73 + p * 2.1) * 0.4)
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2.07
        }
        return total / norm
    }
}

// MARK: - Colour

/// A colour as red, green, blue in 0...1 (display values, as a designer would pick them).
struct BackdropRGB: Hashable {
    var r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(hex: UInt32) { self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255) }

    var cg: CGColor { BackdropPaint.color(r, g, b) }
    func cg(_ alpha: Double) -> CGColor { BackdropPaint.color(r, g, b, alpha) }
    /// Scaled toward black (`by` < 1) or past itself (> 1).
    func scaled(_ by: Double) -> BackdropRGB { BackdropRGB(min(1, r * by), min(1, g * by), min(1, b * by)) }
    /// Mixed toward `other` by `t`, in Oklab so the middle is neither muddy nor washed out.
    func mixed(_ other: BackdropRGB, _ t: Double) -> BackdropRGB { BackdropInk.mix(self, other, t) }
    var luminance: Double { 0.2126 * BackdropInk.linear(r) + 0.7152 * BackdropInk.linear(g) + 0.0722 * BackdropInk.linear(b) }
}

enum BackdropInk {
    static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func encoded(_ c: Double) -> Double { let c = max(0, c); return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    /// Display RGB to Oklab (L, a, b).
    static func oklab(_ c: BackdropRGB) -> SIMD3<Double> {
        let r = linear(c.r), g = linear(c.g), b = linear(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// Oklab back to linear RGB (not display values), unclamped.
    static func linearRGB(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        let l = pow(lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z, 3)
        let m = pow(lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z, 3)
        let s = pow(lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z, 3)
        return SIMD3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                     -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                     -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    static func mix(_ a: BackdropRGB, _ b: BackdropRGB, _ t: Double) -> BackdropRGB {
        let lab = oklab(a) + (oklab(b) - oklab(a)) * t
        let rgb = linearRGB(lab)
        return BackdropRGB(encoded(rgb.x), encoded(rgb.y), encoded(rgb.z))
    }

    /// A 256-entry colour table through `stops` (position 0...1, colour, alpha), mixed in Oklab, for `CIColorMap`.
    /// Floats, so the table itself cannot band.
    static func table(_ stops: [(at: Double, color: BackdropRGB, alpha: Double)]) -> CIImage {
        let n = 256
        var pixels = [Float](repeating: 0, count: n * 4)
        let sorted = stops.sorted { $0.at < $1.at }
        for i in 0..<n {
            let x = Double(i) / Double(n - 1)
            var lower = sorted[0], upper = sorted[sorted.count - 1]
            for k in 0..<(sorted.count - 1) where x >= sorted[k].at && x <= sorted[k + 1].at {
                lower = sorted[k]; upper = sorted[k + 1]; break
            }
            let span = max(0.00001, upper.at - lower.at)
            let t = min(1, max(0, (x - lower.at) / span))
            let c = mix(lower.color, upper.color, t)
            let a = lower.alpha + (upper.alpha - lower.alpha) * t
            // Premultiplied, linear light (the table is tagged linear below).
            pixels[i * 4] = Float(linear(c.r) * a)
            pixels[i * 4 + 1] = Float(linear(c.g) * a)
            pixels[i * 4 + 2] = Float(linear(c.b) * a)
            pixels[i * 4 + 3] = Float(a)
        }
        return CIImage(bitmapData: Data(bytes: pixels, count: pixels.count * 4), bytesPerRow: n * 16, size: CGSize(width: n, height: 1),
                       format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
    }

    static func table(_ stops: [(at: Double, color: BackdropRGB)]) -> CIImage {
        table(stops.map { (at: $0.at, color: $0.color, alpha: 1.0) })
    }

    /// `field` (grey, 0...1) coloured through `table`.
    static func colored(_ field: CIImage, _ table: CIImage) -> CIImage {
        let map = CIFilter.colorMap()
        map.inputImage = field
        map.gradientImage = table
        return (map.outputImage ?? field).cropped(to: field.extent)
    }
}

// MARK: - Painting stills

enum BackdropPainter {
    static let size = CGSize(width: 1280, height: 720)
    static let frame = CGRect(origin: .zero, size: size)

    /// A blank canvas. `deep` gives 16 bits a channel, so long, faint gradients come out smooth.
    static func canvas(width: Int = 1280, height: Int = 720, deep: Bool = true) -> CGContext? {
        let info = deep ? CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
                        : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: deep ? 16 : 8, bytesPerRow: 0,
                                  space: BackdropCanvas.space, bitmapInfo: info) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        return ctx
    }

    /// Paints with `draw` on a canvas of `width` x `height` and returns it as a picture the size of the output.
    /// A smaller canvas is enlarged smoothly: right for anything meant to look out of focus.
    static func paint(width: Int = 1280, height: Int = 720, deep: Bool = true, _ draw: (CGContext) -> Void) -> CIImage? {
        guard let ctx = canvas(width: width, height: height, deep: deep) else { return nil }
        if width != 1280 { ctx.scaleBy(x: CGFloat(width) / 1280, y: CGFloat(height) / 720) }
        draw(ctx)
        guard let image = ctx.makeImage() else { return nil }
        let picture = CIImage(cgImage: image)
        guard width != 1280 else { return picture }
        // Catmull-Rom: smooth and sharp when the canvas is nearly full size, and still smooth (never blocky) when a
        // small canvas is enlarged a long way.
        let enlarge = CIFilter.bicubicScaleTransform()
        enlarge.inputImage = picture.clampedToExtent().cropped(to: picture.extent.insetBy(dx: -8, dy: -8))
        enlarge.scale = Float(1280 / CGFloat(width))
        enlarge.aspectRatio = Float((720 / CGFloat(height)) / (1280 / CGFloat(width)))
        enlarge.parameterB = 0
        enlarge.parameterC = 0.5
        guard let big = enlarge.outputImage else { return nil }
        // Pixel centres: shift by half a source pixel so the enlarged picture lines up with the output.
        let shift = (1280 / CGFloat(width) - 1) / 2
        return big.transformed(by: CGAffineTransform(translationX: -shift, y: -shift * (720 / CGFloat(height)) / (1280 / CGFloat(width)))).cropped(to: frame)
    }

    /// A vertical run of colour from `bottom` to `top` through `stops` (0 at bottom).
    static func vertical(_ ctx: CGContext, _ rect: CGRect, _ stops: [(at: Double, color: BackdropRGB)]) {
        guard let g = BackdropPaint.gradient(stops.map { (at: $0.at, r: $0.color.r, g: $0.color.g, b: $0.color.b) }) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// A soft pool of light (or shade): `color` at `alpha` in the middle, nothing at `radius`. `squash` flattens it.
    static func glow(_ ctx: CGContext, at c: CGPoint, radius: CGFloat, color: BackdropRGB, alpha: Double, squash: CGFloat = 1,
                     blend: CGBlendMode = .normal) {
        guard radius > 0.5, let g = BackdropPaint.gradient([
            (at: 0, r: color.r, g: color.g, b: color.b, a: alpha), (at: 0.35, r: color.r, g: color.g, b: color.b, a: alpha * 0.62),
            (at: 0.7, r: color.r, g: color.g, b: color.b, a: alpha * 0.2), (at: 1, r: color.r, g: color.g, b: color.b, a: 0),
        ]) else { return }
        ctx.saveGState()
        ctx.setBlendMode(blend)
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: 1, y: squash)
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius, options: [])
        ctx.restoreGState()
    }

    /// Fills `path` with `color`, casting a soft shadow down and to the right (the light is always up and to the left).
    static func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, shadow: CGFloat = 0, shadowAlpha: Double = 0.35,
                     offset: CGSize = CGSize(width: 6, height: -8)) {
        ctx.saveGState()
        if shadow > 0 { ctx.setShadow(offset: offset, blur: shadow, color: BackdropPaint.color(0, 0, 0, shadowAlpha)) }
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// Fills `path` with a straight gradient from `from` to `to`.
    static func fill(_ ctx: CGContext, _ path: CGPath, gradient stops: [(at: Double, color: BackdropRGB)], from: CGPoint, to: CGPoint) {
        guard let g = BackdropPaint.gradient(stops.map { (at: $0.at, r: $0.color.r, g: $0.color.g, b: $0.color.b) }) else { return }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    static func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: min(radius, rect.width / 2), cornerHeight: min(radius, rect.height / 2), transform: nil)
    }

    /// A closed shape under a line of points, down to `floor`.
    static func ridge(_ points: [CGPoint], floor: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: floor))
        for p in points { path.addLine(to: p) }
        path.addLine(to: CGPoint(x: last.x, y: floor))
        path.closeSubpath()
        return path
    }

    /// A hill line across the whole width: `base` + `height` x noise, with detail from `rough` (0 smooth ... 1 jagged).
    static func ridgeLine(base: CGFloat, height: CGFloat, seed: Double, wavelength: Double = 380, rough: Double = 0.5,
                          step: CGFloat = 6) -> [CGPoint] {
        stride(from: -step, through: size.width + step, by: step).map { x in
            let n = BackdropNoise.ridge(Double(x) / wavelength, seed: seed, octaves: rough > 0.5 ? 7 : 4)
            let sharp = rough > 0.5 ? (1 - abs(BackdropNoise.ridge(Double(x) / wavelength * 0.7, seed: seed + 3, octaves: 6))) * 2 - 1 : n
            let v = n * (1 - rough * 0.5) + sharp * rough * 0.5
            return CGPoint(x: x, y: base + height * CGFloat(v * 0.5 + 0.5))
        }
    }

    /// Spreads very faint mottling over what is already painted, for paper, plaster and paint that are not dead flat.
    /// `amount` is how far it lightens and darkens (0.03 is subtle), `scale` how big the blotches are.
    static func mottle(_ image: CIImage, amount: Double, scale: CGFloat, channel: Int = 0, offset: CGPoint = .zero) -> CIImage {
        let field = BackdropNoise.field(channel, scale: scale, offset: offset, extent: image.extent)
        // Multiply by (1 - amount) ... (1 + amount) around the noise's middle.
        let k = 2 * amount
        let gain = field.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0), "inputBiasVector": CIVector(x: 1 - amount, y: 1 - amount, z: 1 - amount, w: 0),
        ])
        return image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: gain]).cropped(to: image.extent)
    }

    /// Light that drifts: `image` brightened and darkened by up to `amount` in broad soft patches that slide along at
    /// `speed` pixels a second. Dappled sun, lights shimmering through rain, firelight moving on a wall.
    static func shimmer(_ image: CIImage, at time: Double, amount: Double, scale: CGFloat, speed: CGPoint, channel: Int = 1) -> CIImage {
        mottle(image, amount: amount, scale: scale, channel: channel, offset: CGPoint(x: time * speed.x, y: time * speed.y))
    }

    /// The half-size working area: soft things (gas, light, caustics) are worked out here and enlarged with `enlarged`.
    static let half = CGRect(x: 0, y: 0, width: 640, height: 360)

    /// A half-size picture made full size again, smoothly (`sharp` keeps edges crisper).
    static func enlarged(_ image: CIImage, sharp: Bool = false) -> CIImage {
        let enlarge = CIFilter.bicubicScaleTransform()
        enlarge.inputImage = image.clampedToExtent()
        enlarge.scale = 2
        enlarge.aspectRatio = 1
        enlarge.parameterB = sharp ? 0 : 1
        enlarge.parameterC = sharp ? 0.5 : 0
        return (enlarge.outputImage ?? image).transformed(by: CGAffineTransform(translationX: -0.5, y: -0.5)).cropped(to: frame)
    }

    /// Out of focus by `sigma` pixels, edges held.
    static func defocus(_ image: CIImage, sigma: Double) -> CIImage {
        guard sigma > 0.05 else { return image }
        return image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: image.extent)
    }
}

// MARK: - Still source

/// A backdrop painted once, then shown unchanged: the picture is worked out on its first frame, flattened to a plain bitmap
/// (with its grain and dither already in it) and handed back every frame after, so it costs nothing to keep showing.
final class BackdropStillSource: BackgroundSource {
    private let make: () -> CIImage?
    private var cached: CIImage?

    init(_ make: @escaping () -> CIImage?) { self.make = make }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        if cached == nil { cached = BackdropBake.flatten(make()) }
        return cached
    }
}

extension BackdropBake {
    private static let flattenContext = CIContext(options: [.cacheIntermediates: false])

    /// Renders a still's whole recipe once into an ordinary 8-bit bitmap, so showing it again costs nothing.
    static func flatten(_ image: CIImage?) -> CIImage? {
        guard let image else { return nil }
        let rect = BackdropPainter.frame
        guard let cg = flattenContext.createCGImage(image, from: rect, format: .RGBA8, colorSpace: BackdropCanvas.space) else { return image }
        return CIImage(cgImage: cg)
    }
}

// MARK: - Scenes

/// A scene in two parts: a still painted once (grain and dither baked in), and for live scenes a moving part laid over it
/// each frame, worked out from the clock alone. Subclasses override `paint()` and, if they move, `animate(_:at:)`.
class BackdropScene: BackgroundSource {
    private var still: CIImage?

    /// The painted still, made on first use.
    final var backdrop: CIImage? {
        if still == nil { still = BackdropBake.flatten(paint()) }
        return still
    }

    /// The still part of the scene, at 1280 x 720. Called once.
    func paint() -> CIImage? { nil }

    /// The frame at `time`: the still with whatever moves laid over it. Still scenes leave this alone.
    func animate(_ still: CIImage, at time: Double) -> CIImage? { still }

    final func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        guard let still = backdrop else { return nil }
        return animate(still, at: time)?.cropped(to: BackdropPainter.frame)
    }
}

// MARK: - Sprites

/// Small pictures drawn once and stamped many times a frame.
enum BackdropSprite {
    /// A transparent `side` x `side` sprite, drawn by `draw` with the side length handed in.
    static func make(_ side: Int, _ draw: (CGContext, CGFloat) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: BackdropCanvas.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        draw(ctx, CGFloat(side))
        return ctx.makeImage()
    }

    /// A soft round glow: `core` alpha in the middle falling smoothly to nothing at the edge. `hot` adds a whiter centre.
    static func glow(_ color: BackdropRGB, side: Int = 64, core: Double = 1, hot: Double = 0) -> CGImage? {
        make(side) { ctx, s in
            let c = CGPoint(x: s / 2, y: s / 2)
            if let g = BackdropPaint.gradient([
                (at: 0, r: color.r, g: color.g, b: color.b, a: core), (at: 0.22, r: color.r, g: color.g, b: color.b, a: core * 0.55),
                (at: 0.5, r: color.r, g: color.g, b: color.b, a: core * 0.16), (at: 1, r: color.r, g: color.g, b: color.b, a: 0),
            ]) { ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s / 2, options: []) }
            if hot > 0, let g = BackdropPaint.gradient([(at: 0, r: 1, g: 1, b: 1, a: hot), (at: 1, r: 1, g: 1, b: 1, a: 0)]) {
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s * 0.12, options: [])
            }
        }
    }

    /// An out-of-focus light, as a lens draws it: a disc a little brighter at the rim than inside, with faint rings, a
    /// soft edge, and a thin coloured fringe where the glass splits the light (warm inside, cool outside).
    static func bokeh(_ color: BackdropRGB, side: Int = 128, softness: Double = 1.6) -> CGImage? {
        guard let crisp = make(side, { ctx, s in
            let r = s / 2 - 3
            let c = CGPoint(x: s / 2, y: s / 2)
            // Cool fringe just outside the rim.
            ctx.setFillColor(BackdropPaint.color(color.r * 0.5, color.g * 0.8, 1, 0.35))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let body = r - 2
            if let g = BackdropPaint.gradient([
                (at: 0, r: color.r, g: color.g, b: color.b, a: 0.50), (at: 0.62, r: color.r, g: color.g, b: color.b, a: 0.58),
                (at: 0.86, r: min(1, color.r * 1.1 + 0.05), g: min(1, color.g * 1.05 + 0.04), b: color.b, a: 0.86),
                (at: 0.96, r: min(1, color.r + 0.1), g: min(1, color.g * 0.9 + 0.08), b: color.b * 0.8, a: 1.0),
                (at: 1, r: color.r, g: color.g, b: color.b, a: 0.9),
            ]) { ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: body, options: []) }
            // Faint onion rings, as real glass leaves.
            ctx.setStrokeColor(BackdropPaint.color(1, 1, 1, 0.06))
            ctx.setLineWidth(1.2)
            for k in [0.35, 0.55, 0.72] {
                let rr = body * k
                ctx.strokeEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
            }
        }) else { return nil }
        return BackdropBake.blurred(crisp, sigma: softness) ?? crisp
    }
}

// MARK: - Placing things by the clock

enum BackdropMotion {
    /// A smooth value in 0...1 that eases in and out, from a raw clock-driven phase.
    static func ease(_ x: Double) -> Double { BackdropMath.smoothstep(0, 1, x) }

    /// sin of a phase that is folded into one turn first, so a clock weeks old loses no precision.
    static func wave(_ time: Double, rate: Double, phase: Double = 0) -> Double {
        sin(2 * .pi * BackdropMath.fract(time * rate / (2 * .pi) + phase / (2 * .pi)))
    }

    /// Where something that loops every `period` seconds is in its loop, 0..<1, starting at `offset`.
    static func loop(_ time: Double, period: Double, offset: Double = 0) -> Double {
        BackdropMath.fract(time / period + offset)
    }
}
