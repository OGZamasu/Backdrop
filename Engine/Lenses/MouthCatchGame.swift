import AppKit
import CoreGraphics
import simd

/// Food rains down. Open your mouth to eat it; keep it shut for the bombs.
struct MouthCatchGame: Game {
    static let title = "Mouth Catch"
    static let hint = "Open wide to eat the food. Keep your mouth shut for bombs!"
    static let roundSeconds = 45.0

    enum Kind: Equatable { case food(Int), golden, bomb }

    struct Item {
        var position: SIMD2<Double>
        var fall: Double
        var phase: Double
        var kind: Kind
    }

    struct Floater { var text: String; var position: SIMD2<Double>; var age = 0.0; var good: Bool }

    static let foods = ["🍕", "🍔", "🍩", "🍎", "🍟", "🍪", "🍓", "🌮"]
    static let itemRadius = 38.0
    /// Mouth opening that counts as "open".
    static let openThreshold = 0.4

    let size: CGSize
    private(set) var items: [Item] = []
    private(set) var score = 0
    private(set) var timeLeft = MouthCatchGame.roundSeconds
    private(set) var eaten = 0
    private(set) var combo = 0
    private(set) var elapsed = 0.0
    private var sinceLastEat = 99.0
    private var crumbs = ParticleSystem(capacity: 300)
    private var floaters: [Floater] = []
    private var lastFace: FaceState?
    private var rng: SplitMix64
    private var nextSpawn = 0.4
    private var flash = 0.0

    var isOver: Bool { timeLeft <= 0 }
    var summary: String { combo >= 3 ? "x\(multiplier) · \(Int(timeLeft.rounded(.up)))s" : "\(Int(timeLeft.rounded(.up)))s" }
    var multiplier: Int { 1 + min(3, combo / 3) }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        crumbs.gravity = SIMD2(0, -900)
    }

    /// How close to the mouth's middle an item has to be to be eaten.
    static func catchRadius(for face: FaceState) -> Double { max(46, face.mouthWidth * 0.8) + itemRadius * 0.4 }

    mutating func step(_ dt: Double, world: GameWorld) {
        elapsed += dt
        timeLeft = max(0, timeLeft - dt)
        sinceLastEat += dt
        flash = max(0, flash - dt)
        if sinceLastEat > 2.2 { combo = 0 }
        if let face = world.face { lastFace = face }

        nextSpawn -= dt
        if nextSpawn <= 0 {
            spawn(near: lastFace.map { Double($0.mouth.x) })
            nextSpawn = max(0.45, 1.0 - elapsed * 0.012) * Double.random(in: 0.7...1.3, using: &rng)
        }
        for i in items.indices {
            items[i].position.y -= items[i].fall * dt
            items[i].position.x += sin(items[i].phase + elapsed * 2) * 22 * dt
        }

        if let face = world.face, face.mouthOpen > Self.openThreshold { eat(with: face) }
        items.removeAll { $0.position.y < -Self.itemRadius * 2 }

        crumbs.step(dt)
        for i in floaters.indices { floaters[i].age += dt; floaters[i].position.y += 80 * dt }
        floaters.removeAll { $0.age > 0.9 }
    }

    private mutating func spawn(near x: Double?) {
        let roll = Double.random(in: 0..<1, using: &rng)
        let kind: Kind = elapsed > 3 && roll < 0.15 ? .bomb : roll < 0.23 ? .golden : .food(Int.random(in: 0..<Self.foods.count, using: &rng))
        // Mostly where you are, so you're not chasing food off the edge of the picture.
        let centre = x ?? size.width / 2
        let spread = Double.random(in: 0..<1, using: &rng) < 0.7 ? 340.0 : size.width / 2
        let px = min(size.width - 80, max(80, centre + Double.random(in: -1...1, using: &rng) * spread))
        items.append(Item(position: SIMD2(px, size.height + Self.itemRadius),
                          fall: 230 + elapsed * 3 + Double.random(in: 0...110, using: &rng),
                          phase: Double.random(in: 0..<6.28, using: &rng), kind: kind))
    }

    private mutating func eat(with face: FaceState) {
        let mouth = SIMD2(Double(face.mouth.x), Double(face.mouth.y))
        let reach = Self.catchRadius(for: face)
        var kept: [Item] = []
        for item in items {
            guard simd_distance(item.position, mouth) < reach else { kept.append(item); continue }
            switch item.kind {
            case .bomb:
                score = max(0, score - 3)
                combo = 0
                flash = 0.35
                floaters.append(Floater(text: "-3", position: item.position, good: false))
                crunch(at: item.position, fire: true)
            case .golden:
                combo += 1; sinceLastEat = 0; eaten += 1
                score += 5 * multiplier
                floaters.append(Floater(text: "+\(5 * multiplier)", position: item.position, good: true))
                crunch(at: item.position, fire: false)
            case .food:
                combo += 1; sinceLastEat = 0; eaten += 1
                score += multiplier
                floaters.append(Floater(text: "+\(multiplier)", position: item.position, good: true))
                crunch(at: item.position, fire: false)
            }
        }
        items = kept
    }

    private mutating func crunch(at p: SIMD2<Double>, fire: Bool) {
        for _ in 0..<(fire ? 26 : 12) {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 100...380, using: &rng)
            crumbs.emit(Particle(position: p, velocity: SIMD2(cos(a), sin(a) * 0.8 + 0.4) * s, life: Double.random(in: 0.35...0.8, using: &rng),
                                 size: Double.random(in: 3...7, using: &rng), hue: fire ? 0.07 : 0.1, kind: fire ? 1 : 0))
        }
    }

    // MARK: Test hooks

    /// Replaces everything falling with one item per kind, all at `point`.
    mutating func setItems(_ kinds: [Kind], at point: CGPoint) {
        items = kinds.map { Item(position: SIMD2(Double(point.x), Double(point.y)), fall: 0, phase: 0, kind: $0) }
    }

    /// Moves everything now falling to `point`.
    mutating func moveAllItems(to point: CGPoint) {
        for i in items.indices { items[i].position = SIMD2(Double(point.x), Double(point.y)); items[i].fall = 0 }
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        if flash > 0 {
            ctx.setFillColor(CGColor(red: 1, green: 0.1, blue: 0.05, alpha: flash * 0.9))
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        for item in items {
            let c = CGPoint(x: item.position.x, y: item.position.y)
            let wobble = sin(item.phase + time * 3) * 0.25
            switch item.kind {
            case .bomb:
                if let s = Sprites.emoji("💣", size: 100) { ctx.draw(s, center: c, height: 84, rotation: wobble) }
            case .golden:
                ctx.glow(center: c, radius: 70, red: 1, green: 0.85, blue: 0.2, alpha: 0.75)
                if let s = Sprites.emoji("🍰", size: 100) { ctx.draw(s, center: c, height: 88, rotation: wobble) }
            case .food(let index):
                if let s = Sprites.emoji(Self.foods[index % Self.foods.count], size: 100) { ctx.draw(s, center: c, height: 80, rotation: wobble) }
            }
        }
        if let face = lastFace, face.mouthOpen > Self.openThreshold {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
            ctx.setLineWidth(3)
            let r = Self.catchRadius(for: face)
            ctx.strokeEllipse(in: CGRect(x: face.mouth.x - r, y: face.mouth.y - r, width: r * 2, height: r * 2))
        }
        for p in crumbs.particles {
            let (r, g, b) = p.kind == 1 ? (1.0, 0.45 + 0.4 * (1 - p.progress), 0.1) : (0.95, 0.75, 0.4)
            ctx.fillCircle(center: CGPoint(x: p.position.x, y: p.position.y), radius: p.size, color: CGColor(red: r, green: g, blue: b, alpha: 1 - p.progress))
        }
        for f in floaters {
            ctx.setAlpha(CGFloat(max(0, 1 - f.age / 0.9)))
            ctx.text(f.text, center: CGPoint(x: f.position.x, y: f.position.y), size: 52,
                     color: f.good ? NSColor(red: 1, green: 0.95, blue: 0.4, alpha: 1) : NSColor(red: 1, green: 0.35, blue: 0.3, alpha: 1))
        }
        ctx.setAlpha(1)
    }
}
