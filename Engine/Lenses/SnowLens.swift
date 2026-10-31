import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Snowflakes falling in three depths on a gusting wind. The middle ones catch on whoever is in front of them and build up a little
/// cap of snow before it melts; the far ones pass behind you and the near ones drift past the camera, big and out of focus.
struct SnowField {
    var particles = ParticleSystem(capacity: 900)
    let size: CGSize
    private var rng: SplitMix64
    private var owed = 0.0
    private(set) var time = 0.0

    static let restingKind = 1

    init(size: CGSize, seed: UInt64 = 0x5110) {
        self.size = size
        rng = SplitMix64(seed: seed)
        particles.gravity = .zero
    }

    var landedCount: Int { particles.particles.filter { $0.kind == Self.restingKind }.count }

    /// How near a flake is, from its size: 0 far behind you ... 1 right in front of the camera.
    static func depth(of p: Particle) -> Double { min(1, max(0, (p.size - 1) / 5.5)) }
    /// Small flakes are far away, behind you.
    static func isFar(_ p: Particle) -> Bool { p.size < 2 }
    /// Big ones are so close they are a blur, and pass in front of you without landing.
    static func isNear(_ p: Particle) -> Bool { p.size > 5 }

    /// The wind, in pixels a second: mostly a steady drift to the left, with slow gusts.
    static func wind(at t: Double) -> Double { -26 + 22 * sin(t * 0.37) + 10 * sin(t * 1.1 + 0.6) }

    private static func fall(_ p: Particle) -> Double {
        let d = depth(of: p)
        return 62 + 170 * d * d + 40 * d
    }

    mutating func step(_ dt: Double, matte: MatteQuery?, rate: Double = 100) {
        let dt = WorldKit.clamped(dt)
        time += dt
        owed += rate * dt
        while owed >= 1 {
            owed -= 1
            let pick = Double.random(in: 0..<1, using: &rng)
            let flake: Double = pick < 0.4 ? Double.random(in: 1.0...1.95, using: &rng)
                : pick < 0.955 ? Double.random(in: 2.0...4.9, using: &rng) : Double.random(in: 5.1...6.5, using: &rng)
            var p = Particle(position: SIMD2(Double.random(in: -150...(size.width + 150), using: &rng), size.height + 12 + flake * 3),
                             velocity: .zero, age: 0, life: 40, size: flake, hue: Double.random(in: 0..<1, using: &rng), kind: 0)
            p.velocity = SIMD2(Self.wind(at: time), -Self.fall(p))
            particles.emit(p)
        }

        let wind = Self.wind(at: time)
        let floor = -8.0
        let width = size.width
        particles.step(dt) { p in
            if p.kind == 0 {
                // Drift on the wind (the near ones seem to move more), sway, and flutter a little in speed.
                let d = Self.depth(of: p)
                p.velocity.x = wind * (0.55 + 0.9 * d) + sin(p.age * 1.6 + p.hue * 6.28) * (12 + 22 * d)
                p.velocity.y = -Self.fall(p) * (0.88 + 0.12 * sin(p.age * 2.3 + p.hue * 9))
                if p.position.y < floor || p.position.x < -220 || p.position.x > width + 220 {
                    p.age = p.life
                    return
                }
                // It lands only by coming down from above onto something fairly flat, like the top of a head or a shoulder:
                // a flake already in front of you, or meeting the steep side of you, just falls past.
                if !Self.isFar(p), !Self.isNear(p), let matte, matte.coverage(x: p.position.x, y: p.position.y) > 0.5,
                   matte.coverage(x: p.position.x - p.velocity.x * dt, y: p.position.y - p.velocity.y * dt) < 0.5,
                   matte.coverage(x: p.position.x - 12, y: p.position.y - 8) > 0.5, matte.coverage(x: p.position.x + 12, y: p.position.y - 8) > 0.5 {
                    p.kind = Self.restingKind
                    p.velocity = .zero
                    p.life = p.age + 3.5 + p.hue * 4.5     // melts after a while
                }
            } else if let matte, matte.coverage(x: p.position.x, y: p.position.y) < 0.3 {
                // Whatever it was resting on has moved away: it falls again.
                p.kind = 0
                p.velocity = SIMD2(0, -Self.fall(p))
            } else if let matte, matte.coverage(x: p.position.x, y: p.position.y + 16) > 0.6 {
                // You moved and it ended up inside your outline rather than on top: it melts away quickly.
                p.life = min(p.life, p.age + 0.35)
            }
        }
    }

    mutating func removeAll() {
        particles.removeAll()
        time = 0
    }
}

final class SnowLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private var snow: SnowField

    /// "Frost": the colours of the winter light.
    private static let frost = (sky: SIMD3(0.80, 0.89, 1.04), lift: SIMD3(0.012, 0.017, 0.028), flake: SIMD3(0.94, 0.97, 1.0),
                                shade: SIMD3(0.62, 0.72, 0.88), rim: SIMD3(0.78, 0.88, 1.0))

    init(size: CGSize = CGSize(width: 1280, height: 720)) { snow = SnowField(size: size) }

    func restart() {
        snow.removeAll()
        warmed = false
    }

    /// Whether the sky has been filled yet. Done on the first frame (on the video queue), so it starts already snowing.
    private var warmed = false

    var landedCount: Int { snow.landedCount }
    var flakeCount: Int { snow.particles.particles.count }

    func render(_ input: LensInput) -> CIImage {
        // Gusts bring more snow now and then.
        if !warmed {
            warmed = true
            for _ in 0..<120 { snow.step(1.0 / 15, matte: nil, rate: 85) }
        }
        let rate = 85 + 30 * max(0, sin(input.time * 0.37))
        snow.step(input.dt, matte: input.matteGrid, rate: rate)
        let f = Self.frost

        // A cold, slightly misty light over the room; the person keeps more of their colour.
        let room = WorldKit.grade(input.scenery, saturation: 0.7, tint: (f.sky.x, f.sky.y, f.sky.z), lift: (f.lift.x, f.lift.y, f.lift.z))
        let person = WorldKit.grade(input.composed, saturation: 0.88, tint: (0.93, 0.97, 1.04), lift: (0.004, 0.006, 0.01))
        let mist = CIFilter.linearGradient()
        mist.point0 = CGPoint(x: 0, y: input.rect.minY)
        mist.point1 = CGPoint(x: 0, y: input.rect.minY + input.rect.height * 0.35)
        mist.color0 = CIColor(red: 0.75, green: 0.82, blue: 0.95, alpha: 0.10)
        mist.color1 = CIColor(red: 0.75, green: 0.82, blue: 0.95, alpha: 0)
        var behind = WorldKit.adding((mist.outputImage ?? CIImage.empty()).cropped(to: input.rect), to: room)
        if let far = input.services.overlay({ ctx in drawFlakes(in: ctx, far: true) }) { behind = far.composited(over: behind) }
        var body = WorldKit.place(person: person, over: behind, matte: input.matte, rect: input.rect)
        if let rim = WorldKit.rimLight(matte: input.matte, rect: input.rect, toward: WorldKit.keyLight, width: 10, colour: f.rim, strength: 0.22) {
            body = WorldKit.adding(rim, to: body)
        }
        guard let front = input.services.overlay({ ctx in drawFlakes(in: ctx, far: false) }) else { return body }
        return front.composited(over: body).cropped(to: input.rect)
    }

    // MARK: Drawing

    private func drawFlakes(in ctx: CGContext, far: Bool) {
        ctx.interpolationQuality = .low
        defer { ctx.interpolationQuality = .high }
        let f = Self.frost
        guard let soft = WorldKit.softGlow(f.flake.x, f.flake.y, f.flake.z) else { return }
        if far {
            for p in snow.particles.particles where SnowField.isFar(p) {
                let d = SnowField.depth(of: p)
                ctx.stampDot(soft, at: CGPoint(x: p.position.x, y: p.position.y), radius: 1.6 + 6 * d, alpha: 0.55 + 1.5 * d)
            }
            return
        }
        // Snow resting on you first, so falling flakes pass in front of it: soft heaps with a blue shade under each.
        if let shade = WorldKit.softGlow(f.shade.x, f.shade.y, f.shade.z) {
            for p in snow.particles.particles where p.kind == SnowField.restingKind {
                let melt = min(1, (p.life - p.age) / 1.2) * min(1, p.age / 0.25 + 0.4)
                let r = (4 + p.size * 1.5) * (0.7 + 0.3 * melt)
                // A heap is wider than it is tall, with its shaded underside just below; neighbours run together into a drift.
                ctx.saveGState()
                ctx.translateBy(x: p.position.x, y: p.position.y)
                ctx.scaleBy(x: 2.2, y: 1)
                ctx.stampDot(shade, at: CGPoint(x: 0.4, y: -r * 0.42), radius: r * 1.5, alpha: 0.4 * melt)
                ctx.stampDot(soft, at: .zero, radius: r * 1.8, alpha: 0.85 * melt)
                ctx.stampDot(soft, at: CGPoint(x: -r * 0.12, y: r * 0.2), radius: r * 0.9, alpha: 0.9 * melt)
                ctx.restoreGState()
            }
        }
        for p in snow.particles.particles where p.kind == 0 && !SnowField.isFar(p) {
            let at = CGPoint(x: p.position.x, y: p.position.y)
            if SnowField.isNear(p) {
                // So close it is out of focus: a big soft disc, a little stretched by its fall.
                guard let bokeh = Self.bokeh else { continue }
                let r = p.size * 3.6
                ctx.saveGState()
                ctx.translateBy(x: at.x, y: at.y)
                ctx.scaleBy(x: 1, y: 1.1)
                ctx.setAlpha(0.24)
                ctx.draw(bokeh, in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
                ctx.restoreGState()
            } else if p.size > 4.1, let crystal = Self.crystals[Int(p.hue * 97) % Self.crystals.count] {
                // Big enough to see its shape: a six-armed crystal, slowly turning.
                let r = p.size * 2.9
                ctx.saveGState()
                ctx.translateBy(x: at.x, y: at.y)
                ctx.rotate(by: p.age * (p.hue - 0.5) * 1.6 + p.hue * 6)
                ctx.draw(crystal, in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
                ctx.restoreGState()
            } else if let flake = Self.flake {
                let r = p.size * 1.5
                ctx.draw(flake, in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2))
            }
        }
    }

    // MARK: Sprites

    /// Two six-armed snow crystals with little side branches and a soft glow, drawn once.
    private static let crystals: [CGImage?] = [crystal(branches: 2, seed: 0), crystal(branches: 1, seed: 1)]
    private static let bokeh: CGImage? = makeBokeh()

    /// A small flake: a solid bright middle with a soft cool edge, so one stamp is enough.
    private static let flake: CGImage? = {
        let side = 32
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let c = CGFloat(side) / 2
        let colours = [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 0.96, green: 0.98, blue: 1, alpha: 0.95),
                       CGColor(red: 0.85, green: 0.92, blue: 1, alpha: 0.35), CGColor(red: 0.85, green: 0.92, blue: 1, alpha: 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.32, 0.6, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: c, y: c), startRadius: 0, endCenter: CGPoint(x: c, y: c), endRadius: c, options: [])
        }
        return ctx.makeImage()
    }()

    private static func crystal(branches: Int, seed: Int) -> CGImage? {
        let side = 72
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let c = CGFloat(side) / 2
        ctx.translateBy(x: c, y: c)
        // A faint glow behind, then the arms.
        let glow = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.9, green: 0.95, blue: 1, alpha: 0.55), CGColor(red: 0.9, green: 0.95, blue: 1, alpha: 0)] as CFArray,
                              locations: [0, 1])
        if let glow { ctx.drawRadialGradient(glow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: c * 0.55, options: []) }
        ctx.setLineCap(.round)
        ctx.setShadow(offset: .zero, blur: 4, color: CGColor(red: 0.75, green: 0.88, blue: 1, alpha: 1))
        ctx.setStrokeColor(CGColor(red: 0.97, green: 0.99, blue: 1, alpha: 1))
        let arm = c * 0.86
        for k in 0..<6 {
            ctx.saveGState()
            ctx.rotate(by: CGFloat(k) * .pi / 3)
            ctx.setLineWidth(c * 0.06)
            ctx.move(to: .zero)
            ctx.addLine(to: CGPoint(x: 0, y: arm))
            ctx.strokePath()
            ctx.setLineWidth(c * 0.045)
            for b in 0..<branches {
                let along = arm * (seed == 0 ? [0.42, 0.68][b] : 0.55)
                let reach = arm * (seed == 0 ? [0.26, 0.17][b] : 0.3)
                for side in [-1.0, 1.0] {
                    ctx.move(to: CGPoint(x: 0, y: along))
                    ctx.addLine(to: CGPoint(x: CGFloat(side) * reach * 0.8, y: along + reach * 0.75))
                }
                ctx.strokePath()
            }
            ctx.restoreGState()
        }
        ctx.fillCircle(center: .zero, radius: c * 0.11, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        return ctx.makeImage()
    }

    /// An out-of-focus flake: an even soft disc, a touch brighter at its rim, as a camera lens draws a point of light.
    private static func makeBokeh() -> CGImage? {
        let side = 64
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let c = CGFloat(side) / 2
        let colours = [CGColor(red: 0.97, green: 0.98, blue: 1, alpha: 0.6), CGColor(red: 0.97, green: 0.98, blue: 1, alpha: 0.5),
                       CGColor(red: 0.97, green: 0.98, blue: 1, alpha: 0.62), CGColor(red: 0.97, green: 0.98, blue: 1, alpha: 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.6, 0.8, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: c, y: c), startRadius: 0, endCenter: CGPoint(x: c, y: c), endRadius: c - 1, options: [])
        }
        return ctx.makeImage()
    }
}
