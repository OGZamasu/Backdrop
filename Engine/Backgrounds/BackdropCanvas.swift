import CoreGraphics
import CoreImage
import Foundation

/// A drawing surface for the procedural backdrops: one RGBA bitmap that is wiped and redrawn every frame, then
/// handed to Core Image as a picture. It can be smaller than the output (soft things like glows and bokeh look the
/// same at half size and cost a quarter as much) and is scaled up on the way out.
final class BackdropCanvas {
    static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    let width: Int
    let height: Int
    let context: CGContext
    private let bytesPerRow: Int

    init?(width: Int, height: Int) {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: Self.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              context.data != nil else { return nil }
        self.width = width
        self.height = height
        self.context = context
        bytesPerRow = context.bytesPerRow
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high
    }

    /// Wipes the surface to transparent and resets the drawing state.
    func clear() {
        context.setBlendMode(.copy)
        context.setFillColor(CGColor(gray: 0, alpha: 0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setBlendMode(.normal)
        context.setAlpha(1)
    }

    /// What is on the surface now, as its own picture (the pixels are copied, so drawing again does not disturb it).
    /// With `scale` above 1 the picture is enlarged smoothly, with its edges held so they do not fade.
    /// With `raw` the numbers are used as they are, with no colour conversion: for a surface that holds a measurement
    /// (how much of a blob is here) rather than a picture.
    func image(scale: CGFloat = 1, raw: Bool = false) -> CIImage? {
        guard let base = context.data else { return nil }
        let data = Data(bytes: base, count: bytesPerRow * height)
        let extent = CGRect(x: 0, y: 0, width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        let image = CIImage(bitmapData: data, bytesPerRow: bytesPerRow, size: CGSize(width: width, height: height),
                            format: .RGBA8, colorSpace: raw ? nil : Self.space)
        guard scale != 1 else { return image }
        return image.clampedToExtent().transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: extent)
    }
}

/// Colour and gradient helpers shared by the procedural backdrops.
enum BackdropPaint {
    static func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(colorSpace: BackdropCanvas.space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])
            ?? CGColor(gray: 0, alpha: CGFloat(a))
    }

    /// "RRGGBB" (a leading # is fine) as red, green, blue in 0...1, or nil if it is not a colour.
    static func rgb(hex: String) -> (r: Double, g: Double, b: Double)? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// A gradient through colour stops given as (position 0...1, r, g, b, alpha).
    static func gradient(_ stops: [(at: Double, r: Double, g: Double, b: Double, a: Double)]) -> CGGradient? {
        let colors = stops.map { color($0.r, $0.g, $0.b, $0.a) } as CFArray
        return CGGradient(colorsSpace: BackdropCanvas.space, colors: colors, locations: stops.map { CGFloat($0.at) })
    }

    /// The same, with every stop fully opaque.
    static func gradient(_ stops: [(at: Double, r: Double, g: Double, b: Double)]) -> CGGradient? {
        gradient(stops.map { (at: $0.at, r: $0.r, g: $0.g, b: $0.b, a: 1) })
    }
}

extension CGContext {
    /// A soft round blob: `inner` colour at the centre, fading to `outer` at the radius.
    func backdropGlow(center: CGPoint, radius: CGFloat, inner: CGColor, outer: CGColor) {
        guard radius > 0.5,
              let gradient = CGGradient(colorsSpace: BackdropCanvas.space, colors: [inner, outer] as CFArray, locations: [0, 1])
        else { return }
        drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
}

/// Work done once when a backdrop is first shown, to make a still picture it can then reuse for free.
enum BackdropBake {
    private static let context = CIContext()

    /// `image` with a Gaussian blur of `sigma` pixels, at the same size.
    static func blurred(_ image: CGImage, sigma: Double) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        defer { context.clearCaches() }
        return context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: BackdropCanvas.space)
    }
}

/// Small deterministic helpers, so a backdrop looks the same every time it starts.
enum BackdropMath {
    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// The part after the decimal point, always in 0..<1, also for negative numbers.
    static func fract(_ x: Double) -> Double { x - x.rounded(.down) }

    static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}
