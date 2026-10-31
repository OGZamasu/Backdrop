import AppKit
import CoreGraphics
import simd

/// Keep a beach ball in the air with your head. The ball bounces off the top of your head (lean into it to send it higher);
/// let it hit the floor and it costs a heart. Every header scores, and the ball gets heavier as you go.
struct FaceKeepyUppyGame: FaceGame {
    static let title = "Keepy Uppy"
    static let hint = "Head the ball to keep it up. Don't let it drop!"
    static let presenceHint = "Look into the camera to play"
    static let move = FaceGameMove.nodHead
    static let accent = FaceGamePalette.leaf
    static let scoreLabel = "HEADERS"

    static let lives = 3
    static let ballRadius = 54.0
    /// The lowest speed a header sends the ball up at, so even a still head keeps it going.
    static let minimumKick = 760.0
    static let restitution = 0.78

    let size: CGSize
    private(set) var ball: SIMD2<Double>
    private(set) var velocity = SIMD2<Double>(0, 0)
    private(set) var spin = 0.0
    private(set) var angle = 0.0
    private(set) var score = 0
    private(set) var hearts = FaceKeepyUppyGame.lives
    private(set) var elapsed = 0.0
    /// Seconds until a fresh ball drops in; the ball waits above the top of the picture meanwhile.
    private(set) var serving = 1.0
    /// The head as the game sees it: a circle over the top of your head, smoothed, and how fast it is moving.
    private(set) var head: SIMD2<Double>?
    private(set) var headRadius = 100.0
    private(set) var headVelocity = SIMD2<Double>(0, 0)
    private(set) var best = 0
    private var streak = 0
    private var missingFor = 0.0
    private var cooldown = 0.0
    private var squash = 0.0
    private var squashAngle = 0.0
    private var rng: SplitMix64
    private var trail: [SIMD2<Double>] = []
    private var pops: [(x: Double, y: Double, age: Double)] = []
    private var sparks = ParticleSystem(capacity: 200)
    private var floaters: [FaceGameFloater] = []

    var isOver: Bool { hearts <= 0 }
    var summary: String { "Lives \(hearts)" }
    /// The ball gets heavier as the game goes on.
    var gravity: Double { 1050 + min(550, elapsed * 7) }

    var chips: [FaceGameChip] { streak >= 5 ? [.hearts(hearts, of: Self.lives), .text("STREAK \(streak)")] : [.hearts(hearts, of: Self.lives)] }
    var ending: FaceGameEnding { .lost("DROPPED IT!") }
    var endLine: String { best <= 1 ? "Keep it up a little longer next time" : "Your best run was \(best) in a row" }
    var tip: String? {
        if elapsed < 4 { return "Head the ball!" }
        if serving > 0, hearts < Self.lives { return "Here comes another ball" }
        return nil
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        ball = SIMD2(size.width / 2, size.height + Self.ballRadius * 2)
        sparks.gravity = SIMD2(0, -600)
        sparks.drag = 1.2
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.1)
        sparks.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
        for i in pops.indices { pops[i].age += dt }
        pops.removeAll { $0.age > 0.45 }
        squash = max(0, squash - dt * 6)
        guard !isOver else { return }
        // The ball hangs in the air while there is no head to play it with.
        guard let face = world.face else {
            missingFor += dt
            if missingFor > 0.3 { head = nil }
            return
        }
        missingFor = 0
        elapsed += dt
        track(face, dt: dt)

        if serving > 0 {
            serving -= dt
            ball = SIMD2(min(size.width - 120, max(120, head?.x ?? size.width / 2)), size.height + Self.ballRadius * 1.5)
            velocity = SIMD2(0, -120)
            if serving <= 0 { serving = 0 }
            return
        }
        var h = dt
        while h > 1e-9 {
            let part = min(h, 1.0 / 120)
            fly(part)
            h -= part
            if serving > 0 { break }
        }
        trail.insert(ball, at: 0)
        if trail.count > 8 { trail.removeLast() }
    }

    /// Follows the top of the head: a circle above the eyes about as wide as the head, smoothed, with its speed.
    private mutating func track(_ face: FaceState, dt: Double) {
        let up = SIMD2(Double(face.up.dx), Double(face.up.dy))
        let eyes = SIMD2(Double(face.eyeCenter.x), Double(face.eyeCenter.y))
        let target = eyes + up * face.interocular * 0.55
        let radius = max(60, face.interocular * 1.35)
        guard let previous = head else {
            head = target
            headRadius = radius
            headVelocity = .zero
            return
        }
        let next = previous + (target - previous) * (1 - exp(-28 * dt))
        let measured = (next - previous) / max(dt, 1e-3)
        headVelocity += (measured - headVelocity) * (1 - exp(-14 * dt))
        let fastest = 2200.0
        if simd_length(headVelocity) > fastest { headVelocity = simd_normalize(headVelocity) * fastest }
        head = next
        headRadius += (radius - headRadius) * (1 - exp(-6 * dt))
    }

    private mutating func fly(_ h: Double) {
        cooldown = max(0, cooldown - h)
        velocity.y -= gravity * h
        velocity *= (1 - 0.08 * h)
        ball += velocity * h
        angle += spin * h
        spin *= (1 - 0.6 * h)

        let r = Self.ballRadius
        if ball.x < r { ball.x = r; velocity.x = abs(velocity.x) * 0.85; spin = -spin; bump(SIMD2(0, ball.y), angle: 0) }
        if ball.x > size.width - r { ball.x = size.width - r; velocity.x = -abs(velocity.x) * 0.85; spin = -spin; bump(SIMD2(size.width, ball.y), angle: .pi) }
        // The top of the picture is a ceiling: there is little room above a head in a webcam picture, so the ball comes back off it
        // instead of disappearing.
        if ball.y > size.height - r, velocity.y > 0 {
            ball.y = size.height - r
            velocity.y = -velocity.y * 0.55
            bump(SIMD2(ball.x, size.height), angle: -.pi / 2)
        }

        if let head, cooldown == 0 {
            let gap = ball - head
            let d = simd_length(gap)
            let reach = r + headRadius
            if d < reach, d > 1e-6 {
                let normal = gap / d
                let relative = velocity - headVelocity
                let closing = simd_dot(relative, normal)
                if closing < 0 || d < reach * 0.8 {
                    header(normal: normal, closing: closing)
                }
            }
        }
        if ball.y < -r {
            drop()
        }
    }

    private mutating func header(normal: SIMD2<Double>, closing: Double) {
        guard let head else { return }
        ball = head + normal * (Self.ballRadius + headRadius + 1)
        var out = velocity - (1 + Self.restitution) * min(0, closing) * normal + headVelocity * 0.55
        // Always up, with a little sideways scatter, so a head that never moves can't keep it up for ever.
        out.y = max(out.y, Self.minimumKick + Double.random(in: 0...80, using: &rng))
        out.x = out.x * 0.7 + Double.random(in: -170...170, using: &rng)
        out.x = max(-520, min(520, out.x))
        velocity = out
        spin = -out.x / 60 + Double.random(in: -2...2, using: &rng)
        cooldown = 0.18
        squash = 1
        squashAngle = atan2(normal.y, normal.x)
        score += 1
        streak += 1
        best = max(best, streak)
        let contact = head + normal * headRadius
        pops.append((contact.x, contact.y, 0))
        for _ in 0..<10 {
            let a = atan2(normal.y, normal.x) + Double.random(in: -1.2...1.2, using: &rng), v = Double.random(in: 160...420, using: &rng)
            sparks.emit(Particle(position: contact, velocity: SIMD2(cos(a), sin(a)) * v, life: Double.random(in: 0.3...0.6, using: &rng),
                                 size: Double.random(in: 5...12, using: &rng), kind: Int.random(in: 0...2, using: &rng)))
        }
        if streak > 0, streak % 10 == 0 {
            floaters.append(FaceGameFloater(text: "\(streak) IN A ROW!", position: SIMD2(size.width / 2, size.height * 0.72), tone: FaceGamePalette.sun, size: 56, life: 1.2, rise: 50))
        } else {
            floaters.append(FaceGameFloater(text: "+1", position: contact + SIMD2(0, 60), tone: FaceGamePalette.cream, size: 44, life: 0.7))
        }
    }

    /// A small squash where the ball meets a wall or the ceiling.
    private mutating func bump(_ at: SIMD2<Double>, angle: Double) {
        squash = 0.6
        squashAngle = angle
    }

    private mutating func drop() {
        hearts -= 1
        streak = 0
        floaters.append(FaceGameFloater(text: "DROPPED!", position: SIMD2(min(size.width - 160, max(160, ball.x)), 120), tone: FaceGamePalette.coral, size: 48, life: 1.0, rise: 60))
        serving = hearts > 0 ? 1.4 : 0
        trail.removeAll()
    }

    /// After the round only the particles and words carry on; with no face, nothing in the rules moves.
    mutating func settle(_ dt: Double) {
        step(dt, world: GameWorld(size: size, matte: nil, motion: nil, face: nil))
    }

    // MARK: Test hooks

    /// Puts the ball somewhere with a speed, in play straight away.
    mutating func placeBall(at point: CGPoint, velocity v: SIMD2<Double>) {
        ball = SIMD2(Double(point.x), Double(point.y))
        velocity = v
        serving = 0
        cooldown = 0
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        drawHeadPad(ctx, time: time)
        for (i, p) in trail.enumerated() where i > 0 && simd_length(velocity) > 500 {
            let t = Double(i) / Double(trail.count)
            FaceGamePaint.spark(ctx, at: CGPoint(x: p.x, y: p.y), radius: Self.ballRadius * (1 - 0.6 * t), tone: FaceGamePalette.cream, alpha: 0.18 * (1 - t))
        }
        for pop in pops {
            let t = pop.age / 0.45
            let r = 30 + 70 * FaceGameEase.cubicOut(t)
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.sun, 0.85 * (1 - t)))
            ctx.setLineWidth(CGFloat(7 * (1 - t) + 1))
            ctx.strokeEllipse(in: CGRect(x: pop.x - r, y: pop.y - r * 0.6, width: r * 2, height: r * 1.2))
        }
        drawBall(ctx, time: time)
        for p in sparks.particles {
            let tone = [FaceGamePalette.sun, FaceGamePalette.cream, FaceGamePalette.leaf][p.kind % 3]
            FaceGamePaint.spark(ctx, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 - 0.5 * p.progress), tone: tone, alpha: 1 - p.progress)
        }
        FaceGamePaint.draw(floaters, in: ctx)
    }

    /// A faint arc over the head, showing where the ball bounces.
    private func drawHeadPad(_ ctx: CGContext, time: Double) {
        guard let head else { return }
        let falling = velocity.y < 0 && serving == 0
        let glow = falling ? 0.5 + 0.3 * sin(time * 8) : 0.3
        ctx.saveGState()
        ctx.setLineCap(.round)
        let c = CGPoint(x: head.x, y: head.y)
        for (width, tone, alpha) in [(14.0, FaceGamePalette.ink, 0.25), (6.0, FaceGamePalette.leaf, glow)] {
            ctx.setStrokeColor(FaceGamePaint.cg(tone, alpha))
            ctx.setLineWidth(CGFloat(width))
            ctx.addArc(center: c, radius: CGFloat(headRadius), startAngle: .pi * 0.18, endAngle: .pi * 0.82, clockwise: false)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private func drawBall(_ ctx: CGContext, time: Double) {
        let r = Self.ballRadius
        if serving > 0 || ball.y > size.height + r * 0.6 {
            // Above the picture: an arrow at the top edge says where it will come down.
            let x = min(size.width - 120, max(120, ball.x))
            let bob = 6 * sin(time * 7)
            let tip = CGPoint(x: x, y: size.height - 150 + bob)
            FaceGameArt.stamp(ctx, FaceKeepyUppyArt.paint, at: CGPoint(x: x, y: tip.y + 56), height: 52, rotation: time)
            FaceGameArt.stamp(ctx, FaceKeepyUppyArt.shade, at: CGPoint(x: x, y: tip.y + 56), height: 52)
            let arrow = CGMutablePath()
            arrow.move(to: CGPoint(x: tip.x - 16, y: tip.y + 22))
            arrow.addLine(to: CGPoint(x: tip.x + 16, y: tip.y + 22))
            arrow.addLine(to: CGPoint(x: tip.x, y: tip.y))
            arrow.closeSubpath()
            FaceGameArt.fillLit(ctx, arrow, tone: FaceGamePalette.cream, edgeWidth: 2.5, edgeTone: FaceGamePalette.ink)
            return
        }
        let c = CGPoint(x: ball.x, y: ball.y)
        FaceGameArt.contactShadow(ctx, center: CGPoint(x: c.x + 10, y: c.y - 12), width: r * 2.3, height: r * 2.3, alpha: 0.28)
        // A squash along the line of the last header, springing back.
        let s = 0.22 * squash
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(squashAngle))
        ctx.scaleBy(x: CGFloat(1 - s), y: CGFloat(1 + s * 0.6))
        ctx.rotate(by: CGFloat(-squashAngle))
        FaceGameArt.stamp(ctx, FaceKeepyUppyArt.paint, at: .zero, height: r * 2, rotation: angle)
        FaceGameArt.stamp(ctx, FaceKeepyUppyArt.shade, at: .zero, height: r * 2)
        ctx.restoreGState()
    }
}

/// The beach ball: its coloured panels (which spin) and its light and shade (which stay put, because the light does).
enum FaceKeepyUppyArt {
    static var paint: CGImage? {
        FaceGameArt.sprite("keepy-paint", width: 160, height: 160) { ctx, _ in
            let c = CGPoint(x: 80, y: 80), r = 76.0
            let tones = [FaceGamePalette.coral, FaceGamePalette.cream, FaceGamePalette.sky, FaceGamePalette.sun, FaceGamePalette.cream, FaceGamePalette.mint]
            ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.clip()
            for (i, tone) in tones.enumerated() {
                // Panels curve from pole to pole like the seams of a real beach ball.
                let a0 = Double(i) / 6 * 2 * .pi, a1 = Double(i + 1) / 6 * 2 * .pi
                let panel = CGMutablePath()
                panel.move(to: c)
                panel.addQuadCurve(to: CGPoint(x: c.x + cos(a0) * r * 1.2, y: c.y + sin(a0) * r * 1.2),
                                   control: CGPoint(x: c.x + cos(a0 + 0.35) * r * 0.6, y: c.y + sin(a0 + 0.35) * r * 0.6))
                panel.addLine(to: CGPoint(x: c.x + cos(a1) * r * 1.2, y: c.y + sin(a1) * r * 1.2))
                panel.addQuadCurve(to: c, control: CGPoint(x: c.x + cos(a1 + 0.35) * r * 0.6, y: c.y + sin(a1 + 0.35) * r * 0.6))
                panel.closeSubpath()
                ctx.addPath(panel)
                ctx.setFillColor(FaceGamePaint.cg(tone))
                ctx.fillPath()
            }
            ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.cream))
            ctx.fillEllipse(in: CGRect(x: c.x - 12, y: c.y - 12, width: 24, height: 24))
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.ink, 0.25))
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: c.x - 12, y: c.y - 12, width: 24, height: 24))
        }
    }

    static var shade: CGImage? {
        FaceGameArt.sprite("keepy-shade", width: 160, height: 160) { ctx, _ in
            let c = CGPoint(x: 80, y: 80), r = 76.0
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.saveGState()
            ctx.addEllipse(in: rect)
            ctx.clip()
            let hot = CGPoint(x: c.x - r * 0.4, y: c.y + r * 0.42)
            let colors = [FaceGamePaint.cg(FaceGamePaint.Tone(1, 1, 1), 0.3), FaceGamePaint.cg(FaceGamePaint.Tone(1, 1, 1), 0),
                          FaceGamePaint.cg(FaceGamePalette.ink, 0.45)] as CFArray
            if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: colors, locations: [0, 0.45, 1]) {
                ctx.drawRadialGradient(g, startCenter: hot, startRadius: 0, endCenter: c, endRadius: r * 1.1, options: [.drawsAfterEndLocation])
            }
            ctx.restoreGState()
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.ink, 0.6))
            ctx.setLineWidth(3.5)
            ctx.strokeEllipse(in: rect.insetBy(dx: 1.5, dy: 1.5))
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 28, y: c.y + 34), width: 40, height: 20, rotation: 0.65, alpha: 0.85)
            FaceGameArt.highlight(ctx, center: CGPoint(x: c.x - 44, y: c.y + 14), width: 10, height: 8, alpha: 0.6)
        }
    }
}
