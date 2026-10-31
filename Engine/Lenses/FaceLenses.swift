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
        func pct(_ v: Double) -> Int { Int((v * 100).rounded()) }
        return LensStatus(hint, detail: "Mouth \(pct(f.mouthOpen))% · Brows \(pct(f.browRaise))% · Blink \(pct(f.blink))% · Smile \(pct(f.smile))%")
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

/// Funhouse-mirror warps that stay flattering: smooth swells with feathered edges, springing with your expression.
/// Big Eyes swell further when you raise your brows, Chipmunk puffs up when you smile, Big Mouth grows as you open wide.
final class FunhouseLens: Lens {
    enum Kind: String, CaseIterable { case bigEyes, chipmunk, bigMouth }

    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    private let kind: Kind
    private let statusBox = StatusBox()
    private var hint = FaceHint()
    /// The last face seen, kept until the warp has eased out after the face is lost.
    private var lastFace: FaceState?
    private var latch = ExprLatch()
    /// How far the warp is in, 0 (none) to 1 (at rest) and a little more when you react; on a spring, so it overshoots.
    private var amount = ExprSpring()
    private var reaction = ExprSpring()

    /// How strongly the warp is applied right now (about 1 at rest, more while reacting).
    var strength: Double { amount.value * (1 + 0.45 * reaction.value) }
    var isReacting: Bool { latch.isOn }

    init(kind: Kind) {
        self.kind = kind
        ExprWarpKernel.warmUp()
    }

    func restart() { lastFace = nil; latch.reset(); amount.reset(); reaction.reset() }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status(kind == .bigEyes ? "Raise your eyebrows" : kind == .chipmunk ? "Smile to stuff your cheeks" : "Open wide")
        let dt = min(input.dt, 0.25)
        if let f = input.face { lastFace = f }
        if let f = input.face {
            switch kind {
            case .bigEyes: latch.update(f.browRaise, on: 0.5, off: 0.3)
            case .chipmunk: latch.update(f.smile, on: 0.5, off: 0.3)
            case .bigMouth: latch.update(f.mouthOpen, on: 0.35, off: 0.2)
            }
        } else {
            latch.reset()
        }
        amount.step(toward: input.face == nil ? 0 : 1, dt: dt, frequency: 3, damping: input.face == nil ? 1 : 0.55)
        let open = input.face.map { exprSmoothstep(0.1, 0.9, $0.mouthOpen) } ?? 0
        reaction.step(toward: kind == .bigMouth ? (latch.isOn ? 0.4 + 0.6 * open : 0) : (latch.isOn ? 1 : 0), dt: dt, frequency: 2.6, damping: 0.4)
        if input.face == nil && amount.value < 0.004 { lastFace = nil }
        guard let face = lastFace else { return input.composed }
        return ExprWarp.warp(input.composed, terms: Self.terms(kind, face: face, strength: strength, time: input.time), bounds: input.rect, wholeFrame: true)
    }

    /// The warps for one face. `strength` is 1 at rest.
    static func terms(_ kind: Kind, face f: FaceState, strength s: Double, time: Double) -> [ExprWarpTerm] {
        let io = f.interocular
        switch kind {
        case .bigEyes:
            return [f.leftEye, f.rightEye].map { eye in
                var t = ExprWarpTerm(center: eye, across: io * 0.82, along: io * 0.7, angle: f.roll)
                t.magnify = min(0.62, 0.42 * s)
                return t
            }
        case .chipmunk:
            // Cheeks swell and bulge outward past the jaw; a gentle chew keeps them alive.
            let chew = 1 + 0.06 * sin(time * 2 * .pi * 1.6)
            return [-1.0, 1.0].map { side in
                var t = ExprWarpTerm.face(f, side * 0.9, -0.86, across: 0.64, along: 0.7)
                t.magnify = min(0.6, 0.34 * s * chew)
                let out = f.acrossVector * side * io * 0.22 * s + f.downVector * io * 0.04 * s
                t.push = CGVector(dx: out.x, dy: out.y)
                return t
            }
        case .bigMouth:
            let mouth = f.mouth
            var t = ExprWarpTerm(center: mouth, across: io * 1.15, along: io * 0.86, angle: f.roll)
            t.magnify = min(0.62, 0.32 * s)
            return [t]
        }
    }
}

// MARK: - Breath

/// Open wide and something pours out: a glossy banded rainbow, or a roaring flame with embers and smoke.
final class BreathLens: Lens {
    enum Kind: String, CaseIterable { case rainbow, fire }

    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    private let kind: Kind
    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var particles = ParticleSystem(capacity: 700)
    private var rng = SplitMix64(seed: 0xB0F)
    private var owed = [0.0, 0.0, 0.0]
    private var heat = Ramp()
    private var mouth = CGPoint.zero
    private var scale = 1.0

    /// Mouth opening needed to start, and (lower) to keep going, so a wobbling jaw doesn't flicker it.
    static let startAt = 0.45, stopAt = 0.3
    private var spewing = false

    /// What each particle is.
    private enum Bit { static let body = 0, sparkle = 1, drop = 2, ember = 3, smoke = 4 }

    /// The rainbow's seven bands, top of the arc first: soft, sunny and never neon.
    static let rainbowBands: [ExprRGB] = [(0.98, 0.32, 0.38), (1.0, 0.58, 0.24), (1.0, 0.86, 0.32), (0.42, 0.84, 0.46),
                                          (0.28, 0.66, 1.0), (0.42, 0.44, 0.96), (0.72, 0.44, 0.96)]
    /// Fire from white-hot at the mouth to deep red at the tips.
    static let flameRamp: [(Double, ExprRGB)] = [(0, (1.0, 0.98, 0.88)), (0.14, (1.0, 0.88, 0.42)), (0.36, (1.0, 0.56, 0.14)),
                                                 (0.66, (0.92, 0.26, 0.06)), (1, (0.55, 0.08, 0.04))]

    var particleCount: Int { particles.particles.count }

    init(kind: Kind) {
        self.kind = kind
        particles.gravity = SIMD2(0, kind == .rainbow ? -1100 : 240)
        particles.drag = kind == .fire ? 1.1 : 0.1
    }

    func restart() { particles.removeAll(); spewing = false; heat = Ramp(); owed = [0, 0, 0] }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status(kind == .rainbow ? "Open wide" : "Open wide and breathe out")
        let dt = min(input.dt, 0.1)

        if let face = input.face {
            spewing = face.mouthOpen > (spewing ? Self.stopAt : Self.startAt)
            scale = max(0.35, face.interocular / 84)
            mouth = CGPoint(x: face.mouth.x + face.downVector.x * face.interocular * 0.1, y: face.mouth.y + face.downVector.y * face.interocular * 0.1)
            if spewing { emit(from: face, dt: dt, time: input.time) }
        } else {
            spewing = false
        }
        heat.move(toward: spewing ? 1 : 0, dt: dt, rate: spewing ? 6 : 3)
        let time = input.time
        if kind == .fire {
            particles.step(dt) { p in
                // Flames lick sideways as they go, more the older they are.
                guard p.kind != Bit.smoke else { return }
                let swirl = sin(p.position.y * 0.021 + time * 9 + p.hue * 6) * 900 * p.progress
                p.velocity.x += swirl * dt
            }
        } else {
            particles.step(dt)
        }
        particles.particles.removeAll { $0.position.y < -80 || $0.position.y > 820 }
        guard !particles.particles.isEmpty || heat.value > 0.01 else { return input.composed }

        if kind == .fire {
            // Flames and smoke are soft, so they are drawn at half size (a quarter of the pixels) and scaled up; the embers,
            // small and sharp, go on at full size.
            var picture = input.composed
            if let soft = halfSize(input.rect, { ctx in drawFlames(ctx) }) { picture = soft.composited(over: picture) }
            guard let sparks = input.services.exprOverlay({ ctx in drawEmbers(ctx) }) else { return picture.cropped(to: input.rect) }
            return sparks.composited(over: picture).cropped(to: input.rect)
        }
        guard let layer = input.services.exprOverlay({ ctx in drawRainbow(ctx, time: time) }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    private var softCanvas: CGContext?

    /// Draws into a private half-size canvas (in full-size coordinates) and hands it back scaled up to cover `rect`.
    private func halfSize(_ rect: CGRect, _ draw: (CGContext) -> Void) -> CIImage? {
        let w = max(1, Int(rect.width / 2)), h = max(1, Int(rect.height / 2))
        if softCanvas?.width != w || softCanvas?.height != h {
            softCanvas = CGColorSpace(name: CGColorSpace.sRGB).flatMap {
                CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: $0, bitmapInfo: Sprites.bitmapInfo)
            }
        }
        guard let ctx = softCanvas else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.saveGState()
        ctx.interpolationQuality = .medium
        ctx.scaleBy(x: 0.5, y: 0.5)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        draw(ctx)
        ctx.restoreGState()
        guard let image = ctx.makeImage() else { return nil }
        return CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: 2, y: 2).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }

    private func emit(from face: FaceState, dt: Double, time: Double) {
        let down = face.downVector, across = face.acrossVector
        let origin = mouth.simd
        let open = 0.5 + face.mouthOpen
        switch kind {
        case .rainbow:
            // The body of the stream: a steady chain whose sideways sway comes from time, not dice, so it reads as one ribbon.
            let rate = 70.0
            owed[0] += dt * rate
            while owed[0] >= 1 {
                owed[0] -= 1
                // Each link starts where it would be had it left the mouth at its own moment within the frame, so the
                // links of one frame don't pile up on one spot and pinch the ribbon.
                let lead = owed[0] / rate
                let moment = time - lead
                let sway = sin(moment * 2.7) * 0.22 + sin(moment * 5.3) * 0.08
                let speed = 360 * scale * (0.85 + 0.25 * face.mouthOpen)
                let velocity = down * speed + across * (sway * speed)
                particles.emit(Particle(position: origin + velocity * lead, velocity: velocity, age: lead, life: 1.6,
                                        size: face.interocular * 0.8 * (0.8 + 0.3 * face.mouthOpen), hue: moment, kind: Bit.body))
            }
            owed[1] += dt * 34 * open
            while owed[1] >= 1 {
                owed[1] -= 1
                let speed = Double.random(in: 200...420, using: &rng) * scale
                let side = Double.random(in: -1...1, using: &rng)
                particles.emit(Particle(position: origin + across * side * face.interocular * 0.3,
                                        velocity: down * speed + across * side * 260 * scale,
                                        life: Double.random(in: 0.55...0.95, using: &rng), size: Double.random(in: 9...20, using: &rng) * scale,
                                        hue: Double.random(in: 0..<7, using: &rng), kind: Bool.random(using: &rng) ? Bit.sparkle : Bit.drop))
            }
        case .fire:
            owed[0] += dt * 105 * open
            while owed[0] >= 1 {
                owed[0] -= 1
                let speed = Double.random(in: 520...860, using: &rng) * scale
                let sideways = Double.random(in: -1...1, using: &rng) * 170 * scale
                particles.emit(Particle(position: origin + across * Double.random(in: -0.12...0.12, using: &rng) * face.interocular,
                                        velocity: down * speed + across * sideways,
                                        life: Double.random(in: 0.42...0.78, using: &rng), size: Double.random(in: 17...29, using: &rng) * scale,
                                        hue: Double.random(in: 0..<1, using: &rng), kind: Bit.body))
            }
            owed[1] += dt * 26 * open
            while owed[1] >= 1 {
                owed[1] -= 1
                let speed = Double.random(in: 300...700, using: &rng) * scale
                let angle = Double.random(in: -0.6...0.6, using: &rng)
                let dir = down * cos(angle) + across * sin(angle)
                particles.emit(Particle(position: origin, velocity: dir * speed, life: Double.random(in: 0.7...1.3, using: &rng),
                                        size: Double.random(in: 2.5...5, using: &rng) * scale, hue: Double.random(in: 0..<1, using: &rng), kind: Bit.ember))
            }
            owed[2] += dt * 18 * open
            while owed[2] >= 1 {
                owed[2] -= 1
                let speed = Double.random(in: 360...560, using: &rng) * scale
                particles.emit(Particle(position: origin, velocity: down * speed + across * Double.random(in: -90...90, using: &rng) * scale,
                                        life: Double.random(in: 1.1...1.6, using: &rng), size: Double.random(in: 26...40, using: &rng) * scale,
                                        hue: Double.random(in: 0..<1, using: &rng), kind: Bit.smoke))
            }
        }
    }

    // MARK: Rainbow

    private func drawRainbow(_ ctx: CGContext, time: Double) {
        let body = particles.particles.filter { $0.kind == Bit.body }.sorted { $0.age < $1.age }
        if body.count >= 2 {
            // Where the ribbon runs and how wide it is at each point: it spreads as it falls and tapers away at the tail.
            let points = body.map { CGPoint(x: $0.position.x, y: $0.position.y) }
            let widths = body.map { p -> Double in
                let spread = 1 + 1.5 * exprSmoothstep(0, 1, p.progress)
                let grow = exprOutCubic(min(1, p.age / 0.14))
                let taper = 1 - exprSmoothstep(0.6, 1, p.progress)
                return p.size * spread * (0.35 + 0.65 * grow) * taper
            }
            var normals: [CGVector] = []
            for i in points.indices {
                let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
                let dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy)
                normals.append(len > 0.5 ? CGVector(dx: -dy / len, dy: dx / len) : (normals.last ?? CGVector(dx: 1, dy: 0)))
            }
            func edge(_ i: Int, _ f: Double, dx: Double = 0, dy: Double = 0) -> CGPoint {   // f from -0.5 (one side) to 0.5 (the other)
                CGPoint(x: points[i].x + normals[i].dx * widths[i] * f + dx, y: points[i].y + normals[i].dy * widths[i] * f + dy)
            }
            /// The strip between two offsets across the ribbon, as one closed outline, so no seams show along it.
            func strip(_ a: Double, _ b: Double, dx: Double = 0, dy: Double = 0) -> CGPath {
                let path = CGMutablePath()
                path.move(to: edge(0, a, dx: dx, dy: dy))
                for i in 1..<points.count { path.addLine(to: edge(i, a, dx: dx, dy: dy)) }
                for i in stride(from: points.count - 1, through: 0, by: -1) { path.addLine(to: edge(i, b, dx: dx, dy: dy)) }
                path.closeSubpath()
                return path
            }
            // A soft shadow down and to the right, so it sits on the picture rather than being pasted on.
            ctx.addPath(strip(-0.5, 0.5, dx: 5 * scale, dy: -8 * scale))
            ctx.setFillColor(exprColor((0.12, 0.04, 0.2), 0.16)); ctx.fillPath()
            let n = Self.rainbowBands.count
            for (j, colour) in Self.rainbowBands.enumerated() {
                let a = -0.5 + Double(j) / Double(n), b = -0.5 + Double(j + 1) / Double(n) + (j < n - 1 ? 0.01 : 0)
                ctx.addPath(strip(a, b))
                ctx.setFillColor(exprColor(colour)); ctx.fillPath()
            }
            // Gloss: a bright streak near the lit edge and a soft shade along the far one.
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            for (f, colour, alpha, width) in [(-0.33, (1.0, 1.0, 1.0), 0.5, 0.06), (0.42, (0.22, 0.08, 0.38), 0.2, 0.12)] as [(Double, ExprRGB, Double, Double)] {
                ctx.setStrokeColor(exprColor(colour, alpha))
                ctx.setLineWidth(max(1, (widths.max() ?? 10) * width * 0.7))
                ctx.move(to: edge(0, f))
                for i in 1..<points.count { ctx.addLine(to: edge(i, f)) }
                ctx.strokePath()
            }
        }
        // Sparkles and drops thrown off the stream.
        for p in particles.particles where p.kind != Bit.body {
            let t = p.progress
            let fade = min(1, p.age / 0.06) * (1 - exprSmoothstep(0.6, 1, t))
            let at = CGPoint(x: p.position.x, y: p.position.y)
            if p.kind == Bit.sparkle {
                let twinkle = 0.65 + 0.35 * sin(p.age * 24 + p.hue)
                ctx.exprStamp(ExprSprites.twinkle(variant: Int(p.hue) % 4), at: at, height: p.size * 2.2 * twinkle, rotation: p.age * 2 + p.hue, alpha: fade)
            } else {
                let colour = Self.rainbowBands[Int(p.hue) % Self.rainbowBands.count]
                ctx.fillCircle(center: at, radius: p.size * 0.42, color: exprColor(colour, fade))
                ctx.fillCircle(center: CGPoint(x: at.x - p.size * 0.13, y: at.y + p.size * 0.13), radius: p.size * 0.13, color: exprColor((1, 1, 1), 0.85 * fade))
            }
        }
    }

    // MARK: Fire

    static func flameColour(_ t: Double) -> ExprRGB {
        let ramp = flameRamp
        for i in 1..<ramp.count where t <= ramp[i].0 {
            let k = (t - ramp[i - 1].0) / (ramp[i].0 - ramp[i - 1].0)
            return exprMix(ramp[i - 1].1, ramp[i].1, k)
        }
        return ramp[ramp.count - 1].1
    }

    private func drawFlames(_ ctx: CGContext) {
        // Smoke first, under the flames, in ordinary blending so it darkens what is behind it.
        if let puff = Sprites.dot(red: 0.24, green: 0.2, blue: 0.22) {
            for p in particles.particles where p.kind == Bit.smoke && p.progress > 0.3 {
                let t = (p.progress - 0.3) / 0.7
                let alpha = 0.32 * exprSmoothstep(0, 0.25, t) * (1 - exprSmoothstep(0.5, 1, t))
                ctx.stampDot(puff, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 + 1.6 * t), alpha: alpha)
            }
        }
        // The outer flame in ordinary blending too, so it keeps its colour over a white wall where adding light can't show.
        if let under = Sprites.dot(red: 0.95, green: 0.32, blue: 0.08) {
            for (i, p) in particles.particles.enumerated() where p.kind == Bit.body && p.progress > 0.25 && i % 2 == 0 {
                let t = p.progress
                ctx.stampDot(under, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (0.6 + 1.3 * exprSmoothstep(0, 0.8, t)) * 0.8,
                             alpha: 0.3 * (1 - exprSmoothstep(0.5, 1, t)))
            }
        }
        ctx.setBlendMode(.plusLighter)
        if heat.value > 0.01 {
            // The mouth glows and lights the chin.
            ctx.glow(center: mouth, radius: 120 * scale * heat.value, red: 1, green: 0.45, blue: 0.12, alpha: 0.32 * heat.value)
            ctx.glow(center: mouth, radius: 34 * scale * heat.value, red: 1, green: 0.95, blue: 0.75, alpha: 0.8 * heat.value)
        }
        for p in particles.particles where p.kind == Bit.body {
            let t = p.progress
            let c = Self.flameColour(t)
            let q = { (v: Double) in (v * 24).rounded() / 24 }
            guard let dot = Sprites.dot(red: q(c.r), green: q(c.g), blue: q(c.b)) else { continue }
            // Stretched along the way it is going (kept square to the picture, which draws far faster than a turned sprite).
            let speed = hypot(p.velocity.x, p.velocity.y)
            let stretch = 1 + min(0.8, speed / (900 * scale))
            let radius = p.size * (0.6 + 1.3 * exprSmoothstep(0, 0.8, t))
            let alpha = (t < 0.1 ? 0.9 : 0.75) * (1 - exprSmoothstep(0.55, 1, t))
            let along = abs(p.velocity.y) >= abs(p.velocity.x)
            let rx = radius * (along ? 1 : stretch), ry = radius * (along ? stretch : 1)
            ctx.setAlpha(CGFloat(alpha))
            ctx.draw(dot, in: CGRect(x: p.position.x - rx, y: p.position.y - ry, width: rx * 2, height: ry * 2))
            ctx.setAlpha(1)
        }
        ctx.setBlendMode(.normal)
    }

    /// Embers with short streaks behind them.
    private func drawEmbers(_ ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        for p in particles.particles where p.kind == Bit.ember {
            let t = p.progress
            let c = exprMix((1.0, 0.86, 0.4), (1.0, 0.3, 0.06), t)
            let alpha = (1 - exprSmoothstep(0.6, 1, t)) * (0.75 + 0.25 * sin(p.age * 30 + p.hue * 9))
            ctx.setStrokeColor(exprColor(c, alpha * 0.8))
            ctx.setLineWidth(p.size)
            ctx.move(to: CGPoint(x: p.position.x, y: p.position.y))
            ctx.addLine(to: CGPoint(x: p.position.x - p.velocity.x * 0.035, y: p.position.y - p.velocity.y * 0.035))
            ctx.strokePath()
            ctx.fillCircle(center: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * 0.7, color: exprColor((1, 0.95, 0.75), alpha))
        }
        ctx.setBlendMode(.normal)
    }
}

// MARK: - Laser eyes

/// Raise your eyebrows and your eyes flare, then two hot beams burn out of them to the edges of the picture.
final class LaserEyesLens: Lens {
    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var power = Ramp()
    private var firing = false
    private var sparks = ParticleSystem(capacity: 200)
    private var rng = SplitMix64(seed: 0x1A5E2)
    private var presence = ExprPresence()

    static let startAt = 0.55, stopAt = 0.35

    /// How strongly the beams are drawn right now, 0...1.
    var beamPower: Double { power.value }

    init() { sparks.gravity = SIMD2(0, -500) }

    func restart() { sparks.removeAll(); power = Ramp(); firing = false; presence.reset() }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Raise your eyebrows")
        let dt = min(input.dt, 0.1)
        presence.update(input.face, dt: dt)
        if let face = input.face { firing = face.browRaise > (firing ? Self.stopAt : Self.startAt) } else { firing = false }
        power.move(toward: firing ? 1 : 0, dt: dt, rate: firing ? 9 : 5)
        sparks.step(dt)

        guard let face = presence.face, power.value > 0.01 || !sparks.particles.isEmpty else { return input.composed }
        let beams = Self.beams(from: face, in: input.rect)
        if firing {
            let scale = max(0.35, face.interocular / 84)
            for beam in beams where Double.random(in: 0..<1, using: &rng) < 0.6 {
                // Hot sparks spit from the eye where the beam leaves it.
                let heading = SIMD2(beam.end.x - beam.start.x, beam.end.y - beam.start.y) / max(hypot(beam.end.x - beam.start.x, beam.end.y - beam.start.y), 1)
                let angle = atan2(heading.y, heading.x) + Double.random(in: -0.9...0.9, using: &rng)
                let speed = Double.random(in: 120...420, using: &rng) * scale
                sparks.emit(Particle(position: beam.start.simd + heading * face.interocular * 0.15, velocity: SIMD2(cos(angle), sin(angle)) * speed,
                                     life: Double.random(in: 0.2...0.5, using: &rng), size: Double.random(in: 2...4, using: &rng) * scale))
            }
        }

        guard let layer = input.services.exprOverlay({ ctx in draw(ctx, beams: beams, face: face, time: input.time) }) else { return input.composed }
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

    /// A slice across a beam, in one colour: a soft bloom that falls off the way light does. Stretched along the beam.
    private static func profile(_ c: ExprRGB) -> CGImage? {
        ExprSprites.make(String(format: "laser-profile-%.2f-%.2f-%.2f", c.r, c.g, c.b), side: 64) { ctx in
            if let bloom = ExprShapes.gradient([(c, 0), (c, 0.18), (c, 0.5), (c, 1)], alphas: [1, 0.55, 0.16, 0]) {
                ctx.drawLinearGradient(bloom, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 1), options: [])
                ctx.drawLinearGradient(bloom, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: -1), options: [])
            }
        }
    }

    /// The beam's layers from the outside in: a wide magenta bloom, a red glow, a hot pink body and a white core.
    private static let layers: [(width: Double, colour: ExprRGB, alpha: Double)] = [
        (110, (1.0, 0.12, 0.30), 0.42), (44, (1.0, 0.24, 0.20), 0.85), (15, (1.0, 0.62, 0.52), 1.0), (5, (1.0, 1.0, 1.0), 1.0),
    ]

    private func draw(_ ctx: CGContext, beams: [Beam], face: FaceState, time: Double) {
        let p = power.value * presence.alpha
        let io = face.interocular
        let scale = max(0.35, io / 84)
        let shimmer = 1 + 0.05 * sin(time * 47) + 0.03 * sin(time * 113)
        // The beam reaches out from the eye as it charges, rather than appearing all at once.
        let reach = exprOutCubic(exprSmoothstep(0.15, 1, power.value))
        ctx.setBlendMode(.plusLighter)
        for beam in beams {
            let dx = beam.end.x - beam.start.x, dy = beam.end.y - beam.start.y
            let length = hypot(dx, dy) * reach
            ctx.saveGState()
            ctx.translateBy(x: beam.start.x, y: beam.start.y)
            ctx.rotate(by: atan2(dy, dx))
            for layer in Self.layers {
                let w = layer.width * scale * shimmer * (0.4 + 0.6 * p)
                guard let slice = Self.profile(layer.colour) else { continue }
                ctx.setAlpha(CGFloat(layer.alpha * p))
                ctx.draw(slice, in: CGRect(x: 0, y: -w / 2, width: length, height: w))
            }
            ctx.setAlpha(1)
            ctx.restoreGState()
            drawFlare(ctx, at: beam.start, face: face, power: p, time: time)
        }
        if let hot = Sprites.dot(red: 1, green: 0.92, blue: 0.8), let halo = Sprites.dot(red: 1, green: 0.3, blue: 0.25) {
            for s in sparks.particles {
                let at = CGPoint(x: s.position.x, y: s.position.y), fade = (1 - s.progress) * presence.alpha
                ctx.stampDot(halo, at: at, radius: s.size * 3, alpha: 0.6 * fade)
                ctx.stampDot(hot, at: at, radius: s.size * 1.3, alpha: fade)
            }
        }
        ctx.setBlendMode(.normal)
    }

    /// The flare where a beam leaves an eye: a hot white core, a red bloom, a long thin streak across and a slowly turning glint.
    private func drawFlare(_ ctx: CGContext, at eye: CGPoint, face: FaceState, power p: Double, time: Double) {
        let io = face.interocular
        ctx.glow(center: eye, radius: io * 0.62 * p, red: 1, green: 0.16, blue: 0.24, alpha: 0.55 * p)
        ctx.glow(center: eye, radius: io * 0.22 * p, red: 1, green: 0.95, blue: 0.92, alpha: 1.0 * p)
        guard let streak = Sprites.dot(red: 1, green: 0.55, blue: 0.6) else { return }
        ctx.saveGState()
        ctx.translateBy(x: eye.x, y: eye.y)
        ctx.rotate(by: face.roll)
        ctx.scaleBy(x: 1, y: 0.06)
        ctx.stampDot(streak, at: .zero, radius: io * 1.5 * p, alpha: 0.75 * p)
        ctx.restoreGState()
        ctx.exprStamp(ExprSprites.twinkle(variant: 0), at: eye, height: io * 0.75 * p, rotation: face.roll + time * 0.7, alpha: 0.8 * p)
    }
}
