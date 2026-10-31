import CoreImage
import simd
import XCTest

private let frame = CGSize(width: 1280, height: 720)

/// A world with a person made of rectangles in it.
private func world(_ body: [CGRect] = [], motion: [CGRect]? = nil) -> GameWorld {
    GameWorld(size: frame, matte: BodyRectsMatte(rects: body), motion: motion.map { BodyRectsMatte(rects: $0) }, face: nil)
}

private let everywhere = [CGRect(origin: .zero, size: frame)]

/// A person standing normally, `u` pixels of head across, `cx` pixels from the left, as the game measures one.
private func person(cx: Double = 640, u: Double = 200, top: Double = 560) -> BodyFrame {
    let rects = BodyFrame(left: cx - 1.35 * u, right: cx + 1.35 * u, top: top, bottom: 0, headWidth: u, shoulderY: top - 1.5 * u).neutralRects
    return BodyFrame(scan: BodyScan(matte: BodyRectsMatte(rects: rects), size: frame)) ?? BodyFrame(left: cx - 1.35 * u, right: cx + 1.35 * u, top: top, bottom: 0, headWidth: u, shoulderY: top - 1.5 * u)
}

// MARK: - Meteor Dodge

final class BodyGameMeteorTests: XCTestCase {
    private func still(_ game: inout MeteorDodgeGame, seconds: Double, body: [CGRect]) {
        for _ in 0..<Int(seconds * 30) { game.step(1.0 / 30, world: world(body)) }
    }

    func testAMeteorCannotHurtYouWhileItIsOnlyAShadow() {
        var game = MeteorDodgeGame(size: frame, seed: 1)
        game.holdSpawning()
        game.launch(at: SIMD2(640, 360), telegraph: 1.0, flight: 0.7)
        for _ in 0..<27 {                         // 0.9 s: still in the warning
            game.step(1.0 / 30, world: world(everywhere))
            let m = game.meteors[0]
            XCTAssertFalse(m.isLethal)
            XCTAssertGreaterThan(m.position.y, frame.height, "during the warning the rock is still off the top of the picture")
        }
        XCTAssertEqual(game.lives, 3, "standing in the shadow is safe until the rock arrives")
        still(&game, seconds: 0.5, body: everywhere)
        XCTAssertEqual(game.lives, 2, "once it is falling, it hurts")
        XCTAssertTrue(game.meteors.isEmpty)
    }

    func testEveryMeteorGivesAFairWarningAndRoomToLeave() {
        for seed in 1...4 {
            for startAt in [0.0, 100.0] {                       // the gentle start and the hardest rain
                var game = MeteorDodgeGame(size: frame, seed: UInt64(seed))
                game.fastForward(to: startAt)
                let body = [CGRect(x: 300, y: 0, width: 500, height: 450)]
                var launched = 0
                for _ in 0..<(30 * 60) where !game.isOver {
                    game.step(1.0 / 30, world: world(body))
                    if game.meteorsLaunched > launched {
                        launched = game.meteorsLaunched
                        guard let newest = game.meteors.last else { return XCTFail("a new meteor should be on the field") }
                        XCTAssertLessThanOrEqual(newest.age, 0.04, "it starts at the beginning of its warning")
                        XCTAssertGreaterThanOrEqual(newest.telegraph, 0.78)
                        XCTAssertGreaterThanOrEqual(newest.telegraph + newest.flight, 1.3, "at least 1.3 s from first shadow to landing, even at the hardest")
                        for other in game.meteors.dropLast() {
                            XCTAssertGreaterThan(simd_distance(other.target, newest.target), newest.radius + other.radius + 40,
                                                 "landing spots stay apart so there is somewhere to stand")
                        }
                    }
                    for m in game.meteors where m.age < m.telegraph { XCTAssertGreaterThan(m.position.y, frame.height) }
                }
                XCTAssertGreaterThan(launched, 3, "seed \(seed) from \(startAt)")
            }
        }
    }

    func testTheFirstHitCanNotComeBeforeTheFirstWarningIsOver() throws {
        // The whole picture is "you": the first rock to start falling hits at once, so when that happens is the earliest a hit can be.
        for seed in 1...6 {
            var game = MeteorDodgeGame(size: frame, seed: UInt64(seed))
            var firstSpawn: Double?
            var warning = 0.0
            for _ in 0..<(30 * 20) where game.hits == 0 {
                game.step(1.0 / 30, world: world(everywhere))
                if firstSpawn == nil, let m = game.meteors.first { firstSpawn = game.elapsed; warning = m.telegraph }
            }
            let spawned = try XCTUnwrap(firstSpawn)
            XCTAssertEqual(game.hits, 1)
            XCTAssertGreaterThanOrEqual(game.hitTimes[0], spawned + warning - 0.001, "seed \(seed)")
        }
    }

    func testLeavingTheShadowInTimeMeansNoHit() {
        var game = MeteorDodgeGame(size: frame, seed: 2)
        game.holdSpawning()
        game.launch(at: SIMD2(640, 300), telegraph: 1.0, flight: 0.7)
        still(&game, seconds: 0.7, body: [CGRect(x: 560, y: 200, width: 160, height: 200)])      // standing right where it will land
        still(&game, seconds: 2, body: [CGRect(x: 1000, y: 0, width: 200, height: 400)])          // then you step away
        XCTAssertEqual(game.lives, 3)
        XCTAssertEqual(game.hits, 0)
        XCTAssertTrue(game.meteors.isEmpty, "it landed and is gone")
    }

    func testStayingPutIsAHitWithAGracePeriodAfter() {
        var game = MeteorDodgeGame(size: frame, seed: 3)
        game.holdSpawning()
        let body = [CGRect(x: 500, y: 100, width: 300, height: 400)]
        game.launch(at: SIMD2(640, 300), telegraph: 0.5, flight: 0.5)
        game.launch(at: SIMD2(660, 320), telegraph: 0.9, flight: 0.5)           // arrives during the grace period
        still(&game, seconds: 1.05, body: body)
        XCTAssertEqual(game.lives, 2)
        XCTAssertGreaterThan(game.graceLeft, 0)
        XCTAssertTrue(game.invulnerable)
        still(&game, seconds: 0.6, body: body)
        XCTAssertEqual(game.lives, 2, "the second rock goes through you harmlessly while you are in the grace period")
        still(&game, seconds: 1.6, body: body)
        XCTAssertFalse(game.invulnerable)
        game.launch(at: SIMD2(640, 300), telegraph: 0.2, flight: 0.3)
        still(&game, seconds: 0.7, body: body)
        XCTAssertEqual(game.lives, 1, "after the grace period you can be hit again")
    }

    func testThreeHitsEndTheGame() {
        var game = MeteorDodgeGame(size: frame, seed: 4)
        game.holdSpawning()
        for _ in 0..<3 {
            game.launch(at: SIMD2(640, 300), telegraph: 0.2, flight: 0.3)
            still(&game, seconds: 0.7, body: everywhere)
            still(&game, seconds: MeteorDodgeGame.graceSeconds, body: [])
        }
        XCTAssertEqual(game.lives, 0)
        XCTAssertTrue(game.isOver)
        XCTAssertTrue(game.summary.contains("0"))
    }

    func testCloseCallsPayABonus() {
        var game = MeteorDodgeGame(size: frame, seed: 5)
        game.holdSpawning()
        let beside = [CGRect(x: 720, y: 0, width: 300, height: 720)]            // 30 px from the rock's edge
        game.launch(at: SIMD2(640, 300), radius: 44, telegraph: 0.3, flight: 0.6)
        still(&game, seconds: 1.2, body: beside)
        XCTAssertEqual(game.hits, 0)
        XCTAssertEqual(game.nearMisses, 1)
        XCTAssertEqual(game.bonus, 3)

        var far = MeteorDodgeGame(size: frame, seed: 5)
        far.holdSpawning()
        far.launch(at: SIMD2(640, 300), radius: 44, telegraph: 0.3, flight: 0.6)
        still(&far, seconds: 1.2, body: [CGRect(x: 1100, y: 0, width: 100, height: 200)])
        XCTAssertEqual(far.nearMisses, 0, "nowhere near you is not a near miss")
    }

    func testShieldsProtectAndStarsScore() {
        var game = MeteorDodgeGame(size: frame, seed: 6)
        game.holdSpawning()
        let body = [CGRect(x: 500, y: 100, width: 300, height: 500)]
        game.drop(.shield, at: SIMD2(650, 300))
        still(&game, seconds: 0.1, body: body)
        XCTAssertGreaterThan(game.shieldLeft, 4.5)
        XCTAssertEqual(game.pickupsTaken, 1)
        let bonusAfterShield = game.bonus
        game.launch(at: SIMD2(640, 300), telegraph: 0.2, flight: 0.3)
        still(&game, seconds: 0.7, body: body)
        XCTAssertEqual(game.lives, 3, "the shield stops the rock")
        XCTAssertGreaterThan(game.bonus, bonusAfterShield, "and breaking one scores")
        still(&game, seconds: 5, body: body)
        XCTAssertEqual(game.shieldLeft, 0)
        game.launch(at: SIMD2(640, 300), telegraph: 0.2, flight: 0.3)
        still(&game, seconds: 0.7, body: body)
        XCTAssertEqual(game.lives, 2, "and then it wears off")

        var star = MeteorDodgeGame(size: frame, seed: 6)
        star.holdSpawning()
        let before = star.score
        star.drop(.star, at: SIMD2(650, 300))
        still(&star, seconds: 0.1, body: body)
        XCTAssertEqual(star.score - before, 10)
        star.drop(.star, at: SIMD2(100, 600))
        still(&star, seconds: 0.1, body: body)
        XCTAssertEqual(star.pickupsTaken, 1, "a star out of reach is not collected")
    }

    func testScoreIsSecondsSurvivedPlusBonuses() {
        var game = MeteorDodgeGame(size: frame, seed: 7)
        game.holdSpawning()
        still(&game, seconds: 12.1, body: [])
        XCTAssertEqual(game.score, 12)
        game.drop(.star, at: SIMD2(650, 300))
        still(&game, seconds: 1, body: [CGRect(x: 500, y: 100, width: 300, height: 500)])
        XCTAssertEqual(game.score, 13 + 10, "a second more and a star")
    }

    func testNobodyInViewNothingHurtsAndTheRainStillFalls() {
        var game = MeteorDodgeGame(size: frame, seed: 8)
        still(&game, seconds: 40, body: [])
        XCTAssertEqual(game.lives, 3)
        XCTAssertEqual(game.hits, 0)
        XCTAssertGreaterThan(game.meteorsLaunched, 8)
        XCTAssertGreaterThanOrEqual(game.score, 39)

        var blind = MeteorDodgeGame(size: frame, seed: 8)
        for _ in 0..<(30 * 20) { blind.step(1.0 / 30, world: GameWorld(size: frame, matte: nil, motion: nil, face: nil)) }
        XCTAssertEqual(blind.lives, 3, "no matte at all is the same as nobody there")
    }

    func testTheRainGetsHeavier() {
        let early = MeteorDodgeGame(size: frame, seed: 9)
        var late = MeteorDodgeGame(size: frame, seed: 9)
        late.fastForward(to: 200)
        XCTAssertLessThan(late.currentTelegraph, early.currentTelegraph)
        XCTAssertLessThan(late.currentFlight, early.currentFlight)
        XCTAssertGreaterThan(late.maxActive, early.maxActive)
        XCTAssertGreaterThanOrEqual(late.currentTelegraph, 0.78)
        var a = MeteorDodgeGame(size: frame, seed: 10), b = MeteorDodgeGame(size: frame, seed: 10)
        b.fastForward(to: 90)
        for _ in 0..<(30 * 20) { a.step(1.0 / 30, world: world()); b.step(1.0 / 30, world: world()) }
        XCTAssertGreaterThan(b.meteorsLaunched, a.meteorsLaunched, "more rocks in the same time later on")
    }

    func testAHugeStepDoesNotSkipTheWarning() {
        var game = MeteorDodgeGame(size: frame, seed: 11)
        game.holdSpawning()
        game.launch(at: SIMD2(640, 300), telegraph: 1.0, flight: 0.7)
        game.step(30, world: world(everywhere))
        XCTAssertEqual(game.lives, 3, "a stalled frame can't make a meteor land on you without being seen")
        XCTAssertLessThanOrEqual(game.elapsed, 0.11)
    }

    func testSameSeedPlaysTheSame() {
        var a = MeteorDodgeGame(size: frame, seed: 12), b = MeteorDodgeGame(size: frame, seed: 12)
        let body = [CGRect(x: 400, y: 0, width: 400, height: 500)]
        for _ in 0..<(30 * 30) { a.step(1.0 / 30, world: world(body)); b.step(1.0 / 30, world: world(body)) }
        XCTAssertEqual(a.meteors.map(\.target), b.meteors.map(\.target))
        XCTAssertEqual(a.score, b.score)
        XCTAssertEqual(a.hitTimes, b.hitTimes)
        var c = MeteorDodgeGame(size: frame, seed: 13)
        for _ in 0..<(30 * 30) { c.step(1.0 / 30, world: world(body)) }
        XCTAssertNotEqual(a.hitTimes + [Double(a.meteorsLaunched)], c.hitTimes + [Double(c.meteorsLaunched)], "another seed plays another game")
    }

    func testRainIsAimedAtYouSoThereIsSomethingToDodge() {
        var game = MeteorDodgeGame(size: frame, seed: 14)
        let body = CGRect(x: 520, y: 100, width: 240, height: 360)
        var aimed = 0, total = 0
        for _ in 0..<(30 * 60) {
            let before = game.meteorsLaunched
            game.step(1.0 / 30, world: world([body]))
            if game.meteorsLaunched > before, let m = game.meteors.last {
                total += 1
                if body.insetBy(dx: -90, dy: -90).contains(CGPoint(x: m.target.x, y: m.target.y)) { aimed += 1 }
            }
            if game.isOver { break }
        }
        XCTAssertGreaterThan(total, 5)
        XCTAssertGreaterThan(Double(aimed) / Double(total), 0.35)
    }
}

// MARK: - Hole in the Wall

final class BodyGameHoleTests: XCTestCase {
    /// A spread of people: near, far, left, right, small.
    private var people: [BodyFrame] {
        [person(cx: 640, u: 200), person(cx: 640, u: 150), person(cx: 330, u: 160), person(cx: 960, u: 170),
         person(cx: 640, u: 110, top: 520), person(cx: 560, u: 130, top: 600)]
    }

    func testTheFrameOfAPersonIsMeasuredFromTheirSilhouette() throws {
        let head = CGRect(x: 540, y: 300, width: 200, height: 260)
        let shoulders = CGRect(x: 370, y: 0, width: 540, height: 270)
        let neck = CGRect(x: 600, y: 270, width: 80, height: 40)
        let measured = try XCTUnwrap(BodyFrame(scan: BodyScan(matte: BodyRectsMatte(rects: [head, shoulders, neck]), size: frame)))
        XCTAssertEqual(measured.headWidth, 200, accuracy: 24)
        XCTAssertEqual(measured.centerX, 640, accuracy: 24)
        XCTAssertEqual(measured.top, 560, accuracy: 20)
        XCTAssertEqual(measured.width, 540, accuracy: 32)
        XCTAssertEqual(measured.shoulderY, 270, accuracy: 50)
        XCTAssertNil(BodyFrame(scan: BodyScan(matte: BodyRectsMatte(), size: frame)), "nobody, no frame")
    }

    func testEveryHoleFitsThePersonItWasMadeFor() throws {
        for (index, ref) in people.enumerated() {
            var made = 0
            for template in BodyHole.Template.allCases {
                for tight in [0.0, 0.5, 1.0] {
                    guard let hole = BodyHole.make(template, around: ref, size: frame, tight: tight) else { continue }
                    made += 1
                    let pose = BodyScan(matte: BodyRectsMatte(rects: hole.idealPose(for: ref, size: frame)), size: frame)
                    let posed = hole.judge(pose)
                    XCTAssertTrue(posed.passed, "person \(index), \(template), tight \(tight): the pose it asks for must pass, got \(posed)")
                    XCTAssertLessThanOrEqual(posed.outsideFraction, 0.04, "\(template) leaves the pose room to spare")

                    let still = hole.judge(BodyScan(matte: BodyRectsMatte(rects: ref.neutralRects), size: frame))
                    XCTAssertFalse(still.passed, "person \(index), \(template): standing still must not pass")
                }
            }
            XCTAssertGreaterThanOrEqual(made, 12, "person \(index): at least four shapes are on offer at every tightness")
        }
    }

    func testAPersonStandingInTheMiddleCanBeAskedForEveryPoseButMiddle() {
        let ref = person()
        for template in BodyHole.Template.allCases where template != .middle {
            XCTAssertNotNil(BodyHole.make(template, around: ref, size: frame, tight: 0), "\(template)")
        }
        XCTAssertNil(BodyHole.make(.middle, around: ref, size: frame, tight: 0), "already there, nothing to ask")
    }

    func testSomeonePressedAgainstTheLeftIsAskedToGoRightAndCannotBeAskedToGoLeft() {
        let ref = person(cx: 300, u: 160)
        XCTAssertNil(BodyHole.make(.left, around: ref, size: frame, tight: 0))
        XCTAssertNotNil(BodyHole.make(.right, around: ref, size: frame, tight: 0))
        XCTAssertNotNil(BodyHole.make(.middle, around: ref, size: frame, tight: 0))
    }

    func testHolesGrowWithThePersonAndStayOnTheScreen() throws {
        let near = try XCTUnwrap(BodyHole.make(.crouch, around: person(u: 200), size: frame, tight: 0))
        let far = try XCTUnwrap(BodyHole.make(.crouch, around: person(u: 120), size: frame, tight: 0))
        func width(_ hole: BodyHole) -> Double {
            guard case .rect(let r, _)? = hole.parts.first else { return 0 }
            return r.width
        }
        XCTAssertGreaterThan(width(near), width(far))
        for ref in people {
            for template in [BodyHole.Template.left, .right, .middle] {
                guard let hole = BodyHole.make(template, around: ref, size: frame, tight: 0), case .rect(let door, _)? = hole.parts.first else { continue }
                XCTAssertGreaterThanOrEqual(door.minX, -40, "a doorway may run a little off the side, never far")
                XCTAssertLessThanOrEqual(door.maxX, frame.width + 40)
            }
        }
    }

    func testTheThresholdIsForgiving() throws {
        let ref = person()
        let hole = try XCTUnwrap(BodyHole.make(.left, around: ref, size: frame, tight: 0))
        guard case .rect(let door, _)? = hole.parts.first else { return XCTFail() }
        func verdict(overhang: Double) -> BodyHole.Verdict {
            // A 400 wide block whose right edge sticks out past the door by `overhang` of its width.
            let block = CGRect(x: door.maxX + 400 * overhang - 400, y: 0, width: 400, height: 300)
            return hole.judge(BodyScan(matte: BodyRectsMatte(rects: [block]), size: frame))
        }
        XCTAssertTrue(verdict(overhang: 0).passed)
        XCTAssertTrue(verdict(overhang: 0.07).passed, "a sliver over the edge is fine")
        XCTAssertFalse(verdict(overhang: 0.3).passed, "a third of you in the wall is not")
        XCTAssertFalse(hole.judge(BodyScan(matte: BodyRectsMatte(), size: frame)).passed, "no one is not a pass")
    }

    func testArmsHaveToActuallyBeRaisedOrStretchedOut() throws {
        let ref = person()
        let up = try XCTUnwrap(BodyHole.make(.armsUp, around: ref, size: frame, tight: 0))
        let out = try XCTUnwrap(BodyHole.make(.armsOut, around: ref, size: frame, tight: 0))
        let upPose = BodyScan(matte: BodyRectsMatte(rects: up.idealPose(for: ref, size: frame)), size: frame)
        let outPose = BodyScan(matte: BodyRectsMatte(rects: out.idealPose(for: ref, size: frame)), size: frame)
        XCTAssertTrue(up.judge(upPose).passed)
        XCTAssertTrue(out.judge(outPose).passed)
        XCTAssertFalse(up.judge(outPose).passed, "arms out is not arms up")
        XCTAssertFalse(out.judge(upPose).passed, "and arms up is not arms out")
        XCTAssertFalse(up.zones.isEmpty)
    }

    func testTheMeterShowsHowCloseYouAreAndWhatIsMissing() throws {
        let ref = person()
        let standing = BodyScan(matte: BodyRectsMatte(rects: ref.neutralRects), size: frame)
        let duck = try XCTUnwrap(BodyHole.make(.crouch, around: ref, size: frame, tight: 0))
        let standingAtADuckWall = duck.judge(standing)
        XCTAssertFalse(standingAtADuckWall.passed)
        XCTAssertEqual(standingAtADuckWall.advice, "LOWER!", "most of you fits, but your head is too high")
        XCTAssertLessThan(standingAtADuckWall.match, 0.88)
        let ducked = duck.judge(BodyScan(matte: BodyRectsMatte(rects: duck.idealPose(for: ref, size: frame)), size: frame))
        XCTAssertTrue(ducked.passed)
        XCTAssertNil(ducked.advice)
        XCTAssertGreaterThanOrEqual(ducked.match, 0.95)

        let up = try XCTUnwrap(BodyHole.make(.armsUp, around: ref, size: frame, tight: 0))
        let noArms = up.judge(standing)
        XCTAssertEqual(noArms.advice, "MORE ARMS!")
        XCTAssertLessThan(noArms.match, 0.88)
        let left = try XCTUnwrap(BodyHole.make(.left, around: ref, size: frame, tight: 0))
        XCTAssertNil(left.judge(standing).advice, "a person well outside the hole is just told how much fits")
    }

    func testFittingThroughAWallScoresAndSpeedsUpTheNext() throws {
        var game = HoleInTheWallGame(size: frame, seed: 1)
        let ref = person()
        let started = game.approachSeconds
        XCTAssertTrue(game.startWall(.crouch, around: ref))
        let hole = try XCTUnwrap(game.wall?.hole)
        let ducked = BodyRectsMatte(rects: hole.idealPose(for: ref, size: frame))
        for _ in 0..<(30 * 8) where game.passedWalls == 0 { game.step(1.0 / 30, world: GameWorld(size: frame, matte: ducked, motion: nil, face: nil)) }
        XCTAssertEqual(game.passedWalls, 1)
        XCTAssertEqual(game.lives, 3)
        XCTAssertGreaterThanOrEqual(game.score, 10)
        XCTAssertLessThan(game.approachSeconds, started, "passing speeds the next wall up")
        guard case .result(let passed, _) = game.stage else { return XCTFail("expected the result, got \(game.stage)") }
        XCTAssertTrue(passed)
    }

    func testMissingCostsALifeAndSmashesTheWall() throws {
        var game = HoleInTheWallGame(size: frame, seed: 2)
        let ref = person()
        XCTAssertTrue(game.startWall(.crouch, around: ref))
        let standing = BodyRectsMatte(rects: ref.neutralRects)
        for _ in 0..<(30 * 8) where game.failedWalls == 0 { game.step(1.0 / 30, world: GameWorld(size: frame, matte: standing, motion: nil, face: nil)) }
        XCTAssertEqual(game.failedWalls, 1)
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.streak, 0)
        XCTAssertFalse(try XCTUnwrap(game.verdict).passed)
        // The result plays out, then a breather, then the next wall.
        for _ in 0..<(30 * 4) { game.step(1.0 / 30, world: GameWorld(size: frame, matte: standing, motion: nil, face: nil)) }
        XCTAssertNotNil(game.wall, "the next wall is on its way")
        XCTAssertEqual(game.wallsStarted, 2)
    }

    func testThreeMissesEndTheGame() {
        var game = HoleInTheWallGame(size: frame, seed: 3)
        let ref = person()
        let standing = GameWorld(size: frame, matte: BodyRectsMatte(rects: ref.neutralRects), motion: nil, face: nil)
        var steps = 0
        while !game.isOver, steps < 30 * 120 {
            if game.wall == nil { _ = game.startWall(.crouch, around: ref) }
            game.step(1.0 / 30, world: standing)
            steps += 1
        }
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.lives, 0)
    }

    func testTheWallWaitsForYouIfYouWalkOffAtTheLastMoment() {
        var game = HoleInTheWallGame(size: frame, seed: 4)
        let ref = person()
        XCTAssertTrue(game.startWall(.left, around: ref))
        let nobody = GameWorld(size: frame, matte: BodyRectsMatte(), motion: nil, face: nil)
        for _ in 0..<(30 * 20) { game.step(1.0 / 30, world: nobody) }
        XCTAssertEqual(game.lives, 3, "an empty room doesn't lose lives")
        XCTAssertEqual(game.failedWalls, 0)
        XCTAssertLessThan(game.wall?.progress ?? 0, 1, "it holds just short of you")
        let back = GameWorld(size: frame, matte: BodyRectsMatte(rects: ref.neutralRects), motion: nil, face: nil)
        for _ in 0..<(30 * 3) { game.step(1.0 / 30, world: back) }
        XCTAssertEqual(game.failedWalls + game.passedWalls, 1, "and judges you when you are back")
    }

    func testNoMatteAtAllNeverCrashes() {
        var game = HoleInTheWallGame(size: frame, seed: 5)
        for _ in 0..<(30 * 20) { game.step(1.0 / 30, world: GameWorld(size: frame, matte: nil, motion: nil, face: nil)) }
        XCTAssertEqual(game.lives, 3)
        XCTAssertNil(game.wall, "with no one to measure there is no wall to build")
    }

    func testAPerfectPlayerSeesEveryShapeAndNeverRepeatsOne() {
        var game = HoleInTheWallGame(size: frame, seed: 7)
        let standing = person()
        var seen: [BodyHole.Template] = []
        var counted = 0
        for _ in 0..<(30 * 330) where game.passedWalls < 16 {
            var rects = standing.neutralRects
            if game.stage == .approaching, let wall = game.wall, let ref = game.reference, wall.progress > 0.4 {
                rects = wall.hole.idealPose(for: ref, size: frame)
            }
            game.step(1.0 / 30, world: world(rects))
            if game.wallsStarted > counted, let template = game.lastTemplate {
                counted = game.wallsStarted
                seen.append(template)
            }
        }
        XCTAssertEqual(game.failedWalls, 0, "the poses it asks for can always be made")
        XCTAssertGreaterThanOrEqual(game.passedWalls, 16)
        XCTAssertGreaterThanOrEqual(Set(seen).count, 5, "walls vary: \(seen)")
        for (a, b) in zip(seen, seen.dropFirst()) { XCTAssertNotEqual(a, b, "no shape twice in a row") }
        XCTAssertEqual(game.approachSeconds, HoleInTheWallGame.fastestApproach, accuracy: 0.8, "and the walls got faster")
        XCTAssertGreaterThan(game.streak, 10)
    }

    func testTheEasyWallsComeFirst() {
        for seed in 1...6 {
            var game = HoleInTheWallGame(size: frame, seed: UInt64(seed))
            var first: [BodyHole.Template] = []
            let standing = person()
            var counted = 0
            for _ in 0..<(30 * 60) where first.count < 2 {
                var rects = standing.neutralRects
                if game.stage == .approaching, let wall = game.wall, let ref = game.reference, wall.progress > 0.4 { rects = wall.hole.idealPose(for: ref, size: frame) }
                game.step(1.0 / 30, world: world(rects))
                if game.wallsStarted > counted, let t = game.lastTemplate { counted = game.wallsStarted; first.append(t) }
            }
            XCTAssertTrue(first.allSatisfy { [.left, .right, .middle, .crouch].contains($0) }, "seed \(seed): \(first)")
        }
    }

    func testSameSeedBuildsTheSameWalls() {
        func templates(seed: UInt64) -> [BodyHole.Template] {
            var game = HoleInTheWallGame(size: frame, seed: seed)
            var out: [BodyHole.Template] = []
            var counted = 0
            let standing = person()
            for _ in 0..<(30 * 60) {
                var rects = standing.neutralRects
                if let wall = game.wall, let ref = game.reference, game.stage == .approaching, wall.progress > 0.4 { rects = wall.hole.idealPose(for: ref, size: frame) }
                game.step(1.0 / 30, world: world(rects))
                if game.wallsStarted > counted, let t = game.lastTemplate { counted = game.wallsStarted; out.append(t) }
            }
            return out
        }
        XCTAssertEqual(templates(seed: 21), templates(seed: 21))
    }

    func testTheWallGrowsFromFarAwayToFillingThePicture() {
        XCTAssertEqual(HoleInTheWallGame.scale(at: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(HoleInTheWallGame.scale(at: 0), 1.0 / 6, accuracy: 1e-9)
        var last = 0.0
        for i in 0...20 {
            let s = HoleInTheWallGame.scale(at: Double(i) / 20)
            XCTAssertGreaterThan(s, last)
            last = s
        }
        XCTAssertLessThan(HoleInTheWallGame.scale(at: 0.5), 0.3, "most of the growth comes at the end, like a real approach")
    }
}

// MARK: - Bubble Wrap

final class BodyGameBubbleTests: XCTestCase {
    func testTheSheetCoversThePicture() {
        let game = BubbleWrapGame(size: frame, seed: 1)
        XCTAssertGreaterThan(game.bubbles.count, 150)
        XCTAssertLessThan(game.bubbles.count, 300)
        for y in stride(from: 0.0, through: 720, by: 40) {
            for x in stride(from: 0.0, through: 1280, by: 40) {
                let near = game.bubbles.contains { simd_distance($0.center, SIMD2(x, y)) <= BubbleWrapGame.spacing * 0.6 }
                XCTAssertTrue(near, "(\(x), \(y)) is bare")
            }
        }
    }

    func testStandingStillPopsNothingAndTheRoundEnds() {
        var game = BubbleWrapGame(size: frame, seed: 2)
        var steps = 0
        while !game.isOver, steps < 30 * 60 {
            game.step(1.0 / 30, world: world([CGRect(x: 300, y: 0, width: 600, height: 500)], motion: []))
            steps += 1
        }
        XCTAssertEqual(game.popped, 0)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(Double(steps) / 30, BubbleWrapGame.roundSeconds, accuracy: 0.2)
    }

    func testNoMotionAtAllPopsNothing() {
        var game = BubbleWrapGame(size: frame, seed: 3)
        for _ in 0..<60 { game.step(1.0 / 30, world: GameWorld(size: frame, matte: nil, motion: nil, face: nil)) }
        XCTAssertEqual(game.popped, 0)
    }

    func testASwipeBurstsBubblesAlongItsPath() throws {
        var game = BubbleWrapGame(size: frame, seed: 4)
        let hand = CGRect(x: 600, y: 300, width: 120, height: 120)
        game.step(1.0 / 30, world: world(motion: [hand]))
        XCTAssertGreaterThanOrEqual(game.popped, 2)
        XCTAssertLessThan(game.popped, 12, "a hand pops the bubbles under it, not the whole sheet")
        let index = try XCTUnwrap(game.bubble(near: CGPoint(x: 660, y: 360)))
        if case .popped = game.bubbles[index].state {} else { XCTFail("the bubble under the hand is flat") }
        XCTAssertGreaterThanOrEqual(game.score, game.popped, "at least a point each")
        let far = try XCTUnwrap(game.bubble(near: CGPoint(x: 100, y: 100)))
        XCTAssertTrue(game.bubbles[far].isWhole)
    }

    func testAPoppedBubbleDoesNotPopAgainAndRefillsAfterAFewSeconds() {
        var game = BubbleWrapGame(size: frame, seed: 5)
        game.popEverything()
        let count = game.popped
        XCTAssertEqual(game.wholeCount, 0)
        for _ in 0..<10 { game.step(1.0 / 30, world: world(motion: everywhere)) }
        XCTAssertEqual(game.popped, count, "flat bubbles can't be popped again")
        for _ in 0..<(30 * 3) { game.step(1.0 / 30, world: world(motion: [])) }
        XCTAssertLessThan(game.wholeCount, game.bubbles.count / 4, "three seconds later they are mostly still flat")
        for _ in 0..<(30 * 7) { game.step(1.0 / 30, world: world(motion: [])) }
        XCTAssertEqual(game.wholeCount, game.bubbles.count, "ten seconds later the sheet is full again")
    }

    func testQuickPopsBuildAComboAndSlowOnesDoNot() {
        var fast = BubbleWrapGame(size: frame, seed: 6)
        for i in 0..<30 {
            let x = 100.0 + Double(i) * 36
            fast.step(1.0 / 30, world: world(motion: [CGRect(x: x, y: 300, width: 70, height: 70)]))
        }
        XCTAssertGreaterThanOrEqual(fast.multiplier, 3, "a long swipe builds a multiplier, streak \(fast.streak)")
        XCTAssertGreaterThan(fast.score, fast.popped, "which pays more than a point a pop")

        var slow = BubbleWrapGame(size: frame, seed: 6)
        for i in 0..<6 {
            slow.step(1.0 / 30, world: world(motion: [CGRect(x: 100.0 + Double(i) * 180, y: 300, width: 60, height: 60)]))
            for _ in 0..<40 { slow.step(1.0 / 30, world: world(motion: [])) }
        }
        XCTAssertEqual(slow.multiplier, 1, "pops too far apart in time never build a combo")
        XCTAssertLessThan(slow.bestStreak, 6)
    }

    func testGoldenBubblesAreWorthMore() throws {
        var game = BubbleWrapGame(size: frame, seed: 7)
        let gold = try XCTUnwrap(game.bubbles.firstIndex(where: \.gold))
        let at = game.bubbles[gold].center
        game.step(1.0 / 30, world: world(motion: [CGRect(x: at.x - 30, y: at.y - 30, width: 60, height: 60)]))
        XCTAssertEqual(game.goldPopped, 1)
        XCTAssertGreaterThanOrEqual(game.score, 10)
    }

    func testAHandSweepingBackAndForthDoesNotEmptyTheSheetForGood() {
        var game = BubbleWrapGame(size: frame, seed: 8)
        var worstEmpty = 0
        for i in 0..<(30 * 30) {
            let phase = Double(i) / 30
            let x = 640 + 520 * sin(phase * 2.2), y = 360 + 200 * sin(phase * 1.3)
            game.step(1.0 / 30, world: world(motion: [CGRect(x: x - 70, y: y - 70, width: 140, height: 140)]))
            worstEmpty = max(worstEmpty, game.bubbles.count - game.wholeCount)
        }
        XCTAssertGreaterThan(game.popped, 60, "swiping is rewarding")
        XCTAssertLessThan(worstEmpty, game.bubbles.count * 3 / 4, "one hand never clears the sheet")
    }

    func testSameSeedPlaysTheSame() {
        var a = BubbleWrapGame(size: frame, seed: 9), b = BubbleWrapGame(size: frame, seed: 9)
        for i in 0..<300 {
            let motion = [CGRect(x: Double(i % 40) * 30, y: Double(i % 17) * 40, width: 100, height: 100)]
            a.step(1.0 / 30, world: world(motion: motion))
            b.step(1.0 / 30, world: world(motion: motion))
        }
        XCTAssertEqual(a.score, b.score)
        XCTAssertEqual(a.bubbles.map(\.state), b.bubbles.map(\.state))
    }
}

// MARK: - Catalog

final class BodyGameCatalogTests: XCTestCase {
    func testTheBodyGamesAreInTheCatalog() throws {
        for (id, glyph) in [("meteor-dodge", "☄️"), ("hole-in-the-wall", "🕳️"), ("bubble-wrap", "🫧"), ("keepy-uppy", "🏐"), ("laser-limbo", "🚨"),
                            ("punching-bag", "🥊"), ("goalkeeper", "🧤"), ("ninja-stars", "🥷")] {
            let info = try XCTUnwrap(LensCatalog.info(for: id), id)
            XCTAssertEqual(info.category, .games)
            XCTAssertEqual(info.glyph, glyph)
            XCTAssertTrue(info.scored)
            XCTAssertFalse(info.needsFace)
            XCTAssertFalse(info.needsHands)
            XCTAssertFalse(info.blurb.isEmpty)
            let lens = info.make()
            XCTAssertTrue(lens.needs.contains(.matte))
            XCTAssertTrue(lens.wantsMatteGrid)
            XCTAssertEqual(lens.status?.title, nil, "nothing to report before the first frame")
        }
        XCTAssertEqual(BodyGames.all.count, 8)
    }
}

// MARK: - Rendering

final class BodyGameRenderTests: XCTestCase {
    private let h = LensHarness()

    /// A frame of the synthetic scene with the game's drawing laid over it.
    private func picture(_ base: LensInput, _ draw: @escaping (CGContext) -> Void) throws -> CIImage {
        let layer = try XCTUnwrap(h.services.overlay(draw))
        return layer.composited(over: base.composed).cropped(to: base.rect)
    }

    private func nobody(_ base: LensInput) -> LensInput {
        LensInput(time: base.time, dt: base.dt, rect: base.rect, camera: base.camera, matte: nil, background: base.background,
                  composed: base.background ?? base.camera, matteGrid: MatteGrid(outputSize: base.rect.size), face: nil, services: base.services)
    }

    private func nonBlank(_ image: CIImage, against plain: CIImage) -> Bool {
        let a = h.bitmap(image), b = h.bitmap(plain)
        var differing = 0
        for i in stride(from: 0, to: a.bytes.count, by: 4 * 97) where abs(Int(a.bytes[i]) - Int(b.bytes[i])) > 24 || abs(Int(a.bytes[i + 2]) - Int(b.bytes[i + 2])) > 24 { differing += 1 }
        return differing > 12
    }

    // MARK: Meteor Dodge pictures

    func testMeteorDodgeStates() throws {
        let base = h.input()
        var game = MeteorDodgeGame(size: frame, seed: 3)
        game.holdSpawning()
        let body = h.grid

        // Warnings only: shadows closing in, nothing falling yet.
        game.launch(at: SIMD2(300, 260), lean: 0.35, radius: 48, telegraph: 1.2, flight: 0.8)
        game.launch(at: SIMD2(980, 200), lean: -0.3, radius: 40, telegraph: 1.2, flight: 0.8)
        game.launch(at: SIMD2(760, 520), lean: 0.1, radius: 56, telegraph: 1.2, flight: 0.8)
        for _ in 0..<26 { game.step(1.0 / 30, world: GameWorld(size: frame, matte: nil, motion: nil, face: nil)) }
        Output.save(try picture(base) { game.draw(in: $0, time: 0.9) }, as: "bodygame-meteor-warning.png")

        // Mid-flight: trails and glow.
        for _ in 0..<22 { game.step(1.0 / 30, world: GameWorld(size: frame, matte: nil, motion: nil, face: nil)) }
        let flight = try picture(base) { game.draw(in: $0, time: 1.4) }
        Output.save(flight, as: "bodygame-meteor-flight.png")
        XCTAssertTrue(nonBlank(flight, against: base.composed))

        // A pick-up falling, a shield on, and sparks after a landing.
        game.drop(.shield, at: SIMD2(300, 560))
        game.drop(.star, at: SIMD2(1000, 600))
        for _ in 0..<16 { game.step(1.0 / 30, world: GameWorld(size: frame, matte: nil, motion: nil, face: nil)) }
        Output.save(try picture(base) { game.draw(in: $0, time: 2.1) }, as: "bodygame-meteor-landing.png")

        // Hit, with the screen flash; and with the shield bubble round the person.
        var hit = MeteorDodgeGame(size: frame, seed: 4)
        hit.holdSpawning()
        hit.launch(at: SIMD2(640, 360), lean: 0.2, radius: 52, telegraph: 0.3, flight: 0.4)
        for _ in 0..<26 { hit.step(1.0 / 30, world: GameWorld(size: frame, matte: body, motion: nil, face: nil)) }
        XCTAssertEqual(hit.lives, 2)
        let ouch = try picture(base) { hit.draw(in: $0, time: 0.9) }
        Output.save(ouch, as: "bodygame-meteor-hit.png")

        var shielded = MeteorDodgeGame(size: frame, seed: 5)
        shielded.holdSpawning()
        shielded.drop(.shield, at: SIMD2(640, 380))
        for _ in 0..<5 { shielded.step(1.0 / 30, world: GameWorld(size: frame, matte: body, motion: nil, face: nil)) }
        shielded.launch(at: SIMD2(520, 300), lean: 0.2, radius: 50, telegraph: 0.2, flight: 0.3)
        for _ in 0..<18 { shielded.step(1.0 / 30, world: GameWorld(size: frame, matte: body, motion: nil, face: nil)) }
        Output.save(try picture(base) { shielded.draw(in: $0, time: 0.2) }, as: "bodygame-meteor-shield.png")
    }

    // MARK: Hole in the Wall pictures

    func testHoleInTheWallStates() throws {
        let base = h.input()
        let ref = try XCTUnwrap(BodyFrame(scan: BodyScan(matte: h.grid, size: frame)))
        let live = GameWorld(size: frame, matte: h.grid, motion: nil, face: nil)

        for template in BodyHole.Template.allCases where template != .middle {
            var game = HoleInTheWallGame(size: frame, seed: 5)
            guard game.startWall(template, around: ref) else { XCTFail("\(template) should be possible for the synthetic person"); continue }
            for _ in 0..<(30 * 4) { game.step(1.0 / 30, world: live) }
            let wall = try XCTUnwrap(game.wall)
            XCTAssertGreaterThan(wall.progress, 0.5)
            Output.save(try picture(base) { game.draw(in: $0, time: 2) }, as: "bodygame-hole-\(template)-approach.png")
            while let w = game.wall, w.progress < 0.97, game.stage == .approaching { game.step(1.0 / 30, world: live) }
            Output.save(try picture(base) { game.draw(in: $0, time: 3) }, as: "bodygame-hole-\(template)-near.png")
            game.arriveNow()
            Output.save(try picture(base) { game.draw(in: $0, time: 3.1) }, as: "bodygame-hole-\(template)-arrived.png")
        }

        // The far wall, a pass, and a smash.
        var far = HoleInTheWallGame(size: frame, seed: 6)
        XCTAssertTrue(far.startWall(.left, around: ref))
        for _ in 0..<45 { far.step(1.0 / 30, world: live) }
        Output.save(try picture(base) { far.draw(in: $0, time: 1) }, as: "bodygame-hole-far.png")

        var smash = HoleInTheWallGame(size: frame, seed: 7)
        XCTAssertTrue(smash.startWall(.left, around: ref))
        smash.arriveNow()
        for _ in 0..<12 { smash.step(1.0 / 30, world: live) }
        XCTAssertEqual(smash.lives, 2)
        Output.save(try picture(base) { smash.draw(in: $0, time: 1) }, as: "bodygame-hole-smash.png")

        var pass = HoleInTheWallGame(size: frame, seed: 8)
        XCTAssertTrue(pass.startWall(.crouch, around: ref))
        let hole = try XCTUnwrap(pass.wall?.hole)
        let ducked = GameWorld(size: frame, matte: BodyRectsMatte(rects: hole.idealPose(for: ref, size: frame)), motion: nil, face: nil)
        pass.arriveNow()
        for _ in 0..<5 { pass.step(1.0 / 30, world: ducked) }
        XCTAssertEqual(pass.passedWalls, 1)
        Output.save(try picture(base) { pass.draw(in: $0, time: 1) }, as: "bodygame-hole-pass.png")
    }

    // MARK: Bubble Wrap pictures

    func testBubbleWrapStates() throws {
        let base = h.input()
        var game = BubbleWrapGame(size: frame, seed: 4)
        Output.save(try picture(base) { game.draw(in: $0, time: 0.5) }, as: "bodygame-bubbles-fresh.png")

        for i in 0..<40 {
            let x = 120.0 + Double(i) * 26, y = 380 + 160 * sin(Double(i) / 6)
            game.step(1.0 / 30, world: world(motion: [CGRect(x: x - 60, y: y - 60, width: 120, height: 120)]))
        }
        let busy = try picture(base) { game.draw(in: $0, time: 1.4) }
        Output.save(busy, as: "bodygame-bubbles-popping.png")
        XCTAssertTrue(nonBlank(busy, against: base.composed))

        for _ in 0..<(30 * 5 + 6) { game.step(1.0 / 30, world: world(motion: [])) }
        Output.save(try picture(base) { game.draw(in: $0, time: 7) }, as: "bodygame-bubbles-refilling.png")
    }

    // MARK: Through the lens

    func testEachGameRendersThroughItsLensWithAndWithoutAPerson() throws {
        let base = h.input()
        let empty = nobody(base)
        let lenses: [(String, Lens, Int)] = [
            ("meteor", GameLens<MeteorDodgeGame>(id: "test.meteor", needs: [.matte], store: MemoryScoreStore()), 30 * 9),
            ("hole", GameLens<HoleInTheWallGame>(id: "test.hole", needs: [.matte], store: MemoryScoreStore()), 30 * 10),
            ("bubbles", GameLens<BubbleWrapGame>(id: "test.bubbles", needs: [.matte], store: MemoryScoreStore()), 30 * 8),
        ]
        // A dozen poses of a person swaying, drawn once and replayed, so there is motion to pop bubbles with.
        let sway: [LensInput] = (0..<12).map { k in
            var scene = SyntheticScene()
            scene.center.x = 640 + 200 * sin(Double(k) / 12 * 2 * .pi)
            let grid = MatteGrid(outputSize: frame)
            let made = scene.input(services: h.services, compositor: h.compositor, grid: grid, background: SyntheticScene.backdrop())
            return made
        }
        for (name, lens, frames) in lenses {
            lens.restart()
            var out = base.composed
            for i in 0..<frames {
                let pose = sway[(i / 2) % sway.count]
                out = lens.render(h.at(pose, time: Double(i) / 30))
            }
            XCTAssertEqual(out.extent.size, frame, "\(name) covers the picture")
            XCTAssertNotNil(lens.status, name)
            Output.save(out, as: "bodygame-\(name)-lens.png")

            let lonely = LensHarness()
            let none = lonely.at(empty, time: 0)
            var emptyOut = none.composed
            for i in 0..<45 { emptyOut = lens.render(lonely.at(none, time: 20 + Double(i) / 30)) }
            XCTAssertEqual(emptyOut.extent.size, frame, "\(name) with no one in view")
            Output.save(emptyOut, as: "bodygame-\(name)-lens-empty.png")

            // And with no silhouette grid at all, as when the pipeline has none to give.
            let gridless = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: base.background,
                                     composed: base.camera, matteGrid: nil, face: nil, services: base.services)
            for _ in 0..<10 { XCTAssertEqual(lens.render(gridless).extent.size, frame, "\(name) with no grid") }
        }
    }

    /// What a lens adds to a frame: the same lens loop against a lens that does nothing.
    func testEachGameAddsLittleToTheFrame() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        final class Nothing: Lens {
            let needs: LensNeeds = [.matte]
            var wantsMatteGrid: Bool { true }
            func render(_ input: LensInput) -> CIImage { input.composed }
        }
        let base = h.input()
        let baseline = h.cost(of: Nothing(), base: base)
        print(String(format: "PERF body games: baseline mean %.1f ms", baseline.mean))
        var lenses: [(String, Lens)] = []
        for id in ["meteor-dodge", "hole-in-the-wall", "bubble-wrap", "keepy-uppy", "laser-limbo", "punching-bag", "goalkeeper", "ninja-stars",
                   "balloon-pop", "breakout", "ball-pit"] {
            lenses.append((id, BodyGameNewLensTests.lens(id)))
        }
        for (name, lens) in lenses {
            lens.restart()
            for i in 0..<120 { _ = lens.render(h.at(base, time: Double(i) / 30)) }              // through the countdown, into the game
            let cost = h.cost(of: lens, base: base, frames: 150)
            print(String(format: "PERF %-18@ mean %5.1f ms  worst %5.1f ms  (+%.1f)", name as NSString, cost.mean, cost.worst, cost.mean - baseline.mean))
            XCTAssertLessThan(cost.mean - baseline.mean, 9, "\(name) adds too much to every frame")
        }
    }

    /// An empty room shows the waiting screen; stepping in starts a countdown and then the game.
    private func checkTheLensWaitsThenPlays<G: Game>(_ lens: GameLens<G>, _ name: String) throws {
        let base = h.input()
        let none = nobody(base)
        var out = none.composed
        for i in 0..<20 { out = lens.render(h.at(none, time: Double(i) / 30)) }
        XCTAssertEqual(lens.phase, .waiting, name)
        XCTAssertEqual(lens.status?.title, "Step into the frame to play", name)
        XCTAssertTrue(nonBlank(out, against: none.composed), "\(name) asks you to step in")

        for i in 0..<20 { _ = lens.render(h.at(base, time: 1 + Double(i) / 30)) }
        guard case .countdown = lens.phase else { return XCTFail("\(name): expected a countdown, got \(lens.phase)") }
        for i in 0..<(30 * 4) { _ = lens.render(h.at(base, time: 2 + Double(i) / 30)) }
        XCTAssertEqual(lens.phase, .playing, name)
        XCTAssertTrue(lens.status?.title.hasPrefix("Score") ?? false, name)
    }

    func testEveryGameWaitsForSomeoneThenCountsDownAndPlays() throws {
        try checkTheLensWaitsThenPlays(GameLens<MeteorDodgeGame>(id: "test.meteor.wait", needs: [.matte], store: MemoryScoreStore()), "meteor")
        try checkTheLensWaitsThenPlays(GameLens<HoleInTheWallGame>(id: "test.hole.wait", needs: [.matte], store: MemoryScoreStore()), "hole")
        try checkTheLensWaitsThenPlays(GameLens<BubbleWrapGame>(id: "test.bubbles.wait", needs: [.matte], store: MemoryScoreStore()), "bubbles")
    }
}
