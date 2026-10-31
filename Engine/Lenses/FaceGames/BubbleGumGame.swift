import AppKit
import CoreGraphics
import simd

/// Blow a bubble-gum bubble from your own mouth. Keep your mouth open and it grows; close it and the bubble floats off and
/// scores by its size. But every bubble has a breaking point: blow too long and it pops all over your face. Three pops and the
/// round is over; otherwise it ends after a minute.
struct BubbleGumGame: FaceGame {
    static let title = "Bubble Gum"
    static let hint = "Keep your mouth open to blow. Close it to keep the bubble before it pops!"
    static let presenceHint = "Look into the camera to play"
    static let move = FaceGameMove.openMouth
    static let accent = FaceGamePalette.bubblegum
    static let scoreLabel = "POINTS"

    static let lives = 3
    static let roundSeconds = 60.0
    /// A bubble smaller than this when the mouth shuts just goes back in: no points, no harm.
    static let smallest = 0.18
    /// Bubbles never last past this size, and a few give up well before it.
    static let popRange = 0.55...1.0

    /// A bubble that was kept: floating up and away.
    struct Floater: Equatable {
        var position: SIMD2<Double>
        var radius: Double
        var age = 0.0
        var points: Int
    }

    let size: CGSize
    /// 0 with no bubble, growing towards 1 while you blow.
    private(set) var bubble = 0.0
    /// The size this bubble will pop at. Secret: the bubble only hints at it by wobbling.
    private(set) var popAt: Double
    private(set) var score = 0
    private(set) var hearts = BubbleGumGame.lives
    private(set) var kept = 0
    private(set) var biggest = 0
    private(set) var timeLeft = BubbleGumGame.roundSeconds
    private(set) var elapsed = 0.0
    private(set) var floating: [Floater] = []
    private var mouth = FaceGameTrigger(on: 0.3, off: 0.16, offDelay: 0.15)
    /// After a pop or a keep, the mouth has to close before a new bubble can start.
    private var needsClose = false
    private var lastFace: FaceState?
    private var splat = 0.0
    private var splatSeed = 0
    private var rng: SplitMix64
    private var shreds = ParticleSystem(capacity: 160)
    private var words: [FaceGameFloater] = []

    var isOver: Bool { hearts <= 0 || timeLeft <= 0 }
    var summary: String { "Lives \(hearts) · \(Int(timeLeft.rounded(.up)))s" }
    var blowing: Bool { mouth.isOn && !needsClose }

    var chips: [FaceGameChip] { [.clock(timeLeft, of: Self.roundSeconds), .hearts(hearts, of: Self.lives)] }
    var ending: FaceGameEnding { hearts <= 0 ? .lost("POP!") : .timeUp("TIME'S UP!") }
    var endLine: String { kept == 0 ? "No bubbles kept this time" : "You kept \(kept) \(kept == 1 ? "bubble" : "bubbles"), the biggest worth \(biggest)" }
    var tip: String? {
        if elapsed < 4, bubble == 0 { return "Open your mouth to blow!" }
        if bubble > 0.45 { return "Close your mouth to keep it!" }
        return nil
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        popAt = 1
        shreds.gravity = SIMD2(0, -900)
        shreds.drag = 0.8
        popAt = Double.random(in: Self.popRange, using: &rng)
    }

    /// How much a bubble of this size scores: 1 for a little one up to 10 at full size.
    static func points(for size: Double) -> Int { max(1, Int((size * 10).rounded())) }

    /// The bubble's radius in pixels for a face: bigger faces blow bigger bubbles.
    static func radius(_ size: Double, face: FaceState) -> Double { face.interocular * (0.3 + 2.1 * size) }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.1)
        shreds.step(dt)
        FaceGamePaint.advance(&words, by: dt)
        splat = max(0, splat - dt / 1.6)
        for i in floating.indices {
            floating[i].age += dt
            floating[i].position.y += (90 + 60 * floating[i].age) * dt
            floating[i].position.x += sin(floating[i].age * 2.4 + floating[i].radius) * 40 * dt
        }
        floating.removeAll { $0.age > 2.4 || $0.position.y - $0.radius > size.height }
        guard !isOver else { return }
        // The bubble holds while the face is gone.
        guard let face = world.face else { return }
        lastFace = face
        elapsed += dt
        timeLeft = max(0, timeLeft - dt)

        mouth.update(face.mouthOpen, dt: dt)
        if needsClose {
            if !mouth.isOn { needsClose = false }
            return
        }
        if mouth.isOn {
            // It grows faster as it gets bigger, like a real one.
            bubble += (0.2 + 0.32 * bubble) * dt
            if bubble >= popAt { pop(face) }
        } else if bubble > 0 {
            if bubble >= Self.smallest { keep(face) } else { bubble = max(0, bubble - dt * 1.5) }
        }
    }

    private mutating func keep(_ face: FaceState) {
        let points = Self.points(for: bubble)
        score += points
        kept += 1
        biggest = max(biggest, points)
        let r = Self.radius(bubble, face: face)
        let c = bubbleCenter(face, radius: r)
        floating.append(Floater(position: SIMD2(Double(c.x), Double(c.y)), radius: r, points: points))
        words.append(FaceGameFloater(text: "+\(points)", position: SIMD2(Double(c.x) + r * 0.9, Double(c.y) + r * 0.6), tone: points >= 8 ? FaceGamePalette.sun : FaceGamePalette.cream,
                                     size: points >= 8 ? 60 : 48))
        if points >= 8 {
            words.append(FaceGameFloater(text: "HUGE!", position: SIMD2(Double(c.x), Double(c.y) + r + 40), tone: FaceGamePalette.bubblegum, size: 52, life: 1.0))
        }
        newBubble()
    }

    private mutating func pop(_ face: FaceState) {
        hearts -= 1
        let r = Self.radius(bubble, face: face)
        let c = bubbleCenter(face, radius: r)
        for _ in 0..<26 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), v = Double.random(in: 0.5...1.2, using: &rng) * r * 3
            shreds.emit(Particle(position: SIMD2(Double(c.x) + cos(a) * r * 0.8, Double(c.y) + sin(a) * r * 0.8), velocity: SIMD2(cos(a), sin(a)) * v,
                                 life: Double.random(in: 0.4...0.9, using: &rng), size: Double.random(in: 8...20, using: &rng), hue: a))
        }
        splat = 1
        splatSeed = Int.random(in: 0..<1000, using: &rng)
        words.append(FaceGameFloater(text: "POP!", position: SIMD2(Double(c.x), Double(c.y) + r + 30), tone: FaceGamePalette.coral, size: 64, life: 1.0))
        newBubble()
    }

    private mutating func newBubble() {
        bubble = 0
        needsClose = true
        popAt = Double.random(in: Self.popRange, using: &rng)
    }

    /// After the round only the particles and words carry on; with no face, nothing in the rules moves.
    mutating func settle(_ dt: Double) {
        step(dt, world: GameWorld(size: size, matte: nil, motion: nil, face: nil))
    }

    // MARK: Test hooks

    /// Sets where the bubble now growing will pop.
    mutating func setPopPoint(_ value: Double) { popAt = value }

    // MARK: Drawing

    /// The bubble sits in front of the lips and grows mostly downwards and out, like a real one.
    private func bubbleCenter(_ face: FaceState, radius r: Double) -> CGPoint {
        let down = CGVector(dx: -face.up.dx, dy: -face.up.dy)
        let drop = r * 0.35
        return CGPoint(x: face.mouth.x + down.dx * drop, y: face.mouth.y + down.dy * drop)
    }

    func draw(in ctx: CGContext, time: Double) {
        for f in floating { drawFloating(f, ctx, time: time) }
        if let face = lastFace {
            if splat > 0.01 { drawSplat(ctx, face: face) }
            if bubble > 0.005 { drawBubble(ctx, face: face, time: time) }
        }
        for p in shreds.particles {
            let r = p.size * (1 - 0.3 * p.progress)
            ctx.saveGState()
            ctx.translateBy(x: p.position.x, y: p.position.y)
            ctx.rotate(by: CGFloat(p.hue + p.age * 5))
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.bubblegum, 1 - p.progress))
            ctx.fillEllipse(in: CGRect(x: -r, y: -r * 0.45, width: r * 2, height: r * 0.9))
            ctx.restoreGState()
        }
        drawGauge(ctx, time: time)
        FaceGamePaint.draw(words, in: ctx)
    }

    private func drawBubble(_ ctx: CGContext, face: FaceState, time: Double) {
        let r = Self.radius(bubble, face: face)
        let c = bubbleCenter(face, radius: r)
        // Close to its breaking point a bubble trembles and thins out: the only warning you get.
        let strain = FaceGamePaint.smoothstep(popAt - 0.2, popAt, bubble)
        let wobble = 0.03 + 0.09 * strain
        let sx = 1 + wobble * sin(time * (9 + 14 * strain)), sy = 1 + wobble * cos(time * (11 + 12 * strain))
        let breathe = blowing ? 1 + 0.02 * sin(time * 14) : 1
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(face.roll))
        ctx.scaleBy(x: CGFloat(sx * breathe), y: CGFloat(sy * breathe))
        FaceGameArt.stamp(ctx, BubbleGumArt.bubble, at: .zero, height: r * 2, alpha: 0.96 - 0.3 * strain)
        ctx.restoreGState()
    }

    private func drawFloating(_ f: Floater, _ ctx: CGContext, time: Double) {
        let fade = 1 - FaceGamePaint.smoothstep(1.7, 2.4, f.age)
        let shrink = 1 - 0.25 * FaceGamePaint.smoothstep(0, 2.4, f.age)
        let wobble = 1 + 0.04 * sin(f.age * 7)
        ctx.saveGState()
        ctx.translateBy(x: f.position.x, y: f.position.y)
        ctx.scaleBy(x: CGFloat(wobble), y: CGFloat(2 - wobble))
        FaceGameArt.stamp(ctx, BubbleGumArt.bubble, at: .zero, height: f.radius * 2 * shrink, alpha: 0.9 * fade)
        ctx.restoreGState()
        if f.age > 2.0 {
            let t = (f.age - 2.0) / 0.4
            for k in 0..<6 {
                let a = Double(k) / 6 * 2 * .pi
                let d = f.radius * shrink * (0.8 + 0.5 * t)
                FaceGamePaint.spark(ctx, at: CGPoint(x: f.position.x + cos(a) * d, y: f.position.y + sin(a) * d), radius: 10, tone: FaceGamePalette.cream, alpha: 1 - t)
            }
        }
    }

    /// Gum stuck all over the face after a pop, sliding off as it fades.
    private func drawSplat(_ ctx: CGContext, face: FaceState) {
        let r = face.interocular * 1.25
        let c = CGPoint(x: face.mouth.x + face.up.dx * r * 0.45, y: face.mouth.y + face.up.dy * r * 0.45 - (1 - splat) * 30)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(min(1, splat * 1.6)))
        FaceGameArt.stamp(ctx, BubbleGumArt.splat(splatSeed % 3), at: c, height: r * 2.4, rotation: face.roll)
        ctx.restoreGState()
    }

    /// A gauge down the left side showing how big the bubble is, against the sizes worth the most.
    private func drawGauge(_ ctx: CGContext, time: Double) {
        let plate = CGRect(x: GameScreens.margin.width, y: 150, width: 84, height: 340)
        GameUIPlate.draw(ctx, plate, radius: 34)
        let track = CGRect(x: plate.midX - 14, y: plate.minY + 64, width: 28, height: plate.height - 92)
        FaceGamePaint.fill(ctx, rounded: track, radius: 14, color: FaceGamePaint.cg(FaceGamePalette.ink, 0.8))
        let level = FaceGamePaint.clamp01(bubble)
        if level > 0.01 {
            let fill = CGRect(x: track.minX, y: track.minY, width: track.width, height: max(track.width, track.height * level))
            FaceGameArt.fillLit(ctx, FaceGamePaint.roundedPath(fill, radius: 14), tone: FaceGamePalette.bubblegum)
        }
        for tick in [0.25, 0.5, 0.75] {
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.cream, 0.5))
            ctx.fill(CGRect(x: track.minX - 6, y: track.minY + track.height * tick - 1.5, width: 6, height: 3))
        }
        FaceGamePaint.label(ctx, "\(Self.points(for: max(bubble, 0.01)))", at: CGPoint(x: plate.midX, y: plate.minY + 32), align: .center, size: 30,
                            fill: FaceGamePaint.nsColor(bubble > 0.75 ? FaceGamePalette.sun : FaceGamePalette.cream))
        FaceGameArt.stamp(ctx, BubbleGumArt.bubble, at: CGPoint(x: plate.midX, y: plate.maxY - 22), height: 30 + 6 * sin(time * 3))
    }
}

/// The bubble and the gum it leaves behind.
enum BubbleGumArt {
    typealias Tone = FaceGamePaint.Tone

    /// A glossy pink bubble, see-through in the middle and deeper at the rim, lit from the top left.
    static var bubble: CGImage? {
        FaceGameArt.sprite("bubblegum-bubble", width: 320, height: 320) { ctx, _ in
            let c = CGPoint(x: 160, y: 160), r = 150.0
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.saveGState()
            ctx.addEllipse(in: rect)
            ctx.clip()
            let gum = FaceGamePalette.bubblegum
            let colors = [FaceGamePaint.cg(FaceGameArt.lighter(gum, 0.5), 0.84), FaceGamePaint.cg(gum, 0.9), FaceGamePaint.cg(gum * 0.74, 0.98)] as CFArray
            if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: colors, locations: [0, 0.62, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - 26, y: c.y + 30), startRadius: 0, endCenter: c, endRadius: r, options: [.drawsAfterEndLocation])
            }
            // A faint band of colour from the thin film, and light bouncing up from below on the right.
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.sky, 0.16))
            ctx.setLineWidth(10)
            ctx.addArc(center: c, radius: CGFloat(r - 14), startAngle: -.pi * 0.35, endAngle: .pi * 0.15, clockwise: false)
            ctx.strokePath()
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.cream, 0.3))
            ctx.setLineWidth(8)
            ctx.addArc(center: c, radius: CGFloat(r - 10), startAngle: -.pi * 0.62, endAngle: -.pi * 0.3, clockwise: false)
            ctx.strokePath()
            ctx.restoreGState()
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: gum), 0.85))
            ctx.setLineWidth(4)
            ctx.strokeEllipse(in: rect.insetBy(dx: 2, dy: 2))
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 54, y: c.y + 62), width: 110, height: 56, rotation: 0.65, alpha: 0.75)
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 62, y: c.y + 70), width: 46, height: 22, rotation: 0.65, alpha: 0.95)
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 94, y: c.y + 20), width: 18, height: 14, alpha: 0.7)
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x + 70, y: c.y - 82), width: 40, height: 14, rotation: 0.7, alpha: 0.3)
        }
    }

    /// Gum spread over a face after a pop: a pink blob with drips.
    static func splat(_ variant: Int) -> CGImage? {
        FaceGameArt.sprite("bubblegum-splat-\(variant)", width: 240, height: 240) { ctx, _ in
            let c = CGPoint(x: 120, y: 128)
            var radii: [Double] = []
            for i in 0..<16 { radii.append(78 + 22 * FaceGamePaint.hash(i + variant * 40, 2)) }
            let blob = CGMutablePath()
            blob.addPath(FaceGameArt.blob(center: c, radii: radii, rotation: Double(variant)))
            for k in 0..<4 {
                let x = c.x - 60 + Double(k) * 40 + 10 * FaceGamePaint.hash(k + variant, 5)
                let len = 40 + 50 * FaceGamePaint.hash(k + variant, 6)
                blob.addPath(FaceGamePaint.roundedPath(CGRect(x: x - 9, y: c.y - 70 - len, width: 18, height: len + 30), radius: 9))
            }
            FaceGameArt.fillLit(ctx, blob, tone: FaceGamePalette.bubblegum, edgeWidth: 3, contrast: 0.8)
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 40, y: c.y + 46), width: 60, height: 26, rotation: 0.6, alpha: 0.6)
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x + 30, y: c.y + 10), width: 24, height: 12, rotation: 0.6, alpha: 0.4)
        }
    }
}
