import AppKit
import CoreGraphics
import simd

/// You are in goal. Shots come at you from far away, growing as they come, and a ring shows where each will arrive. Get some part
/// of yourself onto the ring before the ball gets there to save it; miss and it's a goal. Gold balls are worth three.
/// Three goals and the match is over.
///
/// Shots are aimed from where you are and how big you are: early ones come straight at you, later ones go just beside you, never
/// further than you can reach by leaning or stretching an arm.
struct GoalkeeperGame: Game {
    static let title = "Goalkeeper"
    static let hint = "Get in front of the ball to save it!"
    static let accent = SIMD3<Double>(0.45, 0.9, 0.62)

    static let startingLives = 3
    /// How much of the ring (of nine points) you must cover when the ball arrives.
    static let saveSamples = 3
    static let goldValue = 3

    struct Shot {
        var start: SIMD2<Double>
        var target: SIMD2<Double>
        /// Seconds from the kick to arriving.
        var flight: Double
        /// How far the ball bends sideways on the way, in pixels at its widest.
        var curve: Double
        var golden: Bool
        /// The ball's radius when it arrives.
        var radius: Double
        var age = 0.0

        var progress: Double { bodyClamp(age / flight, 0, 1) }
        /// How big it looks: far and small at first, rushing up at the end.
        var scale: Double { 1 / (1 + 4 * (1 - progress)) }
        var position: SIMD2<Double> {
            let k = (scale - 0.2) / 0.8
            let bend = sin(.pi * k) * curve
            let along = target - start
            let side = simd_length(along) > 1e-6 ? SIMD2(-along.y, along.x) / simd_length(along) : SIMD2<Double>(1, 0)
            return start + along * k + side * bend
        }
    }

    /// A saved ball, knocked away.
    struct Clearance {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var radius: Double
        var golden: Bool
        var spin: Double
        var angle = 0.0
        var age = 0.0
    }

    struct Ripple {
        var position: SIMD2<Double>
        var radius: Double
        var saved: Bool
        var age = 0.0
    }

    let size: CGSize
    private(set) var shot: Shot?
    private(set) var lives = GoalkeeperGame.startingLives
    private(set) var score = 0
    private(set) var saves = 0
    private(set) var goals = 0
    private(set) var shotsTaken = 0
    private(set) var streak = 0
    private(set) var reference: BodyFrame?

    private var rng: SplitMix64
    private var nextShot = 1.2
    private var shooting = true
    private var sinceScan = 9.0
    private var sinceGoal = 99.0
    private var flash = 0.0
    private var clearances: [Clearance] = []
    private var ripples: [Ripple] = []
    private var sparkles = ParticleSystem(capacity: 300)
    private var floaters: [BodyFloater] = []
    private var head: CGRect?
    private var spinAngle = 0.0

    var isOver: Bool { lives <= 0 }
    var summary: String { "Lives \(lives) · Saves \(saves)" }

    var readout: GameUIReadout {
        GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), combo: streak >= 3 ? streak : 0, label: "Saves \(saves)")
    }

    var result: GameUIResult {
        let line: String
        switch saves {
        case 0: line = "Step in front of the target ring to block the shot"
        case 1..<10: line = "\(saves) saves. Watch the ring and move early"
        default: line = "A wall between the posts!"
        }
        return GameUIResult(headline: "Out of lives", line: line, stats: [("\(saves)", "saves"), ("\(goals)", "let in"), ("\(shotsTaken)", "shots")])
    }
    /// 0 for the first shot, 1 by the twentieth.
    var difficulty: Double { min(1, Double(shotsTaken) / 20) }
    var currentFlight: Double { 1.75 - 0.7 * difficulty }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        sparkles.gravity = SIMD2(0, -600)
        sparkles.drag = 1
        BodyArtCache.warm("goal") {
            _ = GoalkeeperArt.side(height: Int(size.height))
            _ = GoalkeeperArt.top(width: Int(size.width))
            _ = GoalkeeperArt.ball(golden: false)
            _ = GoalkeeperArt.ball(golden: true)
            _ = GoalkeeperArt.glove()
            _ = KeepyUppyArt.light()
        }
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = bodyClamp(dt, 0, 0.1)
        sinceGoal += dt
        flash = max(0, flash - dt)
        look(at: world.matte, dt)

        if var current = shot {
            current.age += dt
            spinAngle += dt * (4 + 6 * current.progress)
            if current.age >= current.flight {
                shot = nil
                resolve(current, matte: world.matte)
            } else {
                shot = current
            }
        } else if shooting, !isOver {
            nextShot -= dt
            if nextShot <= 0 { kick() }
        }

        for i in clearances.indices {
            clearances[i].age += dt
            clearances[i].velocity.y -= 900 * dt
            clearances[i].position += clearances[i].velocity * dt
            clearances[i].angle += clearances[i].spin * dt
            clearances[i].radius *= max(0.6, 1 - 0.9 * dt)
        }
        clearances.removeAll { $0.age > 1.2 }
        for i in ripples.indices { ripples[i].age += dt }
        ripples.removeAll { $0.age > 0.7 }
        sparkles.step(dt)
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll { $0.isDone }
    }

    private mutating func look(at matte: MatteQuery?, _ dt: Double) {
        sinceScan += dt
        guard sinceScan >= 0.15 else { return }
        sinceScan = 0
        let scan = BodyScan(matte: matte, size: size, step: 24)
        head = scan.headZone
        guard let frame = BodyFrame(scan: scan) else { return }
        reference = reference.map { $0.blended(toward: frame, by: 0.4) } ?? frame
    }

    /// Picks where the next shot goes, from where the player is now.
    private mutating func kick() {
        let fallback = BodyFrame(left: size.width / 2 - 250, right: size.width / 2 + 250, top: size.height * 0.78, bottom: 0,
                                 headWidth: 160, shoulderY: size.height * 0.78 - 240)
        let frame = reference ?? fallback
        let u = max(90, frame.headWidth)
        let low = max(110, frame.shoulderY - 0.6 * u), high = min(size.height - 190, frame.top - 0.1 * u)
        var target: SIMD2<Double>
        let straight = shotsTaken < 2 || Double.random(in: 0..<1, using: &rng) < 0.45 - 0.25 * difficulty
        if straight {
            // Straight at you: be there, and it's saved.
            target = SIMD2(frame.centerX + Double.random(in: -0.35...0.35, using: &rng) * frame.width / 2,
                           Double.random(in: low...max(low, high), using: &rng))
        } else {
            // Just beside you: reach for it. Never further than a stretch.
            let side: Double = Bool.random(using: &rng) ? -1 : 1
            let reach = Double.random(in: 0.4...(0.9 + 0.8 * difficulty), using: &rng) * u
            var x = side < 0 ? frame.left - reach : frame.right + reach
            if x < 90 || x > size.width - 90 { x = side < 0 ? frame.right + reach : frame.left - reach }
            target = SIMD2(x, Double.random(in: low...max(low, high), using: &rng))
        }
        target.x = bodyClamp(target.x, 90, size.width - 90)
        target.y = bodyClamp(target.y, 100, size.height - 190)
        // Kicked from far off across the pitch: from the other side of the picture, never from behind the player's head.
        var startX = (target.x < size.width / 2 ? size.width * 0.74 : size.width * 0.26) + Double.random(in: -90...90, using: &rng)
        if let head, startX > Double(head.minX) - 60, startX < Double(head.maxX) + 60 {
            startX = startX < Double(head.midX) ? Double(head.minX) - 80 : Double(head.maxX) + 80
        }
        let start = SIMD2(bodyClamp(startX, 140, size.width - 140), size.height * 0.64)
        let golden = shotsTaken >= 3 && Double.random(in: 0..<1, using: &rng) < 0.14
        let curve = difficulty > 0.3 ? Double.random(in: -90...90, using: &rng) * difficulty : 0
        shot = Shot(start: start, target: target, flight: currentFlight, curve: curve, golden: golden, radius: bodyClamp(0.36 * u, 40, 64))
        shotsTaken += 1
    }

    private mutating func resolve(_ shot: Shot, matte: MatteQuery?) {
        let covered = matte.map { BodySense.bodyHits(at: shot.target, radius: shot.radius * 0.75, in: $0) } ?? 0
        if covered >= Self.saveSamples {
            saves += 1
            streak += 1
            let value = shot.golden ? Self.goldValue : 1
            score += value
            ripples.append(Ripple(position: shot.target, radius: shot.radius, saved: true))
            // Knocked away, back out and to the side, spinning.
            let away: Double = shot.target.x < size.width / 2 ? -1 : 1
            clearances.append(Clearance(position: shot.target, velocity: SIMD2(away * Double.random(in: 250...480, using: &rng), Double.random(in: 380...620, using: &rng)),
                                        radius: shot.radius, golden: shot.golden, spin: away * 9))
            for _ in 0..<(shot.golden ? 26 : 14) {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                sparkles.emit(Particle(position: shot.target, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 150...480, using: &rng),
                                       life: Double.random(in: 0.3...0.7, using: &rng), size: Double.random(in: 3...7, using: &rng), kind: shot.golden ? 1 : 0))
            }
            let words = streak >= 3 ? "SAVE! x\(streak)" : "SAVE!"
            floaters.append(BodyFloater.placed(shot.golden ? "GOLD SAVE +\(value)" : words, at: shot.target + SIMD2(0, shot.radius + 40), size: size,
                                               color: shot.golden ? BodyGamePalette.gold : BodyGamePalette.mint, fontSize: 52, avoiding: head))
        } else {
            goals += 1
            streak = 0
            lives = max(0, lives - 1)
            sinceGoal = 0
            flash = 0.5
            ripples.append(Ripple(position: shot.target, radius: shot.radius, saved: false))
            floaters.append(BodyFloater.placed("GOAL!", at: shot.target + SIMD2(0, shot.radius + 40), size: size, color: BodyGamePalette.coral,
                                               fontSize: 64, life: 1.1, avoiding: head))
        }
        nextShot = 0.9 - 0.4 * difficulty
    }

    // MARK: Test hooks

    /// Stops shots from being taken on their own.
    mutating func holdShots() { shooting = false }

    /// Takes a shot now that arrives at `target`.
    mutating func shoot(at target: SIMD2<Double>, flight: Double = 1.2, golden: Bool = false, radius: Double = 50) {
        shot = Shot(start: SIMD2(target.x < size.width / 2 ? size.width * 0.74 : size.width * 0.26, size.height * 0.64), target: target,
                    flight: flight, curve: 0, golden: golden, radius: radius)
        shotsTaken += 1
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        drawGoal(in: ctx, time: time)
        for ripple in ripples where !ripple.saved { drawNetRipple(ripple, in: ctx) }
        if let shot {
            drawTarget(shot, in: ctx, time: time)
            drawBall(at: shot.position, radius: shot.radius * shot.scale, golden: shot.golden, angle: spinAngle, in: ctx)
        }
        for ripple in ripples where ripple.saved {
            let t = ripple.age / 0.7
            let r = ripple.radius * (1 + 1.6 * BodyEase.outCubic(t))
            ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.mint, CGFloat(0.9 * (1 - t))))
            ctx.setLineWidth(CGFloat(9 * (1 - t) + 1))
            ctx.strokeEllipse(in: CGRect(x: ripple.position.x - r, y: ripple.position.y - r, width: r * 2, height: r * 2))
        }
        for c in clearances {
            let fade = bodyClamp((1.2 - c.age) / 0.4, 0, 1)
            ctx.setAlpha(CGFloat(fade))
            drawBall(at: c.position, radius: c.radius, golden: c.golden, angle: c.angle, in: ctx)
            ctx.setAlpha(1)
        }
        for p in sparkles.particles {
            ctx.setAlpha(CGFloat(1 - p.progress))
            let colour = p.kind == 1 ? BodyGamePalette.gold : BodyGamePalette.mint
            ctx.fillCircle(center: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 - 0.5 * p.progress), color: colour.bodyShade(0.2))
        }
        ctx.setAlpha(1)
        for floater in floaters { floater.draw(in: ctx) }
        BodyGameHUD.flash(ctx, size: size, strength: flash / 0.5 * 0.7)
    }

    /// The goal round the picture: white posts down the sides and a crossbar along the top, with a strip of net inside them.
    /// Drawn once, as three strips, so each frame only copies them.
    private func drawGoal(in ctx: CGContext, time: Double) {
        let band = GoalkeeperArt.band
        if let side = GoalkeeperArt.side(height: Int(size.height)) {
            ctx.draw(side, in: CGRect(x: 0, y: 0, width: band, height: size.height))
            ctx.saveGState()
            ctx.translateBy(x: size.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ctx.draw(side, in: CGRect(x: 0, y: 0, width: band, height: size.height))
            ctx.restoreGState()
        }
        if let top = GoalkeeperArt.top(width: Int(size.width)) {
            ctx.draw(top, in: CGRect(x: 0, y: size.height - band, width: size.width, height: band))
        }
    }

    /// Where the ball will arrive: a ring that closes in as it comes, mint for a normal shot and gold for a gold one.
    private func drawTarget(_ shot: Shot, in ctx: CGContext, time: Double) {
        let c = CGPoint(x: shot.target.x, y: shot.target.y), r = shot.radius
        let t = shot.progress
        let colour = shot.golden ? BodyGamePalette.gold : BodyGamePalette.mint
        let appear = BodyEase.outBack(shot.age / 0.3)
        BodyGlow.stamp(ctx, at: c, radius: CGFloat(r * 2.2 * appear), color: colour, alpha: 0.18 + 0.25 * t)
        ctx.fillCircle(center: c, radius: CGFloat(r * appear), color: BodyGamePalette.cg(colour, CGFloat(0.12 + 0.12 * t)))
        let closing = r * (1 + 1.4 * (1 - BodyEase.inOutSine(t))) * appear
        ctx.setStrokeColor(BodyGamePalette.cg(colour, CGFloat(0.6 + 0.35 * sin(time * (6 + 10 * t)))))
        ctx.setLineWidth(5)
        ctx.strokeEllipse(in: CGRect(x: c.x - closing, y: c.y - closing, width: closing * 2, height: closing * 2))
        ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.cream, 0.9))
        ctx.setLineWidth(2.5)
        ctx.strokeEllipse(in: CGRect(x: c.x - r * appear, y: c.y - r * appear, width: r * 2 * appear, height: r * 2 * appear))
        // A glove mark in the middle: "put a hand here".
        if let glove = GoalkeeperArt.glove() {
            ctx.draw(glove, center: c, height: CGFloat(r * 1.1 * appear), alpha: CGFloat(0.55 + 0.3 * t))
        }
    }

    private func drawNetRipple(_ ripple: Ripple, in ctx: CGContext) {
        let t = ripple.age / 0.7
        let c = CGPoint(x: ripple.position.x, y: ripple.position.y)
        for k in 0..<3 {
            let lag = Double(k) * 0.12
            let local = bodyClamp((t - lag) / (1 - lag), 0, 1)
            guard local > 0, local < 1 else { continue }
            let r = ripple.radius * (0.6 + 2.2 * BodyEase.outCubic(local))
            ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.coral, CGFloat(0.8 * (1 - local))))
            ctx.setLineWidth(CGFloat(6 * (1 - local) + 1))
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        BodyGlow.stamp(ctx, at: c, radius: CGFloat(ripple.radius * 1.6), color: BodyGamePalette.coral, alpha: 0.6 * (1 - t))
    }

    private func drawBall(at p: SIMD2<Double>, radius r: Double, golden: Bool, angle: Double, in ctx: CGContext) {
        guard r > 1, let panels = GoalkeeperArt.ball(golden: golden), let light = KeepyUppyArt.light() else { return }
        BodyGlow.stamp(ctx, at: CGPoint(x: p.x + r * 0.15, y: p.y - r * 0.3), radius: CGFloat(r * 1.4), red: 0.04, green: 0.02, blue: 0.1, alpha: 0.35)
        if golden { BodyGlow.stamp(ctx, at: CGPoint(x: p.x, y: p.y), radius: CGFloat(r * 2.2), color: BodyGamePalette.gold, alpha: 0.5) }
        ctx.draw(panels, center: CGPoint(x: p.x, y: p.y), height: CGFloat(r * 2), rotation: CGFloat(angle))
        ctx.draw(light, center: CGPoint(x: p.x, y: p.y), height: CGFloat(r * 2))
    }
}

/// The goal posts, the ball and the glove mark, drawn once.
enum GoalkeeperArt {
    /// How deep each strip of goal is: the post and the net inside it.
    static let band: CGFloat = 96
    private static let postWidth: CGFloat = 20

    /// The net: a fine diagonal lattice that fades toward the middle of the picture, so it never covers the player.
    private static func net(_ ctx: CGContext, in rect: CGRect, fadeTowardX: Bool) {
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
        ctx.setLineWidth(1.5)
        let reach = rect.width + rect.height
        var x = rect.minX - reach
        while x < rect.maxX + reach {
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x + reach, y: rect.minY + reach))
            ctx.move(to: CGPoint(x: x + reach, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.minY + reach))
            x += 28
        }
        ctx.strokePath()
        // Fade the inner edge out.
        ctx.setBlendMode(.destinationOut)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let g = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 1)] as CFArray, locations: [0, 1]) {
            if fadeTowardX {
                ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX + rect.width * 0.35, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [.drawsAfterEndLocation])
            } else {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY - rect.height * 0.35), end: CGPoint(x: 0, y: rect.minY), options: [.drawsAfterEndLocation])
            }
        }
        ctx.restoreGState()
    }

    /// The left side of the goal (the right is the same, mirrored): a post with net inside it.
    static func side(height: Int) -> CGImage? {
        BodyArtCache.image("goal-side-\(height)", width: Int(band), height: height) { ctx in
            net(ctx, in: CGRect(x: postWidth, y: 0, width: band - postWidth, height: CGFloat(height) - postWidth), fadeTowardX: true)
            if let p = post(vertical: true) { ctx.draw(p, in: CGRect(x: -4, y: -8, width: postWidth + 8, height: CGFloat(height) + 8)) }
        }
    }

    /// The top of the goal: the crossbar with net under it.
    static func top(width: Int) -> CGImage? {
        BodyArtCache.image("goal-top-\(width)", width: width, height: Int(band)) { ctx in
            net(ctx, in: CGRect(x: postWidth, y: 0, width: CGFloat(width) - 2 * postWidth, height: band - postWidth), fadeTowardX: false)
            if let p = post(vertical: false) { ctx.draw(p, in: CGRect(x: -4, y: band - postWidth - 4, width: CGFloat(width) + 8, height: postWidth + 8)) }
        }
    }

    /// A white post, rounded, lit from the left (or from the top, lying across).
    static func post(vertical: Bool) -> CGImage? {
        BodyArtCache.image(vertical ? "goal-post-v" : "goal-post-h", width: vertical ? 28 : 64, height: vertical ? 64 : 28) { ctx in
            let rect = vertical ? CGRect(x: 4, y: 0, width: 20, height: 64) : CGRect(x: 0, y: 4, width: 64, height: 20)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let colors = [CGColor(red: 0.62, green: 0.64, blue: 0.7, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                          CGColor(red: 0.92, green: 0.93, blue: 0.96, alpha: 1), CGColor(red: 0.55, green: 0.57, blue: 0.64, alpha: 1)] as CFArray
            ctx.setShadow(offset: CGSize(width: 2, height: -2), blur: 4, color: CGColor(red: 0, green: 0, blue: 0.05, alpha: 0.5))
            ctx.setFillColor(CGColor(red: 0.8, green: 0.8, blue: 0.84, alpha: 1))
            ctx.fill(rect)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.clip(to: rect)
            if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.3, 0.6, 1]) {
                if vertical {
                    ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
                } else {
                    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
                }
            }
        }
    }

    /// A football: white with dark pentagons, or gold with dark ones.
    static func ball(golden: Bool) -> CGImage? {
        BodyArtCache.image(golden ? "goal-ball-gold" : "goal-ball", width: 160, height: 160) { ctx in
            let c = CGPoint(x: 80, y: 80), R: CGFloat = 76
            ctx.addEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
            ctx.clip()
            ctx.setFillColor(golden ? CGColor(red: 1, green: 0.84, blue: 0.36, alpha: 1) : CGColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
            let ink = golden ? CGColor(red: 0.45, green: 0.27, blue: 0.04, alpha: 1) : CGColor(red: 0.13, green: 0.13, blue: 0.18, alpha: 1)
            func pentagon(_ at: CGPoint, _ r: CGFloat, _ turn: CGFloat) -> [CGPoint] {
                (0..<5).map { i in
                    let a = turn + .pi / 2 + CGFloat(i) * 2 * .pi / 5
                    return CGPoint(x: at.x + cos(a) * r, y: at.y + sin(a) * r)
                }
            }
            let middle = pentagon(c, R * 0.3, 0)
            // Seams from each corner of the middle patch out to the ring of patches.
            ctx.setStrokeColor(golden ? CGColor(red: 0.6, green: 0.42, blue: 0.1, alpha: 0.8) : CGColor(red: 0.55, green: 0.56, blue: 0.62, alpha: 1))
            ctx.setLineWidth(2.5)
            for p in middle {
                ctx.move(to: p)
                ctx.addLine(to: CGPoint(x: c.x + (p.x - c.x) * 2.3, y: c.y + (p.y - c.y) * 2.3))
            }
            ctx.strokePath()
            ctx.setFillColor(ink)
            ctx.addLines(between: middle)
            ctx.closePath()
            ctx.fillPath()
            for i in 0..<5 {
                let a = .pi / 2 + .pi / 5 + CGFloat(i) * 2 * .pi / 5
                let at = CGPoint(x: c.x + cos(a) * R * 0.86, y: c.y + sin(a) * R * 0.86)
                ctx.addLines(between: pentagon(at, R * 0.27, a + .pi / 2 + .pi / 5))
                ctx.closePath()
                ctx.fillPath()
            }
        }
    }

    /// A simple glove outline, to say "put a hand here".
    static func glove() -> CGImage? {
        BodyArtCache.image("goal-glove", width: 96, height: 112) { ctx in
            let path = CGMutablePath()
            path.addRoundedRect(in: CGRect(x: 22, y: 8, width: 52, height: 56), cornerWidth: 18, cornerHeight: 18)
            for (i, x) in [24.0, 37.0, 50.0, 63.0].enumerated() {
                let h = [34.0, 42.0, 40.0, 32.0][i]
                path.addRoundedRect(in: CGRect(x: x - 1, y: 46, width: 12, height: h), cornerWidth: 6, cornerHeight: 6)
            }
            path.addRoundedRect(in: CGRect(x: 4, y: 30, width: 30, height: 13), cornerWidth: 6.5, cornerHeight: 6.5, transform: CGAffineTransform(rotationAngle: 0.5).translatedBy(x: 22, y: -14))
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 5, color: CGColor(red: 0.07, green: 0.07, blue: 0.13, alpha: 0.7))
            ctx.addPath(path)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.fillPath()
        }
    }
}
