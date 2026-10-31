import CoreImage
import simd
import XCTest

private let frame = CGSize(width: 1280, height: 720)
private func world(_ scene: SyntheticScene?) -> GameWorld { GameWorld(size: frame, matte: nil, motion: nil, face: scene?.face()) }

// MARK: - Copy Cat

final class FaceGameCopyCatTests: XCTestCase {
    private let dt = 1.0 / 30

    private func run(_ game: inout CopyCatGame, _ seconds: Double, _ scene: SyntheticScene?) {
        for _ in 0..<Int((seconds / dt).rounded()) { game.step(dt, world: world(scene)) }
    }

    func testEveryFaceIsRecognisedWhenHeld() {
        for pose in CopyCatGame.Pose.allCases {
            var game = CopyCatGame(size: frame, seed: 1)
            game.show(pose)
            run(&game, 0.8, faceGameCopy(pose))
            XCTAssertEqual(game.copies, 1, "\(pose) should be copied")
            XCTAssertGreaterThanOrEqual(game.score, 10)
            XCTAssertEqual(game.hearts, CopyCatGame.lives)
        }
    }

    func testTheWrongFaceIsNotACopy() {
        var game = CopyCatGame(size: frame, seed: 2)
        game.show(.browsUp)
        run(&game, 1.5, faceGameScene(smile: 1))
        XCTAssertEqual(game.copies, 0)
        game.show(.tiltLeft)
        run(&game, 1.5, faceGameScene(roll: -0.3))
        XCTAssertEqual(game.copies, 0, "tipping the other way doesn't count")
    }

    func testAFlickeringReadingIsNotACopy() {
        var game = CopyCatGame(size: frame, seed: 3)
        game.show(.openWide)
        for i in 0..<45 { game.step(dt, world: world(faceGameScene(mouth: i % 2 == 0 ? 0.9 : 0))) }
        XCTAssertEqual(game.copies, 0, "a mouth that flashes open every other frame is noise")
    }

    func testAQuickCopyEarnsTheBonus() {
        var game = CopyCatGame(size: frame, seed: 4)
        game.show(.smile)
        run(&game, 0.7, faceGameCopy(.smile))
        XCTAssertEqual(game.score, 15)
        var slow = CopyCatGame(size: frame, seed: 4)
        slow.show(.smile)
        run(&slow, 2.0, faceGameScene())
        run(&slow, 0.7, faceGameCopy(.smile))
        XCTAssertEqual(slow.score, 10)
    }

    func testRunningOutOfTimeCostsAHeartAndThreeEndTheRound() {
        var game = CopyCatGame(size: frame, seed: 5)
        game.show(.browsUp)
        run(&game, CopyCatGame.timeLimit(afterCopies: 0) + 0.2, faceGameScene())
        XCTAssertEqual(game.hearts, 2)
        XCTAssertEqual(game.outcome, .missed)
        run(&game, 30, faceGameScene())
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.hearts, 0)
        let score = game.score
        run(&game, 2, faceGameCopy(game.current))
        XCTAssertEqual(game.score, score, "nothing scores after the end")
    }

    func testANewCardFollowsACopyAndItIsADifferentFace() {
        var game = CopyCatGame(size: frame, seed: 6)
        game.show(.eyesShut)
        run(&game, 0.6, faceGameCopy(.eyesShut))
        XCTAssertEqual(game.outcome, .copied)
        run(&game, 0.8, faceGameScene())
        XCTAssertNil(game.outcome)
        XCTAssertNotEqual(game.current, .eyesShut)
    }

    func testTheCardsGetFasterButNeverTooFast() {
        XCTAssertGreaterThan(CopyCatGame.timeLimit(afterCopies: 0), CopyCatGame.timeLimit(afterCopies: 10))
        XCTAssertEqual(CopyCatGame.timeLimit(afterCopies: 100), 2.4, accuracy: 1e-9)
    }

    func testNoFaceStopsTheTimer() {
        var game = CopyCatGame(size: frame, seed: 7)
        game.show(.smile)
        let left = game.timeLeft
        run(&game, 10, nil)
        XCTAssertEqual(game.timeLeft, left)
        XCTAssertEqual(game.hearts, CopyCatGame.lives)
    }

    func testAHugeStepAndTheSameSeed() {
        var game = CopyCatGame(size: frame, seed: 8)
        game.step(30, world: world(faceGameScene()))
        XCTAssertEqual(game.hearts, CopyCatGame.lives, "a stall doesn't run the timer out")
        var a = CopyCatGame(size: frame, seed: 9), b = CopyCatGame(size: frame, seed: 9)
        var seenA: [CopyCatGame.Pose] = [], seenB: [CopyCatGame.Pose] = []
        for _ in 0..<(30 * 20) {
            a.step(dt, world: world(faceGameCopy(a.current)))
            b.step(dt, world: world(faceGameCopy(b.current)))
            if seenA.last != a.current { seenA.append(a.current) }
            if seenB.last != b.current { seenB.append(b.current) }
        }
        XCTAssertEqual(seenA, seenB)
        XCTAssertGreaterThan(a.copies, 8, "a player who copies at once copies plenty")
    }
}

// MARK: - Space Blaster

final class FaceGameSpaceBlasterTests: XCTestCase {
    private let dt = 1.0 / 60

    private func run(_ game: inout SpaceBlasterGame, _ seconds: Double, _ scene: SyntheticScene?) {
        for _ in 0..<Int((seconds / dt).rounded()) { game.step(dt, world: world(scene)) }
    }

    func testMovingTheHeadSteersTheShip() {
        var game = SpaceBlasterGame(size: frame, seed: 1)
        game.place(rocks: [])
        run(&game, 0.5, faceGameScene())
        XCTAssertEqual(game.shipX, 640, accuracy: 2)
        run(&game, 1.5, faceGameScene(at: CGPoint(x: 640 + 84, y: 420)))
        XCTAssertEqual(game.shipX, 640 + SpaceBlasterGame.reach, accuracy: 4, "one eye-spacing moves it the reach")
        run(&game, 1.5, faceGameScene(at: CGPoint(x: 100, y: 420)))
        XCTAssertGreaterThanOrEqual(game.shipX, 90, "and it stays on screen")
    }

    func testAnOpenMouthFiresAndAShutOneDoesNot() {
        var game = SpaceBlasterGame(size: frame, seed: 2)
        game.place(rocks: [])
        run(&game, 1, faceGameScene())
        XCTAssertEqual(game.shots, 0)
        run(&game, 1, faceGameScene(mouth: 0.8))
        XCTAssertEqual(Double(game.shots), 1 / SpaceBlasterGame.fireInterval, accuracy: 1.5)
        let shots = game.shots
        run(&game, 1, faceGameScene())
        XCTAssertEqual(game.shots, shots)
    }

    func testABoltSplitsABigRockAndASmallOneIsGone() {
        // One quick open of the mouth fires exactly one bolt.
        func oneShot(at rock: SpaceBlasterGame.Rock) -> SpaceBlasterGame {
            var game = SpaceBlasterGame(size: frame, seed: 3)
            game.place(rocks: [rock])
            run(&game, 0.05, faceGameScene(mouth: 0.8))
            run(&game, 0.6, faceGameScene())
            XCTAssertEqual(game.shots, 1)
            return game
        }
        let big = oneShot(at: SpaceBlasterGame.Rock(position: SIMD2(640, 420), velocity: .zero, radius: SpaceBlasterGame.bigRadius))
        XCTAssertEqual(big.score, 10)
        XCTAssertEqual(big.destroyed, 1)
        XCTAssertEqual(big.rocks.count, 2, "it broke into two small pieces")
        XCTAssertTrue(big.rocks.allSatisfy { !$0.big })
        let small = oneShot(at: SpaceBlasterGame.Rock(position: SIMD2(640, 420), velocity: .zero, radius: SpaceBlasterGame.smallRadius))
        XCTAssertEqual(small.score, 15)
        XCTAssertTrue(small.rocks.isEmpty)
    }

    func testARockHittingTheShipCostsOneHeartThenAMomentOfSafety() {
        var game = SpaceBlasterGame(size: frame, seed: 4)
        let rock = SpaceBlasterGame.Rock(position: SIMD2(640, SpaceBlasterGame.shipY + 10), velocity: .zero, radius: SpaceBlasterGame.bigRadius)
        game.place(rocks: [rock, rock])
        run(&game, 0.1, faceGameScene())
        XCTAssertEqual(game.hearts, 2, "one heart, not two, for rocks arriving together")
        game.place(rocks: [rock])
        run(&game, 0.1, faceGameScene())
        XCTAssertEqual(game.hearts, 2, "still safe")
        game.place(rocks: [])
        run(&game, 2, faceGameScene())
        game.place(rocks: [rock])
        run(&game, 0.1, faceGameScene())
        XCTAssertEqual(game.hearts, 1)
    }

    func testNobodyThereHoldsSpaceStill() {
        var game = SpaceBlasterGame(size: frame, seed: 5)
        game.place(rocks: [SpaceBlasterGame.Rock(position: SIMD2(300, 500), velocity: SIMD2(0, -200), radius: 30)])
        run(&game, 2, nil)
        XCTAssertEqual(game.rocks.first?.position.y, 500)
        XCTAssertEqual(game.elapsed, 0)
    }

    func testAPilotWhoStaysStillLosesInTheEndAndTheSameSeedFliesTheSame() {
        var a = SpaceBlasterGame(size: frame, seed: 6), b = SpaceBlasterGame(size: frame, seed: 6)
        for _ in 0..<(60 * 120) where !a.isOver {
            a.step(dt, world: world(faceGameScene()))
            b.step(dt, world: world(faceGameScene()))
        }
        XCTAssertTrue(a.isOver, "the rocks get you eventually")
        XCTAssertEqual(a.rocks, b.rocks)
        var big = SpaceBlasterGame(size: frame, seed: 7)
        big.step(30, world: world(faceGameScene()))
        XCTAssertLessThanOrEqual(big.elapsed, 0.1 + 1e-9)
    }
}

// MARK: - Keepy Uppy

final class FaceGameKeepyUppyTests: XCTestCase {
    private let dt = 1.0 / 60

    private func run(_ game: inout FaceKeepyUppyGame, _ seconds: Double, _ scene: SyntheticScene?) {
        for _ in 0..<Int((seconds / dt).rounded()) { game.step(dt, world: world(scene)) }
    }

    func testTheBallBouncesOffTheHead() throws {
        var game = FaceKeepyUppyGame(size: frame, seed: 1)
        let person = faceGameScene(at: CGPoint(x: 640, y: 360))
        run(&game, 0.2, person)
        let head = try XCTUnwrap(game.head)
        game.placeBall(at: CGPoint(x: head.x + 10, y: head.y + game.headRadius + 120), velocity: SIMD2(0, -300))
        for _ in 0..<30 where game.score == 0 { game.step(dt, world: world(person)) }
        XCTAssertEqual(game.score, 1)
        XCTAssertGreaterThan(game.velocity.y, FaceKeepyUppyGame.minimumKick - 1, "on its way back up")
        XCTAssertGreaterThan(game.ball.y, head.y + game.headRadius)
        for _ in 0..<30 {
            game.step(dt, world: world(person))
            XCTAssertLessThanOrEqual(game.ball.y, frame.height - FaceKeepyUppyGame.ballRadius + 1e-6, "the top of the picture is a ceiling")
        }
    }

    func testABallThatMissesTheHeadIsDropped() {
        var game = FaceKeepyUppyGame(size: frame, seed: 2)
        let person = faceGameScene(at: CGPoint(x: 640, y: 360))
        run(&game, 0.2, person)
        game.placeBall(at: CGPoint(x: 120, y: 600), velocity: SIMD2(0, -200))
        run(&game, 2, person)
        XCTAssertEqual(game.hearts, 2)
        XCTAssertEqual(game.score, 0)
        XCTAssertGreaterThan(game.serving, 0, "a new ball is on its way")
    }

    func testAPlayerWhoFollowsTheBallKeepsItUp() {
        var game = FaceKeepyUppyGame(size: frame, seed: 3)
        var x = 640.0
        for _ in 0..<(60 * 40) {
            x = faceGameSlew(x, toward: game.ball.x, limit: 14)
            game.step(dt, world: world(faceGameScene(at: CGPoint(x: x, y: 360))))
        }
        XCTAssertGreaterThan(game.score, 15)
        XCTAssertEqual(game.hearts, FaceKeepyUppyGame.lives, "never dropped it")
        XCTAssertTrue(game.ball.x >= 0 && game.ball.x <= frame.width)
    }

    func testStandingStillLosesEveryBallAndTheSameSeedPlaysTheSame() {
        var a = FaceKeepyUppyGame(size: frame, seed: 4), b = FaceKeepyUppyGame(size: frame, seed: 4)
        for _ in 0..<(60 * 60) where !a.isOver {
            a.step(dt, world: world(faceGameScene(at: CGPoint(x: 200, y: 360))))
            b.step(dt, world: world(faceGameScene(at: CGPoint(x: 200, y: 360))))
        }
        XCTAssertTrue(a.isOver)
        XCTAssertEqual(a.ball, b.ball)
        XCTAssertEqual(a.score, b.score)
    }

    func testNobodyThereFreezesTheBallAndAHugeStepDoesNotTunnel() throws {
        var game = FaceKeepyUppyGame(size: frame, seed: 5)
        let person = faceGameScene(at: CGPoint(x: 640, y: 360))
        run(&game, 0.2, person)
        game.placeBall(at: CGPoint(x: 640, y: 650), velocity: SIMD2(0, -100))
        run(&game, 2, nil)
        XCTAssertEqual(game.ball.y, 650)
        run(&game, 0.05, person)
        let head = try XCTUnwrap(game.head)
        game.placeBall(at: CGPoint(x: head.x, y: head.y + game.headRadius + 100), velocity: SIMD2(0, -900))
        game.step(30, world: world(person))
        XCTAssertGreaterThan(game.ball.y, head.y, "it didn't fall through the head")
        XCTAssertEqual(game.score, 1)
    }
}

// MARK: - Tilt Racer

final class FaceGameTiltRacerTests: XCTestCase {
    private let dt = 1.0 / 60

    private func run(_ game: inout TiltRacerGame, _ seconds: Double, _ scene: SyntheticScene?) {
        for _ in 0..<Int((seconds / dt).rounded()) { game.step(dt, world: world(scene)) }
    }

    func testTippingTheHeadSteersTheWayTheHeadLeans() {
        var game = TiltRacerGame(size: frame, seed: 1)
        game.place(cars: [])
        run(&game, 1.5, faceGameScene(roll: 0.15))
        XCTAssertEqual(game.playerX, -0.5, accuracy: 0.03, "the top of the head leans left in the picture, so the car goes left")
        run(&game, 1.5, faceGameScene(roll: -0.6))
        XCTAssertEqual(game.playerX, 0.92, accuracy: 0.02, "never off the road")
        run(&game, 1.5, faceGameScene())
        XCTAssertEqual(game.playerX, 0, accuracy: 0.02)
    }

    func testACarInYourLaneIsACrashAndSwervingMissesIt() {
        var game = TiltRacerGame(size: frame, seed: 2)
        game.place(cars: [TiltRacerGame.Car(x: 0, z: 20, speed: 0, paint: 0)])
        run(&game, 2, faceGameScene())
        XCTAssertEqual(game.hearts, 2)
        XCTAssertEqual(game.passed, 0, "a car you hit doesn't count as passed")

        var dodger = TiltRacerGame(size: frame, seed: 2)
        dodger.place(cars: [TiltRacerGame.Car(x: 0, z: 20, speed: 0, paint: 0)])
        run(&dodger, 2, faceGameScene(roll: -0.2))
        XCTAssertEqual(dodger.hearts, TiltRacerGame.lives)
        XCTAssertEqual(dodger.passed, 1)
        XCTAssertEqual(dodger.score, 10)
    }

    func testCoinsInYourLaneAreCollected() {
        var game = TiltRacerGame(size: frame, seed: 3)
        game.place(cars: [], coins: [TiltRacerGame.Coin(x: 0, z: 10), TiltRacerGame.Coin(x: 2.0 / 3, z: 12)])
        run(&game, 1.5, faceGameScene())
        XCTAssertEqual(game.score, 25)
    }

    func testTheTrafficNeverBlocksEveryLaneAndAGoodDriverLastsAMinute() {
        for seed in 1...3 as ClosedRange<UInt64> {
            var game = TiltRacerGame(size: frame, seed: seed)
            var roll = 0.0
            for _ in 0..<(60 * 60) where !game.isOver {
                roll = faceGameSlew(roll, toward: faceGameRacerRoll(game), limit: 0.02)
                game.step(dt, world: world(faceGameScene(roll: roll)))
                let ahead = game.cars.filter { $0.z > TiltRacerGame.farZ - TiltRacerGame.fairGap }.map(\.x)
                XCTAssertFalse(TiltRacerGame.lanes.allSatisfy { lane in ahead.contains { abs($0 - lane) < 0.2 } }, "seed \(seed): every lane blocked")
            }
            XCTAssertGreaterThanOrEqual(game.hearts, 2, "seed \(seed)")
            XCTAssertGreaterThan(game.passed, 15, "seed \(seed)")
        }
    }

    func testTheViewAndTheBasics() {
        var game = TiltRacerGame(size: frame, seed: 4)
        XCTAssertEqual(game.screenY(0), TiltRacerGame.playerY, accuracy: 1e-9)
        XCTAssertLessThan(game.screenY(TiltRacerGame.farZ), TiltRacerGame.horizonY)
        XCTAssertGreaterThan(game.screenY(TiltRacerGame.farZ), TiltRacerGame.horizonY - 10)
        run(&game, 2, nil)
        XCTAssertEqual(game.distance, 0, "no driver, no driving")
        game.step(30, world: world(faceGameScene()))
        XCTAssertLessThanOrEqual(game.distance, game.speed * 0.1 + 1e-6)
        var a = TiltRacerGame(size: frame, seed: 5), b = TiltRacerGame(size: frame, seed: 5)
        run(&a, 20, faceGameScene())
        run(&b, 20, faceGameScene())
        XCTAssertEqual(a.cars, b.cars)
    }
}

// MARK: - Bubble Gum

final class FaceGameBubbleGumTests: XCTestCase {
    private let dt = 1.0 / 30

    private func run(_ game: inout BubbleGumGame, _ seconds: Double, _ scene: SyntheticScene?) {
        for _ in 0..<Int((seconds / dt).rounded()) { game.step(dt, world: world(scene)) }
    }

    func testBlowingGrowsTheBubbleAndClosingKeepsIt() {
        var game = BubbleGumGame(size: frame, seed: 1)
        game.setPopPoint(1)
        run(&game, 1.5, faceGameScene(mouth: 0.8))
        let size = game.bubble
        XCTAssertGreaterThan(size, 0.3)
        run(&game, 0.5, faceGameScene())
        XCTAssertEqual(game.bubble, 0)
        XCTAssertEqual(game.kept, 1)
        XCTAssertEqual(game.score, BubbleGumGame.points(for: size), "scored by its size")
        XCTAssertEqual(game.floating.count, 1, "and it floats away")
        XCTAssertEqual(game.hearts, BubbleGumGame.lives)
    }

    func testBlowingPastTheBreakingPointPopsIt() {
        var game = BubbleGumGame(size: frame, seed: 2)
        game.setPopPoint(0.3)
        run(&game, 3, faceGameScene(mouth: 0.8))
        XCTAssertEqual(game.hearts, 2)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.bubble, 0, "and no new bubble while the mouth stays open")
        run(&game, 0.5, faceGameScene())
        run(&game, 0.5, faceGameScene(mouth: 0.8))
        XCTAssertGreaterThan(game.bubble, 0, "close, then open again, for a new one")
    }

    func testATinyBubbleIsNeitherScoredNorLost() {
        var game = BubbleGumGame(size: frame, seed: 3)
        run(&game, 0.3, faceGameScene(mouth: 0.8))
        XCTAssertLessThan(game.bubble, BubbleGumGame.smallest)
        run(&game, 1, faceGameScene())
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.kept, 0)
        XCTAssertEqual(game.hearts, BubbleGumGame.lives)
    }

    func testAMouthThatFlickersShutForAFrameDoesNotLetGo() {
        var game = BubbleGumGame(size: frame, seed: 4)
        game.setPopPoint(1)
        for i in 0..<45 { game.step(dt, world: world(faceGameScene(mouth: i % 5 == 4 ? 0 : 0.8))) }
        XCTAssertEqual(game.kept, 0)
        XCTAssertGreaterThan(game.bubble, 0.3, "still blowing the same bubble")
    }

    func testTheRoundEndsAfterThreePopsOrAMinute() {
        var popper = BubbleGumGame(size: frame, seed: 5)
        for _ in 0..<(30 * 40) where !popper.isOver {
            let mouth = popper.bubble == 0 && popper.elapsed.truncatingRemainder(dividingBy: 6) > 5 ? 0 : 0.8
            popper.step(dt, world: world(faceGameScene(mouth: mouth)))
        }
        XCTAssertTrue(popper.isOver)
        XCTAssertEqual(popper.hearts, 0)
        XCTAssertEqual(popper.ending, .lost("POP!"))

        var careful = BubbleGumGame(size: frame, seed: 6)
        run(&careful, 61, faceGameScene())
        XCTAssertTrue(careful.isOver)
        XCTAssertEqual(careful.ending, .timeUp("TIME'S UP!"))
    }

    func testNobodyThereHoldsEverything() {
        var game = BubbleGumGame(size: frame, seed: 7)
        game.setPopPoint(1)
        run(&game, 1, faceGameScene(mouth: 0.8))
        let (size, left) = (game.bubble, game.timeLeft)
        run(&game, 3, nil)
        XCTAssertEqual(game.bubble, size)
        XCTAssertEqual(game.timeLeft, left)
        game.step(30, world: world(faceGameScene(mouth: 0.8)))
        XCTAssertLessThan(game.bubble - size, 0.1, "a stall doesn't blow it up")
    }
}

// MARK: - The lens that runs them

final class FaceGameLensRunnerTests: XCTestCase {
    private func drive<G: FaceGame>(_ lens: FaceGameLens<G>, _ h: LensHarness, _ base: LensInput, seconds: Double, time: inout Double,
                                    face: (Int) -> FaceState?) -> CIImage {
        var out = base.composed
        for i in 0..<Int(seconds * 30) {
            out = lens.render(LensInput(time: time, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: base.background,
                                        composed: base.composed, matteGrid: nil, face: face(i), services: base.services))
            time += 1.0 / 30
        }
        return out
    }

    func testAFlickeringFaceStillStartsARoundButAnEmptyRoomDoesNot() {
        let h = LensHarness()
        let base = h.input(wantsGrid: false)
        var time = 0.0
        let lens = FaceGameLens<MouthCatchGame>(id: "test.flicker", store: MemoryScoreStore())
        _ = drive(lens, h, base, seconds: 3, time: &time) { _ in nil }
        XCTAssertEqual(lens.phase, .waiting)
        _ = drive(lens, h, base, seconds: 1.5, time: &time) { i in i % 3 == 2 ? nil : SyntheticScene().face() }
        guard case .countdown = lens.phase else { return XCTFail("a face seen two frames in three should start a round, got \(lens.phase)") }
    }

    func testTheStatusSaysHowTheRoundEnded() {
        let h = LensHarness()
        let base = h.input(wantsGrid: false)
        var time = 0.0
        let lens = FaceGameLens<MouthCatchGame>(id: "test.status", store: MemoryScoreStore())
        lens.restart()
        XCTAssertEqual(lens.status?.title, "Get ready…")
        _ = drive(lens, h, base, seconds: 3.2, time: &time) { _ in SyntheticScene().face() }
        XCTAssertEqual(lens.phase, .playing)
        XCTAssertEqual(lens.status?.title, "Score 0")
        _ = drive(lens, h, base, seconds: MouthCatchGame.roundSeconds + 0.5, time: &time) { _ in SyntheticScene().face() }
        guard case .over = lens.phase else { return XCTFail("expected the end, got \(lens.phase)") }
        XCTAssertTrue(lens.status?.title.hasPrefix("Time's up: ") ?? false, "\(String(describing: lens.status))")
        _ = drive(lens, h, base, seconds: FaceGameLens<MouthCatchGame>.gameOverSeconds + 0.2, time: &time) { _ in SyntheticScene().face() }
        guard case .countdown = lens.phase else { return XCTFail("still there: straight into the next round, got \(lens.phase)") }
    }

    func testEveryGameRendersInEveryStageWithAndWithoutAFace() {
        func exercise<G: FaceGame>(_ type: G.Type) {
            let h = LensHarness()
            let base = h.input(wantsGrid: false)
            var time = 0.0
            let lens = FaceGameLens<G>(id: "test.\(G.title)", store: MemoryScoreStore())
            for (seconds, present) in [(1.0, false), (1.0, true), (4.0, true), (2.0, false), (1.0, true)] {
                let out = drive(lens, h, base, seconds: seconds, time: &time) { _ in present ? SyntheticScene().face() : nil }
                XCTAssertEqual(out.extent.size, frame, G.title)
            }
            XCTAssertEqual(lens.phase, .playing, G.title)
            // A huge stall and a tilted, far face don't break anything.
            let stalled = lens.render(LensInput(time: time, dt: 5, rect: base.rect, camera: base.camera, matte: nil, background: nil, composed: base.composed,
                                                matteGrid: nil, face: SyntheticScene(center: CGPoint(x: 300, y: 500), scale: 0.4, roll: 0.6).face(), services: base.services))
            XCTAssertEqual(stalled.extent.size, frame, G.title)
        }
        exercise(MouthCatchGame.self)
        exercise(FlappyFaceGame.self)
        exercise(StaringContestGame.self)
        exercise(BrowRunnerGame.self)
        exercise(FaceSnakeGame.self)
        exercise(CopyCatGame.self)
        exercise(SpaceBlasterGame.self)
        exercise(FaceKeepyUppyGame.self)
        exercise(TiltRacerGame.self)
        exercise(BubbleGumGame.self)
    }

    /// The pictures each game keeps are drawn the first time they are needed, on the video queue. That first frame must not stall.
    func testTheFirstFramesDoNotStall() {
        func worst<G: FaceGame>(_ type: G.Type) -> Double {
            FaceGameArt.forgetAll()
            let h = LensHarness()
            let base = h.input(wantsGrid: false)
            let lens = FaceGameLens<G>(id: "test.first.\(G.title)", store: MemoryScoreStore())
            var time = 0.0, slowest = 0.0
            for i in 0..<Int(30 * 4.5) {
                let start = CFAbsoluteTimeGetCurrent()
                _ = lens.render(LensInput(time: time, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: base.background,
                                          composed: base.composed, matteGrid: nil, face: faceGameScene(mouth: i % 40 < 20 ? 0.7 : 0).face(), services: base.services))
                slowest = max(slowest, (CFAbsoluteTimeGetCurrent() - start) * 1000)
                time += 1.0 / 30
            }
            return slowest
        }
        var lines: [String] = []
        for (name, ms) in [("mouth", worst(MouthCatchGame.self)), ("flappy", worst(FlappyFaceGame.self)), ("staring", worst(StaringContestGame.self)),
                           ("runner", worst(BrowRunnerGame.self)), ("snake", worst(FaceSnakeGame.self)), ("copycat", worst(CopyCatGame.self)),
                           ("blaster", worst(SpaceBlasterGame.self)), ("keepy", worst(FaceKeepyUppyGame.self)), ("racer", worst(TiltRacerGame.self)),
                           ("bubble", worst(BubbleGumGame.self))] {
            lines.append(String(format: "%@ %.1f", name, ms))
            // About 30 ms on a quiet machine at most; the margin is for a busy one.
            XCTAssertLessThan(ms, 60, "\(name) stalls while it draws its pictures for the first time")
        }
        print("FACEGAME WORST FIRST FRAMES MS: " + lines.joined(separator: ", "))
    }

    /// The middle cost of a frame (lens and render) over many frames: steadier than the mean on a busy machine.
    private func medianCost(of lens: Lens, _ h: LensHarness, base: LensInput, frames: Int = 60) -> Double {
        guard let buffer = h.compositor.makeOutputBuffer() else { return 0 }
        var durations: [Double] = []
        for i in 0..<frames {
            let started = CFAbsoluteTimeGetCurrent()
            h.compositor.render(lens.render(h.at(base, time: Double(i) / 30)), into: buffer)
            durations.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        return durations.sorted()[frames / 2]
    }

    func testEveryGameFitsTheFrameBudget() {
        let h = LensHarness()
        let base = h.input(wantsGrid: false)
        func measure<G: FaceGame>(_ type: G.Type) -> Double {
            var time = 0.0
            let lens = FaceGameLens<G>(id: "test.\(G.title)", store: MemoryScoreStore())
            lens.restart()
            _ = drive(lens, h, base, seconds: 5, time: &time) { _ in faceGameScene(mouth: 0.6).face() }
            return medianCost(of: lens, h, base: base)
        }
        final class Plain: Lens { let needs: LensNeeds = []; func render(_ input: LensInput) -> CIImage { input.composed } }
        let baseline = medianCost(of: Plain(), h, base: base)
        var lines: [String] = []
        for (name, ms) in [("mouth", measure(MouthCatchGame.self)), ("flappy", measure(FlappyFaceGame.self)), ("staring", measure(StaringContestGame.self)),
                           ("runner", measure(BrowRunnerGame.self)), ("snake", measure(FaceSnakeGame.self)), ("copycat", measure(CopyCatGame.self)),
                           ("blaster", measure(SpaceBlasterGame.self)), ("keepy", measure(FaceKeepyUppyGame.self)), ("racer", measure(TiltRacerGame.self)),
                           ("bubble", measure(BubbleGumGame.self))] {
            lines.append(String(format: "%@ %.1f", name, ms - baseline))
            XCTAssertLessThan(ms - baseline, 9, "\(name) adds too much to every frame")
        }
        print("FACEGAME COST (ms over a \(String(format: "%.1f", baseline)) ms baseline): " + lines.joined(separator: ", "))
    }
}
