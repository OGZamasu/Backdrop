import CoreImage
import simd
import XCTest

private let frame = CGSize(width: 1280, height: 720)

private func world(_ body: [CGRect]? = nil, motion: [CGRect]? = nil) -> GameWorld {
    GameWorld(size: frame, matte: body.map { BodyRectsMatte(rects: $0) }, motion: motion.map { BodyRectsMatte(rects: $0) }, face: nil)
}

/// A person standing normally: shoulders, a neck, a head `u` pixels across whose top is at `top`.
private func person(cx: Double = 640, u: Double = 200, top: Double = 560) -> BodyFrame {
    BodyFrame(left: cx - 1.35 * u, right: cx + 1.35 * u, top: top, bottom: 0, headWidth: u, shoulderY: top - 1.5 * u)
}

private extension BodyFrame {
    /// The rectangles of this person with the head and neck moved sideways by `lean` and everything moved down by `duck`.
    func pose(lean: Double = 0, duck: Double = 0) -> [CGRect] {
        let rects = neutralRects
        return rects.enumerated().map { i, r in
            (i == 0 ? r : r.offsetBy(dx: lean, dy: 0)).offsetBy(dx: 0, dy: -duck)
        }
    }
}

// MARK: - Keepy Uppy

final class BodyGameKeepyUppyTests: XCTestCase {
    private let floor = [CGRect(x: 440, y: 0, width: 400, height: 400)]

    func testAStillBodyBouncesTheBallSoftlyAndScoresNothing() {
        var game = KeepyUppyGame(size: frame, seed: 1)
        game.place(ball: SIMD2(640, 600), velocity: SIMD2(0, -200))
        var highest = 0.0
        for i in 0..<(30 * 6) {
            game.step(1.0 / 30, world: world(floor, motion: []))
            if i > 30 { highest = max(highest, game.ball.y) }
        }
        XCTAssertEqual(game.hits, 0, "a still body is not a hit")
        XCTAssertEqual(game.score, 0)
        XCTAssertLessThan(highest, 560, "and it never bounces back as high as it fell from")
    }

    func testAMovingBodyKicksTheBallUpAndScores() {
        var game = KeepyUppyGame(size: frame, seed: 2)
        game.place(ball: SIMD2(640, 520), velocity: SIMD2(0, -300))
        var rose = false
        for _ in 0..<12 {
            game.step(1.0 / 30, world: world(floor, motion: floor))
            if game.velocity.y > 400 { rose = true }
        }
        XCTAssertTrue(rose, "a moving body sends the ball up hard")
        XCTAssertEqual(game.hits, 1, "one touch, one hit")
        XCTAssertEqual(game.score, 1)
        XCTAssertGreaterThan(game.ball.y, 470, "and it is clear of the body again")
    }

    func testDroppingTheBallCostsALifeAndThreeDropsEndIt() {
        var game = KeepyUppyGame(size: frame, seed: 3)
        for _ in 0..<(30 * 3) { game.step(1.0 / 30, world: world()) }
        XCTAssertEqual(game.drops, 1)
        XCTAssertEqual(game.lives, 2)
        XCTAssertGreaterThan(game.serving, 0, "the next ball is served")
        XCTAssertGreaterThan(game.ball.y, frame.height * 0.6, "from high up, where it can be seen coming")
        for _ in 0..<(30 * 8) { game.step(1.0 / 30, world: world()) }
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.lives, 0)
    }

    func testKeepingItUpBuildsAStreakWorthMore() {
        var game = KeepyUppyGame(size: frame, seed: 4)
        let ground = [CGRect(x: 0, y: 0, width: 1280, height: 300)]
        var bestValue = 1
        for _ in 0..<(30 * 30) {
            game.step(1.0 / 30, world: world(ground, motion: ground))
            bestValue = max(bestValue, game.hitValue)
        }
        XCTAssertEqual(game.drops, 0, "a body that keeps moving never drops it")
        XCTAssertGreaterThanOrEqual(game.hits, 8)
        XCTAssertGreaterThanOrEqual(bestValue, 2, "five in a row makes a hit worth two")
        XCTAssertGreaterThan(game.score, game.hits, "so the score outruns the hit count")
        XCTAssertTrue(game.ball.x >= KeepyUppyGame.radius && game.ball.x <= frame.width - KeepyUppyGame.radius, "the ball stays in the picture")
    }

    func testKnockingTheBallThroughAStarPaysFive() {
        var game = KeepyUppyGame(size: frame, seed: 5)
        game.placeStar(at: SIMD2(640, 520))
        game.place(ball: SIMD2(640, 380), velocity: SIMD2(0, 650))
        for _ in 0..<10 { game.step(1.0 / 30, world: world()) }
        XCTAssertEqual(game.starsTaken, 1)
        XCTAssertEqual(game.score, 5)
        XCTAssertNil(game.star)
    }

    func testAHugeStepAndNoSilhouetteNeverBreakIt() {
        var game = KeepyUppyGame(size: frame, seed: 6)
        game.place(ball: SIMD2(640, 500), velocity: SIMD2(300, 0))
        game.step(40, world: world(floor, motion: floor))
        XCTAssertTrue(game.ball.x.isFinite && game.ball.y.isFinite)
        XCTAssertLessThanOrEqual(game.elapsed, 0.11, "a stalled frame counts as a short one")
        for _ in 0..<200 { game.step(1.0 / 30, world: GameWorld(size: frame, matte: nil, motion: nil, face: nil)) }
        XCTAssertGreaterThan(game.drops, 0)
    }

    func testSameSeedPlaysTheSame() {
        var a = KeepyUppyGame(size: frame, seed: 7), b = KeepyUppyGame(size: frame, seed: 7)
        let ground = [CGRect(x: 200, y: 0, width: 700, height: 320)]
        for i in 0..<(30 * 20) {
            let moving = i % 20 < 8 ? ground : []
            a.step(1.0 / 30, world: world(ground, motion: moving))
            b.step(1.0 / 30, world: world(ground, motion: moving))
        }
        XCTAssertEqual(a.ball, b.ball)
        XCTAssertEqual(a.score, b.score)
        XCTAssertEqual(a.hits, b.hits)
    }
}

// MARK: - Laser Limbo

final class BodyGameLaserTests: XCTestCase {
    private func play(_ game: inout LaserLimboGame, seconds: Double, body: [CGRect]?) {
        for _ in 0..<Int(seconds * 30) { game.step(1.0 / 30, world: world(body)) }
    }

    func testStandingTallUnderTheBarIsAHitAndDuckingClearsIt() {
        let ref = person()
        var tall = LaserLimboGame(size: frame, seed: 1)
        tall.holdWaves()
        tall.startWave(.duck, around: ref, headAt: ref.centerX)
        play(&tall, seconds: 6, body: ref.pose())
        XCTAssertEqual(tall.lives, 2)
        XCTAssertEqual(tall.cleanWaves, 0)

        var low = LaserLimboGame(size: frame, seed: 1)
        low.holdWaves()
        low.startWave(.duck, around: ref, headAt: ref.centerX)
        play(&low, seconds: 6, body: ref.pose(duck: 1.3 * ref.headWidth))
        XCTAssertEqual(low.lives, 3, "ducking about a head's height is enough")
        XCTAssertEqual(low.cleanWaves, 1)
        XCTAssertEqual(low.bonus, LaserLimboGame.cleanBonus)
        XCTAssertTrue(low.beams.isEmpty, "the wave is over")
    }

    func testLeaningTheWayItSaysClearsTheBlade() {
        for (seed, x) in [(2, 640.0), (3, 300.0), (4, 980.0)] {
            let ref = person(cx: x, u: 170)
            var still = LaserLimboGame(size: frame, seed: UInt64(seed))
            still.holdWaves()
            still.startWave(.lean, around: ref, headAt: x)
            let way = Double(still.leanWay)
            XCTAssertNotEqual(way, 0)
            play(&still, seconds: 5, body: ref.pose())
            XCTAssertEqual(still.lives, 2, "at \(x): a head left where it was is hit")

            var leaning = LaserLimboGame(size: frame, seed: UInt64(seed))
            leaning.holdWaves()
            leaning.startWave(.lean, around: ref, headAt: x)
            play(&leaning, seconds: 5, body: ref.pose(lean: way * 1.0 * ref.headWidth))
            XCTAssertEqual(leaning.lives, 3, "at \(x): leaning a head's width the way it says is enough")
            XCTAssertEqual(leaning.cleanWaves, 1)
        }
    }

    func testMovingIntoTheGapClearsBothBlades() throws {
        let ref = person(u: 180)
        var game = LaserLimboGame(size: frame, seed: 5)
        game.holdWaves()
        game.startWave(.gap, around: ref, headAt: ref.centerX)
        let blades = game.beams.map(\.end).sorted()
        XCTAssertEqual(blades.count, 2)
        let middle = (blades[0] + blades[1]) / 2
        XCTAssertGreaterThan(blades[1] - blades[0], ref.headWidth * 1.5, "the gap is wider than a head")
        XCTAssertGreaterThan(abs(middle - ref.centerX), ref.headWidth * 0.5, "and to one side, so you have to move")
        play(&game, seconds: 5, body: ref.pose(lean: middle - ref.centerX))
        XCTAssertEqual(game.lives, 3)
        XCTAssertEqual(game.cleanWaves, 1)
    }

    func testTheWarningIsHarmlessAndAHitGivesAGracePeriod() {
        var game = LaserLimboGame(size: frame, seed: 6)
        game.holdWaves()
        game.startWave(.duck, around: person(), headAt: 640)
        let everywhere = [CGRect(origin: .zero, size: frame)]
        play(&game, seconds: 1.3, body: everywhere)
        XCTAssertEqual(game.lives, 3, "a beam that has not switched on cannot hurt")
        play(&game, seconds: 1.0, body: everywhere)
        XCTAssertEqual(game.lives, 2)
        XCTAssertGreaterThan(game.graceLeft, 0)
        play(&game, seconds: 1.2, body: everywhere)
        XCTAssertEqual(game.lives, 2, "still touching it during the grace period costs nothing more")
    }

    func testThreeHitsEndItAndNobodyThereIsNeverHit() {
        var game = LaserLimboGame(size: frame, seed: 7)
        let ref = person()
        for _ in 0..<(30 * 90) where !game.isOver { game.step(1.0 / 30, world: world(ref.pose())) }
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.hits, 3)

        var empty = LaserLimboGame(size: frame, seed: 7)
        play(&empty, seconds: 60, body: [])
        XCTAssertEqual(empty.lives, 3)
        XCTAssertGreaterThan(empty.waves, 8, "the waves keep coming")
        XCTAssertGreaterThanOrEqual(empty.score, 60 + LaserLimboGame.cleanBonus * 8)

        var blind = LaserLimboGame(size: frame, seed: 7)
        play(&blind, seconds: 20, body: nil)
        XCTAssertEqual(blind.lives, 3, "no silhouette at all is the same as nobody")
    }

    func testEveryWaveAsksForAMoveAPersonCanMake() {
        // A player who always does what the wave asks never gets hit, whatever the wave and wherever they stand.
        for (seed, x) in [(8, 640.0), (9, 330.0), (10, 950.0)] {
            var game = LaserLimboGame(size: frame, seed: UInt64(seed))
            let ref = person(cx: x, u: 170)
            var seen = Set<String>()
            for _ in 0..<(30 * 70) {
                var pose = ref.pose()
                if let pattern = game.pattern {
                    seen.insert("\(pattern)")
                    switch pattern {
                    case .duck: pose = ref.pose(duck: 1.3 * ref.headWidth)
                    case .lean: pose = ref.pose(lean: Double(game.leanWay) * 1.0 * ref.headWidth)
                    case .gap:
                        let ends = game.beams.map(\.end).sorted()
                        if ends.count == 2 { pose = ref.pose(lean: (ends[0] + ends[1]) / 2 - ref.centerX) }
                    }
                }
                game.step(1.0 / 30, world: world(pose))
            }
            XCTAssertEqual(game.hits, 0, "standing at \(x)")
            XCTAssertEqual(seen.count, 3, "all three kinds of wave come up: \(seen)")
            XCTAssertGreaterThan(game.cleanWaves, 8)
        }
    }

    func testSameSeedPlaysTheSame() {
        var a = LaserLimboGame(size: frame, seed: 11), b = LaserLimboGame(size: frame, seed: 11)
        let body = person(cx: 500).pose()
        for _ in 0..<(30 * 30) { a.step(1.0 / 30, world: world(body)); b.step(1.0 / 30, world: world(body)) }
        XCTAssertEqual(a.score, b.score)
        XCTAssertEqual(a.hits, b.hits)
        XCTAssertEqual(a.beams.map(\.end), b.beams.map(\.end))
        var huge = LaserLimboGame(size: frame, seed: 11)
        huge.step(30, world: world(body))
        XCTAssertLessThanOrEqual(huge.elapsed, 0.11)
    }
}

// MARK: - Punching Bag

final class BodyGamePunchingBagTests: XCTestCase {
    private func hung(_ seed: UInt64 = 1) -> PunchingBagGame {
        var game = PunchingBagGame(size: frame, seed: seed)
        game.hang(at: 900, centerY: 330, width: 150)
        return game
    }

    func testASwingThroughTheBagHitsItAndKnocksItAway() {
        var fromLeft = hung()
        let c = fromLeft.bagCenter
        fromLeft.step(1.0 / 30, world: world(nil, motion: [CGRect(x: c.x - 120, y: c.y - 120, width: 120, height: 240)]))
        XCTAssertEqual(fromLeft.hits, 1)
        XCTAssertGreaterThan(fromLeft.spin, 0, "hit from the left, it swings right")
        XCTAssertGreaterThanOrEqual(fromLeft.score, 5)

        var fromRight = hung()
        fromRight.step(1.0 / 30, world: world(nil, motion: [CGRect(x: c.x, y: c.y - 120, width: 120, height: 240)]))
        XCTAssertEqual(fromRight.hits, 1)
        XCTAssertLessThan(fromRight.spin, 0, "hit from the right, it swings left")
        for _ in 0..<15 { fromRight.step(1.0 / 30, world: world()) }
        XCTAssertLessThan(fromRight.angle, 0, "and really goes")
    }

    func testStandingStillBesideItIsNotAHit() {
        var game = hung()
        let c = game.bagCenter
        let arm = [CGRect(x: c.x - 200, y: c.y - 60, width: 140, height: 120)]
        for _ in 0..<(30 * 5) { game.step(1.0 / 30, world: world(arm, motion: [])) }
        XCTAssertEqual(game.hits, 0)
        XCTAssertEqual(game.score, 0)
    }

    func testOneSwingIsOneHitAndHarderSwingsScoreMore() {
        var game = hung()
        let c = game.bagCenter
        let swing = [CGRect(x: c.x - 200, y: c.y - 200, width: 400, height: 400)]
        for _ in 0..<6 { game.step(1.0 / 30, world: world(nil, motion: swing)) }
        XCTAssertEqual(game.hits, 1, "a swing that lasts a few frames counts once")
        let big = game.score

        var light = hung()
        light.step(1.0 / 30, world: world(nil, motion: [CGRect(x: c.x - 80, y: c.y - 80, width: 40, height: 160)]))
        XCTAssertEqual(light.hits, 1)
        XCTAssertGreaterThan(big, light.score, "a swing through all of the bag beats a glancing one")
        XCTAssertGreaterThan(game.lastStrength, light.lastStrength)
    }

    func testQuickHitsBuildACombo() {
        var game = hung()
        let everywhere = [CGRect(origin: .zero, size: frame)]
        for i in 0..<(30 * 6) { game.step(1.0 / 30, world: world(nil, motion: i % 12 == 0 ? everywhere : [])) }
        XCTAssertGreaterThanOrEqual(game.hits, 12)
        XCTAssertGreaterThanOrEqual(game.multiplier, 3)
        var slow = hung()
        for i in 0..<(30 * 12) { slow.step(1.0 / 30, world: world(nil, motion: i % 60 == 0 ? everywhere : [])) }
        XCTAssertEqual(slow.multiplier, 1, "hits too far apart never build one")
    }

    func testTheRoundEndsAndTheBagStaysBesideThePlayer() {
        var game = PunchingBagGame(size: frame, seed: 2)
        let player = person(cx: 400, u: 160)
        var steps = 0
        while !game.isOver, steps < 30 * 60 { game.step(1.0 / 30, world: world(player.pose(), motion: [])); steps += 1 }
        XCTAssertEqual(Double(steps) / 30, PunchingBagGame.roundSeconds, accuracy: 0.2)
        XCTAssertGreaterThan(game.anchorX, player.right, "with too little room on the left, it hangs on the right")
        XCTAssertLessThan(game.anchorX, frame.width - game.bagWidth / 2, "and stays in the picture")
        XCTAssertGreaterThan(game.bagCenter.y, player.shoulderY - 0.2 * player.headWidth, "at about shoulder height or above")

        var right = PunchingBagGame(size: frame, seed: 3)
        let crowded = person(cx: 1000, u: 160)
        for _ in 0..<(30 * 8) { right.step(1.0 / 30, world: world(crowded.pose(), motion: [])) }
        XCTAssertLessThan(right.anchorX, crowded.left, "someone on the right gets the bag on their left")

        var middle = PunchingBagGame(size: frame, seed: 4)
        let centred = person(cx: 640, u: 160)
        for _ in 0..<(30 * 8) { middle.step(1.0 / 30, world: world(centred.pose(), motion: [])) }
        XCTAssertLessThan(middle.anchorX, centred.left, "someone in the middle gets it on the left, clear of the summary at the top right")
        XCTAssertGreaterThan(middle.anchorX - middle.bagWidth / 2, 180, "and clear of the score at the top left")
    }

    func testSameSeedPlaysTheSameAndNothingBreaks() {
        var a = hung(4), b = hung(4)
        let swing = [CGRect(x: 700, y: 150, width: 300, height: 300)]
        for i in 0..<300 {
            let m = i % 9 == 0 ? swing : []
            a.step(1.0 / 30, world: world(nil, motion: m))
            b.step(1.0 / 30, world: world(nil, motion: m))
        }
        XCTAssertEqual(a.score, b.score)
        XCTAssertEqual(a.angle, b.angle)
        var odd = hung(5)
        odd.step(50, world: world(nil, motion: swing))
        for _ in 0..<30 { odd.step(1.0 / 30, world: GameWorld(size: frame, matte: nil, motion: nil, face: nil)) }
        XCTAssertTrue(odd.angle.isFinite)
        XCTAssertLessThanOrEqual(abs(odd.angle), 1.0)
    }
}

// MARK: - Goalkeeper

final class BodyGameGoalkeeperTests: XCTestCase {
    private func play(_ game: inout GoalkeeperGame, seconds: Double, body: [CGRect]?) {
        for _ in 0..<Int(seconds * 30) { game.step(1.0 / 30, world: world(body)) }
    }

    func testBeingOnTheRingWhenTheBallArrivesSavesIt() {
        var game = GoalkeeperGame(size: frame, seed: 1)
        game.holdShots()
        game.shoot(at: SIMD2(900, 350), flight: 1.0)
        play(&game, seconds: 1.2, body: [CGRect(x: 820, y: 250, width: 200, height: 220)])
        XCTAssertEqual(game.saves, 1)
        XCTAssertEqual(game.score, 1)
        XCTAssertEqual(game.lives, 3)
        XCTAssertNil(game.shot)
    }

    func testMissingItIsAGoalAndThreeGoalsEndIt() {
        var game = GoalkeeperGame(size: frame, seed: 2)
        game.holdShots()
        game.shoot(at: SIMD2(1000, 350), flight: 1.0)
        play(&game, seconds: 1.2, body: [CGRect(x: 300, y: 0, width: 300, height: 500)])
        XCTAssertEqual(game.goals, 1)
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(game.score, 0)
        for _ in 0..<2 {
            game.shoot(at: SIMD2(1000, 350), flight: 0.5)
            play(&game, seconds: 0.7, body: [])
        }
        XCTAssertTrue(game.isOver)
    }

    func testOnlyWhereYouAreWhenItArrivesCounts() {
        var game = GoalkeeperGame(size: frame, seed: 3)
        game.holdShots()
        game.shoot(at: SIMD2(900, 350), flight: 1.0)
        play(&game, seconds: 0.85, body: [CGRect(x: 300, y: 0, width: 300, height: 500)])
        XCTAssertEqual(game.saves + game.goals, 0, "nothing is decided before the ball gets there")
        play(&game, seconds: 0.3, body: [CGRect(x: 820, y: 250, width: 200, height: 220)])
        XCTAssertEqual(game.saves, 1, "diving across at the last moment still saves it")
    }

    func testGoldBallsAreWorthThree() {
        var game = GoalkeeperGame(size: frame, seed: 4)
        game.holdShots()
        game.shoot(at: SIMD2(640, 300), flight: 0.6, golden: true)
        play(&game, seconds: 0.8, body: [CGRect(x: 540, y: 200, width: 200, height: 200)])
        XCTAssertEqual(game.score, GoalkeeperGame.goldValue)
    }

    func testShotsAreAlwaysWithinReach() {
        for (seed, x) in [(5, 640.0), (6, 260.0), (7, 1020.0)] {
            var game = GoalkeeperGame(size: frame, seed: UInt64(seed))
            let ref = person(cx: x, u: 160)
            var targets: [SIMD2<Double>] = []
            var counted = 0
            for _ in 0..<(30 * 90) where !game.isOver {
                // A keeper who always gets there: so the match runs long and every kind of shot comes up.
                var body = ref.pose()
                if let shot = game.shot, shot.progress > 0.5 { body.append(CGRect(x: shot.target.x - 60, y: shot.target.y - 60, width: 120, height: 120)) }
                game.step(1.0 / 30, world: world(body))
                if game.shotsTaken > counted, let shot = game.shot, let seen = game.reference {
                    counted = game.shotsTaken
                    targets.append(shot.target)
                    // Within a stretch of the player as the game saw them when it kicked.
                    let reach = CGRect(x: seen.left - 1.75 * seen.headWidth, y: 90, width: seen.width + 3.5 * seen.headWidth, height: frame.height - 270)
                    XCTAssertTrue(reach.contains(CGPoint(x: shot.target.x, y: shot.target.y)), "at \(x): \(shot.target) is out of reach of \(seen)")
                }
            }
            XCTAssertGreaterThan(targets.count, 20, "standing at \(x)")
            XCTAssertEqual(game.goals, 0)
            for t in targets {
                XCTAssertTrue(t.x >= 90 && t.x <= frame.width - 90 && t.y <= frame.height - 190, "and on the picture, clear of the HUD")
            }
            let beside = targets.filter { $0.x < ref.left - 0.3 * ref.headWidth || $0.x > ref.right + 0.3 * ref.headWidth }
            XCTAssertGreaterThan(beside.count, 3, "some shots make you reach")
        }
    }

    func testNobodyAndSameSeed() {
        var a = GoalkeeperGame(size: frame, seed: 8), b = GoalkeeperGame(size: frame, seed: 8)
        let body = person(cx: 600).pose()
        for _ in 0..<(30 * 20) { a.step(1.0 / 30, world: world(body)); b.step(1.0 / 30, world: world(body)) }
        XCTAssertEqual(a.saves, b.saves)
        XCTAssertEqual(a.goals, b.goals)
        XCTAssertEqual(a.shot?.target, b.shot?.target)
        var blind = GoalkeeperGame(size: frame, seed: 9)
        for _ in 0..<(30 * 10) { blind.step(1.0 / 30, world: GameWorld(size: frame, matte: nil, motion: nil, face: nil)) }
        XCTAssertGreaterThan(blind.goals, 0, "with no one in goal the shots go in, and nothing breaks")
        blind.step(60, world: world())
    }
}

// MARK: - Ninja Stars

final class BodyGameNinjaTests: XCTestCase {
    private let middle = [CGRect(x: 540, y: 0, width: 200, height: 520)]

    private func play(_ game: inout NinjaStarsGame, seconds: Double, body: [CGRect]?, motion: [CGRect]? = nil) {
        for _ in 0..<Int(seconds * 30) { game.step(1.0 / 30, world: world(body, motion: motion)) }
    }

    func testAStarReachingAStillBodyHits() {
        var game = NinjaStarsGame(size: frame, seed: 1)
        game.holdThrows()
        game.throwStar(from: SIMD2(-40, 300), through: SIMD2(640, 300), telegraph: 0.3, speed: 900)
        play(&game, seconds: 1.5, body: middle, motion: [])
        XCTAssertEqual(game.hits, 1)
        XCTAssertEqual(game.lives, 2)
        XCTAssertTrue(game.stars.isEmpty)
    }

    func testSwattingItAsItArrivesBlocksIt() {
        var game = NinjaStarsGame(size: frame, seed: 2)
        game.holdThrows()
        game.throwStar(from: SIMD2(-40, 300), through: SIMD2(640, 300), telegraph: 0.3, speed: 900)
        play(&game, seconds: 1.5, body: middle, motion: [CGRect(x: 500, y: 220, width: 120, height: 160)])
        XCTAssertEqual(game.blocks, 1)
        XCTAssertEqual(game.hits, 0)
        XCTAssertEqual(game.score, NinjaStarsGame.blockPoints)
    }

    func testOutOfItsPathItFliesByAndThatScoresToo() {
        var game = NinjaStarsGame(size: frame, seed: 3)
        game.holdThrows()
        game.throwStar(from: SIMD2(-40, 300), through: SIMD2(640, 300), telegraph: 0.3, speed: 900)
        play(&game, seconds: 2.5, body: [CGRect(x: 900, y: 0, width: 200, height: 200)])
        XCTAssertEqual(game.dodges, 1)
        XCTAssertEqual(game.score, NinjaStarsGame.dodgePoints)
        XCTAssertEqual(game.lives, 3)
    }

    func testTheWarningComesFirstAndAHitGivesAGracePeriod() {
        var game = NinjaStarsGame(size: frame, seed: 4)
        game.holdThrows()
        game.throwStar(from: SIMD2(-40, 300), through: SIMD2(640, 300), telegraph: 0.6, speed: 900)
        play(&game, seconds: 0.5, body: middle)
        XCTAssertEqual(game.stars.first?.position, SIMD2(-40, 300), "it waits at the edge while the glint shows")
        play(&game, seconds: 1.0, body: middle)
        XCTAssertEqual(game.lives, 2)
        game.throwStar(from: SIMD2(1320, 300), through: SIMD2(640, 300), telegraph: 0.1, speed: 1200)
        play(&game, seconds: 0.6, body: middle)
        XCTAssertEqual(game.lives, 2, "a second star just after a hit glances off")
    }

    func testStarsAreAimedAtYouAndThreeHitsEndIt() {
        var game = NinjaStarsGame(size: frame, seed: 5)
        var steps = 0
        while !game.isOver, steps < 30 * 90 { game.step(1.0 / 30, world: world(middle, motion: [])); steps += 1 }
        XCTAssertTrue(game.isOver, "standing still, the stars find you")
        XCTAssertEqual(game.hits, 3)
        XCTAssertLessThan(game.dodges, game.thrown, "most of them were coming at you")

        var nobody = NinjaStarsGame(size: frame, seed: 5)
        play(&nobody, seconds: 30, body: [])
        XCTAssertEqual(nobody.lives, 3)
        XCTAssertGreaterThan(nobody.thrown, 12)
    }

    func testSameSeedPlaysTheSame() {
        var a = NinjaStarsGame(size: frame, seed: 6), b = NinjaStarsGame(size: frame, seed: 6)
        for i in 0..<(30 * 30) {
            let m = i % 10 < 4 ? middle : []
            a.step(1.0 / 30, world: world(middle, motion: m))
            b.step(1.0 / 30, world: world(middle, motion: m))
        }
        XCTAssertEqual(a.score, b.score)
        XCTAssertEqual(a.stars.map(\.to), b.stars.map(\.to))
        var huge = NinjaStarsGame(size: frame, seed: 7)
        huge.step(100, world: world(middle))
        XCTAssertLessThanOrEqual(huge.elapsed, 0.11)
    }
}

// MARK: - Through the lens

final class BodyGameNewLensTests: XCTestCase {
    private let h = LensHarness()

    /// A body game's lens with a best-score store that forgets, so tests leave nothing behind.
    static func lens(_ id: String) -> Lens {
        let store = MemoryScoreStore()
        switch id {
        case "keepy-uppy": return GameLens<KeepyUppyGame>(id: id, needs: [.matte], store: store)
        case "laser-limbo": return GameLens<LaserLimboGame>(id: id, needs: [.matte], store: store)
        case "punching-bag": return GameLens<PunchingBagGame>(id: id, needs: [.matte], store: store)
        case "goalkeeper": return GameLens<GoalkeeperGame>(id: id, needs: [.matte], store: store)
        case "ninja-stars": return GameLens<NinjaStarsGame>(id: id, needs: [.matte], store: store)
        case "balloon-pop": return GameLens<BalloonGame>(id: id, needs: [.matte], store: store)
        case "breakout": return GameLens<BreakoutGame>(id: id, needs: [.matte], store: store)
        case "meteor-dodge": return GameLens<MeteorDodgeGame>(id: id, needs: [.matte], store: store)
        case "hole-in-the-wall": return GameLens<HoleInTheWallGame>(id: id, needs: [.matte], store: store)
        case "bubble-wrap": return GameLens<BubbleWrapGame>(id: id, needs: [.matte], store: store)
        default: return BallPitLens()
        }
    }

    /// Every new game runs through its catalog lens over the synthetic person, and with nobody and no silhouette at all.
    func testEachNewGameRendersWithAndWithoutAPerson() throws {
        let base = h.input()
        for id in ["keepy-uppy", "laser-limbo", "punching-bag", "goalkeeper", "ninja-stars"] {
            let lens = Self.lens(id)
            lens.restart()
            var out = base.composed
            for i in 0..<(30 * 6) { out = lens.render(h.at(base, time: Double(i) / 30)) }
            XCTAssertEqual(out.extent.size, frame, id)
            XCTAssertTrue(lens.status?.title.hasPrefix("Score") ?? false, "\(id) is playing: \(String(describing: lens.status))")
            Output.save(out, as: "bodygame-lens-\(id).png")

            let empty = LensInput(time: 30, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: base.background,
                                  composed: base.background ?? base.camera, matteGrid: MatteGrid(outputSize: base.rect.size), face: nil, services: base.services)
            var lonely = empty.composed
            for i in 0..<60 { lonely = lens.render(h.at(empty, time: 30 + Double(i) / 30)) }
            XCTAssertEqual(lonely.extent.size, frame, "\(id) with nobody there")
            Output.save(lonely, as: "bodygame-lens-\(id)-empty.png")

            let gridless = LensInput(time: 40, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: nil,
                                     composed: base.camera, matteGrid: nil, face: nil, services: base.services)
            for _ in 0..<5 { XCTAssertEqual(lens.render(gridless).extent.size, frame, "\(id) with no grid") }

            let fresh = Self.lens(id)
            var waiting = base.composed
            let none = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: base.background,
                                 composed: base.background ?? base.camera, matteGrid: MatteGrid(outputSize: base.rect.size), face: nil, services: base.services)
            for i in 0..<10 { waiting = fresh.render(h.at(none, time: Double(i) / 30)) }
            XCTAssertEqual(fresh.status?.title, "Step into the frame to play", id)
            Output.save(waiting, as: "bodygame-lens-\(id)-waiting.png")
        }
    }

    /// The first frame of a new game must not stall the video: the art is drawn lazily and kept, and a first frame stays quick.
    func testTheFirstFramesAreQuick() throws {
        let base = h.input()
        for id in ["keepy-uppy", "laser-limbo", "punching-bag", "goalkeeper", "ninja-stars", "balloon-pop", "breakout", "meteor-dodge",
                   "hole-in-the-wall", "bubble-wrap"] {
            let lens = Self.lens(id)
            lens.restart()
            var worst = 0.0
            for i in 0..<(30 * 4) {
                let started = CFAbsoluteTimeGetCurrent()
                _ = lens.render(h.at(base, time: Double(i) / 30))
                worst = max(worst, (CFAbsoluteTimeGetCurrent() - started) * 1000)
            }
            print(String(format: "FIRSTFRAMES %-18@ worst %.1f ms", id as NSString, worst))
            XCTAssertLessThan(worst, 120, "\(id): no frame of the first four seconds may stall (worst \(worst) ms)")
        }
    }

    /// What each body game costs the CPU a frame, its rules and its drawing, without the GPU work every lens shares. Opt-in.
    func testRulesAndDrawingCostLittle() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let canvas = try XCTUnwrap(OverlayCanvas(size: frame, slots: 3))
        let body = h.grid
        let swing = BodyRectsMatte(rects: [CGRect(x: 300, y: 150, width: 680, height: 300)])
        func measure<G: Game>(_ name: String, _ make: () -> G) {
            var game = make()
            var times: [Double] = []
            for i in 0..<240 {
                let world = GameWorld(size: frame, matte: body, motion: i % 4 == 0 ? swing : nil, face: nil)
                let started = CFAbsoluteTimeGetCurrent()
                game.step(1.0 / 30, world: world)
                game.draw(in: canvas.begin(), time: Double(i) / 30)
                _ = canvas.image()
                if i >= 60 { times.append((CFAbsoluteTimeGetCurrent() - started) * 1000) }
            }
            let sorted = times.sorted()
            print(String(format: "CPU %-18@ median %.2f ms  p90 %.2f ms  worst %.2f ms", name as NSString, sorted[sorted.count / 2],
                         sorted[sorted.count * 9 / 10], sorted.last ?? 0))
            XCTAssertLessThan(sorted[sorted.count / 2], 6, "\(name) should draw in a few milliseconds")
        }
        measure("meteor-dodge") { MeteorDodgeGame(size: frame, seed: 1) }
        measure("hole-in-the-wall") { HoleInTheWallGame(size: frame, seed: 1) }
        measure("bubble-wrap") { BubbleWrapGame(size: frame, seed: 1) }
        measure("balloon-pop") { BalloonGame(size: frame, seed: 1) }
        measure("breakout") { BreakoutGame(size: frame, seed: 1) }
        measure("keepy-uppy") { KeepyUppyGame(size: frame, seed: 1) }
        measure("laser-limbo") { LaserLimboGame(size: frame, seed: 1) }
        measure("punching-bag") { PunchingBagGame(size: frame, seed: 1) }
        measure("goalkeeper") { GoalkeeperGame(size: frame, seed: 1) }
        measure("ninja-stars") { NinjaStarsGame(size: frame, seed: 1) }
        var physics = BallPit(size: frame)
        var stepping: [Double] = []
        for i in 0..<240 {
            let started = CFAbsoluteTimeGetCurrent()
            physics.step(1.0 / 30, matte: body)
            if i >= 120 { stepping.append((CFAbsoluteTimeGetCurrent() - started) * 1000) }
        }
        print(String(format: "CPU %-18@ median %.2f ms", "ball-pit physics" as NSString, stepping.sorted()[stepping.count / 2]))
        let pit = BallPitLens()
        let base = h.input()
        var times: [Double] = []
        for i in 0..<240 {
            let started = CFAbsoluteTimeGetCurrent()
            _ = pit.render(h.at(base, time: Double(i) / 30))
            if i >= 120 { times.append((CFAbsoluteTimeGetCurrent() - started) * 1000) }
        }
        let sorted = times.sorted()
        print(String(format: "CPU %-18@ median %.2f ms  p90 %.2f ms  worst %.2f ms", "ball-pit" as NSString, sorted[sorted.count / 2],
                     sorted[sorted.count * 9 / 10], sorted.last ?? 0))
    }
}
