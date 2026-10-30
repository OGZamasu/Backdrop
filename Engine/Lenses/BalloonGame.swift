import AppKit
import CoreGraphics
import simd

/// Balloons drift up the screen. Swat them: they pop where your body is *moving*, so a still body lets them float past.
/// Gold ones are worth five, bombs cost you three.
struct BalloonGame: Game {
    static let title = "Balloon Pop"
    static let hint = "Wave and swat to pop balloons. Dodge the bombs!"

    enum Kind { case normal, gold, bomb }

    struct Balloon {
        var position: SIMD2<Double>
        var rise: Double
        var radius: Double
        var colour: Double
        var kind: Kind
        var phase: Double
    }

    struct Floater { var text: String; var position: SIMD2<Double>; var age = 0.0; var good: Bool }

    static let roundSeconds = 45.0

    let size: CGSize
    private(set) var balloons: [Balloon] = []
    private(set) var score = 0
    private(set) var timeLeft = BalloonGame.roundSeconds
    private(set) var elapsed = 0.0
    private(set) var popped = 0
    private var confetti = ParticleSystem(capacity: 400)
    private var floaters: [Floater] = []
    private var rng: SplitMix64
    private var nextSpawn = 0.3

    var isOver: Bool { timeLeft <= 0 }
    var summary: String { "\(Int(timeLeft.rounded(.up)))s" }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        confetti.gravity = SIMD2(0, -700)
    }

    mutating func step(_ dt: Double, world: GameWorld) {
        elapsed += dt
        timeLeft = max(0, timeLeft - dt)

        nextSpawn -= dt
        if nextSpawn <= 0 {
            spawn()
            nextSpawn = max(0.3, 0.95 - elapsed * 0.014) * Double.random(in: 0.7...1.3, using: &rng)
        }

        for i in balloons.indices {
            balloons[i].position.y += balloons[i].rise * dt
            balloons[i].position.x += sin(balloons[i].phase + elapsed * 1.4) * 34 * dt
        }
        balloons.removeAll { $0.position.y - $0.radius * 1.4 > size.height }

        if let motion = world.motion { pop(using: motion) }

        confetti.step(dt)
        for i in floaters.indices { floaters[i].age += dt; floaters[i].position.y += 70 * dt }
        floaters.removeAll { $0.age > 0.9 }
    }

    private mutating func spawn() {
        let roll = Double.random(in: 0..<1, using: &rng)
        let kind: Kind = elapsed > 4 && roll < 0.13 ? .bomb : roll < 0.2 ? .gold : .normal
        let radius = Double.random(in: 38...58, using: &rng)
        balloons.append(Balloon(position: SIMD2(Double.random(in: 90...(size.width - 90), using: &rng), -radius * 1.4),
                                rise: 90 + elapsed * 1.3 + Double.random(in: 0...60, using: &rng),
                                radius: radius, colour: Double.random(in: 0..<1, using: &rng), kind: kind,
                                phase: Double.random(in: 0..<6.28, using: &rng)))
    }

    private mutating func pop(using motion: MatteQuery) {
        var survivors: [Balloon] = []
        for balloon in balloons {
            if touched(balloon, by: motion) {
                popped += 1
                let points: Int
                switch balloon.kind {
                case .normal: points = 1
                case .gold: points = 5
                case .bomb: points = -3
                }
                score = max(0, score + points)
                burst(at: balloon)
                floaters.append(Floater(text: points > 0 ? "+\(points)" : "\(points)", position: balloon.position, good: points > 0))
            } else {
                survivors.append(balloon)
            }
        }
        balloons = survivors
    }

    /// Whether something is moving through the balloon: the strongest motion at its middle or around its rim.
    func touched(_ balloon: Balloon, by motion: MatteQuery) -> Bool {
        var strongest = motion.coverage(x: balloon.position.x, y: balloon.position.y)
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi
            strongest = max(strongest, motion.coverage(x: balloon.position.x + cos(a) * balloon.radius * 0.85,
                                                       y: balloon.position.y + sin(a) * balloon.radius * 1.0))
        }
        return strongest > 0.5
    }

    private mutating func burst(at balloon: Balloon) {
        for _ in 0..<(balloon.kind == .bomb ? 30 : 18) {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng), speed = Double.random(in: 120...420, using: &rng)
            confetti.emit(Particle(position: balloon.position, velocity: SIMD2(cos(angle), sin(angle)) * speed,
                                   life: Double.random(in: 0.5...1.0, using: &rng), size: Double.random(in: 4...9, using: &rng),
                                   hue: balloon.kind == .bomb ? 0.08 : balloon.colour + Double.random(in: -0.08...0.08, using: &rng),
                                   kind: balloon.kind == .bomb ? 1 : 0))
        }
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        for balloon in balloons { Self.drawBalloon(balloon, in: ctx) }
        for p in confetti.particles {
            let (r, g, b) = p.kind == 1 ? (1.0, 0.55 + 0.4 * (1 - p.progress), 0.1) : Palette.rgb(hue: p.hue)
            ctx.setAlpha(CGFloat(1 - p.progress))
            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: p.position.x - p.size, y: p.position.y - p.size * 0.6, width: p.size * 2, height: p.size * 1.2))
        }
        ctx.setAlpha(1)
        for f in floaters {
            ctx.setAlpha(CGFloat(max(0, 1 - f.age / 0.9)))
            ctx.text(f.text, center: CGPoint(x: f.position.x, y: f.position.y), size: 56,
                     color: f.good ? NSColor(red: 1, green: 0.95, blue: 0.4, alpha: 1) : NSColor(red: 1, green: 0.3, blue: 0.25, alpha: 1))
        }
        ctx.setAlpha(1)
    }

    static func drawBalloon(_ b: Balloon, in ctx: CGContext) {
        let c = CGPoint(x: b.position.x, y: b.position.y)
        if b.kind == .bomb {
            if let bomb = Sprites.emoji("💣", size: 110) { ctx.draw(bomb, center: c, height: b.radius * 2.3) }
            return
        }
        let ry = b.radius * 1.18
        // String.
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: c.x, y: c.y - ry))
        ctx.addCurve(to: CGPoint(x: c.x + sin(b.phase) * 10, y: c.y - ry - b.radius * 1.7),
                     control1: CGPoint(x: c.x - 14, y: c.y - ry - b.radius * 0.5),
                     control2: CGPoint(x: c.x + 14, y: c.y - ry - b.radius * 1.1))
        ctx.strokePath()
        // Body, shaded from a highlight toward the edge.
        let (r, g, bl) = b.kind == .gold ? (1.0, 0.8, 0.12) : Palette.rgb(hue: b.colour, saturation: 0.82, brightness: 0.96)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: min(1, r + 0.45), green: min(1, g + 0.45), blue: min(1, bl + 0.45), alpha: 1),
                                                               CGColor(red: r, green: g, blue: bl, alpha: 1),
                                                               CGColor(red: r * 0.6, green: g * 0.6, blue: bl * 0.6, alpha: 1)] as CFArray,
                                  locations: [0, 0.45, 1])!
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - b.radius, y: c.y - ry, width: b.radius * 2, height: ry * 2))
        ctx.clip()
        ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: c.x - b.radius * 0.35, y: c.y + ry * 0.4), startRadius: 0,
                               endCenter: c, endRadius: b.radius * 1.25, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        // Knot.
        ctx.setFillColor(CGColor(red: r * 0.7, green: g * 0.7, blue: bl * 0.7, alpha: 1))
        ctx.move(to: CGPoint(x: c.x, y: c.y - ry + 3))
        ctx.addLine(to: CGPoint(x: c.x - 7, y: c.y - ry - 8))
        ctx.addLine(to: CGPoint(x: c.x + 7, y: c.y - ry - 8))
        ctx.fillPath()
        if b.kind == .gold { ctx.text("★", center: c, size: b.radius * 0.9, color: NSColor(red: 1, green: 1, blue: 0.9, alpha: 0.9)) }
    }
}
