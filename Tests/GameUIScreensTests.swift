import CoreImage
import XCTest

private let gameUIFrame = CGSize(width: 1280, height: 720)

/// The shared game screens: what they show by default, how the runner picks who to wait for, that every screen keeps inside the 5%
/// border and off the player's face, and that the plates cost well under a millisecond and bake nothing once play has begun.
final class GameUIScreensTests: XCTestCase {
    private let h = LensHarness()

    /// A game with none of the screen hooks: everything comes from the defaults.
    struct GameUIPlain: Game {
        static let title = "Plain"
        static let hint = "Do the thing. Then do it again."
        var score = 0
        var isOver: Bool { score >= 3 }
        var summary: String { "Lives 2" }
        init(size: CGSize, seed: UInt64) {}
        mutating func step(_ dt: Double, world: GameWorld) { score += 1 }
        func draw(in ctx: CGContext, time: Double) {}
    }

    /// A game that ends at once, as a win or when the clock ran out, depending on its seed.
    struct GameUIEnding: Game {
        static let title = "Ending"
        static let hint = "Wait"
        let won: Bool
        var score = 7
        var isOver = false
        var summary: String { "" }
        init(size: CGSize, seed: UInt64) { won = seed % 2 == 0 }
        var result: GameUIResult { GameUIResult(headline: won ? "You win!" : "Time's up!", kind: won ? .won : .timeUp) }
        mutating func step(_ dt: Double, world: GameWorld) { isOver = true }
        func draw(in ctx: CGContext, time: Double) {}
    }

    private func look(_ player: GameUIPlayer = .body, icon: GameUIIcon = .body) -> GameScreens.Look {
        GameScreens.Look(title: "Hole in the Wall", hint: HoleInTheWallGame.hint, presenceHint: "Step into the frame to play", accent: GameUIPalette.sky,
                         icon: icon, scoreLabel: "SCORE", player: player)
    }

    // MARK: Defaults

    func testAGameWithNoHooksGetsSensibleScreens() {
        var game = GameUIPlain(size: gameUIFrame, seed: 1)
        game.step(0.1, world: GameWorld(size: gameUIFrame, matte: nil, motion: nil, face: nil))
        XCTAssertEqual(game.readout.score, 1)
        XCTAssertEqual(game.readout.label, "Lives 2", "the summary goes in the status plate")
        XCTAssertNil(game.readout.lives)
        XCTAssertEqual(game.result.headline, "Game over")
        XCTAssertEqual(game.result.line, "Lives 2")
        XCTAssertEqual(game.result.kind, .lost)
        XCTAssertEqual(GameUIPlain.onboarding, ["Do the thing.", "Then do it again."], "the hint, a sentence at a time")
        XCTAssertEqual(GameUIPlain.icon, .automatic)
        XCTAssertEqual(GameUIPlain.scoreLabel, "SCORE")
        XCTAssertEqual(GameUIPlain.scoreText(12), "12")
        XCTAssertFalse(GameUIPlain.warmUp(0))
    }

    func testFaceGamesFillTheScreensFromTheirChipsAndEndings() {
        let catcher = MouthCatchGame(size: gameUIFrame, seed: 1)
        let readout = catcher.readout
        XCTAssertEqual(readout.time?.of, MouthCatchGame.roundSeconds)
        XCTAssertEqual(readout.time?.left, MouthCatchGame.roundSeconds)
        XCTAssertEqual(catcher.result.kind, .timeUp)
        XCTAssertEqual(MouthCatchGame.icon, .face(.openMouth))
        XCTAssertTrue(MouthCatchGame.onboarding.isEmpty, "face games teach with a live tip instead")
        let staring = StaringContestGame(size: gameUIFrame, seed: 1)
        XCTAssertEqual(staring.readout.time?.of, StaringContestGame.winSeconds)
        XCTAssertEqual(StaringContestGame.scoreText(123), "12.3 s")
    }

    func testEveryCatalogGameHasItsOwnColourAndShortScreens() {
        for info in LensCatalog.games where info.scored {
            guard let lens = info.make() as? LensBrowserGameLike else { return XCTFail("\(info.id) does not run through GameLens") }
            XCTAssertNotNil(lens, info.id)
        }
        let accents: [SIMD3<Double>] = [BalloonGame.accent, BreakoutGame.accent, MeteorDodgeGame.accent, HoleInTheWallGame.accent, BubbleWrapGame.accent,
                                        KeepyUppyGame.accent, LaserLimboGame.accent, PunchingBagGame.accent, GoalkeeperGame.accent, NinjaStarsGame.accent,
                                        HandPlayMagicDuel.accent, HandPlayBeatPads.accent, HandPlayAirHockey.accent, HandPlayStarCatcher.accent,
                                        HandPlaySimon.accent, HandPlayJuggle.accent]
        for accent in accents { XCTAssertNotEqual(accent, GameUIPalette.gold * 0, "a colour, not black") }
        for line in BalloonGame.onboarding + HandPlayStarCatcher.onboarding + FruitSlashGame.onboarding {
            XCTAssertLessThan(GameUIType.width(line, size: 25, weight: .bold), 1280 - 64 * 2 - 104, line)
        }
    }

    // MARK: The runner

    func testTheRunnerWaitsForWhatTheGameIsPlayedWith() {
        XCTAssertEqual(GameLens<GameUIPlain>(id: "t", needs: [.matte], store: MemoryScoreStore()).player, .body)
        XCTAssertEqual(GameLens<GameUIPlain>(id: "t", needs: [.hands], store: MemoryScoreStore()).player, .hands)
        XCTAssertEqual(HandGameLens<FruitSlashGame>(id: "t", needs: [.hands, .matte], store: MemoryScoreStore()).player, .hands)
        XCTAssertEqual(FaceGameLens<MouthCatchGame>(id: "t", store: MemoryScoreStore()).player, .face)
        XCTAssertEqual(FaceGameLens<MouthCatchGame>.settleSeconds, 0.6)
        XCTAssertEqual(HandGameLens<FruitSlashGame>.countdownSeconds, GameLens<GameUIPlain>.countdownSeconds)
    }

    func testTheStatusLineSaysHowTheRoundEnded() {
        let base = h.input(wantsGrid: false)
        for (seed, title) in [(UInt64(2), "You win! 7"), (UInt64(3), "Time's up: 7")] {
            let lens = GameLens<GameUIEnding>(id: "t.end", needs: [.hands], store: MemoryScoreStore(), make: { size, _ in GameUIEnding(size: size, seed: seed) })
            lens.restart()
            var time = 0.0
            while time < GameLens<GameUIEnding>.countdownSeconds + 0.3 {
                _ = lens.render(h.at(base, time: time, hands: [HandFixtures.hand(.open)]))
                time += 1.0 / 30
            }
            XCTAssertEqual(lens.status?.title, title)
            XCTAssertEqual(lens.status?.detail, "New best!")
        }
    }

    func testTheOpeningHintsComeAfterGoAndThePauseTakesOverWhenThePlayerLeaves() throws {
        let lens = GameLens<BalloonGame>(id: "t.balloon", needs: [.matte], store: MemoryScoreStore())
        let base = h.input()
        lens.restart()
        var time = 0.0
        func run(_ seconds: Double, present: Bool) -> CIImage {
            var out = base.composed
            let end = time + seconds
            while time < end {
                var input = h.at(base, time: time)
                if !present {
                    input = LensInput(time: time, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                                      composed: base.composed, matteGrid: nil, face: nil, services: base.services)
                }
                out = lens.render(input)
                time += 1.0 / 30
            }
            return out
        }
        _ = run(GameLens<BalloonGame>.countdownSeconds + 1.5, present: true)
        XCTAssertEqual(lens.phase, .playing)
        let hinting = h.bitmap(run(0.1, present: true))
        let away = h.bitmap(run(GameLens<BalloonGame>.absenceGrace + 0.6, present: false))
        let band = CGRect(x: 420, y: 40, width: 440, height: 52)
        XCTAssertGreaterThan(hinting.change(from: h.bitmap(base.composed), in: band), 20, "a hint along the bottom")
        XCTAssertGreaterThan(away.change(from: h.bitmap(base.composed), in: band), 20, "the pause, low in the picture")
        XCTAssertEqual(lens.phase, .playing, "paused, not ended")
    }

    // MARK: Where the screens go

    /// Draws one screen on its own and returns its layer.
    private func layer(_ draw: @escaping (CGContext) -> Void) throws -> Bitmap {
        let image = try XCTUnwrap(h.services.overlay(draw))
        return h.bitmap(image)
    }

    /// How many sampled pixels of a layer are drawn on (clearly, not a faint shadow) where `inside` says, in picture coordinates
    /// (origin bottom left, y up).
    private func drawn(_ bits: Bitmap, where inside: (Int, Int) -> Bool) -> Int {
        var count = 0
        for y in stride(from: 0, to: bits.height, by: 2) {
            for x in stride(from: 0, to: bits.width, by: 2) where inside(x, y) {
                if bits.bytes[((bits.height - 1 - y) * bits.width + x) * 4 + 3] > 40 { count += 1 }
            }
        }
        return count
    }

    func testEveryScreenKeepsInsideTheBorderAndOffTheFace() throws {
        let look = look()
        let face = SyntheticScene().face().rect.insetBy(dx: 12, dy: 18)
        var motion = GameUIMotion()
        let readout = GameUIReadout(score: 98765, lives: (1, 5), time: (4.2, 60), combo: 4, label: "Round 10/10")
        motion.step(0.1, readout: readout, record: true)
        let screens: [(String, (CGContext) -> Void)] = [
            ("waiting", { GameScreens.waiting($0, size: gameUIFrame, look: look, progress: 0.6, best: "1234", age: 2, time: 1) }),
            ("countdown", { GameScreens.countdown($0, size: gameUIFrame, look: look, remaining: 1.4, total: 3, time: 1) }),
            ("go", { GameScreens.go($0, size: gameUIFrame, look: look, age: 0.15, time: 1) }),
            ("plates", { GameScreens.plates($0, size: gameUIFrame, look: look, readout: readout, scoreText: "98765", best: "120", record: true, motion: motion, time: 1) }),
            ("pill", { GameScreens.pill($0, size: gameUIFrame, text: "Swing your arms right through the balloons", look: look, alpha: 1, time: 1) }),
            ("paused", { GameScreens.paused($0, size: gameUIFrame, look: look, age: 1, time: 1) }),
            ("result", { GameScreens.result($0, size: gameUIFrame, look: look, result: GameUIResult(headline: "Out of lives", line: "Copy the little figures: they show the pose",
                                                                                                    stats: [("12", "walls"), ("3", "smashed"), ("450", "points")]),
                                            score: 450, scoreText: { "\($0)" }, best: "300", newBest: false, age: 2, total: 6, time: 1, shaded: false) }),
            ("won", { GameScreens.result($0, size: gameUIFrame, look: look, result: GameUIResult(headline: "You win!", kind: .won), score: 30, scoreText: { "\($0)" },
                                         best: nil, newBest: false, age: 5, total: 6, time: 1, shaded: false) }),
            ("callout", { GameScreens.callout($0, size: gameUIFrame, text: "LAST ROUND", age: 0.5) }),
            ("prompt", { GameScreens.prompt($0, size: gameUIFrame, text: "WATCH") }),
        ]
        for (name, draw) in screens {
            let bits = try layer(draw)
            XCTAssertEqual(drawn(bits) { x, y in x < 40 || x > 1240 || y < 20 || y > 700 }, 0, "\(name) keeps inside the border")
            XCTAssertEqual(drawn(bits) { x, y in face.contains(CGPoint(x: x, y: y)) }, 0, "\(name) stays off the face")
            XCTAssertGreaterThan(drawn(bits) { _, _ in true }, 100, "\(name) shows something")
        }
    }

    func testScreensSitLowOrInTheCorners() throws {
        let look = look(.hands, icon: .hand(.open))
        // The cards stay in the lower third; the plates stay in the top corners and leave the middle of the top free for call-outs.
        let cards = try layer {
            GameScreens.countdown($0, size: gameUIFrame, look: look, remaining: 2.5, total: 3, time: 0)
        }
        XCTAssertEqual(drawn(cards) { _, y in y > 250 }, 0, "the countdown card is low")
        let plates = try layer {
            GameScreens.plates($0, size: gameUIFrame, look: look, readout: GameUIReadout(score: 12, lives: (3, 3)), scoreText: "12", best: "40", record: false,
                               motion: GameUIMotion(), time: 0)
        }
        let band = Int(GameScreens.topBand(gameUIFrame)) - 20
        XCTAssertEqual(drawn(plates) { _, y in y < band }, 0, "the plates keep to the top band")
        XCTAssertEqual(drawn(plates) { x, _ in x > 420 && x < 860 }, 0, "and to the corners")
    }

    // MARK: Cost

    func testThePlatesCostWellUnderAMillisecondAndBakeNothingDuringPlay() throws {
        let look = look()
        var step = 0
        while GameScreens.warmUp(step, look: look) { step += 1 }
        var motion = GameUIMotion()
        // One round of play: the score climbing, the clock running down, a life lost, a combo, a label that counts.
        func readout(_ i: Int) -> GameUIReadout {
            GameUIReadout(score: i * 7, lives: (3 - i / 60, 3), time: (60 - Double(i) / 30, 60), combo: 1 + i / 40, label: "Wave \(1 + i / 30)")
        }
        _ = h.services.overlay { ctx in
            for i in [0, 89] { GameScreens.plates(ctx, size: gameUIFrame, look: look, readout: readout(i), scoreText: "\(i * 7)", best: "100", record: false, motion: motion, time: 0) }
        }
        let before = GameUISprites.baked
        var times: [Double] = []
        for i in 0..<180 {
            let r = readout(i)
            motion.step(1.0 / 30, readout: r, record: i > 90)
            let started = CFAbsoluteTimeGetCurrent()
            _ = h.services.overlay { ctx in
                GameScreens.plates(ctx, size: gameUIFrame, look: look, readout: r, scoreText: "\(r.score)", best: "100", record: i > 90, motion: motion,
                                   time: Double(i) / 30)
            }
            times.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        let empty: Double = {
            var t: [Double] = []
            for _ in 0..<60 {
                let started = CFAbsoluteTimeGetCurrent()
                _ = h.services.overlay { _ in }
                t.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
            }
            return t.sorted()[30]
        }()
        let median = times.sorted()[90] - empty
        print(String(format: "GAMEUI plates: median %.3f ms over an empty overlay, %d pictures baked during play", median, GameUISprites.baked - before))
        if GameUISprites.baked > before { print("GAMEUI baked during play: " + GameUISprites.recent.suffix(GameUISprites.baked - before).joined(separator: " ; ")) }
        XCTAssertLessThan(median, 1, "the plates cost well under a millisecond")
        XCTAssertLessThanOrEqual(GameUISprites.baked - before, 2, "a running score, clock and label bake (almost) nothing")
    }

    func testTheFirstFramesOfAGameDoNotStall() {
        let base = h.input()
        let lens = GameLens<NinjaStarsGame>(id: "t.first", needs: [.matte], store: MemoryScoreStore())
        var slowest = 0.0
        for i in 0..<(30 * 5) {
            let started = CFAbsoluteTimeGetCurrent()
            _ = lens.render(h.at(base, time: Double(i) / 30))
            slowest = max(slowest, (CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        print(String(format: "GAMEUI slowest of the first frames: %.1f ms", slowest))
        XCTAssertEqual(lens.phase, .playing)
        XCTAssertLessThan(slowest, 60, "no stall while the screens bake their pictures")
    }
}
