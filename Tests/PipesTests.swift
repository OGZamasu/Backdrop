import AppKit
import CoreImage
import SceneKit
import XCTest

final class PipeGrowthTests: XCTestCase {
    private let dims = PipeGrowth.wideDimensions

    private func run(seed: UInt64, steps: Int, size: Int? = nil) -> [PipeGrowth.Event] {
        var growth = size.map { PipeGrowth(size: $0, seed: seed) } ?? PipeGrowth(seed: seed)
        return (0..<steps).flatMap { _ in growth.step() }
    }

    private func inside(_ cell: PipeGrowth.Cell) -> Bool {
        (0..<dims.x).contains(cell.x) && (0..<dims.y).contains(cell.y) && (0..<dims.z).contains(cell.z)
    }

    func testTheBoxIsWideLikeTheFrame() {
        let aspect = Double(dims.x) / Double(dims.y)
        XCTAssertEqual(aspect, 16.0 / 9.0, accuracy: 0.2, "the volume should be shaped like a widescreen frame, not a cube")
        XCTAssertGreaterThan(dims.x, dims.z * 3, "and shallow, so the camera can fill the frame with it")
    }

    func testPipesStayInsideTheBoxAndMoveOneCellAtATime() {
        for seed in 1...5 as ClosedRange<UInt64> {
            for case .extend(let from, let to, _, _, _) in run(seed: seed, steps: 3000) {
                let delta = to &- from
                XCTAssertEqual(abs(delta.x) + abs(delta.y) + abs(delta.z), 1, "seed \(seed): \(from) → \(to) isn't a single step")
                XCTAssertTrue(inside(to), "seed \(seed): \(to) is outside the box")
            }
        }
    }

    func testNoCellIsEverUsedTwiceBetweenClears() {
        for seed in 1...5 as ClosedRange<UInt64> {
            var used = Set<PipeGrowth.Cell>()
            for event in run(seed: seed, steps: 4000) {
                switch event {
                case .clear: used.removeAll()
                case .start(let cell, _, _): XCTAssertTrue(used.insert(cell).inserted, "seed \(seed): started on a used cell \(cell)")
                case .extend(_, let to, _, _, _): XCTAssertTrue(used.insert(to).inserted, "seed \(seed): ran into a used cell \(to)")
                case .end: break
                }
            }
        }
    }

    func testPipesNeverDoubleBackAndJointsMarkTurns() {
        var headings: [Int: PipeGrowth.Cell] = [:]
        for event in run(seed: 7, steps: 4000) {
            switch event {
            case .start(_, _, let pipe): headings[pipe] = nil
            case .extend(let from, let to, _, let turned, let pipe):
                let direction = to &- from
                if let previous = headings[pipe] {
                    XCTAssertNotEqual(direction, PipeGrowth.Cell(repeating: 0) &- previous, "pipe \(pipe) reversed onto itself")
                    XCTAssertEqual(turned, direction != previous, "the joint flag should match whether the pipe turned")
                }
                headings[pipe] = direction
            default: break
            }
        }
    }

    func testEveryPipeStartsGrowsAndEndsInOrder() {
        var open = Set<Int>()
        var most = 0
        for event in run(seed: 3, steps: 3000) {
            switch event {
            case .start(_, _, let pipe): XCTAssertTrue(open.insert(pipe).inserted, "pipe \(pipe) started twice"); most = max(most, open.count)
            case .extend(_, _, _, _, let pipe): XCTAssertTrue(open.contains(pipe), "pipe \(pipe) grew without starting")
            case .end(_, _, let pipe): XCTAssertNotNil(open.remove(pipe), "pipe \(pipe) ended without starting")
            case .clear: XCTAssertTrue(open.isEmpty, "cleared the box while pipes were still growing")
            }
        }
        XCTAssertEqual(most, 3, "several pipes should grow at once, to fill a wide frame quickly")
    }

    func testPipesSpreadAcrossTheWholeWidthAndHeight() {
        var low = PipeGrowth.Cell(repeating: .max), high = PipeGrowth.Cell(repeating: .min)
        for event in run(seed: 21, steps: 1500) {
            if case .extend(_, let to, _, _, _) = event { low = pointwiseMin(low, to); high = pointwiseMax(high, to) }
        }
        XCTAssertLessThanOrEqual(low.x, 2, "pipes should reach the left edge")
        XCTAssertGreaterThanOrEqual(high.x, dims.x - 3, "and the right edge")
        XCTAssertLessThanOrEqual(low.y, 1, "and the bottom")
        XCTAssertGreaterThanOrEqual(high.y, dims.y - 2, "and the top")
    }

    func testTheBoxClearsAndStartsOverAndTurnsHappen() {
        let events = run(seed: 11, steps: 6000)
        XCTAssertTrue(events.contains(.clear), "it should wipe and restart rather than fill up forever")
        XCTAssertTrue(events.contains { if case .extend(_, _, _, true, _) = $0 { return true } else { return false } }, "pipes should turn")
        let colors = Set(events.compactMap { event -> Int? in if case .start(_, let c, _) = event { return c } else { return nil } })
        XCTAssertGreaterThan(colors.count, 3, "pipes should come in a mix of colours")
    }

    func testSameSeedGivesTheSamePipes() {
        XCTAssertEqual(run(seed: 42, steps: 500), run(seed: 42, steps: 500))
        XCTAssertNotEqual(run(seed: 42, steps: 500), run(seed: 43, steps: 500))
    }

    func testAPipeThatCannotMoveEndsInsteadOfHanging() {
        // A 2×2×2 box fills almost at once, so pipes get boxed in constantly.
        var growth = PipeGrowth(size: 2, maxSegments: 6, seed: 9)
        let events = (0..<500).flatMap { _ in growth.step() }
        XCTAssertTrue(events.contains { if case .end = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains(.clear))
    }
}

final class PipesRenderingTests: XCTestCase {
    private let ciContext = CIContext()

    /// A red ball in the upper half of the frame, lit flat so only position matters.
    private func upperBallScene() -> (SCNScene, SCNNode) {
        let scene = SCNScene()
        scene.background.contents = NSColor.black
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.red
        let sphere = SCNSphere(radius: 0.8)
        sphere.materials = [material]
        let ball = SCNNode(geometry: sphere)
        ball.position = SCNVector3(0, 1.5, 0)
        scene.rootNode.addChildNode(ball)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(0, 0, 7)
        scene.rootNode.addChildNode(camera)
        return (scene, camera)
    }

    func testOffscreenRenderIsTheRightWayUp() throws {
        let (scene, camera) = upperBallScene()
        let renderer = try XCTUnwrap(OffscreenSceneRenderer(scene: scene, pointOfView: camera, width: 320, height: 180))
        let image = try XCTUnwrap(renderer.render(at: 0))

        XCTAssertEqual(image.extent.size, CGSize(width: 320, height: 180))
        // Core Image counts rows from the bottom, so "up" is a high y.
        let top = TestSupport.pixel(image, x: 160, y: 123, context: ciContext)
        let bottom = TestSupport.pixel(image, x: 160, y: 57, context: ciContext)
        XCTAssertGreaterThan(top.r, 200, "the ball should be near the top, got \(top)")
        XCTAssertLessThan(bottom.r + bottom.g + bottom.b, 30, "and nothing near the bottom, got \(bottom)")
    }

    func testPipesDrawSomethingAndKeepGrowing() throws {
        func brightness(_ image: CIImage) -> Double {
            let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
            var pixel = [Float](repeating: 0, count: 4)
            ciContext.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                             format: .RGBAf, colorSpace: TestSupport.srgb)
            return Double(pixel[0] + pixel[1] + pixel[2])
        }

        let stage = PipesStage(seed: 5)
        let early = try XCTUnwrap(stage.frame(at: 0))
        // Images from the stage are views onto one GPU texture that the next frame overwrites, so measure straight away.
        let earlyBrightness = brightness(early)
        XCTAssertEqual(early.extent.size, CGSize(width: 1280, height: 720))
        XCTAssertLessThan(earlyBrightness, 0.01, "nothing has grown yet, so the first frame should be black")

        var later = early
        for tick in 1...120 { later = try XCTUnwrap(stage.frame(at: Double(tick) / 30)) }   // four seconds at 30 fps
        XCTAssertGreaterThan(brightness(later), earlyBrightness + 0.05, "pipes should have grown into view")

        if let folder = ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("pipes.png")
            try ciContext.writePNGRepresentation(of: later, to: url, format: .RGBA8, colorSpace: TestSupport.srgb)
        }
    }

    private func averageBrightness(of image: CIImage, in rect: CGRect) -> Double {
        let average = image.cropped(to: rect).applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
        var pixel = [Float](repeating: 0, count: 4)
        ciContext.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBAf, colorSpace: TestSupport.srgb)
        return Double(pixel[0] + pixel[1] + pixel[2])
    }

    func testPipesFillAWidescreenFrameEdgeToEdge() throws {
        // The cube version left black bars down both sides. Watch a full cycle and require that at some point
        // every edge strip of the frame has pipes in it.
        let stage = PipesStage(seed: 5)
        let w = 1280.0, h = 720.0
        let strips: [(name: String, rect: CGRect)] = [
            ("left", CGRect(x: 0, y: 0, width: w * 0.12, height: h)),
            ("right", CGRect(x: w * 0.88, y: 0, width: w * 0.12, height: h)),
            ("top", CGRect(x: 0, y: h * 0.88, width: w, height: h * 0.12)),
            ("bottom", CGRect(x: 0, y: 0, width: w, height: h * 0.12)),
        ]
        var best: [String: Double] = [:]
        var bestCoverage = 0.0
        var bestImage: CIImage?
        for tick in 0..<1200 {                                     // forty seconds at 30 fps
            let image = try XCTUnwrap(stage.frame(at: Double(tick) / 30))
            guard tick % 20 == 0 else { continue }
            let values = strips.map { averageBrightness(of: image, in: $0.rect) }
            let coverage = values.min() ?? 0
            if coverage > bestCoverage {
                bestCoverage = coverage
                best = Dictionary(uniqueKeysWithValues: zip(strips.map(\.name), values))
                bestImage = image
                if let folder = ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] {
                    try ciContext.writePNGRepresentation(of: image, to: URL(fileURLWithPath: folder).appendingPathComponent("pipes-fullest.png"),
                                                         format: .RGBA8, colorSpace: TestSupport.srgb)
                }
            }
        }
        XCTAssertNotNil(bestImage)
        XCTAssertGreaterThan(bestCoverage, 0.03, "every edge of the frame should get pipes at some point; best strip brightnesses were \(best)")
    }

    func testRenderingStaysWithinTheFrameBudgetThroughAFullCycle() throws {
        let stage = PipesStage(seed: 8)
        var durations: [Double] = []
        for tick in 0..<1200 {                                     // forty seconds: fills, winds down and clears
            let start = CFAbsoluteTimeGetCurrent()
            _ = stage.frame(at: Double(tick) / 30)
            durations.append(CFAbsoluteTimeGetCurrent() - start)
        }
        let mean = durations.reduce(0, +) / Double(durations.count)
        let worst = durations.max() ?? 0
        let busiest = durations.sorted().suffix(durations.count / 5).reduce(0, +) / Double(durations.count / 5)
        print(String(format: "PIPES-PERF mean %.1f ms, busiest 20%% %.1f ms, worst %.1f ms per frame", mean * 1000, busiest * 1000, worst * 1000))
        // The whole pipeline has about 33 ms per frame, and Vision and compositing need most of it.
        XCTAssertLessThan(mean, 0.010, "pipes cost \(Int(mean * 1000)) ms per frame on average")
        XCTAssertLessThan(worst, 0.040, "a single frame took \(Int(worst * 1000)) ms")
    }

    func testSourceReturnsFramesAndReleasesTheSceneOnStop() {
        let source = PipesSource()
        let camera = TestSupport.solid(0, 0, 0)
        XCTAssertNotNil(source.frame(at: 0, camera: camera))
        source.stop()
        XCTAssertNotNil(source.frame(at: 1, camera: camera), "a stopped source should rebuild itself if used again")
    }

    func testPipesAreABuiltInBackgroundAndOldLibrariesStillLoad() throws {
        XCTAssertTrue(Background.builtIns.contains(.pipes))
        XCTAssertTrue(Background.pipes.isLive)
        // A background saved before this kind existed still decodes.
        let old = #"{"id":"11111111-1111-1111-1111-111111111111","name":"x","kind":{"blur":{"radius":10}},"origin":"imported","parallax":false,"createdAt":0}"#
        XCTAssertNoThrow(try JSONDecoder().decode(Background.self, from: Data(old.utf8)))
        let round = try JSONDecoder().decode(Background.self, from: JSONEncoder().encode(Background.pipes))
        XCTAssertEqual(round, Background.pipes)
    }
}
