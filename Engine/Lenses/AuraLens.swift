import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// A flame-like glow around your outline whose tongues lick upward, light wrapping your edges, and embers rising off your
/// head and shoulders: powering up. The rainbow style runs the colours round your outline instead.
final class AuraLens: Lens {
    enum Style { case power, rainbow }

    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private let style: Style
    private var sparks = ParticleSystem(capacity: 360)
    private var rng = SplitMix64(seed: 0xA11A)
    private var presence = WorldPresence()
    private var owed = 0.0

    /// Power: deep ember red through orange and gold to a white-hot core. Read from dark (faint glow) to bright (hottest).
    private static let emberRamp: [(Double, SIMD3<Double>)] = [
        (0, SIMD3(0, 0, 0)), (0.16, SIMD3(0.32, 0.03, 0.0)), (0.38, SIMD3(0.92, 0.28, 0.02)),
        (0.62, SIMD3(1.0, 0.62, 0.12)), (0.84, SIMD3(1.0, 0.86, 0.46)), (1, SIMD3(1.0, 0.97, 0.86)),
    ]
    /// Rainbow: the same shape in grey, to be coloured by the hue wheel.
    private static let whiteRamp: [(Double, SIMD3<Double>)] = [
        (0, SIMD3(0, 0, 0)), (0.2, SIMD3(0.10, 0.10, 0.10)), (0.5, SIMD3(0.55, 0.55, 0.55)), (0.8, SIMD3(0.92, 0.92, 0.92)), (1, SIMD3(1, 1, 1)),
    ]

    // Made on the first frame, on the video queue, so picking the lens never waits for them.
    private var ramp: CIImage?
    private var wheel: CIImage?
    private var prepared = false

    init(style: Style) {
        self.style = style
        sparks.gravity = SIMD2(0, 40)   // heat rises
    }

    func restart() {
        sparks.removeAll()
        presence.reset()
    }

    var sparkCount: Int { sparks.particles.count }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        ramp = WorldKit.ramp(style == .power ? Self.emberRamp : Self.whiteRamp)
        if style == .rainbow { wheel = Self.hueWheel() }
    }

    func render(_ input: LensInput) -> CIImage {
        prepare()
        presence.update(grid: input.matteGrid, dt: input.dt)
        guard let matte = input.matte else { return input.composed }
        let rect = input.rect, t = input.time
        let dt = WorldKit.clamped(input.dt)

        // The glow is soft, so it is worked out at quarter size: a sixteenth of the pixels.
        let scale = 0.25
        let box = CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale)
        let small = WorldKit.shrink(matte, rect: rect, by: scale)
        // Tall blobs of noise drifting up push the tight glow about, so its edge licks upward like flame.
        let noise = WorldKit.clouds(box.insetBy(dx: -24, dy: -24), grain: 7, offset: CGPoint(x: t * 5, y: -t * 46), stretch: CGSize(width: 1, height: 2.6))
        let tight = small.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 2.0])
            .clampedToExtent().applyingGaussianBlur(sigma: 2.4)
            .transformed(by: CGAffineTransform(translationX: 0, y: 2))
            .applyingFilter("CIDisplacementDistortion", parameters: ["inputDisplacementImage": noise, kCIInputScaleKey: 16.0])
            .cropped(to: box)
        let wide = small.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 3.0])
            .clampedToExtent().applyingGaussianBlur(sigma: 13).cropped(to: box)
        let flicker = 0.93 + 0.05 * sin(t * 11) + 0.03 * sin(t * 23 + 1)
        let strength = WorldKit.adding(scaled(tight, 0.7 * flicker), to: scaled(wide, 0.75)).cropped(to: box)

        var light = strength
        if let ramp { light = strength.applyingFilter("CIColorMap", parameters: ["inputGradientImage": ramp]) }
        if style == .rainbow, let wheel {
            let centre = presence.centre * scale
            let turn = CGAffineTransform(translationX: -CGFloat(Self.wheelSide) / 2, y: -CGFloat(Self.wheelSide) / 2)
                .concatenating(CGAffineTransform(rotationAngle: CGFloat(t * 0.7)))
                .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y))
            // The colours are darker than white, so lift them back to the same strength as the power glow.
            light = WorldKit.brightened(WorldKit.multiply(wheel.transformed(by: turn).clampedToExtent(), light), 1.7).cropped(to: box)
        }
        let glow = WorldKit.enlarge(light.settingAlphaOne(in: box), rect: rect, from: scale)

        // Embers behind you, so they rise off your shoulders and out from behind your head without crossing your face.
        emitSparks(from: input.matteGrid, dt: dt)
        sparks.step(dt) { p in
            p.velocity.x += sin(p.age * 4.2 + p.hue * 40) * 70 * dt
            p.velocity *= exp(-0.5 * dt)
        }
        var behind = WorldKit.adding(glow, to: input.scenery)
        if let layer = input.services.overlay({ ctx in draw(sparks: ctx, time: t) }) { behind = WorldKit.adding(layer, to: behind) }
        var body = input.placingPerson(over: behind)

        // Light wrapping round your own edges.
        let wrap = style == .power ? SIMD3(1.0, 0.62, 0.22) : SIMD3(0.8, 0.85, 1.0)
        if let edge = WorldKit.edgeGlow(matte: matte, rect: rect, width: 30, colour: wrap, strength: 0.42 * flicker) {
            body = WorldKit.adding(edge, to: body)
        }
        return body.cropped(to: rect)
    }

    private func scaled(_ grey: CIImage, _ k: Double) -> CIImage {
        WorldKit.tint(grey, SIMD3(1, 1, 1), strength: k)
    }

    // MARK: Embers

    private func emitSparks(from grid: MatteGrid?, dt: Double) {
        guard let grid else { return }
        owed += dt * 140
        guard owed >= 1 else { return }
        // The tops and sides of the outline, not the bottom edge.
        let edges = grid.edges().filter { grid.coverage(x: $0.x, y: $0.y + grid.cellSize * 1.5) < 0.5 }
        guard !edges.isEmpty else {
            owed = 0
            return
        }
        while owed >= 1 {
            owed -= 1
            let at = edges[Int.random(in: 0..<edges.count, using: &rng)]
            sparks.emit(Particle(position: SIMD2(at.x, at.y),
                                 velocity: SIMD2(Double.random(in: -50...50, using: &rng), Double.random(in: 70...210, using: &rng)),
                                 life: Double.random(in: 0.8...1.7, using: &rng),
                                 size: pow(Double.random(in: 0...1, using: &rng), 2) * 4 + 1.6,
                                 hue: Double.random(in: 0..<1, using: &rng)))
        }
    }

    private func draw(sparks ctx: CGContext, time: Double) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        defer { ctx.interpolationQuality = .high }
        let centre = presence.centre
        for p in sparks.particles {
            let k = p.progress
            let fade = (1 - k * k) * min(1, p.age / 0.12)
            let (r, g, b): (Double, Double, Double)
            switch style {
            case .power:
                // White-gold when new, cooling through orange to a deep red ember.
                (r, g, b) = (1, 0.92 - 0.55 * k, 0.6 * (1 - k) * (1 - k))
            case .rainbow:
                let angle = atan2(p.position.y - centre.y, p.position.x - centre.x) / (2 * .pi)
                // Straight from the hue table, so only a few dozen glow sprites are ever made.
                let c = FireworkSkySim.colour(hue: angle - time * 0.7 / (2 * .pi) + 2)
                (r, g, b) = (c.x, c.y, c.z)
            }
            let at = CGPoint(x: p.position.x, y: p.position.y)
            let radius = p.size * (1.25 - 0.6 * k)
            let speed = simd_length(p.velocity)
            if speed > 60, p.size > 2.2, let tail = WorldKit.comet(r, g, b) {
                let length = min(26, speed * 0.07) + radius * 2
                ctx.saveGState()
                ctx.translateBy(x: at.x, y: at.y)
                ctx.rotate(by: atan2(p.velocity.y, p.velocity.x))
                ctx.setAlpha(CGFloat(fade * 0.8))
                ctx.draw(tail, in: CGRect(x: -length, y: -radius * 1.4, width: length + radius * 0.6, height: radius * 2.8))
                ctx.restoreGState()
            }
            if let glow = WorldKit.softGlow(r, g, b) { ctx.stampDot(glow, at: at, radius: radius * 2.6, alpha: fade * 0.55) }
            if p.size > 2.2, let core = WorldKit.softGlow(1, min(1, g + 0.3), min(1, b + 0.3)) { ctx.stampDot(core, at: at, radius: radius, alpha: fade) }
        }
        ctx.setBlendMode(.normal)
    }

    // MARK: Hue wheel

    private static let wheelSide = 256

    /// Every hue round a circle, made once: what the rainbow glow takes its colour from as it turns.
    private static func hueWheel() -> CIImage? {
        let side = wheelSide
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let angle = atan2(Double(side - 1 - y) - Double(side) / 2 + 0.5, Double(x) - Double(side) / 2 + 0.5) / (2 * .pi) + 1   // row 0 is the top
                let c = Palette.rgb(hue: angle.truncatingRemainder(dividingBy: 1), saturation: 0.78)
                let i = (y * side + x) * 4
                bytes[i] = UInt8(c.b * 255)
                bytes[i + 1] = UInt8(c.g * 255)
                bytes[i + 2] = UInt8(c.r * 255)
                bytes[i + 3] = 255
            }
        }
        let image = bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)?.makeImage()
        }
        return image.map { CIImage(cgImage: $0) }
    }
}
