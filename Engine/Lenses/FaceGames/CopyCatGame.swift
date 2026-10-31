import AppKit
import CoreGraphics
import simd

/// The cat pulls a face; copy it before its timer runs out. Smile, open wide, raise your brows, shut your eyes, tip your head.
/// Each face copied scores, a quick copy scores more, and the cards come faster. Three misses and the round is over.
struct CopyCatGame: FaceGame {
    static let title = "Copy Cat"
    static let hint = "Copy the cat's face before its time runs out. Three misses and you're out."
    static let presenceHint = "Look into the camera to play"
    static let move = FaceGameMove.copyFaces
    static let accent = FaceGamePalette.berry
    static let scoreLabel = "POINTS"

    /// A face to copy.
    enum Pose: CaseIterable, Equatable {
        case smile, openWide, browsUp, eyesShut, tiltLeft, tiltRight

        var word: String {
            switch self {
            case .smile: return "SMILE!"
            case .openWide: return "OPEN WIDE!"
            case .browsUp: return "BROWS UP!"
            case .eyesShut: return "EYES SHUT!"
            case .tiltLeft, .tiltRight: return "TILT!"
            }
        }

        /// What the tip pill says if the player seems stuck.
        var nudge: String {
            switch self {
            case .smile: return "Big smile!"
            case .openWide: return "Open your mouth wide!"
            case .browsUp: return "Lift your eyebrows up high!"
            case .eyesShut: return "Close your eyes for a moment"
            case .tiltLeft, .tiltRight: return "Tip your head like the cat"
            }
        }

        /// How far the cat leans, in radians: the way to tip your head, as it appears in the picture.
        var lean: Double {
            switch self {
            case .tiltLeft: return 0.36
            case .tiltRight: return -0.36
            default: return 0
            }
        }

        /// 0...1: how much of this face the reading shows, where 1 is enough to count.
        func level(_ face: FaceState) -> Double {
            switch self {
            case .smile: return FaceGamePaint.clamp01(face.smile / 0.42)
            case .openWide: return FaceGamePaint.clamp01(face.mouthOpen / 0.42)
            case .browsUp: return FaceGamePaint.clamp01(face.browRaise / 0.48)
            case .eyesShut: return FaceGamePaint.clamp01(face.blink / 0.6)
            case .tiltLeft: return FaceGamePaint.clamp01(face.roll / 0.2)
            case .tiltRight: return FaceGamePaint.clamp01(-face.roll / 0.2)
            }
        }
    }

    enum Outcome: Equatable { case copied, missed }

    static let lives = 3
    /// How long a face must be held, once the reading is steadily there.
    static let holdSeconds = 0.4
    /// A copy this fast earns the bonus.
    static let quickSeconds = 1.4
    static func timeLimit(afterCopies n: Int) -> Double { max(2.4, 4.6 - 0.12 * Double(n)) }

    let size: CGSize
    private(set) var current: Pose = .smile
    private(set) var score = 0
    private(set) var hearts = CopyCatGame.lives
    private(set) var copies = 0
    /// Seconds the current face has been held.
    private(set) var hold = 0.0
    private(set) var cardAge = 0.0
    private(set) var outcome: Outcome?
    private(set) var elapsed = 0.0
    /// The reading for the current face, smoothed so one noisy frame neither makes nor breaks a copy.
    private(set) var level = 0.0
    private var limit = CopyCatGame.timeLimit(afterCopies: 0) + 1
    private var resolvedFor = 0.0
    private var stuckFor = 0.0
    private var lastFace: FaceState?
    private var rng: SplitMix64
    private var sparks = ParticleSystem(capacity: 200)
    private var floaters: [FaceGameFloater] = []

    /// How long a new card takes to slide in; the timer waits for it.
    static let entrance = 0.5

    var isOver: Bool { hearts <= 0 }
    var summary: String { "Lives \(hearts) · \(copies) copied" }
    var timeLeft: Double { max(0, limit - max(0, cardAge - Self.entrance)) }

    var chips: [FaceGameChip] { [.hearts(hearts, of: Self.lives)] }
    var ending: FaceGameEnding { .lost("THREE MISSES!") }
    var endLine: String { copies == 1 ? "You copied 1 face" : "You copied \(copies) faces" }
    var tip: String? {
        if elapsed < 3.5 { return "Copy the cat's face!" }
        if outcome == nil, stuckFor > 1.6 { return current.nudge }
        return nil
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        sparks.gravity = SIMD2(0, -500)
        sparks.drag = 1.5
        current = Pose.allCases[Int.random(in: 0..<3, using: &rng)]
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.1)
        sparks.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
        guard !isOver else { return }
        // The cat waits for a face: no one can copy anything without one.
        guard let face = world.face else { return }
        lastFace = face
        elapsed += dt
        cardAge += dt

        if outcome != nil {
            resolvedFor += dt
            if resolvedFor >= 0.7 { deal() }
            return
        }
        level = FaceGameEase.approach(level, current.level(face), rate: 12, dt: dt)
        if level >= 0.85 {
            hold += dt
            stuckFor = 0
        } else {
            hold = max(0, hold - dt * 1.5)
            if cardAge > Self.entrance { stuckFor += dt }
        }
        let needed = current == .eyesShut ? Self.holdSeconds * 0.75 : Self.holdSeconds
        if hold >= needed {
            copied()
        } else if cardAge > Self.entrance, timeLeft <= 0 {
            missed()
        }
    }

    private mutating func copied() {
        outcome = .copied
        resolvedFor = 0
        copies += 1
        let quick = cardAge - Self.entrance < Self.quickSeconds
        let points = 10 + (quick ? 5 : 0)
        score += points
        let card = cardCenter
        floaters.append(FaceGameFloater(text: "+\(points)", position: SIMD2(Double(card.x), Double(card.y) + 230), tone: FaceGamePalette.sun, size: 58))
        if quick {
            floaters.append(FaceGameFloater(text: "QUICK!", position: SIMD2(Double(card.x), Double(card.y) + 180), tone: FaceGamePalette.mint, size: 40, life: 1.0))
        }
        burst(at: card, count: 30, tones: [0, 1, 2])
        if let face = lastFace { burst(at: CGPoint(x: face.rect.midX, y: face.rect.maxY), count: 18, tones: [0, 3]) }
    }

    private mutating func missed() {
        outcome = .missed
        resolvedFor = 0
        hearts -= 1
        floaters.append(FaceGameFloater(text: "MISSED", position: SIMD2(Double(cardCenter.x), Double(cardCenter.y) + 220), tone: FaceGamePalette.coral, size: 44))
    }

    /// The next card: a different face from the last one.
    private mutating func deal() {
        var next = current
        while next == current { next = Pose.allCases[Int.random(in: 0..<Pose.allCases.count, using: &rng)] }
        current = next
        outcome = nil
        hold = 0
        level = 0
        cardAge = 0
        stuckFor = 0
        limit = Self.timeLimit(afterCopies: copies)
    }

    /// The colours sparks come in; a particle's `kind` picks one.
    private static let sparkTones = [FaceGamePalette.sun, FaceGamePalette.mint, FaceGamePalette.cream, FaceGamePalette.bubblegum]

    private mutating func burst(at p: CGPoint, count: Int, tones: [Int]) {
        for i in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), v = Double.random(in: 160...520, using: &rng)
            sparks.emit(Particle(position: SIMD2(Double(p.x), Double(p.y)), velocity: SIMD2(cos(a), sin(a)) * v + SIMD2(0, 120),
                                 life: Double.random(in: 0.5...1.0, using: &rng), size: Double.random(in: 6...16, using: &rng), kind: tones[i % tones.count]))
        }
    }

    /// After the round, the last card finishes falling away and the sparks settle.
    mutating func settle(_ dt: Double) {
        resolvedFor += dt
        sparks.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
    }

    // MARK: Test hooks

    /// Puts up a fresh card with this face.
    mutating func show(_ pose: Pose) {
        current = pose
        outcome = nil
        hold = 0
        level = 0
        cardAge = Self.entrance
        stuckFor = 0
        limit = Self.timeLimit(afterCopies: copies)
    }

    // MARK: Drawing

    private var cardCenter: CGPoint { CGPoint(x: size.width - 250, y: size.height * 0.52) }

    func draw(in ctx: CGContext, time: Double) {
        drawMirror(ctx, time: time)
        drawCard(ctx, time: time)
        for p in sparks.particles {
            let tone = Self.sparkTones[p.kind % Self.sparkTones.count]
            FaceGamePaint.spark(ctx, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 - 0.5 * p.progress), tone: tone, alpha: 1 - p.progress)
        }
        FaceGamePaint.draw(floaters, in: ctx)
    }

    /// The card with the cat, sliding in, flying off when copied, dropping away when missed.
    private func drawCard(_ ctx: CGContext, time: Double) {
        var c = cardCenter
        c.y += 5 * sin(time * 1.6)
        var rotation = 0.0
        var scale = 1.0, alpha = 1.0
        let enter = FaceGameEase.backOut(min(1, cardAge / Self.entrance), overshoot: 1.4)
        c.x += (1 - enter) * 460
        rotation += (1 - enter) * 0.3
        switch outcome {
        case .copied:
            let t = resolvedFor / 0.7
            scale = 1 + 0.12 * FaceGameEase.wobble(min(1, t * 2), swings: 1.5) + 0.1 * t
            c.y += 520 * t * t * t
            alpha = 1 - FaceGamePaint.smoothstep(0.5, 1, t)
        case .missed:
            let t = resolvedFor / 0.7
            rotation += FaceGameEase.wobble(min(1, t * 1.6), swings: 3) * 0.14 - 0.3 * t * t
            c.y -= 560 * t * t
            alpha = 1 - FaceGamePaint.smoothstep(0.55, 1, t)
        case nil:
            break
        }
        guard alpha > 0.01 else { return }
        let w = 300.0, h = 390.0
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(rotation))
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.setAlpha(CGFloat(alpha))

        let card = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        // The card itself, with its shadow and the coloured band for the word, is one kept picture.
        let band = CGRect(x: card.minX + 14, y: card.maxY - 78, width: w - 28, height: 64)
        let tone = outcome == .missed ? FaceGamePalette.coral : (outcome == .copied ? FaceGamePalette.mint * 0.85 : Self.accent)
        FaceGameArt.stamp(ctx, Self.cardBase(tone), at: CGPoint(x: 6, y: -8), height: h + 64)
        FaceGamePaint.label(ctx, current.word, at: CGPoint(x: 0, y: band.midY), align: .center, size: 36, fill: .white)

        // The cat, tipping its head when that is the face, with a ring that fills as you hold the face.
        let catCenter = CGPoint(x: 0, y: -12)
        let lean = current.lean * (0.75 + 0.25 * sin(time * 3))
        FaceGameArt.stamp(ctx, CopyCatArt.cat(current), at: catCenter, height: 240, rotation: lean)
        if current.lean != 0 { drawLeanArrow(ctx, center: catCenter, toLeft: current.lean > 0, time: time) }
        let needed = current == .eyesShut ? Self.holdSeconds * 0.75 : Self.holdSeconds
        let fill = outcome == .copied ? 1 : min(1, hold / needed)
        if fill > 0.01 {
            ctx.setLineCap(.round)
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.mint))
            ctx.setLineWidth(10)
            ctx.addArc(center: catCenter, radius: 118, startAngle: .pi / 2, endAngle: CGFloat(.pi / 2 - fill * 2 * .pi), clockwise: true)
            ctx.strokePath()
        }
        if outcome == .copied {
            FaceGameArt.stamp(ctx, FaceGameArt.starSprite(tone: FaceGamePalette.mint), at: CGPoint(x: 96, y: 80), height: 80 * FaceGameEase.backOut(min(1, resolvedFor / 0.3), overshoot: 2.5))
        }

        // The timer along the bottom, draining from mint to coral.
        let left = outcome == nil ? timeLeft / limit : 0
        let track = CGRect(x: card.minX + 30, y: card.minY + 22, width: w - 60, height: 16)
        FaceGamePaint.fill(ctx, rounded: track, radius: 8, color: FaceGamePaint.cg(FaceGamePalette.ink, 0.2))
        if left > 0.005 {
            let tone = left > 0.5 ? FaceGamePaint.mix(FaceGamePalette.sun, FaceGamePalette.mint, (left - 0.5) * 2) : FaceGamePaint.mix(FaceGamePalette.coral, FaceGamePalette.sun, left * 2)
            FaceGamePaint.fill(ctx, rounded: CGRect(x: track.minX, y: track.minY, width: max(16, track.width * left), height: track.height), radius: 8, color: FaceGamePaint.cg(tone))
        }
        ctx.restoreGState()
    }

    /// A blank card: cream, lit from the top left, with a soft shadow below and to the right and a band for the word.
    private static func cardBase(_ band: FaceGamePaint.Tone) -> CGImage? {
        let key = String(format: "copycat-card-%.2f-%.2f-%.2f", band.x, band.y, band.z)
        return FaceGameArt.sprite(key, width: 364, height: 454) { ctx, _ in
            // The card is drawn 6 pixels left and 8 up from the picture's middle, leaving room for its shadow.
            let card = CGRect(x: 26, y: 40, width: 300, height: 390)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 8, height: -12), blur: 22, color: FaceGamePaint.cg(FaceGamePalette.ink, 0.55))
            ctx.addPath(FaceGamePaint.roundedPath(card, radius: 34))
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.cream))
            ctx.fillPath()
            ctx.restoreGState()
            FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(card, radius: 34), tone: FaceGamePalette.cream, edgeWidth: 4, edgeTone: FaceGameArt.edge(of: accent), contrast: 0.4)
            let strip = CGRect(x: card.minX + 14, y: card.maxY - 78, width: card.width - 28, height: 64)
            FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(strip, radius: 24), tone: band, contrast: 0.6)
        }
    }

    /// A curved arrow beside the cat showing which way to tip.
    private func drawLeanArrow(_ ctx: CGContext, center c: CGPoint, toLeft: Bool, time: Double) {
        let side = toLeft ? -1.0 : 1.0
        let swing = 0.1 * sin(time * 3)
        let start = .pi / 2 + side * 0.25, end = .pi / 2 + side * (0.95 + swing)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(FaceGamePaint.cg(Self.accent))
        ctx.setLineWidth(9)
        ctx.addArc(center: c, radius: 132, startAngle: CGFloat(start), endAngle: CGFloat(end), clockwise: !toLeft)
        ctx.strokePath()
        let tip = CGPoint(x: c.x + cos(end) * 132, y: c.y + sin(end) * 132)
        let heading = end + side * .pi / 2
        let head = CGMutablePath()
        head.move(to: CGPoint(x: tip.x + cos(heading) * 18, y: tip.y + sin(heading) * 18))
        head.addLine(to: CGPoint(x: tip.x + cos(heading + 2.3) * 16, y: tip.y + sin(heading + 2.3) * 16))
        head.addLine(to: CGPoint(x: tip.x + cos(heading - 2.3) * 16, y: tip.y + sin(heading - 2.3) * 16))
        head.closeSubpath()
        ctx.addPath(head)
        ctx.setFillColor(FaceGamePaint.cg(Self.accent))
        ctx.fillPath()
    }

    /// "You": the little face copying what the camera reads off yours, with a meter for the face the cat wants.
    private func drawMirror(_ ctx: CGContext, time: Double) {
        let c = CGPoint(x: 250, y: size.height * 0.52)
        let rect = CGRect(x: c.x - 110, y: c.y - 130, width: 220, height: 260)
        GameUIPlate.draw(ctx, rect, radius: 36)
        FaceGamePaint.label(ctx, "YOU", at: CGPoint(x: c.x, y: rect.maxY - 30), align: .center, size: 24, fill: FaceGamePaint.nsColor(Self.accent))
        var pose = FaceGameMascot.Pose()
        if let f = lastFace {
            pose.eyes = 1 - f.blink
            pose.brows = f.browRaise
            pose.mouth = f.mouthOpen
            pose.smile = 0.2 + 0.8 * f.smile
            pose.tilt = max(-0.5, min(0.5, f.roll))
        }
        FaceGameMascot.draw(ctx, center: CGPoint(x: c.x, y: c.y + 6), radius: 70, pose: pose)
        let bar = CGRect(x: rect.minX + 30, y: rect.minY + 24, width: rect.width - 60, height: 18)
        FaceGamePaint.meter(ctx, in: bar, fill: outcome == .copied ? 1 : level, from: FaceGamePalette.sky, to: FaceGamePalette.mint)
    }
}
