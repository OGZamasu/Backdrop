import CoreImage
import XCTest

final class MatteGridTests: XCTestCase {
    private let ciContext = CIContext()

    func testTheGridKnowsWhichWayIsUp() {
        // White in the TOP-left quarter. In Core Image "top" is a high y.
        let white = TestSupport.solid(1, 1, 1, size: CGSize(width: 640, height: 360)).transformed(by: CGAffineTransform(translationX: 0, y: 360))
        let matte = white.composited(over: TestSupport.solid(0, 0, 0))
        let grid = MatteGrid(outputSize: CGSize(width: 1280, height: 720))
        grid.update(from: matte, rect: CGRect(x: 0, y: 0, width: 1280, height: 720), context: ciContext)

        XCTAssertGreaterThan(grid.coverage(x: 100, y: 600), 0.95, "top left should be covered")
        XCTAssertLessThan(grid.coverage(x: 100, y: 100), 0.05, "bottom left should be empty")
        XCTAssertLessThan(grid.coverage(x: 1000, y: 600), 0.05, "top right should be empty")
        XCTAssertLessThan(grid.coverage(x: 1000, y: 100), 0.05, "bottom right should be empty")
        XCTAssertEqual(grid.fraction, 0.25, accuracy: 0.02)
    }

    func testOutsideTheFrameIsEmptyAndTheEdgeIsSmooth() {
        let grid = MatteGrid.filled([CGRect(x: 400, y: 200, width: 200, height: 200)], outputSize: CGSize(width: 1280, height: 720))
        XCTAssertEqual(grid.coverage(x: -50, y: 300), 0)
        XCTAssertEqual(grid.coverage(x: 2000, y: 300), 0)
        XCTAssertEqual(grid.coverage(x: 500, y: 300), 1, accuracy: 0.001)
        let across = stride(from: 390.0, through: 410.0, by: 2.0).map { grid.coverage(x: $0, y: 300) }
        XCTAssertEqual(across, across.sorted(), "coverage should rise smoothly across an edge")
        XCTAssertTrue(across.contains { $0 > 0.1 && $0 < 0.9 }, "and pass through in-between values")
    }

    func testEdgePointsLieOnTheOutline() throws {
        let grid = MatteGrid.filled([CGRect(x: 400, y: 200, width: 200, height: 200)], outputSize: CGSize(width: 1280, height: 720))
        for sample in [0.0, 0.3, 0.6, 0.99] {
            let p = try XCTUnwrap(grid.edgePoint(sample))
            let nearEdge = min(abs(p.x - 400), abs(p.x - 600), abs(p.y - 200), abs(p.y - 400))
            XCTAssertLessThan(nearEdge, 12, "\(p) isn't on the outline")
        }
        XCTAssertNil(MatteGrid(outputSize: CGSize(width: 1280, height: 720)).edgePoint(0.5), "nobody there, no outline")
    }
}

final class SilhouetteTests: XCTestCase {
    private let size = CGSize(width: 1280, height: 720)
    /// A solid block 200 wide, 200 tall, with its top at y = 400.
    private var block: MatteGrid { MatteGrid.filled([CGRect(x: 400, y: 200, width: 200, height: 200)], outputSize: size, cellSize: 4) }

    func testABallOnTopIsPushedUp() throws {
        let hit = try XCTUnwrap(Silhouette.contact(center: SIMD2(500, 412), radius: 20, in: block))
        XCTAssertGreaterThan(hit.normal.y, 0.9)
        XCTAssertGreaterThan(hit.depth, 0)
    }

    func testBallsAtTheSidesAreNudgedOutward() throws {
        let left = try XCTUnwrap(Silhouette.contact(center: SIMD2(392, 300), radius: 20, in: block))
        XCTAssertLessThan(left.normal.x, -0.9)
        let right = try XCTUnwrap(Silhouette.contact(center: SIMD2(608, 300), radius: 20, in: block))
        XCTAssertGreaterThan(right.normal.x, 0.9)
        let under = try XCTUnwrap(Silhouette.contact(center: SIMD2(500, 192), radius: 20, in: block))
        XCTAssertLessThan(under.normal.y, -0.9)
    }

    func testABallFarAwayTouchesNothing() {
        XCTAssertNil(Silhouette.contact(center: SIMD2(900, 600), radius: 20, in: block))
        XCTAssertNil(Silhouette.contact(center: SIMD2(500, 440), radius: 20, in: block), "20 px clear of the top")
    }

    func testABallBuriedDeepInsideIsPulledOutTheNearestWay() throws {
        let hit = try XCTUnwrap(Silhouette.contact(center: SIMD2(500, 380), radius: 20, in: block))   // 20 px below the top
        XCTAssertGreaterThan(hit.normal.y, 0.5, "the top is the nearest way out")
        var position = SIMD2<Double>(500, 380), velocity = SIMD2<Double>(0, 0)
        Silhouette.resolve(position: &position, velocity: &velocity, radius: 20, in: block, restitution: 0.5)
        XCTAssertNil(Silhouette.contact(center: position, radius: 20, in: block), "after resolving it should be clear, at \(position)")
    }

    func testFallingBallsBounceWithTheRightEnergy() {
        var position = SIMD2<Double>(500, 415), velocity = SIMD2<Double>(30, -400)   // 5 px into the top face
        XCTAssertTrue(Silhouette.resolve(position: &position, velocity: &velocity, radius: 20, in: block, restitution: 0.6))
        XCTAssertEqual(velocity.y, 240, accuracy: 30, "400 down at 0.6 restitution should come back about 240 up")
        XCTAssertEqual(velocity.x, 30, accuracy: 5, "sliding speed is kept")
    }

    func testABallMovingAwayIsNotPulledBack() {
        var position = SIMD2<Double>(500, 415), velocity = SIMD2<Double>(0, 300)
        Silhouette.resolve(position: &position, velocity: &velocity, radius: 20, in: block, restitution: 0.6)
        XCTAssertEqual(velocity.y, 300, accuracy: 0.001)
    }
}

final class OverlayCanvasTests: XCTestCase {
    private let ciContext = CIContext()

    func testDrawingLandsWhereItsAskedAndTheRightWayUp() throws {
        let canvas = try XCTUnwrap(OverlayCanvas(size: CGSize(width: 1280, height: 720)))
        let ctx = canvas.begin()
        ctx.fillCircle(center: CGPoint(x: 200, y: 600), radius: 30, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))   // high up
        let image = canvas.image()
        XCTAssertGreaterThan(TestSupport.pixel(image.composited(over: TestSupport.solid(0, 0, 0)), x: 200, y: 600, context: ciContext).r, 240, "drawn high up it should be up there")
        XCTAssertLessThan(TestSupport.pixel(image.composited(over: TestSupport.solid(0, 0, 0)), x: 200, y: 100, context: ciContext).r, 10)
    }

    func testEachFrameStartsClearAndHandedOutPicturesSurviveTheNextOne() throws {
        let canvas = try XCTUnwrap(OverlayCanvas(size: CGSize(width: 1280, height: 720), slots: 3))
        canvas.begin().fillCircle(center: CGPoint(x: 200, y: 300), radius: 30, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let first = canvas.image()
        canvas.begin().fillCircle(center: CGPoint(x: 900, y: 300), radius: 30, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let second = canvas.image()
        let onBlack = { (i: CIImage) in i.composited(over: TestSupport.solid(0, 0, 0)) }
        XCTAssertGreaterThan(TestSupport.pixel(onBlack(first), x: 200, y: 300, context: ciContext).r, 240, "the first picture is still intact")
        XCTAssertLessThan(TestSupport.pixel(onBlack(second), x: 200, y: 300, context: ciContext).r, 10, "the second started clear, with no red left over")
        XCTAssertGreaterThan(TestSupport.pixel(onBlack(second), x: 900, y: 300, context: ciContext).b, 240)
    }

    func testEmojiAndTextAndGlowAllDraw() throws {
        let canvas = try XCTUnwrap(OverlayCanvas(size: CGSize(width: 1280, height: 720)))
        let ctx = canvas.begin()
        let crown = try XCTUnwrap(Sprites.emoji("👑", size: 120))
        ctx.draw(crown, center: CGPoint(x: 300, y: 400), height: 140)
        ctx.text("SCORE 42", center: CGPoint(x: 900, y: 400), size: 60)
        ctx.glow(center: CGPoint(x: 640, y: 150), radius: 80, red: 1, green: 0.8, blue: 0.2, alpha: 1)
        let image = canvas.image()
        Output.save(image.composited(over: TestSupport.solid(0.1, 0.1, 0.15)), as: "canvas-basics.png")
        func covered(_ rect: CGRect) -> Bool {
            let avg = image.cropped(to: rect).applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
            var px = [Float](repeating: 0, count: 4)
            ciContext.render(avg, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: TestSupport.srgb)
            return px[3] > 0.05
        }
        XCTAssertTrue(covered(CGRect(x: 230, y: 330, width: 140, height: 140)), "the emoji")
        XCTAssertTrue(covered(CGRect(x: 780, y: 370, width: 240, height: 60)), "the text")
        XCTAssertTrue(covered(CGRect(x: 600, y: 110, width: 80, height: 80)), "the glow")
        XCTAssertFalse(covered(CGRect(x: 20, y: 20, width: 100, height: 100)), "and nothing elsewhere")
    }
}

final class ParticleSystemTests: XCTestCase {
    func testParticlesFallAgeAndDie() {
        var system = ParticleSystem()
        system.emit(Particle(position: SIMD2(100, 500), velocity: SIMD2(50, 0), life: 1, size: 5))
        system.step(0.5)
        XCTAssertEqual(system.particles.count, 1)
        XCTAssertLessThan(system.particles[0].position.y, 500, "gravity pulls it down")
        XCTAssertEqual(system.particles[0].position.x, 125, accuracy: 0.001)
        XCTAssertEqual(system.particles[0].progress, 0.5, accuracy: 0.001)
        system.step(0.6)
        XCTAssertTrue(system.particles.isEmpty, "past its life it is gone")
    }

    func testCapacityDropsTheOldestAndAdjustCanBounce() {
        var system = ParticleSystem(capacity: 3)
        for i in 0..<5 { system.emit(Particle(position: SIMD2(Double(i), 0), velocity: .zero, life: 10, size: 1)) }
        XCTAssertEqual(system.particles.map(\.position.x), [2, 3, 4], "the oldest go first")

        system.removeAll()
        system.emit(Particle(position: SIMD2(0, 10), velocity: SIMD2(0, -200), life: 10, size: 1))
        system.step(0.1) { p in if p.position.y < 0 { p.position.y = 0; p.velocity.y = abs(p.velocity.y) } }
        XCTAssertGreaterThanOrEqual(system.particles[0].position.y, 0)
    }
}

final class FaceStateTests: XCTestCase {
    func testAFaceKnowsItsOwnUpwardsAndWhereThingsGo() {
        let upright = SyntheticScene(center: CGPoint(x: 640, y: 400)).face()
        XCTAssertEqual(upright.roll, 0, accuracy: 1e-9)
        XCTAssertEqual(upright.up.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(upright.up.dy, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(upright.headTop.y, upright.eyeCenter.y)
        XCTAssertGreaterThan(upright.nose.y, upright.mouth.y)
        XCTAssertLessThan(upright.nose.y, upright.eyeCenter.y)
        XCTAssertEqual(upright.interocular, 84, accuracy: 1e-9)

        let tilted = SyntheticScene(center: CGPoint(x: 640, y: 400), roll: 0.4).face()
        XCTAssertEqual(tilted.roll, 0.4, accuracy: 1e-9)
        XCTAssertLessThan(tilted.up.dx, 0, "tipped counter-clockwise, the top of the head leans left")
        XCTAssertLessThan(tilted.headTop.x, tilted.eyeCenter.x)
        XCTAssertEqual(hypot(tilted.up.dx, tilted.up.dy), 1, accuracy: 1e-9)
    }
}

/// A lens that records what it was handed, for testing the pipeline.
final class ProbeLens: Lens {
    var needs: LensNeeds
    var wantsMatteGrid: Bool
    private(set) var inputs: [LensInput] = []
    var fill = CIColor(red: 0, green: 1, blue: 0)

    init(needs: LensNeeds, grid: Bool) { self.needs = needs; wantsMatteGrid = grid }

    func render(_ input: LensInput) -> CIImage {
        inputs.append(input)
        return CIImage(color: fill).cropped(to: input.rect)
    }
}

final class LensPipelineTests: XCTestCase {
    private let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))

    private func run(_ pipeline: FramePipeline) -> CVPixelBuffer? {
        var result: CVPixelBuffer?
        pipeline.onOutput = { buffer, _ in result = buffer }
        pipeline.queue.sync { pipeline.process(scene.cameraBuffer(), at: .zero) }
        return result
    }

    func testALensGetsTheMatteAndSilhouetteItAskedForEvenWithNoBackdrop() throws {
        let pipeline = FramePipeline()
        pipeline.matteOverride = { [scene] _ in scene.matteBuffer() }
        pipeline.setBackground(.off, source: nil)
        let probe = ProbeLens(needs: [.matte], grid: true)
        pipeline.setLens(probe)
        let out = try XCTUnwrap(run(pipeline))

        let input = try XCTUnwrap(probe.inputs.first)
        XCTAssertNotNil(input.matte, "it asked for the matte")
        XCTAssertNil(input.background, "the backdrop is Off")
        let grid = try XCTUnwrap(input.matteGrid, "it asked for the silhouette grid")
        XCTAssertGreaterThan(grid.coverage(x: 640, y: 420), 0.9, "the head is in the grid")
        XCTAssertLessThan(grid.coverage(x: 100, y: 100), 0.1, "and the room is not")
        assertColor(TestSupport.pixel(out, x: 640, y: 360), (0, 255, 0), tolerance: 6, "what the lens returned is what comes out")
    }

    func testALensThatNeedsNothingCostsNothing() throws {
        let pipeline = FramePipeline()
        var visionCalls = 0
        pipeline.matteOverride = { [scene] _ in visionCalls += 1; return scene.matteBuffer() }
        pipeline.setBackground(.off, source: nil)
        let probe = ProbeLens(needs: [], grid: false)
        pipeline.setLens(probe)
        _ = run(pipeline)
        XCTAssertEqual(visionCalls, 0, "no backdrop and no need for a silhouette means no segmentation")
        XCTAssertNil(try XCTUnwrap(probe.inputs.first).matte)
        XCTAssertNil(try XCTUnwrap(probe.inputs.first).matteGrid)
    }

    func testWithABackdropTheLensSeesItAndTheComposedPicture() throws {
        let pipeline = FramePipeline()
        pipeline.matteOverride = { [scene] _ in scene.matteBuffer() }
        let backdrop = Background(id: UUID(), name: "g", kind: .gradient(.graphite), origin: .builtIn)
        pipeline.setBackground(backdrop, source: GradientSource(preset: .graphite))
        let probe = ProbeLens(needs: [.matte], grid: false)
        pipeline.setLens(probe)
        _ = run(pipeline)
        let input = try XCTUnwrap(probe.inputs.first)
        XCTAssertNotNil(input.background)
        XCTAssertNotNil(input.matte)
        XCTAssertNil(input.matteGrid, "it didn't ask for the grid")
        XCTAssertEqual(input.composed.extent, pipeline.compositor.rect)
        XCTAssertGreaterThan(input.dt, 0)
        XCTAssertLessThanOrEqual(input.dt, 0.1)
    }

    func testTakingTheLensOffRestoresThePlainPicture() throws {
        let pipeline = FramePipeline()
        pipeline.setBackground(.off, source: nil)
        pipeline.setLens(ProbeLens(needs: [], grid: false))
        XCTAssertNotNil(run(pipeline))
        pipeline.setLens(nil)
        let out = try XCTUnwrap(run(pipeline))
        let camera = TestSupport.pixel(scene.cameraBuffer(), x: 50, y: 50)
        assertColor(TestSupport.pixel(out, x: 50, y: 50), camera, tolerance: 10, "the camera shows through again")
    }
}
