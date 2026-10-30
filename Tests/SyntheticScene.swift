import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import XCTest

/// Saves a picture when BACKDROP_TEST_OUTPUT is set, so lenses can be looked at, not just measured.
enum Output {
    static let context = CIContext()
    static func save(_ image: CIImage, as name: String) {
        guard let folder = ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] else { return }
        try? context.writePNGRepresentation(of: image, to: URL(fileURLWithPath: folder).appendingPathComponent(name),
                                            format: .RGBA8, colorSpace: TestSupport.srgb)
    }
}

/// A pretend person in a pretend room, so lenses can be run and looked at with no camera and no Vision.
/// Head-relative geometry is drawn and reported from the same numbers, so what a lens thinks is the mouth is the mouth.
struct SyntheticScene {
    static let size = CGSize(width: 1280, height: 720)

    var center = CGPoint(x: 640, y: 420)
    var scale: Double = 1
    /// Radians, counter-clockwise.
    var roll: Double = 0
    var mouthOpen: Double = 0
    var browRaise: Double = 0
    /// 0 eyes open, 1 shut.
    var blink: Double = 0
    /// 0 neutral, 1 a broad smile.
    var smile: Double = 0

    // Head-relative layout, before roll.
    private var io: Double { 84 * scale }
    private var eyeHeight: Double { 20 * scale }
    private var mouthHeight: Double { -60 * scale }

    private func rotated(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: center.x + x * cos(roll) - y * sin(roll), y: center.y + x * sin(roll) + y * cos(roll))
    }

    func face() -> FaceState {
        let browDistance = 0.40 + 0.28 * browRaise
        let browHeight = eyeHeight + io * browDistance
        return FaceState(leftEye: rotated(-io / 2, eyeHeight), rightEye: rotated(io / 2, eyeHeight),
                         mouth: rotated(0, mouthHeight), mouthWidth: 70 * scale * (1 + 0.35 * smile),
                         browCenter: rotated(0, browHeight),
                         rect: CGRect(x: center.x - 95 * scale, y: center.y - 120 * scale, width: 190 * scale, height: 240 * scale),
                         mouthOpen: mouthOpen, browRaise: browRaise, browDistance: browDistance, blink: blink, smile: smile)
    }

    // MARK: Pictures

    func cameraBuffer() -> CVPixelBuffer {
        let (buffer, ctx) = Self.bitmap(pixelFormat: kCVPixelFormatType_32BGRA)
        // The room.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.18, green: 0.46, blue: 0.52, alpha: 1),
                                                               CGColor(red: 0.05, green: 0.10, blue: 0.22, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 720), end: CGPoint(x: 0, y: 0), options: [])
        ctx.setFillColor(CGColor(red: 0.92, green: 0.80, blue: 0.50, alpha: 1))
        ctx.fill(CGRect(x: 110, y: 340, width: 230, height: 250))
        ctx.setFillColor(CGColor(red: 0.55, green: 0.35, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 960, y: 0, width: 220, height: 300))

        // The person.
        let skin = CGColor(red: 0.93, green: 0.74, blue: 0.62, alpha: 1)
        ctx.setFillColor(CGColor(red: 0.25, green: 0.35, blue: 0.78, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: center.x - 270 * scale, y: center.y - 470 * scale, width: 540 * scale, height: 340 * scale))
        ctx.setFillColor(skin)
        ctx.fill(CGRect(x: center.x - 40 * scale, y: center.y - 190 * scale, width: 80 * scale, height: 110 * scale))

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: roll)
        ctx.setFillColor(skin)
        ctx.fillEllipse(in: CGRect(x: -95 * scale, y: -120 * scale, width: 190 * scale, height: 240 * scale))
        ctx.setFillColor(CGColor(red: 0.22, green: 0.14, blue: 0.10, alpha: 1))                       // hair
        ctx.fillEllipse(in: CGRect(x: -100 * scale, y: 12 * scale, width: 200 * scale, height: 126 * scale))
        ctx.setFillColor(skin)
        ctx.fillEllipse(in: CGRect(x: -80 * scale, y: -10 * scale, width: 160 * scale, height: 70 * scale))   // forehead showing under the fringe
        for side in [-1.0, 1.0] {                                                                      // eyes
            let ex = side * io / 2
            ctx.setFillColor(.white); ctx.fillEllipse(in: CGRect(x: ex - 17 * scale, y: eyeHeight - 11 * scale * (1 - 0.85 * blink), width: 34 * scale, height: 22 * scale * (1 - 0.85 * blink)))
            if blink < 0.5 { ctx.fillCircle(center: CGPoint(x: ex, y: eyeHeight), radius: 7 * scale, color: CGColor(red: 0.15, green: 0.1, blue: 0.08, alpha: 1)) }
            let browY = eyeHeight + io * (0.40 + 0.28 * browRaise)
            ctx.setStrokeColor(CGColor(red: 0.18, green: 0.11, blue: 0.08, alpha: 1)); ctx.setLineWidth(7 * scale); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: ex - 20 * scale, y: browY)); ctx.addLine(to: CGPoint(x: ex + 20 * scale, y: browY)); ctx.strokePath()
        }
        ctx.setStrokeColor(CGColor(red: 0.75, green: 0.55, blue: 0.45, alpha: 1)); ctx.setLineWidth(5 * scale)                          // nose
        ctx.move(to: CGPoint(x: 0, y: eyeHeight - 8 * scale)); ctx.addLine(to: CGPoint(x: 0, y: -28 * scale)); ctx.strokePath()
        let mouthHeightPx = (6 + 46 * mouthOpen) * scale
        ctx.setFillColor(CGColor(red: 0.45, green: 0.08, blue: 0.10, alpha: 1))
        let mouthWidthPx = 70 * scale * (1 + 0.35 * smile)
        ctx.fillEllipse(in: CGRect(x: -mouthWidthPx / 2, y: mouthHeight - mouthHeightPx / 2, width: mouthWidthPx, height: mouthHeightPx))
        ctx.restoreGState()
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// The person's silhouette, one channel, 255 where they are.
    func matteBuffer() -> CVPixelBuffer {
        let (buffer, ctx) = Self.bitmap(pixelFormat: kCVPixelFormatType_OneComponent8)
        ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(origin: .zero, size: Self.size))
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: center.x - 270 * scale, y: center.y - 470 * scale, width: 540 * scale, height: 340 * scale))
        ctx.fill(CGRect(x: center.x - 40 * scale, y: center.y - 190 * scale, width: 80 * scale, height: 110 * scale))
        ctx.saveGState(); ctx.translateBy(x: center.x, y: center.y); ctx.rotate(by: roll)
        ctx.fillEllipse(in: CGRect(x: -100 * scale, y: -120 * scale, width: 200 * scale, height: 258 * scale))
        ctx.restoreGState()
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// Everything a lens is handed for one frame, made the way the pipeline makes it.
    func input(time: Double = 0, dt: Double = 1.0 / 30, services: LensServices, compositor: Compositor,
               grid: MatteGrid? = nil, background: CIImage? = nil, withFace: Bool = true) -> LensInput {
        let camera = CIImage(cvPixelBuffer: cameraBuffer())
        let fitted = compositor.fitted(camera)
        let matte = compositor.refinedMatte(camera: camera, mask: Compositor.matte(from: matteBuffer()))
        let composed = background.map { compositor.composite(camera: camera, matte: matte, background: $0) } ?? fitted
        grid?.update(from: matte, rect: compositor.rect, context: compositor.context)
        return LensInput(time: time, dt: dt, rect: compositor.rect, camera: fitted, matte: matte, background: background,
                         composed: composed, matteGrid: grid, face: withFace ? face() : nil, services: services)
    }

    /// A dark purple-to-blue backdrop to put the person in front of.
    static func backdrop() -> CIImage {
        let g = CIFilter.linearGradient()
        g.point0 = CGPoint(x: 0, y: 720); g.point1 = CGPoint(x: 1280, y: 0)
        g.color0 = CIColor(red: 0.30, green: 0.10, blue: 0.45); g.color1 = CIColor(red: 0.05, green: 0.12, blue: 0.35)
        return g.outputImage!.cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func bitmap(pixelFormat: OSType) -> (CVPixelBuffer, CGContext) {
        var created: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1280, 720, pixelFormat, [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &created)
        let buffer = created!
        CVPixelBufferLockBaseAddress(buffer, [])
        let gray = pixelFormat == kCVPixelFormatType_OneComponent8
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 1280, height: 720, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                            space: gray ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: gray ? CGImageAlphaInfo.none.rawValue : CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        return (buffer, ctx)
    }
}
