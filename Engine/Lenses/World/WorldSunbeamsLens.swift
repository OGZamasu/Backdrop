import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Late-afternoon sun through a window at the top left: golden shafts of light slant across the room with dust glittering in them,
/// the window's panes land as bright patches on the wall, your shadow falls across them, and the sun catches your hair.
final class WorldSunbeamsLens: Lens {
    let needs: LensNeeds = [.matte]

    /// "Golden hour": the sunlight, and the cooler shade it leaves.
    static let sun = SIMD3<Double>(1.0, 0.8, 0.5)
    static let shade = SIMD3<Double>(0.82, 0.86, 1.0)
    /// The way the light travels: down and to the right.
    static let travel = simd_normalize(SIMD2<Double>(0.62, -0.78))

    private struct Shaft {
        /// Where across the window it comes through, sideways from the window's middle in pixels.
        var offset: Double
        var width: Double
        var strength: Double
        var phase: Double
    }

    private let size: CGSize
    private let shafts: [Shaft]
    private var motes: [(position: SIMD2<Double>, phase: Double, size: Double)]

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        self.size = size
        var rng = SplitMix64(seed: 0x5BEA)
        shafts = (0..<7).map { k in
            Shaft(offset: -230 + Double(k) * 78 + Double.random(in: -20...20, using: &rng), width: Double.random(in: 40...95, using: &rng),
                  strength: Double.random(in: 0.55...1, using: &rng), phase: Double.random(in: 0...(2 * .pi), using: &rng))
        }
        motes = (0..<110).map { _ in
            (SIMD2(Double.random(in: 0...size.width, using: &rng), Double.random(in: 0...size.height, using: &rng)),
             Double.random(in: 0...(2 * .pi), using: &rng), Double.random(in: 0.8...2.2, using: &rng))
        }
    }

    /// Where the light comes in: just off the top left of the picture.
    var window: SIMD2<Double> { SIMD2(size.width * 0.04, size.height * 1.08) }

    /// How much sunlight falls at a point, 0...1, from the shafts. Used to light the dust.
    func sunlight(at p: SIMD2<Double>, time: Double) -> Double {
        let rel = p - window
        let along = simd_dot(rel, Self.travel)
        guard along > 0 else { return 0 }
        let across = simd_dot(rel, SIMD2(-Self.travel.y, Self.travel.x))
        var total = 0.0
        for s in shafts {
            // Each shaft widens a little as it goes and fades with distance.
            let half = s.width * (0.5 + along / 2400)
            let d = abs(across - s.offset * (1 + along / 1800))
            total += s.strength * (1 - WorldKit.smoothstep(half * 0.5, half, d)) * shimmer(s, time: time)
        }
        return min(1, total) * (1 - WorldKit.smoothstep(700, 1400, along))
    }

    private func shimmer(_ s: Shaft, time: Double) -> Double { 0.78 + 0.22 * sin(time * 0.6 + s.phase) * sin(time * 0.23 + s.phase * 2) }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect, t = input.time
        let dt = WorldKit.clamped(input.dt)
        for i in motes.indices {
            var m = motes[i]
            m.position += SIMD2(sin(t * 0.21 + m.phase) * 7 + 3, cos(t * 0.17 + m.phase * 1.3) * 5 - 2) * dt
            if m.position.x > size.width + 10 { m.position.x = -10 }
            if m.position.y < -10 { m.position.y = size.height + 10 }
            motes[i] = m
        }

        // A warm, slightly hazy room, a little cooler in the shade.
        var room = WorldKit.grade(input.scenery, saturation: 0.95, tint: (0.86, 0.82, 0.8), lift: (0.008, 0.006, 0.006))
        // The sunlight on the wall: the shafts and the window's panes, with your shadow cut out of them.
        var light: CIImage? = lightLayer(rect: rect, time: t)
        if let matte = input.matte, let lit = light {
            let scale = 0.25
            let box = CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale)
            let throwAt = Self.travel * 70 * scale
            let shadow = WorldKit.shrink(matte, rect: rect, by: scale).transformed(by: CGAffineTransform(translationX: throwAt.x, y: throwAt.y))
                .clampedToExtent().applyingGaussianBlur(sigma: 4).cropped(to: box)
            let keep = WorldKit.enlarge(WorldKit.inverted(WorldKit.tint(shadow, SIMD3(1, 1, 1), strength: 0.85)).settingAlphaOne(in: box), rect: rect, from: scale)
            light = WorldKit.multiply(lit, keep).cropped(to: rect)
        }
        if let light { room = WorldKit.adding(light, to: room) }
        room = WorldKit.adding(WorldKit.wash(center: CGPoint(x: window.x, y: window.y), radius: 420, red: Self.sun.x, green: Self.sun.y, blue: Self.sun.z, alpha: 0.32, in: rect), to: room)

        let person = WorldKit.grade(input.composed, saturation: 1.0, tint: (0.88, 0.85, 0.86), lift: (0.004, 0.003, 0.004))
        var body = WorldKit.place(person: person, over: room, matte: input.matte, rect: rect)
        // The sun on you: a warm rim from the window side and a little of the beams' light across you.
        if let rim = WorldKit.rimLight(matte: input.matte, rect: rect, toward: -Self.travel, width: 12, colour: Self.sun, strength: 0.4) {
            body = WorldKit.adding(rim, to: body)
        }
        if let matte = input.matte, let light {
            body = WorldKit.adding(WorldKit.multiply(WorldKit.brightened(light, 0.16), matte).cropped(to: rect), to: body)
        }
        guard let dust = input.services.overlay({ ctx in drawDust(in: ctx, time: t) }) else { return body }
        return WorldKit.adding(dust, to: body).cropped(to: rect)
    }

    // MARK: Drawing

    private lazy var shaftImage = WorldKit.ciSprite(Self.shaftSprite)
    private lazy var panesImage = WorldKit.ciSprite(Self.panesSprite)

    /// The sunlight as a layer to add, all laid out on the graphics chip: the window's panes thrown down and to the right onto the
    /// wall as soft bright patches, and the shafts, long soft strips from the window, each breathing slowly.
    private func lightLayer(rect: CGRect, time: Double) -> CIImage? {
        var layers: [CIImage] = []
        if let panes = panesImage {
            let skew = CGAffineTransform(a: 1, b: -0.35, c: 0.55, d: 1, tx: CGFloat(size.width * 0.62), ty: CGFloat(size.height * 0.18))
            layers.append(panes.transformed(by: CGAffineTransform(translationX: -Self.panePad, y: -Self.panePad).concatenating(skew))
                .fading(0.34 * (0.92 + 0.08 * sin(time * 0.5))))
        }
        if let shaft = shaftImage {
            let angle = atan2(Self.travel.y, Self.travel.x)
            for sh in shafts {
                let from = window + SIMD2(-Self.travel.y, Self.travel.x) * sh.offset
                layers.append(WorldKit.placed(shaft, size: CGSize(width: 1500, height: sh.width * 2), anchor: CGPoint(x: 0, y: sh.width), angle: angle,
                                              at: CGPoint(x: from.x, y: from.y), alpha: 0.26 * sh.strength * shimmer(sh, time: time)))
            }
        }
        return layers.isEmpty ? nil : WorldKit.sum(layers, rect: rect)
    }

    /// The margin round the panes sprite, so its soft edges are not cut off.
    private static let panePad = 40.0

    /// The window's four panes as soft-edged patches of sunlight, made once.
    private static let panesSprite: CGImage? = {
        let panes: [CGRect] = [CGRect(x: 0, y: 0, width: 120, height: 150), CGRect(x: 134, y: 0, width: 120, height: 150),
                               CGRect(x: 0, y: 164, width: 120, height: 150), CGRect(x: 134, y: 164, width: 120, height: 150)]
        let w = Int(254 + panePad * 2), h = Int(314 + panePad * 2)
        let soft = 16.0
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let c = sun
        // Each pane's softness across and up is worked out once per column and once per row.
        let across = panes.map { p in (0..<w).map { x -> Double in
            let px = Double(x) + 0.5 - panePad
            return WorldKit.smoothstep(p.minX - soft, p.minX + soft, px) * (1 - WorldKit.smoothstep(p.maxX - soft, p.maxX + soft, px))
        } }
        let up = panes.map { p in (0..<h).map { y -> Double in
            let py = Double(h - 1 - y) + 0.5 - panePad
            return WorldKit.smoothstep(p.minY - soft, p.minY + soft, py) * (1 - WorldKit.smoothstep(p.maxY - soft, p.maxY + soft, py))
        } }
        for y in 0..<h {
            for x in 0..<w {
                var a = 0.0
                for k in 0..<panes.count { a += across[k][x] * up[k][y] }
                a = min(1, a)
                let i = (y * w + x) * 4
                bytes[i] = UInt8(min(255, c.z * 0.9 * a * 255))
                bytes[i + 1] = UInt8(min(255, c.y * 0.95 * a * 255))
                bytes[i + 2] = UInt8(min(255, c.x * a * 255))
                bytes[i + 3] = UInt8(min(255, a * 255))
            }
        }
        return bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)?.makeImage()
        }
    }()

    private func drawDust(in ctx: CGContext, time: Double) {
        guard let dot = WorldKit.softGlow(1, 0.92, 0.75), let glint = WorldKit.star(1, 0.95, 0.8) else { return }
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        for m in motes {
            let lit = sunlight(at: m.position, time: time)
            guard lit > 0.03 else { continue }
            let twinkle = 0.5 + 0.5 * sin(time * 2.3 + m.phase * 7)
            let at = CGPoint(x: m.position.x, y: m.position.y)
            ctx.stampDot(dot, at: at, radius: m.size * 2.2, alpha: lit * (0.35 + 0.5 * twinkle))
            if twinkle > 0.93 { ctx.stampDot(glint, at: at, radius: m.size * 6, alpha: lit * (twinkle - 0.93) / 0.07) }
        }
        ctx.interpolationQuality = .high
        ctx.setBlendMode(.normal)
    }

    /// One shaft of sunlight lying along the x axis: soft at the sides, brightest near the window and fading out along its length.
    private static let shaftSprite: CGImage? = {
        let w = 256, h = 32
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let across = abs((Double(y) + 0.5) / Double(h) * 2 - 1)
            let side = 1 - WorldKit.smoothstep(0.25, 1, across)
            for x in 0..<w {
                let u = Double(x) / Double(w - 1)
                let a = side * (1 - WorldKit.smoothstep(0.2, 1, u)) * WorldKit.smoothstep(0, 0.04, u)
                let i = (y * w + x) * 4
                bytes[i] = UInt8(min(255, sun.z * a * 255))
                bytes[i + 1] = UInt8(min(255, sun.y * a * 255))
                bytes[i + 2] = UInt8(min(255, sun.x * a * 255))
                bytes[i + 3] = UInt8(min(255, a * 255))
            }
        }
        return bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)?.makeImage()
        }
    }()
}
