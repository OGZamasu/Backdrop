import CoreImage
import CoreMedia
import XCTest

/// A backdrop that is one flat colour, so what shows through where there is no person is unmistakable.
private final class SolidSource: BackgroundSource {
    let colour: CIColor
    init(_ colour: CIColor) { self.colour = colour }
    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? { CIImage(color: colour).cropped(to: camera.extent) }
}

/// A lens that takes a fixed time to draw, standing in for a heavy one.
private final class SlowLens: Lens {
    let needs: LensNeeds = []
    let seconds: Double
    init(seconds: Double) { self.seconds = seconds }
    func render(_ input: LensInput) -> CIImage {
        Thread.sleep(forTimeInterval: seconds)
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
        XCTAssertGreaterThan(seen.count, 8, "frames still come out")
        XCTAssertLessThan(seen.count, 30, "and a slow cutout does skip some")
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
        Thread.sleep(forTimeInterval: 0.5)
        pipeline.queue.sync {}
        let seen = lock.withLock { out }
        XCTAssertEqual(seen.first, 0, "the first one starts at once")
        XCTAssertEqual(seen.last, 9, "and the newest, not an old one, is what follows while it works")
        XCTAssertEqual(seen.count, 2, "everything between was skipped: \(seen)")
    }

    // MARK: Overlap

    func testTheNextCutoutRunsWhileThisFrameIsBeingFinished() {
        let frames = Frames()
        let cutout = 0.040, lens = 0.030, window = 2.0

        /// Frames made in a fixed stretch of time, from a camera that offers one every 10 ms.
        func framesMade(overlapped: Bool) -> Int {
            let pipeline = FramePipeline()
            let (backdrop, source) = greenBackdrop()
            pipeline.setBackground(backdrop, source: source)
            pipeline.setLens(SlowLens(seconds: lens))
            pipeline.matteOverride = { camera in Thread.sleep(forTimeInterval: cutout); return frames.matte(for: camera) }
            let lock = NSLock()
            var done: [Double] = []
            var busy = false
            pipeline.onOutput = { _, _ in lock.withLock { done.append(CFAbsoluteTimeGetCurrent()) } }
            pipeline.queue.sync {}

            let start = CFAbsoluteTimeGetCurrent()
            var k = 0
            while CFAbsoluteTimeGetCurrent() - start < window {
                let time = CMTime(value: CMTimeValue(k), timescale: 30), camera = frames.cameras[k % 2]
                if overlapped {
                    pipeline.queue.async { pipeline.submit(camera, at: time) }
                } else if !lock.withLock({ busy }) {
                    // The old way: cut out and finish one after the other, dropping frames that arrive meanwhile.
                    lock.withLock { busy = true }
                    pipeline.queue.async { pipeline.process(camera, at: time); lock.withLock { busy = false } }
                }
                k += 1
                Thread.sleep(forTimeInterval: 0.010)
            }
            let made = lock.withLock { done.filter { $0 <= start + window }.count }
            pipeline.queue.sync {}
            return made
        }

        let one = framesMade(overlapped: false), two = framesMade(overlapped: true)
        print("OVERLAP frames made in \(window) s: one after the other \(one), overlapped \(two)")
        XCTAssertGreaterThan(Double(two), Double(one) * 1.4, "doing the cutout alongside the finishing should get clearly more frames through (\(two) vs \(one))")
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
