import CoreGraphics
import CoreImage

/// Nod off: keep your eyes shut for a moment and you fall asleep. Big soft Z's drift up from your head, a bubble swells and
/// shrinks at your nose as you breathe, and little stars twinkle around you. Open your eyes and the bubble pops.
final class ExprSleepyLens: ExprOverlayLens {
    /// Eyes this shut count as closed, and they must open past `openAt` to count as open again.
    static let closedAt = 0.6, openAt = 0.35
    /// Seconds of closed eyes before you are asleep, so an ordinary blink doesn't count.
    static let dozeAfter = 0.45

    private var closed = ExprLatch()
    private var closedFor = 0.0
    private var sleep = ExprSpring()
    private var breath = 0.0
    private var sinceZ = 0.0
    private var zs = ParticleSystem(capacity: 12)
    private var pops = ParticleSystem(capacity: 24)
    private var rng = SplitMix64(seed: 0x2222)
    private(set) var popCount = 0

    var isAsleep: Bool { closed.isOn && closedFor >= Self.dozeAfter }
    var zCount: Int { zs.particles.count }
    /// How big the bubble is, 0 (none) to 1.
    var bubbleSize: Double { max(0, sleep.value) * (0.55 + 0.45 * (0.5 - 0.5 * cos(breath))) }

    override var hintText: String { "Close your eyes for a nap" }
    override var isFinished: Bool { presence.face == nil && zs.particles.isEmpty && pops.particles.isEmpty }

    override init() {
        super.init()
        zs.gravity = .zero
        pops.gravity = SIMD2(0, -900)
    }

    override func restart() {
        super.restart()
        closed.reset(); closedFor = 0; sleep.reset(); breath = 0; sinceZ = 0; zs.removeAll(); pops.removeAll(); popCount = 0
    }

    /// The soft lilac lettering for the Z's.
    static let zLook = ExprType.Look(top: .init((1, 1, 1)), bottom: .init((0.8, 0.74, 1.0)), edge: .init((0.3, 0.2, 0.56)), edgeWidth: 0.13)

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        let wasAsleep = isAsleep
        if let face {
            closed.update(face.blink, on: Self.closedAt, off: Self.openAt)
            closedFor = closed.isOn ? closedFor + dt : 0
        } else {
            closed.reset(); closedFor = 0
        }
        if wasAsleep && !isAsleep {
            // Waking up pops the bubble at once.
            if sleep.value > 0.3, let face = presence.face { pop(face) }
            sleep.reset(0)
        }
        sleep.step(toward: isAsleep ? 1 : 0, dt: dt, frequency: 0.9, damping: 0.8)
        breath += dt * 2 * .pi / 3.2
        sinceZ += dt
        if isAsleep, let face, sinceZ > 0.75 {
            sinceZ = 0
            let start = face.exprPoint(0.85, 1.05)
            zs.emit(Particle(position: start.simd, velocity: SIMD2(face.acrossVector.x, face.acrossVector.y) * 18 * face.exprScale + SIMD2(0, 52) * face.exprScale,
                             life: 2.4, size: face.interocular * 0.5, hue: Double.random(in: 0..<6.28, using: &rng), kind: zs.particles.count % 2))
        }
        zs.step(dt)
        pops.step(dt)
    }

    /// Where the bubble hangs: from one nostril, swelling out to the side.
    private func bubbleCentre(_ face: FaceState, radius: Double) -> CGPoint {
        let nostril = face.exprPoint(0.12, -0.62)
        let out = face.acrossVector * 0.55 + face.downVector * 0.45
        return CGPoint(x: nostril.x + out.x * radius, y: nostril.y + out.y * radius)
    }

    private func pop(_ face: FaceState) {
        popCount += 1
        let r = face.interocular * 0.46 * bubbleSize
        let c = bubbleCentre(face, radius: r)
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi
            pops.emit(Particle(position: c.simd + SIMD2(cos(a), sin(a)) * r * 0.8, velocity: SIMD2(cos(a), sin(a)) * 220 * face.exprScale,
                               life: 0.35, size: face.interocular * 0.06, kind: 0))
        }
        pops.emit(Particle(position: c.simd, velocity: .zero, life: 0.22, size: r, kind: 1))
    }

    override func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        // The Z's, swaying up and away, growing as they go.
        for p in zs.particles {
            let t = p.progress
            let sway = sin(p.age * 2.2 + p.hue) * p.size * 0.5
            let alpha = min(1, p.age / 0.3) * (1 - exprSmoothstep(0.55, 1, t))
            let fontSize = p.size * (0.7 + 0.9 * exprOutCubic(t)) * (p.kind == 0 ? 1 : 0.75)
            ctx.exprLabel(ExprType.label(p.kind == 0 ? "Z" : "z", look: Self.zLook), at: CGPoint(x: p.position.x + sway, y: p.position.y),
                          fontSize: fontSize, rotation: 0.25 * sin(p.age * 1.6 + p.hue) - 0.15, alpha: alpha)
        }
        for p in pops.particles {
            let fade = 1 - p.progress
            if p.kind == 1 {
                ctx.setStrokeColor(exprColor((1, 1, 1), 0.8 * fade)); ctx.setLineWidth(max(1, p.size * 0.08))
                let r = p.size * (1 + 0.8 * p.progress)
                ctx.strokeEllipse(in: CGRect(x: p.position.x - r, y: p.position.y - r, width: r * 2, height: r * 2))
            } else {
                ctx.fillCircle(center: CGPoint(x: p.position.x, y: p.position.y), radius: p.size, color: exprColor((0.85, 0.94, 1.0), 0.9 * fade))
            }
        }
        guard let face else { return }
        // Small stars twinkling around you: faint while you're awake, bright once you're asleep.
        let amount = (0.3 + 0.7 * max(0, min(1, sleep.value))) * presence.alpha
        for i in 0..<4 {
            let a = Double(i) * 1.7 + 0.6
            let spot = face.exprPoint(cos(a) * 1.55, 0.35 + sin(a) * 1.2)
            let tw = pow(max(0, sin(time * 1.8 + Double(i) * 2.1)), 2)
            ctx.exprStamp(ExprSprites.twinkle(variant: 3), at: spot, height: face.interocular * (0.18 + 0.2 * tw), rotation: time * 0.4, alpha: amount * (0.3 + 0.7 * tw))
        }
        guard sleep.value > 0.01 else { return }
        // The bubble: a thin glassy skin with a window of light, swelling and shrinking with each breath.
        let r = face.interocular * 0.46 * bubbleSize * presence.alpha
        guard r > 1 else { return }
        let c = bubbleCentre(face, radius: r)
        let disc = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        if let g = ExprShapes.gradient([((0.8, 0.92, 1.0), 0), ((0.56, 0.76, 1.0), 0.72), ((0.86, 0.95, 1.0), 1)], alphas: [0.2, 0.34, 0.75]) {
            ctx.saveGState()
            ctx.addEllipse(in: disc); ctx.clip()
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            ctx.restoreGState()
        }
        ctx.setStrokeColor(exprColor((0.42, 0.62, 0.9), 0.8)); ctx.setLineWidth(max(1, r * 0.06))
        ctx.strokeEllipse(in: disc)
        ctx.setStrokeColor(exprColor((1, 1, 1), 0.85)); ctx.setLineWidth(max(1, r * 0.1)); ctx.setLineCap(.round)
        ctx.addArc(center: c, radius: r * 0.7, startAngle: 1.9, endAngle: 2.7, clockwise: false); ctx.strokePath()
        ctx.fillCircle(center: CGPoint(x: c.x + r * 0.45, y: c.y - r * 0.4), radius: r * 0.07, color: exprColor((1, 1, 1), 0.7))
    }
}
