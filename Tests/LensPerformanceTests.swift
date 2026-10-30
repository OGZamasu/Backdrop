import CoreImage
import XCTest

/// Whole-pipeline cost per lens: real Vision segmentation, the compositor, the lens, and the final render, frame after frame.
/// What matters is what a lens adds to the frame the app already makes (Vision and the compositor are most of it): a frame
/// at 30 fps has 33 ms, and the camera, the hand-off to the virtual camera and the rest of the Mac need room too.
/// These run unoptimised, so they overstate the CPU-side cost of the lenses themselves.
final class LensPerformanceTests: XCTestCase {
    private let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))

    private func measure(lens: Lens?, background: Bool, frames: Int = 45) -> (mean: Double, worst: Double) {
        let pipeline = FramePipeline()
        if background {
            let gradient = Background(id: UUID(), name: "g", kind: .gradient(.graphite), origin: .builtIn)
            pipeline.setBackground(gradient, source: GradientSource(preset: .graphite))
        } else {
            pipeline.setBackground(.off, source: nil)
        }
        pipeline.setLens(lens)
        pipeline.onOutput = { _, _ in }
        let camera = scene.cameraBuffer()
        var durations: [Double] = []
        for i in 0..<(frames + 15) {
            let started = CFAbsoluteTimeGetCurrent()
            pipeline.queue.sync { pipeline.process(camera, at: .zero) }
            if i >= 15 { durations.append((CFAbsoluteTimeGetCurrent() - started) * 1000) }     // the first few warm things up
        }
        return (durations.reduce(0, +) / Double(durations.count), durations.max() ?? 0)
    }

    func testEveryLensFitsInTheFrameBudgetOnTopOfTheBaseline() throws {
        // Two minutes of real Vision work, so it only runs when asked: TEST_RUNNER_BACKDROP_PERF=1 xcodebuild test ...
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let baseline = measure(lens: nil, background: true)
        print(String(format: "PERF %-14@ mean %5.1f ms  worst %5.1f ms", "(no lens)" as NSString, baseline.mean, baseline.worst))
        var heaviest = ("", 0.0)
        for info in LensCatalog.all {
            let r = measure(lens: info.make(), background: true)
            print(String(format: "PERF %-14@ mean %5.1f ms  worst %5.1f ms   (+%.1f)", info.name as NSString, r.mean, r.worst, r.mean - baseline.mean))
            if r.mean > heaviest.1 { heaviest = (info.name, r.mean) }
            XCTAssertLessThan(r.mean - baseline.mean, 9, "\(info.name) adds too much to every frame")
        }
        print("PERF heaviest: \(heaviest.0) at \(String(format: "%.1f", heaviest.1)) ms")
    }
}

/// Where a frame's time goes: which stages run on the CPU, which wait on the neural engine or GPU, and how much of the
/// wall clock the CPU is actually busy for.
final class FrameBreakdownTests: XCTestCase {
    private func cpuSeconds() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
    }

    func testWhereTheFrameTimeGoes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))
        let camera = scene.cameraBuffer()
        let cameraImage = CIImage(cvPixelBuffer: camera)
        let compositor = Compositor()
        let segmenter = PersonSegmenter()
        let smoother = MaskSmoother()
        let grid = MatteGrid(outputSize: compositor.outputSize)
        let background = GradientSource(preset: .graphite).frame(at: 0, camera: cameraImage)!
        let output = compositor.makeOutputBuffer()!

        var vision = 0.0, smooth = 0.0, composite = 0.0, readback = 0.0
        let frames = 120
        func now() -> Double { CFAbsoluteTimeGetCurrent() }
        for i in 0..<(frames + 20) {
            if i == 20 { vision = 0; smooth = 0; composite = 0; readback = 0 }
            var t = now()
            let mask = segmenter.mask(for: camera)!
            vision += now() - t
            t = now()
            let matteBuffer = smoother.smooth(mask)
            smooth += now() - t
            t = now()
            let refined = compositor.refinedMatte(camera: cameraImage, mask: Compositor.matte(from: matteBuffer))
            let image = compositor.composite(camera: cameraImage, matte: refined, background: compositor.prepareBackground(background, fits: false, parallax: nil))
            compositor.render(image, into: output)
            composite += now() - t
            t = now()
            grid.update(from: refined, rect: compositor.rect, context: compositor.context)
            readback += now() - t
        }
        // The same loop again, timing the whole and the CPU's share of it.
        let wallStart = now(), cpuStart = cpuSeconds()
        for _ in 0..<frames {
            let mask = segmenter.mask(for: camera)!
            let matteBuffer = smoother.smooth(mask)
            let refined = compositor.refinedMatte(camera: cameraImage, mask: Compositor.matte(from: matteBuffer))
            compositor.render(compositor.composite(camera: cameraImage, matte: refined, background: compositor.prepareBackground(background, fits: false, parallax: nil)), into: output)
        }
        let wall = now() - wallStart, cpu = cpuSeconds() - cpuStart
        let n = Double(frames)
        print(String(format: "BREAKDOWN per frame: Vision cutout %.1f ms | smoothing %.1f ms | composite+render %.1f ms | silhouette readback %.1f ms",
                     vision / n * 1000, smooth / n * 1000, composite / n * 1000, readback / n * 1000))
        print(String(format: "BREAKDOWN over %d frames: %.1f ms wall per frame, %.1f ms of CPU time per frame (%.0f%% of one core)",
                     frames, wall / n * 1000, cpu / n * 1000, cpu / wall * 100))
    }
}

final class CutoutCostTests: XCTestCase {
    func testCutoutCostByQualityAndInputSize() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))
        let full = scene.cameraBuffer()
        let context = CIContext()
        // A half-size copy, as if the camera were asked for 640x360.
        var half: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &half)
        context.render(CIImage(cvPixelBuffer: full).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)), to: half!)

        for (name, buffer) in [("1280x720", full), ("640x360", half!)] {
            for quality in PersonSegmenter.Quality.allCases {
                let segmenter = PersonSegmenter(quality: quality)
                for _ in 0..<15 { _ = segmenter.mask(for: buffer) }
                let start = CFAbsoluteTimeGetCurrent()
                var size = ""
                for _ in 0..<60 {
                    if let mask = segmenter.mask(for: buffer) { size = "\(CVPixelBufferGetWidth(mask))x\(CVPixelBufferGetHeight(mask))" }
                }
                print(String(format: "CUTOUT input %@ %-8@ %.1f ms per frame (matte %@)", name as NSString, quality.rawValue as NSString,
                             (CFAbsoluteTimeGetCurrent() - start) / 60 * 1000, size as NSString))
            }
        }
    }
}

/// How many frames a whole pipeline can make a second with the real cutout, one stage after another against alongside.
final class ThroughputTests: XCTestCase {
    func testFramesPerSecondWithAndWithoutOverlap() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let camera = SyntheticScene(center: CGPoint(x: 640, y: 420)).cameraBuffer()
        let cases: [(String, () -> Lens?)] = [("no lens", { nil }), ("Breakout", { LensCatalog.info(for: "breakout")!.make() }),
                                              ("Aura", { LensCatalog.info(for: "aura")!.make() })]
        for (name, makeLens) in cases {
            for overlapped in [false, true] {
                let pipeline = FramePipeline()
                let gradient = Background(id: UUID(), name: "g", kind: .gradient(.graphite), origin: .builtIn)
                pipeline.setBackground(gradient, source: GradientSource(preset: .graphite))
                pipeline.setLens(makeLens())
                let lock = NSLock()
                var count = 0
                pipeline.onOutput = { _, _ in lock.withLock { count += 1 } }
                func feed(seconds: Double) {
                    let start = CFAbsoluteTimeGetCurrent()
                    var busy = false
                    while CFAbsoluteTimeGetCurrent() - start < seconds {
                        if overlapped {
                            pipeline.queue.async { pipeline.submit(camera, at: .zero) }
                            Thread.sleep(forTimeInterval: 0.008)
                        } else {
                            // The old way: a camera that drops frames while the previous one is still being made.
                            if !lock.withLock({ busy }) {
                                lock.withLock { busy = true }
                                pipeline.queue.async { pipeline.process(camera, at: .zero); lock.withLock { busy = false } }
                            }
                            Thread.sleep(forTimeInterval: 0.002)
                        }
                    }
                }
                feed(seconds: 1.5)                                   // warm up
                pipeline.queue.sync {}
                let before = lock.withLock { count }
                let start = CFAbsoluteTimeGetCurrent()
                feed(seconds: 4)
                let made = lock.withLock { count } - before
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                print(String(format: "THROUGHPUT %-9@ %@ %5.1f fps", name as NSString, (overlapped ? "alongside     " : "one after other") as NSString, Double(made) / elapsed))
                pipeline.queue.sync {}
            }
        }
    }
}
