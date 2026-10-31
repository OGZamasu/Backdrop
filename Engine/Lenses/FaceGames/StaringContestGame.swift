import AppKit
import CoreGraphics
import simd

/// Don't blink. Your face sits in a marquee frame in the middle while the screen tries everything to make you: a turning swirl,
/// soft flashes, silly creatures closing in, and taunts. The round ends the moment your eyes shut; last 30 seconds and you win.
///
/// The score is how long your eyes stayed open, in tenths of a second.
struct StaringContestGame: FaceGame {
    static let title = "Staring Contest"
    static let hint = "Don't blink! Keep your eyes open for 30 seconds."
    static let presenceHint = "Look into the camera to play"
    static let wantsFaceCrop = true
    /// The face fills a big frame here, so it is cut out sharper than the other games need.
    static let faceCropSide = 256
    static let move = FaceGameMove.keepEyesOpen
    static let accent = FaceGamePalette.bubblegum
    static let scoreLabel = "EYES OPEN"

    /// Open your eyes this long and you win.
    static let winSeconds = 30.0
    /// A blink has to read this long, so one noisy frame can't end the round.
    static let blinkDwell = 0.05
    /// The lights never flash faster than this; more than three flashes a second can be hard on some viewers.
    static let maxFlashesPerSecond = 2.5
    static let frameSide = 300.0
    /// How far from the frame's middle a creature starts, and where it stops and pops.
    static let intruderStart = 480.0
    static let intruderStop = 205.0
    static let maxIntruders = 11

    static let taunts = ["DON'T BLINK!", "BLINK AND YOU LOSE", "YOUR EYES ARE SO DRY", "JUST ONE LITTLE BLINK?", "EYES WIDE OPEN",
                         "EVERYONE IS WATCHING", "BLINKING IS FOR QUITTERS", "SOMETHING IN YOUR EYE?", "SO TEMPTING TO BLINK…",
                         "NOT EVEN A TINY ONE", "DON'T LOOK AWAY", "YOU CAN'T BEAT ME"]

    /// A silly creature on its way in from the edge of the picture.
    struct Intruder: Equatable {
        /// Which way from the frame it comes from, in radians.
        var angle: Double
        /// How far it still has to go: `intruderStart` when it appears, `intruderStop` when it pops.
        var distance: Double
        var speed: Double
        var drift: Double
        var spin: Double
        var phase: Double
        var variant: Int
        var age = 0.0
    }

    let size: CGSize
    private(set) var elapsed = 0.0
    private(set) var blinked = false
    private(set) var won = false
    /// 0 at the start to 1 at the end: how hard the screen is trying.
    private(set) var tension = 0.0
    /// The most recent blink reading.
    private(set) var blinkLevel = 0.0
    private(set) var intruders: [Intruder] = []
    private(set) var taunt = StaringContestGame.taunts[0]
    private(set) var flashCount = 0
    /// How long the face has been missing; the clock waits while it is.
    private(set) var faceLostFor = 0.0

    private var watch = FaceGameTrigger(on: 0.6, off: 0.35)
    /// How closed the eyes read when they're only squinting. Raises the bar a little for someone who laughs with their eyes shut.
    private var restLevel = 0.0
    private var crop: CGImage?
    private var rng: SplitMix64
    private var spin = 0.0
    private var wobble = 0.0
    private var shake = 0.0
    private var spawnTimer = 1.8
    private var tauntTimer = 2.6
    private var tauntAge = 0.0
    private var tauntLife = 2.4
    private var tauntIndex = 0
    private var fakeTimer = 7.0
    private var fakeAge: Double?
    private var flashTimer = 3.0
    private var flash = 0.0
    private var flashAngle = 0.0
    private var sparks = ParticleSystem(capacity: 260)
    private var floaters: [FaceGameFloater] = []
    private var lastTen = 0
    /// 0 while playing, easing to 1 after the round so the frame moves up out of the end card's way.
    private var outro = 0.0
    private var outroClock = 0.0

    var score: Int { Int((elapsed * 10 + 1e-6).rounded(.down)) }
    var isOver: Bool { blinked || won }
    var summary: String { String(format: "%.1f / %.0f s", elapsed, Self.winSeconds) }

    static func scoreText(_ score: Int) -> String { String(format: "%.1f s", Double(score) / 10) }
    var chips: [FaceGameChip] { [.clock(Self.winSeconds - elapsed, of: Self.winSeconds)] }
    var ending: FaceGameEnding { won ? .won("YOU WIN!") : .lost("YOU BLINKED!") }
    var endLine: String { won ? "30 seconds without a single blink" : String(format: "Eyes open for %.1f seconds", elapsed) }
    var tip: String? { elapsed < 3 ? "Keep your eyes open!" : nil }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        sparks.gravity = .zero
        sparks.drag = 2.4
    }

    /// Seconds between flashes at a given tension: slower early on, never faster than `maxFlashesPerSecond`.
    static func flashInterval(tension: Double) -> Double {
        max(1 / maxFlashesPerSecond, FaceGamePaint.lerp(2.4, 0.5, tension))
    }

    /// The text of the fake "3, 2, 1, blink!" countdown at this moment, if one is running.
    var fakeCountdown: String? {
        guard let age = fakeAge else { return nil }
        switch age {
        case ..<0.9: return "3"
        case ..<1.8: return "2"
        case ..<2.7: return "1"
        case ..<3.4: return "BLINK!"
        default: return "just kidding"
        }
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.1)
        if let crop = world.faceCrop { self.crop = crop }
        guard !isOver else { return }
        // A blink can't be judged without a face, so the clock waits for it rather than counting time no one can check.
        guard let face = world.face else { faceLostFor += dt; return }
        faceLostFor = 0

        blinkLevel = face.blink
        watchForBlink(face.blink, dt: dt)
        if blinked { burst(at: center, count: 30, hueBase: 0.0, hueSpread: 0.04, speed: 420); return }

        elapsed = min(Self.winSeconds, elapsed + dt)
        tension = min(1, pow(elapsed / Self.winSeconds, 0.85))
        advanceShow(dt)
        let tens = Int(elapsed / 10)
        if tens > lastTen, elapsed < Self.winSeconds - 1e-9 {
            lastTen = tens
            floaters.append(FaceGameFloater(text: "\(tens * 10) SECONDS!", position: SIMD2(size.width / 2 + 330, center.y + 120),
                                            tone: FaceGamePalette.sun, size: 48, life: 1.4, rise: 40))
            burst(at: center, count: 36, hueBase: 0.13, hueSpread: 0.05, speed: 520)
        }
        if elapsed >= Self.winSeconds - 1e-9 {
            elapsed = Self.winSeconds
            won = true
            burst(at: center, count: 60, hueBase: 0.13, hueSpread: 0.06, speed: 640)
        }
    }

    /// A blink is the reading staying high for a moment. Once it is high it has to fall well below before it counts as open again,
    /// so a squint that wobbles around the line can't end the round, and neither can one noisy frame.
    private mutating func watchForBlink(_ level: Double, dt: Double) {
        let enter = min(0.8, 0.6 + 0.5 * restLevel)
        watch.on = enter
        watch.off = enter - 0.25
        watch.update(level, dt: dt)
        if !watch.isOn {
            restLevel += (min(level, 0.4) - restLevel) * min(1, dt / 2)
        }
        if watch.isOn, watch.onFor >= Self.blinkDwell - 1e-9 { blinked = true }
    }

    private mutating func advanceShow(_ dt: Double) {
        spin += dt * (0.35 + 1.4 * tension)
        wobble += dt * (1.2 + 2.6 * tension)
        shake = max(0, shake - dt * 2.5)

        spawnTimer -= dt
        if spawnTimer <= 0 {
            if intruders.count < Self.maxIntruders { spawnIntruder() }
            spawnTimer = FaceGamePaint.lerp(1.7, 0.4, tension) * Double.random(in: 0.75...1.25, using: &rng)
        }
        var arrived: [Intruder] = []
        for i in intruders.indices {
            intruders[i].distance -= intruders[i].speed * dt
            intruders[i].angle += intruders[i].drift * dt
            intruders[i].age += dt
            if intruders[i].distance <= Self.intruderStop { arrived.append(intruders[i]) }
        }
        intruders.removeAll { $0.distance <= Self.intruderStop }
        for gone in arrived {
            burst(at: position(of: gone), count: 16, hueBase: Double(gone.variant) / Double(StaringContestArt.goofCount), hueSpread: 0.05, speed: 340)
            shake = min(1, shake + 0.25)
        }

        tauntAge += dt
        tauntTimer -= dt
        if tauntTimer <= 0 {
            tauntIndex = (tauntIndex + 1) % Self.taunts.count
            taunt = Self.taunts[tauntIndex]
            tauntAge = 0
            let gap = FaceGamePaint.lerp(3.2, 1.7, tension)
            tauntLife = gap * 0.92
            tauntTimer = gap
        }

        if let age = fakeAge {
            fakeAge = age + dt
            if age + dt > 4.2 {
                fakeAge = nil
                fakeTimer = FaceGamePaint.lerp(9, 5, tension) * Double.random(in: 0.85...1.2, using: &rng)
            }
        } else {
            fakeTimer -= dt
            if fakeTimer <= 0 { fakeAge = 0 }
        }

        flash = max(0, flash - dt * 3)
        flashTimer -= dt
        if flashTimer <= 0 {
            flash = 0.22 + 0.2 * tension
            flashCount += 1
            flashAngle = Double.random(in: 0..<(2 * .pi), using: &rng)
            flashTimer = Self.flashInterval(tension: tension) * Double.random(in: 1...1.4, using: &rng)
        }
        sparks.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
    }

    private mutating func spawnIntruder() {
        let fast = 70 + 110 * tension
        intruders.append(Intruder(angle: Double.random(in: 0..<(2 * .pi), using: &rng), distance: Self.intruderStart,
                                  speed: fast * Double.random(in: 0.8...1.2, using: &rng),
                                  drift: Double.random(in: -0.25...0.25, using: &rng), spin: Double.random(in: -1.5...1.5, using: &rng),
                                  phase: Double.random(in: 0..<(2 * .pi), using: &rng),
                                  variant: Int.random(in: 0..<StaringContestArt.goofCount, using: &rng)))
    }

    private mutating func burst(at p: CGPoint, count: Int, hueBase: Double, hueSpread: Double, speed: Double) {
        for _ in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), v = Double.random(in: 0.3...1, using: &rng) * speed
            sparks.emit(Particle(position: SIMD2(Double(p.x), Double(p.y)), velocity: SIMD2(cos(a), sin(a)) * v,
                                 life: Double.random(in: 0.5...1.1, using: &rng), size: Double.random(in: 8...22, using: &rng),
                                 hue: hueBase + Double.random(in: -hueSpread...hueSpread, using: &rng)))
        }
    }

    mutating func settle(_ dt: Double) {
        outroClock += dt
        outro = FaceGameEase.cubicOut(min(1, outroClock / 0.6))
        sparks.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
    }

    // MARK: Layout

    /// Where the frame sits: in the middle, easing up and shrinking once the round is over.
    private var center: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.57 + 72 * outro) }
    private var frameScale: Double { 1 - 0.3 * outro }

    private func position(of intruder: Intruder) -> CGPoint {
        CGPoint(x: center.x + cos(intruder.angle) * intruder.distance * 1.5, y: center.y + sin(intruder.angle) * intruder.distance * 0.92)
    }

    /// Mint when calm, gold, then coral as the pressure builds.
    private var tensionTone: FaceGamePaint.Tone {
        tension < 0.5 ? FaceGamePaint.mix(FaceGamePalette.mint, FaceGamePalette.sun, tension * 2)
            : FaceGamePaint.mix(FaceGamePalette.sun, FaceGamePalette.coral, (tension - 0.5) * 2)
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        ctx.saveGState()
        let shaking = isOver ? 0 : shake * 12 + tension * tension * 4
        ctx.translateBy(x: CGFloat(sin(time * 53) * shaking), y: CGFloat(cos(time * 47) * shaking))
        drawSwirl(ctx, time: time)
        drawIntruders(ctx, time: time)
        drawBulbs(ctx, time: time)
        drawFrame(ctx, time: time)
        drawFlash(ctx)
        for p in sparks.particles { drawSpark(p, ctx) }
        ctx.restoreGState()
        if !isOver, elapsed > 0 { drawHUD(ctx, time: time) }
        FaceGamePaint.draw(floaters, in: ctx)
    }

    /// A hypnotic swirl turning slowly behind the frame, livelier and brighter as the tension rises. Two arms stroked as paths:
    /// much cheaper than turning a picture the size of the screen.
    private func drawSwirl(_ ctx: CGContext, time: Double) {
        let alpha = (0.2 + 0.22 * tension) * (1 - outro)
        guard alpha > 0.01 else { return }
        let sway = 6 + 30 * tension
        let o = CGPoint(x: center.x + CGFloat(sin(wobble * 0.9) * sway), y: center.y + CGFloat(cos(wobble * 0.7) * sway * 0.6))
        let tones = [FaceGamePalette.grape, FaceGamePalette.bubblegum]
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.bevel)
        ctx.setLineWidth(24)
        let breathe = 1 + 0.05 * sin(time * 0.8)
        for arm in 0..<2 {
            // Points along the arm, joined by curves through their midpoints so the arm is smooth with few points.
            var points: [CGPoint] = []
            for i in 0...36 {
                let f = Double(i) / 36
                let theta = f * 1.8 * 2 * .pi + Double(arm) * .pi - spin
                let r = (140 + f * 360) * breathe * (1 + (0.02 + 0.05 * tension) * sin(f * 16 - time * 4))
                points.append(CGPoint(x: o.x + cos(theta) * r * 1.45, y: o.y + sin(theta) * r * 0.9))
            }
            ctx.beginPath()
            ctx.move(to: points[0])
            for i in 1..<(points.count - 1) {
                let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
                ctx.addQuadCurve(to: mid, control: points[i])
            }
            ctx.addLine(to: points[points.count - 1])
            ctx.setStrokeColor(FaceGamePaint.cg(tones[arm], alpha))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// A pop of light at one corner of the frame, like a camera flash going off: a bright spot and a ring that races out and fades.
    /// Never more than `maxFlashesPerSecond` a second, never a white-out, and small enough to cost almost nothing.
    private func drawFlash(_ ctx: CGContext) {
        guard flash > 0.01, !isOver else { return }
        let reach = Self.frameSide * 0.72
        let from = CGPoint(x: center.x + cos(flashAngle) * reach, y: center.y + sin(flashAngle) * reach * 0.85)
        let t = FaceGamePaint.clamp01(1 - flash / 0.42)
        FaceGamePaint.spark(ctx, at: from, radius: 70 + 60 * t, tone: FaceGamePaint.Tone(1, 0.96, 0.88), alpha: min(1, flash * 2.2))
        let r = 40 + 170 * FaceGameEase.cubicOut(t)
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.cream, min(0.8, flash * 1.8)))
        ctx.setLineWidth(CGFloat(3 + 9 * (1 - t)))
        ctx.strokeEllipse(in: CGRect(x: from.x - r, y: from.y - r, width: r * 2, height: r * 2))
    }

    /// Chasing marquee bulbs around the frame. Each bulb glows warm when lit; the chase is what moves fast.
    private func drawBulbs(_ ctx: CGContext, time: Double) {
        let half = (Self.frameSide / 2 + 36) * frameScale
        let side = half * 2, count = 40
        let chase = isOver ? 3.0 : 4 + 5 * tension
        for k in 0..<count {
            let along = Double(k) / Double(count) * side * 4
            let edge = Int(along / side), s = along - Double(edge) * side
            let p: CGPoint
            switch edge {
            case 0: p = CGPoint(x: center.x - half + s, y: center.y + half)
            case 1: p = CGPoint(x: center.x + half, y: center.y + half - s)
            case 2: p = CGPoint(x: center.x + half - s, y: center.y - half)
            default: p = CGPoint(x: center.x - half, y: center.y - half + s)
            }
            let lit = FaceGamePaint.wrap(Double(k) - time * chase, 4) < 2
            if lit, k % 2 == 0, flash > 0.05 {
                FaceGamePaint.spark(ctx, at: p, radius: 30 * frameScale, tone: blinked ? FaceGamePalette.coral : FaceGamePalette.sun, alpha: flash * 2)
            }
            FaceGameArt.stamp(ctx, StaringContestArt.bulb(lit: lit, red: blinked), at: p, height: 40 * frameScale)
        }
    }

    private func drawIntruders(_ ctx: CGContext, time: Double) {
        let span = Self.intruderStart - Self.intruderStop
        let fade = 1 - outro
        guard fade > 0.01 else { return }
        for intruder in intruders {
            let near = 1 - (intruder.distance - Self.intruderStop) / span
            var p = position(of: intruder)
            // They hop in: a bounce with a squash on landing and a stretch on the way up.
            let hop = abs(sin(intruder.age * 5 + intruder.phase))
            p.y += CGFloat(hop * 22)
            let stretch = 1 + 0.16 * (hop - 0.5)
            let height = (78 + 70 * near) * FaceGameEase.backOut(min(1, intruder.age / 0.4), overshoot: 2)
            FaceGameArt.contactShadow(ctx, center: CGPoint(x: p.x, y: p.y - height * 0.42 - hop * 22), width: height * 0.7, height: height * 0.16, alpha: 0.3 * fade)
            FaceGameArt.stamp(ctx, StaringContestArt.goof(intruder.variant), at: p, height: height, rotation: sin(intruder.age * 3 + intruder.phase) * 0.2,
                              stretch: stretch, alpha: fade)
        }
    }

    private func drawSpark(_ p: Particle, _ ctx: CGContext) {
        let tone = FaceGamePaint.hsv(p.hue, 0.55, 1)
        FaceGamePaint.spark(ctx, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 - 0.5 * p.progress), tone: tone, alpha: 1 - p.progress)
    }

    private func drawFrame(_ ctx: CGContext, time: Double) {
        let side = Self.frameSide * frameScale
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        let tone = blinked ? FaceGamePalette.coral : (won ? FaceGamePalette.sun : tensionTone)
        // A neon halo from a few see-through rings that breathe faster as the tension rises: far cheaper than a soft glow this big.
        let breathe = isOver ? 0.5 : 0.5 + 0.5 * sin(time * (3 + 7 * tension))
        for (grow, alpha) in [(60.0, 0.08), (42.0, 0.12), (24.0, 0.18)] {
            FaceGamePaint.stroke(ctx, rounded: rect.insetBy(dx: -(16 + grow) * frameScale, dy: -(16 + grow) * frameScale), radius: (44 + grow) * frameScale,
                                 color: FaceGamePaint.cg(tone, alpha * (0.6 + 0.6 * tension + 0.3 * breathe)), width: 18 * frameScale)
        }
        // The frame: a flat colour with the light and shade laid over it from one kept picture, so its colour can change freely.
        let outer = rect.insetBy(dx: -16 * frameScale, dy: -16 * frameScale)
        let outline = FaceGamePaint.roundedPath(outer, radius: 44 * frameScale)
        ctx.addPath(outline)
        ctx.setLineWidth(8)
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: tone)))
        ctx.strokePath()
        ctx.addPath(outline)
        ctx.setFillColor(FaceGamePaint.cg(tone))
        ctx.fillPath()
        FaceGameArt.stamp(ctx, StaringContestArt.frameGloss, at: center, height: (Self.frameSide + 32) * frameScale)
        FaceGamePaint.drawFace(ctx, crop: crop, in: rect, corner: 30 * frameScale, fallback: blinked ? "😵" : "🙂")
        FaceGamePaint.stroke(ctx, rounded: rect, radius: 30 * frameScale, color: FaceGamePaint.cg(FaceGameArt.edge(of: tone)), width: 3)
        if faceLostFor > 0.1, !isOver {
            FaceGamePaint.fill(ctx, rounded: rect, radius: 30, color: FaceGamePaint.cg(FaceGamePalette.ink, 0.6))
            FaceGamePaint.sticker(ctx, "?", center: center, size: 110)
        }
    }

    private func drawHUD(_ ctx: CGContext, time: Double) {
        let c = center
        // The taunt along the top, between the score and the clock.
        let fade = 1 - FaceGamePaint.smoothstep(tauntLife - 0.35, tauntLife, tauntAge)
        if fade > 0.01 {
            let pop = FaceGameEase.backOut(min(1, tauntAge / 0.3), overshoot: 2.2)
            ctx.setAlpha(CGFloat(fade))
            FaceGamePaint.sticker(ctx, taunt, center: CGPoint(x: size.width / 2, y: size.height - 72), size: 40,
                                  fill: FaceGamePaint.nsColor(FaceGamePaint.mix(FaceGamePalette.cream, FaceGamePalette.bubblegum, tension)), edgeWidth: 12,
                                  rotation: CGFloat(sin(time * 7) * 0.02 * tension), scale: CGFloat(max(0.01, pop)))
            ctx.setAlpha(1)
        }

        // The fake countdown to the right of the frame.
        if let label = fakeCountdown, let age = fakeAge {
            let big = label.count <= 2
            let beat = FaceGamePaint.wrap(age, 0.9) / 0.9
            let pop = big ? FaceGameEase.backOut(min(1, beat / 0.25), overshoot: 2.4) : 1
            FaceGamePaint.sticker(ctx, label, center: CGPoint(x: c.x + 405, y: c.y + 10), size: big ? 150 : 48,
                                  fill: big ? .white : FaceGamePaint.nsColor(FaceGamePalette.coral), edgeWidth: 12,
                                  rotation: CGFloat(sin(time * 9) * 0.06), scale: CGFloat(max(0.01, pop)))
        }

        drawEye(ctx, at: CGPoint(x: c.x - 270, y: c.y), time: time)

        // Progress to the win under the frame. Its colour is also the tension.
        let bar = CGRect(x: c.x - 240, y: c.y - Self.frameSide / 2 - 96, width: 480, height: 24)
        FaceGamePaint.meter(ctx, in: bar, fill: elapsed / Self.winSeconds, from: FaceGamePalette.mint, to: tensionTone)
        for tick in [1.0 / 3, 2.0 / 3] {
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.cream, 0.55))
            ctx.fill(CGRect(x: bar.minX + bar.width * tick - 1.5, y: bar.minY + 4, width: 3, height: bar.height - 8))
        }
        let near = FaceGamePaint.smoothstep(20, 30, elapsed)
        FaceGamePaint.spark(ctx, at: CGPoint(x: bar.maxX + 26, y: bar.midY), radius: 34 + 10 * near * (0.5 + 0.5 * sin(time * 6)), tone: FaceGamePalette.sun, alpha: 0.3 + 0.5 * near)
        FaceGameArt.stamp(ctx, FaceGameArt.starSprite(), at: CGPoint(x: bar.maxX + 26, y: bar.midY), height: 50, rotation: sin(time * 2) * 0.1)
    }

    /// A drawn eye beside the frame whose lids close as yours do, so you can see how near to losing you are.
    private func drawEye(_ ctx: CGContext, at p: CGPoint, time: Double) {
        let closing = FaceGamePaint.clamp01(blinkLevel / 0.9)
        let danger = watch.isOn || closing > 0.45
        let plate = CGRect(x: p.x - 72, y: p.y - 54, width: 144, height: 108)
        GameUIPlate.draw(ctx, plate, radius: 32)
        let eye = CGRect(x: p.x - 50, y: p.y - 30, width: 100, height: 60)
        let almond = CGMutablePath()
        almond.move(to: CGPoint(x: eye.minX, y: eye.midY))
        almond.addQuadCurve(to: CGPoint(x: eye.maxX, y: eye.midY), control: CGPoint(x: eye.midX, y: eye.maxY + 24))
        almond.addQuadCurve(to: CGPoint(x: eye.minX, y: eye.midY), control: CGPoint(x: eye.midX, y: eye.minY - 24))
        almond.closeSubpath()
        ctx.saveGState()
        ctx.addPath(almond)
        ctx.clip()
        ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.cream))
        ctx.fill(eye.insetBy(dx: 0, dy: -20))
        let look = CGPoint(x: p.x + sin(time * 1.3) * 6, y: p.y + cos(time * 1.7) * 3)
        ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.sky * 0.8))
        ctx.fillEllipse(in: CGRect(x: look.x - 19, y: look.y - 19, width: 38, height: 38))
        ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.ink))
        ctx.fillEllipse(in: CGRect(x: look.x - 9, y: look.y - 9, width: 18, height: 18))
        ctx.setFillColor(FaceGamePaint.cg(FaceGamePaint.Tone(1, 1, 1)))
        ctx.fillEllipse(in: CGRect(x: look.x - 9, y: look.y + 3, width: 7, height: 7))
        // The lids come down from above and up from below as your eyes close.
        let lidTone = FaceGamePaint.cg(danger ? FaceGamePalette.coral : FaceGamePalette.grape)
        let drop = (eye.height + 48) / 2 * closing
        ctx.setFillColor(lidTone)
        ctx.fill(CGRect(x: eye.minX, y: eye.maxY + 24 - drop, width: eye.width, height: drop + 2))
        ctx.fill(CGRect(x: eye.minX, y: eye.minY - 24 - 2, width: eye.width, height: drop * 0.45 + 2))
        ctx.restoreGState()
        ctx.addPath(almond)
        ctx.setStrokeColor(FaceGamePaint.cg(danger ? FaceGamePalette.coral : FaceGamePalette.ink))
        ctx.setLineWidth(5)
        ctx.strokePath()
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.ink))
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        // Lashes ride on the edge of the upper lid.
        for k in -2...2 {
            let dx = Double(k) * 18
            let curve = eye.midY + 27 * (1 - (dx / 50) * (dx / 50))
            let base = min(curve, eye.maxY + 24 - drop)
            ctx.move(to: CGPoint(x: p.x + dx, y: base))
            ctx.addLine(to: CGPoint(x: p.x + dx * 1.18, y: base + 12))
        }
        ctx.strokePath()
    }
}
