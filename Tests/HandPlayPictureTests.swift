import CoreImage
import simd
import XCTest

private let pictureFrame = CGSize(width: 1280, height: 720)
private let pictureTick = 1.0 / 30

private func pictureWorld(_ hands: [HandState] = []) -> GameWorld {
    GameWorld(size: pictureFrame, matte: nil, motion: nil, face: nil, hands: hands)
}

/// A hand placed by its palm.
private func pictureHand(_ fingers: HandFixtures.Fingers, palmAt p: CGPoint, size: Double = 110, id: Int = 1, angle: Double = 0) -> HandState {
    let base = HandFixtures.hand(fingers, at: .zero, size: size, angle: angle, id: id)
    return HandFixtures.moved(base, by: CGVector(dx: p.x - base.palm.x, dy: p.y - base.palm.y))
}

/// Pictures of the HandPlay games in their different moments, for looking at. They only save when BACKDROP_TEST_OUTPUT is set.
final class HandPlayPictureTests: XCTestCase {
    private let h = LensHarness()

    /// Draws the joints of the hands, so the pictures show where the hands were.
    private func withHands(_ image: CIImage, _ hands: [HandState]) -> CIImage {
        guard !hands.isEmpty, let marks = h.services.overlay({ ctx in
            for hand in hands {
                ctx.setStrokeColor(CGColor(red: 0.95, green: 0.78, blue: 0.66, alpha: 0.95))
                ctx.setLineWidth(CGFloat(hand.size * 0.16))
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                for finger in Finger.allCases {
                    ctx.move(to: hand[.wrist])
                    ctx.addLine(to: hand[finger.knuckle])
                    ctx.addLine(to: hand[finger.middleJoint])
                    ctx.addLine(to: hand[finger.tip])
                }
                ctx.strokePath()
            }
        }) else { return image }
        return marks.composited(over: image).cropped(to: image.extent)
    }

    private func scene(_ background: Bool = true) -> LensInput {
        h.input(SyntheticScene(center: CGPoint(x: 640, y: 430)), background: background, wantsGrid: false)
    }

    /// The game drawn over the person, with the hands under it, the way the lens lays it out.
    private func save<G: Game>(_ game: G, hands: [HandState], as name: String, time: Double = 1, background: Bool = true) {
        let base = scene(background)
        let under = withHands(base.composed, hands)
        guard let layer = h.services.overlay({ game.draw(in: $0, time: time) }) else { return XCTFail("no overlay") }
        Output.save(layer.composited(over: under).cropped(to: base.rect), as: name)
    }

    /// The whole lens (with its waiting screen, countdown and score) at a few moments.
    private func saveLens<G: Game>(_ type: G.Type, name: String, hands: [HandState], make: @escaping (CGSize, UInt64) -> G) {
        let lens = GameLens<G>(id: "pic.\(name)", needs: [.hands], store: MemoryScoreStore(), make: make)
        let base = scene()
        var t = 0.0
        var last = base.composed
        func play(_ seconds: Double, _ hands: [HandState]) {
            let end = t + seconds
            while t < end {
                last = lens.render(h.at(base, time: t, hands: hands))
                t += pictureTick
            }
        }
        play(0.4, [])
        Output.save(last, as: "\(name)-waiting.png")
        lens.restart()
        play(1.2, hands)
        Output.save(withHands(last, hands), as: "\(name)-countdown.png")
        play(GameLens<G>.countdownSeconds, hands)
        Output.save(withHands(last, hands), as: "\(name)-lens.png")
    }

    // MARK: The family

    func testPictureOfGlovesAndTags() {
        let base = scene()
        guard let layer = h.services.overlay({ ctx in
            for (i, pose) in HandPlayPose.allCases.enumerated() {
                HandPlayDraw.stamp(ctx, HandPlayGlove.image(pose, height: 200), at: CGPoint(x: 150 + Double(i) * 245, y: 560))
                HandPlayDraw.stamp(ctx, HandPlayGlove.image(pose, height: 48), at: CGPoint(x: 150 + Double(i) * 245, y: 420))
                HandPlayText.draw(ctx, pose.name, at: CGPoint(x: 150 + Double(i) * 245, y: 360), size: 30, color: pose.tone)
            }
            GameScreens.tag(ctx, "+5", at: CGPoint(x: 330, y: 250), tone: GameUIPalette.violet)
            GameScreens.tag(ctx, "+12", at: CGPoint(x: 900, y: 250), tone: GameUIPalette.berry)
            HandPlayText.draw(ctx, "PERFECT", at: CGPoint(x: 1100, y: 120), size: 44, color: HandPlayPalette.gold)
        }) else { return XCTFail("no overlay") }
        Output.save(layer.composited(over: base.composed).cropped(to: base.rect), as: "family-gloves.png")
    }

    // MARK: Endings, light rooms, near and far

    /// Plays a game through the lens with a hand that does nothing useful until it ends, and saves the game-over screen.
    private func saveEnding<G: Game>(_ type: G.Type, name: String, idle: HandState, limit: Double = 90) {
        let lens = GameLens<G>(id: "pic.end.\(name)", needs: [.hands], store: MemoryScoreStore())
        let base = scene()
        lens.restart()
        var t = 0.0
        var last = base.composed
        while t < limit {
            last = lens.render(h.at(base, time: t, hands: [idle]))
            t += pictureTick
            if case .over(let e) = lens.phase, e > 0.8 { break }
        }
        Output.save(withHands(last, [idle]), as: "\(name)-over.png")
    }

    func testPicturesOfEveryEnding() {
        let idle = pictureHand(.point, palmAt: CGPoint(x: 160, y: 120), size: 90)
        saveEnding(HandPlayMagicDuel.self, name: "duel", idle: idle)
        saveEnding(HandPlayJuggle.self, name: "juggle", idle: idle)
        saveEnding(HandPlaySimon.self, name: "simon", idle: idle)
        saveEnding(HandPlayAirHockey.self, name: "hockey", idle: idle, limit: 200)
        saveEnding(HandPlayStarCatcher.self, name: "stars", idle: idle)
        saveEnding(HandPlayBeatPads.self, name: "pads", idle: idle)
    }

    /// Each game mid-play over a pale, bright room, to check that everything still reads on white.
    func testPicturesOnALightRoom() {
        let light = CIImage(color: CIColor(red: 0.94, green: 0.93, blue: 0.9)).cropped(to: CGRect(origin: .zero, size: pictureFrame))
        func save<G: Game>(_ game: G, _ name: String) {
            guard let layer = h.services.overlay({ game.draw(in: $0, time: 1) }) else { return }
            Output.save(layer.composited(over: light), as: "light-\(name).png")
        }
        let open = pictureHand(.open, palmAt: CGPoint(x: 380, y: 300)), fist = pictureHand(.fist, palmAt: CGPoint(x: 900, y: 260), id: 2)
        var duel = HandPlayMagicDuel(size: pictureFrame, seed: 2)
        for i in 0..<(30 * 14) { duel.step(pictureTick, world: pictureWorld(i % 60 < 45 ? [open] : [open, fist])) }
        save(duel, "duel")
        var stars = HandPlayStarCatcher(size: pictureFrame, seed: 2)
        for i in 0..<(30 * 8) { stars.step(pictureTick, world: pictureWorld([pictureHand(.open, palmAt: CGPoint(x: 640 + 300 * sin(Double(i) / 30), y: 280))])) }
        save(stars, "stars")
        var juggle = HandPlayJuggle(size: pictureFrame, seed: 2)
        juggle.place(ballAt: SIMD2(400, 500), velocity: SIMD2(0, 200))
        juggle.place(ballAt: SIMD2(800, 300), velocity: SIMD2(0, -200))
        for _ in 0..<10 { juggle.step(pictureTick, world: pictureWorld([open])) }
        save(juggle, "juggle")
        var hockey = HandPlayAirHockey(size: pictureFrame, seed: 2)
        for _ in 0..<40 { hockey.step(pictureTick, world: pictureWorld([open])) }
        save(hockey, "hockey")
        var pads = HandPlayBeatPads(size: pictureFrame, seed: 2)
        for _ in 0..<(30 * 9) { pads.step(pictureTick, world: pictureWorld([pictureHand(.open, palmAt: CGPoint(x: 640, y: 600))])) }
        save(pads, "pads")
        var simon = HandPlaySimon(size: pictureFrame, seed: 2)
        while simon.stage != .show(1) { simon.step(pictureTick, world: pictureWorld([fist])) }
        for _ in 0..<10 { simon.step(pictureTick, world: pictureWorld([fist])) }
        save(simon, "simon")
    }

    /// Hand-anchored rings and pads at a far, small hand and a near, big one.
    func testPicturesOfNearAndFarHands() {
        let far = pictureHand(.open, palmAt: CGPoint(x: 300, y: 330), size: 55), near = pictureHand(.open, palmAt: CGPoint(x: 900, y: 300), size: 230, id: 2)
        var stars = HandPlayStarCatcher(size: pictureFrame, seed: 3)
        stars.pauseSpawns()
        for _ in 0..<10 { stars.step(pictureTick, world: pictureWorld([far, near])) }
        save(stars, hands: [far, near], as: "near-far-stars.png")
        var juggle = HandPlayJuggle(size: pictureFrame, seed: 3)
        juggle.clearBalls()
        for _ in 0..<10 { juggle.step(pictureTick, world: pictureWorld([far, near])) }
        save(juggle, hands: [far, near], as: "near-far-juggle.png")
        var simon = HandPlaySimon(size: pictureFrame, seed: 3)
        for _ in 0..<10 { simon.step(pictureTick, world: pictureWorld([far, near])) }
        save(simon, hands: [far, near], as: "near-far-simon.png")
    }

    // MARK: Magic Duel

    func testPicturesOfMagicDuel() {
        typealias Game = HandPlayMagicDuel
        var game = Game(size: pictureFrame, seed: 3)
        game.pauseSpawns()
        game.place(.wisp, at: SIMD2(230, 520))
        game.place(.bat, at: SIMD2(1050, 560))
        game.place(.brute, at: SIMD2(1020, 250), castIn: 0.2)
        game.place(.wisp, at: SIMD2(640, 650))
        let open = pictureHand(.open, palmAt: CGPoint(x: 330, y: 300))
        let fist = pictureHand(.fist, palmAt: CGPoint(x: 930, y: 240), id: 2)
        for _ in 0..<8 { game.step(pictureTick, world: pictureWorld([open])) }
        save(game, hands: [open], as: "duel-charge.png")
        for _ in 0..<10 { game.step(pictureTick, world: pictureWorld([open])) }
        save(game, hands: [open], as: "duel-cast.png")
        for _ in 0..<12 { game.step(pictureTick, world: pictureWorld([open, fist])) }
        save(game, hands: [open, fist], as: "duel-shield.png")

        var later = Game(size: pictureFrame, seed: 9)
        for i in 0..<(30 * 40) {
            let hands = i % 120 < 90 ? [pictureHand(.open, palmAt: CGPoint(x: 400 + 300 * sin(Double(i) / 50), y: 330))] : [pictureHand(.fist, palmAt: CGPoint(x: 640, y: 200))]
            later.step(pictureTick, world: pictureWorld(hands))
            if later.isOver { break }
        }
        save(later, hands: [pictureHand(.open, palmAt: CGPoint(x: 400, y: 330))], as: "duel-later.png")
        saveLens(Game.self, name: "duel", hands: [open]) { size, seed in Game(size: size, seed: seed) }
    }

    // MARK: Star Catcher

    func testPicturesOfStarCatcher() {
        typealias Game = HandPlayStarCatcher
        var game = Game(size: pictureFrame, seed: 5)
        game.pauseSpawns()
        let palm = CGPoint(x: 360, y: 300)
        let open = pictureHand(.open, palmAt: palm)
        for (k, kind) in [Game.Kind.star, .golden, .star, .star].enumerated() {
            game.drop(kind, at: SIMD2(palm.x + Double(k % 2) * 30 - 15, palm.y + 20))
            game.step(pictureTick, world: pictureWorld([open]))
        }
        game.drop(.star, at: SIMD2(700, 600), speed: 200)
        game.drop(.golden, at: SIMD2(980, 520), speed: 200)
        game.drop(.bomb, at: SIMD2(560, 520), speed: 200)
        game.drop(.star, at: SIMD2(160, 650), speed: 200)
        for _ in 0..<10 { game.step(pictureTick, world: pictureWorld([open])) }
        save(game, hands: [open], as: "stars-holding.png")
        let fist = pictureHand(.fist, palmAt: palm)
        for _ in 0..<7 { game.step(pictureTick, world: pictureWorld([fist])) }
        save(game, hands: [fist], as: "stars-bank.png")

        var played = Game(size: pictureFrame, seed: 8)
        for i in 0..<(30 * 20) {
            let x = 640 + 380 * sin(Double(i) / 45)
            let hand = i % 90 < 75 ? pictureHand(.open, palmAt: CGPoint(x: x, y: 280)) : pictureHand(.fist, palmAt: CGPoint(x: x, y: 280))
            played.step(pictureTick, world: pictureWorld([hand]))
        }
        save(played, hands: [pictureHand(.open, palmAt: CGPoint(x: 640 + 380 * sin(600.0 / 45), y: 280))], as: "stars-later.png")
        saveLens(Game.self, name: "stars", hands: [open]) { size, seed in Game(size: size, seed: seed) }
    }

    // MARK: Juggle

    func testPicturesOfJuggle() {
        typealias Game = HandPlayJuggle
        var game = Game(size: pictureFrame, seed: 2)
        let left = CGPoint(x: 380, y: 250), right = CGPoint(x: 900, y: 230)
        game.place(ballAt: SIMD2(380, 420), velocity: SIMD2(0, -500))
        game.place(ballAt: SIMD2(820, 560), velocity: SIMD2(-120, 200))
        game.place(ballAt: SIMD2(560, 300), velocity: SIMD2(80, 600))
        let hands = [pictureHand(.open, palmAt: left), pictureHand(.open, palmAt: right, id: 2)]
        for _ in 0..<7 { game.step(pictureTick, world: pictureWorld(hands)) }
        save(game, hands: hands, as: "juggle-bounce.png")
        for _ in 0..<14 { game.step(pictureTick, world: pictureWorld(hands)) }
        save(game, hands: hands, as: "juggle-air.png")

        var low = Game(size: pictureFrame, seed: 3)
        low.place(ballAt: SIMD2(700, 200), velocity: SIMD2(0, -500))
        low.step(pictureTick, world: pictureWorld([pictureHand(.open, palmAt: CGPoint(x: 300, y: 300))]))
        save(low, hands: [pictureHand(.open, palmAt: CGPoint(x: 300, y: 300))], as: "juggle-danger.png")
        saveLens(Game.self, name: "juggle", hands: [pictureHand(.open, palmAt: CGPoint(x: 640, y: 250))]) { size, seed in Game(size: size, seed: seed) }
    }

    // MARK: Air Hockey

    func testPicturesOfAirHockey() {
        typealias Game = HandPlayAirHockey
        var game = Game(size: pictureFrame, seed: 4)
        let a = pictureHand(.open, palmAt: CGPoint(x: 420, y: 220)), b = pictureHand(.open, palmAt: CGPoint(x: 860, y: 180), id: 2)
        for _ in 0..<45 { game.step(pictureTick, world: pictureWorld([a, b])) }
        game.place(puck: SIMD2(520, 300), velocity: SIMD2(700, 900))
        for _ in 0..<6 { game.step(pictureTick, world: pictureWorld([a, b])) }
        save(game, hands: [a, b], as: "hockey-play.png")
        game.place(puck: SIMD2(640, 600), velocity: SIMD2(0, 1400))
        for _ in 0..<10 { game.step(pictureTick, world: pictureWorld([a, b])) }
        save(game, hands: [a, b], as: "hockey-goal.png")
        saveLens(Game.self, name: "hockey", hands: [a]) { size, seed in Game(size: size, seed: seed) }
    }

    // MARK: Beat Pads

    func testPicturesOfBeatPads() {
        typealias Game = HandPlayBeatPads
        var game = Game(size: pictureFrame, seed: 6)
        let rest = pictureHand(.open, palmAt: CGPoint(x: 640, y: 420))
        while game.elapsed < 9.3 { game.step(pictureTick, world: pictureWorld([rest])) }
        // A fingertip coming down onto whichever pad has the next note.
        let next = game.notes.first { $0.judgement == nil && $0.time > game.elapsed }
        let pad = game.pads[next?.pad ?? 1]
        while let n = next, game.elapsed < n.time - 0.18 { game.step(pictureTick, world: pictureWorld([rest])) }
        for k in 0..<6 {
            let tip = CGPoint(x: pad.x, y: pad.y + 160 - Double(k) * 32)
            let hand = HandFixtures.moved(HandFixtures.hand(.point, at: .zero, size: 110), by: CGVector(dx: tip.x - 25, dy: tip.y - 210))
            game.step(pictureTick, world: pictureWorld([hand]))
        }
        let hand = HandFixtures.moved(HandFixtures.hand(.point, at: .zero, size: 110), by: CGVector(dx: pad.x - 25, dy: pad.y - 50))
        save(game, hands: [hand], as: "pads-hit.png")
        for _ in 0..<8 { game.step(pictureTick, world: pictureWorld([rest])) }
        save(game, hands: [rest], as: "pads-rings.png")
        var done = Game(size: pictureFrame, seed: 6)
        done.setNotes([(0, 1), (1, 1.5)])
        while !done.isOver { done.step(pictureTick, world: pictureWorld([rest])) }
        save(done, hands: [], as: "pads-over.png")
        saveLens(Game.self, name: "pads", hands: [rest]) { size, seed in Game(size: size, seed: seed) }
    }

    // MARK: Hand Simon

    func testPicturesOfHandSimon() {
        typealias Game = HandPlaySimon
        var game = Game(size: pictureFrame, seed: 7)
        game.setSequence([.fist, .peace, .thumbsUp, .open])
        let fist = pictureHand(.fist, palmAt: CGPoint(x: 330, y: 330))
        while game.stage != .show(1) { game.step(pictureTick, world: pictureWorld([fist])) }
        for _ in 0..<10 { game.step(pictureTick, world: pictureWorld([fist])) }
        save(game, hands: [fist], as: "simon-show.png")
        while game.stage != .turn { game.step(pictureTick, world: pictureWorld([])) }
        for _ in 0..<12 { game.step(pictureTick, world: pictureWorld([fist])) }
        let peace = pictureHand(.peace, palmAt: CGPoint(x: 330, y: 330))
        for _ in 0..<6 { game.step(pictureTick, world: pictureWorld([peace])) }
        save(game, hands: [peace], as: "simon-turn.png")
        let open = pictureHand(.open, palmAt: CGPoint(x: 330, y: 330))
        while game.stage == .turn { game.step(pictureTick, world: pictureWorld([open])) }
        for _ in 0..<12 { game.step(pictureTick, world: pictureWorld([open])) }
        save(game, hands: [open], as: "simon-mistake.png")
        saveLens(Game.self, name: "simon", hands: [fist]) { size, seed in Game(size: size, seed: seed) }
    }
}
