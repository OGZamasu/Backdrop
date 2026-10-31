import CoreImage
import simd
import XCTest

private let handFrame = CGSize(width: 1280, height: 720)
private let tick = 1.0 / 30

private func handWorld(_ hands: [HandState] = []) -> GameWorld {
    GameWorld(size: handFrame, matte: nil, motion: nil, face: nil, hands: hands)
}

/// Hands for the tests, placed by the point that matters to the game.
private enum TestHands {
    static func make(_ fingers: HandFixtures.Fingers, palmAt p: CGPoint, size: Double = 100, id: Int = 1) -> HandState {
        let base = HandFixtures.hand(fingers, at: .zero, size: size, id: id)
        return HandFixtures.moved(base, by: CGVector(dx: p.x - base.palm.x, dy: p.y - base.palm.y))
    }

    static func pointing(tipAt p: CGPoint, size: Double = 100, id: Int = 1) -> HandState {
        let base = HandFixtures.hand(.point, at: .zero, size: size, id: id)
        return HandFixtures.moved(base, by: CGVector(dx: p.x - base.indexTip.x, dy: p.y - base.indexTip.y))
    }
}

/// A player who always has a fingertip on its way to a mole worth hitting.
private struct MoleBot {
    var tip = CGPoint(x: 640, y: 150)

    mutating func hands(for game: WhackAMoleGame) -> [HandState] {
        let targets = game.moles.filter { $0.kind.isTarget && game.isHittable($0) }
        if let target = targets.min(by: { $0.age > $1.age }) {
            let head = game.head(of: target)
            let dx = head.x - tip.x, dy = head.y - tip.y, distance = hypot(dx, dy)
            if distance > 1 {
                let step = min(distance, 55)
                tip.x += dx / distance * step
                tip.y += dy / distance * step
            }
        }
        return [TestHands.pointing(tipAt: tip)]
    }
}

// MARK: - Following hands

final class HandGamePokeTrackerTests: XCTestCase {
    private func follow(_ tracker: inout HandPokeTracker, _ path: [CGPoint], start: Double = 0) -> [HandPokeTracker.Hitter] {
        var last: [HandPokeTracker.Hitter] = []
        for (i, p) in path.enumerated() { last = tracker.update([TestHands.make(.open, palmAt: p)], now: start + Double(i) * tick) }
        return last
    }

    func testEachHandGivesAPalmAndFiveFingertips() {
        var tracker = HandPokeTracker()
        let hitters = tracker.update([TestHands.make(.open, palmAt: CGPoint(x: 400, y: 300), id: 1), TestHands.make(.fist, palmAt: CGPoint(x: 800, y: 300), id: 2)], now: 0)
        XCTAssertEqual(hitters.count, 12)
        XCTAssertEqual(hitters.filter(\.isPalm).count, 2)
        XCTAssertGreaterThan(hitters.first { $0.isPalm }?.radius ?? 0, hitters.first { !$0.isPalm }?.radius ?? 99, "the palm is wider than a fingertip")
    }

    func testAHandAtRestOrTremblingIsStill() {
        var tracker = HandPokeTracker()
        let still = follow(&tracker, Array(repeating: CGPoint(x: 500, y: 300), count: 30))
        XCTAssertTrue(still.allSatisfy { !$0.isPoking }, "no motion, no poke")

        var shaky = HandPokeTracker()
        let jitter = (0..<30).map { CGPoint(x: 500 + ($0 % 2 == 0 ? 3 : -3), y: 300 + ($0 % 3 == 0 ? 2 : -2)) }
        let trembling = follow(&shaky, jitter)
        XCTAssertTrue(trembling.allSatisfy { !$0.isPoking }, "a few pixels of tracking noise is not a poke")
    }

    func testAQuickMovementPokesWithEveryPartOfTheHand() {
        var tracker = HandPokeTracker()
        let path = (0..<8).map { CGPoint(x: 300 + Double($0) * 50, y: 300) }       // 1500 px/s
        let fast = follow(&tracker, path)
        XCTAssertEqual(fast.count, 6)
        XCTAssertTrue(fast.allSatisfy(\.isPoking), "palm, thumb and all four fingertips")
        XCTAssertEqual(fast.first?.speed ?? 0, 1500, accuracy: 120)
    }

    func testAGentleMovementStillCounts() {
        var tracker = HandPokeTracker()
        let path = (0..<20).map { CGPoint(x: 300 + Double($0) * 6, y: 300) }       // 180 px/s
        XCTAssertTrue(follow(&tracker, path).allSatisfy(\.isPoking), "do not make it hard")
    }

    func testTheSpeedThatCountsScalesWithTheHand() {
        var near = HandPokeTracker(), far = HandPokeTracker()
        // 200 px/s is a poke for a small, far-away hand but a lazy drift for a hand held right up to the camera.
        var a: [HandPokeTracker.Hitter] = [], b: [HandPokeTracker.Hitter] = []
        for i in 0..<20 {
            let p = CGPoint(x: 300 + Double(i) * 6.7, y: 300)
            a = far.update([TestHands.make(.open, palmAt: p, size: 50)], now: Double(i) * tick)
            b = near.update([TestHands.make(.open, palmAt: p, size: 300)], now: Double(i) * tick)
        }
        XCTAssertTrue(a.allSatisfy(\.isPoking))
        XCTAssertFalse(b.contains { $0.isPoking })
    }

    func testAHandThatWasLostStartsAFreshTrail() {
        var tracker = HandPokeTracker()
        _ = follow(&tracker, (0..<8).map { CGPoint(x: 300 + Double($0) * 50, y: 300) })
        // Gone for most of a second, back somewhere else: it has not "moved" from the old place.
        let back = tracker.update([TestHands.make(.open, palmAt: CGPoint(x: 900, y: 300))], now: 1.2)
        XCTAssertTrue(back.allSatisfy { $0.previous == $0.position }, "no sweep across the gap")
        XCTAssertTrue(back.allSatisfy { !$0.isPoking })
    }

    func testAJumpIsNotASweep() {
        var tracker = HandPokeTracker()
        _ = tracker.update([TestHands.make(.open, palmAt: CGPoint(x: 200, y: 300))], now: 0)
        let jumped = tracker.update([TestHands.make(.open, palmAt: CGPoint(x: 1000, y: 300))], now: tick)
        XCTAssertTrue(jumped.allSatisfy { $0.previous == $0.position }, "a tracking jump of 800 px is not a hand crossing the picture")
    }

    func testNoHandsGiveNothingAndForgetTheOldOnes() {
        var tracker = HandPokeTracker()
        XCTAssertTrue(tracker.update([], now: 0).isEmpty)
        _ = follow(&tracker, (0..<5).map { CGPoint(x: 300 + Double($0) * 50, y: 300) })
        XCTAssertTrue(tracker.update([], now: 2).isEmpty)
    }
}

// MARK: - Whack-a-Mole

final class HandGameWhackTests: XCTestCase {
    private func fresh(seed: UInt64 = 1) -> WhackAMoleGame {
        var game = WhackAMoleGame(size: handFrame, seed: seed)
        game.pauseSpawns()
        return game
    }

    private func headPosition(_ game: WhackAMoleGame, hole: Int) -> CGPoint {
        let mole = game.moles.first { $0.hole == hole }
        return mole.map { game.head(of: $0) } ?? game.holes[hole]
    }

    /// A fingertip swings in from the side and touches `point`, then the hand goes away.
    private func poke(_ game: inout WhackAMoleGame, at point: CGPoint, from offset: CGVector = CGVector(dx: -260, dy: 0), frames: Int = 5) {
        for i in 0...frames {
            let k = 1 - Double(i) / Double(frames)
            let tip = CGPoint(x: point.x + offset.dx * k, y: point.y + offset.dy * k)
            game.step(tick, world: handWorld([TestHands.pointing(tipAt: tip)]))
        }
        for _ in 0..<3 { game.step(tick, world: handWorld()) }
    }

    func testThereAreSevenToNineHolesAcrossThePicture() {
        let game = fresh()
        XCTAssertTrue((7...9).contains(game.holes.count))
        XCTAssertLessThan(game.holes.map(\.x).min() ?? 9999, 220)
        XCTAssertGreaterThan(game.holes.map(\.x).max() ?? 0, 1060, "the lawn runs the width of the picture")
        XCTAssertTrue(game.holes.allSatisfy { $0.x > 100 && $0.x < 1180 && $0.y > 100 && $0.y < 560 })
        XCTAssertEqual(Set(game.holes.map { "\($0.x),\($0.y)" }).count, game.holes.count)
    }

    func testMolesPopUpAndDuckBackDown() {
        var game = WhackAMoleGame(size: handFrame, seed: 3)
        var mostAtOnce = 0
        var peaked = false
        for _ in 0..<(30 * 20) {
            game.step(tick, world: handWorld())
            mostAtOnce = max(mostAtOnce, game.moles.count)
            XCTAssertTrue(game.moles.allSatisfy { game.holes.indices.contains($0.hole) })
            if game.moles.contains(where: { game.rise(of: $0) == 1 }) { peaked = true }
        }
        XCTAssertGreaterThan(game.spawned, 8)
        XCTAssertTrue(peaked, "they come all the way up")
        XCTAssertGreaterThan(game.escaped, 3, "with nobody there, they get away")
        XCTAssertLessThanOrEqual(mostAtOnce, 4)
        XCTAssertEqual(game.score, 0)
    }

    func testNoTwoMolesShareAHole() {
        var game = WhackAMoleGame(size: handFrame, seed: 8)
        for _ in 0..<(30 * 44) {
            game.step(tick, world: handWorld())
            XCTAssertEqual(Set(game.moles.map(\.hole)).count, game.moles.count)
        }
    }

    func testTheRoundGetsFasterAsItGoesOn() {
        for seed in [1, 2, 3, 4] as [UInt64] {
            var game = WhackAMoleGame(size: handFrame, seed: seed)
            var spawnedAt15 = 0, spawnedAt30 = 0
            var earlyStays: [Double] = [], lateStays: [Double] = []
            var seen = Set<Int>()
            for i in 0..<(30 * 45) {
                game.step(tick, world: handWorld())
                let t = Double(i) / 30
                if t >= 14.9 && spawnedAt15 == 0 { spawnedAt15 = game.spawned }
                if t >= 29.9 && spawnedAt30 == 0 { spawnedAt30 = game.spawned }
                for m in game.moles where !seen.contains(game.spawned) && m.age < 0.05 {
                    seen.insert(game.spawned)
                    if t < 15 { earlyStays.append(m.stay) } else if t > 30 { lateStays.append(m.stay) }
                }
            }
            let early = spawnedAt15, late = game.spawned - spawnedAt30
            XCTAssertGreaterThan(late, early, "seed \(seed): more moles in the last 15 seconds (\(late)) than the first (\(early))")
            if !earlyStays.isEmpty && !lateStays.isEmpty {
                XCTAssertLessThan(lateStays.reduce(0, +) / Double(lateStays.count), earlyStays.reduce(0, +) / Double(earlyStays.count),
                                  "and each one stays up for less time")
            }
        }
    }

    func testBombsBunniesAndGoldMolesAllTurnUp() {
        var kinds = Set<String>()
        for seed in [1, 2, 3, 4, 5] as [UInt64] {
            var game = WhackAMoleGame(size: handFrame, seed: seed)
            for _ in 0..<(30 * 45) {
                game.step(tick, world: handWorld())
                for m in game.moles { kinds.insert("\(m.kind)") }
            }
        }
        XCTAssertEqual(kinds, ["mole", "golden", "bunny", "bomb"])
    }

    func testTheFirstFewSecondsAreOnlyMoles() {
        for seed in [1, 2, 3, 4, 5, 6] as [UInt64] {
            var game = WhackAMoleGame(size: handFrame, seed: seed)
            for _ in 0..<(30 * 3) {
                game.step(tick, world: handWorld())
                XCTAssertTrue(game.moles.allSatisfy { $0.kind == .mole })
            }
        }
    }

    // MARK: Poking

    func testAFingertipPokeWhacksAMole() throws {
        var game = fresh()
        game.place(.mole, hole: 1)
        let head = headPosition(game, hole: 1)
        poke(&game, at: head)
        XCTAssertEqual(game.whacks, 1)
        XCTAssertEqual(game.score, 1)
        XCTAssertNotNil(game.moles.first?.whacked, "it is squashed, and not gone at once")
        XCTAssertFalse(game.isHittable(try XCTUnwrap(game.moles.first)), "and cannot be whacked twice")
    }

    func testTheSquashedMoleSlidesBackDownAndIsGone() {
        var game = fresh()
        game.place(.mole, hole: 2)
        poke(&game, at: headPosition(game, hole: 2))
        for _ in 0..<30 { game.step(tick, world: handWorld()) }
        XCTAssertTrue(game.moles.isEmpty)
        XCTAssertEqual(game.score, 1)
    }

    func testAHandRestingOverAHoleWinsNothing() {
        var game = fresh()
        game.place(.mole, hole: 0, stay: 20)
        let head = headPosition(game, hole: 0)
        // A pointing finger, an open palm and a trembling fist, all sitting on the mole for three seconds.
        for i in 0..<90 {
            game.step(tick, world: handWorld([TestHands.pointing(tipAt: head)]))
            XCTAssertEqual(game.whacks, 0, "frame \(i)")
        }
        for _ in 0..<90 { game.step(tick, world: handWorld([TestHands.make(.open, palmAt: head, id: 2)])) }
        for i in 0..<90 {
            let wobble = CGPoint(x: head.x + (i % 2 == 0 ? 3 : -3), y: head.y + (i % 3 == 0 ? 2 : -2))
            game.step(tick, world: handWorld([TestHands.make(.fist, palmAt: wobble, id: 3)]))
        }
        XCTAssertEqual(game.whacks, 0)
        XCTAssertEqual(game.score, 0)
        XCTAssertNil(game.moles.first?.whacked)
    }

    func testAGentleApproachStillWhacks() {
        var game = fresh()
        game.place(.mole, hole: 4, stay: 20)
        let head = headPosition(game, hole: 4)
        // Six pixels a frame, 180 a second: nowhere near a slap.
        for i in 0..<70 {
            let tip = CGPoint(x: head.x - 300 + Double(i) * 6, y: head.y)
            game.step(tick, world: handWorld([TestHands.pointing(tipAt: tip)]))
        }
        XCTAssertEqual(game.whacks, 1)
    }

    func testMovingFarFromAMoleWhacksNothing() {
        var game = fresh()
        game.place(.mole, hole: 0, stay: 20)
        let head = headPosition(game, hole: 0)
        for i in 0..<60 {
            let tip = CGPoint(x: head.x + 400 + 60 * sin(Double(i) / 3), y: head.y - 300 + 80 * cos(Double(i) / 3))
            game.step(tick, world: handWorld([TestHands.pointing(tipAt: tip)]))
        }
        XCTAssertEqual(game.whacks, 0)
    }

    func testAnOpenPalmSlapWhacks() {
        var game = fresh()
        game.place(.mole, hole: 5)
        let head = headPosition(game, hole: 5)
        for i in 0...4 {
            let palm = CGPoint(x: head.x, y: head.y + 40 + 250 * (1 - Double(i) / 4))
            game.step(tick, world: handWorld([TestHands.make(.open, palmAt: palm)]))
        }
        XCTAssertEqual(game.whacks, 1)
    }

    func testEitherHandWorks() {
        for id in [1, 2] {
            var game = fresh()
            game.place(.mole, hole: 6)
            let head = headPosition(game, hole: 6)
            let resting = TestHands.make(.fist, palmAt: CGPoint(x: 100, y: 100), id: id == 1 ? 2 : 1)
            for i in 0...5 {
                let k = 1 - Double(i) / 5
                game.step(tick, world: handWorld([resting, TestHands.pointing(tipAt: CGPoint(x: head.x - 250 * k, y: head.y), id: id)]))
            }
            XCTAssertEqual(game.whacks, 1, "hand id \(id)")
        }
    }

    func testAPokeThatCrossesAMoleBetweenTwoFramesStillLands() {
        var game = fresh()
        game.place(.mole, hole: 3)
        let head = headPosition(game, hole: 3)
        game.step(tick, world: handWorld([TestHands.pointing(tipAt: CGPoint(x: head.x - 140, y: head.y))]))
        game.step(tick, world: handWorld([TestHands.pointing(tipAt: CGPoint(x: head.x + 140, y: head.y))]))
        XCTAssertEqual(game.whacks, 1)
    }

    func testATrackingJumpAcrossThePictureIsNotAPoke() {
        var game = fresh()
        game.place(.mole, hole: 3)
        let head = headPosition(game, hole: 3)
        game.step(tick, world: handWorld([TestHands.pointing(tipAt: CGPoint(x: head.x - 450, y: head.y))]))
        game.step(tick, world: handWorld([TestHands.pointing(tipAt: CGPoint(x: head.x + 450, y: head.y))]))
        XCTAssertEqual(game.whacks, 0)
    }

    func testAMoleStillSinkingBelowHalfwayCannotBeHit() {
        var game = fresh()
        game.place(.mole, hole: 1, stay: 0)
        for _ in 0..<5 { game.step(tick, world: handWorld()) }      // 0.17 s in: about to sink
        guard let mole = game.moles.first else { return XCTFail("still there") }
        if game.rise(of: mole) <= 0.5 {
            let head = game.head(of: mole)
            for i in 0...3 { game.step(tick, world: handWorld([TestHands.pointing(tipAt: CGPoint(x: head.x - 200 * (1 - Double(i) / 3), y: head.y))])) }
            XCTAssertEqual(game.whacks, 0)
        }
    }

    // MARK: Scoring

    func testRunsOfHitsBuildAMultiplier() {
        var game = fresh()
        var scores: [Int] = []
        for _ in 0..<6 {
            game.place(.mole, hole: 1)
            poke(&game, at: headPosition(game, hole: 1))
            scores.append(game.score)
        }
        XCTAssertEqual(scores, [1, 2, 4, 6, 8, 11], "x2 from the third hit, x3 from the sixth")
        XCTAssertEqual(game.multiplier, 3)
        XCTAssertEqual(game.whacks, 6)
        XCTAssertTrue(game.summary.hasPrefix("x3"))
    }

    func testGoldIsWorthFive() {
        var game = fresh()
        game.place(.golden, hole: 2)
        poke(&game, at: headPosition(game, hole: 2))
        XCTAssertEqual(game.score, 5)
    }

    func testBunniesAndBombsCostPointsButNeverGoBelowZero() {
        var game = fresh()
        for _ in 0..<4 { game.place(.mole, hole: 0); poke(&game, at: headPosition(game, hole: 0)) }
        XCTAssertEqual(game.score, 1 + 1 + 2 + 2, "a few moles first (from the third hit they pay double)")
        game.place(.bunny, hole: 0)
        poke(&game, at: headPosition(game, hole: 0))
        XCTAssertEqual(game.score, 6 - 3)
        XCTAssertEqual(game.combo, 0, "the run is over")
        XCTAssertEqual(game.bunniesHit, 1)
        game.place(.bomb, hole: 0)
        poke(&game, at: headPosition(game, hole: 0))
        XCTAssertEqual(game.score, 0, "a bomb costs five, and three was all there was")
        game.place(.bomb, hole: 0)
        poke(&game, at: headPosition(game, hole: 0))
        game.place(.bunny, hole: 0)
        poke(&game, at: headPosition(game, hole: 0))
        XCTAssertEqual(game.score, 0, "and it never goes negative")
        XCTAssertEqual(game.bombsHit, 2)
    }

    func testLettingBunniesAndBombsGoCostsNothing() {
        var game = fresh()
        game.place(.bunny, hole: 0, stay: 0.4)
        game.place(.bomb, hole: 5, stay: 0.4)
        for _ in 0..<60 { game.step(tick, world: handWorld()) }
        XCTAssertTrue(game.moles.isEmpty)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.escaped, 0, "only moles you wanted count as getting away")
    }

    func testAMoleThatGetsAwayEndsTheRun() {
        var game = fresh()
        for _ in 0..<3 { game.place(.mole, hole: 1); poke(&game, at: headPosition(game, hole: 1)) }
        XCTAssertEqual(game.combo, 3)
        game.place(.mole, hole: 2, stay: 0.3)
        for _ in 0..<45 { game.step(tick, world: handWorld()) }
        XCTAssertEqual(game.combo, 0)
        XCTAssertEqual(game.escaped, 1)
    }

    // MARK: The round

    func testAPlayerWhoKeepsPokingScoresAndAnIdleOneDoesNot() {
        var played = WhackAMoleGame(size: handFrame, seed: 7), idle = WhackAMoleGame(size: handFrame, seed: 7)
        var bot = MoleBot()
        for _ in 0..<(30 * 46) {
            played.step(tick, world: handWorld(bot.hands(for: played)))
            idle.step(tick, world: handWorld([TestHands.pointing(tipAt: CGPoint(x: 640, y: 80))]))
        }
        XCTAssertTrue(played.isOver)
        XCTAssertGreaterThan(played.whacks, 15, "a hand that keeps up gets plenty of them")
        XCTAssertGreaterThan(played.score, 20)
        XCTAssertEqual(idle.score, 0)
        XCTAssertGreaterThan(played.score, idle.score)
    }

    func testTheRoundLastsFortyFiveSecondsAndEnds() {
        var game = WhackAMoleGame(size: handFrame, seed: 5)
        var steps = 0
        while !game.isOver && steps < 30 * 60 { game.step(tick, world: handWorld()); steps += 1 }
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(Double(steps) / 30, WhackAMoleGame.roundSeconds, accuracy: 0.2)
        XCTAssertTrue(game.moles.isEmpty, "the lawn is empty at the end")
        let after = game.score
        game.step(1, world: handWorld())
        XCTAssertEqual(game.score, after)
    }

    func testTheSameSeedPlaysTheSame() {
        func run(_ seed: UInt64) -> (Int, [Int], [Int]) {
            var game = WhackAMoleGame(size: handFrame, seed: seed)
            var holes: [Int] = []
            for i in 0..<400 {
                let hands = i % 40 < 12 ? [TestHands.pointing(tipAt: CGPoint(x: 100 + Double(i % 40) * 90, y: 300))] : []
                game.step(tick, world: handWorld(hands))
                holes.append(contentsOf: game.moles.map(\.hole))
            }
            return (game.score, game.moles.map(\.hole), holes)
        }
        let a = run(11), b = run(11), c = run(12)
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, b.1)
        XCTAssertEqual(a.2, b.2)
        XCTAssertNotEqual(a.2, c.2, "another seed, another lawn")
    }

    func testHandsComingAndGoingNeverBreakIt() {
        var game = WhackAMoleGame(size: handFrame, seed: 21)
        var rng = SplitMix64(seed: 99)
        for i in 0..<(30 * 45) {
            var hands: [HandState] = []
            // A hand that blinks in and out, jumps about and sometimes brings a second one.
            if Int.random(in: 0..<4, using: &rng) != 0 {
                hands.append(TestHands.make(.point, palmAt: CGPoint(x: Double.random(in: 0...1280, using: &rng), y: Double.random(in: 0...720, using: &rng)), id: 1 + i / 50 % 3))
            }
            if i % 90 < 30 { hands.append(TestHands.make(.open, palmAt: CGPoint(x: 900, y: 200), id: 9)) }
            game.step(tick, world: handWorld(hands))
            XCTAssertGreaterThanOrEqual(game.score, 0)
        }
        XCTAssertTrue(game.isOver)
    }

    func testAHugeStepDoesNotBreakIt() {
        var game = WhackAMoleGame(size: handFrame, seed: 2)
        game.step(30, world: handWorld([TestHands.make(.open, palmAt: CGPoint(x: 400, y: 300))]))
        XCTAssertGreaterThan(game.timeLeft, 0, "one step cannot eat the whole round")
        game.step(-1, world: handWorld())
        XCTAssertLessThanOrEqual(game.timeLeft, WhackAMoleGame.roundSeconds)
    }

    func testTheWaitingScreenAsksForAHand() {
        XCTAssertEqual(WhackAMoleGame.presenceHint, "Hold up your hand to play")
    }
}

// MARK: - Rock Paper Scissors

final class HandGameRockPaperScissorsTests: XCTestCase {
    typealias Game = RockPaperScissorsGame

    private let rock = TestHands.make(.fist, palmAt: CGPoint(x: 640, y: 300))
    private let paper = TestHands.make(.open, palmAt: CGPoint(x: 640, y: 300))
    private let scissors = TestHands.make(.peace, palmAt: CGPoint(x: 640, y: 300))

    private func hand(for move: Game.Move) -> HandState {
        switch move {
        case .rock: return rock
        case .paper: return paper
        case .scissors: return scissors
        }
    }

    /// Plays the countdown showing `counting`, then gives the frames of SHOOT to `reading`, up to the reveal.
    private func play(_ game: inout Game, counting: [HandState] = [], reading: (Int) -> [HandState]) {
        var guardCount = 0
        while game.stage != .reading && guardCount < 600 { game.step(tick, world: handWorld(counting)); guardCount += 1 }
        var frame = 0
        while game.stage == .reading && guardCount < 1200 { game.step(tick, world: handWorld(reading(frame))); frame += 1; guardCount += 1 }
    }

    /// Plays a whole round to the reveal, with the computer set to `pick` and the player showing `show`.
    private func round(_ game: inout Game, pick: Game.Move, show: Game.Move?) {
        while game.stage != .ready { game.step(tick, world: handWorld()) }
        game.setPick(pick)
        play(&game) { _ in show.map { [self.hand(for: $0)] } ?? [] }
    }

    func testTheThreeGesturesAreReadFromTheHand() {
        XCTAssertEqual(Game.gesture(of: rock), .rock)
        XCTAssertEqual(Game.gesture(of: paper), .paper)
        XCTAssertEqual(Game.gesture(of: scissors), .scissors)
        XCTAssertNil(Game.gesture(of: HandFixtures.hand(.point)), "one finger is not scissors")
        XCTAssertNil(Game.gesture(of: HandFixtures.hand(.gun)))
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: .pi / 5) {
            XCTAssertEqual(Game.gesture(of: HandFixtures.hand(.fist, size: 70, angle: angle)), .rock)
            XCTAssertEqual(Game.gesture(of: HandFixtures.hand(.open, size: 150, angle: angle, mirrored: true)), .paper)
            XCTAssertEqual(Game.gesture(of: HandFixtures.hand(.peace, angle: angle)), .scissors)
        }
    }

    func testTheGestureRulesAgreeWithWhatVisionReported() {
        XCTAssertEqual(Game.gesture(of: HandFixtures.recorded(HandFixtures.Recorded.openPalm)), .paper)
        XCTAssertNil(Game.gesture(of: HandFixtures.recorded(HandFixtures.Recorded.pointUp)), "a pointing finger is none of the three")
        XCTAssertNil(Game.gesture(of: HandFixtures.recorded(HandFixtures.Recorded.pointRight)))
    }

    func testWhoBeatsWho() {
        XCTAssertTrue(Game.Move.rock.beats(.scissors))
        XCTAssertTrue(Game.Move.paper.beats(.rock))
        XCTAssertTrue(Game.Move.scissors.beats(.paper))
        for a in Game.Move.allCases {
            XCTAssertFalse(a.beats(a))
            for b in Game.Move.allCases where a != b { XCTAssertNotEqual(a.beats(b), b.beats(a)) }
        }
    }

    func testTheCountdownRunsRockPaperScissorsThenShoot() {
        var game = Game(size: handFrame, seed: 1)
        var seen: [Game.Stage] = []
        for _ in 0..<400 {
            game.step(tick, world: handWorld([rock]))
            if seen.last != game.stage { seen.append(game.stage) }
            if game.stage == .reveal { break }
        }
        XCTAssertEqual(seen, [.ready, .beat(0), .beat(1), .beat(2), .reading, .reveal])
    }

    func testWinningARound() {
        var game = Game(size: handFrame, seed: 1)
        round(&game, pick: .rock, show: .paper)
        XCTAssertEqual(game.outcome, .win)
        XCTAssertEqual(game.yours, .paper)
        XCTAssertEqual(game.score, 1)
        XCTAssertEqual(game.round, 1)
        XCTAssertEqual(game.losses, 0)
    }

    func testLosingARound() {
        var game = Game(size: handFrame, seed: 1)
        round(&game, pick: .paper, show: .rock)
        XCTAssertEqual(game.outcome, .lose)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.round, 1)
        XCTAssertEqual(game.losses, 1)
    }

    func testEveryPairingGivesTheRightResult() {
        for mine in Game.Move.allCases {
            for theirs in Game.Move.allCases {
                var game = Game(size: handFrame, seed: 4)
                round(&game, pick: theirs, show: mine)
                let expected: Game.Outcome = mine == theirs ? .draw : mine.beats(theirs) ? .win : .lose
                XCTAssertEqual(game.outcome, expected, "\(mine) against \(theirs)")
            }
        }
    }

    func testADrawIsPlayedAgainWithoutCounting() {
        var game = Game(size: handFrame, seed: 1)
        round(&game, pick: .scissors, show: .scissors)
        XCTAssertEqual(game.outcome, .draw)
        XCTAssertEqual(game.round, 0)
        XCTAssertEqual(game.draws, 1)
        while game.stage == .reveal { game.step(tick, world: handWorld()) }
        XCTAssertEqual(game.stage, .ready, "straight into the same round again")
        XCTAssertEqual(game.round, 0)
        XCTAssertFalse(game.isOver)
    }

    func testNothingClearMeansAgainWithoutScoring() {
        // No hand at all, and a hand that never settles on a shape.
        let shapes = [rock, paper, scissors, HandFixtures.hand(.point)]
        let scenarios: [(String, (Int) -> [HandState])] = [("no hand", { _ in [] }), ("restless hand", { [shapes[$0 / 2 % 4]] })]
        for (name, reading) in scenarios {
            var game = Game(size: handFrame, seed: 1)
            while game.stage != .ready { game.step(tick, world: handWorld()) }
            game.setPick(.paper)
            play(&game, reading: reading)
            XCTAssertEqual(game.outcome, .unread, name)
            XCTAssertNil(game.yours, name)
            XCTAssertEqual(game.score, 0, name)
            XCTAssertEqual(game.round, 0, name)
            XCTAssertEqual(game.losses, 0, name)
            XCTAssertEqual(game.unreadStreak, 1, name)
        }
    }

    func testAFlickeringHandIsReadByMajority() {
        // Mostly paper, with a bad frame in every three: still paper.
        var game = Game(size: handFrame, seed: 1)
        while game.stage != .ready { game.step(tick, world: handWorld()) }
        game.setPick(.rock)
        play(&game) { frame in [frame % 3 == 0 ? self.rock : self.paper] }
        XCTAssertEqual(game.yours, .paper)
        XCTAssertEqual(game.outcome, .win)

        // Even a hand that drops out of view for some of the frames.
        var dropping = Game(size: handFrame, seed: 1)
        while dropping.stage != .ready { dropping.step(tick, world: handWorld()) }
        dropping.setPick(.paper)
        play(&dropping) { frame in frame % 5 < 2 ? [] : [self.scissors] }
        XCTAssertEqual(dropping.yours, .scissors)
        XCTAssertEqual(dropping.outcome, .win)
    }

    func testAHandThatChangesToTheAnswerDuringShootIsRead() {
        // The fist from the countdown becomes paper in the first moments after SHOOT: the paper is the answer.
        var game = Game(size: handFrame, seed: 1)
        while game.stage != .ready { game.step(tick, world: handWorld()) }
        game.setPick(.rock)
        play(&game, counting: [rock]) { frame in [frame < 6 ? self.rock : self.paper] }
        XCTAssertEqual(game.yours, .paper)
    }

    func testTheFistFromTheCountdownIsNotTheAnswer() {
        // A fist for the first few frames after SHOOT, which is still the pump from the countdown, and then nothing.
        var game = Game(size: handFrame, seed: 1)
        while game.stage != .ready { game.step(tick, world: handWorld()) }
        play(&game, counting: [rock]) { frame in frame < 3 ? [self.rock] : [] }
        XCTAssertEqual(game.outcome, .unread)
    }

    func testTooFewGoodFramesIsNotEnough() {
        var game = Game(size: handFrame, seed: 1)
        while game.stage != .ready { game.step(tick, world: handWorld()) }
        play(&game) { frame in frame >= 10 && frame < 13 ? [self.rock] : [] }
        XCTAssertEqual(game.outcome, .unread, "three frames of a fist in nearly a second")
    }

    func testTwoHandsMustAgree() {
        var game = Game(size: handFrame, seed: 1)
        while game.stage != .ready { game.step(tick, world: handWorld()) }
        play(&game) { _ in [self.rock, TestHands.make(.open, palmAt: CGPoint(x: 900, y: 300), id: 2)] }
        XCTAssertEqual(game.outcome, .unread, "a fist in one hand and a flat palm in the other is not an answer")

        var both = Game(size: handFrame, seed: 1)
        while both.stage != .ready { both.step(tick, world: handWorld()) }
        both.setPick(.paper)
        play(&both) { _ in [self.scissors, TestHands.make(.peace, palmAt: CGPoint(x: 900, y: 300), id: 2)] }
        XCTAssertEqual(both.yours, .scissors)

        var oneClear = Game(size: handFrame, seed: 1)
        while oneClear.stage != .ready { oneClear.step(tick, world: handWorld()) }
        play(&oneClear) { _ in [self.rock, HandFixtures.hand(.point, at: CGPoint(x: 900, y: 300), id: 2)] }
        XCTAssertEqual(oneClear.yours, .rock, "a hand that is not any of the three does not spoil the other")
    }

    func testTheComputerCannotSeeYourHandBeforeShoot() {
        // What you show before SHOOT, however clearly, is ignored: with an empty hand at SHOOT nothing was seen.
        var game = Game(size: handFrame, seed: 1)
        while game.stage != .ready { game.step(tick, world: handWorld()) }
        play(&game, counting: [paper]) { _ in [] }
        XCTAssertEqual(game.outcome, .unread)
        XCTAssertEqual(game.yours, nil)
    }

    func testTheComputersMovesDoNotDependOnYourHand() {
        func picks(showing: Game.Move?, seed: UInt64) -> [Game.Move] {
            var game = Game(size: handFrame, seed: seed)
            var out: [Game.Move] = []
            var lastStage = Game.Stage.reveal
            for _ in 0..<(30 * 160) where !game.isOver {
                game.step(tick, world: handWorld(showing.map { [hand(for: $0)] } ?? []))
                if game.stage == .ready && lastStage != .ready { out.append(game.pick) }
                lastStage = game.stage
            }
            return out
        }
        for seed in [1, 2, 3] as [UInt64] {
            let none = picks(showing: nil, seed: seed), fist = picks(showing: .rock, seed: seed)
            let flat = picks(showing: .paper, seed: seed), vee = picks(showing: .scissors, seed: seed)
            let n = min(none.count, fist.count, flat.count, vee.count)
            XCTAssertGreaterThanOrEqual(n, 3)
            XCTAssertEqual(Array(none.prefix(n)), Array(fist.prefix(n)), "seed \(seed)")
            XCTAssertEqual(Array(none.prefix(n)), Array(flat.prefix(n)), "seed \(seed)")
            XCTAssertEqual(Array(none.prefix(n)), Array(vee.prefix(n)), "seed \(seed)")
        }
    }

    func testTheComputerPlaysAllThreeMovesAboutEvenly() {
        var counts = [Game.Move: Int]()
        for seed in 1...300 as ClosedRange<UInt64> { counts[Game(size: handFrame, seed: seed).pick, default: 0] += 1 }
        for move in Game.Move.allCases { XCTAssertTrue((70...130).contains(counts[move] ?? 0), "\(move): \(counts[move] ?? 0)") }
    }

    func testTheMatchEndsAfterFiveRounds() {
        var game = Game(size: handFrame, seed: 2)
        // Win, win, lose, win, lose: five decided rounds, three wins.
        let plan: [(pick: Game.Move, show: Game.Move)] = [(.rock, .paper), (.rock, .paper), (.paper, .rock), (.rock, .paper), (.paper, .rock)]
        for (i, step) in plan.enumerated() {
            XCTAssertFalse(game.isOver, "round \(i + 1)")
            round(&game, pick: step.pick, show: step.show)
            XCTAssertEqual(game.round, i + 1)
        }
        XCTAssertEqual(game.wins, 3)
        XCTAssertEqual(game.losses, 2)
        XCTAssertFalse(game.isOver, "the last result is shown before the game ends")
        while !game.isOver { game.step(tick, world: handWorld()) }
        XCTAssertEqual(game.score, 3)
    }

    func testThreeLossesEndItEarly() {
        var game = Game(size: handFrame, seed: 2)
        round(&game, pick: .rock, show: .paper)
        for _ in 0..<3 { round(&game, pick: .rock, show: .scissors) }
        XCTAssertEqual(game.losses, 3)
        XCTAssertFalse(game.isOver)
        while !game.isOver { game.step(tick, world: handWorld()) }
        XCTAssertEqual(game.score, 1)
        XCTAssertEqual(game.round, 4)
    }

    func testDrawsAndMissedReadsDoNotUseUpRounds() {
        var game = Game(size: handFrame, seed: 3)
        for _ in 0..<4 { round(&game, pick: .paper, show: .paper) }
        round(&game, pick: .paper, show: nil)
        XCTAssertEqual(game.round, 0)
        XCTAssertFalse(game.isOver)
        XCTAssertEqual(game.summary, "Round 1/5 · ❤️❤️❤️")
    }

    func testTheSummaryShowsRoundAndLives() {
        var game = Game(size: handFrame, seed: 3)
        round(&game, pick: .rock, show: .scissors)
        XCTAssertEqual(game.summary, "Round 2/5 · ❤️❤️🖤")
    }

    func testSameSeedSameGame() {
        func run() -> [Int] {
            var game = Game(size: handFrame, seed: 77)
            var trace: [Int] = []
            for i in 0..<400 {
                game.step(tick, world: handWorld([i % 7 < 4 ? self.paper : self.scissors]))
                trace.append(game.pick.rawValue * 10 + game.score)
            }
            return trace
        }
        XCTAssertEqual(run(), run())
    }

    func testNoHandsEverAndHugeStepsDoNotBreakIt() {
        var game = Game(size: handFrame, seed: 5)
        for _ in 0..<(30 * 90) { game.step(tick, world: handWorld()) }
        game.step(100, world: handWorld())
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.wins, 0)
    }

    func testTheWaitingScreenAsksForAHand() {
        XCTAssertEqual(Game.presenceHint, "Hold up your hand to play")
    }
}

// MARK: - Palm Pong

final class HandGamePalmPongTests: XCTestCase {
    typealias Game = PalmPongGame

    /// An open hand whose palm is at the given height, a bit in from the left.
    private func palm(y: Double, x: Double = 400, id: Int = 1) -> HandState { TestHands.make(.open, palmAt: CGPoint(x: x, y: y), id: id) }

    /// The height a palm has to be at for the paddle to settle at `y`.
    private func palmHeight(forPaddleAt y: Double) -> Double { 360 + (y - 360) / 1.25 }

    private func run(_ game: inout Game, seconds: Double, hands: [HandState]) {
        for _ in 0..<Int(seconds * 30) { game.step(tick, world: handWorld(hands)) }
    }

    func testThePaddleFollowsThePalmUpAndDown() {
        var game = Game(size: handFrame, seed: 1)
        run(&game, seconds: 1, hands: [palm(y: 560)])
        XCTAssertEqual(game.playerY, game.target, accuracy: 3)
        XCTAssertGreaterThan(game.playerY, 560, "the paddle follows, stretched a little so the edges are in reach")
        run(&game, seconds: 1, hands: [palm(y: 250)])
        XCTAssertLessThan(game.playerY, 250)
        run(&game, seconds: 1, hands: [palm(y: 0)])
        XCTAssertEqual(game.playerY, game.playerHalf, accuracy: 1, "and never leaves the picture")
        run(&game, seconds: 1, hands: [palm(y: 720)])
        XCTAssertEqual(game.playerY, 720 - game.playerHalf, accuracy: 1)
    }

    func testAJumpingHandMakesThePaddleSlideNotTeleport() {
        var game = Game(size: handFrame, seed: 1)
        run(&game, seconds: 1, hands: [palm(y: 150)])
        let before = game.playerY
        game.step(tick, world: handWorld([palm(y: 600)]))
        XCTAssertLessThanOrEqual(game.playerY - before, Game.paddleSpeed * tick + 0.01)
        XCTAssertLessThan(game.playerY, game.target - 100, "it has not arrived yet")
        run(&game, seconds: 0.6, hands: [palm(y: 600)])
        XCTAssertEqual(game.playerY, game.target, accuracy: 4, "but it does get there")
    }

    func testTheLeftMostHandSteers() {
        var game = Game(size: handFrame, seed: 1)
        let leftLow = palm(y: 200, x: 300, id: 1), rightHigh = palm(y: 600, x: 900, id: 2)
        run(&game, seconds: 1, hands: [rightHigh, leftLow])
        XCTAssertEqual(game.controllingHand, 1)
        XCTAssertLessThan(game.playerY, 250, "listening to the low hand on the left, whatever order they come in")
        var swapped = Game(size: handFrame, seed: 1)
        run(&swapped, seconds: 1, hands: [leftLow, rightHigh])
        XCTAssertEqual(swapped.playerY, game.playerY, accuracy: 0.5)
    }

    func testTheHandInChargeIsNotSwappedOnATinyDifference() {
        var game = Game(size: handFrame, seed: 1)
        run(&game, seconds: 0.5, hands: [palm(y: 200, x: 300, id: 1)])
        XCTAssertEqual(game.controllingHand, 1)
        // A second hand turns up a little to the left: hand 1 stays in charge until the other is clearly further left.
        run(&game, seconds: 0.5, hands: [palm(y: 200, x: 300, id: 1), palm(y: 600, x: 270, id: 2)])
        XCTAssertEqual(game.controllingHand, 1)
        run(&game, seconds: 0.5, hands: [palm(y: 200, x: 300, id: 1), palm(y: 600, x: 150, id: 2)])
        XCTAssertEqual(game.controllingHand, 2)
        run(&game, seconds: 0.5, hands: [palm(y: 200, x: 300, id: 1)])
        XCTAssertEqual(game.controllingHand, 1, "and when it goes, the other takes over")
    }

    func testWhenTheHandVanishesThePaddleStaysPut() {
        var game = Game(size: handFrame, seed: 1)
        run(&game, seconds: 1, hands: [palm(y: 560)])
        let there = game.playerY
        run(&game, seconds: 0.3, hands: [])
        XCTAssertFalse(game.handLost, "a moment's drop-out is not noticed")
        run(&game, seconds: 2, hands: [])
        XCTAssertEqual(game.playerY, there, accuracy: 0.01)
        XCTAssertTrue(game.handLost)
        run(&game, seconds: 1, hands: [palm(y: 200)])
        XCTAssertFalse(game.handLost)
        XCTAssertLessThan(game.playerY, there, "and it picks up again when the hand returns")
    }

    func testTheBallBouncesOffThePaddleAndScores() {
        var game = Game(size: handFrame, seed: 1)
        run(&game, seconds: 1, hands: [palm(y: palmHeight(forPaddleAt: 360))])
        game.place(ball: SIMD2(300, game.playerY), velocity: SIMD2(-600, 0))
        let speedBefore = simd_length(game.velocity)
        run(&game, seconds: 0.5, hands: [palm(y: palmHeight(forPaddleAt: 360))])
        XCTAssertEqual(game.returns, 1)
        XCTAssertEqual(game.score, 1)
        XCTAssertEqual(game.lives, 3)
        XCTAssertGreaterThan(game.velocity.x, 0, "back toward the computer")
        XCTAssertGreaterThan(simd_length(game.velocity), speedBefore, "a little faster")
        XCTAssertEqual(game.rally, 1)
    }

    func testTheEdgeOfThePaddleSendsTheBallSteeply() {
        var up = Game(size: handFrame, seed: 1), down = Game(size: handFrame, seed: 1)
        let hand = [palm(y: palmHeight(forPaddleAt: 360))]
        run(&up, seconds: 1, hands: hand)
        run(&down, seconds: 1, hands: hand)
        up.place(ball: SIMD2(300, up.playerY + up.playerHalf * 0.8), velocity: SIMD2(-600, 0))
        down.place(ball: SIMD2(300, down.playerY - down.playerHalf * 0.8), velocity: SIMD2(-600, 0))
        run(&up, seconds: 0.5, hands: hand)
        run(&down, seconds: 0.5, hands: hand)
        XCTAssertGreaterThan(up.velocity.y, 150, "hit with the top, it goes up")
        XCTAssertLessThan(down.velocity.y, -150, "hit with the bottom, it goes down")
    }

    func testMissingCostsALifeAndTheBallIsServedAgain() {
        var game = Game(size: handFrame, seed: 1)
        let hand = [palm(y: palmHeight(forPaddleAt: 600))]
        run(&game, seconds: 1, hands: hand)
        game.place(ball: SIMD2(300, 100), velocity: SIMD2(-700, 0))
        run(&game, seconds: 0.6, hands: hand)
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(game.returns, 0)
        XCTAssertGreaterThan(game.serving, 0, "a pause before the next ball")
        XCTAssertEqual(game.velocity, .zero)
        run(&game, seconds: 2, hands: hand)
        XCTAssertEqual(game.serving, 0)
        XCTAssertLessThan(game.velocity.x, 0, "and it comes toward you")
        XCTAssertEqual(game.summary, "❤️❤️🖤")
    }

    func testThreeMissesEndTheGame() {
        var game = Game(size: handFrame, seed: 4)
        let hand = [palm(y: palmHeight(forPaddleAt: 650))]
        var guardCount = 0
        while !game.isOver && guardCount < 30 * 120 {
            if game.serving <= 0 && game.velocity.x < 0 && game.ball.y > 500 { game.place(ball: SIMD2(game.ball.x, 80), velocity: game.velocity) }
            game.step(tick, world: handWorld(hand))
            guardCount += 1
        }
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.lives, 0)
        let score = game.score
        game.step(tick, world: handWorld(hand))
        XCTAssertEqual(game.score, score)
    }

    func testNoOneThereLosesEverythingEventually() {
        var game = Game(size: handFrame, seed: 5)
        run(&game, seconds: 240, hands: [])
        XCTAssertTrue(game.isOver, "a paddle left in the middle catches some, but not every ball")
    }

    func testTheBallStaysOnTheCourtAndSpeedsUpAsTheRallyGoes() {
        var game = Game(size: handFrame, seed: 6)
        var speeds: [Double] = []
        var lastRally = 0
        for _ in 0..<(30 * 40) {
            // A player who always has the paddle under the ball.
            let hands = [palm(y: palmHeight(forPaddleAt: game.ball.y))]
            game.step(tick, world: handWorld(hands))
            XCTAssertGreaterThanOrEqual(game.ball.y, 0)
            XCTAssertLessThanOrEqual(game.ball.y, 720)
            if game.rally > lastRally { speeds.append(simd_length(game.velocity)) }
            lastRally = game.rally
        }
        XCTAssertGreaterThan(game.returns, 4)
        XCTAssertGreaterThan(speeds.count, 6)
        XCTAssertGreaterThan(speeds[5], speeds[0] + 100, "each hit adds speed")
        XCTAssertLessThanOrEqual(speeds.max() ?? 0, Game.topSpeed + 1)
    }

    func testTheComputerCanBeBeaten() {
        // A player who keeps the ball in play and sends it to the corners by catching it on the edge of the paddle.
        var beaten = 0
        for seed in [1, 2, 3, 4, 5] as [UInt64] {
            var game = Game(size: handFrame, seed: seed)
            var side = 1.0
            for _ in 0..<(30 * 90) where !game.isOver {
                let aimAt = game.ball.y + side * game.playerHalf * 0.75
                game.step(tick, world: handWorld([palm(y: palmHeight(forPaddleAt: aimAt))]))
                if game.velocity.x > 0 { side = game.ball.y > 360 ? 1 : -1 }
            }
            beaten += game.rallyWins
        }
        XCTAssertGreaterThan(beaten, 0, "the computer misses sometimes")
    }

    func testTheComputerIsLimitedInSpeedAndReactionBeforeAnythingElse() {
        var game = Game(size: handFrame, seed: 1)
        game.place(computerAt: 100)
        let before = game.computerY
        game.place(ball: SIMD2(640, 650), velocity: SIMD2(900, 0))
        game.step(0.1, world: handWorld())
        XCTAssertLessThanOrEqual(abs(game.computerY - before), game.computerSpeed * 0.1 + 0.01)
        XCTAssertLessThan(game.computerSpeed, Game.topSpeed * 0.5, "slower than a steep fast ball")
    }

    func testTheComputerReturnsAnEasyBall() {
        var game = Game(size: handFrame, seed: 1)
        game.place(computerAt: 360)
        game.place(ball: SIMD2(1100, 360), velocity: SIMD2(500, 0))
        game.step(0.4, world: handWorld())
        XCTAssertLessThan(game.velocity.x, 0, "back toward you")
        XCTAssertEqual(game.rallyWins, 0)
    }

    func testTheComputerMissingScoresARallyWin() {
        var game = Game(size: handFrame, seed: 1)
        game.place(computerAt: 100)
        game.place(ball: SIMD2(1100, 650), velocity: SIMD2(800, 0))
        run(&game, seconds: 0.5, hands: [palm(y: 360)])
        XCTAssertEqual(game.rallyWins, 1)
        XCTAssertEqual(game.score, 5)
        XCTAssertEqual(game.lives, 3)
        XCTAssertGreaterThan(game.serving, 0)
    }

    func testSameSeedSameHandsSamePlay() {
        func trace() -> [Double] {
            var game = Game(size: handFrame, seed: 31)
            var out: [Double] = []
            for i in 0..<600 {
                game.step(tick, world: handWorld([palm(y: 360 + 200 * sin(Double(i) / 20))]))
                out.append(game.ball.x + game.ball.y + game.computerY)
            }
            return out
        }
        XCTAssertEqual(trace(), trace())
    }

    func testAHugeStepDoesNotBreakIt() {
        var game = Game(size: handFrame, seed: 1)
        game.place(ball: SIMD2(300, 360), velocity: SIMD2(-900, 400))
        game.step(30, world: handWorld([palm(y: 360)]))
        XCTAssertTrue(game.ball.y >= 0 && game.ball.y <= 720)
        XCTAssertGreaterThanOrEqual(game.lives, 0)
    }

    func testTheWaitingScreenAsksForAHand() {
        XCTAssertEqual(Game.presenceHint, "Hold up your hand to play")
    }
}

// MARK: - As lenses

final class HandGameLensTests: XCTestCase {
    private let h = LensHarness()

    /// Draws the joints of the hands on top of a picture, so the pictures from these tests show where the hands were.
    private func withHands(_ image: CIImage, _ hands: [HandState]) -> CIImage {
        guard !hands.isEmpty, let marks = h.services.overlay({ ctx in
            for hand in hands {
                ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0.7, alpha: 0.9))
                ctx.setLineWidth(10)
                ctx.setLineCap(.round)
                for finger in Finger.allCases {
                    ctx.move(to: hand[.wrist])
                    ctx.addLine(to: hand[finger.knuckle])
                    ctx.addLine(to: hand[finger.middleJoint])
                    ctx.addLine(to: hand[finger.tip])
                }
                ctx.strokePath()
                for joint in hand.joints { ctx.fillCircle(center: joint, radius: 8, color: CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)) }
            }
        }) else { return image }
        return marks.composited(over: image).cropped(to: image.extent)
    }

    private struct Run<G: HandGameScreens> {
        let lens: HandGameLens<G>
        let base: LensInput
        var time = 0.0
        var last: CIImage

        init(_ lens: HandGameLens<G>, base: LensInput) {
            self.lens = lens
            self.base = base
            last = base.composed
        }

        mutating func play(_ seconds: Double, hands: (Double) -> [HandState], harness: LensHarness) {
            let end = time + seconds
            while time < end {
                last = lens.render(harness.at(base, time: time, hands: hands(time)))
                time += tick
            }
        }
    }

    private func steady(_ hands: [HandState]) -> (Double) -> [HandState] { { _ in hands } }

    func testTheGamesAreInTheCatalogAsHandGames() {
        for (id, name) in [("whack-a-mole", "Whack-a-Mole"), ("rock-paper-scissors", "Rock Paper Scissors"), ("palm-pong", "Palm Pong")] {
            guard let info = LensCatalog.info(for: id) else { XCTFail("missing \(id)"); continue }
            XCTAssertEqual(info.name, name)
            XCTAssertEqual(info.category, .games)
            XCTAssertTrue(info.needsHands)
            XCTAssertFalse(info.needsFace)
            XCTAssertTrue(info.scored)
            XCTAssertEqual(info.glyph.count, 1, "one emoji")
            XCTAssertFalse(info.blurb.isEmpty)
            let lens = info.make()
            XCTAssertTrue(lens.needs.contains(.hands))
            XCTAssertFalse(lens.needs.contains(.matte))
        }
        XCTAssertEqual(HandGames.all.count, 3)
    }

    private func checkLifecycle<G: HandGameScreens>(_ type: G.Type, id: String, file: StaticString = #filePath, line: UInt = #line) {
        let lens = HandGameLens<G>(id: id, needs: [.hands], store: MemoryScoreStore())
        var run = Run(lens, base: h.input())
        let hand = TestHands.make(.open, palmAt: CGPoint(x: 400, y: 330))

        run.play(1.2, hands: steady([]), harness: h)
        XCTAssertEqual(lens.phase, .waiting, "no hand, no game", file: file, line: line)
        XCTAssertEqual(lens.status?.title, "Hold up your hand to play", file: file, line: line)
        XCTAssertEqual(run.last.extent, run.base.rect, file: file, line: line)

        run.play(0.8, hands: steady([hand]), harness: h)
        guard case .countdown = lens.phase else { return XCTFail("a hand starts the countdown, got \(lens.phase)", file: file, line: line) }
        run.play(HandGameLens<G>.countdownSeconds + 0.3, hands: steady([hand]), harness: h)
        XCTAssertEqual(lens.phase, .playing, file: file, line: line)
        XCTAssertEqual(run.last.extent, run.base.rect, file: file, line: line)

        // Hands gone: it keeps drawing, then waits for you.
        run.play(0.8, hands: steady([]), harness: h)
        XCTAssertEqual(lens.phase, .playing, file: file, line: line)
        run.play(HandGameLens<G>.absenceGrace + 1.5, hands: steady([]), harness: h)
        XCTAssertEqual(lens.phase, .playing, "still waiting for you", file: file, line: line)
        let paused = lens.game.summary
        run.play(1, hands: steady([]), harness: h)
        XCTAssertEqual(lens.game.summary, paused, "the clock stops while you are away", file: file, line: line)
        run.play(0.5, hands: steady([hand]), harness: h)
        XCTAssertEqual(run.last.extent, run.base.rect, file: file, line: line)
    }

    func testEachGameWaitsCountsDownPlaysAndPausesWithoutHands() {
        checkLifecycle(WhackAMoleGame.self, id: "test.whack")
        checkLifecycle(RockPaperScissorsGame.self, id: "test.rps")
        checkLifecycle(PalmPongGame.self, id: "test.pong")
    }

    func testEachGameRendersOverAPersonWithAndWithoutHandsAndWithoutAMatte() {
        for info in HandGames.all {
            for background in [true, false] {
                let lens = info.make()
                lens.restart()
                var out: CIImage?
                for scene in [SyntheticScene(), SyntheticScene(center: CGPoint(x: 300, y: 300), scale: 0.6)] {
                    let base = h.input(scene, background: background, wantsGrid: false)
                    for i in 0..<(30 * 5) {
                        let hands = i % 40 < 20 ? [TestHands.make(i % 80 < 40 ? .open : .fist, palmAt: CGPoint(x: 300 + Double(i % 60) * 10, y: 300))] : []
                        out = lens.render(h.at(base, time: Double(i) / 30, hands: hands))
                    }
                }
                XCTAssertEqual(out?.extent, SyntheticScene.size.asRect, "\(info.id) background \(background)")
            }
        }
    }

    func testStatusLinesAreShortAndFriendly() {
        for info in HandGames.all {
            let lens = info.make()
            lens.restart()
            let base = h.input()
            _ = lens.render(base)
            XCTAssertNotNil(lens.status)
            XCTAssertLessThan(lens.status?.title.count ?? 99, 40)
            XCTAssertTrue(info.blurb.count < 90, info.blurb)
        }
    }

    func testEachGameCostsLittleToDraw() {
        let base = h.input()
        for (index, info) in HandGames.all.enumerated() {
            let lens = info.make()
            lens.restart()
            let hands = [TestHands.make(.open, palmAt: CGPoint(x: 400, y: 330)), TestHands.make(.point, palmAt: CGPoint(x: 800, y: 280), id: 2)]
            for i in 0..<(30 * 8) { _ = lens.render(h.at(base, time: Double(i) / 30, hands: hands)) }
            // Making and rendering one frame with this lens, as the median of many (the machine may be busy with other work).
            let cost = HandGameCost.median(of: lens, base: h.at(base, time: 0, hands: hands), harness: h)
            XCTAssertLessThan(cost, 12, "\(info.id) #\(index): \(cost)")
        }
    }

    // MARK: Pictures

    /// A game that is already some way in, for a picture.
    private func picture<G: HandGameScreens>(_ type: G.Type, id: String, name: String, hands: [HandState],
                                  scene: SyntheticScene = SyntheticScene(center: CGPoint(x: 640, y: 440)),
                                  make: @escaping (CGSize, UInt64) -> G, over: Bool = false) throws {
        let lens = HandGameLens<G>(id: id, needs: [.hands], store: MemoryScoreStore(), make: make)
        var run = Run(lens, base: h.input(scene, wantsGrid: false))
        run.play(0.6, hands: steady([]), harness: h)
        Output.save(withHands(run.last, []), as: "\(name)-waiting.png")
        lens.restart()
        run.play(1.0, hands: steady(hands), harness: h)
        Output.save(withHands(run.last, hands), as: "\(name)-countdown.png")
        run.play(HandGameLens<G>.countdownSeconds, hands: steady(hands), harness: h)
        run.play(0.2, hands: steady(hands), harness: h)
        Output.save(withHands(run.last, hands), as: "\(name)-playing.png")
        if over {
            run.play(1.0, hands: steady(hands), harness: h)
            Output.save(withHands(run.last, hands), as: "\(name)-over.png")
        }
    }

    func testPictureOfWhackAMole() throws {
        let hands = [TestHands.pointing(tipAt: CGPoint(x: 420, y: 235), id: 1), TestHands.make(.open, palmAt: CGPoint(x: 930, y: 190), id: 2)]
        try picture(WhackAMoleGame.self, id: "pic.whack", name: "whack", hands: hands, make: { size, seed in
            var game = WhackAMoleGame(size: size, seed: 4)
            var bot = MoleBot()
            for _ in 0..<(30 * 13) { game.step(tick, world: handWorld(bot.hands(for: game))) }
            return game
        }, over: false)
    }

    func testPictureOfWhackAMoleGameOver() throws {
        try picture(WhackAMoleGame.self, id: "pic.whack2", name: "whack-end", hands: [TestHands.make(.open, palmAt: CGPoint(x: 600, y: 300))], make: { size, seed in
            var game = WhackAMoleGame(size: size, seed: 4)
            var bot = MoleBot()
            for _ in 0..<(30 * 45 - 8) { game.step(tick, world: handWorld(bot.hands(for: game))) }
            return game
        }, over: true)
    }

    func testPictureOfWhackedMoles() throws {
        var game = WhackAMoleGame(size: handFrame, seed: 5)
        game.pauseSpawns()
        for hole in [0, 2, 3, 5, 7, 8] { game.place([0, 2, 7, 8].contains(hole) ? (hole == 2 ? .golden : .mole) : hole == 3 ? .bunny : .bomb, hole: hole) }
        let hands = { (i: Int) -> [HandState] in
            [TestHands.pointing(tipAt: CGPoint(x: 330 + Double(i) * 55, y: 380), id: 1), TestHands.make(.open, palmAt: CGPoint(x: 1000 - Double(i) * 50, y: 395), id: 2)]
        }
        var frame = 0
        for hole in [2, 0, 3, 5] {
            game.whackMole(inHole: hole)
            for _ in 0..<3 { game.step(tick, world: handWorld(hands(frame))); frame += 1 }
        }
        let base = h.input(SyntheticScene(center: CGPoint(x: 640, y: 440)), wantsGrid: false)
        let layer = try XCTUnwrap(h.services.overlay { game.draw(in: $0, time: 1.3) })
        Output.save(withHands(layer.composited(over: base.composed).cropped(to: base.rect), hands(frame)), as: "whack-squash.png")
        XCTAssertGreaterThanOrEqual(game.whacks, 2)
        XCTAssertEqual(game.bunniesHit, 1)
        XCTAssertEqual(game.bombsHit, 1)
    }

    func testPictureOfRockPaperScissors() throws {
        let fist = TestHands.make(.fist, palmAt: CGPoint(x: 640, y: 250), size: 110)
        try picture(RockPaperScissorsGame.self, id: "pic.rps", name: "rps", hands: [fist], make: { size, seed in
            RockPaperScissorsGame(size: size, seed: seed)
        })
    }

    func testPicturesOfEachRockPaperScissorsStage() throws {
        let lens = HandGameLens<RockPaperScissorsGame>(id: "pic.rps2", needs: [.hands], store: MemoryScoreStore(), make: { size, seed in
            var game = RockPaperScissorsGame(size: size, seed: seed)
            game.setPick(.scissors)
            return game
        })
        let hand = TestHands.make(.open, palmAt: CGPoint(x: 640, y: 250), size: 110)
        let fist = TestHands.make(.fist, palmAt: CGPoint(x: 640, y: 250), size: 110)
        var run = Run(lens, base: h.input(SyntheticScene(center: CGPoint(x: 640, y: 440)), wantsGrid: false))
        lens.restart()
        run.play(HandGameLens<RockPaperScissorsGame>.countdownSeconds + 0.1, hands: steady([fist]), harness: h)
        run.play(RockPaperScissorsGame.readyTime - 0.2, hands: steady([fist]), harness: h)
        Output.save(withHands(run.last, [fist]), as: "rps-ready.png")
        run.play(0.5, hands: steady([fist]), harness: h)
        Output.save(withHands(run.last, [fist]), as: "rps-rock.png")
        run.play(0.65, hands: steady([fist]), harness: h)
        Output.save(withHands(run.last, [fist]), as: "rps-paper.png")
        run.play(0.65, hands: steady([fist]), harness: h)
        Output.save(withHands(run.last, [fist]), as: "rps-scissors.png")
        run.play(0.55, hands: steady([hand]), harness: h)
        Output.save(withHands(run.last, [hand]), as: "rps-shoot.png")
        run.play(0.8, hands: steady([hand]), harness: h)
        Output.save(withHands(run.last, [hand]), as: "rps-lose.png")
        XCTAssertEqual(lens.game.outcome, .lose)
        run.play(2.0, hands: steady([hand]), harness: h)
        // Next round, and this time nothing readable.
        let shrug = HandFixtures.hand(.point, at: CGPoint(x: 640, y: 150), size: 110)
        run.play(RockPaperScissorsGame.readyTime + 3 * RockPaperScissorsGame.beatTime + RockPaperScissorsGame.readTime + 0.3, hands: steady([shrug]), harness: h)
        Output.save(withHands(run.last, [shrug]), as: "rps-unread.png")
        XCTAssertEqual(lens.game.outcome, .unread)
    }

    func testPictureOfRockPaperScissorsGameOver() throws {
        let hand = TestHands.make(.open, palmAt: CGPoint(x: 640, y: 250), size: 110)
        try picture(RockPaperScissorsGame.self, id: "pic.rps3", name: "rps-end", hands: [hand], make: { size, seed in
            var game = RockPaperScissorsGame(size: size, seed: seed)
            var wonRounds = 0
            while !game.finished && wonRounds < 40 {
                game.setPick(.rock)
                var guardCount = 0
                while game.stage != .reveal && guardCount < 600 { game.step(tick, world: handWorld([hand])); guardCount += 1 }
                while game.stage == .reveal && !game.finished && guardCount < 1200 { game.step(tick, world: handWorld([hand])); guardCount += 1 }
                wonRounds += 1
            }
            return game
        }, over: true)
    }

    func testPictureOfPalmPong() throws {
        let hand = TestHands.make(.open, palmAt: CGPoint(x: 330, y: 420), size: 120)
        try picture(PalmPongGame.self, id: "pic.pong", name: "pong", hands: [hand], make: { size, seed in
            var game = PalmPongGame(size: size, seed: seed)
            // A good player, a few seconds in: a rally under way and the ball mid-flight.
            var n = 0
            while n < 30 * 40 && !(game.rally >= 3 && game.ball.x > 500 && game.ball.x < 800 && game.velocity.x > 0 && game.ball.y < 300) {
                game.step(tick, world: handWorld([TestHands.make(.open, palmAt: CGPoint(x: 330, y: 360 + (game.ball.y - 360) / 1.25), size: 120)]))
                n += 1
            }
            return game
        })
    }

    func testPictureOfPalmPongGameOver() throws {
        let hand = TestHands.make(.open, palmAt: CGPoint(x: 330, y: 560), size: 120)
        try picture(PalmPongGame.self, id: "pic.pong2", name: "pong-end", hands: [hand], make: { size, seed in
            var game = PalmPongGame(size: size, seed: seed)
            var n = 0
            while !game.isOver && n < 30 * 200 {
                // Play well for a while, then stop caring.
                let y = game.returns < 6 ? game.ball.y : 700.0
                game.step(tick, world: handWorld([TestHands.make(.open, palmAt: CGPoint(x: 330, y: 360 + (y - 360) / 1.25), size: 120)]))
                n += 1
            }
            return game
        }, over: true)
    }
}

private extension CGSize {
    var asRect: CGRect { CGRect(origin: .zero, size: self) }
}
