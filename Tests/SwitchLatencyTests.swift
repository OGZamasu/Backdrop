import CoreImage
import XCTest

/// How long it takes, from the moment something is chosen, for the picture to change: building it, then its first frames.
/// A choice made in the menu runs on the video queue, so anything slow here freezes the live picture for that long.
final class SwitchLatencyTests: XCTestCase {
    private let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))

    private func ms(_ block: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    func testHowLongEachLensTakesToAppear() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let pipeline = FramePipeline()
        pipeline.setBackground(.off, source: nil)
        pipeline.onOutput = { _, _ in }
        let camera = scene.cameraBuffer()
        func frame() -> Double { ms { pipeline.queue.sync { pipeline.process(camera, at: .zero) } } }
        for _ in 0..<20 { _ = frame() }
        let steady = (0..<10).map { _ in frame() }.reduce(0, +) / 10
        print(String(format: "SWITCH steady frame with no lens: %.0f ms", steady))

        for info in LensCatalog.all {
            var lens: Lens?
            let make = ms { lens = info.make() }
            pipeline.setLens(lens)
            let first = frame()
            let rest = (0..<5).map { _ in frame() }
            print(String(format: "SWITCH %-14@ make %6.0f ms   first frame %6.0f ms   next five %@", info.name as NSString, make, first,
                         rest.map { String(format: "%.0f", $0) }.joined(separator: " ") as NSString))
        }
    }

    func testHowLongEachBackgroundTakesToAppear() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let pipeline = FramePipeline()
        pipeline.setBackground(.off, source: nil)
        pipeline.onOutput = { _, _ in }
        let camera = scene.cameraBuffer()
        func frame() -> Double { ms { pipeline.queue.sync { pipeline.process(camera, at: .zero) } } }
        for _ in 0..<20 { _ = frame() }

        let sources: [(String, () -> (Background, BackgroundSource?))] = [
            ("blur", { (.softBlur, BlurSource(radius: 24)) }),
            ("gradient", { (Background(id: UUID(), name: "g", kind: .gradient(.graphite), origin: .builtIn), GradientSource(preset: .graphite)) }),
            ("pipes", { (Background(id: UUID(), name: "p", kind: .pipes, origin: .builtIn), PipesSource()) }),
            ("maze", { (Background(id: UUID(), name: "m", kind: .maze, origin: .builtIn), MazeSource()) }),
        ]
        for (name, make) in sources {
            var made: (Background, BackgroundSource?)?
            let build = ms { made = make() }
            let config = ms { pipeline.setBackground(made!.0, source: made!.1); pipeline.queue.sync {} }
            let first = frame()
            let rest = (0..<5).map { _ in frame() }
            print(String(format: "SWITCH %-9@ build %6.0f ms   setBackground %6.0f ms   first frame %6.0f ms   next five %@", name as NSString, build, config, first,
                         rest.map { String(format: "%.0f", $0) }.joined(separator: " ") as NSString))
        }
    }
}

/// A source that takes a few frames to produce anything, like a live window starting up.
private final class SlowStartSource: BackgroundSource {
    var readyAfter: Int
    private var asked = 0
    init(readyAfter: Int) { self.readyAfter = readyAfter }
    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        asked += 1
        return asked > readyAfter ? CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: camera.extent) : nil
    }
}

final class SwitchFeedbackTests: XCTestCase {
    private let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))

    private func makePipeline() -> (FramePipeline, () -> Void, () -> [Int]) {
        let pipeline = FramePipeline()
        pipeline.matteOverride = { [scene] _ in scene.matteBuffer() }
        pipeline.setBackground(.off, source: nil)
        pipeline.onOutput = { _, _ in }
        var applied: [Int] = []
        pipeline.onApplied = { applied.append($0) }
        let camera = scene.cameraBuffer()
        return (pipeline, { pipeline.queue.sync { pipeline.process(camera, at: .zero) } }, { pipeline.queue.sync { applied } })
    }

    func testAChangeIsReportedOnceItsPictureHasGoneOut() {
        let (pipeline, frame, applied) = makePipeline()
        frame()
        pipeline.setLens(ProbeLens(needs: [], grid: false), change: 1)
        frame()
        XCTAssertEqual(applied(), [], "not on the first frame: it takes a couple to be sure")
        frame()
        XCTAssertEqual(applied(), [1])
        frame(); frame()
        XCTAssertEqual(applied(), [1], "reported once")
    }

    func testABackgroundStillWarmingUpIsNotReportedUntilItAppears() {
        let (pipeline, frame, applied) = makePipeline()
        let slow = SlowStartSource(readyAfter: 6)
        pipeline.setBackground(Background(id: UUID(), name: "w", kind: .display, origin: .builtIn), source: slow, change: 7)
        for _ in 0..<6 { frame() }
        XCTAssertEqual(applied(), [], "all this time the dark placeholder has been showing")
        for _ in 0..<3 { frame() }
        XCTAssertEqual(applied(), [7], "reported once the source delivers")
    }

    func testTheLatestChangeWins() {
        let (pipeline, frame, applied) = makePipeline()
        pipeline.setLens(ProbeLens(needs: [], grid: false), change: 1)
        pipeline.setLens(nil, change: 2)
        for _ in 0..<4 { frame() }
        XCTAssertEqual(applied(), [2], "the first change was replaced before any frame, so only the second is heard of")
    }

    func testChangesMadeWithoutATokenAreSilent() {
        let (pipeline, frame, applied) = makePipeline()
        pipeline.setLens(ProbeLens(needs: [], grid: false))
        for _ in 0..<4 { frame() }
        XCTAssertEqual(applied(), [])
    }
}
