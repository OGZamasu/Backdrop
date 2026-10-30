import CoreImage
import simd
import XCTest

/// A silhouette that is whatever the test says: solid rectangles, or nothing.
private struct Blocks: MatteQuery {
    var rects: [CGRect] = []
    func coverage(x: Double, y: Double) -> Double { rects.contains { $0.contains(CGPoint(x: x, y: y)) } ? 1 : 0 }
}

private let frame = CGSize(width: 1280, height: 720)

final class BalloonGameTests: XCTestCase {
    private func world(motion: MatteQuery? = nil) -> GameWorld { GameWorld(size: frame, matte: nil, motion: motion, face: nil) }

    func testBalloonsRiseAndLeave() {
        var game = BalloonGame(size: frame, seed: 1)
        for _ in 0..<60 { game.step(1.0 / 30, world: world()) }
        XCTAssertFalse(game.balloons.isEmpty, "two seconds in there should be balloons")
        XCTAssertTrue(game.balloons.allSatisfy { $0.position.y > -100 })
        for _ in 0..<(30 * 40) { game.step(1.0 / 30, world: world()) }
        XCTAssertTrue(game.balloons.allSatisfy { $0.position.y - $0.radius * 1.4 <= frame.height }, "the ones that float off the top are removed")
    }

    func testStandingStillPopsNothing() {
        var game = BalloonGame(size: frame, seed: 2)
        for _ in 0..<(30 * 20) { game.step(1.0 / 30, world: world(motion: Blocks())) }
        XCTAssertEqual(game.popped, 0)
        XCTAssertEqual(game.score, 0)
    }

    func testSwatsPopBalloonsAndScore() {
        var game = BalloonGame(size: frame, seed: 3)
        var sawGood = false
        // A swat that covers the whole screen pops everything it meets.
        let everywhere = Blocks(rects: [CGRect(origin: .zero, size: frame)])
        for _ in 0..<(30 * 12) {
            game.step(1.0 / 30, world: world(motion: everywhere))
            if game.score > 0 { sawGood = true }
        }
        XCTAssertGreaterThan(game.popped, 3)
        XCTAssertTrue(sawGood, "regular balloons are worth points")
        XCTAssertTrue(game.balloons.isEmpty || game.balloons.allSatisfy { $0.position.y < 0 }, "nothing survives being swatted at")
    }

    func testBombsCostPointsButNeverGoBelowZero() {
        var game = BalloonGame(size: frame, seed: 4)
        let everywhere = Blocks(rects: [CGRect(origin: .zero, size: frame)])
        for _ in 0..<(30 * 44) { game.step(1.0 / 30, world: world(motion: everywhere)) }
        XCTAssertGreaterThanOrEqual(game.score, 0)
    }

    func testTheRoundEnds() {
        var game = BalloonGame(size: frame, seed: 5)
        var steps = 0
        while !game.isOver && steps < 30 * 60 { game.step(1.0 / 30, world: world()); steps += 1 }
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(Double(steps) / 30, BalloonGame.roundSeconds, accuracy: 0.2)
    }

    func testSameSeedPlaysTheSame() {
        var a = BalloonGame(size: frame, seed: 9), b = BalloonGame(size: frame, seed: 9)
        for _ in 0..<200 { a.step(1.0 / 30, world: world()); b.step(1.0 / 30, world: world()) }
        XCTAssertEqual(a.balloons.map(\.position.x), b.balloons.map(\.position.x))
    }
}

final class BreakoutGameTests: XCTestCase {
    private func world(_ matte: MatteQuery?) -> GameWorld { GameWorld(size: frame, matte: matte, motion: nil, face: nil) }

    func testTheBallStaysInsideAndEventuallyLosesALife() {
        var game = BreakoutGame(size: frame, seed: 1)
        for _ in 0..<(30 * 40) {
            game.step(1.0 / 30, world: world(nil))
            if game.serving <= 0 {
                XCTAssertGreaterThanOrEqual(game.ball.x, 0)
                XCTAssertLessThanOrEqual(game.ball.x, frame.width)
                XCTAssertLessThanOrEqual(game.ball.y, frame.height + 1)
            }
        }
        XCTAssertLessThan(game.lives, 3, "with no one to bat it back the ball drops")
    }

    func testPlayingWithNoOneEndsTheGame() {
        var game = BreakoutGame(size: frame, seed: 2)
        for _ in 0..<(30 * 120) where !game.isOver { game.step(1.0 / 30, world: world(nil)) }
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.lives, 0)
    }

    func testBouncingOffAWallOfBodyKeepsTheBallAliveAndBreaksBricks() {
        // A wide, low body across the bottom of the frame, like someone standing at a desk.
        let body = Blocks(rects: [CGRect(x: 0, y: 0, width: frame.width, height: 150)])
        var game = BreakoutGame(size: frame, seed: 3)
        let bricksAtStart = game.bricks.count
        for _ in 0..<(30 * 60) { game.step(1.0 / 30, world: world(body)) }
        XCTAssertEqual(game.lives, 3, "the ball never gets past the floor of bodies")
        XCTAssertLessThan(game.bricks.count, bricksAtStart, "and keeps coming back up to hit bricks")
        XCTAssertGreaterThan(game.score, 0)
    }

    func testHittingABrickRemovesItAndReversesTheBall() throws {
        var game = BreakoutGame(size: frame, seed: 4)
        // Aim at a brick on the bottom row, so nothing else is in the way.
        let brick = try XCTUnwrap(game.bricks.last)
        let count = game.bricks.count
        game.place(ball: SIMD2(brick.rect.midX, brick.rect.minY - 20), velocity: SIMD2(0, 500))
        for _ in 0..<10 { game.step(1.0 / 60, world: world(nil)) }
        XCTAssertEqual(game.bricks.count, count - 1)
        XCTAssertLessThan(game.velocity.y, 0, "the ball comes back down")
        XCTAssertEqual(game.score, 10 * (7 - min(6, brick.row)), "higher rows pay more")
    }

    func testClearingTheBoardStartsANewLevel() throws {
        var game = BreakoutGame(size: frame, seed: 5)
        game.keepOnly(1)
        let brick = try XCTUnwrap(game.bricks.first)
        game.place(ball: SIMD2(brick.rect.midX, brick.rect.minY - 20), velocity: SIMD2(0, 500))
        for _ in 0..<10 { game.step(1.0 / 60, world: world(nil)) }
        XCTAssertEqual(game.level, 2)
        XCTAssertGreaterThan(game.bricks.count, 30, "a fresh, bigger wall")
        XCTAssertGreaterThan(game.serving, 0, "and the ball waits to be served again")
    }
}

final class BallPitTests: XCTestCase {
    func testBallsFallAndPileUpOnTheFloor() {
        var pit = BallPit(size: frame)
        for _ in 0..<(30 * 20) { pit.step(1.0 / 30, matte: nil) }
        XCTAssertGreaterThan(pit.balls.count, 20)
        XCTAssertTrue(pit.balls.allSatisfy { $0.position.y >= $0.radius - 1 }, "nothing falls through the floor")
        XCTAssertTrue(pit.balls.allSatisfy { $0.position.x >= 0 && $0.position.x <= frame.width })
        XCTAssertLessThanOrEqual(pit.balls.count, pit.capacity)
        let settled = pit.balls.filter { $0.position.y < 120 }
        XCTAssertGreaterThan(settled.count, 5, "they collect on the floor")
    }

    func testBallsBounceOffAShelf() {
        var pit = BallPit(size: frame)
        let shelf = Blocks(rects: [CGRect(x: 300, y: 300, width: 680, height: 40)])
        for _ in 0..<(30 * 15) { pit.step(1.0 / 30, matte: shelf) }
        let inside = pit.balls.filter { Blocks(rects: shelf.rects).coverage(x: $0.position.x, y: $0.position.y) > 0 }
        XCTAssertTrue(inside.isEmpty, "no ball is stuck inside the shelf")
        let onTop = pit.balls.filter { $0.position.y > 340 && $0.position.x > 300 && $0.position.x < 980 }
        XCTAssertGreaterThan(onTop.count, 3, "some rest on top of it")
    }

    func testBallsDoNotStackOnTopOfEachOther() {
        var pit = BallPit(size: frame)
        for _ in 0..<(30 * 20) { pit.step(1.0 / 30, matte: nil) }
        var worst = 0.0
        for i in pit.balls.indices {
            for j in pit.balls.indices where j > i {
                let d = simd_length(pit.balls[i].position - pit.balls[j].position)
                worst = max(worst, (pit.balls[i].radius + pit.balls[j].radius) - d)
            }
        }
        XCTAssertLessThan(worst, 12, "balls may squash a little but not merge")
    }
}

final class GameLensTests: XCTestCase {
    /// A tiny game that scores one point a second and ends after `length` seconds.
    struct Counter: Game {
        static let title = "Counter"
        static let hint = "Just wait"
        var score = 0
        var isOver: Bool { elapsed >= 3 }
        var summary: String { "t=\(Int(elapsed))" }
        private var elapsed = 0.0
        init(size: CGSize, seed: UInt64) {}
        mutating func step(_ dt: Double, world: GameWorld) { elapsed += dt; score = Int(elapsed) }
        func draw(in ctx: CGContext, time: Double) {}
    }

    private let compositor = Compositor()
    private lazy var services = LensServices(context: compositor.context, size: compositor.outputSize)

    private func lens(store: ScoreStore = MemoryScoreStore()) -> GameLens<Counter> {
        GameLens<Counter>(id: "counter", needs: [.matte], store: store)
    }

    /// Runs the lens for `seconds` of video, with the person there or not.
    private func play(_ lens: GameLens<Counter>, present: Bool, seconds: Double, grid: MatteGrid) {
        let scene = SyntheticScene()
        var t = 0.0
        while t < seconds {
            let input = scene.input(time: t, dt: 1.0 / 30, services: services, compositor: compositor, grid: grid)
            if !present { grid.update(from: CIImage(color: .black).cropped(to: compositor.rect), rect: compositor.rect, context: compositor.context) }
            _ = lens.render(input)
            t += 1.0 / 30
        }
    }

    private var frame_size: CGSize { compositor.outputSize }

    func testItWaitsForSomeoneThenCountsDownThenPlaysThenEnds() {
        let lens = lens()
        let grid = MatteGrid(outputSize: frame_size)
        XCTAssertEqual(lens.phase, .waiting)
        play(lens, present: false, seconds: 2, grid: grid)
        XCTAssertEqual(lens.phase, .waiting, "an empty room doesn't start a game")

        play(lens, present: true, seconds: 1, grid: grid)
        guard case .countdown = lens.phase else { return XCTFail("expected a countdown, got \(lens.phase)") }

        play(lens, present: true, seconds: GameLens<Counter>.countdownSeconds + 0.2, grid: grid)
        XCTAssertEqual(lens.phase, .playing)

        play(lens, present: true, seconds: 3.3, grid: grid)
        guard case .over = lens.phase else { return XCTFail("expected game over, got \(lens.phase)") }
        XCTAssertEqual(lens.status?.title, "Game over: 3")
    }

    func testLeavingThePicturePausesTheGame() {
        let lens = lens()
        let grid = MatteGrid(outputSize: frame_size)
        play(lens, present: true, seconds: 0.7 + GameLens<Counter>.countdownSeconds + 0.5, grid: grid)
        XCTAssertEqual(lens.phase, .playing)
        // Gone long enough for the pause to kick in, then a stretch that would have ended the game if it hadn't.
        play(lens, present: false, seconds: GameLens<Counter>.absenceGrace + 0.5, grid: grid)
        let paused = lens.game.summary
        play(lens, present: false, seconds: 3, grid: grid)
        XCTAssertEqual(lens.phase, .playing, "still waiting for you")
        XCTAssertEqual(lens.game.summary, paused, "the clock stopped")
        play(lens, present: true, seconds: 4, grid: grid)
        guard case .over = lens.phase else { return XCTFail("coming back resumes the game, got \(lens.phase)") }
    }

    func testBestScoresAreKept() {
        let store = MemoryScoreStore()
        let lens = lens(store: store)
        let grid = MatteGrid(outputSize: frame_size)
        play(lens, present: true, seconds: 0.7 + GameLens<Counter>.countdownSeconds + 3.5, grid: grid)
        XCTAssertEqual(store.best(for: "counter"), 3)
        XCTAssertEqual(lens.status?.detail, "New best!")
        store.record(1, for: "counter")
        XCTAssertEqual(store.best(for: "counter"), 3, "a worse score doesn't replace it")
    }

    func testRestartGoesStraightToTheCountdown() {
        let lens = lens()
        lens.restart()
        guard case .countdown(let t) = lens.phase else { return XCTFail() }
        XCTAssertEqual(t, GameLens<Counter>.countdownSeconds)
    }

    func testDefaultsStoreRoundTrips() {
        let name = "backdrop.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        let store = DefaultsScoreStore(defaults: suite)
        XCTAssertEqual(store.best(for: "x"), 0)
        store.record(12, for: "x"); store.record(7, for: "x")
        XCTAssertEqual(store.best(for: "x"), 12)
    }
}

final class GameRenderTests: XCTestCase {
    func testGamesRenderOverASyntheticScene() throws {
        let compositor = Compositor()
        let services = LensServices(context: compositor.context, size: compositor.outputSize)
        let scene = SyntheticScene()
        let grid = MatteGrid(outputSize: compositor.outputSize)
        let backdrop = SyntheticScene.backdrop()

        // Balloon pop: pretend the player is swatting wildly so a few balloons pop.
        let balloons = GameLens<BalloonGame>(id: "test.balloons", needs: [.matte], store: MemoryScoreStore())
        balloons.restart()
        var last: CIImage?
        for i in 0..<(30 * 8) {
            var s = scene
            s.center.x = 640 + 220 * sin(Double(i) / 6)        // sweeping side to side makes motion
            let input = s.input(time: Double(i) / 30, services: services, compositor: compositor, grid: grid, background: backdrop)
            last = balloons.render(input)
        }
        Output.save(try XCTUnwrap(last), as: "game-balloons.png")

        let breakout = GameLens<BreakoutGame>(id: "test.breakout", needs: [.matte], store: MemoryScoreStore())
        breakout.restart()
        for i in 0..<(30 * 9) {
            var s = scene
            s.center = CGPoint(x: 640 + 300 * sin(Double(i) / 25), y: 200)
            let input = s.input(time: Double(i) / 30, services: services, compositor: compositor, grid: grid, background: backdrop)
            last = breakout.render(input)
        }
        Output.save(try XCTUnwrap(last), as: "game-breakout.png")

        let pit = BallPitLens()
        for i in 0..<(30 * 8) {
            let input = scene.input(time: Double(i) / 30, services: services, compositor: compositor, grid: grid, background: backdrop)
            last = pit.render(input)
        }
        Output.save(try XCTUnwrap(last), as: "game-ballpit.png")
        XCTAssertGreaterThan(pit.ballCount, 20)
    }
}
