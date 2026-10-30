import AppKit
import CoreGraphics
import CoreImage
import simd

extension CGPoint {
    var simd: SIMD2<Double> { SIMD2(Double(x), Double(y)) }
}

extension FaceState {
    /// Down the face, toward the chin, as a vector for physics.
    var downVector: SIMD2<Double> { SIMD2(Double(-up.dx), Double(-up.dy)) }
    /// Across the face to the right of the picture.
    var acrossVector: SIMD2<Double> { SIMD2(Double(across.dx), Double(across.dy)) }
}

extension CGContext {
    /// Draws in face units: the origin is between the eyes, x runs along the eyes, y up the face, and 1 is the eye spacing.
    /// A hat drawn at y = 1.5 sits on top of the head however far away the face is and however it is tilted.
    func inFaceSpace(_ face: FaceState, _ draw: () -> Void) {
        saveGState()
        translateBy(x: face.eyeCenter.x, y: face.eyeCenter.y)
        rotate(by: face.roll)
        scaleBy(x: face.interocular, y: face.interocular)
        draw()
        restoreGState()
    }
}

/// What a face lens tells the interface: how to use it, or that it can't find you.
struct FaceHint {
    var latest: FaceState?

    func status(_ hint: String) -> LensStatus {
        guard let f = latest else { return LensStatus("Looking for your face…", detail: "Face the camera in good light") }
        return LensStatus(hint, detail: "Mouth \(Int((f.mouthOpen * 100).rounded()))% · Brows \(Int((f.browRaise * 100).rounded()))%")
    }
}

/// Eases from 0 toward 1 (or back) at a steady rate; for things that charge up and fade.
struct Ramp {
    private(set) var value = 0.0
    mutating func move(toward target: Double, dt: Double, rate: Double) {
        let step = rate * dt
        value = target > value ? min(target, value + step) : max(target, value - step)
    }
}

// MARK: - Dress-up

/// Props that sit on your head and face and follow every tilt.
final class PropsLens: Lens {
    enum Kind: String, CaseIterable { case cat, shades, crown, party }

    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    private let kind: Kind
    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var visibleFor = 0.0

    init(kind: Kind) { self.kind = kind }

    func restart() { visibleFor = 0 }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status(kind == .shades ? "Deal with it" : "Strike a pose")
        guard let face = input.face else { visibleFor = 0; return input.composed }
        visibleFor += input.dt

        guard let layer = input.services.overlay({ ctx in
            ctx.inFaceSpace(face) {
                switch kind {
                case .cat: Self.drawCat(ctx)
                case .shades: Self.drawShades(ctx, drop: Self.drop(visibleFor))
                case .crown: Self.drawCrown(ctx, bounce: Self.drop(visibleFor))
                case .party: Self.drawPartyHat(ctx, bounce: Self.drop(visibleFor))
                }
            }
        }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    /// How far above its resting place a prop starts, in eye-spacings, falling into place over half a second.
    static func drop(_ seconds: Double) -> Double {
        let t = min(1, seconds / 0.55)
        return pow(1 - t, 3) * 2.6
    }

    private static func polygon(_ ctx: CGContext, _ points: [(Double, Double)]) {
        ctx.move(to: CGPoint(x: points[0].0, y: points[0].1))
        for p in points.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
        ctx.closePath()
    }

    private static func gradient(_ top: (Double, Double, Double), _ bottom: (Double, Double, Double)) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                   colors: [CGColor(red: top.0, green: top.1, blue: top.2, alpha: 1), CGColor(red: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1)] as CFArray,
                   locations: [0, 1])!
    }

    // MARK: Cat

    static func drawCat(_ ctx: CGContext) {
        let fur = CGColor(red: 0.96, green: 0.62, blue: 0.24, alpha: 1)
        let ink = CGColor(red: 0.30, green: 0.14, blue: 0.06, alpha: 1)
        let pink = CGColor(red: 1.0, green: 0.62, blue: 0.7, alpha: 1)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(0.05)
        for side in [-1.0, 1.0] {
            polygon(ctx, [(side * 1.05, 1.0), (side * 0.28, 1.5), (side * 0.98, 2.15)])
            ctx.setFillColor(fur); ctx.setStrokeColor(ink)
            ctx.drawPath(using: .fillStroke)
            polygon(ctx, [(side * 0.92, 1.22), (side * 0.5, 1.5), (side * 0.93, 1.88)])
            ctx.setFillColor(pink); ctx.fillPath()
        }
        // Nose and whiskers.
        polygon(ctx, [(-0.1, -0.36), (0.1, -0.36), (0, -0.46)])
        ctx.setFillColor(pink); ctx.fillPath()
        ctx.setLineCap(.round)
        for side in [-1.0, 1.0] {
            for (i, dy) in [0.12, 0.0, -0.12].enumerated() {
                let from = CGPoint(x: side * 0.34, y: -0.52 - Double(i) * 0.05)
                let to = CGPoint(x: side * 1.3, y: -0.52 + dy * 1.4 - Double(i) * 0.1)
                for (width, colour) in [(0.055, ink), (0.03, CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))] as [(Double, CGColor)] {
                    ctx.setLineWidth(width); ctx.setStrokeColor(colour)
                    ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
                }
            }
        }
    }

    // MARK: Shades

    static func drawShades(_ ctx: CGContext, drop: Double) {
        ctx.translateBy(x: 0, y: drop)
        let black = CGColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(black); ctx.setLineWidth(0.06)
        for side in [-1.0, 1.0] {            // arms
            ctx.move(to: CGPoint(x: side * 0.9, y: 0.07)); ctx.addLine(to: CGPoint(x: side * 1.2, y: 0.1)); ctx.strokePath()
        }
        ctx.move(to: CGPoint(x: -0.12, y: 0.1)); ctx.addQuadCurve(to: CGPoint(x: 0.12, y: 0.1), control: CGPoint(x: 0, y: 0.2)); ctx.strokePath()
        for side in [-1.0, 1.0] {
            let rect = CGRect(x: side * 0.5 - 0.42, y: -0.27, width: 0.84, height: 0.56)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 0.2, cornerHeight: 0.2, transform: nil))
            ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 0.94)); ctx.setStrokeColor(black); ctx.setLineWidth(0.05)
            ctx.drawPath(using: .fillStroke)
            // A glint across the glass.
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 0.2, cornerHeight: 0.2, transform: nil)); ctx.clip()
            polygon(ctx, [(rect.minX + 0.12, rect.maxY), (rect.minX + 0.3, rect.maxY), (rect.minX + 0.08, rect.minY), (rect.minX - 0.1, rect.minY)])
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22)); ctx.fillPath()
            ctx.restoreGState()
        }
    }

    // MARK: Crown

    static func drawCrown(_ ctx: CGContext, bounce: Double) {
        ctx.translateBy(x: 0, y: bounce)
        let points: [(Double, Double)] = [(-0.72, 1.12), (-0.78, 1.9), (-0.36, 1.55), (0, 2.08), (0.36, 1.55), (0.78, 1.9), (0.72, 1.12)]
        ctx.saveGState()
        polygon(ctx, points); ctx.clip()
        ctx.drawLinearGradient(gradient((1.0, 0.92, 0.35), (0.85, 0.58, 0.08)), start: CGPoint(x: 0, y: 2.1), end: CGPoint(x: 0, y: 1.1), options: [])
        ctx.restoreGState()
        ctx.setLineJoin(.round); ctx.setLineWidth(0.05); ctx.setStrokeColor(CGColor(red: 0.55, green: 0.36, blue: 0.04, alpha: 1))
        polygon(ctx, points); ctx.strokePath()
        for (x, y, r, c) in [(0.0, 1.3, 0.075, CGColor(red: 0.9, green: 0.1, blue: 0.2, alpha: 1)),
                             (-0.4, 1.28, 0.06, CGColor(red: 0.2, green: 0.5, blue: 1, alpha: 1)),
                             (0.4, 1.28, 0.06, CGColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)),
                             (-0.78, 1.95, 0.065, CGColor(red: 1, green: 0.98, blue: 0.85, alpha: 1)),
                             (0.0, 2.13, 0.07, CGColor(red: 1, green: 0.98, blue: 0.85, alpha: 1)),
                             (0.78, 1.95, 0.065, CGColor(red: 1, green: 0.98, blue: 0.85, alpha: 1))] {
            ctx.fillCircle(center: CGPoint(x: x, y: y), radius: r, color: c)
        }
    }

    // MARK: Party hat

    static func drawPartyHat(_ ctx: CGContext, bounce: Double) {
        ctx.translateBy(x: 0, y: bounce)
        let cone: [(Double, Double)] = [(-0.62, 1.2), (0.62, 1.2), (0.12, 3.0)]
        ctx.saveGState()
        polygon(ctx, cone); ctx.clip()
        ctx.setFillColor(CGColor(red: 0.95, green: 0.3, blue: 0.62, alpha: 1)); ctx.fill(CGRect(x: -1, y: 1, width: 2, height: 2.2))
        ctx.setFillColor(CGColor(red: 0.3, green: 0.8, blue: 1, alpha: 1))
        for i in 0..<4 {                       // diagonal stripes
            let y = 1.15 + Double(i) * 0.5
            polygon(ctx, [(-1, y), (1, y + 0.5), (1, y + 0.72), (-1, y + 0.22)]); ctx.fillPath()
        }
        ctx.restoreGState()
        ctx.setLineJoin(.round); ctx.setLineWidth(0.04); ctx.setStrokeColor(CGColor(red: 0.45, green: 0.1, blue: 0.3, alpha: 1))
        polygon(ctx, cone); ctx.strokePath()
        ctx.fillCircle(center: CGPoint(x: 0.12, y: 3.02), radius: 0.15, color: CGColor(red: 1, green: 0.9, blue: 0.3, alpha: 1))
        ctx.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: -0.66, y: 1.14, width: 1.32, height: 0.1))
    }
}

// MARK: - Funhouse

/// Bulges part of the face, like a funhouse mirror.
final class FunhouseLens: Lens {
    enum Kind: String, CaseIterable { case bigEyes, chipmunk, bigMouth }

    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    private let kind: Kind
    private let statusBox = StatusBox()
    private var hint = FaceHint()

    init(kind: Kind) { self.kind = kind }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Look at the camera")
        guard let face = input.face else { return input.composed }

        let io = face.interocular
        var out = input.composed
        for bump in Self.bumps(kind, face: face, io: io) {
            let filter = CIFilter(name: "CIBumpDistortion")!
            filter.setValue(out, forKey: kCIInputImageKey)
            filter.setValue(CIVector(cgPoint: bump.center), forKey: kCIInputCenterKey)
            filter.setValue(bump.radius, forKey: kCIInputRadiusKey)
            filter.setValue(bump.scale, forKey: kCIInputScaleKey)
            out = (filter.outputImage ?? out).cropped(to: input.rect)
        }
        return out
    }

    struct Bump { var center: CGPoint; var radius: Double; var scale: Double }

    static func bumps(_ kind: Kind, face: FaceState, io: Double) -> [Bump] {
        func point(_ x: Double, _ y: Double) -> CGPoint {       // face units to output pixels
            let c = cos(face.roll), s = sin(face.roll)
            return CGPoint(x: face.eyeCenter.x + (x * c - y * s) * io, y: face.eyeCenter.y + (x * s + y * c) * io)
        }
        switch kind {
        case .bigEyes: return [Bump(center: face.leftEye, radius: io * 0.62, scale: 0.7), Bump(center: face.rightEye, radius: io * 0.62, scale: 0.7)]
        case .chipmunk: return [Bump(center: point(-0.62, -0.62), radius: io * 0.62, scale: 0.65), Bump(center: point(0.62, -0.62), radius: io * 0.62, scale: 0.65)]
        case .bigMouth: return [Bump(center: face.mouth, radius: io * (0.75 + face.mouthOpen * 0.25), scale: 0.75)]
        }
    }
}

// MARK: - Breath

/// Open wide and something comes out: rainbows or flames.
final class BreathLens: Lens {
    enum Kind: String, CaseIterable { case rainbow, fire }

    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    private let kind: Kind
    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var particles = ParticleSystem(capacity: 700)
    private var rng = SplitMix64(seed: 0xB0F)
    private var owed = 0.0

    /// Mouth opening needed to start, and (lower) to keep going, so a wobbling jaw doesn't flicker it.
    static let startAt = 0.45, stopAt = 0.3
    private var spewing = false

    var particleCount: Int { particles.particles.count }

    init(kind: Kind) {
        self.kind = kind
        particles.gravity = SIMD2(0, kind == .rainbow ? -1500 : 240)
        particles.drag = kind == .fire ? 1.1 : 0.15
    }

    func restart() { particles.removeAll() }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status(kind == .rainbow ? "Open wide" : "Open wide and breathe out")
        let dt = input.dt

        if let face = input.face {
            spewing = face.mouthOpen > (spewing ? Self.stopAt : Self.startAt)
            if spewing { emit(from: face, dt: dt, time: input.time) }
        } else {
            spewing = false
        }
        particles.step(dt)
        particles.particles.removeAll { $0.position.y < -60 }

        guard let layer = input.services.overlay({ ctx in draw(ctx) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    private func emit(from face: FaceState, dt: Double, time: Double) {
        owed += dt * (kind == .rainbow ? 170 : 150) * (0.5 + face.mouthOpen)
        let scale = max(0.6, face.interocular / 90)
        let down = face.downVector, across = face.acrossVector
        let origin = face.mouth.simd + down * face.interocular * 0.12
        while owed >= 1 {
            owed -= 1
            let speed = Double.random(in: kind == .rainbow ? 330...560 : 520...880, using: &rng) * scale
            let sideways = Double.random(in: -1...1, using: &rng) * (kind == .rainbow ? 140 : 160) * scale
            particles.emit(Particle(position: origin, velocity: down * speed + across * sideways,
                                    life: kind == .rainbow ? Double.random(in: 1.0...1.6, using: &rng) : Double.random(in: 0.45...0.8, using: &rng),
                                    size: (kind == .rainbow ? Double.random(in: 15...30, using: &rng) : Double.random(in: 14...26, using: &rng)) * scale,
                                    hue: time * 0.55 + Double.random(in: -0.04...0.04, using: &rng), kind: 0))
        }
    }

    private func draw(_ ctx: CGContext) {
        if kind == .fire { ctx.setBlendMode(.plusLighter) }
        for p in particles.particles {
            let t = p.progress
            switch kind {
            case .rainbow:
                let (r, g, b) = Palette.rgb(hue: (p.hue * 24).rounded() / 24, saturation: 0.85, brightness: 1)
                guard let dot = Sprites.dot(red: r, green: g, blue: b) else { continue }
                ctx.stampDot(dot, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 + t * 0.6), alpha: 1 - t * t)
            case .fire:
                // White-hot at the mouth, orange in the middle, dark red at the tips, swelling as it goes.
                let (r, g, b) = t < 0.3 ? (1.0, 0.95, 0.6) : t < 0.65 ? (1.0, 0.5, 0.1) : (0.8, 0.15, 0.05)
                guard let dot = Sprites.dot(red: r, green: g, blue: b) else { continue }
                ctx.stampDot(dot, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 + t * 2.2), alpha: (1 - t) * 0.85)
            }
        }
        ctx.setBlendMode(.normal)
    }
}

// MARK: - Laser eyes

/// Raise your eyebrows and beams shoot out of your eyes.
final class LaserEyesLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var power = Ramp()
    private var firing = false
    private var sparks = ParticleSystem(capacity: 200)
    private var rng = SplitMix64(seed: 0x1A5E2)

    static let startAt = 0.55, stopAt = 0.35

    /// How strongly the beams are drawn right now, 0...1.
    var beamPower: Double { power.value }

    init() { sparks.gravity = SIMD2(0, -500) }

    func restart() { sparks.removeAll(); power = Ramp() }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Raise your eyebrows")
        let dt = input.dt
        if let face = input.face { firing = face.browRaise > (firing ? Self.stopAt : Self.startAt) } else { firing = false }
        power.move(toward: firing ? 1 : 0, dt: dt, rate: firing ? 9 : 5)
        sparks.step(dt)

        guard let face = input.face, power.value > 0.01 else { return input.composed }
        let beams = Self.beams(from: face, in: input.rect)
        if firing {
            for beam in beams where Double.random(in: 0..<1, using: &rng) < 0.7 {
                let angle = Double.random(in: 0..<(2 * .pi), using: &rng), speed = Double.random(in: 80...380, using: &rng)
                sparks.emit(Particle(position: beam.end.simd, velocity: SIMD2(cos(angle), sin(angle)) * speed,
                                     life: Double.random(in: 0.25...0.6, using: &rng), size: Double.random(in: 4...10, using: &rng)))
            }
        }

        guard let layer = input.services.overlay({ ctx in draw(ctx, beams: beams, face: face, time: input.time) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    struct Beam { var start: CGPoint; var end: CGPoint }

    /// One beam from each eye, heading outward and a little downward until it leaves the picture.
    static func beams(from face: FaceState, in rect: CGRect) -> [Beam] {
        let down = face.downVector, across = face.acrossVector
        return [(-1.0, face.leftEye), (1.0, face.rightEye)].map { side, eye in
            let heading = simd_normalize(across * side * cos(0.22) + down * sin(0.22))
            let start = eye.simd
            return Beam(start: eye, end: exit(from: start, heading: heading, rect: rect))
        }
    }

    /// Where a ray from inside `rect` leaves it.
    static func exit(from start: SIMD2<Double>, heading: SIMD2<Double>, rect: CGRect) -> CGPoint {
        var t = Double.infinity
        if heading.x > 1e-9 { t = min(t, (rect.maxX - start.x) / heading.x) } else if heading.x < -1e-9 { t = min(t, (rect.minX - start.x) / heading.x) }
        if heading.y > 1e-9 { t = min(t, (rect.maxY - start.y) / heading.y) } else if heading.y < -1e-9 { t = min(t, (rect.minY - start.y) / heading.y) }
        t = max(0, t.isFinite ? t : 0)
        return CGPoint(x: start.x + heading.x * t, y: start.y + heading.y * t)
    }

    private func draw(_ ctx: CGContext, beams: [Beam], face: FaceState, time: Double) {
        let p = power.value
        let flicker = 1 + 0.18 * sin(time * 70)
        let scale = max(0.6, face.interocular / 90)
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        for beam in beams {
            for (width, colour, alpha) in [(46.0, (1.0, 0.1, 0.1), 0.3), (22.0, (1.0, 0.2, 0.15), 0.6), (9.0, (1.0, 0.65, 0.55), 0.95), (3.5, (1.0, 1.0, 1.0), 1.0)] {
                ctx.setStrokeColor(CGColor(red: colour.0, green: colour.1, blue: colour.2, alpha: alpha * p))
                ctx.setLineWidth(width * scale * p * flicker)
                ctx.move(to: beam.start); ctx.addLine(to: beam.end); ctx.strokePath()
            }
            ctx.glow(center: beam.start, radius: 70 * scale * p, red: 1, green: 0.3, blue: 0.2, alpha: 0.9)
            ctx.glow(center: beam.end, radius: 90 * p, red: 1, green: 0.45, blue: 0.25, alpha: 0.8)
        }
        if let dot = Sprites.dot(red: 1, green: 0.8, blue: 0.4) {
            for s in sparks.particles {
                ctx.stampDot(dot, at: CGPoint(x: s.position.x, y: s.position.y), radius: s.size * 2.2, alpha: 1 - s.progress)
            }
        }
        ctx.setBlendMode(.normal)
    }
}
