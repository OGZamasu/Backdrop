import CoreGraphics
import CoreImage

/// Comic-book sound effects for your face: laugh and "HA HA!" bursts out beside you, gasp with your mouth open for "WOW!",
/// raise your eyebrows for "WHAT?!". Each one pops out of a halftone starburst with speed lines, then flies away.
final class ExprComicPowLens: ExprOverlayLens {
    enum Word: String, CaseIterable {
        case laugh = "HA HA!", wow = "WOW!", what = "WHAT?!"

        /// The starburst behind each word.
        var burst: ExprPalette.Ramp {
            switch self {
            case .laugh: return ExprPalette.Ramp(light: (1.0, 0.55, 0.62), base: (0.96, 0.22, 0.36), dark: (0.76, 0.08, 0.26), edge: (0.25, 0.04, 0.12))
            case .wow: return ExprPalette.Ramp(light: (0.55, 0.88, 1.0), base: (0.18, 0.6, 1.0), dark: (0.1, 0.36, 0.86), edge: (0.04, 0.1, 0.3))
            case .what: return ExprPalette.Ramp(light: (0.84, 0.66, 1.0), base: (0.6, 0.3, 0.96), dark: (0.4, 0.14, 0.8), edge: (0.16, 0.05, 0.3))
            }
        }
    }

    struct Pop {
        var word: Word
        var at: CGPoint
        var size: Double
        var tilt: Double
        var age = 0.0
    }

    static let life = 1.6
    static let cooldown = 0.45

    private var smile = ExprLatch(), mouth = ExprLatch(), brows = ExprLatch()
    private(set) var pops: [Pop] = []
    private var sinceLast = 10.0
    private var nextSide = 1.0
    private var rng = SplitMix64(seed: 0xC0C0)
    private(set) var popCount = 0

    override var hintText: String { "Laugh, gasp or raise your eyebrows" }
    override var isFinished: Bool { presence.face == nil && pops.isEmpty }

    override func restart() {
        super.restart()
        smile.reset(); mouth.reset(); brows.reset(); pops = []; sinceLast = 10; nextSide = 1; popCount = 0
    }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        sinceLast += dt
        for i in pops.indices { pops[i].age += dt }
        pops.removeAll { $0.age > Self.life }
        guard let face else { smile.reset(); mouth.reset(); brows.reset(); return }
        let wasSmile = smile.isOn, wasMouth = mouth.isOn, wasBrows = brows.isOn
        smile.update(face.smile, on: 0.55, off: 0.3)
        mouth.update(face.mouthOpen, on: 0.5, off: 0.3)
        brows.update(face.browRaise, on: 0.55, off: 0.35)
        var word: Word?
        if smile.isOn && (!wasSmile || (mouth.isOn && !wasMouth)) { word = .laugh }
        else if mouth.isOn && !wasMouth { word = .wow }
        else if brows.isOn && !wasBrows { word = .what }
        if let word, sinceLast >= Self.cooldown { spawn(word, face: face) }
    }

    private func spawn(_ word: Word, face: FaceState) {
        sinceLast = 0
        popCount += 1
        let size = max(face.interocular * 2.3, 180)
        // Beside the head, alternating sides, a little above the eyes, always inside the picture and clear of the face.
        let clear = face.interocular * 1.25 + size * 0.5
        func spot(_ side: Double) -> CGPoint {
            let raw = face.exprPoint(side * clear / face.interocular, 0.55)
            return face.exprKeepInside(raw, half: CGSize(width: size * 0.5, height: size * 0.4), in: bounds)
        }
        var at = spot(nextSide)
        if abs(at.x - face.eyeCenter.x) < clear * 0.85 { at = spot(-nextSide) }
        if pops.count >= 3 { pops.removeFirst() }
        pops.append(Pop(word: word, at: at, size: size, tilt: nextSide * Double.random(in: 0.06...0.16, using: &rng)))
        nextSide = -nextSide
    }

    /// A jagged starburst with halftone dots, baked per colour.
    static func burst(_ word: Word) -> CGImage? {
        ExprSprites.make("expr-comic-burst-\(word.rawValue)", side: 320) { ctx in
            let path = CGMutablePath()
            let spikes = 14
            var rng = SplitMix64(seed: UInt64(word.rawValue.count * 977))
            for i in 0..<(spikes * 2) {
                let a = Double(i) / Double(spikes * 2) * 2 * .pi + 0.1
                let r = i % 2 == 0 ? Double.random(in: 0.82...0.95, using: &rng) : Double.random(in: 0.5...0.6, using: &rng)
                let p = CGPoint(x: cos(a) * r, y: sin(a) * r * 0.78)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            ExprPaint.glossy(ctx, path, word.burst, edgeWidth: 0.05, shadow: 0.35, shine: 0, rim: 0.3)
            ctx.saveGState()
            ctx.addPath(path); ctx.clip()
            ctx.setFillColor(exprColor((1, 1, 1), 0.22))
            for gx in stride(from: -1.0, through: 1.0, by: 0.09) {
                for gy in stride(from: -1.0, through: 1.0, by: 0.09) {
                    // Dots that grow toward the lower right: the printed shading of a comic.
                    let r = 0.012 + 0.022 * max(0, min(1, (gx - gy + 1.2) / 2.4))
                    let x = gx + (Int((gy + 1) / 0.09) % 2 == 0 ? 0 : 0.045)
                    ctx.fillEllipse(in: CGRect(x: x - r, y: gy - r, width: r * 2, height: r * 2))
                }
            }
            ctx.restoreGState()
        }
    }

    override func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        for p in pops {
            let inT = exprOutBack(min(1, p.age / 0.28), overshoot: 2.6)
            let outT = exprSmoothstep(Self.life - 0.35, Self.life, p.age)
            let scale = inT * (1 + 0.25 * outT)
            let alpha = 1 - outT
            let shake = p.age < 0.5 ? sin(p.age * 70) * 0.04 * (1 - p.age / 0.5) : 0
            let lift = outT * p.size * 0.25
            ctx.saveGState()
            ctx.translateBy(x: p.at.x, y: p.at.y + lift)
            ctx.rotate(by: p.tilt + shake)
            // Speed lines first, bursting outward.
            ctx.setLineCap(.round)
            ctx.setStrokeColor(exprColor(p.word.burst.light, 0.85 * alpha))
            ctx.setLineWidth(max(2, p.size * 0.016))
            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi + 0.13
                let r0 = p.size * 0.56 * scale, r1 = p.size * (0.68 + 0.08 * Double(i % 3)) * scale
                ctx.move(to: CGPoint(x: cos(a) * r0, y: sin(a) * r0 * 0.8)); ctx.addLine(to: CGPoint(x: cos(a) * r1, y: sin(a) * r1 * 0.8)); ctx.strokePath()
            }
            ctx.exprStamp(Self.burst(p.word), at: .zero, height: p.size * 1.15 * scale, alpha: alpha)
            let label = ExprType.label(p.word.rawValue, look: ExprType.comic)
            let fontSize = p.size * 0.19 * scale
            ctx.exprLabel(label, at: CGPoint(x: 0, y: -p.size * 0.02 * scale), fontSize: fontSize, alpha: alpha)
            ctx.restoreGState()
        }
    }
}
