import CoreImage
import CoreImage.CIFilterBuiltins

/// A rippling glow around your outline, and sparks rising off it: powering up.
final class AuraLens: Lens {
    enum Style { case power, rainbow }

    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private let style: Style
    private var sparks = ParticleSystem(capacity: 360)
    private var rng = SplitMix64(seed: 0xA11A)

    init(style: Style) {
        self.style = style
        sparks.gravity = SIMD2(0, 70)   // heat rises
    }

    func restart() { sparks.removeAll() }

    var sparkCount: Int { sparks.particles.count }

    func render(_ input: LensInput) -> CIImage {
        guard let matte = input.matte else { return input.composed }
        let rect = input.rect, t = input.time

        // The glow is soft, so work at half size: a quarter of the pixels to blur.
        let small = CGRect(x: 0, y: 0, width: rect.width / 2, height: rect.height / 2)
        let half = matte.transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY).concatenating(CGAffineTransform(scaleX: 0.5, y: 0.5)))
        func halo(radius: Double, sigma: Double) -> CIImage {
            half.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
                .clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: small)
        }
        // Noise that scrolls upward ripples the tight halo so it licks like flame.
        let noise = CIFilter.randomGenerator().outputImage!
            .transformed(by: CGAffineTransform(translationX: CGFloat(t * 18), y: CGFloat(-t * 130)))
            .cropped(to: small).clampedToExtent().applyingGaussianBlur(sigma: 4).cropped(to: small)
        let flicker = 0.9 + 0.1 * sin(t * 19)
        let core = halo(radius: 10, sigma: 9)
            .applyingFilter("CIDisplacementDistortion", parameters: ["inputDisplacementImage": noise, kCIInputScaleKey: 30.0])
            .gain(2.6 * flicker)
        let outer = halo(radius: 6, sigma: 34).gain(1.7)
        let enlarge = CGAffineTransform(scaleX: 2, y: 2).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))

        // Hot white-yellow close in, deep orange further out (or shifting colours, for rainbow).
        func tint(_ strength: CIImage, hot: CIColor, cool: CIColor) -> CIImage {
            var ramp = strength.applyingFilter("CIFalseColor", parameters: ["inputColor0": cool, "inputColor1": hot])
            if style == .rainbow { ramp = ramp.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: t * 1.3]) }
            let blend = CIFilter.blendWithMask()
            blend.inputImage = ramp
            blend.backgroundImage = CIImage(color: .clear).cropped(to: small)
            blend.maskImage = strength
            return (blend.outputImage ?? ramp).transformed(by: enlarge).cropped(to: rect)
        }
        let hotCore: CIColor, coolCore: CIColor, hotOuter: CIColor, coolOuter: CIColor
        switch style {
        case .power:
            (hotCore, coolCore) = (CIColor(red: 1.0, green: 0.95, blue: 0.55), CIColor(red: 0.95, green: 0.45, blue: 0.02))
            (hotOuter, coolOuter) = (CIColor(red: 1.0, green: 0.55, blue: 0.05), CIColor(red: 0.6, green: 0.05, blue: 0.0))
        case .rainbow:
            (hotCore, coolCore) = (CIColor(red: 0.5, green: 1.0, blue: 0.95), CIColor(red: 0.7, green: 0.2, blue: 1.0))
            (hotOuter, coolOuter) = (CIColor(red: 0.4, green: 0.6, blue: 1.0), CIColor(red: 0.5, green: 0.0, blue: 0.8))
        }
        let outerLayer = tint(outer, hot: hotOuter, cool: coolOuter).fading(0.75)
        let coreLayer = tint(core, hot: hotCore, cool: coolCore)
        let glow = coreLayer.composited(over: outerLayer.composited(over: input.scenery))
        let body = input.placingPerson(over: glow)

        guard let grid = input.matteGrid else { return body }
        emitSparks(from: grid, dt: input.dt)
        sparks.step(input.dt)
        guard let layer = input.services.overlay({ ctx in self.draw(sparks: ctx) }) else { return body }
        return layer.composited(over: body)
    }

    private func emitSparks(from grid: MatteGrid, dt: Double) {
        let edges = grid.edges()
        guard !edges.isEmpty else { return }
        let count = Int(dt * 260 + Double.random(in: 0..<1, using: &rng))
        for _ in 0..<count {
            let at = edges[Int.random(in: 0..<edges.count, using: &rng)]
            sparks.emit(Particle(position: SIMD2(at.x, at.y),
                                 velocity: SIMD2(Double.random(in: -40...40, using: &rng), Double.random(in: 90...230, using: &rng)),
                                 life: Double.random(in: 0.7...1.6, using: &rng),
                                 size: Double.random(in: 3...8, using: &rng),
                                 hue: Double.random(in: 0..<1, using: &rng)))
        }
    }

    private func draw(sparks ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        for p in sparks.particles {
            let fade = 1 - p.progress * p.progress
            let (r, g, b): (Double, Double, Double)
            switch style {
            case .power: (r, g, b) = (1, 0.65 + 0.3 * (1 - p.progress), 0.25 * (1 - p.progress))
            case .rainbow: (r, g, b) = Palette.rgb(hue: p.hue + p.progress * 0.2)
            }
            guard let dot = Sprites.dot(red: (r * 20).rounded() / 20, green: (g * 20).rounded() / 20, blue: (b * 20).rounded() / 20) else { continue }
            ctx.stampDot(dot, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1.4 - 0.6 * p.progress), alpha: fade)
        }
    }
}
