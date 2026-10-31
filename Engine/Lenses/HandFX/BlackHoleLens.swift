import CoreGraphics
import CoreImage
import simd

/// A black hole held between the hands. Hold both hands up and one opens between them; spread them and it grows. The picture around it
/// bends and swirls inward, a glowing disc of matter spins round it, and wisps of light are pulled off your fingertips into it. With one
/// hand it is a small one floating over the palm; with none it collapses to nothing.
struct BlackHoleRig {
    /// A speck of the glowing disc: where it is round the hole, how far out (in hole radii) and how bright.
    struct Orbiter {
        var angle: Double
        var distance: Double
        var brightness: Double
        var size: Double
    }

    private(set) var centre = HandFXSteady(calm: 1.6, eager: 0.03)
    /// The hole's radius in pixels, eased toward where the hands want it.
    private(set) var radius = HandFXLevel(rise: 0.22, fall: 0.22, value: 0)
    /// 0...1: how far the hole has formed. It swells in and collapses out.
    private(set) var open = HandFXLevel(rise: 0.35, fall: 0.25)
    private(set) var orbiters: [Orbiter] = []
    private(set) var debris = ParticleSystem(capacity: 80)
    private(set) var time = 0.0
    private(set) var twoHanded = false
    private var steadier = HandFXSteadier()
    private var owed = 0.0
    private var rng = SplitMix64(seed: 0xB1AC)

    /// How the disc tips toward the camera, and how flat it looks.
    static let tilt = -0.32
    static let flatness = 0.3

    init() {
        debris.gravity = .zero
        var seed = SplitMix64(seed: 0xD15C)
        orbiters = (0..<110).map { _ in
            let d = 1.45 + pow(Double.random(in: 0...1, using: &seed), 1.6) * 1.5
            return Orbiter(angle: Double.random(in: 0..<(2 * .pi), using: &seed), distance: d,
                           brightness: Double.random(in: 0.5...1, using: &seed), size: Double.random(in: 2...4.5, using: &seed))
        }
    }

    mutating func removeAll() {
        self = BlackHoleRig()
    }

    /// The radius the hole is drawn at now: its size times how far it has formed.
    var drawnRadius: Double { radius.value * open.value }
    var point: CGPoint? { centre.point }

    /// Where the hole wants to be for these hands, and how big: between two hands and as wide as they are spread, or over one palm.
    static func target(for hands: [HandState]) -> (centre: CGPoint, radius: Double)? {
        guard let a = hands.first else { return nil }
        if hands.count >= 2 {
            let b = hands[1]
            let spread = HandFXKit.distance(a.palm, b.palm)
            return (HandFXKit.lerp(a.palm, b.palm, 0.5), min(170, max(26, spread * 0.17)))
        }
        let up = HandFXKit.up(of: a)
        return (HandFXKit.point(HandFXKit.vector(a.palm) + up * a.size * 1.05), min(56, max(16, a.size * 0.2)))
    }

    mutating func update(hands raw: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        let hands = steadier.update(raw, dt: dt)
        twoHanded = hands.count >= 2
        if let target = Self.target(for: hands) {
            // Starting from nothing, it opens where the hands are; after that it glides.
            let snap = open.value < 0.05 ? 0.0 : Double.infinity
            centre.update(target.centre, dt: dt, snap: snap)
            if open.value < 0.05 { radius.value = target.radius }
            radius.approach(target.radius, dt: dt)
            open.approach(1, dt: dt)
            pull(from: hands, dt: dt)
        } else {
            open.approach(0, dt: dt)
        }
        // The disc turns, the inside faster than the outside.
        for i in orbiters.indices { orbiters[i].angle += dt * 2.6 / pow(orbiters[i].distance, 1.5) }
        stepDebris(dt: dt)
    }

    /// Light is drawn off the fingertips and falls in.
    private mutating func pull(from hands: [HandState], dt: Double) {
        guard open.value > 0.5, let c = centre.value else { return }
        owed += dt * 26 * Double(hands.count) * open.value
        while owed >= 1 {
            owed -= 1
            let hand = hands[Int.random(in: 0..<hands.count, using: &rng)]
            let tip = HandFXKit.vector(hand[Finger.allCases[Int.random(in: 0..<5, using: &rng)].tip])
            let toward = c - tip
            let d = max(1, simd_length(toward))
            let along = toward / d, across = SIMD2(-along.y, along.x)
            debris.emit(Particle(position: tip, velocity: along * Double.random(in: 40...120, using: &rng) + across * Double.random(in: 120...240, using: &rng),
                                 age: 0, life: 2.5, size: Double.random(in: 2...3.5, using: &rng), hue: Double.random(in: 0..<1, using: &rng)))
        }
    }

    private mutating func stepDebris(dt: Double) {
        guard let c = centre.value else { debris.removeAll(); return }
        let r = max(8, drawnRadius)
        debris.step(dt) { p in
            let toward = c - p.position
            let d = max(r * 0.5, simd_length(toward))
            p.velocity += toward / d * min(5200, 2.2e6 / (d * d)) * dt
            p.velocity *= max(0, 1 - 0.6 * dt)
            if d < r * 1.02 { p.age = p.life }
        }
    }
}

final class BlackHoleLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig = BlackHoleRig()
    private var hint = HandFXHint()
    private let published = StatusBox()

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hands", detail: "A black hole opens between them") }

    func restart() {
        rig.removeAll()
        hint.reset()
    }

    var radius: Double { rig.drawnRadius }
    var centre: CGPoint? { rig.point }
    var isHinting: Bool { hint.isShowing }

    /// Colours of the disc, from the hot inside to the cooler rim.
    static let disc = (inner: SIMD3<Double>(1.0, 0.92, 0.7), middle: SIMD3<Double>(1.0, 0.6, 0.25), outer: SIMD3<Double>(0.9, 0.3, 0.55))

    func render(_ input: LensInput) -> CIImage {
        rig.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        published.value = currentStatus(input.hands)

        var out = input.composed
        let r = rig.drawnRadius
        if r > 1.5, let c = rig.point {
            out = bend(out, around: c, radius: r, rect: input.rect)
            // The far half of the disc, then the hole in front of it, painted on one layer.
            if let behind = input.services.overlay({ ctx in
                drawDisc(in: ctx, centre: c, radius: r, front: false)
                drawCore(in: ctx, centre: c, radius: r)
            }) {
                out = behind.composited(over: out)
            }
        }
        if (r > 1.5 || !rig.debris.particles.isEmpty), let c = rig.point,
           let front = input.services.overlay({ ctx in
               drawDisc(in: ctx, centre: c, radius: r, front: true)
               drawDebris(in: ctx)
           }) {
            out = HandFXLight.add(front, to: out, rect: input.rect, bloom: 0.9)
        }
        return hint.compose(over: out.cropped(to: input.rect), services: input.services, rect: input.rect, accent: Self.disc.middle)
    }

    private func currentStatus(_ hands: [HandState]) -> LensStatus {
        if hands.isEmpty { return LensStatus("Hold up your hands", detail: "A black hole opens between them") }
        if hands.count == 1 { return LensStatus("Bring your other hand in", detail: "The black hole grows between them") }
        return LensStatus("Spread your hands", detail: "The further apart, the bigger it gets")
    }

    /// Space bends round the hole: the picture is pinched in toward it and swirled, more strongly the bigger it is.
    private func bend(_ picture: CIImage, around c: CGPoint, radius r: Double, rect: CGRect) -> CIImage {
        let strength = min(1, r / 40)
        // Clamped first, so pulling the edges inward never drags emptiness into the picture.
        let pinch = picture.clampedToExtent().applyingFilter("CIBumpDistortion", parameters: [
            kCIInputCenterKey: CIVector(cgPoint: c), kCIInputRadiusKey: r * 3.4, kCIInputScaleKey: -0.55 * strength,
        ])
        let swirl = pinch.applyingFilter("CITwirlDistortion", parameters: [
            kCIInputCenterKey: CIVector(cgPoint: c), kCIInputRadiusKey: r * 2.9, kCIInputAngleKey: 1.1 * strength,
        ])
        // Outside its reach the bending does nothing, so only that square is worked on.
        let reach = r * 3.5
        let box = CGRect(x: Double(c.x) - reach, y: Double(c.y) - reach, width: reach * 2, height: reach * 2).intersection(rect)
        return swirl.cropped(to: box).composited(over: picture).cropped(to: rect)
    }

    // MARK: Drawing

    /// Where a point of the disc lands in the picture.
    private static func place(_ angle: Double, _ distance: Double, centre c: CGPoint, radius r: Double) -> CGPoint {
        let x = cos(angle) * distance * r, y = sin(angle) * distance * r * BlackHoleRig.flatness
        let t = BlackHoleRig.tilt
        return CGPoint(x: Double(c.x) + x * cos(t) - y * sin(t), y: Double(c.y) + x * sin(t) + y * cos(t))
    }

    private static let specks: [CGImage?] = [disc.inner, disc.middle, disc.outer].map { HandFXKit.speckSprite($0) }

    /// The half of the disc behind the hole or the half in front of it: a soft glowing band, and the specks of matter in it. The front half
    /// is added as light; the far half is painted, because the hole has to cover it.
    private func drawDisc(in ctx: CGContext, centre c: CGPoint, radius r: Double, front: Bool) {
        guard r > 1.5 else { return }
        ctx.setBlendMode(front ? .plusLighter : .normal)
        ctx.interpolationQuality = .low
        // The band: three soft ellipses, hot inside and cooler out, each half drawn on its own side of the hole.
        let turn = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(BlackHoleRig.tilt)).scaledBy(x: 1, y: CGFloat(BlackHoleRig.flatness))
        let from = front ? Double.pi : 0, to = front ? 2 * Double.pi : Double.pi
        for (distance, width, colour, alpha) in [(1.55, 0.3, Self.disc.inner, 0.26), (1.9, 0.5, Self.disc.middle, 0.15), (2.4, 0.7, Self.disc.outer, 0.08)] {
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: CGFloat(distance * r), startAngle: CGFloat(from), endAngle: CGFloat(to), clockwise: false, transform: turn)
            ctx.addPath(path)
            ctx.setLineWidth(CGFloat(width * r * BlackHoleRig.flatness * 1.6))
            ctx.setStrokeColor(HandFXKit.cgColor(colour, alpha))
            ctx.strokePath()
        }
        for o in rig.orbiters {
            let s = sin(o.angle)
            guard front ? s <= 0 : s > 0 else { continue }
            // The side coming toward us is brighter.
            let approach = 0.65 + 0.35 * cos(o.angle)
            let band = min(2, Int((o.distance - 1.45) / 0.55))
            let p = Self.place(o.angle, o.distance, centre: c, radius: r)
            if let speck = Self.specks[band] {
                ctx.stampDot(speck, at: p, radius: o.size * (0.6 + r / 70), alpha: o.brightness * approach)
            }
        }
        if front {
            // The bright ring of light bent right round the hole, just outside its edge.
            for (w, a) in [(r * 0.12, 0.16), (max(1.2, r * 0.025), 0.7)] {
                ctx.setLineWidth(CGFloat(w))
                ctx.setStrokeColor(HandFXKit.cgColor(Self.disc.middle + (SIMD3(1, 1, 1) - Self.disc.middle) * 0.5, a * min(1, r / 20)))
                ctx.strokeEllipse(in: CGRect(x: c.x - r * 1.04, y: c.y - r * 1.04, width: r * 2.08, height: r * 2.08))
            }
        }
        ctx.interpolationQuality = .high
        ctx.setBlendMode(.normal)
    }

    /// The hole itself: utterly dark, with a soft edge so it sits in the picture instead of being cut out of it.
    private func drawCore(in ctx: CGContext, centre c: CGPoint, radius r: Double) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colours = [CGColor(colorSpace: space, components: [0, 0, 0, 1])!, CGColor(colorSpace: space, components: [0.02, 0, 0.03, 1])!,
                       CGColor(colorSpace: space, components: [0.05, 0.01, 0.06, 0])!] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.86, 1]) else { return }
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(r * 1.06), options: [])
    }

    /// Wisps pulled off the fingertips, stretched along the way they fly.
    private func drawDebris(in ctx: CGContext) {
        guard let tail = WorldKit.comet(1, 0.7, 0.45), let speck = Self.specks[0] else { return }
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        for p in rig.debris.particles {
            let speed = simd_length(p.velocity)
            let fade = min(1, p.age * 4)
            let at = CGPoint(x: p.position.x, y: p.position.y)
            if speed > 40 {
                let length = min(60, 10 + speed * 0.06)
                ctx.saveGState()
                ctx.translateBy(x: at.x, y: at.y)
                ctx.rotate(by: CGFloat(atan2(p.velocity.y, p.velocity.x)))
                ctx.setAlpha(CGFloat(0.8 * fade))
                ctx.draw(tail, in: CGRect(x: -length, y: -p.size * 1.5, width: length, height: p.size * 3))
                ctx.restoreGState()
            }
            ctx.stampDot(speck, at: at, radius: p.size * 2, alpha: fade)
        }
        ctx.interpolationQuality = .high
    }
}
