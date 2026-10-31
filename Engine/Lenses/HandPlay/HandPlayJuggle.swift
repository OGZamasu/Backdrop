import AppKit
import CoreGraphics
import simd

/// Juggle. Balls fall under a soft gravity; bounce them back up with the flat of your hand. Every bounce scores, times the number of balls
/// in the air, and every eight bounces another ball joins in, up to four. Where a ball lands on your palm steers it: catch it on the left
/// of your hand and it goes left. A ball that hits the bottom of the picture costs a heart and comes back from the top.
///
/// The palm carries a springy ring, and the ball bounces off it (a shallow capsule the shape of the ring) with real physics, including the
/// hand's own speed. A ball always leaves a hand with enough lift to be reached again, so a hand that is simply held still under it keeps
/// it going: tracking lags, and the game forgives.
struct HandPlayJuggle: Game {
    static let title = "Juggle"
    static let hint = "Bounce the balls up with your palms. Don't let them drop!"
    static let presenceHint = "Hold up your hand to play"
    static let onboarding = ["Bounce the ball up with your palm", "Every eight bounces, another ball joins in"]
    static let accent = SIMD3<Double>(0.42, 0.78, 1.0)
    static let icon = GameUIIcon.hand(.open)
    static let startingLives = 3
    static let maxBalls = 4
    /// Bounces between one new ball and the next.
    static let hitsPerBall = 8
    static let ballRadius = 40.0
    /// Pixels a second squared: a floaty fall, so the hand has time to get there.
    static let gravity = 540.0
    /// The least and most upward speed a bounce gives.
    static let minimumLift = 640.0
    static let maximumLift = 1120.0
    static let restitution = 0.8

    /// Panel colours of the balls, in the order they join.
    enum Colours {
        static let sets: [(HandPlayTone, HandPlayTone)] = [
            (HandPlayPalette.coral, HandPlayPalette.gold),
            (HandPlayPalette.sky, HandPlayPalette.mint),
            (HandPlayPalette.violet, HandPlayPalette.rose),
            (HandPlayPalette.mint, HandPlayPalette.gold),
        ]
        static let pad = HandPlayPalette.ice
        static let padHot = HandPlayPalette.gold
    }

    struct Ball: Equatable {
        var id: Int
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var angle = 0.0
        var spin = 0.0
        var age = 0.0
        /// 1 just after a bounce, easing back to 0: the squash.
        var squash = 0.0
        var squashAngle = 0.0
        var cooldown = 0.0
        var colour: Int
    }

    struct Pad: Equatable {
        var hand: Int
        var center: SIMD2<Double>
        var previous: SIMD2<Double>
        var velocity = SIMD2<Double>.zero
        var radius: Double
        var presence = 0.0
        var visible = true
        /// 1 just after a ball bounced off it.
        var dip = 0.0
    }

    let size: CGSize
    private(set) var balls: [Ball] = []
    private(set) var pads: [Pad] = []
    private(set) var score = 0
    private(set) var lives = HandPlayJuggle.startingLives
    private(set) var hits = 0
    private(set) var drops = 0
    private(set) var elapsed = 0.0
    /// Balls waiting to come back in, with seconds to go.
    private(set) var returning: [Double] = []
    private var nextID = 1
    private var colourCount = 0
    private var roster = HandPlayRoster()
    private var fx: SplitMix64
    private var rng: SplitMix64
    private var particles = ParticleSystem(capacity: 300)
    private var floaters: [HandPlayFloater] = []
    private var hurt = 0.0
    private var newBallBanner = 0.0
    private var addsSpawned = 0

    var isOver: Bool { lives <= 0 }
    /// What every bounce is worth right now.
    var multiplier: Int { max(1, balls.count) }
    var summary: String {
        let hearts = String(repeating: "❤️", count: max(0, lives)) + String(repeating: "🖤", count: max(0, Self.startingLives - lives))
        return multiplier > 1 ? hearts + " · x\(multiplier)" : hearts
    }
    private var unit: Double { Double(size.width) / 1280 }
    private var radius: Double { Self.ballRadius * unit }

    var readout: GameUIReadout { GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), combo: multiplier > 1 ? multiplier : 0) }

    var result: GameUIResult {
        let line: String
        switch hits {
        case 0: line = "Hold a flat hand under the ball as it falls"
        case 1..<16: line = "Keep it going for a second ball"
        default: line = "A circus act in the making"
        }
        let seconds = Int(elapsed)
        return GameUIResult(headline: "Dropped it!", line: line,
                            stats: [("\(hits)", "bounces"), ("\(1 + min(Self.maxBalls - 1, hits / Self.hitsPerBall))", "most balls"),
                                    (String(format: "%d:%02d", seconds / 60, seconds % 60), "time")])
    }
    /// Balls owed to the player: one to start, and one more for every `hitsPerBall` bounces.
    private var ballsDue: Int { min(Self.maxBalls, 1 + hits / Self.hitsPerBall) }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        fx = SplitMix64(seed: seed ^ 0x1066_BA11)
        particles.gravity = SIMD2(0, -500)
        returning = [0.5]
    }

    /// How big a hand's pad is.
    static func padRadius(forHandSize size: Double, unit: Double) -> Double { min(130, max(58, size * 0.85)) * unit }

    // MARK: Step

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.25)
        guard !isOver else { return }
        elapsed += dt
        hurt = max(0, hurt - dt)
        newBallBanner = max(0, newBallBanner - dt)
        roster.update(world.hands, dt: dt, now: elapsed)
        updatePads(dt)

        for i in returning.indices { returning[i] -= dt }
        while let ready = returning.firstIndex(where: { $0 <= 0 }) {
            returning.remove(at: ready)
            launch()
        }
        // A new ball joins when enough bounces have been made.
        if balls.count + returning.count < ballsDue {
            addsSpawned += 1
            newBallBanner = 1.4
            returning.append(0.6)
        }

        moveBalls(dt)
        particles.step(dt)
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll(where: \.isDone)

        if isOver {
            balls.removeAll()
            returning.removeAll()
            particles.removeAll()
            floaters.removeAll()
            hurt = 0
            newBallBanner = 0
        }
    }

    private mutating func updatePads(_ dt: Double) {
        var next: [Pad] = []
        for entry in roster.entries {
            // The pad sits a little above the middle of the palm, toward the fingers: where a ball meets a flat hand.
            let up = entry.hand[.middleMCP] - entry.hand.wrist
            let length = max(1e-6, hypot(up.dx, up.dy))
            let center = entry.palm.handPlayVector + SIMD2(Double(up.dx), Double(up.dy)) / length * entry.size * 0.18
            let r = Self.padRadius(forHandSize: entry.size, unit: unit)
            if var pad = pads.first(where: { $0.hand == entry.id }) {
                pad.previous = pad.center
                if entry.visible {
                    pad.center = center
                    pad.radius += (r - pad.radius) * HandPlayEase.follow(dt, tau: 0.15)
                }
                pad.velocity = entry.velocity
                pad.presence = entry.presence
                // A hand lost for a frame or two still has its pad where it was, so a ball is not dropped by a blur.
                pad.visible = entry.isHeld
                pad.dip = max(0, pad.dip - dt / 0.3)
                next.append(pad)
            } else if entry.visible {
                next.append(Pad(hand: entry.id, center: center, previous: center, radius: r, presence: entry.presence))
            }
        }
        pads = next
    }

    private mutating func launch() {
        let w = Double(size.width)
        let x = w * Double.random(in: 0.3...0.7, using: &rng)
        balls.append(Ball(id: nextID, position: SIMD2(x, Double(size.height) + radius * 1.5),
                          velocity: SIMD2(Double.random(in: -60...60, using: &rng), -120) * unit, colour: colourCount % Colours.sets.count))
        nextID += 1
        colourCount += 1
    }

    private mutating func moveBalls(_ dt: Double) {
        let r = radius, w = Double(size.width), h = Double(size.height)
        // Small steps, so neither a fast ball nor a fast hand can pass through the other.
        let fastest = max(balls.map { simd_length($0.velocity) }.max() ?? 0, pads.map { simd_distance($0.center, $0.previous) / max(dt, 1e-6) }.max() ?? 0)
        let steps = max(1, min(12, Int(ceil(fastest * dt / (r * 0.4)))))
        let slice = dt / Double(steps)
        let g = Self.gravity * unit * (1 + 0.06 * Double(max(0, balls.count - 1)))
        for s in 0..<steps {
            let along = Double(s + 1) / Double(steps)
            for i in balls.indices {
                balls[i].velocity.y -= g * slice
                balls[i].position += balls[i].velocity * slice
                balls[i].cooldown = max(0, balls[i].cooldown - slice)
                if balls[i].position.x < r { balls[i].position.x = r; balls[i].velocity.x = abs(balls[i].velocity.x) * 0.85 }
                if balls[i].position.x > w - r { balls[i].position.x = w - r; balls[i].velocity.x = -abs(balls[i].velocity.x) * 0.85 }
                if balls[i].position.y > h - r && balls[i].velocity.y > 0 && balls[i].age > 1 { balls[i].velocity.y = -abs(balls[i].velocity.y) * 0.5 }
                for pad in pads where pad.visible {
                    let center = pad.previous + (pad.center - pad.previous) * along
                    bounce(i, off: pad, at: center)
                }
            }
        }
        for i in balls.indices {
            balls[i].age += dt
            balls[i].angle += balls[i].spin * dt
            balls[i].spin *= exp(-dt * 0.6)
            balls[i].squash = max(0, balls[i].squash - dt / 0.28)
        }
        // Dropped.
        for ball in balls where ball.position.y < -r {
            lives -= 1
            drops += 1
            hurt = 0.6
            floaters.append(HandPlayFloater(text: "DROP!", origin: SIMD2(ball.position.x, 70 * unit), tone: HandPlayPalette.coral, size: 50))
            if lives > 0 { returning.append(1.3) }
        }
        balls.removeAll { $0.position.y < -r }
    }

    /// The pad is the ring drawn on the palm: wide and shallow, so it is a capsule (a short flat bar with round ends), not a circle.
    static func padShape(radius: Double) -> (halfLength: Double, thickness: Double) { (radius * 0.58, radius * 0.45) }

    private mutating func bounce(_ i: Int, off pad: Pad, at center: SIMD2<Double>) {
        let r = radius
        let shape = Self.padShape(radius: pad.radius)
        let reach = shape.thickness + r
        let x = min(shape.halfLength, max(-shape.halfLength, balls[i].position.x - center.x))
        let nearest = SIMD2(center.x + x, center.y)
        let offset = balls[i].position - nearest
        let distance = simd_length(offset)
        guard distance < reach, distance > 1e-6 else { return }
        let n = offset / distance
        // Out of the pad, whatever happens next.
        balls[i].position = nearest + n * (reach + 0.5)
        let relative = balls[i].velocity - pad.velocity
        let closing = simd_dot(relative, n)
        guard closing < 0, balls[i].cooldown <= 0 else { return }

        var v = balls[i].velocity - (1 + Self.restitution) * closing * n
        if n.y > -0.35 {
            // From above or the side: always enough lift to be reached again, and steered by where on the hand it landed.
            v.y = max(Self.minimumLift * unit, min(Self.maximumLift * unit, v.y))
            v.x += ((balls[i].position.x - center.x) / (pad.radius + r)) * 300 * unit
        }
        v.x = max(-560 * unit, min(560 * unit, v.x))
        balls[i].velocity = v
        balls[i].cooldown = 0.14
        balls[i].squash = 1
        balls[i].squashAngle = atan2(n.y, n.x)
        balls[i].spin += (-n.y * relative.x + n.x * relative.y) / max(r, 1) * 0.6
        if let k = pads.firstIndex(where: { $0.hand == pad.hand }) { pads[k].dip = 1 }

        hits += 1
        let points = multiplier
        score += points
        let at = nearest + n * shape.thickness
        // Beside the ball and below it, so the ball flying up does not cover it.
        let side: Double = balls[i].position.x < Double(size.width) / 2 ? 1 : -1
        floaters.append(HandPlayFloater(text: "+\(points)", origin: at + SIMD2(side * (r + 46 * unit), 0), tone: HandPlayPalette.gold, size: 38, life: 0.7, rise: 60))
        let tone = Colours.sets[balls[i].colour].0
        for _ in 0..<8 {
            let a = atan2(n.y, n.x) + Double.random(in: -1.3...1.3, using: &fx)
            particles.emit(Particle(position: at, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 120...340, using: &fx),
                                    life: Double.random(in: 0.25...0.5, using: &fx), size: Double.random(in: 3...7, using: &fx),
                                    hue: Double(balls[i].colour), kind: tone == HandPlayPalette.gold ? 1 : 0))
        }
    }

    // MARK: Test hooks

    /// Puts a ball somewhere with a speed, and stops the opening ball from coming in.
    @discardableResult
    mutating func place(ballAt position: SIMD2<Double>, velocity: SIMD2<Double> = .zero) -> Int {
        returning.removeAll()
        balls.append(Ball(id: nextID, position: position, velocity: velocity, age: 2, colour: colourCount % Colours.sets.count))
        nextID += 1
        colourCount += 1
        return nextID - 1
    }

    mutating func clearBalls() {
        balls.removeAll()
        returning.removeAll()
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        if hurt > 0 { HandPlayDraw.vignette(ctx, size: size, tone: HandPlayPalette.coral, alpha: 0.5 * HandPlayEase.outCubic(hurt / 0.6)) }
        guard !isOver else { return }
        // Shadows on the floor first, so they sit under everything.
        for ball in balls {
            let height = HandPlayEase.clamp(ball.position.y / Double(size.height))
            HandPlayDraw.shadow(ctx, at: CGPoint(x: ball.position.x + 10 * unit, y: 24 * unit), width: radius * 2.4 * (1.15 - 0.6 * height),
                                height: radius * 0.55 * (1.15 - 0.6 * height), alpha: 0.5 * (1 - 0.75 * height))
        }
        for pad in pads { drawPad(ctx, pad) }
        for ball in balls { drawBall(ctx, ball) }
        for p in particles.particles {
            let t = p.progress
            let tone = p.kind == 1 ? HandPlayPalette.gold : Colours.sets[min(Colours.sets.count - 1, max(0, Int(p.hue)))].0
            ctx.fillCircle(center: p.position.handPlayPoint, radius: CGFloat(p.size * unit * (1 - 0.6 * t)), color: tone.lighter(0.25).cg(1 - t))
        }
        for f in floaters { f.draw(ctx) }
        if newBallBanner > 0 {
            GameScreens.callout(ctx, size: size, text: "+1 BALL!", age: 1.4 - newBallBanner, tone: GameUIPalette.violet, life: 1.4)
        }
    }

    /// The pad on a palm: a springy ring, lit, that dips when a ball lands on it.
    private func drawPad(_ ctx: CGContext, _ pad: Pad) {
        let alpha = pad.presence
        guard alpha > 0.01 else { return }
        let p = pad.center.handPlayPoint
        let dip = HandPlayEase.spring(1 - pad.dip, frequency: 18, damping: 6)
        let squash = pad.dip > 0 ? 1 - 0.25 * (1 - dip) : 1
        let r = pad.radius
        HandPlayDraw.glow(ctx, at: p, radius: r * 1.25, tone: pad.dip > 0 ? Colours.padHot : Colours.pad, alpha: (0.18 + 0.3 * pad.dip) * alpha)
        HandPlayDraw.stamp(ctx, HandPlayJuggleArt.pad(radius: CGFloat(r)), at: p, sx: CGFloat(1 + (1 - squash) * 0.4), sy: CGFloat(squash),
                           alpha: CGFloat(alpha * (pad.visible ? 1 : 0.5)))
    }

    private func drawBall(_ ctx: CGContext, _ ball: Ball) {
        let r = CGFloat(radius)
        let p = ball.position.handPlayPoint
        let enter = HandPlayEase.clamp(ball.age / 0.3)
        // Squash along the bounce, stretch across it, then spring back.
        let wobble = ball.squash > 0 ? exp(-6 * (1 - ball.squash)) * cos(18 * (1 - ball.squash)) * ball.squash : 0
        let set = Colours.sets[ball.colour % Colours.sets.count]
        // The panels turn as it spins (baked at angle steps); the light stays put.
        let panels = HandPlayDraw.turned(HandPlayJuggleArt.panels(set, colourKey: ball.colour, radius: r), key: "jg.panels|\(ball.colour)|\(Int(r * 10))",
                                         angle: ball.angle, steps: 36)
        if abs(wobble) > 0.01 {
            // Squash along the bounce, stretch across it, and spring back.
            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: CGFloat(ball.squashAngle))
            ctx.scaleBy(x: CGFloat(1 - 0.28 * wobble), y: CGFloat(1 + 0.22 * wobble))
            ctx.rotate(by: CGFloat(-ball.squashAngle))
            HandPlayDraw.stamp(ctx, panels, at: .zero, alpha: CGFloat(enter))
            HandPlayDraw.stamp(ctx, HandPlayJuggleArt.shading(radius: r), at: .zero, alpha: CGFloat(enter))
            ctx.restoreGState()
        } else {
            HandPlayDraw.stamp(ctx, panels, at: p, alpha: CGFloat(enter))
            HandPlayDraw.stamp(ctx, HandPlayJuggleArt.shading(radius: r), at: p, alpha: CGFloat(enter))
        }

        // A warning below a ball that is low and falling.
        if ball.position.y < 260 * unit && ball.velocity.y < 0 {
            let k = HandPlayEase.clamp(1 - ball.position.y / (260 * unit))
            let pulse = 0.6 + 0.4 * sin(elapsed * 14)
            let x = CGFloat(ball.position.x), base = CGFloat(36 * unit)
            let chevron = CGMutablePath()
            chevron.move(to: CGPoint(x: x - 20 * CGFloat(unit), y: base + 14 * CGFloat(unit)))
            chevron.addLine(to: CGPoint(x: x, y: base))
            chevron.addLine(to: CGPoint(x: x + 20 * CGFloat(unit), y: base + 14 * CGFloat(unit)))
            ctx.saveGState()
            ctx.addPath(chevron)
            ctx.setStrokeColor(HandPlayPalette.coral.cg(k * pulse))
            ctx.setLineWidth(CGFloat(7 * unit))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
}

/// The baked pictures for Juggle.
enum HandPlayJuggleArt {
    /// The coloured panels of a ball, which turn as it spins: six wedges round a pole set toward the top left, so it reads as round.
    static func panels(_ set: (HandPlayTone, HandPlayTone), colourKey: Int, radius r: CGFloat) -> CGImage? {
        HandPlaySprites.image("jg.panels|\(colourKey)|\(Int(r * 10))", side: Int(ceil(r * 2.2))) { ctx in
            ctx.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            ctx.clip()
            let pole = CGPoint(x: -r * 0.18, y: r * 0.22)
            let tones = [set.0, HandPlayPalette.cream, set.1, set.0, HandPlayPalette.cream, set.1]
            for k in 0..<6 {
                let a0 = CGFloat(k) * .pi / 3, a1 = a0 + .pi / 3
                let wedge = CGMutablePath()
                wedge.move(to: pole)
                // Curved seams: each edge bows a little, as seams on a sphere do.
                wedge.addQuadCurve(to: CGPoint(x: cos(a0) * r * 1.6, y: sin(a0) * r * 1.6), control: CGPoint(x: pole.x + cos(a0 + 0.35) * r * 0.9,
                                                                                                      y: pole.y + sin(a0 + 0.35) * r * 0.9))
                wedge.addLine(to: CGPoint(x: cos(a1) * r * 1.6, y: sin(a1) * r * 1.6))
                wedge.addQuadCurve(to: pole, control: CGPoint(x: pole.x + cos(a1 + 0.35) * r * 0.9, y: pole.y + sin(a1 + 0.35) * r * 0.9))
                wedge.closeSubpath()
                ctx.addPath(wedge)
                ctx.setFillColor(tones[k].cg())
                ctx.fillPath()
            }
            ctx.fillCircle(center: pole, radius: r * 0.16, color: HandPlayPalette.cream.cg())
        }
    }

    /// Light and shade laid over the panels, which stay put while the panels turn: a soft highlight on the top left, a darker rim on the
    /// bottom right, a sharp shine and a crisp edge.
    static func shading(radius r: CGFloat) -> CGImage? {
        HandPlaySprites.image("jg.shade|\(Int(r * 10))", side: Int(ceil(r * 2.4))) { ctx in
            let disc = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
            ctx.saveGState()
            ctx.addEllipse(in: disc)
            ctx.clip()
            HandPlayDraw.radial(ctx, [(HandPlayPalette.ink, 0), (HandPlayPalette.ink, 0.08), (HandPlayPalette.ink, 0.55)], center: CGPoint(x: -r * 0.12, y: r * 0.12),
                                radius: r * 1.12, from: CGPoint(x: -r * 0.35, y: r * 0.38), locations: [0, 0.55, 1])
            HandPlayDraw.radial(ctx, [(HandPlayPalette.cream, 0.55), (HandPlayPalette.cream, 0)], center: CGPoint(x: -r * 0.4, y: r * 0.42), radius: r * 0.6)
            // Light bouncing up from below on the far side.
            HandPlayDraw.radial(ctx, [(HandPlayPalette.ice, 0.3), (HandPlayPalette.ice, 0)], center: CGPoint(x: r * 0.7, y: -r * 0.75), radius: r * 0.55)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.translateBy(x: -r * 0.42, y: r * 0.5)
            ctx.rotate(by: 0.7)
            ctx.setFillColor(HandPlayPalette.cream.cg(0.9))
            ctx.fillEllipse(in: CGRect(x: -r * 0.2, y: -r * 0.1, width: r * 0.4, height: r * 0.2))
            ctx.restoreGState()
            ctx.setStrokeColor(HandPlayPalette.ink.cg(0.7))
            ctx.setLineWidth(max(1.5, r * 0.06))
            ctx.strokeEllipse(in: disc.insetBy(dx: r * 0.03, dy: r * 0.03))
        }
    }

    /// The springy pad on a palm: a ring of light on a faint disc, seen a little from above.
    static func pad(radius: CGFloat) -> CGImage? {
        let r = (radius / 4).rounded() * 4
        return HandPlaySprites.image("jg.pad|\(Int(r))", width: Int(ceil(r * 2.3)), height: Int(ceil(r * 1.3))) { ctx in
            let ring = CGRect(x: -r, y: -r * 0.45, width: r * 2, height: r * 0.9)
            ctx.saveGState()
            ctx.addEllipse(in: ring)
            ctx.clip()
            HandPlayDraw.fill(ctx, [(HandPlayPalette.ice, 0.32), (HandPlayPalette.sky, 0.12)], from: CGPoint(x: 0, y: r * 0.45), to: CGPoint(x: 0, y: -r * 0.45))
            ctx.restoreGState()
            // A dark edge under the ring, so it reads on a white wall too.
            ctx.setStrokeColor(HandPlayPalette.ink.cg(0.35))
            ctx.setLineWidth(max(5, r * 0.12))
            ctx.strokeEllipse(in: ring)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: r * 0.12, color: HandPlayPalette.sky.cg(0.9))
            ctx.setStrokeColor(HandPlayPalette.ice.cg(0.95))
            ctx.setLineWidth(max(3, r * 0.08))
            ctx.strokeEllipse(in: ring)
            ctx.restoreGState()
            ctx.setStrokeColor(HandPlayPalette.cream.cg(0.85))
            ctx.setLineWidth(max(2, r * 0.035))
            ctx.setLineCap(.round)
            // A glint along the top-left of the ring. The arc is added squashed, so it follows the ellipse, and stroked unsquashed.
            ctx.saveGState()
            ctx.scaleBy(x: 1, y: 0.45)
            ctx.addArc(center: .zero, radius: r * 0.86, startAngle: 1.9, endAngle: 2.7, clockwise: false)
            ctx.restoreGState()
            ctx.strokePath()
        }
    }
}
