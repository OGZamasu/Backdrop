import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Small tools shared by the weather, light and particle filters: a colour grade in one step, the person laid over a layer,
/// and glow dots with a limited set of colours so the sprite cache stays small.
enum WorldKit {
    /// Changes the mood of a picture in a single pass: colour drained to `saturation`, each channel scaled by `tint`, then `lift` added.
    /// Core Image does this in linear light, so a tint of 0.25 looks about half as bright, and a lift of 0.01 is already a visible haze.
    static func grade(_ image: CIImage, saturation: Double, tint: (r: Double, g: Double, b: Double),
                      lift: (r: Double, g: Double, b: Double) = (0, 0, 0)) -> CIImage {
        let luma = (r: 0.2126, g: 0.7152, b: 0.0722)
        let grey = 1 - saturation
        func row(_ channel: Int, _ scale: Double) -> CIVector {
            let own = [saturation, 0, 0], second = [0, saturation, 0], third = [0, 0, saturation]
            let base = channel == 0 ? own : channel == 1 ? second : third
            return CIVector(x: CGFloat(scale * (grey * luma.r + base[0])), y: CGFloat(scale * (grey * luma.g + base[1])),
                            z: CGFloat(scale * (grey * luma.b + base[2])), w: 0)
        }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": row(0, tint.r), "inputGVector": row(1, tint.g), "inputBVector": row(2, tint.b),
            "inputBiasVector": CIVector(x: CGFloat(lift.r), y: CGFloat(lift.g), z: CGFloat(lift.b), w: 0),
        ])
    }

    /// Lays `person` (already graded the way the lens wants) over `layer` through the cutout. With nobody in view the layer is the picture.
    static func place(person: CIImage, over layer: CIImage, matte: CIImage?, rect: CGRect) -> CIImage {
        guard let matte else { return layer.cropped(to: rect) }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = person
        blend.backgroundImage = layer
        blend.maskImage = matte
        return (blend.outputImage ?? layer).cropped(to: rect)
    }

    /// A soft glow dot whose colour is rounded to a coarse step, so thousands of slightly different colours share a few sprites.
    static func dot(_ r: Double, _ g: Double, _ b: Double) -> CGImage? {
        func snap(_ v: Double) -> Double { (min(1, max(0, v)) * 12).rounded() / 12 }
        return Sprites.dot(red: snap(r), green: snap(g), blue: snap(b))
    }

    /// Adds a layer of light to a picture, so glows brighten what is behind them instead of covering it.
    static func adding(_ light: CIImage, to base: CIImage) -> CIImage {
        let add = CIFilter.additionCompositing()
        add.inputImage = light
        add.backgroundImage = base
        // Adding also adds the two opacities. Put the picture back to fully opaque without touching its colours: clamping would
        // divide the colours by the opacity and halve the very light just added.
        guard let sum = add.outputImage else { return light.composited(over: base) }
        let area = base.extent.isInfinite ? light.extent : base.extent
        return sum.settingAlphaOne(in: area)
    }

    /// A big soft round wash of light, made on the graphics chip. A glow this wide painted by the CPU would cost milliseconds.
    static func wash(center: CGPoint, radius: Double, red: Double, green: Double, blue: Double, alpha: Double, in rect: CGRect) -> CIImage {
        let gradient = CIFilter.gaussianGradient()
        gradient.center = center
        gradient.radius = Float(radius)
        gradient.color0 = CIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
        gradient.color1 = CIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 0)
        // Only the part of the picture the light reaches is worked on.
        let reach = radius * 3.2
        let box = CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2).intersection(rect)
        return (gradient.outputImage ?? CIImage.empty()).cropped(to: box)
    }

    private static let spriteLock = NSLock()
    private static var glows: [Int: CGImage] = [:]
    private static var comets: [Int: CGImage] = [:]
    private static var stars: [Int: CGImage] = [:]

    /// A round glow with a smooth, gaussian-like fall-off: a little brighter in the middle than the edge of a firefly's halo and
    /// with no visible rings. Cheap to stamp many times.
    static func softGlow(_ r: Double, _ g: Double, _ b: Double) -> CGImage? {
        let key = colourKey(r, g, b)
        spriteLock.lock(); defer { spriteLock.unlock() }
        if let hit = glows[key] { return hit }
        let (r, g, b) = (snap(r), snap(g), snap(b))
        let side = 96
        let image = bitmap(width: side, height: side) { x, y in
            let dx = (Double(x) + 0.5) / Double(side) * 2 - 1, dy = (Double(y) + 0.5) / Double(side) * 2 - 1
            let t = (dx * dx + dy * dy).squareRoot()
            let a = exp(-4.6 * t * t) * (1 - smoothstep(0.7, 1, t))
            return (r, g, b, a)
        }
        glows[key] = image
        return image
    }

    /// A tail for a moving spark: thin and faint on the left, thick and bright on the right, where the spark itself is. Draw it turned
    /// along the direction of travel with its right edge on the spark, and stretched to the length wanted.
    static func comet(_ r: Double, _ g: Double, _ b: Double) -> CGImage? {
        let key = colourKey(r, g, b)
        spriteLock.lock(); defer { spriteLock.unlock() }
        if let hit = comets[key] { return hit }
        let (r, g, b) = (snap(r), snap(g), snap(b))
        let w = 128, h = 32
        let image = bitmap(width: w, height: h) { x, y in
            let u = (Double(x) + 0.5) / Double(w)
            let across = (Double(y) + 0.5 - Double(h) / 2) / (1.2 + 6.8 * pow(u, 1.4))
            // The end where the spark is fades off a little so a tail does not end in a hard edge.
            let a = pow(u, 1.7) * exp(-2.6 * across * across) * (1 - smoothstep(0.9, 1, u))
            // Whitest at the spark, the sprite's own colour along the rest of the tail.
            let hot = pow(u, 6) * 0.6
            return (r + (1 - r) * hot, g + (1 - g) * hot, b + (1 - b) * hot, a)
        }
        comets[key] = image
        return image
    }

    /// A four-pointed glint: a bright centre with thin rays along the axes and a fainter pair on the diagonals. Glitter.
    static func star(_ r: Double, _ g: Double, _ b: Double) -> CGImage? {
        let key = colourKey(r, g, b)
        spriteLock.lock(); defer { spriteLock.unlock() }
        if let hit = stars[key] { return hit }
        let (r, g, b) = (snap(r), snap(g), snap(b))
        let side = 64
        let image = bitmap(width: side, height: side) { x, y in
            let dx = (Double(x) + 0.5) / Double(side) * 2 - 1, dy = (Double(y) + 0.5) / Double(side) * 2 - 1
            let horizontal = exp(-abs(dy) * 26) * pow(max(0, 1 - abs(dx)), 2.4)
            let vertical = exp(-abs(dx) * 26) * pow(max(0, 1 - abs(dy)), 2.4)
            // The diagonals are the same shape turned a quarter, and shorter.
            let u = (dx + dy) * 0.7071, v = (dx - dy) * 0.7071
            let slashA = exp(-abs(v) * 30) * pow(max(0, 1 - abs(u) * 1.8), 2.4) * 0.5
            let slashB = exp(-abs(u) * 30) * pow(max(0, 1 - abs(v) * 1.8), 2.4) * 0.5
            let glow = exp(-9 * (dx * dx + dy * dy))
            let a = min(1, max(max(horizontal, vertical), max(slashA, slashB)) + glow)
            let hot = exp(-30 * (dx * dx + dy * dy))
            return (r + (1 - r) * hot, g + (1 - g) * hot, b + (1 - b) * hot, a)
        }
        stars[key] = image
        return image
    }

    private static func snap(_ v: Double) -> Double { (min(1, max(0, v)) * 12).rounded() / 12 }
    private static func colourKey(_ r: Double, _ g: Double, _ b: Double) -> Int {
        func step(_ v: Double) -> Int { Int((min(1, max(0, v)) * 12).rounded()) }
        return (step(r) * 13 + step(g)) * 13 + step(b)
    }

    /// A premultiplied picture made pixel by pixel from a function giving red, green, blue and opacity.
    private static func bitmap(width: Int, height: Int, _ colour: (Int, Int) -> (Double, Double, Double, Double)) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b, a) = colour(x, height - 1 - y)      // row 0 of the bitmap is the top
                let i = (y * width + x) * 4
                bytes[i] = UInt8(min(255, max(0, b * a * 255)))
                bytes[i + 1] = UInt8(min(255, max(0, g * a * 255)))
                bytes[i + 2] = UInt8(min(255, max(0, r * a * 255)))
                bytes[i + 3] = UInt8(min(255, max(0, a * 255)))
            }
        }
        return bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)?.makeImage()
        }
    }

    /// A smooth 0...1 ramp between two edges.
    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / max(1e-9, edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// A number in 0..<1 that depends only on `seed`: noise that never changes between runs.
    static func hash(_ seed: Int) -> Double {
        var z = UInt64(truncatingIfNeeded: seed) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    /// Frame time with a cap, so a stalled frame does not fire every cannon at once.
    static func clamped(_ dt: Double) -> Double { min(max(dt, 0), 1.0 / 15) }
}
