import AppKit
import CoreGraphics
import simd

/// A beach ball drops in from the top. Bounce it back up with your head, shoulders and hands and don't let it hit the floor.
///
/// Only a real hit counts: the ball bounces softly off a still body and rolls away, but when the part of you it touches is
/// *moving* it gets a proper kick upward. Each hit scores, a run of hits scores more, and a gold star hangs in the air now and
/// then for a bonus if you knock the ball through it. Three drops and it's over.
struct KeepyUppyGame: Game {
    static let title = "Keepy Uppy"
    static let hint = "Bump the ball up with your head and hands. Don't let it drop!"
    static let accent = SIMD3<Double>(0.45, 0.88, 0.62)

    static let startingLives = 3
    static let radius = 64.0
    static let gravity = 800.0
    /// How hard a hit sends the ball up, before the bonus for hitting hard.
    static let kickSpeed = 640.0
    /// Seconds the ball hovers, growing in, before it falls.
    static let serveSeconds = 1.1
    static let starRadius = 34.0
    /// Hits in a row for each extra point a hit is worth.
    static let streakStep = 5

    struct Star {
        var position: SIMD2<Double>
        var age = 0.0
        var life = 7.0
    }

    struct Ring {
        var position: SIMD2<Double>
        var age = 0.0
    }

    let size: CGSize
    private(set) var ball: SIMD2<Double>
    private(set) var velocity = SIMD2<Double>(0, 0)
    private(set) var spin = 0.0
    private(set) var angle = 0.0
    private(set) var lives = KeepyUppyGame.startingLives
    private(set) var score = 0
    private(set) var hits = 0
    private(set) var drops = 0
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var starsTaken = 0
    private(set) var star: Star?
    /// Seconds left before a served ball starts to fall.
    private(set) var serving = KeepyUppyGame.serveSeconds
    private(set) var elapsed = 0.0

    private var rng: SplitMix64
    private var sinceKick = 9.0
    private var sinceDrop = 99.0
    private var nextStar = 6.0
    private var squash = 1.0
    private var squashNormal = SIMD2<Double>(0, 1)
    private var trail: [SIMD2<Double>] = []
    private var rings: [Ring] = []
    private var sparkles = ParticleSystem(capacity: 300)
    private var floaters: [BodyFloater] = []
    private var bodyCenterX: Double?
    private var head: CGRect?
    private var finished = false

    var isOver: Bool { finished }
    var summary: String { streak >= 2 ? "Lives \(lives) · Streak \(streak)" : "Lives \(lives)" }

    /// Hearts, the run of hits in a row, and what the next hit is worth as the combo.
    var readout: GameUIReadout {
        GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), combo: hitValue > 1 ? hitValue : 0,
                      label: streak >= 2 ? "\(streak) in a row" : nil)
    }

    var result: GameUIResult {
        let line: String
        switch bestStreak {
        case 0...2: line = "Get under the ball and bump it straight up"
        case 3..<10: line = "Your best run was \(bestStreak) in a row"
        default: line = "\(bestStreak) in a row: a real keepy-uppy pro"
        }
        return GameUIResult(headline: "Dropped it!", line: line, stats: [("\(hits)", "hits"), ("\(bestStreak)", "best run"), ("\(starsTaken)", "stars")])
    }
    /// What the next hit is worth.
    var hitValue: Int { 1 + streak / Self.streakStep }
    /// Heavier as the game goes on, so the ball comes back quicker.
    var currentGravity: Double { Self.gravity * (1 + 0.3 * min(1, elapsed / 90)) }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        ball = SIMD2(size.width / 2, size.height - 120)
        sparkles.gravity = SIMD2(0, -500)
        sparkles.drag = 1.1
        BodyArtCache.warm("keepy") {
            _ = KeepyUppyArt.panels()
            _ = KeepyUppyArt.light()
            _ = KeepyUppyArt.star()
        }
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = bodyClamp(dt, 0, 0.1)
        elapsed += dt
        sinceKick += dt
        sinceDrop += dt
        squash = min(1, squash + dt * 3.5)
        advanceEffects(dt)
        advanceStar(dt)
        if let matte = world.matte, Int(elapsed * 30) % 6 == 0 {
            let scan = BodyScan(matte: matte, size: size, step: 32)
            if scan.present, let box = scan.box { bodyCenterX = Double(box.midX) }
            head = scan.headZone
        }
        if finished { return }

        if serving > 0 {
            serving -= dt
            angle += 0.6 * dt
            return
        }

        let speed = simd_length(velocity)
        let steps = max(1, Int(ceil(speed * dt / (Self.radius * 0.4))))
        let h = dt / Double(steps)
        for _ in 0..<steps {
            velocity.y -= currentGravity * h
            velocity *= (1 - 0.12 * h)
            ball += velocity * h
            bounceOffWalls()
            if let matte = world.matte { touch(matte, motion: world.motion) }
            if ball.y < -Self.radius * 1.2 {
                drop()
                return
            }
        }
        angle += spin * dt
        spin *= max(0, 1 - 0.6 * dt)
        trail.append(ball)
        if trail.count > 8 { trail.removeFirst(trail.count - 8) }
        collectStar()
    }

    private mutating func bounceOffWalls() {
        let r = Self.radius
        if ball.x < r { ball.x = r; velocity.x = abs(velocity.x) * 0.8; spin += velocity.y * 0.004 }
        if ball.x > size.width - r { ball.x = size.width - r; velocity.x = -abs(velocity.x) * 0.8; spin -= velocity.y * 0.004 }
        if ball.y > size.height - r { ball.y = size.height - r; velocity.y = -abs(velocity.y) * 0.55 }
    }

    /// Bounces the ball off you. A still body is soft; a moving one kicks.
    private mutating func touch(_ matte: MatteQuery, motion: MatteQuery?) {
        let r = Self.radius
        guard let contact = Silhouette.contact(center: ball, radius: r, in: matte) else { return }
        let n = contact.normal
        ball += n * contact.depth
        let approach = simd_dot(velocity, n)
        let at = ball - n * r
        // Three of nine points moving: a real bump moves a lot of outline, the flicker of a still cutout's edge does not.
        let moving = motion.map { BodySense.motionHits(at: at, radius: r * 0.8, in: $0) } ?? 0
        if moving >= 3, sinceKick > 0.2 {
            kick(normal: n, strength: Double(moving) / 9, at: at)
        } else if approach < 0 {
            // A soft bounce off something still: it loses most of its speed and rolls off.
            velocity -= (1 + 0.5) * approach * n
            velocity.x += n.x * 40
            spin += (velocity.x * n.y - velocity.y * n.x) * 0.002
        }
    }

    private mutating func kick(normal n: SIMD2<Double>, strength: Double, at point: SIMD2<Double>) {
        sinceKick = 0
        // Mostly up, leaning the way the surface faces, and a little back toward the middle so it stays in play.
        var heading = simd_normalize(SIMD2(n.x * 0.55, 1.0))
        heading.x += (size.width / 2 - ball.x) / size.width * 0.35
        heading = simd_normalize(heading)
        velocity = heading * (Self.kickSpeed + 220 * bodyClamp(strength, 0, 1))
        spin = -n.x * 6 + Double.random(in: -1.5...1.5, using: &rng)
        squash = 0.68
        squashNormal = n
        let value = hitValue
        hits += 1
        streak += 1
        bestStreak = max(bestStreak, streak)
        score += value
        rings.append(Ring(position: point))
        for _ in 0..<10 {
            let a = Double.random(in: 0.2...(.pi - 0.2), using: &rng)
            sparkles.emit(Particle(position: point, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 120...360, using: &rng),
                                   life: Double.random(in: 0.3...0.6, using: &rng), size: Double.random(in: 3...6, using: &rng)))
        }
        floaters.append(BodyFloater.placed("+\(value)", at: ball + SIMD2(n.x * 90, 40), size: size,
                                           color: value > 1 ? BodyGamePalette.gold : BodyGamePalette.cream, fontSize: value > 1 ? 52 : 44, life: 0.8,
                                           avoiding: head))
        if streak > 0, streak % Self.streakStep == 0 {
            floaters.append(BodyFloater.placed("\(streak) IN A ROW!", at: SIMD2(size.width / 2, 170), size: size, color: BodyGamePalette.gold,
                                               fontSize: 56, life: 1.2, rise: 30))
        }
    }

    private mutating func drop() {
        lives = max(0, lives - 1)
        drops += 1
        streak = 0
        sinceDrop = 0
        trail.removeAll()
        floaters.append(BodyFloater.placed("DROP!", at: SIMD2(ball.x, 80), size: size, color: BodyGamePalette.coral, fontSize: 60, life: 1.1, rise: 40))
        if lives == 0 {
            finished = true
            return
        }
        serve()
    }

    /// The next ball hovers above the player, grows in, then falls.
    private mutating func serve() {
        let middle = bodyCenterX ?? size.width / 2
        ball = SIMD2(bodyClamp(middle + Double.random(in: -90...90, using: &rng), 200, size.width - 200), size.height - 120)
        velocity = SIMD2(Double.random(in: -40...40, using: &rng), 0)
        spin = 0
        serving = Self.serveSeconds
    }

    private mutating func advanceStar(_ dt: Double) {
        if var current = star {
            current.age += dt
            star = current.age < current.life ? current : nil
        } else if !finished {
            nextStar -= dt
            if nextStar <= 0 {
                nextStar = Double.random(in: 7...11, using: &rng)
                star = Star(position: SIMD2(Double.random(in: 220...(size.width - 220), using: &rng),
                                            Double.random(in: (size.height * 0.62)...(size.height - 190), using: &rng)))
            }
        }
    }

    private mutating func collectStar() {
        guard let current = star, simd_distance(current.position, ball) < Self.radius + Self.starRadius else { return }
        star = nil
        starsTaken += 1
        score += 5
        for _ in 0..<24 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            sparkles.emit(Particle(position: current.position, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 160...460, using: &rng),
                                   life: Double.random(in: 0.4...0.8, using: &rng), size: Double.random(in: 4...8, using: &rng), kind: 1))
        }
        floaters.append(BodyFloater.placed("STAR +5", at: current.position + SIMD2(0, 40), size: size, color: BodyGamePalette.gold, fontSize: 54))
    }

    private mutating func advanceEffects(_ dt: Double) {
        sparkles.step(dt)
        for i in rings.indices { rings[i].age += dt }
        rings.removeAll { $0.age > 0.45 }
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll { $0.isDone }
    }

    // MARK: Test hooks

    /// Puts the ball somewhere with a heading, skipping any serve.
    mutating func place(ball position: SIMD2<Double>, velocity heading: SIMD2<Double>) {
        ball = position
        velocity = heading
        serving = 0
        trail.removeAll()
    }

    /// Hangs a star somewhere now.
    mutating func placeStar(at point: SIMD2<Double>) { star = Star(position: point) }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        if let star { drawStar(star, in: ctx, time: time) }
        drawShadow(in: ctx)
        for ring in rings {
            let t = ring.age / 0.45
            let radius = Self.radius * (0.5 + 1.3 * BodyEase.outCubic(t))
            ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.gold, CGFloat(0.9 * (1 - t))))
            ctx.setLineWidth(CGFloat(8 * (1 - t) + 1))
            ctx.strokeEllipse(in: CGRect(x: ring.position.x - radius, y: ring.position.y - radius, width: radius * 2, height: radius * 2))
        }
        drawBall(in: ctx, time: time)
        for p in sparkles.particles {
            ctx.setAlpha(CGFloat(1 - p.progress))
            if p.kind == 1 {
                ctx.addPath(BodyShapes.star(center: CGPoint(x: p.position.x, y: p.position.y), radius: CGFloat(p.size * 1.5), rotation: CGFloat(p.age * 5), inner: 0.42))
                ctx.setFillColor(BodyGamePalette.cg(BodyGamePalette.gold))
                ctx.fillPath()
            } else {
                ctx.fillCircle(center: CGPoint(x: p.position.x, y: p.position.y), radius: p.size, color: BodyGamePalette.cg(BodyGamePalette.cream))
            }
        }
        ctx.setAlpha(1)
        for floater in floaters { floater.draw(in: ctx) }
    }

    /// A shadow on the floor under the ball: small and faint when it is high, so you can judge where it will come down.
    private func drawShadow(in ctx: CGContext) {
        guard serving <= 0 else { return }
        let height = bodyClamp(ball.y / size.height, 0, 1)
        let w = Self.radius * (1.8 - 0.9 * height)
        BodyGlow.stamp(ctx, at: CGPoint(x: ball.x, y: 8), radius: CGFloat(w), red: 0.04, green: 0.02, blue: 0.1, alpha: 0.4 * (1 - height * 0.7))
    }

    private func drawBall(in ctx: CGContext, time: Double) {
        let r = Self.radius
        var grow = 1.0
        if serving > 0 {
            let t = 1 - serving / Self.serveSeconds
            grow = BodyEase.outBack(bodyClamp(t / 0.6, 0, 1))
            let ring = r * (1.2 + 1.6 * (1 - BodyEase.outCubic(t)))
            ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.cream, CGFloat(0.8 * t)))
            ctx.setLineWidth(4)
            ctx.setLineDash(phase: CGFloat(time * 40), lengths: [14, 10])
            ctx.strokeEllipse(in: CGRect(x: ball.x - ring, y: ball.y - ring, width: ring * 2, height: ring * 2))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        guard grow > 0.01, let panels = KeepyUppyArt.panels(), let light = KeepyUppyArt.light() else { return }
        // A faint trail when it is moving fast.
        let fast = bodyClamp((simd_length(velocity) - 500) / 600, 0, 1)
        if fast > 0 {
            for (i, p) in trail.dropLast().enumerated() {
                let k = Double(i + 1) / Double(max(1, trail.count))
                BodyGlow.stamp(ctx, at: CGPoint(x: p.x, y: p.y), radius: CGFloat(r * 0.9 * k), color: BodyGamePalette.cream, alpha: 0.22 * k * fast)
            }
        }
        let flat = squash >= 1 ? 1.0 : 0.68 + 0.32 * BodyEase.outElastic(bodyClamp((squash - 0.68) / 0.32, 0, 1))
        let tilt = atan2(squashNormal.y, squashNormal.x)
        ctx.saveGState()
        ctx.translateBy(x: ball.x, y: ball.y)
        ctx.rotate(by: CGFloat(tilt))
        ctx.scaleBy(x: CGFloat(flat), y: CGFloat(1 / sqrt(flat)))
        ctx.rotate(by: -CGFloat(tilt))
        let side = CGFloat(r * 2 * grow)
        // The panels turn with the ball; the light stays put, up and to the left.
        ctx.draw(panels, center: .zero, height: side, rotation: CGFloat(angle))
        ctx.draw(light, center: .zero, height: side)
        ctx.restoreGState()
    }

    private func drawStar(_ star: Star, in ctx: CGContext, time: Double) {
        let c = CGPoint(x: star.position.x, y: star.position.y)
        let appear = BodyEase.outBack(star.age / 0.45)
        let leaving = bodyClamp((star.life - star.age) / 0.6, 0, 1)
        let blink = star.life - star.age < 2 ? 0.75 + 0.25 * sin(time * 10) : 1
        let s = Self.starRadius * appear * leaving
        guard s > 1 else { return }
        BodyGlow.stamp(ctx, at: c, radius: CGFloat(s * 2.6), color: BodyGamePalette.gold, alpha: 0.5 * blink)
        if let sprite = KeepyUppyArt.star() {
            ctx.draw(sprite, center: CGPoint(x: c.x, y: c.y + 6 * sin(time * 2.4)), height: CGFloat(s * 2.4), rotation: CGFloat(sin(time * 1.7) * 0.2),
                     alpha: CGFloat(blink))
        }
    }
}

/// The beach ball, in two layers drawn once: the coloured panels, which spin, and the light and shade, which do not.
enum KeepyUppyArt {
    /// "Seaside": the panels of a classic beach ball, pulled off pure primaries.
    static let panelColours: [NSColor] = [
        NSColor(red: 0.95, green: 0.32, blue: 0.36, alpha: 1),
        NSColor(red: 1.00, green: 0.97, blue: 0.92, alpha: 1),
        NSColor(red: 0.28, green: 0.62, blue: 0.97, alpha: 1),
        NSColor(red: 1.00, green: 0.82, blue: 0.28, alpha: 1),
        NSColor(red: 0.32, green: 0.80, blue: 0.56, alpha: 1),
        NSColor(red: 1.00, green: 0.97, blue: 0.92, alpha: 1),
    ]

    /// The panels as they really sit on a sphere: each one a slice between two meridians running from a pole tipped toward the
    /// viewer, seen straight on, so the seams curve the way a real ball's do.
    static func panels() -> CGImage? {
        BodyArtCache.image("keepy-ball-panels", width: 160, height: 160) { ctx in
            let c = CGPoint(x: 80, y: 80), R = 76.0
            ctx.addEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
            ctx.clip()
            let pole = simd_normalize(SIMD3<Double>(-0.34, 0.44, 0.83))
            let e1 = simd_normalize(simd_cross(pole, SIMD3<Double>(0, 0, 1))), e2 = simd_cross(pole, e1)
            func project(_ v: SIMD3<Double>) -> CGPoint { CGPoint(x: c.x + v.x * R, y: c.y + v.y * R) }
            func meridian(_ phi: Double, _ t: Double) -> SIMD3<Double> {
                cos(t) * pole + sin(t) * (cos(phi) * e1 + sin(phi) * e2)
            }
            /// The front half of a meridian, from the pole to where it goes round the rim, and the angle of that point on the rim.
            func front(_ phi: Double) -> (points: [CGPoint], rim: Double) {
                var points: [CGPoint] = []
                var last = meridian(phi, 0)
                for k in 0...60 {
                    let v = meridian(phi, Double(k) / 60 * .pi)
                    if v.z < 0 {
                        let f = last.z / (last.z - v.z)
                        let edge = last + (v - last) * f
                        points.append(project(edge))
                        return (points, atan2(edge.y, edge.x))
                    }
                    points.append(project(v))
                    last = v
                }
                return (points, atan2(last.y, last.x))
            }
            let count = panelColours.count
            for i in 0..<count {
                let a = front(Double(i) / Double(count) * 2 * .pi), b = front(Double(i + 1) / Double(count) * 2 * .pi)
                let path = CGMutablePath()
                path.addLines(between: a.points)
                // Round the outside of the rim, the short way, from one meridian's end to the next; the clip trims it to the ball.
                var sweep = b.rim - a.rim
                while sweep > .pi { sweep -= 2 * .pi }
                while sweep < -.pi { sweep += 2 * .pi }
                for k in 0...12 {
                    let angle = a.rim + sweep * Double(k) / 12
                    path.addLine(to: CGPoint(x: c.x + cos(angle) * R * 1.3, y: c.y + sin(angle) * R * 1.3))
                }
                for p in b.points.reversed() { path.addLine(to: p) }
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(BodyGamePalette.cg(panelColours[i]))
                ctx.fillPath()
            }
            // The round cap over the pole, and its rim.
            let cap = CGMutablePath()
            for k in 0...40 {
                let p = project(meridian(Double(k) / 40 * 2 * .pi, 0.2))
                if k == 0 { cap.move(to: p) } else { cap.addLine(to: p) }
            }
            cap.closeSubpath()
            ctx.addPath(cap)
            ctx.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.92, alpha: 1))
            ctx.fillPath()
            ctx.addPath(cap)
            ctx.setStrokeColor(CGColor(red: 0.62, green: 0.58, blue: 0.56, alpha: 0.8))
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }
    }

    static func light() -> CGImage? {
        BodyArtCache.image("keepy-ball-light", width: 160, height: 160) { ctx in
            let c = CGPoint(x: 80, y: 80), R: CGFloat = 76
            let disc = CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)
            ctx.saveGState()
            ctx.addEllipse(in: disc)
            ctx.clip()
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let shade = [CGColor(red: 1, green: 1, blue: 1, alpha: 0.28), CGColor(red: 0, green: 0, blue: 0.05, alpha: 0),
                         CGColor(red: 0.02, green: 0, blue: 0.08, alpha: 0.5)] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: shade, locations: [0, 0.45, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - R * 0.35, y: c.y + R * 0.4), startRadius: 0, endCenter: c, endRadius: R * 1.15,
                                       options: [.drawsAfterEndLocation])
            }
            ctx.glow(center: CGPoint(x: c.x + R * 0.7, y: c.y - R * 0.7), radius: R * 0.6, red: 1, green: 0.95, blue: 0.85, alpha: 0.25)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.translateBy(x: c.x - R * 0.38, y: c.y + R * 0.44)
            ctx.rotate(by: 0.7)
            ctx.glow(center: .zero, radius: R * 0.4, red: 1, green: 1, blue: 1, alpha: 0.45)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
            ctx.fillEllipse(in: CGRect(x: -R * 0.22, y: -R * 0.08, width: R * 0.44, height: R * 0.16))
            ctx.restoreGState()
            ctx.addEllipse(in: disc.insetBy(dx: 1.5, dy: 1.5))
            ctx.setStrokeColor(CGColor(red: 0.1, green: 0.08, blue: 0.18, alpha: 0.55))
            ctx.setLineWidth(3)
            ctx.strokePath()
        }
    }

    /// The bonus star: a fat, faceted gold star.
    static func star() -> CGImage? {
        BodyArtCache.image("keepy-star", width: 128, height: 124) { ctx in
            let c = CGPoint(x: 64, y: 60), R: CGFloat = 54
            let shape = BodyShapes.star(center: c, radius: R, inner: 0.5)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 6, color: CGColor(red: 0.3, green: 0.15, blue: 0, alpha: 0.45))
            ctx.addPath(shape)
            ctx.setFillColor(CGColor(red: 0.95, green: 0.62, blue: 0.12, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
            for i in 0..<5 {
                let a = CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / 5
                let tip = CGPoint(x: c.x + cos(a) * R, y: c.y + sin(a) * R)
                for side in [-1.0, 1.0] {
                    let b = a + CGFloat(side) * .pi / 5
                    let valley = CGPoint(x: c.x + cos(b) * R * 0.5, y: c.y + sin(b) * R * 0.5)
                    let mx = (tip.x + valley.x) / 2 - c.x, my = (tip.y + valley.y) / 2 - c.y
                    let lit = max(0, (-mx * 0.7 + my * 0.7) / R)
                    ctx.move(to: c)
                    ctx.addLine(to: tip)
                    ctx.addLine(to: valley)
                    ctx.closePath()
                    ctx.setFillColor(CGColor(red: 1, green: 0.7 + 0.26 * lit, blue: 0.16 + 0.5 * lit, alpha: 1))
                    ctx.fillPath()
                }
            }
            ctx.addPath(shape)
            ctx.setStrokeColor(CGColor(red: 1, green: 0.97, blue: 0.82, alpha: 0.95))
            ctx.setLineWidth(3)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
    }
}
