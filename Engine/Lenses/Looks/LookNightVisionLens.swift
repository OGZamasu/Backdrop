import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Green night-vision video: bright phosphor, hissing grain, a dark rim where the infra-red light runs out,
/// and a camera display with a blinking red REC.
final class LookNightVisionLens: Lens {
    let needs: LensNeeds = []

    private static let phosphor: LookColour = (0.30, 1.0, 0.36)

    /// What the tube sees: brightness lifted hard out of the shadows, and skin of every colour bright, since skin throws
    /// infra-red light back strongly whatever its tone.
    private static let infrared = LookGrade(size: 24) { c in
        let lifted = powf(max(0, LookTone.luma(c)), 0.62)
        return SIMD3(repeating: min(1, lifted + 0.3 * LookTone.skinness(c) * (1 - lifted)))
    }

    private var clock: LookClock
    private let labels = LookDisplayCache()

    init(startDate: Date = Date()) { clock = LookClock(startDate: startDate) }

    func restart() { clock.restart(); labels.reset() }

    /// Whether the red REC dot is lit: on for a little over half of every second.
    static func recordDotIsLit(at time: Double) -> Bool {
        let beat = time - time.rounded(.down)
        return beat < 0.6
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let t = clock.elapsed(at: input.time)
        let frame = Int(t * 30)

        // An intensifier tube is soft and grainy, so the picture is worked at half size: cheaper, and the grain comes out chunkier.
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        let quarter = LookKit.size(of: rect, scaledBy: 0.25)

        // The tube lifts the shadows hard and clips the highlights.
        let gain = 1.0 + 0.04 * sin(t * 3.1) + 0.03 * sin(t * 11.3)
        let lifted = Self.infrared.apply(LookKit.shrink(input.composed, rect: rect, by: 0.5))
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.28, kCIInputBrightnessKey: -0.02])
        let strong = LookKit.levels(lifted, gain: gain)

        // Hot spots bloom.
        let bloom = LookKit.enlarge(LookKit.levels(LookKit.shrink(strong, rect: half, by: 0.5), gain: 2.4, bias: -1.45)
            .clampedToExtent().applyingGaussianBlur(sigma: 3).cropped(to: quarter), to: half, from: quarter)

        // Hiss: a screen of faint noise everywhere, and bright sparkles from the tube.
        let hiss = LookKit.noise(half, frame: frame, mean: 0.006, spread: 0.02)
        let phosphor = LookKit.tint(LookKit.screen(hiss, over: strong), by: Self.phosphor)
        let glowing = LookKit.screen(LookKit.tint(bloom, by: (0.55, 1.0, 0.6)), over: phosphor)

        // The infra-red lamp reaches the middle of the picture and gives out towards the edges.
        let lit = LookKit.multiply(LookKit.vignette(half, inner: 0.12, outer: 0.85, edge: LookKit.lin(0.12)), over: glowing)
        let sparkles = LookKit.speckle(half, frame: frame, coverage: 0.03, strength: 0.7, size: 1, colour: (0.7, 1, 0.75))
        let picture = LookKit.enlarge(sparkles.composited(over: lit), to: rect, from: half)

        // The display stays sharp: the labels are drawn once a second, the red dot and the frame counter as they change.
        var result = picture
        let second = Int(t)
        if let words = labels.layer(String(second), size: rect.size, draw: { ctx in self.drawLabels(ctx, rect: rect, time: t) }) {
            result = words.composited(over: result)
        }
        if let live = input.services.overlay({ ctx in self.drawLive(ctx, rect: rect, time: t) }) { result = live.composited(over: result) }
        return result.cropped(to: rect)
    }

    private static let ink = NSColor(red: 0.72, green: 1, blue: 0.78, alpha: 1)
    private static let glow = NSColor(red: 0.2, green: 1, blue: 0.3, alpha: 0.8)
    private static let margin: CGFloat = 64

    /// What only changes now and then: the corner marks, the words, the date and the battery.
    private func drawLabels(_ ctx: CGContext, rect: CGRect, time t: Double) {
        let ink = Self.ink, glow = Self.glow, margin = Self.margin
        LookKit.cornerMarks(in: ctx, rect: rect.insetBy(dx: 40, dy: 40), length: 46, width: 3, colour: ink.withAlphaComponent(0.8).cgColor)
        LookKit.text("REC", in: ctx, at: CGPoint(x: margin + 42, y: rect.maxY - margin - 30), size: 36, colour: ink, weight: .heavy, tracking: 3, glow: glow)
        let date = clock.date(after: t)
        LookKit.text("NIGHT VISION", in: ctx, at: CGPoint(x: margin, y: margin + 36), size: 26, colour: ink, weight: .bold, tracking: 4, glow: glow)
        LookKit.text(LookClock.day(date) + "  " + LookClock.time(date), in: ctx, at: CGPoint(x: margin, y: margin), size: 24, colour: ink, weight: .semibold, tracking: 1, glow: glow)

        // A battery that is mostly full.
        let cell = CGRect(x: rect.maxX - margin - 72, y: margin + 4, width: 66, height: 30)
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(3)
        ctx.stroke(cell)
        ctx.setFillColor(ink.cgColor)
        ctx.fill(CGRect(x: cell.maxX, y: cell.midY - 6, width: 6, height: 12))
        for bar in 0..<3 { ctx.fill(CGRect(x: cell.minX + 6 + CGFloat(bar) * 19, y: cell.minY + 6, width: 15, height: 18)) }
    }

    /// What changes every frame: the blinking dot and the counter.
    private func drawLive(_ ctx: CGContext, rect: CGRect, time t: Double) {
        let top = rect.maxY - Self.margin - 30
        if Self.recordDotIsLit(at: t) {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 14, color: CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 1))
            ctx.setFillColor(CGColor(red: 1, green: 0.12, blue: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: Self.margin, y: top + 6, width: 26, height: 26))
            ctx.restoreGState()
        }
        LookKit.text(LookClock.timecode(t), in: ctx, at: CGPoint(x: rect.maxX - Self.margin, y: top), size: 36, colour: Self.ink, weight: .bold, tracking: 2,
                     glow: Self.glow, anchor: .trailing)
    }
}
