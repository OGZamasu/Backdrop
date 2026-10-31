import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Out-of-focus lights floating up through a warm dark room: the soft glowing discs a fast lens makes of distant lamps.
///
/// Three depths: far lights are small, crisp and many; middle ones larger; a few near ones huge, faint and very soft.
/// Each disc is a ready-made sprite with a brighter rim, faint rings and a thin cool fringe, as real glass draws them.
/// They are stamped on a half-size surface (they are soft, so nobody can tell) and added as light, so overlaps glow.
/// A disc's place is worked out from the clock alone.
final class BokehSource: BackgroundSource {
    private struct Disc {
        let x: Double, y: Double              // where it is at time zero, as a share of the width and travel
        let radius: Double                    // on the half-size surface
        let rise: Double                      // pixels a second
        let sway: Double, swayRate: Double, swayPhase: Double
        let strength: Double, pulseRate: Double, pulsePhase: Double
        let sprite: Int
        let near: Bool
    }

    private static let size = CGSize(width: 1280, height: 720)
    private static let half = CGSize(width: 640, height: 360)
    /// Gold, amber, peach, rose, cream and one cool teal for contrast.
    private static let tints: [BackdropRGB] = [
        BackdropRGB(hex: 0xFFC65C), BackdropRGB(hex: 0xFF9A3D), BackdropRGB(hex: 0xFFB890), BackdropRGB(hex: 0xFF7F8F), BackdropRGB(hex: 0xFFEBC2),
        BackdropRGB(hex: 0x6ADBD0),
    ]

    private let discs: [Disc]
    private var sprites: [CGImage] = []
    private var softSprites: [CGImage] = []
    private var canvas: BackdropCanvas?
    private var room: CIImage?

    init(seed: UInt64 = 0xB0CE) {
        var rng = SplitMix64(seed: seed)
        var made: [Disc] = []
        // (count, radius range, rise range, strength, near)
        for (count, radii, rises, strength, near) in [(26, 5.0...13.0, 2.0...5.0, 0.55, false), (16, 15.0...30.0, 4.0...8.0, 0.36, false), (6, 46.0...74.0, 8.0...12.0, 0.16, true)] {
            for _ in 0..<count {
                made.append(Disc(x: .random(in: 0..<1, using: &rng), y: .random(in: 0..<1, using: &rng), radius: .random(in: radii, using: &rng),
                                 rise: .random(in: rises, using: &rng),
                                 sway: .random(in: 6...24, using: &rng), swayRate: .random(in: 0.05...0.16, using: &rng), swayPhase: .random(in: 0..<(2 * .pi), using: &rng),
                                 strength: strength * .random(in: 0.65...1.0, using: &rng), pulseRate: .random(in: 0.08...0.3, using: &rng),
                                 pulsePhase: .random(in: 0..<(2 * .pi), using: &rng), sprite: Int.random(in: 0..<Self.tints.count, using: &rng), near: near))
            }
        }
        // Far ones first, so the near ones lie over them.
        discs = made
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        if canvas == nil { canvas = BackdropCanvas(width: Int(Self.half.width), height: Int(Self.half.height)) }
        if room == nil { room = BackdropBake.flatten(Self.makeRoom()) }
        if sprites.isEmpty { sprites = Self.tints.compactMap { BackdropSprite.bokeh($0, side: 96, softness: 1.4) } }
        if softSprites.isEmpty { softSprites = Self.tints.compactMap { BackdropSprite.bokeh($0, side: 96, softness: 5) } }
        guard let canvas, let room, sprites.count == Self.tints.count, softSprites.count == Self.tints.count else { return nil }

        canvas.clear()
        let ctx = canvas.context
        ctx.interpolationQuality = .low        // the discs are soft anyway; the best resampling costs several times as much
        ctx.setBlendMode(.plusLighter)
        for disc in discs {
            let span = Self.half.height + disc.radius * 2
            let travel = BackdropMath.fract(disc.y + disc.rise * time / span)
            let y = -disc.radius + travel * span
            let x = disc.x * Self.half.width + disc.sway * BackdropMotion.wave(time, rate: disc.swayRate, phase: disc.swayPhase)
            let pulse = 0.8 + 0.2 * BackdropMotion.wave(time, rate: disc.pulseRate, phase: disc.pulsePhase)
            // Fade in from the bottom and out at the top, so nothing pops at the edges.
            let edge = BackdropMath.smoothstep(0, 0.12, travel) * (1 - BackdropMath.smoothstep(0.88, 1, travel))
            ctx.setAlpha(CGFloat(disc.strength * pulse * (0.35 + 0.65 * edge)))
            let sprite = disc.near ? softSprites[disc.sprite] : sprites[disc.sprite]
            ctx.draw(sprite, in: CGRect(x: x - disc.radius, y: y - disc.radius, width: disc.radius * 2, height: disc.radius * 2))
        }
        ctx.setAlpha(1)
        ctx.setBlendMode(.normal)

        guard let lights = canvas.image(scale: Self.size.width / Self.half.width) else { return room }
        let add = CIFilter.additionCompositing()
        add.inputImage = lights
        add.backgroundImage = room
        return add.outputImage?.cropped(to: CGRect(origin: .zero, size: Self.size)) ?? room
    }

    // MARK: Still pieces

    /// A dark, warm room far out of focus: wine and brown, a faint window shape, a glow low in the middle.
    private static func makeRoom() -> CIImage? {
        guard let painted = BackdropPainter.paint(width: 320, height: 180, { ctx in
            if let ramp = BackdropPaint.gradient([(at: 0, r: 0.17, g: 0.07, b: 0.06), (at: 0.5, r: 0.10, g: 0.045, b: 0.07), (at: 1, r: 0.06, g: 0.03, b: 0.10)]) {
                ctx.drawLinearGradient(ramp, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1280, y: 720), options: [])
            }
            // A tall window, barely there, and a lamp's warmth.
            BackdropPainter.glow(ctx, at: CGPoint(x: 1010, y: 420), radius: 300, color: BackdropRGB(0.24, 0.16, 0.24), alpha: 0.4, squash: 1.4)
            BackdropPainter.glow(ctx, at: CGPoint(x: 300, y: 260), radius: 520, color: BackdropRGB(0.6, 0.3, 0.12), alpha: 0.28)
            BackdropPainter.glow(ctx, at: CGPoint(x: 640, y: 300), radius: 600, color: BackdropRGB(0.45, 0.2, 0.12), alpha: 0.22)
        }) else { return nil }
        return BackdropFinish.finish(BackdropFinish.vignette(BackdropPainter.defocus(painted, sigma: 18), strength: 0.3), grain: 0.8)
    }
}
