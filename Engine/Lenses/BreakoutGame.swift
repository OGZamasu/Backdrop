import AppKit
import CoreGraphics
import simd

/// Breakout with you as the paddle: the ball bounces off your silhouette and smashes the bricks along the top.
struct BreakoutGame: Game {
    static let title = "Breakout"
    static let hint = "Bat the ball with your body to break the bricks."
    static let accent = SIMD3<Double>(1.0, 0.66, 0.36)

    struct Brick { var rect: CGRect; var row: Int }

    /// A piece of a broken brick, tumbling away.
    struct Shard {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var rotation: Double
        var spin: Double
        var size: Double
        var row: Int
        var age = 0.0
    }

    /// A ring where the ball met something.
    struct Ring {
        var position: SIMD2<Double>
        var body: Bool
        var age = 0.0
    }

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
    private(set) var bodyHits = 0
    private var speed = 470.0
    private var rng: SplitMix64
    private var sparks = ParticleSystem(capacity: 240)
    private var shards: [Shard] = []
    private var rings: [Ring] = []
    private var floaters: [BodyFloater] = []
    /// Where the ball has been, newest last, for its trail.
    private var trail: [SIMD2<Double>] = []
    private var squash = 1.0
    private var squashNormal = SIMD2<Double>(0, 1)
    private var serveLength = 1.2
    private var sinceMiss = 99.0
    private var levelAge = 99.0

    static let radius = 13.0
    static let columns = 10
    static let brickHeight = 28.0
    static let brickGap = 8.0

    var isOver: Bool { lives <= 0 }
    var summary: String { "Lives \(lives) · Level \(level)" }

    var readout: GameUIReadout { GameUIReadout(score: score, lives: (max(0, lives), 3), label: "Level \(level)") }

    var result: GameUIResult {
        let line: String
        switch bricksBroken {
        case 0..<5: line = "Lean into the ball to send it back up"
        case 5..<30: line = "Brick by brick. Aim for the gaps!"
        default: line = "A wrecking ball in human form"
        }
        return GameUIResult(headline: "Out of balls", line: line, stats: [("\(bricksBroken)", "bricks"), ("\(level)", "level"), ("\(bodyHits)", "returns")])
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        ball = SIMD2(size.width / 2, size.height * 0.5)
        velocity = .zero
        sparks.gravity = SIMD2(0, -600)
        sparks.drag = 0.8
        buildBricks()
        beginServe(after: 1.2)
        let sizes = bricks.first.map { ($0.rect.width, $0.rect.height) }
        BodyArtCache.warm("breakout") {
            if let (w, h) = sizes { for row in BreakoutArt.rows.indices { _ = BreakoutArt.brick(row: row, width: w, height: h) } }
            _ = BreakoutArt.ball()
        }
    }

    /// The top of the brick wall: low enough to leave the HUD's band clear.
    private var wallTop: Double { size.height - 158 }

    private mutating func buildBricks() {
        let rows = min(7, 4 + level)
        let margin = 70.0, gap = Self.brickGap
        let width = (size.width - margin * 2 - gap * Double(Self.columns - 1)) / Double(Self.columns), height = Self.brickHeight
        bricks = (0..<rows).flatMap { row in
            (0..<Self.columns).map { column in
                Brick(rect: CGRect(x: margin + Double(column) * (width + gap),
                                   y: wallTop - height - Double(row) * (height + gap), width: width, height: height), row: row)
            }
        }
    }

    /// Holds the ball where it will be served from, so it can grow in there instead of jumping when play starts.
    private mutating func beginServe(after seconds: Double) {
        serving = seconds
        serveLength = seconds
        ball = SIMD2(size.width / 2 + Double.random(in: -150...150, using: &rng), size.height * 0.5)
        velocity = .zero
        trail.removeAll()
    }

    private mutating func serve() {
        let angle = Double.random(in: 0.3...0.9, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
        velocity = SIMD2(sin(angle), -cos(angle) * 0.6) * speed        // heads down toward you first
        serving = 0
    }

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = bodyClamp(dt, 0, 0.1)
        levelBanner = max(0, levelBanner - dt)
        levelAge += dt
        sinceMiss += dt
        squash = min(1, squash + dt * 4)
        advanceEffects(dt)
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
        trail.append(ball)
        if trail.count > 10 { trail.removeFirst(trail.count - 10) }
    }

    private mutating func advanceEffects(_ dt: Double) {
        sparks.step(dt)
        for i in shards.indices {
            shards[i].age += dt
            shards[i].velocity.y -= 1300 * dt
            shards[i].position += shards[i].velocity * dt
            shards[i].rotation += shards[i].spin * dt
        }
        shards.removeAll { $0.age > 0.9 }
        for i in rings.indices { rings[i].age += dt }
        rings.removeAll { $0.age > 0.4 }
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll { $0.isDone }
    }

    private mutating func collide(_ world: GameWorld) {
        let r = Self.radius
        if ball.x < r { ball.x = r; velocity.x = abs(velocity.x); bounced(SIMD2(1, 0), body: false) }
        if ball.x > size.width - r { ball.x = size.width - r; velocity.x = -abs(velocity.x); bounced(SIMD2(-1, 0), body: false) }
        if ball.y > size.height - r { ball.y = size.height - r; velocity.y = -abs(velocity.y); bounced(SIMD2(0, -1), body: false) }

        if ball.y < -r * 2 {
            lives -= 1
            sinceMiss = 0
            floaters.append(BodyFloater.placed("MISS", at: SIMD2(ball.x, 90), size: size, color: BodyGamePalette.coral, fontSize: 56, life: 1.1, rise: 40))
            beginServe(after: 1.4)
            return
        }

        if let matte = world.matte {
            let before = ball
            if Silhouette.resolve(position: &ball, velocity: &velocity, radius: r, in: matte, restitution: 1.0) {
                // Keep the game moving: a bat always sends the ball upward with some life in it.
                if velocity.y < 280 { velocity.y = 280 }
                velocity = simd_normalize(velocity) * speed
                let normal = simd_length(ball - before) > 1e-6 ? simd_normalize(ball - before) : SIMD2<Double>(0, 1)
                if rings.last.map({ $0.age > 0.15 || !$0.body }) ?? true {
                    bodyHits += 1
                    rings.append(Ring(position: ball - normal * r, body: true))
                    for _ in 0..<8 {
                        let a = atan2(normal.y, normal.x) + Double.random(in: -0.9...0.9, using: &rng)
                        sparks.emit(Particle(position: ball - normal * r, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 160...420, using: &rng),
                                             life: Double.random(in: 0.25...0.5, using: &rng), size: Double.random(in: 2.5...5, using: &rng), kind: 1))
                    }
                }
                bounced(normal, body: true)
            }
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
            shatter(brick, from: normal)
            bounced(normal, body: false)
            if bricksBroken % 4 == 0 || brick.row <= 1 {
                floaters.append(BodyFloater.placed("+\(worth)", at: SIMD2(rect.midX, rect.minY - 20), size: size, fontSize: 34, life: 0.7, rise: 40))
            }
            break
        }

        if bricks.isEmpty {
            level += 1
            levelBanner = 2
            levelAge = 0
            speed = min(900, speed + 40)
            buildBricks()
            beginServe(after: 1.2)
        }
    }

    private mutating func bounced(_ normal: SIMD2<Double>, body: Bool) {
        squash = body ? 0.62 : 0.78
        squashNormal = normal
    }

    private mutating func shatter(_ brick: Brick, from normal: SIMD2<Double>) {
        let rect = brick.rect
        for k in 0..<6 {
            let x = rect.minX + rect.width * (Double(k % 3) + 0.5) / 3, y = rect.minY + rect.height * (Double(k / 3) + 0.5) / 2
            let away = SIMD2(x - rect.midX, y - rect.midY) * 4 - normal * 120
            shards.append(Shard(position: SIMD2(x, y), velocity: away + SIMD2(Double.random(in: -80...80, using: &rng), Double.random(in: 60...260, using: &rng)),
                                rotation: 0, spin: Double.random(in: -9...9, using: &rng), size: Double.random(in: 9...15, using: &rng), row: brick.row))
        }
        for _ in 0..<6 {
            sparks.emit(Particle(position: SIMD2(rect.midX, rect.midY),
                                 velocity: SIMD2(Double.random(in: -220...220, using: &rng), Double.random(in: -60...280, using: &rng)),
                                 life: Double.random(in: 0.3...0.6, using: &rng), size: Double.random(in: 2.5...5, using: &rng), hue: Double(brick.row)))
        }
        rings.append(Ring(position: SIMD2(rect.midX, rect.midY), body: false))
    }

    // MARK: Test hooks

    /// Puts the ball somewhere with a heading, skipping the serve.
    mutating func place(ball position: SIMD2<Double>, velocity heading: SIMD2<Double>) {
        ball = position
        velocity = heading
        serving = 0
        trail.removeAll()
    }

    /// Leaves only the last `count` bricks, so a test can clear the board in one hit.
    mutating func keepOnly(_ count: Int) { bricks = Array(bricks.suffix(count)) }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        drawFloorWarning(in: ctx, time: time)
        for brick in bricks {
            guard let sprite = BreakoutArt.brick(row: brick.row, width: brick.rect.width, height: brick.rect.height) else { continue }
            let pad = BreakoutArt.margin
            ctx.draw(sprite, in: brick.rect.insetBy(dx: -pad, dy: -pad))
        }
        for shard in shards { drawShard(shard, in: ctx) }
        for ring in rings {
            let t = ring.age / 0.4
            let radius = Self.radius * (1.2 + (ring.body ? 4.5 : 3.0) * BodyEase.outCubic(t))
            let colour = ring.body ? BodyGamePalette.gold : BodyGamePalette.cream
            ctx.setStrokeColor(BodyGamePalette.cg(colour, CGFloat(0.85 * (1 - t))))
            ctx.setLineWidth(CGFloat(5 * (1 - t) + 1))
            ctx.strokeEllipse(in: CGRect(x: ring.position.x - radius, y: ring.position.y - radius, width: radius * 2, height: radius * 2))
        }
        for p in sparks.particles {
            let colour = p.kind == 1 ? BodyGamePalette.gold : BreakoutArt.rows[Int(p.hue) % BreakoutArt.rows.count]
            ctx.setAlpha(CGFloat(1 - p.progress))
            ctx.fillCircle(center: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 - 0.4 * p.progress), color: colour.bodyShade(0.3))
        }
        ctx.setAlpha(1)
        drawBall(in: ctx, time: time)
        for floater in floaters { floater.draw(in: ctx) }
        BodyGameHUD.banner(ctx, "LEVEL \(level)", age: levelAge, size: size, color: BodyGamePalette.gold, life: 1.8)
    }

    /// A soft coral glow along the bottom edge, where a ball is lost, stronger while the ball is low and falling.
    private func drawFloorWarning(in ctx: CGContext, time: Double) {
        let danger = serving <= 0 && velocity.y < 0 ? bodyClamp(1 - ball.y / (size.height * 0.5), 0, 1) : 0
        let alpha = 0.12 + 0.3 * danger * (0.8 + 0.2 * sin(time * 8))
        let (r, g, b) = BodyGamePalette.rgb(BodyGamePalette.coral)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [CGColor(red: r, green: g, blue: b, alpha: CGFloat(alpha)), CGColor(red: r, green: g, blue: b, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 46), options: [])
    }

    private func drawShard(_ shard: Shard, in ctx: CGContext) {
        let colour = BreakoutArt.rows[shard.row % BreakoutArt.rows.count]
        let fade = bodyClamp((0.9 - shard.age) / 0.4, 0, 1)
        ctx.saveGState()
        ctx.translateBy(x: shard.position.x, y: shard.position.y)
        ctx.rotate(by: CGFloat(shard.rotation))
        ctx.setAlpha(CGFloat(fade))
        let s = shard.size
        ctx.move(to: CGPoint(x: -s, y: -s * 0.6))
        ctx.addLine(to: CGPoint(x: s * 0.9, y: -s * 0.4))
        ctx.addLine(to: CGPoint(x: s * 0.2, y: s * 0.7))
        ctx.closePath()
        ctx.setFillColor(colour.bodyShade(0.15))
        ctx.fillPath()
        ctx.move(to: CGPoint(x: -s, y: -s * 0.6))
        ctx.addLine(to: CGPoint(x: s * 0.2, y: s * 0.7))
        ctx.addLine(to: CGPoint(x: -s * 0.2, y: -s * 0.1))
        ctx.closePath()
        ctx.setFillColor(colour.bodyShade(0.5))
        ctx.fillPath()
        ctx.restoreGState()
    }

    private func drawBall(in ctx: CGContext, time: Double) {
        let r = Self.radius
        if serving > 0 {
            // Growing in where it will be served from, with a ring closing on it.
            let t = bodyClamp(1 - serving / serveLength, 0, 1)
            let grow = BodyEase.outBack(bodyClamp((t - 0.35) / 0.65, 0, 1))
            let ring = r * (1.4 + 5 * (1 - BodyEase.outCubic(t)))
            ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.cream, CGFloat(0.8 * t)))
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: ball.x - ring, y: ball.y - ring, width: ring * 2, height: ring * 2))
            if grow > 0.01, let sprite = BreakoutArt.ball() {
                BodyGlow.stamp(ctx, at: CGPoint(x: ball.x, y: ball.y), radius: CGFloat(r * 3.4 * grow), color: BodyGamePalette.sky, alpha: 0.5)
                ctx.draw(sprite, center: CGPoint(x: ball.x, y: ball.y), height: CGFloat(r * 2.4 * grow))
            }
            return
        }
        // The trail: fading glows where the ball has just been.
        for (i, p) in trail.dropLast().enumerated() {
            let k = Double(i + 1) / Double(max(1, trail.count))
            BodyGlow.stamp(ctx, at: CGPoint(x: p.x, y: p.y), radius: CGFloat(r * (0.6 + 1.2 * k)), color: BodyGamePalette.sky, alpha: 0.35 * k)
        }
        BodyGlow.stamp(ctx, at: CGPoint(x: ball.x, y: ball.y), radius: CGFloat(r * 3.4), color: BodyGamePalette.sky, alpha: 0.55)
        guard let sprite = BreakoutArt.ball() else { return }
        // Squashed flat against whatever it just hit, springing back round.
        let k = BodyEase.outElastic(bodyClamp((squash - 0.6) / 0.4, 0, 1))
        let flat = squash >= 1 ? 1.0 : 0.62 + 0.38 * k
        ctx.saveGState()
        ctx.translateBy(x: ball.x, y: ball.y)
        ctx.rotate(by: CGFloat(atan2(squashNormal.y, squashNormal.x)))
        ctx.scaleBy(x: CGFloat(flat), y: CGFloat(1 / sqrt(flat)))
        ctx.rotate(by: -CGFloat(atan2(squashNormal.y, squashNormal.x)))
        ctx.draw(sprite, center: .zero, height: CGFloat(r * 2.4))
        ctx.restoreGState()
    }
}

/// Breakout's bricks and ball, drawn once: glossy candy bricks lit from the top left, and a bright pearl of a ball.
enum BreakoutArt {
    /// "Sunset arcade", top row to bottom.
    static let rows: [NSColor] = [
        NSColor(red: 0.95, green: 0.36, blue: 0.52, alpha: 1),   // raspberry
        NSColor(red: 1.00, green: 0.50, blue: 0.38, alpha: 1),   // coral
        NSColor(red: 1.00, green: 0.68, blue: 0.28, alpha: 1),   // tangerine
        NSColor(red: 0.98, green: 0.84, blue: 0.32, alpha: 1),   // lemon
        NSColor(red: 0.42, green: 0.85, blue: 0.56, alpha: 1),   // mint
        NSColor(red: 0.30, green: 0.75, blue: 0.92, alpha: 1),   // lagoon
        NSColor(red: 0.58, green: 0.56, blue: 0.98, alpha: 1),   // periwinkle
    ]
    /// Room round each brick for its shadow.
    static let margin = 8.0

    static func brick(row: Int, width: Double, height: Double) -> CGImage? {
        let which = ((row % rows.count) + rows.count) % rows.count
        let w = Int((width + margin * 2).rounded()), h = Int((height + margin * 2).rounded())
        return BodyArtCache.image("breakout-brick-\(which)-\(w)x\(h)", width: w, height: h) { ctx in
            drawBrick(ctx, colour: rows[which], rect: CGRect(x: margin, y: margin, width: Double(w) - margin * 2, height: Double(h) - margin * 2))
        }
    }

    static func ball() -> CGImage? {
        BodyArtCache.image("breakout-ball", width: 64, height: 64) { ctx in
            let rect = CGRect(x: 4, y: 4, width: 56, height: 56)
            ctx.saveGState()
            ctx.addEllipse(in: rect)
            ctx.clip()
            BodyShapes.fillLit(ctx, rect, light: CGColor(red: 1, green: 1, blue: 1, alpha: 1), body: CGColor(red: 0.86, green: 0.95, blue: 1, alpha: 1),
                               shade: CGColor(red: 0.4, green: 0.66, blue: 0.95, alpha: 1))
            ctx.restoreGState()
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
            ctx.fillEllipse(in: CGRect(x: 17, y: 38, width: 12, height: 9))
            ctx.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
            ctx.setStrokeColor(CGColor(red: 0.2, green: 0.4, blue: 0.75, alpha: 0.6))
            ctx.setLineWidth(2)
            ctx.strokePath()
        }
    }

    private static func drawBrick(_ ctx: CGContext, colour: NSColor, rect: CGRect) {
        let shape = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        // Contact shadow below and to the right.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 2, height: -4), blur: 6, color: CGColor(red: 0.04, green: 0.02, blue: 0.1, alpha: 0.5))
        ctx.addPath(shape)
        ctx.setFillColor(colour.bodyShade(-0.4))
        ctx.fillPath()
        ctx.restoreGState()
        // Body: lit top, deep bottom.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        BodyShapes.fillVertical(ctx, rect, top: colour.bodyShade(0.35), middle: colour.bodyShade(0), bottom: colour.bodyShade(-0.38))
        // A darker lower lip, so it reads as a slab with a top face.
        ctx.setFillColor(colour.bodyShade(-0.45).copy(alpha: 0.55) ?? colour.bodyShade(-0.45))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 5))
        // Gloss along the top.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.38))
        ctx.addPath(CGPath(roundedRect: CGRect(x: rect.minX + 6, y: rect.maxY - rect.height * 0.36, width: rect.width - 12, height: rect.height * 0.22),
                           cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.fillPath()
        // A slanted glint near the left end.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.45))
        ctx.move(to: CGPoint(x: rect.minX + 14, y: rect.minY + 6))
        ctx.addLine(to: CGPoint(x: rect.minX + 20, y: rect.minY + 6))
        ctx.addLine(to: CGPoint(x: rect.minX + 28, y: rect.maxY - 6))
        ctx.addLine(to: CGPoint(x: rect.minX + 22, y: rect.maxY - 6))
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 7.5, cornerHeight: 7.5, transform: nil))
        ctx.setStrokeColor(colour.bodyShade(-0.55).copy(alpha: 0.8) ?? colour.bodyShade(-0.55))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
    }
}
