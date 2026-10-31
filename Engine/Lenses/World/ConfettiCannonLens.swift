import CoreGraphics
import CoreImage
import simd

/// Two party poppers in the bottom corners. Each shot throws paper, foil and curly ribbon into the air; it slows almost at once,
/// tumbles end over end, drifts on a gentle wind, and the pieces in front of you settle on your head and shoulders before they
/// slide off again. Pieces further back pass behind you, smaller and a little dimmer.
struct ConfettiCannonSim {
    enum Shape: Int, CaseIterable {
        case rectangle, strip, disc
        /// A curly streamer that ripples as it falls.
        case ribbon
    }

    struct Piece {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var angle: Double
        var spin: Double
        /// Phase of the end-over-end tumble: the paper is face on when its cosine is 1.
        var flip: Double
        var flipRate: Double
        var size: Double
        var colour: Int
        var shape: Shape
        var age = 0.0
        var life: Double
        var swayPhase: Double
        var swayRate: Double
        /// How much the air holds it up: 0 falls like a stone, 1 floats.
        var lightness: Double
        var bounced = false
        var resting = false
        /// 0 far behind you (small, passes behind) ... 1 right by the camera (big, in front).
        var depth = 0.75
        /// How long whatever it rests on has been missing. A cutout that drops out for a frame or two does not shake it off.
        var unsupported = 0.0

        /// Whether it is drawn behind the person, and so never lands on them.
        var isBehind: Bool { depth < 0.3 }
        /// How big it looks for its depth.
        var scale: Double { 0.55 + 0.65 * depth }
    }

    /// "Party": eight bright colours, then two metallic foils (gold and silver) that flash as they turn.
    static let palette: [(r: Double, g: Double, b: Double)] = [
        (0.98, 0.26, 0.36), (1.00, 0.58, 0.16), (1.00, 0.84, 0.22), (0.38, 0.84, 0.42), (0.18, 0.78, 0.94),
        (0.30, 0.48, 0.98), (0.66, 0.40, 0.95), (1.00, 0.45, 0.76), (0.98, 0.78, 0.36), (0.88, 0.90, 0.96),
    ]
    /// The foil colours, which glint.
    static func isFoil(_ colour: Int) -> Bool { colour >= 8 }

    /// Where each popper's mouth is, and the way it points (radians from the right, counter-clockwise). Both lean in toward you.
    static func muzzle(_ side: Int, in size: CGSize) -> CGPoint {
        CGPoint(x: side == 0 ? 78 : size.width - 78, y: 84)
    }

    static func aim(_ side: Int) -> Double { side == 0 ? 58 * .pi / 180 : 122 * .pi / 180 }

    let size: CGSize
    private(set) var pieces: [Piece] = []
    /// Seconds since each popper (left, right) last fired: drives the flash, the recoil and the smoke.
    private(set) var sinceShot: [Double] = [9, 9]
    private(set) var time = 0.0
    private(set) var shots = 0
    private var rng: SplitMix64
    private var untilNextShot = 0.0
    private var nextSide = 0
    var capacity = 520
    /// Whether the poppers go off by themselves. Tests switch it off to place the confetti exactly.
    var firesByItself = true

    init(size: CGSize, seed: UInt64 = 0xC0F3771) {
        self.size = size
        rng = SplitMix64(seed: seed)
    }

    var restingCount: Int { pieces.filter(\.resting).count }

    mutating func removeAll() {
        pieces.removeAll()
        sinceShot = [9, 9]
        untilNextShot = 0
        time = 0
    }

    /// A gentle wind that comes and goes, in pixels a second.
    static func wind(at t: Double) -> Double { 26 * sin(t * 0.45) + 16 * sin(t * 1.3 + 1.0) }

    /// Puts a piece of paper in the air. For tests.
    mutating func insert(_ piece: Piece) { pieces.append(piece) }

    /// Fires one popper (0 left, 1 right) now.
    mutating func fire(side: Int, count: Int? = nil) {
        let n = count ?? Int.random(in: 85...110, using: &rng)
        let muzzle = Self.muzzle(side, in: size), heading = Self.aim(side)
        sinceShot[side] = 0
        shots += 1
        for _ in 0..<n {
            let angle = heading + Double.random(in: -0.30...0.30, using: &rng)
            // Bunched toward the slow end so the burst has a bright dense core and a few long throws.
            let speed = 560 + 1000 * pow(Double.random(in: 0...1, using: &rng), 1.35)
            let shape: Shape = {
                let r = Double.random(in: 0...1, using: &rng)
                return r < 0.5 ? .rectangle : r < 0.66 ? .strip : r < 0.86 ? .disc : .ribbon
            }()
            let lightness = shape == .ribbon ? Double.random(in: 0...0.35, using: &rng) : Double.random(in: 0...1, using: &rng)
            let along = Double.random(in: 0...26, using: &rng)
            let colour = Double.random(in: 0...1, using: &rng) < 0.16 ? 8 + Int.random(in: 0...1, using: &rng) : Int.random(in: 0..<8, using: &rng)
            pieces.append(Piece(
                position: SIMD2(muzzle.x + cos(heading) * along, muzzle.y + sin(heading) * along),
                velocity: SIMD2(cos(angle), sin(angle)) * speed,
                angle: Double.random(in: 0..<(2 * .pi), using: &rng),
                spin: Double.random(in: -4.5...4.5, using: &rng) * (shape == .ribbon ? 0.4 : 1),
                flip: Double.random(in: 0..<(2 * .pi), using: &rng),
                flipRate: Double.random(in: 5...13, using: &rng) * (Bool.random(using: &rng) ? 1 : -1),
                size: shape == .disc ? Double.random(in: 9...14, using: &rng) : Double.random(in: 13...22, using: &rng),
                colour: colour, shape: shape, life: Double.random(in: 11...15, using: &rng),
                swayPhase: Double.random(in: 0..<(2 * .pi), using: &rng), swayRate: Double.random(in: 2.2...4.6, using: &rng),
                lightness: lightness, depth: Double.random(in: 0...1, using: &rng)))
        }
        if pieces.count > capacity { pieces.removeFirst(pieces.count - capacity) }
    }

    mutating func step(_ rawDt: Double, matte: MatteQuery?) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        sinceShot[0] += dt
        sinceShot[1] += dt

        untilNextShot -= dt
        if untilNextShot <= 0, firesByItself {
            fire(side: nextSide)
            // Every fourth volley both poppers go off together.
            if shots % 4 == 0 { fire(side: 1 - nextSide) }
            nextSide = 1 - nextSide
            untilNextShot = Double.random(in: 1.8...3.0, using: &rng)
        }

        let wind = Self.wind(at: time)
        for i in pieces.indices {
            var p = pieces[i]
            p.age += dt
            if p.resting {
                // Sitting on a shoulder. When the shoulder has really moved away it falls again.
                let held = matte.map { $0.coverage(x: p.position.x, y: p.position.y) >= 0.25 } ?? true
                p.unsupported = held ? 0 : p.unsupported + dt
                if p.unsupported > 0.12 { p.resting = false } else {
                    pieces[i] = p
                    continue
                }
            }
            p.flip += p.flipRate * dt
            p.angle += p.spin * dt

            // Air drag pulls the speed toward a slow drift: wind and sway sideways, a gentle fall (faster edge on).
            let edgeOn = 1 - abs(cos(p.flip))
            let fall = (92 + 60 * (1 - p.lightness)) * (1 + 0.7 * edgeOn)
            let sway = sin(p.age * p.swayRate + p.swayPhase) * (34 + 26 * p.lightness)
            let target = SIMD2(wind * (0.5 + p.lightness) + sway, -fall)
            let drag = 1.15 + 0.9 * p.lightness
            p.velocity += (target - p.velocity) * (1 - exp(-drag * dt))
            let before = p.position
            p.position += p.velocity * dt

            if let matte, !p.isBehind, p.velocity.y < 0, Self.touches(matte, from: before, to: p.position) {
                if !p.bounced {
                    // First touch: a little hop, then it settles on the second.
                    p.bounced = true
                    p.velocity = SIMD2(p.velocity.x * 0.3 + Double.random(in: -70...70, using: &rng), Double.random(in: 90...190, using: &rng))
                    p.position = before
                } else {
                    p.resting = true
                    p.velocity = .zero
                    p.life = p.age + 2.6 + Double.random(in: 0...3.2, using: &rng)
                }
            }
            pieces[i] = p
        }
        pieces.removeAll { $0.age >= $0.life || $0.position.y < -30 || $0.position.x < -80 || $0.position.x > size.width + 80 }
    }

    /// Whether a piece that moved from `a` to `b` ended up in, or passed through, the silhouette.
    private static func touches(_ matte: MatteQuery, from a: SIMD2<Double>, to b: SIMD2<Double>) -> Bool {
        if matte.coverage(x: b.x, y: b.y) > 0.5 { return true }
        return matte.coverage(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) > 0.5
    }
}

final class ConfettiCannonLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private var field: ConfettiCannonSim
    private let size: CGSize
    /// Puffs of smoke from the poppers: where, how old, and which way they drift.
    private var puffs: [(position: SIMD2<Double>, velocity: SIMD2<Double>, age: Double, size: Double)] = []
    private var lastShots = 0
    private var rng = SplitMix64(seed: 0xC0F5)

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        self.size = size
        field = ConfettiCannonSim(size: size)
    }

    func restart() {
        field.removeAll()
        puffs.removeAll()
    }

    var pieceCount: Int { field.pieces.count }
    var restingCount: Int { field.restingCount }
    /// Fires a popper at once. For tests and previews.
    func fire(side: Int) { field.fire(side: side) }

    func render(_ input: LensInput) -> CIImage {
        field.step(input.dt, matte: input.matteGrid)
        stepSmoke(WorldKit.clamped(input.dt))

        var behind = input.scenery
        if let layer = input.services.overlay({ ctx in drawPieces(in: ctx, behind: true) }) { behind = layer.composited(over: behind) }
        let body = input.placingPerson(over: behind.cropped(to: input.rect))
        guard let front = input.services.overlay({ ctx in drawFront(in: ctx) }) else { return body }
        return front.composited(over: body).cropped(to: input.rect)
    }

    // MARK: Smoke

    private func stepSmoke(_ dt: Double) {
        if field.shots != lastShots {
            for side in 0..<2 where field.sinceShot[side] < 0.05 {
                let m = ConfettiCannonSim.muzzle(side, in: size), h = ConfettiCannonSim.aim(side)
                for _ in 0..<7 {
                    let a = h + Double.random(in: -0.5...0.5, using: &rng)
                    puffs.append((SIMD2(m.x, m.y) + SIMD2(cos(h), sin(h)) * 20, SIMD2(cos(a), sin(a)) * Double.random(in: 60...220, using: &rng),
                                  0, Double.random(in: 22...40, using: &rng)))
                }
            }
            lastShots = field.shots
        }
        for i in puffs.indices {
            puffs[i].age += dt
            puffs[i].velocity *= exp(-2.4 * dt)
            puffs[i].velocity.y += 26 * dt
            puffs[i].position += puffs[i].velocity * dt
        }
        puffs.removeAll { $0.age > 1.6 }
    }

    // MARK: Drawing

    private func drawFront(in ctx: CGContext) {
        drawPieces(in: ctx, behind: false)
        drawSmoke(in: ctx)
        drawPoppers(in: ctx)
        drawMuzzleFlashes(in: ctx)
    }

    private func drawPieces(in ctx: CGContext, behind: Bool) {
        // Small sprites turned and squashed: plain bilinear is plenty and much cheaper than the canvas's high-quality filter.
        ctx.interpolationQuality = .low
        defer { ctx.interpolationQuality = .high }
        for p in field.pieces where p.isBehind == behind {
            let facing = abs(cos(p.flip))
            let fadeOut = p.resting ? min(1, (p.life - p.age) / 0.8) : 1
            let dim = behind ? 0.82 : 1.0
            if p.shape == .ribbon {
                drawRibbon(p, facing: facing, alpha: fadeOut * dim, in: ctx)
                continue
            }
            let squash = max(0.16, facing)
            let shade = facing > 0.94 ? 3 : facing > 0.72 ? 2 : facing > 0.42 ? 1 : 0
            guard let sprite = sprite(colour: p.colour, shape: p.shape, shade: shade) else { continue }
            let s = p.size * p.scale
            let width: Double, height: Double
            switch p.shape {
            case .rectangle: (width, height) = (s * 1.6, s)
            case .strip: (width, height) = (s * 3.4, s * 0.55)
            case .disc, .ribbon: (width, height) = (s, s)
            }
            // A fast piece near the camera smears along its path.
            let speed = simd_length(p.velocity)
            let smear = p.depth > 0.7 && speed > 380 ? min(2.2, 1 + (speed - 380) / 500) : 1
            ctx.saveGState()
            ctx.translateBy(x: p.position.x, y: p.position.y)
            if smear > 1.01 {
                ctx.rotate(by: atan2(p.velocity.y, p.velocity.x))
                ctx.scaleBy(x: smear, y: 1 / smear.squareRoot())
                ctx.rotate(by: -atan2(p.velocity.y, p.velocity.x))
            }
            ctx.rotate(by: p.angle)
            ctx.scaleBy(x: 1, y: squash)
            ctx.setAlpha(fadeOut * dim / (smear > 1.01 ? smear * 0.8 : 1))
            ctx.draw(sprite, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
            ctx.restoreGState()
            // Foil catches the light for an instant as it turns face on.
            if ConfettiCannonSim.isFoil(p.colour), facing > 0.97, !behind, let glint = WorldKit.star(1, 0.95, 0.8) {
                ctx.setBlendMode(.plusLighter)
                ctx.stampDot(glint, at: CGPoint(x: p.position.x, y: p.position.y), radius: s * 1.3, alpha: (facing - 0.97) / 0.03 * fadeOut)
                ctx.setBlendMode(.normal)
            }
        }
    }

    /// A curly streamer: a ribbon that ripples along its length, darker where it turns away.
    private func drawRibbon(_ p: ConfettiCannonSim.Piece, facing: Double, alpha: Double, in ctx: CGContext) {
        let base = ConfettiCannonSim.palette[p.colour % ConfettiCannonSim.palette.count]
        let tone = 0.62 + 0.38 * facing
        let length = p.size * 4.2 * p.scale, amplitude = p.size * 0.42 * p.scale
        let path = CGMutablePath()
        let steps = 14
        for k in 0...steps {
            let u = Double(k) / Double(steps)
            let x = (u - 0.5) * length
            let y = sin(u * 2 * .pi * 1.7 + p.age * 7 + p.swayPhase) * amplitude * (0.6 + 0.4 * sin(u * .pi))
            if k == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.saveGState()
        ctx.translateBy(x: p.position.x, y: p.position.y)
        ctx.rotate(by: p.angle * 0.6 - 0.9)
        ctx.setAlpha(alpha)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.setLineWidth(max(1.6, 3.6 * p.scale))
        ctx.setStrokeColor(CGColor(red: base.r * tone * 0.8, green: base.g * tone * 0.8, blue: base.b * tone * 0.8, alpha: 1))
        ctx.strokePath()
        // A thin highlight along the top edge, as a ribbon is shiny.
        ctx.translateBy(x: -0.5, y: 0.8)
        ctx.addPath(path)
        ctx.setLineWidth(max(0.8, 1.4 * p.scale))
        ctx.setStrokeColor(CGColor(red: min(1, base.r * tone + 0.25), green: min(1, base.g * tone + 0.25), blue: min(1, base.b * tone + 0.25), alpha: 0.9))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawSmoke(in ctx: CGContext) {
        guard let puff = WorldKit.softGlow(0.92, 0.9, 0.95) else { return }
        for p in puffs {
            let k = p.age / 1.6
            ctx.stampDot(puff, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (0.6 + 1.6 * k), alpha: 0.32 * (1 - k) * (1 - k))
        }
    }

    private func drawPoppers(in ctx: CGContext) {
        for side in 0..<2 {
            guard let art = Self.popper(litAbove: side == 0) else { continue }
            let muzzle = ConfettiCannonSim.muzzle(side, in: size), heading = ConfettiCannonSim.aim(side)
            // Kicks back when it fires and springs into place with a little overshoot.
            let since = field.sinceShot[side]
            let recoil = 18 * exp(-since * 7) * cos(since * 16)
            let swell = 1 + 0.05 * exp(-since * 10)
            ctx.saveGState()
            ctx.translateBy(x: muzzle.x - cos(heading) * recoil, y: muzzle.y - sin(heading) * recoil)
            ctx.rotate(by: heading)
            ctx.scaleBy(x: 1, y: swell)
            let w = Double(art.width) / 2, h = Double(art.height) / 2
            ctx.draw(art, in: CGRect(x: -w + Self.mouthInset, y: -h / 2, width: w, height: h))
            ctx.restoreGState()
        }
    }

    /// A bright pop at the mouth of a popper that has just gone off, over in a fifth of a second.
    private func drawMuzzleFlashes(in ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        defer { ctx.setBlendMode(.normal) }
        for side in 0..<2 where field.sinceShot[side] < 0.22 {
            let k = pow(1 - field.sinceShot[side] / 0.22, 2)
            let m = ConfettiCannonSim.muzzle(side, in: size), h = ConfettiCannonSim.aim(side)
            let centre = CGPoint(x: m.x + cos(h) * 34, y: m.y + sin(h) * 34)
            // Drawn as smooth gradients rather than a stretched sprite, which would band at this size.
            ctx.glow(center: centre, radius: 150 * (1.2 - 0.5 * k), red: 1, green: 0.85, blue: 0.55, alpha: 0.5 * k)
            ctx.glow(center: centre, radius: 56 * (1.2 - 0.4 * k), red: 1, green: 1, blue: 0.94, alpha: 0.85 * k)
        }
    }

    // MARK: Sprites

    private var sprites: [Int: CGImage] = [:]

    private func sprite(colour: Int, shape: ConfettiCannonSim.Shape, shade: Int) -> CGImage? {
        let key = (colour * 8 + shape.rawValue) * 4 + shade
        if let hit = sprites[key] { return hit }
        guard let made = Self.makeSprite(colour: colour, shape: shape, shade: shade) else { return nil }
        sprites[key] = made
        return made
    }

    /// A piece of paper in one colour, seen at one of four brightnesses: dark edge on, bright when it catches the light face on.
    /// Foil goes nearly white at its brightest.
    private static func makeSprite(colour: Int, shape: ConfettiCannonSim.Shape, shade: Int) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let w = 48, h = shape == .strip ? 24 : 48
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let base = ConfettiCannonSim.palette[colour % ConfettiCannonSim.palette.count]
        let foil = ConfettiCannonSim.isFoil(colour)
        let level = [0.55, 0.78, 0.96, 1.0][shade], whiten = shade == 3 ? (foil ? 0.7 : 0.3) : 0.0
        func tone(_ v: Double, _ lift: Double) -> CGFloat { CGFloat(min(1, max(0, (v * level + lift) * (1 - whiten) + whiten))) }
        let top = CGColor(red: tone(base.r, 0.12), green: tone(base.g, 0.12), blue: tone(base.b, 0.12), alpha: 1)
        let bottom = CGColor(red: tone(base.r, -0.1), green: tone(base.g, -0.1), blue: tone(base.b, -0.1), alpha: 1)
        let rect = CGRect(x: 2, y: 2, width: w - 4, height: h - 4)
        if shape == .disc { ctx.addEllipse(in: rect) } else { ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)) }
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]) {
            // Lit from the top left, like everything else.
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: CGFloat(w), y: 0), options: [])
        }
        if foil {
            // A crinkle of light across the foil.
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
            ctx.fill(CGRect(x: 0, y: CGFloat(h) * 0.55, width: CGFloat(w), height: CGFloat(h) * 0.12))
        }
        return ctx.makeImage()
    }

    /// How far into the sprite the popper's mouth is, so its mouth sits on the muzzle point.
    private static let mouthInset = 14.0

    private static let popperLock = NSLock()
    private static var poppers: [Bool: CGImage] = [:]

    /// A party popper drawn once at twice the size it is shown: a striped cone, shaded as a round thing lit from above, a gold
    /// foil rim round its mouth with the dark inside showing, and a pull string at the back. Pointing right, mouth at the right.
    private static func popper(litAbove: Bool) -> CGImage? {
        popperLock.lock(); defer { popperLock.unlock() }
        if let hit = poppers[litAbove] { return hit }
        let w = 440, h = 220
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        ctx.scaleBy(x: 2, y: 2)
        ctx.translateBy(x: 0, y: 55)
        if !litAbove { ctx.scaleBy(x: 1, y: -1) }
        let mouthX: CGFloat = 220 - CGFloat(mouthInset), tailX: CGFloat = 26
        let mouthR: CGFloat = 46, tailR: CGFloat = 15
        func colour(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }

        // A soft shadow behind it so it stands off any backdrop.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 3, height: -5), blur: 14, color: colour(0, 0, 0, 0.45))
        let body = CGMutablePath()
        body.move(to: CGPoint(x: tailX, y: -tailR))
        body.addLine(to: CGPoint(x: mouthX, y: -mouthR))
        body.addLine(to: CGPoint(x: mouthX, y: mouthR))
        body.addLine(to: CGPoint(x: tailX, y: tailR))
        body.addArc(center: CGPoint(x: tailX, y: 0), radius: tailR, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
        body.closeSubpath()
        ctx.addPath(body)
        ctx.setFillColor(colour(0.80, 0.12, 0.24))
        ctx.fillPath()
        ctx.restoreGState()

        // Spiral stripes in gold, then shading across the cone so it reads as round.
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        ctx.setFillColor(colour(1.0, 0.80, 0.28))
        for k in -1..<6 {
            let x = CGFloat(k) * 40 + 20
            let stripe = CGMutablePath()
            stripe.move(to: CGPoint(x: x, y: -60)); stripe.addLine(to: CGPoint(x: x + 17, y: -60))
            stripe.addLine(to: CGPoint(x: x + 43, y: 60)); stripe.addLine(to: CGPoint(x: x + 26, y: 60)); stripe.closeSubpath()
            ctx.addPath(stripe)
            ctx.fillPath()
        }
        let shading = [colour(1, 1, 1, 0.38), colour(1, 1, 1, 0.08), colour(0, 0, 0, 0.05), colour(0.15, 0, 0.05, 0.5)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: shading, locations: [0, 0.3, 0.55, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: mouthR), end: CGPoint(x: 0, y: -mouthR), options: [])
        }
        // A thin bright streak where the light catches the curve.
        ctx.setStrokeColor(colour(1, 1, 1, 0.55))
        ctx.setLineWidth(2.4)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: tailX + 12, y: tailR * 0.55))
        ctx.addLine(to: CGPoint(x: mouthX - 18, y: mouthR * 0.62))
        ctx.strokePath()
        ctx.restoreGState()

        // The pull string at the back, a little curl of twine with a bead.
        ctx.setStrokeColor(colour(0.95, 0.9, 0.78))
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: tailX - tailR + 2, y: 0))
        ctx.addCurve(to: CGPoint(x: -6, y: -14), control1: CGPoint(x: 0, y: 10), control2: CGPoint(x: -14, y: 4))
        ctx.strokePath()
        ctx.fillCircle(center: CGPoint(x: -6, y: -15), radius: 4, color: colour(0.98, 0.82, 0.3))

        // The mouth: a gold foil rim, the dark inside, and a sliver of light on the rim's upper edge.
        let rim = CGRect(x: mouthX - 11, y: -mouthR - 3, width: 22, height: mouthR * 2 + 6)
        let gold = [colour(1, 0.94, 0.62), colour(0.92, 0.66, 0.16), colour(0.62, 0.38, 0.06)] as CFArray
        ctx.saveGState()
        ctx.addEllipse(in: rim)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: space, colors: gold, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rim.maxY), end: CGPoint(x: 0, y: rim.minY), options: [])
        }
        ctx.restoreGState()
        let inside = rim.insetBy(dx: 5, dy: 7)
        ctx.saveGState()
        ctx.addEllipse(in: inside)
        ctx.clip()
        let dark = [colour(0.08, 0.02, 0.05), colour(0.30, 0.06, 0.12)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: dark, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: inside.maxY), end: CGPoint(x: 0, y: inside.minY), options: [])
        }
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: rim.midX, y: rim.midY)
        ctx.scaleBy(x: rim.width / rim.height, y: 1)
        ctx.setStrokeColor(colour(1, 1, 0.9, 0.85))
        ctx.setLineWidth(3)
        ctx.addArc(center: .zero, radius: rim.height / 2 - 1.5, startAngle: .pi * 0.55, endAngle: .pi * 0.85, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()

        guard let image = ctx.makeImage() else { return nil }
        poppers[litAbove] = image
        return image
    }
}
