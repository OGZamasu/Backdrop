import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText

/// Shared bits for the live scenes: things that fall and tumble.
private struct BackdropFaller {
    let x: Double, y: Double            // where it starts, as shares of the width and height
    let fall: Double, drift: Double     // pixels a second, down and sideways (on the half-size canvas)
    let sway: Double, swayRate: Double, phase: Double
    let spin: Double, flip: Double      // turns a second around its face, and across it (tumbling)
    let size: Double, kind: Int, near: Bool

    static func make(count: Int, seed: UInt64, kinds: Int, fall: ClosedRange<Double>, drift: ClosedRange<Double>, size: ClosedRange<Double>) -> [BackdropFaller] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in
            let depth = pow(Double.random(in: 0..<1, using: &rng), 1.8)
            let scale = 0.55 + 0.9 * depth
            return BackdropFaller(x: .random(in: 0..<1, using: &rng), y: .random(in: 0..<1, using: &rng),
                                  fall: Double.random(in: fall, using: &rng) * scale, drift: Double.random(in: drift, using: &rng) * scale,
                                  sway: .random(in: 8...26, using: &rng), swayRate: .random(in: 0.4...1.1, using: &rng), phase: .random(in: 0..<(2 * .pi), using: &rng),
                                  spin: .random(in: -0.35...0.35, using: &rng), flip: .random(in: 0.2...0.7, using: &rng),
                                  size: Double.random(in: size, using: &rng) * scale, kind: Int.random(in: 0..<kinds, using: &rng), near: depth > 0.82)
        }
    }

    /// Draws every faller at `time` on a 640 x 360 canvas, wrapping around the edges, tumbling as it goes.
    static func draw(_ fallers: [BackdropFaller], sprites: [CGImage], soft: [CGImage], into ctx: CGContext, at time: Double) {
        let w = 640.0, h = 360.0, margin = 40.0
        for f in fallers {
            let y = h + margin - BackdropMath.fract(f.y + f.fall * time / (h + 2 * margin)) * (h + 2 * margin)
            let x = BackdropMath.fract(f.x + f.drift * time / (w + 2 * margin)) * (w + 2 * margin) - margin
                + f.sway * BackdropMotion.wave(time, rate: f.swayRate, phase: f.phase)
            let angle = 2 * Double.pi * BackdropMath.fract(f.spin * time + f.phase)
            let turn = BackdropMotion.wave(time, rate: 2 * .pi * f.flip, phase: f.phase)
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: angle)
            ctx.scaleBy(x: max(0.18, abs(turn)), y: 1)
            let sprite = f.near ? soft[f.kind % soft.count] : sprites[f.kind % sprites.count]
            ctx.setAlpha(f.near ? 0.8 : 1)
            ctx.draw(sprite, in: CGRect(x: -f.size / 2, y: -f.size / 2, width: f.size, height: f.size))
            ctx.restoreGState()
        }
    }
}

// MARK: - Drifting clouds

/// A bright summer sky with soft clouds sliding slowly past in two layers, the near ones faster.
final class BackdropDriftingClouds: BackdropScene {
    typealias RGB = BackdropRGB
    private var tables: (body: CIImage, belly: CIImage)?

    override func paint() -> CIImage? {
        tables = (BackdropInk.table([(at: 0, color: RGB(hex: 0xC9D8EA), alpha: 0), (at: 0.5, color: RGB(hex: 0xC9D8EA), alpha: 0),
                                     (at: 0.72, color: RGB(hex: 0xE6EEF7), alpha: 0.7), (at: 1, color: RGB(1, 1, 1), alpha: 1)]),
                  BackdropInk.table([(at: 0, color: RGB(hex: 0x9FB1C8), alpha: 0), (at: 0.5, color: RGB(hex: 0x9FB1C8), alpha: 0),
                                     (at: 0.72, color: RGB(hex: 0x9FB1C8), alpha: 0.6), (at: 1, color: RGB(hex: 0x95A8C0), alpha: 0.85)]))
        return BackdropPainter.paint(width: 320, height: 180) { ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: RGB(hex: 0xB4D6F0)), (at: 0.45, color: RGB(hex: 0x6FA7DD)), (at: 1, color: RGB(hex: 0x2F69B3))])
            BackdropPainter.glow(ctx, at: CGPoint(x: 140, y: 700), radius: 620, color: RGB(1, 0.98, 0.9), alpha: 0.45, blend: .screen)
        }
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        guard let tables else { return still }
        let frame = BackdropPainter.frame
        // Each layer: a field of noise made into cloud, over its own copy shifted down and greyer, so the clouds are lit
        // from above with darker bellies. Worked out at half size (clouds are soft) and enlarged.
        let half = CGRect(x: 0, y: 0, width: 640, height: 360)
        func layer(channel: Int, scale: CGFloat, speed: Double, stretch: CGFloat, strength: Double) -> CIImage {
            let offset = CGPoint(x: time * speed / 2, y: 20)
            let body = BackdropInk.colored(BackdropNoise.field(channel, scale: scale / 2, offset: offset, stretch: stretch, extent: half), tables.body)
            let belly = BackdropInk.colored(BackdropNoise.field(channel, scale: scale / 2, offset: CGPoint(x: offset.x, y: offset.y + 7 * scale), stretch: stretch, extent: half), tables.belly)
            return body.composited(over: belly).applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: strength)])
        }
        let clouds = layer(channel: 2, scale: 7, speed: 13, stretch: 0.55, strength: 0.95).composited(over: layer(channel: 0, scale: 4.2, speed: 5, stretch: 0.45, strength: 0.75))
        let enlarge = CIFilter.bicubicScaleTransform()
        enlarge.inputImage = clouds.clampedToExtent()
        enlarge.scale = 2
        enlarge.aspectRatio = 1
        enlarge.parameterB = 1
        enlarge.parameterC = 0
        let sky = (enlarge.outputImage ?? clouds).cropped(to: frame).composited(over: still)
        return BackdropFinish.finish(BackdropFinish.vignette(sky, strength: 0.12), grain: 0.5)
    }
}

// MARK: - Campfire

/// A campfire at night at the edge of a wood: flames licking up from crossed logs, sparks rising, the fire's warm light
/// flickering gently on a tent and the trees.
final class BackdropCampfire: BackdropScene {
    typealias RGB = BackdropRGB
    private static let fire = CGPoint(x: 230, y: 96)
    private struct Spark { let phase: Double, period: Double, drift: Double, sway: Double, size: Double }
    private let sparks: [Spark]
    private var canvas: BackdropCanvas?
    private var glow: CGImage?

    override init() {
        var rng = SplitMix64(seed: 0xF12E)
        sparks = (0..<46).map { _ in
            Spark(phase: .random(in: 0..<1, using: &rng), period: .random(in: 2.2...4.5, using: &rng), drift: .random(in: -40...60, using: &rng),
                  sway: .random(in: 6...18, using: &rng), size: .random(in: 1.0...2.4, using: &rng))
        }
    }

    override func paint() -> CIImage? {
        BackdropPainter.paint { ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: RGB(hex: 0x14121C)), (at: 0.3, color: RGB(hex: 0x0E1A2E)), (at: 1, color: RGB(hex: 0x04070F))])
            var rng = SplitMix64(seed: 0xF12F)
            for _ in 0..<150 {
                let p = CGPoint(x: .random(in: 0..<1280, using: &rng), y: .random(in: 330..<720, using: &rng))
                let r = CGFloat.random(in: 0.5...1.2, using: &rng)
                ctx.setFillColor(RGB(0.9, 0.93, 1).cg(Double.random(in: 0.2...0.75, using: &rng)))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            // Trees all round, their trunks catching a little firelight.
            for _ in 0..<30 {
                var x = CGFloat.random(in: -30...1310, using: &rng)
                if x > 460 && x < 820 { x += x < 640 ? -240 : 240 }
                BackdropLandscape.pine(ctx, x: x, base: 120, height: CGFloat.random(in: 200...420, using: &rng), color: RGB(hex: 0x070B10).cg, rng: &rng)
            }
            // Ground.
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: 130), [(at: 0, color: RGB(hex: 0x0B0806)), (at: 1, color: RGB(hex: 0x1A120C))])
            // A tent on the right, glowing from inside.
            let tent = CGMutablePath()
            tent.move(to: CGPoint(x: 900, y: 110)); tent.addLine(to: CGPoint(x: 1050, y: 330)); tent.addLine(to: CGPoint(x: 1230, y: 110)); tent.closeSubpath()
            BackdropPainter.fill(ctx, tent, gradient: [(at: 0, color: RGB(hex: 0xB8662E)), (at: 0.6, color: RGB(hex: 0x6B3218)), (at: 1, color: RGB(hex: 0x2E150A))],
                                 from: CGPoint(x: 900, y: 0), to: CGPoint(x: 1230, y: 0))
            let door = CGMutablePath()
            door.move(to: CGPoint(x: 1010, y: 110)); door.addLine(to: CGPoint(x: 1050, y: 300)); door.addLine(to: CGPoint(x: 1095, y: 110)); door.closeSubpath()
            BackdropPainter.fill(ctx, door, gradient: [(at: 0, color: RGB(hex: 0xFFC46A)), (at: 1, color: RGB(hex: 0xC2672A))], from: CGPoint(x: 0, y: 110), to: CGPoint(x: 0, y: 300))
            BackdropPainter.glow(ctx, at: CGPoint(x: 1050, y: 160), radius: 160, color: RGB(hex: 0xFFA94D), alpha: 0.25, blend: .screen)
            // Stones ringing the fire, and the crossed logs.
            let f = Self.fire
            for k in 0..<9 {
                let a = Double(k) / 9 * 2 * .pi
                let p = CGPoint(x: f.x + cos(a) * 70, y: f.y - 18 + sin(a) * 16)
                BackdropPainter.fill(ctx, CGPath(ellipseIn: CGRect(x: p.x - 16, y: p.y - 9, width: 32, height: 20), transform: nil),
                                     gradient: [(at: 0, color: RGB(hex: 0x2A2420)), (at: 1, color: RGB(hex: 0x6E5040))], from: CGPoint(x: 0, y: p.y - 9), to: CGPoint(x: 0, y: p.y + 11))
            }
            for (dx, angle) in [(CGFloat(-10), CGFloat(0.35)), (10, -0.35), (0, 0.05)] {
                ctx.saveGState()
                ctx.translateBy(x: f.x + dx, y: f.y - 6)
                ctx.rotate(by: angle)
                BackdropPainter.fill(ctx, BackdropPainter.rounded(CGRect(x: -62, y: -9, width: 124, height: 18), 9),
                                     gradient: [(at: 0, color: RGB(hex: 0x1E120A)), (at: 0.7, color: RGB(hex: 0x4A2C18)), (at: 1, color: RGB(hex: 0xA2502A))], from: CGPoint(x: 0, y: -9), to: CGPoint(x: 0, y: 9))
                ctx.restoreGState()
            }
        }.map { BackdropFinish.finish(BackdropFinish.vignette($0, strength: 0.3), grain: 0.9) }
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        if canvas == nil { canvas = BackdropCanvas(width: 640, height: 360) }
        if glow == nil { glow = BackdropSprite.glow(RGB(hex: 0xFFB050), side: 32, core: 1, hot: 0.8) }
        guard let canvas, let glow else { return still }
        let f = CGPoint(x: Self.fire.x / 2, y: Self.fire.y / 2)
        // A gentle flicker, from a few slow waves added together: never a flash.
        let flicker = 0.88 + 0.06 * BackdropMotion.wave(time, rate: 7.1) + 0.04 * BackdropMotion.wave(time, rate: 11.3, phase: 1) + 0.03 * BackdropMotion.wave(time, rate: 3.2, phase: 2)
        canvas.clear()
        let ctx = canvas.context
        ctx.setBlendMode(.plusLighter)
        // Firelight on the ground and trees.
        BackdropPainter.glow(ctx, at: CGPoint(x: f.x, y: f.y + 6), radius: CGFloat(190 * flicker), color: RGB(hex: 0xFF8A3A), alpha: 0.20 * flicker, squash: 0.55)
        BackdropPainter.glow(ctx, at: CGPoint(x: f.x, y: f.y + 16), radius: CGFloat(70 * flicker), color: RGB(hex: 0xFFB060), alpha: 0.28 * flicker)
        // Flames: tongues of fire, each rising and falling on its own, layered red to yellow to a white-hot heart.
        for k in 0..<7 {
            let spread = Double(k - 3)
            let lift = 0.7 + 0.3 * BackdropMotion.wave(time, rate: 6 + Double(k) * 1.3, phase: Double(k) * 2.1)
            let height = (54 - abs(spread) * 9) * lift
            let sway = 6 * BackdropMotion.wave(time, rate: 4.4 + Double(k), phase: Double(k))
            let base = CGPoint(x: f.x + spread * 8, y: f.y - 2)
            for (scale, colour, alpha) in [(1.0, RGB(hex: 0xE2401C), 0.55), (0.72, RGB(hex: 0xFF9A2E), 0.7), (0.42, RGB(hex: 0xFFE7A0), 0.85)] {
                let w = (13 - abs(spread) * 1.4) * scale, hh = height * scale
                let tongue = CGMutablePath()
                tongue.move(to: CGPoint(x: base.x - w, y: base.y))
                tongue.addQuadCurve(to: CGPoint(x: base.x + sway, y: base.y + hh), control: CGPoint(x: base.x - w * 0.9, y: base.y + hh * 0.6))
                tongue.addQuadCurve(to: CGPoint(x: base.x + w, y: base.y), control: CGPoint(x: base.x + w * 0.9 + sway * 0.5, y: base.y + hh * 0.5))
                tongue.closeSubpath()
                ctx.addPath(tongue)
                ctx.setFillColor(colour.cg(alpha * flicker))
                ctx.fillPath()
            }
        }
        // Sparks rising, swaying, cooling and fading.
        for s in sparks {
            let p = BackdropMotion.loop(time, period: s.period, offset: s.phase)
            let at = CGPoint(x: f.x + s.drift * p + s.sway * BackdropMotion.wave(time, rate: 2.5, phase: s.phase * 6), y: f.y + 20 + p * 220)
            let life = (1 - p) * BackdropMath.smoothstep(0, 0.08, p)
            ctx.setAlpha(CGFloat(life))
            let r = s.size * (1.6 - p)
            ctx.draw(glow, in: CGRect(x: at.x - r * 2, y: at.y - r * 2, width: r * 4, height: r * 4))
        }
        ctx.setAlpha(1)
        ctx.setBlendMode(.normal)
        guard let fire = canvas.image(scale: 2) else { return still }
        let soft = fire.applyingGaussianBlur(sigma: 1.2).cropped(to: BackdropPainter.frame)
        return soft.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: still]).cropped(to: BackdropPainter.frame)
    }
}

// MARK: - Aquarium

/// Under water: light from the surface rippling down in shafts and dancing caustics, fish gliding by at different
/// depths, bubbles rising, seaweed swaying over a sandy floor with rocks and coral.
final class BackdropAquarium: BackdropScene {
    typealias RGB = BackdropRGB
    private struct Fish { let y: Double, speed: Double, phase: Double, size: Double, kind: Int, depth: Double, bob: Double }
    private struct Bubble { let x: Double, phase: Double, period: Double, size: Double }
    private let fish: [Fish]
    private let bubbles: [Bubble]
    private var fishSprites: [CGImage] = []
    private var bubble: CGImage?
    private var canvas: BackdropCanvas?
    private var causticTable: CIImage?
    private var causticMask: CIImage?

    override init() {
        var rng = SplitMix64(seed: 0xF15A)
        fish = (0..<9).map { k in
            let depth = Double.random(in: 0..<1, using: &rng)
            return Fish(y: .random(in: 0.3...0.85, using: &rng), speed: (k % 2 == 0 ? 1 : -1) * .random(in: 10...24, using: &rng) * (0.6 + 0.6 * depth),
                        phase: .random(in: 0..<1, using: &rng), size: 26 + 40 * depth, kind: Int.random(in: 0..<3, using: &rng), depth: depth,
                        bob: .random(in: 0..<(2 * .pi), using: &rng))
        }
        bubbles = (0..<26).map { _ in
            Bubble(x: .random(in: 0.04...0.18, using: &rng) + (Bool.random(using: &rng) ? 0 : 0.8), phase: .random(in: 0..<1, using: &rng),
                   period: .random(in: 4...8, using: &rng), size: .random(in: 2...5, using: &rng))
        }
    }

    override func paint() -> CIImage? {
        causticTable = BackdropInk.table([(at: 0, color: RGB(0.8, 1, 1), alpha: 0.42), (at: 0.03, color: RGB(0.6, 0.95, 1), alpha: 0.14), (at: 0.07, color: RGB(0.5, 0.9, 1), alpha: 0), (at: 1, color: RGB(0.5, 0.9, 1), alpha: 0)])
        causticMask = BackdropPainter.paint(width: 64, height: 36) { ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: RGB(0.75, 0.75, 0.75)), (at: 0.16, color: RGB(0.6, 0.6, 0.6)), (at: 0.25, color: RGB(0.08, 0.08, 0.08)),
                                                                  (at: 0.7, color: RGB(0.12, 0.12, 0.12)), (at: 1, color: RGB(0.55, 0.55, 0.55))])
        }
        return BackdropPainter.paint { ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: RGB(hex: 0x05233A)), (at: 0.5, color: RGB(hex: 0x0B4A6E)), (at: 1, color: RGB(hex: 0x1C86A8))])
            // Shafts of light from the surface.
            var rng = SplitMix64(seed: 0xA9A)
            for _ in 0..<6 {
                let top = CGFloat.random(in: 80...1200, using: &rng), w = CGFloat.random(in: 50...120, using: &rng)
                let beam = CGMutablePath()
                beam.move(to: CGPoint(x: top - w / 2, y: 720)); beam.addLine(to: CGPoint(x: top + w / 2, y: 720))
                beam.addLine(to: CGPoint(x: top + w * 1.6 - 120, y: 80)); beam.addLine(to: CGPoint(x: top - w * 0.4 - 120, y: 80)); beam.closeSubpath()
                BackdropRoom.soft(ctx, beam, RGB(0.7, 0.95, 1).cg(0.10), blur: 26)
            }
            // Sand, rocks and coral along the bottom.
            BackdropPainter.fill(ctx, BackdropPainter.ridge(BackdropPainter.ridgeLine(base: 70, height: 50, seed: 6.1, wavelength: 260, rough: 0.1), floor: -10),
                                 gradient: [(at: 0, color: RGB(hex: 0x6E6A52)), (at: 1, color: RGB(hex: 0xB5A57A))], from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 120))
            for (x, w, h) in [(CGFloat(120), CGFloat(170), CGFloat(110)), (1080, 220, 140), (300, 90, 60), (900, 110, 70)] {
                BackdropPainter.fill(ctx, CGPath(ellipseIn: CGRect(x: x - w / 2, y: 40, width: w, height: h), transform: nil),
                                     gradient: [(at: 0, color: RGB(hex: 0x1E3A44)), (at: 1, color: RGB(hex: 0x4F7480))], from: CGPoint(x: x + w / 2, y: 40), to: CGPoint(x: x - w / 3, y: 40 + h))
            }
            for (x, colour) in [(CGFloat(190), RGB(hex: 0xE8735A)), (CGFloat(1010), RGB(hex: 0xD9668F)), (CGFloat(1150), RGB(hex: 0xF0A04B))] {
                // Branching coral.
                func branch(_ p: CGPoint, _ angle: CGFloat, _ length: CGFloat, _ depth: Int) {
                    guard depth > 0 else { return }
                    let end = CGPoint(x: p.x + sin(angle) * length, y: p.y + cos(angle) * length)
                    ctx.move(to: p); ctx.addLine(to: end)
                    ctx.setStrokeColor(colour.scaled(0.75 + 0.08 * Double(depth)).cg); ctx.setLineWidth(CGFloat(depth) * 2.4); ctx.setLineCap(.round); ctx.strokePath()
                    branch(end, angle - 0.42, length * 0.74, depth - 1)
                    branch(end, angle + 0.38, length * 0.7, depth - 1)
                }
                branch(CGPoint(x: x, y: 90), 0, 52, 4)
            }
        }.map { BackdropFinish.finish(BackdropFinish.vignette($0, strength: 0.3), grain: 0.8) }
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        if fishSprites.isEmpty { fishSprites = [RGB(hex: 0xFF9A3C), RGB(hex: 0x5FD3E8), RGB(hex: 0xF5D04A)].compactMap(Self.makeFish) }
        if bubble == nil { bubble = Self.makeBubble() }
        if canvas == nil { canvas = BackdropCanvas(width: 640, height: 360) }
        guard let canvas, let bubble, fishSprites.count == 3, let causticTable, let causticMask else { return still }
        let frame = BackdropPainter.frame
        // Caustics: where two drifting ripple fields nearly agree, light gathers into a dancing net.
        // Worked out at half size and enlarged: the net is soft-edged anyway.
        let half = BackdropPainter.half
        let a = BackdropNoise.field(0, scale: 0.7, offset: CGPoint(x: time * 4.5, y: time * 2.5), extent: half)
        let b = BackdropNoise.field(1, scale: 0.95, offset: CGPoint(x: -time * 3.5, y: time * 3), extent: half)
        let net = BackdropInk.colored(a.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: b]).cropped(to: half), causticTable)
        let caustics = BackdropPainter.enlarged(net).applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: causticMask])

        canvas.clear()
        let ctx = canvas.context
        // Seaweed swaying from the sand.
        ctx.setLineCap(.round)
        for k in 0..<8 {
            let x0 = Double([40, 70, 260, 330, 880, 930, 1180, 1230][k]) / 2
            let height = 70.0 + Double(k % 3) * 22
            let sway = 14 * BackdropMotion.wave(time, rate: 0.7 + Double(k) * 0.07, phase: Double(k))
            ctx.move(to: CGPoint(x: x0, y: 20))
            ctx.addCurve(to: CGPoint(x: x0 + sway, y: 20 + height), control1: CGPoint(x: x0 - sway * 0.6, y: 20 + height * 0.35), control2: CGPoint(x: x0 + sway * 1.2, y: 20 + height * 0.7))
            ctx.setStrokeColor(RGB(hex: 0x2E6B3E).scaled(0.8 + 0.1 * Double(k % 3)).cg(0.95))
            ctx.setLineWidth(5)
            ctx.strokePath()
        }
        // Fish, far ones first: faded into the blue and smaller.
        for f in fish.sorted(by: { $0.depth < $1.depth }) {
            let span = 640.0 + 160
            let x = BackdropMath.fract(f.phase + f.speed * time / span) * span - 80
            let y = 360 * f.y + 6 * BackdropMotion.wave(time, rate: 0.8, phase: f.bob)
            let wiggle = 0.06 * BackdropMotion.wave(time, rate: 5, phase: f.bob)
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: wiggle)
            if f.speed < 0 { ctx.scaleBy(x: -1, y: 1) }
            ctx.setAlpha(CGFloat(0.45 + 0.55 * f.depth))
            let size = f.size / 2
            ctx.draw(fishSprites[f.kind], in: CGRect(x: -size, y: -size / 2, width: size * 2, height: size))
            ctx.restoreGState()
        }
        // Bubbles rising and wobbling.
        for bb in bubbles {
            let p = BackdropMotion.loop(time, period: bb.period, offset: bb.phase)
            let at = CGPoint(x: bb.x * 640 + 4 * BackdropMotion.wave(time, rate: 3, phase: bb.phase * 9), y: 30 + p * 360)
            ctx.setAlpha(CGFloat(0.8 * (1 - BackdropMath.smoothstep(0.85, 1, p))))
            let r = bb.size * (0.8 + 0.4 * p)
            ctx.draw(bubble, in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2))
        }
        ctx.setAlpha(1)
        guard let life = canvas.image(scale: 2) else { return still }
        let lit = caustics.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: still]).cropped(to: frame)
        return BackdropFinish.finish(life.composited(over: lit))
    }

    /// A fish facing right: a plump body lit from above, a forked tail, a fin, an eye.
    private static func makeFish(_ colour: RGB) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: 128, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: BackdropCanvas.space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 118, y: 32))
        body.addCurve(to: CGPoint(x: 34, y: 34), control1: CGPoint(x: 100, y: 58), control2: CGPoint(x: 52, y: 56))
        body.addCurve(to: CGPoint(x: 118, y: 32), control1: CGPoint(x: 52, y: 10), control2: CGPoint(x: 100, y: 6))
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: 40, y: 33)); tail.addLine(to: CGPoint(x: 6, y: 54)); tail.addQuadCurve(to: CGPoint(x: 6, y: 12), control: CGPoint(x: 18, y: 33)); tail.closeSubpath()
        BackdropPainter.fill(ctx, tail, gradient: [(at: 0, color: colour.scaled(0.6)), (at: 1, color: colour)], from: CGPoint(x: 6, y: 0), to: CGPoint(x: 40, y: 0))
        BackdropPainter.fill(ctx, body, gradient: [(at: 0, color: colour.scaled(0.55)), (at: 0.55, color: colour), (at: 1, color: colour.mixed(RGB(1, 1, 1), 0.45))],
                             from: CGPoint(x: 0, y: 10), to: CGPoint(x: 0, y: 56))
        let fin = CGMutablePath()
        fin.move(to: CGPoint(x: 66, y: 50)); fin.addQuadCurve(to: CGPoint(x: 92, y: 52), control: CGPoint(x: 76, y: 64)); fin.closeSubpath()
        ctx.addPath(fin); ctx.setFillColor(colour.scaled(0.75).cg); ctx.fillPath()
        ctx.setFillColor(RGB(1, 1, 1).cg); ctx.fillEllipse(in: CGRect(x: 96, y: 34, width: 9, height: 9))
        ctx.setFillColor(RGB(0.05, 0.05, 0.1).cg); ctx.fillEllipse(in: CGRect(x: 99, y: 36, width: 5, height: 5))
        return ctx.makeImage()
    }

    private static func makeBubble() -> CGImage? {
        BackdropSprite.make(32) { ctx, s in
            let r = CGRect(x: 2, y: 2, width: s - 4, height: s - 4)
            ctx.setFillColor(RGB(0.8, 0.95, 1).cg(0.12)); ctx.fillEllipse(in: r)
            ctx.setStrokeColor(RGB(0.85, 0.97, 1).cg(0.75)); ctx.setLineWidth(1.6); ctx.strokeEllipse(in: r.insetBy(dx: 1, dy: 1))
            ctx.setFillColor(RGB(1, 1, 1).cg(0.9)); ctx.fillEllipse(in: CGRect(x: s * 0.28, y: s * 0.58, width: s * 0.18, height: s * 0.18))
        }
    }
}

// MARK: - Nebula

/// Drifting forward forever through clouds of glowing gas and stars: each layer swells slowly toward you and fades as the
/// next comes up behind it, so the journey never ends and never jumps.
final class BackdropNebula: BackdropScene {
    typealias RGB = BackdropRGB
    private var gasTable: CIImage?
    private static let cycle = 26.0

    override func paint() -> CIImage? {
        // One table for the gas: clear, then deep blue, violet, magenta and a pink-white heart where it is densest.
        gasTable = BackdropInk.table([(at: 0, color: RGB(0, 0, 0), alpha: 0), (at: 0.42, color: RGB(hex: 0x0A1238), alpha: 0),
                                      (at: 0.58, color: RGB(hex: 0x203C9A), alpha: 0.32), (at: 0.72, color: RGB(hex: 0x5A2A8C), alpha: 0.42),
                                      (at: 0.86, color: RGB(hex: 0xB0307E), alpha: 0.55), (at: 1, color: RGB(hex: 0xF0A0C8), alpha: 0.7)])
        // Deep space and its stars are still: far stars do not seem to move, only the gas drifting past does.
        return BackdropPainter.paint(deep: false) { ctx in
            if let g = BackdropPaint.gradient([(at: 0, r: 0.04, g: 0.03, b: 0.09), (at: 1, r: 0.005, g: 0.005, b: 0.02)]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 360), startRadius: 0, endCenter: CGPoint(x: 640, y: 360), endRadius: 800, options: [.drawsAfterEndLocation])
            }
            var rng = SplitMix64(seed: 0x5EB)
            for i in 0..<320 {
                let p = CGPoint(x: .random(in: 0..<1280, using: &rng), y: .random(in: 0..<720, using: &rng))
                let r = CGFloat.random(in: 0.5...1.4, using: &rng)
                if i % 25 == 0 { BackdropPainter.glow(ctx, at: p, radius: 10, color: RGB(0.8, 0.88, 1), alpha: 0.4) }
                ctx.setFillColor(RGB(0.92, 0.94, 1).cg(Double.random(in: 0.3...1, using: &rng)))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        }.map { BackdropFinish.finish($0, grain: 0.4) }
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        guard let gasTable else { return still }
        let half = BackdropPainter.half
        let centre = CGPoint(x: 320, y: 190)
        var gas: CIImage?
        for k in 0..<2 {
            // Where this layer is in its swell: it grows from 1x to 2x over a cycle, fading in then out, half a cycle
            // apart from the other, so there is always one arriving as the other passes.
            let p = BackdropMotion.loop(time, period: Self.cycle, offset: Double(k) / 2)
            let zoom = pow(2, p)
            let fade = sin(p * .pi)
            let toward = CGAffineTransform(translationX: -centre.x, y: -centre.y).concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
                .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y))
            let layer = BackdropInk.colored(BackdropNoise.field(k, scale: 2.4, offset: CGPoint(x: Double(k) * 97, y: Double(k) * 53), extent: half), gasTable)
                .transformed(by: toward).cropped(to: half)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: fade, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: fade, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: fade, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: fade),
                ])
            gas = gas.map { layer.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: $0]) } ?? layer
        }
        guard let gas else { return still }
        let picture = BackdropPainter.enlarged(gas.cropped(to: half)).applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: still])
        return BackdropFinish.vignette(picture.cropped(to: BackdropPainter.frame), strength: 0.3)
    }
}

// MARK: - Cherry blossom

/// Under a cherry tree in full bloom: a soft canopy of pink against a pale spring sky, a dark branch across the top, and
/// petals drifting down on the breeze, the nearest ones big and out of focus.
final class BackdropCherryBlossom: BackdropScene {
    typealias RGB = BackdropRGB
    private let petals = BackdropFaller.make(count: 80, seed: 0xB10, kinds: 3, fall: 14...26, drift: 10...26, size: 9...15)
    private var sprites: [CGImage] = []
    private var soft: [CGImage] = []
    private var canvas: BackdropCanvas?

    override func paint() -> CIImage? {
        guard let canopy = BackdropPainter.paint(width: 640, height: 360, { ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: RGB(hex: 0xC9D6B4)), (at: 0.35, color: RGB(hex: 0xA7B8E0)), (at: 1, color: RGB(hex: 0x8D9FD6))])
            var rng = SplitMix64(seed: 0xB11)
            // Blossom clouds, densest along the top and the sides, leaving clear sky in the middle.
            let pinks = [RGB(hex: 0xF6B8CF), RGB(hex: 0xEE95B6), RGB(hex: 0xFBE1EA), RGB(hex: 0xE07FA5)]
            for _ in 0..<120 {
                let side = Bool.random(using: &rng)
                let x = CGFloat.random(in: 0...1280, using: &rng)
                let topBand = CGFloat.random(in: 560...760, using: &rng)
                let sideBand = CGFloat.random(in: 200...720, using: &rng)
                let p = side ? CGPoint(x: x < 640 ? x * 0.3 : 1280 - (1280 - x) * 0.3, y: sideBand) : CGPoint(x: x, y: topBand)
                BackdropPainter.glow(ctx, at: p, radius: CGFloat.random(in: 40...110, using: &rng), color: pinks[Int.random(in: 0..<pinks.count, using: &rng)], alpha: 0.75)
            }
            // A meadow, far off, at the bottom.
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: 150), [(at: 0, color: RGB(hex: 0x6E8F5A)), (at: 1, color: RGB(hex: 0xA9BE8C))])
        }) else { return nil }
        let blurred = BackdropPainter.defocus(canopy, sigma: 9)
        guard let branch = BackdropPainter.paint({ ctx in
            // The branch: dark bark, tapering, with twigs and little clusters of flowers in focus.
            let bark = RGB(hex: 0x2E1F22)
            var rng = SplitMix64(seed: 0xB12)
            func limb(_ p: CGPoint, _ angle: CGFloat, _ length: CGFloat, _ width: CGFloat, _ depth: Int) {
                let bend = CGFloat.random(in: -0.25...0.25, using: &rng)
                let end = CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length)
                let mid = CGPoint(x: (p.x + end.x) / 2 - sin(angle) * length * bend * 0.3, y: (p.y + end.y) / 2 + cos(angle) * length * bend * 0.3)
                ctx.move(to: p); ctx.addQuadCurve(to: end, control: mid)
                ctx.setStrokeColor(bark.cg); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.strokePath()
                if depth == 0 {
                    for _ in 0..<5 {
                        let q = CGPoint(x: end.x + CGFloat.random(in: -14...14, using: &rng), y: end.y + CGFloat.random(in: -12...12, using: &rng))
                        flower(ctx, at: q, size: CGFloat.random(in: 6...9, using: &rng), rng: &rng)
                    }
                    return
                }
                limb(end, angle + CGFloat.random(in: -0.5 ... -0.15, using: &rng), length * 0.72, width * 0.62, depth - 1)
                limb(end, angle + CGFloat.random(in: 0.15...0.55, using: &rng), length * 0.66, width * 0.58, depth - 1)
            }
            limb(CGPoint(x: -20, y: 690), -0.12, 260, 22, 4)
            limb(CGPoint(x: 1300, y: 650), .pi + 0.18, 190, 18, 3)
        }) else { return nil }
        return BackdropFinish.finish(BackdropFinish.vignette(branch.composited(over: blurred), strength: 0.14), grain: 0.6)
    }

    /// A five-petalled blossom, pale pink with a deeper centre.
    private func flower(_ ctx: CGContext, at c: CGPoint, size: CGFloat, rng: inout SplitMix64) {
        let turn = CGFloat.random(in: 0...(2 * .pi), using: &rng)
        for k in 0..<5 {
            let a = turn + CGFloat(k) / 5 * 2 * .pi
            let p = CGPoint(x: c.x + cos(a) * size * 0.55, y: c.y + sin(a) * size * 0.55)
            ctx.setFillColor(RGB(hex: 0xFAD3E1).cg)
            ctx.fillEllipse(in: CGRect(x: p.x - size * 0.45, y: p.y - size * 0.45, width: size * 0.9, height: size * 0.9))
        }
        ctx.setFillColor(RGB(hex: 0xD9608E).cg)
        ctx.fillEllipse(in: CGRect(x: c.x - size * 0.22, y: c.y - size * 0.22, width: size * 0.44, height: size * 0.44))
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        if sprites.isEmpty {
            let tints = [RGB(hex: 0xF9C6D8), RGB(hex: 0xF4A9C4), RGB(hex: 0xFDE4EE)]
            sprites = tints.compactMap { Self.petal($0, blur: 0) }
            soft = tints.compactMap { Self.petal($0, blur: 3) }
        }
        if canvas == nil { canvas = BackdropCanvas(width: 640, height: 360) }
        guard let canvas, sprites.count == 3, soft.count == 3 else { return still }
        canvas.clear()
        BackdropFaller.draw(petals, sprites: sprites, soft: soft, into: canvas.context, at: time)
        // Sun dappling through the moving canopy.
        let dappled = BackdropPainter.shimmer(still, at: time, amount: 0.07, scale: 2.6, speed: CGPoint(x: 14, y: -6))
        guard let falling = canvas.image(scale: 2) else { return dappled }
        return falling.composited(over: dappled)
    }

    /// A petal: rounded, with the little notch at its tip, pale at the edge and pinker at the base.
    private static func petal(_ tint: RGB, blur: Double) -> CGImage? {
        guard let crisp = BackdropSprite.make(48, { ctx, s in
            let path = CGMutablePath()
            path.move(to: CGPoint(x: s / 2, y: s * 0.08))
            path.addCurve(to: CGPoint(x: s * 0.44, y: s * 0.86), control1: CGPoint(x: s * 0.05, y: s * 0.3), control2: CGPoint(x: s * 0.12, y: s * 0.86))
            path.addLine(to: CGPoint(x: s / 2, y: s * 0.78))
            path.addLine(to: CGPoint(x: s * 0.56, y: s * 0.86))
            path.addCurve(to: CGPoint(x: s / 2, y: s * 0.08), control1: CGPoint(x: s * 0.88, y: s * 0.86), control2: CGPoint(x: s * 0.95, y: s * 0.3))
            BackdropPainter.fill(ctx, path, gradient: [(at: 0, color: tint.mixed(RGB(hex: 0xE07FA5), 0.5)), (at: 1, color: tint.mixed(RGB(1, 1, 1), 0.3))],
                                 from: CGPoint(x: 0, y: s * 0.08), to: CGPoint(x: 0, y: s * 0.86))
        }) else { return nil }
        return blur > 0 ? (BackdropBake.blurred(crisp, sigma: blur) ?? crisp) : crisp
    }
}

// MARK: - Digital rain

/// Streams of green glyphs running down a dark screen, each led by a bright white-green head and trailing off.
///
/// The glyphs are drawn once as a grid; each frame works out only how bright each cell is (a few thousand numbers), and
/// the GPU lights the grid with that, adding a soft glow.
final class BackdropDigitalRain: BackdropScene {
    typealias RGB = BackdropRGB
    private static let cols = 64, rows = 36
    private struct Stream { let phase: Double, speed: Double, length: Double }
    private let streams: [[Stream]]
    private var glyphs: CIImage?
    private var cells: [UInt8]

    override init() {
        var rng = SplitMix64(seed: 0xD161)
        streams = (0..<Self.cols).map { _ in
            (0..<2).map { _ in Stream(phase: .random(in: 0..<1, using: &rng), speed: .random(in: 4...11, using: &rng), length: .random(in: 8...22, using: &rng)) }
        }
        cells = [UInt8](repeating: 0, count: Self.cols * Self.rows * 4)
    }

    override func paint() -> CIImage? {
        glyphs = BackdropBake.flatten(Self.makeGlyphs())
        return BackdropPainter.paint(width: 64, height: 36) { ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: RGB(hex: 0x010604)), (at: 1, color: RGB(hex: 0x03100A))])
        }
    }

    /// The glyph grid: half-width kana, digits and a few letters in a monospaced face, white on black, some mirrored.
    private static func makeGlyphs() -> CIImage? {
        BackdropPainter.paint(deep: false) { ctx in
            ctx.setFillColor(RGB(0, 0, 0).cg); ctx.fill(BackdropPainter.frame)
            let set = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜ0123456789Z:.=*+<>")
            let font = CTFontCreateWithName("Menlo-Regular" as CFString, 17, nil)
            var rng = SplitMix64(seed: 0x61F)
            let cw = 1280.0 / Double(cols), ch = 720.0 / Double(rows)
            for c in 0..<cols {
                for r in 0..<rows {
                    let glyph = String(set[Int.random(in: 0..<set.count, using: &rng)])
                    let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                                     NSAttributedString.Key(kCTForegroundColorAttributeName as String): RGB(1, 1, 1).cg]
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: attributes))
                    ctx.saveGState()
                    let x = Double(c) * cw + cw / 2, y = Double(rows - 1 - r) * ch + ch * 0.25
                    ctx.translateBy(x: x, y: y)
                    if Bool.random(using: &rng) { ctx.scaleBy(x: -1, y: 1) }
                    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                    ctx.textPosition = CGPoint(x: -width / 2, y: 0)
                    CTLineDraw(line, ctx)
                    ctx.restoreGState()
                }
            }
        }
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        guard let glyphs else { return still }
        let cols = Self.cols, rows = Self.rows
        // Brightness of every cell: each stream's head runs down its column; cells behind it fade with distance.
        cells.withUnsafeMutableBufferPointer { out in
            out.update(repeating: 0)
            var i = 3
            while i < out.count { out[i] = 255; i += 4 }
            for c in 0..<cols {
                for s in streams[c] {
                    let travel = Double(rows) + s.length
                    let head = BackdropMath.fract(s.phase + s.speed * time / travel) * travel
                    // Only the rows the trail covers (rows counted from the top).
                    let first = max(0, Int((head - s.length).rounded(.up))), last = min(rows - 1, Int(head))
                    guard first <= last else { continue }
                    for r in first...last {
                        let behind = head - Double(r)
                        guard behind >= 0, behind < s.length else { continue }
                        let fade = 1 - behind / s.length
                        let level = fade * fade
                        let at = (r * cols + c) * 4
                        let isHead = behind < 1
                        let red = isHead ? 0.75 : 0.10 * level, green = isHead ? 1.0 : level, blue = isHead ? 0.82 : 0.32 * level
                        out[at] = max(out[at], UInt8(min(255, red * 255)))
                        out[at + 1] = max(out[at + 1], UInt8(min(255, green * 255)))
                        out[at + 2] = max(out[at + 2], UInt8(min(255, blue * 255)))
                    }
                }
            }
        }
        let frame = BackdropPainter.frame
        let map = CIImage(bitmapData: Data(cells), bytesPerRow: cols * 4, size: CGSize(width: cols, height: rows), format: .RGBA8, colorSpace: BackdropCanvas.space)
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: 1280 / CGFloat(cols), y: 720 / CGFloat(rows)))
            .cropped(to: frame)
        let lit = glyphs.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: map]).cropped(to: frame)
        let glow = lit.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25)).clampedToExtent().applyingGaussianBlur(sigma: 3)
            .transformed(by: CGAffineTransform(scaleX: 4, y: 4)).cropped(to: frame)
        let screen = lit.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: glow.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: still])])
        return BackdropFinish.finish(BackdropFinish.vignette(screen.cropped(to: frame), strength: 0.35))
    }
}

// MARK: - Autumn leaves

/// A park in autumn, softly out of focus in golden light, with leaves of red, orange and gold tumbling down.
final class BackdropAutumnLeaves: BackdropScene {
    typealias RGB = BackdropRGB
    private let leaves = BackdropFaller.make(count: 36, seed: 0xA07, kinds: 4, fall: 18...34, drift: 6...20, size: 20...32)
    private var sprites: [CGImage] = []
    private var soft: [CGImage] = []
    private var canvas: BackdropCanvas?

    override func paint() -> CIImage? {
        BackdropPainter.paint(width: 640, height: 360) { ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: RGB(hex: 0x6E4A2A)), (at: 0.3, color: RGB(hex: 0xA6743F)), (at: 0.65, color: RGB(hex: 0xC99A62)), (at: 1, color: RGB(hex: 0xD8B57E))])
            BackdropPainter.glow(ctx, at: CGPoint(x: 150, y: 690), radius: 620, color: RGB(hex: 0xFFE2A6), alpha: 0.45, blend: .screen)
            var rng = SplitMix64(seed: 0xA08)
            // Trunks, then masses of foliage in the warm colours of the season, dense at the sides and the top.
            for _ in 0..<9 {
                var x = CGFloat.random(in: 0...1280, using: &rng)
                if x > 460 && x < 820 { x += x < 640 ? -260 : 260 }
                let w = CGFloat.random(in: 18...46, using: &rng)
                ctx.setFillColor(RGB(hex: 0x3A2618).cg(0.85)); ctx.fill(CGRect(x: x - w / 2, y: 80, width: w, height: 600))
            }
            let foliage = [RGB(hex: 0xD9732B), RGB(hex: 0xB8421F), RGB(hex: 0xE8B23A), RGB(hex: 0x9C5A24), RGB(hex: 0xC98A2E)]
            for _ in 0..<110 {
                let edge = Bool.random(using: &rng)
                let x = edge ? (Bool.random(using: &rng) ? CGFloat.random(in: -60...360, using: &rng) : CGFloat.random(in: 920...1340, using: &rng)) : CGFloat.random(in: 0...1280, using: &rng)
                let y = edge ? CGFloat.random(in: 260...760, using: &rng) : CGFloat.random(in: 600...780, using: &rng)
                BackdropPainter.glow(ctx, at: CGPoint(x: x, y: y), radius: CGFloat.random(in: 50...120, using: &rng), color: foliage[Int.random(in: 0..<foliage.count, using: &rng)], alpha: 0.8)
            }
            // A path and fallen leaves on the grass.
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: 130), [(at: 0, color: RGB(hex: 0x8A5A2A)), (at: 1, color: RGB(hex: 0xB78A4E))])
        }.map { BackdropFinish.finish(BackdropFinish.vignette(BackdropPainter.defocus($0, sigma: 7), strength: 0.2), grain: 0.8) }
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        if sprites.isEmpty {
            let tints = [RGB(hex: 0xD9562A), RGB(hex: 0xE89A2E), RGB(hex: 0xC23A22), RGB(hex: 0xE8C04A)]
            sprites = tints.compactMap { Self.leaf($0, blur: 0) }
            soft = tints.compactMap { Self.leaf($0, blur: 3) }
        }
        if canvas == nil { canvas = BackdropCanvas(width: 640, height: 360) }
        guard let canvas, sprites.count == 4, soft.count == 4 else { return still }
        canvas.clear()
        BackdropFaller.draw(leaves, sprites: sprites, soft: soft, into: canvas.context, at: time)
        let dappled = BackdropPainter.shimmer(still, at: time, amount: 0.07, scale: 2.8, speed: CGPoint(x: -12, y: -5))
        guard let falling = canvas.image(scale: 2) else { return dappled }
        return falling.composited(over: dappled)
    }

    /// A maple leaf: five pointed lobes, a stem and veins, lit from the upper left.
    private static func leaf(_ tint: RGB, blur: Double) -> CGImage? {
        guard let crisp = BackdropSprite.make(64, { ctx, s in
            let c = CGPoint(x: s / 2, y: s * 0.42)
            let path = CGMutablePath()
            let lobes: [(angle: CGFloat, length: CGFloat)] = [(-1.25, 0.32), (-0.62, 0.4), (0, 0.5), (0.62, 0.4), (1.25, 0.32)]
            path.move(to: CGPoint(x: c.x, y: c.y - s * 0.06))
            for (i, lobe) in lobes.enumerated() {
                let a = lobe.angle + .pi / 2
                let tip = CGPoint(x: c.x - cos(a) * s * lobe.length, y: c.y + sin(a) * s * lobe.length)
                let before = CGPoint(x: c.x - cos(a - 0.28) * s * lobe.length * 0.55, y: c.y + sin(a - 0.28) * s * lobe.length * 0.55)
                let after = CGPoint(x: c.x - cos(a + 0.28) * s * lobe.length * 0.55, y: c.y + sin(a + 0.28) * s * lobe.length * 0.55)
                path.addLine(to: i == 0 ? before : before)
                path.addLine(to: tip)
                path.addLine(to: after)
            }
            path.closeSubpath()
            BackdropPainter.fill(ctx, path, gradient: [(at: 0, color: tint.mixed(RGB(1, 0.95, 0.7), 0.25)), (at: 1, color: tint.scaled(0.7))],
                                 from: CGPoint(x: 0, y: s), to: CGPoint(x: s, y: 0))
            ctx.setStrokeColor(tint.scaled(0.55).cg(0.7)); ctx.setLineWidth(1.2)
            for lobe in lobes {
                let a = lobe.angle + .pi / 2
                ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x - cos(a) * s * lobe.length * 0.8, y: c.y + sin(a) * s * lobe.length * 0.8))
            }
            ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x, y: s * 0.06))
            ctx.strokePath()
        }) else { return nil }
        return blur > 0 ? (BackdropBake.blurred(crisp, sigma: blur) ?? crisp) : crisp
    }
}

// MARK: - Holiday lights

/// A cosy room on a winter evening: strings of coloured bulbs looped across the wall, each glowing and gently breathing,
/// a decorated tree softly out of focus in the corner.
final class BackdropHolidayLights: BackdropScene {
    typealias RGB = BackdropRGB
    private struct Bulb { let at: CGPoint, colour: RGB, rate: Double, phase: Double }
    private var bulbs: [Bulb] = []
    private var canvas: BackdropCanvas?
    private var halo: [RGB: CGImage] = [:]
    /// Warm white, red, green, gold and blue, as old-fashioned bulbs are.
    private static let colours = [RGB(hex: 0xFFE2A8), RGB(hex: 0xFF4B4B), RGB(hex: 0x4BD47A), RGB(hex: 0xFFC23A), RGB(hex: 0x4FA3FF)]

    override func paint() -> CIImage? {
        var made: [Bulb] = []
        guard let room = BackdropPainter.paint(width: 640, height: 360, { ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: RGB(hex: 0x1A1210)), (at: 0.5, color: RGB(hex: 0x16222A)), (at: 1, color: RGB(hex: 0x0C141A))])
            BackdropPainter.glow(ctx, at: CGPoint(x: 640, y: 420), radius: 520, color: RGB(hex: 0x3A3020), alpha: 0.6)
            // The tree in the corner, with its own lights, out of focus.
            let tree = CGMutablePath()
            tree.move(to: CGPoint(x: 1060, y: 40)); tree.addLine(to: CGPoint(x: 1180, y: 520)); tree.addLine(to: CGPoint(x: 1300, y: 40)); tree.closeSubpath()
            ctx.addPath(tree); ctx.setFillColor(RGB(hex: 0x0E2A1C).cg); ctx.fillPath()
            var rng = SplitMix64(seed: 0x401)
            for _ in 0..<40 {
                let y = CGFloat.random(in: 60...480, using: &rng)
                let half = (520 - y) / 480 * 120
                let x = 1180 + CGFloat.random(in: -half...half, using: &rng)
                BackdropPainter.glow(ctx, at: CGPoint(x: x, y: y), radius: 26, color: Self.colours[Int.random(in: 0..<Self.colours.count, using: &rng)], alpha: 0.7, blend: .screen)
            }
        }) else { return nil }
        let blurred = BackdropPainter.defocus(room, sigma: 8)
        guard let strings = BackdropPainter.paint({ ctx in
            // Two strings looped across the top of the wall, each sagging between hooks.
            var rng = SplitMix64(seed: 0x402)
            for (k, y0) in [CGFloat(660), 560].enumerated() {
                let hooks: [CGFloat] = k == 0 ? [-40, 330, 700, 1060, 1320] : [-40, 200, 520, 860, 1320]
                for i in 0..<(hooks.count - 1) {
                    let a = CGPoint(x: hooks[i], y: y0), b = CGPoint(x: hooks[i + 1], y: y0)
                    let sag: CGFloat = 70
                    let wire = CGMutablePath()
                    wire.move(to: a); wire.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2, y: y0 - sag * 2))
                    ctx.addPath(wire); ctx.setStrokeColor(RGB(hex: 0x0A0E0C).cg); ctx.setLineWidth(2.2); ctx.strokePath()
                    let n = 9
                    for j in 1..<n {
                        let t = CGFloat(j) / CGFloat(n)
                        let p = CGPoint(x: (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * (a.x + b.x) / 2 + t * t * b.x,
                                        y: (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * (y0 - sag * 2) + t * t * b.y)
                        let colour = Self.colours[Int.random(in: 0..<Self.colours.count, using: &rng)]
                        // Socket and glass bulb hanging down.
                        ctx.setFillColor(RGB(hex: 0x1C1F1C).cg); ctx.fill(CGRect(x: p.x - 3, y: p.y - 8, width: 6, height: 8))
                        BackdropPainter.fill(ctx, CGPath(ellipseIn: CGRect(x: p.x - 5, y: p.y - 22, width: 10, height: 15), transform: nil),
                                             gradient: [(at: 0, color: colour.scaled(0.7)), (at: 0.6, color: colour), (at: 1, color: colour.mixed(RGB(1, 1, 1), 0.6))],
                                             from: CGPoint(x: p.x + 5, y: p.y - 22), to: CGPoint(x: p.x - 4, y: p.y - 9))
                        made.append(Bulb(at: CGPoint(x: p.x, y: p.y - 15), colour: colour, rate: .random(in: 0.4...1.1, using: &rng), phase: .random(in: 0..<(2 * .pi), using: &rng)))
                    }
                }
            }
        }) else { return nil }
        bulbs = made
        return BackdropFinish.finish(BackdropFinish.vignette(strings.composited(over: blurred), strength: 0.3), grain: 0.8)
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        if halo.isEmpty { for c in Self.colours { halo[c] = BackdropSprite.glow(c, side: 64, core: 0.9, hot: 0.6) } }
        if canvas == nil { canvas = BackdropCanvas(width: 640, height: 360) }
        guard let canvas else { return still }
        canvas.clear()
        let ctx = canvas.context
        ctx.setBlendMode(.plusLighter)
        for b in bulbs {
            // A slow breath, never off: bulbs glow between two thirds and full.
            let level = 0.68 + 0.32 * (0.5 + 0.5 * BackdropMotion.wave(time, rate: b.rate, phase: b.phase))
            guard let sprite = halo[b.colour] else { continue }
            ctx.setAlpha(CGFloat(level * 0.85))
            let r: CGFloat = 22
            ctx.draw(sprite, in: CGRect(x: b.at.x / 2 - r, y: b.at.y / 2 - r, width: r * 2, height: r * 2))
        }
        ctx.setAlpha(1)
        ctx.setBlendMode(.normal)
        guard let glow = canvas.image(scale: 2) else { return still }
        return glow.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: still]).cropped(to: BackdropPainter.frame)
    }
}
