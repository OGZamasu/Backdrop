import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// The northern lights: curtains of green light with violet hems ripple slowly across a starry sky over a dark pine forest, and
/// their glow catches the top of your head and shoulders.
///
/// The curtains are drawn small, as rows of thin strokes standing on a folding hem, then coloured, softened and glowed on the
/// graphics chip and scaled up.
final class WorldNorthernLightsLens: Lens {
    let needs: LensNeeds = [.matte]

    /// "Aurora": the lower hem is green, the tops of the rays violet, and a faint pink fringe now and then.
    static let green = SIMD3<Double>(0.22, 1.0, 0.56)
    static let violet = SIMD3<Double>(0.58, 0.32, 1.0)
    static let pink = SIMD3<Double>(1.0, 0.36, 0.62)

    private let size: CGSize
    private let stars: [(x: Double, y: Double, rate: Double, phase: Double, size: Double)]

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        self.size = size
        stars = (0..<130).map { i in
            (x: WorldKit.hash(i * 5 + 11) * size.width, y: size.height * (0.22 + 0.78 * WorldKit.hash(i * 5 + 12)),
             rate: 0.6 + 2.2 * WorldKit.hash(i * 5 + 13), phase: 6.28 * WorldKit.hash(i * 5 + 14), size: 0.9 + 1.9 * pow(WorldKit.hash(i * 5 + 15), 2))
        }
    }

    /// How strongly the lights are shining at a moment, 0.55...1: they swell and fade over half a minute or so.
    static func intensity(at t: Double) -> Double {
        0.78 + 0.14 * sin(t * 0.21) + 0.08 * sin(t * 0.53 + 1.3)
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect, t = input.time
        let glow = Self.intensity(at: t)

        // Night: the room drained to a deep blue, a little lighter low down where the sky meets the hills.
        let night = WorldKit.grade(input.scenery, saturation: 0.45, tint: (0.07, 0.10, 0.19), lift: (0.0, 0.002, 0.006))
        let aurora = curtains(rect: rect, time: t, strength: glow)
        var sky = WorldKit.adding(aurora, to: night)
        if let layer = input.services.overlay({ ctx in drawStarsAndForest(in: ctx, time: t) }) { sky = layer.composited(over: sky) }

        // You are lit softly from above in the aurora's green, and the rest of you sits in the cool night.
        let person = WorldKit.grade(input.composed, saturation: 0.7, tint: (0.42, 0.52, 0.58), lift: (0.0, 0.004 * glow, 0.003))
        var body = WorldKit.place(person: person, over: sky, matte: input.matte, rect: rect)
        if let rim = WorldKit.rimLight(matte: input.matte, rect: rect, toward: SIMD2(0.15, 1), width: 16, colour: Self.green * 0.8 + Self.violet * 0.15,
                                       strength: 0.5 * glow) {
            body = WorldKit.adding(rim, to: body)
        }
        return body
    }

    /// The curtains drawn small: each one a row of thin strokes standing on a hem that folds and slides, taller and brighter in
    /// some stretches than others. One stroke carries both parts of the curtain: its lower glow in the red channel and its upper
    /// reaches in the green, so each can take its own colour later. Made fresh every frame on a small canvas of its own.
    private var canvas: CGContext?

    private func curtainShape(box: CGRect, time t: Double) -> CIImage? {
        if canvas == nil {
            canvas = CGContext(data: nil, width: Int(box.width), height: Int(box.height), bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)
        }
        guard let ctx = canvas, let column = Self.column else { return nil }
        ctx.clear(box)
        ctx.interpolationQuality = .low
        ctx.setBlendMode(.plusLighter)
        // (base height, how tall, brightness, phase, which way the folds travel)
        let layers: [(base: Double, tall: Double, gain: Double, phase: Double, travel: Double)] = [(0.58, 0.36, 1.0, 0, 1), (0.77, 0.22, 0.55, 2.4, -1)]
        for c in layers {
            for x in stride(from: -2.0, to: box.width + 2, by: 2) {
                let u = x / box.width
                let fold = 9 * sin(u * 9.5 + t * 0.32 * c.travel + c.phase) + 5 * sin(u * 23 - t * 0.55 * c.travel + c.phase * 2)
                    + 2.2 * sin(u * 61 + t * 1.1 + c.phase)
                let base = box.height * c.base + fold
                let tall = box.height * c.tall * (0.62 + 0.38 * sin(u * 13 + t * 0.21 + c.phase * 3))
                let patch = max(0, 0.55 + 0.45 * sin(u * 5.1 - t * 0.18 * c.travel + c.phase) * sin(u * 2.3 + t * 0.07 + c.phase * 1.7))
                // Rays: a fixed scatter of brighter and dimmer strokes, rippled by a wave running along the curtain.
                let ray = 0.45 + 0.3 * WorldKit.hash(Int(x / 2) * 7 + Int(c.phase * 10)) + 0.25 * sin(u * 190 + sin(u * 37 + t * 0.4) * 3 + c.phase)
                ctx.setAlpha(CGFloat(min(1, c.gain * patch * ray)))
                ctx.draw(column, in: CGRect(x: x, y: base - 2, width: 2.8, height: tall * 1.25))
            }
        }
        ctx.setAlpha(1)
        ctx.setBlendMode(.normal)
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }

    /// Two curtains of light as an opaque layer to add over the sky: black where there is none.
    private func curtains(rect: CGRect, time t: Double, strength: Double) -> CIImage {
        let scale = 0.25
        let box = CGRect(x: 0, y: 0, width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
        guard let shape = curtainShape(box: box, time: t)?.settingAlphaOne(in: box) else { return CIImage(color: .black).cropped(to: rect) }
        let soft = shape.clampedToExtent().applyingGaussianBlur(sigma: 0.9).cropped(to: box)
        // Red carries the lower glow (green light), green the upper reaches (violet light).
        let g = Self.green * 0.85 * strength, v = Self.violet * 0.34 * strength
        let coloured = soft.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(g.x), y: CGFloat(v.x), z: 0, w: 0),
            "inputGVector": CIVector(x: CGFloat(g.y), y: CGFloat(v.y), z: 0, w: 0),
            "inputBVector": CIVector(x: CGFloat(g.z), y: CGFloat(v.z), z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: box)
        // Now and then a pink fringe along the hem.
        let pink = Self.pink * 0.14 * strength * (0.5 + 0.5 * sin(t * 0.4))
        let fringe = soft.transformed(by: CGAffineTransform(translationX: 0, y: -2.5)).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(pink.x), y: 0, z: 0, w: 0), "inputGVector": CIVector(x: CGFloat(pink.y), y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: CGFloat(pink.z), y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: box)
        var light = WorldKit.adding(fringe, to: coloured)
        // A wide soft glow round the curtains lights the whole sky a little.
        let bloom = light.clampedToExtent().applyingGaussianBlur(sigma: 7).cropped(to: box)
        light = WorldKit.adding(WorldKit.brightened(bloom, 0.45), to: light).cropped(to: box)
        return WorldKit.enlarge(light.settingAlphaOne(in: box), rect: rect, from: scale)
    }

    /// One stroke of a curtain. Red: brightest at its foot (the hem) and fading upward. Green: its upper reaches, where the light
    /// turns violet. Drawn once.
    private static let column: CGImage? = {
        let h = 160
        var bytes = [UInt8](repeating: 0, count: h * 4)
        for y in 0..<h {
            let v = (1 - Double(y) / Double(h - 1)) * 1.25        // 0 at the bottom row ... 1.25 at the top
            let lower = WorldKit.smoothstep(0, 0.04, v) * (0.25 + 0.75 * exp(-v * 4.2)) * (1 - WorldKit.smoothstep(0.55, 0.9, v))
            let upper = WorldKit.smoothstep(0.3, 0.6, v) * (1 - WorldKit.smoothstep(0.85, 1.25, v)) * 0.8
            bytes[y * 4] = 0                                         // blue
            bytes[y * 4 + 1] = UInt8(min(255, upper * 255))          // green
            bytes[y * 4 + 2] = UInt8(min(255, lower * 255))          // red
            bytes[y * 4 + 3] = UInt8(min(255, max(lower, upper) * 255))
        }
        return bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: 1, height: h, bitsPerComponent: 8, bytesPerRow: 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)?.makeImage()
        }
    }()

    private func drawStarsAndForest(in ctx: CGContext, time: Double) {
        ctx.interpolationQuality = .low
        if let dot = WorldKit.softGlow(0.86, 0.92, 1) {
            ctx.setBlendMode(.plusLighter)
            for s in stars {
                let twinkle = 0.55 + 0.45 * sin(time * s.rate + s.phase)
                ctx.stampDot(dot, at: CGPoint(x: s.x, y: s.y), radius: s.size * 1.6, alpha: 0.25 + 0.6 * twinkle)
            }
            ctx.setBlendMode(.normal)
        }
        ctx.interpolationQuality = .high
        if let forest = Self.forest { ctx.draw(forest, in: CGRect(x: 0, y: 0, width: forest.width, height: forest.height)) }
    }

    /// "Boreal": two rows of pine trees along the bottom, the far row a little lighter, drawn once.
    static let forest: CGImage? = {
        let w = 1280, h = 190
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        func pine(x: Double, height: Double, width: Double, colour: CGColor) {
            let path = CGMutablePath()
            let tiers = 5
            path.move(to: CGPoint(x: x, y: height))
            for k in 0..<tiers {
                let f = Double(k + 1) / Double(tiers)
                let y = height * (1 - f * 0.86)
                let half = width / 2 * (0.35 + 0.65 * f)
                path.addLine(to: CGPoint(x: x + half, y: y))
                path.addLine(to: CGPoint(x: x + half * 0.45, y: y + height * 0.06))
            }
            path.addLine(to: CGPoint(x: x + 3, y: 0))
            path.addLine(to: CGPoint(x: x - 3, y: 0))
            for k in (0..<tiers).reversed() {
                let f = Double(k + 1) / Double(tiers)
                let y = height * (1 - f * 0.86)
                let half = width / 2 * (0.35 + 0.65 * f)
                path.addLine(to: CGPoint(x: x - half * 0.45, y: y + height * 0.06))
                path.addLine(to: CGPoint(x: x - half, y: y))
            }
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(colour)
            ctx.fillPath()
        }
        let far = CGColor(red: 0.05, green: 0.09, blue: 0.13, alpha: 1), near = CGColor(red: 0.015, green: 0.03, blue: 0.045, alpha: 1)
        ctx.setFillColor(far)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: 40))
        var x = -20.0, i = 0
        while x < Double(w) + 20 {
            pine(x: x, height: 70 + 60 * WorldKit.hash(i * 2 + 501), width: 30 + 18 * WorldKit.hash(i * 2 + 502), colour: far)
            x += 16 + 18 * WorldKit.hash(i * 7 + 503)
            i += 1
        }
        ctx.setFillColor(near)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: 22))
        x = -30
        while x < Double(w) + 30 {
            pine(x: x, height: 100 + 85 * WorldKit.hash(i * 2 + 901), width: 44 + 26 * WorldKit.hash(i * 2 + 902), colour: near)
            x += 26 + 40 * WorldKit.hash(i * 7 + 903)
            i += 1
        }
        return ctx.makeImage()
    }()
}
