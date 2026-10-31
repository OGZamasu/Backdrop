import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// A perfectly symmetrical you: one half of your face is mirrored onto the other, along the line down the middle of your face,
/// fading out softly around the head. Tip your head the other way to swap which half is copied.
final class ExprMirrorFaceLens: Lens {
    /// How far you must tip your head (radians) to choose a side.
    static let tipAt = 0.14

    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var amount = ExprSpring()
    private var lastFace: FaceState?
    /// Which half is copied across: -1 the half on the left of the picture, +1 the right.
    private(set) var source = -1.0
    private var blend = ExprSpring(-1)

    init() {}

    func restart() { amount.reset(); lastFace = nil; source = -1; blend.reset(-1) }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Tip your head to switch sides")
        let dt = min(max(input.dt, 0), 0.25)
        if let f = input.face {
            lastFace = f
            // Tip toward a side to copy that side; in between, keep whatever was chosen.
            if f.roll > Self.tipAt { source = 1 } else if f.roll < -Self.tipAt { source = -1 }
        }
        amount.step(toward: input.face == nil ? 0 : 1, dt: dt, frequency: 2.4, damping: input.face == nil ? 1 : 0.8)
        blend.step(toward: source, dt: dt, frequency: 2.2, damping: 0.85)
        if input.face == nil && amount.value < 0.004 { lastFace = nil }
        guard let face = lastFace else { return input.composed }

        // Reflect the picture across the line through the eyes' midpoint, up the face.
        let c = face.eyeCenter
        let mirror = CGAffineTransform(translationX: -c.x, y: -c.y)
            .concatenating(CGAffineTransform(rotationAngle: -face.roll))
            .concatenating(CGAffineTransform(scaleX: -1, y: 1))
            .concatenating(CGAffineTransform(rotationAngle: face.roll))
            .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
        let mirrored = input.composed.clampedToExtent().transformed(by: mirror).cropped(to: input.rect)
        let strength = max(0, min(1, amount.value))
        let b = blend.value
        guard let mask = input.services.exprOverlay({ ctx in
            ctx.inFaceSpace(face) {
                // The copied half replaces the other one: weight each half by how far the choice has swung to it.
                for (half, weight) in [(1.0, max(0, -b)), (-1.0, max(0, b))] where weight > 0.01 {
                    ctx.saveGState()
                    ctx.clip(to: CGRect(x: half > 0 ? 0 : -3, y: -4, width: 3, height: 7))
                    ctx.translateBy(x: 0, y: -0.3)
                    ctx.scaleBy(x: 1.4, y: 1.62)
                    let stops: [(Double, Double)] = [(0, 1), (0.74, 1), (0.9, 0.45), (1, 0)]
                    if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { exprColor((1, 1, 1), $0.1 * strength * weight) } as CFArray,
                                          locations: stops.map { CGFloat($0.0) }) {
                        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
                    }
                    ctx.restoreGState()
                }
            }
        }) else { return input.composed }
        let mix = CIFilter.blendWithAlphaMask()
        mix.inputImage = mirrored
        mix.backgroundImage = input.composed
        mix.maskImage = mask
        return (mix.outputImage ?? input.composed).cropped(to: input.rect)
    }
}

/// Your face glitches like a broken video signal: colour channels split, slices of your face jump sideways and blocks
/// smear. Blink for a quick burst, hold your mouth open for a full meltdown; at rest it only flickers now and then.
final class ExprGlitchFaceLens: Lens {
    static let mouthOn = 0.45, mouthOff = 0.25
    static let blinkOn = 0.6, blinkOff = 0.3
    static let burstLength = 0.45

    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var mouth = ExprLatch()
    private var blink = ExprLatch()
    private var held = Ramp()
    private var sinceBurst = 10.0
    private var presence = ExprPresence()
    private(set) var burstCount = 0

    /// How broken the picture is right now, 0...1.
    private(set) var level = 0.0

    var isMeltingDown: Bool { mouth.isOn }

    init() {}

    func restart() { mouth.reset(); blink.reset(); held = Ramp(); sinceBurst = 10; presence.reset(); burstCount = 0; level = 0 }

    /// A hash of a whole number to 0..<1, for glitch choices that stay put for a beat and then jump.
    static func hash(_ n: Int, _ salt: Int = 0) -> Double {
        var x = UInt64(bitPattern: Int64(n &* 73_856_093 ^ salt &* 19_349_663))
        x = (x ^ (x >> 33)) &* 0xff51afd7ed558ccd
        x = (x ^ (x >> 33)) &* 0xc4ceb9fe1a85ec53
        x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }

    /// The small flickers at rest: now and then, for a fraction of a second.
    static func idleFlicker(at time: Double) -> Double {
        let beat = Int(floor(time / 0.8))
        guard hash(beat, 7) < 0.3 else { return 0 }
        let inBeat = time / 0.8 - Double(beat)
        return inBeat < 0.18 ? 0.35 : 0
    }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Blink, or open your mouth")
        let dt = min(max(input.dt, 0), 0.25)
        presence.update(input.face, dt: dt)
        sinceBurst += dt
        if let f = input.face {
            mouth.update(f.mouthOpen, on: Self.mouthOn, off: Self.mouthOff)
            let was = blink.isOn
            blink.update(f.blink, on: Self.blinkOn, off: Self.blinkOff)
            if blink.isOn && !was { sinceBurst = 0; burstCount += 1 }
        } else {
            mouth.reset(); blink.reset()
        }
        held.move(toward: mouth.isOn ? 1 : 0, dt: dt, rate: mouth.isOn ? 4 : 2.5)
        let burst = sinceBurst < Self.burstLength ? 1 - sinceBurst / Self.burstLength : 0
        level = max(held.value, burst * 0.9, Self.idleFlicker(at: input.time)) * presence.alpha
        guard let face = presence.face, level > 0.01 else { return input.composed }
        return glitched(input, face: face, level: level, time: input.time)
    }

    private func glitched(_ input: LensInput, face: FaceState, level g: Double, time: Double) -> CIImage {
        let io = face.interocular
        let corners = [(-1.6, 1.8), (1.6, 1.8), (-1.6, -2.2), (1.6, -2.2)].map { face.exprPoint($0.0, $0.1) }
        let region = corners.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }.integral.intersection(input.rect)
        guard !region.isNull, region.width > 4, region.height > 4 else { return input.composed }
        let beat = Int(floor(time * 14))
        let base = input.composed.clampedToExtent()
        // Colour channels pulled apart: red one way, green and blue the other.
        let split = io * (0.03 + 0.09 * g) * (0.6 + 0.8 * Self.hash(beat, 1))
        let red = base.applyingFilter("CIColorMatrix", parameters: ["inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
            .transformed(by: CGAffineTransform(translationX: split, y: 0))
        let cyan = base.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
            .transformed(by: CGAffineTransform(translationX: -split, y: 0))
        var picture = red.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: cyan]).cropped(to: region)
        // Slices of the face jump sideways.
        let slices = 9
        let sliceHeight = region.height / Double(slices)
        for i in 0..<slices where Self.hash(beat * 31 + i, 2) < 0.25 + 0.5 * g {
            let shift = (Self.hash(beat * 17 + i, 3) - 0.5) * io * 0.9 * g
            let strip = CGRect(x: region.minX, y: region.minY + Double(i) * sliceHeight, width: region.width, height: sliceHeight * (0.5 + Self.hash(i, beat)))
            picture = picture.clampedToExtent().transformed(by: CGAffineTransform(translationX: shift, y: 0)).cropped(to: strip)
                .composited(over: picture).cropped(to: region)
        }
        // A smeared block or two.
        if g > 0.3 {
            for k in 0..<2 where Self.hash(beat, 10 + k) < g {
                let w = io * (0.4 + 0.6 * Self.hash(beat, 20 + k)), h = io * (0.15 + 0.25 * Self.hash(beat, 30 + k))
                let x = region.minX + (region.width - w) * Self.hash(beat, 40 + k), y = region.minY + (region.height - h) * Self.hash(beat, 50 + k)
                let block = CGRect(x: x, y: y, width: w, height: h)
                let pixels = picture.applyingFilter("CIPixellate", parameters: [kCIInputCenterKey: CIVector(x: x, y: y), kCIInputScaleKey: max(4, io * 0.14)])
                picture = pixels.cropped(to: block).composited(over: picture).cropped(to: region)
            }
        }
        // Fade the glitch out softly around the head, and add scanlines and stray bars of colour on top.
        guard let mask = input.services.exprOverlay({ ctx in
            ctx.inFaceSpace(face) {
                ctx.translateBy(x: 0, y: -0.25)
                ctx.scaleBy(x: 1.55, y: 2.0)
                let stops: [(Double, Double)] = [(0, 1), (0.75, 1), (1, 0)]
                if let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { exprColor((1, 1, 1), $0.1) } as CFArray,
                                         locations: stops.map { CGFloat($0.0) }) {
                    ctx.drawRadialGradient(grad, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
                }
            }
        }) else { return input.composed }
        let mix = CIFilter.blendWithAlphaMask()
        mix.inputImage = picture
        mix.backgroundImage = input.composed
        mix.maskImage = mask
        let broken = (mix.outputImage ?? input.composed).cropped(to: input.rect)
        guard let marks = input.services.exprOverlay({ ctx in
            // Scanlines, only over the head.
            ctx.saveGState()
            ctx.inFaceSpace(face) { ctx.addEllipse(in: CGRect(x: -1.3, y: -2.05, width: 2.6, height: 3.6)) }
            ctx.clip()
            ctx.setFillColor(exprColor((0.02, 0.02, 0.05), 0.14 * g))
            var y = region.minY
            while y < region.maxY { ctx.fill(CGRect(x: region.minX, y: y, width: region.width, height: 1.5)); y += 4 }
            ctx.restoreGState()
            for k in 0..<4 where Self.hash(beat, 60 + k) < g * 0.8 {
                let colour = k % 2 == 0 ? ExprPalette.neonCyan : ExprPalette.neonPink
                let w = io * (0.3 + 0.9 * Self.hash(beat, 70 + k)), h = max(2, io * 0.04)
                let x = region.minX + (region.width - w) * Self.hash(beat, 80 + k), yy = region.minY + region.height * Self.hash(beat, 90 + k)
                ctx.setFillColor(exprColor(colour, 0.7 * g)); ctx.fill(CGRect(x: x, y: yy, width: w, height: h))
            }
        }) else { return broken }
        return marks.composited(over: broken).cropped(to: input.rect)
    }
}
