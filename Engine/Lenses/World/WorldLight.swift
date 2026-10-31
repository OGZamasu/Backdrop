import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Light that falls on the person, shared by the world filters: a rim along the edge that faces a light, a glow around the outline,
/// colour ramps and soft noise. Everything wide and soft is worked out at half or quarter size on the graphics chip.
extension WorldKit {
    /// Where the key light comes from in every world filter: the top left, as a unit vector pointing at it.
    static let keyLight = simd_normalize(SIMD2<Double>(-0.62, 0.78))

    /// Moves a picture to the origin and shrinks it by `scale`.
    static func shrink(_ image: CIImage, rect: CGRect, by scale: Double) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
            .concatenating(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))))
    }

    /// Undoes `shrink`: back to full size over `rect`.
    static func enlarge(_ image: CIImage, rect: CGRect, from scale: Double) -> CIImage {
        image.transformed(by: CGAffineTransform(scaleX: CGFloat(1 / scale), y: CGFloat(1 / scale))
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))).cropped(to: rect)
    }

    /// Keeps a colour-matrix result to its input's area: a bias would otherwise light up the whole endless plane around it,
    /// which a later turn or stretch cannot handle.
    private static func within(_ out: CIImage, of input: CIImage) -> CIImage {
        input.extent.isInfinite ? out : out.cropped(to: input.extent)
    }

    /// A grey picture turned into opaque light of one colour (black where the grey is black), ready to add.
    static func tint(_ grey: CIImage, _ c: SIMD3<Double>, strength: Double) -> CIImage {
        within(grey.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(c.x * strength), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: CGFloat(c.y * strength), y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: CGFloat(c.z * strength), y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]), of: grey)
    }

    /// A coloured picture made brighter or dimmer by `k`, opaque, for adding.
    static func brightened(_ image: CIImage, _ k: Double) -> CIImage {
        within(image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(k), y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: CGFloat(k), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(k), w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]), of: image)
    }

    /// One minus a grey picture.
    static func inverted(_ grey: CIImage) -> CIImage {
        within(grey.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: -1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: -1, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 1),
        ]), of: grey)
    }

    static func multiply(_ a: CIImage, _ b: CIImage) -> CIImage {
        a.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: b])
    }

    /// Light catching the edge of the person that faces `toward` (a unit vector pointing at the light), `width` pixels deep. It is
    /// kept on the person, so add it straight onto the finished picture. Nil when there is no one or no light.
    static func rimLight(matte: CIImage?, rect: CGRect, toward: SIMD2<Double>, width: Double, colour: SIMD3<Double>, strength: Double) -> CIImage? {
        guard let matte, strength > 0.003 else { return nil }
        let scale = 0.5
        let box = CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale)
        let small = shrink(matte, rect: rect, by: scale).clampedToExtent()
        let d = toward * width * scale
        // Where stepping toward the light leaves the silhouette, the edge faces it.
        let open = inverted(small.transformed(by: CGAffineTransform(translationX: CGFloat(-d.x), y: CGFloat(-d.y))))
        let edge = multiply(open, small).applyingGaussianBlur(sigma: max(1, width * scale * 0.35)).cropped(to: box)
        let light = enlarge(tint(edge, colour, strength: strength), rect: rect, from: scale)
        return multiply(light, matte).cropped(to: rect)
    }

    /// A soft glow just inside the whole outline, all the way round: light wrapping the edge. Kept on the person.
    static func edgeGlow(matte: CIImage?, rect: CGRect, width: Double, colour: SIMD3<Double>, strength: Double) -> CIImage? {
        guard let matte, strength > 0.003 else { return nil }
        let scale = 0.25
        let box = CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale)
        let small = shrink(matte, rect: rect, by: scale).clampedToExtent()
        let soft = small.applyingGaussianBlur(sigma: max(0.8, width * scale * 0.5)).cropped(to: box)
        let band = enlarge(tint(inverted(soft), colour, strength: strength), rect: rect, from: scale)
        return multiply(band, matte).cropped(to: rect)
    }

    /// The silhouette spread out into a soft glow, at quarter size with its origin at zero: 0 far away, near 1 at the edge.
    /// `grow` fattens the outline first, in full-size pixels.
    static func halo(matte: CIImage, rect: CGRect, sigma: Double, grow: Double = 0, scale: Double = 0.25) -> CIImage {
        let box = CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale)
        var small = shrink(matte, rect: rect, by: scale)
        if grow * scale >= 1 { small = small.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: grow * scale]) }
        return small.clampedToExtent().applyingGaussianBlur(sigma: max(0.6, sigma * scale)).cropped(to: box)
    }

    // MARK: Ramps and noise

    /// A strip of colour, left to right, for looking a brightness up in with `CIColorMap`. Stops are positions and sRGB colours.
    static func ramp(_ stops: [(Double, SIMD3<Double>)], width: Int = 256) -> CIImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let colours = stops.compactMap { CGColor(colorSpace: space, components: [CGFloat($0.1.x), CGFloat($0.1.y), CGFloat($0.1.z), 1]) } as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colours, locations: stops.map { CGFloat($0.0) }) else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        return context.makeImage().map { CIImage(cgImage: $0) }
    }

    private static let whiteNoise: CIImage = CIFilter.randomGenerator().outputImage ?? CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))

    /// Smooth grey noise over `box` (in whatever coordinates the caller works in): blobs about `grain` pixels across, slid by `offset`
    /// so it can drift. Values sit around 0.5.
    static func clouds(_ box: CGRect, grain: Double, offset: CGPoint, stretch: CGSize = CGSize(width: 1, height: 1)) -> CIImage {
        let pick = CIVector(x: 0, y: 1, z: 0, w: 0)
        let cell = max(1, grain / 3)
        let area = box.insetBy(dx: -CGFloat(cell * 5), dy: -CGFloat(cell * 5))
        // The generator's opacity is random too and its colours are not premultiplied by it: make it opaque first, without dividing.
        return whiteNoise
            .transformed(by: CGAffineTransform(translationX: offset.x / CGFloat(cell), y: offset.y / CGFloat(cell)))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(cell) * stretch.width, y: CGFloat(cell) * stretch.height))
            .cropped(to: area).settingAlphaOne(in: area)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": pick, "inputGVector": pick, "inputBVector": pick,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .clampedToExtent()
            .applyingGaussianBlur(sigma: cell * 1.2)
            .cropped(to: box)
    }

    /// A linear stretch of a grey picture: `low` becomes 0 and `high` becomes 1, clamped. Turns soft noise into wisps.
    static func levels(_ grey: CIImage, low: Double, high: Double) -> CIImage {
        let k = 1 / max(1e-3, high - low)
        return grey.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(k), y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: CGFloat(k), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(k), w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: CGFloat(-low * k), y: CGFloat(-low * k), z: CGFloat(-low * k), w: 0),
        ]).applyingFilter("CIColorClamp")
    }
}

/// Where the person is, smoothed so a flickering cutout does not make anything jump: the middle of the body, the top of the head,
/// and how sure we are that someone is there (eases in and out instead of switching).
struct WorldPresence {
    private(set) var centre = SIMD2<Double>(640, 330)
    /// The highest point of the silhouette, in output pixels.
    private(set) var top = 560.0
    /// How wide the silhouette is, in output pixels.
    private(set) var width = 400.0
    /// 0 nobody is there ... 1 someone clearly is.
    private(set) var level = 0.0
    private var seen = false

    /// Reads the grid (every other cell is plenty) and eases toward what it finds. A frame with nobody only fades the presence out.
    mutating func update(grid: MatteGrid?, dt: Double) {
        let dt = WorldKit.clamped(dt)
        guard let grid else {
            level = max(0, level - dt * 1.5)
            return
        }
        var count = 0.0, sx = 0.0, sy = 0.0, highest = -1.0, left = Double.greatestFiniteMagnitude, right = -1.0
        let w = grid.width, h = grid.height
        grid.cells.withUnsafeBufferPointer { cells in
            for gy in stride(from: 0, to: h, by: 2) {
                let row = gy * w
                let y = (Double(h - 1 - gy) + 0.5) * grid.cellSize
                for gx in stride(from: 0, to: w, by: 2) where cells[row + gx] > 127 {
                    let x = (Double(gx) + 0.5) * grid.cellSize
                    count += 1
                    sx += x
                    sy += y
                    highest = max(highest, y)
                    left = min(left, x)
                    right = max(right, x)
                }
            }
        }
        let sampled = Double((w + 1) / 2 * ((h + 1) / 2))
        guard count / sampled > 0.01 else {
            level = max(0, level - dt * 1.5)
            return
        }
        let found = SIMD2(sx / count, sy / count)
        let k = seen ? 1 - exp(-dt * 6) : 1
        centre += (found - centre) * k
        top += (highest - top) * k
        width += (max(40, right - left) - width) * k
        seen = true
        level = min(1, level + dt * 2.5)
    }

    mutating func reset() {
        level = 0
        seen = false
    }
}

/// A small canvas for big soft light: pools of glow, smoke and haze drawn at a quarter of the size and scaled up on the graphics
/// chip. A wide glow costs sixteen times less to paint here than on the full-size overlay, and nobody can tell the difference.
final class WorldSoftCanvas {
    static let scale = 0.25
    private var context: CGContext?
    private var box = CGRect.zero

    /// Draws into a cleared canvas in full-size coordinates (they are scaled down for you) and returns the picture at full size,
    /// transparent where nothing was drawn.
    func draw(rect: CGRect, _ body: (CGContext) -> Void) -> CIImage? {
        let small = CGRect(x: 0, y: 0, width: (rect.width * Self.scale).rounded(), height: (rect.height * Self.scale).rounded())
        if context == nil || small != box {
            box = small
            context = CGContext(data: nil, width: Int(small.width), height: Int(small.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)
        }
        guard let ctx = context else { return nil }
        ctx.clear(small)
        ctx.saveGState()
        ctx.interpolationQuality = .low
        ctx.scaleBy(x: CGFloat(Self.scale), y: CGFloat(Self.scale))
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        body(ctx)
        ctx.restoreGState()
        guard let image = ctx.makeImage() else { return nil }
        return WorldKit.enlarge(CIImage(cgImage: image), rect: rect, from: Self.scale)
    }
}

extension WorldKit {
    /// A sprite as a picture the graphics chip can turn, stretch and fade, made once per sprite.
    static func ciSprite(_ image: CGImage?) -> CIImage? { image.map { CIImage(cgImage: $0) } }

    /// Places a sprite: its own lower left corner at the origin, stretched to `size`, turned by `angle` about the origin, moved to
    /// `at`, and faded to `alpha`. For laying many large soft shapes on the graphics chip instead of the CPU.
    static func placed(_ sprite: CIImage, size: CGSize, anchor: CGPoint = .zero, angle: Double, at: CGPoint, alpha: Double, shear: Double = 0) -> CIImage {
        let sx = size.width / sprite.extent.width, sy = size.height / sprite.extent.height
        let transform = CGAffineTransform(translationX: -sprite.extent.minX, y: -sprite.extent.minY)
            .concatenating(CGAffineTransform(scaleX: sx, y: sy))
            .concatenating(CGAffineTransform(translationX: -anchor.x, y: -anchor.y))
            .concatenating(CGAffineTransform(a: 1, b: 0, c: CGFloat(shear), d: 1, tx: 0, ty: 0))
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(angle)))
            .concatenating(CGAffineTransform(translationX: at.x, y: at.y))
        return sprite.transformed(by: transform).fading(alpha)
    }

    /// Light layers added together, over black, ready to add to a picture.
    static func sum(_ layers: [CIImage], rect: CGRect) -> CIImage {
        var total = CIImage(color: .black).cropped(to: rect)
        for layer in layers {
            let add = CIFilter.additionCompositing()
            add.inputImage = layer.cropped(to: rect)
            add.backgroundImage = total
            total = add.outputImage ?? total
        }
        return total.settingAlphaOne(in: rect)
    }
}
