import AppKit
import CoreGraphics
import simd

/// Rock, Paper, Scissors against the computer. It counts "Rock... Paper... Scissors... SHOOT!", then looks at your hand for a moment:
/// a fist is rock, a flat hand is paper, two fingers are scissors. Win five rounds' worth of fights before it beats you three times.
///
/// The computer's move is chosen when the round starts, from its own random numbers, and never looks at your hand, so it cannot cheat.
/// Your hand is only read after SHOOT, by a vote over the frames of a short window, because tracking flickers.
struct RockPaperScissorsGame: HandGameScreens {
    static let title = "Rock Paper Scissors"
    static let hint = "Pump your fist, then show your hand on SHOOT!"
    static let presenceHint = "Hold up your hand to play"
    static let onboarding = ["Pump your fist on each beat", "Show your move when it says SHOOT"]
    static let accent = SIMD3<Double>(0.45, 0.78, 1.0)
    static let icon = GameUIIcon.hand(.fist)

    /// Rounds that count: a draw, or a hand the camera could not read, is played again.
    static let rounds = 5
    static let maxLosses = 3

    enum Move: Int, CaseIterable {
        case rock, paper, scissors

        var emoji: String {
            switch self {
            case .rock: return "✊"
            case .paper: return "✋"
            case .scissors: return "✌️"
            }
        }

        var name: String {
            switch self {
            case .rock: return "Rock"
            case .paper: return "Paper"
            case .scissors: return "Scissors"
            }
        }

        func beats(_ other: Move) -> Bool {
            (self == .rock && other == .scissors) || (self == .paper && other == .rock) || (self == .scissors && other == .paper)
        }

        /// How the winner wins, for the line under the result.
        func explains(over other: Move) -> String {
            switch (self, other) {
            case (.rock, .scissors): return "Rock crushes scissors"
            case (.paper, .rock): return "Paper covers rock"
            case (.scissors, .paper): return "Scissors cut paper"
            default: return ""
            }
        }
    }

    enum Outcome: Equatable {
        case win, lose, draw
        /// Nothing clear was seen, so nothing counts.
        case unread
    }

    enum Stage: Equatable {
        /// A moment to get your hand up.
        case ready
        /// 0, 1, 2: "Rock", "Paper", "Scissors".
        case beat(Int)
        /// SHOOT: your hand is being read.
        case reading
        case reveal
    }

    // Timings, in seconds.
    static let readyTime = 0.9
    static let beatTime = 0.65
    static let readTime = 0.9
    /// The first moments after SHOOT are ignored: that is still the fist from the countdown, on its way to becoming the answer.
    static let readDelay = 0.12
    static let revealTime = 2.3
    /// Fewer frames than this with a clear gesture and it counts as not seen.
    static let minimumVotes = 5
    /// How much of the vote the winner needs.
    static let majority = 0.55

    let size: CGSize
    private(set) var stage = Stage.ready
    private(set) var stageTime = 0.0
    /// Rounds that were won or lost.
    private(set) var round = 0
    private(set) var wins = 0
    private(set) var losses = 0
    private(set) var draws = 0
    /// Times in a row nothing clear was seen.
    private(set) var unreadStreak = 0
    /// What the computer will play this round. Chosen before you do anything, and not changed by what you do.
    private(set) var pick: Move
    /// What your hand was read as, once SHOOT is over.
    private(set) var yours: Move?
    private(set) var outcome: Outcome?
    private(set) var finished = false
    private var votes = [Double](repeating: 0, count: Move.allCases.count)
    private var voteFrames = 0
    private var pickRNG: SplitMix64
    private var fxRNG: SplitMix64
    private var confetti = ParticleSystem(capacity: 160)

    var score: Int { wins }
    var isOver: Bool { finished }
    var summary: String {
        let hearts = String(repeating: "❤️", count: max(0, Self.maxLosses - losses)) + String(repeating: "🖤", count: min(Self.maxLosses, losses))
        return "Round \(min(round + 1, Self.rounds))/\(Self.rounds) · \(hearts)"
    }

    static func warmUp(_ step: Int) -> Bool {
        if step < 6 { _ = RockPaperScissorsArt.gloveSprite(Move.allCases[step % 3], robot: step >= 3); return true }
        if step == 6 { _ = RockPaperScissorsArt.robotHead(); return true }
        return false
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        // The computer's choices have a stream of their own, so nothing that happens in the game can change what it plays next.
        var picks = SplitMix64(seed: seed)
        pick = Move.allCases[Int.random(in: 0..<Move.allCases.count, using: &picks)]
        pickRNG = picks
        fxRNG = SplitMix64(seed: seed ^ 0x5DEECE66D)
        confetti.gravity = SIMD2(0, -600)
    }

    /// What a hand is showing: nil when it is not clearly any of the three. A thumbs up is still a fist; a pointing finger or a pinch
    /// is none of them. A hand that is half way between poses falls back on how many fingers are out.
    static func gesture(of hand: HandState) -> Move? {
        switch hand.gesturePose {
        case .fist, .thumbsUp, .thumbsDown: return .rock
        case .openPalm: return .paper
        case .peace: return .scissors
        case .point, .fingerGun, .pinch: return nil
        case .okSign, .unknown: break
        }
        switch hand.fingersUp {
        case 0: return .rock
        case 3, 4: return .paper
        case 2: return hand.isExtended(.index) && hand.isExtended(.middle) ? .scissors : nil
        default: return nil
        }
    }

    /// The move the vote leans toward so far during SHOOT, to show the player what the camera sees.
    var leaning: Move? {
        guard stage == .reading, voteFrames > 0 else { return nil }
        return Move.allCases.max { votes[$0.rawValue] < votes[$1.rawValue] }
    }

    var readout: GameUIReadout {
        GameUIReadout(score: wins, lives: (max(0, Self.maxLosses - losses), Self.maxLosses), label: "Round \(min(round + 1, Self.rounds))/\(Self.rounds)")
    }

    var result: GameUIResult {
        let won = wins > losses
        return GameUIResult(headline: won ? "You won the match!" : "The robot wins", line: won ? "Too quick for the machine" : "Best of five again?",
                            stats: [("\(wins)", "won"), ("\(losses)", "lost"), ("\(draws)", "draws")], kind: won ? .won : .lost)
    }

    // MARK: Step

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.5)
        guard !finished else { return }
        stageTime += dt
        confetti.step(dt)

        switch stage {
        case .ready:
            if stageTime >= Self.readyTime { enter(.beat(0)) }
        case .beat(let n):
            if stageTime >= Self.beatTime { enter(n < 2 ? .beat(n + 1) : .reading) }
        case .reading:
            vote(world.hands)
            if stageTime >= Self.readTime {
                resolve()
                enter(.reveal)
            }
        case .reveal:
            let length = outcome == .unread ? Self.revealTime * 0.75 : Self.revealTime
            if stageTime >= length { advance() }
        }
    }

    private mutating func enter(_ next: Stage) {
        stage = next
        stageTime = 0
        if next == .reading {
            votes = [Double](repeating: 0, count: Move.allCases.count)
            voteFrames = 0
            yours = nil
            outcome = nil
        }
    }

    /// One frame's say in the vote. Two hands only count if they agree.
    private mutating func vote(_ hands: [HandState]) {
        guard stageTime >= Self.readDelay else { return }
        let seen = hands.compactMap(Self.gesture(of:))
        guard let first = seen.first, seen.allSatisfy({ $0 == first }) else { return }
        // What the hand is doing at the end of the window matters more than at the start.
        let weight = 1 + min(1, (stageTime - Self.readDelay) / (Self.readTime - Self.readDelay))
        votes[first.rawValue] += weight
        voteFrames += 1
    }

    private mutating func resolve() {
        let total = votes.reduce(0, +)
        let best = Move.allCases.max { votes[$0.rawValue] < votes[$1.rawValue] } ?? .rock
        guard voteFrames >= Self.minimumVotes, total > 0, votes[best.rawValue] >= total * Self.majority else {
            yours = nil
            outcome = .unread
            unreadStreak += 1
            return
        }
        unreadStreak = 0
        yours = best
        if best == pick {
            outcome = .draw
            draws += 1
        } else if best.beats(pick) {
            outcome = .win
            wins += 1
            round += 1
            cheer()
        } else {
            outcome = .lose
            losses += 1
            round += 1
        }
    }

    private mutating func advance() {
        if round >= Self.rounds || losses >= Self.maxLosses {
            finished = true
            return
        }
        pick = Move.allCases[Int.random(in: 0..<Move.allCases.count, using: &pickRNG)]
        enter(.ready)
    }

    private mutating func cheer() {
        for _ in 0..<70 {
            let angle = Double.random(in: 0..<(2 * .pi), using: &fxRNG), speed = Double.random(in: 150...620, using: &fxRNG)
            confetti.emit(Particle(position: SIMD2(size.width / 2, size.height * 0.72), velocity: SIMD2(cos(angle), sin(angle) + 0.6) * speed,
                                   life: Double.random(in: 0.9...1.6, using: &fxRNG), size: Double.random(in: 5...10, using: &fxRNG),
                                   hue: Double.random(in: 0..<1, using: &fxRNG)))
        }
    }

    // MARK: Test hooks

    /// Decides what the computer plays this round.
    mutating func setPick(_ move: Move) { pick = move }

    /// Jumps straight to a stage, as if the countdown had run.
    mutating func begin(_ next: Stage) { enter(next) }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        let w = size.width, h = size.height
        let you = CGPoint(x: w * 0.17, y: h * 0.42), bot = CGPoint(x: w * 0.83, y: h * 0.42)
        let top = CGPoint(x: w / 2, y: h - GameScreens.margin.height - 34)

        switch stage {
        case .ready:
            let enter = HandGameEase.outBack(stageTime / 0.35)
            banner(ctx, "ROUND \(min(round + 1, Self.rounds))", sub: "Get your fist ready", color: HandGamePalette.cream, at: top, scale: enter)
            RockPaperScissorsArt.glove(ctx, .rock, at: you, robot: false, scale: 1, time: time)
            RockPaperScissorsArt.robot(ctx, at: bot, mood: .waiting, move: .rock, scale: 1, time: time)
        case .beat(let n):
            let pop = 1 + 0.18 * max(0, 1 - stageTime / 0.18)
            banner(ctx, Self.words[min(n, 2)] + "…", sub: nil, color: [HandGamePalette.sky, HandGamePalette.berry, HandGamePalette.gold][min(n, 2)], at: top, scale: pop)
            // Both fists pump down on every beat.
            let bob = -sin(min(1, stageTime / Self.beatTime) * .pi) * 40
            RockPaperScissorsArt.glove(ctx, .rock, at: CGPoint(x: you.x, y: you.y + bob), robot: false, scale: 1, time: time)
            RockPaperScissorsArt.robot(ctx, at: bot, mood: .waiting, move: .rock, scale: 1, time: time, bob: bob)
        case .reading:
            let shake = sin(time * 70) * 4 * max(0, 1 - stageTime * 2)
            banner(ctx, "SHOOT!", sub: nil, color: HandGamePalette.coral, at: CGPoint(x: top.x + shake, y: top.y), scale: HandGameEase.outBack(stageTime / 0.2))
            // What the camera is reading, live, so you can see it has your hand.
            if let lean = leaning {
                RockPaperScissorsArt.glove(ctx, lean, at: you, robot: false, scale: 1, time: time)
            } else {
                RockPaperScissorsArt.question(ctx, at: you, time: time)
            }
            RockPaperScissorsArt.robot(ctx, at: bot, mood: .thinking, move: .rock, scale: 1, time: time, hidden: true)
        case .reveal:
            drawReveal(ctx, you: you, bot: bot, top: top, time: time)
        }

        for p in confetti.particles {
            let c = [HandGamePalette.gold, HandGamePalette.mint, HandGamePalette.sky, HandGamePalette.coral, HandGamePalette.berry][Int(p.hue * 5) % 5]
            ctx.saveGState()
            ctx.translateBy(x: p.position.x, y: p.position.y)
            ctx.rotate(by: CGFloat(p.age * 8 + p.hue * 6))
            ctx.setFillColor(CGColor(srgbRed: c.x, green: c.y, blue: c.z, alpha: 1 - p.progress))
            ctx.fill(CGRect(x: -p.size, y: -p.size * 0.45, width: p.size * 2, height: p.size * 0.9))
            ctx.restoreGState()
        }
    }

    private static let words = ["ROCK", "PAPER", "SCISSORS"]

    /// The big word at the top, between the score and status plates, on a plate like theirs, with an optional line under it.
    private func banner(_ ctx: CGContext, _ text: String, sub: String?, color: SIMD3<Double>, at p: CGPoint, scale: Double) {
        let wText = HandGameType.width(text, size: 44)
        let wSub = sub.map { HandGameType.width($0, size: 19, weight: .bold) } ?? 0
        let w = max(wText, wSub) + 64, hgt: CGFloat = sub == nil ? 66 : 92
        let rect = CGRect(x: p.x - w / 2, y: p.y + 33 - hgt, width: w, height: hgt)
        ctx.saveGState()
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.scaleBy(x: CGFloat(max(0.01, scale)), y: CGFloat(max(0.01, scale)))
        ctx.translateBy(x: -rect.midX, y: -rect.midY)
        GameUIPlate.draw(ctx, rect, radius: 28)
        HandGameType.draw(ctx, text, at: CGPoint(x: rect.midX, y: rect.maxY - 33), size: 44, color: HandGamePalette.color(color))
        if let sub { HandGameType.draw(ctx, sub, at: CGPoint(x: rect.midX, y: rect.minY + 22), size: 19, weight: .bold) }
        ctx.restoreGState()
    }

    private func drawReveal(_ ctx: CGContext, you: CGPoint, bot: CGPoint, top: CGPoint, time: Double) {
        let t = stageTime
        // The hands pop in, overshoot a little and settle; the loser's shakes and dims.
        let pop = 1 + 0.3 * exp(-7 * t) * cos(16 * t)
        let enter = HandGameEase.outBack(t / 0.3)
        guard let mine = yours else {
            banner(ctx, "Didn't catch that", sub: "Make a fist, a flat hand or a V", color: HandGamePalette.sky, at: top, scale: enter)
            RockPaperScissorsArt.question(ctx, at: you, time: time)
            RockPaperScissorsArt.robot(ctx, at: bot, mood: .confused, move: pick, scale: 1, time: time, hidden: true)
            return
        }
        let youWon = outcome == .win, youLost = outcome == .lose
        let shake = { (lost: Bool) -> Double in lost ? sin(time * 40) * 0.08 * max(0, 1 - t * 1.5) : 0 }
        if youWon { HandGameArt.halo(ctx, at: you, radius: 150, red: 0.45, green: 1, blue: 0.6, alpha: 0.55) }
        if youLost { HandGameArt.halo(ctx, at: bot, radius: 150, red: 1, green: 0.5, blue: 0.45, alpha: 0.5) }
        RockPaperScissorsArt.glove(ctx, mine, at: you, robot: false, scale: pop * (youWon ? 1.1 : 1), time: time, rotation: shake(youLost), alpha: youLost ? 0.6 : 1)
        RockPaperScissorsArt.robot(ctx, at: bot, mood: youWon ? .sad : youLost ? .happy : .waiting, move: pick, scale: pop * (youLost ? 1.1 : 1),
                                   time: time, rotation: shake(youWon), alpha: youWon ? 0.6 : 1)
        if finished {
            let won = wins > losses
            banner(ctx, won ? "YOU WIN THE MATCH!" : "ROBOT WINS THE MATCH", sub: nil, color: won ? HandGamePalette.gold : HandGamePalette.coral, at: top, scale: enter)
            return
        }
        switch outcome {
        case .win: banner(ctx, "YOU WIN!", sub: mine.explains(over: pick), color: HandGamePalette.mint, at: top, scale: enter)
        case .lose: banner(ctx, "I WIN!", sub: pick.explains(over: mine), color: HandGamePalette.coral, at: top, scale: enter)
        default: banner(ctx, "DRAW!", sub: "Both played \(mine.name.lowercased()). Again!", color: HandGamePalette.gold, at: top, scale: enter)
        }
    }
}

// MARK: - The hands and the robot

/// The look of Rock Paper Scissors: two cartoon gloves (yours in cream with a sky cuff, the robot's in brushed steel with a coral cuff)
/// drawn for each of the three moves, and a robot whose screen face reacts to how the round went.
enum RockPaperScissorsArt {
    enum Mood { case waiting, thinking, happy, sad, confused }

    static func glove(_ ctx: CGContext, _ move: RockPaperScissorsGame.Move, at p: CGPoint, robot: Bool, scale: Double, time: Double,
                      rotation: Double = 0, alpha: CGFloat = 1) {
        guard let sprite = gloveSprite(move, robot: robot) else { return }
        let w = CGFloat(sprite.width), h = CGFloat(sprite.height)
        ctx.saveGState()
        ctx.setAlpha(alpha)
        if abs(scale - 1) < 0.004 && abs(rotation) < 0.002 {
            // At rest it is drawn pixel for pixel, which costs far less than resampling a big sprite every frame.
            let origin = CGPoint(x: (p.x - w / 2).rounded(), y: (p.y - h / 2).rounded())
            ctx.translateBy(x: origin.x + (robot ? 0 : w), y: origin.y)
            if !robot { ctx.scaleBy(x: -1, y: 1) }
            ctx.draw(sprite, in: CGRect(x: 0, y: 0, width: w, height: h))
        } else {
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: CGFloat(rotation))
            // Your hand faces the robot and the robot's faces you: thumbs toward the middle.
            if !robot { ctx.scaleBy(x: -1, y: 1) }
            ctx.draw(sprite, in: CGRect(x: -w * CGFloat(scale) / 2, y: -h * CGFloat(scale) / 2, width: w * CGFloat(scale), height: h * CGFloat(scale)))
        }
        ctx.restoreGState()
        if !robot { HandGameType.draw(ctx, "YOU", at: CGPoint(x: p.x, y: p.y - 150), size: 26, color: HandGamePalette.color(HandGamePalette.sky)) }
    }

    /// A glove baked at the size it is shown (250 pixels tall for yours, a little smaller for the robot's).
    static func gloveSprite(_ move: RockPaperScissorsGame.Move, robot: Bool) -> CGImage? {
        HandGameSprites.image("rps.glove.\(move.rawValue).\(robot)", size: CGSize(width: 240, height: 280), scale: robot ? 0.82 : 0.893) { ctx in
            drawGlove(ctx, move, robot: robot)
        }
    }

    static func robotHead() -> CGImage? {
        HandGameSprites.image("rps.robot", size: CGSize(width: 150, height: 150), scale: 124.0 / 150) { drawRobotHead($0) }
    }

    /// A pulsing question mark where your hand will show, while nothing has been read.
    static func question(_ ctx: CGContext, at p: CGPoint, time: Double) {
        let pulse = 1 + 0.06 * sin(time * 8)
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.setLineWidth(5)
        ctx.setLineDash(phase: CGFloat(time * 30), lengths: [14, 10])
        ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.cream, 0.6))
        ctx.strokeEllipse(in: CGRect(x: -86, y: -86, width: 172, height: 172))
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.restoreGState()
        HandGameType.draw(ctx, "?", at: p, size: 96, color: HandGamePalette.color(HandGamePalette.cream), scale: CGFloat(pulse))
        HandGameType.draw(ctx, "YOU", at: CGPoint(x: p.x, y: p.y - 150), size: 26, color: HandGamePalette.color(HandGamePalette.sky))
    }

    /// The robot: its head above, its gloved hand below. `hidden` keeps its hand behind its back (a question mark on its screen).
    static func robot(_ ctx: CGContext, at p: CGPoint, mood: Mood, move: RockPaperScissorsGame.Move, scale: Double, time: Double, bob: Double = 0,
                      rotation: Double = 0, alpha: CGFloat = 1, hidden: Bool = false) {
        let headAt = CGPoint(x: p.x, y: p.y + 196)
        if let head = robotHead() {
            let tilt = mood == .confused ? 0.15 * sin(time * 3) : mood == .happy ? 0.06 * sin(time * 10) : 0
            ctx.saveGState()
            ctx.translateBy(x: headAt.x, y: (headAt.y + CGFloat(mood == .happy ? abs(sin(time * 9)) * 6 : 0)).rounded())
            ctx.rotate(by: CGFloat(tilt))
            let w = CGFloat(head.width), h = CGFloat(head.height)
            ctx.setAlpha(alpha)
            ctx.draw(head, in: CGRect(x: (-w / 2).rounded(), y: (-h / 2).rounded(), width: w, height: h))
            face(ctx, mood: mood, time: time, alpha: alpha)
            ctx.restoreGState()
        }
        if hidden {
            HandGameType.draw(ctx, "?", at: CGPoint(x: p.x, y: p.y + CGFloat(bob)), size: 80, color: HandGamePalette.color(HandGamePalette.coral, 0.9),
                              scale: CGFloat(1 + 0.05 * sin(time * 10)))
        } else {
            glove(ctx, move, at: CGPoint(x: p.x, y: p.y + CGFloat(bob)), robot: true, scale: scale, time: time, rotation: rotation, alpha: alpha)
        }
    }

    /// The robot's screen face: two eyes and a mouth in glowing dots, drawn live so it can blink and react.
    private static func face(_ ctx: CGContext, mood: Mood, time: Double, alpha: CGFloat) {
        let glow = HandGamePalette.color(mood == .sad ? HandGamePalette.coral : HandGamePalette.mint, Double(alpha))
        ctx.setStrokeColor(glow)
        ctx.setFillColor(glow)
        ctx.setLineCap(.round)
        ctx.setLineWidth(5)
        let blink = (time.truncatingRemainder(dividingBy: 3.1)) < 0.12
        for s in [-1.0, 1.0] {
            let e = CGPoint(x: CGFloat(s) * 20, y: 6)
            switch mood {
            case .happy:
                ctx.addArc(center: CGPoint(x: e.x, y: e.y - 4), radius: 9, startAngle: 0.3, endAngle: .pi - 0.3, clockwise: false)
                ctx.strokePath()
            case .sad:
                ctx.move(to: CGPoint(x: e.x - 8, y: e.y - 6)); ctx.addLine(to: CGPoint(x: e.x + 8, y: e.y + 6))
                ctx.move(to: CGPoint(x: e.x - 8, y: e.y + 6)); ctx.addLine(to: CGPoint(x: e.x + 8, y: e.y - 6))
                ctx.strokePath()
            case .thinking:
                let look = CGFloat(sin(time * 5) * 5)
                ctx.fillEllipse(in: CGRect(x: e.x - 6 + look, y: e.y - 6, width: 12, height: 12))
            default:
                ctx.fillEllipse(in: CGRect(x: e.x - 6, y: e.y - (blink ? 1.5 : 7), width: 12, height: blink ? 3 : 14))
            }
        }
        switch mood {
        case .happy:
            ctx.addArc(center: CGPoint(x: 0, y: -14), radius: 14, startAngle: .pi + 0.4, endAngle: -0.4, clockwise: false)
            ctx.strokePath()
        case .sad:
            ctx.addArc(center: CGPoint(x: 0, y: -26), radius: 12, startAngle: 0.5, endAngle: .pi - 0.5, clockwise: false)
            ctx.strokePath()
        case .confused:
            ctx.move(to: CGPoint(x: -12, y: -18)); ctx.addLine(to: CGPoint(x: -4, y: -14)); ctx.addLine(to: CGPoint(x: 4, y: -20)); ctx.addLine(to: CGPoint(x: 12, y: -15))
            ctx.strokePath()
        default:
            ctx.move(to: CGPoint(x: -10, y: -18)); ctx.addLine(to: CGPoint(x: 10, y: -18))
            ctx.strokePath()
        }
    }

    private static func drawRobotHead(_ ctx: CGContext) {
        let steel = SIMD3<Double>(0.78, 0.8, 0.88)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 2, height: -4), blur: 7, color: HandGamePalette.color(HandGamePalette.ink, 0.45))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        // Antenna with a glowing tip.
        ctx.setStrokeColor(HandGameSprites.shade(steel, 0.6))
        ctx.setLineWidth(4)
        ctx.move(to: CGPoint(x: 0, y: 46)); ctx.addLine(to: CGPoint(x: 0, y: 66))
        ctx.strokePath()
        ctx.setFillColor(HandGamePalette.color(HandGamePalette.coral))
        ctx.fillEllipse(in: CGRect(x: -7, y: 62, width: 14, height: 14))
        // Ears.
        for s in [-1.0, 1.0] {
            let ear = CGPath(roundedRect: CGRect(x: CGFloat(s) * 58 - 8, y: -16, width: 16, height: 32), cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.addPath(ear)
            ctx.setFillColor(HandGameSprites.shade(steel, 0.7))
            ctx.fillPath()
        }
        let head = CGPath(roundedRect: CGRect(x: -54, y: -48, width: 108, height: 96), cornerWidth: 26, cornerHeight: 26, transform: nil)
        ctx.saveGState()
        ctx.addPath(head)
        ctx.clip()
        HandGameSprites.linear(ctx, [HandGameSprites.shade(steel, 1.2), HandGameSprites.shade(steel, 0.92), HandGameSprites.shade(steel, 0.62)], locations: [0, 0.5, 1],
                               from: CGPoint(x: -40, y: 48), to: CGPoint(x: 40, y: -48))
        ctx.restoreGState()
        ctx.addPath(head)
        ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.ink, 0.55))
        ctx.setLineWidth(2)
        ctx.strokePath()
        // The screen.
        let screen = CGPath(roundedRect: CGRect(x: -42, y: -36, width: 84, height: 70), cornerWidth: 16, cornerHeight: 16, transform: nil)
        ctx.addPath(screen)
        ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.1, blue: 0.16, alpha: 1))
        ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(screen)
        ctx.clip()
        HandGameSprites.linear(ctx, [CGColor(gray: 1, alpha: 0.12), CGColor(gray: 1, alpha: 0)], from: CGPoint(x: -30, y: 34), to: CGPoint(x: 0, y: 0))
        ctx.restoreGState()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// A cartoon glove making `move`, thumb on the left (+x is the little finger side), cuff at the bottom.
    private static func drawGlove(_ ctx: CGContext, _ move: RockPaperScissorsGame.Move, robot: Bool) {
        let fill: SIMD3<Double> = robot ? SIMD3(0.8, 0.82, 0.9) : SIMD3(1.0, 0.97, 0.92)
        let line = HandGamePalette.ink
        let cuff: SIMD3<Double> = robot ? HandGamePalette.coral : HandGamePalette.sky
        func lit(_ path: CGPath, _ color: SIMD3<Double>, width: CGFloat = 4) {
            let b = path.boundingBox
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            HandGameSprites.linear(ctx, [HandGameSprites.shade(color, 1.08), HandGameSprites.shade(color, robot ? 0.68 : 0.8)],
                                   from: CGPoint(x: b.minX, y: b.maxY), to: CGPoint(x: b.maxX, y: b.minY))
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(HandGamePalette.color(line, 0.9))
            ctx.setLineWidth(width)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
        func finger(from base: CGPoint, length: CGFloat, width: CGFloat, angle: CGFloat) -> CGPath {
            var t = CGAffineTransform(translationX: base.x, y: base.y).rotated(by: angle)
            return CGPath(roundedRect: CGRect(x: -width / 2, y: -width / 2, width: width, height: length + width / 2), cornerWidth: width / 2,
                          cornerHeight: width / 2, transform: &t)
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 3, height: -6), blur: 9, color: HandGamePalette.color(HandGamePalette.ink, 0.4))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        // Cuff.
        lit(CGPath(roundedRect: CGRect(x: -50, y: -128, width: 100, height: 42), cornerWidth: 14, cornerHeight: 14, transform: nil), cuff)
        ctx.setStrokeColor(HandGameSprites.shade(cuff, 1.3, alpha: 0.7))
        ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: -40, y: -100)); ctx.addLine(to: CGPoint(x: 40, y: -100))
        ctx.strokePath()
        switch move {
        case .paper:
            // Four fingers up and a little spread, the thumb out to the side.
            for (i, len) in [CGFloat(82), 94, 88, 70].enumerated() {
                let x = -33 + CGFloat(i) * 22
                lit(finger(from: CGPoint(x: x, y: 18), length: len, width: 25, angle: CGFloat(Double(i) - 1.5) * -0.09), fill)
            }
            lit(finger(from: CGPoint(x: -44, y: -36), length: 62, width: 27, angle: 0.95), fill)
            lit(CGPath(roundedRect: CGRect(x: -54, y: -92, width: 108, height: 122), cornerWidth: 34, cornerHeight: 34, transform: nil), fill)
            // The lines on the back of the glove.
            ctx.setStrokeColor(HandGamePalette.color(line, 0.35))
            ctx.setLineWidth(3)
            for x in [-16.0, 0, 16] {
                ctx.move(to: CGPoint(x: x, y: -10)); ctx.addLine(to: CGPoint(x: x * 1.1, y: 16))
            }
            ctx.strokePath()
        case .rock:
            lit(CGPath(roundedRect: CGRect(x: -58, y: -92, width: 116, height: 118), cornerWidth: 38, cornerHeight: 38, transform: nil), fill)
            // Four curled fingers seen from the front, knuckles up.
            for i in 0..<4 {
                let x = -46 + CGFloat(i) * 23.5
                lit(CGPath(roundedRect: CGRect(x: x - 1, y: -4, width: 26, height: 44), cornerWidth: 12, cornerHeight: 12, transform: nil), fill, width: 3.5)
            }
            // The thumb folded across the front.
            lit(CGPath(roundedRect: CGRect(x: -58, y: -40, width: 74, height: 28), cornerWidth: 14, cornerHeight: 14, transform: nil), fill, width: 3.5)
        case .scissors:
            lit(finger(from: CGPoint(x: -24, y: 16), length: 92, width: 26, angle: 0.2), fill)
            lit(finger(from: CGPoint(x: 0, y: 18), length: 100, width: 26, angle: -0.2), fill)
            lit(CGPath(roundedRect: CGRect(x: -56, y: -92, width: 112, height: 118), cornerWidth: 36, cornerHeight: 36, transform: nil), fill)
            for i in 0..<2 {
                let x = 6 + CGFloat(i) * 23
                lit(CGPath(roundedRect: CGRect(x: x, y: -6, width: 25, height: 40), cornerWidth: 12, cornerHeight: 12, transform: nil), fill, width: 3.5)
            }
            lit(CGPath(roundedRect: CGRect(x: -56, y: -42, width: 70, height: 27), cornerWidth: 13, cornerHeight: 13, transform: nil), fill, width: 3.5)
        }
        if robot {
            // Rivets on the steel glove.
            ctx.setFillColor(HandGameSprites.shade(fill, 0.55))
            for x in [-30.0, 0, 30] { ctx.fillEllipse(in: CGRect(x: x - 3, y: -78, width: 6, height: 6)) }
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
