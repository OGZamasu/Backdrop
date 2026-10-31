import CoreGraphics
import Foundation

/// The little round face the face games use to show you what to do: it raises its brows, opens wide, tilts, smiles. It also
/// stands in for your face before the camera has handed over a picture of it.
enum FaceGameMascot {
    typealias Tone = FaceGamePaint.Tone

    /// What the face is doing, each 0...1 except `tilt` (radians).
    struct Pose {
        var eyes = 1.0
        var brows = 0.0
        var mouth = 0.0
        var smile = 0.45
        var tilt = 0.0
        var dizzy = false
    }

    enum Mood { case happy, dizzy }

    static func draw(_ ctx: CGContext, in rect: CGRect, mood: Mood) {
        draw(ctx, center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
             pose: Pose(smile: mood == .happy ? 0.7 : 0, dizzy: mood == .dizzy))
    }

    /// The disc itself, lit from the top left, drawn once.
    private static var disc: CGImage? {
        FaceGameArt.sprite("mascot-disc", width: 192, height: 192) { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            FaceGameArt.litBall(ctx, center: c, radius: 88, tone: FaceGamePalette.sun, edgeWidth: 5, gloss: 0)
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 34, y: c.y + 46), width: 52, height: 26, rotation: 0.55, alpha: 0.55)
            for side in [-1.0, 1.0] {
                FaceGamePaint.spark(ctx, at: CGPoint(x: c.x + side * 50, y: c.y - 22), radius: 22, tone: FaceGamePalette.coral, alpha: 0.4)
            }
        }
    }

    /// Draws the face at `center`, `radius` pixels round, doing `pose`.
    static func draw(_ ctx: CGContext, center c: CGPoint, radius r: Double, pose: Pose) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(pose.tilt))
        if let disc { ctx.draw(disc, in: CGRect(x: -r * 1.09, y: -r * 1.09, width: r * 2.18, height: r * 2.18)) }
        let ink = FaceGamePaint.cg(FaceGamePalette.ink)
        ctx.setLineCap(.round)

        // Eyes.
        for side in [-1.0, 1.0] {
            let e = CGPoint(x: side * r * 0.34, y: r * 0.12)
            if pose.dizzy {
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(CGFloat(r * 0.09))
                let s = r * 0.12
                ctx.move(to: CGPoint(x: e.x - s, y: e.y - s)); ctx.addLine(to: CGPoint(x: e.x + s, y: e.y + s))
                ctx.move(to: CGPoint(x: e.x - s, y: e.y + s)); ctx.addLine(to: CGPoint(x: e.x + s, y: e.y - s))
                ctx.strokePath()
            } else if pose.eyes < 0.18 {
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(CGFloat(r * 0.08))
                ctx.addArc(center: CGPoint(x: e.x, y: e.y + r * 0.06), radius: CGFloat(r * 0.14), startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
                ctx.strokePath()
            } else {
                let h = r * 0.3 * pose.eyes, w = r * 0.21
                ctx.setFillColor(ink)
                ctx.fillEllipse(in: CGRect(x: e.x - w / 2, y: e.y - h / 2, width: w, height: h))
                ctx.setFillColor(FaceGamePaint.cg(Tone(1, 1, 1), 0.95))
                let g = r * 0.075
                ctx.fillEllipse(in: CGRect(x: e.x - w * 0.28 - g / 2, y: e.y + h * 0.18 - g / 2, width: g, height: g))
            }
            // Brows.
            let lift = r * (0.36 + 0.2 * pose.brows)
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(CGFloat(r * 0.075))
            ctx.move(to: CGPoint(x: e.x - side * r * 0.13, y: lift - r * 0.02 + side * 0))
            ctx.addQuadCurve(to: CGPoint(x: e.x + side * r * 0.13, y: lift - r * 0.03 * (1 - pose.brows)),
                             control: CGPoint(x: e.x, y: lift + r * 0.05 + r * 0.04 * pose.brows))
            ctx.strokePath()
        }

        // Mouth: an opening when it is open, otherwise a curve that smiles as much as asked.
        let mouthY = -r * 0.36
        if pose.mouth > 0.08 {
            let w = r * (0.32 + 0.06 * pose.smile), h = r * (0.1 + 0.42 * pose.mouth)
            let hole = CGRect(x: -w / 2, y: mouthY - h / 2 - r * 0.02, width: w, height: h)
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.42, 0.08, 0.14)))
            ctx.fillEllipse(in: hole)
            ctx.saveGState()
            ctx.addEllipse(in: hole)
            ctx.clip()
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.coral))
            ctx.fillEllipse(in: CGRect(x: -w * 0.36, y: hole.minY - h * 0.2, width: w * 0.72, height: h * 0.55))
            ctx.restoreGState()
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(CGFloat(r * 0.05))
            ctx.strokeEllipse(in: hole)
        } else {
            let w = r * (0.34 + 0.16 * pose.smile)
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(CGFloat(r * 0.08))
            ctx.move(to: CGPoint(x: -w / 2, y: mouthY + r * 0.06 * pose.smile))
            ctx.addQuadCurve(to: CGPoint(x: w / 2, y: mouthY + r * 0.06 * pose.smile), control: CGPoint(x: 0, y: mouthY - r * (0.02 + 0.26 * pose.smile)))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: Acting out a move

    /// The little face acting out a move, `radius` pixels round, looping with the clock.
    static func act(_ ctx: CGContext, _ move: FaceGameMove, center c: CGPoint, radius r: Double, time: Double) {
        var pose = FaceGameMascot.Pose()
        var at = c
        let cycle = FaceGamePaint.wrap(time, 1.6) / 1.6
        let held = FaceGamePaint.smoothstep(0.1, 0.25, cycle) * (1 - FaceGamePaint.smoothstep(0.65, 0.8, cycle))
        var arrows: [(CGPoint, Double)] = []
        switch move {
        case .keepEyesOpen:
            pose.eyes = 1.25 + 0.05 * sin(time * 20)
            pose.brows = 0.55
            pose.smile = 0.1
        case .raiseBrows:
            pose.brows = held
            pose.eyes = 1 + 0.2 * held
            if held > 0.5 { arrows.append((CGPoint(x: c.x, y: c.y + r * 1.22), .pi / 2)) }
        case .openMouth:
            pose.mouth = held
            pose.brows = 0.3 * held
        case .moveHead:
            at.x += sin(time * 2.6) * r * 0.32
            arrows = [(CGPoint(x: c.x - r * 1.3, y: c.y), .pi), (CGPoint(x: c.x + r * 1.3, y: c.y), 0)]
        case .nodHead:
            at.y += sin(time * 2.6) * r * 0.22
            arrows = [(CGPoint(x: c.x + r * 1.25, y: c.y + r * 0.45), .pi / 2), (CGPoint(x: c.x + r * 1.25, y: c.y - r * 0.45), -.pi / 2)]
        case .steerNose:
            at.x += cos(time * 2.2) * r * 0.22
            at.y += sin(time * 2.2) * r * 0.16
            pose.tilt = cos(time * 2.2) * 0.1
        case .tiltHead:
            pose.tilt = sin(time * 2.4) * 0.38
        case .smile:
            pose.smile = 0.15 + 0.85 * held
        case .copyFaces:
            let step = Int(FaceGamePaint.wrap(time, 4.5) / 0.9)
            switch step {
            case 0: pose.smile = 1
            case 1: pose.mouth = 0.9
            case 2: pose.brows = 1; pose.eyes = 1.2
            case 3: pose.eyes = 0
            default: pose.tilt = 0.35
            }
        }
        FaceGameMascot.draw(ctx, center: at, radius: r, pose: pose)
        for (p, angle) in arrows { chevron(ctx, at: p, angle: angle, size: r * 0.3) }
    }

    private static func chevron(_ ctx: CGContext, at p: CGPoint, angle: Double, size s: Double) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: CGFloat(angle))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for (width, tone, alpha) in [(s * 0.55, FaceGamePalette.ink, 0.6), (s * 0.3, FaceGamePalette.cream, 1.0)] {
            ctx.setStrokeColor(FaceGamePaint.cg(tone, alpha))
            ctx.setLineWidth(CGFloat(width))
            ctx.move(to: CGPoint(x: -s * 0.4, y: s * 0.7))
            ctx.addLine(to: CGPoint(x: s * 0.4, y: 0))
            ctx.addLine(to: CGPoint(x: -s * 0.4, y: -s * 0.7))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
