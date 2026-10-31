import AppKit
import CoreGraphics
import simd

/// Hand Simon, the memory game, played with hand shapes. The card on the right shows a short run of poses (fist, open hand, peace, point,
/// thumbs up), one after another; then it is your turn to make them in the same order. Get them all and the run grows by one. Hold a
/// wrong shape, or take too long, and you lose a heart and see the run again. Ten rounds to win.
///
/// A pose counts once it has been held for a moment, so passing through other shapes on the way does not matter, and a wrong one only
/// counts when it is held clearly for a full second. The shape you just made is never counted as wrong while you change to the next.
struct HandPlaySimon: Game {
    static let title = "Hand Simon"
    static let hint = "Watch the hand shapes, then copy them in order."
    static let presenceHint = "Hold up your hand to play"
    /// Simon teaches as it goes ("WATCH", "YOUR TURN"), so it needs no opening hints.
    static let onboarding: [String] = []
    static let accent = SIMD3<Double>(0.7, 0.55, 1.0)
    static let icon = GameUIIcon.hand(.peace)
    static let startingLives = 3
    static let rounds = 10
    /// How long the right shape has to be held to count.
    static let holdToMatch = 0.3
    /// How long a wrong shape has to be held to count against you.
    static let holdToMiss = 1.0
    /// How long you have for each shape.
    static let stepTimeout = 7.0

    enum Stage: Equatable {
        /// "ROUND n", before the run is shown.
        case ready
        /// Showing the n-th shape of the run.
        case show(Int)
        /// The blank between two shapes being shown.
        case gap(Int)
        /// Your turn.
        case turn
        case success
        case mistake
        case finished
    }

    let size: CGSize
    private(set) var sequence: [HandPlayPose]
    private(set) var stage = Stage.ready
    private(set) var stageTime = 0.0
    private(set) var round = 1
    private(set) var step = 0
    private(set) var score = 0
    private(set) var lives = HandPlaySimon.startingLives
    private(set) var matched = 0.0
    private(set) var wrong = 0.0
    /// What the hands are showing this frame, as the game reads it.
    private(set) var reading: HandPlayPose?
    private(set) var won = false
    private(set) var tooSlow = false
    private var lingering: HandPlayPose?
    private var roster = HandPlayRoster()
    private var rng: SplitMix64
    private var fx: SplitMix64
    private var elapsed = 0.0
    private var particles = ParticleSystem(capacity: 200)
    private var floaters: [HandPlayFloater] = []
    private var lastAccepted = -9.0

    var isOver: Bool { stage == .finished }
    var summary: String {
        let hearts = String(repeating: "❤️", count: max(0, lives)) + String(repeating: "🖤", count: max(0, Self.startingLives - lives))
        return "Round \(min(round, Self.rounds)) · " + hearts
    }
    private var unit: Double { Double(size.width) / 1280 }

    var readout: GameUIReadout {
        GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), label: "Round \(min(round, Self.rounds))/\(Self.rounds)",
                      tip: round == 1 && stage == .turn ? "Make the shapes in the same order" : nil)
    }

    var result: GameUIResult {
        if won { return GameUIResult(headline: "All ten rounds!", line: "A perfect memory for hands", kind: .won) }
        let cleared = max(0, round - 1)
        return GameUIResult(headline: "Out of hearts", line: round <= 1 ? "Watch the card on the right, then copy it" : "You reached round \(round)",
                            stats: [("\(cleared)", "rounds cleared"), ("\(sequence.count)", "longest run"), ("\(score)", "points")])
    }

    /// How long each shape is shown: quicker as the rounds go on.
    var showTime: Double { HandPlayEase.lerp(1.05, 0.62, Double(round - 1) / Double(Self.rounds - 1)) }
    static let gapTime = 0.24
    /// The shape you are being asked for now.
    var target: HandPlayPose? { stage == .turn && step < sequence.count ? sequence[step] : nil }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        var picks = SplitMix64(seed: seed)
        let first = Self.next(after: nil, using: &picks)
        sequence = [first, Self.next(after: first, using: &picks)]
        rng = picks
        fx = SplitMix64(seed: seed ^ 0x5103_0)
        particles.gravity = SIMD2(0, -500)
    }

    /// A random shape, never the same as the one before it, so every step is a visible change.
    static func next(after previous: HandPlayPose?, using rng: inout SplitMix64) -> HandPlayPose {
        let options = HandPlayPose.allCases.filter { $0 != previous }
        return options[Int.random(in: 0..<options.count, using: &rng)]
    }

    // MARK: Step

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.25)
        guard !isOver else { return }
        elapsed += dt
        stageTime += dt
        roster.update(world.hands, dt: dt, now: elapsed)
        reading = read()
        particles.step(dt)
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll(where: \.isDone)

        switch stage {
        case .ready:
            if stageTime >= 1.1 { enter(.show(0)) }
        case .show(let n):
            if stageTime >= showTime { enter(n + 1 < sequence.count ? .gap(n) : .turn) }
        case .gap(let n):
            if stageTime >= Self.gapTime { enter(.show(n + 1)) }
        case .turn:
            play(dt)
        case .success:
            if stageTime >= 1.3 {
                if round >= Self.rounds {
                    won = true
                    enter(.finished)
                } else {
                    round += 1
                    sequence.append(Self.next(after: sequence.last, using: &rng))
                    enter(.ready)
                }
            }
        case .mistake:
            if stageTime >= 1.9 { enter(lives <= 0 ? .finished : .ready) }
        case .finished:
            break
        }
        if isOver {
            particles.removeAll()
            floaters.removeAll()
        }
    }

    /// What the hands are showing: the asked-for shape if any hand is making it, otherwise whatever the first hand that is clearly making a
    /// shape shows.
    private func read() -> HandPlayPose? {
        let poses = roster.entries.filter(\.visible).compactMap { HandPlayReading.pose(of: $0.hand) }
        if let want = target, poses.contains(want) { return want }
        return poses.first
    }

    private mutating func enter(_ next: Stage) {
        stage = next
        stageTime = 0
        if next == .turn {
            step = 0
            matched = 0
            wrong = 0
            tooSlow = false
            // Whatever the hand is doing as the turn starts is not an answer yet.
            lingering = reading
        }
    }

    private mutating func play(_ dt: Double) {
        guard let want = target else { return }
        if reading != lingering { lingering = nil }
        if reading == want {
            matched += dt
        } else if reading == nil {
            matched = max(0, matched - dt * 0.5)
        } else {
            matched = max(0, matched - dt * 2)
        }
        if let shown = reading, shown != want, shown != lingering {
            wrong += dt
        } else {
            wrong = max(0, wrong - dt)
        }

        if matched >= Self.holdToMatch {
            accept(want)
        } else if wrong >= Self.holdToMiss {
            miss(slow: false)
        } else if stageTime >= Self.stepTimeout {
            miss(slow: true)
        }
    }

    private mutating func accept(_ pose: HandPlayPose) {
        score += 1
        step += 1
        lastAccepted = elapsed
        lingering = pose
        matched = 0
        wrong = 0
        stageTime = 0
        let at = tileCenter(step - 1, of: sequence.count).handPlayVector
        for _ in 0..<12 {
            let a = Double.random(in: 0..<(2 * .pi), using: &fx)
            particles.emit(Particle(position: at, velocity: SIMD2(cos(a), sin(a) + 0.5) * Double.random(in: 120...320, using: &fx),
                                    life: Double.random(in: 0.35...0.7, using: &fx), size: Double.random(in: 3...6, using: &fx), hue: Double(pose.rawValue)))
        }
        if step >= sequence.count {
            score += 2
            floaters.append(HandPlayFloater(text: "+\(sequence.count + 2)", origin: SIMD2(Double(size.width) / 2, 150 * unit), tone: HandPlayPalette.gold, size: 48))
            enter(.success)
        }
    }

    private mutating func miss(slow: Bool) {
        lives -= 1
        tooSlow = slow
        enter(.mistake)
    }

    // MARK: Test hooks

    mutating func setSequence(_ poses: [HandPlayPose]) { sequence = poses }

    /// Jumps straight to a stage.
    mutating func begin(_ next: Stage) { enter(next) }

    // MARK: Layout

    /// Where the card that shows the shapes sits.
    var cardCenter: CGPoint { CGPoint(x: size.width * 0.845, y: size.height * 0.5) }

    /// Where tile `index` of a run of `count` sits, in the strip along the bottom, just above the band the shared hints use.
    func tileCenter(_ index: Int, of count: Int) -> CGPoint {
        let pitch = 64 * unit
        let x = Double(size.width) / 2 + (Double(index) - Double(count - 1) / 2) * pitch
        return CGPoint(x: x, y: 138 * unit)
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        guard !isOver else { return }
        drawCard(ctx)
        drawStrip(ctx)
        drawHands(ctx)
        for p in particles.particles {
            let t = p.progress
            let tone = HandPlayPose(rawValue: Int(p.hue))?.tone ?? HandPlayPalette.gold
            HandPlayDraw.glint(ctx, at: p.position.handPlayPoint, radius: p.size * 1.8 * unit * (1 - 0.5 * t), alpha: 1 - t, tone: tone.lighter(0.4))
        }
        for f in floaters { f.draw(ctx) }
        drawBanner(ctx)
    }

    /// What is happening now, between the plates at the top: news springs in as a call-out, a standing state sits on a small plate.
    private func drawBanner(_ ctx: CGContext) {
        switch stage {
        case .ready:
            GameScreens.callout(ctx, size: size, text: round == Self.rounds ? "LAST ROUND" : "ROUND \(round)", age: stageTime, tone: GameUIPalette.violet,
                                life: 1.6)
        case .show, .gap:
            GameScreens.prompt(ctx, size: size, text: "WATCH")
        case .turn:
            if step == 0 && stageTime < 1.4 {
                GameScreens.callout(ctx, size: size, text: "YOUR TURN", age: stageTime, tone: GameUIPalette.mint, life: 1.4)
            } else {
                GameScreens.prompt(ctx, size: size, text: "\(step + 1) OF \(sequence.count)", tone: GameUIPalette.mint)
            }
        case .success:
            GameScreens.callout(ctx, size: size, text: round == Self.rounds ? "YOU DID IT!" : "NICE!", age: stageTime, tone: GameUIPalette.gold, life: 2)
        case .mistake:
            GameScreens.callout(ctx, size: size, text: tooSlow ? "TOO SLOW" : "OOPS!", age: stageTime, tone: GameUIPalette.coral, life: 2)
        case .finished:
            break
        }
    }

    /// The card on the right: a shape and its name while the run is shown, a question mark on your turn, and the shape you missed after a
    /// mistake.
    private func drawCard(_ ctx: CGContext) {
        let u = CGFloat(unit)
        let c = cardCenter
        var pose: HandPlayPose?
        var flip = 1.0
        switch stage {
        case .show(let n):
            pose = sequence[n]
            flip = HandPlayEase.outBack(stageTime / 0.22, overshoot: 1.6)
        case .mistake:
            pose = step < sequence.count ? sequence[step] : nil
            flip = HandPlayEase.outBack(stageTime / 0.25)
        case .gap:
            flip = HandPlayEase.clamp(stageTime / Self.gapTime)
        default:
            break
        }
        let scaleX = CGFloat(max(0.02, abs(flip)))
        if let pose {
            let tone = stage == .mistake ? HandPlayPalette.coral : pose.tone
            HandPlayDraw.glow(ctx, at: c, radius: 190 * unit, tone: tone, alpha: 0.35 * Double(scaleX))
            HandPlayDraw.stamp(ctx, HandPlaySimonArt.card(tone, unit: u), at: c, sx: scaleX)
            HandPlayDraw.stamp(ctx, HandPlayGlove.image(pose, height: 150 * u), at: CGPoint(x: c.x, y: c.y + 22 * u), sx: scaleX)
            HandPlayText.draw(ctx, pose.name, at: CGPoint(x: c.x, y: c.y - 92 * u), size: 26 * u, color: HandPlayPalette.cream, scale: scaleX)
            if stage == .mistake {
                HandPlayText.draw(ctx, "IT WAS", at: CGPoint(x: c.x, y: c.y + 152 * u), size: 26 * u, color: HandPlayPalette.cream)
            }
        } else {
            HandPlayDraw.stamp(ctx, HandPlaySimonArt.cardBack(unit: u), at: c, sx: scaleX)
            if stage == .turn {
                HandPlayText.draw(ctx, "YOUR TURN", at: CGPoint(x: c.x, y: c.y - 92 * u), size: 24 * u, color: HandPlayPalette.mint)
            }
        }
    }

    /// The run, as a strip of tiles along the bottom: face up while it is shown, face down on your turn until you match each one.
    private func drawStrip(_ ctx: CGContext) {
        let u = CGFloat(unit)
        let count = sequence.count
        for i in 0..<count {
            let p = tileCenter(i, of: count)
            var faceUp = false, current = false, missed = false
            switch stage {
            case .show(let n): faceUp = i <= n; current = i == n
            case .gap(let n): faceUp = i <= n
            case .turn: faceUp = i < step; current = i == step
            case .success, .finished: faceUp = true
            case .mistake: faceUp = i <= step; missed = i == step
            case .ready: faceUp = false
            }
            let lift = current ? 10 * u : 0
            let at = CGPoint(x: p.x, y: p.y + lift)
            // The current tile is baked a size up rather than scaled, so it is still a plain stamp.
            let tileUnit = current ? u * 1.12 : u
            if faceUp {
                let tone = missed ? HandPlayPalette.coral : sequence[i].tone
                HandPlayDraw.stamp(ctx, HandPlaySimonArt.tile(tone, unit: tileUnit), at: at)
                HandPlayDraw.stamp(ctx, HandPlayGlove.image(sequence[i], height: 42 * tileUnit), at: at)
            } else {
                HandPlayDraw.stamp(ctx, HandPlaySimonArt.tileBack(unit: tileUnit), at: at)
            }
            if current && stage == .turn {
                let pulse = 0.6 + 0.4 * sin(elapsed * 6)
                HandPlayDraw.ring(ctx, at: at, radius: 36 * unit, width: 4 * unit, tone: HandPlayPalette.gold, alpha: pulse)
            }
            if stage == .turn && i < step && elapsed - lastAccepted < 0.5 && i == step - 1 {
                let t = (elapsed - lastAccepted) / 0.5
                HandPlayDraw.ring(ctx, at: at, radius: (30 + 40 * HandPlayEase.outCubic(t)) * unit, width: 6 * unit * (1 - t), tone: HandPlayPalette.gold, alpha: 1 - t)
            }
        }
    }

    /// Round each hand: a ring, a badge with the shape the camera sees, and on your turn an arc that fills while you hold the right one.
    private func drawHands(_ ctx: CGContext) {
        let u = unit
        for entry in roster.entries where entry.presence > 0.01 {
            let p = entry.palm
            let r = min(180, max(70, entry.size * 1.05)) * u
            let seen = entry.isHeld ? HandPlayReading.pose(of: entry.hand) : nil
            let isTarget = seen != nil && seen == target
            let shaking = stage == .turn && wrong > 0.35 && seen != nil && !isTarget
            let tone = isTarget ? HandPlayPalette.mint : shaking ? HandPlayPalette.coral : HandPlayPalette.cream
            HandPlayDraw.ring(ctx, at: p, radius: r, width: 4 * u, tone: tone, alpha: 0.7 * entry.presence, outlined: true)
            if stage == .turn && isTarget {
                HandPlayDraw.arc(ctx, at: p, radius: r, width: 9 * u, fraction: matched / Self.holdToMatch, tone: HandPlayPalette.mint, alpha: entry.presence)
            }
            if stage == .turn && shaking {
                HandPlayDraw.arc(ctx, at: p, radius: r + 12 * u, width: 6 * u, fraction: wrong / Self.holdToMiss, tone: HandPlayPalette.coral, alpha: 0.8 * entry.presence)
            }
            if let seen {
                let shake = shaking ? sin(elapsed * 40) * 5 * u : 0
                let badge = CGPoint(x: p.x + r * 0.8 + shake, y: p.y + r * 0.8)
                HandPlayDraw.stamp(ctx, HandPlaySimonArt.badge(unit: CGFloat(u)), at: badge, alpha: CGFloat(entry.presence))
                HandPlayDraw.stamp(ctx, HandPlayGlove.image(seen, height: CGFloat(46 * u)), at: badge, alpha: CGFloat(entry.presence))
            }
        }
    }
}

/// The baked pictures for Hand Simon: cards, tiles and the badge by the hand.
enum HandPlaySimonArt {
    /// A rounded card in a pose's colour, lit from the top left, with an inner frame.
    static func card(_ tone: HandPlayTone, unit: CGFloat) -> CGImage? {
        let w = 210 * unit, h = 260 * unit
        return HandPlaySprites.image("sm.card|\(tone.key)|\(Int(unit * 100))", width: Int(ceil(w * 1.25)), height: Int(ceil(h * 1.2))) { ctx in
            panel(ctx, width: w, height: h, top: tone.lighter(0.22), bottom: tone.darker(0.3), frame: HandPlayPalette.cream.cg(0.5))
        }
    }

    /// The back of the card: deep violet with a soft star pattern and a big question mark.
    static func cardBack(unit: CGFloat) -> CGImage? {
        let w = 210 * unit, h = 260 * unit
        return HandPlaySprites.image("sm.back|\(Int(unit * 100))", width: Int(ceil(w * 1.25)), height: Int(ceil(h * 1.2))) { ctx in
            panel(ctx, width: w, height: h, top: HandPlayPalette.dusk.lighter(0.12), bottom: HandPlayPalette.ink, frame: HandPlayPalette.violet.cg(0.7))
            for (x, y, s) in [(-0.3, 0.32, 0.07), (0.32, 0.22, 0.05), (-0.22, -0.3, 0.05), (0.28, -0.34, 0.07), (0.0, 0.4, 0.04)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.addPath(HandPlayDraw.starPath(center: CGPoint(x: x * w, y: y * h), radius: s * w))
                ctx.setFillColor(HandPlayPalette.violet.cg(0.55))
                ctx.fillPath()
            }
            if let mark = HandPlayText.image("?", size: 120 * unit, color: HandPlayPalette.cream) {
                let mw = CGFloat(mark.width), mh = CGFloat(mark.height)
                ctx.draw(mark, in: CGRect(x: -mw / 2, y: -mh / 2 + 18 * unit, width: mw, height: mh))
            }
        }
    }

    private static func panel(_ ctx: CGContext, width w: CGFloat, height h: CGFloat, top: HandPlayTone, bottom: HandPlayTone, frame: CGColor) {
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let shape = CGPath(roundedRect: rect, cornerWidth: w * 0.12, cornerHeight: w * 0.12, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: w * 0.02, height: -w * 0.04), blur: w * 0.1, color: HandPlayPalette.ink.cg(0.55))
        ctx.addPath(shape)
        ctx.setFillColor(bottom.cg())
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        HandPlayDraw.fill(ctx, [(top, 1), (bottom, 1)], from: CGPoint(x: -w * 0.3, y: h / 2), to: CGPoint(x: w * 0.3, y: -h / 2))
        HandPlayDraw.radial(ctx, [(HandPlayPalette.cream, 0.28), (HandPlayPalette.cream, 0)], center: CGPoint(x: -w * 0.3, y: h * 0.35), radius: w * 0.6)
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: w * 0.06, dy: w * 0.06), cornerWidth: w * 0.08, cornerHeight: w * 0.08, transform: nil))
        ctx.setStrokeColor(frame)
        ctx.setLineWidth(max(1.5, w * 0.012))
        ctx.strokePath()
        ctx.addPath(shape)
        ctx.setStrokeColor(HandPlayPalette.ink.cg(0.6))
        ctx.setLineWidth(max(1.5, w * 0.015))
        ctx.strokePath()
    }

    /// A small tile in the strip, face up, in a pose's colour.
    static func tile(_ tone: HandPlayTone, unit: CGFloat) -> CGImage? {
        let s = 54 * unit
        return HandPlaySprites.image("sm.tile|\(tone.key)|\(Int(unit * 100))", side: Int(ceil(s * 1.4))) { ctx in
            tileShape(ctx, side: s, top: tone.lighter(0.15), bottom: tone.darker(0.3))
        }
    }

    /// A tile face down.
    static func tileBack(unit: CGFloat) -> CGImage? {
        let s = 54 * unit
        return HandPlaySprites.image("sm.tileback|\(Int(unit * 100))", side: Int(ceil(s * 1.4))) { ctx in
            tileShape(ctx, side: s, top: HandPlayPalette.dusk.lighter(0.1), bottom: HandPlayPalette.ink)
            if let mark = HandPlayText.image("?", size: 30 * unit, color: HandPlayPalette.violet.lighter(0.4), outline: 0.4) {
                let mw = CGFloat(mark.width), mh = CGFloat(mark.height)
                ctx.draw(mark, in: CGRect(x: -mw / 2, y: -mh / 2, width: mw, height: mh))
            }
        }
    }

    private static func tileShape(_ ctx: CGContext, side s: CGFloat, top: HandPlayTone, bottom: HandPlayTone) {
        let rect = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
        let shape = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: s * 0.03, height: -s * 0.06), blur: s * 0.12, color: HandPlayPalette.ink.cg(0.5))
        ctx.addPath(shape)
        ctx.setFillColor(bottom.cg())
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        HandPlayDraw.fill(ctx, [(top, 1), (bottom, 1)], from: CGPoint(x: 0, y: s / 2), to: CGPoint(x: 0, y: -s / 2))
        ctx.restoreGState()
        ctx.addPath(shape)
        ctx.setStrokeColor(HandPlayPalette.ink.cg(0.6))
        ctx.setLineWidth(max(1.2, s * 0.03))
        ctx.strokePath()
    }

    /// The round badge by a hand that shows the shape the camera sees.
    static func badge(unit: CGFloat) -> CGImage? {
        let r = 34 * unit
        return HandPlaySprites.image("sm.badge|\(Int(unit * 100))", side: Int(ceil(r * 2.6))) { ctx in
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: r * 0.05, height: -r * 0.1), blur: r * 0.25, color: HandPlayPalette.ink.cg(0.5))
            ctx.fillCircle(center: .zero, radius: r, color: HandPlayPalette.ink.cg(0.72))
            ctx.restoreGState()
            ctx.setStrokeColor(HandPlayPalette.cream.cg(0.35))
            ctx.setLineWidth(max(1.5, r * 0.06))
            ctx.strokeEllipse(in: CGRect(x: -r + r * 0.03, y: -r + r * 0.03, width: r * 1.94, height: r * 1.94))
        }
    }
}
