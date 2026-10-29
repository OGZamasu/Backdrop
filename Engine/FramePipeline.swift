import CoreImage
import CoreMedia
import CoreVideo
import QuartzCore

/// Camera frame in, finished frame out: segment, composite, hand off to the virtual camera and the preview.
///
/// Configuration changes are applied on `queue`, the same queue the camera delivers frames on, so a frame
/// is never half-way through a background swap.
final class FramePipeline {
    let queue = DispatchQueue(label: "app.backdrop.pipeline", qos: .userInteractive)
    let compositor: Compositor

    /// Every finished frame (1280×720 BGRA). Called on `queue`.
    var onOutput: ((CVPixelBuffer, CMTime) -> Void)?
    /// A downscaled copy for the on-screen preview, delivered only while preview is enabled. Called on `queue`.
    var onPreview: ((CGImage) -> Void)?

    private let segmenter = PersonSegmenter()
    private let smoother = MaskSmoother()

    private var background = Background.off
    private var source: BackgroundSource?
    private var outgoing: (source: BackgroundSource, startedAt: CFTimeInterval)?
    private var parameters = CompositeParameters()
    private var previewEnabled = false
    private var frameCount = 0

    private let transitionDuration: CFTimeInterval = 0.45

    init(compositor: Compositor = Compositor()) {
        self.compositor = compositor
    }

    // MARK: Configuration

    func setBackground(_ new: Background, source newSource: BackgroundSource?) {
        queue.async {
            if case .passthrough = new.kind {
                self.source?.stop()
                self.outgoing?.source.stop()
                self.source = nil
                self.outgoing = nil
            } else {
                newSource?.start()
                if let old = self.source {
                    // Dissolve from whatever was showing, even if that was itself mid-dissolve.
                    self.outgoing?.source.stop()
                    self.outgoing = (old, CACurrentMediaTime())
                }
                self.source = newSource
            }
            self.background = new
        }
    }

    /// Applies edited settings (such as the parallax toggle) to the background already showing, without restarting its source.
    func updateCurrentBackground(_ updated: Background) {
        queue.async { if updated.id == self.background.id { self.background = updated } }
    }

    func setParameters(_ new: CompositeParameters) { queue.async { self.parameters = new } }
    func setQuality(_ quality: PersonSegmenter.Quality) { queue.async { self.segmenter.quality = quality } }
    func setPreviewEnabled(_ enabled: Bool) { queue.async { self.previewEnabled = enabled } }

    func stop() {
        queue.async {
            self.source?.stop()
            self.outgoing?.source.stop()
            self.outgoing = nil
            self.smoother.reset()
        }
    }

    // MARK: Processing

    /// Must be called on `queue`.
    func process(_ camera: CVPixelBuffer, at time: CMTime) {
        let now = CACurrentMediaTime()
        let cameraImage = CIImage(cvPixelBuffer: camera)
        let composed: CIImage

        if case .passthrough = background.kind {
            composed = compositor.compose(camera: cameraImage, mask: nil, background: nil)
        } else {
            // If Vision hiccups, reuse the last matte. Only if there has never been one do we fall back to
            // a heavy blur, so the room you meant to hide is never shown, even for a frame.
            let matteBuffer = segmenter.mask(for: camera).map(smoother.smooth) ?? smoother.latest
            if let matteBuffer {
                let parallax = background.parallax
                    ? CGPoint(x: (smoother.centroid.x - 0.5) * 2, y: (0.5 - smoother.centroid.y) * 2)
                    : nil
                composed = compositor.compose(camera: cameraImage,
                                              mask: Compositor.matte(from: matteBuffer),
                                              background: backgroundImage(camera: cameraImage, now: now, parallax: parallax),
                                              params: parameters)
            } else {
                let blurred = cameraImage.clampedToExtent().applyingGaussianBlur(sigma: 40).cropped(to: cameraImage.extent)
                composed = compositor.compose(camera: blurred, mask: nil, background: nil)
            }
        }

        guard let output = compositor.makeOutputBuffer() else { return }
        compositor.render(composed, into: output)
        onOutput?(output, time)

        frameCount += 1
        if previewEnabled, frameCount % 2 == 0, let onPreview {
            let half = CIImage(cvPixelBuffer: output).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
            if let image = compositor.context.createCGImage(half, from: half.extent) { onPreview(image) }
        }
    }

    private func backgroundImage(camera: CIImage, now: CFTimeInterval, parallax: CGPoint?) -> CIImage {
        func prepared(_ source: BackgroundSource?) -> CIImage? {
            guard let source, let frame = source.frame(at: now, camera: camera) else { return nil }
            return compositor.prepareBackground(frame, fits: source.fitsContent, parallax: parallax)
        }

        // Until a video or window delivers its first frame, hold a dark fill rather than showing the room.
        let placeholder = CIImage(color: CIColor(red: 0.07, green: 0.07, blue: 0.08)).cropped(to: compositor.rect)
        let current = prepared(source) ?? placeholder

        guard let outgoing else { return current }
        let progress = (now - outgoing.startedAt) / transitionDuration
        if progress >= 1 {
            outgoing.source.stop()
            self.outgoing = nil
            return current
        }
        return compositor.dissolve(from: prepared(outgoing.source) ?? placeholder, to: current, progress: progress)
    }
}

extension Compositor {
    /// Wraps a single-channel matte without colour management. Gamma-converting a matte would bend
    /// its mid-tones, which are exactly the soft edge pixels.
    static func matte(from buffer: CVPixelBuffer) -> CIImage {
        CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
    }
}
