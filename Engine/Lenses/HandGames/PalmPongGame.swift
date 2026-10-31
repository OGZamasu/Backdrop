import AppKit
import CoreGraphics
import simd

/// Pong with your palm as the paddle. Hold a hand up and move it up and down: the paddle on the left follows its height. The computer
/// plays the right-hand side. Every return scores, beating the computer scores more, and the ball gets quicker as the rally goes on.
/// You have three lives; miss the ball and you lose one.
///
/// Tracking jumps, drops out and flickers, so the paddle glides toward the hand at a limited speed, and when the hand goes it stays
/// where it was (dimmed) rather than running off.
struct PalmPongGame: HandGameScreens {
    static let title = "Palm Pong"
    static let hint = "Move your palm up and down to steer the paddle."
    static let presenceHint = "Hold up your hand to play"
    static let onboarding = ["Move your palm up and down", "The left paddle follows your hand"]
    static let accent = SIMD3<Double>(0.78, 0.6, 1.0)
    static let icon = GameUIIcon.hand(.open)
    static let startingLives = 3

    struct Floater { var text: String; var position: SIMD2<Double>; var age = 0.0; var good: Bool }

    // Sizes and speeds, for a 1280-wide picture. They scale with the width.
    static let ballRadius = 22.0
    static let paddleHalfWidth = 13.0
    static let paddleMargin = 64.0
    static let playerHalfHeight = 105.0
    static let computerHalfHeight = 88.0
    /// The fastest the paddle chases the hand, in pixels a second.
    static let paddleSpeed = 1900.0
    static let baseSpeed = 500.0
    static let topSpeed = 1150.0
    /// How often the computer looks at the ball again, in seconds.
    static let computerReaction = 0.2
    /// How long a hand may be missing before the paddle shows it has lost you.
    static let handGrace = 0.5

    let size: CGSize
    private(set) var ball: SIMD2<Double>
    private(set) var velocity = SIMD2<Double>.zero
    private(set) var playerY: Double
    private(set) var computerY: Double
    /// Where the paddle is heading: the height of the palm, stretched a little so the edges are in reach.
    private(set) var target: Double
    private(set) var score = 0
    private(set) var lives = PalmPongGame.startingLives
    /// Balls the player has sent back.
    private(set) var returns = 0
    /// Times the computer missed.
    private(set) var rallyWins = 0
    /// Hits so far in this rally, by either side.
    private(set) var rally = 0
    /// The longest rally of the game.
    private(set) var bestRally = 0
    /// Seconds before the ball is served, while there is no ball in play.
    private(set) var serving = 1.2
    /// The hand steering the paddle, and how long since it was last seen.
    private(set) var controllingHand: Int?
    private(set) var sinceHand = 99.0
    private var palm: CGPoint?
    private var trail: [SIMD2<Double>] = []
    private var sparks = ParticleSystem(capacity: 160)
    private var floaters: [Floater] = []
    private var rng: SplitMix64
    private var aimClock = 0.0
    private var aimAt: Double
    private var playerFlash = 0.0
    private var computerFlash = 0.0
    private var missFlash = 0.0

    var isOver: Bool { lives <= 0 }
    var summary: String {
        let hearts = String(repeating: "❤️", count: max(0, lives)) + String(repeating: "🖤", count: max(0, Self.startingLives - lives))
        return hearts
    }
    private var unit: Double { Double(size.width) / 1280 }
    private var radius: Double { Self.ballRadius * unit }

    /// The rally counts up in the status plate beside the hearts; a tip asks for the hand back when it is lost.
    var readout: GameUIReadout {
        GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), label: rally >= 2 && !isOver ? "Rally \(rally)" : nil,
                      tip: handLost && !isOver ? "Hold up your hand to move the paddle" : nil)
    }

    var result: GameUIResult {
        let line: String
        switch returns {
        case 0: line = "Hold your palm level with the ball"
        case 1..<10: line = "Getting the hang of it"
        default: line = rallyWins > 0 ? "You beat the robot \(rallyWins) times!" : "A wall of a paddle"
        }
        return GameUIResult(headline: "Out of lives", line: line,
                            stats: [("\(returns)", "returns"), ("\(rallyWins)", "points won"), ("\(bestRally)", "best rally")])
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        ball = SIMD2(size.width / 2, size.height / 2)
        playerY = size.height / 2
        computerY = size.height / 2
        target = size.height / 2
        aimAt = size.height / 2
        sparks.gravity = SIMD2(0, -300)
    }

    /// The x of the front face of the left paddle, where the ball bounces.
    var playerFace: Double { (Self.paddleMargin + Self.paddleHalfWidth) * unit }
    var computerFace: Double { Double(size.width) - (Self.paddleMargin + Self.paddleHalfWidth) * unit }
    var playerHalf: Double { Self.playerHalfHeight * unit }
    var computerHalf: Double { Self.computerHalfHeight * unit }
    /// The fastest the computer paddle can go right now.
    var computerSpeed: Double { min(560, 300 + 16 * Double(rally)) * unit }
    /// Whether the hand has been gone long enough to show it.
    var handLost: Bool { sinceHand > Self.handGrace }

    private var topSpeed: Double { Self.topSpeed * unit }
    private func serveSpeed() -> Double { min(700, Self.baseSpeed + 22 * Double(rallyWins)) * unit }

    // MARK: Step

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.5)
        guard lives > 0 else { return }
        follow(world.hands, dt: dt)
        movePlayer(dt)
        playerFlash = max(0, playerFlash - dt)
        computerFlash = max(0, computerFlash - dt)
        missFlash = max(0, missFlash - dt)
        sparks.step(dt)
        for i in floaters.indices { floaters[i].age += dt; floaters[i].position.y += 70 * dt }
        floaters.removeAll { $0.age > 0.9 }

        moveComputer(dt)
        if serving > 0 {
            serving -= dt
            if serving <= 0 { serving = 0; serve() }
            return
        }
        advanceBall(dt)
    }

    /// Picks the hand to follow: the left-most one, sticking with the one already in charge unless another is clearly further left.
    private mutating func follow(_ hands: [HandState], dt: Double) {
        guard var chosen = hands.min(by: { $0.palm.x < $1.palm.x }) else {
            sinceHand += dt
            return
        }
        if let id = controllingHand, let current = hands.first(where: { $0.id == id }), current.palm.x <= chosen.palm.x + 70 * unit {
            chosen = current
        }
        controllingHand = chosen.id
        sinceHand = 0
        palm = chosen.palm
        let middle = Double(size.height) / 2
        let reach = middle + (Double(chosen.palm.y) - middle) * 1.25
        target = min(Double(size.height) - playerHalf, max(playerHalf, reach))
    }

    /// Glides toward the hand: smooth, and never faster than `paddleSpeed`, so a tracking jump is a quick slide, not a teleport.
    private mutating func movePlayer(_ dt: Double) {
        let ease = 1 - exp(-dt / 0.05)
        let limit = Self.paddleSpeed * unit * dt
        let move = min(limit, max(-limit, (target - playerY) * ease))
        playerY = min(Double(size.height) - playerHalf, max(playerHalf, playerY + move))
    }

    /// The computer looks at the ball every so often, aims a little off (more as the rally goes on), and walks there at a limited speed.
    private mutating func moveComputer(_ dt: Double) {
        aimClock -= dt
        if aimClock <= 0 {
            aimClock = Self.computerReaction
            if serving <= 0 && velocity.x > 0 {
                let wobble = min(1.1, 0.25 + 0.07 * Double(rally))
                aimAt = ball.y + Double.random(in: -1...1, using: &rng) * computerHalf * wobble
            } else {
                let middle = Double(size.height) / 2
                aimAt = middle + (ball.y - middle) * 0.3
            }
        }
        let limit = computerSpeed * dt
        let move = min(limit, max(-limit, aimAt - computerY))
        computerY = min(Double(size.height) - computerHalf, max(computerHalf, computerY + move))
    }

    /// Where a ball waits to be served: the middle of the court, low enough to stay off the face.
    private var servePoint: SIMD2<Double> { SIMD2(size.width / 2, size.height * 0.36) }

    private mutating func serve() {
        ball = servePoint + SIMD2(0, Double.random(in: -70...70, using: &rng))
        let angle = Double.random(in: -0.35...0.35, using: &rng)
        velocity = SIMD2(-cos(angle), sin(angle)) * serveSpeed()
        rally = 0
        trail.removeAll()
    }

    private mutating func advanceBall(_ dt: Double) {
        let r = radius
        let steps = max(1, Int(ceil(simd_length(velocity) * dt / (r * 0.5))))
        let slice = dt / Double(steps)
        for _ in 0..<steps {
            ball += velocity * slice
            if ball.y < r { ball.y = r; velocity.y = abs(velocity.y) }
            if ball.y > Double(size.height) - r { ball.y = Double(size.height) - r; velocity.y = -abs(velocity.y) }
            hitPaddles()
            if ball.x < -r { playerMissed(); return }
            if ball.x > Double(size.width) + r { computerMissed(); return }
        }
        trail.append(ball)
        if trail.count > 9 { trail.removeFirst() }
    }

    private mutating func hitPaddles() {
        let r = radius
        // Left: the player's paddle.
        if velocity.x < 0, ball.x - r <= playerFace, ball.x + r >= playerFace - 2 * Self.paddleHalfWidth * unit,
           abs(ball.y - playerY) <= playerHalf + r * 0.6 {
            ball.x = playerFace + r
            let offset = (ball.y - playerY) / (playerHalf + r * 0.6)
            bounce(offset: offset, direction: 1)
            returns += 1
            rally += 1
            bestRally = max(bestRally, rally)
            score += 1
            playerFlash = 0.2
            floaters.append(Floater(text: "+1", position: SIMD2(playerFace + 70 * unit, ball.y + 40), good: true))
            spray(at: SIMD2(playerFace, ball.y), toward: 1)
        }
        // Right: the computer's.
        if velocity.x > 0, ball.x + r >= computerFace, ball.x - r <= computerFace + 2 * Self.paddleHalfWidth * unit,
           abs(ball.y - computerY) <= computerHalf + r * 0.6 {
            ball.x = computerFace - r
            let offset = (ball.y - computerY) / (computerHalf + r * 0.6)
            bounce(offset: offset, direction: -1)
            rally += 1
            bestRally = max(bestRally, rally)
            computerFlash = 0.2
            spray(at: SIMD2(computerFace, ball.y), toward: -1)
        }
    }

    /// Sends the ball away from a paddle: the nearer the edge it hit, the steeper it goes, and every hit is a little faster.
    private mutating func bounce(offset: Double, direction: Double) {
        let speed = min(topSpeed, simd_length(velocity) + 42 * unit)
        let angle = min(0.95, max(-0.95, offset * 0.85 + Double.random(in: -0.08...0.08, using: &rng)))
        velocity = SIMD2(cos(angle) * direction, sin(angle)) * speed
    }

    private mutating func playerMissed() {
        lives -= 1
        rally = 0
        serving = 1.4
        missFlash = 0.45
        velocity = .zero
        trail.removeAll()
        ball = servePoint
        floaters.append(Floater(text: "MISS!", position: SIMD2(150 * unit, Double(size.height) / 2), good: false))
        if lives <= 0 {
            // Nothing is stepped once the game is over, so don't leave a flash or a floating word frozen on the picture.
            missFlash = 0
            floaters.removeAll()
            sparks.removeAll()
        }
    }

    private mutating func computerMissed() {
        rallyWins += 1
        score += 5
        rally = 0
        serving = 1.3
        velocity = .zero
        trail.removeAll()
        floaters.append(Floater(text: "+5 NICE!", position: SIMD2(Double(size.width) - 230 * unit, Double(size.height) / 2), good: true))
        for _ in 0..<26 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 150...520, using: &rng)
            sparks.emit(Particle(position: SIMD2(Double(size.width) - 40 * unit, ball.y), velocity: SIMD2(cos(a), sin(a)) * s,
                                 life: Double.random(in: 0.5...1.0, using: &rng), size: Double.random(in: 4...8, using: &rng),
                                 hue: Double.random(in: 0..<1, using: &rng)))
        }
        ball = servePoint
    }

    private mutating func spray(at point: SIMD2<Double>, toward: Double) {
        for _ in 0..<9 {
            let a = Double.random(in: -1.2...1.2, using: &rng), s = Double.random(in: 150...420, using: &rng)
            sparks.emit(Particle(position: point, velocity: SIMD2(cos(a) * toward, sin(a)) * s, life: Double.random(in: 0.25...0.5, using: &rng),
                                 size: Double.random(in: 3...6, using: &rng), hue: toward > 0 ? 0.5 : 0.92))
        }
    }

    // MARK: Test hooks

    /// Puts the ball somewhere with a heading and starts play at once.
    mutating func place(ball position: SIMD2<Double>, velocity heading: SIMD2<Double>) {
        ball = position
        velocity = heading
        serving = 0
        trail.removeAll()
    }

    /// Puts the computer's paddle somewhere, and holds it there for a moment.
    mutating func place(computerAt y: Double) {
        computerY = y
        aimAt = y
        aimClock = 10
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        let u = CGFloat(unit)
        let w = size.width, h = size.height
        drawTable(ctx)
        if missFlash > 0 {
            // A soft coral glow on your side when a ball gets past, never a flash of the whole picture.
            let k = min(1, missFlash / 0.45)
            HandGameArt.halo(ctx, in: CGRect(x: -160 * u, y: -40 * u, width: 320 * u, height: h + 80 * u), red: 1, green: 0.42, blue: 0.4, alpha: 0.75 * k)
        }
        if let palm, !handLost { drawPalmRing(ctx, at: palm, time: time) }
        drawPaddle(ctx, x: Self.paddleMargin * unit, y: playerY, half: playerHalf, hot: playerFlash, colour: HandGamePalette.sky, dim: handLost ? 0.45 : 1)
        drawPaddle(ctx, x: Double(w) - Self.paddleMargin * unit, y: computerY, half: computerHalf, hot: computerFlash, colour: HandGamePalette.coral, dim: 1)

        drawBallInPlay(ctx, time: time)

        for p in sparks.particles {
            let c = [HandGamePalette.sky, HandGamePalette.gold, HandGamePalette.coral, HandGamePalette.mint][Int(p.hue * 4) % 4]
            HandGameArt.halo(ctx, at: CGPoint(x: p.position.x, y: p.position.y), radius: CGFloat(p.size * 2.2) * u, red: c.x, green: c.y, blue: c.z, alpha: 1 - p.progress)
        }
        for f in floaters {
            let pop = HandGameEase.outBack(f.age / 0.22)
            HandGameType.draw(ctx, f.text, at: CGPoint(x: f.position.x, y: f.position.y), size: 36 * u,
                              color: HandGamePalette.color(f.good ? HandGamePalette.gold : HandGamePalette.coral),
                              alpha: CGFloat(min(1, (0.9 - f.age) / 0.3)), scale: CGFloat(pop))
        }
    }

    /// A quiet court: a rounded border inside the safe margin and a dotted net down the middle that fades out across the face.
    private func drawTable(_ ctx: CGContext) {
        let u = CGFloat(unit)
        let court = CGRect(x: 28 * u, y: 24 * u, width: size.width - 56 * u, height: size.height - 48 * u)
        ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.cream, 0.16))
        ctx.setLineWidth(3 * u)
        ctx.addPath(CGPath(roundedRect: court, cornerWidth: 26 * u, cornerHeight: 26 * u, transform: nil))
        ctx.strokePath()
        let dots = 22
        for i in 0..<dots {
            let y = court.minY + 20 * u + CGFloat(i) / CGFloat(dots - 1) * (court.height - 40 * u)
            let middle = abs(y - size.height * 0.6) / (size.height * 0.28)
            let a = 0.08 + 0.18 * min(1, Double(middle * middle))
            ctx.fillCircle(center: CGPoint(x: size.width / 2, y: y), radius: 3.5 * u, color: HandGamePalette.color(HandGamePalette.cream, a))
        }
    }

    /// The ball and its tail, or while a ball is being served a ring round the one waiting in the middle. Nothing once the game is over.
    private func drawBallInPlay(_ ctx: CGContext, time: Double) {
        guard !isOver else { return }
        let middle = CGPoint(x: servePoint.x, y: servePoint.y)
        if serving > 0 {
            let r = CGFloat(radius)
            let ring = r * 2.1 * CGFloat(1 + 0.12 * sin(time * 8))
            ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.cream, 0.6))
            ctx.setLineWidth(4)
            ctx.setLineDash(phase: CGFloat(time * 40), lengths: [10, 8])
            ctx.strokeEllipse(in: CGRect(x: middle.x - ring, y: middle.y - ring, width: ring * 2, height: ring * 2))
            ctx.setLineDash(phase: 0, lengths: [])
            // An arrow toward you: the next ball comes your way.
            let a = CGPoint(x: middle.x - ring - 26, y: middle.y)
            ctx.setFillColor(HandGamePalette.color(HandGamePalette.cream, 0.6))
            ctx.move(to: CGPoint(x: a.x - 14, y: a.y)); ctx.addLine(to: CGPoint(x: a.x + 6, y: a.y + 12)); ctx.addLine(to: CGPoint(x: a.x + 6, y: a.y - 12))
            ctx.closePath()
            ctx.fillPath()
            drawBall(ctx, at: middle, time: time)
        } else {
            if trail.count > 1 {
                let points = (trail + [ball]).map { CGPoint(x: $0.x, y: $0.y) }
                let widths = points.indices.map { Double($0) / Double(points.count - 1) * radius * 1.7 }
                FruitSlashArt.ribbon(ctx, points, widths: widths, color: HandGamePalette.color(HandGamePalette.gold, 0.35))
            }
            drawBall(ctx, at: CGPoint(x: ball.x, y: ball.y), time: time)
        }
    }

    /// A ring round the palm in charge, so you can see which hand the paddle is listening to.
    private func drawPalmRing(_ ctx: CGContext, at palm: CGPoint, time: Double) {
        let u = CGFloat(unit)
        let r = 44 * u * CGFloat(1 + 0.04 * sin(time * 4))
        HandGameArt.halo(ctx, at: palm, radius: r * 1.4, red: HandGamePalette.sky.x, green: HandGamePalette.sky.y, blue: HandGamePalette.sky.z, alpha: 0.25)
        ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.ink, 0.45))
        ctx.setLineWidth(7 * u)
        ctx.strokeEllipse(in: CGRect(x: palm.x - r, y: palm.y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.sky, 0.95))
        ctx.setLineWidth(3.5 * u)
        ctx.strokeEllipse(in: CGRect(x: palm.x - r, y: palm.y - r, width: r * 2, height: r * 2))
        // A faint line from the palm to the paddle it steers.
        ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.sky, 0.25))
        ctx.setLineWidth(2 * u)
        ctx.setLineDash(phase: CGFloat(-time * 30), lengths: [5 * u, 9 * u])
        ctx.move(to: CGPoint(x: palm.x - r, y: palm.y))
        ctx.addLine(to: CGPoint(x: (Self.paddleMargin + Self.paddleHalfWidth * 2) * unit, y: playerY))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func drawPaddle(_ ctx: CGContext, x: Double, y: Double, half: Double, hot: Double, colour: SIMD3<Double>, dim: Double) {
        let u = CGFloat(unit)
        let squash = hot / 0.2
        let halfWidth = Self.paddleHalfWidth * unit * (1 + 0.45 * squash)
        let rect = CGRect(x: x - halfWidth, y: y - half * (1 - 0.06 * squash), width: halfWidth * 2, height: half * 2 * (1 - 0.06 * squash))
        if squash > 0.01 {
            HandGameArt.halo(ctx, in: rect.insetBy(dx: -50 * u, dy: -40 * u), red: colour.x, green: colour.y, blue: colour.z, alpha: 0.6 * squash * dim)
        }
        guard let sprite = Self.paddleSprite(colour, half: half / unit, scale: unit) else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(dim))
        let w = CGFloat(sprite.width), h = CGFloat(sprite.height)
        if squash > 0.01 {
            // The sprite has room round the paddle for its glow and shadow.
            let padX = (w - CGFloat(Self.paddleHalfWidth * 2 * unit)) / 2, padY = (h - CGFloat(half * 2)) / 2
            ctx.draw(sprite, in: rect.insetBy(dx: -padX, dy: -padY))
        } else {
            ctx.draw(sprite, in: CGRect(x: (x - Double(w) / 2).rounded(), y: (y - Double(h) / 2).rounded(), width: Double(w), height: Double(h)))
        }
        ctx.restoreGState()
    }

    /// A paddle with its shadow, gradient and glossy strip, baked once per colour and length.
    private static func paddleSprite(_ colour: SIMD3<Double>, half: Double, scale: Double = 1) -> CGImage? {
        let w = CGFloat(paddleHalfWidth * 2), h = CGFloat(half * 2), padX: CGFloat = 46, padY: CGFloat = 36
        let key = "pong.paddle.\(Int(half)).\(Int(colour.x * 255))\(Int(colour.y * 255)).\(Int(scale * 1000))"
        return HandGameSprites.image(key, size: CGSize(width: w + padX * 2, height: h + padY * 2), scale: CGFloat(scale)) { ctx in
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            // A soft glow in the paddle's colour, baked in.
            ctx.saveGState()
            ctx.scaleBy(x: w / 2 + padX, y: h / 2 + padY)
            HandGameSprites.radial(ctx, [HandGameSprites.shade(colour, 1, alpha: 0.38), HandGameSprites.shade(colour, 1, alpha: 0.12), HandGameSprites.shade(colour, 1, alpha: 0)],
                                   locations: [0, 0.6, 1], center: .zero, radius: 1)
            ctx.restoreGState()
            let r = w / 2
            let body = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 3, height: -5), blur: 8, color: HandGamePalette.color(HandGamePalette.ink, 0.5))
            ctx.addPath(body)
            ctx.setFillColor(HandGameSprites.shade(colour, 0.7))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(body)
            ctx.clip()
            HandGameSprites.linear(ctx, [HandGameSprites.shade(colour, 1.35), HandGameSprites.shade(colour, 1.0), HandGameSprites.shade(colour, 0.68)], locations: [0, 0.45, 1],
                                   from: CGPoint(x: rect.minX, y: 0), to: CGPoint(x: rect.maxX, y: 0))
            // A glossy strip down the lit side.
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.45))
            ctx.addPath(CGPath(roundedRect: CGRect(x: rect.minX + r * 0.35, y: rect.minY + r, width: r * 0.45, height: rect.height - r * 2),
                               cornerWidth: r * 0.2, cornerHeight: r * 0.2, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(body)
            ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.ink, 0.6))
            ctx.setLineWidth(2)
            ctx.strokePath()
        }
    }

    /// A glossy cream ball with a soft shadow below it.
    private func drawBall(_ ctx: CGContext, at p: CGPoint, time: Double) {
        let r = CGFloat(radius)
        HandGameArt.halo(ctx, at: CGPoint(x: p.x + r * 0.5, y: p.y - r * 0.8), radius: r * 1.5, red: HandGamePalette.ink.x, green: HandGamePalette.ink.y,
                         blue: HandGamePalette.ink.z, alpha: 0.45)
        HandGameArt.halo(ctx, at: p, radius: r * 2.6, red: 1, green: 0.9, blue: 0.55, alpha: 0.45)
        guard let sprite = Self.ballSprite() else { return }
        ctx.draw(sprite, center: p, height: r * 2 * 60 / 52)
    }

    static func warmUp(_ step: Int) -> Bool {
        switch step {
        case 0: _ = ballSprite()
        case 1: _ = paddleSprite(HandGamePalette.sky, half: playerHalfHeight)
        case 2: _ = paddleSprite(HandGamePalette.coral, half: computerHalfHeight)
        default: return false
        }
        return true
    }

    private static func ballSprite() -> CGImage? {
        HandGameSprites.image("pong.ball", size: CGSize(width: 60, height: 60)) { ctx in
            let rr: CGFloat = 26
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: -rr, y: -rr, width: rr * 2, height: rr * 2))
            ctx.clip()
            HandGameSprites.radial(ctx, [CGColor(srgbRed: 1, green: 1, blue: 0.97, alpha: 1), CGColor(srgbRed: 1, green: 0.93, blue: 0.7, alpha: 1),
                                         CGColor(srgbRed: 0.93, green: 0.7, blue: 0.36, alpha: 1)], locations: [0, 0.55, 1],
                                   center: CGPoint(x: 3, y: -3), radius: rr * 1.1, focus: CGPoint(x: -9, y: 9))
            ctx.restoreGState()
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
            ctx.fillEllipse(in: CGRect(x: -14, y: 6, width: 10, height: 7))
            ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.ink, 0.45))
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: -rr, y: -rr, width: rr * 2, height: rr * 2))
        }
    }
}
