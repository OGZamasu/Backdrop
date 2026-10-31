import CoreGraphics
import Foundation

/// Space Blaster's ship, rocks, saucer and planet, drawn in vector once and kept.
enum SpaceBlasterArt {
    typealias Tone = FaceGamePaint.Tone

    static let hull = Tone(0.9, 0.92, 0.98)
    static let trim = FaceGamePalette.coral
    static let rockTone = Tone(0.56, 0.5, 0.64)
    /// Where the cockpit is on the ship picture, from its middle, and how big; the pilot's face goes there.
    static let cockpit = CGPoint(x: 0, y: 14)
    static let cockpitRadius = 27.0

    /// The ship, 180 by 200 pixels, nose up, centred on its middle.
    static var ship: CGImage? {
        FaceGameArt.sprite("blaster-ship", width: 180, height: 200) { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            // Wings.
            for side in [-1.0, 1.0] {
                let wing = CGMutablePath()
                wing.move(to: CGPoint(x: c.x + side * 22, y: c.y + 10))
                wing.addLine(to: CGPoint(x: c.x + side * 82, y: c.y - 44))
                wing.addQuadCurve(to: CGPoint(x: c.x + side * 70, y: c.y - 66), control: CGPoint(x: c.x + side * 88, y: c.y - 64))
                wing.addLine(to: CGPoint(x: c.x + side * 24, y: c.y - 50))
                wing.closeSubpath()
                FaceGameArt.fillLit(ctx, wing, tone: trim, edgeWidth: 3)
                FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: c.x + side * 76 - 6, y: c.y - 70, width: 12, height: 40), radius: 6), tone: hull, edgeWidth: 2.5)
            }
            // The fuselage: a rounded dart.
            let body = CGMutablePath()
            body.move(to: CGPoint(x: c.x, y: c.y + 92))
            body.addCurve(to: CGPoint(x: c.x - 34, y: c.y - 40), control1: CGPoint(x: c.x - 26, y: c.y + 70), control2: CGPoint(x: c.x - 38, y: c.y + 10))
            body.addQuadCurve(to: CGPoint(x: c.x + 34, y: c.y - 40), control: CGPoint(x: c.x, y: c.y - 70))
            body.addCurve(to: CGPoint(x: c.x, y: c.y + 92), control1: CGPoint(x: c.x + 38, y: c.y + 10), control2: CGPoint(x: c.x + 26, y: c.y + 70))
            body.closeSubpath()
            FaceGameArt.fillLit(ctx, body, tone: hull, edgeWidth: 3.5, edgeTone: Tone(0.32, 0.36, 0.52))
            // A racing stripe and the nose cone.
            ctx.saveGState()
            ctx.addPath(body)
            ctx.clip()
            ctx.setFillColor(FaceGamePaint.cg(trim))
            ctx.fill(CGRect(x: c.x - 34, y: c.y - 30, width: 68, height: 10))
            let cone = CGMutablePath()
            cone.addEllipse(in: CGRect(x: c.x - 30, y: c.y + 58, width: 60, height: 60))
            FaceGameArt.fillLit(ctx, cone, tone: trim)
            ctx.restoreGState()
            // The engine.
            FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(CGRect(x: c.x - 18, y: c.y - 62, width: 36, height: 20), radius: 6), tone: Tone(0.5, 0.52, 0.62), edgeWidth: 2.5)
            // The cockpit rim.
            let pit = CGPoint(x: c.x + cockpit.x, y: c.y + cockpit.y)
            FaceGameArt.litBall(ctx, center: pit, radius: cockpitRadius + 6, tone: Tone(0.4, 0.44, 0.6), edgeWidth: 2, gloss: 0)
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.ink))
            ctx.fillEllipse(in: CGRect(x: pit.x - cockpitRadius, y: pit.y - cockpitRadius, width: cockpitRadius * 2, height: cockpitRadius * 2))
        }
    }

    /// The glass over the cockpit: a tint and a glint, drawn over the pilot's face.
    static var glass: CGImage? {
        FaceGameArt.sprite("blaster-glass", width: 64, height: 64) { ctx, _ in
            let r = cockpitRadius
            let c = CGPoint(x: 32, y: 32)
            ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.clip()
            if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: [FaceGamePaint.cg(FaceGamePalette.sky, 0.05), FaceGamePaint.cg(FaceGamePalette.sky, 0.35)] as CFArray,
                                  locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            }
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 9, y: c.y + 11), width: 22, height: 10, rotation: 0.7, alpha: 0.85)
        }
    }

    /// A space rock, 128 pixels square, lumpy and cratered.
    static func rock(_ variant: Int) -> CGImage? {
        FaceGameArt.sprite("blaster-rock-\(variant)", width: 128, height: 128) { ctx, _ in
            let c = CGPoint(x: 64, y: 64)
            var radii: [Double] = []
            for i in 0..<11 { radii.append(52 + 8 * FaceGamePaint.hash(i + variant * 31, 4) - 4) }
            let body = FaceGameArt.blob(center: c, radii: radii, rotation: Double(variant))
            FaceGameArt.fillLit(ctx, body, tone: rockTone, edgeWidth: 3.5)
            ctx.saveGState()
            ctx.addPath(body)
            ctx.clip()
            for k in 0..<4 {
                let a = FaceGamePaint.hash(k + variant * 7, 1) * 2 * .pi, d = 10 + 26 * FaceGamePaint.hash(k + variant * 7, 2)
                let r = 7 + 9 * FaceGamePaint.hash(k + variant * 7, 3)
                let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
                // A crater: shaded on its upper left inside, lit on its lower right rim.
                ctx.setFillColor(FaceGamePaint.cg(rockTone * 0.62))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.85, width: r * 2, height: r * 1.7))
                ctx.setFillColor(FaceGamePaint.cg(FaceGameArt.lighter(rockTone, 0.25)))
                ctx.fillEllipse(in: CGRect(x: p.x - r * 0.55, y: p.y - r * 0.8, width: r * 1.5, height: r * 1.1))
                ctx.setFillColor(FaceGamePaint.cg(rockTone * 0.78))
                ctx.fillEllipse(in: CGRect(x: p.x - r * 0.8, y: p.y - r * 0.5, width: r * 1.5, height: r * 1.25))
            }
            ctx.restoreGState()
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 18, y: c.y + 24), width: 30, height: 14, rotation: 0.7, alpha: 0.35)
        }
    }

    /// A flying saucer, 160 by 100 pixels; its lights are drawn live so they can chase.
    static var saucer: CGImage? {
        FaceGameArt.sprite("blaster-saucer", width: 160, height: 100) { ctx, _ in
            let dome = CGMutablePath()
            dome.addEllipse(in: CGRect(x: 50, y: 40, width: 60, height: 52))
            FaceGameArt.fillLit(ctx, dome, tone: FaceGamePalette.mint, edgeWidth: 3)
            FaceGameArt.highlight(ctx, center: CGPoint(x: 70, y: 76), width: 18, height: 9, rotation: 0.6, alpha: 0.8)
            let disc = CGMutablePath()
            disc.addEllipse(in: CGRect(x: 8, y: 22, width: 144, height: 40))
            FaceGameArt.fillLit(ctx, disc, tone: Tone(0.72, 0.74, 0.86), edgeWidth: 3.5)
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.42, 0.44, 0.58)))
            ctx.fillEllipse(in: CGRect(x: 40, y: 18, width: 80, height: 16))
        }
    }

    /// A ringed planet in the distance.
    static var planet: CGImage? {
        FaceGameArt.sprite("blaster-planet", width: 300, height: 220) { ctx, _ in
            let c = CGPoint(x: 150, y: 110)
            let ring = CGRect(x: c.x - 140, y: c.y - 30, width: 280, height: 60)
            func ringArc(front: Bool) {
                ctx.saveGState()
                ctx.clip(to: front ? CGRect(x: 0, y: 0, width: 300, height: c.y) : CGRect(x: 0, y: c.y, width: 300, height: 110))
                ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.sun, 0.75))
                ctx.setLineWidth(10)
                ctx.strokeEllipse(in: ring)
                ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.cream, 0.5))
                ctx.setLineWidth(3)
                ctx.strokeEllipse(in: ring.insetBy(dx: 12, dy: 4))
                ctx.restoreGState()
            }
            ringArc(front: false)
            FaceGameArt.litBall(ctx, center: c, radius: 78, tone: FaceGamePalette.grape, edgeWidth: 0, gloss: 0.3)
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: c.x - 78, y: c.y - 78, width: 156, height: 156))
            ctx.clip()
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.bubblegum, 0.25))
            for (y, h) in [(18.0, 16.0), (-12.0, 10.0), (-40.0, 14.0)] { ctx.fill(CGRect(x: c.x - 80, y: c.y + y, width: 160, height: h)) }
            ctx.restoreGState()
            ringArc(front: true)
        }
    }
}
