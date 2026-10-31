import CoreGraphics
import Foundation

/// The sky, hills and ground behind the runner. It is a pure function of how far you have run and the clock, so it needs no
/// state: far things slide past slowly and near things quickly (parallax), and the light turns from day to night and back.
enum BrowRunnerScenery {
    typealias Tone = FaceGamePaint.Tone

    /// How far round the day we are: 1 at noon, 0.5 at sunset, 0 in the dead of night.
    static func daylight(meters: Double, cycleMeters: Double) -> Double {
        (1 + cos(2 * .pi * meters / cycleMeters)) / 2
    }

    private struct Light {
        /// Radians round the day: 0 at noon, pi at midnight.
        let theta: Double
        var sun: Double { cos(theta) }
        /// 1 in full day, 0 at night.
        var day: Double { FaceGamePaint.smoothstep(-0.3, 0.4, sun) }
        /// 1 at sunset and sunrise, fading either side.
        var dusk: Double { max(0, 1 - abs(sun) / 0.4) }

        func pick(day dayTone: Tone, night nightTone: Tone) -> Tone {
            let base = FaceGamePaint.mix(nightTone, dayTone, day)
            return FaceGamePaint.mix(base, Tone(1, 0.55, 0.3), dusk * 0.28)
        }
    }

    static func draw(_ ctx: CGContext, size: CGSize, groundY: Double, distance: Double, time: Double, cycleMeters: Double, pixelsPerMeter: Double) {
        let light = Light(theta: 2 * .pi * distance / (cycleMeters * pixelsPerMeter))
        drawWash(ctx, size: size, groundY: groundY, light: light)
        drawStars(ctx, size: size, groundY: groundY, light: light, time: time)
        drawSkyBodies(ctx, size: size, groundY: groundY, light: light)
        drawClouds(ctx, size: size, distance: distance, time: time, light: light)
        drawMountains(ctx, size: size, groundY: groundY, scroll: distance * 0.06, light: light)
        drawHills(ctx, size: size, groundY: groundY, scroll: distance * 0.16, light: light)
        drawTrees(ctx, size: size, groundY: groundY, scroll: distance * 0.42, light: light)
        drawGround(ctx, size: size, groundY: groundY, scroll: distance, light: light)
    }

    // MARK: Sky

    /// A tint over the whole picture: navy at night, orange at the edges of the day.
    private static func drawWash(_ ctx: CGContext, size: CGSize, groundY: Double, light: Light) {
        let night = 1 - light.day
        if night > 0.01 {
            let top = FaceGamePaint.cg(Tone(0.02, 0.03, 0.16), 0.5 * night)
            let bottom = FaceGamePaint.cg(Tone(0.05, 0.06, 0.24), 0.3 * night)
            if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: [bottom, top] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: groundY), end: CGPoint(x: 0, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        }
        if light.dusk > 0.01 {
            let warm = FaceGamePaint.cg(Tone(1, 0.5, 0.2), 0.34 * light.dusk)
            let clear = FaceGamePaint.cg(Tone(1, 0.5, 0.2), 0)
            if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: [warm, clear] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: groundY), end: CGPoint(x: 0, y: groundY + 420), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        }
    }

    private static func drawStars(_ ctx: CGContext, size: CGSize, groundY: Double, light: Light, time: Double) {
        let night = 1 - FaceGamePaint.smoothstep(-0.05, 0.3, light.sun)
        guard night > 0.02 else { return }
        for i in 0..<70 {
            let x = FaceGamePaint.hash(i, 1) * size.width
            let y = groundY + 150 + FaceGamePaint.hash(i, 2) * (size.height - groundY - 170)
            let twinkle = 0.55 + 0.45 * sin(time * (1.5 + FaceGamePaint.hash(i, 3) * 3) + Double(i))
            FaceGamePaint.spark(ctx, at: CGPoint(x: x, y: y), radius: 3 + 4 * FaceGamePaint.hash(i, 4), tone: Tone(1, 1, 0.85), alpha: night * twinkle)
        }
    }

    /// The sun climbs from the left, crosses and sets on the right; the moon follows the same road half a day later.
    private static func drawSkyBodies(_ ctx: CGContext, size: CGSize, groundY: Double, light: Light) {
        func place(_ phase: Double) -> (point: CGPoint, height: Double) {
            let h = cos(phase)
            return (CGPoint(x: size.width * (0.5 + 0.4 * sin(phase)), y: groundY + 30 + 400 * max(h, -0.15)), h)
        }
        let sun = place(light.theta)
        if sun.height > -0.12 {
            let glowTone = FaceGamePaint.mix(Tone(1, 0.55, 0.25), Tone(1, 0.9, 0.5), light.day)
            ctx.glow(center: sun.point, radius: 190, red: glowTone.x, green: glowTone.y, blue: glowTone.z, alpha: 0.55)
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePaint.mix(Tone(1, 0.5, 0.2), Tone(1, 0.92, 0.35), light.day)))
            ctx.fillEllipse(in: CGRect(x: sun.point.x - 46, y: sun.point.y - 46, width: 92, height: 92))
        }
        let moon = place(light.theta + .pi)
        if moon.height > -0.12 {
            ctx.glow(center: moon.point, radius: 170, red: 0.7, green: 0.8, blue: 1, alpha: 0.45)
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.96, 0.97, 1)))
            ctx.fillEllipse(in: CGRect(x: moon.point.x - 40, y: moon.point.y - 40, width: 80, height: 80))
            ctx.setFillColor(FaceGamePaint.cg(Tone(0.78, 0.82, 0.92)))
            for (dx, dy, r) in [(-14.0, 10.0, 11.0), (12.0, -8.0, 8.0), (8.0, 18.0, 6.0)] {
                ctx.fillEllipse(in: CGRect(x: moon.point.x + dx - r, y: moon.point.y + dy - r, width: r * 2, height: r * 2))
            }
        }
    }

    /// The same drawn clouds as Flappy Face, fainter at night.
    private static func drawClouds(_ ctx: CGContext, size: CGSize, distance: Double, time: Double, light: Light) {
        let loop = 2160.0
        let alpha = 0.35 + 0.55 * light.day
        for i in 0..<6 {
            let x = FaceGamePaint.wrap(Double(i) * loop / 6 - distance * 0.05 - time * 6, loop) - 220
            let y = 470 + Double(i % 3) * 58 + FaceGamePaint.hash(i, 5) * 30
            guard let image = FlappyFaceArt.cloud(i % 2, small: i % 3 == 1) else { continue }
            FaceGameArt.blit(ctx, image, at: CGPoint(x: x - Double(image.width) / 2, y: y - Double(image.height) / 2), alpha: alpha)
        }
    }

    // MARK: Land

    private static func drawMountains(_ ctx: CGContext, size: CGSize, groundY: Double, scroll: Double, light: Light) {
        let tile = 340.0
        let first = Int((scroll / tile).rounded(.down)) - 1
        let last = first + Int(size.width / tile) + 3
        let path = CGMutablePath()
        path.move(to: CGPoint(x: Double(first) * tile - scroll, y: groundY - 10))
        for n in first...last {
            let x = Double(n) * tile - scroll
            let valley = groundY + 20 + 50 * FaceGamePaint.hash(n, 7)
            let peak = groundY + 120 + 110 * FaceGamePaint.hash(n, 8)
            path.addLine(to: CGPoint(x: x, y: valley))
            path.addLine(to: CGPoint(x: x + tile * (0.35 + 0.3 * FaceGamePaint.hash(n, 9)), y: peak))
        }
        path.addLine(to: CGPoint(x: Double(last + 1) * tile - scroll, y: groundY - 10))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(FaceGamePaint.cg(light.pick(day: Tone(0.46, 0.58, 0.82), night: Tone(0.1, 0.13, 0.34)), 0.7))
        ctx.fillPath()
    }

    private static func drawHills(_ ctx: CGContext, size: CGSize, groundY: Double, scroll: Double, light: Light) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -10, y: groundY - 10))
        var x = -10.0
        while x <= size.width + 20 {
            let w = x + scroll
            path.addLine(to: CGPoint(x: x, y: groundY + 46 + 36 * sin(w * 0.0105 + 1.3) + 20 * sin(w * 0.026)))
            x += 16
        }
        path.addLine(to: CGPoint(x: size.width + 20, y: groundY - 10))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(FaceGamePaint.cg(light.pick(day: Tone(0.27, 0.68, 0.42), night: Tone(0.05, 0.22, 0.24)), 0.85))
        ctx.fillPath()
    }

    private static func drawTrees(_ ctx: CGContext, size: CGSize, groundY: Double, scroll: Double, light: Light) {
        let tile = 170.0
        let first = Int((scroll / tile).rounded(.down)) - 1
        let last = first + Int(size.width / tile) + 3
        let leaf = light.pick(day: Tone(0.1, 0.46, 0.26), night: Tone(0.02, 0.13, 0.16))
        let trunk = light.pick(day: Tone(0.42, 0.28, 0.16), night: Tone(0.08, 0.06, 0.1))
        for n in first...last {
            let x = Double(n) * tile - scroll + FaceGamePaint.hash(n, 10) * 60
            let kind = FaceGamePaint.hash(n, 11)
            let h = 62 + 54 * FaceGamePaint.hash(n, 12)
            if kind < 0.42 {                                            // pine
                ctx.setFillColor(FaceGamePaint.cg(trunk))
                ctx.fill(CGRect(x: x - 5, y: groundY - 4, width: 10, height: 18))
                ctx.setFillColor(FaceGamePaint.cg(leaf))
                for (k, width) in [(0.0, 0.52), (0.28, 0.4), (0.52, 0.28)] {
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: x - h * width, y: groundY + 8 + h * k))
                    ctx.addLine(to: CGPoint(x: x, y: groundY + 8 + h * (k + 0.55)))
                    ctx.addLine(to: CGPoint(x: x + h * width, y: groundY + 8 + h * k))
                    ctx.fillPath()
                }
            } else if kind < 0.75 {                                     // round tree
                ctx.setFillColor(FaceGamePaint.cg(trunk))
                ctx.fill(CGRect(x: x - 6, y: groundY - 4, width: 12, height: h * 0.55))
                ctx.setFillColor(FaceGamePaint.cg(leaf))
                ctx.fillEllipse(in: CGRect(x: x - h * 0.4, y: groundY + h * 0.3, width: h * 0.8, height: h * 0.72))
            } else {                                                    // bush
                ctx.setFillColor(FaceGamePaint.cg(leaf))
                for (dx, r) in [(-0.3, 0.26), (0.0, 0.34), (0.3, 0.24)] {
                    ctx.fillEllipse(in: CGRect(x: x + dx * h - r * h, y: groundY - 6, width: r * 2 * h, height: r * 1.7 * h))
                }
            }
        }
    }

    private static func drawGround(_ ctx: CGContext, size: CGSize, groundY: Double, scroll: Double, light: Light) {
        let soil = light.pick(day: Tone(0.5, 0.34, 0.2), night: Tone(0.13, 0.1, 0.17))
        let dark = light.pick(day: Tone(0.38, 0.24, 0.14), night: Tone(0.08, 0.06, 0.12))
        let grass = light.pick(day: Tone(0.38, 0.8, 0.28), night: Tone(0.1, 0.34, 0.22))
        ctx.setFillColor(FaceGamePaint.cg(soil))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: groundY))
        // Pebbles and stripes slide by at full speed.
        let tile = 90.0
        let first = Int((scroll / tile).rounded(.down)) - 1
        let last = first + Int(size.width / tile) + 3
        ctx.setFillColor(FaceGamePaint.cg(dark))
        for n in first...last {
            let x = Double(n) * tile - scroll
            ctx.fillEllipse(in: CGRect(x: x + 20 * FaceGamePaint.hash(n, 13), y: 20 + 55 * FaceGamePaint.hash(n, 14), width: 26 + 20 * FaceGamePaint.hash(n, 15), height: 10))
        }
        ctx.setFillColor(FaceGamePaint.cg(grass))
        ctx.fill(CGRect(x: 0, y: groundY - 16, width: size.width, height: 16))
        let blade = FaceGamePaint.cg(FaceGamePaint.mix(grass, Tone(1, 1, 1), 0.2))
        ctx.setFillColor(blade)
        let tuft = 44.0
        let t0 = Int((scroll / tuft).rounded(.down)) - 1
        for n in t0...(t0 + Int(size.width / tuft) + 3) {
            let x = Double(n) * tuft - scroll
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: groundY))
            ctx.addLine(to: CGPoint(x: x + 5, y: groundY + 7 + 8 * FaceGamePaint.hash(n, 16)))
            ctx.addLine(to: CGPoint(x: x + 10, y: groundY))
            ctx.fillPath()
        }
        ctx.setStrokeColor(FaceGamePaint.cg(Tone(0.05, 0.08, 0.05), 0.9))
        ctx.setLineWidth(5)
        ctx.move(to: CGPoint(x: 0, y: groundY - 16))
        ctx.addLine(to: CGPoint(x: size.width, y: groundY - 16))
        ctx.strokePath()
    }
}
