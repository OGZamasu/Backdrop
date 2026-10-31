import AppKit
import CoreGraphics
import CoreImage
import simd

/// Where things go on a face: the maths between "an eye-spacing above the eyes" and pixels in the picture.
struct FaceFrame {
    let face: FaceState
    let io: Double
    let roll: Double

    init(_ face: FaceState) {
        self.face = face
        io = max(face.interocular, 1)
        roll = face.roll
    }

    /// A point in the picture as eye-spacings from the middle of the eyes, along and up the face.
    func local(_ p: CGPoint) -> SIMD2<Double> {
        let dx = Double(p.x - face.eyeCenter.x), dy = Double(p.y - face.eyeCenter.y)
        let c = cos(-roll), s = sin(-roll)
        return SIMD2((dx * c - dy * s) / io, (dx * s + dy * c) / io)
    }

    func pixel(_ local: SIMD2<Double>) -> CGPoint {
        let c = cos(roll), s = sin(roll)
        return CGPoint(x: Double(face.eyeCenter.x) + (local.x * c - local.y * s) * io, y: Double(face.eyeCenter.y) + (local.x * s + local.y * c) * io)
    }

    func local(_ anchor: PackAnchor) -> SIMD2<Double> {
        switch anchor {
        case .eyes, .screen: return .zero
        case .leftEye: return SIMD2(-0.5, 0)
        case .rightEye: return SIMD2(0.5, 0)
        case .nose: return local(face.nose)
        case .mouth: return local(face.mouth)
        case .forehead: return SIMD2(0, 0.95)
        case .headTop: return SIMD2(0, 1.55)
        case .chin: return SIMD2(local(face.mouth).x, local(face.mouth).y - 0.42)
        case .cheekLeft: return SIMD2(-0.62, -0.62)
        case .cheekRight: return SIMD2(0.62, -0.62)
        case .face: return local(CGPoint(x: face.rect.midX, y: face.rect.midY))
        }
    }
}

/// A lens read from a folder of plain files: pictures, emoji, text and shapes pinned to the face, effects that switch on
/// with a smile or a raised eyebrow, a warp, a look for the whole picture.
final class PackLens: Lens {
    let pack: LensPack
    let needs: LensNeeds
    var status: LensStatus? { statusBox.value }

    private struct Element {
        var ramp = Ramp()
        var on = false
        var shownFor = 0.0
    }

    private struct EmitterState {
        var element = Element()
        var particles: ParticleSystem
        var owed = 0.0
    }

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var layers: [Element]
    private var warps: [Element]
    private var emitters: [EmitterState]
    private var rng = SplitMix64(seed: 0x1E75)

    /// For tests: how many particles are alive.
    var particleCount: Int { emitters.reduce(0) { $0 + $1.particles.particles.count } }

    init(_ pack: LensPack) {
        self.pack = pack
        needs = pack.needsFace ? [.face] : []
        layers = Array(repeating: Element(), count: pack.layers.count)
        warps = Array(repeating: Element(), count: pack.warps.count)
        // However many emitters there are, they share a fixed number of particles between them.
        emitters = pack.emitters.map { _ in EmitterState(particles: ParticleSystem(capacity: max(60, 480 / max(1, pack.emitters.count)))) }
        // Pictures are read now, when the lens is chosen, not in the middle of a video frame.
        for layer in pack.layers { if case .image(let image) = layer.content { _ = image.cgImage } }
        for i in emitters.indices {
            let spec = Self.spec(pack.emitters[i].preset)
            emitters[i].particles.gravity = SIMD2(0, spec.gravity)
            emitters[i].particles.drag = spec.drag
        }
    }

    func restart() {
        layers = Array(repeating: Element(), count: layers.count)
        warps = Array(repeating: Element(), count: warps.count)
        for i in emitters.indices { emitters[i].particles.removeAll(); emitters[i].element = Element() }
    }

    // MARK: Frame

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = pack.needsFace ? hint.status(pack.name) : nil
        let dt = input.dt, rect = input.rect
        let face = input.face
        let frame = face.map(FaceFrame.init)

        var picture = look(input.composed, rect: rect)

        // Warps first: they bend the picture, and everything drawn after stays crisp.
        for i in pack.warps.indices {
            let warp = pack.warps[i]
            let shown = update(&warps[i], trigger: warp.show, needsFace: true, face: face, dt: dt)
            guard shown > 0.02, let frame else { continue }
            let centre = frame.pixel(frame.local(warp.anchor) + warp.offset)
            let filter = CIFilter(name: "CIBumpDistortion")!
            filter.setValue(picture, forKey: kCIInputImageKey)
            filter.setValue(CIVector(cgPoint: centre), forKey: kCIInputCenterKey)
            filter.setValue(warp.radius * frame.io, forKey: kCIInputRadiusKey)
            filter.setValue((warp.kind == .bulge ? 1 : -1) * warp.strength * shown, forKey: kCIInputScaleKey)
            picture = (filter.outputImage ?? picture).cropped(to: rect)
        }

        // Emitters have particles to move even while they are switched off.
        for i in pack.emitters.indices {
            let emitter = pack.emitters[i]
            let shown = update(&emitters[i].element, trigger: emitter.show, needsFace: true, face: face, dt: dt)
            if shown > 0.3, let frame { emit(i, frame: frame, shown: shown, dt: dt, time: input.time) }
            emitters[i].particles.step(dt)
            emitters[i].particles.particles.removeAll { $0.position.y < -80 || $0.position.y > rect.height + 120 }
        }

        let drawsAnything = !pack.layers.isEmpty || !pack.emitters.isEmpty
        guard drawsAnything else { return picture }
        for i in pack.layers.indices {
            let layer = pack.layers[i]
            _ = update(&layers[i], trigger: layer.show, needsFace: layer.anchor != .screen, face: face, dt: dt)
        }

        guard let overlay = input.services.overlay({ ctx in
            for i in pack.layers.indices where layers[i].ramp.value > 0.01 {
                draw(pack.layers[i], state: layers[i], frame: frame, rect: rect, time: input.time, in: ctx)
            }
            for i in pack.emitters.indices { drawParticles(of: i, in: ctx) }
        }) else { return picture }
        return overlay.composited(over: picture).cropped(to: rect)
    }

    /// Moves an element's fade toward on or off and returns how visible it is, 0...1.
    private func update(_ element: inout Element, trigger: PackTrigger, needsFace: Bool, face: FaceState?, dt: Double) -> Double {
        let reading = face.map { trigger.signal.value(in: $0) } ?? 0
        let canShow = !(needsFace || trigger.needsFace) || face != nil
        element.on = canShow && trigger.isOn(trigger.signal == .always || trigger.signal == .faceFound ? 1 : reading, wasOn: element.on)
        element.ramp.move(toward: element.on ? 1 : 0, dt: dt, rate: 1 / trigger.fade)
        // Keep the clock while fading out, so a "dropIn" doesn't leap back up as it disappears.
        element.shownFor = element.on ? element.shownFor + dt : (element.ramp.value > 0 ? element.shownFor : 0)
        return element.ramp.value
    }

    // MARK: Look

    private func look(_ image: CIImage, rect: CGRect) -> CIImage {
        let look = pack.look
        guard !look.isNeutral else { return image }
        var out = image
        if look.saturation != 1 || look.contrast != 1 || look.brightness != 0 {
            out = out.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: look.saturation, kCIInputContrastKey: look.contrast,
                                                                    kCIInputBrightnessKey: look.brightness])
        }
        if look.hue != 0 { out = out.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: look.hue * .pi / 180]) }
        if let t = look.tint, t.count >= 3 {
            out = CIImage(color: CIColor(red: t[0], green: t[1], blue: t[2], alpha: look.tintAmount)).cropped(to: rect).composited(over: out)
        }
        if look.vignette > 0 {
            out = out.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: look.vignette * 1.5, kCIInputRadiusKey: 1.6])
        }
        return out.cropped(to: rect)
    }

    // MARK: Layers

    private func draw(_ layer: PackLayer, state: Element, frame: FaceFrame?, rect: CGRect, time: Double, in ctx: CGContext) {
        let onScreen = layer.anchor == .screen
        guard onScreen || frame != nil else { return }
        let unit = onScreen ? Double(rect.height) : frame!.io

        // Animation: a nudge, a scale, a turn.
        var nudge = SIMD2<Double>.zero, scale = 1.0, turn = 0.0
        if let a = layer.animation {
            let phase = time * a.speed * 2 * .pi
            switch a.kind {
            case .bob: nudge.y = sin(phase) * a.amount
            case .float: nudge = SIMD2(sin(phase * 1.3) * a.amount * 0.5, sin(phase * 0.7) * a.amount)
            case .pulse: scale = 1 + sin(phase) * a.amount
            case .spin: turn = phase
            case .wiggle: turn = sin(phase) * a.amount * 0.5
            case .dropIn: nudge.y = pow(1 - min(1, state.shownFor / (0.55 / a.speed)), 3) * 2.6 * (onScreen ? 0.4 : 1)
            }
        }

        for side in layer.mirror ? [1.0, -1.0] : [1.0] {
            // Where it sits across the face, anchor and offset together, then flipped about the middle of the face.
            var position = layer.offset + (onScreen ? .zero : (frame?.local(layer.anchor) ?? .zero))
            position.x *= side
            position += SIMD2(nudge.x * side, nudge.y)

            let point: CGPoint
            var angle = layer.rotation * side + turn * side
            if onScreen {
                point = CGPoint(x: rect.midX + position.x * rect.width, y: rect.midY + position.y * rect.height)
            } else if let frame {
                point = frame.pixel(position)
                if layer.followsHead { angle += frame.roll }
            } else { continue }

            ctx.saveGState()
            ctx.translateBy(x: point.x, y: point.y)
            ctx.rotate(by: angle)
            ctx.scaleBy(x: scale, y: scale)
            ctx.setAlpha(CGFloat(layer.opacity * state.ramp.value))
            ctx.setBlendMode(layer.blend.mode)
            let height = layer.size * unit, width = layer.width * unit
            switch layer.content {
            case .image(let picture):
                if side < 0 { ctx.scaleBy(x: -1, y: 1) }
                if let image = picture.cgImage {
                    let w = height * Double(image.width) / Double(image.height)
                    ctx.draw(image, in: CGRect(x: -w / 2, y: -height / 2, width: w, height: height))
                }
            case .emoji(let emoji):
                if side < 0 { ctx.scaleBy(x: -1, y: 1) }
                if let sprite = Sprites.emoji(emoji, size: 100) {
                    let w = height * Double(sprite.width) / Double(sprite.height)
                    ctx.draw(sprite, in: CGRect(x: -w / 2, y: -height / 2, width: w, height: height))
                }
            case .text(let text):
                let weights: [NSFont.Weight] = [.regular, .semibold, .bold, .heavy]
                let weight = weights[min(3, Int(layer.weight * 4))]
                ctx.text(text, center: .zero, size: max(4, height), color: NSColor(cgColor: layer.color) ?? .white, weight: weight)
            case .shape(let shape):
                if side < 0 { ctx.scaleBy(x: -1, y: 1) }
                Self.drawShape(shape, width: width, height: height, fill: layer.color, stroke: layer.stroke,
                               strokeWidth: layer.strokeWidth.map { $0 * unit }, in: ctx)
            }
            ctx.restoreGState()
        }
    }

    static func drawShape(_ shape: PackShape, width w: Double, height h: Double, fill: CGColor, stroke: CGColor?, strokeWidth: Double? = nil,
                          in ctx: CGContext) {
        let box = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let path = CGMutablePath()
        switch shape {
        case .circle: path.addEllipse(in: box)
        case .rect: path.addRect(box)
        case .roundRect: path.addRoundedRect(in: box, cornerWidth: min(w, h) * 0.22, cornerHeight: min(w, h) * 0.22)
        case .triangle:
            path.move(to: CGPoint(x: 0, y: h / 2)); path.addLine(to: CGPoint(x: w / 2, y: -h / 2)); path.addLine(to: CGPoint(x: -w / 2, y: -h / 2)); path.closeSubpath()
        case .star:
            for i in 0..<10 {
                let a = Double.pi / 2 + Double(i) * .pi / 5, r = i % 2 == 0 ? 0.5 : 0.21
                let p = CGPoint(x: cos(a) * r * w, y: sin(a) * r * h)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        case .heart:
            path.move(to: CGPoint(x: 0, y: -h / 2))
            path.addCurve(to: CGPoint(x: -w / 2, y: h * 0.12), control1: CGPoint(x: -w * 0.3, y: -h * 0.3), control2: CGPoint(x: -w / 2, y: -h * 0.05))
            path.addCurve(to: CGPoint(x: 0, y: h * 0.18), control1: CGPoint(x: -w / 2, y: h * 0.48), control2: CGPoint(x: -w * 0.1, y: h * 0.5))
            path.addCurve(to: CGPoint(x: w / 2, y: h * 0.12), control1: CGPoint(x: w * 0.1, y: h * 0.5), control2: CGPoint(x: w / 2, y: h * 0.48))
            path.addCurve(to: CGPoint(x: 0, y: -h / 2), control1: CGPoint(x: w / 2, y: -h * 0.05), control2: CGPoint(x: w * 0.3, y: -h * 0.3))
            path.closeSubpath()
        }
        // A see-through fill (an outline-only shape) is skipped: filling a full-screen shape with nothing still costs milliseconds.
        if fill.alpha > 0.002 {
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath()
        }
        if let stroke {
            ctx.addPath(path)
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(max(1.5, strokeWidth ?? min(w, h) * 0.06))
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
    }

    // MARK: Emitters

    struct EmitterSpec {
        var gravity: Double
        var drag: Double
        var rate: Double
        var speed: ClosedRange<Double>
        var spread: Double
        var life: ClosedRange<Double>
        var size: ClosedRange<Double>
        /// Which way it goes, as a multiple of the face's own down and across directions.
        var heading: SIMD2<Double>
        var additive: Bool
    }

    static func spec(_ preset: PackEmitter.Preset) -> EmitterSpec {
        switch preset {
        case .rainbow: return EmitterSpec(gravity: -1500, drag: 0.15, rate: 170, speed: 330...560, spread: 140, life: 1.0...1.6, size: 15...30, heading: SIMD2(0, 1), additive: false)
        case .fire: return EmitterSpec(gravity: 240, drag: 1.1, rate: 150, speed: 520...880, spread: 160, life: 0.45...0.8, size: 14...26, heading: SIMD2(0, 1), additive: true)
        case .hearts: return EmitterSpec(gravity: 90, drag: 0.4, rate: 7, speed: 120...260, spread: 160, life: 1.4...2.2, size: 26...44, heading: SIMD2(0, -1), additive: false)
        case .sparkles: return EmitterSpec(gravity: 0, drag: 1.4, rate: 60, speed: 80...260, spread: 360, life: 0.4...0.9, size: 8...16, heading: SIMD2(0, 0), additive: true)
        case .confetti: return EmitterSpec(gravity: -900, drag: 0.5, rate: 90, speed: 300...700, spread: 220, life: 1.2...2.0, size: 7...13, heading: SIMD2(0, -1), additive: false)
        case .bubbles: return EmitterSpec(gravity: 120, drag: 0.6, rate: 10, speed: 40...120, spread: 120, life: 1.6...2.6, size: 12...34, heading: SIMD2(0, -1), additive: false)
        }
    }

    private func emit(_ index: Int, frame: FaceFrame, shown: Double, dt: Double, time: Double) {
        let emitter = pack.emitters[index]
        let spec = Self.spec(emitter.preset)
        let scale = max(0.6, frame.io / 90) * emitter.size
        let origin = frame.pixel(frame.local(emitter.anchor) + emitter.offset).simd
        let down = frame.face.downVector, across = frame.face.acrossVector
        emitters[index].owed += dt * spec.rate * emitter.rate * shown
        while emitters[index].owed >= 1 {
            emitters[index].owed -= 1
            let speed = Double.random(in: spec.speed, using: &rng) * scale
            let sideways = Double.random(in: -1...1, using: &rng) * spec.spread * scale
            var velocity = down * spec.heading.y * speed + across * (spec.heading.x * speed + sideways)
            if spec.heading == .zero {                       // sparkles go every which way
                let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                velocity = SIMD2(cos(a), sin(a)) * speed
            } else if spec.heading.y < 0 {                   // hearts and confetti go up and out
                velocity = -down * abs(spec.heading.y) * speed + across * sideways
            }
            emitters[index].particles.emit(Particle(position: origin, velocity: velocity, life: Double.random(in: spec.life, using: &rng),
                                                    size: Double.random(in: spec.size, using: &rng) * scale,
                                                    hue: time * 0.55 + Double.random(in: -0.04...0.04, using: &rng),
                                                    kind: Int.random(in: 0..<8, using: &rng)))
        }
    }

    private func drawParticles(of index: Int, in ctx: CGContext) {
        let preset = pack.emitters[index].preset
        let spec = Self.spec(preset)
        if spec.additive { ctx.setBlendMode(.plusLighter) }
        defer { ctx.setBlendMode(.normal); ctx.setAlpha(1) }
        for p in emitters[index].particles.particles {
            let t = p.progress, at = CGPoint(x: p.position.x, y: p.position.y)
            switch preset {
            case .rainbow:
                let (r, g, b) = Palette.rgb(hue: (p.hue * 24).rounded() / 24, saturation: 0.85, brightness: 1)
                if let dot = Sprites.dot(red: r, green: g, blue: b) { ctx.stampDot(dot, at: at, radius: p.size * (1 + t * 0.6), alpha: 1 - t * t) }
            case .fire:
                let (r, g, b) = t < 0.3 ? (1.0, 0.95, 0.6) : t < 0.65 ? (1.0, 0.5, 0.1) : (0.8, 0.15, 0.05)
                if let dot = Sprites.dot(red: r, green: g, blue: b) { ctx.stampDot(dot, at: at, radius: p.size * (1 + t * 2.2), alpha: (1 - t) * 0.85) }
            case .sparkles:
                let twinkle = 0.5 + 0.5 * sin(p.age * 30 + Double(p.kind))
                if let dot = Sprites.dot(red: 1, green: 0.95, blue: 0.7) { ctx.stampDot(dot, at: at, radius: p.size * (1 - 0.5 * t), alpha: (1 - t) * (0.4 + 0.6 * twinkle)) }
            case .hearts:
                if let sprite = Sprites.emoji(p.kind % 2 == 0 ? "❤️" : "💖", size: 100) {
                    ctx.draw(sprite, center: at, height: p.size * (1 + 0.2 * sin(p.age * 6)), rotation: sin(p.age * 3 + Double(p.kind)) * 0.3, alpha: min(1, (1 - t) * 2))
                }
            case .confetti:
                let (r, g, b) = Palette.rgb(hue: Double(p.kind) / 8, saturation: 0.8, brightness: 1)
                ctx.saveGState()
                ctx.translateBy(x: at.x, y: at.y)
                ctx.rotate(by: p.age * 7 + Double(p.kind))
                ctx.setAlpha(CGFloat(1 - t * t))
                ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
                ctx.fill(CGRect(x: -p.size, y: -p.size * 0.5, width: p.size * 2, height: p.size))
                ctx.restoreGState()
            case .bubbles:
                ctx.setAlpha(CGFloat((1 - t) * 0.8))
                ctx.setStrokeColor(CGColor(red: 0.8, green: 0.95, blue: 1, alpha: 1))
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: at.x - p.size, y: at.y - p.size, width: p.size * 2, height: p.size * 2))
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
                ctx.fillEllipse(in: CGRect(x: at.x - p.size, y: at.y - p.size, width: p.size * 2, height: p.size * 2))
            }
        }
    }
}
