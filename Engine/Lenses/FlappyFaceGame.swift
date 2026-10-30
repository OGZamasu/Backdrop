import AppKit
import CoreGraphics
import simd

/// Flappy Bird where the bird is your face and your head is the controls: move up and down to fly through the gaps.
struct FlappyFaceGame: Game {
    static let title = "Flappy Face"
    static let hint = "Move your head up and down to fly through the gaps."
    static let wantsFaceCrop = true

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

    let size: CGSize
    private(set) var pipes: [Pipe] = []
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var birdY: Double
    private(set) var tilt = 0.0
    private(set) var invulnerable = 0.0
    private(set) var elapsed = 0.0
    private var crop: CGImage?
    private var rng: SplitMix64
    private var spawnAt: Double

    var birdX: Double { size.width * 0.24 }
    var isOver: Bool { lives <= 0 }
    var summary: String { "Lives " + String(repeating: "♥", count: max(0, lives)) }
    var speed: Double { 250 + min(130, Double(score) * 6) }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        birdY = size.height / 2
        spawnAt = size.width + 120
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
        }

        if invulnerable == 0, pipes.contains(where: { hits($0) }) {
            lives -= 1
            invulnerable = 1.6
        }
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

    /// Whether the bird overlaps a pipe's solid parts.
    func hits(_ pipe: Pipe) -> Bool {
        let r = Self.hitRadius
        guard birdX + r > pipe.x, birdX - r < pipe.x + Self.pipeWidth else { return false }
        return birdY - r < pipe.gapCenter - pipe.gap / 2 || birdY + r > pipe.gapCenter + pipe.gap / 2
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        for pipe in pipes { Self.drawPipe(pipe, size: size, in: ctx) }
        drawBird(in: ctx, time: time)
    }

    private static func drawPipe(_ pipe: Pipe, size: CGSize, in ctx: CGContext) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let body = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.45, green: 0.85, blue: 0.3, alpha: 1), CGColor(red: 0.2, green: 0.55, blue: 0.15, alpha: 1),
                                                           CGColor(red: 0.12, green: 0.38, blue: 0.1, alpha: 1)] as CFArray, locations: [0, 0.45, 1])!
        let capHeight = 40.0, overhang = 10.0
        let bottom = CGRect(x: pipe.x, y: -10, width: pipeWidth, height: pipe.gapCenter - pipe.gap / 2 + 10)
        let top = CGRect(x: pipe.x, y: pipe.gapCenter + pipe.gap / 2, width: pipeWidth, height: size.height - (pipe.gapCenter + pipe.gap / 2) + 10)
        for (rect, capY) in [(bottom, bottom.maxY - capHeight), (top, top.minY)] {
            for part in [rect, CGRect(x: rect.minX - overhang, y: capY, width: rect.width + overhang * 2, height: capHeight)] {
                ctx.saveGState()
                ctx.addPath(CGPath(roundedRect: part, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.clip()
                ctx.drawLinearGradient(body, start: CGPoint(x: part.minX, y: 0), end: CGPoint(x: part.maxX, y: 0), options: [])
                ctx.restoreGState()
                ctx.setStrokeColor(CGColor(red: 0.08, green: 0.25, blue: 0.07, alpha: 1)); ctx.setLineWidth(4)
                ctx.addPath(CGPath(roundedRect: part, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.strokePath()
            }
        }
    }

    private func drawBird(in ctx: CGContext, time: Double) {
        if invulnerable > 0, Int(invulnerable * 12) % 2 == 0 { return }       // blink while safe
        let c = CGPoint(x: birdX, y: birdY)
        let r = Self.birdRadius
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: max(-0.5, min(0.5, tilt)))
        // Wings flap either side of the head.
        let flap = sin(time * 20) * 0.5
        for side in [-1.0, 1.0] {
            ctx.saveGState()
            ctx.translateBy(x: side * (r + 6), y: -4)
            ctx.rotate(by: side * (0.5 + flap))
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
            ctx.fillEllipse(in: CGRect(x: side > 0 ? -4 : -32, y: -10, width: 36, height: 20))
            ctx.restoreGState()
        }
        let face = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
        if let crop {
            ctx.saveGState()
            ctx.addEllipse(in: face); ctx.clip()
            ctx.draw(crop, in: face)
            ctx.restoreGState()
        } else if let chick = Sprites.emoji("🐤", size: 100) {
            ctx.draw(chick, center: .zero, height: r * 2.2)
        }
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.setLineWidth(5)
        ctx.strokeEllipse(in: face)
        ctx.restoreGState()
    }
}
