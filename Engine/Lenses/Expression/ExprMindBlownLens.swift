import CoreGraphics
import CoreImage

/// Mind blown: drop your jaw and raise your eyebrows together. The top of your head fizzes for a beat, then goes off in a
/// cartoon mushroom cloud: a soft flash, a ring of shock, a fireball that cools to smoke, and sparks raining down.
final class ExprMindBlownLens: ExprOverlayLens {
    /// Both the mouth and the brows must pass this to go off, and one of them must drop below `resetAt` before it can again.
    static let triggerAt = 0.45, resetAt = 0.25
    /// The fizz before the bang, and how long the whole show runs.
    static let fuse = 0.32, showLength = 2.6

    /// One ball of the cloud, in face units relative to the top of the head (y up), so it rides along if you move.
    struct Puff {
        var to: CGPoint
        var delay: Double
        var size: Double
        var seed: Double
    }

    private var shocked = ExprLatch()
    /// Seconds since the fuse was lit; nil when nothing is going on.
    private var showAge: Double?
    private var puffs: [Puff] = []
    private var sparks = ParticleSystem(capacity: 120)
    private var rng = SplitMix64(seed: 0xB00B)
    private(set) var blastCount = 0
    /// Where the blast happened, in pixels, and how big the face was, kept so the cloud can finish if the face goes.
    private var anchor: FaceState?

    var isShocked: Bool { shocked.isOn }
    var isExploding: Bool { (showAge ?? -1) >= Self.fuse }

    override var hintText: String { "Drop your jaw and raise your brows" }
    override var isFinished: Bool { presence.face == nil && showAge == nil && sparks.particles.isEmpty }

    override init() {
        super.init()
        sparks.gravity = SIMD2(0, -700)
        sparks.drag = 0.6
    }

    override func restart() {
        super.restart()
        shocked.reset(); showAge = nil; puffs = []; sparks.removeAll(); blastCount = 0; anchor = nil
    }

    /// A cauliflower puff of cloud: a few balls merged into one outline, lit from the top left, in one of three tones.
    static func puff(_ ramp: ExprPalette.Ramp, key: String) -> CGImage? {
        ExprSprites.make("expr-boom-\(key)", side: 192) { ctx in
            let path = CGMutablePath()
            for (x, y, r) in [(0.0, -0.08, 0.6), (-0.38, 0.12, 0.42), (0.36, 0.16, 0.44), (0.02, 0.38, 0.42)] as [(Double, Double, Double)] {
                path.addEllipse(in: CGRect(x: x - r, y: y - r - 0.06, width: r * 2, height: r * 2))
            }
            ctx.setLineJoin(.round)
            ctx.setLineWidth(0.08)
            ctx.setStrokeColor(exprColor(ramp.edge))
            ctx.addPath(path); ctx.strokePath()
            ctx.saveGState()
            ctx.addPath(path); ctx.clip(using: .winding)
            if let g = ExprShapes.gradient([(ramp.light, 0), (ramp.base, 0.5), (ramp.dark, 1)]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: -0.4, y: 0.75), end: CGPoint(x: 0.35, y: -0.7), options: [])
            }
            // Each ball's own soft top light.
            for (x, y, r) in [(-0.38, 0.12, 0.42), (0.36, 0.16, 0.44), (0.02, 0.38, 0.42)] as [(Double, Double, Double)] {
                if let g = ExprShapes.gradient([(ramp.light, 0), (ramp.light, 1)], alphas: [0.7, 0]) {
                    let c = CGPoint(x: x - r * 0.3, y: y + r * 0.3 - 0.06)
                    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * 0.7, options: [])
                }
            }
            ctx.restoreGState()
        }
    }

    /// Smoke lit by its own fire: warm cream on top, grey-brown underneath.
    static let smoke = puff(ExprPalette.Ramp(light: (1.0, 0.97, 0.9), base: (0.8, 0.75, 0.74), dark: (0.52, 0.47, 0.52), edge: (0.34, 0.28, 0.34)), key: "smoke")
    /// A darker puff, for the shaded side of the cloud.
    static let shade = puff(ExprPalette.Ramp(light: (0.88, 0.84, 0.82), base: (0.62, 0.57, 0.6), dark: (0.38, 0.34, 0.4), edge: (0.26, 0.22, 0.28)), key: "shade")
    /// The fireball the cloud starts as.
    static let fireball = puff(ExprPalette.Ramp(light: (1.0, 0.98, 0.7), base: (1.0, 0.66, 0.22), dark: (0.9, 0.3, 0.08), edge: (0.6, 0.16, 0.04)), key: "fire")

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        if let face {
            let was = shocked.isOn
            shocked.update(min(face.mouthOpen, face.browRaise), on: Self.triggerAt, off: Self.resetAt)
            if shocked.isOn && !was && showAge == nil { light(face) }
            if showAge != nil { anchor = face }
        } else {
            shocked.reset()
        }
        if var age = showAge {
            let before = age
            age += dt
            if before < Self.fuse && age >= Self.fuse, let f = anchor { bang(f) }
            if age < Self.fuse, let f = anchor { fizz(f, dt: dt) }
            showAge = age > Self.showLength ? nil : age
        }
        sparks.step(dt)
    }

    private func light(_ face: FaceState) {
        showAge = 0
        anchor = face
        // The cloud: a column of puffs up from the head and a wide cap on top.
        puffs = []
        for i in 0..<6 {
            puffs.append(Puff(to: CGPoint(x: Double.random(in: -0.12...0.12, using: &rng), y: 0.3 + Double(i) * 0.32),
                              delay: Double(i) * 0.03, size: 0.62 - Double(i) * 0.02, seed: Double.random(in: 0..<6.28, using: &rng)))
        }
        for i in 0..<11 {
            let a = Double(i) / 11 * 2 * .pi
            puffs.append(Puff(to: CGPoint(x: cos(a) * 0.95, y: 2.25 + sin(a) * 0.36), delay: 0.1 + Double(i % 3) * 0.03,
                              size: Double.random(in: 0.64...0.84, using: &rng), seed: Double.random(in: 0..<6.28, using: &rng)))
        }
        for i in 0..<4 {
            puffs.append(Puff(to: CGPoint(x: -0.45 + Double(i) * 0.3, y: 2.55), delay: 0.14, size: 0.8, seed: Double.random(in: 0..<6.28, using: &rng)))
        }
    }

    private func fizz(_ face: FaceState, dt: Double) {
        let top = face.exprPoint(0, layout(face).base)
        if Double.random(in: 0..<1, using: &rng) < dt * 40 {
            let a = Double.random(in: 0.3...2.8, using: &rng) + face.roll
            sparks.emit(Particle(position: top.simd, velocity: SIMD2(cos(a), sin(a)) * 260 * face.exprScale, life: 0.3, size: 3 * face.exprScale, kind: 0))
        }
    }

    private func bang(_ face: FaceState) {
        blastCount += 1
        let fit = layout(face)
        let top = face.exprPoint(0, fit.base + 0.4 * fit.scale)
        let scale = face.exprScale * fit.scale
        for _ in 0..<28 {
            let a = Double.random(in: 0.25...(Double.pi - 0.25), using: &rng) + face.roll
            let speed = Double.random(in: 300...680, using: &rng) * scale
            sparks.emit(Particle(position: top.simd, velocity: SIMD2(cos(a), sin(a)) * speed, life: Double.random(in: 0.6...1.2, using: &rng),
                                 size: Double.random(in: 2.5...5.5, using: &rng) * scale, hue: Double.random(in: 0..<1, using: &rng), kind: 1))
        }
    }

    /// How big the cloud is and where it starts (face units up from the eyes), so all of it fits under the top of the
    /// picture: with little room it starts lower, over the hair, and then gets smaller.
    func layout(_ face: FaceState) -> (scale: Double, base: Double) {
        let up = Double(face.up.dy)
        guard up > 0.3 else { return (1, 1.4) }
        let room = (bounds.maxY - bounds.height * 0.05 - face.eyeCenter.y) / (face.interocular * up) - 1.4
        let tall = 3.6
        if room >= tall { return (1, 1.4) }
        let scale = max(0.6, room / tall)
        let drop = min(0.8, max(0, tall * scale - room))
        return (min(scale, max(0.25, (room + drop) / tall)), 1.4 - drop)
    }

    override func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        if let age = showAge, let f = face ?? anchor {
            let fit = layout(f)
            let k = fit.scale
            ctx.saveGState()
            ctx.inFaceSpace(f) {
                ctx.translateBy(x: 0, y: fit.base)
                if age < Self.fuse {
                    // The fuse: the top of the head glows hotter and hotter.
                    let charge = age / Self.fuse
                    ctx.setBlendMode(.plusLighter)
                    ctx.glow(center: .zero, radius: 0.3 + 0.5 * charge, red: 1, green: 0.8, blue: 0.4, alpha: 0.35 + 0.5 * charge)
                    ctx.setBlendMode(.normal)
                } else {
                    let t = age - Self.fuse
                    drawBlast(ctx, t: t, squeeze: k)
                }
            }
            ctx.restoreGState()
        }
        ctx.setBlendMode(.plusLighter)
        if let hot = Sprites.dot(red: 1, green: 0.85, blue: 0.5) {
            for p in sparks.particles {
                let at = CGPoint(x: p.position.x, y: p.position.y)
                let fade = 1 - exprSmoothstep(0.5, 1, p.progress)
                ctx.setStrokeColor(exprColor((1, 0.6, 0.2), 0.8 * fade)); ctx.setLineWidth(p.size); ctx.setLineCap(.round)
                ctx.move(to: at); ctx.addLine(to: CGPoint(x: at.x - p.velocity.x * 0.03, y: at.y - p.velocity.y * 0.03)); ctx.strokePath()
                ctx.stampDot(hot, at: at, radius: p.size * 1.8, alpha: fade)
            }
        }
        ctx.setBlendMode(.normal)
    }

    /// The bang, `t` seconds in, in face units with the top of the head at the origin.
    private func drawBlast(_ ctx: CGContext, t: Double, squeeze k: Double) {
        let fade = 1 - exprSmoothstep(Self.showLength - Self.fuse - 0.7, Self.showLength - Self.fuse, t)
        // A soft flash, over in a quarter of a second.
        if t < 0.3 {
            ctx.setBlendMode(.plusLighter)
            ctx.glow(center: CGPoint(x: 0, y: 0.6 * k), radius: 2.6, red: 1, green: 0.95, blue: 0.8, alpha: 0.5 * (1 - t / 0.3))
            ctx.setBlendMode(.normal)
        }
        // The shock ring, flat around the head.
        if t < 0.5 {
            let r = (0.4 + 3.2 * exprOutCubic(t / 0.5)) * (0.5 + 0.5 * k)
            ctx.setStrokeColor(exprColor((1, 0.98, 0.9), 0.75 * (1 - t / 0.5)))
            ctx.setLineWidth(0.08 * (1 - t / 0.5) + 0.01)
            ctx.strokeEllipse(in: CGRect(x: -r, y: -r * 0.22, width: r * 2, height: r * 0.44))
        }
        // The cloud: each puff shoots out to its place, then swells, drifts up and thins away. Fire first, cooling to smoke.
        for p in puffs {
            let local = t - p.delay
            guard local > 0 else { continue }
            let go = exprOutCubic(min(1, local / 0.55))
            let drift = 0.18 * local
            // A face too near the top of the picture gets a smaller cloud, all of it scaled, so none of it is cut off.
            let at = CGPoint(x: (p.to.x * go + sin(local * 1.3 + p.seed) * 0.04) * k, y: (p.to.y * go + drift) * k)
            let size = p.size * 1.25 * (0.35 + 0.65 * exprOutBack(min(1, local / 0.45))) * (1 + 0.2 * local) * k
            let cool = exprSmoothstep(0.15, 0.8, local)
            // Puffs low and to the right are in the cloud's own shadow.
            let shaded = p.to.x > 0.35 || p.to.y < 1.4
            ctx.exprPlace(shaded ? Self.shade : Self.smoke, at: at, height: size, rotation: sin(p.seed) * 0.3, alpha: fade * cool)
            ctx.exprPlace(Self.fireball, at: at, height: size, rotation: sin(p.seed) * 0.3, alpha: fade * (1 - cool))
        }
    }
}
