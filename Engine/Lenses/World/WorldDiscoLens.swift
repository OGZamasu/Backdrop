import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// A disco: a mirror ball turns at the top of the picture and throws spots of coloured light that sweep across the room and
/// across you; coloured beams swing from the corners, and the light pulses gently on the beat.
final class WorldDiscoLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    /// "Studio": the colours of the lights.
    static let palette: [SIMD3<Double>] = [
        SIMD3(1.0, 0.28, 0.72), SIMD3(0.22, 0.84, 1.0), SIMD3(1.0, 0.8, 0.32), SIMD3(0.62, 0.38, 1.0), SIMD3(1.0, 0.96, 0.9),
    ]
    static let tempo = 118.0

    /// 1 on each beat, falling away to 0 before the next: a soft pulse, never a strobe.
    static func beat(at t: Double) -> Double {
        let phase = (t * tempo / 60).truncatingRemainder(dividingBy: 1)
        return exp(-phase * 5)
    }

    /// How far the ball has turned.
    static func turn(at t: Double) -> Double { t * 0.55 }

    private struct Spot {
        var longitude: Double
        var latitude: Double
        var colour: Int
        var size: Double
    }

    private let size: CGSize
    private let spots: [Spot]
    private var presence = WorldPresence()

    init(size: CGSize = CGSize(width: 1280, height: 720)) {
        self.size = size
        var rng = SplitMix64(seed: 0xD15C0)
        spots = (0..<170).map { _ in
            Spot(longitude: Double.random(in: -Double.pi...Double.pi, using: &rng), latitude: Double.random(in: -1.0...0.42, using: &rng),
                 colour: Double.random(in: 0...1, using: &rng) < 0.4 ? 4 : Int.random(in: 0..<4, using: &rng),
                 size: Double.random(in: 4.5...9, using: &rng))
        }
    }

    func restart() { presence.reset() }

    /// Where the ball hangs.
    var ballCentre: CGPoint { CGPoint(x: size.width / 2, y: size.height - 74) }
    static let ballRadius = 58.0

    /// Where each spot is on the picture right now, and how bright, for the spots facing the room.
    func spotPositions(at t: Double) -> [(position: SIMD2<Double>, strength: Double, colour: Int, size: Double)] {
        let turn = Self.turn(at: t)
        return spots.compactMap { s in
            var lon = (s.longitude + turn).truncatingRemainder(dividingBy: 2 * .pi)
            if lon > .pi { lon -= 2 * .pi }
            if lon < -.pi { lon += 2 * .pi }
            guard abs(lon) < 1.2 else { return nil }
            // Thrown onto the back wall: they spread out and speed up toward the sides.
            let x = size.width / 2 + tan(lon) * size.width * 0.28
            let y = size.height * 0.84 + tan(s.latitude) * size.height * 0.5
            let strength = pow(cos(lon), 0.7) * (1 - WorldKit.smoothstep(0.95, 1.2, abs(lon)))
            return (SIMD2(x, y), strength, s.colour, s.size / max(0.45, cos(lon)))
        }
    }

    func render(_ input: LensInput) -> CIImage {
        presence.update(grid: input.matteGrid, dt: input.dt)
        let rect = input.rect, t = input.time
        let pulse = Self.beat(at: t)

        let dark = WorldKit.grade(input.scenery, saturation: 0.8, tint: (0.16, 0.13, 0.24), lift: (0.002, 0.0, 0.006))
        var room = dark
        if let beams = beamLayer(rect: rect, time: t, pulse: pulse) { room = WorldKit.adding(beams, to: room) }
        let person = WorldKit.grade(input.composed, saturation: 1.0, tint: (0.42, 0.38, 0.52), lift: (0.002, 0.0, 0.006))
        var body = WorldKit.place(person: person, over: room, matte: input.matte, rect: rect)
        // The beams light your edges in their colours, changing every bar.
        let bar = Int(t * Self.tempo / 60 / 4)
        let left = Self.palette[bar % 4], right = Self.palette[(bar + 2) % 4]
        if let a = WorldKit.rimLight(matte: input.matte, rect: rect, toward: simd_normalize(SIMD2(-0.8, 0.6)), width: 14, colour: left, strength: 0.45 + 0.25 * pulse) {
            body = WorldKit.adding(a, to: body)
        }
        if let b = WorldKit.rimLight(matte: input.matte, rect: rect, toward: simd_normalize(SIMD2(0.8, 0.6)), width: 14, colour: right, strength: 0.45 + 0.25 * pulse) {
            body = WorldKit.adding(b, to: body)
        }
        // The spots fall on everything, you included, and the ball hangs in front.
        if let light = input.services.overlay({ ctx in drawSpots(in: ctx, time: t, pulse: pulse) }) { body = WorldKit.adding(light, to: body) }
        guard let ball = input.services.overlay({ ctx in drawBall(in: ctx, time: t, pulse: pulse) }) else { return body }
        return ball.composited(over: body).cropped(to: rect)
    }

    // MARK: Drawing

    private func drawSpots(in ctx: CGContext, time: Double, pulse: Double) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        for s in spotPositions(at: time) {
            guard let spot = spotSprites[s.colour] else { continue }
            // Each spot is a little square of light from one mirror, a touch soft at the edge, stretched where it hits at a slant.
            let r = s.size
            ctx.setAlpha(CGFloat(s.strength * (0.7 + 0.3 * pulse)))
            ctx.draw(spot, in: CGRect(x: s.position.x - r * 1.25, y: s.position.y - r, width: r * 2.5, height: r * 2))
        }
        ctx.setAlpha(1)
        ctx.interpolationQuality = .high
        ctx.setBlendMode(.normal)
    }

    private lazy var beamImage = WorldKit.ciSprite(Self.beam)
    private lazy var spotSprites: [CGImage?] = Self.palette.map { Self.spot($0) }

    /// One reflected spot: a bright rounded square with a soft glow round it, in one of the light colours.
    private static func spot(_ c: SIMD3<Double>) -> CGImage? {
        let side = 32
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let mid = CGFloat(side) / 2
        let glow = [CGColor(red: c.x, green: c.y, blue: c.z, alpha: 0.5), CGColor(red: c.x, green: c.y, blue: c.z, alpha: 0)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: glow, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: mid, y: mid), startRadius: 0, endCenter: CGPoint(x: mid, y: mid), endRadius: mid, options: [])
        }
        ctx.setShadow(offset: .zero, blur: 3, color: CGColor(red: c.x, green: c.y, blue: c.z, alpha: 1))
        ctx.setFillColor(CGColor(red: min(1, c.x * 0.5 + 0.5), green: min(1, c.y * 0.5 + 0.5), blue: min(1, c.z * 0.5 + 0.5), alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: mid - 6, y: mid - 6, width: 12, height: 12), cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.fillPath()
        return ctx.makeImage()
    }

    /// Three coloured beams from above, swinging slowly, laid out on the graphics chip.
    private func beamLayer(rect: CGRect, time: Double, pulse: Double) -> CIImage? {
        guard let beam = beamImage else { return nil }
        let bar = Int(time * Self.tempo / 60 / 4)
        let rigs: [(x: Double, sweep: Double, speed: Double, phase: Double)] = [(0.08, 0.5, 0.5, 0), (0.92, 0.5, 0.43, 2.1), (0.5, 0.7, 0.31, 4.2)]
        var layers: [CIImage] = []
        for (k, r) in rigs.enumerated() {
            let c = Self.palette[(bar + k) % 4]
            let angle = -Double.pi / 2 + (r.x - 0.5) * -1.1 + r.sweep * sin(time * r.speed + r.phase)
            let length = size.height * 1.5, width = 240.0
            // Tinting lights up everything outside the sprite too, so cut it back to the sprite before moving it.
            layers.append(WorldKit.placed(WorldKit.tint(beam, c, strength: 1).cropped(to: beam.extent), size: CGSize(width: width, height: length), anchor: CGPoint(x: width / 2, y: length),
                                          angle: angle + .pi / 2, at: CGPoint(x: size.width * r.x, y: size.height + 30), alpha: 0.2 + 0.1 * pulse))
        }
        return WorldKit.sum(layers, rect: rect)
    }

    /// The mirror ball: a sphere of small square mirrors, each catching the light at its own angle, turning, with a few tiles
    /// flashing and a chain up out of the picture.
    private func drawBall(in ctx: CGContext, time: Double, pulse: Double) {
        let c = ballCentre
        let r = Self.ballRadius
        ctx.setStrokeColor(CGColor(red: 0.55, green: 0.55, blue: 0.6, alpha: 1))
        ctx.setLineWidth(2.5)
        ctx.move(to: CGPoint(x: c.x, y: c.y + r))
        ctx.addLine(to: CGPoint(x: c.x, y: size.height + 4))
        ctx.strokePath()
        // The dark grout between the mirrors, shaded as a sphere.
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let g = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.42, green: 0.42, blue: 0.48, alpha: 1), CGColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)] as CFArray,
                              locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.35), startRadius: 0, endCenter: c, endRadius: r * 1.05, options: [])
        }
        let turn = Self.turn(at: time)
        let rows = 11, columns = 22
        let light = simd_normalize(SIMD3(-0.55, 0.65, 0.55))
        for row in 0..<rows {
            let lat0 = -Double.pi / 2 + Double(row) / Double(rows) * .pi, lat1 = -Double.pi / 2 + Double(row + 1) / Double(rows) * .pi
            for col in 0..<columns {
                let lon0 = Double(col) / Double(columns) * 2 * .pi + turn, lon1 = Double(col + 1) / Double(columns) * 2 * .pi + turn
                let mid = (lon0 + lon1) / 2, midLat = (lat0 + lat1) / 2
                let normal = SIMD3(cos(midLat) * sin(mid), sin(midLat), cos(midLat) * cos(mid))
                guard normal.z > 0.05 else { continue }
                func point(_ lat: Double, _ lon: Double) -> CGPoint {
                    let inset = 0.9
                    return CGPoint(x: c.x + r * cos(lat) * sin(lon) * inset + r * 0.0, y: c.y + r * sin(lat) * inset)
                }
                // Shrink each tile toward its middle a little so the grout shows.
                let a = point(lat0 + 0.03, lon0 + 0.03), b = point(lat0 + 0.03, lon1 - 0.03), d = point(lat1 - 0.03, lon0 + 0.03), e = point(lat1 - 0.03, lon1 - 0.03)
                let diffuse = max(0, simd_dot(normal, light))
                let seed = row * 131 + col * 17 + Int(turn / (2 * .pi / Double(columns)))
                let sparkle = WorldKit.hash(seed + Int(time * 6)) > 0.93 ? 1.0 : 0
                let level = 0.25 + 0.6 * diffuse + 0.35 * normal.z * normal.z
                let tint = sparkle > 0 ? Self.palette[(row + col) % 5] : SIMD3(0.82, 0.86, 0.95)
                let v = min(1, level + 0.5 * sparkle)
                ctx.setFillColor(CGColor(red: tint.x * v, green: tint.y * v, blue: tint.z * v, alpha: 1))
                ctx.move(to: a); ctx.addLine(to: b); ctx.addLine(to: e); ctx.addLine(to: d); ctx.closePath()
                ctx.fillPath()
            }
        }
        ctx.restoreGState()
        // A bright highlight where the key light hits, and a couple of glints.
        ctx.glow(center: CGPoint(x: c.x - r * 0.38, y: c.y + r * 0.4), radius: r * 0.5, red: 1, green: 1, blue: 1, alpha: 0.5)
        if let star = WorldKit.star(1, 0.97, 0.9) {
            ctx.setBlendMode(.plusLighter)
            for k in 0..<3 {
                let phase = time * 1.7 + Double(k) * 2.1
                let at = CGPoint(x: c.x + r * 0.62 * sin(phase * 0.7 + Double(k)), y: c.y + r * 0.5 * cos(phase * 0.5 + Double(k) * 1.3))
                ctx.stampDot(star, at: at, radius: 16 + 10 * pulse, alpha: max(0, sin(phase * 2.3)) * 0.9)
            }
            ctx.setBlendMode(.normal)
        }
    }

    /// A beam of light pointing down, as a grey mask: bright and narrow at the top, wide and fading at the bottom, soft at the sides.
    private static let beam: CGImage? = {
        let w = 64, h = 256
        var bytes = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let v = Double(y) / Double(h - 1)
            let half = 0.08 + 0.42 * v
            let along = (1 - WorldKit.smoothstep(0.3, 1, v)) * WorldKit.smoothstep(0, 0.05, v)
            for x in 0..<w {
                let u = (Double(x) + 0.5) / Double(w) - 0.5
                let a = (1 - WorldKit.smoothstep(half * 0.4, half, abs(u))) * along
                bytes[y * w + x] = UInt8(min(255, a * 255))
            }
        }
        return bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
    }()
}
