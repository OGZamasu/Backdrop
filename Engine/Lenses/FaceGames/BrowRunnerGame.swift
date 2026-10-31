import AppKit
import CoreGraphics
import simd

/// An endless runner you play with your eyebrows. Your face is the runner's head; cacti, crates and puddles scroll in faster and
/// faster. Raise your eyebrows to jump, keep them up to jump higher, let them go to drop. Crates can be landed on.
///
/// The score is the distance run, in metres. Hitting anything ends the run.
struct BrowRunnerGame: FaceGame {
    static let title = "Brow Runner"
    static let hint = "Raise your eyebrows to jump. Keep them up to jump higher."
    static let presenceHint = "Look into the camera to play"
    static let wantsFaceCrop = true
    static let move = FaceGameMove.raiseBrows
    static let accent = FaceGamePalette.sky
    static let scoreLabel = "METRES"

    // The track.
    static let groundY = 120.0
    static let playerX = 300.0
    static let pixelsPerMeter = 50.0
    /// One full day and night.
    static let cycleMeters = 400.0
    static let baseSpeed = 320.0
    static let topSpeed = 760.0

    // The jump. Held brows fall slowly on the way up; let go and gravity pulls harder, so a tap is a hop and a hold is a leap.
    static let jumpSpeed = 880.0
    static let gravityHeld = 1800.0
    static let gravityTap = 4200.0
    static let gravityFall = 2900.0
    /// A jump still works this long after running off the edge of something.
    static let coyoteTime = 0.10
    /// A brow raised this long before landing still makes the jump when you land.
    static let bufferTime = 0.14
    /// Brows count as up from here, and only as down again below `browOff` for `browGrace` seconds.
    static let browOn = 0.58
    static let browOff = 0.30
    static let browGrace = 0.07

    static let bodyHalfWidth = 14.0
    /// A crate's top corner within this far above your feet is climbed rather than hit.
    static let ledgeReach = 44.0
    static let crateSize = 72.0

    enum Kind: Equatable { case cactus, crate, puddle }

    struct Obstacle: Equatable {
        var kind: Kind
        /// Left edge.
        var x: Double
        var width: Double
        var height: Double
        var variant: Int
    }

    let size: CGSize
    private(set) var obstacles: [Obstacle] = []
    private(set) var distance = 0.0
    /// How far above the ground the feet are.
    private(set) var height = 0.0
    private(set) var vy = 0.0
    private(set) var grounded = true
    private(set) var crashed = false
    /// How many jumps have been made.
    private(set) var jumps = 0
    private(set) var elapsed = 0.0
    private(set) var brow = 0.0

    private var jumpSwitch = FaceGameTrigger(on: BrowRunnerGame.browOn, off: BrowRunnerGame.browOff, offDelay: BrowRunnerGame.browGrace)
    private var coyote = 0.0
    private var jumpBuffer = 0.0
    private var untilNext = 0.0
    private var lastMilestone = 0
    private var crop: CGImage?
    private var rng: SplitMix64
    private var dust = ParticleSystem(capacity: 240)
    private var floaters: [FaceGameFloater] = []

    var score: Int { Int(distance / Self.pixelsPerMeter) }
    var isOver: Bool { crashed }
    var speed: Double { min(Self.topSpeed, Self.baseSpeed + 1.1 * distance / Self.pixelsPerMeter) }
    var summary: String { "Speed x" + String(format: "%.1f", speed / Self.baseSpeed) }
    /// Whether the eyebrows are being held up right now.
    var browsUp: Bool { jumpSwitch.isOn }

    var chips: [FaceGameChip] { [.text("SPEED ×" + String(format: "%.1f", speed / Self.baseSpeed))] }
    var ending: FaceGameEnding { .lost("CRASH!") }
    var endLine: String { score == 1 ? "You ran 1 metre" : "You ran \(score) metres" }
    var tip: String? {
        if elapsed < 3.5 { return "Raise your eyebrows to jump!" }
        if jumps == 0, elapsed < 8 { return "Lift your eyebrows high!" }
        return nil
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        dust.gravity = SIMD2(0, -500)
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.1)
        if let crop = world.faceCrop { self.crop = crop }
        guard !crashed else { return }
        // With no eyebrows to read the world holds still, rather than running you into a cactus you can't jump.
        guard let face = world.face else { return }

        elapsed += dt
        brow = face.browRaise
        jumpSwitch.update(face.browRaise, dt: dt)
        if jumpSwitch.justTurnedOn { jumpBuffer = Self.bufferTime }

        var left = dt
        while left > 1e-9, !crashed {
            let h = min(left, 1.0 / 120)
            advance(h)
            left -= h
        }
        dust.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)

        let mark = score / 100
        if mark > lastMilestone, !crashed {
            lastMilestone = mark
            floaters.append(FaceGameFloater(text: "\(mark * 100) m!", position: SIMD2(size.width / 2, size.height - 140),
                                            tone: FaceGamePaint.Tone(1, 0.9, 0.3), size: 70, life: 1.3, rise: 40))
            for _ in 0..<40 { emitConfetti() }
        }
    }

    private mutating func advance(_ h: Double) {
        let run = speed
        distance += run * h
        for i in obstacles.indices { obstacles[i].x -= run * h }
        obstacles.removeAll { $0.x + $0.width < -150 }
        untilNext -= run * h
        if untilNext <= 0 { spawnNext() }

        if grounded { coyote = Self.coyoteTime } else { coyote = max(0, coyote - h) }
        jumpBuffer = max(0, jumpBuffer - h)
        if jumpBuffer > 0, coyote > 0 { takeOff() }

        let before = height
        let wasGrounded = grounded
        let gravity = vy > 0 ? (jumpSwitch.isOn ? Self.gravityHeld : Self.gravityTap) : Self.gravityFall
        vy -= gravity * h
        height += vy * h

        let floor = supportHeight(from: before)
        if height <= floor, vy <= 0 {
            if !wasGrounded, vy < -350 { puff(count: 8) }
            height = floor
            vy = 0
            grounded = true
        } else {
            grounded = false
        }
        checkHits()
    }

    private mutating func takeOff() {
        vy = Self.jumpSpeed
        grounded = false
        coyote = 0
        jumpBuffer = 0
        jumps += 1
        puff(count: 7)
    }

    /// The height of whatever the feet are standing on: the ground, or the top of a crate they have come down onto.
    private func supportHeight(from previous: Double) -> Double {
        var floor = 0.0
        for o in obstacles where o.kind == .crate {
            guard Self.playerX + 12 > o.x + 2, Self.playerX - 12 < o.x + o.width - 2 else { continue }
            // Within a hand's breadth of the top counts as on it, so a hop that just misses still gets up.
            if previous >= o.height - 14 { floor = max(floor, o.height) }
        }
        return floor
    }

    private mutating func checkHits() {
        let left = Self.playerX - Self.bodyHalfWidth, right = Self.playerX + Self.bodyHalfWidth
        for o in obstacles {
            let feet = height
            let hit: Bool
            switch o.kind {
            case .cactus:
                hit = right > o.x + 6 && left < o.x + o.width - 6 && feet + 8 < o.height - 6
            case .crate:
                let touching = right > o.x + 3 && left < o.x + o.width - 3
                // Catching the top corner of a crate with your feet isn't a crash: you scramble up onto it.
                if touching, feet >= o.height - Self.ledgeReach, feet < o.height - 8 {
                    height = o.height
                    vy = 0
                    grounded = true
                    puff(count: 5)
                    continue
                }
                hit = touching && feet < o.height - 8
            case .puddle:
                hit = right > o.x + 12 && left < o.x + o.width - 12 && feet < 16
            }
            if hit { crash(into: o); return }
        }
    }

    private mutating func crash(into o: Obstacle) {
        crashed = true
        let tone: Double = o.kind == .puddle ? 0.55 : 0.1
        for _ in 0..<36 {
            let a = Double.random(in: 0.2...2.9, using: &rng), v = Double.random(in: 150...520, using: &rng)
            dust.emit(Particle(position: SIMD2(Self.playerX + 20, Self.groundY + height + 40), velocity: SIMD2(cos(a), sin(a)) * v,
                               life: Double.random(in: 0.5...1.0, using: &rng), size: Double.random(in: 6...14, using: &rng), hue: tone, kind: 1))
        }
    }

    private mutating func puff(count: Int) {
        for _ in 0..<count {
            dust.emit(Particle(position: SIMD2(Self.playerX + Double.random(in: -14...14, using: &rng), Self.groundY + height + 4),
                               velocity: SIMD2(Double.random(in: -220...(-40), using: &rng), Double.random(in: 20...140, using: &rng)),
                               life: Double.random(in: 0.25...0.55, using: &rng), size: Double.random(in: 8...16, using: &rng), hue: 0.1))
        }
    }

    private mutating func emitConfetti() {
        let a = Double.random(in: 0..<(2 * .pi), using: &rng), v = Double.random(in: 200...560, using: &rng)
        dust.emit(Particle(position: SIMD2(size.width / 2, size.height - 140), velocity: SIMD2(cos(a), sin(a)) * v,
                           life: Double.random(in: 0.8...1.5, using: &rng), size: Double.random(in: 6...12, using: &rng),
                           hue: Double.random(in: 0..<1, using: &rng), kind: 2))
    }

    // MARK: Obstacles

    private enum Template { case cactus, cactusPair, cactusTrio, crate, crateRow, crateStack, puddle, longPuddle }

    private mutating func spawnNext() {
        let meters = distance / Self.pixelsPerMeter
        let table: [(Template, Double, Double)] = [(.cactus, 3, 0), (.puddle, 2, 0), (.cactusPair, 2, 60), (.crate, 2, 40), (.crateRow, 1.5, 90),
                                                   (.crateStack, 1.5, 110), (.longPuddle, 1, 120), (.cactusTrio, 1.5, 150)]
        let open = table.filter { meters >= $0.2 }
        var roll = Double.random(in: 0..<open.reduce(0) { $0 + $1.1 }, using: &rng)
        var pick = open[0].0
        for entry in open {
            roll -= entry.1
            if roll < 0 { pick = entry.0; break }
        }

        let tall = Double.random(in: 54...80, using: &rng)
        let crate = Self.crateSize
        let made: Obstacle
        var hard = false
        switch pick {
        case .cactus: made = Obstacle(kind: .cactus, x: 0, width: 46, height: tall, variant: Int.random(in: 0..<4, using: &rng))
        case .cactusPair: made = Obstacle(kind: .cactus, x: 0, width: 118, height: min(tall, 80), variant: 10 + Int.random(in: 0..<4, using: &rng))
        case .cactusTrio: made = Obstacle(kind: .cactus, x: 0, width: 190, height: max(66, min(tall + 4, 84)), variant: 20 + Int.random(in: 0..<4, using: &rng)); hard = true
        case .crate: made = Obstacle(kind: .crate, x: 0, width: crate, height: crate, variant: 0)
        case .crateRow: made = Obstacle(kind: .crate, x: 0, width: crate * Double(Int.random(in: 2...3, using: &rng)), height: crate, variant: 0); hard = true
        case .crateStack: made = Obstacle(kind: .crate, x: 0, width: crate, height: crate * 2, variant: 0); hard = true
        case .puddle: made = Obstacle(kind: .puddle, x: 0, width: 150, height: 16, variant: 0)
        case .longPuddle: made = Obstacle(kind: .puddle, x: 0, width: 210, height: 16, variant: 1); hard = true
        }
        var placed = made
        placed.x = size.width + 100
        obstacles.append(placed)

        let ease = FaceGamePaint.smoothstep(0, 300, meters)
        let gapSeconds = FaceGamePaint.lerp(1.9, 1.05, ease) * Double.random(in: 1.0...1.4, using: &rng) + (hard ? 0.25 : 0)
        untilNext = made.width + gapSeconds * speed
    }

    /// After the crash: the dust settles and the words fade.
    mutating func settle(_ dt: Double) {
        dust.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
    }

    // MARK: Test hooks

    /// Replaces everything ahead with `obstacles`, and stops more from appearing until they have gone by.
    mutating func place(_ obstacles: [Obstacle]) {
        self.obstacles = obstacles
        untilNext = 1e9
    }

    /// Puts the runner at a height with no speed, in the air or standing on whatever is below.
    mutating func lift(to newHeight: Double) {
        height = newHeight
        vy = 0
        grounded = newHeight <= 0
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        BrowRunnerScenery.draw(ctx, size: size, groundY: Self.groundY, distance: distance, time: time,
                               cycleMeters: Self.cycleMeters, pixelsPerMeter: Self.pixelsPerMeter)
        for o in obstacles { drawObstacle(o, ctx, time: time) }
        for p in dust.particles { drawDust(p, ctx) }
        drawPlayer(ctx, time: time)
        if !crashed, elapsed > 0 { drawBrowGauge(ctx, time: time) }
        FaceGamePaint.draw(floaters, in: ctx)
    }

    private func drawDust(_ p: Particle, _ ctx: CGContext) {
        let point = CGPoint(x: p.position.x, y: p.position.y)
        switch p.kind {
        case 2: FaceGamePaint.spark(ctx, at: point, radius: p.size * 1.6, tone: FaceGamePaint.hsv(p.hue, 0.7, 1), alpha: 1 - p.progress)
        case 1: FaceGamePaint.spark(ctx, at: point, radius: p.size * 1.8, tone: p.hue > 0.4 ? FaceGamePaint.Tone(0.5, 0.8, 1) : FaceGamePaint.Tone(1, 0.85, 0.3), alpha: 1 - p.progress)
        default: FaceGamePaint.spark(ctx, at: point, radius: p.size * (1 + p.progress), tone: FaceGamePaint.Tone(0.85, 0.78, 0.62), alpha: 0.8 * (1 - p.progress))
        }
    }

    // MARK: Obstacles

    private func drawObstacle(_ o: Obstacle, _ ctx: CGContext, time: Double) {
        guard o.x < size.width + 40, o.x + o.width > -40 else { return }
        let base = Self.groundY
        switch o.kind {
        case .cactus:
            let count = o.variant >= 20 ? 3 : (o.variant >= 10 ? 2 : 1)
            for k in 0..<count {
                let share = o.width / Double(count)
                let x = o.x + share * (Double(k) + 0.5)
                let h = o.height * (k == 1 && count == 3 ? 1.0 : (count == 1 ? 1.0 : 0.82 + 0.18 * Double((k + o.variant) % 2)))
                let leftArm = (k + o.variant) % 2 == 0
                let rightArm = !leftArm || (k + o.variant) % 3 == 0
                FaceGameArt.contactShadow(ctx, center: CGPoint(x: x + 6, y: base - 8), width: 70, height: 14, alpha: 0.3)
                if let sprite = BrowRunnerArt.cactus(height: h, left: leftArm, right: rightArm) {
                    ctx.draw(sprite, in: CGRect(x: x - Double(sprite.width) / 2, y: base - 12, width: Double(sprite.width), height: Double(sprite.height)))
                }
            }
        case .crate:
            let columns = Int((o.width / Self.crateSize).rounded()), rows = Int((o.height / Self.crateSize).rounded())
            FaceGameArt.contactShadow(ctx, center: CGPoint(x: o.x + o.width / 2 + 8, y: base - 8), width: o.width + 30, height: 16, alpha: 0.32)
            for r in 0..<rows {
                for c in 0..<columns {
                    let rect = CGRect(x: o.x + Double(c) * Self.crateSize, y: base + Double(r) * Self.crateSize, width: Self.crateSize, height: Self.crateSize)
                    if let sprite = BrowRunnerArt.crate { ctx.draw(sprite, in: rect.insetBy(dx: -4, dy: -4)) }
                }
            }
        case .puddle:
            drawPuddle(ctx, x: o.x, width: o.width, base: base, time: time)
        }
    }

    private func drawPuddle(_ ctx: CGContext, x: Double, width: Double, base: Double, time: Double) {
        let rect = CGRect(x: x, y: base - 22, width: width, height: 34)
        if let sprite = BrowRunnerArt.puddle(width: width) { ctx.draw(sprite, in: rect.insetBy(dx: -6, dy: -6)) }
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.cream))
        ctx.setLineWidth(2.5)
        for k in 0..<2 {
            let t = FaceGamePaint.wrap(time * 0.7 + Double(k) * 0.5 + x * 0.01, 1)
            let rx = width * (0.08 + 0.26 * t), ry = 2.5 + 7 * t
            ctx.setAlpha(CGFloat(0.8 * (1 - t)))
            ctx.strokeEllipse(in: CGRect(x: rect.midX + width * 0.08 - rx, y: rect.midY + 2 - ry, width: rx * 2, height: ry * 2))
        }
        ctx.setAlpha(1)
    }

    // MARK: The runner

    private func drawPlayer(_ ctx: CGContext, time: Double) {
        let run = distance / 34
        let air = !grounded
        let bob = air ? 0 : abs(sin(run)) * 5
        let swing = air ? 0 : sin(run)
        let wind = min(1, speed / Self.topSpeed)

        // A shadow on the ground under it, smaller the higher it is.
        let shrink = 1 - min(0.6, height / 320)
        ctx.setFillColor(FaceGamePaint.cg(FaceGamePaint.Tone(0, 0, 0), 0.32 * shrink))
        ctx.fillEllipse(in: CGRect(x: Self.playerX - 38 * shrink, y: Self.groundY - 22, width: 76 * shrink, height: 14))

        ctx.saveGState()
        ctx.translateBy(x: Self.playerX, y: Self.groundY + height)
        if crashed {
            ctx.translateBy(x: -26, y: 0)
            ctx.rotate(by: -1.2)
        } else if air {
            ctx.rotate(by: CGFloat(-0.06 + max(-0.25, min(0.2, vy / 4200))))
        }

        let navy = FaceGamePaint.cg(FaceGamePaint.Tone(0.12, 0.16, 0.38))
        let skinLine = FaceGamePaint.cg(FaceGamePaint.Tone(0.06, 0.06, 0.12))

        // The scarf streams out behind and ripples faster with speed.
        ctx.setLineCap(.round)
        for (width, tone) in [(17.0, FaceGamePaint.Tone(0.35, 0.02, 0.05)), (11.0, FaceGamePaint.Tone(0.95, 0.2, 0.25))] {
            ctx.setLineWidth(CGFloat(width))
            ctx.setStrokeColor(FaceGamePaint.cg(tone))
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -10, y: 76))
            for i in 1...7 {
                let f = Double(i)
                let flutter = sin(run * 0.9 - f * 0.9) * (3 + f * 1.6) + (air ? -vy * 0.006 * f : 0)
                ctx.addLine(to: CGPoint(x: -10 - f * (9 + 5 * wind), y: 76 + flutter - f * 0.8))
            }
            ctx.strokePath()
        }

        // Legs and arms: opposite pairs swing, and in the air the legs tuck.
        func limb(from: CGPoint, angle: Double, length: Double, width: Double, tone: CGColor, foot: Bool) {
            let end = CGPoint(x: from.x + sin(angle) * length, y: from.y - cos(angle) * length)
            ctx.setStrokeColor(skinLine)
            ctx.setLineWidth(CGFloat(width + 6))
            ctx.move(to: from); ctx.addLine(to: end); ctx.strokePath()
            ctx.setStrokeColor(tone)
            ctx.setLineWidth(CGFloat(width))
            ctx.move(to: from); ctx.addLine(to: end); ctx.strokePath()
            if foot {
                ctx.setFillColor(skinLine)
                ctx.fillEllipse(in: CGRect(x: end.x - 11, y: end.y - 8, width: 28, height: 16))
                ctx.setFillColor(FaceGamePaint.cg(FaceGamePaint.Tone(1, 1, 1)))
                ctx.fillEllipse(in: CGRect(x: end.x - 8, y: end.y - 5, width: 22, height: 10))
            }
        }
        let backLeg = air ? -0.7 : -swing * 0.95, frontLeg = air ? 0.55 : swing * 0.95
        let backArm = air ? 2.5 : swing * 1.0, frontArm = air ? -2.4 : -swing * 1.0
        limb(from: CGPoint(x: -8, y: 38), angle: backLeg, length: 36, width: 14, tone: navy, foot: true)
        limb(from: CGPoint(x: -18, y: 74), angle: backArm, length: 30, width: 11, tone: FaceGamePaint.cg(FaceGamePaint.Tone(0.9, 0.5, 0.15)), foot: false)

        // The body: a bright hoodie.
        let torso = CGRect(x: -22, y: 30 + bob * 0.4, width: 44, height: 52)
        FaceGamePaint.outlined(ctx, path: FaceGamePaint.roundedPath(torso, radius: 18), fill: FaceGamePaint.cg(FaceGamePaint.Tone(1, 0.58, 0.14)), edge: skinLine, edgeWidth: 6)
        ctx.setFillColor(FaceGamePaint.cg(FaceGamePaint.Tone(1, 0.82, 0.4), 0.9))
        ctx.fill(CGRect(x: -9, y: torso.minY + 8, width: 18, height: 10))

        limb(from: CGPoint(x: 8, y: 38), angle: frontLeg, length: 36, width: 14, tone: navy, foot: true)
        limb(from: CGPoint(x: 18, y: 74), angle: frontArm, length: 30, width: 11, tone: FaceGamePaint.cg(FaceGamePaint.Tone(0.9, 0.5, 0.15)), foot: false)

        // The head is your face.
        let r = 41.0
        let head = CGRect(x: -r, y: 98 + bob - r, width: r * 2, height: r * 2)
        ctx.setFillColor(skinLine)
        ctx.fillEllipse(in: head.insetBy(dx: -6, dy: -6))
        FaceGamePaint.drawFace(ctx, crop: crop, in: head, corner: r, fallback: crashed ? "😵" : "😀")
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePaint.Tone(1, 1, 1)))
        ctx.setLineWidth(5)
        ctx.strokeEllipse(in: head)
        if jumpSwitch.isOn, air, !crashed {
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePaint.Tone(0.4, 0.95, 1), 0.9))
            ctx.setLineWidth(5)
            for k in -1...1 {
                ctx.move(to: CGPoint(x: Double(k) * 16, y: 6)); ctx.addLine(to: CGPoint(x: Double(k) * 16, y: -16 - Double(1 - abs(k)) * 10))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()

        if crashed {
            // Little stars circling the dazed runner's head.
            for k in 0..<3 {
                let a = time * 4 + Double(k) * 2 * .pi / 3
                let p = CGPoint(x: Self.playerX - 40 + cos(a) * 34, y: Self.groundY + height + 72 + sin(a) * 10)
                FaceGameArt.stamp(ctx, FaceGameArt.starSprite(), at: p, height: 26 + 6 * sin(a), rotation: a)
            }
        }
    }

    /// How high the eyebrows read, with the line they have to cross to jump, so you can see what the camera sees.
    private func drawBrowGauge(_ ctx: CGContext, time: Double) {
        let plate = CGRect(x: GameScreens.margin.width, y: GameScreens.margin.height, width: 330, height: 68)
        GameUIPlate.draw(ctx, plate, radius: 30)
        let up = jumpSwitch.isOn
        var pose = FaceGameMascot.Pose()
        pose.brows = min(1, brow / Self.browOn)
        pose.eyes = 1 + 0.2 * pose.brows
        FaceGameMascot.draw(ctx, center: CGPoint(x: plate.minX + 36, y: plate.midY), radius: 22, pose: pose)
        let bar = CGRect(x: plate.minX + 74, y: plate.midY - 10, width: 230, height: 20)
        FaceGamePaint.meter(ctx, in: bar, fill: brow, from: up ? FaceGamePalette.mint : FaceGamePalette.sky,
                            to: up ? FaceGameArt.lighter(FaceGamePalette.mint, 0.3) : FaceGameArt.lighter(FaceGamePalette.sky, 0.3))
        let mark = bar.minX + bar.width * Self.browOn
        ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.sun))
        ctx.addPath(FaceGamePaint.roundedPath(CGRect(x: mark - 2.5, y: bar.minY - 8, width: 5, height: bar.height + 16), radius: 2.5))
        ctx.fillPath()
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: mark - 7, y: bar.maxY + 14))
        tri.addLine(to: CGPoint(x: mark + 7, y: bar.maxY + 14))
        tri.addLine(to: CGPoint(x: mark, y: bar.maxY + 6))
        tri.closeSubpath()
        ctx.addPath(tri)
        ctx.fillPath()
    }
}
