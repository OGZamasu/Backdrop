import AppKit
import CoreGraphics
import simd

/// Breakout with you as the paddle: the ball bounces off your silhouette and smashes the bricks along the top.
struct BreakoutGame: Game {
    static let title = "Breakout"
    static let hint = "Bat the ball with your body to break the bricks."

    struct Brick { var rect: CGRect; var row: Int }

    let size: CGSize
    private(set) var bricks: [Brick] = []
    private(set) var ball: SIMD2<Double>
    private(set) var velocity: SIMD2<Double>
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var level = 1
    private(set) var bricksBroken = 0
    /// While the ball waits to be served again.
    private(set) var serving = 1.2
    private(set) var levelBanner = 0.0
    private var speed = 470.0
    private var rng: SplitMix64
    private var sparks = ParticleSystem(capacity: 200)

    static let radius = 13.0
    static let columns = 10

    var isOver: Bool { lives <= 0 }
    var summary: String { "Lives \(lives) · Level \(level)" }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        ball = SIMD2(size.width / 2, size.height * 0.5)
        velocity = .zero
        sparks.gravity = SIMD2(0, -500)
        buildBricks()
    }

    private mutating func buildBricks() {
        let rows = min(7, 4 + level)
        let margin = 70.0, gap = 8.0
        let width = (size.width - margin * 2 - gap * Double(Self.columns - 1)) / Double(Self.columns), height = 30.0
        bricks = (0..<rows).flatMap { row in
            (0..<Self.columns).map { column in
                Brick(rect: CGRect(x: margin + Double(column) * (width + gap),
                                   y: size.height - 150 - Double(row) * (height + gap), width: width, height: height), row: row)
            }
        }
    }

    private mutating func serve() {
        ball = SIMD2(size.width / 2 + Double.random(in: -150...150, using: &rng), size.height * 0.5)
        let angle = Double.random(in: 0.3...0.9, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
        velocity = SIMD2(sin(angle), -cos(angle) * 0.6 + 0.0) * speed        // heads down toward you first
        serving = 0
    }

    mutating func step(_ dt: Double, world: GameWorld) {
        levelBanner = max(0, levelBanner - dt)
        sparks.step(dt)
        if serving > 0 {
            serving -= dt
            if serving <= 0 { serve() }
            return
        }

        // Small steps, so a fast ball can't pass through a brick or your arm between frames.
        let steps = max(1, Int(ceil(simd_length(velocity) * dt / (Self.radius * 0.5))))
        for _ in 0..<steps {
            ball += velocity * (dt / Double(steps))
            collide(world)
            if serving > 0 || isOver { return }
        }
    }

    private mutating func collide(_ world: GameWorld) {
        let r = Self.radius
        if ball.x < r { ball.x = r; velocity.x = abs(velocity.x) }
        if ball.x > size.width - r { ball.x = size.width - r; velocity.x = -abs(velocity.x) }
        if ball.y > size.height - r { ball.y = size.height - r; velocity.y = -abs(velocity.y) }

        if ball.y < -r * 2 {
            lives -= 1
            serving = 1.4
            velocity = .zero
            ball = SIMD2(size.width / 2, size.height * 0.5)
            return
        }

        if let matte = world.matte,
           Silhouette.resolve(position: &ball, velocity: &velocity, radius: r, in: matte, restitution: 1.0) {
            // Keep the game moving: a bat always sends the ball upward with some life in it.
            if velocity.y < 280 { velocity.y = 280 }
            velocity = simd_normalize(velocity) * speed
        }

        // Bricks: bounce off the side that was hit.
        for index in bricks.indices {
            let rect = bricks[index].rect
            let nearest = SIMD2(min(max(ball.x, rect.minX), rect.maxX), min(max(ball.y, rect.minY), rect.maxY))
            let offset = ball - nearest
            guard simd_length_squared(offset) < r * r else { continue }
            let normal = simd_length(offset) > 1e-6 ? simd_normalize(offset)
                : SIMD2<Double>(0, velocity.y > 0 ? -1 : 1)
            if simd_dot(velocity, normal) < 0 { velocity -= 2 * simd_dot(velocity, normal) * normal }
            let brick = bricks.remove(at: index)
            let worth = 10 * (bricks.isEmpty ? 1 : (7 - min(6, brick.row)))
            score += worth
            bricksBroken += 1
            speed = min(900, speed + 5)
            velocity = simd_normalize(velocity) * speed
            for _ in 0..<8 {
                sparks.emit(Particle(position: SIMD2(rect.midX, rect.midY),
                                     velocity: SIMD2(Double.random(in: -200...200, using: &rng), Double.random(in: -50...260, using: &rng)),
                                     life: Double.random(in: 0.3...0.7, using: &rng), size: Double.random(in: 3...6, using: &rng),
                                     hue: Double(brick.row) / 7))
            }
            break
        }

        if bricks.isEmpty {
            level += 1
            levelBanner = 2
            speed = min(900, speed + 40)
            buildBricks()
            serving = 1.2
            velocity = .zero
            ball = SIMD2(size.width / 2, size.height * 0.5)
        }
    }

    // MARK: Test hooks

    /// Puts the ball somewhere with a heading, skipping the serve.
    mutating func place(ball position: SIMD2<Double>, velocity heading: SIMD2<Double>) {
        ball = position
        velocity = heading
        serving = 0
    }

    /// Leaves only the last `count` bricks, so a test can clear the board in one hit.
    mutating func keepOnly(_ count: Int) { bricks = Array(bricks.suffix(count)) }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        for brick in bricks {
            let (r, g, b) = Palette.rgb(hue: Double(brick.row) / 8, saturation: 0.75, brightness: 0.98)
            let path = CGPath(roundedRect: brick.rect, cornerWidth: 7, cornerHeight: 7, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 0.95))
            ctx.fillPath()
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))      // a gloss along the top
            ctx.fill(CGRect(x: brick.rect.minX + 4, y: brick.rect.maxY - 9, width: brick.rect.width - 8, height: 5))
        }
        for p in sparks.particles {
            let (r, g, b) = Palette.rgb(hue: p.hue, saturation: 0.6)
            ctx.setAlpha(CGFloat(1 - p.progress))
            ctx.fillCircle(center: CGPoint(x: p.position.x, y: p.position.y), radius: p.size, color: CGColor(red: r, green: g, blue: b, alpha: 1))
        }
        ctx.setAlpha(1)
        if serving <= 0 {
            ctx.glow(center: CGPoint(x: ball.x, y: ball.y), radius: Self.radius * 3, red: 1, green: 1, blue: 1, alpha: 0.5)
            ctx.fillCircle(center: CGPoint(x: ball.x, y: ball.y), radius: Self.radius, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        }
        if levelBanner > 0 { ctx.text("LEVEL \(level)", center: CGPoint(x: size.width / 2, y: size.height * 0.62), size: 110) }
    }
}
