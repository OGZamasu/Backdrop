import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

/// Produces the picture that goes behind you. Sources can be any size; the compositor fits them.
protocol BackgroundSource: AnyObject {
    /// Letterbox over a blurred copy instead of cropping. Right for windows and screens, wrong for photos.
    var fitsContent: Bool { get }
    func start()
    func stop()
    /// The newest frame, or nil if the source hasn't produced one yet. `camera` is the raw camera frame.
    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage?
}

extension BackgroundSource {
    var fitsContent: Bool { false }
    func start() {}
    func stop() {}
}

enum BackgroundSourceFactory {
    @MainActor
    static func make(for background: Background, library: BackgroundLibrary) -> BackgroundSource? {
        switch background.kind {
        case .passthrough:
            return nil
        case .blur(let radius):
            return BlurSource(radius: radius)
        case .gradient(let preset):
            return GradientSource(preset: preset)
        case .pipes:
            return PipesSource()
        case .maze:
            return MazeSource()
        case .image:
            return library.fileURL(for: background).map(ImageSource.init)
        case .video:
            return library.fileURL(for: background).map(VideoLoopSource.init)
        case .window(let bundleID, let title):
            return WindowCaptureSource(target: .window(bundleID: bundleID, title: title))
        case .display:
            return WindowCaptureSource(target: .display)
        case .solid(let hex, let lit):
            return SolidBackdropSource(hex: hex, lit: lit)
        case .treated(let treatment):
            return CameraTreatmentSource(treatment)
        case .procedural(let style):
            return ProceduralBackdrop.makeSource(for: style)
        }
    }
}

// MARK: - Still image

final class ImageSource: BackgroundSource {
    private let image: CIImage?

    init(url: URL) {
        // Decode once at a sensible size. Re-decoding a 24-megapixel photo every frame would sink the pipeline.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 2560,
        ]
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            image = CIImage(cgImage: cgImage)
        } else {
            image = nil
        }
    }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? { image }
}

// MARK: - Blur

/// The classic: your own room, out of focus, the way a fast lens would see it rather than a plain smear.
///
/// - Depth: the top of the picture (the far wall, the ceiling) goes softer than the bottom (the desk and chair near you).
/// - Bokeh: bright spots (lamps, windows) bloom into soft discs instead of fading to grey.
/// - It is worked out on a small copy (a quarter or half the size) and enlarged smoothly, which a blur this wide hides,
///   so even the heaviest costs well under a millisecond.
final class BlurSource: BackgroundSource {
    private let radius: Double
    init(radius: Double) { self.radius = radius }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        let extent = camera.extent
        guard extent.width > 1, extent.height > 1, extent.width.isFinite, extent.height.isFinite else { return nil }
        return BackdropLens.blurred(camera, sigma: radius, bokeh: 0.55).map { BackdropFinish.finish($0) }
    }
}

/// A lens's out-of-focus look for the camera picture, shared by the blurs and the camera looks.
enum BackdropLens {
    /// `image` out of focus by about `sigma` pixels: softer toward the top (further away), with bright spots spread into
    /// discs and laid back on as light (`bokeh` 0 for none, 1 for strong). Nil for an empty picture.
    static func blurred(_ image: CIImage, sigma: Double, bokeh: Double) -> CIImage? {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1, extent.width.isFinite, extent.height.isFinite else { return nil }
        let shrink: CGFloat = sigma <= 8 ? 0.5 : 0.25
        let toSmall = CGAffineTransform(translationX: -extent.minX, y: -extent.minY).concatenating(CGAffineTransform(scaleX: shrink, y: shrink))
        let small = image.transformed(by: toSmall)
        let box = small.extent
        let s = sigma * Double(shrink)

        // Where it is far (the top) the blur is full; toward the bottom it eases to about two thirds.
        let depth = CIFilter.linearGradient()
        depth.point0 = CGPoint(x: 0, y: box.height * 0.08)
        depth.point1 = CGPoint(x: 0, y: box.height * 0.62)
        depth.color0 = CIColor(red: 0.62, green: 0.62, blue: 0.62)
        depth.color1 = CIColor(red: 1, green: 1, blue: 1)
        let variable = CIFilter.maskedVariableBlur()
        variable.inputImage = small.clampedToExtent()
        variable.mask = depth.outputImage?.cropped(to: box)
        variable.radius = Float(s)
        var soft = (variable.outputImage ?? small.clampedToExtent().applyingGaussianBlur(sigma: s)).cropped(to: box)

        if bokeh > 0 {
            // Only what is close to white, spread with a disc (a lens's aperture), then laid back on as light.
            let hot = small.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.6, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1.6, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.6, w: 0), "inputBiasVector": CIVector(x: -1.05, y: -1.05, z: -1.05, w: 0),
            ]).applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                                                           "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)])
            let disc = CIFilter.discBlur()
            disc.inputImage = hot.clampedToExtent()
            disc.radius = Float(max(1, s * 1.15))
            let spread = (disc.outputImage ?? hot).cropped(to: box).clampedToExtent().applyingGaussianBlur(sigma: max(0.6, s * 0.12)).cropped(to: box)
            soft = spread.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: bokeh, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: bokeh, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: bokeh, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]).applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: soft]).cropped(to: box)
        }

        // Back to full size, smoothly, and onto the picture's own place.
        let enlarge = CIFilter.bicubicScaleTransform()
        enlarge.inputImage = soft.clampedToExtent()
        enlarge.scale = Float(1 / shrink)
        enlarge.aspectRatio = 1
        enlarge.parameterB = 1
        enlarge.parameterC = 0
        guard let big = enlarge.outputImage else { return nil }
        return big.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).cropped(to: extent)
    }
}

// MARK: - Looping video

final class VideoLoopSource: BackgroundSource {
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private var endObserver: NSObjectProtocol?
    private var latest: CIImage?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ])
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: nil) { [weak player] _ in
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in player?.play() }
        }
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player.pause()
    }

    func start() { player.play() }
    func stop() { player.pause() }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: itemTime),
           let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            latest = CIImage(cvPixelBuffer: buffer)
        }
        return latest
    }
}
