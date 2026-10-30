import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Metal

struct CompositeParameters {
    /// Blur applied to the matte edge, in output pixels.
    var edgeSoftness: Double = 1.6
    /// Moves the matte edge inward (positive) to trim the halo of old background around hair and shoulders.
    var edgeShift: Double = 0.03
    /// How much background light spills onto the edge of the subject, 0...1.
    var lightWrap: Double = 0.35
    /// How far the subject's colour cast is pulled toward the background's, 0...1.
    var colorMatch: Double = 0.30
}

final class Compositor {
    let outputSize: CGSize
    let context: CIContext

    private var pool: CVPixelBufferPool?
    private let outputSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var tint = SIMD3<Float>(0.5, 0.5, 0.5)
    // Starts at the refresh interval so the very first frame samples the background.
    private static let tintInterval = 8
    private var framesSinceTint = Compositor.tintInterval

    var rect: CGRect { CGRect(origin: .zero, size: outputSize) }

    init(outputSize: CGSize = CGSize(width: 1280, height: 720)) {
        self.outputSize = outputSize
        // Intermediates are left to Core Image's own cache (its default). With caching off, the usual advice for video, Core
        // Image marks every blur's scratch surface purgeable after each frame and claims it back on the next: twice the wakeups
        // per frame (28 against 54, measured at 30 fps) for no saving in memory (about 296 MB either way after half a minute).
        // A camera buffer that comes round again with a new picture in it is still seen as new; CostPerFrameTests checks that.
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device)
        } else {
            context = CIContext()
        }
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: Int(outputSize.width),
            kCVPixelBufferHeightKey: Int(outputSize.height),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
    }

    // MARK: Geometry

    /// Scales `source` to cover `dest`, centred. Anything that overhangs is cropped by the caller.
    static func fillTransform(_ source: CGRect, into dest: CGRect) -> CGAffineTransform {
        placement(source, into: dest, scale: max(dest.width / source.width, dest.height / source.height))
    }

    /// Scales `source` to sit entirely inside `dest`, centred.
    static func fitTransform(_ source: CGRect, into dest: CGRect) -> CGAffineTransform {
        placement(source, into: dest, scale: min(dest.width / source.width, dest.height / source.height))
    }

    private static func placement(_ source: CGRect, into dest: CGRect, scale s: CGFloat) -> CGAffineTransform {
        let w = source.width * s, h = source.height * s
        return CGAffineTransform(translationX: -source.minX, y: -source.minY)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: dest.minX + (dest.width - w) / 2,
                                             y: dest.minY + (dest.height - h) / 2))
    }

    // MARK: Background

    /// Fits a background frame to the output. Windows and screens are letterboxed over a blurred copy of
    /// themselves so slides and documents aren't cropped. Everything else fills the frame.
    ///
    /// `parallax` is the subject's offset from centre in -1...1 (y up); the background drifts the other way.
    func prepareBackground(_ image: CIImage, fits: Bool, parallax: CGPoint?) -> CIImage {
        let r = rect
        if fits {
            let backdrop = image.transformed(by: Self.fillTransform(image.extent, into: r))
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 36)
                .cropped(to: r)
            let content = image.transformed(by: Self.fitTransform(image.extent, into: r))
            return content.composited(over: backdrop).cropped(to: r)
        }

        var transform = Self.fillTransform(image.extent, into: r)
        if let p = parallax {
            // 8% overscan leaves a 4% margin each side, so a 3.5% shift never reveals an edge.
            let overscan: CGFloat = 1.08
            transform = transform
                .concatenating(CGAffineTransform(translationX: -r.midX, y: -r.midY))
                .concatenating(CGAffineTransform(scaleX: overscan, y: overscan))
                .concatenating(CGAffineTransform(translationX: r.midX - p.x * r.width * 0.035,
                                                 y: r.midY - p.y * r.height * 0.035))
        }
        return image.transformed(by: transform).cropped(to: r)
    }

    func dissolve(from: CIImage, to: CIImage, progress: Double) -> CIImage {
        let filter = CIFilter.dissolveTransition()
        filter.inputImage = from
        filter.targetImage = to
        filter.time = Float(max(0, min(1, progress)))
        return (filter.outputImage ?? to).cropped(to: rect)
    }

    // MARK: Compositing

    /// The camera scaled to cover the output, cropped to it.
    func fitted(_ camera: CIImage) -> CIImage {
        camera.transformed(by: Self.fillTransform(camera.extent, into: rect)).cropped(to: rect)
    }

    /// The person's cutout on the output's pixels, edges softened and tightened.
    func refinedMatte(camera: CIImage, mask: CIImage, params: CompositeParameters = .init()) -> CIImage {
        // The matte arrives at Vision's resolution; bring it onto the same pixels as the camera.
        let cameraTransform = Self.fillTransform(camera.extent, into: rect)
        let matte = mask
            .transformed(by: CGAffineTransform(scaleX: camera.extent.width / mask.extent.width,
                                               y: camera.extent.height / mask.extent.height))
            .transformed(by: cameraTransform)
            .cropped(to: rect)
        return refine(matte, params)
    }

    /// Puts the person (where `matte` is white) over `background`, with the colour tricks.
    func composite(camera: CIImage, matte refined: CIImage, background: CIImage, params: CompositeParameters = .init()) -> CIImage {
        let r = rect
        let base = fitted(camera)

        // Colour: nudge the subject toward the background's cast, then let background light wrap the edge.
        var subject = base
        if params.colorMatch > 0 {
            refreshTint(from: background)
            subject = applyTint(to: subject, strength: params.colorMatch)
        }
        if params.lightWrap > 0 {
            subject = wrapLight(from: background, mask: refined, onto: subject, strength: params.lightWrap)
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = subject
        blend.backgroundImage = background
        blend.maskImage = refined
        return (blend.outputImage ?? base).cropped(to: r)
    }

    /// Places the person (`mask` = 255) over `background`. With no mask or background the camera is just fitted.
    func compose(camera: CIImage, mask: CIImage?, background: CIImage?, params: CompositeParameters = .init()) -> CIImage {
        guard let mask, let background else { return fitted(camera) }
        return composite(camera: camera, matte: refinedMatte(camera: camera, mask: mask, params: params),
                         background: background, params: params)
    }

    /// Soften, then re-sharpen around a shifted threshold: smooth edges without a fuzzy halo.
    private func refine(_ matte: CIImage, _ p: CompositeParameters) -> CIImage {
        let softened = matte.clampedToExtent().applyingGaussianBlur(sigma: p.edgeSoftness).cropped(to: rect)
        let gain: CGFloat = 2.2
        let bias = 0.5 - gain * (0.5 + CGFloat(p.edgeShift))
        return softened
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
            ])
            .applyingFilter("CIColorClamp")
    }

    private func wrapLight(from background: CIImage, mask: CIImage, onto subject: CIImage, strength: Double) -> CIImage {
        let r = rect
        // A band just inside the silhouette: inside the mask, but near enough to the edge that the blurred mask is thin.
        let inverseBlur = mask.clampedToExtent().applyingGaussianBlur(sigma: 10).cropped(to: r).applyingFilter("CIColorInvert")
        let band = mask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: inverseBlur])
        let glow = background.clampedToExtent().applyingGaussianBlur(sigma: 14).cropped(to: r)
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: band])
        let s = CGFloat(strength) * 1.6
        return glow
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: s, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: s, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: s, w: 0),
            ])
            // Screen, not addition: adding two opaque layers would push alpha to 2 and brighten the whole subject.
            .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: subject])
    }

    /// Samples the background's average colour a few times a second, rather than reading the GPU every frame.
    private func refreshTint(from background: CIImage) {
        guard framesSinceTint >= Self.tintInterval else { framesSinceTint += 1; return }
        framesSinceTint = 0
        let average = background.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: background.extent)])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: outputSpace)
        let target = SIMD3<Float>(pixel[0], pixel[1], pixel[2])
        tint += (target - tint) * 0.5
    }

    private func applyTint(to image: CIImage, strength: Double) -> CIImage {
        let mean = max((tint.x + tint.y + tint.z) / 3, 0.03)
        func gain(_ channel: Float) -> CGFloat {
            let g = 1 + Float(strength) * 0.6 * (channel / mean - 1)
            return CGFloat(min(max(g, 0.75), 1.25))
        }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain(tint.x), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain(tint.y), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain(tint.z), w: 0),
        ])
    }

    // MARK: Output

    func makeOutputBuffer() -> CVPixelBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    func render(_ image: CIImage, into buffer: CVPixelBuffer) {
        context.render(image, to: buffer, bounds: rect, colorSpace: outputSpace)
    }
}
