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
        case .image:
            return library.fileURL(for: background).map(ImageSource.init)
        case .video:
            return library.fileURL(for: background).map(VideoLoopSource.init)
        case .window(let bundleID, let title):
            return WindowCaptureSource(target: .window(bundleID: bundleID, title: title))
        case .display:
            return WindowCaptureSource(target: .display)
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

/// The classic: your own room, out of focus.
final class BlurSource: BackgroundSource {
    private let radius: Double
    init(radius: Double) { self.radius = radius }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        camera.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: camera.extent)
    }
}

// MARK: - Animated gradient

/// A slow-drifting colour wash. Procedural, so it's free of files and never repeats.
final class GradientSource: BackgroundSource {
    private let preset: GradientPreset
    private let size = CGSize(width: 1280, height: 720)

    init(preset: GradientPreset) { self.preset = preset }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        let colors = preset.colors.map { CIColor(red: $0[0], green: $0[1], blue: $0[2]) }
        let rect = CGRect(origin: .zero, size: size)

        let ramp = CIFilter.linearGradient()
        ramp.point0 = CGPoint(x: size.width * (0.5 + 0.45 * cos(time * 0.11)), y: size.height * (0.5 + 0.45 * sin(time * 0.13)))
        ramp.point1 = CGPoint(x: size.width - ramp.point0.x, y: size.height - ramp.point0.y)
        ramp.color0 = colors[0]
        ramp.color1 = colors[1]
        guard var image = ramp.outputImage?.cropped(to: rect) else { return nil }

        for i in 0..<2 {
            let phase = time * (0.07 + 0.04 * Double(i)) + Double(i) * 2.1
            let glow = CIFilter.radialGradient()
            glow.center = CGPoint(x: size.width * (0.5 + 0.40 * cos(phase)), y: size.height * (0.5 + 0.35 * sin(phase * 1.3)))
            glow.radius0 = 0
            glow.radius1 = Float(size.height * 0.75)
            let tint = colors[2 + i]
            glow.color0 = CIColor(red: tint.red, green: tint.green, blue: tint.blue, alpha: 0.55)
            glow.color1 = CIColor(red: tint.red, green: tint.green, blue: tint.blue, alpha: 0)
            if let layer = glow.outputImage?.cropped(to: rect) { image = layer.composited(over: image) }
        }
        return image
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
