import CoreGraphics
import CoreImage
import simd

/// Cherry blossom petals (or autumn leaves) fluttering down in slow drifts: they spin end over end, swing on the wind, come in
/// flurries, and the near ones settle on your head and shoulders for a moment.
struct PetalDriftSim {
    enum Style {
        case sakura, autumn
    }

    struct Petal {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var angle: Double
        var spin: Double
        var flip: Double
        var flipRate: Double
        var size: Double
        var variant: Int
        /// 0 far (small, behind you) to 1 very close (large and out of focus).
        var depth: Double
        var swayPhase: Double
        var swayRate: Double
        var age = 0.0
        var life = 60.0
        var resting = false
        /// How long whatever it rests on has been missing; a cutout that drops out for a frame does not shake it off.
        var unsupported = 0.0

        /// Whether it is drawn behind the person.
        var isBehind: Bool { depth < 0.5 }
        /// Close enough to be a soft blur rather than a shape.
        var isBlur: Bool { depth > 0.95 }
    }

    static let variants = 4

    let style: Style
    let size: CGSize
    private(set) var petals: [Petal] = []
    private(set) var time = 0.0
    private var rng: SplitMix64
    private var owed = 0.0
    private var untilFlurry = 4.0
    var capacity = 210

    init(style: Style, size: CGSize, seed: UInt64 = 0x5A4A) {
        self.style = style
        self.size = size
        rng = SplitMix64(seed: seed)
        // Start with a sky already full of petals rather than an empty one.
        for _ in 0..<300 { step(1.0 / 30, matte: nil) }
        time = 0
    }

    var restingCount: Int { petals.filter(\.resting).count }

    /// The wind, in pixels a second: long slow swings left and right, so petals travel in drifts.
    static func wind(at t: Double) -> Double { 74 * sin(t * 0.31) + 34 * sin(t * 0.83 + 1.7) }

    private mutating func spawn(x: Double, y: Double, push: Double = 0) {
        let depth = Double.random(in: 0...1, using: &rng)
        let big = style == .sakura ? 15.0 + 28 * depth : 22.0 + 30 * depth
        petals.append(Petal(position: SIMD2(x, y), velocity: SIMD2(push, -40),
                            angle: Double.random(in: 0..<(2 * .pi), using: &rng), spin: Double.random(in: -2.2...2.2, using: &rng),
                            flip: Double.random(in: 0..<(2 * .pi), using: &rng), flipRate: Double.random(in: 2.4...6.0, using: &rng),
                            size: big * Double.random(in: 0.85...1.15, using: &rng), variant: Int.random(in: 0..<Self.variants, using: &rng), depth: depth,
                            swayPhase: Double.random(in: 0..<(2 * .pi), using: &rng), swayRate: Double.random(in: 1.1...2.3, using: &rng)))
        if petals.count > capacity { petals.removeFirst(petals.count - capacity) }
    }

    /// A gust throws a cluster of petals in from the side the wind blows from.
    mutating func flurry() {
        let dir = Self.wind(at: time) >= 0 ? 1.0 : -1.0
        let x = dir > 0 ? -50.0 : size.width + 50
        let baseY = Double.random(in: size.height * 0.45...size.height * 0.95, using: &rng)
        for _ in 0..<28 {
            spawn(x: x + Double.random(in: -60...60, using: &rng) * -dir, y: baseY + Double.random(in: -120...120, using: &rng),
                  push: dir * Double.random(in: 260...460, using: &rng))
        }
    }

    mutating func step(_ rawDt: Double, matte: MatteQuery?) {
        let dt = WorldKit.clamped(rawDt)
        time += dt

        owed += 11 * dt
        let wind = Self.wind(at: time)
        while owed >= 1 {
            owed -= 1
            // They start above the picture, further upwind when the wind is strong.
            let shift = wind * 3.2
            spawn(x: Double.random(in: -80...(size.width + 80), using: &rng) - shift, y: size.height + 30)
        }
        untilFlurry -= dt
        if untilFlurry <= 0 {
            flurry()
            untilFlurry = Double.random(in: 6...11, using: &rng)
        }

        for i in petals.indices {
            var p = petals[i]
            p.age += dt
            if p.resting {
                let held = matte.map { $0.coverage(x: p.position.x, y: p.position.y) >= 0.25 } ?? true
                p.unsupported = held ? 0 : p.unsupported + dt
                if p.unsupported > 0.12 { p.resting = false } else {
                    p.angle += sin(p.age * 3 + p.swayPhase) * 0.01
                    petals[i] = p
                    continue
                }
            }
            p.flip += p.flipRate * dt
            p.angle += p.spin * dt

            // A petal glides when it lies flat and drops when it turns edge on: that is the flutter.
            let edgeOn = 1 - abs(cos(p.flip))
            let fall = (36 + 46 * p.depth) * (0.75 + 0.9 * edgeOn)
            let sway = sin(p.age * p.swayRate + p.swayPhase) * (30 + 26 * p.depth)
            let target = SIMD2(wind * (0.55 + 0.7 * p.depth) + sway, -fall)
            p.velocity += (target - p.velocity) * (1 - exp(-1.5 * dt))
            let before = p.position
            p.position += p.velocity * dt

            if let matte, !p.isBehind, !p.isBlur, p.velocity.y < 0,
               matte.coverage(x: p.position.x, y: p.position.y) > 0.5 || matte.coverage(x: (before.x + p.position.x) / 2, y: (before.y + p.position.y) / 2) > 0.5 {
                p.resting = true
                p.velocity = .zero
                p.life = p.age + 2.4 + Double.random(in: 0...3.4, using: &rng)
            }
            petals[i] = p
        }
        petals.removeAll { $0.age >= $0.life || $0.position.y < -50 || $0.position.x < -260 || $0.position.x > size.width + 260 }
    }
}

final class PetalDriftLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private let style: PetalDriftSim.Style
    private let size: CGSize
    private var drift: PetalDriftSim
    /// The four petals (or leaves), sharp and out of focus, and the blossom branch. Made on the first frame, on the video queue.
    private var sprites: [CGImage?] = []
    private var softSprites: [CGImage?] = []
    private var branch: CGImage?
    private var prepared = false

    init(style: PetalDriftSim.Style = .sakura, size: CGSize = CGSize(width: 1280, height: 720)) {
        self.style = style
        self.size = size
        drift = PetalDriftSim(style: style, size: size)
    }

    /// Starts again with a sky full of petals, as at the first frame.
    func restart() { drift = PetalDriftSim(style: style, size: size) }

    var petalCount: Int { drift.petals.count }
    var restingCount: Int { drift.restingCount }
    var petals: [PetalDriftSim.Petal] { drift.petals }
    /// Throws a flurry in at once. For tests and previews.
    func flurry() { drift.flurry() }

    private func prepare(_ context: CIContext) {
        guard !prepared else { return }
        prepared = true
        sprites = (0..<PetalDriftSim.variants).map { Self.sprite(style: style, variant: $0) }
        // Out of focus: the same art blurred once.
        softSprites = sprites.map { sharp in
            guard let sharp else { return nil }
            let pad = 14.0
            let box = CGRect(x: -pad, y: -pad, width: Double(sharp.width) + pad * 2, height: Double(sharp.height) + pad * 2)
            let blurred = CIImage(cgImage: sharp).clampedToExtent().cropped(to: CGRect(x: 0, y: 0, width: sharp.width, height: sharp.height))
                .composited(over: CIImage(color: .clear).cropped(to: box)).applyingGaussianBlur(sigma: 4.5).cropped(to: box)
            return context.createCGImage(blurred, from: box, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        if style == .sakura { branch = Self.makeBranch() }
    }

    func render(_ input: LensInput) -> CIImage {
        prepare(input.services.context)
        drift.step(input.dt, matte: input.matteGrid)

        // A warm, soft light over everything.
        let warm = style == .sakura
            ? WorldKit.grade(input.composed, saturation: 1.05, tint: (1.04, 1.0, 1.02), lift: (0.004, 0.002, 0.003))
            : WorldKit.grade(input.composed, saturation: 1.1, tint: (1.06, 0.98, 0.90), lift: (0.006, 0.003, 0))
        let warmRoom = style == .sakura
            ? WorldKit.grade(input.scenery, saturation: 1.05, tint: (1.04, 1.0, 1.02), lift: (0.004, 0.002, 0.003))
            : WorldKit.grade(input.scenery, saturation: 1.1, tint: (1.06, 0.98, 0.90), lift: (0.006, 0.003, 0))

        // Sunlight coming in from the upper left, as light added to the room, and catching your hair and shoulders.
        let sun = style == .sakura ? SIMD3(1.0, 0.84, 0.88) : SIMD3(1.0, 0.78, 0.5)
        let sunlit = WorldKit.adding(WorldKit.wash(center: CGPoint(x: input.rect.width * 0.1, y: input.rect.height * 1.02), radius: 520,
                                                   red: sun.x, green: sun.y, blue: sun.z, alpha: 0.16, in: input.rect), to: warmRoom)
        var behind = sunlit
        if let layer = input.services.overlay({ ctx in draw(in: ctx, near: false, time: input.time) }) { behind = layer.composited(over: sunlit) }
        var body = WorldKit.place(person: warm, over: behind, matte: input.matte, rect: input.rect)
        if let rim = WorldKit.rimLight(matte: input.matte, rect: input.rect, toward: WorldKit.keyLight, width: 12, colour: sun, strength: 0.3) {
            body = WorldKit.adding(rim, to: body)
        }
        guard let front = input.services.overlay({ ctx in draw(in: ctx, near: true, time: input.time) }) else { return body }
        return front.composited(over: body).cropped(to: input.rect)
    }

    // MARK: Drawing

    private func draw(in ctx: CGContext, near: Bool, time: Double) {
        ctx.interpolationQuality = .low       // turned and squashed small sprites: bilinear is plenty
        defer { ctx.interpolationQuality = .high }
        if near, let branch {
            // The branch hangs in from the top left corner, swaying a little.
            ctx.saveGState()
            ctx.interpolationQuality = .high
            ctx.translateBy(x: 0, y: size.height)
            ctx.rotate(by: 0.014 * sin(time * 0.7) + 0.006 * sin(time * 1.9))
            ctx.draw(branch, in: CGRect(x: 0, y: -Double(branch.height), width: Double(branch.width), height: Double(branch.height)))
            ctx.restoreGState()
            ctx.interpolationQuality = .low
        }
        for p in drift.petals where p.isBehind != near {
            let fadeOut = p.resting ? min(1, (p.life - p.age) / 0.9) : 1
            if p.isBlur {
                // So close it is out of focus: a soft blot of colour.
                let c = Self.blurColour(style: style, variant: p.variant)
                if let dot = WorldKit.dot(c.r, c.g, c.b) {
                    ctx.stampDot(dot, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * 1.1, alpha: 0.26 * fadeOut)
                }
                continue
            }
            // Far petals and the nearest ones are out of focus; the middle depth is sharp.
            let soft = p.depth < 0.28 || p.depth > 0.8
            guard let sprite = (soft ? softSprites : sprites)[p.variant % max(1, sprites.count)] ?? sprites[p.variant % max(1, sprites.count)] else { continue }
            let squash = max(0.2, abs(cos(p.flip)))
            let tone = 0.62 + 0.38 * squash                                // shaded when turned away
            let aspect = CGFloat(sprite.height) / CGFloat(sprite.width)
            var width = p.size * (style == .sakura ? 0.9 : 1.0)
            if soft, let sharp = sprites[p.variant % sprites.count] { width *= Double(sprite.width) / Double(sharp.width) }
            let height = width * aspect
            let haze = p.depth < 0.28 ? 0.7 : 1
            ctx.saveGState()
            ctx.translateBy(x: p.position.x, y: p.position.y)
            ctx.rotate(by: p.angle)
            ctx.scaleBy(x: squash, y: 1)
            ctx.setAlpha(min(1, tone * haze) * fadeOut)
            ctx.draw(sprite, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
            ctx.restoreGState()
        }
    }

    private static func blurColour(style: PetalDriftSim.Style, variant: Int) -> (r: Double, g: Double, b: Double) {
        if style == .sakura { return variant % 2 == 0 ? (1.0, 0.72, 0.82) : (1.0, 0.86, 0.9) }
        return variant % 2 == 0 ? (1.0, 0.55, 0.15) : (0.95, 0.75, 0.25)
    }

    // MARK: Sprites

    private static func sprite(style: PetalDriftSim.Style, variant: Int) -> CGImage? {
        switch style {
        case .sakura: return petal(variant: variant)
        case .autumn: return leaf(variant: variant)
        }
    }

    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The outline of a cherry petal with a notch in its tip, in a unit box centred on the origin.
    private static func petalPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -0.5))
        path.addCurve(to: CGPoint(x: 0.46, y: 0.26), control1: CGPoint(x: 0.10, y: -0.30), control2: CGPoint(x: 0.54, y: -0.04))
        path.addCurve(to: CGPoint(x: 0.12, y: 0.50), control1: CGPoint(x: 0.40, y: 0.44), control2: CGPoint(x: 0.24, y: 0.53))
        path.addCurve(to: CGPoint(x: 0, y: 0.37), control1: CGPoint(x: 0.07, y: 0.49), control2: CGPoint(x: 0.02, y: 0.43))
        path.addCurve(to: CGPoint(x: -0.12, y: 0.50), control1: CGPoint(x: -0.02, y: 0.43), control2: CGPoint(x: -0.07, y: 0.49))
        path.addCurve(to: CGPoint(x: -0.46, y: 0.26), control1: CGPoint(x: -0.24, y: 0.53), control2: CGPoint(x: -0.40, y: 0.44))
        path.addCurve(to: CGPoint(x: 0, y: -0.5), control1: CGPoint(x: -0.54, y: -0.04), control2: CGPoint(x: -0.10, y: -0.30))
        path.closeSubpath()
        return path
    }

    /// "Sakura": four petal colours, from a pale tip to a deeper pink where the petal joined the flower.
    private static let petalColours: [(tip: (CGFloat, CGFloat, CGFloat), base: (CGFloat, CGFloat, CGFloat))] = [
        ((1.00, 0.88, 0.92), (0.97, 0.58, 0.74)),
        ((1.00, 0.95, 0.97), (0.99, 0.72, 0.83)),
        ((1.00, 0.80, 0.88), (0.92, 0.46, 0.66)),
        ((0.99, 0.84, 0.90), (0.95, 0.54, 0.72)),
    ]

    /// A cherry petal, pale at the edge and deeper pink where it joins the flower, with a sheen and a faint vein.
    private static func petal(variant: Int) -> CGImage? {
        let w = 80, h = 92
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let c = petalColours[variant % petalColours.count]
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.scaleBy(x: CGFloat(w) - 8, y: CGFloat(h) - 8)
        ctx.addPath(petalPath())
        ctx.clip()
        let colors = [CGColor(red: c.base.0, green: c.base.1, blue: c.base.2, alpha: 1), CGColor(red: c.tip.0, green: c.tip.1, blue: c.tip.2, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.8]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: -0.5), end: CGPoint(x: 0, y: 0.4), options: [.drawsAfterEndLocation])
        }
        // A pale sheen on the lit side and a faint centre vein.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
        ctx.fillEllipse(in: CGRect(x: -0.30, y: -0.05, width: 0.28, height: 0.55))
        ctx.setStrokeColor(CGColor(red: c.base.0 * 0.85, green: c.base.1 * 0.7, blue: c.base.2 * 0.8, alpha: 0.55))
        ctx.setLineWidth(0.016)
        ctx.move(to: CGPoint(x: 0, y: -0.48)); ctx.addLine(to: CGPoint(x: 0, y: 0.2)); ctx.strokePath()
        return ctx.makeImage()
    }

    /// "Harvest": a maple leaf in one of four autumn colours, darker at the stem, with veins and a lit edge.
    private static func leaf(variant: Int) -> CGImage? {
        let palette: [((CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat))] = [
            ((0.93, 0.42, 0.12), (0.70, 0.18, 0.08)), ((0.98, 0.70, 0.20), (0.85, 0.42, 0.10)),
            ((0.82, 0.22, 0.14), (0.55, 0.10, 0.08)), ((0.95, 0.80, 0.32), (0.78, 0.55, 0.16)),
        ]
        let side = 88
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let (light, dark) = palette[variant % palette.count]
        ctx.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2 + 4)
        // Five pointed lobes with small teeth, made by varying the radius round the centre.
        let path = CGMutablePath()
        let steps = 160
        for k in 0...steps {
            let a = Double(k) / Double(steps) * 2 * .pi
            let lobe = pow(abs(cos(2.5 * (a - .pi / 2))), 0.7)
            let teeth = 0.06 * pow(abs(sin(a * 15)), 2)
            let base = a > .pi * 1.32 && a < .pi * 1.68 ? 0.55 : 1.0      // a notch where the stem joins
            let r = 38 * (0.48 + 0.52 * lobe + teeth) * base
            let p = CGPoint(x: r * cos(a), y: r * sin(a))
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let colours = [CGColor(red: light.0, green: light.1, blue: light.2, alpha: 1), CGColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: -10, y: 14), startRadius: 0, endCenter: CGPoint(x: 0, y: -4), endRadius: 46, options: [.drawsAfterEndLocation])
        }
        ctx.setStrokeColor(CGColor(red: dark.0 * 0.8, green: dark.1 * 0.8, blue: dark.2 * 0.8, alpha: 0.7))
        ctx.setLineWidth(1.4)
        for k in 0..<5 {
            let a = Double.pi / 2 + Double(k - 2) * 2 * .pi / 5 * 0.62
            ctx.move(to: CGPoint(x: 0, y: -6))
            ctx.addLine(to: CGPoint(x: 30 * cos(a), y: 30 * sin(a)))
        }
        ctx.strokePath()
        ctx.restoreGState()
        ctx.setStrokeColor(CGColor(red: dark.0 * 0.7, green: dark.1 * 0.7, blue: dark.2 * 0.7, alpha: 1))
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 0, y: -6)); ctx.addLine(to: CGPoint(x: 2, y: -40)); ctx.strokePath()
        return ctx.makeImage()
    }

    /// A cherry branch in blossom, drawn once: a tapering bough with a lit upper edge, two twigs, open flowers with deep pink
    /// hearts and gold stamens, a few buds and new leaves. It hangs in from the top left corner.
    private static func makeBranch() -> CGImage? {
        let w = 540, h = 300
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        func colour(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
        func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
        }
        /// A limb as a filled shape that tapers from `from` to `to` pixels wide, with a highlight on its upper side.
        func limb(_ p: [CGPoint], from: Double, to: Double) -> [CGPoint] {
            var centre: [CGPoint] = []
            for k in 0...40 { centre.append(bezier(p[0], p[1], p[2], p[3], Double(k) / 40)) }
            var upper: [CGPoint] = [], lower: [CGPoint] = []
            for (k, c) in centre.enumerated() {
                let next = centre[min(centre.count - 1, k + 1)], prev = centre[max(0, k - 1)]
                let dx = next.x - prev.x, dy = next.y - prev.y
                let len = max(1e-6, (dx * dx + dy * dy).squareRoot())
                let n = CGPoint(x: -dy / len, y: dx / len)
                let half = (from + (to - from) * Double(k) / 40) / 2
                upper.append(CGPoint(x: c.x + n.x * half, y: c.y + n.y * half))
                lower.append(CGPoint(x: c.x - n.x * half, y: c.y - n.y * half))
            }
            let shape = CGMutablePath()
            shape.addLines(between: upper + lower.reversed())
            shape.closeSubpath()
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 3, height: -6), blur: 10, color: colour(0.1, 0.02, 0.05, 0.35))
            ctx.addPath(shape)
            ctx.setFillColor(colour(0.25, 0.14, 0.13))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            let highlight = CGMutablePath()
            highlight.addLines(between: upper)
            ctx.addPath(highlight)
            ctx.setStrokeColor(colour(0.55, 0.38, 0.33, 0.9))
            ctx.setLineWidth(CGFloat(max(1.5, from * 0.28)))
            ctx.strokePath()
            ctx.restoreGState()
            return centre
        }
        let bough = limb([CGPoint(x: -30, y: 268), CGPoint(x: 150, y: 262), CGPoint(x: 300, y: 196), CGPoint(x: 470, y: 205)], from: 30, to: 6)
        let lowTwig = limb([bough[17], CGPoint(x: 260, y: 170), CGPoint(x: 300, y: 120), CGPoint(x: 345, y: 92)], from: 10, to: 3)
        let highTwig = limb([bough[29], CGPoint(x: 380, y: 240), CGPoint(x: 410, y: 262), CGPoint(x: 445, y: 268)], from: 8, to: 2.5)

        // New leaves, fresh green, tucked in behind the flowers.
        for (at, angle) in [(bough[34], 0.6), (lowTwig[30], -1.1), (bough[12], 2.2)] {
            ctx.saveGState()
            ctx.translateBy(x: at.x, y: at.y)
            ctx.rotate(by: angle)
            let leaf = CGMutablePath()
            leaf.move(to: .zero)
            leaf.addQuadCurve(to: CGPoint(x: 34, y: 0), control: CGPoint(x: 16, y: 12))
            leaf.addQuadCurve(to: .zero, control: CGPoint(x: 16, y: -10))
            ctx.addPath(leaf)
            ctx.setFillColor(colour(0.46, 0.66, 0.30))
            ctx.fillPath()
            ctx.setStrokeColor(colour(0.66, 0.82, 0.45, 0.8))
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: 2, y: 0)); ctx.addLine(to: CGPoint(x: 30, y: 1)); ctx.strokePath()
            ctx.restoreGState()
        }

        // Open flowers along the bough and twigs, larger near the trunk.
        let flowers: [(CGPoint, Double, Double)] = [
            (bough[9], 27, 0.2), (bough[21], 25, 1.1), (lowTwig[18], 22, 0.5), (lowTwig[40], 20, 2.0),
            (highTwig[26], 21, 0.9), (bough[38], 19, 1.7), (bough[30], 15, 0.4),
        ]
        for (at, radius, turn) in flowers { flower(at: at, radius: radius, turn: turn) }
        // Buds: tight pink ovals in green cups.
        for (at, angle) in [(highTwig[40], 0.3), (bough[40], -0.2), (lowTwig[28], -1.6)] {
            ctx.saveGState()
            ctx.translateBy(x: at.x, y: at.y)
            ctx.rotate(by: angle)
            ctx.setFillColor(colour(0.94, 0.48, 0.64))
            ctx.fillEllipse(in: CGRect(x: 0, y: -5, width: 14, height: 10))
            ctx.setFillColor(colour(1, 0.8, 0.88, 0.8))
            ctx.fillEllipse(in: CGRect(x: 4, y: 0, width: 7, height: 3.5))
            ctx.setFillColor(colour(0.40, 0.55, 0.26))
            ctx.fillEllipse(in: CGRect(x: -3, y: -4, width: 7, height: 8))
            ctx.restoreGState()
        }

        func flower(at: CGPoint, radius: Double, turn: Double) {
            ctx.saveGState()
            ctx.translateBy(x: at.x, y: at.y)
            ctx.rotate(by: turn)
            ctx.setShadow(offset: CGSize(width: 2, height: -4), blur: 7, color: colour(0.35, 0.05, 0.15, 0.3))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            for k in 0..<5 {
                ctx.saveGState()
                ctx.rotate(by: Double(k) * 2 * .pi / 5)
                ctx.translateBy(x: 0, y: radius * 0.52)
                ctx.scaleBy(x: radius * 0.98, y: radius * 1.05)
                ctx.addPath(petalPath())
                ctx.clip()
                let colours = [colour(0.93, 0.50, 0.66), colour(1, 0.86, 0.92), colour(1, 0.95, 0.97)] as CFArray
                if let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.55, 1]) {
                    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: -0.5), end: CGPoint(x: 0, y: 0.5), options: [])
                }
                ctx.restoreGState()
            }
            ctx.endTransparencyLayer()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            // The flower's heart and its stamens.
            ctx.fillCircle(center: .zero, radius: radius * 0.22, color: colour(0.80, 0.24, 0.40))
            ctx.setStrokeColor(colour(0.86, 0.36, 0.48))
            ctx.setLineWidth(1)
            for k in 0..<9 {
                let a = Double(k) / 9 * 2 * .pi + 0.2
                let tip = CGPoint(x: cos(a) * radius * 0.42, y: sin(a) * radius * 0.42)
                ctx.move(to: .zero)
                ctx.addLine(to: tip)
                ctx.strokePath()
                ctx.fillCircle(center: tip, radius: 1.8, color: colour(1, 0.84, 0.38))
            }
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }
}
