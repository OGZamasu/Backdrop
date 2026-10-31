import CoreGraphics
import CoreImage
import simd

/// A magic wand that grows from a pointing finger. Point and a lacquered wand with a golden star slides out along the finger; move it and
/// the star leaves a trail of twinkling sparkles; flick it and it casts a spell: a burst of stars thrown the way you flicked and a ring of
/// light where the star was.
struct MagicWandRig {
    struct Wand {
        var aiming = HandFXLatch(on: 0.55, off: 0.28, holdOn: 0.06, holdOff: 0.22)
        /// 0...1 (a little more as it springs out): how far the wand is out.
        var out = 0.0
        var outSpeed = 0.0
        /// Where it points, radians, smoothed.
        var angle: Double?
        var grip = HandFXSteady(calm: 2.2, eager: 0.03)
        /// How the star is moving, pixels a second, smoothed.
        var velocity = SIMD2<Double>(0, 0)
        var lastStar: SIMD2<Double>?
        var cooldown = 0.0
        var owed = 0.0
    }

    struct Pose {
        var hand: Int
        var grip: CGPoint
        var star: CGPoint
        var direction: SIMD2<Double>
        var length: Double
        var strength: Double
        var handSize: Double
    }

    /// A ring of light where a spell was cast.
    struct Burst {
        var centre: CGPoint
        var age = 0.0
    }

    enum Kind: Int {
        case glint = 0, speck = 1
    }

    private(set) var memory = HandFXMemory<Wand>()
    private(set) var sparkles = ParticleSystem(capacity: 240)
    private(set) var bursts: [Burst] = []
    private(set) var casts = 0
    private(set) var time = 0.0
    private var steadier = HandFXSteadier()
    private var rng = SplitMix64(seed: 0x3A61C)

    init() {
        sparkles.gravity = SIMD2(0, -70)
        sparkles.drag = 1.4
    }

    mutating func removeAll() {
        memory.removeAll()
        sparkles.removeAll()
        bursts.removeAll()
        steadier.removeAll()
    }

    static func length(for hand: HandState) -> Double { min(300, max(120, hand.size * 1.75)) }

    mutating func update(hands raw: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        let hands = steadier.update(raw, dt: dt)
        memory.update(hands, dt: dt, fade: 0.35) { _ in Wand() }
        for i in memory.entries.indices {
            var entry = memory.entries[i]
            var wand = entry.state
            wand.cooldown = max(0, wand.cooldown - dt)
            if entry.visible {
                let hand = entry.hand
                wand.aiming.update(HandFXPose.point(hand), dt: entry.age < 1e-9 ? 1 : dt)
                let raw = atan2(Double(hand.aim.dy), Double(hand.aim.dx))
                if let a = wand.angle {
                    wand.angle = a + atan2(sin(raw - a), cos(raw - a)) * (1 - exp(-dt / 0.05))
                } else {
                    wand.angle = raw
                }
                wand.grip.update(hand.indexTip, dt: dt, snap: max(160, hand.size * 2.5))
            }
            // A spring slides it out and back.
            let target = entry.visible && wand.aiming.isOn ? 1.0 : 0.0
            let pull = target > wand.out ? 210.0 : 260.0, damping = target > wand.out ? 17.0 : 30.0
            wand.outSpeed += (pull * (target - wand.out) - damping * wand.outSpeed) * dt
            wand.out = max(0, wand.out + wand.outSpeed * dt)
            if wand.out < 0.002, target == 0 { wand.out = 0; wand.outSpeed = 0 }
            entry.state = wand
            memory.modify(i) { $0 = entry }
        }
        for pose in poses { sparkle(pose, dt: dt) }
        for i in bursts.indices { bursts[i].age += dt }
        bursts.removeAll { $0.age > 0.45 }
        sparkles.step(dt)
    }

    var poses: [Pose] {
        memory.entries.compactMap { entry in
            guard let angle = entry.state.angle, let grip = entry.state.grip.point else { return nil }
            let strength = min(1, entry.state.out) * entry.presence
            guard entry.state.out > 0.01, strength > 0.01 else { return nil }
            let d = SIMD2(cos(angle), sin(angle))
            // The wand starts a little back along the finger, so the finger holds it, and slides out from there.
            let start = HandFXKit.vector(grip) - d * entry.hand.size * 0.28
            let length = Self.length(for: entry.hand) * entry.state.out
            return Pose(hand: entry.hand.id, grip: HandFXKit.point(start), star: HandFXKit.point(start + d * length), direction: d,
                        length: length, strength: strength, handSize: entry.hand.size)
        }
    }

    /// The star sheds sparkles as it moves, and a fast flick casts a spell.
    private mutating func sparkle(_ pose: Pose, dt: Double) {
        guard let i = memory.entries.firstIndex(where: { $0.hand.id == pose.hand }), dt > 0 else { return }
        var wand = memory.entries[i].state
        let star = HandFXKit.vector(pose.star)
        // How fast the star is swung is measured where it would be fully out, so the wand sliding out is not taken for a flick.
        let reach = HandFXKit.vector(pose.grip) + pose.direction * Self.length(for: memory.entries[i].hand)
        if let last = wand.lastStar {
            let v = (reach - last) / dt
            wand.velocity += (v - wand.velocity) * min(1, dt / 0.05)
        }
        wand.lastStar = reach
        let speed = simd_length(wand.velocity)
        wand.owed += dt * (8 + min(120, speed * 0.1)) * pose.strength
        var made = 0
        while wand.owed >= 1, made < 12 {
            wand.owed -= 1
            made += 1
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            let glint = Double.random(in: 0..<1, using: &rng) < 0.35
            sparkles.emit(Particle(position: star + SIMD2(cos(a), sin(a)) * Double.random(in: 0...8, using: &rng),
                                   velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 10...60, using: &rng) - wand.velocity * 0.06, age: 0,
                                   life: Double.random(in: 0.7...1.5, using: &rng), size: glint ? Double.random(in: 6...11, using: &rng) : Double.random(in: 2...4, using: &rng),
                                   hue: Double(Int.random(in: 0..<3, using: &rng)) + Double.random(in: 0..<0.9, using: &rng),
                                   kind: glint ? Kind.glint.rawValue : Kind.speck.rawValue))
        }
        if pose.strength > 0.9, speed > max(1000, pose.handSize * 8), wand.cooldown <= 0 {
            cast(at: star, toward: wand.velocity / speed)
            wand.cooldown = 0.45
        }
        memory.modify(i) { $0.state = wand }
    }

    private mutating func cast(at p: SIMD2<Double>, toward d: SIMD2<Double>) {
        casts += 1
        bursts.append(Burst(centre: HandFXKit.point(p)))
        let heading = atan2(d.y, d.x)
        for _ in 0..<36 {
            let a = heading + Double.random(in: -0.6...0.6, using: &rng)
            let glint = Double.random(in: 0..<1, using: &rng) < 0.5
            sparkles.emit(Particle(position: p, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 280...720, using: &rng), age: 0,
                                   life: Double.random(in: 0.6...1.1, using: &rng), size: glint ? Double.random(in: 8...14, using: &rng) : Double.random(in: 2.5...4.5, using: &rng),
                                   hue: Double(Int.random(in: 0..<3, using: &rng)) + Double.random(in: 0..<0.9, using: &rng),
                                   kind: glint ? Kind.glint.rawValue : Kind.speck.rawValue))
        }
    }
}

final class MagicWandLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig = MagicWandRig()
    private var hint = HandFXHint()
    private let published = StatusBox()

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hand", detail: "Point a finger to hold a magic wand") }

    func restart() {
        rig.removeAll()
        hint.reset()
    }

    var wands: [MagicWandRig.Pose] { rig.poses }
    var casts: Int { rig.casts }
    var sparkleCount: Int { rig.sparkles.particles.count }
    var isHinting: Bool { hint.isShowing }

    static let colours: [SIMD3<Double>] = [HandFXPalette.wand.gold, HandFXPalette.wand.rose, HandFXPalette.wand.lilac]

    func render(_ input: LensInput) -> CIImage {
        rig.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        let poses = rig.poses
        published.value = currentStatus(input.hands, poses: poses)
        var out = input.composed
        if !poses.isEmpty || !rig.sparkles.particles.isEmpty || !rig.bursts.isEmpty {
            if let light = input.services.overlay({ ctx in drawLight(in: ctx, poses: poses) }) {
                out = HandFXLight.add(light, to: out, rect: input.rect, bloom: 0.75)
            }
            if !poses.isEmpty, let solid = input.services.overlay({ ctx in drawWands(in: ctx, poses: poses) }) {
                out = solid.composited(over: out)
            }
        }
        return hint.compose(over: out.cropped(to: input.rect), services: input.services, rect: input.rect, accent: HandFXPalette.wand.gold)
    }

    private func currentStatus(_ hands: [HandState], poses: [MagicWandRig.Pose]) -> LensStatus {
        if hands.isEmpty { return LensStatus("Hold up your hand", detail: "Point a finger to hold a magic wand") }
        if poses.contains(where: { $0.strength > 0.5 }) { return LensStatus("Abracadabra", detail: "Flick your finger to cast a spell") }
        return LensStatus("Point a finger", detail: "Index out, other fingers curled")
    }

    // MARK: Drawing

    private static let specks: [CGImage?] = colours.map { HandFXKit.speckSprite($0) }

    private func drawLight(in ctx: CGContext, poses: [MagicWandRig.Pose]) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        let t = rig.time
        for pose in poses {
            // The star's halo, breathing.
            let breathe = 1 + 0.1 * sin(t * 5 + Double(pose.hand))
            HandFXKit.glow(ctx, at: pose.star, radius: pose.handSize * 0.7 * breathe, colour: HandFXPalette.wand.gold, alpha: 0.42 * pose.strength)
            HandFXKit.glow(ctx, at: pose.star, radius: pose.handSize * 0.28, colour: HandFXPalette.white, alpha: 0.4 * pose.strength)
        }
        let stars = Self.colours.map { WorldKit.star($0.x, $0.y, $0.z) }
        for p in rig.sparkles.particles {
            let colour = Int(p.hue) % Self.colours.count
            let twinkle = 0.6 + 0.4 * sin(p.age * 16 + p.hue * 23)
            let alpha = pow(1 - p.progress, 0.9) * twinkle
            let at = CGPoint(x: p.position.x, y: p.position.y)
            if p.kind == MagicWandRig.Kind.glint.rawValue, let star = stars[colour] {
                ctx.draw(star, center: at, height: CGFloat(p.size * 2.6), rotation: CGFloat(p.age * 2 + p.hue), alpha: CGFloat(alpha))
            } else if let speck = Self.specks[colour] {
                ctx.stampDot(speck, at: at, radius: p.size * 2, alpha: alpha)
            }
        }
        // A spell's ring: stars racing outward round a circle.
        if let star = stars[0] {
            for burst in rig.bursts {
                let k = burst.age / 0.45
                let r = 20 + 130 * HandFXKit.easeOutCubic(k)
                for n in 0..<12 {
                    let a = Double(n) / 12 * 2 * .pi + k
                    let p = CGPoint(x: Double(burst.centre.x) + cos(a) * r, y: Double(burst.centre.y) + sin(a) * r)
                    ctx.draw(star, center: p, height: CGFloat(22 * (1 - k) + 6), rotation: CGFloat(a), alpha: CGFloat(1 - k))
                }
                HandFXKit.glow(ctx, at: burst.centre, radius: r * 1.1, colour: HandFXPalette.wand.lilac, alpha: 0.35 * (1 - k))
            }
        }
        ctx.interpolationQuality = .high
    }

    /// The wand and its star, painted solid over the light.
    private func drawWands(in ctx: CGContext, poses: [MagicWandRig.Pose]) {
        guard let wand = Self.wandSprite, let star = Self.starSprite else { return }
        ctx.interpolationQuality = .high
        for pose in poses {
            let d = pose.direction
            let normal = SIMD2(-d.y, d.x)
            let flip: CGFloat = simd_dot(normal, SIMD2(-0.707, 0.707)) >= 0 ? 1 : -1
            let thickness = max(12, pose.handSize * 0.17)
            ctx.saveGState()
            ctx.translateBy(x: pose.grip.x, y: pose.grip.y)
            ctx.rotate(by: CGFloat(atan2(d.y, d.x)))
            ctx.scaleBy(x: 1, y: flip)
            ctx.setAlpha(CGFloat(min(1, pose.strength * 1.5)))
            ctx.draw(wand, in: CGRect(x: 0, y: -thickness / 2, width: pose.length, height: thickness))
            ctx.restoreGState()
            let size = pose.handSize * 0.62 * (0.4 + 0.6 * min(1, pose.strength))
            ctx.draw(star, center: pose.star, height: CGFloat(size), rotation: CGFloat(rig.time * 0.9 + Double(pose.hand)), alpha: CGFloat(min(1, pose.strength * 1.5)))
        }
    }

    /// The wand along +x, handle at the left: dark lacquered wood, lit along its upper side, with gold bands and a gold tip.
    private static let wandSprite: CGImage? = {
        let w = 360.0, h = 36.0
        guard let ctx = HandFXKit.bitmap(width: Int(w), height: Int(h)) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
        // The outline: a handle, then a long taper to the tip.
        let shape = CGMutablePath()
        shape.move(to: CGPoint(x: 4, y: h / 2 - 12))
        shape.addLine(to: CGPoint(x: 92, y: h / 2 - 10))
        shape.addLine(to: CGPoint(x: w - 6, y: h / 2 - 4))
        shape.addQuadCurve(to: CGPoint(x: w - 6, y: h / 2 + 4), control: CGPoint(x: w, y: h / 2))
        shape.addLine(to: CGPoint(x: 92, y: h / 2 + 10))
        shape.addLine(to: CGPoint(x: 4, y: h / 2 + 12))
        shape.addQuadCurve(to: CGPoint(x: 4, y: h / 2 - 12), control: CGPoint(x: -2, y: h / 2))
        func shaded(_ dark: (Double, Double, Double), _ light: (Double, Double, Double)) {
            let stops = [c(dark.0 * 0.6, dark.1 * 0.6, dark.2 * 0.6), c(dark.0, dark.1, dark.2), c(light.0, light.1, light.2),
                         c(dark.0 * 1.2, dark.1 * 1.2, dark.2 * 1.2), c(dark.0 * 0.7, dark.1 * 0.7, dark.2 * 0.7)] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: stops, locations: [0, 0.3, 0.68, 0.82, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
            }
        }
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        shaded((0.2, 0.1, 0.18), (0.62, 0.45, 0.58))
        // Gold bands at the handle and a gold tip.
        for band in [CGRect(x: 84, y: 0, width: 10, height: h), CGRect(x: 100, y: 0, width: 4, height: h), CGRect(x: w - 22, y: 0, width: 22, height: h)] {
            ctx.saveGState()
            ctx.clip(to: band)
            shaded((0.62, 0.42, 0.12), (1.0, 0.92, 0.6))
            ctx.restoreGState()
        }
        // Carved rings on the handle.
        ctx.setStrokeColor(c(0.08, 0.04, 0.07, 0.8))
        ctx.setLineWidth(2)
        for x in stride(from: 18.0, to: 80, by: 14) {
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: h))
        }
        ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(shape)
        ctx.setStrokeColor(c(0.06, 0.03, 0.05, 0.7))
        ctx.setLineWidth(1.2)
        ctx.strokePath()
        return ctx.makeImage()
    }()

    /// A plump five-pointed golden star, lit from the top left, with a fine warm outline and a bright heart.
    private static let starSprite: CGImage? = {
        let side = 160
        guard let ctx = HandFXKit.bitmap(width: side, height: side) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGPoint(x: 80, y: 80)
        let path = CGMutablePath()
        for i in 0..<10 {
            let r = i % 2 == 0 ? 70.0 : 34.0
            let a = .pi / 2 + Double(i) * .pi / 5
            let p = CGPoint(x: 80 + cos(a) * r, y: 80 + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        ctx.setShadow(offset: CGSize(width: 3, height: -4), blur: 6, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(path)
        ctx.setFillColor(CGColor(colorSpace: space, components: [0.9, 0.62, 0.16, 1])!)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let gold = [CGColor(colorSpace: space, components: [1, 0.98, 0.82, 1])!, CGColor(colorSpace: space, components: [1, 0.82, 0.32, 1])!,
                    CGColor(colorSpace: space, components: [0.86, 0.52, 0.1, 1])!] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: gold, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 20, y: 150), end: CGPoint(x: 140, y: 14), options: [])
        }
        let heart = [CGColor(colorSpace: space, components: [1, 1, 0.95, 0.95])!, CGColor(colorSpace: space, components: [1, 1, 0.9, 0])!] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: heart, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: 74, y: 88), startRadius: 0, endCenter: c, endRadius: 30, options: [])
        }
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.7, 0.38, 0.06, 0.9])!)
        ctx.setLineWidth(2.5)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        return ctx.makeImage()
    }()
}
