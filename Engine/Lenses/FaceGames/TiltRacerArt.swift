import CoreGraphics
import Foundation

/// Tilt Racer's cars, coins and roadside trees, seen from behind and drawn once each.
enum TiltRacerArt {
    typealias Tone = FaceGamePaint.Tone

    static let trafficTones = [FaceGamePalette.sky, FaceGamePalette.mint, FaceGamePalette.grape, FaceGamePalette.bubblegum, FaceGamePalette.cream]

    /// A car from behind, 240 by 180 pixels, its wheels on the bottom edge. `tone` is the paint; `player` adds a spoiler and stripes.
    static func car(_ index: Int, player: Bool) -> CGImage? {
        let tone = player ? FaceGamePalette.sun : trafficTones[index % trafficTones.count]
        return FaceGameArt.sprite("racer-car-\(index)-\(player)", width: 240, height: 180) { ctx, _ in
            let ink = FaceGamePalette.ink
            // Tyres.
            for x in [30.0, 172.0] {
                FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: x, y: 6, width: 38, height: 44), radius: 10), tone: Tone(0.16, 0.16, 0.22), edgeWidth: 2)
            }
            // The body: a wide rounded box, narrower at the roof.
            let body = CGMutablePath()
            body.move(to: CGPoint(x: 18, y: 30))
            body.addLine(to: CGPoint(x: 222, y: 30))
            body.addQuadCurve(to: CGPoint(x: 226, y: 92), control: CGPoint(x: 232, y: 60))
            body.addQuadCurve(to: CGPoint(x: 186, y: 104), control: CGPoint(x: 222, y: 104))
            body.addLine(to: CGPoint(x: 54, y: 104))
            body.addQuadCurve(to: CGPoint(x: 14, y: 92), control: CGPoint(x: 18, y: 104))
            body.addQuadCurve(to: CGPoint(x: 18, y: 30), control: CGPoint(x: 8, y: 60))
            body.closeSubpath()
            FaceGameArt.fillLit(ctx, body, tone: tone, edgeWidth: 3.5)
            let cabin = CGMutablePath()
            cabin.move(to: CGPoint(x: 52, y: 100))
            cabin.addLine(to: CGPoint(x: 188, y: 100))
            cabin.addQuadCurve(to: CGPoint(x: 168, y: 152), control: CGPoint(x: 186, y: 146))
            cabin.addLine(to: CGPoint(x: 72, y: 152))
            cabin.addQuadCurve(to: CGPoint(x: 52, y: 100), control: CGPoint(x: 54, y: 146))
            cabin.closeSubpath()
            FaceGameArt.fillLit(ctx, cabin, tone: tone * 0.92, edgeWidth: 3.5)
            // The rear window, dark with a streak of sky in it.
            let glass = CGMutablePath()
            glass.move(to: CGPoint(x: 66, y: 106))
            glass.addLine(to: CGPoint(x: 174, y: 106))
            glass.addQuadCurve(to: CGPoint(x: 160, y: 144), control: CGPoint(x: 172, y: 140))
            glass.addLine(to: CGPoint(x: 80, y: 144))
            glass.addQuadCurve(to: CGPoint(x: 66, y: 106), control: CGPoint(x: 68, y: 140))
            glass.closeSubpath()
            FaceGameArt.fillLit(ctx, glass, tone: Tone(0.2, 0.26, 0.4))
            ctx.saveGState()
            ctx.addPath(glass)
            ctx.clip()
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.sky, 0.35))
            let streak = CGMutablePath()
            streak.move(to: CGPoint(x: 90, y: 106)); streak.addLine(to: CGPoint(x: 112, y: 106))
            streak.addLine(to: CGPoint(x: 138, y: 144)); streak.addLine(to: CGPoint(x: 116, y: 144))
            streak.closeSubpath()
            ctx.addPath(streak)
            ctx.fillPath()
            ctx.restoreGState()
            // Tail lights, bumper and plate.
            for x in [26.0, 176.0] {
                FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: x, y: 62, width: 38, height: 18), radius: 7), tone: FaceGamePalette.coral, edgeWidth: 2)
                FaceGameArt.highlight(ctx, center: CGPoint(x: x + 12, y: 74), width: 14, height: 5, alpha: 0.7)
            }
            FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: 14, y: 26, width: 212, height: 18), radius: 8), tone: Tone(0.3, 0.32, 0.42), edgeWidth: 2)
            FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: 96, y: 52, width: 48, height: 20), radius: 4), tone: FaceGamePalette.cream, edgeWidth: 2)
            if player {
                // Racing stripes and a spoiler.
                ctx.saveGState()
                ctx.addPath(body)
                ctx.addPath(cabin)
                ctx.clip()
                ctx.setFillColor(FaceGamePaint.cg(ink, 0.85))
                ctx.fill(CGRect(x: 104, y: 30, width: 10, height: 130))
                ctx.fill(CGRect(x: 126, y: 30, width: 10, height: 130))
                ctx.restoreGState()
                FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: 30, y: 108, width: 180, height: 14), radius: 5), tone: Tone(0.22, 0.22, 0.3), edgeWidth: 2)
                for x in [56.0, 178.0] { ctx.setFillColor(FaceGamePaint.cg(Tone(0.22, 0.22, 0.3))); ctx.fill(CGRect(x: x, y: 96, width: 6, height: 14)) }
                FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: 70, y: 30, width: 18, height: 10), radius: 4), tone: Tone(0.7, 0.72, 0.78), edgeWidth: 1.5)
                FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: 152, y: 30, width: 18, height: 10), radius: 4), tone: Tone(0.7, 0.72, 0.78), edgeWidth: 1.5)
            }
        }
    }

    /// A gold coin, face on, with a star pressed into it.
    static var coin: CGImage? {
        FaceGameArt.sprite("racer-coin", width: 80, height: 80) { ctx, _ in
            let c = CGPoint(x: 40, y: 40)
            FaceGameArt.litBall(ctx, center: c, radius: 34, tone: FaceGamePalette.sun, edgeWidth: 3, gloss: 0)
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: FaceGamePalette.sun), 0.6))
            ctx.setLineWidth(2.5)
            ctx.strokeEllipse(in: CGRect(x: c.x - 25, y: c.y - 25, width: 50, height: 50))
            FaceGameArt.fillLit(ctx, FaceGameArt.star(center: c, radius: 16, inner: 0.5, round: true), tone: FaceGameArt.lighter(FaceGamePalette.sun, 0.3), edgeWidth: 1.5)
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 13, y: c.y + 15), width: 18, height: 9, rotation: 0.6, alpha: 0.8)
        }
    }

    /// Roadside greenery seen from the side: a round tree, a pine or a bush. Standing on the bottom middle of the picture.
    static func tree(_ kind: Int) -> CGImage? {
        FaceGameArt.sprite("racer-tree-\(kind % 3)", width: 160, height: 220) { ctx, _ in
            let trunk = Tone(0.5, 0.33, 0.2)
            switch kind % 3 {
            case 0:
                FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: 70, y: 4, width: 20, height: 90), radius: 6), tone: trunk, edgeWidth: 2.5)
                let crown = CGMutablePath()
                for (x, y, r) in [(80.0, 150.0, 52.0), (48.0, 118.0, 38.0), (114.0, 120.0, 38.0), (80.0, 104.0, 40.0)] {
                    crown.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
                FaceGameArt.fillLit(ctx, crown, tone: FaceGamePalette.leaf, edgeWidth: 3)
                FaceGameArt.highlight(ctx, center: CGPoint(x: 62, y: 170), width: 34, height: 18, rotation: 0.6, alpha: 0.35)
            case 1:
                FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: 72, y: 4, width: 16, height: 40), radius: 5), tone: trunk, edgeWidth: 2.5)
                for (k, w) in [(0.0, 64.0), (1.0, 50.0), (2.0, 36.0)] {
                    let y = 34 + k * 50
                    let tier = CGMutablePath()
                    tier.move(to: CGPoint(x: 80 - w, y: y))
                    tier.addQuadCurve(to: CGPoint(x: 80 + w, y: y), control: CGPoint(x: 80, y: y - 14))
                    tier.addLine(to: CGPoint(x: 80, y: y + 90))
                    tier.closeSubpath()
                    FaceGameArt.fillLit(ctx, tier, tone: FaceGamePalette.leaf * 0.82, edgeWidth: 3)
                }
            default:
                let bush = CGMutablePath()
                for (x, y, r) in [(50.0, 40.0, 34.0), (84.0, 52.0, 42.0), (118.0, 40.0, 32.0)] {
                    bush.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
                bush.addRect(CGRect(x: 18, y: 6, width: 132, height: 34))
                FaceGameArt.fillLit(ctx, bush, tone: FaceGamePalette.leaf * 1.05, edgeWidth: 3)
                for (x, y) in [(56.0, 50.0), (96.0, 66.0), (118.0, 44.0)] {
                    FaceGameArt.litBall(ctx, center: CGPoint(x: x, y: y), radius: 5, tone: FaceGamePalette.bubblegum, gloss: 0.4)
                }
            }
        }
    }
}
