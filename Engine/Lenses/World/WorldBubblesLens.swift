import CoreGraphics
import CoreImage
import simd

/// Soap bubbles drifting up through a bright room. The ones in front bump gently off you and wobble; stay against one long
/// enough, or let it grow old, and it pops in a fine spray. Smaller ones further back float behind you.
struct WorldBubbleSim {
    struct Bubble {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var radius: Double
        /// 0 far behind you ... 1 close to the camera.
        var depth: Double
        var phase: Double
        var age = 0.0
        var life: Double
        /// Seconds it has spent pressed against the person.
        var touching = 0.0
        var variant: Int

        var isBehind: Bool { depth < 0.35 }
    }

    struct Pop {
        var position: SIMD2<Double>
        var radius: Double
        var age = 0.0
    }

    let size: CGSize
    private(set) var bubbles: [Bubble] = []
    private(set) var pops: [Pop] = []
    private(set) var spray = ParticleSystem(capacity: 200)
    private(set) var time = 0.0
    private(set) var popCount = 0
    private var rng: SplitMix64
    private var owed = 0.0
    var capacity = 30

    static let variants = 3

    init(size: CGSize, seed: UInt64 = 0xB0BB1E) {
        self.size = size
        rng = SplitMix64(seed: seed)
        spray.gravity = SIMD2(0, -700)
        // Start with bubbles already in the air.
        for _ in 0..<18 {
            var b = makeBubble()
            b.position = SIMD2(Double.random(in: 40...(size.width - 40), using: &rng), Double.random(in: 40...(size.height - 60), using: &rng))
            b.age = Double.random(in: 0...4, using: &rng)
            bubbles.append(b)
        }
    }

    /// The breeze, in pixels a second: a slow swing from side to side.
    static func breeze(at t: Double) -> Double { 18 * sin(t * 0.27) + 8 * sin(t * 0.71 + 1) }

    private mutating func makeBubble() -> Bubble {
        let depth = Double.random(in: 0...1, using: &rng)
        let radius = (18 + 54 * pow(Double.random(in: 0...1, using: &rng), 1.3)) * (0.55 + 0.75 * depth)
        // Most come up from below; some drift in from the sides low down.
        let side = Double.random(in: 0...1, using: &rng)
        let position: SIMD2<Double>
        if side < 0.45 {
            position = SIMD2(Double.random(in: 0...size.width, using: &rng), -radius - 4)
        } else {
            let left = side < 0.72
            position = SIMD2(left ? -radius - 4 : size.width + radius + 4, Double.random(in: size.height * 0.1...(size.height * 0.65), using: &rng))
        }
        let inward = position.x < 0 ? 1.0 : position.x > size.width ? -1.0 : 0
        return Bubble(position: position, velocity: SIMD2(inward * 90 + Double.random(in: -20...20, using: &rng), Double.random(in: 20...60, using: &rng)),
                      radius: radius, depth: depth, phase: Double.random(in: 0...(2 * .pi), using: &rng),
                      life: Double.random(in: 9...16, using: &rng), variant: Int.random(in: 0..<Self.variants, using: &rng))
    }

    /// Puts a bubble in the air. For tests.
    mutating func insert(_ bubble: Bubble) { bubbles.append(bubble) }

    mutating func removeAll() {
        bubbles.removeAll()
        pops.removeAll()
        spray.removeAll()
    }

    mutating func step(_ rawDt: Double, matte: MatteQuery?) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        owed += 2.4 * dt
        while owed >= 1 {
            owed -= 1
            if bubbles.count < capacity { bubbles.append(makeBubble()) }
        }

        let breeze = Self.breeze(at: time)
        var popped: [Int] = []
        for i in bubbles.indices {
            var b = bubbles[i]
            b.age += dt
            // Light things rise slowly and wander; big ones are a little lazier.
            let rise = 24 + 22 * (1 - b.radius / 90)
            let wander = SIMD2(sin(b.age * 0.9 + b.phase) * 22, sin(b.age * 1.3 + b.phase * 2) * 8)
            let target = SIMD2(breeze * (0.5 + 0.6 * b.depth), rise) + wander
            b.velocity += (target - b.velocity) * (1 - exp(-0.9 * dt))
            b.position += b.velocity * dt
            if let matte, !b.isBehind {
                if Silhouette.resolve(position: &b.position, velocity: &b.velocity, radius: b.radius * 0.92, in: matte, restitution: 0.45) {
                    // A soap bubble often bursts the moment it touches something; otherwise it bounces and wobbles.
                    if b.touching == 0, Double.random(in: 0...1, using: &rng) < 0.3 { b.touching = 99 }
                    b.touching += dt
                } else {
                    b.touching = max(0, b.touching - dt * 0.5)
                }
            }
            if b.age > b.life || b.touching > 0.6 + b.phase * 0.1 { popped.append(i) }
            bubbles[i] = b
        }
        for i in popped.reversed() { pop(at: i) }
        bubbles.removeAll { $0.position.y > size.height + $0.radius + 10 || $0.position.x < -$0.radius - 60 || $0.position.x > size.width + $0.radius + 60 }
        spray.step(dt)
        for i in pops.indices { pops[i].age += dt }
        pops.removeAll { $0.age > 0.18 }
    }

    /// Bursts a bubble: a flash of its rim and a few droplets flung outward.
    mutating func pop(at index: Int) {
        guard bubbles.indices.contains(index) else { return }
        let b = bubbles.remove(at: index)
        popCount += 1
        pops.append(Pop(position: b.position, radius: b.radius))
        for _ in 0..<Int(5 + b.radius / 8) {
            let a = Double.random(in: 0...(2 * .pi), using: &rng)
            let at = b.position + SIMD2(cos(a), sin(a)) * b.radius * 0.9
            spray.emit(Particle(position: at, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 60...190, using: &rng),
                                life: Double.random(in: 0.25...0.5, using: &rng), size: Double.random(in: 1.0...2.2, using: &rng), hue: b.depth))
        }
    }
}

final class WorldBubblesLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private var sim: WorldBubbleSim
    private var sprites: [CGImage?] = []

    init(size: CGSize = CGSize(width: 1280, height: 720)) { sim = WorldBubbleSim(size: size) }

    func restart() { sim = WorldBubbleSim(size: sim.size) }

    var bubbles: [WorldBubbleSim.Bubble] { sim.bubbles }
    var popCount: Int { sim.popCount }

    func render(_ input: LensInput) -> CIImage {
        if sprites.isEmpty { sprites = (0..<WorldBubbleSim.variants).map { Self.bubbleSprite(variant: $0) } }
        sim.step(input.dt, matte: input.matteGrid)
        let rect = input.rect

        // "Meadow": a bright, airy day with the sun in the top left.
        let sun = SIMD3(1.0, 0.95, 0.85)
        var room = WorldKit.grade(input.scenery, saturation: 1.08, tint: (1.05, 1.04, 1.02), lift: (0.012, 0.012, 0.014))
        room = WorldKit.adding(WorldKit.wash(center: CGPoint(x: rect.width * 0.08, y: rect.height * 1.05), radius: 560, red: sun.x, green: sun.y, blue: sun.z,
                                             alpha: 0.22, in: rect), to: room)
        if let layer = input.services.overlay({ ctx in draw(in: ctx, behind: true) }) { room = layer.composited(over: room) }
        let person = WorldKit.grade(input.composed, saturation: 1.05, tint: (1.04, 1.03, 1.0), lift: (0.006, 0.006, 0.006))
        var body = WorldKit.place(person: person, over: room, matte: input.matte, rect: rect)
        if let rim = WorldKit.rimLight(matte: input.matte, rect: rect, toward: WorldKit.keyLight, width: 12, colour: sun, strength: 0.3) {
            body = WorldKit.adding(rim, to: body)
        }
        guard let front = input.services.overlay({ ctx in draw(in: ctx, behind: false) }) else { return body }
        return front.composited(over: body).cropped(to: rect)
    }

    private func draw(in ctx: CGContext, behind: Bool) {
        ctx.interpolationQuality = .medium
        for b in sim.bubbles where b.isBehind == behind {
            guard let sprite = sprites[b.variant % max(1, sprites.count)] else { continue }
            // Born small and swelling to size; wobbling as it goes, more just after a bump.
            let grow = WorldKit.smoothstep(0, 0.5, b.age)
            let wobble = (0.035 + 0.05 * min(1, b.touching * 3)) * sin(b.age * 6.3 + b.phase)
            let r = b.radius * (0.35 + 0.65 * grow)
            ctx.saveGState()
            ctx.translateBy(x: b.position.x, y: b.position.y)
            ctx.scaleBy(x: 1 + wobble, y: 1 - wobble)
            ctx.setAlpha(behind ? 0.72 : 1)
            ctx.draw(sprite, in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            ctx.restoreGState()
        }
        ctx.interpolationQuality = .high
        if behind { return }
        // Pops: the rim flashes out and fades, and droplets fly.
        for p in sim.pops {
            let k = p.age / 0.18
            let r = p.radius * (1 + 0.35 * k)
            ctx.setLineWidth(2 * (1 - k) + 0.5)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75 * (1 - k)))
            ctx.setLineDash(phase: 0, lengths: [r * 0.35, r * 0.2])
            ctx.strokeEllipse(in: CGRect(x: p.position.x - r, y: p.position.y - r, width: r * 2, height: r * 2))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        if let drop = WorldKit.softGlow(0.92, 0.97, 1) {
            for d in sim.spray.particles {
                ctx.stampDot(drop, at: CGPoint(x: d.position.x, y: d.position.y), radius: d.size * 1.6, alpha: 0.85 * (1 - d.progress))
            }
        }
    }

    // MARK: Sprite

    /// A soap bubble, drawn once per colour scheme: nearly clear in the middle, a rim of swirling thin-film colours, a faint
    /// darker band low down, a bright window reflection at the top left and a small one at the bottom right.
    private static func bubbleSprite(variant: Int) -> CGImage? {
        let side = 160
        let offset = Double(variant) * 2.1
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let dx = (Double(x) + 0.5) / Double(side) * 2 - 1, dy = (Double(side - 1 - y) + 0.5) / Double(side) * 2 - 1
                let t = (dx * dx + dy * dy).squareRoot()
                guard t < 1 else { continue }
                let angle = atan2(dy, dx)
                // Thin-film colour: bands that swirl round the rim.
                let hue = (0.55 + 0.32 * sin(angle * 2 + offset) + 0.22 * t + 0.08 * sin(angle * 5 - offset)).truncatingRemainder(dividingBy: 1) + 1
                let c = Palette.rgb(hue: hue.truncatingRemainder(dividingBy: 1), saturation: 0.5)
                let rim = pow(WorldKit.smoothstep(0.55, 0.985, t), 1.7) * 0.62 * (1 - WorldKit.smoothstep(0.985, 1, t))
                let edge = exp(-pow((t - 0.965) / 0.018, 2)) * 0.35
                let floor = WorldKit.smoothstep(0.3, 0.9, t) * (1 - WorldKit.smoothstep(-0.85, -0.2, dy)) * 0.12
                let a = min(1, 0.035 + rim + edge + floor)
                let white = edge / max(a, 1e-3)
                let r = c.r * (1 - white) + white, g = c.g * (1 - white) + white, b = c.b * (1 - white) + white
                let i = (y * side + x) * 4
                bytes[i] = UInt8(min(255, b * a * 255))
                bytes[i + 1] = UInt8(min(255, g * a * 255))
                bytes[i + 2] = UInt8(min(255, r * a * 255))
                bytes[i + 3] = UInt8(min(255, a * 255))
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        return bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
            let c = CGFloat(side) / 2
            // The window: a soft curved pane of light at the top left.
            ctx.saveGState()
            ctx.translateBy(x: c - c * 0.42, y: c + c * 0.42)
            ctx.rotate(by: .pi / 4)
            ctx.setShadow(offset: .zero, blur: 5, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
            ctx.addPath(CGPath(roundedRect: CGRect(x: -c * 0.26, y: -c * 0.1, width: c * 0.52, height: c * 0.2), cornerWidth: c * 0.1, cornerHeight: c * 0.1, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.fillEllipse(in: CGRect(x: c - c * 0.66, y: c + c * 0.12, width: c * 0.09, height: c * 0.09))
            // A small second reflection on the far side.
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.45))
            ctx.fillEllipse(in: CGRect(x: c + c * 0.42, y: c - c * 0.62, width: c * 0.16, height: c * 0.09))
            return ctx.makeImage()
        }
    }
}
