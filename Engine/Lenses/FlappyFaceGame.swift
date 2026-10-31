import AppKit
import CoreGraphics
import simd

/// Flappy Bird where the bird is your face and your head is the controls: move up and down to fly through the gaps.
struct FlappyFaceGame: FaceGame {
    static let title = "Flappy Face"
    static let hint = "Move your head up and down to fly through the gaps."
    static let presenceHint = "Look into the camera to play"
    static let wantsFaceCrop = true
    static let move = FaceGameMove.nodHead
    static let accent = FaceGamePalette.sun
    static let scoreLabel = "GAPS"

    struct Pipe {
        var x: Double
        var gapCenter: Double
        var gap: Double
        var scored = false
    }

    static let pipeWidth = 120.0
    static let birdRadius = 42.0
    /// Slightly smaller than the face is drawn, so a graze isn't a hit.
    static let hitRadius = 34.0
    static let groundHeight = 34.0

    let size: CGSize
    private(set) var pipes: [Pipe] = []
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var birdY: Double
    private(set) var tilt = 0.0
    private(set) var invulnerable = 0.0
    private(set) var elapsed = 0.0
    /// How far the world has scrolled, for the parallax.
    private(set) var travelled = 0.0
    private var crop: CGImage?
    private var rng: SplitMix64
    private var spawnAt: Double
    private var feathers = ParticleSystem(capacity: 120)
    private var floaters: [FaceGameFloater] = []
    /// Where the bird was over the last moments, newest first, for its trail.
    private var trail: [Double] = []
    private var trailClock = 0.0
    private var dings: [(x: Double, y: Double, age: Double)] = []
    private var hitFlash = 0.0

    var birdX: Double { size.width * 0.24 }
    var isOver: Bool { lives <= 0 }
    var summary: String { "Lives " + String(repeating: "♥", count: max(0, lives)) }
    var speed: Double { 250 + min(130, Double(score) * 6) }

    var chips: [FaceGameChip] { [.hearts(max(0, lives), of: 3)] }
    var ending: FaceGameEnding { .lost("BONK!") }
    var endLine: String { score == 1 ? "You flew through 1 gap" : "You flew through \(score) gaps" }
    var tip: String? { elapsed < 4 ? "Move your head up and down" : nil }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        birdY = size.height / 2
        spawnAt = size.width + 120
        feathers.gravity = SIMD2(0, -380)
        feathers.drag = 1.4
    }

    mutating func step(_ dt: Double, world: GameWorld) {
        elapsed += dt
        if let crop = world.faceCrop { self.crop = crop }

        // The bird goes where your face goes, a touch smoothed.
        let target = world.face.map { Double($0.eyeCenter.y) } ?? birdY
        let previous = birdY
        birdY += (target - birdY) * min(1, dt * 14)
        birdY = min(size.height - Self.birdRadius, max(Self.birdRadius, birdY))
        tilt += ((birdY - previous) / max(dt, 1e-3) / 900 - tilt) * min(1, dt * 10)
        invulnerable = max(0, invulnerable - dt)
        hitFlash = max(0, hitFlash - dt * 2.5)
        travelled += speed * dt

        for i in pipes.indices { pipes[i].x -= speed * dt }
        spawnAt -= speed * dt
        if spawnAt <= size.width {
            addPipe()
            spawnAt += 430
        }
        pipes.removeAll { $0.x + Self.pipeWidth < -10 }

        for i in pipes.indices where !pipes[i].scored && pipes[i].x + Self.pipeWidth < birdX - Self.birdRadius {
            pipes[i].scored = true
            score += 1
            dings.append((pipes[i].x + Self.pipeWidth / 2, pipes[i].gapCenter, 0))
            floaters.append(FaceGameFloater(text: "+1", position: SIMD2(birdX + 20, birdY + 70), tone: FaceGamePalette.sun, size: 50, life: 0.8))
        }

        if invulnerable == 0, pipes.contains(where: { hits($0) }) {
            lives -= 1
            invulnerable = 1.6
            hitFlash = 1
            puffFeathers()
        }

        trailClock += dt
        if trailClock >= 1.0 / 30 {
            trailClock = 0
            trail.insert(birdY, at: 0)
            if trail.count > 10 { trail.removeLast() }
        }
        for i in dings.indices { dings[i].age += dt; dings[i].x -= speed * dt }
        dings.removeAll { $0.age > 0.6 }
        feathers.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
    }

    private mutating func addPipe() {
        let gap = max(205, 280 - Double(score) * 3)
        let margin = gap / 2 + 70
        var centre = Double.random(in: margin...(size.height - margin), using: &rng)
        // Never ask for more of a leap than a head can make in the time between pipes.
        if let last = pipes.last { centre = min(last.gapCenter + 230, max(last.gapCenter - 230, centre)) }
        centre = min(size.height - margin, max(margin, centre))
        pipes.append(Pipe(x: size.width + 20, gapCenter: centre, gap: gap))
    }

    private mutating func puffFeathers() {
        for _ in 0..<16 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 90...320, using: &rng)
            feathers.emit(Particle(position: SIMD2(birdX, birdY), velocity: SIMD2(cos(a), sin(a)) * s, life: Double.random(in: 0.8...1.4, using: &rng),
                                   size: Double.random(in: 9...16, using: &rng), hue: Double.random(in: 0..<(2 * .pi), using: &rng),
                                   kind: Int.random(in: 0...1, using: &rng)))
        }
    }

    /// After the round: feathers drift down and words fade, nothing else moves.
    mutating func settle(_ dt: Double) {
        feathers.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
        hitFlash = max(0, hitFlash - dt * 2.5)
        for i in dings.indices { dings[i].age += dt }
        dings.removeAll { $0.age > 0.6 }
    }

    /// Whether the bird overlaps a pipe's solid parts.
    func hits(_ pipe: Pipe) -> Bool {
        let r = Self.hitRadius
        guard birdX + r > pipe.x, birdX - r < pipe.x + Self.pipeWidth else { return false }
        return birdY - r < pipe.gapCenter - pipe.gap / 2 || birdY + r > pipe.gapCenter + pipe.gap / 2
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        FlappyFaceArt.drawBackdrop(ctx, size: size, travelled: travelled, time: time)
        for pipe in pipes { FlappyFaceArt.drawPipe(ctx, x: pipe.x, gapCenter: pipe.gapCenter, gap: pipe.gap, width: Self.pipeWidth, size: size) }
        FlappyFaceArt.drawGround(ctx, size: size, height: Self.groundHeight, travelled: travelled)
        for ding in dings {
            let t = ding.age / 0.6
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.sun, 0.8 * (1 - t)))
            ctx.setLineWidth(CGFloat(6 * (1 - t) + 1))
            let r = 30 + 90 * FaceGameEase.cubicOut(t)
            ctx.strokeEllipse(in: CGRect(x: ding.x - r, y: ding.y - r, width: r * 2, height: r * 2))
        }
        drawTrail(ctx)
        drawBird(in: ctx, time: time)
        for p in feathers.particles {
            FlappyFaceArt.drawFeather(ctx, at: CGPoint(x: p.position.x, y: p.position.y), size: p.size, angle: p.hue + p.age * 5,
                                      alpha: 1 - p.progress * p.progress, white: p.kind == 1)
        }
        FaceGamePaint.draw(floaters, in: ctx)
    }

    /// Puffs of air the bird leaves behind as it flies.
    private func drawTrail(_ ctx: CGContext) {
        for (i, y) in trail.enumerated() where i > 1 {
            let t = Double(i) / Double(max(1, trail.count))
            let x = birdX - Self.birdRadius * 0.9 - Double(i) * speed / 30
            FaceGamePaint.spark(ctx, at: CGPoint(x: x, y: y), radius: 14 * (1 - t) + 4, tone: FaceGamePalette.cream, alpha: 0.35 * (1 - t))
        }
    }

    private func drawBird(in ctx: CGContext, time: Double) {
        // While safe after a hit the bird breathes in and out of view: a soft pulse, never a strobe.
        let safe = invulnerable > 0 ? 0.55 + 0.45 * (0.5 + 0.5 * cos(invulnerable * 2 * .pi * 2.5)) : 1
        ctx.saveGState()
        ctx.setAlpha(CGFloat(safe))
        ctx.translateBy(x: birdX, y: birdY)
        ctx.rotate(by: CGFloat(max(-0.5, min(0.5, tilt))))
        if hitFlash > 0.01 {
            FaceGamePaint.spark(ctx, at: .zero, radius: Self.birdRadius * (1.8 + 0.8 * (1 - hitFlash)), tone: FaceGamePalette.coral, alpha: 0.7 * hitFlash)
        }
        FlappyFaceArt.drawBird(ctx, radius: Self.birdRadius, flap: time * 15, crop: crop, hurt: hitFlash > 0.3)
        ctx.restoreGState()
    }
}
