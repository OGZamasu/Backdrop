import CoreImage
import simd
import XCTest

private let frame = CGSize(width: 1280, height: 720)

/// Pictures of every body game in its key states, saved when BACKDROP_TEST_OUTPUT is set, so the art can be looked at.
/// Each test also checks the picture is not blank and has the right size.
final class BodyGamePreviewTests: XCTestCase {
    private let h = LensHarness()

    private func world(_ matte: MatteQuery?, motion: MatteQuery? = nil) -> GameWorld {
        GameWorld(size: frame, matte: matte, motion: motion, face: nil)
    }

    /// The synthetic scene with a game's drawing laid over it.
    private func picture(_ base: LensInput, _ draw: @escaping (CGContext) -> Void) throws -> CIImage {
        let layer = try XCTUnwrap(h.services.overlay(draw))
        return layer.composited(over: base.composed).cropped(to: base.rect)
    }

    private func differs(_ image: CIImage, from plain: CIImage) -> Int {
        let a = h.bitmap(image), b = h.bitmap(plain)
        var count = 0
        for i in stride(from: 0, to: a.bytes.count, by: 4 * 53) where abs(Int(a.bytes[i]) - Int(b.bytes[i])) + abs(Int(a.bytes[i + 1]) - Int(b.bytes[i + 1])) > 30 { count += 1 }
        return count
    }

    private func save(_ image: CIImage, _ name: String, against base: LensInput) {
        XCTAssertEqual(image.extent.size, frame, name)
        XCTAssertGreaterThan(differs(image, from: base.composed), 40, "\(name) draws something")
        Output.save(image, as: "bodygame-preview-\(name).png")
    }

    func testBalloonPopPictures() throws {
        let base = h.input()
        var game = BalloonGame(size: frame, seed: 11)
        for _ in 0..<(30 * 7) { game.step(1.0 / 30, world: world(nil, motion: BodyRectsMatte())) }
        save(try picture(base) { game.draw(in: $0, time: 7) }, "balloons-drifting", against: base)
        // A swat across the middle: a few burst at once.
        game.step(1.0 / 30, world: world(nil, motion: BodyRectsMatte(rects: [CGRect(x: 0, y: 250, width: 1280, height: 200)])))
        for _ in 0..<3 { game.step(1.0 / 30, world: world(nil, motion: BodyRectsMatte())) }
        save(try picture(base) { game.draw(in: $0, time: 7.2) }, "balloons-popping", against: base)
        for _ in 0..<(30 * 32) { game.step(1.0 / 30, world: world(nil, motion: BodyRectsMatte())) }
        save(try picture(base) { game.draw(in: $0, time: 41) }, "balloons-last-seconds", against: base)
    }

    func testBreakoutPictures() throws {
        let base = h.input(SyntheticScene(center: CGPoint(x: 640, y: 260)))
        let body = h.grid
        var game = BreakoutGame(size: frame, seed: 4)
        for _ in 0..<20 { game.step(1.0 / 30, world: world(body)) }
        save(try picture(base) { game.draw(in: $0, time: 0.7) }, "breakout-serve", against: base)
        for _ in 0..<(30 * 6) { game.step(1.0 / 30, world: world(body)) }
        save(try picture(base) { game.draw(in: $0, time: 6) }, "breakout-rally", against: base)
        // A brick breaking.
        var smash = BreakoutGame(size: frame, seed: 5)
        let brick = try XCTUnwrap(smash.bricks.last)
        smash.place(ball: SIMD2(brick.rect.midX, brick.rect.minY - 20), velocity: SIMD2(120, 500))
        for _ in 0..<7 { smash.step(1.0 / 60, world: world(nil)) }
        save(try picture(base) { smash.draw(in: $0, time: 1) }, "breakout-smash", against: base)
    }

    func testBallPitPictures() throws {
        let lens = BallPitLens()
        let base = h.input()
        var out = base.composed
        for i in 0..<(30 * 9) { out = lens.render(h.at(base, time: Double(i) / 30)) }
        save(out, "ballpit-settled", against: base)
    }

    // MARK: The new games

    /// The synthetic person as rectangles a game can measure, and their head.
    private var personFrame: BodyFrame { BodyFrame(scan: BodyScan(matte: h.grid, size: frame))! }

    func testKeepyUppyPictures() throws {
        let base = h.input()
        var game = KeepyUppyGame(size: frame, seed: 3)
        for _ in 0..<12 { game.step(1.0 / 30, world: world(h.grid)) }
        save(try picture(base) { game.draw(in: $0, time: 0.4) }, "keepy-serve", against: base)
        // A hit off the top of the head, with a star hanging in the air.
        game.placeStar(at: SIMD2(900, 560))
        game.place(ball: SIMD2(640, 600), velocity: SIMD2(0, -500))
        let head = BodyRectsMatte(rects: [CGRect(x: 560, y: 470, width: 160, height: 80)])
        for _ in 0..<6 { game.step(1.0 / 30, world: world(h.grid, motion: head)) }
        save(try picture(base) { game.draw(in: $0, time: 1.2) }, "keepy-hit", against: base)
        for _ in 0..<10 { game.step(1.0 / 30, world: world(h.grid)) }
        save(try picture(base) { game.draw(in: $0, time: 1.6) }, "keepy-flight", against: base)
    }

    func testLaserLimboPictures() throws {
        let base = h.input()
        let ref = personFrame
        let headX = 640.0
        for pattern in LaserLimboGame.Pattern.allCases {
            var game = LaserLimboGame(size: frame, seed: 4)
            game.holdWaves()
            game.startWave(pattern, around: ref, headAt: headX)
            for _ in 0..<20 { game.step(1.0 / 30, world: world(nil)) }
            save(try picture(base) { game.draw(in: $0, time: 0.7) }, "laser-\(pattern)-warning", against: base)
            for _ in 0..<45 { game.step(1.0 / 30, world: world(nil)) }
            save(try picture(base) { game.draw(in: $0, time: 2.2) }, "laser-\(pattern)-hot", against: base)
        }
        var zap = LaserLimboGame(size: frame, seed: 5)
        zap.holdWaves()
        zap.startWave(.duck, around: ref, headAt: headX)
        for _ in 0..<70 { zap.step(1.0 / 30, world: world(h.grid)) }
        XCTAssertLessThan(zap.lives, 3, "standing tall under a duck bar is a hit")
        save(try picture(base) { zap.draw(in: $0, time: 2.4) }, "laser-zap", against: base)
    }

    func testPunchingBagPictures() throws {
        let base = h.input()
        var game = PunchingBagGame(size: frame, seed: 6)
        for _ in 0..<60 { game.step(1.0 / 30, world: world(h.grid)) }
        save(try picture(base) { game.draw(in: $0, time: 2) }, "bag-idle", against: base)
        let c = game.bagCenter
        let swing = BodyRectsMatte(rects: [CGRect(x: c.x - 160, y: c.y - 120, width: 150, height: 240)])
        game.step(1.0 / 30, world: world(h.grid, motion: swing))
        for _ in 0..<5 { game.step(1.0 / 30, world: world(h.grid)) }
        save(try picture(base) { game.draw(in: $0, time: 2.3) }, "bag-hit", against: base)
        for _ in 0..<12 { game.step(1.0 / 30, world: world(h.grid)) }
        save(try picture(base) { game.draw(in: $0, time: 2.7) }, "bag-swing", against: base)
    }

    func testGoalkeeperPictures() throws {
        let base = h.input()
        var game = GoalkeeperGame(size: frame, seed: 7)
        game.holdShots()
        for _ in 0..<10 { game.step(1.0 / 30, world: world(h.grid)) }
        game.shoot(at: SIMD2(880, 330), flight: 1.4)
        for _ in 0..<14 { game.step(1.0 / 30, world: world(h.grid)) }
        save(try picture(base) { game.draw(in: $0, time: 0.8) }, "goal-incoming", against: base)
        for _ in 0..<16 { game.step(1.0 / 30, world: world(h.grid)) }
        save(try picture(base) { game.draw(in: $0, time: 1.4) }, "goal-arriving", against: base)
        for _ in 0..<14 { game.step(1.0 / 30, world: world(h.grid)) }
        save(try picture(base) { game.draw(in: $0, time: 1.9) }, "goal-conceded", against: base)
        game.shoot(at: SIMD2(640, 300), flight: 0.6, golden: true)
        for _ in 0..<22 { game.step(1.0 / 30, world: world(h.grid)) }
        save(try picture(base) { game.draw(in: $0, time: 2.7) }, "goal-saved", against: base)
    }

    func testNinjaStarsPictures() throws {
        let base = h.input()
        var game = NinjaStarsGame(size: frame, seed: 8)
        game.holdThrows()
        game.throwStar(from: SIMD2(-40, 420), through: SIMD2(560, 330), telegraph: 0.6)
        game.throwStar(from: SIMD2(1320, 300), through: SIMD2(760, 360), telegraph: 0.9)
        for _ in 0..<14 { game.step(1.0 / 30, world: world(h.grid)) }
        save(try picture(base) { game.draw(in: $0, time: 0.5) }, "ninja-warning", against: base)
        for _ in 0..<10 { game.step(1.0 / 30, world: world(h.grid)) }
        save(try picture(base) { game.draw(in: $0, time: 0.8) }, "ninja-flying", against: base)
        let swat = BodyRectsMatte(rects: [CGRect(x: 700, y: 250, width: 300, height: 250), CGRect(x: 300, y: 250, width: 300, height: 250)])
        for _ in 0..<12 { game.step(1.0 / 30, world: world(h.grid, motion: swat)) }
        save(try picture(base) { game.draw(in: $0, time: 1.2) }, "ninja-block", against: base)
    }
}
