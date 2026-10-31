import AppKit
import CoreImage
import simd
import XCTest

private let frame = CGSize(width: 1280, height: 720)

/// A solid rectangle that is the whole silhouette, or nothing.
private struct Everywhere: MatteQuery {
    func coverage(x: Double, y: Double) -> Double { 1 }
}

/// An open hand whose leading fingertip is exactly at `tip`, moving at `speed` pixels a second.
private func swordHand(tip: CGPoint, speed: CGVector = .zero, id: Int = 1) -> HandState {
    let base = HandFixtures.hand(.open, at: .zero, size: 100, id: id)
    return HandFixtures.moved(base, by: CGVector(dx: tip.x - base.leadTip.x, dy: tip.y - base.leadTip.y), velocity: speed, tipVelocity: speed)
}

final class FruitSlashGameTests: XCTestCase {
    private func world(_ hands: [HandState] = [], motion: MatteQuery? = nil) -> GameWorld {
        GameWorld(size: frame, matte: nil, motion: motion, face: nil, faceCrop: nil, hands: hands)
    }

    /// Steps once with a resting hand to set the blade down, then once with it moved fast to `to`.
    private func swing(_ game: inout FruitSlashGame, from: CGPoint, to: CGPoint, dt: Double = 1.0 / 30) {
        game.step(dt, world: world([swordHand(tip: from)]))
        let speed = CGVector(dx: (to.x - from.x) / dt, dy: (to.y - from.y) / dt)
        game.step(dt, world: world([swordHand(tip: to, speed: speed)]))
    }

    func testSwingingAHandThroughFruitSlicesItIntoTwoHalvesAndScores() {
        var game = FruitSlashGame(size: frame, seed: 1)
        game.setFruit([.fruit(0)], at: CGPoint(x: 640, y: 400))
        swing(&game, from: CGPoint(x: 520, y: 400), to: CGPoint(x: 760, y: 400))
        XCTAssertTrue(game.fruit.isEmpty, "it was cut")
        XCTAssertEqual(game.halves.count, 2, "into two halves")
        XCTAssertEqual(game.score, 1)
        XCTAssertEqual(game.sliced, 1)
        XCTAssertNotEqual(game.halves[0].side, game.halves[1].side)
        XCTAssertNotEqual(game.halves[0].velocity, game.halves[1].velocity, "that fly apart")
    }

    func testAHandResting_orCreepingSlowly_overFruitDoesNotCutIt() {
        var game = FruitSlashGame(size: frame, seed: 2)
        game.setFruit([.fruit(1)], at: CGPoint(x: 640, y: 400))
        for _ in 0..<30 { game.step(1.0 / 30, world: world([swordHand(tip: CGPoint(x: 640, y: 400))])) }
        XCTAssertEqual(game.sliced, 0)
        game.step(1.0 / 30, world: world([swordHand(tip: CGPoint(x: 646, y: 400), speed: CGVector(dx: 120, dy: 0))]))
        XCTAssertEqual(game.sliced, 0, "slow is not a slash")
    }

    func testABladeThatJumpedPastTheFruitBetweenTwoLooksStillCutsIt() {
        var game = FruitSlashGame(size: frame, seed: 3)
        game.setFruit([.fruit(2)], at: CGPoint(x: 640, y: 400))
        // 700 pixels in one step: the tip is nowhere near the fruit before or after, but its path went through.
        swing(&game, from: CGPoint(x: 300, y: 410), to: CGPoint(x: 1000, y: 410))
        XCTAssertEqual(game.sliced, 1)
    }

    func testAPathThatPassesBesideTheFruitMissesIt() {
        var game = FruitSlashGame(size: frame, seed: 4)
        game.setFruit([.fruit(2)], at: CGPoint(x: 640, y: 400), radius: 50)
        swing(&game, from: CGPoint(x: 300, y: 560), to: CGPoint(x: 1000, y: 560))
        XCTAssertEqual(game.sliced, 0)
    }

    func testBombsCostALifeAndBreakTheCombo() {
        var game = FruitSlashGame(size: frame, seed: 5)
        game.setFruit([.fruit(0), .fruit(1)], at: CGPoint(x: 400, y: 400))
        swing(&game, from: CGPoint(x: 300, y: 400), to: CGPoint(x: 500, y: 400))
        XCTAssertEqual(game.combo, 2)
        game.setFruit([.bomb], at: CGPoint(x: 800, y: 400))
        swing(&game, from: CGPoint(x: 700, y: 400), to: CGPoint(x: 900, y: 400))
        XCTAssertEqual(game.lives, FruitSlashGame.startingLives - 1)
        XCTAssertEqual(game.combo, 0)
        XCTAssertTrue(game.halves.count == 4, "a bomb leaves no halves")
    }

    func testSlicingSeveralInOneSwipeEarnsABonus() {
        var game = FruitSlashGame(size: frame, seed: 6)
        game.setFruit([.fruit(0), .fruit(3), .fruit(5)], at: CGPoint(x: 640, y: 400))
        swing(&game, from: CGPoint(x: 400, y: 400), to: CGPoint(x: 900, y: 400))
        XCTAssertEqual(game.sliced, 3)
        XCTAssertGreaterThan(game.score, 3, "three at once is worth more than three apart")
    }

    func testFruitThatFallsAwayIsAMissButABombThatFallsAwayIsFine() {
        var game = FruitSlashGame(size: frame, seed: 7)
        game.setFruit([], at: .zero)
        game.launch(.fruit(0), from: 640, apex: 300)
        game.launch(.bomb, from: 400, apex: 300)
        for _ in 0..<(30 * 3) { game.step(1.0 / 30, world: world()) }
        XCTAssertEqual(game.missed, 1, "the fruit")
        XCTAssertEqual(game.lives, FruitSlashGame.startingLives - 1, "and not the bomb")
    }

    func testFruitPeaksWhereItWasThrownTo() {
        var game = FruitSlashGame(size: frame, seed: 8)
        game.setFruit([], at: .zero)
        game.launch(.fruit(0), from: 640, apex: 520)
        var highest = 0.0
        for _ in 0..<(60 * 2) {
            game.step(1.0 / 60, world: world())
            if let f = game.fruit.first { highest = max(highest, f.position.y) }
        }
        XCTAssertEqual(highest, 520, accuracy: 30)
    }

    func testLosingTheLastLifeEndsTheGame() {
        var game = FruitSlashGame(size: frame, seed: 9)
        var steps = 0
        while !game.isOver && steps < 30 * 240 { game.step(1.0 / 30, world: world()); steps += 1 }
        XCTAssertTrue(game.isOver, "with nobody slicing, everything falls")
        XCTAssertEqual(game.lives, 0)
    }

    func testNoHandsMeansAStrongBodyMovementThroughFruitStillCuts() {
        var game = FruitSlashGame(size: frame, seed: 10)
        game.setFruit([.fruit(4)], at: CGPoint(x: 640, y: 400))
        game.step(1.0 / 30, world: world([], motion: Everywhere()))
        XCTAssertEqual(game.sliced, 1)
        game.setFruit([.fruit(4)], at: CGPoint(x: 640, y: 400))
        game.step(1.0 / 30, world: world([swordHand(tip: CGPoint(x: 100, y: 100))], motion: Everywhere()))
        XCTAssertEqual(game.sliced, 1, "but with a hand in view it is only the hand that cuts")
    }

    func testWavesGetBiggerAndSameSeedPlaysTheSame() {
        func play(_ seed: UInt64) -> [Double] {
            var game = FruitSlashGame(size: frame, seed: seed)
            for _ in 0..<(30 * 8) { game.step(1.0 / 30, world: world()) }
            return game.fruit.map(\.position.x)
        }
        XCTAssertEqual(play(11), play(11))
        var early = FruitSlashGame(size: frame, seed: 12)
        var seen = 0
        for _ in 0..<(30 * 4) { early.step(1.0 / 30, world: world()); seen = max(seen, early.fruit.count) }
        XCTAssertGreaterThan(seen, 0, "something flies within the first seconds")
    }

    func testItRunsAsALensAndDrawsAHandBlade() throws {
        let h = LensHarness()
        let lens = HandGameLens<FruitSlashGame>(id: "test.fruit-slash", needs: [.hands, .matte], store: MemoryScoreStore())
        let base = h.input(hands: [swordHand(tip: CGPoint(x: 400, y: 400))])
        var out = base.composed
        for i in 0..<140 {
            let tip = CGPoint(x: 300 + Double(i % 30) * 20, y: 300 + Double(i % 30) * 10)
            out = lens.render(h.at(base, time: Double(i) / 30, hands: [swordHand(tip: tip, speed: CGVector(dx: 600, dy: 300))]))
        }
        Output.save(out, as: "game-fruit-slash.png")
        XCTAssertEqual(out.extent, base.rect)
        XCTAssertEqual(lens.phase, .playing)
        XCTAssertEqual(lens.status?.title.hasPrefix("Score"), true)
    }
}

final class FingerGunTests: XCTestCase {
    func testOnlyAPointingHandIsAGun() {
        XCTAssertTrue(FingerGun.isAimed(HandFixtures.hand(.point)))
        XCTAssertTrue(FingerGun.isAimed(HandFixtures.hand(.gun)))
        XCTAssertFalse(FingerGun.isAimed(HandFixtures.hand(.open)))
        XCTAssertFalse(FingerGun.isAimed(HandFixtures.hand(.fist)))
        XCTAssertFalse(FingerGun.isAimed(HandFixtures.hand(.peace)))
    }

    func testTheCrosshairRunsPastTheTipAlongAFingerHeldAcrossButSitsOnTheTipWhenPointedAtTheCamera() {
        let across = HandFixtures.gun(from: CGPoint(x: 300, y: 300), toward: CGPoint(x: 900, y: 300), size: 100)
        let ahead = FingerGun.crosshair(across)
        XCTAssertGreaterThan(ahead.x, Double(across.indexTip.x) + 60, "out beyond the tip")
        XCTAssertEqual(ahead.y, Double(across.indexTip.y), accuracy: 15)

        // The same hand with its index finger foreshortened, as it looks pointed at the camera.
        var toward = across
        let knuckle = toward[.indexMCP]
        for joint in [HandJoint.indexPIP, .indexDIP, .indexTip] {
            toward.joints[joint.rawValue] = CGPoint(x: knuckle.x + 4, y: knuckle.y + 3)
        }
        let near = FingerGun.crosshair(toward)
        XCTAssertEqual(near.x, Double(toward.indexTip.x), accuracy: 12, "on the fingertip")
    }

    func testDroppingTheThumbFiresOnceAndWigglingItDoesNot() {
        var trigger = FingerGunTrigger()
        let up = HandFixtures.hand(.gun), down = HandFixtures.hand(.gunFired)
        var shots = 0
        for _ in 0..<5 { if trigger.update(up, dt: 1.0 / 30) { shots += 1 } }
        XCTAssertEqual(shots, 0, "thumb up: the hammer is cocked")
        for _ in 0..<5 { if trigger.update(down, dt: 1.0 / 30) { shots += 1 } }
        XCTAssertEqual(shots, 1, "thumb down: one shot, not one every frame")

        // A thumb that wobbles between the two thresholds, never all the way up or all the way down, fires nothing.
        var wobbly = FingerGunTrigger()
        let a = HandFixtures.hand(HandFixtures.Fingers(index: true, middle: false, ring: false, little: false, thumb: 0.62))
        let b = HandFixtures.hand(HandFixtures.Fingers(index: true, middle: false, ring: false, little: false, thumb: 0.76))
        for h in [a, b] { XCTAssertTrue(h.thumbOpen > FingerGunTrigger.thumbDown + 0.01 && h.thumbOpen < FingerGunTrigger.thumbUp - 0.01, "\(h.thumbOpen)") }
        for i in 0..<60 { XCTAssertFalse(wobbly.update(i % 2 == 0 ? a : b, dt: 1.0 / 30)) }
    }

    func testAThumbThatWasNeverUpCannotFire_andAnOldCockedThumbGoesStale() {
        var trigger = FingerGunTrigger()
        let down = HandFixtures.hand(.gunFired)
        for _ in 0..<10 { XCTAssertFalse(trigger.update(down, dt: 1.0 / 30)) }

        var stale = FingerGunTrigger()
        _ = stale.update(HandFixtures.hand(.gun), dt: 1.0 / 30)
        for _ in 0..<40 { _ = stale.update(HandFixtures.hand(.gun), dt: 0.0) }          // thumb stays up…
        var fired = false
        for _ in 0..<3 { fired = fired || stale.update(down, dt: 1.0) }                // …and drops a long time later
        XCTAssertFalse(fired, "a hammer drop has to follow the thumb being up closely")
    }

    func testAFlickOfTheFingerFiresButMovingTheWholeHandDoesNot() {
        var trigger = FingerGunTrigger()
        let steady = HandFixtures.hand(.point, size: 100)
        let sweeping = HandFixtures.moved(steady, by: .zero, velocity: CGVector(dx: 900, dy: 0), tipVelocity: CGVector(dx: 920, dy: 10))
        XCTAssertFalse(trigger.update(sweeping, dt: 1.0 / 30), "the hand and its tip move together")
        let flick = HandFixtures.moved(steady, by: .zero, velocity: CGVector(dx: 20, dy: 0), tipVelocity: CGVector(dx: 20, dy: 900))
        XCTAssertTrue(trigger.update(flick, dt: 1.0 / 30), "the tip moves and the palm doesn't")
        XCTAssertFalse(trigger.update(flick, dt: 1.0 / 30), "not again the very next frame")
    }
}

final class FingerGunsGameTests: XCTestCase {
    private func world(_ hands: [HandState]) -> GameWorld { GameWorld(size: frame, matte: nil, motion: nil, face: nil, faceCrop: nil, hands: hands) }

    /// A gun with its tip at `tip` pointing at the camera (foreshortened), so the crosshair sits on the tip.
    private func gunAt(_ tip: CGPoint, thumb: Double = 1, id: Int = 1) -> HandState {
        var h = HandFixtures.hand(HandFixtures.Fingers(index: true, middle: false, ring: false, little: false, thumb: thumb), size: 100, id: id)
        let knuckle = h[.indexMCP]
        for joint in [HandJoint.indexPIP, .indexDIP, .indexTip] { h.joints[joint.rawValue] = CGPoint(x: knuckle.x + 4, y: knuckle.y + 3) }
        let off = CGVector(dx: tip.x - h.indexTip.x, dy: tip.y - h.indexTip.y)
        return HandFixtures.moved(h, by: off)
    }

    func testShootingATargetScoresItsPoints() {
        var game = FingerGunsGame(size: frame, seed: 1)
        game.setTargets([.ufo], at: CGPoint(x: 600, y: 400))
        game.fire(from: SIMD2(300, 300), at: SIMD2(610, 395))
        XCTAssertEqual(game.score, 3)
        XCTAssertEqual(game.hits, 1)
        XCTAssertTrue(game.targets.isEmpty)
    }

    func testAMissResetsTheStreakAndTheStreakBuildsAMultiplier() {
        var game = FingerGunsGame(size: frame, seed: 2)
        for _ in 0..<3 {
            game.setTargets([.board], at: CGPoint(x: 500, y: 400))
            game.fire(from: SIMD2(300, 300), at: SIMD2(500, 400))
        }
        XCTAssertEqual(game.multiplier, 2, "three in a row")
        game.setTargets([.board], at: CGPoint(x: 500, y: 400))
        game.fire(from: SIMD2(300, 300), at: SIMD2(900, 600))
        XCTAssertEqual(game.multiplier, 1, "a miss ends it")
        XCTAssertEqual(game.shots, 4)
    }

    func testTheDecoyCostsPointsAndCannotGoBelowZero() {
        var game = FingerGunsGame(size: frame, seed: 3)
        game.setTargets([.bunny], at: CGPoint(x: 500, y: 400))
        game.fire(from: .zero, at: SIMD2(500, 400))
        XCTAssertEqual(game.score, 0, "never negative")
        game.setTargets([.star], at: CGPoint(x: 500, y: 400))
        game.fire(from: .zero, at: SIMD2(500, 400))
        game.setTargets([.bunny], at: CGPoint(x: 500, y: 400))
        game.fire(from: .zero, at: SIMD2(500, 400))
        XCTAssertEqual(game.score, 2, "5 for the star minus 3 for the bunny")
    }

    func testDroppingTheThumbWhileAimedAtATargetShootsIt() {
        var game = FingerGunsGame(size: frame, seed: 4)
        game.setTargets([.board], at: CGPoint(x: 700, y: 400))
        for _ in 0..<4 { game.step(1.0 / 30, world: world([gunAt(CGPoint(x: 700, y: 400), thumb: 1)])) }
        XCTAssertEqual(game.score, 0, "thumb up: aiming only")
        game.step(1.0 / 30, world: world([gunAt(CGPoint(x: 700, y: 400), thumb: 0)]))
        XCTAssertEqual(game.score, 1, "thumb down: bang")
    }

    func testHoldingYourAimLocksOnAndShootsEvenIfNoGestureIsEverRead() {
        var game = FingerGunsGame(size: frame, seed: 5)
        game.setTargets([.board], at: CGPoint(x: 700, y: 400))
        var steps = 0
        while game.score == 0 && steps < 60 { game.step(1.0 / 30, world: world([gunAt(CGPoint(x: 700, y: 400), thumb: 0)])); steps += 1 }
        XCTAssertEqual(game.score, 1)
        XCTAssertEqual(Double(steps) / 30, FingerGunsGame.lockSeconds, accuracy: 0.15)
    }

    func testLockOnNeverFiresAtTheDecoy_andResetsWhenYouLookAway() {
        var game = FingerGunsGame(size: frame, seed: 6)
        game.setTargets([.bunny], at: CGPoint(x: 700, y: 400))
        for _ in 0..<60 { game.step(1.0 / 30, world: world([gunAt(CGPoint(x: 700, y: 400), thumb: 0)])) }
        XCTAssertEqual(game.shots, 0)

        game.setTargets([.board], at: CGPoint(x: 700, y: 400))
        for _ in 0..<18 { game.step(1.0 / 30, world: world([gunAt(CGPoint(x: 700, y: 400), thumb: 0)])) }
        for _ in 0..<30 { game.step(1.0 / 30, world: world([gunAt(CGPoint(x: 200, y: 200), thumb: 0)])) }
        for _ in 0..<18 { game.step(1.0 / 30, world: world([gunAt(CGPoint(x: 700, y: 400), thumb: 0)])) }
        XCTAssertEqual(game.shots, 0, "0.6 s, away, then 0.6 s again: neither is long enough")
    }

    func testAHandThatIsNotAimedDoesNothing() {
        var game = FingerGunsGame(size: frame, seed: 7)
        game.setTargets([.board], at: CGPoint(x: 700, y: 400))
        let open = HandFixtures.moved(HandFixtures.hand(.open, size: 100), by: .zero)
        for _ in 0..<90 { game.step(1.0 / 30, world: world([open])) }
        XCTAssertEqual(game.shots, 0)
    }

    func testTwoShotsInARowCanHitTwoTargets() {
        var game = FingerGunsGame(size: frame, seed: 8)
        game.setTargets([.board, .duck], at: CGPoint(x: 300, y: 400))
        // Put the second target elsewhere by firing at a specific spot: one hand per target.
        game.fire(from: .zero, at: SIMD2(300, 400))
        game.fire(from: .zero, at: SIMD2(300, 400))
        XCTAssertEqual(game.hits, 2)
    }

    func testTargetsFlyAcrossAndAreClearedWhenTheyLeave() {
        var game = FingerGunsGame(size: frame, seed: 9)
        var sawTargets = false
        for _ in 0..<(30 * 20) {
            game.step(1.0 / 30, world: world([]))
            sawTargets = sawTargets || !game.targets.isEmpty
            XCTAssertLessThanOrEqual(game.targets.count, 8)
            XCTAssertTrue(game.targets.allSatisfy { $0.position.x > -200 && $0.position.x < frame.width + 200 })
        }
        XCTAssertTrue(sawTargets)
    }

    func testTheRoundEndsAndSameSeedPlaysTheSame() {
        var a = FingerGunsGame(size: frame, seed: 10), b = FingerGunsGame(size: frame, seed: 10)
        var steps = 0
        while !a.isOver && steps < 30 * 60 { a.step(1.0 / 30, world: world([])); b.step(1.0 / 30, world: world([])); steps += 1 }
        XCTAssertTrue(a.isOver)
        XCTAssertEqual(Double(steps) / 30, FingerGunsGame.roundSeconds, accuracy: 0.2)
        XCTAssertEqual(a.targets.map(\.position.x), b.targets.map(\.position.x))
    }

    func testItRunsAsALensAndDrawsTheSight() throws {
        let h = LensHarness()
        let lens = HandGameLens<FingerGunsGame>(id: "test.finger-guns", needs: [.hands], store: MemoryScoreStore())
        let gun = HandFixtures.gun(from: CGPoint(x: 400, y: 250), toward: CGPoint(x: 900, y: 450), size: 110)
        let base = h.input(hands: [gun])
        var out = base.composed
        for i in 0..<150 { out = lens.render(h.at(base, time: Double(i) / 30)) }
        Output.save(out, as: "game-finger-guns.png")
        XCTAssertEqual(lens.phase, .playing)
        XCTAssertEqual(lens.status?.title.hasPrefix("Score"), true)

        // No hand: the game waits on the hand, not on a person in the frame.
        let waiting = HandGameLens<FingerGunsGame>(id: "test.finger-guns-2", needs: [.hands], store: MemoryScoreStore())
        for i in 0..<60 { _ = waiting.render(h.at(h.input(), time: Double(i) / 30, hands: [])) }
        XCTAssertEqual(waiting.phase, .waiting)
        XCTAssertEqual(waiting.status?.title, "Hold up your hand like a gun")
    }
}

final class HandPipelineTests: XCTestCase {
    private let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))

    func testALensThatAsksForHandsGetsThemAndOneThatDoesNotIsNotAskedToLook() throws {
        let pipeline = FramePipeline()
        pipeline.matteOverride = { [scene] _ in scene.matteBuffer() }
        pipeline.setBackground(.off, source: nil)
        var asked = 0
        pipeline.handsOverride = { asked += 1; return [HandFixtures.openPalm(at: CGPoint(x: 500, y: 300), id: 7)] }

        let wants = ProbeLens(needs: [.hands], grid: false)
        pipeline.setLens(wants)
        pipeline.onOutput = { _, _ in }
        pipeline.queue.sync { pipeline.process(scene.cameraBuffer(), at: .zero) }
        XCTAssertEqual(try XCTUnwrap(wants.inputs.first).hands.map(\.id), [7])
        XCTAssertEqual(asked, 1)

        let doesNot = ProbeLens(needs: [.matte], grid: false)
        pipeline.setLens(doesNot)
        pipeline.queue.sync { pipeline.process(scene.cameraBuffer(), at: .zero) }
        XCTAssertTrue(try XCTUnwrap(doesNot.inputs.first).hands.isEmpty)
        XCTAssertEqual(asked, 1, "hand tracking is only asked for by lenses that use it")
    }
}

/// Vision on real pictures of hands. Emoji are the only hands available without a camera, so these check the whole chain from
/// pixels to gesture on cartoon hands; they skip themselves if this Mac's Vision does not find a hand in the picture.
final class RealVisionHandTests: XCTestCase {
    private func picture(of emoji: String) -> CGImage? {
        let side = 900
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.85, green: 0.88, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let text = NSAttributedString(string: emoji, attributes: [.font: NSFont(name: "AppleColorEmoji", size: 700) ?? NSFont.systemFont(ofSize: 700)])
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let box = text.size()
        text.draw(at: NSPoint(x: (CGFloat(side) - box.width) / 2, y: (CGFloat(side) - box.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private func hand(_ emoji: String) throws -> HandState {
        let image = try XCTUnwrap(picture(of: emoji))
        let found = HandTrackingService.detect(in: image)
        try XCTSkipIf(found.isEmpty, "Vision found no hand in \(emoji) on this Mac")
        return HandState(id: 1, joints: found[0].joints)
    }

    func testAnOpenPalmIsAnOpenPalm() throws {
        let h = try hand("✋")
        XCTAssertEqual(h.pose, .openPalm)
        XCTAssertEqual(h.fingersUp, 4)
        XCTAssertGreaterThan(h.size, 100, "the hand fills much of the 900-pixel picture")
    }

    func testAPointingFingerIsAimedAndPointsTheRightWay() throws {
        let up = try hand("👆")
        XCTAssertTrue(FingerGun.isAimed(up))
        XCTAssertGreaterThan(Double(up.aim.dy), 0.9, "pointing up the picture")
        let right = try hand("👉")
        XCTAssertTrue(FingerGun.isAimed(right))
        XCTAssertGreaterThan(Double(right.aim.dx), 0.9, "pointing right")
        XCTAssertGreaterThan(right.thumbOpen, 0.55, "with the thumb up")
    }

    /// More shapes, in a mid skin tone: each must read as what it shows (when this Mac's Vision finds a hand in it at all).
    func testTheOtherGesturesReadOffRealVisionOutput() throws {
        var found = 0
        for (emoji, expected) in [("👍🏽", HandGesture.Pose.thumbsUp), ("🤏🏽", .pinch), ("👌🏽", .okSign), ("🖐🏽", .openPalm), ("👉🏽", .fingerGun)] {
            guard let image = picture(of: emoji) else { continue }
            let hands = HandTrackingService.detect(in: image)
            guard let raw = hands.first else { continue }
            found += 1
            XCTAssertEqual(HandState(id: 1, joints: raw.joints).gesturePose, expected, emoji)
            XCTAssertEqual(raw.confidences.count, HandJoint.count, "with Vision's confidence in each joint")
        }
        try XCTSkipIf(found == 0, "Vision found none of the hands on this Mac")
    }

    func testTheTrackerFollowsAHandAcrossLooks() throws {
        let image = try XCTUnwrap(picture(of: "✋"))
        let found = HandTrackingService.detect(in: image)
        try XCTSkipIf(found.isEmpty, "Vision found no hand on this Mac")
        var smoother = HandSmoother()
        let first = smoother.update(HandSample(hands: found, at: 0), dt: 0.04)
        let second = smoother.update(HandSample(hands: found, at: 0.04), dt: 0.04)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(second[0].pose, .openPalm)
    }
}

/// Pictures of the two games mid-play, for looking at (BACKDROP_TEST_OUTPUT), and a check that they draw something.
final class FlagshipHandGamePictures: XCTestCase {
    private let h = LensHarness()

    private func frame(_ draw: @escaping (CGContext) -> Void) throws -> (CIImage, Bitmap, Bitmap) {
        let base = h.input()
        let layer = try XCTUnwrap(base.services.overlay(draw))
        let out = layer.composited(over: base.composed).cropped(to: base.rect)
        return (out, h.bitmap(out), h.bitmap(base.composed))
    }

    func testFruitSlashMidSwing() throws {
        var game = FruitSlashGame(size: frame_, seed: 21)
        game.setFruit([], at: .zero)
        for (i, x) in [220.0, 430, 640, 850, 1060].enumerated() { game.launch(i == 4 ? .bomb : .fruit(i * 2), from: x, apex: 560 + Double(i % 2) * 60) }
        let none = GameWorld(size: frame_, matte: nil, motion: nil, face: nil, faceCrop: nil, hands: [])
        for _ in 0..<42 { game.step(1.0 / 30, world: none) }
        // A swipe across the middle, a few looks at a time so there is a trail.
        for i in 0..<5 {
            let tip = CGPoint(x: 300 + Double(i) * 140, y: 420 + Double(i) * 18)
            let hand = swordHand(tip: tip, speed: CGVector(dx: 4200, dy: 540))
            game.step(1.0 / 30, world: GameWorld(size: frame_, matte: nil, motion: nil, face: nil, faceCrop: nil, hands: [hand]))
        }
        let (out, bits, plain) = try frame { game.draw(in: $0, time: 1.3) }
        Output.save(out, as: "game-fruit-slash-swing.png")
        XCTAssertGreaterThan(bits.change(from: plain, in: CGRect(x: 0, y: 0, width: 1280, height: 720)), 150)
    }

    func testFingerGunsAiming() throws {
        var game = FingerGunsGame(size: frame_, seed: 22)
        game.setTargets([(.board, CGPoint(x: 260, y: 520)), (.duck, CGPoint(x: 520, y: 600)), (.ufo, CGPoint(x: 830, y: 480)),
                         (.balloon, CGPoint(x: 1040, y: 560)), (.star, CGPoint(x: 700, y: 330)), (.bunny, CGPoint(x: 380, y: 300))])
        var gun = HandFixtures.hand(HandFixtures.Fingers(index: true, middle: false, ring: false, little: false, thumb: 1), at: CGPoint(x: 640, y: 80), size: 120)
        gun = HandFixtures.moved(gun, by: CGVector(dx: 830 - gun.indexTip.x, dy: 480 - gun.indexTip.y))
        for _ in 0..<14 { game.step(1.0 / 30, world: GameWorld(size: frame_, matte: nil, motion: nil, face: nil, faceCrop: nil, hands: [gun])) }
        game.fire(from: SIMD2(640, 120), at: SIMD2(260, 520))
        let (out, bits, plain) = try frame { game.draw(in: $0, time: 0.6) }
        Output.save(out, as: "game-finger-guns-aim.png")
        XCTAssertGreaterThan(bits.change(from: plain, in: CGRect(x: 0, y: 0, width: 1280, height: 720)), 150)
    }

    private let frame_ = CGSize(width: 1280, height: 720)
}
