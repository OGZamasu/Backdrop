import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Stars rushing past in deep space, streaming out from a point behind your head. Every few seconds the ship jumps: the stars
/// stretch into long lines, the tunnel glows, and then it eases back to cruising speed.
struct WorldWarpField {
    struct Star {
        /// Where it is across the view, in a unit square either side of the middle.
        var x: Double
        var y: Double
        /// How far away: 1 at the back, near 0 as it passes the camera.
        var z: Double
        var brightness: Double
        var warm: Bool
    }

    let size: CGSize
    private(set) var stars: [Star] = []
    private(set) var time = 0.0
    private var rng: SplitMix64
    /// Seconds between jumps, and how long one lasts.
    static let jumpEvery = 9.0
    static let jumpLength = 2.6

    init(size: CGSize, count: Int = 240, seed: UInt64 = 0x3A2F) {
        self.size = size
        rng = SplitMix64(seed: seed)
        for _ in 0..<count { stars.append(makeStar(z: Double.random(in: 0.05...1, using: &rng))) }
    }

    private mutating func makeStar(z: Double) -> Star {
        // Somewhere in view at its depth, but never straight down the middle, where a star would sit still and hide behind you.
        let focal = size.height * 0.36
        let reachX = size.width * 0.62 / focal * z, reachY = size.height * 0.62 / focal * z
        var x = 0.0, y = 0.0
        repeat {
            x = Double.random(in: -reachX...reachX, using: &rng)
            y = Double.random(in: -reachY...reachY, using: &rng)
        } while x * x + y * y < 0.012
        return Star(x: x, y: y, z: z, brightness: Double.random(in: 0.35...1, using: &rng), warm: Double.random(in: 0..<1, using: &rng) < 0.12)
    }

    /// 0 cruising ... 1 in the middle of a jump. Eased in and out so nothing lurches.
    static func jump(at t: Double) -> Double {
        let phase = (t - 3).truncatingRemainder(dividingBy: jumpEvery)
        guard t >= 3, phase < jumpLength else { return 0 }
        let rise = WorldKit.smoothstep(0, 0.7, phase), fall = 1 - WorldKit.smoothstep(jumpLength - 0.9, jumpLength, phase)
        return rise * fall
    }

    /// How fast the stars come at the camera, in depth units a second.
    static func speed(at t: Double) -> Double { 0.32 + 2.6 * pow(jump(at: t), 1.5) }

    /// Where a star at depth `z` shows on screen, given the point everything streams out from.
    func project(x: Double, y: Double, z: Double, from centre: SIMD2<Double>) -> SIMD2<Double> {
        let focal = size.height * 0.36
        return centre + SIMD2(x, y) * focal / max(0.02, z)
    }

    mutating func step(_ rawDt: Double, centre: SIMD2<Double>) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        let v = Self.speed(at: time)
        for i in stars.indices {
            stars[i].z -= v * dt
            let p = project(x: stars[i].x, y: stars[i].y, z: stars[i].z, from: centre)
            if stars[i].z < 0.03 || p.x < -60 || p.x > size.width + 60 || p.y < -60 || p.y > size.height + 60 {
                stars[i] = makeStar(z: Double.random(in: 0.85...1.0, using: &rng))
            }
        }
    }
}

/// The warp-speed filter: the room becomes deep space, stars stream past, and you are rim-lit in blue from the tunnel behind you.
final class WorldWarpLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    /// "Hyperspace": blue-white starlight with a few warm stars, and the cold blue of the tunnel.
    static let starlight = SIMD3<Double>(0.78, 0.88, 1.0)
    static let tunnel = SIMD3<Double>(0.25, 0.45, 1.0)

    private var field: WorldWarpField
    private var presence = WorldPresence()
    private var centre: SIMD2<Double>

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        field = WorldWarpField(size: size)
        centre = SIMD2(size.width / 2, size.height * 0.6)
    }

    func restart() {
        field = WorldWarpField(size: field.size)
        presence.reset()
    }

    var stars: [WorldWarpField.Star] { field.stars }
    var jump: Double { WorldWarpField.jump(at: field.time) }
    var vanishingPoint: SIMD2<Double> { centre }

    func render(_ input: LensInput) -> CIImage {
        presence.update(grid: input.matteGrid, dt: input.dt)
        let rect = input.rect
        // Everything streams out from just behind your head, drifting there gently rather than jumping with you.
        let wanted = presence.level > 0.3 ? SIMD2(presence.centre.x, min(rect.height * 0.72, presence.top - 90)) : SIMD2(rect.midX, rect.height * 0.6)
        centre += (wanted - centre) * (1 - exp(-WorldKit.clamped(input.dt) * 1.5))
        field.step(input.dt, centre: centre)
        let j = jump

        let space = WorldKit.grade(input.scenery, saturation: 0.4, tint: (0.04, 0.05, 0.1), lift: (0.0, 0.0, 0.004))
        let at = CGPoint(x: centre.x, y: centre.y)
        let tunnel = Self.tunnel
        var sky = WorldKit.adding(WorldKit.wash(center: at, radius: 420 + 160 * j, red: tunnel.x, green: tunnel.y, blue: tunnel.z, alpha: 0.13 + 0.3 * j, in: rect), to: space)
        sky = WorldKit.adding(WorldKit.wash(center: at, radius: 170 + 90 * j, red: 0.5, green: 0.65, blue: 1, alpha: 0.1 + 0.3 * j, in: rect), to: sky)
        if j > 0.01 { sky = WorldKit.adding(WorldKit.wash(center: at, radius: 50 + 70 * j, red: 0.9, green: 0.95, blue: 1, alpha: 0.6 * j, in: rect), to: sky) }
        if let layer = input.services.overlay({ ctx in draw(in: ctx, jump: j) }) { sky = WorldKit.adding(layer, to: sky) }

        let person = WorldKit.grade(input.composed, saturation: 0.85, tint: (0.6, 0.66, 0.82), lift: (0.0, 0.002, 0.008 + 0.01 * j))
        var body = WorldKit.place(person: person, over: sky, matte: input.matte, rect: rect)
        if let edge = WorldKit.edgeGlow(matte: input.matte, rect: rect, width: 26, colour: SIMD3(0.5, 0.7, 1.0), strength: 0.3 + 0.45 * j) {
            body = WorldKit.adding(edge, to: body)
        }
        return body
    }

    private func draw(in ctx: CGContext, jump j: Double) {
        let v = WorldWarpField.speed(at: field.time)
        // Each streak runs from where the star was a moment ago to where it is now; the faster, the longer.
        let trail = 0.05 + 0.1 * j
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        var bands: [[(CGPoint, CGPoint, Double)]] = Array(repeating: [], count: 6)
        for s in field.stars {
            let head = field.project(x: s.x, y: s.y, z: s.z, from: centre)
            let tail = field.project(x: s.x, y: s.y, z: s.z + v * trail, from: centre)
            let near = 1 - s.z
            let level = min(1, s.brightness * (0.25 + 0.95 * near * near) * min(1, (1 - s.z) * 5))
            let band = min(2, Int(level * 3)) + (s.warm ? 3 : 0)
            bands[band].append((CGPoint(x: tail.x, y: tail.y), CGPoint(x: head.x, y: head.y), near))
        }
        for (index, band) in bands.enumerated() where !band.isEmpty {
            let level = 0.3 + 0.32 * Double(index % 3)
            let c = index >= 3 ? SIMD3(1.0, 0.86, 0.72) : Self.starlight
            // The brightest streaks get a faint wide glow under them as well.
            for (width, alpha) in index % 3 == 2 ? [(4.5, 0.12), (1.7, 0.85)] : [(1.6, 0.85)] {
                let path = CGMutablePath()
                for (tail, head, _) in band {
                    path.move(to: tail)
                    path.addLine(to: head)
                }
                ctx.setLineWidth(width * (0.7 + 0.5 * Double(index % 3)))
                ctx.setStrokeColor(CGColor(red: c.x, green: c.y, blue: c.z, alpha: min(1, alpha * level)))
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        // The nearest stars get a small bright head.
        if let dot = WorldKit.softGlow(0.9, 0.95, 1) {
            for s in field.stars where s.z < 0.35 {
                let p = field.project(x: s.x, y: s.y, z: s.z, from: centre)
                ctx.stampDot(dot, at: CGPoint(x: p.x, y: p.y), radius: 2 + 5 * (0.35 - s.z), alpha: s.brightness * 0.8)
            }
        }
        ctx.setBlendMode(.normal)
    }
}
