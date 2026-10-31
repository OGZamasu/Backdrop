import AppKit
import CoreGraphics
import simd

/// Balloons drift up the screen. Swat them: they pop where your body is *moving*, so a still body lets them float past.
/// Gold ones are worth five, bombs cost you three.
struct BalloonGame: Game {
    static let title = "Balloon Pop"
    static let hint = "Wave and swat to pop balloons. Dodge the bombs!"
    static let accent = SIMD3<Double>(1.0, 0.55, 0.6)

    enum Kind { case normal, gold, bomb }

    struct Balloon {
        var position: SIMD2<Double>
        var rise: Double
        var radius: Double
        /// Which colour, 0..<1, picked from `BalloonArt.palette`.
        var colour: Double
        var kind: Kind
        var phase: Double
    }

    /// A balloon in the moment after it bursts: torn rubber flying out, a ring, a puff.
    struct Burst {
        var position: SIMD2<Double>
        var radius: Double
        var colour: Int
        var kind: Kind
        var spin: Double
        var age = 0.0
    }

    static let roundSeconds = 45.0
    /// How long a burst plays.
    static let burstSeconds = 0.6

    let size: CGSize
    private(set) var balloons: [Balloon] = []
    private(set) var score = 0
    private(set) var timeLeft = BalloonGame.roundSeconds
    private(set) var elapsed = 0.0
    private(set) var popped = 0
    private(set) var bursts: [Burst] = []
    private var sparkles = ParticleSystem(capacity: 400)
    private var floaters: [BodyFloater] = []
    private var rng: SplitMix64
    private var nextSpawn = 0.3
    private var ouch = 0.0
    /// Where the player's head probably is, so points are never written over a face.
    private var head: CGRect?
    private var sinceScan = 9.0

    var isOver: Bool { timeLeft <= 0 }

    var readout: GameUIReadout { GameUIReadout(score: score, time: (max(0, timeLeft), Self.roundSeconds)) }

    var result: GameUIResult {
        let line: String
        switch popped {
        case 0..<8: line = "Swing your arms right through the balloons"
        case 8..<30: line = "Pop! Gold balloons are worth five"
        default: line = "Not a balloon left standing"
        }
        return GameUIResult(headline: "Time's up!", line: line, stats: [("\(popped)", "popped"), ("\(score)", "points")], kind: .timeUp)
    }
    var summary: String { "\(Int(timeLeft.rounded(.up)))s" }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        sparkles.gravity = SIMD2(0, -520)
        sparkles.drag = 1.2
        BodyArtCache.warm("balloons") {
            for i in BalloonArt.palette.indices { _ = BalloonArt.balloon(i) }
            _ = BalloonArt.goldStar()
            _ = BalloonArt.bomb()
        }
    }

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = bodyClamp(dt, 0, 0.1)
        elapsed += dt
        timeLeft = max(0, timeLeft - dt)
        ouch = max(0, ouch - dt)
        sinceScan += dt
        if sinceScan > 0.25 {
            sinceScan = 0
            head = BodyScan(matte: world.matte, size: size, step: 32).headZone
        }

        nextSpawn -= dt
        if nextSpawn <= 0 {
            spawn()
            nextSpawn = max(0.3, 0.95 - elapsed * 0.014) * Double.random(in: 0.7...1.3, using: &rng)
        }

        for i in balloons.indices {
            balloons[i].position.y += balloons[i].rise * dt
            balloons[i].position.x += sin(balloons[i].phase + elapsed * 1.4) * 34 * dt
        }
        balloons.removeAll { $0.position.y - $0.radius * 1.4 > size.height }

        if let motion = world.motion { pop(using: motion) }

        sparkles.step(dt)
        for i in bursts.indices { bursts[i].age += dt }
        bursts.removeAll { $0.age > Self.burstSeconds }
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll { $0.isDone }
    }

    private mutating func spawn() {
        let roll = Double.random(in: 0..<1, using: &rng)
        let kind: Kind = elapsed > 4 && roll < 0.13 ? .bomb : roll < 0.2 ? .gold : .normal
        let radius = Double.random(in: 42...60, using: &rng)
        balloons.append(Balloon(position: SIMD2(Double.random(in: 100...(size.width - 100), using: &rng), -radius * 1.4),
                                rise: 90 + elapsed * 1.3 + Double.random(in: 0...60, using: &rng),
                                radius: radius, colour: Double.random(in: 0..<1, using: &rng), kind: kind,
                                phase: Double.random(in: 0..<6.28, using: &rng)))
    }

    private mutating func pop(using motion: MatteQuery) {
        var survivors: [Balloon] = []
        for balloon in balloons {
            if touched(balloon, by: motion) {
                popped += 1
                let points: Int
                switch balloon.kind {
                case .normal: points = 1
                case .gold: points = 5
                case .bomb: points = -3
                }
                score = max(0, score + points)
                burst(balloon)
                if balloon.kind == .bomb { ouch = 0.5 }
                floaters.append(BodyFloater.placed(points > 0 ? "+\(points)" : "\(points)", at: balloon.position + SIMD2(0, balloon.radius * 0.6),
                                                   size: size, color: points > 0 ? BodyGamePalette.gold : BodyGamePalette.coral,
                                                   fontSize: balloon.kind == .normal ? 48 : 62, avoiding: head))
            } else {
                survivors.append(balloon)
            }
        }
        balloons = survivors
    }

    /// Whether something is moving through the balloon: two or more of nine points across it see motion, so a swat counts and the
    /// flicker along a still person's outline does not.
    func touched(_ balloon: Balloon, by motion: MatteQuery) -> Bool {
        BodySense.motionHits(at: balloon.position, radius: balloon.radius * 0.85, in: motion) >= 2
    }

    private mutating func burst(_ balloon: Balloon) {
        let colour = BalloonArt.index(balloon.colour)
        bursts.append(Burst(position: balloon.position, radius: balloon.radius, colour: colour, kind: balloon.kind,
                            spin: Double.random(in: 0..<(2 * .pi), using: &rng)))
        let count = balloon.kind == .normal ? 10 : 22
        for _ in 0..<count {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng), speed = Double.random(in: 140...460, using: &rng)
            sparkles.emit(Particle(position: balloon.position, velocity: SIMD2(cos(angle), sin(angle) * 0.9 + 0.3) * speed,
                                   life: Double.random(in: 0.35...0.8, using: &rng), size: Double.random(in: 3...8, using: &rng),
                                   hue: Double(colour), kind: balloon.kind == .bomb ? 1 : balloon.kind == .gold ? 2 : 0))
        }
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        // Strings first, so every balloon sits over its own and its neighbours'.
        for balloon in balloons where balloon.kind != .bomb { drawString(balloon, in: ctx) }
        for balloon in balloons { drawBalloon(balloon, in: ctx, time: time) }
        for burst in bursts { drawBurst(burst, in: ctx) }
        for p in sparkles.particles { drawSparkle(p, in: ctx) }
        for floater in floaters { floater.draw(in: ctx) }
        BodyGameHUD.flash(ctx, size: size, color: BodyGamePalette.tangerine, strength: ouch / 0.5 * 0.7)
    }

    /// How fast the balloon is drifting sideways, in pixels a second.
    private func drift(_ b: Balloon) -> Double { sin(b.phase + elapsed * 1.4) * 34 }

    /// It leans into its drift a little and rocks gently, so it never looks pinned in place.
    private func lean(_ b: Balloon) -> Double { -drift(b) / 380 + 0.04 * sin(elapsed * 2.1 + b.phase * 3) }

    /// Where the knot is, after the lean.
    private func knot(_ b: Balloon) -> CGPoint {
        let a = lean(b), reach = b.radius * BalloonArt.knotReach
        return CGPoint(x: b.position.x + sin(a) * reach, y: b.position.y - cos(a) * reach)
    }

    private func drawString(_ b: Balloon, in ctx: CGContext) {
        let top = knot(b)
        let length = b.radius * 2.1
        // The string trails behind the drift and lags its swing.
        let trail = -sin(b.phase + (elapsed - 0.35) * 1.4) * 34 * 0.9
        let wave = sin(elapsed * 3.1 + b.phase * 2) * b.radius * 0.18
        let end = CGPoint(x: top.x + trail + wave * 0.4, y: top.y - length)
        let c1 = CGPoint(x: top.x + wave, y: top.y - length * 0.35), c2 = CGPoint(x: end.x - wave, y: top.y - length * 0.7)
        ctx.saveGState()
        ctx.setLineCap(.round)
        for (width, colour) in [(CGFloat(3.4), BodyGamePalette.cg(BodyGamePalette.ink, 0.3)), (1.6, BodyGamePalette.cg(BodyGamePalette.cream, 0.85))] {
            ctx.move(to: top)
            ctx.addCurve(to: end, control1: c1, control2: c2)
            ctx.setStrokeColor(colour)
            ctx.setLineWidth(width)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private func drawBalloon(_ b: Balloon, in ctx: CGContext, time: Double) {
        let c = CGPoint(x: b.position.x, y: b.position.y)
        let breathe = 0.018 * sin(elapsed * 3 + b.phase)
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(lean(b)))
        ctx.scaleBy(x: CGFloat(1 + breathe), y: CGFloat(1 - breathe))
        switch b.kind {
        case .normal:
            if let sprite = BalloonArt.balloon(BalloonArt.index(b.colour)) { BalloonArt.place(sprite, radius: b.radius, in: ctx) }
        case .gold:
            BodyGlow.stamp(ctx, at: .zero, radius: CGFloat(b.radius * 2), color: BodyGamePalette.gold, alpha: 0.35 + 0.15 * sin(time * 4 + b.phase))
            if let sprite = BalloonArt.goldStar() { BalloonArt.place(sprite, radius: b.radius, in: ctx) }
        case .bomb:
            // A slow coral pulse round it, so it never reads as just another dark balloon.
            BodyGlow.stamp(ctx, at: .zero, radius: CGFloat(b.radius * 1.9), color: BodyGamePalette.coral, alpha: 0.3 + 0.18 * sin(time * 5 + b.phase))
            if let sprite = BalloonArt.bomb() { BalloonArt.place(sprite, radius: b.radius, in: ctx) }
            // The burning fuse: a flickering spark at its tip.
            let tip = CGPoint(x: b.radius * BalloonArt.fuseTip.x, y: b.radius * BalloonArt.fuseTip.y)
            let flicker = 0.7 + 0.3 * sin(time * 37 + b.phase)
            BodyGlow.stamp(ctx, at: tip, radius: CGFloat(b.radius * 0.8 * flicker), red: 1, green: 0.6, blue: 0.2, alpha: 0.9)
            BodyGlow.stamp(ctx, at: tip, radius: CGFloat(b.radius * 0.3), red: 1, green: 1, blue: 0.85, alpha: 1)
            ctx.addPath(BodyShapes.star(center: tip, radius: CGFloat(b.radius * 0.32 * flicker), rotation: CGFloat(time * 9), inner: 0.3))
            ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.75, alpha: 0.95))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    private func drawBurst(_ burst: Burst, in ctx: CGContext) {
        let t = burst.age / Self.burstSeconds
        let c = CGPoint(x: burst.position.x, y: burst.position.y), r = burst.radius
        if burst.kind == .bomb {
            // A soft puff of smoke round an orange flash.
            let flash = bodyClamp(1 - burst.age / 0.18, 0, 1)
            BodyGlow.stamp(ctx, at: c, radius: CGFloat(r * (1.6 + 1.6 * t)), red: 1, green: 0.6, blue: 0.25, alpha: 0.8 * (1 - t))
            if flash > 0 { BodyGlow.stamp(ctx, at: c, radius: CGFloat(r * 1.3), red: 1, green: 0.95, blue: 0.85, alpha: flash) }
            for k in 0..<7 {
                let a = burst.spin + Double(k) / 7 * 2 * .pi
                let reach = r * (0.4 + 1.2 * BodyEase.outCubic(t))
                let puff = CGPoint(x: c.x + cos(a) * reach, y: c.y + sin(a) * reach + 30 * t)
                let size = r * (0.45 + 0.5 * t) * (0.8 + 0.2 * sin(Double(k) * 2.3))
                ctx.fillCircle(center: puff, radius: CGFloat(size), color: CGColor(red: 0.32, green: 0.3, blue: 0.36, alpha: CGFloat(0.55 * (1 - t))))
                ctx.fillCircle(center: CGPoint(x: puff.x - size * 0.25, y: puff.y + size * 0.25), radius: CGFloat(size * 0.55),
                               color: CGColor(red: 0.55, green: 0.53, blue: 0.6, alpha: CGFloat(0.4 * (1 - t))))
            }
            return
        }
        // The snap: a bright ring that races out and thins.
        if t < 0.45 {
            let k = t / 0.45
            let ring = r * (0.8 + 1.2 * BodyEase.outCubic(k))
            ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.cream, CGFloat(0.9 * (1 - k))))
            ctx.setLineWidth(CGFloat(7 * (1 - k) + 1))
            ctx.strokeEllipse(in: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2))
        }
        if burst.age < 0.09 { BodyGlow.stamp(ctx, at: c, radius: CGFloat(r * 1.4), red: 1, green: 1, blue: 0.95, alpha: 0.8) }
        // Torn rubber: curled shreds of the balloon's colour flying out, turning and falling.
        let base = burst.kind == .gold ? BodyGamePalette.gold : BalloonArt.palette[burst.colour]
        let fly = BodyEase.outCubic(t)
        for k in 0..<7 {
            let a = burst.spin + Double(k) / 7 * 2 * .pi
            let reach = r * (0.5 + 1.5 * fly)
            let at = CGPoint(x: c.x + cos(a) * reach, y: c.y + sin(a) * reach - 90 * t * t)
            ctx.saveGState()
            ctx.translateBy(x: at.x, y: at.y)
            ctx.rotate(by: CGFloat(a + t * 7 * (k % 2 == 0 ? 1 : -1)))
            ctx.setAlpha(CGFloat(1 - t * t))
            let w = r * 0.42 * (1 - 0.4 * t), h = r * 0.2
            let shred = CGMutablePath()
            shred.move(to: CGPoint(x: -w, y: 0))
            shred.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: 0, y: h * 1.6))
            shred.addQuadCurve(to: CGPoint(x: -w, y: 0), control: CGPoint(x: 0, y: h * 0.5))
            ctx.addPath(shred)
            ctx.setFillColor(base.bodyShade(k % 2 == 0 ? 0.1 : -0.2))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    private func drawSparkle(_ p: Particle, in ctx: CGContext) {
        let fade = CGFloat(1 - p.progress)
        let at = CGPoint(x: p.position.x, y: p.position.y)
        ctx.setAlpha(fade)
        switch p.kind {
        case 1:
            ctx.fillCircle(center: at, radius: p.size * (1 - 0.5 * p.progress), color: CGColor(red: 1, green: 0.7 - 0.35 * p.progress, blue: 0.25, alpha: 1))
        case 2:
            ctx.addPath(BodyShapes.star(center: at, radius: CGFloat(p.size * 1.6), rotation: CGFloat(p.age * 6), inner: 0.4))
            ctx.setFillColor(BodyGamePalette.cg(BodyGamePalette.gold))
            ctx.fillPath()
        default:
            let colour = BalloonArt.palette[Int(p.hue) % BalloonArt.palette.count]
            ctx.fillCircle(center: at, radius: p.size * 0.8, color: colour.bodyShade(0.25))
        }
        ctx.setAlpha(1)
    }
}

/// The balloons, drawn once each as lit vector art: latex teardrops in a party palette, a gold foil star, and a bomb.
/// Everything is lit from the top left.
enum BalloonArt {
    /// "Party latex": warm and cool colours that sit well together and never go to a pure primary.
    static let palette: [NSColor] = [
        NSColor(red: 0.94, green: 0.28, blue: 0.38, alpha: 1),   // cherry
        NSColor(red: 1.00, green: 0.58, blue: 0.22, alpha: 1),   // tangerine
        NSColor(red: 1.00, green: 0.80, blue: 0.26, alpha: 1),   // lemon
        NSColor(red: 0.30, green: 0.80, blue: 0.56, alpha: 1),   // mint
        NSColor(red: 0.28, green: 0.62, blue: 0.98, alpha: 1),   // sky
        NSColor(red: 0.60, green: 0.43, blue: 0.95, alpha: 1),   // grape
        NSColor(red: 1.00, green: 0.50, blue: 0.74, alpha: 1),   // bubblegum
    ]

    /// The design is drawn round a balloon of this radius, then scaled to each balloon's.
    private static let design = 80.0
    private static let width = 232, height = 288
    /// Where the balloon's middle sits in the picture, from the bottom left, in design units.
    private static let middle = CGPoint(x: 116, y: 156)
    /// How far below the middle the knot hangs, in balloon radii.
    static let knotReach = 1.3
    /// Where the bomb's fuse ends, in balloon radii from its middle.
    static let fuseTip = CGPoint(x: 0.62, y: 1.32)

    static func index(_ colour: Double) -> Int { min(palette.count - 1, max(0, Int(colour * Double(palette.count)))) }

    /// Draws a sprite made by this enum centred on the origin, scaled to a balloon of `radius`.
    static func place(_ sprite: CGImage, radius: Double, in ctx: CGContext) {
        let k = radius / design
        ctx.draw(sprite, in: CGRect(x: -middle.x * k, y: -middle.y * k, width: Double(width) * k, height: Double(height) * k))
    }

    static func balloon(_ index: Int) -> CGImage? {
        let which = ((index % palette.count) + palette.count) % palette.count
        return BodyArtCache.image("balloon-latex-\(which)", width: width, height: height) { drawLatex($0, colour: palette[which]) }
    }

    static func goldStar() -> CGImage? { BodyArtCache.image("balloon-gold-star", width: width, height: height) { drawGold($0) } }

    static func bomb() -> CGImage? { BodyArtCache.image("balloon-bomb", width: width, height: height) { drawBomb($0) } }

    /// A teardrop: round on top, drawn in to the knot at the bottom.
    private static func teardrop(_ r: Double) -> CGPath {
        let ry = r * 1.16
        let p = CGMutablePath()
        let bottom = CGPoint(x: 0, y: -ry)
        p.move(to: bottom)
        p.addCurve(to: CGPoint(x: r, y: ry * 0.08), control1: CGPoint(x: r * 0.42, y: -ry * 0.98), control2: CGPoint(x: r, y: -ry * 0.58))
        p.addCurve(to: CGPoint(x: 0, y: ry), control1: CGPoint(x: r, y: ry * 0.62), control2: CGPoint(x: r * 0.56, y: ry))
        p.addCurve(to: CGPoint(x: -r, y: ry * 0.08), control1: CGPoint(x: -r * 0.56, y: ry), control2: CGPoint(x: -r, y: ry * 0.62))
        p.addCurve(to: bottom, control1: CGPoint(x: -r, y: -ry * 0.58), control2: CGPoint(x: -r * 0.42, y: -ry * 0.98))
        p.closeSubpath()
        return p
    }

    private static func drawLatex(_ ctx: CGContext, colour: NSColor) {
        let r = design
        ctx.translateBy(x: middle.x, y: middle.y)
        let body = teardrop(r)
        // A soft shadow down and to the right, so it floats in front of the picture.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 7, height: -10), blur: 14, color: CGColor(red: 0.05, green: 0.02, blue: 0.1, alpha: 0.35))
        ctx.addPath(body)
        ctx.setFillColor(colour.bodyShade(-0.2))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        let box = CGRect(x: -r, y: -r * 1.16, width: r * 2, height: r * 2.32)
        BodyShapes.fillLit(ctx, box, light: colour.bodyShade(0.55), body: colour.bodyShade(0), shade: colour.bodyShade(-0.5),
                           lightAt: CGPoint(x: -r * 0.38, y: r * 0.5))
        // Light bounced back into the lower right edge: latex glows a little at the rim.
        let (cr, cg, cb) = BodyGamePalette.rgb(colour)
        ctx.glow(center: CGPoint(x: r * 0.62, y: -r * 0.5), radius: r * 0.6, red: cr + (1 - cr) * 0.35, green: cg + (1 - cg) * 0.35,
                 blue: cb + (1 - cb) * 0.35, alpha: 0.45)
        ctx.restoreGState()

        // The shine: a broad soft one and a sharp glint.
        ctx.saveGState()
        ctx.translateBy(x: -r * 0.42, y: r * 0.46)
        ctx.rotate(by: 0.75)
        ctx.glow(center: .zero, radius: r * 0.42, red: 1, green: 1, blue: 1, alpha: 0.45)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.fillEllipse(in: CGRect(x: -r * 0.2, y: -r * 0.08, width: r * 0.4, height: r * 0.16))
        ctx.restoreGState()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: -r * 0.12 - 5, y: r * 0.78 - 5, width: 10, height: 10))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
        ctx.fillEllipse(in: CGRect(x: r * 0.5 - 4, y: -r * 0.62 - 6, width: 8, height: 12))

        // The knot: a little tied nub with its own shine.
        let k = CGMutablePath()
        let y0 = -r * 1.14
        k.move(to: CGPoint(x: -4, y: y0 + 4))
        k.addLine(to: CGPoint(x: 4, y: y0 + 4))
        k.addLine(to: CGPoint(x: 10, y: y0 - 10))
        k.addQuadCurve(to: CGPoint(x: -10, y: y0 - 10), control: CGPoint(x: 0, y: y0 - 15))
        k.closeSubpath()
        ctx.addPath(k)
        ctx.setFillColor(colour.bodyShade(-0.3))
        ctx.fillPath()
        ctx.setFillColor(colour.bodyShade(0.3))
        ctx.fillEllipse(in: CGRect(x: -6, y: y0 - 9, width: 5, height: 6))
    }

    private static func drawGold(_ ctx: CGContext) {
        let r = design
        ctx.translateBy(x: middle.x, y: middle.y)
        let star = BodyShapes.star(center: CGPoint(x: 0, y: r * 0.06), radius: CGFloat(r * 1.12), rotation: 0, inner: 0.56)
        let puffy = star.copy(strokingWithWidth: CGFloat(r * 0.3), lineCap: .round, lineJoin: .round, miterLimit: 1)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 7, height: -10), blur: 14, color: CGColor(red: 0.2, green: 0.1, blue: 0, alpha: 0.4))
        ctx.addPath(star)
        ctx.addPath(puffy)
        ctx.setFillColor(CGColor(red: 0.85, green: 0.58, blue: 0.12, alpha: 1))
        ctx.fillPath(using: .winding)
        ctx.restoreGState()
        // Foil: bands of light and dark gold across it, lit from the top left.
        ctx.saveGState()
        ctx.addPath(star)
        ctx.addPath(puffy)
        ctx.clip(using: .winding)
        let colors = [CGColor(red: 1, green: 0.96, blue: 0.72, alpha: 1), CGColor(red: 0.98, green: 0.78, blue: 0.24, alpha: 1),
                      CGColor(red: 0.78, green: 0.5, blue: 0.08, alpha: 1), CGColor(red: 1, green: 0.86, blue: 0.4, alpha: 1),
                      CGColor(red: 0.66, green: 0.4, blue: 0.06, alpha: 1)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.3, 0.55, 0.72, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: -r, y: r), end: CGPoint(x: r, y: -r), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        // Seams running out to each point, like a real foil balloon.
        ctx.setLineCap(.round)
        for i in 0..<5 {
            let a = CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / 5
            ctx.move(to: .zero)
            ctx.addLine(to: CGPoint(x: cos(a) * CGFloat(r) * 0.9, y: sin(a) * CGFloat(r) * 0.9))
            ctx.setStrokeColor(CGColor(red: 1, green: 0.98, blue: 0.85, alpha: cos(a - 2.3) > 0 ? 0.5 : 0.18))
            ctx.setLineWidth(3)
            ctx.strokePath()
        }
        ctx.restoreGState()
        ctx.glow(center: CGPoint(x: -r * 0.3, y: r * 0.35), radius: r * 0.35, red: 1, green: 1, blue: 0.95, alpha: 0.75)
        ctx.addPath(puffy)
        ctx.setStrokeColor(CGColor(red: 0.62, green: 0.38, blue: 0.05, alpha: 0.5))
        ctx.setLineWidth(2)
        ctx.strokePath()
    }

    private static func drawBomb(_ ctx: CGContext) {
        let r = design * 0.92
        ctx.translateBy(x: middle.x, y: middle.y)
        // The fuse first, so the cap sits over its root.
        let fuse = CGMutablePath()
        fuse.move(to: CGPoint(x: r * 0.36, y: r * 0.86))
        fuse.addCurve(to: CGPoint(x: design * fuseTip.x, y: design * fuseTip.y), control1: CGPoint(x: r * 0.5, y: r * 1.22),
                      control2: CGPoint(x: r * 0.3, y: r * 1.3))
        ctx.setLineCap(.round)
        ctx.addPath(fuse)
        ctx.setStrokeColor(CGColor(red: 0.42, green: 0.3, blue: 0.2, alpha: 1))
        ctx.setLineWidth(9)
        ctx.strokePath()
        ctx.addPath(fuse)
        ctx.setStrokeColor(CGColor(red: 0.82, green: 0.68, blue: 0.48, alpha: 1))
        ctx.setLineWidth(4)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        let ball = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 7, height: -10), blur: 14, color: CGColor(red: 0, green: 0, blue: 0.05, alpha: 0.45))
        ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.17, alpha: 1))
        ctx.fillEllipse(in: ball)
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addEllipse(in: ball)
        ctx.clip()
        BodyShapes.fillLit(ctx, ball, light: CGColor(red: 0.5, green: 0.52, blue: 0.62, alpha: 1), body: CGColor(red: 0.18, green: 0.18, blue: 0.24, alpha: 1),
                           shade: CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1), lightAt: CGPoint(x: -r * 0.4, y: r * 0.45))
        // A cool rim light on the lower right, so it reads on a dark backdrop.
        ctx.glow(center: CGPoint(x: r * 0.75, y: -r * 0.6), radius: r * 0.7, red: 0.45, green: 0.62, blue: 0.95, alpha: 0.5)
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: -r * 0.38, y: r * 0.42)
        ctx.rotate(by: 0.75)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.65))
        ctx.fillEllipse(in: CGRect(x: -r * 0.22, y: -r * 0.09, width: r * 0.44, height: r * 0.18))
        ctx.restoreGState()
        // The cap, turned toward the fuse.
        ctx.saveGState()
        ctx.translateBy(x: r * 0.3, y: r * 0.82)
        ctx.rotate(by: -0.38)
        let cap = CGRect(x: -r * 0.26, y: -r * 0.1, width: r * 0.52, height: r * 0.3)
        ctx.addPath(CGPath(roundedRect: cap, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.clip()
        BodyShapes.fillVertical(ctx, cap, top: CGColor(red: 0.72, green: 0.74, blue: 0.82, alpha: 1), middle: CGColor(red: 0.42, green: 0.44, blue: 0.52, alpha: 1),
                                bottom: CGColor(red: 0.2, green: 0.2, blue: 0.26, alpha: 1))
        ctx.restoreGState()
    }
}
