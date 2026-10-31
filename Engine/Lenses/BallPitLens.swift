import AppKit
import CoreGraphics
import CoreImage
import simd

/// Balls rain down, pile up on the floor and bounce off you. Walk through them and they scatter.
struct BallPit {
    struct Ball {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var radius: Double
        var colour: Int
        /// 0...1, how flattened the ball is from its last landing. Springs back on its own.
        var squash = 0.0
        /// Which way it was flattened: the direction it landed from.
        var squashAngle = Double.pi / 2
    }

    static let colours = 8

    let size: CGSize
    private(set) var balls: [Ball] = []
    private var rng: SplitMix64
    private var owed = 0.0
    var capacity = 70

    init(size: CGSize, seed: UInt64 = 0xBA11) {
        self.size = size
        rng = SplitMix64(seed: seed)
    }

    mutating func removeAll() { balls.removeAll() }

    mutating func step(_ dt: Double, matte: MatteQuery?) {
        let dt = min(max(dt, 0), 0.1)
        owed += dt * 7
        while owed >= 1 {
            owed -= 1
            if balls.count >= capacity { balls.removeFirst() }
            let radius = Double.random(in: 17...29, using: &rng)
            balls.append(Ball(position: SIMD2(Double.random(in: 40...(size.width - 40), using: &rng), size.height + radius),
                              velocity: SIMD2(Double.random(in: -50...50, using: &rng), Double.random(in: -80...0, using: &rng)),
                              radius: radius, colour: Int.random(in: 0..<Self.colours, using: &rng)))
        }

        // Substeps keep fast balls from tunnelling through an arm.
        let steps = 3
        let h = dt / Double(steps)
        for _ in 0..<steps {
            for i in balls.indices {
                balls[i].velocity.y -= 1150 * h
                balls[i].position += balls[i].velocity * h
                var p = balls[i].position, v = balls[i].velocity
                let r = balls[i].radius
                let before = v
                if p.y < r { p.y = r; v.y = abs(v.y) * 0.5; v.x *= 0.94 }
                if p.x < r { p.x = r; v.x = abs(v.x) * 0.6 }
                if p.x > size.width - r { p.x = size.width - r; v.x = -abs(v.x) * 0.6 }
                if let matte { Silhouette.resolve(position: &p, velocity: &v, radius: r, in: matte, restitution: 0.55) }
                // A hard landing flattens the ball for a moment, in the direction it was going.
                let jolt = simd_length(v - before)
                if jolt > 160 {
                    balls[i].squash = max(balls[i].squash, min(0.32, jolt / 2600))
                    balls[i].squashAngle = atan2(before.y, before.x)
                }
                balls[i].position = p
                balls[i].velocity = v
            }
            separateOverlappingBalls()
            keepInsideRoom()
        }
        for i in balls.indices { balls[i].squash = max(0, balls[i].squash - dt * 2.4) }
    }

    /// Neighbours can shove a ball into the floor or a wall; put it back.
    private mutating func keepInsideRoom() {
        for i in balls.indices {
            let r = balls[i].radius
            balls[i].position.y = max(r, balls[i].position.y)
            balls[i].position.x = min(max(r, balls[i].position.x), size.width - r)
        }
    }

    private mutating func separateOverlappingBalls() {
        for i in balls.indices {
            for j in balls.indices where j > i {
                let delta = balls[j].position - balls[i].position
                let distance = simd_length(delta), minimum = balls[i].radius + balls[j].radius
                guard distance < minimum, distance > 1e-6 else { continue }
                let normal = delta / distance
                let push = (minimum - distance) / 2
                balls[i].position -= normal * push
                balls[j].position += normal * push
                // Swap the speed along the line between them, losing a little.
                let relative = simd_dot(balls[j].velocity - balls[i].velocity, normal)
                if relative < 0 {
                    balls[i].velocity += normal * relative * 0.8
                    balls[j].velocity -= normal * relative * 0.8
                }
            }
        }
    }
}

final class BallPitLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private var pit: BallPit

    init(size: CGSize = CGSize(width: 1280, height: 720)) { pit = BallPit(size: size) }

    func restart() { pit.removeAll() }

    var ballCount: Int { pit.balls.count }

    func render(_ input: LensInput) -> CIImage {
        pit.step(input.dt, matte: input.matteGrid)
        let layer = input.services.overlay { ctx in
            // Shadows first, all of them, so no ball's shadow falls on top of another ball.
            if let shadow = BallPitArt.shadow() {
                ctx.interpolationQuality = .low
                for ball in pit.balls {
                    let r = ball.radius
                    let lift = ball.position.y - r
                    if lift < 24 {
                        // Sitting on the floor: a tight dark contact patch under it.
                        ctx.setAlpha(CGFloat(1 - lift / 24))
                        ctx.draw(shadow, in: CGRect(x: ball.position.x - r * 1.1, y: -r * 0.22, width: r * 2.2, height: r * 0.6))
                        ctx.setAlpha(1)
                    }
                    if lift > 8 {
                        // In the air or on the player: a soft shadow down and to the right.
                        ctx.draw(shadow, in: CGRect(x: ball.position.x - r * 0.95 + r * 0.18, y: ball.position.y - r * 1.15, width: r * 1.9, height: r * 1.9))
                    }
                }
                ctx.interpolationQuality = .medium
            }
            for ball in pit.balls {
                guard let sprite = BallPitArt.sprite(colour: ball.colour) else { continue }
                let r = ball.radius
                if ball.squash > 0.01 {
                    // Flattened along the way it landed, fuller across, then springing back.
                    let s = ball.squash
                    ctx.saveGState()
                    ctx.translateBy(x: ball.position.x, y: ball.position.y)
                    ctx.rotate(by: CGFloat(ball.squashAngle))
                    ctx.scaleBy(x: CGFloat(1 - s), y: CGFloat(1 + s * 0.7))
                    ctx.rotate(by: -CGFloat(ball.squashAngle))
                    ctx.draw(sprite, in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
                    ctx.restoreGState()
                } else {
                    ctx.draw(sprite, in: CGRect(x: ball.position.x - r, y: ball.position.y - r, width: r * 2, height: r * 2))
                }
            }
        }
        guard let layer else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }
}

/// The balls, drawn once per colour: shiny moulded plastic lit from the top left, with a faint seam.
enum BallPitArt {
    /// "Toy box": the bright colours of a real ball pit, each pulled just short of a pure primary.
    static let palette: [NSColor] = [
        NSColor(red: 0.93, green: 0.30, blue: 0.34, alpha: 1),   // cherry
        NSColor(red: 1.00, green: 0.60, blue: 0.22, alpha: 1),   // tangerine
        NSColor(red: 1.00, green: 0.82, blue: 0.30, alpha: 1),   // lemon
        NSColor(red: 0.42, green: 0.78, blue: 0.38, alpha: 1),   // leaf
        NSColor(red: 0.22, green: 0.72, blue: 0.78, alpha: 1),   // teal
        NSColor(red: 0.30, green: 0.50, blue: 0.94, alpha: 1),   // cobalt
        NSColor(red: 0.62, green: 0.44, blue: 0.92, alpha: 1),   // grape
        NSColor(red: 0.98, green: 0.52, blue: 0.74, alpha: 1),   // bubblegum
    ]

    static func sprite(colour: Int) -> CGImage? {
        let which = ((colour % palette.count) + palette.count) % palette.count
        return BodyArtCache.image("ballpit-\(which)", width: 112, height: 112) { draw($0, colour: palette[which]) }
    }

    /// A soft dark disc that fades out, stretched under each ball.
    static func shadow() -> CGImage? {
        BodyArtCache.image("ballpit-shadow", width: 64, height: 64) { ctx in
            ctx.glow(center: CGPoint(x: 32, y: 32), radius: 32, red: 0.04, green: 0.02, blue: 0.1, alpha: 0.42)
        }
    }

    private static func draw(_ ctx: CGContext, colour: NSColor) {
        let rect = CGRect(x: 2, y: 2, width: 108, height: 108)
        let r = rect.width / 2, c = CGPoint(x: rect.midX, y: rect.midY)
        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        BodyShapes.fillLit(ctx, rect, light: colour.bodyShade(0.5), body: colour.bodyShade(0), shade: colour.bodyShade(-0.55),
                           lightAt: CGPoint(x: c.x - r * 0.36, y: c.y + r * 0.4))
        // Light from the floor and its neighbours, along the lower right.
        let (cr, cg, cb) = BodyGamePalette.rgb(colour)
        ctx.glow(center: CGPoint(x: c.x + r * 0.62, y: c.y - r * 0.62), radius: r * 0.75, red: cr + (1 - cr) * 0.3, green: cg + (1 - cg) * 0.3,
                 blue: cb + (1 - cb) * 0.3, alpha: 0.4)
        // The moulding seam: a faint curved line across the ball.
        ctx.setStrokeColor(colour.bodyShade(-0.35).copy(alpha: 0.35) ?? colour.bodyShade(-0.35))
        ctx.setLineWidth(2)
        ctx.addArc(center: CGPoint(x: c.x + r * 0.9, y: c.y + r * 1.4), radius: r * 1.95, startAngle: .pi * 1.05, endAngle: .pi * 1.6, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
        // The shine.
        ctx.saveGState()
        ctx.translateBy(x: c.x - r * 0.36, y: c.y + r * 0.4)
        ctx.rotate(by: 0.7)
        ctx.glow(center: .zero, radius: r * 0.45, red: 1, green: 1, blue: 1, alpha: 0.5)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: -r * 0.24, y: -r * 0.1, width: r * 0.48, height: r * 0.2))
        ctx.restoreGState()
        ctx.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
        ctx.setStrokeColor(colour.bodyShade(-0.6).copy(alpha: 0.55) ?? colour.bodyShade(-0.6))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
    }
}
