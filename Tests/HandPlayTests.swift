import CoreImage
import simd
import XCTest

private let playFrame = CGSize(width: 1280, height: 720)
private let playTick = 1.0 / 30

private func playWorld(_ hands: [HandState] = []) -> GameWorld {
    GameWorld(size: playFrame, matte: nil, motion: nil, face: nil, hands: hands)
}

/// Hands for the HandPlay tests, placed by the point that matters to the game.
private enum PlayHands {
    static let thumbsUp = HandFixtures.Fingers(index: false, middle: false, ring: false, little: false, thumb: 1)

    static func make(_ fingers: HandFixtures.Fingers, palmAt p: CGPoint, size: Double = 100, id: Int = 1, angle: Double = 0) -> HandState {
        let base = HandFixtures.hand(fingers, at: .zero, size: size, angle: angle, id: id)
        return HandFixtures.moved(base, by: CGVector(dx: p.x - base.palm.x, dy: p.y - base.palm.y))
    }

    static func pointing(tipAt p: CGPoint, size: Double = 100, id: Int = 1) -> HandState {
        let base = HandFixtures.hand(.point, at: .zero, size: size, id: id)
        return HandFixtures.moved(base, by: CGVector(dx: p.x - base.indexTip.x, dy: p.y - base.indexTip.y))
    }
}

private func playFor<G: Game>(_ game: inout G, seconds: Double, hands: [HandState] = []) {
    for _ in 0..<Int((seconds * 30).rounded()) { game.step(playTick, world: playWorld(hands)) }
}

// MARK: - The shared kit

final class HandPlayKitTests: XCTestCase {
    func testTheFiveShapesAreReadAtAnyAngleAndSize() {
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: .pi / 4) {
            for size in [60.0, 110, 220] {
                let at = CGPoint(x: 640, y: 360)
                XCTAssertEqual(HandPlayReading.pose(of: PlayHands.make(.fist, palmAt: at, size: size, angle: angle)), .fist, "fist \(angle) \(size)")
                XCTAssertEqual(HandPlayReading.pose(of: PlayHands.make(.open, palmAt: at, size: size, angle: angle)), .open)
                XCTAssertEqual(HandPlayReading.pose(of: PlayHands.make(.peace, palmAt: at, size: size, angle: angle)), .peace)
                XCTAssertEqual(HandPlayReading.pose(of: PlayHands.make(.point, palmAt: at, size: size, angle: angle)), .point)
                XCTAssertEqual(HandPlayReading.pose(of: PlayHands.make(.gun, palmAt: at, size: size, angle: angle)), .point, "a thumb out still points")
                XCTAssertEqual(HandPlayReading.pose(of: PlayHands.make(PlayHands.thumbsUp, palmAt: at, size: size, angle: angle)), .thumbsUp)
            }
        }
        XCTAssertEqual(HandPlayReading.pose(of: HandFixtures.recorded(HandFixtures.Recorded.openPalm)), .open, "what Vision reported for an open hand")
        XCTAssertEqual(HandPlayReading.pose(of: HandFixtures.recorded(HandFixtures.Recorded.pointUp)), .point)
        var halfThumb = HandFixtures.Fingers.fist
        halfThumb.thumb = 0.72
        XCTAssertNil(HandPlayReading.pose(of: PlayHands.make(halfThumb, palmAt: CGPoint(x: 400, y: 300))), "a thumb half out is neither a fist nor a thumbs up")
    }

    func testTheGripIgnoresAOneFrameFlicker() {
        var grip = HandPlayGrip()
        let open = PlayHands.make(.open, palmAt: CGPoint(x: 400, y: 300)), fist = PlayHands.make(.fist, palmAt: CGPoint(x: 400, y: 300))
        _ = grip.update(open, dt: playTick)
        XCTAssertEqual(grip.state, .open, "a new hand is read at once")
        XCTAssertNil(grip.update(fist, dt: playTick))
        XCTAssertNil(grip.update(open, dt: playTick))
        XCTAssertEqual(grip.state, .open, "one stray frame changes nothing")
        var changed: (from: HandPlayGrip.State, to: HandPlayGrip.State)?
        for _ in 0..<4 { if let c = grip.update(fist, dt: playTick) { changed = c } }
        XCTAssertEqual(grip.state, .closed, "a fist held for a tenth of a second counts")
        XCTAssertEqual(changed?.from, .open)
        XCTAssertEqual(changed?.to, .closed)
    }

    func testTheRosterMeasuresSpeedAndRemembersALostHandForAMoment() {
        var roster = HandPlayRoster()
        for i in 0..<10 {
            roster.update([PlayHands.make(.open, palmAt: CGPoint(x: 300 + Double(i) * 20, y: 300))], dt: playTick, now: Double(i) * playTick)
        }
        XCTAssertEqual(roster.entries.first?.velocity.x ?? 0, 600, accuracy: 60, "20 px a frame is 600 px a second")
        // Repeated looks between two tracker updates: the speed is measured over a window, so it does not drop to nothing.
        roster.update([PlayHands.make(.open, palmAt: CGPoint(x: 480, y: 300))], dt: playTick, now: 10 * playTick)
        XCTAssertGreaterThan(roster.entries.first?.velocity.x ?? 0, 250)
        roster.update([], dt: 0.3, now: 0.6)
        XCTAssertEqual(roster.entries.count, 1)
        XCTAssertFalse(roster.entries[0].visible)
        roster.update([], dt: 0.4, now: 1.0)
        XCTAssertTrue(roster.entries.isEmpty, "gone after more than half a second")
    }

    func testTextBannersAndGlovesAreDrawnOnceAndKept() {
        let a = HandPlayText.image("PERFECT", size: 40, color: HandPlayPalette.gold)
        let b = HandPlayText.image("PERFECT", size: 40, color: HandPlayPalette.gold)
        XCTAssertNotNil(a)
        XCTAssertTrue(a === b, "the same picture, not drawn again")
        for pose in HandPlayPose.allCases {
            let glove = HandPlayGlove.image(pose, height: 100)
            XCTAssertNotNil(glove)
            XCTAssertTrue(glove === HandPlayGlove.image(pose, height: 100))
        }
    }
}

// MARK: - Magic Duel

final class HandPlayMagicDuelTests: XCTestCase {
    typealias Game = HandPlayMagicDuel

    private func fresh(seed: UInt64 = 1) -> Game {
        var game = Game(size: playFrame, seed: seed)
        game.pauseSpawns()
        return game
    }

    func testAPushThrowsTheFireballThatWay() {
        var game = fresh()
        let left = game.place(.wisp, at: SIMD2(200, 560)), right = game.place(.wisp, at: SIMD2(1080, 560))
        var palm = CGPoint(x: 700, y: 360)
        playFor(&game, seconds: 0.3, hands: [PlayHands.make(.open, palmAt: palm)])
        XCTAssertTrue(game.fireballs.isEmpty, "the fireball is still gathering")
        playFor(&game, seconds: 0.3, hands: [PlayHands.make(.open, palmAt: palm)])
        XCTAssertTrue(game.fireballs.isEmpty, "ready, and waiting for a push")
        XCTAssertEqual(game.casters.first?.target, right, "the reticle sits on the nearest one")
        // A push up and to the left: toward the far monster, not the near one.
        for _ in 0..<4 {
            palm.x -= 22
            palm.y += 9
            game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: palm)]))
        }
        XCTAssertEqual(game.fireballs.count, 1)
        XCTAssertEqual(game.fireballs.first?.target, left)
        XCTAssertLessThan(game.fireballs.first?.velocity.x ?? 0, 0)
        playFor(&game, seconds: 1.2, hands: [PlayHands.make(.open, palmAt: palm)])
        XCTAssertTrue(game.monsters.first { $0.id == left }.map { !$0.isAlive } ?? true, "banished")
        XCTAssertGreaterThanOrEqual(game.score, 1)
    }

    func testAReadyFireballHeldStillGoesByItselfAtTheNearestMonster() {
        var game = fresh()
        game.place(.wisp, at: SIMD2(300, 600))
        let hand = PlayHands.make(.open, palmAt: CGPoint(x: 320, y: 300))
        playFor(&game, seconds: 1.0, hands: [hand])
        XCTAssertTrue(game.fireballs.isEmpty)
        playFor(&game, seconds: 1.5, hands: [hand])
        XCTAssertEqual(game.banished, 1)
        XCTAssertEqual(game.score, 1)
        XCTAssertEqual(game.hearts, 3)
    }

    func testTrackingJitterIsNotAPush() {
        var game = fresh()
        game.place(.wisp, at: SIMD2(300, 600))
        for i in 0..<36 {
            let palm = CGPoint(x: 320 + (i % 2 == 0 ? 4 : -4), y: 300 + (i % 3 == 0 ? 3 : -3))
            game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: palm)]))
        }
        XCTAssertTrue(game.fireballs.isEmpty, "a trembling hand holds its fire until it is pushed or held long enough")
    }

    func testItAimsAtTheMonsterNearestTheHand() {
        var game = fresh()
        let left = game.place(.wisp, at: SIMD2(180, 560)), right = game.place(.wisp, at: SIMD2(1100, 560))
        XCTAssertEqual(game.target(for: CGPoint(x: 300, y: 420)), left)
        XCTAssertEqual(game.target(for: CGPoint(x: 980, y: 420)), right)
        var guardCount = 0
        while game.fireballs.isEmpty && game.banished == 0 && guardCount < 90 {
            game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: CGPoint(x: 980, y: 420))]))
            guardCount += 1
        }
        let hit = game.fireballs.first?.target ?? game.monsters.first { !$0.isAlive }?.id
        XCTAssertEqual(hit, right, "reach toward the one you want")
        XCTAssertTrue(game.monsters.first { $0.id == left }?.isAlive ?? false)
    }

    func testTwoHandsCastTwice() {
        var one = fresh(), two = fresh()
        for g in [0, 1] {
            for (x, y) in [(150.0, 650.0), (1130, 650), (200, 200), (1080, 200)] {
                if g == 0 { one.place(.brute, at: SIMD2(x, y)) } else { two.place(.brute, at: SIMD2(x, y)) }
            }
        }
        var thrownOne = 0, thrownTwo = 0
        for i in 0..<60 {
            // Hands pumping back and forth, throwing whenever a fireball is ready.
            let swing = 50 * sin(Double(i) * 0.7)
            let a = PlayHands.make(.open, palmAt: CGPoint(x: 300 + swing, y: 400)), b = PlayHands.make(.open, palmAt: CGPoint(x: 980 - swing, y: 400), id: 2)
            let before1 = one.fireballs.count, before2 = two.fireballs.count
            one.step(playTick, world: playWorld([a]))
            two.step(playTick, world: playWorld([a, b]))
            thrownOne += max(0, one.fireballs.count - before1)
            thrownTwo += max(0, two.fireballs.count - before2)
        }
        XCTAssertGreaterThanOrEqual(thrownTwo, thrownOne * 2 - 1)
        XCTAssertGreaterThan(thrownOne, 2)
    }

    func testABruteTakesThreeFireballsAndIsWorthFive() {
        var game = fresh()
        game.place(.brute, at: SIMD2(250, 620))
        playFor(&game, seconds: 6.5, hands: [PlayHands.make(.open, palmAt: CGPoint(x: 300, y: 380))])
        XCTAssertEqual(game.banished, 1)
        XCTAssertEqual(game.score, 5)
    }

    func testAFistShieldsYouFromAHex() {
        var game = fresh()
        game.placeHex(at: SIMD2(640 + 420, 324))
        playFor(&game, seconds: 2.5, hands: [PlayHands.make(.fist, palmAt: CGPoint(x: 900, y: 200))])
        XCTAssertEqual(game.hearts, 3)
        XCTAssertEqual(game.blocked, 1)
        XCTAssertEqual(game.score, 1)
        XCTAssertTrue(game.hexes.isEmpty)

        var bare = fresh()
        bare.placeHex(at: SIMD2(640 + 420, 324))
        playFor(&bare, seconds: 2.5)
        XCTAssertEqual(bare.hearts, 2, "without a shield a hex costs a heart")
    }

    func testTheShieldThrowsBackAMonsterAndANakedHomeIsHurt() {
        var shielded = fresh()
        shielded.place(.wisp, at: SIMD2(640 + 330, 324))
        playFor(&shielded, seconds: 2.5, hands: [PlayHands.make(.fist, palmAt: CGPoint(x: 300, y: 200))])
        XCTAssertEqual(shielded.hearts, 3)
        XCTAssertEqual(shielded.monsters.filter(\.isAlive).count, 1, "thrown back, not banished")

        var open = fresh()
        open.place(.wisp, at: SIMD2(640 + 330, 324))
        playFor(&open, seconds: 6)
        XCTAssertEqual(open.hearts, 2)
    }

    func testTheShieldRunsOutAndHasToRecharge() {
        var game = fresh()
        let fist = PlayHands.make(.fist, palmAt: CGPoint(x: 300, y: 200))
        playFor(&game, seconds: 1, hands: [fist])
        XCTAssertTrue(game.shieldUp)
        playFor(&game, seconds: 3, hands: [fist])
        XCTAssertTrue(game.shieldBroken, "about three seconds of shield")
        XCTAssertFalse(game.shieldUp)
        playFor(&game, seconds: 1, hands: [PlayHands.make(.open, palmAt: CGPoint(x: 300, y: 200))])
        playFor(&game, seconds: 0.2, hands: [fist])
        XCTAssertFalse(game.shieldUp, "not yet")
        playFor(&game, seconds: 2, hands: [PlayHands.make(.open, palmAt: CGPoint(x: 300, y: 200))])
        playFor(&game, seconds: 0.2, hands: [fist])
        XCTAssertTrue(game.shieldUp, "back again")
    }

    func testAFlickeringHandNeverRaisesTheShield() {
        var game = fresh()
        for i in 0..<120 {
            let hand = i % 4 == 3 ? PlayHands.make(.fist, palmAt: CGPoint(x: 300, y: 300)) : PlayHands.make(.open, palmAt: CGPoint(x: 300, y: 300))
            game.step(playTick, world: playWorld([hand]))
            XCTAssertFalse(game.shieldUp, "frame \(i)")
        }
    }

    func testNobodyThereLosesAndTheFieldClears() {
        var game = Game(size: playFrame, seed: 4)
        var steps = 0
        while !game.isOver && steps < 30 * 180 { game.step(playTick, world: playWorld()); steps += 1 }
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.hearts, 0)
        XCTAssertTrue(game.monsters.isEmpty && game.fireballs.isEmpty && game.hexes.isEmpty)
        let score = game.score
        game.step(1, world: playWorld())
        XCTAssertEqual(game.score, score)
    }

    func testAPlayerWhoCastsAndShieldsDoesBetterThanOneWhoDoesNot() {
        func play(_ seed: UInt64, active: Bool) -> (score: Int, survived: Double) {
            var game = Game(size: playFrame, seed: seed)
            var t = 0.0
            while !game.isOver && t < 90 {
                var hands: [HandState] = [PlayHands.make(.fist, palmAt: CGPoint(x: 200, y: 120))]
                if active {
                    let danger = game.hexes.contains { simd_distance($0.position, game.home) < 330 }
                    let nearest = game.monsters.filter(\.isAlive).min { simd_distance($0.position, game.home) < simd_distance($1.position, game.home) }
                    if danger {
                        hands = [PlayHands.make(.fist, palmAt: CGPoint(x: 640, y: 200))]
                    } else if let m = nearest {
                        // Hold the hand out toward it, and push when the fireball is ready.
                        let d = simd_normalize(m.position - game.home + SIMD2(0, 1e-6))
                        let ready = game.casters.first.map { $0.charge >= 1 } ?? false
                        let palm = game.home + d * (ready ? 240 : 190)
                        hands = [PlayHands.make(.open, palmAt: CGPoint(x: palm.x, y: palm.y))]
                    } else {
                        hands = [PlayHands.make(.open, palmAt: CGPoint(x: 640, y: 300))]
                    }
                } else {
                    hands = [PlayHands.make(.point, palmAt: CGPoint(x: 200, y: 120))]
                }
                game.step(playTick, world: playWorld(hands))
                t += playTick
            }
            return (game.score, t)
        }
        for seed in [1, 2] as [UInt64] {
            let good = play(seed, active: true), idle = play(seed, active: false)
            XCTAssertGreaterThan(good.score, 10, "seed \(seed)")
            XCTAssertEqual(idle.score, 0)
            XCTAssertGreaterThan(good.survived, idle.survived)
        }
    }

    func testTheSameSeedAndHandsPlayTheSame() {
        func trace(_ seed: UInt64) -> [Double] {
            var game = Game(size: playFrame, seed: seed)
            var out: [Double] = []
            for i in 0..<900 {
                let hand = i % 150 < 100 ? PlayHands.make(.open, palmAt: CGPoint(x: 640 + 300 * sin(Double(i) / 40), y: 360))
                                         : PlayHands.make(.fist, palmAt: CGPoint(x: 640, y: 200))
                game.step(playTick, world: playWorld([hand]))
                out.append(Double(game.score) + game.monsters.reduce(0) { $0 + $1.position.x })
            }
            return out
        }
        XCTAssertEqual(trace(5), trace(5))
        XCTAssertNotEqual(trace(5), trace(6))
    }

    func testAHugeStepAndHandsComingAndGoingDoNotBreakIt() {
        var game = Game(size: playFrame, seed: 3)
        var rng = SplitMix64(seed: 9)
        for i in 0..<(30 * 40) {
            var hands: [HandState] = []
            if Int.random(in: 0..<3, using: &rng) != 0 {
                let fingers: HandFixtures.Fingers = [.open, .fist, .point, .peace][Int.random(in: 0..<4, using: &rng)]
                hands.append(PlayHands.make(fingers, palmAt: CGPoint(x: Double.random(in: 0...1280, using: &rng), y: Double.random(in: 0...720, using: &rng)),
                                            id: 1 + i / 70 % 3))
            }
            game.step(playTick, world: playWorld(hands))
        }
        game.step(30, world: playWorld([PlayHands.make(.open, palmAt: CGPoint(x: 400, y: 300))]))
        game.step(-1, world: playWorld())
        XCTAssertGreaterThanOrEqual(game.hearts, 0)
        XCTAssertEqual(Game.presenceHint, "Hold up your hand to play")
    }
}

// MARK: - Star Catcher

final class HandPlayStarCatcherTests: XCTestCase {
    typealias Game = HandPlayStarCatcher
    private let palm = CGPoint(x: 400, y: 300)
    private var open: HandState { PlayHands.make(.open, palmAt: palm) }
    private var fist: HandState { PlayHands.make(.fist, palmAt: palm) }

    private func fresh() -> Game {
        var game = Game(size: playFrame, seed: 1)
        game.pauseSpawns()
        return game
    }

    private func catchStars(_ game: inout Game, _ kinds: [Game.Kind], hand: HandState? = nil) {
        for kind in kinds {
            game.drop(kind, at: SIMD2(palm.x, palm.y))
            game.step(playTick, world: playWorld([hand ?? open]))
        }
    }

    func testEachStarInAHandfulCountsForItsPlace() {
        XCTAssertEqual(Game.worth(of: [.star]), 1)
        XCTAssertEqual(Game.worth(of: [.star, .star, .star, .star, .star]), 15)
        XCTAssertEqual(Game.worth(of: [.golden, .star]), 3 + 2)
        XCTAssertEqual(Game.worth(of: []), 0)
    }

    func testAnOpenHandCatchesAndAFistBanks() {
        var game = fresh()
        catchStars(&game, [.star, .star, .star])
        XCTAssertEqual(game.holding, 3)
        XCTAssertEqual(game.score, 0, "nothing counts until it is banked")
        playFor(&game, seconds: 0.2, hands: [fist])
        XCTAssertEqual(game.score, 6)
        XCTAssertEqual(game.holding, 0)
        XCTAssertEqual(game.banks, 1)
    }

    func testAClosedHandCatchesNothing() {
        var game = fresh()
        playFor(&game, seconds: 0.2, hands: [fist])
        game.drop(.star, at: SIMD2(palm.x, palm.y + 200), speed: 300)
        playFor(&game, seconds: 2.5, hands: [fist])
        XCTAssertEqual(game.holding, 0)
        XCTAssertTrue(game.items.isEmpty, "it fell past")
    }

    func testABombInAnOpenHandSpillsTheStarsAndCostsAHeart() {
        var game = fresh()
        catchStars(&game, [.star, .golden])
        game.drop(.bomb, at: SIMD2(palm.x, palm.y))
        game.step(playTick, world: playWorld([open]))
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(game.holding, 0)
        XCTAssertEqual(game.spilled, 2)
        // Dazed for a moment: a star sitting in the hand is not caught until it passes.
        game.drop(.star, at: SIMD2(palm.x, palm.y))
        playFor(&game, seconds: 0.4, hands: [open])
        XCTAssertEqual(game.holding, 0)
        playFor(&game, seconds: 0.8, hands: [open])
        XCTAssertEqual(game.holding, 1)
    }

    func testAFistPunchesABombAway() {
        var game = fresh()
        playFor(&game, seconds: 0.2, hands: [fist])
        game.drop(.bomb, at: SIMD2(palm.x, palm.y + 60))
        playFor(&game, seconds: 0.1, hands: [fist])
        XCTAssertEqual(game.lives, 3)
        XCTAssertTrue(game.items.first?.punched ?? false)
        playFor(&game, seconds: 3, hands: [fist])
        XCTAssertTrue(game.items.isEmpty, "and it flies off")
        XCTAssertEqual(game.lives, 3)
    }

    func testAHandHoldsAtMostEight() {
        var game = fresh()
        catchStars(&game, Array(repeating: .star, count: 11))
        XCTAssertEqual(game.holding, Game.handfulLimit)
    }

    func testAFlickerDoesNotBank() {
        var game = fresh()
        catchStars(&game, [.star, .star, .star])
        game.step(playTick, world: playWorld([fist]))
        playFor(&game, seconds: 0.3, hands: [open])
        XCTAssertEqual(game.banks, 0)
        XCTAssertEqual(game.holding, 3)
    }

    func testAHandThatDropsOutForAMomentKeepsItsStars() {
        var game = fresh()
        catchStars(&game, [.star, .star])
        playFor(&game, seconds: 0.5)
        XCTAssertEqual(game.holding, 2)
        playFor(&game, seconds: 0.2, hands: [fist])
        XCTAssertEqual(game.score, 3)

        // Back as a "new" hand (tracking gave it a new id): it picks up the stars.
        var renamed = fresh()
        catchStars(&renamed, [.star, .star])
        playFor(&renamed, seconds: 0.8)
        playFor(&renamed, seconds: 0.1, hands: [PlayHands.make(.open, palmAt: palm, id: 7)])
        XCTAssertEqual(renamed.holding, 2)
        playFor(&renamed, seconds: 0.2, hands: [PlayHands.make(.fist, palmAt: palm, id: 7)])
        XCTAssertEqual(renamed.score, 3)
    }

    func testAHandGoneTooLongDropsItsStars() {
        var game = fresh()
        catchStars(&game, [.star, .star])
        playFor(&game, seconds: 2)
        XCTAssertEqual(game.holding, 0)
        XCTAssertEqual(game.spilled, 2)
        XCTAssertEqual(game.score, 0)
    }

    func testTheRoundLastsAMinute() {
        var game = Game(size: playFrame, seed: 3)
        var steps = 0
        let resting = PlayHands.make(.fist, palmAt: CGPoint(x: 100, y: 100))
        while !game.isOver && steps < 30 * 90 { game.step(playTick, world: playWorld([resting])); steps += 1 }
        XCTAssertEqual(Double(steps) / 30, Game.roundSeconds, accuracy: 0.2)
        XCTAssertTrue(game.items.isEmpty)
    }

    func testThreeBombsEndIt() {
        var game = fresh()
        for _ in 0..<3 {
            game.drop(.bomb, at: SIMD2(palm.x, palm.y))
            playFor(&game, seconds: 1.2, hands: [open])
        }
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.lives, 0)
    }

    func testAPlayerWhoCatchesAndBanksScores() {
        var game = Game(size: playFrame, seed: 11)
        var hand = CGPoint(x: 640, y: 260)
        var t = 0.0
        while !game.isOver {
            let stars = game.items.filter { $0.kind != .bomb && $0.position.y > 150 && $0.position.y < 600 }
            if let next = stars.min(by: { $0.position.y < $1.position.y }) {
                let dx = next.position.x - hand.x
                hand.x += max(-30, min(30, dx))
            }
            let bombNear = game.items.contains { $0.kind == .bomb && !$0.punched && abs($0.position.x - hand.x) < 160 && abs($0.position.y - hand.y) < 200 }
            let bank = game.holding >= 4 || bombNear
            game.step(playTick, world: playWorld([PlayHands.make(bank ? .fist : .open, palmAt: hand)]))
            t += playTick
        }
        XCTAssertGreaterThan(game.caught, 15)
        XCTAssertGreaterThan(game.banks, 3)
        XCTAssertGreaterThan(game.score, 30)
    }

    func testTheSameSeedPlaysTheSame() {
        func trace() -> [Double] {
            var game = Game(size: playFrame, seed: 21)
            var out: [Double] = []
            for i in 0..<900 {
                let fingers: HandFixtures.Fingers = i % 60 < 45 ? .open : .fist
                game.step(playTick, world: playWorld([PlayHands.make(fingers, palmAt: CGPoint(x: 640 + 400 * sin(Double(i) / 30), y: 280))]))
                out.append(Double(game.score) + game.items.reduce(0) { $0 + $1.position.y })
            }
            return out
        }
        XCTAssertEqual(trace(), trace())
    }

    func testAHugeStepDoesNotBreakIt() {
        var game = Game(size: playFrame, seed: 2)
        game.step(40, world: playWorld([open]))
        game.step(-3, world: playWorld())
        XCTAssertGreaterThan(game.timeLeft, 0, "one step cannot eat the round")
        XCTAssertEqual(Game.presenceHint, "Hold up your hand to play")
    }
}

// MARK: - Juggle

final class HandPlayJuggleTests: XCTestCase {
    typealias Game = HandPlayJuggle

    private func bounceOnce(ballX: Double, palmX: Double) -> Game {
        var game = Game(size: playFrame, seed: 1)
        game.place(ballAt: SIMD2(ballX, 480), velocity: SIMD2(0, -300))
        let hand = PlayHands.make(.open, palmAt: CGPoint(x: palmX, y: 280))
        var guardCount = 0
        while game.hits == 0 && guardCount < 90 { game.step(playTick, world: playWorld([hand])); guardCount += 1 }
        return game
    }

    func testAStillPalmBouncesABallBackUp() throws {
        let game = bounceOnce(ballX: 640, palmX: 640)
        XCTAssertEqual(game.hits, 1)
        XCTAssertEqual(game.score, 1)
        let ball = try XCTUnwrap(game.balls.first)
        XCTAssertGreaterThanOrEqual(ball.velocity.y, Game.minimumLift - 1, "always enough lift to be reached again")
        XCTAssertLessThan(abs(ball.velocity.x), 60, "straight up off the middle of the hand")
    }

    func testWhereItLandsOnTheHandSteersIt() throws {
        let right = bounceOnce(ballX: 690, palmX: 640), left = bounceOnce(ballX: 590, palmX: 640)
        XCTAssertGreaterThan(try XCTUnwrap(right.balls.first).velocity.x, 50)
        XCTAssertLessThan(try XCTUnwrap(left.balls.first).velocity.x, -50)
    }

    func testTheBallBouncesOffTheRingNotThinAir() throws {
        // The pad is the ring on the palm: a ball coming down beside the hand, clear of the ring, falls past it.
        var game = Game(size: playFrame, seed: 1)
        game.place(ballAt: SIMD2(640 + 220, 480), velocity: SIMD2(0, -300))
        playFor(&game, seconds: 1.5, hands: [PlayHands.make(.open, palmAt: CGPoint(x: 640, y: 280))])
        XCTAssertEqual(game.hits, 0)
    }

    func testADroppedBallCostsAHeartAndComesBack() {
        var game = Game(size: playFrame, seed: 2)
        game.place(ballAt: SIMD2(640, 160), velocity: SIMD2(0, -300))
        playFor(&game, seconds: 1)
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(game.drops, 1)
        XCTAssertTrue(game.balls.isEmpty)
        playFor(&game, seconds: 1.5)
        XCTAssertEqual(game.balls.count, 1, "a new one drops in from the top")
    }

    func testAFastHandCannotPassThroughABall() {
        var game = Game(size: playFrame, seed: 1)
        game.place(ballAt: SIMD2(640, 330), velocity: SIMD2(0, -100))
        // The hand swings up from well below to well above the ball in two frames.
        game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: CGPoint(x: 640, y: 110))]))
        game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: CGPoint(x: 640, y: 290))]))
        game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: CGPoint(x: 640, y: 470))]))
        XCTAssertEqual(game.hits, 1)
        XCTAssertGreaterThan(game.balls.first?.velocity.y ?? 0, Game.minimumLift - 1)
        XCTAssertGreaterThan(game.balls.first?.position.y ?? 0, 400, "carried up, not left behind")
    }

    /// A player who keeps a palm under every ball.
    private func keepItUp(_ game: inout Game, seconds: Double) {
        var palms = [CGPoint(x: 400, y: 200), CGPoint(x: 880, y: 200)]
        for _ in 0..<Int(seconds * 30) {
            let lowest = game.balls.sorted { $0.position.y + ($0.velocity.y < 0 ? 0 : 400) < $1.position.y + ($1.velocity.y < 0 ? 0 : 400) }
            var hands: [HandState] = []
            for (k, ball) in lowest.prefix(2).enumerated() {
                let dx = ball.position.x - palms[k].x
                palms[k].x += max(-40, min(40, dx))
                hands.append(PlayHands.make(.open, palmAt: palms[k], id: k + 1))
            }
            game.step(playTick, world: playWorld(hands))
        }
    }

    func testBouncesBringMoreBallsAndAMultiplier() {
        var game = Game(size: playFrame, seed: 3)
        keepItUp(&game, seconds: 32)
        XCTAssertGreaterThanOrEqual(game.hits, Game.hitsPerBall)
        XCTAssertGreaterThanOrEqual(game.balls.count + game.returning.count, 2, "a second ball joined")
        XCTAssertGreaterThan(game.score, game.hits, "later bounces are worth more")
    }

    func testAGoodPlayerKeepsOneBallUpForAMinute() {
        var game = Game(size: playFrame, seed: 4)
        var palm = CGPoint(x: 640, y: 200)
        for _ in 0..<(30 * 60) {
            if let ball = game.balls.first { palm.x += max(-40, min(40, ball.position.x - palm.x)) }
            game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: palm)]))
            if game.hits >= Game.hitsPerBall - 1 { break }
        }
        XCTAssertEqual(game.drops, 0)
        XCTAssertGreaterThanOrEqual(game.hits, Game.hitsPerBall - 1)
    }

    func testNobodyThereDropsEverything() {
        var game = Game(size: playFrame, seed: 5)
        var steps = 0
        while !game.isOver && steps < 30 * 60 { game.step(playTick, world: playWorld()); steps += 1 }
        XCTAssertTrue(game.isOver)
        XCTAssertTrue(game.balls.isEmpty)
        XCTAssertEqual(game.score, 0)
    }

    func testBallsStayInsideThePictureSidewaysAndUp() {
        var game = Game(size: playFrame, seed: 6)
        game.place(ballAt: SIMD2(100, 300), velocity: SIMD2(-900, 1400))
        for _ in 0..<60 {
            game.step(playTick, world: playWorld())
            for ball in game.balls {
                XCTAssertGreaterThanOrEqual(ball.position.x, 0)
                XCTAssertLessThanOrEqual(ball.position.x, 1280)
                XCTAssertLessThanOrEqual(ball.position.y, 720)
            }
        }
    }

    func testTheSameSeedPlaysTheSame() {
        func trace() -> [Double] {
            var game = Game(size: playFrame, seed: 8)
            var out: [Double] = []
            for i in 0..<600 {
                game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: CGPoint(x: 640 + 200 * sin(Double(i) / 25), y: 220))]))
                out.append(Double(game.score) + game.balls.reduce(0) { $0 + $1.position.x + $1.position.y })
            }
            return out
        }
        XCTAssertEqual(trace(), trace())
    }

    func testAHugeStepDoesNotBreakIt() {
        var game = Game(size: playFrame, seed: 2)
        game.step(50, world: playWorld([PlayHands.make(.open, palmAt: CGPoint(x: 640, y: 200))]))
        game.step(-2, world: playWorld())
        XCTAssertGreaterThanOrEqual(game.lives, 0)
        XCTAssertEqual(Game.presenceHint, "Hold up your hand to play")
    }
}

// MARK: - Air Hockey

final class HandPlayAirHockeyTests: XCTestCase {
    typealias Game = HandPlayAirHockey

    func testAMalletFollowsItsHandButStaysInYourHalf() throws {
        var game = Game(size: playFrame, seed: 1)
        playFor(&game, seconds: 0.5, hands: [PlayHands.make(.open, palmAt: CGPoint(x: 400, y: 250))])
        let mallet = try XCTUnwrap(game.mallets.first)
        XCTAssertEqual(mallet.position.x, 400, accuracy: 2)
        XCTAssertEqual(mallet.position.y, 250, accuracy: 2)
        playFor(&game, seconds: 0.5, hands: [PlayHands.make(.open, palmAt: CGPoint(x: 400, y: 640))])
        XCTAssertLessThan(try XCTUnwrap(game.mallets.first).position.y, game.middle, "it cannot cross the centre line")
        playFor(&game, seconds: 0.5, hands: [PlayHands.make(.open, palmAt: CGPoint(x: -50, y: 100))])
        XCTAssertGreaterThan(try XCTUnwrap(game.mallets.first).position.x, game.left, "or leave the table")
    }

    func testATrackingJumpIsASlideNotATeleport() throws {
        var game = Game(size: playFrame, seed: 1)
        playFor(&game, seconds: 0.5, hands: [PlayHands.make(.open, palmAt: CGPoint(x: 200, y: 200))])
        let before = try XCTUnwrap(game.mallets.first).position
        game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: CGPoint(x: 1100, y: 200))]))
        let after = try XCTUnwrap(game.mallets.first).position
        XCTAssertLessThanOrEqual(simd_distance(before, after), Game.malletSpeed * playTick + 0.5)
    }

    func testAMalletSwungIntoThePuckSendsItFlying() {
        var game = Game(size: playFrame, seed: 1)
        game.place(computerAt: SIMD2(1100, 600))
        playFor(&game, seconds: 0.5, hands: [PlayHands.make(.open, palmAt: CGPoint(x: 640, y: 80))])
        game.place(puck: SIMD2(640, 260), velocity: .zero)
        for k in 0..<8 { game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: CGPoint(x: 640, y: 80 + Double(k) * 40))])) }
        XCTAssertGreaterThan(game.puckVelocity.y, 600, "up the table, fast")
        XCTAssertGreaterThanOrEqual(game.hits, 1)
    }

    func testThePuckBouncesOffTheWallsAndStaysOnTheTable() {
        var game = Game(size: playFrame, seed: 1)
        game.place(computerAt: SIMD2(150, 600))
        game.place(puck: SIMD2(400, 300), velocity: SIMD2(-1500, 300))
        for _ in 0..<20 {
            game.step(playTick, world: playWorld())
            XCTAssertGreaterThanOrEqual(game.puck.x, game.left)
            XCTAssertLessThanOrEqual(game.puck.x, game.right)
        }
        XCTAssertGreaterThan(game.puckVelocity.x, 0, "came back off the left wall")
    }

    func testScoringInTheTopGoal() {
        var game = Game(size: playFrame, seed: 1)
        game.place(computerAt: SIMD2(1150, 620))
        game.place(puck: SIMD2(640, 500), velocity: SIMD2(0, 1200), touchedByPlayer: true)
        playFor(&game, seconds: 0.5)
        XCTAssertEqual(game.goalsFor, 1)
        XCTAssertEqual(game.score, 1)
        XCTAssertGreaterThan(game.faceoff, 0, "a pause before the next puck")
        playFor(&game, seconds: 1.5)
        XCTAssertGreaterThan(game.puck.y, game.middle, "the computer gets the next puck")
    }

    func testABankShotIsWorthTwo() {
        var game = Game(size: playFrame, seed: 1)
        game.place(computerAt: SIMD2(160, 620))
        game.place(puck: SIMD2(1100, 400), velocity: SIMD2(600, 250), touchedByPlayer: true)
        playFor(&game, seconds: 3)
        XCTAssertEqual(game.goalsFor, 1)
        XCTAssertEqual(game.score, 2)
    }

    func testTheComputerScoringCostsAHeart() {
        var game = Game(size: playFrame, seed: 1)
        game.place(puck: SIMD2(640, 220), velocity: SIMD2(0, -1000))
        playFor(&game, seconds: 0.5)
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(game.goalsAgainst, 1)
        playFor(&game, seconds: 1.5)
        XCTAssertLessThan(game.puck.y, game.middle, "and you get the next puck")
    }

    func testThePostsKeepOutAPuckThatHitsThem() {
        var game = Game(size: playFrame, seed: 1)
        game.place(puck: SIMD2(game.mouth.lowerBound, 160), velocity: SIMD2(0, -700))
        playFor(&game, seconds: 0.4)
        XCTAssertEqual(game.lives, 3)
        XCTAssertGreaterThan(game.puckVelocity.y, 0)
    }

    func testNobodyThereLosesTheMatch() {
        var game = Game(size: playFrame, seed: 3)
        var steps = 0
        while !game.isOver && steps < 30 * 240 { game.step(playTick, world: playWorld()); steps += 1 }
        XCTAssertTrue(game.isOver, "the computer scores three in the end")
        XCTAssertEqual(game.score, 0)
    }

    func testAPlayerWhoGoesForThePuckCanBeatTheComputer() {
        var scored = 0
        for seed in [1, 2, 3, 4] as [UInt64] {
            var game = Game(size: playFrame, seed: seed)
            var t = 0.0
            while !game.isOver && t < 120 {
                // Get under the puck and push up through it; otherwise guard the goal.
                let target: CGPoint
                if game.puck.y < game.middle {
                    let behind = game.puck.y - 80 + (game.puckVelocity.y < 0 ? 0 : 60)
                    target = CGPoint(x: game.puck.x, y: max(60, behind))
                } else {
                    target = CGPoint(x: 640 + (game.puck.x - 640) * 0.5, y: 120)
                }
                game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: target)]))
                XCTAssertLessThanOrEqual(simd_length(game.puckVelocity), Game.topSpeed + 1)
                t += playTick
            }
            scored += game.goalsFor
        }
        XCTAssertGreaterThan(scored, 0)
    }

    func testTheSameSeedPlaysTheSame() {
        func trace() -> [Double] {
            var game = Game(size: playFrame, seed: 9)
            var out: [Double] = []
            for i in 0..<900 {
                game.step(playTick, world: playWorld([PlayHands.make(.open, palmAt: CGPoint(x: 640 + 300 * sin(Double(i) / 20), y: 200 + 80 * cos(Double(i) / 13)))]))
                out.append(game.puck.x + game.puck.y + game.computer.x + Double(game.score))
            }
            return out
        }
        XCTAssertEqual(trace(), trace())
    }

    func testAHugeStepDoesNotBreakIt() {
        var game = Game(size: playFrame, seed: 2)
        game.place(puck: SIMD2(640, 300), velocity: SIMD2(1500, 1500))
        game.step(30, world: playWorld([PlayHands.make(.open, palmAt: CGPoint(x: 640, y: 200))]))
        game.step(-1, world: playWorld())
        XCTAssertTrue(game.puck.x.isFinite && game.puck.y.isFinite)
        XCTAssertEqual(Game.presenceHint, "Hold up your hand to play")
    }
}

// MARK: - Beat Pads

final class HandPlayBeatPadsTests: XCTestCase {
    typealias Game = HandPlayBeatPads
    /// A hand well away from every pad.
    private let resting = PlayHands.make(.open, palmAt: CGPoint(x: 640, y: 620))

    /// Steps with the hand resting until the frame at `time`, then puts a fingertip in `pad` for that frame and a few after, then lifts it.
    private func tap(_ game: inout Game, pad: Int, at time: Double, hold: Int = 3) {
        while game.elapsed + playTick < time - 1e-9 { game.step(playTick, world: playWorld([resting])) }
        let p = game.pads[pad]
        for _ in 0..<hold { game.step(playTick, world: playWorld([PlayHands.pointing(tipAt: p)])) }
        game.step(playTick, world: playWorld([resting]))
    }

    func testTheSongIsWellFormed() {
        var rng = SplitMix64(seed: 4)
        let notes = Game.chart(&rng)
        XCTAssertTrue((80...130).contains(notes.count), "\(notes.count) notes")
        XCTAssertEqual(notes.map(\.time), notes.map(\.time).sorted())
        XCTAssertEqual(Set(notes.map(\.pad)), [0, 1, 2, 3])
        for pad in 0..<4 {
            let times = notes.filter { $0.pad == pad }.map(\.time)
            for (a, b) in zip(times, times.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 0.45, "pad \(pad): time to lift and come back") }
        }
        XCTAssertGreaterThan(notes.first?.time ?? 0, 2, "a moment to get ready")
        let together = Dictionary(grouping: notes, by: \.time).values.filter { $0.count > 1 }
        XCTAssertFalse(together.isEmpty, "some notes need both hands")
        var other = SplitMix64(seed: 5)
        XCTAssertNotEqual(Game.chart(&other).map(\.pad), notes.map(\.pad), "another seed, another song")
    }

    func testOnTheBeatIsPerfectNearlyIsGoodAndWayOffIsNothing() {
        var game = Game(size: playFrame, seed: 1)
        game.setNotes([(1, 2.0), (2, 3.0), (0, 4.0)])
        tap(&game, pad: 1, at: 2.0 + Game.latency)
        tap(&game, pad: 2, at: 3.0 + Game.latency + 0.16)
        tap(&game, pad: 0, at: 4.0 + Game.latency - 0.4)
        XCTAssertEqual(game.notes[0].judgement, .perfect)
        XCTAssertEqual(game.notes[1].judgement, .good)
        XCTAssertNil(game.notes[2].judgement, "far too early: not a hit, not a miss yet")
        XCTAssertEqual(game.score, 3 + 1)
        playFor(&game, seconds: 1, hands: [resting])
        XCTAssertEqual(game.notes[2].judgement, .miss)
        XCTAssertEqual(game.combo, 0)
    }

    func testTheWrongPadDoesNotCount() {
        var game = Game(size: playFrame, seed: 1)
        game.setNotes([(1, 2.0)])
        tap(&game, pad: 3, at: 2.0 + Game.latency)
        XCTAssertNil(game.notes[0].judgement)
        XCTAssertEqual(game.taps, 1)
    }

    func testAHandRestingInAPadTapsOnlyOnce() {
        var game = Game(size: playFrame, seed: 1)
        game.setNotes((0..<6).map { (1, 1.0 + Double($0) * 0.6) })
        let p = game.pads[1]
        for i in 0..<120 {
            // Resting on it, trembling a few pixels.
            let tip = CGPoint(x: p.x + (i % 2 == 0 ? 4 : -4), y: p.y + (i % 3 == 0 ? 3 : -3))
            game.step(playTick, world: playWorld([PlayHands.pointing(tipAt: tip)]))
        }
        XCTAssertEqual(game.taps, 1)
    }

    func testAFingerHoveringOnTheRimDoesNotDrum() {
        var game = Game(size: playFrame, seed: 1)
        game.setNotes([(1, 9)])
        let p = game.pads[1]
        let edge = Game.padRadius + 22 * 0.5
        for i in 0..<90 {
            let r = edge + (i % 2 == 0 ? -6 : 8)
            game.step(playTick, world: playWorld([PlayHands.pointing(tipAt: CGPoint(x: p.x + r, y: p.y))]))
        }
        XCTAssertLessThanOrEqual(game.taps, 1)
    }

    func testAQuickJabThroughAPadBetweenFramesCounts() {
        var game = Game(size: playFrame, seed: 1)
        game.setNotes([(2, 1.0)])
        let p = game.pads[2]
        while game.elapsed + playTick < 1.0 + Game.latency - playTick { game.step(playTick, world: playWorld([resting])) }
        game.step(playTick, world: playWorld([PlayHands.pointing(tipAt: CGPoint(x: p.x - 150, y: p.y + 40))]))
        game.step(playTick, world: playWorld([PlayHands.pointing(tipAt: CGPoint(x: p.x + 150, y: p.y - 40))]))
        XCTAssertNotNil(game.notes[0].judgement)
        XCTAssertNotEqual(game.notes[0].judgement, .miss)
    }

    func testARunOfHitsBuildsAMultiplier() {
        var game = Game(size: playFrame, seed: 1)
        game.setNotes((0..<10).map { ($0 % 4, 1.0 + Double($0) * 0.6) })
        for (k, note) in game.notes.enumerated() {
            tap(&game, pad: note.pad, at: note.time + Game.latency)
            if k == 7 { XCTAssertEqual(game.multiplier, 2) }
        }
        XCTAssertEqual(game.perfects, 10)
        XCTAssertEqual(game.score, 7 * 3 + 3 * 3 * 2, "x2 from the eighth hit in a row")
        XCTAssertEqual(game.bestCombo, 10)
    }

    func testNobodyPlayingMissesEverythingAndTheSongEnds() {
        var game = Game(size: playFrame, seed: 2)
        var steps = 0
        while !game.isOver && steps < 30 * 120 { game.step(playTick, world: playWorld([resting])); steps += 1 }
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(Double(steps) / 30, game.songLength, accuracy: 0.1)
        XCTAssertEqual(game.misses, game.notes.count)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.grade, "D")
    }

    func testAPerfectPlayerGetsAnS() {
        var game = Game(size: playFrame, seed: 3)
        while !game.isOver {
            let now = game.elapsed + playTick - Game.latency
            let due = game.notes.filter { $0.judgement == nil && abs($0.time - now) < playTick / 2 + 1e-6 }
            let hands = due.prefix(2).enumerated().map { PlayHands.pointing(tipAt: game.pads[$0.element.pad], id: $0.offset + 1) }
            game.step(playTick, world: playWorld(hands.isEmpty ? [resting] : hands))
        }
        XCTAssertEqual(game.misses, 0)
        XCTAssertGreaterThanOrEqual(game.accuracy, 0.95)
        XCTAssertEqual(game.grade, "S")
    }

    func testAHugeStepDoesNotBreakIt() {
        var game = Game(size: playFrame, seed: 2)
        game.step(30, world: playWorld([resting]))
        game.step(-1, world: playWorld())
        XCTAssertFalse(game.isOver, "one step cannot eat the song")
        XCTAssertEqual(Game.presenceHint, "Hold up your hand to play")
    }
}

// MARK: - Hand Simon

final class HandPlaySimonTests: XCTestCase {
    typealias Game = HandPlaySimon
    private let at = CGPoint(x: 330, y: 330)

    private func hand(_ pose: HandPlayPose, id: Int = 1) -> HandState {
        let fingers: HandFixtures.Fingers
        switch pose {
        case .fist: fingers = .fist
        case .open: fingers = .open
        case .peace: fingers = .peace
        case .point: fingers = .point
        case .thumbsUp: fingers = PlayHands.thumbsUp
        }
        return PlayHands.make(fingers, palmAt: at, id: id)
    }

    private func toTurn(_ game: inout Game) {
        var guardCount = 0
        while game.stage != .turn && guardCount < 3000 { game.step(playTick, world: playWorld()); guardCount += 1 }
    }

    private func show(_ game: inout Game, _ pose: HandPlayPose, seconds: Double = 0.5) { playFor(&game, seconds: seconds, hands: [hand(pose)]) }

    func testRunsNeverRepeatAShapeBackToBack() {
        var rng = SplitMix64(seed: 3)
        var last: HandPlayPose?
        var seen = Set<HandPlayPose>()
        for _ in 0..<300 {
            let next = Game.next(after: last, using: &rng)
            XCTAssertNotEqual(next, last)
            seen.insert(next)
            last = next
        }
        XCTAssertEqual(seen.count, 5)
        let game = Game(size: playFrame, seed: 1)
        XCTAssertEqual(game.sequence.count, 2)
        XCTAssertNotEqual(game.sequence[0], game.sequence[1])
    }

    func testTheRunIsShownThenItIsYourTurn() {
        var game = Game(size: playFrame, seed: 1)
        var stages: [Game.Stage] = []
        for _ in 0..<300 {
            game.step(playTick, world: playWorld([hand(.open)]))
            if stages.last != game.stage { stages.append(game.stage) }
            if game.stage == .turn { break }
        }
        XCTAssertEqual(stages, [.ready, .show(0), .gap(0), .show(1), .turn])
    }

    func testCopyingTheRunWinsTheRoundAndTheRunGrows() {
        var game = Game(size: playFrame, seed: 1)
        game.setSequence([.fist, .peace])
        toTurn(&game)
        show(&game, .fist)
        XCTAssertEqual(game.step, 1)
        show(&game, .peace)
        XCTAssertEqual(game.stage, .success)
        XCTAssertEqual(game.score, 2 + 2, "a point a shape, and two for the round")
        playFor(&game, seconds: 1.5)
        XCTAssertEqual(game.round, 2)
        XCTAssertEqual(game.sequence.count, 3)
        XCTAssertEqual(Array(game.sequence.prefix(2)), [.fist, .peace], "the same run, one longer")
    }

    func testHoldingAWrongShapeCostsAHeartAndShowsTheRunAgain() {
        var game = Game(size: playFrame, seed: 1)
        game.setSequence([.fist, .peace])
        toTurn(&game)
        show(&game, .open, seconds: 1.2)
        XCTAssertEqual(game.stage, .mistake)
        XCTAssertEqual(game.lives, 2)
        XCTAssertFalse(game.tooSlow)
        playFor(&game, seconds: 2)
        XCTAssertEqual(game.stage, .ready)
        XCTAssertEqual(game.sequence, [.fist, .peace], "the same run again")
    }

    func testPassingThroughOtherShapesOnTheWayIsFine() {
        var game = Game(size: playFrame, seed: 1)
        game.setSequence([.fist, .peace])
        toTurn(&game)
        show(&game, .point, seconds: 0.4)
        show(&game, .open, seconds: 0.3)
        show(&game, .fist)
        XCTAssertEqual(game.step, 1)
        XCTAssertEqual(game.lives, 3)
    }

    func testTheShapeYouJustMadeIsNotWrongWhileYouChange() {
        var game = Game(size: playFrame, seed: 1)
        game.setSequence([.fist, .open])
        toTurn(&game)
        show(&game, .fist, seconds: 2.5)
        XCTAssertEqual(game.step, 1)
        XCTAssertEqual(game.lives, 3, "still holding the fist you were asked for")
        show(&game, .open)
        XCTAssertEqual(game.stage, .success)
    }

    func testAFlickeringHandStillCounts() {
        var game = Game(size: playFrame, seed: 1)
        game.setSequence([.thumbsUp, .peace])
        toTurn(&game)
        for i in 0..<40 { game.step(playTick, world: playWorld(i % 3 == 0 ? [] : [hand(.thumbsUp)])) }
        XCTAssertEqual(game.step, 1, "a thumbs up seen two frames in three")
    }

    func testTakingTooLongCostsAHeart() {
        var game = Game(size: playFrame, seed: 1)
        toTurn(&game)
        playFor(&game, seconds: Game.stepTimeout + 0.3)
        XCTAssertEqual(game.stage, .mistake)
        XCTAssertTrue(game.tooSlow)
        XCTAssertEqual(game.lives, 2)
    }

    func testThreeMistakesEndTheGame() {
        var game = Game(size: playFrame, seed: 1)
        game.setSequence([.fist, .peace])
        for _ in 0..<3 {
            toTurn(&game)
            show(&game, .open, seconds: 1.2)
        }
        XCTAssertEqual(game.lives, 0)
        XCTAssertFalse(game.isOver, "the last mistake is shown first")
        playFor(&game, seconds: 2.5)
        XCTAssertTrue(game.isOver)
        XCTAssertFalse(game.won)
    }

    func testAPerfectPlayerWinsAllTenRounds() {
        var game = Game(size: playFrame, seed: 6)
        var guardCount = 0
        while !game.isOver && guardCount < 30 * 600 {
            game.step(playTick, world: playWorld(game.target.map { [hand($0)] } ?? []))
            guardCount += 1
        }
        XCTAssertTrue(game.won)
        XCTAssertEqual(game.lives, 3)
        XCTAssertEqual(game.round, Game.rounds)
        XCTAssertEqual(game.score, (2...11).reduce(0) { $0 + $1 + 2 })
    }

    func testTheSameSeedGivesTheSameRuns() {
        func runs(_ seed: UInt64) -> [HandPlayPose] {
            var game = Game(size: playFrame, seed: seed)
            for _ in 0..<(30 * 40) { game.step(playTick, world: playWorld(game.target.map { [hand($0)] } ?? [])) }
            return game.sequence
        }
        XCTAssertEqual(runs(3), runs(3))
        XCTAssertNotEqual(runs(3), runs(4))
    }

    func testAHugeStepDoesNotBreakIt() {
        var game = Game(size: playFrame, seed: 2)
        game.step(30, world: playWorld([hand(.open)]))
        game.step(-1, world: playWorld())
        XCTAssertGreaterThanOrEqual(game.lives, 0)
        XCTAssertEqual(Game.presenceHint, "Hold up your hand to play")
    }
}

// MARK: - As lenses

final class HandPlayLensTests: XCTestCase {
    private let h = LensHarness()

    func testTheSixAreInTheCatalogAsHandGames() {
        let expected = [("magic-duel", "Magic Duel"), ("beat-pads", "Beat Pads"), ("air-hockey", "Air Hockey"), ("palm-star-catcher", "Star Catcher"),
                        ("hand-simon", "Hand Simon"), ("palm-juggle", "Juggle")]
        XCTAssertEqual(HandGamesMore.all.map(\.id), expected.map(\.0))
        for (id, name) in expected {
            guard let info = LensCatalog.info(for: id) else { XCTFail("missing \(id)"); continue }
            XCTAssertEqual(info.name, name)
            XCTAssertEqual(info.category, .games)
            XCTAssertTrue(info.needsHands)
            XCTAssertFalse(info.needsFace)
            XCTAssertTrue(info.scored)
            XCTAssertEqual(info.glyph.count, 1, "one emoji")
            XCTAssertLessThan(info.blurb.count, 90, info.blurb)
            let lens = info.make()
            XCTAssertEqual(lens.needs, [.hands], "\(id) plays with hands alone")
        }
    }

    private func checkLifecycle<G: Game>(_ type: G.Type, file: StaticString = #filePath, line: UInt = #line) {
        let lens = GameLens<G>(id: "test.\(G.title)", needs: [.hands], store: MemoryScoreStore())
        let base = h.input()
        var t = 0.0
        var last = base.composed
        func play(_ seconds: Double, _ hands: [HandState]) {
            let end = t + seconds
            while t < end { last = lens.render(h.at(base, time: t, hands: hands)); t += playTick }
        }
        let hand = PlayHands.make(.open, palmAt: CGPoint(x: 400, y: 330))
        play(1.2, [])
        XCTAssertEqual(lens.phase, .waiting, "no hand, no game", file: file, line: line)
        XCTAssertEqual(lens.status?.title, "Hold up your hand to play", file: file, line: line)
        play(0.8, [hand])
        guard case .countdown = lens.phase else { return XCTFail("a hand starts the countdown, got \(lens.phase)", file: file, line: line) }
        play(GameLens<G>.countdownSeconds + 0.3, [hand])
        XCTAssertEqual(lens.phase, .playing, file: file, line: line)
        XCTAssertEqual(last.extent, base.rect, file: file, line: line)
        play(GameLens<G>.absenceGrace + 1.5, [])
        XCTAssertEqual(lens.phase, .playing, "waiting for you", file: file, line: line)
        let paused = lens.game.summary
        play(1, [])
        XCTAssertEqual(lens.game.summary, paused, "the clock stops while you are away", file: file, line: line)
        play(0.5, [hand])
        XCTAssertEqual(last.extent, base.rect, file: file, line: line)
        XCTAssertLessThan(lens.status?.title.count ?? 99, 40, file: file, line: line)
    }

    func testEachGameWaitsCountsDownPlaysAndPausesWithoutHands() {
        checkLifecycle(HandPlayMagicDuel.self)
        checkLifecycle(HandPlayBeatPads.self)
        checkLifecycle(HandPlayAirHockey.self)
        checkLifecycle(HandPlayStarCatcher.self)
        checkLifecycle(HandPlaySimon.self)
        checkLifecycle(HandPlayJuggle.self)
    }

    func testEachGameRendersWithAndWithoutAPersonHandsOrAMatte() {
        for info in HandGamesMore.all {
            for background in [true, false] {
                let lens = info.make()
                lens.restart()
                var out: CIImage?
                for scene in [SyntheticScene(), SyntheticScene(center: CGPoint(x: 300, y: 300), scale: 0.6)] {
                    let base = h.input(scene, background: background, wantsGrid: false)
                    for i in 0..<(30 * 6) {
                        let fingers: HandFixtures.Fingers = [.open, .fist, .point, .peace][i / 20 % 4]
                        let hands = i % 50 < 35 ? [PlayHands.make(fingers, palmAt: CGPoint(x: 300 + Double(i % 70) * 10, y: 280))] : []
                        out = lens.render(h.at(base, time: Double(i) / 30, hands: hands))
                    }
                }
                XCTAssertEqual(out?.extent, CGRect(origin: .zero, size: SyntheticScene.size), "\(info.id) background \(background)")
            }
            // Nobody there at all: no person, no matte, no hands.
            let lens = info.make()
            let base = h.input()
            let lonely = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: nil, composed: base.camera,
                                   matteGrid: nil, face: nil, services: base.services)
            XCTAssertEqual(lens.render(lonely).extent.width, 1280, info.id)
        }
    }

    /// What each game's drawing costs, on its own: the best of a few runs, because the machine running the tests is often busy.
    func testEachGameDrawsInAFewMilliseconds() {
        let services = h.services
        let hands = [PlayHands.make(.open, palmAt: CGPoint(x: 400, y: 300)), PlayHands.make(.fist, palmAt: CGPoint(x: 880, y: 260), id: 2)]
        func cost<G: Game>(_ game: G) -> Double {
            _ = services.overlay { game.draw(in: $0, time: 1) }
            var best = Double.infinity
            for _ in 0..<4 {
                let started = CFAbsoluteTimeGetCurrent()
                for _ in 0..<10 { _ = services.overlay { game.draw(in: $0, time: 1) } }
                best = min(best, (CFAbsoluteTimeGetCurrent() - started) * 100)
            }
            return best
        }
        func warmed<G: Game>(_ game: G, seconds: Double) -> G {
            var g = game
            playFor(&g, seconds: seconds, hands: hands)
            return g
        }
        let costs: [(String, Double)] = [
            ("magic-duel", cost(warmed(HandPlayMagicDuel(size: playFrame, seed: 1), seconds: 25))),
            ("beat-pads", cost(warmed(HandPlayBeatPads(size: playFrame, seed: 1), seconds: 20))),
            ("air-hockey", cost(warmed(HandPlayAirHockey(size: playFrame, seed: 1), seconds: 20))),
            ("palm-star-catcher", cost(warmed(HandPlayStarCatcher(size: playFrame, seed: 1), seconds: 20))),
            ("hand-simon", cost(warmed(HandPlaySimon(size: playFrame, seed: 1), seconds: 4))),
            ("palm-juggle", cost(warmed(HandPlayJuggle(size: playFrame, seed: 1), seconds: 3))),
        ]
        for (id, ms) in costs {
            print("HandPlay draw \(id): \(String(format: "%.2f", ms)) ms")
            XCTAssertLessThan(ms, 4, id)
        }
    }

    func testEachLensCostsLittleThroughThePipeline() {
        let base = h.input()
        for info in HandGamesMore.all {
            let lens = info.make()
            lens.restart()
            let hands = [PlayHands.make(.open, palmAt: CGPoint(x: 400, y: 300)), PlayHands.make(.fist, palmAt: CGPoint(x: 880, y: 260), id: 2)]
            for i in 0..<(30 * 12) { _ = lens.render(h.at(base, time: Double(i) / 30, hands: hands)) }
            let stopwatch = h.cost(of: lens, base: h.at(base, time: 0, hands: hands))
            print("HandPlay pipeline \(info.id): mean \(String(format: "%.2f", stopwatch.mean)) ms")
            // Generous: this includes compositing the whole frame, and the test machine is shared.
            XCTAssertLessThan(stopwatch.mean, 20, "\(info.id): \(stopwatch)")
        }
    }

    func testTheFirstPlayingFrameDoesNotHitch() {
        // Each game paints its pictures the first time it draws them. Counted from an empty cache, so the check does not depend on how
        // busy the machine is: a handful on the first frame, and only a few at a time after that.
        let services = h.services
        let hands = [PlayHands.make(.open, palmAt: CGPoint(x: 400, y: 300)), PlayHands.make(.fist, palmAt: CGPoint(x: 880, y: 260), id: 2)]
        func check<G: Game>(_ make: () -> G, _ id: String) {
            HandPlaySprites.removeAll()
            var game = make()
            var firstBakes = 0, mostBakes = 0, firstMs = 0.0
            for i in 0..<(30 * 6) {
                game.step(playTick, world: playWorld(hands))
                let before = HandPlaySprites.baked, started = CFAbsoluteTimeGetCurrent()
                _ = services.overlay { game.draw(in: $0, time: Double(i) / 30) }
                let bakes = HandPlaySprites.baked - before
                if i == 0 {
                    firstBakes = bakes
                    firstMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
                } else {
                    mostBakes = max(mostBakes, bakes)
                }
            }
            print("HandPlay first frame \(id): \(firstBakes) pictures, \(String(format: "%.1f", firstMs)) ms; at most \(mostBakes) in a later frame")
            XCTAssertLessThanOrEqual(firstBakes, 24, id)
            XCTAssertLessThanOrEqual(mostBakes, 10, id)
            XCTAssertLessThan(firstMs, 250, "\(id): a backstop only; the machine is shared")
        }
        check({ HandPlayMagicDuel(size: playFrame, seed: 1) }, "magic-duel")
        check({ HandPlayBeatPads(size: playFrame, seed: 1) }, "beat-pads")
        check({ HandPlayAirHockey(size: playFrame, seed: 1) }, "air-hockey")
        check({ HandPlayStarCatcher(size: playFrame, seed: 1) }, "palm-star-catcher")
        check({ HandPlaySimon(size: playFrame, seed: 1) }, "hand-simon")
        check({ HandPlayJuggle(size: playFrame, seed: 1) }, "palm-juggle")
    }
}

// MARK: - Tracking drop-outs

final class HandPlayDropoutTests: XCTestCase {
    func testAFistThatDropsOutForAFrameKeepsTheShieldUp() {
        var game = HandPlayMagicDuel(size: playFrame, seed: 1)
        game.pauseSpawns()
        let fist = PlayHands.make(.fist, palmAt: CGPoint(x: 300, y: 200))
        playFor(&game, seconds: 0.3, hands: [fist])
        for i in 0..<30 {
            game.step(playTick, world: playWorld(i % 5 == 2 ? [] : [fist]))
            XCTAssertTrue(game.shieldUp, "frame \(i)")
        }
    }

    func testAHandRestingInAPadThatFlickersDoesNotDrum() {
        var game = HandPlayBeatPads(size: playFrame, seed: 1)
        game.setNotes([(1, 9)])
        let tip = PlayHands.pointing(tipAt: game.pads[1])
        for i in 0..<90 { game.step(playTick, world: playWorld(i % 6 == 3 ? [] : [tip])) }
        XCTAssertEqual(game.taps, 1)
    }

    func testABallStillBouncesOffAHandLostForAFrame() {
        var game = HandPlayJuggle(size: playFrame, seed: 1)
        game.place(ballAt: SIMD2(640, 480), velocity: SIMD2(0, -300))
        let hand = PlayHands.make(.open, palmAt: CGPoint(x: 640, y: 280))
        // Seen, then lost for the frames when the ball arrives.
        playFor(&game, seconds: 0.2, hands: [hand])
        var guardCount = 0
        while game.hits == 0 && guardCount < 30 { game.step(playTick, world: playWorld([])); guardCount += 1 }
        XCTAssertEqual(game.hits, 1)
        XCTAssertLessThan(guardCount, 8)
    }
}
