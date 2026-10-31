import AppKit
import CoreGraphics
import simd

/// A heavy bag hangs beside you on a chain. Swing an arm into it to knock it about: it swings away and comes back for more.
/// Harder swings (more of you moving through the bag) score more, and quick hits in a row build a combo. 40 seconds a round.
///
/// The bag hangs from a trolley on a ceiling rail, so between rounds of hitting it rolls along to stay beside you, on whichever side
/// has more room, and at your shoulder height, sized from how big your head is.
struct PunchingBagGame: Game {
    static let title = "Punching Bag"
    static let hint = "Swing your arms into the bag. Hit it hard and fast!"
    static let accent = SIMD3<Double>(1.0, 0.5, 0.42)

    static let roundSeconds = 40.0
    /// Seconds after a hit before the bag can be hit again, so one swing is one hit.
    static let cooldown = 0.28
    static let comboWindow = 1.3
    static let gravity = 1700.0
    static let damping = 0.55
    /// Motion samples (of fifteen across the bag) a swing must cover to count.
    static let hitSamples = 3

    /// A comic word or a number thrown off by a hit.
    struct Burst {
        var text: String
        var position: SIMD2<Double>
        var big: Bool
        var tilt: Double
        var age = 0.0
    }

    let size: CGSize
    /// Where the chain hangs from, on the rail just above the picture.
    private(set) var anchorX: Double
    /// The swing: radians from straight down, positive toward the right, and how fast it is changing.
    private(set) var angle = 0.0
    private(set) var spin = 0.0
    private(set) var score = 0
    private(set) var hits = 0
    private(set) var bigHits = 0
    private(set) var combo = 0
    private(set) var timeLeft = PunchingBagGame.roundSeconds
    private(set) var lastStrength = 0.0
    /// The bag's size and where it hangs, following the player.
    private(set) var bagWidth = 150.0
    private(set) var bagCenterY = 330.0

    private var rng: SplitMix64
    private var sinceHit = 9.0
    private var dent = 0.0
    private var dentSide = 1.0
    private var targetX: Double
    private var sinceScan = 9.0
    private var bodyX: Double?
    private var head: CGRect?
    private var bursts: [Burst] = []
    private var dust = ParticleSystem(capacity: 200)
    private var comboAge = 99.0

    var isOver: Bool { timeLeft <= 0 }
    var summary: String { "\(Int(timeLeft.rounded(.up)))s" }

    var readout: GameUIReadout {
        GameUIReadout(score: score, time: (max(0, timeLeft), Self.roundSeconds), combo: multiplier > 1 ? multiplier : 0,
                      label: combo >= 2 ? "\(combo) hits" : nil)
    }

    var result: GameUIResult {
        let line: String
        switch hits {
        case 0..<10: line = "Swing right through the bag, fast"
        case 10..<40: line = "Strong! Keep the hits coming for a combo"
        default: line = "The bag never stood a chance"
        }
        return GameUIResult(headline: "Time's up!", line: line, stats: [("\(hits)", "hits"), ("\(bigHits)", "big hits"), ("\(score)", "points")],
                            kind: .timeUp)
    }
    var multiplier: Int { 1 + min(3, combo / 4) }
    var bagHeight: Double { bagWidth * 2.125 }
    /// How far above the bag's middle its strap ring is, where the chain ends.
    var ringHeight: Double { bagWidth * 1.74 }
    /// From the rail to the middle of the bag.
    var length: Double { max(80, size.height + 10 - bagCenterY) }
    var bagCenter: SIMD2<Double> { SIMD2(anchorX + sin(angle) * length, size.height + 10 - cos(angle) * length) }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        anchorX = size.width * 0.26
        targetX = anchorX
        bagCenterY = size.height * 0.46
        dust.gravity = SIMD2(0, -200)
        dust.drag = 2
        BodyArtCache.warm("bag") {
            _ = PunchingBagArt.bag()
            _ = PunchingBagArt.trolley()
        }
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = bodyClamp(dt, 0, 0.1)
        timeLeft = max(0, timeLeft - dt)
        sinceHit += dt
        comboAge += dt
        dent = max(0, dent - dt / 0.3)
        if sinceHit > Self.comboWindow { combo = 0 }
        follow(world.matte, dt)
        swing(dt)
        if let motion = world.motion, sinceHit >= Self.cooldown { punch(motion, matte: world.matte) }
        if let matte = world.matte { bump(matte, motion: world.motion) }
        dust.step(dt)
        for i in bursts.indices { bursts[i].age += dt }
        bursts.removeAll { $0.age > 0.8 }
    }

    /// Keeps the bag beside the player: sized from their head, at their shoulder height, on the side with more room.
    private mutating func follow(_ matte: MatteQuery?, _ dt: Double) {
        sinceScan += dt
        if sinceScan >= 0.15 {
            sinceScan = 0
            let scan = BodyScan(matte: matte, size: size, step: 24)
            head = scan.headZone
            if let frame = BodyFrame(scan: scan) {
                let u = max(90, frame.headWidth)
                bagWidth += (bodyClamp(0.95 * u, 110, 180) - bagWidth) * 0.25
                let wanted = bodyClamp(frame.shoulderY + 0.35 * u, bagHeight / 2 + 30, size.height - ringHeight - 40)
                bagCenterY += (wanted - bagCenterY) * 0.25
                bodyX = frame.centerX
                let gap = frame.width / 2 + bagWidth / 2 + 0.15 * u
                let right = frame.centerX + gap, left = frame.centerX - gap
                let roomRight = size.width - right, roomLeft = left
                // The left is home: the top right of the picture holds the game's summary. Stay on the current side unless the other
                // has clearly more room, or this one has too little for the bag.
                let onRight = anchorX >= frame.centerX
                let tooTight = bagWidth + 60
                var pickRight = onRight ? roomRight > roomLeft - 120 : roomRight > roomLeft + 200
                if roomLeft < tooTight, roomRight > roomLeft { pickRight = true }
                if roomRight < tooTight, roomLeft > roomRight { pickRight = false }
                targetX = bodyClamp(pickRight ? right : left, bagWidth / 2 + 40, size.width - bagWidth / 2 - 40)
            }
        }
        // The trolley only rolls while the bag is nearly still, so a swing is never yanked about.
        if abs(spin) < 0.6, abs(angle) < 0.25 {
            let gap = targetX - anchorX
            anchorX += bodyClamp(gap * 3 * dt, -260 * dt, 260 * dt)
        }
    }

    private mutating func swing(_ dt: Double) {
        let steps = 2
        let h = dt / Double(steps)
        for _ in 0..<steps {
            let pull = -(Self.gravity / length) * sin(angle) - Self.damping * spin
            spin += pull * h
            angle += spin * h
        }
        if abs(angle) > 1.0 { angle = angle > 0 ? 1.0 : -1.0; spin = -spin * 0.3 }
    }

    /// Points spread over the bag, in the picture, with how far across the bag each one is (-1 left edge, 1 right edge).
    private func samples() -> [(point: SIMD2<Double>, across: Double)] {
        let c = bagCenter, w = bagWidth, hgt = bagHeight
        let along = SIMD2(sin(angle), -cos(angle)), side = SIMD2(cos(angle), sin(angle))
        var out: [(SIMD2<Double>, Double)] = []
        for row in 0..<5 {
            let v = (Double(row) / 4 - 0.5) * hgt * 0.84
            for column in 0..<3 {
                let a = Double(column) - 1
                out.append((c + along * v + side * a * w * 0.38, a))
            }
        }
        return out
    }

    private mutating func punch(_ motion: MatteQuery, matte: MatteQuery?) {
        var count = 0, across = 0.0
        var hitPoint = SIMD2<Double>(0, 0)
        for s in samples() where motion.coverage(x: s.point.x, y: s.point.y) > 0.5 {
            count += 1
            across += s.across
            hitPoint += s.point
        }
        guard count >= Self.hitSamples else { return }
        hitPoint /= Double(count)
        across /= Double(count)
        // Pushed away from the side the swing came in on; straight on, away from the player.
        var way: Double = across < -0.15 ? 1 : across > 0.15 ? -1 : 0
        if way == 0 { way = bagCenter.x >= (bodyX ?? size.width / 2) ? 1 : -1 }
        let strength = bodyClamp(Double(count - 2) / 9, 0.15, 1)
        spin += way * (0.4 + 0.9 * strength) * (420 / length).squareRoot()
        sinceHit = 0
        combo += 1
        hits += 1
        lastStrength = strength
        dent = 1
        dentSide = -way
        let before = multiplier
        let points = (5 + Int((15 * strength).rounded())) * multiplier
        score += points
        if multiplier > before { comboAge = 0 }
        // Words go out past the far side of the bag; with no room there, beside its lower half on the near side, below any face.
        var outward = SIMD2(way * (bagWidth * 0.75 + 70), 30)
        let far = bagCenter.x + outward.x
        if far < 150 || far > size.width - 150 { outward = SIMD2(-way * (bagWidth * 0.75 + 70), -bagHeight * 0.3) }
        if strength > 0.62 {
            bigHits += 1
            let words = ["POW!", "WHAM!", "BAM!", "BOOM!", "THWACK!"]
            bursts.append(Burst(text: words[Int.random(in: 0..<words.count, using: &rng)], position: clear(bagCenter + outward + SIMD2(0, 40)), big: true,
                                tilt: Double.random(in: -0.25...0.25, using: &rng)))
        }
        bursts.append(Burst(text: "+\(points)", position: clear(bagCenter + outward - SIMD2(0, strength > 0.62 ? 50 : 0)), big: false, tilt: 0))
        for _ in 0..<Int(8 + 14 * strength) {
            let a = atan2(0.4, way) + Double.random(in: -0.9...0.9, using: &rng)
            dust.emit(Particle(position: hitPoint, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 80...320, using: &rng),
                               life: Double.random(in: 0.35...0.7, using: &rng), size: Double.random(in: 4...10, using: &rng)))
        }
    }

    /// A spot for words that is not on the player's face: moved down below the chin if it would be.
    private func clear(_ p: SIMD2<Double>) -> SIMD2<Double> {
        guard let head else { return p }
        let zone = head.insetBy(dx: -90, dy: -40)
        guard zone.contains(CGPoint(x: p.x, y: p.y)) else { return p }
        return SIMD2(p.x, Double(zone.minY) - 20)
    }

    /// The bag thuds off a still part of the player instead of swinging through them.
    private mutating func bump(_ matte: MatteQuery, motion: MatteQuery?) {
        var solid = 0, side = 0.0
        for s in samples() where matte.coverage(x: s.point.x, y: s.point.y) > 0.5 {
            solid += 1
            side += s.across
        }
        guard solid >= 4 else { return }
        // Swinging toward the side the body is on: send it back, softly.
        let toward = side < 0 ? -1.0 : 1.0
        if spin * toward > 0.15 {
            spin = -spin * 0.35
            dent = max(dent, 0.6)
            dentSide = toward
        }
    }

    // MARK: Test hooks

    /// Moves the bag's rail mount now, without rolling there.
    mutating func hang(at x: Double, centerY: Double, width: Double) {
        anchorX = x
        targetX = x
        bagCenterY = centerY
        bagWidth = width
        angle = 0
        spin = 0
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        let anchor = CGPoint(x: anchorX, y: size.height + 10)
        let top = CGPoint(x: anchorX + sin(angle) * (length - ringHeight), y: size.height + 10 - cos(angle) * (length - ringHeight))
        drawChain(from: anchor, to: top, in: ctx)
        if let trolley = PunchingBagArt.trolley() { ctx.draw(trolley, center: CGPoint(x: anchor.x, y: size.height - 14), height: 44) }

        if let bag = PunchingBagArt.bag() {
            let c = bagCenter
            let squash = 0.1 * BodyEase.outCubic(dent)
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: CGFloat(angle))
            // A dent on the side that was hit: squashed across, a touch taller, and pushed over.
            ctx.translateBy(x: CGFloat(-dentSide * squash * bagWidth * 0.3), y: 0)
            ctx.scaleBy(x: CGFloat(1 - squash), y: CGFloat(1 + squash * 0.4))
            let w = bagWidth * PunchingBagArt.canvasScale, h = bagWidth * PunchingBagArt.canvasScale * PunchingBagArt.aspect
            ctx.draw(bag, in: CGRect(x: -w / 2, y: -h / 2 + PunchingBagArt.centerOffset * bagWidth, width: w, height: h))
            ctx.restoreGState()
        }

        for p in dust.particles {
            ctx.setAlpha(CGFloat(0.55 * (1 - p.progress)))
            ctx.fillCircle(center: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (0.6 + 0.8 * p.progress),
                           color: CGColor(red: 0.92, green: 0.86, blue: 0.76, alpha: 1))
        }
        ctx.setAlpha(1)
        for burst in bursts { drawBurst(burst, in: ctx) }

        BodyGameHUD.banner(ctx, "COMBO x\(multiplier)!", age: comboAge, size: size, color: BodyGamePalette.gold, life: 1.0)
    }

    private func drawChain(from a: CGPoint, to b: CGPoint, in ctx: CGContext) {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 4 else { return }
        let ux = (b.x - a.x) / length, uy = (b.y - a.y) / length
        let links = Int(length / 15)
        ctx.saveGState()
        for k in 0..<links {
            let p = CGPoint(x: a.x + ux * (CGFloat(k) + 0.5) * 15, y: a.y + uy * (CGFloat(k) + 0.5) * 15)
            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: atan2(uy, ux))
            let wide = k % 2 == 0
            let rect = wide ? CGRect(x: -10, y: -6, width: 20, height: 12) : CGRect(x: -10, y: -2.2, width: 20, height: 4.4)
            ctx.setStrokeColor(CGColor(red: 0.16, green: 0.16, blue: 0.2, alpha: 0.9))
            ctx.setLineWidth(5)
            ctx.strokeEllipse(in: rect)
            ctx.setStrokeColor(CGColor(red: 0.72, green: 0.74, blue: 0.8, alpha: 1))
            ctx.setLineWidth(2.5)
            ctx.strokeEllipse(in: rect)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    private func drawBurst(_ burst: Burst, in ctx: CGContext) {
        let t = burst.age / 0.8
        let pop = BodyEase.outBack(burst.age / 0.18, overshoot: 2.4)
        let fade = CGFloat(bodyClamp((0.8 - burst.age) / 0.3, 0, 1))
        let p = CGPoint(x: burst.position.x, y: burst.position.y + 24 * BodyEase.outCubic(t))
        let x = bodyClamp(Double(p.x), 140, size.width - 140), y = bodyClamp(Double(p.y), 90, size.height - 190)
        if burst.big {
            let s = 74 * pop
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: CGFloat(burst.tilt))
            ctx.setAlpha(fade)
            let star = PunchingBagArt.spiky(radius: CGFloat(s))
            ctx.addPath(star)
            ctx.setFillColor(BodyGamePalette.cg(BodyGamePalette.ink, 0.85))
            ctx.fillPath()
            ctx.translateBy(x: -3, y: 3)
            ctx.addPath(PunchingBagArt.spiky(radius: CGFloat(s * 0.94)))
            ctx.setFillColor(BodyGamePalette.cg(BodyGamePalette.gold))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: CGFloat(burst.tilt))
            BodyGameHUD.text(ctx, burst.text, center: CGPoint(x: -3, y: 2), size: CGFloat(30 * pop), color: BodyGamePalette.coral, weight: .black, alpha: fade)
            ctx.restoreGState()
        } else {
            BodyGameHUD.text(ctx, burst.text, center: CGPoint(x: x, y: y), size: CGFloat(42 * (0.6 + 0.4 * pop)), color: BodyGamePalette.cream, alpha: fade)
        }
    }
}

/// The bag, its trolley and the comic burst, drawn once.
enum PunchingBagArt {
    /// The bag is drawn on a canvas this many bag-widths wide (room for straps and shadow)...
    static let canvasScale = 1.5
    /// ...and this much taller than it is wide.
    static let aspect = 2.15
    /// How far to lift the canvas so the bag's own middle lands on the swing point, in bag widths.
    static let centerOffset = 0.3

    /// "Oxblood": deep red leather with a cream band.
    static let leather = NSColor(red: 0.74, green: 0.18, blue: 0.22, alpha: 1)

    static func bag() -> CGImage? {
        BodyArtCache.image("punching-bag", width: 240, height: 516) { drawBag($0) }
    }

    static func trolley() -> CGImage? {
        BodyArtCache.image("punching-trolley", width: 120, height: 80) { ctx in
            let body = CGRect(x: 20, y: 14, width: 80, height: 40)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 5, color: CGColor(red: 0, green: 0, blue: 0.05, alpha: 0.5))
            ctx.addPath(CGPath(roundedRect: body, cornerWidth: 9, cornerHeight: 9, transform: nil))
            ctx.setFillColor(CGColor(red: 0.3, green: 0.31, blue: 0.38, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: body, cornerWidth: 9, cornerHeight: 9, transform: nil))
            ctx.clip()
            BodyShapes.fillVertical(ctx, body, top: CGColor(red: 0.74, green: 0.76, blue: 0.84, alpha: 1), middle: CGColor(red: 0.42, green: 0.44, blue: 0.52, alpha: 1),
                                    bottom: CGColor(red: 0.18, green: 0.19, blue: 0.25, alpha: 1))
            ctx.restoreGState()
            for x in [38.0, 82.0] {
                ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: x - 11, y: 46, width: 22, height: 22))
                ctx.setFillColor(CGColor(red: 0.62, green: 0.64, blue: 0.72, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: x - 5, y: 52, width: 10, height: 10))
            }
            ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.26, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 52, y: 4, width: 16, height: 16))
        }
    }

    /// A jagged comic "POW" burst.
    static func spiky(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let points = 12
        for i in 0..<(points * 2) {
            let a = CGFloat(i) / CGFloat(points * 2) * 2 * .pi
            let r = i % 2 == 0 ? radius : radius * (0.62 + 0.08 * CGFloat(i % 3))
            let p = CGPoint(x: cos(a) * r * 1.25, y: sin(a) * r * 0.85)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func drawBag(_ ctx: CGContext) {
        // Canvas 240 x 516: the body is 160 by 340 with its middle at y 210; the strap ring is at y 488.
        let w: CGFloat = 160, h: CGFloat = 340
        let body = CGRect(x: 40, y: 40, width: w, height: h)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // Straps up to the ring.
        let ring = CGPoint(x: 120, y: 488)
        ctx.setLineCap(.round)
        for (x, shade) in [(54.0, 0.0), (186.0, 0.0), (88.0, 0.15), (152.0, 0.15)] {
            ctx.move(to: CGPoint(x: x, y: body.maxY - 8))
            ctx.addLine(to: CGPoint(x: ring.x + (x - 120) * 0.08, y: ring.y - 8))
            ctx.setStrokeColor(CGColor(red: 0.22 + shade, green: 0.08 + shade * 0.5, blue: 0.08 + shade * 0.5, alpha: 1))
            ctx.setLineWidth(9)
            ctx.strokePath()
        }
        ctx.setStrokeColor(CGColor(red: 0.62, green: 0.64, blue: 0.72, alpha: 1))
        ctx.setLineWidth(6)
        ctx.strokeEllipse(in: CGRect(x: ring.x - 12, y: ring.y - 10, width: 24, height: 20))

        let shape = CGPath(roundedRect: body, cornerWidth: 44, cornerHeight: 36, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 8, height: -10), blur: 16, color: CGColor(red: 0.05, green: 0, blue: 0.08, alpha: 0.45))
        ctx.addPath(shape)
        ctx.setFillColor(leather.bodyShade(-0.3))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        // A cylinder: dark at both sides, lit a third of the way across from the left.
        let colors = [leather.bodyShade(-0.62), leather.bodyShade(-0.1), leather.bodyShade(0.32), leather.bodyShade(0.02),
                      leather.bodyShade(-0.55), leather.bodyShade(-0.35)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.16, 0.32, 0.58, 0.9, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: body.minX, y: 0), end: CGPoint(x: body.maxX, y: 0), options: [])
        }
        // Darker toward the bottom, where less light reaches.
        let fall = [CGColor(red: 0, green: 0, blue: 0, alpha: 0), CGColor(red: 0.05, green: 0, blue: 0.05, alpha: 0.3)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: fall, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: body.midY + 40), end: CGPoint(x: 0, y: body.minY), options: [])
        }
        // Caps top and bottom, with stitching.
        for (y, height) in [(body.maxY - 46, 46.0), (body.minY, 40.0)] {
            ctx.setFillColor(CGColor(red: 0.12, green: 0.02, blue: 0.04, alpha: 0.38))
            ctx.fill(CGRect(x: body.minX, y: y, width: w, height: height))
            let seam = y == body.minY ? y + height : y
            ctx.setStrokeColor(CGColor(red: 1, green: 0.92, blue: 0.85, alpha: 0.6))
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [6, 5])
            ctx.move(to: CGPoint(x: body.minX, y: seam + (y == body.minY ? -5 : 5)))
            ctx.addLine(to: CGPoint(x: body.maxX, y: seam + (y == body.minY ? -5 : 5)))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }
        // A cream band with a gold star on it.
        let band = CGRect(x: body.minX, y: body.minY + h * 0.52, width: w, height: 58)
        if let g = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.62, green: 0.58, blue: 0.52, alpha: 1), CGColor(red: 1, green: 0.96, blue: 0.88, alpha: 1),
                                                            CGColor(red: 0.84, green: 0.8, blue: 0.72, alpha: 1), CGColor(red: 0.5, green: 0.46, blue: 0.42, alpha: 1)] as CFArray,
                              locations: [0, 0.3, 0.62, 1]) {
            ctx.saveGState()
            ctx.clip(to: band)
            ctx.drawLinearGradient(g, start: CGPoint(x: body.minX, y: 0), end: CGPoint(x: body.maxX, y: 0), options: [])
            ctx.restoreGState()
        }
        let star = BodyShapes.star(center: CGPoint(x: band.midX - 10, y: band.midY), radius: 20)
        ctx.addPath(star)
        ctx.setFillColor(BodyGamePalette.cg(BodyGamePalette.gold))
        ctx.fillPath()
        ctx.addPath(star)
        ctx.setStrokeColor(CGColor(red: 0.55, green: 0.32, blue: 0.05, alpha: 0.8))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        // Vertical seams with stitches.
        for x in [body.minX + 46, body.maxX - 40] {
            ctx.setStrokeColor(CGColor(red: 0.1, green: 0, blue: 0.02, alpha: 0.35))
            ctx.setLineWidth(3)
            ctx.move(to: CGPoint(x: x, y: body.minY + 40))
            ctx.addLine(to: CGPoint(x: x, y: body.maxY - 46))
            ctx.strokePath()
        }
        // The leather's shine.
        ctx.glow(center: CGPoint(x: body.minX + w * 0.3, y: body.maxY - 90), radius: 70, red: 1, green: 0.8, blue: 0.78, alpha: 0.28)
        // A soft sheen down the lit side, fading out at both ends.
        let sheen = CGRect(x: body.minX + w * 0.22, y: body.minY + 50, width: 16, height: h - 110)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: sheen, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.clip()
        let glint = [CGColor(red: 1, green: 0.95, blue: 0.95, alpha: 0), CGColor(red: 1, green: 0.95, blue: 0.95, alpha: 0.26),
                     CGColor(red: 1, green: 0.95, blue: 0.95, alpha: 0.12), CGColor(red: 1, green: 0.95, blue: 0.95, alpha: 0)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: glint, locations: [0, 0.25, 0.7, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: sheen.maxY), end: CGPoint(x: 0, y: sheen.minY), options: [])
        }
        ctx.restoreGState()
        ctx.restoreGState()
        ctx.addPath(shape)
        ctx.setStrokeColor(CGColor(red: 0.18, green: 0.02, blue: 0.05, alpha: 0.7))
        ctx.setLineWidth(2.5)
        ctx.strokePath()
    }
}
