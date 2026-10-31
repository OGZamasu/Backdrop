import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Fireflies wandering through a dark night, each blinking on its own slow rhythm. Move, and they drift over to see what you are doing.
struct FireflyGladeSim {
    struct Fly {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var heading: Double
        /// Cruising speed in pixels a second.
        var pace: Double
        var turn: Double
        var phase: Double
        var blinkRate: Double
        /// 0 far away (small, dim, behind you) to 1 close (large, soft, in front).
        var depth: Double
        var colour: SIMD3<Double>
        /// How curious it is right now, 0...1: brightens it and draws it in.
        var excitement = 0.0
    }

    /// Something the flies come to look at.
    struct Interest {
        var point: SIMD2<Double>
        /// 0...1
        var strength: Double
    }

    let size: CGSize
    private(set) var flies: [Fly] = []
    private(set) var time = 0.0
    private var rng: SplitMix64

    init(size: CGSize, count: Int = 52, seed: UInt64 = 0xF1E5) {
        self.size = size
        rng = SplitMix64(seed: seed)
        for _ in 0..<count { flies.append(makeFly()) }
    }

    private mutating func makeFly() -> Fly {
        let hue = Double.random(in: 0.14...0.25, using: &rng)
        let c = Palette.rgb(hue: hue, saturation: Double.random(in: 0.6...0.95, using: &rng))
        return Fly(position: SIMD2(Double.random(in: 0...size.width, using: &rng), Double.random(in: 0...size.height, using: &rng)),
                   velocity: .zero, heading: Double.random(in: 0..<(2 * .pi), using: &rng),
                   pace: Double.random(in: 22...60, using: &rng), turn: Double.random(in: 1.0...2.6, using: &rng),
                   phase: Double.random(in: 0..<(2 * .pi), using: &rng), blinkRate: 2 * .pi / Double.random(in: 1.9...4.2, using: &rng),
                   depth: pow(Double.random(in: 0...1, using: &rng), 0.8), colour: SIMD3(c.r, c.g, c.b))
    }

    /// How brightly a firefly shines right now, 0...1: mostly dark, with a long swelling glow once every few seconds.
    static func glow(of fly: Fly) -> Double {
        let wave = max(0, sin(fly.phase) * 1.2 - 0.2)
        return min(1, pow(wave, 1.5) + fly.excitement * 0.4)
    }

    mutating func removeAll() {
        flies.removeAll()
        time = 0
    }

    mutating func refill(count: Int = 52) {
        while flies.count < count { flies.append(makeFly()) }
    }

    mutating func step(_ rawDt: Double, interest: Interest?) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        let centre = SIMD2(size.width / 2, size.height / 2)
        for i in flies.indices {
            var f = flies[i]
            f.phase += f.blinkRate * dt
            // A lazy wander: the heading drifts on a slow wobble plus a little chance.
            f.heading += (sin(time * 0.7 + f.phase * 0.31) * 0.9 + Double.random(in: -1...1, using: &rng) * f.turn) * dt
            // Keep away from the very edge of the picture.
            let margin = 70.0
            if f.position.x < margin || f.position.x > size.width - margin || f.position.y < margin * 0.7 || f.position.y > size.height - margin * 0.7 {
                let home = atan2(centre.y - f.position.y, centre.x - f.position.x)
                var delta = home - f.heading
                delta = atan2(sin(delta), cos(delta))
                f.heading += delta * min(1, 2.2 * dt * 2)
            }
            let cruise = f.pace * (1 + 0.45 * sin(time * 1.3 + f.phase))
            var target = SIMD2(cos(f.heading), sin(f.heading)) * cruise
            target.y += sin(time * 2.1 + f.phase * 2) * 8        // bobbing

            f.excitement = max(0, f.excitement - dt * 1.4)
            if let interest {
                let to = interest.point - f.position
                let distance = simd_length(to)
                let reach = 560.0
                if distance < reach, distance > 1e-6 {
                    let near = 1 - distance / reach
                    let dir = to / distance
                    let perpendicular = SIMD2(-dir.y, dir.x)
                    // Come close, then circle about instead of piling up on the spot.
                    let radial = max(-1, min(1, (distance - 110) / 280))
                    target += (dir * radial * 240 + perpendicular * 120) * interest.strength * (0.35 + near)
                    f.excitement = max(f.excitement, interest.strength * near)
                }
            }
            f.velocity += (target - f.velocity) * (1 - exp(-2.2 * dt))
            let speed = simd_length(f.velocity)
            if speed > 230 { f.velocity *= 230 / speed }
            f.position += f.velocity * dt
            flies[i] = f
        }
    }
}

/// Finds where the person is moving, from how their silhouette changed since the last frame, and hands it to the flies as something to visit.
struct FireflyMotionWatcher {
    private var previous: [UInt8] = []
    private var level = 0.0
    private var point = SIMD2<Double>.zero

    mutating func reset() {
        previous = []
        level = 0
    }

    mutating func interest(from grid: MatteGrid?) -> FireflyGladeSim.Interest? {
        guard let grid else {
            level *= 0.9
            return level > 0.04 ? FireflyGladeSim.Interest(point: point, strength: level) : nil
        }
        defer { previous = grid.cells }
        guard previous.count == grid.cells.count else { return nil }

        // Every other cell is plenty to find an arm, and keeps this cheap.
        var count = 0.0, sx = 0.0, sy = 0.0
        let width = grid.width, height = grid.height
        grid.cells.withUnsafeBufferPointer { now in
            previous.withUnsafeBufferPointer { before in
                for gy in stride(from: 0, to: height, by: 2) {
                    let row = gy * width
                    for gx in stride(from: 0, to: width, by: 2) {
                        let change = Int(now[row + gx]) - Int(before[row + gx])
                        if change > 60 || change < -60 {
                            count += 4
                            sx += (Double(gx) + 0.5) * 4
                            sy += (Double(height - gy) - 0.5) * 4
                        }
                    }
                }
            }
        }
        if count >= 8 {
            let target = SIMD2(sx / count * grid.cellSize, sy / count * grid.cellSize)
            point = level < 0.05 ? target : point + (target - point) * 0.35
            level = min(1, level + 0.12 + count / 150)
        } else {
            level *= 0.93
        }
        return level > 0.04 ? FireflyGladeSim.Interest(point: point, strength: level) : nil
    }
}

final class FireflyGladeLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private var glade: FireflyGladeSim
    private var watcher = FireflyMotionWatcher()

    init(size: CGSize = CGSize(width: 1280, height: 720)) { glade = FireflyGladeSim(size: size) }

    func restart() {
        glade.removeAll()
        glade.refill()
        watcher.reset()
    }

    var flyCount: Int { glade.flies.count }
    var flies: [FireflyGladeSim.Fly] { glade.flies }

    func render(_ input: LensInput) -> CIImage {
        glade.step(input.dt, interest: watcher.interest(from: input.matteGrid))
        let rect = input.rect

        // "Glade": deep blue-green night in the room, and the person in cool moonlight so they are still plainly there.
        let night = WorldKit.grade(input.scenery, saturation: 0.55, tint: (0.10, 0.17, 0.22), lift: (0, 0.0015, 0.004))
        let vignette = CIFilter.vignette()
        vignette.inputImage = night
        vignette.intensity = 1.1
        vignette.radius = 1.9
        let sky = (vignette.outputImage ?? night).cropped(to: rect)
        let person = WorldKit.grade(input.composed, saturation: 0.75, tint: (0.36, 0.45, 0.56), lift: (0, 0.001, 0.004))

        var behind = sky
        if let layer = input.services.overlay({ ctx in draw(in: ctx, near: false) }) { behind = WorldKit.adding(layer, to: sky) }
        var body = WorldKit.place(person: person, over: behind, matte: input.matte, rect: rect)
        if let moon = WorldKit.rimLight(matte: input.matte, rect: rect, toward: WorldKit.keyLight, width: 12, colour: SIMD3(0.55, 0.7, 1.0), strength: 0.45) {
            body = WorldKit.adding(moon, to: body)
        }
        // The light a fly throws on you as it passes close: a wide warm pool, painted small, that only lands on you.
        if let matte = input.matte, let pools = softLight.draw(rect: rect, { ctx in drawPools(in: ctx) }) {
            body = WorldKit.adding(WorldKit.multiply(pools.settingAlphaOne(in: rect), matte).cropped(to: rect), to: body)
        }
        guard let front = input.services.overlay({ ctx in draw(in: ctx, near: true) }) else { return body }
        return WorldKit.adding(front, to: body).cropped(to: rect)
    }

    private let softLight = WorldSoftCanvas()

    private func drawPools(in ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        for f in glade.flies {
            let b = FireflyGladeSim.glow(of: f)
            guard b > 0.1, let pool = WorldKit.softGlow(f.colour.x, f.colour.y * 0.95, f.colour.z * 0.6) else { continue }
            ctx.stampDot(pool, at: CGPoint(x: f.position.x, y: f.position.y), radius: 70 + 60 * f.depth, alpha: 0.22 * b)
        }
        ctx.setBlendMode(.normal)
    }

    private func draw(in ctx: CGContext, near: Bool) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        defer {
            ctx.setBlendMode(.normal)
            ctx.interpolationQuality = .high
        }
        for f in glade.flies where (f.depth >= 0.55) == near {
            let b = FireflyGladeSim.glow(of: f)
            guard b > 0.02 else { continue }
            let p = CGPoint(x: f.position.x, y: f.position.y)
            let c = f.colour
            if f.depth > 0.94, let bokeh = Self.bokeh, let core = WorldKit.softGlow(1, 1, 0.7) {
                // So close it is out of focus: a soft disc of light with a faint bright rim, brightest in the middle.
                let r = 14 + 10 * (f.depth - 0.94) / 0.06
                ctx.setAlpha(CGFloat(0.6 * b))
                ctx.draw(bokeh, in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.setAlpha(1)
                ctx.stampDot(core, at: p, radius: r * 0.55, alpha: 0.9 * b)
                continue
            }
            // A wide halo, a warm body and a white-hot point. Close ones are bigger and softer, far ones small and sharp.
            if let halo = WorldKit.softGlow(c.x, c.y, c.z) {
                ctx.stampDot(halo, at: p, radius: 13 + 15 * f.depth, alpha: 0.34 * b)
                ctx.stampDot(halo, at: p, radius: 4.5 + 3.5 * f.depth, alpha: b)
            }
            if let core = WorldKit.softGlow(1, 1, 0.85) {
                ctx.stampDot(core, at: p, radius: 2.4 + 1.8 * f.depth, alpha: b)
            }
        }
    }

    /// An out-of-focus firefly: a warm disc, even inside with a slightly brighter rim. Drawn once.
    private static let bokeh: CGImage? = {
        let side = 64
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let c = CGFloat(side) / 2
        let colours = [CGColor(red: 0.85, green: 0.95, blue: 0.35, alpha: 0.35), CGColor(red: 0.85, green: 0.95, blue: 0.35, alpha: 0.42),
                       CGColor(red: 0.95, green: 1, blue: 0.55, alpha: 0.7), CGColor(red: 0.85, green: 0.95, blue: 0.35, alpha: 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.7, 0.85, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: c, y: c), startRadius: 0, endCenter: CGPoint(x: c, y: c), endRadius: c - 1, options: [])
        }
        return ctx.makeImage()
    }()
}
