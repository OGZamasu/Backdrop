import CoreGraphics
import CoreImage

/// A small cloud follows your head around and sulks. Raise your eyebrows and it darkens, rains on you and throws lightning.
final class ExprStormCloudLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    /// Brow raise needed to start the storm, and (lower) to keep it going.
    static let startAt = 0.55, stopAt = 0.35

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var rain = ParticleSystem(capacity: 260)
    private var rng = SplitMix64(seed: 0x57024)
    private var raising = ExprLatch()
    private var storm = Ramp()
    private var owed = 0.0
    private var visibleFor = 0.0
    private var untilBolt = 0.0
    /// The bolt in face units, from the cloud down to the face, and how long ago it struck. Nil when there is none.
    private var bolt: [CGPoint]?
    private var boltAge = 0.0
    private(set) var boltCount = 0
    /// The picture's bounds, so the cloud can be kept inside them.
    private var bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)

    var isStormy: Bool { raising.isOn }
    var rainCount: Int { rain.particles.count }
    /// How dark and angry the cloud is, 0...1.
    var stormLevel: Double { storm.value }
    /// How bright the last lightning flash still is, 0...1.
    var flashLevel: Double { bolt == nil ? 0 : Self.envelope(boltAge) }

    init() { rain.gravity = .zero }

    func restart() {
        rain.removeAll()
        raising.reset()
        storm = Ramp()
        owed = 0; visibleFor = 0; untilBolt = 0
        bolt = nil; boltCount = 0
    }

    /// How bright a strike is at `age` seconds: two quick flickers, then a fade.
    static func envelope(_ age: Double) -> Double {
        if age < 0.06 { return 1 }
        if age < 0.1 { return 0.3 }
        if age < 0.2 { return 1 }
        return max(0, 1 - (age - 0.2) / 0.14)
    }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Raise your eyebrows for a storm")
        let dt = min(input.dt, 0.25)
        bounds = input.rect

        if let face = input.face {
            visibleFor += dt
            let was = raising.isOn
            raising.update(face.browRaise, on: Self.startAt, off: Self.stopAt)
            if raising.isOn && !was { untilBolt = 0.3 }
            storm.move(toward: raising.isOn ? 1 : 0, dt: dt, rate: raising.isOn ? 3.5 : 1.6)
            if raising.isOn {
                makeRain(from: face, time: input.time, dt: dt)
                untilBolt -= dt
                if untilBolt <= 0 { strike(); untilBolt = Double.random(in: 0.8...1.8, using: &rng) }
            }
        } else {
            raising.reset()
            visibleFor = 0
            storm.move(toward: 0, dt: dt, rate: 3)
        }
        if bolt != nil {
            boltAge += dt
            if boltAge > 0.36 { bolt = nil }
        }
        rain.step(dt)
        if input.face == nil && rain.particles.isEmpty && bolt == nil { return input.composed }

        guard let layer = input.services.exprOverlay({ ctx in draw(ctx, face: input.face, time: input.time) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    // MARK: Where things are

    /// Where the cloud floats: above the head, bobbing gently, and never off the edge of the picture (a face close to the
    /// camera has no room above it, so the cloud comes down to sit on the hair).
    private func cloudCenter(_ face: FaceState, time: Double) -> CGPoint {
        let io = face.interocular
        let base = face.exprPoint(0, 2.15)
        let bobbing = CGPoint(x: base.x + sin(time * 0.9) * io * 0.08, y: base.y + sin(time * 1.7) * io * 0.05)
        let h = cloudHeight(face)
        return face.exprKeepInside(bobbing, half: CGSize(width: h * 0.48, height: h * 0.34), in: bounds)
    }

    /// The cloud's height in pixels (its whole picture), a little bigger when it is angry.
    private func cloudHeight(_ face: FaceState) -> Double { face.interocular * (2.0 + 0.3 * storm.value) }

    // MARK: Weather

    private func makeRain(from face: FaceState, time: Double, dt: Double) {
        let io = face.interocular
        let centre = cloudCenter(face, time: time)
        let width = cloudHeight(face) * 0.36
        owed += dt * 150 * storm.value
        while owed >= 1 {
            owed -= 1
            let speed = io * Double.random(in: 9...13, using: &rng)
            let start = SIMD2(centre.x + Double.random(in: -1...1, using: &rng) * width, centre.y - io * 0.42)
            rain.emit(Particle(position: start, velocity: SIMD2(-speed * 0.07, -speed),
                               life: io * 5.2 / speed, size: io * Double.random(in: 0.2...0.34, using: &rng)))
        }
    }

    private func strike() {
        boltCount += 1
        boltAge = 0
        let startX = Double.random(in: -0.5...0.5, using: &rng)
        let endX = Double.random(in: -0.55...0.55, using: &rng)
        let endY = Double.random(in: -1.0 ... -0.3, using: &rng)
        let top = 1.78
        var points: [CGPoint] = []
        let steps = 8
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let jitter = i == 0 || i == steps ? 0 : Double.random(in: -0.2...0.2, using: &rng)
            points.append(CGPoint(x: startX + (endX - startX) * t + jitter, y: top + (endY - top) * t))
        }
        bolt = points
    }

    // MARK: Drawing

    private func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        if let face {
            let io = face.interocular
            let strobe = flashLevel
            if strobe > 0 {
                ctx.glow(center: face.exprFaceCenter, radius: io * 3.2, red: 0.8, green: 0.88, blue: 1, alpha: 0.38 * strobe)
            }
            drawCloud(ctx, face: face, time: time)
            ctx.setLineCap(.round)
            ctx.setLineWidth(max(1.2, io * 0.025))
            for p in rain.particles {
                let fade = min(1, p.age / 0.08)
                let along = SIMD2(p.velocity.x, p.velocity.y) / max(hypot(p.velocity.x, p.velocity.y), 1)
                ctx.setStrokeColor(exprColor((0.72, 0.86, 1.0), 0.75 * fade))
                ctx.move(to: CGPoint(x: p.position.x, y: p.position.y))
                ctx.addLine(to: CGPoint(x: p.position.x - along.x * p.size, y: p.position.y - along.y * p.size))
                ctx.strokePath()
            }
            if let bolt { drawBolt(ctx, face: face, points: bolt) }
        } else {
            // The cloud is gone with the face; let the last of the rain finish falling.
            ctx.setLineCap(.round)
            ctx.setLineWidth(2)
            for p in rain.particles {
                ctx.setStrokeColor(exprColor((0.72, 0.86, 1.0), 0.6 * (1 - p.progress)))
                ctx.move(to: CGPoint(x: p.position.x, y: p.position.y))
                ctx.addLine(to: CGPoint(x: p.position.x + p.velocity.x * 0.02, y: p.position.y + p.velocity.y * 0.02))
                ctx.strokePath()
            }
        }
    }

    private func drawCloud(_ ctx: CGContext, face: FaceState, time: Double) {
        let pop = 1 - pow(1 - min(1, visibleFor / 0.45), 3)
        let h = cloudHeight(face) * pop
        let centre = cloudCenter(face, time: time)
        let s = storm.value
        // A cloud shakes when it is angry.
        let shake = s > 0.5 ? sin(time * 38) * face.interocular * 0.012 * s : 0
        let at = CGPoint(x: centre.x + shake, y: centre.y)
        let tilt = face.roll * 0.25

        ctx.exprStamp(ExprSprites.cloud(stormy: false), at: at, height: h, rotation: tilt, alpha: 1)
        if s > 0.01 { ctx.exprStamp(ExprSprites.cloud(stormy: true), at: at, height: h, rotation: tilt, alpha: s) }

        // A small face on the cloud: content at rest, scowling in a storm.
        ctx.saveGState()
        ctx.translateBy(x: at.x, y: at.y)
        ctx.rotate(by: tilt)
        ctx.scaleBy(x: h / 2, y: h / 2)
        let ink = exprColor(exprMix((0.3, 0.34, 0.45), (0.95, 0.95, 1), s), 1)
        ctx.setFillColor(ink)
        let blink = 1 - 0.9 * max(0, pow(sin(time * 0.8), 40))
        for x in [-0.26, 0.26] {
            ctx.fillEllipse(in: CGRect(x: x - 0.055, y: 0.0 - 0.07 * blink, width: 0.11, height: 0.14 * blink))
        }
        ctx.setStrokeColor(ink)
        ctx.setLineCap(.round)
        ctx.setLineWidth(0.04)
        ctx.move(to: CGPoint(x: -0.12, y: -0.17 - 0.05 * (1 - s)))
        ctx.addQuadCurve(to: CGPoint(x: 0.12, y: -0.17 - 0.05 * (1 - s)), control: CGPoint(x: 0, y: -0.17 - 0.1 * (1 - s) + 0.1 * s))
        ctx.strokePath()
        if s > 0.05 {
            ctx.setStrokeColor(exprColor((0.95, 0.95, 1), s))
            for side in [-1.0, 1.0] {
                ctx.move(to: CGPoint(x: side * 0.4, y: 0.17)); ctx.addLine(to: CGPoint(x: side * 0.14, y: 0.1)); ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }

    private func drawBolt(_ ctx: CGContext, face: FaceState, points: [CGPoint]) {
        let strength = Self.envelope(boltAge)
        guard strength > 0.01, points.count > 1 else { return }
        let io = face.interocular
        let path = CGMutablePath()
        for (i, p) in points.enumerated() {
            let pt = face.exprPoint(p.x, p.y)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.setBlendMode(.plusLighter)
        ctx.setLineJoin(.miter)
        ctx.setLineCap(.round)
        for (width, colour, alpha) in [(0.3, (0.35, 0.5, 1.0), 0.3), (0.12, (0.7, 0.82, 1.0), 0.7), (0.045, (1.0, 1.0, 1.0), 1.0)] as [(Double, ExprRGB, Double)] {
            ctx.setStrokeColor(exprColor(colour, alpha * strength))
            ctx.setLineWidth(io * width)
            ctx.addPath(path); ctx.strokePath()
        }
        if let last = points.last {
            ctx.glow(center: face.exprPoint(last.x, last.y), radius: io * 0.8, red: 0.8, green: 0.88, blue: 1, alpha: 0.8 * strength)
        }
        ctx.setBlendMode(.normal)
    }
}
