import AppKit
import CoreGraphics
import simd

/// Air Hockey against the computer. The picture is the table: your goal is the slot at the bottom, the computer's is at the top, and each
/// of your hands is a mallet that can roam your half. Strike the puck into the top slot; keep it out of yours. The puck slides and rebounds
/// with real momentum, so a hand swung through it sends it flying. Three goals against you and the match is over; every goal you score
/// makes the computer a little quicker.
///
/// A mallet glides after its hand at a limited speed, so a tracking jump is a quick slide rather than a teleport that fires the puck off
/// at an impossible speed; a hand that drops out leaves its mallet where it was for a moment, dimmed.
struct HandPlayAirHockey: Game {
    static let title = "Air Hockey"
    static let hint = "Your hands are the mallets. Score in the top goal!"
    static let presenceHint = "Hold up your hand to play"
    static let onboarding = ["Your hands are the mallets", "Score in the goal at the top"]
    static let accent = SIMD3<Double>(1.0, 0.5, 0.48)
    static let icon = GameUIIcon.hand(.open)
    static let startingLives = 3

    /// Ice and neon: a cool rink, a coral player, a violet computer, a gold-trimmed puck.
    enum Colours {
        static let rink = HandPlayPalette.ice
        static let rinkLine = HandPlayPalette.sky
        static let centreLine = HandPlayPalette.coral
        static let player = HandPlayPalette.coral
        static let computer = HandPlayPalette.violet
        static let puck = HandPlayTone(0.16, 0.16, 0.22)
        static let trim = HandPlayPalette.gold
    }

    struct Mallet: Equatable {
        var hand: Int
        var position: SIMD2<Double>
        var previous: SIMD2<Double>
        var velocity = SIMD2<Double>.zero
        var presence = 0.0
        var visible = true
        /// Seconds since its hand was last seen.
        var missing = 0.0
        var flash = 0.0
    }

    enum Scorer: Equatable { case player, computer }

    // Sizes and speeds for a 1280-wide picture; they scale with the width.
    static let puckRadius = 30.0
    static let malletRadius = 54.0
    static let mouthHalfWidth = 190.0
    static let edge = 60.0
    static let topSpeed = 1800.0
    /// The fastest a mallet chases its hand.
    static let malletSpeed = 2600.0
    static let friction = 0.2
    static let faceoffTime = 1.3

    let size: CGSize
    private(set) var puck: SIMD2<Double>
    private(set) var puckVelocity = SIMD2<Double>.zero
    private(set) var puckSpin = 0.0
    private(set) var puckAngle = 0.0
    private(set) var mallets: [Mallet] = []
    private(set) var computer: SIMD2<Double>
    private(set) var computerVelocity = SIMD2<Double>.zero
    private(set) var score = 0
    private(set) var lives = HandPlayAirHockey.startingLives
    private(set) var goalsFor = 0
    private(set) var goalsAgainst = 0
    private(set) var hits = 0
    /// Seconds until the puck is back in play after a goal, or 0 while it is in play.
    private(set) var faceoff = HandPlayAirHockey.faceoffTime
    private(set) var lastScorer: Scorer?
    private(set) var elapsed = 0.0
    private var faceoffSpot: SIMD2<Double>
    private var computerTarget: SIMD2<Double>
    private var planClock = 0.0
    private var lastTouch: Scorer?
    private var bankedSinceTouch = false
    private var stillFor = 0.0
    private var trail: [SIMD2<Double>] = []
    private var roster = HandPlayRoster()
    private var rng: SplitMix64
    private var fx: SplitMix64
    private var particles = ParticleSystem(capacity: 320)
    private var floaters: [HandPlayFloater] = []
    private var rings: [(at: SIMD2<Double>, age: Double)] = []
    private var banner = 0.0
    private var bankShotBanner = false
    private var computerFlash = 0.0

    var isOver: Bool { lives <= 0 }
    var summary: String {
        String(repeating: "❤️", count: max(0, lives)) + String(repeating: "🖤", count: max(0, Self.startingLives - lives))
    }
    private var unit: Double { Double(size.width) / 1280 }

    var readout: GameUIReadout { GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), label: "You \(goalsFor) · CPU \(goalsAgainst)") }

    var result: GameUIResult {
        let won = goalsFor > goalsAgainst
        let line: String
        switch goalsFor {
        case 0: line = "Swing a mallet through the puck to shoot"
        case 1..<4: line = "Bank it off the side walls to beat the keeper"
        default: line = won ? "You out-scored the machine!" : "A real end-to-end game"
        }
        let seconds = Int(elapsed)
        return GameUIResult(headline: won ? "You win!" : "Final buzzer", line: line,
                            stats: [("\(goalsFor) : \(goalsAgainst)", "goals"), ("\(hits)", "hits"), (String(format: "%d:%02d", seconds / 60, seconds % 60), "time")],
                            kind: won ? .won : .lost)
    }

    var left: Double { Self.edge * unit }
    var right: Double { Double(size.width) - Self.edge * unit }
    var bottom: Double { 34 * unit }
    var top: Double { Double(size.height) - 34 * unit }
    var middle: Double { Double(size.height) / 2 }
    var mouth: ClosedRange<Double> { Double(size.width) / 2 - Self.mouthHalfWidth * unit ... Double(size.width) / 2 + Self.mouthHalfWidth * unit }
    private var puckR: Double { Self.puckRadius * unit }
    private var malletR: Double { Self.malletRadius * unit }
    /// How fast the computer's mallet can go: quicker for every goal you score.
    var computerSpeed: Double { min(820, 430 + 60 * Double(goalsFor)) * unit }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        fx = SplitMix64(seed: seed ^ 0x40CC_E1)
        let w = Double(size.width), h = Double(size.height)
        // The first puck starts on your side, so you get the first shot.
        faceoffSpot = SIMD2(w / 2, h / 2 - 150 * w / 1280)
        puck = faceoffSpot
        computer = SIMD2(w / 2, h - 34 * w / 1280 - 130 * w / 1280)
        computerTarget = computer
        particles.gravity = SIMD2(0, -200)
    }

    // MARK: Step

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.25)
        guard !isOver else { return }
        elapsed += dt
        banner = max(0, banner - dt)
        computerFlash = max(0, computerFlash - dt)
        roster.update(world.hands, dt: dt, now: elapsed)
        followHands(dt)
        planComputer(dt)

        if faceoff > 0 {
            faceoff = max(0, faceoff - dt)
            moveComputer(dt)
            if faceoff == 0 {
                puck = faceoffSpot
                puckVelocity = .zero
                trail.removeAll()
                stillFor = 0
            }
        } else {
            simulate(dt)
        }
        effects(dt)

        if isOver {
            particles.removeAll()
            floaters.removeAll()
            rings.removeAll()
            trail.removeAll()
        }
    }

    /// Each hand drives a mallet in your half.
    private mutating func followHands(_ dt: Double) {
        var next: [Mallet] = []
        for entry in roster.entries {
            let target = clampToPlayer(entry.palm.handPlayVector)
            if var mallet = mallets.first(where: { $0.hand == entry.id }) {
                mallet.previous = mallet.position
                if entry.visible {
                    let want = mallet.position + (target - mallet.position) * HandPlayEase.follow(dt, tau: 0.03)
                    let move = want - mallet.position
                    let limit = Self.malletSpeed * unit * dt
                    let length = simd_length(move)
                    mallet.position += length > limit ? move / length * limit : move
                }
                mallet.velocity = dt > 0 ? (mallet.position - mallet.previous) / dt : .zero
                mallet.visible = entry.isHeld
                mallet.missing = entry.missing
                mallet.presence = entry.presence
                mallet.flash = max(0, mallet.flash - dt)
                next.append(mallet)
            } else if entry.visible {
                next.append(Mallet(hand: entry.id, position: target, previous: target, presence: entry.presence))
            }
        }
        mallets = next
    }

    private func clampToPlayer(_ p: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(min(right - malletR, max(left + malletR, p.x)), min(middle - malletR * 0.4, max(bottom + malletR * 0.6, p.y)))
    }

    private func clampToComputer(_ p: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(min(right - malletR, max(left + malletR, p.x)), min(top - malletR * 0.6, max(middle + malletR * 0.4, p.y)))
    }

    /// The computer looks at the puck every tenth of a second: it defends its goal when the puck comes at it, strikes when the puck is
    /// slow on its side, and waits near its goal otherwise.
    private mutating func planComputer(_ dt: Double) {
        planClock -= dt
        guard planClock <= 0 else { return }
        planClock = 0.1
        let guardLine = top - 120 * unit
        let w = Double(size.width)
        let home = SIMD2(w / 2 + (puck.x - w / 2) * 0.35, guardLine)
        guard faceoff <= 0 else { computerTarget = home; return }
        let error = Double.random(in: -1...1, using: &rng) * malletR * max(0.15, 0.6 - 0.08 * Double(goalsFor))
        if puck.y > middle {
            if puckVelocity.y > 260 * unit {
                // Coming at the goal: get in front of it.
                let t = (guardLine - puck.y) / max(puckVelocity.y, 1)
                let x = puck.x + puckVelocity.x * max(0, t)
                computerTarget = clampToComputer(SIMD2(min(mouth.upperBound + malletR, max(mouth.lowerBound - malletR, x + error)), guardLine))
            } else {
                // Get behind the puck, on the line to your goal, and drive through it.
                let goal = SIMD2(w / 2 + error * 2, bottom)
                let line = simd_normalize(goal - puck + SIMD2(0, -1e-6))
                let behind = puck - line * (malletR + puckR + 12 * unit)
                computerTarget = clampToComputer(simd_distance(computer, behind) < 30 * unit ? puck + line * 60 * unit : behind)
            }
        } else {
            computerTarget = clampToComputer(home)
        }
    }

    private mutating func moveComputer(_ dt: Double) {
        let move = computerTarget - computer
        let length = simd_length(move)
        let limit = computerSpeed * dt
        let before = computer
        computer += length > limit ? move / length * limit : move
        computer = clampToComputer(computer)
        computerVelocity = dt > 0 ? (computer - before) / dt : .zero
    }

    private mutating func simulate(_ dt: Double) {
        let fastest = max(simd_length(puckVelocity) * dt, mallets.map { simd_distance($0.position, $0.previous) }.max() ?? 0, computerSpeed * dt)
        let steps = max(1, min(16, Int(ceil(fastest / (puckR * 0.5)))))
        let slice = dt / Double(steps)
        let computerStart = computer
        moveComputer(dt)
        let computerEnd = computer
        for s in 0..<steps {
            let along = Double(s + 1) / Double(steps)
            puck += puckVelocity * slice
            walls()
            for i in mallets.indices where mallets[i].visible {
                let at = mallets[i].previous + (mallets[i].position - mallets[i].previous) * along
                if strike(from: at, velocity: mallets[i].velocity, by: .player) { mallets[i].flash = 0.2 }
            }
            let c = computerStart + (computerEnd - computerStart) * along
            if strike(from: c, velocity: computerVelocity, by: .computer) { computerFlash = 0.2 }
            if checkGoal() { return }
        }
        puckVelocity *= exp(-Self.friction * dt)
        puckAngle += puckSpin * dt
        puckSpin *= exp(-dt * 0.8)
        trail.append(puck)
        if trail.count > 8 { trail.removeFirst() }

        // A puck left sitting where nobody can reach it gets a nudge back toward the middle.
        stillFor = simd_length(puckVelocity) < 20 * unit ? stillFor + dt : 0
        if stillFor > 5 {
            stillFor = 0
            let w = Double(size.width)
            puckVelocity = simd_normalize(SIMD2(w / 2, middle) - puck + SIMD2(0, 1e-6)) * 260 * unit
        }
    }

    private mutating func walls() {
        let r = puckR, e = 0.9
        if puck.x - r < left { puck.x = left + r; puckVelocity.x = abs(puckVelocity.x) * e; bank() }
        if puck.x + r > right { puck.x = right - r; puckVelocity.x = -abs(puckVelocity.x) * e; bank() }
        let inMouth = mouth.contains(puck.x)
        if !inMouth {
            if puck.y - r < bottom { puck.y = bottom + r; puckVelocity.y = abs(puckVelocity.y) * e }
            if puck.y + r > top { puck.y = top - r; puckVelocity.y = -abs(puckVelocity.y) * e }
        }
        // The posts at each side of each goal.
        for post in [SIMD2(mouth.lowerBound, bottom), SIMD2(mouth.upperBound, bottom), SIMD2(mouth.lowerBound, top), SIMD2(mouth.upperBound, top)] {
            let d = puck - post
            let distance = simd_length(d)
            if distance < r, distance > 1e-6 {
                let n = d / distance
                puck = post + n * r
                let closing = simd_dot(puckVelocity, n)
                if closing < 0 { puckVelocity -= 1.8 * closing * n }
            }
        }
        let speed = simd_length(puckVelocity), cap = Self.topSpeed * unit
        if speed > cap { puckVelocity *= cap / speed }
    }

    private mutating func bank() { if lastTouch == .player { bankedSinceTouch = true } }

    /// Whether a mallet at `at` moving at `velocity` struck the puck, and if so, the bounce.
    private mutating func strike(from at: SIMD2<Double>, velocity: SIMD2<Double>, by who: Scorer) -> Bool {
        let reach = malletR + puckR
        let d = puck - at
        let distance = simd_length(d)
        guard distance < reach else { return false }
        let n = distance > 1e-6 ? d / distance : SIMD2(0, who == .player ? 1 : -1)
        puck = at + n * (reach + 0.5)
        let mallet = SIMD2(min(2400 * unit, max(-2400 * unit, velocity.x)), min(2400 * unit, max(-2400 * unit, velocity.y)))
        let relative = puckVelocity - mallet
        let closing = simd_dot(relative, n)
        guard closing < 0 else { return false }
        puckVelocity -= 1.88 * closing * n
        let speed = simd_length(puckVelocity), cap = Self.topSpeed * unit
        if speed > cap { puckVelocity *= cap / speed }
        puckSpin += (n.x * relative.y - n.y * relative.x) / max(puckR, 1) * 0.15
        lastTouch = who
        bankedSinceTouch = false
        stillFor = 0
        let impact = -closing
        if who == .player { hits += 1 }
        if impact > 150 * unit {
            let contact = at + n * malletR
            rings.append((contact, 0))
            let tone = who == .player ? 0.0 : 1.0
            for _ in 0..<Int(min(14, 4 + impact / (120 * unit))) {
                let a = atan2(n.y, n.x) + Double.random(in: -1.2...1.2, using: &fx)
                particles.emit(Particle(position: contact, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 150...420, using: &fx),
                                        life: Double.random(in: 0.2...0.45, using: &fx), size: Double.random(in: 2.5...5.5, using: &fx), hue: tone))
            }
        }
        return true
    }

    private mutating func checkGoal() -> Bool {
        if puck.y < bottom - puckR * 0.6 && mouth.contains(puck.x) {
            goal(by: .computer)
            return true
        }
        if puck.y > top + puckR * 0.6 && mouth.contains(puck.x) {
            goal(by: .player)
            return true
        }
        return false
    }

    private mutating func goal(by who: Scorer) {
        lastScorer = who
        banner = 1.4
        let w = Double(size.width)
        let spot = SIMD2(puck.x, who == .player ? top : bottom)
        switch who {
        case .player:
            goalsFor += 1
            let points = bankedSinceTouch && lastTouch == .player ? 2 : 1
            bankShotBanner = points == 2
            score += points
            floaters.append(HandPlayFloater(text: "+\(points)", origin: spot - SIMD2(0, 90 * unit), tone: HandPlayPalette.gold, size: 56, life: 1.1))
            // The computer gets the next puck.
            faceoffSpot = SIMD2(w / 2, middle + 150 * unit)
        case .computer:
            goalsAgainst += 1
            lives -= 1
            bankShotBanner = false
            faceoffSpot = SIMD2(w / 2, middle - 150 * unit)
        }
        let tones: [Double] = who == .player ? [0, 2, 3] : [1]
        for _ in 0..<40 {
            let a = Double.random(in: 0..<(2 * .pi), using: &fx)
            particles.emit(Particle(position: spot, velocity: SIMD2(cos(a) * 1.2, (who == .player ? -1 : 1) * abs(sin(a)) + 0.2) * Double.random(in: 200...560, using: &fx),
                                    life: Double.random(in: 0.6...1.2, using: &fx), size: Double.random(in: 4...9, using: &fx),
                                    hue: tones[Int.random(in: 0..<tones.count, using: &fx)], kind: 1))
        }
        faceoff = Self.faceoffTime
        puckVelocity = .zero
        lastTouch = nil
        bankedSinceTouch = false
        trail.removeAll()
    }

    private mutating func effects(_ dt: Double) {
        particles.step(dt)
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll(where: \.isDone)
        for i in rings.indices { rings[i].age += dt }
        rings.removeAll { $0.age > 0.35 }
    }

    // MARK: Test hooks

    /// Puts the puck somewhere with a speed, in play at once, as if you (or nobody) had just hit it.
    mutating func place(puck position: SIMD2<Double>, velocity: SIMD2<Double>, touchedByPlayer: Bool = false) {
        puck = position
        puckVelocity = velocity
        faceoff = 0
        lastTouch = touchedByPlayer ? .player : nil
        bankedSinceTouch = false
        trail.removeAll()
    }

    /// Parks the computer's mallet out of the way, or somewhere in particular.
    mutating func place(computerAt position: SIMD2<Double>) {
        computer = position
        computerTarget = position
        planClock = 99
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        drawRink(ctx)
        guard !isOver else { return }
        drawPuck(ctx)
        for mallet in mallets { drawMallet(ctx, at: mallet.position.handPlayPoint, tone: Colours.player, alpha: mallet.presence * (mallet.visible ? 1 : 0.55), flash: mallet.flash) }
        drawMallet(ctx, at: computer.handPlayPoint, tone: Colours.computer, alpha: 1, flash: computerFlash)
        for ring in rings {
            let t = ring.age / 0.35
            HandPlayDraw.ring(ctx, at: ring.at.handPlayPoint, radius: (10 + 60 * HandPlayEase.outCubic(t)) * unit, width: 5 * unit * (1 - t), tone: HandPlayPalette.cream, alpha: 1 - t)
        }
        for p in particles.particles {
            let t = p.progress
            let tone: HandPlayTone
            switch Int(p.hue) {
            case 1: tone = Colours.computer.lighter(0.3)
            case 2: tone = HandPlayPalette.gold
            case 3: tone = HandPlayPalette.mint
            default: tone = p.kind == 1 ? Colours.player : HandPlayPalette.cream
            }
            ctx.fillCircle(center: p.position.handPlayPoint, radius: CGFloat(p.size * unit * (1 - 0.5 * t)), color: tone.cg(1 - t))
        }
        for f in floaters { f.draw(ctx) }
        drawBanners(ctx)
    }

    /// News of a goal, in the shared call-out between the plates, right under the goal it was scored in.
    private func drawBanners(_ ctx: CGContext) {
        guard banner > 0, let who = lastScorer else { return }
        let age = 1.4 - banner
        if who == .player {
            GameScreens.callout(ctx, size: size, text: bankShotBanner ? "BANK SHOT!" : "GOAL!", age: age, tone: GameUIPalette.mint, life: 1.4, textSize: 52)
        } else {
            GameScreens.callout(ctx, size: size, text: "CPU SCORES", age: age, tone: GameUIPalette.coral, life: 1.4, textSize: 40)
        }
    }

    /// The rink: lines only, so you stay in the picture. It never changes, so it is painted once into a picture the size of the frame and
    /// stamped whole.
    private func drawRink(_ ctx: CGContext) {
        let w = size.width, h = size.height
        let geometry = Rink(left: left, right: right, bottom: bottom, top: top, middle: middle, mouthLeft: mouth.lowerBound, mouthRight: mouth.upperBound,
                            unit: unit, width: Double(w))
        let image = HandPlaySprites.image("ah.rink|\(Int(w))x\(Int(h))", width: Int(w), height: Int(h)) { c in
            c.translateBy(x: -w / 2, y: -h / 2)
            Self.paintRink(c, geometry)
        }
        HandPlayDraw.stamp(ctx, image, at: CGPoint(x: w / 2, y: h / 2))
    }

    private struct Rink { var left, right, bottom, top, middle, mouthLeft, mouthRight, unit, width: Double }

    /// A glowing edge with a gap for each goal, a soft dashed centre line with a face-off spot at each end, the creases round the goals, and
    /// the goal slots, dark with glowing posts, each in the colour of who it belongs to.
    private static func paintRink(_ ctx: CGContext, _ g: Rink) {
        let u = g.unit, w = g.width
        let corner = 70 * u
        let a = g.mouthLeft, b = g.mouthRight
        let edge = CGMutablePath()
        edge.move(to: CGPoint(x: b, y: g.bottom))
        edge.addArc(tangent1End: CGPoint(x: g.right, y: g.bottom), tangent2End: CGPoint(x: g.right, y: g.top), radius: CGFloat(corner))
        edge.addArc(tangent1End: CGPoint(x: g.right, y: g.top), tangent2End: CGPoint(x: g.left, y: g.top), radius: CGFloat(corner))
        edge.addLine(to: CGPoint(x: b, y: g.top))
        edge.move(to: CGPoint(x: a, y: g.top))
        edge.addArc(tangent1End: CGPoint(x: g.left, y: g.top), tangent2End: CGPoint(x: g.left, y: g.bottom), radius: CGFloat(corner))
        edge.addArc(tangent1End: CGPoint(x: g.left, y: g.bottom), tangent2End: CGPoint(x: g.right, y: g.bottom), radius: CGFloat(corner))
        edge.addLine(to: CGPoint(x: a, y: g.bottom))
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(edge)
        ctx.setStrokeColor(Colours.rinkLine.cg(0.22))
        ctx.setLineWidth(CGFloat(18 * u))
        ctx.strokePath()
        // A dark edge under the bright line, so the rink reads on a white wall too.
        ctx.addPath(edge)
        ctx.setStrokeColor(HandPlayPalette.ink.cg(0.3))
        ctx.setLineWidth(CGFloat(8.5 * u))
        ctx.strokePath()
        ctx.addPath(edge)
        ctx.setStrokeColor(Colours.rink.cg(0.9))
        ctx.setLineWidth(CGFloat(5 * u))
        ctx.strokePath()

        ctx.setStrokeColor(Colours.centreLine.cg(0.5))
        ctx.setLineWidth(CGFloat(5 * u))
        ctx.setLineDash(phase: 0, lengths: [CGFloat(26 * u), CGFloat(16 * u)])
        ctx.move(to: CGPoint(x: g.left, y: g.middle))
        ctx.addLine(to: CGPoint(x: g.right, y: g.middle))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        for x in [g.left + 150 * u, g.right - 150 * u] {
            ctx.setStrokeColor(Colours.rinkLine.cg(0.55))
            ctx.setLineWidth(CGFloat(4 * u))
            ctx.strokeEllipse(in: CGRect(x: x - 40 * u, y: g.middle - 40 * u, width: 80 * u, height: 80 * u))
            ctx.fillCircle(center: CGPoint(x: x, y: g.middle), radius: CGFloat(7 * u), color: Colours.centreLine.cg(0.7))
        }
        for (y, start, end) in [(g.bottom, 0.0, Double.pi), (g.top, Double.pi, 2 * Double.pi)] {
            ctx.addArc(center: CGPoint(x: w / 2, y: y), radius: CGFloat(150 * u), startAngle: CGFloat(start), endAngle: CGFloat(end), clockwise: false)
            ctx.setStrokeColor(Colours.rinkLine.cg(0.5))
            ctx.strokePath()
        }
        ctx.restoreGState()

        for (y, tone) in [(g.bottom, Colours.player), (g.top, Colours.computer)] {
            let slot = CGRect(x: a, y: y - 9 * u, width: b - a, height: 18 * u)
            HandPlayDraw.glow(ctx, in: slot.insetBy(dx: -30 * u, dy: -26 * u), tone: tone, alpha: 0.45)
            ctx.addPath(CGPath(roundedRect: slot, cornerWidth: 9 * u, cornerHeight: 9 * u, transform: nil))
            ctx.setFillColor(HandPlayPalette.ink.cg(0.7))
            ctx.fillPath()
            for x in [a, b] {
                HandPlayDraw.glow(ctx, at: CGPoint(x: x, y: y), radius: 22 * u, tone: Colours.trim, alpha: 0.8)
                ctx.fillCircle(center: CGPoint(x: x, y: y), radius: CGFloat(8 * u), color: Colours.trim.lighter(0.3).cg())
            }
        }
    }

    private func drawPuck(_ ctx: CGContext) {
        let u = CGFloat(unit)
        if faceoff > 0 {
            // The next puck fades in where it will be served, with a ring counting down.
            let t = 1 - faceoff / Self.faceoffTime
            let p = faceoffSpot.handPlayPoint
            HandPlayDraw.arc(ctx, at: p, radius: puckR * 1.9, width: 5 * unit, fraction: t, tone: HandPlayPalette.cream, alpha: 0.8)
            HandPlayDraw.shadow(ctx, at: CGPoint(x: p.x + 8 * u, y: p.y - 10 * u), width: puckR * 2.6, height: puckR * 1.6, alpha: 0.5 * t)
            HandPlayDraw.stamp(ctx, HandPlayAirHockeyArt.puck(unit: u), at: p, scale: CGFloat(0.6 + 0.4 * HandPlayEase.outBack(t)), alpha: CGFloat(t))
            return
        }
        let speed = simd_length(puckVelocity) / (Self.topSpeed * unit)
        if speed > 0.25 {
            for (i, q) in trail.enumerated() {
                let k = Double(i + 1) / Double(trail.count + 1)
                HandPlayDraw.glow(ctx, at: q.handPlayPoint, radius: puckR * (0.6 + 0.8 * k), tone: Colours.trim, alpha: 0.35 * k * min(1, speed * 1.5))
            }
        }
        let p = puck.handPlayPoint
        HandPlayDraw.shadow(ctx, at: CGPoint(x: p.x + 8 * u, y: p.y - 10 * u), width: puckR * 2.6, height: puckR * 1.6, alpha: 0.5)
        let turned = HandPlayDraw.turned(HandPlayAirHockeyArt.puck(unit: u), key: "ah.puck|\(Int(unit * 100))", angle: puckAngle, steps: 24, period: 2 * .pi / 5)
        HandPlayDraw.stamp(ctx, turned, at: p)
    }

    private func drawMallet(_ ctx: CGContext, at p: CGPoint, tone: HandPlayTone, alpha: Double, flash: Double) {
        guard alpha > 0.01 else { return }
        let u = CGFloat(unit)
        HandPlayDraw.glow(ctx, at: p, radius: malletR * 1.7, tone: tone, alpha: (0.3 + 1.5 * flash) * alpha)
        HandPlayDraw.shadow(ctx, at: CGPoint(x: p.x + 12 * u, y: p.y - 14 * u), width: malletR * 2.5, height: malletR * 1.7, alpha: 0.45 * alpha)
        HandPlayDraw.stamp(ctx, HandPlayAirHockeyArt.mallet(tone, unit: u), at: p, scale: CGFloat(1 + 0.5 * flash), alpha: CGFloat(alpha))
    }
}

/// The baked pictures for Air Hockey.
enum HandPlayAirHockeyArt {
    /// The puck from above: a dark bevelled disc with a gold inlay ring and a small star, lit from the top left.
    static func puck(unit: CGFloat) -> CGImage? {
        let r = CGFloat(HandPlayAirHockey.puckRadius) * unit
        return HandPlaySprites.image("ah.puck|\(Int(unit * 100))", side: Int(ceil(r * 2.3))) { ctx in
            let disc = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
            ctx.saveGState()
            ctx.addEllipse(in: disc)
            ctx.clip()
            HandPlayDraw.fill(ctx, [(HandPlayTone(0.46, 0.47, 0.56), 1), (HandPlayAirHockey.Colours.puck, 1), (HandPlayTone(0.05, 0.05, 0.08), 1)],
                              from: CGPoint(x: -r * 0.7, y: r * 0.7), to: CGPoint(x: r * 0.7, y: -r * 0.7), locations: [0, 0.45, 1])
            // The flat top, a shade lighter than the bevel.
            let face = disc.insetBy(dx: r * 0.16, dy: r * 0.16)
            ctx.addEllipse(in: face)
            ctx.clip()
            HandPlayDraw.radial(ctx, [(HandPlayTone(0.3, 0.31, 0.4), 1), (HandPlayTone(0.14, 0.14, 0.2), 1)], center: .zero, radius: r * 0.9,
                                from: CGPoint(x: -r * 0.3, y: r * 0.3))
            ctx.restoreGState()
            let trim = HandPlayAirHockey.Colours.trim
            ctx.setStrokeColor(trim.cg(0.95))
            ctx.setLineWidth(r * 0.09)
            ctx.strokeEllipse(in: disc.insetBy(dx: r * 0.3, dy: r * 0.3))
            ctx.addPath(HandPlayDraw.starPath(radius: r * 0.3, inner: 0.45))
            ctx.setFillColor(trim.lighter(0.2).cg())
            ctx.fillPath()
            ctx.setStrokeColor(HandPlayPalette.cream.cg(0.6))
            ctx.setLineWidth(r * 0.07)
            ctx.setLineCap(.round)
            ctx.addArc(center: .zero, radius: r * 0.9, startAngle: 1.9, endAngle: 2.8, clockwise: false)
            ctx.strokePath()
            ctx.setStrokeColor(HandPlayPalette.ink.cg(0.8))
            ctx.setLineWidth(r * 0.06)
            ctx.strokeEllipse(in: disc.insetBy(dx: r * 0.03, dy: r * 0.03))
        }
    }

    /// A mallet from above: a wide coloured base with a raised knob, both lit from the top left, with a bright rim.
    static func mallet(_ tone: HandPlayTone, unit: CGFloat) -> CGImage? {
        let r = CGFloat(HandPlayAirHockey.malletRadius) * unit
        return HandPlaySprites.image("ah.mallet|\(tone.key)|\(Int(unit * 100))", side: Int(ceil(r * 2.3))) { ctx in
            let base = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
            ctx.saveGState()
            ctx.addEllipse(in: base)
            ctx.clip()
            HandPlayDraw.fill(ctx, [(tone.lighter(0.4), 1), (tone, 1), (tone.darker(0.45), 1)], from: CGPoint(x: -r * 0.7, y: r * 0.7),
                              to: CGPoint(x: r * 0.7, y: -r * 0.7), locations: [0, 0.45, 1])
            // A groove round the base.
            ctx.setStrokeColor(tone.darker(0.5).cg(0.6))
            ctx.setLineWidth(r * 0.05)
            ctx.strokeEllipse(in: base.insetBy(dx: r * 0.2, dy: r * 0.2))
            ctx.restoreGState()
            // The knob, with its own shadow on the base.
            let knob = base.insetBy(dx: r * 0.42, dy: r * 0.42)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: r * 0.08, height: -r * 0.1), blur: r * 0.14, color: HandPlayPalette.ink.cg(0.55))
            ctx.setFillColor(tone.darker(0.2).cg())
            ctx.fillEllipse(in: knob)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addEllipse(in: knob)
            ctx.clip()
            HandPlayDraw.radial(ctx, [(tone.lighter(0.6), 1), (tone.lighter(0.1), 1), (tone.darker(0.3), 1)], center: CGPoint(x: r * 0.05, y: -r * 0.05),
                                radius: r * 0.62, from: CGPoint(x: -r * 0.18, y: r * 0.2), locations: [0, 0.5, 1])
            ctx.restoreGState()
            ctx.setStrokeColor(HandPlayPalette.cream.cg(0.7))
            ctx.setLineWidth(r * 0.06)
            ctx.setLineCap(.round)
            ctx.addArc(center: .zero, radius: r * 0.9, startAngle: 1.8, endAngle: 2.9, clockwise: false)
            ctx.strokePath()
            ctx.setStrokeColor(HandPlayPalette.ink.cg(0.75))
            ctx.setLineWidth(r * 0.05)
            ctx.strokeEllipse(in: base.insetBy(dx: r * 0.025, dy: r * 0.025))
        }
    }
}
