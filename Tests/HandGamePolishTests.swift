import CoreImage
import simd
import XCTest

private let polishFrame = CGSize(width: 1280, height: 720)
private let polishTick = 1.0 / 30

/// Pictures of every hand game in each of its screens, and of their sprites, for looking at (BACKDROP_TEST_OUTPUT), with checks
/// that each screen draws something and stays inside the picture.
final class HandGamePolishPictures: XCTestCase {
    private let h = LensHarness()

    private func world(_ hands: [HandState]) -> GameWorld { GameWorld(size: polishFrame, matte: nil, motion: nil, face: nil, hands: hands) }

    /// An open hand placed by its palm.
    private func open(at p: CGPoint, size: Double = 110, id: Int = 1) -> HandState {
        let base = HandFixtures.hand(.open, at: .zero, size: size, id: id)
        return HandFixtures.moved(base, by: CGVector(dx: p.x - base.palm.x, dy: p.y - base.palm.y))
    }

    /// Runs a lens through waiting, countdown, play and game over, saving a picture of each.
    private func screens<G: HandGameScreens>(_ type: G.Type, name: String, hands: [HandState], playFor: Double = 0.5,
                                             during: ((Double) -> [HandState])? = nil, make: @escaping (CGSize, UInt64) -> G) throws {
        let lens = HandGameLens<G>(id: "pic.\(name)", needs: [.hands], store: MemoryScoreStore(), make: make)
        let base = h.input(SyntheticScene(center: CGPoint(x: 640, y: 440)), wantsGrid: false)
        var time = 0.0
        var out = base.composed
        func play(_ seconds: Double, _ hands: [HandState]) {
            let end = time + seconds
            while time < end {
                out = lens.render(h.at(base, time: time, hands: hands))
                time += polishTick
            }
        }
        play(0.8, [])
        Output.save(out, as: "\(name)-1-waiting.png")
        XCTAssertEqual(lens.phase, .waiting)
        play(1.4, hands)
        Output.save(out, as: "\(name)-2-countdown.png")
        play(HandGameLens<G>.countdownSeconds, hands)
        if let during {
            let end = time + playFor
            while time < end {
                out = lens.render(h.at(base, time: time, hands: during(time)))
                time += polishTick
            }
        } else {
            play(playFor, hands)
        }
        Output.save(out, as: "\(name)-3-playing.png")
        XCTAssertEqual(lens.phase, .playing)
        XCTAssertEqual(out.extent, base.rect)
        var guardSteps = 0
        while lens.phase == .playing && guardSteps < 30 * 400 {
            out = lens.render(h.at(base, time: time, hands: hands))
            time += polishTick
            guardSteps += 1
        }
        play(1.2, hands)
        Output.save(out, as: "\(name)-4-over.png")
        if case .over = lens.phase {} else { XCTFail("\(name) reached \(lens.phase), not the end") }
    }

    /// A hand swung to and fro across the picture, a blade's worth of speed.
    private func swinging(_ t: Double) -> [HandState] {
        let x = 640 + 420 * sin(t * 5), y = 380 + 120 * cos(t * 3.3)
        let base = HandFixtures.hand(.open, at: .zero, size: 100)
        return [HandFixtures.moved(base, by: CGVector(dx: x - base.leadTip.x, dy: y - base.leadTip.y), velocity: CGVector(dx: 2100 * cos(t * 5), dy: -400 * sin(t * 3.3)),
                                   tipVelocity: CGVector(dx: 2100 * cos(t * 5), dy: -400 * sin(t * 3.3)))]
    }

    func testFruitSlashScreens() throws {
        try screens(FruitSlashGame.self, name: "fruit", hands: [open(at: CGPoint(x: 380, y: 260))], playFor: 0.45, during: swinging, make: { size, _ in
            var game = FruitSlashGame(size: size, seed: 4)
            for (i, x) in [200.0, 400, 620, 840, 1060].enumerated() { game.launch(i == 3 ? .bomb : .fruit(i * 2 + 1), from: x, apex: 560 + Double(i % 2) * 50) }
            for _ in 0..<16 { game.step(polishTick, world: GameWorld(size: size, matte: nil, motion: nil, face: nil, hands: [])) }
            return game
        })
    }

    func testFruitSheet() throws {
        let base = h.input(SyntheticScene(center: CGPoint(x: 640, y: 440)), background: true, wantsGrid: false)
        let layer = try XCTUnwrap(h.services.overlay { ctx in
            for n in 0..<FruitSlashGame.kinds.count {
                let x = 110 + Double(n) * 150
                FruitSlashGame.drawFruit(FruitSlashGame.Fruit(position: SIMD2(x, 560), velocity: .zero, radius: 52 * FruitSlashArt.art(n).scale, angle: 0,
                                                              spin: 0, kind: .fruit(n)), in: ctx, time: 0)
                for side in [-1.0, 1.0] {
                    FruitSlashGame.drawHalf(FruitSlashGame.Half(position: SIMD2(x + side * 24, 330 + side * 40), velocity: .zero, angle: 0.3, spin: 0,
                                                                radius: 52 * FruitSlashArt.art(n).scale, kind: n, cut: 0, side: side), in: ctx)
                }
            }
            FruitSlashGame.drawFruit(FruitSlashGame.Fruit(position: SIMD2(640, 130), velocity: .zero, radius: 50, angle: 0, spin: 0, kind: .bomb), in: ctx, time: 0.3)
        })
        Output.save(layer.composited(over: base.composed).cropped(to: base.rect), as: "sheet-fruit.png")
    }

    func testFruitSlashMidSwingCloseUp() throws {
        var game = FruitSlashGame(size: polishFrame, seed: 21)
        game.setFruit([], at: .zero)
        for (i, x) in [220.0, 430, 640, 850, 1060].enumerated() { game.launch(i == 4 ? .bomb : .fruit(i), from: x, apex: 560 + Double(i % 2) * 60) }
        for _ in 0..<42 { game.step(polishTick, world: world([])) }
        for i in 0..<6 {
            let tip = CGPoint(x: 300 + Double(i) * 120, y: 400 + Double(i) * 16)
            let base = HandFixtures.hand(.open, at: .zero, size: 100)
            let hand = HandFixtures.moved(base, by: CGVector(dx: tip.x - base.leadTip.x, dy: tip.y - base.leadTip.y), velocity: CGVector(dx: 3600, dy: 480),
                                          tipVelocity: CGVector(dx: 3600, dy: 480))
            game.step(polishTick, world: world([hand]))
        }
        let base = h.input(SyntheticScene(center: CGPoint(x: 640, y: 440)), wantsGrid: false)
        let layer = try XCTUnwrap(h.services.overlay { game.draw(in: $0, time: 1.3) })
        Output.save(layer.composited(over: base.composed).cropped(to: base.rect), as: "fruit-swing.png")
        XCTAssertGreaterThan(game.sliced, 0)
    }

    /// A gun pointing at the camera with its tip at `p`.
    private func gun(tipAt p: CGPoint, thumb: Double = 1, size: Double = 110) -> HandState {
        var hand = HandFixtures.hand(HandFixtures.Fingers(index: true, middle: false, ring: false, little: false, thumb: thumb), at: CGPoint(x: 640, y: 120), size: size)
        let knuckle = hand[.indexMCP]
        for joint in [HandJoint.indexPIP, .indexDIP, .indexTip] { hand.joints[joint.rawValue] = CGPoint(x: knuckle.x + 4, y: knuckle.y + 3) }
        return HandFixtures.moved(hand, by: CGVector(dx: p.x - hand.indexTip.x, dy: p.y - hand.indexTip.y))
    }

    func testFingerGunsScreens() throws {
        try screens(FingerGunsGame.self, name: "guns", hands: [gun(tipAt: CGPoint(x: 820, y: 470))], playFor: 0.6, during: { t in
            [self.gun(tipAt: CGPoint(x: 820 + 30 * sin(t * 2), y: 470), thumb: Int(t * 3) % 2 == 0 ? 1 : 0)]
        }, make: { size, _ in
            var game = FingerGunsGame(size: size, seed: 9)
            game.setTargets([(.board, CGPoint(x: 250, y: 520)), (.duck, CGPoint(x: 480, y: 610)), (.ufo, CGPoint(x: 830, y: 470)),
                             (.balloon, CGPoint(x: 1050, y: 560)), (.star, CGPoint(x: 1010, y: 300)), (.bunny, CGPoint(x: 300, y: 300))])
            return game
        })
    }

    func testFingerGunsMidShot() throws {
        var game = FingerGunsGame(size: polishFrame, seed: 22)
        game.setTargets([(.board, CGPoint(x: 230, y: 540)), (.duck, CGPoint(x: 480, y: 610)), (.ufo, CGPoint(x: 830, y: 480)),
                         (.balloon, CGPoint(x: 1060, y: 560)), (.star, CGPoint(x: 1000, y: 300)), (.bunny, CGPoint(x: 300, y: 300))])
        for _ in 0..<12 { game.step(polishTick, world: world([gun(tipAt: CGPoint(x: 830, y: 480))])) }
        game.fire(from: SIMD2(700, 170), at: SIMD2(1060, 560))
        game.step(polishTick, world: world([gun(tipAt: CGPoint(x: 830, y: 480))]))
        let base = h.input(SyntheticScene(center: CGPoint(x: 640, y: 440)), wantsGrid: false)
        let layer = try XCTUnwrap(h.services.overlay { game.draw(in: $0, time: 0.6) })
        Output.save(layer.composited(over: base.composed).cropped(to: base.rect), as: "guns-shot.png")
        XCTAssertEqual(game.hits, 1)
    }

    func testWhackScreens() throws {
        try screens(WhackAMoleGame.self, name: "whack", hands: [open(at: CGPoint(x: 400, y: 250))], playFor: 0.4, make: { size, _ in
            var game = WhackAMoleGame(size: size, seed: 4)
            game.pauseSpawns()
            for (hole, kind) in [(0, WhackAMoleGame.Kind.mole), (2, .golden), (4, .bunny), (6, .bomb), (7, .mole), (8, .mole)] { game.place(kind, hole: hole) }
            game.whackMole(inHole: 8, age: 0.04)
            return game
        })
    }

    func testRockPaperScissorsScreens() throws {
        let fist = HandFixtures.hand(.fist, at: CGPoint(x: 640, y: 120), size: 110)
        try screens(RockPaperScissorsGame.self, name: "rps", hands: [fist], playFor: 0.4, make: { size, seed in
            var game = RockPaperScissorsGame(size: size, seed: seed)
            game.setPick(.scissors)
            return game
        })
        // Each stage, one at a time.
        var game = RockPaperScissorsGame(size: polishFrame, seed: 3)
        game.setPick(.scissors)
        let base = h.input(SyntheticScene(center: CGPoint(x: 640, y: 440)), wantsGrid: false)
        let paper = HandFixtures.hand(.open, at: CGPoint(x: 640, y: 120), size: 110)
        var shots: [(String, Double)] = [("ready", 0.5), ("beat", 1.3), ("shoot", 3.1), ("reveal", 4.1)]
        var t = 0.0
        while !shots.isEmpty {
            game.step(polishTick, world: world(t < 2.9 ? [fist] : [paper]))
            t += polishTick
            if t >= shots[0].1 {
                let layer = try XCTUnwrap(h.services.overlay { game.draw(in: $0, time: t) })
                Output.save(layer.composited(over: base.composed).cropped(to: base.rect), as: "rps-stage-\(shots[0].0).png")
                shots.removeFirst()
            }
        }
        XCTAssertEqual(game.outcome, .lose)
    }

    func testPalmPongScreens() throws {
        try screens(PalmPongGame.self, name: "pong", hands: [open(at: CGPoint(x: 330, y: 420))], playFor: 2.2, during: { t in
            [self.open(at: CGPoint(x: 330, y: 360 + 200 * sin(t * 1.7)))]
        }, make: { size, seed in PalmPongGame(size: size, seed: seed) })
    }
}

/// The help each game gives a noisy camera, and the shared screens.
final class HandGameRealWorldTests: XCTestCase {
    private let h = LensHarness()
    private func world(_ hands: [HandState]) -> GameWorld { GameWorld(size: polishFrame, matte: nil, motion: nil, face: nil, hands: hands) }

    /// A gun held across the picture with its fingertip at `tip`.
    private func gun(tipAt tip: CGPoint, thumb: Double = 1, size: Double = 100, id: Int = 1) -> HandState {
        let base = HandFixtures.gun(from: CGPoint(x: 300, y: 200), toward: CGPoint(x: 900, y: 500), size: size, thumb: thumb, id: id)
        return HandFixtures.moved(base, by: CGVector(dx: tip.x - base.indexTip.x, dy: tip.y - base.indexTip.y))
    }

    // MARK: Finger Guns

    func testTurningTheFingerToTheCameraDoesNotDropTheAim() {
        var game = FingerGunsGame(size: polishFrame, seed: 1)
        game.setTargets([.board], at: CGPoint(x: 100, y: 650))
        let aimed = gun(tipAt: CGPoint(x: 700, y: 400))
        for _ in 0..<10 { game.step(polishTick, world: world([aimed])) }
        XCTAssertEqual(game.sights.count, 1)
        // The same hand, now read as a fist: the finger points down the lens.
        let fist = HandFixtures.moved(HandFixtures.hand(.fist, size: 100), by: CGVector(dx: aimed.wrist.x - 640, dy: aimed.wrist.y - 300))
        for _ in 0..<8 { game.step(polishTick, world: world([fist])) }
        XCTAssertEqual(game.sights.count, 1, "still aiming")
        for _ in 0..<12 { game.step(polishTick, world: world([fist])) }
        XCTAssertTrue(game.sights.isEmpty, "a fist held on is not a gun")
    }

    func testANearMissIsPulledOntoTheTargetAndLocksOn() {
        var game = FingerGunsGame(size: polishFrame, seed: 2)
        game.setTargets([.board], at: CGPoint(x: 700, y: 420))
        // 60 pixels off the middle of a target 46 across: outside it, but close.
        let near = gun(tipAt: CGPoint(x: 700 - 60, y: 420), thumb: 1)
        let tipToSight = FingerGun.crosshair(near) - SIMD2(Double(near.indexTip.x), Double(near.indexTip.y))
        let placed = HandFixtures.moved(near, by: CGVector(dx: -tipToSight.x, dy: -tipToSight.y))
        var steps = 0
        while game.score == 0 && steps < 60 { game.step(polishTick, world: world([placed])); steps += 1 }
        XCTAssertEqual(game.score, 1, "aim assist and the slack let a shaky hand lock on")
        let sightMiss = gun(tipAt: CGPoint(x: 700 - 200, y: 420))
        var far = FingerGunsGame(size: polishFrame, seed: 2)
        far.setTargets([.board], at: CGPoint(x: 700, y: 420))
        for _ in 0..<60 { far.step(polishTick, world: world([sightMiss])) }
        XCTAssertEqual(far.score, 0, "but a real miss is a miss")
    }

    func testATremblingHandGivesASteadySight() {
        var game = FingerGunsGame(size: polishFrame, seed: 3)
        game.setTargets([.board], at: CGPoint(x: 100, y: 650))
        var rng = SplitMix64(seed: 9)
        var points: [SIMD2<Double>] = []
        for i in 0..<60 {
            var hand = gun(tipAt: CGPoint(x: 640, y: 400))
            hand.joints = hand.joints.map { CGPoint(x: $0.x + CGFloat(Double.random(in: -5...5, using: &rng)), y: $0.y + CGFloat(Double.random(in: -5...5, using: &rng))) }
            game.step(polishTick, world: world([hand]))
            if i > 20, let s = game.sights.first { points.append(s.point) }
        }
        let mean = points.reduce(SIMD2<Double>(0, 0), +) / Double(points.count)
        let spread = (points.map { simd_length_squared($0 - mean) }.reduce(0, +) / Double(points.count)).squareRoot()
        XCTAssertLessThan(spread, 6, "the sight does not shimmer")
    }

    // MARK: Fruit Slash

    func testASwipeThatJustMissesAFruitStillCutsIt() {
        var game = FruitSlashGame(size: polishFrame, seed: 4)
        game.setFruit([.fruit(1)], at: CGPoint(x: 640, y: 400), radius: 50)
        let path: [CGPoint] = [CGPoint(x: 400, y: 400 + 50 + FruitSlashGame.reach - 4), CGPoint(x: 880, y: 400 + 50 + FruitSlashGame.reach - 4)]
        for (i, tip) in path.enumerated() {
            let base = HandFixtures.hand(.open, at: .zero, size: 100)
            let speed = CGVector(dx: i == 0 ? 0 : 480 * 30, dy: 0)
            // Fingers up, so the palm is well below the fruit and only the tip's path can cut.
            let hand = HandFixtures.moved(base, by: CGVector(dx: tip.x - base.leadTip.x, dy: tip.y - base.leadTip.y), velocity: speed, tipVelocity: speed)
            game.step(polishTick, world: world([hand]))
        }
        XCTAssertEqual(game.sliced, 1)
    }

    func testEveryFruitHasItsArtAndTheHalvesRememberWhichFruit() {
        XCTAssertEqual(FruitSlashGame.kinds.count, 8)
        for n in 0..<FruitSlashGame.kinds.count {
            XCTAssertNotNil(FruitSlashArt.whole(n))
            XCTAssertNotNil(FruitSlashArt.half(n))
            XCTAssertNotNil(FruitSlashArt.splat(n))
        }
        var game = FruitSlashGame(size: polishFrame, seed: 5)
        game.setFruit([.fruit(6)], at: CGPoint(x: 640, y: 400))
        game.cut(at: 0, direction: SIMD2(1, 0))
        XCTAssertEqual(game.halves.map(\.kind), [6, 6])
        XCTAssertEqual(game.readout.lives?.left, 3)
        XCTAssertEqual(game.result.stats.first?.value, "1")
    }

    // MARK: Whack-a-Mole

    func testTheHolesStayInsideTheBorderAndOffTheFace() {
        let game = WhackAMoleGame(size: polishFrame, seed: 1)
        for hole in game.holes {
            // The drawn hole is about 125 pixels either side and 60 up and down.
            XCTAssertGreaterThanOrEqual(hole.x - 120, 64 * 0.9, "\(hole)")
            XCTAssertLessThanOrEqual(hole.x + 120, 1280 - 64 * 0.9, "\(hole)")
            let overTheFace = hole.x > 420 && hole.x < 860 && hole.y > 260
            XCTAssertFalse(overTheFace, "\(hole) is where a face usually is")
        }
    }

    // MARK: Rock Paper Scissors

    func testAThumbsUpIsRockAndAPinchIsNothing() {
        XCTAssertEqual(RockPaperScissorsGame.gesture(of: HandFixtures.thumbsUp()), .rock)
        XCTAssertNil(RockPaperScissorsGame.gesture(of: HandFixtures.hand(.pinch)))
        XCTAssertEqual(RockPaperScissorsGame.gesture(of: HandFixtures.hand(.okSign)), .paper, "three fingers up reads as a flat hand")
    }

    func testWhileShootIsReadTheGameShowsWhatItSees() {
        var game = RockPaperScissorsGame(size: polishFrame, seed: 1)
        game.begin(.reading)
        XCTAssertNil(game.leaning)
        for _ in 0..<12 { game.step(polishTick, world: world([HandFixtures.hand(.peace)])) }
        XCTAssertEqual(game.leaning, .scissors)
    }

    // MARK: Palm Pong

    func testTheBallIsServedFromBelowTheFace() {
        var game = PalmPongGame(size: polishFrame, seed: 1)
        for _ in 0..<40 { game.step(polishTick, world: world([])) }
        XCTAssertLessThan(game.ball.y, 720 * 0.5)
    }

    // MARK: The shared screens

    private func lifecycle<G: HandGameScreens>(_ type: G.Type, id: String, file: StaticString = #filePath, line: UInt = #line) {
        let lens = HandGameLens<G>(id: id, needs: [.hands], store: MemoryScoreStore())
        let base = h.input(wantsGrid: false)
        var t = 0.0
        func play(_ seconds: Double, _ hands: [HandState]) {
            let end = t + seconds
            while t < end { _ = lens.render(h.at(base, time: t, hands: hands)); t += polishTick }
        }
        let hand = HandFixtures.hand(.open, at: CGPoint(x: 400, y: 250))
        play(1, [])
        XCTAssertEqual(lens.phase, .waiting, file: file, line: line)
        play(0.7, [hand])
        guard case .countdown = lens.phase else { return XCTFail("\(lens.phase)", file: file, line: line) }
        play(HandGameLens<G>.countdownSeconds, [hand])
        XCTAssertEqual(lens.phase, .playing, file: file, line: line)
        XCTAssertEqual(lens.status?.title.hasPrefix("Score"), true, file: file, line: line)
        // Hands flicker away for a third of a second: nothing pauses.
        play(0.3, [])
        XCTAssertEqual(lens.phase, .playing, file: file, line: line)
    }

    func testEveryGameRunsThroughTheSharedScreens() {
        lifecycle(FruitSlashGame.self, id: "t.fruit")
        lifecycle(FingerGunsGame.self, id: "t.guns")
        lifecycle(WhackAMoleGame.self, id: "t.whack")
        lifecycle(RockPaperScissorsGame.self, id: "t.rps")
        lifecycle(PalmPongGame.self, id: "t.pong")
    }

    func testTheScreensKeepInsideTheBorder() throws {
        let look = GameScreens.Look(title: "Fruit Slash", hint: FruitSlashGame.hint, presenceHint: FruitSlashGame.presenceHint, accent: FruitSlashGame.accent,
                                    icon: .hand(.open), scoreLabel: "SCORE", player: .hands)
        var motion = GameUIMotion()
        let readouts = [GameUIReadout(score: 98765, lives: (2, 3), combo: 4), GameUIReadout(score: 7, time: (3.2, 45), combo: 3),
                        GameUIReadout(score: 12, lives: (0, 3), label: "Round 5/5")]
        for readout in readouts {
            motion.step(1, readout: readout, record: true)
            let layer = try XCTUnwrap(h.services.overlay { ctx in
                GameScreens.plates(ctx, size: polishFrame, look: look, readout: readout, scoreText: "\(readout.score)", best: "123456", record: true,
                                   motion: motion, time: 1)
                GameScreens.callout(ctx, size: polishFrame, text: "COMBO x4", age: 0.5)
                GameScreens.pill(ctx, size: polishFrame, text: "A hint that is fairly long, as hints go", look: look, alpha: 1, time: 1)
            })
            let bits = h.bitmap(layer)
            var drawnOutside = 0
            for y in stride(from: 0, to: 720, by: 2) {
                for x in stride(from: 0, to: 1280, by: 2) where x < 40 || x > 1240 || y < 20 || y > 700 {
                    if bits.bytes[(y * 1280 + x) * 4 + 3] > 40 { drawnOutside += 1 }
                }
            }
            XCTAssertEqual(drawnOutside, 0, "\(readout)")
        }
    }

    func testEveryGameIsCheapToDrawThroughItsLens() {
        let base = h.input(wantsGrid: false)
        let hands = [HandFixtures.hand(.open, at: CGPoint(x: 400, y: 250)), HandFixtures.hand(.point, at: CGPoint(x: 850, y: 250), id: 2)]
        for info in FlagshipHandGames.all + HandGames.all {
            let lens = info.make()
            lens.restart()
            for i in 0..<(30 * 6) { _ = lens.render(h.at(base, time: Double(i) / 30, hands: hands)) }
            XCTAssertLessThan(HandGameCost.median(of: lens, base: h.at(base, time: 0, hands: hands), harness: h), 12, info.id)
        }
    }

    func testSpritesAreBakedDuringTheCountdown() {
        // Every game's warm-up ends, and bakes without trouble.
        func drain<G: HandGameScreens>(_ type: G.Type) -> Int {
            var step = 0
            while G.warmUp(step) && step < 200 { step += 1 }
            return step
        }
        XCTAssertGreaterThan(drain(FruitSlashGame.self), 20)
        XCTAssertGreaterThan(drain(FingerGunsGame.self), 5)
        XCTAssertGreaterThan(drain(WhackAMoleGame.self), 5)
        XCTAssertGreaterThan(drain(RockPaperScissorsGame.self), 5)
        XCTAssertGreaterThan(drain(PalmPongGame.self), 0)
        XCTAssertLessThan(drain(FruitSlashGame.self), Int(HandGameLens<FruitSlashGame>.countdownSeconds * 30) - 5, "all baked before play starts")
    }

    /// What drawing each game's own layer costs on the CPU, warmed up and mid-play: the part of a frame this area adds.
    func testDrawingEachGameMidPlayIsCheap() throws {
        func measure<G: HandGameScreens>(_ game: G, hands: [HandState], name: String) throws -> Double {
            var game = game
            var motion = GameUIMotion()
            let look = GameScreens.Look(title: G.title, hint: G.hint, presenceHint: G.presenceHint, accent: G.accent, icon: G.icon, scoreLabel: G.scoreLabel,
                                        player: .hands)
            var step = 0
            while G.warmUp(step) { step += 1 }
            var times: [Double] = []
            for i in 0..<90 {
                game.step(polishTick, world: world(hands))
                motion.step(polishTick, readout: game.readout, record: false)
                let started = CFAbsoluteTimeGetCurrent()
                _ = h.services.overlay { ctx in
                    game.draw(in: ctx, time: Double(i) * polishTick)
                    GameScreens.plates(ctx, size: polishFrame, look: look, readout: game.readout, scoreText: "\(game.score)", best: "10", record: false,
                                       motion: motion, time: Double(i) * polishTick)
                }
                if i >= 30 { times.append((CFAbsoluteTimeGetCurrent() - started) * 1000) }
            }
            // The median, because on a machine busy with other work the odd frame is held up by something else entirely.
            let median = times.sorted()[times.count / 2]
            print("draw cost \(name): median \(String(format: "%.2f", median)) ms, worst \(String(format: "%.2f", times.max() ?? 0)) ms")
            return median
        }
        let open = [HandFixtures.hand(.open, at: CGPoint(x: 400, y: 250)), HandFixtures.hand(.point, at: CGPoint(x: 850, y: 250), id: 2)]
        var whack = WhackAMoleGame(size: polishFrame, seed: 1)
        whack.pauseSpawns()
        for hole in 0..<9 { whack.place(hole % 3 == 0 ? .golden : .mole, hole: hole) }
        var guns = FingerGunsGame(size: polishFrame, seed: 2)
        guns.setTargets([(.board, CGPoint(x: 250, y: 520)), (.duck, CGPoint(x: 480, y: 610)), (.ufo, CGPoint(x: 830, y: 470)),
                         (.balloon, CGPoint(x: 1050, y: 560)), (.star, CGPoint(x: 1010, y: 300)), (.bunny, CGPoint(x: 300, y: 300))])
        var rps = RockPaperScissorsGame(size: polishFrame, seed: 3)
        rps.begin(.reveal)
        let costs = [try measure(FruitSlashGame(size: polishFrame, seed: 1), hands: open, name: "fruit"), try measure(guns, hands: open, name: "guns"),
                     try measure(whack, hands: open, name: "whack"), try measure(rps, hands: open, name: "rps"),
                     try measure(PalmPongGame(size: polishFrame, seed: 4), hands: open, name: "pong")]
        for c in costs { XCTAssertLessThan(c, 6, "well under a frame") }
    }
}

/// What a lens costs to make and render a frame, as the median of many frames: on a machine busy with other builds the odd frame is
/// held up by something else entirely, and the mean would measure that instead.
enum HandGameCost {
    static func median(of lens: Lens, base: LensInput, harness: LensHarness, frames: Int = 60) -> Double {
        guard let buffer = harness.compositor.makeOutputBuffer() else { return .infinity }
        var times: [Double] = []
        for i in 0..<frames {
            let started = CFAbsoluteTimeGetCurrent()
            harness.compositor.render(lens.render(harness.at(base, time: Double(i) / 30)), into: buffer)
            times.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        return times.sorted()[frames / 2]
    }
}
