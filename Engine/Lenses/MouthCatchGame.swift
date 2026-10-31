import AppKit
import CoreGraphics
import simd

/// Food rains down. Open your mouth to eat it; keep it shut for the bombs.
struct MouthCatchGame: FaceGame {
    static let title = "Mouth Catch"
    static let hint = "Open wide to eat the food. Keep your mouth shut for bombs!"
    static let presenceHint = "Look into the camera to play"
    static let roundSeconds = 45.0
    static let move = FaceGameMove.openMouth
    static let accent = FaceGamePalette.tangerine
    static let scoreLabel = "POINTS"

    enum Kind: Equatable { case food(Int), golden, bomb }

    struct Item {
        var position: SIMD2<Double>
        var fall: Double
        var phase: Double
        var kind: Kind
        var age = 0.0
    }

    /// The menu, in the order `Kind.food` numbers it.
    static let foods: [FaceGameFood.Kind] = [.pizza, .burger, .donut, .apple, .cookie, .strawberry, .watermelon, .cherries]
    static let itemRadius = 38.0
    /// Mouth opening that counts as "open". It stays open until the reading drops below `closeThreshold`, so a mouth hovering
    /// around the line doesn't flicker between eating and not.
    static let openThreshold = 0.36
    static let closeThreshold = 0.22

    let size: CGSize
    private(set) var items: [Item] = []
    private(set) var score = 0
    private(set) var timeLeft = MouthCatchGame.roundSeconds
    private(set) var eaten = 0
    private(set) var combo = 0
    private(set) var elapsed = 0.0
    private var sinceLastEat = 99.0
    private var crumbs = ParticleSystem(capacity: 320)
    private var floaters: [FaceGameFloater] = []
    private var lastFace: FaceState?
    private var mouth = FaceGameTrigger(on: MouthCatchGame.openThreshold, off: MouthCatchGame.closeThreshold, offDelay: 0.08)
    private var rng: SplitMix64
    private var nextSpawn = 0.4
    private var ouch = 0.0
    private var chomp = 0.0
    private var openness = 0.0

    var isOver: Bool { timeLeft <= 0 }
    var summary: String { combo >= 3 ? "x\(multiplier) · \(Int(timeLeft.rounded(.up)))s" : "\(Int(timeLeft.rounded(.up)))s" }
    var multiplier: Int { 1 + min(3, combo / 3) }
    var mouthIsOpen: Bool { mouth.isOn }

    var chips: [FaceGameChip] { [.clock(timeLeft, of: Self.roundSeconds), .multiplier(multiplier)] }
    var ending: FaceGameEnding { .timeUp("TIME'S UP!") }
    var endLine: String { eaten == 0 ? "Nothing eaten this time" : "You ate \(eaten) \(eaten == 1 ? "treat" : "treats")" }
    var tip: String? {
        if elapsed < 4 { return "Open wide to eat!" }
        if mouth.isOn, let face = lastFace, items.contains(where: { item in
            item.kind == .bomb && abs(item.position.x - Double(face.mouth.x)) < 130 && item.position.y > Double(face.mouth.y)
                && item.position.y - Double(face.mouth.y) < 240
        }) {
            return "Bomb! Shut your mouth!"
        }
        return nil
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        crumbs.gravity = SIMD2(0, -900)
    }

    /// How close to the mouth's middle an item has to be to be eaten.
    static func catchRadius(for face: FaceState) -> Double { max(46, face.mouthWidth * 0.8) + itemRadius * 0.4 }

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.1)
        elapsed += dt
        timeLeft = max(0, timeLeft - dt)
        sinceLastEat += dt
        ouch = max(0, ouch - dt * 2)
        chomp = max(0, chomp - dt * 4)
        if sinceLastEat > 2.2 { combo = 0 }
        if let face = world.face {
            lastFace = face
            mouth.update(face.mouthOpen, dt: dt)
        }
        openness = FaceGameEase.approach(openness, mouth.isOn ? 1 : 0, rate: 14, dt: dt)

        nextSpawn -= dt
        if nextSpawn <= 0 {
            spawn(near: lastFace.map { Double($0.mouth.x) })
            nextSpawn = max(0.45, 1.0 - elapsed * 0.012) * Double.random(in: 0.7...1.3, using: &rng)
        }
        for i in items.indices {
            items[i].age += dt
            items[i].position.y -= items[i].fall * dt
            items[i].position.x += sin(items[i].phase + elapsed * 2) * 22 * dt
        }

        if let face = world.face, mouth.isOn {
            pull(toward: face, dt: dt)
            eat(with: face)
        }
        items.removeAll { $0.position.y < -Self.itemRadius * 2 }

        crumbs.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
    }

    /// An open mouth draws nearby food in a little, so a real face that is a touch off still gets its snack. Bombs are never pulled.
    private mutating func pull(toward face: FaceState, dt: Double) {
        let mouthPoint = SIMD2(Double(face.mouth.x), Double(face.mouth.y))
        let reach = Self.catchRadius(for: face) * 2.2
        for i in items.indices where items[i].kind != .bomb {
            let gap = mouthPoint - items[i].position
            let d = simd_length(gap)
            guard d < reach, d > 1 else { continue }
            items[i].position += gap / d * min(d, 260 * dt * (1 - d / reach))
        }
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
        let mouthPoint = SIMD2(Double(face.mouth.x), Double(face.mouth.y))
        let reach = Self.catchRadius(for: face)
        var kept: [Item] = []
        for item in items {
            guard simd_distance(item.position, mouthPoint) < reach else { kept.append(item); continue }
            switch item.kind {
            case .bomb:
                score = max(0, score - 3)
                combo = 0
                ouch = 1
                floaters.append(FaceGameFloater(text: "-3", position: item.position + SIMD2(0, 40), tone: FaceGamePalette.coral, size: 56))
                boom(at: item.position)
            case .golden:
                combo += 1; sinceLastEat = 0; eaten += 1
                score += 5 * multiplier
                chomp = 1
                floaters.append(FaceGameFloater(text: "+\(5 * multiplier)", position: item.position + SIMD2(0, 50), tone: FaceGamePalette.sun, size: 64))
                crunch(at: item.position, tone: FaceGamePalette.sun, count: 22)
            case .food(let index):
                combo += 1; sinceLastEat = 0; eaten += 1
                score += multiplier
                chomp = 1
                floaters.append(FaceGameFloater(text: "+\(multiplier)", position: item.position + SIMD2(0, 50), tone: FaceGamePalette.cream))
                crunch(at: item.position, tone: Self.foods[index % Self.foods.count].juice, count: 14)
            }
        }
        items = kept
    }

    /// Crumbs in the food's own colour. The colour rides on the particle, packed into `kind` as three digits.
    private mutating func crunch(at p: SIMD2<Double>, tone: FaceGamePaint.Tone, count: Int) {
        let code = 1000 + Int(tone.x * 9) * 100 + Int(tone.y * 9) * 10 + Int(tone.z * 9)
        for _ in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 120...420, using: &rng)
            crumbs.emit(Particle(position: p, velocity: SIMD2(cos(a), sin(a) * 0.8 + 0.5) * s, life: Double.random(in: 0.35...0.8, using: &rng),
                                 size: Double.random(in: 3...8, using: &rng), hue: Double.random(in: 0...1, using: &rng), kind: code))
        }
    }

    private mutating func boom(at p: SIMD2<Double>) {
        for _ in 0..<12 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 40...160, using: &rng)
            crumbs.emit(Particle(position: p, velocity: SIMD2(cos(a), sin(a)) * s + SIMD2(0, 120), life: Double.random(in: 0.6...1.1, using: &rng),
                                 size: Double.random(in: 18...34, using: &rng), kind: 1))
        }
        for _ in 0..<22 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 220...560, using: &rng)
            crumbs.emit(Particle(position: p, velocity: SIMD2(cos(a), sin(a)) * s, life: Double.random(in: 0.3...0.6, using: &rng),
                                 size: Double.random(in: 5...11, using: &rng), kind: 2))
        }
    }

    /// After the round: crumbs land and words fade, nothing else moves.
    mutating func settle(_ dt: Double) {
        crumbs.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
        ouch = max(0, ouch - dt * 2)
        chomp = max(0, chomp - dt * 4)
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
        if ouch > 0.01 { drawOuch(ctx) }
        drawMouthRing(ctx, time: time)
        let shake = ouch * ouch * 10
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(sin(time * 61) * shake), y: CGFloat(cos(time * 53) * shake))
        for item in items { drawItem(item, ctx, time: time) }
        ctx.restoreGState()
        for p in crumbs.particles { drawCrumb(p, ctx) }
        FaceGamePaint.draw(floaters, in: ctx)
    }

    private func drawItem(_ item: Item, _ ctx: CGContext, time: Double) {
        let c = CGPoint(x: item.position.x, y: item.position.y)
        let sway = sin(item.phase + time * 2.6) * 0.22
        // A little stretch while it falls fast, and a jiggle as it appears.
        let stretch = 1 + 0.06 * min(1, item.fall / 400) + 0.12 * FaceGameEase.wobble(min(1, item.age / 0.6), swings: 2)
        switch item.kind {
        case .bomb:
            FaceGameArt.stamp(ctx, FaceGameFood.bomb, at: c, height: 104, rotation: sway, stretch: stretch)
            let tip = CGPoint(x: c.x + 104 * (FaceGameFood.fuseTip.x * cos(sway) - FaceGameFood.fuseTip.y * sin(sway)),
                              y: c.y + 104 * (FaceGameFood.fuseTip.x * sin(sway) + FaceGameFood.fuseTip.y * cos(sway)))
            let flicker = 0.7 + 0.3 * sin(time * 41 + item.phase)
            FaceGamePaint.spark(ctx, at: tip, radius: 26 * flicker, tone: FaceGamePalette.tangerine, alpha: 0.8)
            FaceGamePaint.spark(ctx, at: tip, radius: 10, tone: FaceGamePalette.cream, alpha: 1)
            for k in 0..<3 {
                let a = time * 9 + Double(k) * 2.1 + item.phase
                FaceGamePaint.spark(ctx, at: CGPoint(x: tip.x + cos(a) * 12, y: tip.y + sin(a * 1.3) * 12), radius: 5, tone: FaceGamePalette.sun, alpha: 0.9)
            }
        case .golden:
            let pulse = 1 + 0.06 * sin(time * 6 + item.phase)
            FaceGamePaint.spark(ctx, at: c, radius: 80 * pulse, tone: FaceGamePalette.sun, alpha: 0.45)
            FaceGameArt.stamp(ctx, FaceGameFood.golden, at: c, height: 104 * pulse, rotation: time * 1.4 + item.phase)
            for k in 0..<4 {
                let a = time * 2 + Double(k) * .pi / 2
                let twinkle = max(0, sin(time * 5 + Double(k) * 1.7))
                FaceGamePaint.spark(ctx, at: CGPoint(x: c.x + cos(a) * 58, y: c.y + sin(a) * 58), radius: 9 * twinkle, tone: FaceGamePalette.cream, alpha: twinkle)
            }
        case .food(let index):
            FaceGameArt.stamp(ctx, FaceGameFood.sprite(Self.foods[index % Self.foods.count]), at: c, height: 104, rotation: sway, stretch: stretch)
        }
    }

    /// A ring of light around an open mouth, so you can see where the food has to go; it flashes when you bite.
    private func drawMouthRing(_ ctx: CGContext, time: Double) {
        guard let face = lastFace, openness > 0.02 else { return }
        let c = face.mouth
        let r = Self.catchRadius(for: face) * (0.8 + 0.2 * openness) * (1 + 0.18 * chomp)
        FaceGamePaint.spark(ctx, at: c, radius: r * 1.5, tone: FaceGamePalette.mint, alpha: 0.25 * openness + 0.35 * chomp)
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: CGFloat(time * 40), lengths: [CGFloat(r * 0.32), CGFloat(r * 0.2)])
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.ink, 0.35 * openness))
        ctx.setLineWidth(9)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePaint.mix(FaceGamePalette.mint, FaceGamePalette.cream, chomp), 0.9 * openness))
        ctx.setLineWidth(5)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }

    /// A soft warm glow in from the edges when a bomb goes off: felt, not a red wall.
    private func drawOuch(_ ctx: CGContext) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let colors = [FaceGamePaint.cg(FaceGamePalette.coral, 0), FaceGamePaint.cg(FaceGamePalette.coral, 0.42 * ouch)] as CFArray
        if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: colors, locations: [0.45, 1]) {
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width * 0.62, options: [.drawsAfterEndLocation])
        }
    }

    private func drawCrumb(_ p: Particle, _ ctx: CGContext) {
        let point = CGPoint(x: p.position.x, y: p.position.y)
        switch p.kind {
        case 1:
            // Smoke: grows and fades.
            FaceGamePaint.spark(ctx, at: point, radius: p.size * (1 + 1.4 * p.progress), tone: FaceGamePaint.Tone(0.35, 0.33, 0.4), alpha: 0.55 * (1 - p.progress))
        case 2:
            FaceGamePaint.spark(ctx, at: point, radius: p.size * (1.4 - p.progress), tone: FaceGamePaint.mix(FaceGamePalette.sun, FaceGamePalette.tangerine, p.progress),
                                alpha: 1 - p.progress)
        default:
            let code = max(0, p.kind - 1000)
            var tone = FaceGamePaint.Tone(Double(code / 100) / 9, Double(code / 10 % 10) / 9, Double(code % 10) / 9)
            tone = FaceGamePaint.mix(tone, FaceGamePalette.cream, p.hue * 0.35)
            let r = p.size * (1 - 0.4 * p.progress)
            ctx.setFillColor(FaceGamePaint.cg(tone, 1 - p.progress * p.progress))
            ctx.fillEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        }
    }
}
