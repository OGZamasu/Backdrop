import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Where a stage spotlight points. It follows you on a spring, so it lags a moment behind and settles with a small overshoot,
/// and with nobody on stage it sweeps slowly back and forth looking for someone.
struct WorldSpotlightRig {
    let size: CGSize
    private(set) var aim: SIMD2<Double>
    private(set) var velocity = SIMD2<Double>.zero
    /// How wide the pool of light is, in pixels from its middle to where it fades.
    private(set) var radius = 260.0
    private(set) var time = 0.0
    /// 0 searching ... 1 locked on to someone.
    private(set) var lock = 0.0

    init(size: CGSize) {
        self.size = size
        aim = SIMD2(size.width / 2, size.height * 0.5)
    }

    /// Where it drifts while nobody is there.
    func searchPoint(at t: Double) -> SIMD2<Double> {
        SIMD2(size.width * (0.5 + 0.3 * sin(t * 0.42)), size.height * (0.5 + 0.08 * sin(t * 0.83 + 1)))
    }

    /// `target` is the point on you to light (nil when nobody is there) and `width` how wide you are.
    mutating func step(_ rawDt: Double, target: SIMD2<Double>?, width: Double) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        lock += ((target == nil ? 0 : 1) - lock) * (1 - exp(-dt * 3))
        let goal = target ?? searchPoint(at: time)
        // A slightly under-damped spring: it overshoots a touch and settles, like a real operator.
        let stiffness = target == nil ? 6.0 : 26.0
        let damping = 2 * stiffness.squareRoot() * 0.72
        velocity += ((goal - aim) * stiffness - velocity * damping) * dt
        aim += velocity * dt
        let wanted = target == nil ? 210 : min(380, max(170, width * 0.55))
        radius += (wanted - radius) * (1 - exp(-dt * 3))
    }

    mutating func reset() {
        aim = SIMD2(size.width / 2, size.height * 0.5)
        velocity = .zero
        lock = 0
    }
}

/// A dark stage and one warm spotlight that finds you and follows you about: a soft beam from above, dust glittering in it, a pool
/// of light on you and the wall behind, and your shadow cast down the wall.
final class WorldSpotlightLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    /// "Tungsten": the warm white of a theatre lamp.
    static let lamp = SIMD3<Double>(1.0, 0.92, 0.78)

    private var rig: WorldSpotlightRig
    private var presence = WorldPresence()
    private var motes: [(position: SIMD2<Double>, phase: Double, size: Double)]

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        rig = WorldSpotlightRig(size: size)
        var seeded = SplitMix64(seed: 0xD057)
        motes = (0..<90).map { _ in
            (SIMD2(Double.random(in: 0...size.width, using: &seeded), Double.random(in: 0...size.height, using: &seeded)),
             Double.random(in: 0...(2 * .pi), using: &seeded), Double.random(in: 1.0...2.6, using: &seeded))
        }
    }

    func restart() {
        rig.reset()
        presence.reset()
    }

    var aim: SIMD2<Double> { rig.aim }
    var lock: Double { rig.lock }

    /// Where the lamp hangs: above the top of the picture, leaning a little toward where it points.
    private func source(_ rect: CGRect) -> SIMD2<Double> {
        SIMD2(rect.midX + (rig.aim.x - rect.midX) * 0.35, rect.maxY + 260)
    }

    func render(_ input: LensInput) -> CIImage {
        presence.update(grid: input.matteGrid, dt: input.dt)
        let rect = input.rect
        let target: SIMD2<Double>? = presence.level > 0.5 ? SIMD2(presence.centre.x, max(presence.centre.y + 40, presence.top - 150)) : nil
        rig.step(input.dt, target: target, width: presence.width)
        let t = input.time
        stepMotes(WorldKit.clamped(input.dt), time: t)

        let at = CGPoint(x: rig.aim.x, y: rig.aim.y)
        let l = Self.lamp
        // Lighting is a multiplier: a little light everywhere, a lot in the pool.
        func lightMap(radius: Double, strength: Double, ambient: Double) -> CIImage {
            let pool = WorldKit.wash(center: at, radius: radius, red: l.x * strength, green: l.y * strength, blue: l.z * strength, alpha: 1, in: rect)
            let base = CIImage(color: CIColor(red: CGFloat(ambient), green: CGFloat(ambient * 0.95), blue: CGFloat(ambient * 1.1))).cropped(to: rect)
            return WorldKit.adding(pool, to: base)
        }
        // The wall: lit in a wider pool, with your shadow thrown down onto it.
        var wallLight = lightMap(radius: rig.radius * 1.35, strength: 1.25, ambient: 0.1)
        if let matte = input.matte {
            let scale = 0.25
            let box = CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale)
            let shadow = WorldKit.shrink(matte, rect: rect, by: scale).transformed(by: CGAffineTransform(translationX: 6, y: -14))
                .clampedToExtent().applyingGaussianBlur(sigma: 5).cropped(to: box)
            let keep = WorldKit.inverted(WorldKit.tint(shadow, SIMD3(1, 1, 1), strength: 0.75 * rig.lock))
            wallLight = WorldKit.multiply(wallLight, WorldKit.enlarge(keep.settingAlphaOne(in: box), rect: rect, from: scale))
        }
        let wall = WorldKit.multiply(WorldKit.grade(input.scenery, saturation: 0.75, tint: (0.9, 0.85, 0.82)), wallLight).cropped(to: rect)
        var behind = wall
        if let beam = input.services.overlay({ ctx in drawBeam(in: ctx, rect: rect, time: t) }) { behind = WorldKit.adding(beam, to: behind) }

        // You: lit in a tighter, brighter pool, warm on the side facing the lamp.
        let youLight = lightMap(radius: rig.radius, strength: 1.35, ambient: 0.16)
        let lit = WorldKit.multiply(WorldKit.grade(input.composed, saturation: 1.0, tint: (1.02, 0.98, 0.94)), youLight).cropped(to: rect)
        var body = WorldKit.place(person: lit, over: behind, matte: input.matte, rect: rect)
        let toward = simd_normalize(source(rect) - rig.aim)
        if let rim = WorldKit.rimLight(matte: input.matte, rect: rect, toward: toward, width: 12, colour: l, strength: 0.45 * rig.lock) {
            body = WorldKit.adding(rim, to: body)
        }
        if let front = input.services.overlay({ ctx in drawMotes(in: ctx, rect: rect, time: t) }) { body = WorldKit.adding(front, to: body) }
        return body.cropped(to: rect)
    }

    // MARK: Beam and dust

    private func stepMotes(_ dt: Double, time: Double) {
        let size = rig.size
        for i in motes.indices {
            var m = motes[i]
            m.position += SIMD2(sin(time * 0.31 + m.phase) * 9, cos(time * 0.23 + m.phase * 1.7) * 6 - 3) * dt
            if m.position.y < -10 { m.position.y = size.height + 10 }
            if m.position.x < -10 { m.position.x = size.width + 10 }
            if m.position.x > size.width + 10 { m.position.x = -10 }
            motes[i] = m
        }
    }

    /// How far inside the beam a point is: 1 on its centre line, 0 outside it.
    private func insideBeam(_ p: SIMD2<Double>, rect: CGRect) -> Double {
        let a = source(rect), b = rig.aim
        let axis = b - a
        let length = simd_length(axis)
        guard length > 1 else { return 0 }
        let along = simd_dot(p - a, axis) / (length * length)
        guard along > 0 else { return 0 }
        let halfWidth = rig.radius * 0.85 * along
        let off = abs(simd_dot(p - a, SIMD2(-axis.y, axis.x) / length))
        return max(0, 1 - off / max(1, halfWidth)) * min(1, along * 1.6)
    }

    private func drawBeam(in ctx: CGContext, rect: CGRect, time: Double) {
        guard let beam = Self.beam else { return }
        let a = source(rect), b = rig.aim
        let axis = b - a
        let length = simd_length(axis) * 1.08
        let width = rig.radius * 1.8 * 1.08
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.translateBy(x: a.x, y: a.y)
        ctx.rotate(by: atan2(axis.y, axis.x) + .pi / 2)
        ctx.setAlpha(0.3 * (0.94 + 0.06 * sin(time * 1.3)))
        ctx.draw(beam, in: CGRect(x: -width / 2, y: -length, width: width, height: length))
        ctx.restoreGState()
    }

    private func drawMotes(in ctx: CGContext, rect: CGRect, time: Double) {
        guard let dot = WorldKit.softGlow(1, 0.95, 0.85) else { return }
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        for m in motes {
            let inside = insideBeam(m.position, rect: rect)
            guard inside > 0.02 else { continue }
            let twinkle = 0.55 + 0.45 * sin(time * 2.1 + m.phase * 5)
            ctx.stampDot(dot, at: CGPoint(x: m.position.x, y: m.position.y), radius: m.size * 2.2, alpha: inside * twinkle * 0.75)
        }
        ctx.interpolationQuality = .high
        ctx.setBlendMode(.normal)
    }

    /// The beam of light, pointing down: narrow and brighter at the lamp, wide and fading at the far end, soft at the sides,
    /// with faint streaks of haze along it. Drawn once.
    private static let beam: CGImage? = {
        let w = 128, h = 256
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let l = lamp
        for y in 0..<h {
            let v = Double(y) / Double(h - 1)              // 0 at the lamp (top row) ... 1 at the far end
            let half = 0.06 + 0.44 * v
            let along = (1 - WorldKit.smoothstep(0.35, 1, v)) * (0.55 + 0.45 * (1 - v)) * WorldKit.smoothstep(0, 0.08, v)
            for x in 0..<w {
                let u = (Double(x) + 0.5) / Double(w) - 0.5
                let edge = 1 - WorldKit.smoothstep(half * 0.55, half, abs(u))
                let haze = 0.82 + 0.18 * sin(u / max(0.05, half) * 9 + v * 3)
                let a = min(1, edge * along * haze)
                let i = (y * w + x) * 4
                bytes[i] = UInt8(min(255, l.z * a * 255))
                bytes[i + 1] = UInt8(min(255, l.y * a * 255))
                bytes[i + 2] = UInt8(min(255, l.x * a * 255))
                bytes[i + 3] = UInt8(min(255, a * 255))
            }
        }
        return bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)?.makeImage()
        }
    }()
}
