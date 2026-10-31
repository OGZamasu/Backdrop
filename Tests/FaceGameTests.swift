import CoreImage
import simd
import XCTest

private let frame = CGSize(width: 1280, height: 720)

private func faceWorld(_ face: FaceState?) -> GameWorld { GameWorld(size: frame, matte: nil, motion: nil, face: face) }

/// The synthetic person's face with the readings the test cares about.
private func restingFace(blink: Double = 0, brow: Double = 0) -> FaceState {
    var scene = SyntheticScene()
    scene.blink = blink
    scene.browRaise = brow
    return scene.face()
}

/// A face whose nose is at `point`, however far away it looks.
private func face(nose point: CGPoint, scale: Double = 1) -> FaceState {
    let origin = SyntheticScene(center: .zero, scale: scale).face().nose
    return SyntheticScene(center: CGPoint(x: point.x - origin.x, y: point.y - origin.y), scale: scale).face()
}

// MARK: - The switch behind blinks and jumps

final class FaceGameTriggerTests: XCTestCase {
    func testItComesOnAtTheThresholdAndStaysOnAcrossTheBand() {
        var t = FaceGameTrigger(on: 0.6, off: 0.3)
        t.update(0.5, dt: 0.1)
        XCTAssertFalse(t.isOn)
        t.update(0.6, dt: 0.1)
        XCTAssertTrue(t.isOn)
        XCTAssertTrue(t.justTurnedOn)
        t.update(0.4, dt: 0.1)
        XCTAssertTrue(t.isOn, "between the two lines it holds")
        XCTAssertFalse(t.justTurnedOn)
        t.update(0.29, dt: 0.1)
        XCTAssertFalse(t.isOn)
    }

    func testAShortDipDoesNotLetGo() {
        var t = FaceGameTrigger(on: 0.6, off: 0.3, offDelay: 0.07)
        t.update(0.9, dt: 0.02)
        for _ in 0..<3 { t.update(0.1, dt: 0.02) }
        XCTAssertTrue(t.isOn, "60 ms under the line is not long enough")
        t.update(0.9, dt: 0.02)
        for _ in 0..<3 { t.update(0.1, dt: 0.02) }
        XCTAssertTrue(t.isOn, "and coming back up starts the count again")
        for _ in 0..<2 { t.update(0.1, dt: 0.02) }
        XCTAssertFalse(t.isOn)
    }

    func testItCountsHowLongItHasBeenOn() {
        var t = FaceGameTrigger(on: 0.5, off: 0.2)
        t.update(1, dt: 0.04)
        XCTAssertEqual(t.onFor, 0.04, accuracy: 1e-9)
        t.update(0.8, dt: 0.04)
        XCTAssertEqual(t.onFor, 0.08, accuracy: 1e-9)
        t.update(0, dt: 0.04)
        XCTAssertEqual(t.onFor, 0)
    }
}

// MARK: - Staring Contest

final class FaceGameStaringContestTests: XCTestCase {
    private let dt = 1.0 / 30

    private func play(_ game: inout StaringContestGame, seconds: Double, blink: Double = 0, step: Double = 1.0 / 30) {
        for _ in 0..<Int((seconds / step).rounded()) { game.step(step, world: faceWorld(restingFace(blink: blink))) }
    }

    private func feed(_ game: inout StaringContestGame, _ readings: [Double]) {
        for reading in readings { game.step(dt, world: faceWorld(restingFace(blink: reading))) }
    }

    func testTheScoreIsTenthsOfASecondWithYourEyesOpen() {
        var game = StaringContestGame(size: frame, seed: 1)
        play(&game, seconds: 5)
        XCTAssertLessThanOrEqual(abs(game.score - 50), 1)
        XCTAssertFalse(game.isOver)
        XCTAssertEqual(game.summary, "5.0 / 30 s")
    }

    func testABlinkEndsTheRoundWithTheTimeSoFar() {
        var game = StaringContestGame(size: frame, seed: 2)
        play(&game, seconds: 3)
        let before = game.score
        play(&game, seconds: 0.2, blink: 1)
        XCTAssertTrue(game.blinked)
        XCTAssertTrue(game.isOver)
        XCTAssertFalse(game.won)
        XCTAssertLessThanOrEqual(game.score - before, 1, "the clock stops the moment it happens")
        let final = game.score
        play(&game, seconds: 2)
        XCTAssertEqual(game.score, final, "and stays stopped")
    }

    func testOneNoisyFrameIsNotABlink() {
        var game = StaringContestGame(size: frame, seed: 3)
        play(&game, seconds: 2)
        feed(&game, [1.0, 0, 0, 0])
        XCTAssertFalse(game.isOver)
        // A glitchy tracker: a spike every other frame, never two in a row.
        feed(&game, Array(repeating: [1.0, 0.0], count: 45).flatMap { $0 })
        XCTAssertFalse(game.isOver, "spikes with open eyes between them are not blinks")
    }

    func testASquintWhileLaughingIsNotABlink() {
        var game = StaringContestGame(size: frame, seed: 4)
        play(&game, seconds: 6, blink: 0.45)
        XCTAssertFalse(game.isOver, "eyes narrowed to a squint are still open")
        // A squint that wobbles up and down but never gets to a real blink.
        let wobble = (0..<240).map { 0.25 + 0.3 * (0.5 + 0.5 * sin(Double($0) / 3)) }
        feed(&game, wobble)
        XCTAssertFalse(game.isOver)
    }

    func testOnceClosedItTakesRealOpeningToResetTheCount() {
        // Two frames above the line with a half-open frame between still add up to a blink...
        var game = StaringContestGame(size: frame, seed: 5)
        feed(&game, [0.7, 0.5, 0.5])
        XCTAssertTrue(game.blinked, "a lid that only half opens is still a blink")
        // ...but opening properly in between does not.
        var other = StaringContestGame(size: frame, seed: 5)
        feed(&other, [0.7, 0.2, 0.7, 0.2, 0.7, 0.2])
        XCTAssertFalse(other.blinked)
    }

    func testTwoFramesOfShutEyesAreABlinkAtThirtyFramesASecond() {
        var game = StaringContestGame(size: frame, seed: 6)
        feed(&game, [0, 0, 1.0])
        XCTAssertFalse(game.blinked, "one frame is not enough")
        feed(&game, [1.0])
        XCTAssertTrue(game.blinked)
    }

    func testTheBlinkRuleDoesNotDependOnTheFrameRate() {
        var game = StaringContestGame(size: frame, seed: 7)
        for _ in 0..<2 { game.step(1.0 / 60, world: faceWorld(restingFace(blink: 1))) }
        XCTAssertFalse(game.blinked, "33 ms of closed eyes at 60 fps is a flicker")
        for _ in 0..<3 { game.step(1.0 / 60, world: faceWorld(restingFace(blink: 1))) }
        XCTAssertTrue(game.blinked)
    }

    func testSomeoneWhoAlwaysSquintsStillLosesToARealBlink() {
        var game = StaringContestGame(size: frame, seed: 8)
        play(&game, seconds: 10, blink: 0.5)
        feed(&game, [0.68, 0.68, 0.68])
        XCTAssertFalse(game.isOver, "after ten seconds of squinting, a reading of 0.68 is just a harder squint")
        feed(&game, [1, 1, 1])
        XCTAssertTrue(game.blinked)
    }

    func testThirtySecondsWithOpenEyesWins() {
        var game = StaringContestGame(size: frame, seed: 9)
        play(&game, seconds: 29)
        XCTAssertFalse(game.isOver)
        play(&game, seconds: 3)
        XCTAssertTrue(game.won)
        XCTAssertTrue(game.isOver)
        XCTAssertFalse(game.blinked)
        XCTAssertEqual(game.score, 300)
        XCTAssertEqual(game.elapsed, StaringContestGame.winSeconds)
        play(&game, seconds: 2, blink: 1)
        XCTAssertEqual(game.score, 300, "a win stays a win")
    }

    func testLosingTheFaceFreezesTheClock() {
        var game = StaringContestGame(size: frame, seed: 10)
        play(&game, seconds: 3)
        let (elapsed, intruders) = (game.elapsed, game.intruders)
        for _ in 0..<90 { game.step(dt, world: faceWorld(nil)) }
        XCTAssertEqual(game.elapsed, elapsed)
        XCTAssertEqual(game.intruders, intruders, "and the show waits too")
        XCTAssertFalse(game.isOver, "a missing face is not a blink")
        play(&game, seconds: 1)
        XCTAssertEqual(game.elapsed, elapsed + 1, accuracy: 0.05)
    }

    func testAHugeStepDoesNotSkipAhead() {
        var game = StaringContestGame(size: frame, seed: 11)
        game.step(30, world: faceWorld(restingFace()))
        XCTAssertLessThanOrEqual(game.elapsed, 0.1 + 1e-9)
        XCTAssertFalse(game.isOver)
    }

    func testTheSameSeedPlaysTheSameAndAnotherDoesNot() {
        var a = StaringContestGame(size: frame, seed: 42), b = StaringContestGame(size: frame, seed: 42), c = StaringContestGame(size: frame, seed: 43)
        play(&a, seconds: 14)
        play(&b, seconds: 14)
        play(&c, seconds: 14)
        XCTAssertEqual(a.intruders, b.intruders)
        XCTAssertEqual(a.taunt, b.taunt)
        XCTAssertEqual(a.flashCount, b.flashCount)
        XCTAssertNotEqual(a.intruders, c.intruders)
    }

    func testThePressureBuildsAsTheRoundGoesOn() throws {
        var game = StaringContestGame(size: frame, seed: 3)
        var tensions: [Double] = [], crowd: [Int] = []
        for _ in 0..<29 {
            var busiest = 0
            for _ in 0..<30 { game.step(dt, world: faceWorld(restingFace())); busiest = max(busiest, game.intruders.count) }
            tensions.append(game.tension)
            crowd.append(busiest)
        }
        XCTAssertEqual(tensions, tensions.sorted(), "the meter only rises")
        XCTAssertLessThan(try XCTUnwrap(tensions.first), 0.1)
        XCTAssertGreaterThan(try XCTUnwrap(tensions.last), 0.9)
        XCTAssertGreaterThan(try XCTUnwrap(crowd[22...].max()), try XCTUnwrap(crowd[..<6].max()), "more silly faces at the end than at the start")
        XCTAssertLessThanOrEqual(try XCTUnwrap(crowd.max()), StaringContestGame.maxIntruders)
    }

    func testSillyFacesCloseInAndPopAtTheFrame() {
        var game = StaringContestGame(size: frame, seed: 12)
        var previous: [StaringContestGame.Intruder] = []
        var popped = 0
        for _ in 0..<(30 * 25) {
            game.step(dt, world: faceWorld(restingFace()))
            for now in game.intruders {
                XCTAssertGreaterThan(now.distance, StaringContestGame.intruderStop)
                XCTAssertLessThanOrEqual(now.distance, StaringContestGame.intruderStart)
                if let before = previous.first(where: { $0.phase == now.phase }) {
                    XCTAssertLessThan(now.distance, before.distance, "they only ever come closer")
                }
            }
            for old in previous where !game.intruders.contains(where: { $0.phase == old.phase }) {
                popped += 1
                XCTAssertLessThanOrEqual(old.distance - old.speed * dt, StaringContestGame.intruderStop + 1e-6, "one only goes when it reaches the frame")
            }
            previous = game.intruders
        }
        XCTAssertGreaterThan(popped, 5)
    }

    func testTheTauntsKeepChangingAndTheFakeCountdownRuns() {
        var game = StaringContestGame(size: frame, seed: 13)
        var seen = Set<String>(), labels: [String] = []
        for _ in 0..<(30 * 29) {
            game.step(dt, world: faceWorld(restingFace()))
            seen.insert(game.taunt)
            if let label = game.fakeCountdown, labels.last != label { labels.append(label) }
        }
        XCTAssertGreaterThanOrEqual(seen.count, 6)
        XCTAssertTrue(seen.isSubset(of: Set(StaringContestGame.taunts)))
        XCTAssertTrue(labels.starts(with: ["3", "2", "1", "BLINK!", "just kidding"]), "got \(labels)")
    }

    func testTheLightsNeverFlashMoreThanTheSafeRate() {
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertGreaterThanOrEqual(StaringContestGame.flashInterval(tension: t), 1 / StaringContestGame.maxFlashesPerSecond - 1e-9)
        }
        var game = StaringContestGame(size: frame, seed: 14)
        var counts: [Int] = []
        for _ in 0..<(30 * 29) {
            game.step(dt, world: faceWorld(restingFace()))
            counts.append(game.flashCount)
        }
        XCTAssertGreaterThan(game.flashCount, 8, "there are flashes")
        for i in 30..<counts.count { XCTAssertLessThanOrEqual(counts[i] - counts[i - 30], 3, "no second has more than three flashes") }
    }
}

// MARK: - Brow Runner

/// A player who takes off a beat before each obstacle and keeps their brows up until they are past it.
private func browBot(_ game: BrowRunnerGame) -> Double {
    let x = BrowRunnerGame.playerX
    guard let next = game.obstacles.first(where: { $0.x + $0.width + 20 > x - BrowRunnerGame.bodyHalfWidth }) else { return 0 }
    let front = next.x - (x + 14), rear = next.x + next.width - (x - 14)
    let spanSeconds = (next.width + 28) / game.speed
    let leadSeconds = max(0.12, (0.85 - spanSeconds) / 2)
    return front / game.speed <= leadSeconds && rear > 0 ? 0.9 : 0
}

final class FaceGameBrowRunnerTests: XCTestCase {
    private let dt = 1.0 / 120

    private func world(brow: Double?) -> GameWorld { faceWorld(brow.map { restingFace(brow: $0) }) }

    /// A runner on an empty road.
    private func quiet(seed: UInt64 = 1) -> BrowRunnerGame {
        var game = BrowRunnerGame(size: frame, seed: seed)
        game.place([])
        return game
    }

    private func obstacle(_ kind: BrowRunnerGame.Kind, x: Double, width: Double, height: Double) -> BrowRunnerGame.Obstacle {
        BrowRunnerGame.Obstacle(kind: kind, x: x, width: width, height: height, variant: 0)
    }

    private func apex(holdingFor seconds: Double) -> Double {
        var game = quiet()
        var best = 0.0
        let held = Int((seconds / dt).rounded())
        for i in 0..<Int(2 / dt) {
            game.step(dt, world: world(brow: i < held ? 0.9 : 0))
            best = max(best, game.height)
        }
        return best
    }

    func testRaisingTheBrowsJumpsAndTheRunnerComesBackDown() {
        var game = quiet()
        game.step(dt, world: world(brow: 0))
        XCTAssertTrue(game.grounded)
        XCTAssertEqual(game.jumps, 0)
        game.step(dt, world: world(brow: 0.9))
        XCTAssertEqual(game.jumps, 1)
        XCTAssertFalse(game.grounded)
        for _ in 0..<12 { game.step(dt, world: world(brow: 0.9)) }
        XCTAssertGreaterThan(game.height, 20)
        for _ in 0..<240 { game.step(dt, world: world(brow: 0)) }
        XCTAssertTrue(game.grounded)
        XCTAssertEqual(game.height, 0, accuracy: 1e-9)
        XCTAssertEqual(game.jumps, 1)
    }

    func testHoldingJumpsHigherThanATap() {
        let tap = apex(holdingFor: 0.01), medium = apex(holdingFor: 0.25), full = apex(holdingFor: 1.0)
        XCTAssertGreaterThan(tap, 85, "even a tap clears the small stuff")
        XCTAssertLessThan(tap, 145)
        XCTAssertGreaterThan(medium, tap + 15)
        XCTAssertGreaterThan(full, medium + 15)
        XCTAssertGreaterThan(full, 180, "a held jump clears a stack of two crates")
        XCTAssertLessThan(full, 260)
    }

    func testAFlutteringBrowDoesNotDoubleJump() {
        // Held up but jittering from well above the line to well below it and back, every 50 ms.
        var game = quiet()
        for i in 0..<Int(3 / dt) { game.step(dt, world: world(brow: (i / 6) % 2 == 0 ? 0.7 : 0.25)) }
        XCTAssertEqual(game.jumps, 1)

        // Noise that hovers around the line without ever dropping below the release level.
        var noisy = quiet(seed: 2)
        var rng = SplitMix64(seed: 5)
        for _ in 0..<Int(3 / dt) { noisy.step(dt, world: world(brow: 0.62 + (Double.random(in: 0..<1, using: &rng) - 0.5) * 0.5)) }
        XCTAssertEqual(noisy.jumps, 1, "once up, it stays up until the brows really come down")
    }

    func testNoiseBelowTheLineNeverJumps() {
        var game = quiet()
        var rng = SplitMix64(seed: 6)
        for _ in 0..<Int(5 / dt) { game.step(dt, world: world(brow: 0.3 + (Double.random(in: 0..<1, using: &rng) - 0.5) * 0.5)) }
        XCTAssertEqual(game.jumps, 0)
    }

    func testBringingTheBrowsDownAndUpAgainJumpsAgain() {
        var game = quiet()
        for _ in 0..<Int(0.4 / dt) { game.step(dt, world: world(brow: 0.9)) }
        for _ in 0..<Int(1.2 / dt) { game.step(dt, world: world(brow: 0)) }
        XCTAssertTrue(game.grounded)
        for _ in 0..<Int(0.2 / dt) { game.step(dt, world: world(brow: 0.9)) }
        XCTAssertEqual(game.jumps, 2)
    }

    func testAJumpStillWorksJustAfterRunningOffACrate() {
        func attempt(pressing delay: Double) -> Int {
            var game = BrowRunnerGame(size: frame, seed: 1)
            game.place([obstacle(.crate, x: BrowRunnerGame.playerX - 30, width: 72, height: 144)])
            game.lift(to: 144)
            game.step(dt, world: world(brow: 0))
            XCTAssertTrue(game.grounded, "standing on the crate")
            var guardCount = 0
            while game.grounded, guardCount < 600 {
                game.step(dt, world: world(brow: 0))
                guardCount += 1
            }
            XCTAssertFalse(game.grounded, "it ran off the end")
            for _ in 0..<Int((delay / dt).rounded()) { game.step(dt, world: world(brow: 0)) }
            for _ in 0..<4 { game.step(dt, world: world(brow: 0.9)) }
            return game.jumps
        }
        XCTAssertEqual(attempt(pressing: 0.05), 1, "inside the coyote window")
        XCTAssertEqual(attempt(pressing: 0.12), 0, "and not long after")
    }

    func testPressingJustBeforeLandingStillJumps() {
        // Find which frame a plain hop lands on.
        var probe = quiet()
        var landing = 0
        for i in 0..<Int(2 / dt) {
            probe.step(dt, world: world(brow: i < 3 ? 0.9 : 0))
            if i > 20, probe.grounded { landing = i; break }
        }
        XCTAssertGreaterThan(landing, 30)

        func hop(pressingBeforeLanding lead: Double) -> Int {
            var game = quiet()
            let pressAt = landing - Int((lead / dt).rounded())
            for i in 0..<(landing + Int(0.3 / dt)) {
                let brow: Double = i < 3 || (i >= pressAt && i < pressAt + 3) ? 0.9 : 0
                game.step(dt, world: world(brow: brow))
            }
            return game.jumps
        }
        XCTAssertEqual(hop(pressingBeforeLanding: 0.10), 2, "a press a moment early is remembered")
        XCTAssertEqual(hop(pressingBeforeLanding: 0.30), 1, "but not one from long before")
    }

    func testRunningIntoACactusEndsTheRun() {
        var game = quiet()
        game.place([obstacle(.cactus, x: 700, width: 46, height: 70)])
        var steps = 0
        while !game.isOver, steps < Int(4 / dt) { game.step(dt, world: world(brow: 0)); steps += 1 }
        XCTAssertTrue(game.isOver)
        XCTAssertGreaterThan(game.score, 0)
        let score = game.score
        game.step(0.5, world: world(brow: 0.9))
        XCTAssertEqual(game.score, score, "nothing moves after a crash")
    }

    func testJumpingInTimeClearsACactusAPuddleAndACrateStack() {
        for (kind, width, height) in [(BrowRunnerGame.Kind.cactus, 46.0, 78.0), (.puddle, 150.0, 16.0), (.puddle, 210.0, 16.0), (.crate, 72.0, 144.0), (.cactus, 190.0, 84.0)] {
            var game = quiet()
            game.place([obstacle(kind, x: 900, width: width, height: height)])
            if kind == .puddle, width > 200 { game.lift(to: 0) }
            for _ in 0..<Int(6 / dt) { game.step(dt, world: world(brow: browBot(game))) }
            XCTAssertFalse(game.isOver, "\(kind) \(width)x\(height) should be jumpable")
            XCTAssertGreaterThan(game.jumps, 0)
        }
    }

    func testPuddlesOnlyCatchRunnersOnTheGround() {
        var game = quiet()
        game.place([obstacle(.puddle, x: BrowRunnerGame.playerX - 60, width: 150, height: 16)])
        game.lift(to: 40)
        game.step(dt, world: world(brow: 0))
        XCTAssertFalse(game.isOver, "in the air over it")
        var grounded = quiet()
        grounded.place([obstacle(.puddle, x: BrowRunnerGame.playerX - 60, width: 150, height: 16)])
        grounded.step(dt, world: world(brow: 0))
        XCTAssertTrue(grounded.isOver, "splash")
    }

    func testACrateCanBeStoodOnButNotRunInto() {
        var onTop = quiet()
        onTop.place([obstacle(.crate, x: BrowRunnerGame.playerX - 100, width: 216, height: 72)])
        onTop.lift(to: 120)
        for _ in 0..<Int(0.3 / dt) { onTop.step(dt, world: world(brow: 0)) }
        XCTAssertFalse(onTop.isOver)
        XCTAssertEqual(onTop.height, 72, accuracy: 1e-9, "landed on the top")
        XCTAssertTrue(onTop.grounded)

        var nearMiss = quiet()
        nearMiss.place([obstacle(.crate, x: BrowRunnerGame.playerX - 30, width: 72, height: 72)])
        nearMiss.lift(to: 64)
        nearMiss.step(dt, world: world(brow: 0))
        XCTAssertFalse(nearMiss.isOver, "a hop that only just misses the top still gets up")
        XCTAssertEqual(nearMiss.height, 72, accuracy: 1e-9)

        var corner = quiet()
        corner.place([obstacle(.crate, x: BrowRunnerGame.playerX - 30, width: 72, height: 72)])
        corner.lift(to: 40)
        corner.step(dt, world: world(brow: 0))
        XCTAssertFalse(corner.isOver, "catching the top corner with your feet climbs onto the crate")
        XCTAssertEqual(corner.height, 72, accuracy: 1e-9)

        var tooLow = quiet()
        tooLow.place([obstacle(.crate, x: BrowRunnerGame.playerX - 30, width: 72, height: 72)])
        tooLow.lift(to: 15)
        tooLow.step(dt, world: world(brow: 0))
        XCTAssertTrue(tooLow.isOver, "but lower down it is a wall")

        var head = quiet()
        head.place([obstacle(.crate, x: 700, width: 72, height: 72)])
        for _ in 0..<Int(4 / dt) where !head.isOver { head.step(dt, world: world(brow: 0)) }
        XCTAssertTrue(head.isOver, "the side of a crate is a wall")
    }

    func testItSpeedsUpAndTopsOut() {
        var game = quiet()
        XCTAssertEqual(game.speed, BrowRunnerGame.baseSpeed)
        var previous = game.speed
        for _ in 0..<(60 * 100) {
            game.step(1.0 / 60, world: world(brow: 0))
            XCTAssertGreaterThanOrEqual(game.speed, previous)
            previous = game.speed
        }
        XCTAssertEqual(game.speed, BrowRunnerGame.topSpeed)
        XCTAssertEqual(game.score, Int(game.distance / BrowRunnerGame.pixelsPerMeter))
    }

    func testObstaclesAreFairEnoughForAGoodPlayerToSurviveForAMinuteAndAHalf() {
        for seed in 1...5 as ClosedRange<UInt64> {
            var game = BrowRunnerGame(size: frame, seed: seed)
            for _ in 0..<(60 * 90) where !game.isOver { game.step(1.0 / 60, world: world(brow: browBot(game))) }
            XCTAssertFalse(game.isOver, "seed \(seed): crashed at \(game.score) m with \(game.obstacles.map { "\($0.kind) @\(Int($0.x))" })")
            XCTAssertGreaterThan(game.score, 500, "seed \(seed)")
            XCTAssertGreaterThan(game.jumps, 20)
        }
    }

    func testAHugeStepDoesNotSkipAcrossObstacles() {
        var game = BrowRunnerGame(size: frame, seed: 3)
        game.step(30, world: world(brow: 0))
        XCTAssertLessThanOrEqual(game.distance, BrowRunnerGame.baseSpeed * 0.1 * 1.05)
    }

    func testNothingHappensWithoutAFace() {
        var game = BrowRunnerGame(size: frame, seed: 4)
        for _ in 0..<120 { game.step(1.0 / 60, world: world(brow: nil)) }
        XCTAssertEqual(game.distance, 0)
        XCTAssertTrue(game.obstacles.isEmpty)
        XCTAssertFalse(game.isOver)
        game.step(1.0 / 60, world: world(brow: 0))
        XCTAssertGreaterThan(game.distance, 0, "and it carries on when the face is back")
    }

    func testTheSameSeedMakesTheSameRoad() {
        var a = BrowRunnerGame(size: frame, seed: 77), b = BrowRunnerGame(size: frame, seed: 77), c = BrowRunnerGame(size: frame, seed: 78)
        for _ in 0..<(60 * 30) {
            a.step(1.0 / 60, world: world(brow: browBot(a)))
            b.step(1.0 / 60, world: world(brow: browBot(b)))
            c.step(1.0 / 60, world: world(brow: browBot(c)))
        }
        XCTAssertEqual(a.obstacles, b.obstacles)
        XCTAssertEqual(a.distance, b.distance)
        XCTAssertEqual(a.jumps, b.jumps)
        XCTAssertNotEqual(a.obstacles, c.obstacles)
    }

    func testTheLightGoesFromDayToNightAndBack() {
        XCTAssertEqual(BrowRunnerScenery.daylight(meters: 0, cycleMeters: 400), 1, accuracy: 1e-9)
        XCTAssertEqual(BrowRunnerScenery.daylight(meters: 100, cycleMeters: 400), 0.5, accuracy: 1e-9)
        XCTAssertEqual(BrowRunnerScenery.daylight(meters: 200, cycleMeters: 400), 0, accuracy: 1e-9)
        XCTAssertEqual(BrowRunnerScenery.daylight(meters: 400, cycleMeters: 400), 1, accuracy: 1e-9)
    }
}

// MARK: - Face Snake

final class FaceGameSnakeTests: XCTestCase {
    private let dt = 1.0 / 60
    private let rest = CGPoint(x: 640, y: 400)

    private func steer(_ game: inout FaceSnakeGame, nose: CGPoint?, seconds: Double) {
        for _ in 0..<Int((seconds / dt).rounded()) { game.step(dt, world: faceWorld(nose.map { face(nose: $0) })) }
    }

    func testTheHeadSwimsAtASteadySpeed() {
        var game = FaceSnakeGame(size: frame, seed: 1)
        steer(&game, nose: rest, seconds: 0.5)
        var worst = 0.0, best = 1e9
        for _ in 0..<120 {
            let before = game.head
            game.step(dt, world: faceWorld(face(nose: rest)))
            let moved = simd_length(game.head - before)
            worst = max(worst, moved)
            best = min(best, moved)
        }
        XCTAssertEqual(worst, game.speed * dt, accuracy: 0.01)
        XCTAssertEqual(best, game.speed * dt, accuracy: 0.01, "it never speeds up or slows down on its own")
    }

    func testItTurnsNoFasterThanASnakeCanAndFollowsTheNose() {
        var game = FaceSnakeGame(size: frame, seed: 2)
        steer(&game, nose: rest, seconds: 0.3)
        // The nose goes hard to the left: the goal is far behind the head.
        var biggestTurn = 0.0
        var heading = game.heading
        for _ in 0..<Int(1.0 / dt) {
            game.step(dt, world: faceWorld(face(nose: CGPoint(x: rest.x - 200, y: rest.y))))
            biggestTurn = max(biggestTurn, abs(FaceSnakeGame.angleBetween(heading, game.heading)))
            heading = game.heading
        }
        XCTAssertLessThanOrEqual(biggestTurn, game.speed / FaceSnakeGame.turnRadius * dt + 1e-9)
        XCTAssertGreaterThan(biggestTurn, 0.8 * game.speed / FaceSnakeGame.turnRadius * dt, "and it does turn flat out")

        steer(&game, nose: CGPoint(x: rest.x - 200, y: rest.y), seconds: 5)
        var xs: [Double] = []
        for _ in 0..<120 {
            game.step(dt, world: faceWorld(face(nose: CGPoint(x: rest.x - 200, y: rest.y))))
            xs.append(game.head.x)
        }
        let average = xs.reduce(0, +) / Double(xs.count)
        XCTAssertLessThan(average, 450, "the head hangs around the left side while the nose is there, got \(average)")
        XCTAssertGreaterThan(game.aim.x, 0)
        XCTAssertLessThan(game.aim.x, 450)
    }

    func testASmallMovementOfTheHeadReachesFarAcrossThePicture() {
        // One eye-spacing of movement moves the goal the same amount whether the face is near or far.
        func offset(scale: Double) -> Double {
            var game = FaceSnakeGame(size: frame, seed: 3)
            let eye = 84 * scale
            for _ in 0..<30 { game.step(dt, world: faceWorld(face(nose: rest, scale: scale))) }
            for _ in 0..<120 { game.step(dt, world: faceWorld(face(nose: CGPoint(x: rest.x + eye, y: rest.y), scale: scale))) }
            return game.aim.x - frame.width / 2
        }
        let near = offset(scale: 1), far = offset(scale: 0.75)
        XCTAssertEqual(near, FaceSnakeGame.reachPerEyeSpacing, accuracy: 6)
        XCTAssertEqual(far, FaceSnakeGame.reachPerEyeSpacing, accuracy: 6)
    }

    func testTheGoalStaysInsideThePicture() {
        var game = FaceSnakeGame(size: frame, seed: 4)
        steer(&game, nose: rest, seconds: 0.2)
        steer(&game, nose: CGPoint(x: rest.x + 900, y: rest.y - 900), seconds: 2)
        XCTAssertLessThanOrEqual(game.aim.x, frame.width)
        XCTAssertGreaterThanOrEqual(game.aim.y, 0)
    }

    func testEatingFruitScoresGrowsTheSnakeAndSpeedsItUp() {
        var game = FaceSnakeGame(size: frame, seed: 5)
        steer(&game, nose: rest, seconds: 0.1)
        let length = game.body.count
        let speed = game.speed
        game.place(fruitAt: [CGPoint(x: game.head.x + 45 * cos(game.heading), y: game.head.y + 45 * sin(game.heading))])
        steer(&game, nose: rest, seconds: 0.05)
        XCTAssertEqual(game.score, 1)
        XCTAssertEqual(game.fruit.count, 1, "a new piece appears at once")
        steer(&game, nose: rest, seconds: 1)
        XCTAssertEqual(game.body.count, length + FaceSnakeGame.growth)
        XCTAssertGreaterThan(game.speed, speed, "a little quicker")
        XCTAssertLessThan(game.speed, speed + 10)
    }

    func testFruitOutOfReachIsLeftAlone() {
        var game = FaceSnakeGame(size: frame, seed: 6)
        game.place(fruitAt: [CGPoint(x: 100, y: 100)])
        steer(&game, nose: rest, seconds: 1)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.fruit.count, 1)
    }

    func testTheSpeedHasALimit() {
        var game = FaceSnakeGame(size: frame, seed: 7)
        steer(&game, nose: rest, seconds: 0.1)
        for _ in 0..<60 {
            game.place(fruitAt: [CGPoint(x: game.head.x, y: game.head.y)])
            game.step(dt, world: faceWorld(face(nose: rest)))
        }
        XCTAssertEqual(game.speed, FaceSnakeGame.topSpeed)
        XCTAssertEqual(game.score, 60)
    }

    func testBitingYourOwnTailEndsTheGame() {
        var game = FaceSnakeGame(size: frame, seed: 8)
        game.grow(by: 40)
        steer(&game, nose: rest, seconds: 0.2)
        XCTAssertFalse(game.isOver)
        steer(&game, nose: rest, seconds: 8)
        XCTAssertTrue(game.isOver, "circling in one place with a long body bites it")
        let head = game.head
        steer(&game, nose: CGPoint(x: 100, y: 100), seconds: 1)
        XCTAssertEqual(game.head, head, "and it stops")
    }

    func testTheNeckIsSafeInATightTurn() {
        var game = FaceSnakeGame(size: frame, seed: 9)
        steer(&game, nose: rest, seconds: 25)
        XCTAssertFalse(game.isOver, "circling in the tightest circle with a short snake is fine")
    }

    func testTheEdgesWrapAround() {
        var game = FaceSnakeGame(size: frame, seed: 10)
        game.place(head: CGPoint(x: 1265, y: 360), heading: 0)
        var jumped = false
        var previous = game.head.x
        for _ in 0..<30 {
            game.step(dt, world: faceWorld(face(nose: rest)))
            if abs(game.head.x - previous) > 600 { jumped = true }
            previous = game.head.x
            XCTAssertGreaterThanOrEqual(game.head.x, 0)
            XCTAssertLessThan(game.head.x, frame.width)
        }
        XCTAssertTrue(jumped, "it came back in on the other side")
        XCTAssertFalse(game.isOver)
        XCTAssertEqual(game.body.count, 6, "and it kept its body")
    }

    func testTheBodyFollowsTheHeadAlongItsPath() {
        var game = FaceSnakeGame(size: frame, seed: 11)
        steer(&game, nose: rest, seconds: 1)
        let spacing = FaceSnakeGame.segmentSpacing
        let points = [game.head] + game.body
        for (a, b) in zip(points, points.dropFirst()) { XCTAssertLessThanOrEqual(simd_length(a - b), spacing + 0.01) }
        XCTAssertEqual(game.body.count, FaceSnakeGame.startSegments)
    }

    func testNoFaceHoldsTheSnakeStill() {
        var game = FaceSnakeGame(size: frame, seed: 12)
        steer(&game, nose: rest, seconds: 1)
        let (head, elapsed) = (game.head, game.elapsed)
        steer(&game, nose: nil, seconds: 3)
        XCTAssertEqual(game.head, head)
        XCTAssertEqual(game.elapsed, elapsed)
        XCTAssertFalse(game.isOver)
    }

    func testAHugeStepDoesNotJumpTheHeadThroughTheBody() {
        var game = FaceSnakeGame(size: frame, seed: 13)
        steer(&game, nose: rest, seconds: 0.2)
        let before = game.head
        game.step(30, world: faceWorld(face(nose: rest)))
        XCTAssertLessThanOrEqual(simd_length(game.head - before), game.speed * 0.1 + 1)
    }

    func testFruitAppearsInTheOpenAndTheSameSeedPlaysTheSame() {
        var a = FaceSnakeGame(size: frame, seed: 21), b = FaceSnakeGame(size: frame, seed: 21), c = FaceSnakeGame(size: frame, seed: 22)
        for _ in 0..<(60 * 10) {
            a.step(dt, world: faceWorld(face(nose: rest)))
            b.step(dt, world: faceWorld(face(nose: rest)))
            c.step(dt, world: faceWorld(face(nose: rest)))
        }
        XCTAssertEqual(a.head, b.head)
        XCTAssertEqual(a.fruit, b.fruit)
        XCTAssertNotEqual(a.fruit, c.fruit)

        var game = FaceSnakeGame(size: frame, seed: 23)
        steer(&game, nose: rest, seconds: 0.1)
        for _ in 0..<25 {
            game.place(fruitAt: [CGPoint(x: game.head.x, y: game.head.y)])
            game.step(dt, world: faceWorld(face(nose: rest)))
            for piece in game.fruit {
                XCTAssertGreaterThanOrEqual(piece.position.x, 100)
                XCTAssertLessThanOrEqual(piece.position.x, frame.width - 100)
                XCTAssertLessThanOrEqual(piece.position.y, frame.height - 130)
                XCTAssertGreaterThan(simd_length(piece.position - game.head), 100, "never on top of the head")
                XCTAssertTrue(game.body.allSatisfy { simd_length(piece.position - $0) > 40 }, "or the body")
            }
        }
    }
}

// MARK: - The games as lenses

/// Runs a game as a lens over the synthetic room, with whatever face the test hands it at each moment.
private final class FaceGameDriver<G: FaceGame> {
    let harness = LensHarness()
    let lens: FaceGameLens<G>
    let base: LensInput
    private(set) var time = 0.0

    init(make: ((CGSize, UInt64) -> G)? = nil) {
        lens = FaceGameLens<G>(id: "test.\(G.title)", store: MemoryScoreStore(), make: make)
        base = harness.input(wantsGrid: false)
    }

    @discardableResult
    func run(_ seconds: Double, fps: Double = 30, face: (FaceGameLens<G>) -> FaceState?) -> CIImage {
        var out = base.composed
        for _ in 0..<Int((seconds * fps).rounded()) {
            let input = LensInput(time: time, dt: 1 / fps, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                                  composed: base.composed, matteGrid: nil, face: face(lens), services: base.services)
            out = lens.render(input)
            time += 1 / fps
        }
        return out
    }
}

final class FaceGameRenderTests: XCTestCase {
    private func check(_ image: CIImage, _ message: String) {
        XCTAssertEqual(image.extent.width, 1280, message)
        XCTAssertEqual(image.extent.height, 720, message)
    }

    func testStaringContestFromWaitingToWinning() {
        let d = FaceGameDriver<StaringContestGame>()
        let open = restingFace()
        var shot = d.run(0.2) { _ in open }
        Output.save(shot, as: "facegame-staring-1-waiting.png")
        XCTAssertEqual(d.lens.phase, .waiting)
        d.run(0.5) { _ in open }
        shot = d.run(0.8) { _ in open }
        Output.save(shot, as: "facegame-staring-2-countdown.png")
        guard case .countdown = d.lens.phase else { return XCTFail("expected the countdown, got \(d.lens.phase)") }

        d.run(2.4) { _ in open }
        shot = d.run(4) { _ in open }
        Output.save(shot, as: "facegame-staring-3-early.png")
        XCTAssertEqual(d.lens.phase, .playing)
        XCTAssertGreaterThan(d.lens.game.elapsed, 3)

        // A squint in the middle of it all.
        shot = d.run(0.5) { _ in restingFace(blink: 0.45) }
        Output.save(shot, as: "facegame-staring-3b-squint.png")
        XCTAssertEqual(d.lens.phase, .playing)

        for _ in 0..<150 where d.lens.game.fakeCountdown != "2" { d.run(0.1) { _ in open } }
        shot = d.run(0.1) { _ in open }
        Output.save(shot, as: "facegame-staring-3c-fake-countdown.png")
        XCTAssertNotNil(d.lens.game.fakeCountdown)

        shot = d.run(Double(max(1, 20 - Int(d.lens.game.elapsed - 5)))) { _ in open }
        Output.save(shot, as: "facegame-staring-4-late.png")
        XCTAssertGreaterThan(d.lens.game.tension, 0.7)

        shot = d.run(0.3) { _ in restingFace(blink: 1) }
        Output.save(shot, as: "facegame-staring-5-blinked.png")
        guard case .over = d.lens.phase else { return XCTFail("a blink should end the round, got \(d.lens.phase)") }
        XCTAssertTrue(d.lens.game.blinked)
        check(shot, "game over")
    }

    func testStaringContestWon() {
        let d = FaceGameDriver<StaringContestGame>()
        d.lens.restart()
        let open = restingFace()
        d.run(FaceGameLens<StaringContestGame>.countdownSeconds + 0.2) { _ in open }
        d.run(29) { _ in open }
        let shot = d.run(2.5) { _ in open }
        Output.save(shot, as: "facegame-staring-6-won.png")
        XCTAssertTrue(d.lens.game.won)
        XCTAssertEqual(d.lens.status?.title, "You win! 30.0 s")
    }

    func testBrowRunnerFromWaitingToCrashing() {
        let d = FaceGameDriver<BrowRunnerGame>()
        let rest = restingFace()
        var shot = d.run(0.2) { _ in rest }
        Output.save(shot, as: "facegame-runner-1-waiting.png")
        d.run(0.5) { _ in rest }
        shot = d.run(0.8) { _ in rest }
        Output.save(shot, as: "facegame-runner-2-countdown.png")
        guard case .countdown = d.lens.phase else { return XCTFail("expected the countdown, got \(d.lens.phase)") }

        d.run(2.4) { _ in rest }
        shot = d.run(2) { lens in restingFace(brow: browBot(lens.game)) }
        Output.save(shot, as: "facegame-runner-3-running.png")
        XCTAssertEqual(d.lens.phase, .playing)

        // Play on, as a good player, to see a jump and then the night.
        var sawJump: CIImage?
        var sawDusk = false
        for _ in 0..<(30 * 40) {
            let image = d.run(1.0 / 30) { lens in restingFace(brow: browBot(lens.game)) }
            if sawJump == nil, d.lens.game.height > 120 { sawJump = image; Output.save(image, as: "facegame-runner-4-jump.png") }
            if !sawDusk, d.lens.game.score >= 95 { sawDusk = true; Output.save(image, as: "facegame-runner-4b-dusk.png") }
            if d.lens.game.score >= 220 { break }
        }
        XCTAssertNotNil(sawJump)
        XCTAssertGreaterThanOrEqual(d.lens.game.score, 220, "the bot should get this far")
        Output.save(d.run(1.0 / 30) { lens in restingFace(brow: browBot(lens.game)) }, as: "facegame-runner-5-night.png")

        shot = d.run(0.1) { _ in rest }
        for _ in 0..<80 {
            if case .over = d.lens.phase { break }
            shot = d.run(0.1) { _ in rest }
        }
        shot = d.run(0.4) { _ in rest }
        Output.save(shot, as: "facegame-runner-6-crashed.png")
        guard case .over = d.lens.phase else { return XCTFail("expected a crash, got \(d.lens.phase)") }
        check(shot, "game over")
    }

    func testFaceSnakeFromWaitingToTheEnd() {
        let d = FaceGameDriver<FaceSnakeGame>()
        let rest = face(nose: CGPoint(x: 640, y: 400))
        var shot = d.run(0.2) { _ in rest }
        Output.save(shot, as: "facegame-snake-1-waiting.png")
        d.run(0.5) { _ in rest }
        shot = d.run(0.8) { _ in rest }
        Output.save(shot, as: "facegame-snake-2-countdown.png")
        d.run(2.4) { _ in rest }

        // An autopilot nose that heads for the nearest fruit.
        let gain = FaceSnakeGame.reachPerEyeSpacing / 84
        func pilot(_ lens: FaceGameLens<FaceSnakeGame>) -> FaceState {
            let game = lens.game
            guard game.elapsed > 0, let goal = game.fruit.min(by: { simd_length($0.position - game.head) < simd_length($1.position - game.head) })?.position else { return rest }
            return face(nose: CGPoint(x: 640 + (goal.x - 640) / gain, y: 400 + (goal.y - 360) / gain))
        }
        shot = d.run(1.5) { pilot($0) }
        Output.save(shot, as: "facegame-snake-3-early.png")
        for _ in 0..<(30 * 60) {
            shot = d.run(1.0 / 30) { pilot($0) }
            if d.lens.game.score >= 7 || d.lens.game.isOver { break }
        }
        Output.save(shot, as: "facegame-snake-4-long.png")
        XCTAssertGreaterThanOrEqual(d.lens.game.score, 4, "an autopilot that steers for the fruit eats some")
    }

    func testFaceSnakeGameOver() {
        let d = FaceGameDriver<FaceSnakeGame>(make: { size, seed in
            var game = FaceSnakeGame(size: size, seed: seed)
            game.grow(by: 34)
            return game
        })
        let rest = face(nose: CGPoint(x: 640, y: 400))
        d.lens.restart()
        d.run(FaceGameLens<FaceSnakeGame>.countdownSeconds + 0.5) { _ in rest }
        var shot = d.run(0.5) { _ in rest }
        for _ in 0..<100 {
            if case .over = d.lens.phase { break }
            shot = d.run(0.1) { _ in rest }
        }
        shot = d.run(0.3) { _ in rest }
        Output.save(shot, as: "facegame-snake-5-over.png")
        guard case .over = d.lens.phase else { return XCTFail("expected a bite, got \(d.lens.phase)") }
        check(shot, "game over")
    }

    func testFaceSnakeAcrossTheEdge() throws {
        let harness = LensHarness()
        let base = harness.input(wantsGrid: false)
        var game = FaceSnakeGame(size: frame, seed: 5)
        game.grow(by: 6)
        game.place(head: CGPoint(x: 1262, y: 300), heading: 0.2)
        for _ in 0..<12 { game.step(1.0 / 60, world: faceWorld(face(nose: CGPoint(x: 640, y: 400)))) }
        let layer = try XCTUnwrap(base.services.overlay { game.draw(in: $0, time: 1) })
        let shot = layer.composited(over: base.composed).cropped(to: base.rect)
        Output.save(shot, as: "facegame-snake-6-across-the-edge.png")
        XCTAssertFalse(game.isOver)
    }

    func testEveryGameRendersWithNoOneThereAndWhenTheFaceIsLost() {
        func exercise<G: FaceGame>(_ type: G.Type, face present: FaceState) {
            let d = FaceGameDriver<G>()
            check(d.run(1) { _ in nil }, "\(G.title): nobody there")
            XCTAssertEqual(d.lens.phase, .waiting, "\(G.title): an empty room doesn't start a game")
            d.run(0.7) { _ in present }
            d.run(FaceGameLens<G>.countdownSeconds + 0.3) { _ in present }
            XCTAssertEqual(d.lens.phase, .playing, G.title)
            d.run(1) { _ in present }
            // Lost for a moment: the game waits. Lost for long: the lens asks you to come back.
            check(d.run(0.5) { _ in nil }, "\(G.title): face lost briefly")
            let frozen = d.lens.game.summary
            check(d.run(2.5) { _ in nil }, "\(G.title): face lost for a while")
            XCTAssertEqual(d.lens.game.summary, frozen, "\(G.title): the game is paused while you're away")
            XCTAssertEqual(d.lens.phase, .playing, G.title)
            check(d.run(0.5) { _ in present }, "\(G.title): and back again")
        }
        exercise(StaringContestGame.self, face: restingFace())
        exercise(BrowRunnerGame.self, face: restingFace())
        exercise(FaceSnakeGame.self, face: face(nose: CGPoint(x: 640, y: 400)))
    }

    func testEveryGameRendersTiltedAndFarAway() {
        for scene in [SyntheticScene(center: CGPoint(x: 400, y: 380), scale: 0.5, roll: 0.5), SyntheticScene(center: CGPoint(x: 900, y: 450), scale: 1.6, roll: -0.4)] {
            let present = scene.face()
            func exercise<G: FaceGame>(_ type: G.Type) {
                let d = FaceGameDriver<G>()
                d.lens.restart()
                check(d.run(FaceGameLens<G>.countdownSeconds + 2) { _ in present }, "\(G.title)")
            }
            exercise(StaringContestGame.self)
            exercise(BrowRunnerGame.self)
            exercise(FaceSnakeGame.self)
        }
    }

    func testTheCatalogEntriesAreRegisteredAndMatchTheirLenses() throws {
        let ids = ["staring-contest", "brow-runner", "face-snake", "face-copycat", "face-space-blaster", "face-keepy-uppy", "face-tilt-racer", "face-bubble-gum"]
        for id in ids {
            let info = try XCTUnwrap(LensCatalog.info(for: id), id)
            XCTAssertEqual(info.category, .games)
            XCTAssertTrue(info.needsFace)
            XCTAssertTrue(info.scored)
            XCTAssertFalse(info.blurb.isEmpty)
            XCTAssertEqual(info.glyph.count, 1, "one emoji")
            XCTAssertEqual(info.make().needs, [.face])
            XCTAssertTrue(info.showsText, "the games put words on the picture")
        }
        XCTAssertEqual(FaceGames.all.map(\.id), ids)
    }
}
