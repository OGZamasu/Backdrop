import CoreImage
import CoreMedia
import XCTest

/// A backdrop that is one flat colour, so what shows through where there is no person is unmistakable.
private final class SolidSource: BackgroundSource {
    let colour: CIColor
    init(_ colour: CIColor) { self.colour = colour }
    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? { CIImage(color: colour).cropped(to: camera.extent) }
}

/// Where the time went: when each cutout and each lens render started and ended.
private final class IntervalLog {
    var cutouts: [ClosedRange<Double>] = []
    var finishes: [ClosedRange<Double>] = []
}

/// A lens that takes a fixed time to draw and says when it did.
private final class IntervalLens: Lens {
    let needs: LensNeeds = []
    let seconds: Double
    let report: (Double, Double) -> Void
    init(seconds: Double, report: @escaping (Double, Double) -> Void) { self.seconds = seconds; self.report = report }
    func render(_ input: LensInput) -> CIImage {
        let start = CFAbsoluteTimeGetCurrent()
        Thread.sleep(forTimeInterval: seconds)
        report(start, CFAbsoluteTimeGetCurrent())
        return input.composed
    }
}

final class CutoutOverlapTests: XCTestCase {
    private let green = CIColor(red: 0, green: 1, blue: 0)
    private func greenBackdrop() -> (Background, BackgroundSource) {
        (Background(id: UUID(), name: "green", kind: .gradient(.graphite), origin: .builtIn), SolidSource(green))
    }

    /// Two camera frames with the person far to the left and far to the right, and the cutout that belongs to each.
    private struct Frames {
        let cameras: [CVPixelBuffer]
        let mattes: [UnsafeMutableRawPointer: CVPixelBuffer]
        let positions: [Double]
        init() {
            positions = [300, 980]
            var cameras: [CVPixelBuffer] = [], mattes: [UnsafeMutableRawPointer: CVPixelBuffer] = [:]
            for x in positions {
                let scene = SyntheticScene(center: CGPoint(x: x, y: 420))
                let camera = scene.cameraBuffer()
                cameras.append(camera)
                mattes[Unmanaged.passUnretained(camera).toOpaque()] = scene.matteBuffer()
            }
            self.cameras = cameras
            self.mattes = mattes
        }
        func matte(for camera: CVPixelBuffer) -> CVPixelBuffer? { mattes[Unmanaged.passUnretained(camera).toOpaque()] }
    }

    // MARK: Every frame gets its own cutout

    func testEveryFrameIsCompositedWithTheCutoutMadeFromThatFrame() {
        let frames = Frames()
        let pipeline = FramePipeline()
        let (backdrop, source) = greenBackdrop()
        pipeline.setBackground(backdrop, source: source)
        pipeline.matteResponsiveness = 1                   // the person jumps across the picture between frames; don't blend them
        pipeline.matteOverride = { camera in
            Thread.sleep(forTimeInterval: 0.025)           // a cutout that takes a while, so frames queue up behind it
            return frames.matte(for: camera)
        }

        let lock = NSLock()
        var results: [(frame: Int, onPerson: RGB, elsewhere: RGB)] = []
        pipeline.onOutput = { buffer, time in
            let k = Int(time.value)
            let mine = frames.positions[k % 2], other = frames.positions[(k + 1) % 2]
            // Low on the screen, where the shirt is: blue on the person, backdrop green anywhere else.
            let result = (k, TestSupport.pixel(buffer, x: Int(mine), y: 720 - 170), TestSupport.pixel(buffer, x: Int(other), y: 720 - 170))
            lock.withLock { results.append(result) }
        }

        for k in 0..<30 {
            pipeline.queue.async { pipeline.submit(frames.cameras[k % 2], at: CMTime(value: CMTimeValue(k), timescale: 30)) }
            Thread.sleep(forTimeInterval: 0.012)
        }
        pipeline.queue.sync {}
        Thread.sleep(forTimeInterval: 0.3)
        pipeline.queue.sync {}

        let seen = lock.withLock { results }
        XCTAssertGreaterThanOrEqual(seen.count, 3, "frames still come out")
        for r in seen {
            XCTAssertGreaterThan(r.onPerson.b, 150, "frame \(r.frame): the person should be blue, got \(r.onPerson)")
            XCTAssertLessThan(r.onPerson.g, 140, "frame \(r.frame): and not the backdrop")
            XCTAssertGreaterThan(r.elsewhere.g, 220, "frame \(r.frame): where the person isn't should be the green backdrop, got \(r.elsewhere)")
        }
        XCTAssertEqual(seen.map(\.frame), seen.map(\.frame).sorted(), "frames come out in the order they were taken")
    }

    func testTheNewestFrameIsTheOneThatIsKept() {
        let frames = Frames()
        let pipeline = FramePipeline()
        let (backdrop, source) = greenBackdrop()
        pipeline.setBackground(backdrop, source: source)
        pipeline.matteResponsiveness = 1
        pipeline.matteOverride = { camera in Thread.sleep(forTimeInterval: 0.06); return frames.matte(for: camera) }
        let lock = NSLock()
        var out: [Int] = []
        pipeline.onOutput = { _, time in lock.withLock { out.append(Int(time.value)) } }

        for k in 0..<10 { pipeline.queue.async { pipeline.submit(frames.cameras[k % 2], at: CMTime(value: CMTimeValue(k), timescale: 30)) } }
        // Wait for the last one rather than for a fixed time, so a busy machine only makes this slower, not wrong.
        let deadline = Date().addingTimeInterval(10)
        while lock.withLock({ out.last }) != 9, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        pipeline.queue.sync {}
        let seen = lock.withLock { out }
        XCTAssertEqual(seen.first, 0, "the first one starts at once")
        XCTAssertEqual(seen.last, 9, "and the newest, not an old one, is what follows while it works")
        XCTAssertLessThanOrEqual(seen.count, 4, "nearly everything between was skipped: \(seen)")
    }

    // MARK: Overlap

    func testTheNextCutoutRunsWhileThisFrameIsBeingFinished() {
        let frames = Frames()
        let lock = NSLock()
        let log = IntervalLog()

        func run(overlapped: Bool) -> (cutouts: [ClosedRange<Double>], finishes: [ClosedRange<Double>]) {
            log.cutouts = []; log.finishes = []
            let pipeline = FramePipeline()
            let (backdrop, source) = greenBackdrop()
            pipeline.setBackground(backdrop, source: source)
            pipeline.setLens(IntervalLens(seconds: 0.03) { start, end in lock.withLock { log.finishes.append(start...end) } })
            pipeline.matteOverride = { camera in
                let start = CFAbsoluteTimeGetCurrent()
                Thread.sleep(forTimeInterval: 0.04)
                lock.withLock { log.cutouts.append(start...CFAbsoluteTimeGetCurrent()) }
                return frames.matte(for: camera)
            }
            pipeline.onOutput = { _, _ in }
            pipeline.queue.sync {}
            for k in 0..<12 {
                let time = CMTime(value: CMTimeValue(k), timescale: 30), camera = frames.cameras[k % 2]
                if overlapped { pipeline.queue.async { pipeline.submit(camera, at: time) } } else { pipeline.queue.async { pipeline.process(camera, at: time) } }
                Thread.sleep(forTimeInterval: 0.01)
            }
            Thread.sleep(forTimeInterval: 0.6)
            pipeline.queue.sync {}
            return lock.withLock { (log.cutouts, log.finishes) }
        }

        func overlap(_ a: ClosedRange<Double>, _ b: ClosedRange<Double>) -> Double { max(0, min(a.upperBound, b.upperBound) - max(a.lowerBound, b.lowerBound)) }
        func mostOverlap(_ r: (cutouts: [ClosedRange<Double>], finishes: [ClosedRange<Double>])) -> Double {
            r.finishes.flatMap { f in r.cutouts.map { overlap(f, $0) } }.max() ?? 0
        }

        let together = run(overlapped: true)
        XCTAssertGreaterThan(mostOverlap(together), 0.015, "a cutout ran while a frame was being finished (the most they overlapped: \(mostOverlap(together)) s)")
        let apart = run(overlapped: false)
        XCTAssertLessThan(mostOverlap(apart), 0.002, "the old, one-after-the-other way never does")
    }

    // MARK: Safety

    func testAFrameThatNeedsNoCutoutIsMadeAtOnceAndNeverAsksForOne() {
        let pipeline = FramePipeline()
        pipeline.setBackground(.off, source: nil)
        var asked = 0
        pipeline.matteOverride = { _ in asked += 1; return nil }
        var outputs = 0
        pipeline.onOutput = { _, _ in outputs += 1 }
        pipeline.queue.sync { pipeline.submit(SyntheticScene().cameraBuffer(), at: .zero) }
        XCTAssertEqual(outputs, 1, "straight through, on the spot")
        XCTAssertEqual(asked, 0)
    }

    func testStoppingThrowsAwayACutoutThatWasStillRunning() {
        let frames = Frames()
        let pipeline = FramePipeline()
        let (backdrop, source) = greenBackdrop()
        pipeline.setBackground(backdrop, source: source)
        pipeline.matteOverride = { camera in Thread.sleep(forTimeInterval: 0.15); return frames.matte(for: camera) }
        let lock = NSLock()
        var outputs = 0
        pipeline.onOutput = { _, _ in lock.withLock { outputs += 1 } }

        pipeline.queue.async { pipeline.submit(frames.cameras[0], at: .zero) }
        Thread.sleep(forTimeInterval: 0.05)
        pipeline.stop()
        Thread.sleep(forTimeInterval: 0.3)
        pipeline.queue.sync {}
        XCTAssertEqual(lock.withLock { outputs }, 0, "nothing comes out after stop")

        // And it picks up again afterwards.
        pipeline.queue.async { pipeline.submit(frames.cameras[1], at: .zero) }
        Thread.sleep(forTimeInterval: 0.4)
        pipeline.queue.sync {}
        XCTAssertEqual(lock.withLock { outputs }, 1)
    }

    func testChangingQualityWhileCutoutsAreRunningIsSafe() {
        let segmenter = PersonSegmenter(quality: .fast)
        let camera = SyntheticScene().cameraBuffer()
        let done = expectation(description: "cutouts")
        DispatchQueue.global().async {
            for _ in 0..<12 { _ = segmenter.mask(for: camera) }
            done.fulfill()
        }
        for i in 0..<300 { segmenter.quality = i % 2 == 0 ? .balanced : .fast; usleep(500) }
        wait(for: [done], timeout: 30)
        XCTAssertNotNil(segmenter.mask(for: camera))
    }
}

/// A source that counts how often it is started and stopped.
private final class CountingSource: BackgroundSource {
    private(set) var starts = 0, stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? { CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: camera.extent) }
}

final class PipelineOrderAndRestartTests: XCTestCase {
    private let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))

    func testFramesNeverComeOutOfOrderWhenTheBackgroundIsSwitchedOffDuringACutout() {
        let pipeline = FramePipeline()
        let gradient = Background(id: UUID(), name: "g", kind: .gradient(.graphite), origin: .builtIn)
        pipeline.setBackground(gradient, source: GradientSource(preset: .graphite))
        pipeline.matteOverride = { [scene] _ in Thread.sleep(forTimeInterval: 0.12); return scene.matteBuffer() }
        let lock = NSLock()
        var out: [Int] = []
        pipeline.onOutput = { _, time in lock.withLock { out.append(Int(time.value)) } }
        let camera = scene.cameraBuffer()
        func frame(_ k: Int) { pipeline.queue.async { pipeline.submit(camera, at: CMTime(value: CMTimeValue(k), timescale: 30)) } }

        frame(1)                                          // its cutout takes a while
        Thread.sleep(forTimeInterval: 0.03)
        frame(2)                                          // waits behind it
        pipeline.setBackground(.off, source: nil)         // no cutout is needed from now on
        frame(3)                                          // made at once
        Thread.sleep(forTimeInterval: 0.4)
        pipeline.queue.sync {}
        let seen = lock.withLock { out }
        XCTAssertEqual(seen, seen.sorted(), "in order: \(seen)")
        XCTAssertEqual(seen.last, 3, "and the newest is what ended up on screen")
        XCTAssertFalse(seen.contains(2), "a frame that was waiting for a cutout nobody needs any more is dropped")
    }

    func testTurningTheCameraOffAndOnAgainRestartsTheBackgroundsSource() {
        let pipeline = FramePipeline()
        let source = CountingSource()
        pipeline.setBackground(Background(id: UUID(), name: "v", kind: .display, origin: .builtIn), source: source)
        pipeline.queue.sync {}
        XCTAssertEqual(source.starts, 1)

        pipeline.stop(); pipeline.queue.sync {}
        XCTAssertEqual(source.stops, 1, "camera off pauses it")
        pipeline.markStarted(); pipeline.queue.sync {}
        XCTAssertEqual(source.starts, 2, "camera on starts it again, or a video would stay frozen")
        pipeline.markStarted(); pipeline.queue.sync {}
        XCTAssertEqual(source.starts, 2, "and a source that is already running isn't started twice")
    }

    func testTheClockForFrameOrderRestartsWithTheCamera() {
        let pipeline = FramePipeline()
        pipeline.setBackground(.off, source: nil)
        var out: [Int] = []
        pipeline.onOutput = { _, time in out.append(Int(time.value)) }
        let camera = scene.cameraBuffer()
        pipeline.queue.sync { pipeline.submit(camera, at: CMTime(value: 500, timescale: 30)) }
        pipeline.stop(); pipeline.queue.sync {}
        pipeline.markStarted(); pipeline.queue.sync {}
        pipeline.queue.sync { pipeline.submit(camera, at: CMTime(value: 3, timescale: 30)) }     // a new session's timestamps start low
        XCTAssertEqual(out, [500, 3], "a restarted camera isn't mistaken for old frames")
    }
}
