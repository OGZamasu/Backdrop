import XCTest

final class MazeTests: XCTestCase {
    private let sizes = [(1, 1), (2, 1), (1, 7), (5, 5), (21, 11), (40, 3)]

    private func reachable(in maze: Maze) -> Int {
        var seen: Set<Maze.Cell> = [Maze.Cell(0, 0)]
        var queue = [Maze.Cell(0, 0)]
        while let cell = queue.popLast() {
            for direction in maze.openDirections(from: cell) {
                let next = cell &+ direction.vector
                if seen.insert(next).inserted { queue.append(next) }
            }
        }
        return seen.count
    }

    func testEveryCellIsReachableAndThereAreNoLoops() {
        for (w, h) in sizes {
            for seed in 1...4 as ClosedRange<UInt64> {
                let maze = Maze(width: w, height: h, seed: seed)
                XCTAssertEqual(reachable(in: maze), w * h, "\(w)×\(h) seed \(seed): some cells are walled off")
                let passages = (0..<h).flatMap { y in (0..<w).map { x in maze.openDirections(from: Maze.Cell(x, y)).count } }.reduce(0, +) / 2
                XCTAssertEqual(passages, w * h - 1, "\(w)×\(h) seed \(seed): a perfect maze has exactly cells-1 passages")
            }
        }
    }

    func testPassagesWorkBothWaysAndTheOuterEdgeIsClosed() {
        let maze = Maze(width: 21, height: 11, seed: 3)
        for y in 0..<maze.height {
            for x in 0..<maze.width {
                let cell = Maze.Cell(x, y)
                for direction in Maze.Direction.allCases {
                    let next = cell &+ direction.vector
                    if maze.isOpen(cell, direction) {
                        XCTAssertTrue(maze.contains(next), "\(cell) opens off the edge of the maze")
                        XCTAssertTrue(maze.isOpen(next, direction.opposite), "\(cell) → \(next) is open one way only")
                    }
                }
            }
        }
    }

    func testSameSeedSameMazeDifferentSeedDifferentMaze() {
        func signature(_ m: Maze) -> [Int] { (0..<m.height).flatMap { y in (0..<m.width).map { x in m.openDirections(from: Maze.Cell(x, y)).map(\.rawValue).reduce(0) { $0 | (1 << $1) } } } }
        XCTAssertEqual(signature(Maze(width: 12, height: 8, seed: 5)), signature(Maze(width: 12, height: 8, seed: 5)))
        XCTAssertNotEqual(signature(Maze(width: 12, height: 8, seed: 5)), signature(Maze(width: 12, height: 8, seed: 6)))
    }

    func testAMazeHasDeadEndsForTheWalkerToTurnAroundIn() {
        let maze = Maze(width: 21, height: 11, seed: 2)
        let deadEnds = (0..<maze.height).flatMap { y in (0..<maze.width).map { Maze.Cell($0, y) } }.filter { maze.openDirections(from: $0).count == 1 }
        XCTAssertGreaterThan(deadEnds.count, 5)
    }
}

final class MazeWalkerTests: XCTestCase {
    private let frame = 1.0 / 30

    private func walk(seed: UInt64, mazeSeed: UInt64 = 1, frames: Int, width: Int = 21, height: Int = 11) -> (maze: Maze, poses: [MazeWalker.Pose], walker: MazeWalker) {
        let maze = Maze(width: width, height: height, seed: mazeSeed)
        var walker = MazeWalker(maze: maze, seed: seed)
        var poses = [walker.pose]
        for _ in 0..<frames { poses.append(walker.advance(by: frame)) }
        return (maze, poses, walker)
    }

    func testTheWalkerNeverGoesThroughAWall() {
        for seed in 1...4 as ClosedRange<UInt64> {
            let (maze, poses, _) = walk(seed: seed, mazeSeed: seed, frames: 6000)
            for pose in poses {
                let fx = pose.x - pose.x.rounded(), fy = pose.y - pose.y.rounded()
                let onX = abs(fx) > 1e-9, onY = abs(fy) > 1e-9
                XCTAssertFalse(onX && onY, "seed \(seed): \(pose) is off the corridors")
                if onX {
                    let from = Maze.Cell(Int(pose.x.rounded(.down)), Int(pose.y.rounded()))
                    XCTAssertTrue(maze.isOpen(from, .east), "seed \(seed): walked through a wall near \(from) going east/west")
                } else if onY {
                    let from = Maze.Cell(Int(pose.x.rounded()), Int(pose.y.rounded(.down)))
                    XCTAssertTrue(maze.isOpen(from, .south), "seed \(seed): walked through a wall near \(from) going north/south")
                }
            }
        }
    }

    func testTheViewTurnsSmoothlyAndNeverSpinsAround() {
        let (_, poses, _) = walk(seed: 2, frames: 20000)
        for (a, b) in zip(poses, poses.dropFirst()) {
            XCTAssertLessThan(abs(b.yaw - a.yaw), 0.2, "the view jumped from \(a.yaw) to \(b.yaw) in one frame")
        }
        XCTAssertLessThan((poses.map(\.yaw).max() ?? 0) - (poses.map(\.yaw).min() ?? 0), 80,
                          "the yaw should not wind up by whole extra turns")
    }

    func testTheCameraFacesTheWayItIsGoing() {
        let (_, poses, _) = walk(seed: 3, frames: 6000)
        var checked = 0
        for (a, b) in zip(poses, poses.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            guard abs(dx) + abs(dy) > 1e-6, a.yaw == b.yaw else { continue }   // moving, not turning
            let expected = atan2(-dx, -dy)
            let difference = (a.yaw - expected).truncatingRemainder(dividingBy: 2 * .pi)
            XCTAssertEqual(min(abs(difference), 2 * .pi - abs(difference)), 0, accuracy: 1e-6, "walking (\(dx), \(dy)) but facing \(a.yaw)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    func testTheWalkerAboutFacesAtDeadEnds() {
        let (_, poses, _) = walk(seed: 4, frames: 20000)
        let window = 30   // an about-face takes 0.9 s
        let swings = poses.indices.dropFirst(window).filter { abs(poses[$0].yaw - poses[$0 - window].yaw) > 2.8 }
        XCTAssertFalse(swings.isEmpty, "it should turn all the way round at a dead end")
    }

    func testTheWalkerExploresMostOfTheMazeAtAWalkingPace() {
        let frames = 24000   // 13 minutes
        let (maze, poses, walker) = walk(seed: 5, frames: frames)
        let visited = Set(poses.map { Maze.Cell(Int($0.x.rounded()), Int($0.y.rounded())) })
        let coverage = Double(visited.count) / Double(maze.width * maze.height)
        let pace = Double(walker.cellsTraveled) / (Double(frames) * frame)
        print(String(format: "MAZE-STATS coverage %.0f%%, pace %.2f cells/s", coverage * 100, pace))
        XCTAssertGreaterThan(coverage, 0.6, "it should wander widely, not shuffle back and forth")
        XCTAssertGreaterThan(pace, 0.45)
        XCTAssertLessThan(pace, MazeWalker.cellsPerSecond)
    }

    func testAHugeGapBetweenFramesDoesNotTeleportTheCamera() {
        let maze = Maze(width: 21, height: 11, seed: 1)
        var walker = MazeWalker(maze: maze, seed: 1)
        let before = walker.pose
        let after = walker.advance(by: 30)   // the app was suspended for half a minute
        XCTAssertLessThan(abs(after.x - before.x) + abs(after.y - before.y), 0.5)
    }

    func testSameSeedsRetraceTheSameWalk() {
        XCTAssertEqual(walk(seed: 9, frames: 600).poses, walk(seed: 9, frames: 600).poses)
        XCTAssertNotEqual(walk(seed: 9, frames: 600).poses, walk(seed: 10, frames: 600).poses)
    }

    func testAOneCellMazeStaysPutInsteadOfLoopingForever() {
        let maze = Maze(width: 1, height: 1, seed: 1)
        var walker = MazeWalker(maze: maze, seed: 1)
        let start = walker.pose
        for _ in 0..<100 { walker.advance(by: frame) }
        XCTAssertEqual(walker.pose, start)
    }
}

final class MazeRenderingTests: XCTestCase {
    private let ciContext = CIContext()

    private func average(_ image: CIImage, in rect: CGRect) -> (r: Double, g: Double, b: Double) {
        let area = image.cropped(to: rect).applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
        var pixel = [Float](repeating: 0, count: 4)
        ciContext.render(area, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBAf, colorSpace: TestSupport.srgb)
        return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }

    private func save(_ image: CIImage, as name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] else { return }
        try ciContext.writePNGRepresentation(of: image, to: URL(fileURLWithPath: folder).appendingPathComponent(name),
                                             format: .RGBA8, colorSpace: TestSupport.srgb)
    }

    func testTheMazeRendersBrickCorridorsTheRightWayUp() throws {
        let stage = MazeStage(seed: 11)
        var image = try XCTUnwrap(stage.frame(at: 0))
        for tick in 1...240 {                                           // eight seconds at 30 fps
            image = try XCTUnwrap(stage.frame(at: Double(tick) / 30))
            if tick == 60 || tick == 150 { try save(image, as: "maze-\(tick).png") }
        }
        try save(image, as: "maze.png")

        let whole = average(image, in: image.extent)
        XCTAssertGreaterThan(whole.r + whole.g + whole.b, 0.15, "the corridor should be lit, not black")
        XCTAssertGreaterThan(whole.r, whole.b * 1.15, "brick walls should make the picture warm and red, got \(whole)")

        let w = image.extent.width, h = image.extent.height
        let floor = average(image, in: CGRect(x: w * 0.3, y: 0, width: w * 0.4, height: h * 0.15))
        let ceiling = average(image, in: CGRect(x: w * 0.3, y: h * 0.85, width: w * 0.4, height: h * 0.15))
        print(String(format: "MAZE-LOOK floor %.2f, ceiling %.2f, whole %.2f/%.2f/%.2f",
                     floor.r + floor.g + floor.b, ceiling.r + ceiling.g + ceiling.b, whole.r, whole.g, whole.b))
        XCTAssertGreaterThan(floor.r + floor.g + floor.b, ceiling.r + ceiling.g + ceiling.b, "the floor (pale tile) should be at the bottom")
    }

    func testBrickTextureHasBothBrickAndMortarAndTilesWithoutAFlatTile() throws {
        let tile = MazeTextures.bricks()
        XCTAssertEqual(tile.width, 256)
        XCTAssertEqual(tile.height, 256)
        let image = CIImage(cgImage: tile)
        // Seen 2×2, as a wall repeats it, so a seam would show up when I look at the saved picture.
        let tiled = image.transformed(by: CGAffineTransform(translationX: 256, y: 0)).composited(over: image)
            .composited(over: image.transformed(by: CGAffineTransform(translationX: 0, y: 256)))
            .composited(over: image.transformed(by: CGAffineTransform(translationX: 256, y: 256)))
            .transformed(by: CGAffineTransform(translationX: 0, y: 0))
        try save(tiled.cropped(to: CGRect(x: 0, y: 0, width: 512, height: 512)), as: "bricks-tiled.png")

        let mortar = TestSupport.pixel(image, x: 1, y: 1, context: ciContext)
        XCTAssertGreaterThan(mortar.r, 140, "the tile's corner should be pale mortar")
        let brick = TestSupport.pixel(image, x: 32, y: 16, context: ciContext)
        XCTAssertGreaterThan(brick.r, brick.b + 40, "the middle of a brick should be red")
    }

    func testRenderingStaysWellInsideTheFrameBudget() throws {
        let stage = MazeStage(seed: 21)
        var durations: [Double] = []
        for tick in 0..<900 {                                           // thirty seconds
            let start = CFAbsoluteTimeGetCurrent()
            _ = stage.frame(at: Double(tick) / 30)
            durations.append(CFAbsoluteTimeGetCurrent() - start)
        }
        let mean = durations.reduce(0, +) / Double(durations.count)
        print(String(format: "MAZE-PERF mean %.1f ms, worst %.1f ms per frame", mean * 1000, (durations.max() ?? 0) * 1000))
        XCTAssertLessThan(mean, 0.010)
        XCTAssertLessThan(durations.max() ?? 0, 0.040)
    }

    func testAFreshMazeIsBuiltAfterWalkingFarEnough() throws {
        let stage = MazeStage(seed: 5)
        XCTAssertEqual(stage.mazesBuilt, 1)
        let first = (0..<stage.maze.height).flatMap { y in (0..<stage.maze.width).map { stage.maze.openDirections(from: Maze.Cell($0, y)).count } }
        var t = 0.0
        while stage.mazesBuilt == 1 && t < 900 { _ = stage.frame(at: t); t += 0.25 }   // 0.25 s is the longest step the walker takes
        XCTAssertEqual(stage.mazesBuilt, 2, "after a long walk it should switch to a new maze")
        XCTAssertLessThan(t, 900)
        let second = (0..<stage.maze.height).flatMap { y in (0..<stage.maze.width).map { stage.maze.openDirections(from: Maze.Cell($0, y)).count } }
        XCTAssertNotEqual(first, second)
        XCTAssertNotNil(stage.frame(at: t + 0.1), "and keep rendering across the switch")
    }

    func testSourceBuildsLazilyAndRebuildsAfterStop() {
        let source = MazeSource()
        let camera = TestSupport.solid(0, 0, 0)
        XCTAssertNotNil(source.frame(at: 0, camera: camera))
        source.stop()
        XCTAssertNotNil(source.frame(at: 1, camera: camera))
    }

    func testMazeIsABuiltInAndOldLibrariesStillDecode() throws {
        XCTAssertTrue(Background.builtIns.contains(.maze))
        XCTAssertTrue(Background.maze.isLive)
        XCTAssertEqual(Set(Background.builtIns.map(\.id)).count, Background.builtIns.count, "IDs must stay unique")
        let round = try JSONDecoder().decode(Background.self, from: JSONEncoder().encode(Background.maze))
        XCTAssertEqual(round, Background.maze)
    }
}
