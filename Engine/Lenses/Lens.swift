import CoreGraphics
import CoreImage
import CoreVideo

/// What a lens needs the pipeline to work out for it each frame. Asking for less keeps the video fast.
struct LensNeeds: OptionSet {
    let rawValue: Int
    /// The person's silhouette, from the same cutout that places you in front of a backdrop.
    static let matte = LensNeeds(rawValue: 1 << 0)
    /// Where the face is and what it is doing: eyes, mouth, eyebrows.
    static let face = LensNeeds(rawValue: 1 << 1)
}

/// One line for the interface: a score, a hint, a countdown.
struct LensStatus: Equatable {
    var title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }
}

/// Everything a lens may draw on or react to, for one frame.
///
/// All coordinates are output pixels with the origin at the lower left and y pointing up, which is how Core Image
/// and Core Graphics both work, so nothing needs flipping.
struct LensInput {
    let time: Double
    /// Seconds since the previous frame, clamped so a stall doesn't launch every object across the screen.
    let dt: Double
    let rect: CGRect
    /// The camera, fitted to the output.
    let camera: CIImage
    /// The person's cutout on the output's pixels, when the lens asked for it.
    let matte: CIImage?
    /// The backdrop behind the person, or nil when the backdrop is Off.
    let background: CIImage?
    /// The picture so far: the person over the backdrop, or just the camera.
    let composed: CIImage
    /// The same silhouette as a small grid the CPU can read, for physics. Only when `wantsMatteGrid`.
    let matteGrid: MatteGrid?
    let face: FaceState?
    let services: LensServices
}

/// A live effect or game that goes on top of the picture, like a Snapchat lens.
protocol Lens: AnyObject {
    var needs: LensNeeds { get }
    /// Whether to read the silhouette back to the CPU each frame (a small cost, needed for collisions).
    var wantsMatteGrid: Bool { get }
    var status: LensStatus? { get }
    /// Returns the finished picture, covering `input.rect`.
    func render(_ input: LensInput) -> CIImage
    /// Starts over: a new game, a clean slate.
    func restart()
}

extension Lens {
    var wantsMatteGrid: Bool { false }
    var status: LensStatus? { nil }
    func restart() {}
}

/// Shared tools handed to every lens.
final class LensServices {
    let context: CIContext
    let size: CGSize
    private let canvas: OverlayCanvas?
    private var pool: CVPixelBufferPool?

    init(context: CIContext, size: CGSize) {
        self.context = context
        self.size = size
        canvas = OverlayCanvas(size: size, slots: 4)
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
    }

    /// Draws into a fresh transparent layer and returns it, ready to composite. Up to four of these can be in
    /// use in one frame.
    func overlay(_ draw: (CGContext) -> Void) -> CIImage? {
        guard let canvas else { return nil }
        draw(canvas.begin())
        return canvas.image()
    }

    /// A full-size buffer, for a lens that keeps a picture from one frame to the next.
    func makeBuffer() -> CVPixelBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
