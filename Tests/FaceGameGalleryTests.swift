import CoreImage
import simd
import XCTest

/// Runs any face game through its lens with a "player" that poses the synthetic person each frame, and saves pictures of each
/// stage: waiting, settling, countdown, play, later play and the end card. The pictures are for looking at; the frames that are
/// saved are drawn from a freshly posed person so the game's art lines up with them.
final class FaceGameGalleryDriver<G: FaceGame> {
    let harness = LensHarness()
    let lens: FaceGameLens<G>
    let base: LensInput
    private(set) var time = 0.0

    init(make: ((CGSize, UInt64) -> G)? = nil) {
        lens = FaceGameLens<G>(id: "gallery.\(G.title)", store: MemoryScoreStore(), make: make)
        base = harness.input(wantsGrid: false)
    }

    /// Plays `seconds` with `player` posing the person (nil: nobody there) and returns the last frame, drawn properly.
    @discardableResult
    func run(_ seconds: Double, fps: Double = 30, player: (Double, G) -> SyntheticScene?) -> CIImage {
        var out = base.composed
        let frames = max(1, Int((seconds * fps).rounded()))
        for i in 0..<frames {
            let scene = player(time, lens.game)
            let input: LensInput
            if i == frames - 1 {
                let posed = harness.input(scene ?? SyntheticScene(), time: time, dt: 1 / fps, wantsGrid: false)
                input = LensInput(time: time, dt: 1 / fps, rect: posed.rect, camera: posed.camera, matte: posed.matte, background: posed.background,
                                  composed: scene == nil ? posed.background ?? posed.composed : posed.composed, matteGrid: nil, face: scene?.face(), services: posed.services)
            } else {
                input = LensInput(time: time, dt: 1 / fps, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                                  composed: base.composed, matteGrid: nil, face: scene?.face(), services: base.services)
            }
            out = lens.render(input)
            time += 1 / fps
        }
        return out
    }

    /// Plays a whole round, saving `name-1-waiting.png` … `name-6-over.png`. `ender` plays badly so the round finishes.
    func tour(_ name: String, play: Double = 6, later: Double = 8, player: @escaping (Double, G) -> SyntheticScene?,
              ender: ((Double, G) -> SyntheticScene?)? = nil) {
        Output.save(run(0.4) { _, _ in nil }, as: "\(name)-1-waiting.png")
        Output.save(run(0.35, player: player), as: "\(name)-2-settling.png")
        run(0.6, player: player)
        Output.save(run(1.2, player: player), as: "\(name)-3-countdown.png")
        run(FaceGameLens<G>.countdownSeconds, player: player)
        Output.save(run(play, player: player), as: "\(name)-4-play.png")
        Output.save(run(later, player: player), as: "\(name)-5-later.png")
        let finish = ender ?? player
        for _ in 0..<300 {
            if case .over = lens.phase { break }
            run(0.5, player: finish)
        }
        Output.save(run(2.2, player: finish), as: "\(name)-6-over.png")
    }
}

/// The synthetic person, posed.
func faceGameScene(at center: CGPoint = CGPoint(x: 640, y: 420), scale: Double = 1, roll: Double = 0, mouth: Double = 0, brows: Double = 0,
                   blink: Double = 0, smile: Double = 0) -> SyntheticScene {
    var s = SyntheticScene(center: center, scale: scale, roll: roll)
    s.mouthOpen = mouth
    s.browRaise = brows
    s.blink = blink
    s.smile = smile
    return s
}

/// Moves `value` towards `goal` by at most `limit`: a player whose head can only move so fast.
func faceGameSlew(_ value: Double, toward goal: Double, limit: Double) -> Double { value + max(-limit, min(limit, goal - value)) }

final class FaceGameGalleryTests: XCTestCase {
    func testMouthCatchGallery() {
        let d = FaceGameGalleryDriver<MouthCatchGame>()
        d.tour("gallery-mouth", play: 7, later: 12) { t, _ in
            faceGameScene(at: CGPoint(x: 640 + 90 * sin(t * 0.9), y: 420), mouth: sin(t * 2.4) > -0.2 ? 0.8 : 0)
        }
    }

    func testFlappyGallery() {
        let d = FaceGameGalleryDriver<FlappyFaceGame>()
        d.tour("gallery-flappy", play: 6, later: 8, player: { _, game in
            let next = game.pipes.first { $0.x + FlappyFaceGame.pipeWidth > game.birdX - 40 }
            return faceGameScene(at: CGPoint(x: 640, y: (next?.gapCenter ?? 360) - 20))
        }, ender: { _, _ in faceGameScene(at: CGPoint(x: 640, y: 40)) })
    }

    func testStaringGallery() {
        let d = FaceGameGalleryDriver<StaringContestGame>()
        d.tour("gallery-staring", play: 5, later: 18, player: { _, _ in faceGameScene() }, ender: { _, _ in faceGameScene(blink: 1) })
    }

    func testBrowRunnerGallery() {
        let d = FaceGameGalleryDriver<BrowRunnerGame>()
        d.tour("gallery-runner", play: 5, later: 14, player: { _, game in faceGameScene(brows: faceGameBrowBot(game)) }, ender: { _, _ in faceGameScene() })
    }

    func testSnakeGallery() {
        let d = FaceGameGalleryDriver<FaceSnakeGame>(make: { size, seed in
            var game = FaceSnakeGame(size: size, seed: seed)
            game.grow(by: 24)
            return game
        })
        // An autopilot nose that heads for the nearest fruit, moved as a person would move it.
        var nose = CGPoint(x: 640, y: 400)
        let rest = SyntheticScene().face().nose
        d.tour("gallery-snake", play: 5, later: 8, player: { _, game in
            let gain = FaceSnakeGame.reachPerEyeSpacing / 84
            if game.elapsed > 0, let goal = game.fruit.min(by: { simd_length($0.position - game.head) < simd_length($1.position - game.head) })?.position {
                nose.x = faceGameSlew(nose.x, toward: rest.x + (goal.x - 640) / gain, limit: 8)
                nose.y = faceGameSlew(nose.y, toward: rest.y + (goal.y - 360) / gain, limit: 8)
            }
            return faceGameScene(at: CGPoint(x: 640 + nose.x - rest.x, y: 420 + nose.y - rest.y))
        }, ender: { _, _ in faceGameScene() })
    }

    func testCopyCatGallery() {
        let d = FaceGameGalleryDriver<CopyCatGame>()
        d.tour("gallery-copycat", play: 4.2, later: 7, player: { _, game in
            guard game.cardAge > 1.1 else { return faceGameScene() }
            return faceGameCopy(game.current)
        }, ender: { _, _ in faceGameScene() })
    }

    func testSpaceBlasterGallery() {
        let d = FaceGameGalleryDriver<SpaceBlasterGame>()
        var x = 640.0
        d.tour("gallery-blaster", play: 6, later: 10, player: { _, game in
            let target = game.rocks.min(by: { $0.position.y < $1.position.y })?.position.x ?? 640
            let goal = 640 + (target - 640) * 84 / SpaceBlasterGame.reach
            x = faceGameSlew(x, toward: goal, limit: 5)
            let lined = game.rocks.contains { abs($0.position.x - game.shipX) < $0.radius + 10 }
            return faceGameScene(at: CGPoint(x: x, y: 420), mouth: lined ? 0.8 : 0)
        }, ender: { _, _ in faceGameScene() })
    }

    func testKeepyUppyGallery() {
        let d = FaceGameGalleryDriver<FaceKeepyUppyGame>()
        var x = 640.0
        d.tour("gallery-keepy", play: 5, later: 9, player: { _, game in
            x = faceGameSlew(x, toward: game.ball.x, limit: 18)
            return faceGameScene(at: CGPoint(x: x, y: 360))
        }, ender: { _, _ in faceGameScene(at: CGPoint(x: 220, y: 360)) })
    }

    func testTiltRacerGallery() {
        let d = FaceGameGalleryDriver<TiltRacerGame>()
        var roll = 0.0
        d.tour("gallery-racer", play: 6, later: 10, player: { _, game in
            roll = faceGameSlew(roll, toward: faceGameRacerRoll(game), limit: 0.03)
            return faceGameScene(roll: roll)
        }, ender: { _, _ in faceGameScene() })
    }

    func testBubbleGumGallery() {
        let d = FaceGameGalleryDriver<BubbleGumGame>()
        d.tour("gallery-bubble", play: 3.4, later: 5, player: { t, game in
            faceGameScene(mouth: game.bubble < 0.5 && FaceGamePaint.wrap(t, 4) < 3.2 ? 0.8 : 0)
        }, ender: { _, _ in faceGameScene(mouth: 0.9) })
    }
}

/// The person pulling the face a Copy Cat card asks for.
func faceGameCopy(_ pose: CopyCatGame.Pose) -> SyntheticScene {
    switch pose {
    case .smile: return faceGameScene(smile: 1)
    case .openWide: return faceGameScene(mouth: 0.9)
    case .browsUp: return faceGameScene(brows: 0.9)
    case .eyesShut: return faceGameScene(blink: 1)
    case .tiltLeft: return faceGameScene(roll: 0.3)
    case .tiltRight: return faceGameScene(roll: -0.3)
    }
}

/// A Brow Runner player who takes off a beat before each obstacle and keeps their brows up until they are past it.
func faceGameBrowBot(_ game: BrowRunnerGame) -> Double {
    let x = BrowRunnerGame.playerX
    guard let next = game.obstacles.first(where: { $0.x + $0.width + 20 > x - BrowRunnerGame.bodyHalfWidth }) else { return 0 }
    let front = next.x - (x + 14), rear = next.x + next.width - (x - 14)
    let spanSeconds = (next.width + 28) / game.speed
    let leadSeconds = max(0.12, (0.85 - spanSeconds) / 2)
    return front / game.speed <= leadSeconds && rear > 0 ? 0.9 : 0
}

/// A Tilt Racer driver: the roll that steers to the lane with the most room ahead, through the middle only if it is clear.
func faceGameRacerRoll(_ game: TiltRacerGame) -> Double {
    func room(_ lane: Double) -> Double {
        game.cars.filter { abs($0.x - lane) < 0.3 && $0.z > -1.5 && $0.spin == 0 }.map(\.z).min() ?? 1000
    }
    let lanes = TiltRacerGame.lanes
    let here = lanes.min { abs($0 - game.playerX) < abs($1 - game.playerX) } ?? 0
    var goal = here
    if room(here) < 35, let best = lanes.max(by: { room($0) < room($1) }), room(best) > room(here) {
        goal = abs(best - here) > 1 && room(0) < 14 ? here : best
    }
    return -goal * TiltRacerGame.fullTilt
}
