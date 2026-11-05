import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import XCTest

/// Pretend shared screens for Present: a light slide, a dark code editor, a tall document and a very wide dashboard, drawn in code at
/// the sizes real windows come in.
enum StageFixtures {
    enum Content: String, CaseIterable {
        case slide, code, tallDocument, wideDashboard

        var size: CGSize {
            switch self {
            case .slide: return CGSize(width: 1920, height: 1080)
            case .code: return CGSize(width: 1600, height: 1000)
            case .tallDocument: return CGSize(width: 900, height: 1400)
            case .wideDashboard: return CGSize(width: 2560, height: 1080)
            }
        }
    }

    private static var cache: [Content: CIImage] = [:]

    static func image(_ content: Content) -> CIImage {
        if let hit = cache[content] { return hit }
        let made = CIImage(cgImage: draw(content))
        cache[content] = made
        return made
    }

    /// The same picture in a pixel buffer, the way a capture delivers it, so a test can mark it rewritten each frame.
    static func buffer(_ content: Content) -> CVPixelBuffer {
        let size = content.size
        var created: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &created)
        Output.context.render(image(content), to: created!)
        return created!
    }

    private static func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, at p: CGPoint, in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(at: p)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func mono(_ s: String, _ size: CGFloat, _ color: NSColor, at p: CGPoint, in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSAttributedString(string: s, attributes: [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), .foregroundColor: color]).draw(at: p)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func draw(_ content: Content) -> CGImage {
        let size = content.size
        let w = Int(size.width), h = Int(size.height)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: TestSupport.srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let W = CGFloat(w), H = CGFloat(h)
        switch content {
        case .slide:
            ctx.setFillColor(NSColor(srgbRed: 0.98, green: 0.98, blue: 0.97, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setFillColor(NSColor(srgbRed: 0.27, green: 0.62, blue: 1.0, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 120, y: H - 150, width: 90, height: 10))
            text("Q3 Roadmap", 96, .bold, NSColor(srgbRed: 0.1, green: 0.11, blue: 0.14, alpha: 1), at: CGPoint(x: 112, y: H - 290), in: ctx)
            text("What ships, what slips, and why", 40, .regular, NSColor(srgbRed: 0.42, green: 0.44, blue: 0.5, alpha: 1), at: CGPoint(x: 116, y: H - 360), in: ctx)
            let bullets = ["Hand control for Present", "Live window thumbnails", "Paused and lost cards", "60 fps sharing"]
            for (k, b) in bullets.enumerated() {
                let y = H - 500 - CGFloat(k) * 86
                ctx.setFillColor(NSColor(srgbRed: 0.27, green: 0.62, blue: 1.0, alpha: 1).cgColor)
                ctx.fillEllipse(in: CGRect(x: 124, y: y + 18, width: 16, height: 16))
                text(b, 44, .medium, NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1), at: CGPoint(x: 164, y: y), in: ctx)
            }
            let values: [CGFloat] = [0.35, 0.52, 0.48, 0.7, 0.86, 0.78]
            for (k, v) in values.enumerated() {
                let x = 1080 + CGFloat(k) * 120
                let colour = k % 2 == 0 ? NSColor(srgbRed: 0.27, green: 0.62, blue: 1.0, alpha: 1) : NSColor(srgbRed: 0.36, green: 0.84, blue: 0.74, alpha: 1)
                ctx.setFillColor(colour.cgColor)
                ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 160, width: 76, height: 640 * v), cornerWidth: 12, cornerHeight: 12, transform: nil))
                ctx.fillPath()
            }
            ctx.setFillColor(NSColor(srgbRed: 0.85, green: 0.86, blue: 0.88, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 1060, y: 150, width: 740, height: 3))
        case .code:
            ctx.setFillColor(NSColor(srgbRed: 0.11, green: 0.12, blue: 0.15, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setFillColor(NSColor(srgbRed: 0.16, green: 0.17, blue: 0.21, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: H - 56, width: W, height: 56))
            for (k, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                ctx.setFillColor(c.cgColor)
                ctx.fillEllipse(in: CGRect(x: 22 + CGFloat(k) * 30, y: H - 36, width: 16, height: 16))
            }
            text("StageComposer.swift", 22, .medium, NSColor(white: 0.75, alpha: 1), at: CGPoint(x: 680, y: H - 42), in: ctx)
            let lines: [(String, NSColor)] = [
                ("final class StageComposer {", NSColor(srgbRed: 0.98, green: 0.47, blue: 0.62, alpha: 1)),
                ("    let rect: CGRect", NSColor(srgbRed: 0.85, green: 0.86, blue: 0.9, alpha: 1)),
                ("    private var panelCache: PanelArt?", NSColor(srgbRed: 0.85, green: 0.86, blue: 0.9, alpha: 1)),
                ("", .white),
                ("    func backdrop(_ f: Inputs) -> CIImage {", NSColor(srgbRed: 0.45, green: 0.78, blue: 1.0, alpha: 1)),
                ("        updateAspect(from: f.content, dt: f.dt)", NSColor(srgbRed: 0.85, green: 0.86, blue: 0.9, alpha: 1)),
                ("        switch f.layout.arrangement {", NSColor(srgbRed: 0.98, green: 0.47, blue: 0.62, alpha: 1)),
                ("        case .floatingPanel: return stage(f)", NSColor(srgbRed: 0.85, green: 0.86, blue: 0.9, alpha: 1)),
                ("        case .presenter: return filled(f)", NSColor(srgbRed: 0.85, green: 0.86, blue: 0.9, alpha: 1)),
                ("        }", NSColor(srgbRed: 0.85, green: 0.86, blue: 0.9, alpha: 1)),
                ("    }", NSColor(srgbRed: 0.85, green: 0.86, blue: 0.9, alpha: 1)),
                ("", .white),
                ("    // The shadow, deeper and further while held.", NSColor(srgbRed: 0.5, green: 0.55, blue: 0.62, alpha: 1)),
                ("    let lift = f.live.panelLift", NSColor(srgbRed: 0.85, green: 0.86, blue: 0.9, alpha: 1)),
                ("    let spring = Spring(omega: 10.5, zeta: 0.8)", NSColor(srgbRed: 0.99, green: 0.78, blue: 0.45, alpha: 1)),
                ("}", NSColor(srgbRed: 0.85, green: 0.86, blue: 0.9, alpha: 1)),
            ]
            for (k, line) in lines.enumerated() {
                let y = H - 120 - CGFloat(k) * 50
                mono(String(format: "%3d", k + 1), 26, NSColor(white: 0.38, alpha: 1), at: CGPoint(x: 26, y: y), in: ctx)
                mono(line.0, 28, line.1, at: CGPoint(x: 110, y: y), in: ctx)
            }
        case .tallDocument:
            ctx.setFillColor(NSColor(srgbRed: 0.93, green: 0.93, blue: 0.92, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 60, y: 40, width: W - 120, height: H - 80))
            text("Meeting notes", 54, .bold, NSColor(white: 0.1, alpha: 1), at: CGPoint(x: 110, y: H - 170), in: ctx)
            text("Thursday, design review", 28, .regular, NSColor(white: 0.45, alpha: 1), at: CGPoint(x: 112, y: H - 220), in: ctx)
            for k in 0..<22 {
                let y = H - 300 - CGFloat(k) * 46
                let width = k % 6 == 5 ? 380.0 : 660.0 - Double(k % 3) * 40
                ctx.setFillColor(NSColor(white: k % 6 == 0 ? 0.25 : 0.72, alpha: 1).cgColor)
                ctx.addPath(CGPath(roundedRect: CGRect(x: 110, y: y, width: width, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil))
                ctx.fillPath()
            }
        case .wideDashboard:
            ctx.setFillColor(NSColor(srgbRed: 0.07, green: 0.08, blue: 0.1, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            text("Live traffic", 48, .bold, NSColor(white: 0.95, alpha: 1), at: CGPoint(x: 70, y: H - 120), in: ctx)
            for panel in 0..<4 {
                let x = 60 + CGFloat(panel) * 620
                ctx.setFillColor(NSColor(srgbRed: 0.12, green: 0.13, blue: 0.17, alpha: 1).cgColor)
                ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 80, width: 580, height: 780), cornerWidth: 24, cornerHeight: 24, transform: nil))
                ctx.fillPath()
                let colour = [NSColor.systemTeal, .systemPink, .systemOrange, .systemIndigo][panel]
                ctx.setStrokeColor(colour.cgColor)
                ctx.setLineWidth(6)
                ctx.move(to: CGPoint(x: x + 30, y: 300))
                for k in 1..<12 {
                    let y = 300 + 280 * (0.5 + 0.5 * sin(Double(k) * 0.9 + Double(panel)))
                    ctx.addLine(to: CGPoint(x: x + 30 + CGFloat(k) * 47, y: y))
                }
                ctx.strokePath()
                text(["12.4k", "318 ms", "99.98%", "4,812"][panel], 64, .semibold, NSColor(white: 0.95, alpha: 1), at: CGPoint(x: x + 30, y: 720), in: ctx)
            }
        }
        return ctx.makeImage()!
    }
}

/// A shared screen for tests: a picture, a status, and whether it has been told to pause.
final class FakeShareSource: StageContentSource {
    var image: CIImage?
    var buffer: CVPixelBuffer?
    var status: StageContentStatus = .live
    private(set) var paused = false
    var fitsContent: Bool { true }

    init(_ content: StageFixtures.Content?) {
        image = content.map(StageFixtures.image)
    }

    init(buffer: CVPixelBuffer) {
        self.buffer = buffer
    }

    func setPaused(_ paused: Bool) { self.paused = paused }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        if let buffer {
            // Marked as rewritten, as a capture does with a reused buffer, so nothing is served from a cache.
            CostPerFrameTests.freshen(buffer)
            return CIImage(cvPixelBuffer: buffer)
        }
        return image
    }
}

/// A pipeline set up for Present with a fake camera, cutout and screen, run frame by frame on its own queue.
final class StageRig {
    let pipeline = FramePipeline()
    let source: FakeShareSource
    var scene = SyntheticScene(center: CGPoint(x: 900, y: 400))
    var hands: [HandState] = []
    var withPerson = true
    private(set) var output: CVPixelBuffer?
    private(set) var preview: CGImage?
    private(set) var layouts: [StageLayout] = []
    private(set) var reports: [StageReport] = []
    private var time: Int64 = 0
    private lazy var camera = scene.cameraBuffer()
    private lazy var matte = visionSized ? SyntheticScene.shrunk(scene.matteBuffer()) : scene.matteBuffer()
    /// Hands the pipeline a cutout the size Vision makes (256 by 144) instead of a full-size one, as for measuring cost.
    var visionSized = false
    private lazy var empty = SyntheticScene.emptyMatte()

    init(content: StageFixtures.Content? = .slide, layout: StageLayout, paused: Bool = false, title: String? = "Keynote – Q3 Roadmap",
         kind: BackgroundKind = .display) {
        source = FakeShareSource(content)
        pipeline.matteOverride = { [unowned self] _ in self.withPerson ? self.matte : self.empty }
        pipeline.matteResponsiveness = 1
        pipeline.handsOverride = { [unowned self] in self.hands }
        pipeline.onOutput = { [unowned self] buffer, _ in self.output = buffer }
        pipeline.onPreview = { [unowned self] image in self.preview = image }
        pipeline.onStageLayoutChanged = { [unowned self] l in self.layouts.append(l) }
        pipeline.onStageReport = { [unowned self] r in self.reports.append(r) }
        pipeline.setPreviewEnabled(true)
        pipeline.setBackground(Background(id: UUID(), name: "Share", kind: kind, origin: .imported), source: source)
        pipeline.setStage(layout, paused: paused, title: title)
        pipeline.queue.sync {}
    }

    func rebuildCamera() {
        camera = scene.cameraBuffer()
        matte = scene.matteBuffer()
    }

    /// Runs `frames` frames at 30 a second.
    func run(_ frames: Int = 1) {
        for _ in 0..<frames {
            time += 1
            let t = time
            pipeline.queue.sync { pipeline.process(camera, at: CMTime(value: t, timescale: 30)) }
        }
    }

    var outputImage: CIImage { CIImage(cvPixelBuffer: output!) }

    /// The output with the preview's chrome laid over it at full size, the way the preview shows it (at twice the resolution).
    func previewAtFullSize() -> CIImage {
        let base = outputImage
        guard let canvas = OverlayCanvas(size: CGSize(width: 1280, height: 720), slots: 1) else { return base }
        let ctx = canvas.begin()
        StageOverlay.draw(pipeline.lastOverlay, in: ctx, pixel: 2)
        return canvas.image().composited(over: base)
    }
}

extension SyntheticScene {
    /// A cutout shrunk to the size Vision's balanced quality gives, so its smoothing costs what it does in the app.
    static func shrunk(_ full: CVPixelBuffer) -> CVPixelBuffer {
        var created: CVPixelBuffer?
        CVPixelBufferCreate(nil, 256, 144, kCVPixelFormatType_OneComponent8, [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &created)
        let small = created!
        CVPixelBufferLockBaseAddress(full, .readOnly); CVPixelBufferLockBaseAddress(small, [])
        let src = CVPixelBufferGetBaseAddress(full)!.assumingMemoryBound(to: UInt8.self), dst = CVPixelBufferGetBaseAddress(small)!.assumingMemoryBound(to: UInt8.self)
        let srcRow = CVPixelBufferGetBytesPerRow(full), dstRow = CVPixelBufferGetBytesPerRow(small)
        for y in 0..<144 { for x in 0..<256 { dst[y * dstRow + x] = src[(y * 5) * srcRow + x * 5] } }
        CVPixelBufferUnlockBaseAddress(full, .readOnly); CVPixelBufferUnlockBaseAddress(small, [])
        return small
    }

    /// A cutout with nobody in it.
    static func emptyMatte() -> CVPixelBuffer {
        var created: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1280, 720, kCVPixelFormatType_OneComponent8, [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &created)
        let b = created!
        CVPixelBufferLockBaseAddress(b, [])
        memset(CVPixelBufferGetBaseAddress(b)!, 0, CVPixelBufferGetDataSize(b))
        CVPixelBufferUnlockBaseAddress(b, [])
        return b
    }
}
