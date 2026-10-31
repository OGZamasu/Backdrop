import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Blobs of warm wax drifting up and down in glowing liquid, merging and pulling apart.
///
/// Each frame draws a handful of soft round glows, white on black, on a small surface: where blobs overlap their glows add
/// up. Core Image then turns that measurement into wax. Anything above a level is wax, coloured by how far above it is;
/// the rest is the lit liquid behind. Because the edge is a level in a smooth field, blobs bulge toward each other and fuse
/// the way real ones do. The same measurement, compared with itself shifted toward the light, gives each blob a soft
/// highlight on its upper left; a blurred copy of the wax gives the glow it throws into the liquid. Blob places come from
/// the clock alone, so a stall cannot make them jump.
final class LavaLampSource: BackgroundSource {
    private struct Blob {
        let x: Double, xSway: Double, xRate: Double, xPhase: Double
        let yRate: Double, yPhase: Double, yLow: Double, yHigh: Double
        let radius: Double
    }

    private static let size = CGSize(width: 1280, height: 720)
    private static let fieldWidth = 320, fieldHeight = 180

    private let blobs: [Blob]
    private var canvas: BackdropCanvas?
    private var glass: CIImage?
    private var tables: (wax: CIImage, shine: CIImage)?
    private var falloff: CGImage?

    init(seed: UInt64 = 0x1A7A) {
        var rng = SplitMix64(seed: seed)
        blobs = (0..<10).map { i in
            Blob(x: 0.12 + 0.76 * Double(i) / 9 + .random(in: -0.04...0.04, using: &rng),
                 xSway: .random(in: 0.04...0.11, using: &rng), xRate: .random(in: 0.05...0.11, using: &rng), xPhase: .random(in: 0..<(2 * .pi), using: &rng),
                 yRate: .random(in: 0.035...0.075, using: &rng), yPhase: .random(in: 0..<(2 * .pi), using: &rng),
                 yLow: .random(in: 0.10...0.28, using: &rng), yHigh: .random(in: 0.72...0.92, using: &rng),
                 radius: .random(in: 28...46, using: &rng))
        }
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        if canvas == nil { canvas = BackdropCanvas(width: Self.fieldWidth, height: Self.fieldHeight) }
        if glass == nil { glass = BackdropBake.flatten(Self.makeGlass()) }
        if tables == nil { tables = Self.makeTables() }
        if falloff == nil { falloff = Self.makeFalloff() }
        guard let canvas, let glass, let tables, let falloff else { return nil }

        let ctx = canvas.context
        canvas.clear()
        ctx.setFillColor(BackdropPaint.color(0, 0, 0))
        ctx.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        ctx.setBlendMode(.plusLighter)
        let w = Double(canvas.width), h = Double(canvas.height)
        for blob in blobs {
            // Up and down in a slow wave that lingers at the ends, with a lazy sideways wander.
            let rise = 0.5 - 0.5 * BackdropMotion.wave(time, rate: blob.yRate, phase: blob.yPhase + .pi / 2)
            let centre = CGPoint(x: w * (blob.x + blob.xSway * BackdropMotion.wave(time, rate: blob.xRate, phase: blob.xPhase)),
                                 y: h * (blob.yLow + (blob.yHigh - blob.yLow) * rise))
            // Blobs swell a little as they warm up near the bottom, and stretch as they travel.
            let radius = blob.radius * (1.0 + 0.12 * (1 - rise))
            let stretch = 1.0 + 0.10 * abs(BackdropMotion.wave(time, rate: blob.yRate, phase: blob.yPhase))
            ctx.draw(falloff, in: CGRect(x: centre.x - radius / stretch, y: centre.y - radius * stretch, width: radius * 2 / stretch, height: radius * 2 * stretch))
        }
        // The wax pooling along the bottom and capping the top, which the blobs grow out of and sink back into.
        for (x, y, r) in [(0.28, -0.07, 62.0), (0.70, -0.09, 70.0), (0.5, 1.08, 52.0)] {
            ctx.draw(falloff, in: CGRect(x: w * x - r, y: h * y - r, width: r * 2, height: r * 2))
        }
        ctx.setBlendMode(.normal)

        // A touch of blur before the level is cut takes the speckle out of the edge, which Core Graphics's gradients leave in.
        guard let measured = canvas.image(raw: true) else { return glass }
        // The wax is coloured and lit at half size, then enlarged with a sharp filter: the edges stay crisp and it costs a
        // quarter as much.
        let frame = BackdropPainter.half
        // A touch of blur on the small measurement takes out the speckle Core Graphics's gradients leave in it (the
        // highlight, which follows the slope, would show it); then a smooth B-spline enlargement.
        let smooth = measured.clampedToExtent().applyingGaussianBlur(sigma: 0.9).cropped(to: measured.extent)
        let enlarge = CIFilter.bicubicScaleTransform()
        enlarge.inputImage = smooth.clampedToExtent()
        enlarge.scale = Float(frame.width / CGFloat(canvas.width))
        enlarge.aspectRatio = 1
        enlarge.parameterB = 1
        enlarge.parameterC = 0
        guard let field = enlarge.outputImage?.cropped(to: frame) else { return glass }

        let wax = BackdropInk.colored(field, tables.wax)
        // Light from the upper left: where the field is higher just toward the lower right, the surface faces the light.
        // facing = 0.5 + 3 x (field ahead - field here).
        let ahead = field.transformed(by: CGAffineTransform(translationX: -3.5, y: 3.5)).cropped(to: frame)
        let gain = 3.0
        let aheadScaled = ahead.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0), "inputBiasVector": CIVector(x: 0.5, y: 0.5, z: 0.5, w: 0),
        ])
        let hereNegated = field.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -gain, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: -gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: -gain, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        let facing = hereNegated.applyingFilter("CILinearDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: aheadScaled]).cropped(to: frame)
        // The highlight only lands on wax: laid "atop" it, so the liquid around stays clear.
        let shine = BackdropInk.colored(facing, tables.shine)
        let shaded = shine.applyingFilter("CISourceAtopCompositing", parameters: [kCIInputBackgroundImageKey: wax]).cropped(to: frame)
        // The glow the wax throws into the liquid around it, worked out small.
        let bloom = shaded.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)).clampedToExtent()
            .applyingGaussianBlur(sigma: 9).transformed(by: CGAffineTransform(scaleX: 4, y: 4)).cropped(to: BackdropPainter.frame)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.55, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.55, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.55, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.55),
            ])
        let liquid = bloom.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: glass]).cropped(to: BackdropPainter.frame)
        return BackdropFinish.finish(BackdropPainter.enlarged(shaded, sharp: true).composited(over: liquid))
    }

    // MARK: Still pieces

    /// One blob's share of the measurement: strongest in the middle, smoothly down to nothing at the edge, so blobs have no
    /// rim of their own. Drawn once as a picture; a picture is also drawn the same way every time, where a gradient is not.
    private static func makeFalloff() -> CGImage? {
        let side = 128
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: BackdropCanvas.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let ramp = BackdropPaint.gradient([(at: 0, r: 1, g: 1, b: 1, a: 0.80), (at: 0.25, r: 1, g: 1, b: 1, a: 0.67),
                                                 (at: 0.5, r: 1, g: 1, b: 1, a: 0.40), (at: 0.75, r: 1, g: 1, b: 1, a: 0.13),
                                                 (at: 1, r: 1, g: 1, b: 1, a: 0)])
        else { return nil }
        let c = CGPoint(x: side / 2, y: side / 2)
        ctx.drawRadialGradient(ramp, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(side) / 2, options: [])
        return ctx.makeImage()
    }

    /// The liquid, lit from below: deep violet at the top to glowing magenta at the bottom, the hot glow of the bulb at
    /// the foot, and the long soft reflections of a glass cylinder down both sides.
    private static func makeGlass() -> CIImage? {
        guard let painted = BackdropPainter.paint(width: 640, height: 360, { ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [
                (at: 0, color: BackdropRGB(hex: 0x9C1650)), (at: 0.4, color: BackdropRGB(hex: 0x52105A)), (at: 1, color: BackdropRGB(hex: 0x1A0636)),
            ])
            BackdropPainter.glow(ctx, at: CGPoint(x: 640, y: -80), radius: 820, color: BackdropRGB(1.0, 0.42, 0.28), alpha: 0.45, squash: 0.7, blend: .screen)
            for (x, w, a) in [(CGFloat(150), CGFloat(70), 0.10), (CGFloat(1110), CGFloat(110), 0.07), (CGFloat(240), CGFloat(18), 0.12)] {
                if let g = BackdropPaint.gradient([(at: 0, r: 1, g: 0.85, b: 0.95, a: 0), (at: 0.5, r: 1, g: 0.85, b: 0.95, a: a), (at: 1, r: 1, g: 0.85, b: 0.95, a: 0)]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: x - w / 2, y: 0), end: CGPoint(x: x + w / 2, y: 0), options: [])
                }
            }
        }) else { return nil }
        return BackdropFinish.vignette(painted, strength: 0.25)
    }

    /// The tables that turn "how much blob is here" into wax (clear below the level, a soft edge, then colour deepening
    /// from a red rim to a golden heart), and the surface's slope into the highlight's warm white.
    private static func makeTables() -> (wax: CIImage, shine: CIImage) {
        let level = 0.30
        let wax = BackdropInk.table([
            (at: 0, color: BackdropRGB(hex: 0xFF3A40), alpha: 0), (at: level - 0.005, color: BackdropRGB(hex: 0xFF3A40), alpha: 0),
            (at: level + 0.045, color: BackdropRGB(hex: 0xF0383E), alpha: 1), (at: 0.5, color: BackdropRGB(hex: 0xFF6A3A), alpha: 1),
            (at: 0.78, color: BackdropRGB(hex: 0xFFA640), alpha: 1), (at: 1, color: BackdropRGB(hex: 0xFFD066), alpha: 1),
        ])
        let shine = BackdropInk.table([
            (at: 0, color: BackdropRGB(1, 0.9, 0.75), alpha: 0), (at: 0.56, color: BackdropRGB(1, 0.9, 0.75), alpha: 0),
            (at: 0.8, color: BackdropRGB(1, 0.92, 0.8), alpha: 0.35), (at: 1, color: BackdropRGB(1, 0.97, 0.9), alpha: 0.7),
        ])
        return (wax, shine)
    }
}
