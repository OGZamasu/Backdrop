import AppKit
import CoreGraphics
import simd

/// Throwing stars fly in from the sides at you. A glint at the edge and a dashed line show each one coming. Swat it with a quick move
/// as it arrives (the part of you it reaches must be moving) to knock it away, or get out of its path. If it reaches a part of you
/// that is standing still, it hits. Three hits and you're out.
struct NinjaStarsGame: Game {
    static let title = "Ninja Stars"
    static let hint = "Swat the stars away with quick moves!"
    static let accent = SIMD3<Double>(1.0, 0.5, 0.48)

    static let startingLives = 3
    static let graceSeconds = 1.3
    static let radius = 30.0
    static let blockPoints = 2
    static let dodgePoints = 1

    struct Star {
        var from: SIMD2<Double>
        var to: SIMD2<Double>
        /// Seconds of warning (the glint and the dashed line) before it is thrown.
        var telegraph: Double
        /// Pixels a second once thrown.
        var speed: Double
        var spin: Double
        var age = 0.0
        var position: SIMD2<Double>

        var heading: SIMD2<Double> { simd_normalize(to - from) }
        var thrown: Bool { age >= telegraph }
    }

    /// A star knocked away, spinning off.
    struct Ricochet {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var spin: Double
        var age = 0.0
    }

    struct Clang {
        var position: SIMD2<Double>
        var blocked: Bool
        var age = 0.0
    }

    let size: CGSize
    private(set) var stars: [Star] = []
    private(set) var lives = NinjaStarsGame.startingLives
    private(set) var score = 0
    private(set) var blocks = 0
    private(set) var dodges = 0
    private(set) var hits = 0
    private(set) var thrown = 0
    private(set) var graceLeft = 0.0
    private(set) var elapsed = 0.0

    private var rng: SplitMix64
    private var nextThrow = 1.2
    private var throwing = true
    private var sinceScan = 9.0
    private var sinceHit = 99.0
    private var flash = 0.0
    private var bodyPoints: [CGPoint] = []
    private var head: CGRect?
    private var ricochets: [Ricochet] = []
    private var clangs: [Clang] = []
    private var sparks = ParticleSystem(capacity: 300)
    private var floaters: [BodyFloater] = []

    var isOver: Bool { lives <= 0 }
    var summary: String { "Lives \(lives) · Blocks \(blocks)" }

    var readout: GameUIReadout { GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), label: "Blocks \(blocks)") }

    var result: GameUIResult {
        let line: String
        switch blocks {
        case 0: line = "Swing a hand fast through a star to swat it"
        case 1..<12: line = "Quick hands! Swat them before they land"
        default: line = "A true ninja master"
        }
        return GameUIResult(headline: "Out of lives", line: line,
                            stats: [("\(blocks)", "swatted"), ("\(dodges)", "dodged"), (String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60), "survived")])
    }
    var difficulty: Double { min(1, elapsed / 80) }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        sparks.gravity = SIMD2(0, -700)
        sparks.drag = 0.8
        BodyArtCache.warm("ninja") { _ = NinjaStarArt.star() }
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = bodyClamp(dt, 0, 0.1)
        elapsed += dt
        graceLeft = max(0, graceLeft - dt)
        sinceHit += dt
        flash = max(0, flash - dt)
        look(at: world.matte, dt)

        if throwing {
            nextThrow -= dt
            if nextThrow <= 0 {
                let most = 2 + Int(difficulty * 2)
                if stars.count < most { aim() }
                nextThrow = (1.7 - 1.0 * difficulty) * Double.random(in: 0.8...1.2, using: &rng)
            }
        }

        var kept: [Star] = []
        for var star in stars {
            star.age += dt
            var gone = false
            if star.thrown {
                let travel = star.speed * min(dt, star.age - star.telegraph)
                let looks = max(1, Int((travel / (Self.radius * 0.6)).rounded(.up)))
                for _ in 0..<looks {
                    star.position += star.heading * (travel / Double(looks))
                    if let matte = world.matte, BodySense.bodyHits(at: star.position, radius: Self.radius * 0.8, in: matte) >= 2 {
                        meet(star, motion: world.motion)
                        gone = true
                        break
                    }
                }
                if !gone, isOff(star.position) {
                    dodges += 1
                    score += Self.dodgePoints
                    gone = true
                }
            }
            if !gone { kept.append(star) }
        }
        stars = kept

        for i in ricochets.indices {
            ricochets[i].age += dt
            ricochets[i].velocity.y -= 900 * dt
            ricochets[i].position += ricochets[i].velocity * dt
        }
        ricochets.removeAll { $0.age > 1 }
        for i in clangs.indices { clangs[i].age += dt }
        clangs.removeAll { $0.age > 0.45 }
        sparks.step(dt)
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll { $0.isDone }
    }

    private func isOff(_ p: SIMD2<Double>) -> Bool {
        p.x < -60 || p.x > size.width + 60 || p.y < -60 || p.y > size.height + 60
    }

    private mutating func look(at matte: MatteQuery?, _ dt: Double) {
        sinceScan += dt
        guard sinceScan >= 0.15 else { return }
        sinceScan = 0
        let scan = BodyScan(matte: matte, size: size, step: 24)
        head = scan.headZone
        // Aimed at shoulders, arms and chest, never the face.
        let face = head?.insetBy(dx: -30, dy: -30)
        bodyPoints = scan.present ? scan.solidPoints(every: 2).filter { $0.y > 60 && $0.y < size.height - 150 && !(face?.contains($0) ?? false) } : []
    }

    /// Picks a spot on the player and an edge to throw from, with a clear line between them.
    private mutating func aim() {
        var target: SIMD2<Double>
        if bodyPoints.isEmpty {
            target = SIMD2(size.width / 2 + Double.random(in: -200...200, using: &rng), Double.random(in: 180...480, using: &rng))
        } else {
            let p = bodyPoints[Int.random(in: 0..<bodyPoints.count, using: &rng)]
            target = SIMD2(Double(p.x), Double(p.y))
        }
        let left = Bool.random(using: &rng)
        let fromY = bodyClamp(target.y + Double.random(in: -160...200, using: &rng), 90, size.height - 170)
        let from = SIMD2(left ? -40.0 : size.width + 40, fromY)
        // Aim through the target and on, so a star you dodge flies off the other side.
        let way = simd_normalize(target - from)
        let to = from + way * (size.width * 2)
        let telegraph = 0.85 - 0.3 * difficulty
        let speed = 620 + 380 * difficulty
        stars.append(Star(from: from, to: to, telegraph: telegraph, speed: speed, spin: (left ? -1 : 1) * Double.random(in: 14...20, using: &rng),
                          position: from))
        thrown += 1
    }

    /// A star reaching the player: knocked away if that part of them is moving (three of nine points round it, so the flicker along a
    /// still cutout's edge is not enough), a hit if it is still.
    private mutating func meet(_ star: Star, motion: MatteQuery?) {
        let at = star.position
        let moving = motion.map { BodySense.motionHits(at: at, radius: Self.radius * 1.4, in: $0) } ?? 0
        if moving >= 3 {
            blocks += 1
            score += Self.blockPoints
            clangs.append(Clang(position: at, blocked: true))
            let back = star.heading * -1
            ricochets.append(Ricochet(position: at, velocity: SIMD2(back.x * 420, 380 + Double.random(in: 0...200, using: &rng)), spin: star.spin * 1.6))
            for _ in 0..<16 {
                let a = atan2(back.y, back.x) + Double.random(in: -1.2...1.2, using: &rng)
                sparks.emit(Particle(position: at, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 200...560, using: &rng),
                                     life: Double.random(in: 0.2...0.5, using: &rng), size: Double.random(in: 2...4, using: &rng)))
            }
            floaters.append(BodyFloater.placed("BLOCK +\(Self.blockPoints)", at: at + SIMD2(back.x * 70, 50), size: size, color: BodyGamePalette.sky,
                                               fontSize: 44, life: 0.8, avoiding: head))
        } else if graceLeft > 0 {
            // Just after a hit, stars glance off harmlessly.
            clangs.append(Clang(position: at, blocked: true))
        } else {
            hits += 1
            lives = max(0, lives - 1)
            graceLeft = Self.graceSeconds
            sinceHit = 0
            flash = 0.5
            clangs.append(Clang(position: at, blocked: false))
            for _ in 0..<12 {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                sparks.emit(Particle(position: at, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 80...300, using: &rng),
                                     life: Double.random(in: 0.3...0.6, using: &rng), size: Double.random(in: 4...8, using: &rng), kind: 1))
            }
            floaters.append(BodyFloater.placed("OUCH!", at: at + SIMD2(0, 60), size: size, color: BodyGamePalette.coral, fontSize: 58, avoiding: head))
        }
    }

    // MARK: Test hooks

    /// Stops stars from being thrown on their own.
    mutating func holdThrows() { throwing = false }

    /// Throws a star now from `from`, through `target` and on.
    mutating func throwStar(from: SIMD2<Double>, through target: SIMD2<Double>, telegraph: Double = 0.5, speed: Double = 700) {
        let to = from + simd_normalize(target - from) * (size.width * 2)
        stars.append(Star(from: from, to: to, telegraph: telegraph, speed: speed, spin: 16, position: from))
        thrown += 1
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        for star in stars where !star.thrown { drawWarning(star, in: ctx, time: time) }
        for clang in clangs {
            let t = clang.age / 0.45
            let r = Self.radius * (0.8 + 2.4 * BodyEase.outCubic(t))
            let colour = clang.blocked ? BodyGamePalette.cream : BodyGamePalette.coral
            ctx.setStrokeColor(BodyGamePalette.cg(colour, CGFloat(0.9 * (1 - t))))
            ctx.setLineWidth(CGFloat(7 * (1 - t) + 1))
            ctx.strokeEllipse(in: CGRect(x: clang.position.x - r, y: clang.position.y - r, width: r * 2, height: r * 2))
            if clang.age < 0.08 { BodyGlow.stamp(ctx, at: CGPoint(x: clang.position.x, y: clang.position.y), radius: CGFloat(Self.radius * 2.2), red: 1, green: 1, blue: 0.95, alpha: 0.9) }
        }
        for star in stars where star.thrown { drawStar(star.position, angle: star.spin * star.age, heading: star.heading, in: ctx) }
        for r in ricochets {
            ctx.setAlpha(CGFloat(bodyClamp((1 - r.age) / 0.4, 0, 1)))
            drawStar(r.position, angle: r.spin * r.age, heading: nil, in: ctx)
            ctx.setAlpha(1)
        }
        for p in sparks.particles {
            ctx.setAlpha(CGFloat(1 - p.progress))
            let colour = p.kind == 1 ? BodyGamePalette.coral.bodyShade(0.3) : CGColor(red: 1, green: 0.9, blue: 0.6, alpha: 1)
            ctx.fillCircle(center: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 - 0.5 * p.progress), color: colour)
        }
        ctx.setAlpha(1)
        for floater in floaters { floater.draw(in: ctx) }
        BodyGameHUD.flash(ctx, size: size, strength: flash / 0.5 * 0.6)
    }

    /// The glint at the edge where a star is about to come from, and a dashed line along its path.
    private func drawWarning(_ star: Star, in ctx: CGContext, time: Double) {
        let t = bodyClamp(star.age / star.telegraph, 0, 1)
        let edge = SIMD2(bodyClamp(star.from.x, 18, size.width - 18), star.from.y)
        let reach = min(520.0, size.width * 0.45)
        let end = edge + star.heading * reach * BodyEase.outCubic(t / 0.5)
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: CGFloat(-time * 90), lengths: [10, 14])
        ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.ink, 0.3))
        ctx.setLineWidth(7)
        ctx.move(to: CGPoint(x: edge.x, y: edge.y))
        ctx.addLine(to: CGPoint(x: end.x, y: end.y))
        ctx.strokePath()
        ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.cream, CGFloat(0.35 + 0.45 * t)))
        ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: edge.x, y: edge.y))
        ctx.addLine(to: CGPoint(x: end.x, y: end.y))
        ctx.strokePath()
        ctx.restoreGState()
        // The glint: a four-point sparkle that grows and turns as the throw comes.
        let s = 18 + 26 * BodyEase.outBack(t)
        let at = CGPoint(x: edge.x, y: edge.y)
        BodyGlow.stamp(ctx, at: at, radius: CGFloat(s * 1.6), red: 1, green: 0.95, blue: 0.8, alpha: 0.7)
        ctx.addPath(BodyShapes.star(center: at, radius: CGFloat(s), rotation: CGFloat(time * 2), inner: 0.18))
        ctx.setFillColor(CGColor(red: 1, green: 0.98, blue: 0.9, alpha: 0.95))
        ctx.fillPath()
    }

    private func drawStar(_ p: SIMD2<Double>, angle: Double, heading: SIMD2<Double>?, in ctx: CGContext) {
        guard let sprite = NinjaStarArt.star() else { return }
        let c = CGPoint(x: p.x, y: p.y), side = CGFloat(Self.radius * 2.4)
        if let heading {
            // A blur of the spin behind it.
            for k in 1...3 {
                let back = CGPoint(x: c.x - heading.x * Double(k) * 16, y: c.y - heading.y * Double(k) * 16)
                ctx.draw(sprite, center: back, height: side, rotation: CGFloat(angle - Double(k) * 0.35), alpha: CGFloat(0.28 / Double(k)))
            }
        }
        // A cool rim of light behind it, so steel reads on a dark backdrop, and a soft shadow so it reads on a light one.
        BodyGlow.stamp(ctx, at: CGPoint(x: c.x + 4, y: c.y - 6), radius: side * 0.7, red: 0.04, green: 0.02, blue: 0.1, alpha: 0.4)
        BodyGlow.stamp(ctx, at: c, radius: side * 0.75, red: 0.75, green: 0.88, blue: 1, alpha: 0.35)
        ctx.draw(sprite, center: c, height: side, rotation: CGFloat(angle))
    }
}

/// The throwing star, drawn once: four steel blades, each with a lit half and a shaded half, round a ringed hub.
enum NinjaStarArt {
    static func star() -> CGImage? {
        BodyArtCache.image("ninja-star", width: 128, height: 128) { ctx in
            let c = CGPoint(x: 64, y: 64), R: CGFloat = 58, waist: CGFloat = 16
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 3, color: CGColor(red: 0, green: 0, blue: 0.05, alpha: 0.6))
            let outline = CGMutablePath()
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4
                let r = i % 2 == 0 ? R : waist
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { outline.move(to: p) } else { outline.addLine(to: p) }
            }
            outline.closeSubpath()
            ctx.addPath(outline)
            ctx.setFillColor(CGColor(red: 0.4, green: 0.42, blue: 0.5, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
            // Each blade: two facets, the one facing the top left bright.
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 2
                let tip = CGPoint(x: c.x + cos(a) * R, y: c.y + sin(a) * R)
                for side in [-1.0, 1.0] {
                    let b = a + CGFloat(side) * .pi / 4
                    let notch = CGPoint(x: c.x + cos(b) * waist, y: c.y + sin(b) * waist)
                    let mid = CGPoint(x: (tip.x + notch.x) / 2 - c.x, y: (tip.y + notch.y) / 2 - c.y)
                    let lit = max(0, (-mid.x + mid.y) / (R * 0.7)) * 0.5 + (side > 0 ? 0.25 : 0)
                    ctx.move(to: c)
                    ctx.addLine(to: tip)
                    ctx.addLine(to: notch)
                    ctx.closePath()
                    let v = 0.55 + 0.42 * min(1, lit)
                    ctx.setFillColor(CGColor(red: v, green: v * 1.02, blue: min(1, v * 1.12), alpha: 1))
                    ctx.fillPath()
                }
            }
            // A bright edge on every blade.
            ctx.addPath(outline)
            ctx.setStrokeColor(CGColor(red: 0.92, green: 0.95, blue: 1, alpha: 0.75))
            ctx.setLineWidth(1.5)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            // The hub: a dark ring with a hole.
            ctx.setFillColor(CGColor(red: 0.18, green: 0.18, blue: 0.24, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - 13, y: c.y - 13, width: 26, height: 26))
            ctx.setFillColor(CGColor(red: 0.7, green: 0.72, blue: 0.8, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18))
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
        }
    }
}
