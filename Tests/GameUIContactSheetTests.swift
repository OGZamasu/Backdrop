import CoreImage
import XCTest

/// Pictures of every scored game in each of its screens (waiting, countdown, playing, over), saved side by side as
/// `gameui-<state>-<game>.png` when BACKDROP_TEST_OUTPUT is set, so the whole family can be laid out on contact sheets and judged
/// as one product (`out/gameui_sheets.py`). Skipped without an output folder: it runs every game for several seconds.
final class GameUIContactSheetTests: XCTestCase {
    private let h = LensHarness()
    private let tick = 1.0 / 30

    enum Player { case body, hands, face }

    struct Entry {
        let name: String
        let player: Player
        let make: (ScoreStore) -> Lens
        /// Ends the round on the spot, so the result card can be pictured without playing a whole round.
        let end: (Lens) -> Void
        let isOver: (Lens) -> Bool
    }

    private static func body<G: Game>(_ name: String, _ type: G.Type) -> Entry {
        Entry(name: name, player: .body, make: { GameLens<G>(id: "sheet.\(name)", needs: [.matte], store: $0) },
              end: { ($0 as? GameLens<G>)?.endRound() }, isOver: { lens in
                  if case .over = (lens as? GameLens<G>)?.phase { return true } else { return false }
              })
    }

    private static func hands<G: Game>(_ name: String, _ type: G.Type) -> Entry {
        Entry(name: name, player: .hands, make: { GameLens<G>(id: "sheet.\(name)", needs: [.hands], store: $0) },
              end: { ($0 as? GameLens<G>)?.endRound() }, isOver: { lens in
                  if case .over = (lens as? GameLens<G>)?.phase { return true } else { return false }
              })
    }

    private static func handGame<G: HandGameScreens>(_ name: String, _ type: G.Type, matte: Bool = false) -> Entry {
        Entry(name: name, player: .hands, make: { HandGameLens<G>(id: "sheet.\(name)", needs: matte ? [.hands, .matte] : [.hands], store: $0) },
              end: { ($0 as? HandGameLens<G>)?.endRound() }, isOver: { lens in
                  if case .over = (lens as? HandGameLens<G>)?.phase { return true } else { return false }
              })
    }

    private static func face<G: FaceGame>(_ name: String, _ type: G.Type) -> Entry {
        Entry(name: name, player: .face, make: { FaceGameLens<G>(id: "sheet.\(name)", store: $0) },
              end: { ($0 as? FaceGameLens<G>)?.endRound() }, isOver: { lens in
                  if case .over = (lens as? FaceGameLens<G>)?.phase { return true } else { return false }
              })
    }

    static let entries: [Entry] = [
        body("balloon-pop", BalloonGame.self), body("breakout", BreakoutGame.self),
        body("meteor-dodge", MeteorDodgeGame.self), body("hole-in-the-wall", HoleInTheWallGame.self), body("bubble-wrap", BubbleWrapGame.self),
        body("keepy-uppy", KeepyUppyGame.self), body("laser-limbo", LaserLimboGame.self), body("punching-bag", PunchingBagGame.self),
        body("goalkeeper", GoalkeeperGame.self), body("ninja-stars", NinjaStarsGame.self),
        handGame("fruit-slash", FruitSlashGame.self, matte: true), handGame("finger-guns", FingerGunsGame.self),
        handGame("whack-a-mole", WhackAMoleGame.self), handGame("rock-paper-scissors", RockPaperScissorsGame.self),
        handGame("palm-pong", PalmPongGame.self),
        hands("magic-duel", HandPlayMagicDuel.self), hands("beat-pads", HandPlayBeatPads.self), hands("air-hockey", HandPlayAirHockey.self),
        hands("star-catcher", HandPlayStarCatcher.self), hands("hand-simon", HandPlaySimon.self), hands("juggle", HandPlayJuggle.self),
        face("staring-contest", StaringContestGame.self), face("brow-runner", BrowRunnerGame.self), face("face-snake", FaceSnakeGame.self),
        face("mouth-catch", MouthCatchGame.self), face("flappy-face", FlappyFaceGame.self), face("copy-cat", CopyCatGame.self),
        face("space-blaster", SpaceBlasterGame.self), face("face-keepy-uppy", FaceKeepyUppyGame.self), face("tilt-racer", TiltRacerGame.self),
        face("bubble-gum", BubbleGumGame.self),
    ]

    /// The person, moving gently so body games see motion and face games see a face that does things.
    private func scene(_ player: Player, at t: Double) -> SyntheticScene {
        switch player {
        case .body:
            return SyntheticScene(center: CGPoint(x: 640 + 170 * sin(t * 2.1), y: 420))
        case .hands:
            return SyntheticScene(center: CGPoint(x: 640, y: 440))
        case .face:
            var s = SyntheticScene(center: CGPoint(x: 640 + 50 * sin(t * 0.8), y: 430 + 36 * sin(t * 1.7)))
            s.mouthOpen = max(0, sin(t * 2.3))
            s.browRaise = max(0, sin(t * 1.4 + 1))
            s.roll = 0.12 * sin(t * 0.9)
            return s
        }
    }

    /// Open hands drifting around the lower half, palms toward the camera.
    private func hands(at t: Double) -> [HandState] {
        let a = HandFixtures.hand(.open, at: CGPoint(x: 360 + 120 * sin(t * 2.4), y: 190 + 60 * cos(t * 3.1)), size: 105, id: 1,
                                  velocity: CGVector(dx: 300 * cos(t * 2.4), dy: -180 * sin(t * 3.1)))
        let b = HandFixtures.hand(.open, at: CGPoint(x: 930 + 100 * cos(t * 2.0), y: 210 + 50 * sin(t * 2.7)), size: 100, id: 2,
                                  velocity: CGVector(dx: -200 * sin(t * 2.0), dy: 135 * cos(t * 2.7)))
        return [a, b]
    }

    /// The room behind the player: the usual dark backdrop, or (with GAMEUI_LIGHT set) a pale wall, to check everything still reads.
    private let room: CIImage = {
        guard ProcessInfo.processInfo.environment["GAMEUI_LIGHT"] != nil else { return SyntheticScene.backdrop() }
        let wall = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 720), "inputPoint1": CIVector(x: 1280, y: 0),
            "inputColor0": CIColor(red: 0.97, green: 0.95, blue: 0.9), "inputColor1": CIColor(red: 0.85, green: 0.88, blue: 0.9),
        ])?.outputImage ?? CIImage(color: CIColor(red: 0.95, green: 0.94, blue: 0.9))
        return wall.cropped(to: CGRect(origin: .zero, size: SyntheticScene.size))
    }()

    private func frame(_ entry: Entry, at t: Double, present: Bool, cache: inout (Double, LensInput)?) -> LensInput {
        // A fresh camera picture every few frames is plenty to move the person; in between the last one is reused.
        let base: LensInput
        if let cached = cache, t - cached.0 < 0.1 {
            base = cached.1
        } else {
            let s = scene(entry.player, at: t)
            base = s.input(time: t, dt: tick, services: h.services, compositor: h.compositor, grid: entry.player == .body ? h.grid : nil,
                           background: room, withFace: entry.player == .face && present)
            cache = (t, base)
        }
        var input = h.at(base, time: t, dt: tick, hands: entry.player == .hands && present ? hands(at: t) : [])
        if entry.player == .body && !present {
            input = LensInput(time: t, dt: tick, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                              composed: base.composed, matteGrid: nil, face: nil, services: base.services, hands: [])
        }
        return input
    }

    func testPictureEveryGameInEveryScreen() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] == nil, "only makes pictures")
        let only = ProcessInfo.processInfo.environment["GAMEUI_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        for entry in Self.entries where only?.contains(entry.name) ?? true {
            let store = MemoryScoreStore()
            store.record(3, for: "sheet.\(entry.name)")
            let lens = entry.make(store)
            var t = 0.0
            var cache: (Double, LensInput)?
            var out = h.input().composed
            func run(_ seconds: Double, present: Bool = true) {
                let end = t + seconds
                while t < end {
                    out = lens.render(frame(entry, at: t, present: present, cache: &cache))
                    t += tick
                }
            }
            run(0.6, present: false)
            run(0.25)
            Output.save(out, as: "gameui-1-waiting-\(entry.name).png")
            run(1.4)
            Output.save(out, as: "gameui-2-countdown-\(entry.name).png")
            run(2.15)
            Output.save(out, as: "gameui-5-go-\(entry.name).png")
            run(3.65)
            Output.save(out, as: "gameui-3-playing-\(entry.name).png")
            run(2.3, present: false)
            Output.save(out, as: "gameui-6-paused-\(entry.name).png")
            run(0.3)
            if !entry.isOver(lens) { entry.end(lens) }
            run(1.3)
            if entry.isOver(lens) { Output.save(out, as: "gameui-4-over-\(entry.name).png") }
        }
    }
}
