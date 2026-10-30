import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

extension LensInput {
    /// The picture without the person: the backdrop, or the plain camera if there isn't one.
    var scenery: CIImage { background ?? camera }

    /// Lays the person (from the composed picture, so their colour-matching is kept) over `layer`.
    func placingPerson(over layer: CIImage) -> CIImage {
        guard let matte else { return composed }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = composed
        blend.backgroundImage = layer
        blend.maskImage = matte
        return (blend.outputImage ?? composed).cropped(to: rect)
    }

    var clear: CIImage { CIImage(color: .clear).cropped(to: rect) }
}

extension CIImage {
    /// Multiplies every channel, including alpha, by a factor. Fades a layer without touching its colours.
    func fading(_ factor: Double) -> CIImage {
        applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(factor))])
    }

    func gain(_ k: Double) -> CIImage {
        applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(k), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(k), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(k), w: 0),
        ]).applyingFilter("CIColorClamp")
    }
}

/// Colour helpers shared by the lenses.
enum Palette {
    /// Fully saturated colour for a hue in 0...1.
    static func rgb(hue: Double, saturation: Double = 1, brightness: Double = 1) -> (r: Double, g: Double, b: Double) {
        let c = NSColor(hue: hue.truncatingRemainder(dividingBy: 1), saturation: saturation, brightness: brightness, alpha: 1)
            .usingColorSpace(.sRGB) ?? .white
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }
}

extension Sprites {
    private static let dotLock = NSLock()
    private static var dots: [String: CGImage] = [:]

    /// A soft round dot, bright in the middle and fading out. Cheap to stamp thousands of times.
    static func dot(red: Double, green: Double, blue: Double) -> CGImage? {
        let key = String(format: "%.2f-%.2f-%.2f", red, green, blue)
        dotLock.lock(); defer { dotLock.unlock() }
        if let hit = dots[key] { return hit }
        let side = 64
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(colorSpace: space, components: [red, green, blue, 1])!,
                      CGColor(colorSpace: space, components: [red, green, blue, 0.55])!,
                      CGColor(colorSpace: space, components: [red, green, blue, 0])!] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.3, 1])!
        let mid = CGPoint(x: side / 2, y: side / 2)
        ctx.drawRadialGradient(gradient, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: CGFloat(side / 2), options: [])
        guard let image = ctx.makeImage() else { return nil }
        dots[key] = image
        return image
    }
}

extension CGContext {
    /// Stamps a soft dot, `radius` pixels from centre to fade-out.
    func stampDot(_ image: CGImage, at p: CGPoint, radius: Double, alpha: Double) {
        guard alpha > 0.004, radius > 0.4 else { return }
        setAlpha(CGFloat(min(1, alpha)))
        draw(image, in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        setAlpha(1)
    }
}
