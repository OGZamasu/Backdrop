import CoreGraphics
import CoreImage
import simd

/// A blade of light held in a fist. Close a hand and a metal hilt appears in it; the blade springs out of the top, hums, and leaves a
/// glowing arc when swung. Open the hand and it slides back in. Two fists, two blades; where they cross, sparks fly.
///
/// The blade follows the line from the wrist to the knuckles, which Vision finds steadily even in a fist, and that line is smoothed just
/// enough to calm the tremble without making a fast swing lag.
struct LightBladeRig {
    struct Blade {
        /// Whether the hand is a fist, with a little patience either way so a flicker of the pose does not snap the blade off.
        var grip = HandFXLatch(on: 0.62, off: 0.32, holdOn: 0.08, holdOff: 0.2)
        /// 0...1 (a little more while it springs out): how far the blade is out. A spring, so it overshoots and settles.
        var extend = 0.0
        var extendSpeed = 0.0
        /// Where the blade points, in radians, smoothed.
        var angle: Double?
        /// How fast it is turning, radians a second, smoothed: the swing.
        var turn = 0.0
        var centre = HandFXSteady(calm: 2.4, eager: 0.03)
        /// Which colour it is.
        var colour: Int
        /// Where the blade has been lately, newest last, for the swing trail.
        var history: [(base: CGPoint, tip: CGPoint, time: Double)] = []
    }

    /// What one blade looks like this frame.
    struct Pose {
        var hand: Int
        var base: CGPoint
        var tip: CGPoint
        var direction: SIMD2<Double>
        /// The hilt's middle and length, in pixels.
        var hiltCentre: CGPoint
        var hiltLength: Double
        var width: Double
        /// 0...1: how far out, times how present the hand is.
        var strength: Double
        var colour: Int
    }

    private(set) var memory = HandFXMemory<Blade>()
    private(set) var sparks = ParticleSystem(capacity: 160)
    private(set) var time = 0.0
    private(set) var clashes = 0
    private var made = 0
    /// Steadies the joints first, so the far end of a long blade does not magnify the tremble of the wrist.
    private var steadier = HandFXSteadier()
    private var rng = SplitMix64(seed: 0xB1ADE)

    init() {
        sparks.gravity = SIMD2(0, -700)
        sparks.drag = 0.6
    }

    mutating func removeAll() {
        memory.removeAll()
        sparks.removeAll()
        steadier.removeAll()
    }

    /// The blade's full length for a hand of a given size.
    static func length(for hand: HandState) -> Double { min(640, max(230, hand.size * 4.8)) }

    mutating func update(hands raw: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        let hands = steadier.update(raw, dt: dt)
        var fresh = made
        memory.update(hands, dt: dt, fade: 0.4) { _ in
            defer { fresh += 1 }
            return Blade(colour: fresh)
        }
        made = fresh
        for i in memory.entries.indices {
            var entry = memory.entries[i]
            var blade = entry.state
            if entry.visible {
                let hand = entry.hand
                blade.grip.update(HandFXPose.fist(hand), dt: entry.age < 1e-9 ? 1 : dt)
                let up = HandFXKit.up(of: hand)
                let raw = atan2(up.y, up.x)
                if let a = blade.angle {
                    let delta = atan2(sin(raw - a), cos(raw - a))
                    let step = delta * (1 - exp(-dt / 0.045))
                    blade.angle = a + step
                    blade.turn += (step / max(dt, 1e-3) - blade.turn) * 0.5
                } else {
                    blade.angle = raw
                }
                let middle = HandFXKit.lerp(hand.palm, hand[.middleMCP], 0.35)
                blade.centre.update(middle, dt: dt, snap: max(160, hand.size * 2.5))
            }
            // The blade is a spring pulled out by a closed fist and in by anything else, including the hand going.
            let target = entry.visible && blade.grip.isOn ? 1.0 : 0.0
            let pull = target > blade.extend ? 230.0 : 300.0, damping = target > blade.extend ? 19.0 : 34.0
            blade.extendSpeed += (pull * (target - blade.extend) - damping * blade.extendSpeed) * dt
            blade.extend = max(0, blade.extend + blade.extendSpeed * dt)
            if blade.extend < 0.002, target == 0 { blade.extend = 0; blade.extendSpeed = 0 }
            entry.state = blade
            memory.modify(i) { $0 = entry }
        }
        let poses = self.poses
        for pose in poses {
            guard let i = memory.entries.firstIndex(where: { $0.hand.id == pose.hand }) else { continue }
            memory.modify(i) { entry in
                entry.state.history.append((pose.base, pose.tip, time))
                entry.state.history.removeAll { time - $0.time > 0.14 }
            }
        }
        clash(poses)
        sparks.step(dt)
    }

    /// Every blade or hilt showing now.
    var poses: [Pose] {
        memory.entries.compactMap { entry in
            guard let angle = entry.state.angle, let centre = entry.state.centre.point else { return nil }
            let hiltShow = min(1, entry.state.extend * 4) * entry.presence
            guard hiltShow > 0.01 else { return nil }
            let d = SIMD2(cos(angle), sin(angle))
            let hiltLength = entry.hand.size * 1.25
            let c = HandFXKit.vector(centre)
            let base = c + d * hiltLength * 0.5
            let tip = base + d * Self.length(for: entry.hand) * max(0, entry.state.extend)
            return Pose(hand: entry.hand.id, base: HandFXKit.point(base), tip: HandFXKit.point(tip), direction: d, hiltCentre: centre,
                        hiltLength: hiltLength, width: min(64, max(26, entry.hand.size * 0.42)), strength: min(1, entry.state.extend) * entry.presence,
                        colour: entry.state.colour)
        }
    }

    /// Where two blades cross, sparks fly.
    private mutating func clash(_ poses: [Pose]) {
        let out = poses.filter { $0.strength > 0.6 }
        guard out.count >= 2 else { return }
        for i in 0..<(out.count - 1) {
            for j in (i + 1)..<out.count {
                guard let hit = Self.crossing(out[i].base, out[i].tip, out[j].base, out[j].tip) else { continue }
                if clashes == 0 || Double.random(in: 0..<1, using: &rng) < 0.7 { clashes += 1 }
                for _ in 0..<6 {
                    let a = Double.random(in: 0..<(2 * .pi), using: &rng), s = Double.random(in: 180...520, using: &rng)
                    sparks.emit(Particle(position: HandFXKit.vector(hit), velocity: SIMD2(cos(a), sin(a)) * s, age: 0,
                                         life: Double.random(in: 0.25...0.55, using: &rng), size: Double.random(in: 1.8...3.6, using: &rng)))
                }
            }
        }
    }

    /// Where segment ab crosses segment cd, if it does.
    static func crossing(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        let r = SIMD2(Double(b.x - a.x), Double(b.y - a.y)), s = SIMD2(Double(d.x - c.x), Double(d.y - c.y))
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-9 else { return nil }
        let q = SIMD2(Double(c.x - a.x), Double(c.y - a.y))
        let t = (q.x * s.y - q.y * s.x) / denominator, u = (q.x * r.y - q.y * r.x) / denominator
        guard t >= 0, t <= 1, u >= 0, u <= 1 else { return nil }
        return CGPoint(x: Double(a.x) + r.x * t, y: Double(a.y) + r.y * t)
    }
}

final class LightBladeLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig = LightBladeRig()
    private var hint = HandFXHint()
    private let published = StatusBox()

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hand", detail: "Make a fist to light the blade") }

    func restart() {
        rig.removeAll()
        hint.reset()
    }

    var blades: [LightBladeRig.Pose] { rig.poses }
    var clashes: Int { rig.clashes }
    var isHinting: Bool { hint.isShowing }

    func render(_ input: LensInput) -> CIImage {
        rig.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        let poses = rig.poses
        published.value = currentStatus(input.hands, poses: poses)

        var out = input.composed
        if !poses.isEmpty || !rig.sparks.particles.isEmpty {
            // The blade lights up everything near it.
            for pose in poses where pose.strength > 0.05 {
                let c = HandFXPalette.blades[pose.colour % HandFXPalette.blades.count]
                let mid = HandFXKit.lerp(pose.base, pose.tip, 0.5)
                let length = HandFXKit.distance(pose.base, pose.tip)
                out = WorldKit.adding(WorldKit.wash(center: mid, radius: length * 0.55 + 40, red: c.x, green: c.y, blue: c.z,
                                                    alpha: 0.15 * pose.strength, in: input.rect), to: out)
            }
            if let light = input.services.overlay({ ctx in drawLight(in: ctx, poses: poses, time: input.time) }) {
                out = HandFXLight.add(light, to: out, rect: input.rect, bloom: 0.8)
            }
            if !poses.isEmpty, let hilts = input.services.overlay({ ctx in drawHilts(in: ctx, poses: poses) }) {
                out = hilts.composited(over: out)
            }
        }
        return hint.compose(over: out, services: input.services, rect: input.rect, accent: HandFXPalette.blades[0])
    }

    private func currentStatus(_ hands: [HandState], poses: [LightBladeRig.Pose]) -> LensStatus {
        if hands.isEmpty { return LensStatus("Hold up your hand", detail: "Make a fist to light the blade") }
        if poses.contains(where: { $0.strength > 0.5 }) { return LensStatus("Swing it!", detail: "Open your hand to put it away") }
        return LensStatus("Make a fist", detail: "Your blade lights up in it")
    }

    // MARK: Drawing

    private static func beam(_ colour: Int) -> CGImage? {
        let c = HandFXPalette.blades[colour % HandFXPalette.blades.count]
        return HandFXSprites.named("blade-beam-\(colour % HandFXPalette.blades.count)") { HandFXKit.beamSprite(c, core: 0.17, body: 0.32) }
    }

    /// The rounded end of a blade: the same cross-section, closing in a half circle.
    private static func end(_ colour: Int) -> CGImage? {
        let c = HandFXPalette.blades[colour % HandFXPalette.blades.count]
        return HandFXSprites.named("blade-end-\(colour % HandFXPalette.blades.count)") {
            HandFXKit.sprite(width: 48, height: 96) { u, v in
                let x = u * 2 - 1, y = (v - 0.5) * 2
                let d = x < 0 ? abs(y) : (x * x + y * y).squareRoot()
                let white = exp(-pow(d / 0.17, 2)), inner = 0.62 * exp(-pow(d / 0.32, 2)), outer = 0.16 * exp(-pow(d / 0.5, 2)) * (1 - WorldKit.smoothstep(0.75, 1, d))
                let sum = SIMD3<Double>(1, 1, 1) * white + c * (inner + outer)
                let a = min(1, max(sum.x, max(sum.y, sum.z)))
                return a < 1e-4 ? (0, 0, 0, 0) : (sum.x / a, sum.y / a, sum.z / a, a)
            }
        }
    }

    private func drawLight(in ctx: CGContext, poses: [LightBladeRig.Pose], time: Double) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .medium
        for pose in poses where pose.strength > 0.01 {
            let colour = HandFXPalette.blades[pose.colour % HandFXPalette.blades.count]
            drawTrail(for: pose, colour: colour, in: ctx)
            // The hum: the blade's width and brightness waver very slightly.
            let hum = 1 + 0.035 * sin(time * 47 + Double(pose.hand)) + 0.02 * sin(time * 113)
            let width = pose.width * 2.1 * hum
            let length = HandFXKit.distance(pose.base, pose.tip)
            let end = min(length, width * 0.5)
            let d = pose.direction
            let shaftEnd = HandFXKit.point(HandFXKit.vector(pose.tip) - d * end)
            let alpha = min(1, pose.strength * 1.15) * (0.96 + 0.04 * hum)
            if let beam = Self.beam(pose.colour) {
                HandFXKit.drawBeam(beam, from: pose.base, to: shaftEnd, width: width, alpha: alpha, in: ctx)
            }
            if let cap = Self.end(pose.colour) {
                ctx.saveGState()
                ctx.translateBy(x: shaftEnd.x, y: shaftEnd.y)
                ctx.rotate(by: CGFloat(atan2(d.y, d.x)))
                ctx.setAlpha(CGFloat(alpha))
                ctx.draw(cap, in: CGRect(x: 0, y: -width / 2, width: width / 2, height: width))
                ctx.restoreGState()
            }
            // A flare where the blade leaves the hilt.
            HandFXKit.glow(ctx, at: pose.base, radius: pose.width * 1.1, colour: colour, alpha: 0.7 * pose.strength)
        }
        if let speck = Self.spark {
            for p in rig.sparks.particles {
                let fade = 1 - p.progress
                ctx.stampDot(speck, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * 2.4, alpha: fade)
            }
        }
        ctx.interpolationQuality = .high
    }

    private static let spark = HandFXKit.speckSprite(SIMD3(1, 0.85, 0.5))

    /// A swing leaves fading echoes of the blade behind it, joined by a faint fan of light, gone within a tenth of a second or so.
    private func drawTrail(for pose: LightBladeRig.Pose, colour: SIMD3<Double>, in ctx: CGContext) {
        guard let entry = rig.memory.entries.first(where: { $0.hand.id == pose.hand }) else { return }
        let history = entry.state.history
        guard history.count >= 2, abs(entry.state.turn) > 2.2 else { return }
        let swing = min(1, (abs(entry.state.turn) - 2.2) / 6)
        let newest = history[history.count - 1].time
        let width = pose.width * 2.1
        for i in 1..<history.count {
            let a = history[i - 1], b = history[i]
            let fade = max(0, 1 - (newest - a.time) / 0.14) * swing * pose.strength
            guard fade > 0.01 else { continue }
            // The fan between two echoes, from a quarter of the way up, where the blade sweeps fastest.
            let a0 = HandFXKit.lerp(a.base, a.tip, 0.25), b0 = HandFXKit.lerp(b.base, b.tip, 0.25)
            ctx.beginPath()
            ctx.move(to: a0)
            ctx.addLine(to: a.tip)
            ctx.addLine(to: b.tip)
            ctx.addLine(to: b0)
            ctx.closePath()
            ctx.setFillColor(HandFXKit.cgColor(colour, 0.12 * fade))
            ctx.fillPath()
            // An echo of the blade itself, soft-edged, where it was.
            if let beam = Self.beam(pose.colour) {
                HandFXKit.drawBeam(beam, from: a0, to: a.tip, width: width * 0.8, alpha: 0.3 * fade, in: ctx)
            }
        }
    }

    /// The hilt: brushed metal with a grip, a collar where the blade comes out, and a small light in the blade's colour. Drawn once and
    /// turned to fit; it is flipped across its length so its lit side always faces the top left, where the light comes from.
    private func drawHilts(in ctx: CGContext, poses: [LightBladeRig.Pose]) {
        guard let hilt = Self.hiltSprite else { return }
        ctx.interpolationQuality = .high
        for pose in poses {
            let show = min(1, pose.strength * 4 + 0.0)
            guard show > 0.01 else { continue }
            let d = pose.direction
            let angle = atan2(d.y, d.x)
            // The sprite's lit side is its +y side; flip it when that side faces away from the top left.
            let normal = SIMD2(-d.y, d.x)
            let flip: CGFloat = simd_dot(normal, SIMD2(-0.707, 0.707)) >= 0 ? 1 : -1
            let length = pose.hiltLength, width = length * Double(hilt.height) / Double(hilt.width)
            ctx.saveGState()
            ctx.translateBy(x: pose.hiltCentre.x, y: pose.hiltCentre.y)
            ctx.rotate(by: CGFloat(angle))
            ctx.scaleBy(x: 1, y: flip)
            ctx.setAlpha(CGFloat(show))
            ctx.draw(hilt, in: CGRect(x: -length / 2, y: -width / 2, width: length, height: width))
            // The little light on the side, in the blade's colour.
            let c = HandFXPalette.blades[pose.colour % HandFXPalette.blades.count]
            HandFXKit.glow(ctx, at: CGPoint(x: length * 0.12, y: width * 0.12), radius: width * 0.42, colour: c, alpha: 0.9 * show)
            ctx.restoreGState()
        }
        ctx.interpolationQuality = .high
    }

    /// The hilt along +x (the blade comes out at the right), lit from +y.
    private static let hiltSprite: CGImage? = {
        let w = 300.0, h = 72.0
        guard let ctx = HandFXKit.bitmap(width: Int(w), height: Int(h)) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func colour(_ g: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: space, components: [g * 0.96, g * 0.98, g, a])! }
        /// A metal cylinder across `rect`: bright along the upper third, dark along the bottom.
        func cylinder(_ rect: CGRect, radius: Double, light: Double, dark: Double) {
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let stops = [colour(dark * 0.8), colour(dark), colour(light * 0.9), colour(light), colour(light * 0.75), colour(dark * 0.7)] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: stops, locations: [0, 0.18, 0.5, 0.66, 0.82, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
            }
            ctx.restoreGState()
        }
        // Soft shadow under the whole hilt, toward the bottom right.
        ctx.setShadow(offset: CGSize(width: 2, height: -3), blur: 5, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 8, y: 14, width: w - 26, height: h - 30), cornerWidth: 18, cornerHeight: 18, transform: nil))
        ctx.setFillColor(colour(0.3))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        // The body, the pommel, the grip and the collar.
        cylinder(CGRect(x: 8, y: 14, width: w - 26, height: h - 30), radius: 18, light: 0.82, dark: 0.22)
        cylinder(CGRect(x: 6, y: 12, width: 34, height: h - 26), radius: 14, light: 0.6, dark: 0.12)
        for k in 0..<6 {
            cylinder(CGRect(x: 58 + Double(k) * 21, y: 12, width: 11, height: h - 26), radius: 5, light: 0.32, dark: 0.07)
        }
        cylinder(CGRect(x: w - 64, y: 6, width: 52, height: h - 14), radius: 12, light: 0.95, dark: 0.28)
        // The emitter's dark mouth and a bright rim round it.
        ctx.setFillColor(colour(0.08))
        ctx.fill(CGRect(x: w - 14, y: 16, width: 8, height: h - 34))
        ctx.setStrokeColor(colour(1, 0.8))
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: w - 63, y: h - 12)); ctx.addLine(to: CGPoint(x: w - 14, y: h - 12))
        ctx.strokePath()
        // A dark socket for the little light.
        ctx.setFillColor(colour(0.05))
        ctx.fillEllipse(in: CGRect(x: w * 0.62 - 7, y: h * 0.62 - 7, width: 14, height: 14))
        return ctx.makeImage()
    }()
}
