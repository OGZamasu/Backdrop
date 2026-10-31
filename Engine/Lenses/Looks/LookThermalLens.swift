import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Where a thermal camera would aim its crosshair, and what it would read. Pure, so it can be tested.
enum LookThermalPlan {
    /// The warm spot to aim at: just inside the top of the head. Nil when nobody is in view.
    static func aim(in grid: MatteGrid) -> CGPoint? {
        guard grid.fraction > 0.01 else { return nil }
        var top: Int?
        search: for row in 0..<grid.height {
            for column in 0..<grid.width where grid.cells[row * grid.width + column] > 127 { top = row; break search }
        }
        guard let top else { return nil }
        // The head is the first stretch below the crown, about a hand's breadth.
        let rows = max(2, Int(110 / grid.cellSize))
        var sum = 0.0, count = 0.0
        for row in top..<min(grid.height, top + rows) {
            for column in 0..<grid.width where grid.cells[row * grid.width + column] > 127 { sum += Double(column) + 0.5; count += 1 }
        }
        guard count > 0 else { return nil }
        let y = (Double(grid.height - 1 - top) + 0.5) * grid.cellSize - 52
        return CGPoint(x: sum / count * grid.cellSize, y: y)
    }

    /// A skin temperature that wanders a little, in °C.
    static func reading(at time: Double) -> Double {
        36.5 + 0.35 * sin(time * 0.9) + 0.18 * sin(time * 2.7 + 1) + 0.07 * sin(time * 7.1)
    }

    /// The room's temperature, drifting very slowly.
    static func ambient(at time: Double) -> Double { 21.4 + 0.3 * sin(time * 0.17) }
}

/// A heat-camera view: you glow yellow and white, the room is cold blue and purple, with a crosshair and a temperature readout.
final class LookThermalLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    static let lowest = 20.0, highest = 40.0

    private static let rampStops: [(Double, LookColour)] = [
        (0.00, (0.01, 0.00, 0.08)), (0.16, (0.12, 0.00, 0.38)), (0.32, (0.42, 0.00, 0.55)), (0.48, (0.78, 0.08, 0.32)),
        (0.62, (0.97, 0.34, 0.05)), (0.78, (1.00, 0.74, 0.08)), (0.90, (1.00, 0.95, 0.50)), (1.00, (1.00, 1.00, 0.95)),
    ]
    private static let rampImage = LookKit.ramp(rampStops)
    private static let ramp = rampImage.map { CIImage(cgImage: $0) }

    /// How hot each colour reads, on the eye's scale: skin (by its hue, so every skin tone) runs hottest, brightness adds a little.
    private static let heat = LookGrade(size: 24) { c in
        let skin = LookTone.skinness(c)
        return SIMD3(repeating: 0.3 + 0.52 * skin + 0.18 * LookTone.luma(c))
    }

    private var clock = LookClock()
    private let labels = LookDisplayCache()
    private var aim: CGPoint?

    func restart() { clock.restart(); aim = nil; labels.reset() }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let t = clock.elapsed(at: input.time)
        guard let ramp = Self.ramp, let matte = input.matte else { return input.composed }

        // Thermal sensors are coarse and soft, so the whole picture is worked out at a quarter of the size.
        let small = LookKit.size(of: rect, scaledBy: 0.25)
        let shrunk = LookKit.shrink(input.composed, rect: rect, by: 0.25)
        let brightness = LookKit.perceptual(LookKit.grey(shrunk))
        let body = LookKit.shrink(matte, rect: rect, by: 0.25)
        let warm = body.clampedToExtent().applyingGaussianBlur(sigma: 1.6).cropped(to: small)

        // A body is warm all over and bare skin hottest of all, whatever its colour; hair and clothes run cooler. The room is
        // cool, with its lamps a little warmer, and warm air hangs just round you.
        let skin = Self.heat.apply(shrunk)
        let you = LookKit.levels(skin, gain: 0.62, bias: 0.36)
        let room = LookKit.levels(brightness, gain: 0.3, bias: 0.04)
        let haze = LookKit.levels(body.clampedToExtent().applyingGaussianBlur(sigma: 7).cropped(to: small), gain: 0.16)
        let picture0 = LookKit.screen(haze, over: LookKit.blend(you, over: room, mask: warm))
        // The sensor shimmers a little.
        let shimmer = LookKit.noise(small, frame: Int(t * 15), mean: 0.975, spread: 0.05)
        let heat = LookKit.multiply(shimmer, over: picture0)
        let picture = LookKit.enlarge(LookKit.colourise(heat, with: ramp), to: rect, from: small)

        // The scale and labels hardly change, so they are drawn only when the ambient reading does; the crosshair moves every frame.
        let ambient = String(format: "AMB %.1f°C", LookThermalPlan.ambient(at: t))
        var result = picture
        if let fixed = labels.layer(ambient, size: rect.size, draw: { ctx in self.drawLabels(ctx, rect: rect, ambient: ambient) }) { result = fixed.composited(over: result) }
        if let live = input.services.overlay({ ctx in self.drawCrosshair(ctx, rect: rect, time: t, dt: input.dt, grid: input.matteGrid) }) { result = live.composited(over: result) }
        return result.cropped(to: rect)
    }

    private func drawCrosshair(_ ctx: CGContext, rect: CGRect, time t: Double, dt: Double, grid: MatteGrid?) {
        let ink = NSColor.white
        let shadow = CGColor(gray: 0, alpha: 0.55)

        // The crosshair glides after the warmest spot.
        let spot = grid.flatMap { LookThermalPlan.aim(in: $0) }
        if let spot {
            let ease = 1 - exp(-dt * 7)
            aim = aim.map { CGPoint(x: $0.x + (spot.x - $0.x) * ease, y: $0.y + (spot.y - $0.y) * ease) } ?? spot
        }
        let at = aim ?? CGPoint(x: rect.midX, y: rect.midY)
        let reading = spot != nil ? LookThermalPlan.reading(at: t) : LookThermalPlan.ambient(at: t)
        for (colour, width) in [(shadow, CGFloat(6)), (ink.cgColor, CGFloat(2.5))] {
            ctx.setStrokeColor(colour)
            ctx.setLineWidth(width)
            ctx.strokeEllipse(in: CGRect(x: at.x - 30, y: at.y - 30, width: 60, height: 60))
            for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
                ctx.move(to: CGPoint(x: at.x + dx * 22, y: at.y + dy * 22))
                ctx.addLine(to: CGPoint(x: at.x + dx * 46, y: at.y + dy * 46))
            }
            ctx.strokePath()
        }
        LookKit.text(String(format: "%.1f°C", reading), in: ctx, at: CGPoint(x: at.x + 54, y: at.y - 10), size: 28, colour: ink, weight: .bold, glow: .black)
    }

    /// The colour scale down the right edge, the words and the corner marks.
    private func drawLabels(_ ctx: CGContext, rect: CGRect, ambient: String) {
        let ink = NSColor.white
        // Colour scale down the right edge.
        let bar = CGRect(x: rect.maxX - 96, y: 150, width: 20, height: rect.height - 300)
        if let image = Self.rampImage {
            ctx.saveGState()
            ctx.setStrokeColor(ink.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(bar.insetBy(dx: -1, dy: -1))
            ctx.translateBy(x: bar.minX, y: bar.minY)
            ctx.rotate(by: .pi / 2)
            ctx.draw(image, in: CGRect(x: 0, y: -bar.width, width: bar.height, height: bar.width))
            ctx.restoreGState()
        }
        for step in 0...4 {
            let f = Double(step) / 4
            let degrees = Self.lowest + (Self.highest - Self.lowest) * f
            LookKit.text(String(format: "%.0f°", degrees), in: ctx, at: CGPoint(x: bar.maxX + 10, y: bar.minY + bar.height * f - 9), size: 18, colour: ink, weight: .semibold, glow: .black)
        }

        LookKit.text("THERMAL", in: ctx, at: CGPoint(x: 56, y: rect.maxY - 78), size: 26, colour: ink, weight: .bold, tracking: 4, glow: .black)
        LookKit.text(ambient, in: ctx, at: CGPoint(x: 56, y: 52), size: 22, colour: ink, weight: .semibold, glow: .black)
        LookKit.cornerMarks(in: ctx, rect: rect.insetBy(dx: 36, dy: 36), length: 34, width: 3, colour: CGColor(gray: 1, alpha: 0.8))
    }
}
