import AppKit
import CoreGraphics
import CoreImage

/// A sci-fi face scanner: brackets snap onto your face, a scan line sweeps it, your eyes and mouth are marked, and a panel
/// beside you reads your mood and your smile, brows and mouth as live meters. The colours change with the mood.
final class ExprFaceScanLens: ExprOverlayLens {
    enum Mood: String, CaseIterable {
        case calm, happy, surprised, loud, asleep

        var label: String { rawValue.uppercased() }
        /// Each mood's accent colour, all from the neon set.
        var accent: ExprRGB {
            switch self {
            case .calm: return ExprPalette.neonCyan
            case .happy: return ExprPalette.neonLime
            case .surprised: return ExprPalette.neonAmber
            case .loud: return ExprPalette.neonPink
            case .asleep: return (0.72, 0.62, 1.0)
            }
        }
    }

    static let settle = 0.25
    /// The panel's size in pixels at 1280x720: fixed, so its words stay readable however far away you are.
    static let panelSize = CGSize(width: 232, height: 158)

    private(set) var mood = Mood.calm
    private var candidate = Mood.calm
    private var candidateFor = 0.0
    private var accent = ExprPalette.neonCyan
    private var lock = ExprSpring()
    private var meters = [0.0, 0.0, 0.0]
    private var side = 1.0
    private var panelSlide = ExprSpring(1)
    /// Where the readout panel was last drawn, in pixels.
    private(set) var panelFrame = CGRect.null

    override var hintText: String { "Hold still while it scans you" }

    override func restart() {
        super.restart()
        mood = .calm; candidate = .calm; candidateFor = 0; accent = ExprPalette.neonCyan; lock.reset(); meters = [0, 0, 0]; side = 1; panelSlide.reset(1)
    }

    static func mood(for f: FaceState, current: Mood) -> Mood {
        func over(_ v: Double, _ start: Double, _ stay: Double, _ m: Mood) -> Bool { v > (current == m ? stay : start) }
        if over(f.blink, 0.7, 0.5, .asleep) { return .asleep }
        if over(f.mouthOpen, 0.5, 0.3, .loud) && f.smile < 0.5 { return .loud }
        if over(f.browRaise, 0.55, 0.35, .surprised) { return .surprised }
        if over(f.smile, 0.5, 0.3, .happy) { return .happy }
        return .calm
    }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        lock.step(toward: face == nil ? 0 : 1, dt: dt, frequency: 1.8, damping: 0.55)
        guard let face else { return }
        let want = Self.mood(for: face, current: mood)
        if want == mood {
            candidate = mood; candidateFor = 0
        } else if want == candidate {
            candidateFor += dt
            if candidateFor >= Self.settle { mood = want; candidateFor = 0 }
        } else {
            candidate = want; candidateFor = dt
        }
        accent = exprMix(accent, mood.accent, 1 - exp(-dt / 0.15))
        for (i, v) in [face.smile, face.browRaise, face.mouthOpen].enumerated() { meters[i] = exprEase(meters[i], toward: v, dt: dt, tau: 0.12) }
        // The panel sits beside the face, on whichever side has room; it only moves over when it must.
        let fits = { (s: Double) -> Bool in
            let x = face.exprFaceCenter.x + s * (face.interocular * 1.6 + Self.panelSize.width * 0.5 + 12)
            return x - Self.panelSize.width / 2 > self.bounds.minX + self.bounds.width * 0.05 && x + Self.panelSize.width / 2 < self.bounds.maxX - self.bounds.width * 0.05
        }
        if !fits(side) && fits(-side) { side = -side }
        panelSlide.step(toward: side, dt: dt, frequency: 2, damping: 0.75)
    }

    override func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        guard let face else { return }
        let fade = presence.alpha
        let k = max(0, min(1.2, lock.value))
        ctx.setBlendMode(.plusLighter)
        ctx.inFaceSpace(face) {
            let spread = 1 + 0.7 * (1 - min(1, k))
            let box = CGRect(x: -1.3 * spread, y: -2.0 * spread - 0.2, width: 2.6 * spread, height: 3.55 * spread)
            drawBrackets(ctx, box: box, alpha: fade * min(1, k), io: face.interocular)
            if k > 0.6 { drawScan(ctx, box: box, time: time, alpha: fade * (k - 0.6) / 0.4) }
            // Landmarks: the eyes and mouth, joined.
            let marks = [CGPoint(x: -0.5, y: 0), CGPoint(x: 0.5, y: 0), CGPoint(x: 0, y: -0.95)]
            ctx.setStrokeColor(exprColor(accent, 0.45 * fade * min(1, k))); ctx.setLineWidth(max(0.012, 1.2 / face.interocular))
            ctx.move(to: marks[0]); ctx.addLine(to: marks[1]); ctx.addLine(to: marks[2]); ctx.closePath(); ctx.strokePath()
            for (i, m) in marks.enumerated() {
                let r = 0.09 + 0.02 * sin(time * 4 + Double(i))
                ctx.setStrokeColor(exprColor(accent, 0.9 * fade * min(1, k))); ctx.setLineWidth(max(0.02, 1.6 / face.interocular))
                ctx.strokeEllipse(in: CGRect(x: m.x - r, y: m.y - r, width: r * 2, height: r * 2))
            }
        }
        ctx.setBlendMode(.normal)
        drawPanel(ctx, face: face, time: time, alpha: fade * exprSmoothstep(0.5, 1, k))
    }

    private func drawBrackets(_ ctx: CGContext, box: CGRect, alpha: Double, io: Double) {
        let arm = 0.36
        let path = CGMutablePath()
        for (x, y, dx, dy) in [(box.minX, box.maxY, 1.0, -1.0), (box.maxX, box.maxY, -1.0, -1.0), (box.minX, box.minY, 1.0, 1.0), (box.maxX, box.minY, -1.0, 1.0)] {
            path.move(to: CGPoint(x: x + dx * arm, y: y)); path.addLine(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x, y: y + dy * arm))
        }
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let px = 1 / max(io, 1)
        // A dark edge under the line in ordinary blending, so the brackets read on a white wall too, then the light.
        ctx.setBlendMode(.normal)
        ctx.setStrokeColor(exprColor((0.02, 0.04, 0.08), 0.45 * alpha)); ctx.setLineWidth(6 * px)
        ctx.addPath(path); ctx.strokePath()
        ctx.setStrokeColor(exprColor(accent, alpha)); ctx.setLineWidth(3.2 * px)
        ctx.addPath(path); ctx.strokePath()
        ctx.setBlendMode(.plusLighter)
        ctx.setStrokeColor(exprColor(accent, 0.25 * alpha)); ctx.setLineWidth(10 * px)
        ctx.addPath(path); ctx.strokePath()
    }

    /// A bright line sweeping down the box with a fading wash behind it.
    private func drawScan(_ ctx: CGContext, box: CGRect, time: Double, alpha: Double) {
        let t = (time / 2.4).truncatingRemainder(dividingBy: 1)
        let y = box.maxY - box.height * exprSmoothstep(0, 1, t)
        let band = box.height * 0.18
        ctx.saveGState()
        ctx.clip(to: CGRect(x: box.minX, y: y, width: box.width, height: band))
        if let g = ExprShapes.gradient([(accent, 0), (accent, 1)], alphas: [0.35 * alpha, 0]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y), end: CGPoint(x: 0, y: y + band), options: [])
        }
        ctx.restoreGState()
        ctx.setStrokeColor(exprColor(accent, 0.9 * alpha)); ctx.setLineWidth(box.width * 0.008)
        ctx.move(to: CGPoint(x: box.minX + 0.08, y: y)); ctx.addLine(to: CGPoint(x: box.maxX - 0.08, y: y)); ctx.strokePath()
    }

    private func drawPanel(_ ctx: CGContext, face: FaceState, time: Double, alpha: Double) {
        guard alpha > 0.01 else { return }
        let size = Self.panelSize
        let raw = CGPoint(x: face.exprFaceCenter.x + panelSlide.value * (face.interocular * 1.6 + size.width * 0.5 + 12), y: face.eyeCenter.y)
        let c = face.exprKeepInside(raw, half: CGSize(width: size.width / 2, height: size.height / 2), in: bounds)
        let frame = CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
        panelFrame = frame
        ctx.saveGState()
        ctx.setAlpha(CGFloat(alpha))
        // Glass panel with a clipped corner.
        let cut = 16.0
        let panel = CGMutablePath()
        panel.move(to: CGPoint(x: frame.minX, y: frame.minY)); panel.addLine(to: CGPoint(x: frame.maxX - cut, y: frame.minY))
        panel.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + cut)); panel.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        panel.addLine(to: CGPoint(x: frame.minX + cut, y: frame.maxY)); panel.addLine(to: CGPoint(x: frame.minX, y: frame.maxY - cut)); panel.closeSubpath()
        ctx.setFillColor(exprColor((0.03, 0.06, 0.1), 0.9)); ctx.addPath(panel); ctx.fillPath()
        ctx.setStrokeColor(exprColor(accent, 0.85)); ctx.setLineWidth(1.6); ctx.addPath(panel); ctx.strokePath()

        let left = frame.minX + 16
        let blink = sin(time * 5) > 0 ? 1.0 : 0.35
        ctx.fillCircle(center: CGPoint(x: left + 4, y: frame.maxY - 22), radius: 4, color: exprColor(accent, blink))
        ExprHUDText.draw(ctx, "FACE SCAN", at: CGPoint(x: left + 16, y: frame.maxY - 22), size: 15, colour: (0.85, 0.95, 1.0), weight: .bold)
        ExprHUDText.draw(ctx, "MOOD", at: CGPoint(x: left, y: frame.maxY - 52), size: 14, colour: (0.6, 0.72, 0.8), weight: .semibold)
        ExprHUDText.draw(ctx, mood.label, at: CGPoint(x: left + 58, y: frame.maxY - 52), size: 20, colour: mood.accent, weight: .heavy)
        for (i, name) in ["SMILE", "BROWS", "MOUTH"].enumerated() {
            let y = frame.maxY - 84 - Double(i) * 24
            ExprHUDText.draw(ctx, name, at: CGPoint(x: left, y: y), size: 13, colour: (0.6, 0.72, 0.8), weight: .semibold)
            let bar = CGRect(x: left + 62, y: y - 5, width: size.width - 94, height: 10)
            ctx.setFillColor(exprColor((1, 1, 1), 0.12)); ctx.fill(bar)
            let v = max(0, min(1, meters[i]))
            ctx.setFillColor(exprColor(accent, 0.95)); ctx.fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width * v, height: bar.height))
            // Tick marks every tenth.
            ctx.setFillColor(exprColor((0.03, 0.06, 0.1), 0.6))
            for k in 1..<10 { ctx.fill(CGRect(x: bar.minX + bar.width * Double(k) / 10 - 0.5, y: bar.minY, width: 1, height: bar.height)) }
        }
        ctx.restoreGState()
    }
}

/// Small HUD words, baked once per word, size and colour, drawn left-aligned and centred on a line.
enum ExprHUDText {
    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]

    static func image(_ text: String, size: CGFloat, colour: ExprRGB, weight: NSFont.Weight) -> CGImage? {
        let key = "\(text)|\(Int(size))|\(Int(colour.r * 255)),\(Int(colour.g * 255)),\(Int(colour.b * 255))|\(weight.rawValue)"
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let scale = 2.0
        let font = ExprType.font(size: size * scale, weight: weight)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(srgbRed: colour.r, green: colour.g, blue: colour.b, alpha: 1),
                                                                         .kern: size * scale * 0.06])
        let box = attributed.size()
        let width = Int(ceil(box.width)) + 4, height = Int(ceil(box.height)) + 4
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        attributed.draw(at: NSPoint(x: 2, y: 2))
        NSGraphicsContext.restoreGraphicsState()
        guard let made = ctx.makeImage() else { return nil }
        if cache.count > 80 { cache.removeAll() }
        cache[key] = made
        return made
    }

    /// Draws `text` with its left end at `at.x` and its middle on `at.y`.
    static func draw(_ ctx: CGContext, _ text: String, at: CGPoint, size: CGFloat, colour: ExprRGB, weight: NSFont.Weight) {
        guard let image = image(text, size: size, colour: colour, weight: weight) else { return }
        let w = Double(image.width) / 2, h = Double(image.height) / 2
        ctx.draw(image, in: CGRect(x: at.x - 2, y: at.y - h / 2, width: w, height: h))
    }
}
