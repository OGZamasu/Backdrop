import AppKit
import CoreGraphics
import simd

/// A sheet of bubble wrap covers the picture. Wave, swipe and swat to pop the bubbles: they pop where your body is *moving*,
/// so standing still pops nothing. Popped bubbles go flat and fill up again a few seconds later, and quick pops build a combo.
struct BubbleWrapGame: Game {
    static let title = "Bubble Wrap"
    static let hint = "Swipe and wave to pop the bubbles. Keep popping for combos!"
    static let accent = SIMD3<Double>(0.55, 0.85, 1.0)
    static let roundSeconds = 45.0
    /// Distance between bubble centres.
    static let spacing = 80.0
    /// How long you have to pop the next one to keep a combo going.
    static let comboWindow = 0.9
    /// Seconds a popped bubble stays flat, between these two.
    static let refillRange = 5.5...8.5
    static let tintCount = 6

    struct Bubble {
        enum State: Equatable {
            case whole
            /// Flat, with this many seconds until it fills up again.
            case popped(Double)
            /// Filling up, from 0 to 1.
            case inflating(Double)
        }

        var center: SIMD2<Double>
        var state = State.whole
        var tint: Int
        var wrinkle: Int
        var gold = false
        /// Seconds since it last changed state, for the squish and the wobble.
        var age = 0.0

        var isWhole: Bool { state == .whole }
    }

    struct PopRing {
        var position: SIMD2<Double>
        var tint: Int
        var age = 0.0
    }

    let size: CGSize
    private(set) var bubbles: [Bubble] = []
    private(set) var score = 0
    private(set) var timeLeft = BubbleWrapGame.roundSeconds
    private(set) var elapsed = 0.0
    private(set) var popped = 0
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var goldPopped = 0

    private var sinceLastPop = 99.0
    private var droplets = ParticleSystem(capacity: 500)
    private var rings: [PopRing] = []
    private var floaters: [BodyFloater] = []
    private var comboText = ""
    private var comboAge = 99.0
    private var rng: SplitMix64

    var isOver: Bool { timeLeft <= 0 }
    var multiplier: Int { 1 + min(4, streak / 10) }
    var summary: String { multiplier > 1 ? "x\(multiplier) · \(Int(timeLeft.rounded(.up)))s" : "\(Int(timeLeft.rounded(.up)))s" }

    var readout: GameUIReadout {
        GameUIReadout(score: score, time: (max(0, timeLeft), Self.roundSeconds), combo: multiplier > 1 ? multiplier : 0,
                      label: streak >= 3 ? "Streak \(streak)" : nil)
    }

    var result: GameUIResult {
        let line: String
        switch popped {
        case 0..<20: line = "Sweep your arms through the sheet to pop more"
        case 20..<80: line = "So satisfying. Keep a streak going for combos"
        default: line = "Not a single bubble left unpopped!"
        }
        return GameUIResult(headline: "Time's up!", line: line, stats: [("\(popped)", "popped"), ("\(bestStreak)", "best streak"), ("\(goldPopped)", "gold")],
                            kind: .timeUp)
    }
    var wholeCount: Int { bubbles.filter(\.isWhole).count }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        droplets.gravity = SIMD2(0, -520)
        droplets.drag = 1.4
        layOutSheet()
        BodyArtCache.warm("bubbles") {
            for tint in 0..<Self.tintCount {
                _ = BubbleWrapArt.whole(tint: tint, gold: false)
                for variant in 0..<BubbleWrapArt.wrinkleVariants { _ = BubbleWrapArt.flat(tint: tint, variant: variant) }
            }
            _ = BubbleWrapArt.whole(tint: 0, gold: true)
        }
    }

    /// Rows of bubbles, every other row shifted half a bubble, like the real thing.
    private mutating func layOutSheet() {
        let d = Self.spacing, rowGap = d * 0.866
        var y = 0.0, row = 0
        while y < size.height + rowGap {
            var x = row % 2 == 0 ? 0.0 : d / 2
            while x < size.width + d / 2 {
                bubbles.append(Bubble(center: SIMD2(x, y), tint: Int.random(in: 0..<Self.tintCount, using: &rng),
                                      wrinkle: Int.random(in: 0..<BubbleWrapArt.wrinkleVariants, using: &rng),
                                      gold: Double.random(in: 0..<1, using: &rng) < 0.025))
                x += d
            }
            y += rowGap
            row += 1
        }
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = bodyClamp(dt, 0, 0.1)
        elapsed += dt
        timeLeft = max(0, timeLeft - dt)
        sinceLastPop += dt
        comboAge += dt
        if sinceLastPop > Self.comboWindow { streak = 0 }

        refill(dt)
        if let motion = world.motion { popTouched(by: motion) }

        droplets.step(dt)
        for i in rings.indices { rings[i].age += dt }
        rings.removeAll { $0.age > 0.4 }
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll { $0.isDone }
    }

    private mutating func refill(_ dt: Double) {
        var goldNow = bubbles.filter(\.gold).count
        for i in bubbles.indices {
            bubbles[i].age += dt
            switch bubbles[i].state {
            case .whole:
                break
            case .popped(let left):
                if left - dt <= 0 {
                    bubbles[i].state = .inflating(0)
                    bubbles[i].age = 0
                    if goldNow < 6, Double.random(in: 0..<1, using: &rng) < 0.06 { bubbles[i].gold = true; goldNow += 1 }
                } else {
                    bubbles[i].state = .popped(left - dt)
                }
            case .inflating(let t):
                bubbles[i].state = t + dt / 0.4 >= 1 ? .whole : .inflating(t + dt / 0.4)
            }
        }
    }

    private mutating func popTouched(by motion: MatteQuery) {
        for i in bubbles.indices where bubbles[i].isWhole && touched(bubbles[i], by: motion) { pop(i) }
    }

    /// Whether something is moving through the bubble: at least two of fifteen samples inside it see motion, so a flicker at
    /// the edge of a still silhouette doesn't count.
    func touched(_ bubble: Bubble, by motion: MatteQuery) -> Bool {
        let c = bubble.center, r = Self.spacing * 0.5
        var seen = 0
        func look(_ x: Double, _ y: Double) { if motion.coverage(x: x, y: y) > 0.5 { seen += 1 } }
        look(c.x, c.y)
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi
            look(c.x + cos(a) * r * 0.4, c.y + sin(a) * r * 0.4)
        }
        for k in 0..<8 {
            let a = (Double(k) + 0.5) / 8 * 2 * .pi
            look(c.x + cos(a) * r * 0.8, c.y + sin(a) * r * 0.8)
        }
        return seen >= 2
    }

    private mutating func pop(_ index: Int) {
        let bubble = bubbles[index]
        let before = multiplier
        bubbles[index].state = .popped(Double.random(in: Self.refillRange, using: &rng))
        bubbles[index].age = 0
        bubbles[index].wrinkle = Int.random(in: 0..<BubbleWrapArt.wrinkleVariants, using: &rng)
        let wasGold = bubble.gold
        bubbles[index].gold = false

        popped += 1
        streak += 1
        bestStreak = max(bestStreak, streak)
        sinceLastPop = 0
        let worth = (wasGold ? 10 : 1) * multiplier
        score += worth
        if wasGold { goldPopped += 1 }

        rings.append(PopRing(position: bubble.center, tint: bubble.tint))
        let kind = wasGold ? 2 : 0
        for _ in 0..<(wasGold ? 16 : 9) {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng), speed = Double.random(in: 150...430, using: &rng)
            droplets.emit(Particle(position: bubble.center, velocity: SIMD2(cos(angle), sin(angle)) * speed,
                                   life: Double.random(in: 0.35...0.7, using: &rng), size: Double.random(in: 3...6.5, using: &rng),
                                   hue: Double(bubble.tint), kind: kind))
        }
        for _ in 0..<3 {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng), speed = Double.random(in: 60...200, using: &rng)
            droplets.emit(Particle(position: bubble.center, velocity: SIMD2(cos(angle), sin(angle)) * speed,
                                   life: Double.random(in: 0.3...0.5, using: &rng), size: Double.random(in: 5...8, using: &rng), kind: 1))
        }

        if multiplier > before {
            // One callout at a time, in the band above the combo meter: a new one replaces the last.
            comboText = "COMBO x\(multiplier)!"
            comboAge = 0
        }
        if wasGold {
            floaters.append(BodyFloater.placed("+\(worth)", at: bubble.center + SIMD2(0, 40), size: size, fontSize: 60))
        } else if multiplier >= 2, floaters.count < 4, popped % 4 == 0 {
            floaters.append(BodyFloater.placed("+\(worth)", at: bubble.center + SIMD2(0, 30), size: size, fontSize: 34, life: 0.7))
        }
    }

    // MARK: Test hooks

    /// Pops every bubble that is whole, as if a hand had swept over the whole sheet.
    mutating func popEverything() {
        for i in bubbles.indices where bubbles[i].isWhole { pop(i) }
    }

    /// The bubble whose centre is nearest a point.
    func bubble(near point: CGPoint) -> Int? {
        bubbles.indices.min { simd_distance(bubbles[$0].center, SIMD2(Double(point.x), Double(point.y))) <
                              simd_distance(bubbles[$1].center, SIMD2(Double(point.x), Double(point.y))) }
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        // The film over everything: a faint sheen so it reads as one sheet.
        ctx.setFillColor(CGColor(red: 0.85, green: 0.95, blue: 1, alpha: 0.04))
        ctx.fill(CGRect(origin: .zero, size: size))

        // Bubbles are plain copies of ready-made pictures, so keep the context from smoothing them.
        ctx.interpolationQuality = .none
        for bubble in bubbles { drawBubble(bubble, in: ctx, time: time) }
        ctx.interpolationQuality = .high

        for ring in rings {
            let t = ring.age / 0.4
            let radius = 22 + 46 * t
            let (r, g, b) = BubbleWrapArt.tintColour(ring.tint, gold: false)
            ctx.setStrokeColor(CGColor(red: min(1, r + 0.5), green: min(1, g + 0.5), blue: min(1, b + 0.5), alpha: CGFloat(1 - t)))
            ctx.setLineWidth(CGFloat(6 * (1 - t) + 1))
            ctx.strokeEllipse(in: CGRect(x: ring.position.x - radius, y: ring.position.y - radius, width: radius * 2, height: radius * 2))
        }
        for p in droplets.particles {
            let at = CGPoint(x: p.position.x, y: p.position.y)
            ctx.setAlpha(CGFloat(1 - p.progress))
            switch p.kind {
            case 1:
                ctx.fillCircle(center: at, radius: p.size * (1 - 0.6 * p.progress), color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            case 2:
                ctx.fillCircle(center: at, radius: p.size, color: CGColor(red: 1, green: 0.86, blue: 0.25, alpha: 1))
            default:
                let (r, g, b) = BubbleWrapArt.tintColour(Int(p.hue), gold: false)
                ctx.fillCircle(center: at, radius: p.size, color: CGColor(red: min(1, r + 0.35), green: min(1, g + 0.35), blue: min(1, b + 0.35), alpha: 1))
                ctx.fillCircle(center: CGPoint(x: at.x - p.size * 0.3, y: at.y + p.size * 0.3), radius: p.size * 0.35,
                               color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            }
        }
        ctx.setAlpha(1)
        for floater in floaters { floater.draw(in: ctx) }
        BodyGameHUD.banner(ctx, comboText, age: comboAge, size: size, color: BodyGamePalette.gold, life: 1.1)
    }

    private func drawBubble(_ bubble: Bubble, in ctx: CGContext, time: Double) {
        let c = CGPoint(x: bubble.center.x, y: bubble.center.y)
        let side = CGFloat(BubbleWrapArt.pixels)
        let home = CGRect(x: (c.x - side / 2).rounded(), y: (c.y - side / 2).rounded(), width: side, height: side)
        switch bubble.state {
        case .whole:
            // Off the edge of the picture: nothing to draw.
            guard home.maxX > 0, home.minX < size.width, home.maxY > 0, home.minY < size.height,
                  let sprite = BubbleWrapArt.whole(tint: bubble.tint, gold: bubble.gold) else { return }
            ctx.draw(sprite, in: home)
            // A glint that sweeps across the sheet.
            let sweep = (bubble.center.x + bubble.center.y * 0.7 - time * 240).truncatingRemainder(dividingBy: 1700)
            if abs(sweep) < 70 {
                BodyGlow.stamp(ctx, at: CGPoint(x: c.x - 11, y: c.y + 11), radius: 24, red: 1, green: 1, blue: 1, alpha: 0.55 * (1 - abs(sweep) / 70))
            }
            if bubble.gold {
                BodyGlow.stamp(ctx, at: c, radius: side * 0.85, red: 1, green: 0.8, blue: 0.2, alpha: 0.35 + 0.2 * sin(time * 5 + bubble.center.x))
            }
        case .popped:
            guard home.maxX > 0, home.minX < size.width, home.maxY > 0, home.minY < size.height,
                  let sprite = BubbleWrapArt.flat(tint: bubble.tint, variant: bubble.wrinkle) else { return }
            // Squashed a little at the moment of the pop.
            let squish = 1 + 0.22 * max(0, 1 - bubble.age / 0.14)
            if squish > 1.01 {
                ctx.interpolationQuality = .high
                ctx.draw(sprite, center: c, height: side * CGFloat(squish))
                ctx.interpolationQuality = .none
            } else {
                ctx.draw(sprite, in: home)
            }
        case .inflating(let t):
            guard let sprite = BubbleWrapArt.whole(tint: bubble.tint, gold: bubble.gold) else { return }
            let back = 1 + 2.70158 * pow(t - 1, 3) + 1.70158 * pow(t - 1, 2)
            ctx.interpolationQuality = .high
            ctx.draw(sprite, center: c, height: side * CGFloat(0.35 + 0.65 * back), alpha: CGFloat(0.35 + 0.65 * t))
            ctx.interpolationQuality = .none
        }
    }

}

/// The bubbles, drawn once each: shiny and round when whole, flat and wrinkled when popped.
enum BubbleWrapArt {
    static let wrinkleVariants = 4
    /// The bubbles are designed on a 128 point square and made at the size they are drawn, so putting one on screen is a plain copy.
    private static let designSide = 128
    private static let radius = 58.0
    /// Pixels across the picture of one bubble.
    static let pixels = 87

    /// A pastel colour for each tint, or gold.
    static func tintColour(_ tint: Int, gold: Bool) -> (Double, Double, Double) {
        if gold { return (1, 0.82, 0.25) }
        // Mostly the cool blues of real wrap, with a few pinks and greens, so you are still easy to see through it.
        let hues = [0.55, 0.58, 0.62, 0.50, 0.90, 0.40]
        return Palette.rgb(hue: hues[((tint % hues.count) + hues.count) % hues.count], saturation: 0.42, brightness: 1)
    }

    static func whole(tint: Int, gold: Bool) -> CGImage? {
        let which = ((tint % BubbleWrapGame.tintCount) + BubbleWrapGame.tintCount) % BubbleWrapGame.tintCount
        return BodyArtCache.image(gold ? "bubble-gold" : "bubble-\(which)", width: pixels, height: pixels) {
            $0.scaleBy(x: CGFloat(pixels) / CGFloat(designSide), y: CGFloat(pixels) / CGFloat(designSide))
            drawWhole($0, colour: tintColour(which, gold: gold), gold: gold)
        }
    }

    static func flat(tint: Int, variant: Int) -> CGImage? {
        let which = ((tint % BubbleWrapGame.tintCount) + BubbleWrapGame.tintCount) % BubbleWrapGame.tintCount
        let shape = ((variant % wrinkleVariants) + wrinkleVariants) % wrinkleVariants
        return BodyArtCache.image("bubble-flat-\(which)-\(shape)", width: pixels, height: pixels) {
            $0.scaleBy(x: CGFloat(pixels) / CGFloat(designSide), y: CGFloat(pixels) / CGFloat(designSide))
            drawFlat($0, colour: tintColour(which, gold: false), variant: shape)
        }
    }

    private static func drawWhole(_ ctx: CGContext, colour: (Double, Double, Double), gold: Bool) {
        let (r, g, b) = colour
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGPoint(x: Double(designSide) / 2, y: Double(designSide) / 2), R = radius
        let circle = CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)

        // A thin dark shadow ring just outside, so the bubble stands out on a bright picture.
        let shadow = [CGColor(red: 0, green: 0, blue: 0, alpha: 0), CGColor(red: 0, green: 0, blue: 0, alpha: 0),
                      CGColor(red: 0, green: 0, blue: 0, alpha: 0.2), CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: shadow, locations: [0, 0.8, 0.93, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: c.x + 2, y: c.y - 3), startRadius: 0,
                                   endCenter: CGPoint(x: c.x + 2, y: c.y - 3), endRadius: R + 6, options: [])
        }

        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        // The glassy body: clear in the middle, tinted and denser toward the rim.
        let bodyAlpha: CGFloat = gold ? 0.5 : 0.2
        let body = [CGColor(red: r, green: g, blue: b, alpha: 0.04), CGColor(red: r, green: g, blue: b, alpha: gold ? 0.2 : 0.09),
                    CGColor(red: r * 0.7, green: g * 0.75, blue: b * 0.9, alpha: bodyAlpha + 0.1)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: body, locations: [0, 0.6, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: c.x - R * 0.2, y: c.y + R * 0.25), startRadius: 0,
                                   endCenter: c, endRadius: R * 1.15, options: [.drawsAfterEndLocation])
        }
        // Light bending through the bottom edge.
        ctx.glow(center: CGPoint(x: c.x + R * 0.38, y: c.y - R * 0.52), radius: R * 0.72, red: 1, green: 1, blue: 1, alpha: 0.26)
        ctx.restoreGState()

        // The rim: bright where the light hits, darker on the far side.
        ctx.setLineWidth(3.5)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.addArc(center: c, radius: R - 2, startAngle: 0.5 * .pi, endAngle: 1.15 * .pi, clockwise: false)
        ctx.strokePath()
        ctx.setStrokeColor(CGColor(red: r * 0.55, green: g * 0.6, blue: b * 0.8, alpha: 0.75))
        ctx.addArc(center: c, radius: R - 2, startAngle: 1.2 * .pi, endAngle: 2.45 * .pi, clockwise: false)
        ctx.strokePath()

        // The shine.
        ctx.saveGState()
        ctx.translateBy(x: c.x - R * 0.38, y: c.y + R * 0.42)
        ctx.rotate(by: .pi * 0.22)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.fillEllipse(in: CGRect(x: -R * 0.27, y: -R * 0.14, width: R * 0.54, height: R * 0.28))
        ctx.restoreGState()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
        ctx.fillEllipse(in: CGRect(x: c.x + R * 0.42 - 4.5, y: c.y - R * 0.42 - 4.5, width: 9, height: 9))
        if gold {
            // A four-point sparkle in the middle.
            let s = R * 0.34
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0.9, alpha: 0.95))
            ctx.move(to: CGPoint(x: c.x, y: c.y + s))
            ctx.addLine(to: CGPoint(x: c.x + s * 0.28, y: c.y + s * 0.28))
            ctx.addLine(to: CGPoint(x: c.x + s, y: c.y))
            ctx.addLine(to: CGPoint(x: c.x + s * 0.28, y: c.y - s * 0.28))
            ctx.addLine(to: CGPoint(x: c.x, y: c.y - s))
            ctx.addLine(to: CGPoint(x: c.x - s * 0.28, y: c.y - s * 0.28))
            ctx.addLine(to: CGPoint(x: c.x - s, y: c.y))
            ctx.addLine(to: CGPoint(x: c.x - s * 0.28, y: c.y + s * 0.28))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    private static func drawFlat(_ ctx: CGContext, colour: (Double, Double, Double), variant: Int) {
        let (r, g, b) = colour
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var rng = SplitMix64(seed: UInt64(variant) &* 104_729 &+ 3)
        let c = CGPoint(x: Double(designSide) / 2, y: Double(designSide) / 2), R = radius * 0.94
        let circle = CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)

        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        // A dull, slightly dented disc.
        let dent = [CGColor(red: 0.1, green: 0.12, blue: 0.2, alpha: 0.14), CGColor(red: r * 0.5, green: g * 0.5, blue: b * 0.6, alpha: 0.10),
                    CGColor(red: 0.1, green: 0.12, blue: 0.2, alpha: 0.05)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: dent, locations: [0, 0.7, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: R, options: [.drawsAfterEndLocation])
        }
        // Creases: a dark line with a light line beside it, so they look pressed into the plastic. Short and curved, not cracks.
        ctx.setLineCap(.round)
        for _ in 0..<3 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), reach = Double.random(in: 0.2...0.55, using: &rng) * R
            let from = CGPoint(x: c.x + cos(a) * reach, y: c.y + sin(a) * reach)
            let heading = a + Double.random(in: 1.2...2.0, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
            let length = Double.random(in: 0.5...0.9, using: &rng) * R
            let to = CGPoint(x: from.x + cos(heading) * length, y: from.y + sin(heading) * length)
            let bend = CGPoint(x: (from.x + to.x) / 2 + Double.random(in: -12...12, using: &rng), y: (from.y + to.y) / 2 + Double.random(in: -12...12, using: &rng))
            let crease = CGMutablePath()
            crease.move(to: from)
            crease.addQuadCurve(to: to, control: bend)
            ctx.addPath(crease)
            ctx.setStrokeColor(CGColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 0.3))
            ctx.setLineWidth(2.6)
            ctx.strokePath()
            ctx.saveGState()
            ctx.translateBy(x: 1.6, y: -1.6)
            ctx.addPath(crease)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
            ctx.setLineWidth(1.6)
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.restoreGState()

        // A pressed-in rim: light on the near side, dark on the far side, the opposite of a raised bubble.
        ctx.setLineWidth(3)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.6))
        ctx.addArc(center: c, radius: R - 1.5, startAngle: 1.25 * .pi, endAngle: 2.2 * .pi, clockwise: false)
        ctx.strokePath()
        ctx.setStrokeColor(CGColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 0.45))
        ctx.addArc(center: c, radius: R - 1.5, startAngle: 0.25 * .pi, endAngle: 1.2 * .pi, clockwise: false)
        ctx.strokePath()
    }
}
