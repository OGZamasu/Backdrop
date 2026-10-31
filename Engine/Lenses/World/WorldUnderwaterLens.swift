import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Under the sea: the room turns blue-green and darker with depth, rippling caustic light from the surface dances over the walls
/// and over you, shafts of light sway down from above, specks drift in the water and streams of bubbles rise.
final class WorldUnderwaterLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    /// "Lagoon": the water, the light from the surface, and the deep.
    static let water = SIMD3<Double>(0.18, 0.62, 0.72)
    static let surface = SIMD3<Double>(0.75, 1.0, 0.95)

    private let size: CGSize
    /// The caustic tile, made once on first use (on the video queue) and shared by every copy of the lens.
    private static let causticTile: CIImage? = makeCaustics()
    private var caustics: CIImage? { Self.causticTile }
    private static let tile = 128
    private var specks: [(position: SIMD2<Double>, phase: Double, size: Double)]
    private var bubbles: [(position: SIMD2<Double>, radius: Double, phase: Double, speed: Double)] = []
    private var rng = SplitMix64(seed: 0x5EA5)
    private var owed = 0.0

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        self.size = size
        var seeded = SplitMix64(seed: 0x5EED)
        specks = (0..<70).map { _ in
            (SIMD2(Double.random(in: 0...size.width, using: &seeded), Double.random(in: 0...size.height, using: &seeded)),
             Double.random(in: 0...(2 * .pi), using: &seeded), Double.random(in: 0.8...2.4, using: &seeded))
        }
    }

    func restart() { bubbles.removeAll() }

    var bubbleCount: Int { bubbles.count }

    /// Where the bubble streams rise from, as fractions across the bottom.
    static let vents: [Double] = [0.1, 0.83, 0.94]

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect, t = input.time
        step(WorldKit.clamped(input.dt), time: t)

        // The water: everything tinted and dimmer the deeper it is, which is lower in the picture.
        let deep = CIFilter.linearGradient()
        deep.point0 = CGPoint(x: 0, y: rect.minY)
        deep.point1 = CGPoint(x: 0, y: rect.maxY)
        deep.color0 = CIColor(red: 0.5, green: 0.55, blue: 0.62)
        deep.color1 = CIColor(red: 1, green: 1, blue: 1)
        let depth = (deep.outputImage ?? CIImage.empty()).cropped(to: rect)
        let w = Self.water
        var tinted = WorldKit.multiply(WorldKit.grade(input.scenery, saturation: 0.35, tint: (w.x * 0.8, w.y * 1.15, w.z), lift: (0.0, 0.034, 0.04)), depth)
        // Brighter water up toward the surface.
        tinted = WorldKit.adding(WorldKit.wash(center: CGPoint(x: rect.midX, y: rect.maxY + 160), radius: 520, red: w.x, green: w.y, blue: w.z, alpha: 0.35, in: rect), to: tinted)
        let light = causticLight(rect: rect, time: t)
        var room = WorldKit.adding(WorldKit.brightened(light, 0.2), to: tinted).cropped(to: rect)
        if let shafts = shaftLayer(rect: rect, time: t) { room = WorldKit.adding(shafts, to: room) }

        let personTinted = WorldKit.multiply(WorldKit.grade(input.composed, saturation: 0.85, tint: (0.68, 0.9, 0.94), lift: (0.0, 0.006, 0.01)), depth)
        var body = WorldKit.place(person: personTinted.cropped(to: rect), over: room, matte: input.matte, rect: rect)
        if let matte = input.matte {
            // The same rippling light plays across you.
            body = WorldKit.adding(WorldKit.multiply(WorldKit.brightened(light, 0.26), matte).cropped(to: rect), to: body)
            if let rim = WorldKit.rimLight(matte: matte, rect: rect, toward: SIMD2(0, 1), width: 12, colour: Self.surface, strength: 0.35) {
                body = WorldKit.adding(rim, to: body)
            }
        }
        guard let front = input.services.overlay({ ctx in drawWater(in: ctx, time: t) }) else { return body }
        return front.composited(over: body).cropped(to: rect)
    }

    // MARK: Light

    /// Two copies of the caustic pattern drifting different ways, keeping the darker of the two at each point: the bright lines
    /// cross and split like real light under waves. Opaque, black where there is none, brighter near the surface.
    private func causticLight(rect: CGRect, time t: Double) -> CIImage {
        guard let caustics else { return CIImage(color: .black).cropped(to: rect) }
        // Worked out at half size: soft light needs no more.
        let k = 0.5
        let box = CGRect(x: 0, y: 0, width: rect.width * k, height: rect.height * k)
        let a = caustics.transformed(by: CGAffineTransform(scaleX: 2.0 * k, y: 1.8 * k).concatenating(CGAffineTransform(translationX: t * 16 * k, y: t * 7 * k)))
        let b = caustics.transformed(by: CGAffineTransform(scaleX: 2.6 * k, y: 2.3 * k).concatenating(CGAffineTransform(rotationAngle: 0.5))
            .concatenating(CGAffineTransform(translationX: -t * 11 * k, y: t * 13 * k)))
        // Where the two webs cross the light focuses brightest; elsewhere each web shows faintly.
        let both = WorldKit.adding(WorldKit.brightened(a, 0.5), to: WorldKit.brightened(b, 0.5)).cropped(to: box)
        let fade = CIFilter.linearGradient()
        fade.point0 = .zero
        fade.point1 = CGPoint(x: 0, y: box.height)
        fade.color0 = CIColor(red: 0.35, green: 0.35, blue: 0.35)
        fade.color1 = CIColor(red: 1, green: 1, blue: 1)
        let lit = WorldKit.multiply(WorldKit.levels(both, low: 0.3, high: 0.95), (fade.outputImage ?? CIImage.empty()).cropped(to: box))
        return WorldKit.enlarge(WorldKit.tint(lit, Self.surface, strength: 1).settingAlphaOne(in: box), rect: rect, from: k)
    }

    /// A seamless tile of caustic lines: bright where two cells of a scattered pattern meet, the way light focuses under ripples.
    private static func makeCaustics() -> CIImage? {
        let n = tile
        var rng = SplitMix64(seed: 0xCA05)
        let points = (0..<8).map { _ in SIMD2(Double.random(in: 0..<Double(n), using: &rng), Double.random(in: 0..<Double(n), using: &rng)) }
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        let size = Double(n)
        for y in 0..<n {
            for x in 0..<n {
                // Bend the plane with waves that repeat with the tile, so the lines curve the way light under ripples does.
                let fx = (Double(x) + 0.5) / size * 2 * .pi, fy = (Double(y) + 0.5) / size * 2 * .pi
                let p = SIMD2(Double(x) + 0.5 + 6 * sin(fy * 2 + 0.7) + 3 * sin(fx * 3 + fy), Double(y) + 0.5 + 6 * sin(fx * 2 + 1.9) + 3 * sin(fy * 3 - fx))
                var first = Double.greatestFiniteMagnitude, second = Double.greatestFiniteMagnitude
                for q in points {
                    // Wrap round the edges, so the tile repeats without a seam.
                    var d = abs(p - q)
                    d.x = min(d.x, size - d.x)
                    d.y = min(d.y, size - d.y)
                    let dist = (d.x * d.x + d.y * d.y).squareRoot()
                    if dist < first {
                        second = first
                        first = dist
                    } else if dist < second {
                        second = dist
                    }
                }
                let edge = second - first
                let v = pow(1 - WorldKit.smoothstep(0, 5, edge), 1.5) * 0.8 + 0.2 * pow(1 - WorldKit.smoothstep(0, 16, edge), 2)
                let i = (y * n + x) * 4
                let byte = UInt8(min(255, v * 255))
                bytes[i] = byte
                bytes[i + 1] = byte
                bytes[i + 2] = byte
                bytes[i + 3] = 255
            }
        }
        let image = bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)?.makeImage()
        }
        guard let image else { return nil }
        // Repeated without end, so it can be slid and scaled freely.
        let tiled = CIFilter.affineTile()
        tiled.inputImage = CIImage(cgImage: image)
        tiled.transform = .identity
        return tiled.outputImage
    }

    // MARK: Particles

    private func step(_ dt: Double, time: Double) {
        for i in specks.indices {
            var s = specks[i]
            s.position += SIMD2(sin(time * 0.3 + s.phase) * 6 + 4, -5 + cos(time * 0.4 + s.phase) * 3) * dt
            if s.position.y < -6 { s.position.y = size.height + 6 }
            if s.position.x > size.width + 6 { s.position.x = -6 }
            specks[i] = s
        }
        owed += dt * 5
        while owed >= 1 {
            owed -= 1
            let vent = Self.vents[Int.random(in: 0..<Self.vents.count, using: &rng)]
            bubbles.append((SIMD2(size.width * vent + Double.random(in: -12...12, using: &rng), -8), Double.random(in: 2.5...7, using: &rng),
                            Double.random(in: 0...(2 * .pi), using: &rng), Double.random(in: 90...170, using: &rng)))
        }
        for i in bubbles.indices {
            bubbles[i].position.y += bubbles[i].speed * dt
            bubbles[i].position.x += sin(time * 4 + bubbles[i].phase) * 22 * dt
        }
        bubbles.removeAll { $0.position.y > size.height + 10 }
        if bubbles.count > 120 { bubbles.removeFirst(bubbles.count - 120) }
    }

    // MARK: Drawing

    private lazy var shaftImage = WorldKit.ciSprite(Self.shaft)

    /// Shafts of light from the surface, swaying slowly, laid out on the graphics chip.
    private func shaftLayer(rect: CGRect, time: Double) -> CIImage? {
        guard let shaft = shaftImage else { return nil }
        let layers = (0..<7).map { k -> CIImage in
            let x = size.width * (0.02 + 0.16 * Double(k) + 0.07 * WorldKit.hash(k * 7 + 3)) + 40 * sin(time * 0.25 + Double(k) * 1.7)
            let lean = 0.2 + 0.08 * sin(time * 0.31 + Double(k))
            let width = 40 + 90 * WorldKit.hash(k * 13 + 1)
            let alpha = (0.06 + 0.1 * WorldKit.hash(k * 5 + 2)) * (0.75 + 0.25 * sin(time * 0.7 + Double(k) * 2.3))
            return WorldKit.placed(shaft, size: CGSize(width: size.height * 1.1, height: width), anchor: CGPoint(x: 0, y: width / 2), angle: -.pi / 2 - lean,
                                   at: CGPoint(x: x, y: size.height + 20), alpha: alpha)
        }
        return WorldKit.sum(layers, rect: rect)
    }

    /// Specks in the water and the bubbles, in front of everything.
    private func drawWater(in ctx: CGContext, time: Double) {
        ctx.interpolationQuality = .low
        if let speck = WorldKit.softGlow(0.85, 1, 0.95) {
            ctx.setBlendMode(.plusLighter)
            for s in specks {
                ctx.stampDot(speck, at: CGPoint(x: s.position.x, y: s.position.y), radius: s.size * 1.8, alpha: 0.25 + 0.15 * sin(time + s.phase))
            }
            ctx.setBlendMode(.normal)
        }
        ctx.interpolationQuality = .high
        for b in bubbles {
            let r = b.radius * (1 + 0.08 * sin(time * 9 + b.phase))
            let box = CGRect(x: b.position.x - r, y: b.position.y - r, width: r * 2, height: r * 2)
            ctx.setFillColor(CGColor(red: 0.75, green: 0.95, blue: 1, alpha: 0.12))
            ctx.fillEllipse(in: box)
            ctx.setStrokeColor(CGColor(red: 0.85, green: 1, blue: 1, alpha: 0.7))
            ctx.setLineWidth(1.2)
            ctx.strokeEllipse(in: box.insetBy(dx: 0.6, dy: 0.6))
            ctx.fillCircle(center: CGPoint(x: b.position.x - r * 0.35, y: b.position.y + r * 0.35), radius: max(0.8, r * 0.28),
                           color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        }
    }

    /// A shaft of light along the x axis: brightest at the surface end, soft at the sides.
    private static let shaft: CGImage? = {
        let w = 256, h = 32
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let c = surface
        for y in 0..<h {
            let across = abs((Double(y) + 0.5) / Double(h) * 2 - 1)
            let side = 1 - WorldKit.smoothstep(0.15, 1, across)
            for x in 0..<w {
                let u = Double(x) / Double(w - 1)
                let a = side * (1 - WorldKit.smoothstep(0.1, 1, u))
                let i = (y * w + x) * 4
                bytes[i] = UInt8(min(255, c.z * a * 255))
                bytes[i + 1] = UInt8(min(255, c.y * a * 255))
                bytes[i + 2] = UInt8(min(255, c.x * a * 255))
                bytes[i + 3] = UInt8(min(255, a * 255))
            }
        }
        return bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)?.makeImage()
        }
    }()
}
