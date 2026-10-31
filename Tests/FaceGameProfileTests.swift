import CoreImage
import simd
import XCTest

/// Times how long each face game takes to draw one frame on the overlay, as the fastest of many tries so a busy machine doesn't
/// cloud the number. Prints a line per game and per shared drawing piece, for working on the games' speed.
final class FaceGameProfileTests: XCTestCase {
    private func fastest(_ times: Int = 30, _ body: () -> Void) -> Double {
        var best = Double.infinity
        for _ in 0..<times {
            let start = CFAbsoluteTimeGetCurrent()
            body()
            best = min(best, (CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        return best
    }

    func testHowLongEachGameTakesToDraw() {
        let canvas = OverlayCanvas(size: CGSize(width: 1280, height: 720), slots: 1)!
        func profile<G: FaceGame>(_ type: G.Type, seconds: Double = 6, scene: @escaping (Double, G) -> SyntheticScene) -> String {
            var game = G(size: CGSize(width: 1280, height: 720), seed: 3)
            var t = 0.0
            while t < seconds {
                game.step(1.0 / 30, world: GameWorld(size: CGSize(width: 1280, height: 720), matte: nil, motion: nil, face: scene(t, game).face()))
                t += 1.0 / 30
            }
            let ms = fastest {
                let ctx = canvas.begin()
                ctx.interpolationQuality = .low
                game.draw(in: ctx, time: t)
                _ = canvas.image()
            }
            XCTAssertLessThan(ms, 8, "\(G.title) takes too long to draw")
            return String(format: "%@ %.2f", G.title, ms)
        }
        var lines: [String] = []
        lines.append(profile(MouthCatchGame.self) { t, _ in faceGameScene(mouth: sin(t * 2) > 0 ? 0.8 : 0) })
        lines.append(profile(FlappyFaceGame.self) { _, g in faceGameScene(at: CGPoint(x: 640, y: (g.pipes.first { $0.x + 120 > g.birdX - 40 }?.gapCenter ?? 360) - 20)) })
        lines.append(profile(StaringContestGame.self, seconds: 20) { _, _ in faceGameScene() })
        lines.append(profile(BrowRunnerGame.self) { _, g in faceGameScene(brows: faceGameBrowBot(g)) })
        lines.append(profile(FaceSnakeGame.self) { _, _ in faceGameScene() })
        lines.append(profile(CopyCatGame.self) { _, g in g.cardAge > 1 ? faceGameCopy(g.current) : faceGameScene() })
        lines.append(profile(SpaceBlasterGame.self) { _, _ in faceGameScene(mouth: 0.8) })
        lines.append(profile(FaceKeepyUppyGame.self) { _, g in faceGameScene(at: CGPoint(x: g.ball.x, y: 360)) })
        lines.append(profile(TiltRacerGame.self) { _, g in faceGameScene(roll: faceGameRacerRoll(g)) })
        lines.append(profile(BubbleGumGame.self) { _, _ in faceGameScene(mouth: 0.8) })

        // And the pieces everyone uses.
        let plate = fastest {
            let ctx = canvas.begin()
            let look = GameScreens.Look(title: "Test", hint: "", presenceHint: "", accent: FaceGamePalette.sky, icon: .face(.openMouth), scoreLabel: "POINTS",
                                        player: .face)
            GameScreens.plates(ctx, size: CGSize(width: 1280, height: 720), look: look, readout: GameUIReadout(score: 123, lives: (2, 3), time: (12, 45)),
                               scoreText: "123", best: "456", record: false, motion: GameUIMotion(), time: 1)
            _ = canvas.image()
        }
        let empty = fastest {
            _ = canvas.begin()
            _ = canvas.image()
        }
        lines.append(String(format: "HUD %.2f, empty canvas %.2f", plate, empty))
        print("FACEGAME DRAW MS (fastest): " + lines.joined(separator: " | "))
    }

    func testWhatThePiecesCost() {
        let canvas = OverlayCanvas(size: CGSize(width: 1280, height: 720), slots: 1)!
        func cost(_ name: String, _ draw: (CGContext) -> Void) -> String {
            let ms = fastest(20) {
                let ctx = canvas.begin()
                ctx.interpolationQuality = .low
                draw(ctx)
                _ = canvas.image()
            }
            return String(format: "%@ %.2f", name, ms)
        }
        let rect = CGRect(x: 470, y: 250, width: 330, height: 330)
        let crop = FaceGameFood.sprite(.apple)
        var parts: [String] = []
        parts.append(cost("fillLit330") { FaceGameArt.fillLit($0, FaceGamePaint.roundedPath(rect, radius: 40), tone: FaceGamePalette.mint, edgeWidth: 4) })
        parts.append(cost("solid330") { ctx in ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.mint)); ctx.addPath(FaceGamePaint.roundedPath(rect, radius: 40)); ctx.fillPath() })
        parts.append(cost("face300") { FaceGamePaint.drawFace($0, crop: crop, in: rect.insetBy(dx: 15, dy: 15), corner: 30) })
        parts.append(cost("spark420") { FaceGamePaint.spark($0, at: CGPoint(x: 640, y: 360), radius: 420, tone: FaceGamePalette.cream, alpha: 0.3) })
        parts.append(cost("glow420") { $0.glow(center: CGPoint(x: 640, y: 360), radius: 420, red: 1, green: 1, blue: 1, alpha: 0.3) })
        parts.append(cost("goofs11") { ctx in for i in 0..<11 { FaceGameArt.stamp(ctx, StaringContestArt.goof(i), at: CGPoint(x: 100 + Double(i) * 100, y: 300), height: 120, rotation: 0.2) } })
        parts.append(cost("shadows11") { ctx in for i in 0..<11 { FaceGameArt.contactShadow(ctx, center: CGPoint(x: 100 + Double(i) * 100, y: 300), width: 90, height: 20) } })
        parts.append(cost("bulbs40") { ctx in for i in 0..<40 { FaceGamePaint.spark(ctx, at: CGPoint(x: 100 + Double(i) * 25, y: 300), radius: 22, tone: FaceGamePalette.sun, alpha: 0.7) } })
        parts.append(cost("ellipses80") { ctx in for i in 0..<80 { ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.ink)); ctx.fillEllipse(in: CGRect(x: 100 + Double(i) * 12, y: 300, width: 19, height: 19)) } })
        parts.append(cost("swirl") { ctx in
            ctx.setLineWidth(30); ctx.setLineCap(.round); ctx.setLineJoin(.bevel)
            for arm in 0..<2 {
                ctx.beginPath()
                for i in 0...44 {
                    let f = Double(i) / 44, theta = f * 4 * .pi + Double(arm) * .pi, r = 150 + f * 420
                    let p = CGPoint(x: 640 + cos(theta) * r * 1.45, y: 400 + sin(theta) * r * 0.9)
                    if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
                }
                ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.grape, 0.3)); ctx.strokePath()
            }
        })
        parts.append(cost("veil") { ctx in ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.ink, 0.5)); ctx.fill(CGRect(x: 0, y: 0, width: 1280, height: 720)) })
        parts.append(cost("sticker40") { FaceGamePaint.sticker($0, "BLINK AND YOU LOSE", center: CGPoint(x: 640, y: 650), size: 40, scale: 0.98) })
        parts.append(cost("haloRings") { ctx in
            for grow in [60.0, 42.0, 24.0] { FaceGamePaint.stroke(ctx, rounded: rect.insetBy(dx: -grow, dy: -grow), radius: 44 + grow, color: FaceGamePaint.cg(FaceGamePalette.mint, 0.1), width: 18) }
        })
        print("FACEGAME PIECES MS: " + parts.joined(separator: " | "))
    }
}
