import CoreGraphics
import Foundation
import simd

/// Who lives on the ice.
enum VistaArcticCast {
    static let bear = 0, penguin = 1, seal = 2, fox = 3, owl = 4, narwhal = 5

    static var cast: VistaCast {
        var layout = VistaLayout()
        layout.farGround = 318
        layout.nearGround = 84
        layout.roamLow = 400
        layout.roamHigh = 640

        var polar = VistaSpecies(name: "polar bear", art: bear, height: 230, aspect: 1.55, speed: 62)
        polar.temper = .brute
        polar.home = 0.22
        polar.charge = 1.7
        polar.actSeconds = 3.0
        polar.actReach = 1.55
        polar.cry = "ROAR!"
        polar.cryAt = 0.85
        polar.beats = [VistaBeat(at: 0.85, event: .shake(4)), VistaBeat(at: 0.2, event: .burst(.snow, 6, 0.7)), VistaBeat(at: 2.75, event: .burst(.snow, 12, 1.1))]
        polar.emitters = [VistaEmitter(kind: .smoke, from: 0.85, to: 1.9, rate: 16, at: SIMD2(0.42, 1.38), velocity: SIMD2(150, 30), spread: 30)]

        var pen = VistaSpecies(name: "penguin", art: penguin, height: 118, aspect: 0.62, speed: 46)
        pen.gait = .waddle
        pen.slides = true
        pen.temper = .prey
        pen.home = 0.26
        pen.charge = 1.2
        pen.actSeconds = 2.4
        pen.cry = "HONK!"
        pen.cryAt = 0.4
        pen.beats = [VistaBeat(at: 0.3, event: .jump(300)), VistaBeat(at: 1.0, event: .jump(300)), VistaBeat(at: 1.4, event: .burst(.snow, 4, 0.5))]

        var harbor = VistaSpecies(name: "seal", art: seal, height: 100, aspect: 1.8, speed: 36)
        harbor.home = 0.3
        harbor.actSeconds = 2.8
        harbor.cry = "ARF ARF!"
        harbor.cryAt = 0.6
        harbor.actReach = 1.15
        harbor.beats = [VistaBeat(at: 0.25, event: .burst(.snow, 4, 0.5)), VistaBeat(at: 0.7, event: .burst(.sparkle, 3, 0.4))]

        var arctic = VistaSpecies(name: "arctic fox", art: fox, height: 112, aspect: 1.5, speed: 118)
        arctic.temper = .prey
        arctic.stalks = true
        arctic.home = 0.17
        arctic.charge = 1.8
        arctic.actSeconds = 2.3
        arctic.cry = "YIP!"
        arctic.cryAt = 1.5
        arctic.beats = [VistaBeat(at: 0.55, event: .jump(640)), VistaBeat(at: 1.38, event: .burst(.snow, 14, 1.2))]

        var snowy = VistaSpecies(name: "snowy owl", art: owl, height: 96, aspect: 0.9, speed: 150)
        snowy.body = .flier
        snowy.act = .perch
        snowy.temper = .prey
        snowy.perchesOnHand = true
        snowy.home = 0.3
        snowy.interest = 0.9
        snowy.cry = "HOO HOO!"
        snowy.band = 430...630

        var whale = VistaSpecies(name: "narwhal", art: narwhal, height: 280, aspect: 0.6, speed: 56)
        // Under the water it swims over to you quickly; you only see the ripples.
        whale.charge = 3.5
        whale.body = .emerger
        whale.farOnly = true
        whale.temper = .steady
        whale.home = 0.03
        whale.interest = 0.8
        whale.actSeconds = 3.6
        whale.cry = "PFFT!"
        whale.cryAt = 1.2
        whale.emitters = [VistaEmitter(kind: .splash, from: 1.15, to: 1.6, rate: 70, at: SIMD2(0.02, 0.84), velocity: SIMD2(0, 470), spread: 80)]

        return VistaCast(species: [polar, pen, harbor, arctic, snowy, whale], roster: [0, 1, 1, 1, 2, 3, 4, 5], layout: layout, cap: 9, visibleAtStart: 6)
    }
}

/// A polar night on the ice shelf: the northern lights rippling over snowy peaks, a dark sea with icebergs, falling snow, and the
/// creatures of the ice coming over to see you.
final class VistaArcticStage: VistaStage {
    let cast = VistaArcticCast.cast
    let hint = "Wave to scatter them, or hold up a hand for the owl"
    let accent: UInt32 = 0x3E9CC4
    let fx = VistaFXColors(dust: 0xE6F2FF, snow: 0xF4FAFF, sparkle: 0xB8FFEA, ember: 0xFFC27A, smoke: 0xE4EEFA, water: 0xD8F0FF,
                           notes: [0x9BFFE4, 0xC8B4FF], heart: 0xFF8FB0)
    let haze: UInt32 = 0x8FA9D6
    let hazeAmount = 0.24

    /// The palette of the place, named.
    private enum Ice {
        static let night: UInt32 = 0x070B22
        static let aurora: UInt32 = 0x7DFFC4
        static let auroraHigh: UInt32 = 0xB28CFF
        static let moon: UInt32 = 0xF2F7FF
        static let snowLit: UInt32 = 0xDCEAF6
        static let snowShade: UInt32 = 0x7F9DC8
        static let sea: UInt32 = 0x123A5A
        static let iceLit: UInt32 = 0xF2FAFF
        static let iceShade: UInt32 = 0x86A8D2
    }
    private let ink = VistaInkStyle(rim: 0x9BFFE4, rimAmount: 0.5, line: 1.8, ink: 0.55, gloss: 0.18)

    private enum Tone {
        static let bear = VistaTone(0xFFFFFF, 0xE8EEF3, 0x96A9C3)
        static let bearFar = VistaTone(0xD3DDE9, 0xBCC9D9, 0x7E91AE)
        static let penguin = VistaTone(0x4A5370, 0x252C40, 0x0F121C)
        static let seal = VistaTone(0xD0D8E2, 0x9DA9BA, 0x5B6780)
        static let fox = VistaTone(0xFFFFFF, 0xEEF2F6, 0xA0B0C6)
        static let foxFar = VistaTone(0xD8E0EA, 0xC4CFDC, 0x8495AE)
        static let owl = VistaTone(0xFFFFFF, 0xF0F3F7, 0xA9B5C7)
        static let narwhal = VistaTone(0xD4DEE9, 0x9BABC1, 0x55637D)
        static let tusk = VistaTone(0xFFF8E4, 0xEADFC2, 0xA99E80)
    }

    private var painting: VistaPainting?
    private var backdrop: VistaLayer?
    private var drifts: [VistaLayer] = []
    private var streak: CGImage?
    private var figures: [VistaFigure?]

    init() { figures = Array(repeating: nil, count: cast.species.count) }

    // MARK: Painting, in steps

    var backdropSteps: Int { 4 }
    var bakeSteps: Int { 5 + cast.species.count }

    func bake(step: Int) {
        switch step {
        case 0:
            painting = VistaPainting(CGRect(x: -48, y: 0, width: 1376, height: 720))
            painting?.paint { ctx in paintSky(ctx) }
        case 1:
            painting?.paint { ctx in paintAurora(ctx) }
        case 2:
            painting?.paint { ctx in
                paintMountains(ctx)
                paintSea(ctx)
            }
        case 3:
            painting?.paint { ctx in
                paintShelf(ctx)
                paintVignette(ctx)
            }
            backdrop = painting?.finish(parallax: 12)
            painting = nil
        case 4:
            drifts = paintDrifts()
            streak = VistaInk.picture(width: 18, height: 170) { ctx in
                VistaInk.fill(ctx, CGRect(x: 0, y: 0, width: 18, height: 170), [(0, VistaInk.color(Ice.auroraHigh, 0)), (0.6, VistaInk.color(0xA8FFE0, 0.3)), (1, VistaInk.color(0xD8FFF0, 0.7))],
                              from: CGPoint(x: 0, y: 170), to: CGPoint(x: 0, y: 0))
                // Soft at the sides.
                ctx.setBlendMode(.destinationIn)
                VistaInk.fill(ctx, CGRect(x: 0, y: 0, width: 18, height: 170), [(0, VistaInk.color(0xFFFFFF, 0)), (0.5, VistaInk.color(0xFFFFFF, 1)), (1, VistaInk.color(0xFFFFFF, 0))],
                              from: CGPoint(x: 0, y: 0), to: CGPoint(x: 18, y: 0))
            }
        default:
            let i = step - 5
            guard figures.indices.contains(i) else { return }
            let sp = cast.species[i]
            let u = sp.height * cast.layout.scale(sp.farOnly ? min(1, sp.home + 0.06) : 1)
            let parts: [VistaPart?]
            switch sp.art {
            case VistaArcticCast.bear: parts = bakeBear(u)
            case VistaArcticCast.penguin: parts = bakePenguin(u)
            case VistaArcticCast.seal: parts = bakeSeal(u)
            case VistaArcticCast.fox: parts = bakeFox(u)
            case VistaArcticCast.owl: parts = bakeOwl(u)
            default: parts = bakeNarwhal(u)
            }
            figures[i] = VistaFigure(parts, haze: haze, amount: hazeAmount)
        }
    }

    func isReady(species: Int) -> Bool { figures.indices.contains(species) && figures[species] != nil }

    // MARK: The world

    private func paintSky(_ ctx: CGContext) {
        let rect = CGRect(x: -48, y: 300, width: 1376, height: 420)
        VistaInk.fillDown(ctx, rect, [(0, VistaInk.color(Ice.night)), (0.3, VistaInk.color(0x0E1A44)), (0.58, VistaInk.color(0x163C66)),
                                      (0.8, VistaInk.color(0x2A6886)), (0.93, VistaInk.color(0x5FA8B8)), (1, VistaInk.color(0x9AD6D4))])
        var rng = VistaInk.generator(17)
        for _ in 0..<170 {
            let p = CGPoint(x: rng.range(-48, 1328), y: rng.range(430, 720))
            let r = rng.range(0.5, 1.3)
            ctx.setFillColor(VistaInk.color(0xFFFFFF, rng.range(0.25, 0.85)))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        for _ in 0..<10 {
            let p = CGPoint(x: rng.range(0, 1280), y: rng.range(500, 710))
            VistaInk.blob(ctx, p, rx: 7, ry: 7, VistaInk.color(0xCFE6FF, 0.5))
            ctx.setFillColor(VistaInk.color(0xFFFFFF))
            ctx.fillEllipse(in: CGRect(x: p.x - 1.4, y: p.y - 1.4, width: 2.8, height: 2.8))
        }
        // The aurora's standing glow, under the moving curtains.
        for i in 0..<9 {
            let x = 120 + Double(i) * 140
            VistaInk.blob(ctx, CGPoint(x: x, y: 520 + 40 * sin(Double(i) * 0.9)), rx: 220, ry: 90, VistaInk.color(Ice.aurora, 0.07))
        }
        // The moon, high on the left: the light everything here is lit by.
        let moon = CGPoint(x: 205, y: 610)
        VistaInk.blob(ctx, moon, rx: 300, ry: 220, VistaInk.color(0x9CC4FF, 0.16))
        VistaInk.blob(ctx, moon, rx: 90, ry: 90, VistaInk.color(0xDCEBFF, 0.4))
        VistaInk.oval(ctx, moon, rx: 31, ry: 31, VistaInk.color(Ice.moon))
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: moon.x - 31, y: moon.y - 31, width: 62, height: 62))
        ctx.clip()
        for (dx, dy, r) in [(-9.0, 8.0, 7.0), (10.0, -6.0, 5.0), (4.0, 14.0, 3.5), (-12.0, -11.0, 4.0)] {
            VistaInk.blob(ctx, CGPoint(x: moon.x + dx, y: moon.y + dy), rx: r, ry: r, VistaInk.color(0xB8C6DE, 0.55), inner: 0.4)
        }
        VistaInk.blob(ctx, CGPoint(x: moon.x + 22, y: moon.y - 18), rx: 40, ry: 40, VistaInk.color(0x9DB0D2, 0.35))
        ctx.restoreGState()
    }

    /// Two ranges of snowy peaks, faceted: lit on the left where the moon is, in blue shade on the right.
    private func paintMountains(_ ctx: CGContext) {
        func range(seed: UInt64, base: Double, high: Double, count: Int, lit: UInt32, shade: UInt32, snowLine: Double) {
            var rng = VistaInk.generator(seed)
            var peaks: [CGPoint] = []
            let step = 1420.0 / Double(count)
            for i in 0...count {
                let x = -70 + Double(i) * step + rng.range(-step * 0.25, step * 0.25)
                peaks.append(CGPoint(x: x, y: base + rng.range(high * 0.45, high)))
                peaks.append(CGPoint(x: x + step * rng.range(0.42, 0.58), y: base + rng.range(high * 0.05, high * 0.3)))
            }
            let outline = CGMutablePath()
            outline.move(to: CGPoint(x: -70, y: base - 40))
            for p in peaks { outline.addLine(to: p) }
            outline.addLine(to: CGPoint(x: 1400, y: base - 40))
            outline.closeSubpath()
            VistaInk.fill(ctx, outline, [(0, VistaInk.color(lit)), (1, VistaInk.color(VistaInk.mixHex(lit, shade, 0.7)))],
                          from: CGPoint(x: 0, y: base + high), to: CGPoint(x: 0, y: base - 40))
            // The shaded faces: from each peak down its right side.
            for i in stride(from: 0, to: peaks.count - 2, by: 2) {
                let top = peaks[i], valley = peaks[i + 1]
                let face = CGMutablePath()
                face.move(to: top)
                face.addLine(to: valley)
                face.addLine(to: CGPoint(x: valley.x - (valley.x - top.x) * 0.15, y: base - 40))
                face.addLine(to: CGPoint(x: top.x + (valley.x - top.x) * 0.08, y: base - 40))
                face.closeSubpath()
                ctx.saveGState()
                ctx.addPath(outline)
                ctx.clip()
                VistaInk.fill(ctx, face, [(0, VistaInk.color(shade, 0.85)), (1, VistaInk.color(shade, 0.35))], from: top, to: CGPoint(x: top.x, y: base - 40))
                ctx.restoreGState()
                // A rim of aurora light along the ridge.
                ctx.setStrokeColor(VistaInk.color(Ice.aurora, 0.28))
                ctx.setLineWidth(1.4)
                ctx.move(to: CGPoint(x: top.x - (top.x - (i > 0 ? peaks[i - 1].x : top.x - 60)) * 0.5, y: top.y - (top.y - (i > 0 ? peaks[i - 1].y : top.y)) * 0.5))
                ctx.addLine(to: top)
                ctx.strokePath()
            }
            // The snow line: below it the rock shows through, faintly.
            ctx.saveGState()
            ctx.addPath(outline)
            ctx.clip()
            VistaInk.fill(ctx, CGRect(x: -70, y: base - 40, width: 1480, height: snowLine), [(0, VistaInk.color(0x2A3E66, 0)), (1, VistaInk.color(0x2A3E66, 0.35))],
                          from: CGPoint(x: 0, y: base - 40 + snowLine), to: CGPoint(x: 0, y: base - 40))
            ctx.restoreGState()
        }
        range(seed: 4, base: 350, high: 150, count: 7, lit: 0xB8CDE8, shade: 0x5C77A8, snowLine: 50)
        // Haze between the ranges.
        VistaInk.fill(ctx, CGRect(x: -48, y: 320, width: 1376, height: 90), [(0, VistaInk.color(0x9AD6D4, 0)), (1, VistaInk.color(0x8CC6CC, 0.55))],
                      from: CGPoint(x: 0, y: 410), to: CGPoint(x: 0, y: 330))
        range(seed: 9, base: 330, high: 90, count: 9, lit: 0xDDEBF8, shade: 0x7491C0, snowLine: 30)
        VistaInk.fill(ctx, CGRect(x: -48, y: 300, width: 1376, height: 60), [(0, VistaInk.color(0x9AD6D4, 0)), (1, VistaInk.color(0xA6DCD8, 0.6))],
                      from: CGPoint(x: 0, y: 360), to: CGPoint(x: 0, y: 312))
    }

    private func paintSea(_ ctx: CGContext) {
        let top = 334.0, bottom = 298.0
        VistaInk.fillDown(ctx, CGRect(x: -48, y: bottom, width: 1376, height: top - bottom),
                          [(0, VistaInk.color(0x6FAFBF)), (0.25, VistaInk.color(0x2D6A88)), (1, VistaInk.color(Ice.sea))])
        var rng = VistaInk.generator(23)
        // The aurora and the moon in the water.
        for i in 0..<14 {
            let x = rng.range(-40, 1320)
            VistaInk.blob(ctx, CGPoint(x: x, y: top - 12), rx: rng.range(8, 22), ry: 14, VistaInk.color(i % 3 == 0 ? 0x8CF0FF : Ice.aurora, 0.18))
        }
        VistaInk.blob(ctx, CGPoint(x: 205, y: top - 14), rx: 26, ry: 16, VistaInk.color(0xEAF2FF, 0.5))
        ctx.setStrokeColor(VistaInk.color(0xEAF6FF, 0.5))
        ctx.setLineWidth(1.2)
        for _ in 0..<40 {
            let y = rng.range(bottom + 4, top - 3)
            let x = rng.range(-40, 1320), w = rng.range(6, 30) * (y - bottom) / (top - bottom) + 4
            ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + w, y: y)); ctx.strokePath()
        }
        // Icebergs out on the water.
        iceberg(ctx, x: 150, base: 318, width: 190, height: 96, seed: 2)
        iceberg(ctx, x: 1150, base: 322, width: 140, height: 70, seed: 5)
        iceberg(ctx, x: 760, base: 328, width: 70, height: 26, seed: 7)
        // Floes.
        for _ in 0..<9 {
            let x = rng.range(-20, 1300), y = rng.range(bottom + 6, top - 8)
            let w = rng.range(30, 90) * (0.4 + 0.6 * (top - y) / (top - bottom))
            let floe = VistaInk.smooth([(x - w / 2, y), (x - w * 0.3, y + 4), (x + w * 0.35, y + 3.5), (x + w / 2, y - 0.5), (x + w * 0.2, y - 3), (x - w * 0.4, y - 2.5)])
            ctx.addPath(floe)
            ctx.setFillColor(VistaInk.color(0xC6DDF0))
            ctx.fillPath()
            ctx.setFillColor(VistaInk.color(0xF4FAFF))
            ctx.fill(CGRect(x: x - w * 0.42, y: y + 0.5, width: w * 0.8, height: 2.6))
        }
    }

    private func iceberg(_ ctx: CGContext, x: Double, base: Double, width: Double, height: Double, seed: UInt64) {
        var rng = VistaInk.generator(seed)
        var pts: [CGPoint] = [CGPoint(x: x - width / 2, y: base)]
        let n = 6
        for i in 1..<n {
            let k = Double(i) / Double(n)
            let hump = sin(k * .pi)
            pts.append(CGPoint(x: x - width / 2 + width * k + rng.range(-8, 8), y: base + height * (0.35 + 0.65 * hump) * rng.range(0.7, 1.05)))
        }
        pts.append(CGPoint(x: x + width / 2, y: base))
        let outline = CGMutablePath()
        outline.addLines(between: pts)
        outline.closeSubpath()
        VistaInk.fill(ctx, outline, [(0, VistaInk.color(Ice.iceLit)), (1, VistaInk.color(0xB8D2EC))], from: CGPoint(x: x - width / 2, y: base + height), to: CGPoint(x: x + width / 2, y: base))
        // Facets in shade on the right of each crest.
        ctx.saveGState()
        ctx.addPath(outline)
        ctx.clip()
        for i in 1..<(pts.count - 1) where i % 2 == 1 {
            let face = CGMutablePath()
            face.move(to: pts[i])
            face.addLine(to: pts[i + 1])
            face.addLine(to: CGPoint(x: pts[i + 1].x, y: base))
            face.addLine(to: CGPoint(x: pts[i].x + 6, y: base))
            face.closeSubpath()
            ctx.addPath(face)
            ctx.setFillColor(VistaInk.color(Ice.iceShade, 0.75))
            ctx.fillPath()
        }
        VistaInk.blob(ctx, CGPoint(x: x + width * 0.3, y: base + height * 0.2), rx: width * 0.4, ry: height * 0.5, VistaInk.color(0x5E82B4, 0.35))
        ctx.restoreGState()
        ctx.addPath(outline)
        ctx.setStrokeColor(VistaInk.color(0x5F80AE, 0.6))
        ctx.setLineWidth(1)
        ctx.strokePath()
        // Its reflection, and the foam at the water line.
        VistaInk.blob(ctx, CGPoint(x: x, y: base - 6), rx: width * 0.5, ry: 6, VistaInk.color(0xBFE0F0, 0.3))
        ctx.setFillColor(VistaInk.color(0xFFFFFF, 0.7))
        ctx.fill(CGRect(x: x - width * 0.48, y: base - 1, width: width * 0.96, height: 1.6))
    }

    /// The ice shelf: blue snow in moonlight, drifts and wind ridges, a lip of ice at the far edge, a jumble of pressure ice on the right.
    private func paintShelf(_ ctx: CGContext) {
        let edge = 300.0
        let shelf = VistaInk.ridge(left: -48, width: 1376, base: edge, bottom: 0, amplitude: 4, wavelength: 140, seed: 13)
        VistaInk.fill(ctx, shelf, [(0, VistaInk.color(0xE4F0FA)), (0.25, VistaInk.color(0xC7DCEE)), (0.6, VistaInk.color(0xA3BEDC)), (1, VistaInk.color(0x7D99C4))],
                      from: CGPoint(x: 0, y: edge), to: CGPoint(x: 0, y: 0))
        ctx.saveGState()
        ctx.addPath(shelf)
        ctx.clip()
        // Moonlight from the upper left.
        VistaInk.blob(ctx, CGPoint(x: 260, y: 230), rx: 700, ry: 160, VistaInk.color(0xF2F8FF, 0.35))
        var rng = VistaInk.generator(29)
        // Drifts in perspective: long soft mounds, lit on top, shaded below.
        for _ in 0..<26 {
            let t = rng.unit()
            let y = edge - 14 - pow(t, 1.4) * (edge - 20)
            let s = 0.3 + 1.3 * pow(t, 1.3)
            let x = rng.range(-60, 1340)
            let w = rng.range(90, 220) * s, h = rng.range(5, 12) * s
            VistaInk.blob(ctx, CGPoint(x: x, y: y - h * 0.6), rx: w, ry: h, VistaInk.color(Ice.snowShade, 0.28))
            VistaInk.blob(ctx, CGPoint(x: x - w * 0.1, y: y), rx: w * 0.85, ry: h * 0.8, VistaInk.color(0xF4FAFF, 0.4))
        }
        // Wind ridges.
        ctx.setLineCap(.round)
        for _ in 0..<60 {
            let t = rng.unit()
            let y = edge - 10 - pow(t, 1.3) * (edge - 14)
            let s = 0.3 + 1.2 * t
            let x = rng.range(-40, 1320), w = rng.range(30, 90) * s
            ctx.setStrokeColor(VistaInk.color(rng.chance(0.5) ? 0x8DA9D2 : 0xFFFFFF, rng.range(0.15, 0.35)))
            ctx.setLineWidth(CGFloat(max(0.8, 1.6 * s)))
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addQuadCurve(to: CGPoint(x: x + w, y: y + rng.range(-3, 3) * s), control: CGPoint(x: x + w * 0.5, y: y + 3 * s))
            ctx.strokePath()
        }
        // Glints.
        for _ in 0..<160 {
            let t = rng.unit()
            let y = edge - 6 - t * (edge - 8)
            let r = 0.5 + 1.2 * t
            ctx.setFillColor(VistaInk.color(0xFFFFFF, rng.range(0.4, 0.9)))
            ctx.fillEllipse(in: CGRect(x: rng.range(-40, 1320), y: y, width: r, height: r))
        }
        ctx.restoreGState()
        // The lip at the far edge, catching the light.
        ctx.setStrokeColor(VistaInk.color(0xFFFFFF, 0.7))
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: -48, y: edge + 1))
        var x = -48.0
        while x <= 1336 { ctx.addLine(to: CGPoint(x: x, y: VistaInk.ridgeHeight(at: x, left: -48, base: edge, amplitude: 4, wavelength: 140, seed: 13) + 1)); x += 16 }
        ctx.strokePath()
        // Pressure ice: tilted slabs on the right.
        var slabs = VistaInk.generator(41)
        for i in 0..<9 {
            let cx = 930 + Double(i) * 42 + slabs.range(-14, 14), base = 262 + slabs.range(-8, 10)
            let w = slabs.range(34, 62), h = slabs.range(26, 58), lean = slabs.range(-0.5, 0.5)
            let top = CGPoint(x: cx + lean * 20, y: base + h)
            let slab = CGMutablePath()
            slab.move(to: CGPoint(x: cx - w / 2, y: base))
            slab.addLine(to: CGPoint(x: top.x - w * 0.3, y: top.y - 4))
            slab.addLine(to: CGPoint(x: top.x + w * 0.2, y: top.y))
            slab.addLine(to: CGPoint(x: cx + w / 2, y: base))
            slab.closeSubpath()
            VistaInk.fill(ctx, slab, [(0, VistaInk.color(0xF4FBFF)), (0.6, VistaInk.color(0xB4CEEA)), (1, VistaInk.color(0x6E8DBE))],
                          from: CGPoint(x: cx - w / 2, y: top.y), to: CGPoint(x: cx + w / 2, y: base))
            ctx.addPath(slab)
            ctx.setStrokeColor(VistaInk.color(0x5873A2, 0.55))
            ctx.setLineWidth(1)
            ctx.strokePath()
            if i % 3 == 0 { VistaInk.blob(ctx, CGPoint(x: cx, y: base), rx: w * 0.9, ry: 6, VistaInk.color(0xF4FAFF, 0.6)) }
        }
    }

    private func paintVignette(_ ctx: CGContext) {
        let g = VistaInk.gradient([(0, VistaInk.color(0x050A1E, 0)), (0.62, VistaInk.color(0x050A1E, 0)), (1, VistaInk.color(0x050A1E, 0.5))])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 380), startRadius: 0, endCenter: CGPoint(x: 640, y: 380), endRadius: 820, options: [.drawsAfterEndLocation])
    }

    /// The curtains of the northern lights: where each one's bright hem runs, so that the moving glints can follow it.
    private static let curtains: [(seed: Double, base: Double, reach: Double, tint: UInt32)] = [(3, 515, 150, 0x7DFFC4), (8, 590, 105, 0x8CF0FF)]

    private static func hem(_ i: Int, _ x: Double) -> Double {
        let c = curtains[i]
        return c.base + 42 * sin(x / 640 * 2 * .pi + c.seed) + 18 * sin(x / 270 * 2 * .pi + c.seed * 2.1) + 6 * sin(x / 95 * 2 * .pi + c.seed * 3.3)
    }

    /// The northern lights: broad folded curtains with a bright hem, rays rising from it and fading into violet.
    private func paintAurora(_ ctx: CGContext) {
        for (i, c) in Self.curtains.enumerated() {
            var rng = VistaInk.generator(UInt64(c.seed) * 7)
            func reach(_ x: Double) -> Double { c.reach * (0.7 + 0.5 * VistaInk.noise(x / 110, c.seed) + 0.25 * VistaInk.noise(x / 31, c.seed + 4)) }
            // The glow above the hem.
            let band = CGMutablePath()
            band.move(to: CGPoint(x: -60, y: Self.hem(i, -60)))
            var x = -60.0
            while x <= 1340 { band.addLine(to: CGPoint(x: x, y: Self.hem(i, x))); x += 10 }
            x = 1340
            while x >= -60 { band.addLine(to: CGPoint(x: x, y: Self.hem(i, x) + reach(x))); x -= 10 }
            band.closeSubpath()
            VistaInk.fill(ctx, band, [(0, VistaInk.color(Ice.auroraHigh, 0)), (0.55, VistaInk.color(Ice.auroraHigh, 0.1)), (0.85, VistaInk.color(c.tint, 0.2)), (1, VistaInk.color(c.tint, 0.3))],
                          from: CGPoint(x: 0, y: c.base + c.reach * 1.2), to: CGPoint(x: 0, y: c.base - 50))
            // Rays: bright at the hem, fading as they rise.
            ctx.setLineCap(.butt)
            x = -60
            while x < 1340 {
                let y0 = Self.hem(i, x), r = reach(x) * rng.range(0.6, 1.1)
                let strength = 0.04 + 0.1 * VistaInk.noise(x / 18, c.seed + 2)
                ctx.setLineWidth(CGFloat(rng.range(1.5, 4)))
                for (k, (from, to)) in [(0.0, 0.3), (0.3, 0.65), (0.65, 1.0)].enumerated() {
                    ctx.setStrokeColor(VistaInk.mix(VistaInk.mixHex(c.tint, 0xFFFFFF, 0.25), Ice.auroraHigh, Double(k) * 0.45, alpha: strength * [1.4, 0.7, 0.2][k]))
                    ctx.move(to: CGPoint(x: x + from * 4, y: y0 + r * from))
                    ctx.addLine(to: CGPoint(x: x + to * 4, y: y0 + r * to))
                    ctx.strokePath()
                }
                x += rng.range(2.5, 6)
            }
            // The hem itself, softly bright.
            for (width, alpha) in [(22.0, 0.05), (9.0, 0.12), (3.0, 0.4)] {
                ctx.setStrokeColor(VistaInk.color(VistaInk.mixHex(c.tint, 0xFFFFFF, 0.4), alpha))
                ctx.setLineWidth(CGFloat(width))
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: -60, y: Self.hem(i, -60)))
                x = -60
                while x <= 1340 { ctx.addLine(to: CGPoint(x: x, y: Self.hem(i, x))); x += 8 }
                ctx.strokePath()
            }
        }
    }

    /// Snow banked in the bottom corners, in front of everything.
    private func paintDrifts() -> [VistaLayer] {
        func drift(_ rect: CGRect, flip: Bool, seed: UInt64) -> VistaLayer? {
            VistaInk.layer(rect, parallax: 40) { ctx in
                var rng = VistaInk.generator(seed)
                let x0 = Double(rect.minX), w = Double(rect.width)
                let edgeX = flip ? x0 + w : x0
                let dir = flip ? -1.0 : 1.0
                let mound = CGMutablePath()
                mound.move(to: CGPoint(x: edgeX, y: -2))
                mound.addLine(to: CGPoint(x: edgeX, y: 120))
                mound.addCurve(to: CGPoint(x: edgeX + dir * w * 0.62, y: 34), control1: CGPoint(x: edgeX + dir * w * 0.25, y: 128), control2: CGPoint(x: edgeX + dir * w * 0.4, y: 56))
                mound.addCurve(to: CGPoint(x: edgeX + dir * w, y: -2), control1: CGPoint(x: edgeX + dir * w * 0.8, y: 18), control2: CGPoint(x: edgeX + dir * w * 0.92, y: 6))
                mound.closeSubpath()
                VistaInk.fill(ctx, mound, [(0, VistaInk.color(0xF6FBFF)), (0.5, VistaInk.color(0xC6D9EE)), (1, VistaInk.color(0x7E9AC8))],
                              from: CGPoint(x: edgeX, y: 130), to: CGPoint(x: edgeX + dir * w * 0.6, y: 0))
                ctx.saveGState()
                ctx.addPath(mound)
                ctx.clip()
                VistaInk.blob(ctx, CGPoint(x: edgeX + dir * w * 0.2, y: 110), rx: w * 0.4, ry: 22, VistaInk.color(0xFFFFFF, 0.8))
                VistaInk.blob(ctx, CGPoint(x: edgeX + dir * w * 0.5, y: 10), rx: w * 0.5, ry: 30, VistaInk.color(0x6683B6, 0.4))
                for _ in 0..<40 {
                    let p = CGPoint(x: edgeX + dir * rng.range(0, w * 0.8), y: rng.range(4, 120))
                    ctx.setFillColor(VistaInk.color(0xFFFFFF, rng.range(0.5, 1)))
                    ctx.fillEllipse(in: CGRect(x: p.x, y: p.y, width: 1.6, height: 1.6))
                }
                ctx.restoreGState()
                ctx.addPath(mound)
                ctx.setStrokeColor(VistaInk.color(0x9FFFE8, 0.35))
                ctx.setLineWidth(1.6)
                ctx.strokePath()
            }
        }
        return [drift(CGRect(x: -40, y: 0, width: 300, height: 136), flip: false, seed: 3), drift(CGRect(x: 1040, y: 0, width: 280, height: 136), flip: true, seed: 4)].compactMap { $0 }
    }

    // MARK: Each frame

    func paintBackdrop(_ ctx: CGContext, _ frame: VistaFrame) {
        ctx.interpolationQuality = .low
        backdrop?.draw(in: ctx, shift: frame.shift)
        drawAuroraLife(ctx, frame)
        drawSpout(ctx, frame)
        drawSnow(ctx, frame, layer: 0)
        ctx.interpolationQuality = .high
    }

    /// The northern lights are never still: bright knots run along each hem, and rays flare up and fade.
    private func drawAuroraLife(_ ctx: CGContext, _ frame: VistaFrame) {
        let t = frame.time
        let dx = Double(frame.shift.x) * 12
        for (i, c) in Self.curtains.enumerated() {
            guard let glow = VistaSprites.glow(c.tint) else { continue }
            let speed = i == 0 ? 38.0 : -27.0
            for k in 0..<7 {
                var x = (t * speed + Double(k) * 1480 / 7 + c.seed * 50).truncatingRemainder(dividingBy: 1480)
                if x < 0 { x += 1480 }
                x -= 100
                let pulse = 0.5 + 0.5 * sin(t * 1.3 + Double(k) * 2.1 + c.seed)
                ctx.stampDot(glow, at: CGPoint(x: x + dx, y: Self.hem(i, x) + 8), radius: 30 + 14 * pulse, alpha: 0.12 + 0.2 * pulse)
            }
        }
        if let streak {
            for k in 0..<16 {
                let f = Double(k)
                let i = k % 2
                let x = (f * 211.7 + 40).truncatingRemainder(dividingBy: 1300) - 10 + sin(t * 0.13 + f) * 30
                let flare = max(0, sin(t * (0.5 + 0.07 * f) + f * 1.9))
                guard flare > 0.05 else { continue }
                let y = Self.hem(i, x)
                ctx.setAlpha(CGFloat(flare * flare * 0.8))
                ctx.draw(streak, in: CGRect(x: x + dx - 9, y: y - 6, width: 18, height: 170 * (0.7 + 0.4 * VistaInk.noise(f, 1))))
            }
            ctx.setAlpha(1)
        }
    }

    /// Now and then, far out on the water, a whale blows.
    private func drawSpout(_ ctx: CGContext, _ frame: VistaFrame) {
        let period = 23.0
        let t = frame.time.truncatingRemainder(dividingBy: period)
        guard t < 2.2, let dot = Sprites.dot(red: 0.92, green: 0.97, blue: 1) else { return }
        let x = 980.0 + Double(frame.shift.x) * 12, base = 330.0
        let k = t / 2.2
        for i in 0..<14 {
            let a = Double(i) / 13 * .pi
            let spread = cos(a) * 26 * k
            let height = sin(a) * 34 * min(1, k * 3) + 6
            ctx.stampDot(dot, at: CGPoint(x: x + spread, y: base + height * (1 - k * 0.3)), radius: 3 + 3 * k, alpha: 0.5 * (1 - k))
        }
        ctx.setFillColor(VistaInk.color(0x1C3550, 0.8 * (1 - k)))
        ctx.fillEllipse(in: CGRect(x: x - 14, y: base - 3, width: 28, height: 6))
    }

    /// Falling snow at three depths: fine and slow far off, big and soft close up.
    private func drawSnow(_ ctx: CGContext, _ frame: VistaFrame, layer: Int) {
        guard let dot = Sprites.dot(red: 0.96, green: 0.98, blue: 1) else { return }
        let count = layer == 0 ? 70 : 22
        let t = frame.time
        for i in 0..<count {
            let f = Double(i) + Double(layer) * 100
            let depth = layer == 0 ? 0.3 + 0.5 * VistaInk.noise(f * 1.7, 2) : 1.0
            let fall = (18 + 26 * depth) * (layer == 0 ? 1 : 1.6)
            let y = 760 - (f * 61.7 + t * fall).truncatingRemainder(dividingBy: 800)
            let x = (f * 113.3).truncatingRemainder(dividingBy: 1340) - 30 + sin(t * 0.7 + f) * 18 + Double(frame.shift.x) * (layer == 0 ? 8 : 50)
            let r = layer == 0 ? 1.2 + 2.2 * depth : 4 + Double(i % 3) * 2
            ctx.stampDot(dot, at: CGPoint(x: x, y: y), radius: r, alpha: layer == 0 ? 0.55 + 0.35 * depth : 0.35)
        }
    }

    func paintForeground(_ ctx: CGContext, _ frame: VistaFrame) {
        ctx.interpolationQuality = .low
        for drift in drifts { drift.draw(in: ctx, shift: frame.shift) }
        drawSnow(ctx, frame, layer: 1)
        ctx.interpolationQuality = .high
    }

    // MARK: The creatures

    func paintCreature(_ ctx: CGContext, _ rig: VistaRig) {
        guard let figure = figures[rig.creature.species] else { return }
        let p = figure.parts(for: rig)
        switch rig.species.art {
        case VistaArcticCast.bear: drawBear(ctx, rig, p)
        case VistaArcticCast.penguin: drawPenguin(ctx, rig, p)
        case VistaArcticCast.seal: drawSeal(ctx, rig, p)
        case VistaArcticCast.fox: drawFox(ctx, rig, p)
        case VistaArcticCast.owl: drawOwl(ctx, rig, p)
        default: drawNarwhal(ctx, rig, p)
        }
    }

    // MARK: Polar bear

    private enum Bear {
        static let body = 0, head = 1, jaw = 2, ear = 3, leg = 4, legFar = 5, foreleg = 6, forelegFar = 7
        static let hip = CGPoint(x: -0.44, y: 0.42)
        static let shoulder = CGPoint(x: 0.24, y: 0.44)
        static let neck = CGPoint(x: 0.4, y: 0.62)
        static let jawPivot = CGPoint(x: 0.6, y: 0.538)
    }

    private func bakeBear(_ u: Double) -> [VistaPart?] {
        var s = ink
        s.rimAmount = 0.32
        let body = VistaPart.bake(u: u, pivot: Bear.hip, box: CGRect(x: -0.84, y: 0.2, width: 1.36, height: 0.72)) { ctx in
            VistaInk.shade(ctx, VistaInk.ellipse(-0.75, 0.6, 0.05, 0.045), Tone.bear, s, u: u, gloss: 0)
            let path = VistaInk.smooth([(-0.77, 0.47), (-0.72, 0.65), (-0.52, 0.77), (-0.2, 0.79), (0.08, 0.86), (0.28, 0.82), (0.44, 0.68), (0.46, 0.48),
                                        (0.34, 0.3), (0.06, 0.24), (-0.32, 0.25), (-0.64, 0.3)])
            VistaInk.shade(ctx, path, Tone.bear, s, u: u)
            // Creamy under the belly, fur along the back, a crease at the shoulder.
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(-0.12, 0.27, 0.56, 0.09), VistaInk.color(0xF0E2C2, 0.45), soft: 0.05, u: u)
            var lines: [(CGPoint, CGPoint, CGPoint)] = []
            for i in 0..<10 {
                let x = -0.66 + Double(i) * 0.11
                lines.append((CGPoint(x: x, y: 0.66), CGPoint(x: x + 0.03, y: 0.61), CGPoint(x: x + 0.07, y: 0.58)))
            }
            lines.append((CGPoint(x: 0.12, y: 0.74), CGPoint(x: 0.2, y: 0.6), CGPoint(x: 0.16, y: 0.44)))
            lines.append((CGPoint(x: -0.42, y: 0.7), CGPoint(x: -0.34, y: 0.56), CGPoint(x: -0.4, y: 0.4)))
            VistaInk.strokes(ctx, clip: path, width: 1.7 / u, VistaInk.color(0x8EA2C0, 0.32), lines)
        }
        let head = VistaPart.bake(u: u, pivot: Bear.neck, box: CGRect(x: 0.34, y: 0.46, width: 0.58, height: 0.38)) { ctx in
            let path = VistaInk.smooth([(0.4, 0.7), (0.48, 0.78), (0.6, 0.78), (0.71, 0.7), (0.83, 0.635), (0.875, 0.585), (0.84, 0.535),
                                        (0.68, 0.512), (0.52, 0.52), (0.41, 0.57)])
            VistaInk.shade(ctx, path, Tone.bear, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.77, 0.56, 0.09, 0.045), VistaInk.color(0xF6EEDB, 0.6), soft: 0.02, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.5, 0.56, 0.08, 0.05), VistaInk.color(0x9AACC4, 0.35), soft: 0.04, u: u)
            VistaInk.oval(ctx, CGPoint(x: 0.857, y: 0.594), rx: 0.034, ry: 0.026, VistaInk.color(0x1A1622))
            VistaInk.oval(ctx, CGPoint(x: 0.848, y: 0.604), rx: 0.012, ry: 0.007, VistaInk.color(0xFFFFFF, 0.7))
            ctx.setStrokeColor(VistaInk.color(0x4A5470, 0.8))
            ctx.setLineWidth(CGFloat(1.6 / u))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 0.85, y: 0.566))
            ctx.addQuadCurve(to: CGPoint(x: 0.71, y: 0.545), control: CGPoint(x: 0.8, y: 0.54))
            ctx.strokePath()
        }
        let jaw = VistaPart.bake(u: u, pivot: Bear.jawPivot, box: CGRect(x: 0.56, y: 0.46, width: 0.3, height: 0.1)) { ctx in
            VistaInk.shade(ctx, VistaInk.smooth([(0.58, 0.545), (0.74, 0.546), (0.83, 0.535), (0.8, 0.508), (0.66, 0.498), (0.57, 0.515)]), Tone.bear, s, u: u, gloss: 0)
        }
        let ear = VistaPart.bake(u: u, pivot: CGPoint(x: 0.5, y: 0.75), box: CGRect(x: 0.44, y: 0.72, width: 0.13, height: 0.12)) { ctx in
            VistaInk.shade(ctx, VistaInk.ellipse(0.5, 0.785, 0.046, 0.043), Tone.bear, s, u: u, gloss: 0)
            VistaInk.oval(ctx, CGPoint(x: 0.505, y: 0.782), rx: 0.022, ry: 0.02, VistaInk.color(0xA8B4C8))
        }
        // Legs thick at the top, narrowing to the wrist, with a broad flat paw and claws.
        func leg(_ tone: VistaTone, length: Double) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.16, y: -length - 0.06, width: 0.36, height: length + 0.16)) { ctx in
                let l = length
                let path = VistaInk.smooth([(-0.12, 0.06), (0.11, 0.06), (0.12, -l * 0.35), (0.085, -l * 0.78), (0.15, -l * 0.9), (0.17, -l - 0.005),
                                            (0.06, -l - 0.012), (-0.09, -l - 0.005), (-0.1, -l * 0.86), (-0.095, -l * 0.5)], tension: 0.55)
                VistaInk.shade(ctx, path, tone, s, u: u, gloss: 0.12)
                ctx.setStrokeColor(VistaInk.color(0x2A2838, 0.75))
                ctx.setLineWidth(CGFloat(1.8 / u))
                ctx.setLineCap(.round)
                for i in 0..<3 {
                    let x = 0.1 + Double(i) * 0.025
                    ctx.move(to: CGPoint(x: x, y: -l + 0.012)); ctx.addLine(to: CGPoint(x: x + 0.016, y: -l - 0.008))
                }
                ctx.strokePath()
            }
        }
        return [body, head, jaw, ear, leg(Tone.bear, length: 0.42), leg(Tone.bearFar, length: 0.42), leg(Tone.bear, length: 0.44), leg(Tone.bearFar, length: 0.44)]
    }

    private func drawBear(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let rear = rig.hold(rise: 0.7, fall: 0.55)
        let roar = rig.phase == .acting ? max(0, min(1, (rig.actTime - 0.7) / 0.2)) * max(0, min(1, (2.1 - rig.actTime) / 0.3)) : 0
        let lean = 0.82 * rear
        let s = rig.stride
        func swing(_ phase: Double) -> (angle: Double, lift: Double) {
            guard rig.moving else { return (0, 0) }
            return (sin(s + phase) * 0.24, max(0, cos(s + phase)) * 0.03)
        }
        let breath = 1 + 0.012 * rig.breath
        let shoulder = vistaTurn(Bear.shoulder, about: Bear.hip, by: lean)
        // Far legs. When it rears, its forelegs hang down from the raised chest, paws curled.
        let fb = swing(.pi), ff = swing(0)
        ctx.place(p[Bear.legFar], at: CGPoint(x: Bear.hip.x + 0.06, y: Bear.hip.y + fb.lift), angle: fb.angle - 0.14 * rear)
        ctx.place(p[Bear.forelegFar], at: CGPoint(x: shoulder.x + 0.06, y: shoulder.y + ff.lift), angle: ff.angle + 0.35 * rear, sy: 1 - 0.2 * rear)
        // Body.
        ctx.place(p[Bear.body], at: Bear.hip, angle: lean, sy: breath)
        // Near legs.
        let nb = swing(0), nf = swing(.pi)
        ctx.place(p[Bear.leg], at: CGPoint(x: Bear.hip.x, y: Bear.hip.y + nb.lift), angle: nb.angle - 0.2 * rear)
        ctx.place(p[Bear.foreleg], at: CGPoint(x: shoulder.x, y: shoulder.y + nf.lift), angle: nf.angle + 0.55 * rear + 0.18 * roar * sin(rig.actTime * 9), sy: 1 - 0.15 * rear)
        // Head: carried low, nodding as it walks, lifted to roar, turned toward you.
        let neck = vistaTurn(Bear.neck, about: Bear.hip, by: lean)
        let nod = rig.moving ? sin(s * 2) * 0.03 : sin(rig.clock * 0.9) * 0.02
        let look = rig.gaze.y * 0.22 * rig.attention
        let headAngle = -lean * 0.35 + nod + look + 0.3 * roar
        let twitch = max(0, sin(rig.clock * 1.3) - 0.94) * 6
        ctx.local(at: neck, angle: headAngle) {
            let o = CGPoint(x: -Bear.neck.x, y: -Bear.neck.y)
            ctx.place(p[Bear.ear], at: CGPoint(x: 0.5 + o.x, y: 0.75 + o.y), angle: twitch * 0.3)
            if roar > 0.02 {
                // The open mouth, behind the lower jaw as it drops.
                let tip = vistaTurn(CGPoint(x: 0.83, y: 0.52), about: Bear.jawPivot, by: -0.55 * roar)
                let mouth = CGMutablePath()
                mouth.move(to: CGPoint(x: 0.58 + o.x, y: 0.545 + o.y))
                mouth.addLine(to: CGPoint(x: 0.86 + o.x, y: 0.565 + o.y))
                mouth.addLine(to: CGPoint(x: tip.x + o.x, y: tip.y + o.y))
                mouth.closeSubpath()
                ctx.addPath(mouth)
                ctx.setFillColor(VistaInk.color(0x5A1424))
                ctx.fillPath()
            }
            ctx.place(p[Bear.head], at: .zero)
            if roar > 0.02 {
                ctx.place(p[Bear.jaw], at: CGPoint(x: Bear.jawPivot.x + o.x, y: Bear.jawPivot.y + o.y), angle: -0.55 * roar)
                ctx.setFillColor(VistaInk.color(0xFFFFFF))
                for x in [0.79, 0.69] {
                    ctx.move(to: CGPoint(x: x + o.x, y: 0.56 + o.y)); ctx.addLine(to: CGPoint(x: x + 0.025 + o.x, y: 0.56 + o.y))
                    ctx.addLine(to: CGPoint(x: x + 0.012 + o.x, y: 0.525 + o.y)); ctx.fillPath()
                }
            }
            VistaFace.bead(ctx, 0.645 + o.x, 0.68 + o.y, r: 0.022, look: rig.gaze, blink: roar > 0.3 ? 0.7 : rig.blink)
        }
    }

    // MARK: Penguin

    private enum Penguin {
        static let body = 0, head = 1, flipper = 2, flipperFar = 3, foot = 4
        static let neck = CGPoint(x: 0.0, y: 0.7)
        static let shoulder = CGPoint(x: -0.03, y: 0.62)
    }

    private func bakePenguin(_ u: Double) -> [VistaPart?] {
        let s = ink
        let outline = VistaInk.smooth([(0.0, 0.05), (0.17, 0.09), (0.27, 0.27), (0.27, 0.52), (0.19, 0.72), (0.06, 0.8), (-0.1, 0.78), (-0.22, 0.64),
                                       (-0.27, 0.42), (-0.25, 0.2), (-0.15, 0.08)])
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.32, y: 0.0, width: 0.64, height: 0.85)) { ctx in
            VistaInk.shade(ctx, outline, Tone.penguin, s, u: u)
            // The white front and the warm yellow at the top of the chest.
            let belly = VistaInk.ellipse(0.11, 0.4, 0.16, 0.34)
            VistaInk.patch(ctx, clip: outline, belly, VistaInk.color(0xF7F9FC), soft: 0.015, u: u)
            VistaInk.patch(ctx, clip: belly, VistaInk.ellipse(0.13, 0.68, 0.12, 0.1), VistaInk.color(0xFFE7A0, 0.85), soft: 0.04, u: u)
            VistaInk.patch(ctx, clip: belly, VistaInk.ellipse(0.2, 0.25, 0.1, 0.2), VistaInk.color(0xB7C6DA, 0.6), soft: 0.04, u: u)
            VistaInk.patch(ctx, clip: outline, VistaInk.ellipse(0.24, 0.5, 0.05, 0.25), VistaInk.color(0x9BFFE4, 0.25), soft: 0.02, u: u)
        }
        let head = VistaPart.bake(u: u, pivot: Penguin.neck, box: CGRect(x: -0.16, y: 0.66, width: 0.52, height: 0.34)) { ctx in
            let skull = VistaInk.ellipse(0.03, 0.83, 0.15, 0.145)
            VistaInk.shade(ctx, skull, Tone.penguin, s, u: u)
            VistaInk.patch(ctx, clip: skull, VistaInk.ellipse(-0.04, 0.77, 0.07, 0.05), VistaInk.color(0xFFC53A), soft: 0.02, u: u)
            let beak = VistaInk.smooth([(0.13, 0.865), (0.24, 0.845), (0.33, 0.812), (0.24, 0.8), (0.13, 0.79)], tension: 0.3)
            VistaInk.shade(ctx, beak, VistaTone(0x5A5A6A, 0x2C2C38, 0x15151C), s, u: u, rim: 0.5)
            VistaInk.patch(ctx, clip: beak, VistaInk.ellipse(0.18, 0.795, 0.06, 0.016), VistaInk.color(0xFF9A3C), soft: 0.004, u: u)
        }
        func flipper(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.07, y: -0.4, width: 0.14, height: 0.44)) { ctx in
                let path = VistaInk.smooth([(-0.03, 0.01), (0.04, -0.02), (0.05, -0.2), (0.02, -0.36), (-0.03, -0.24), (-0.05, -0.06)])
                VistaInk.shade(ctx, path, tone, s, u: u)
                VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.05, -0.18, 0.02, 0.16), VistaInk.color(0xE8EEF6, 0.7), soft: 0.01, u: u)
            }
        }
        let foot = VistaPart.bake(u: u, box: CGRect(x: -0.06, y: -0.02, width: 0.2, height: 0.08)) { ctx in
            VistaInk.shade(ctx, VistaInk.smooth([(-0.04, 0.0), (0.1, 0.0), (0.125, 0.022), (0.02, 0.04), (-0.045, 0.024)]), VistaTone(0xFFB766, 0xF08A2E, 0xA84F14), s, u: u, gloss: 0.1)
        }
        return [body, head, flipper(Tone.penguin), flipper(VistaTone(0x30374C, 0x1A2030, 0x0A0C14)), foot]
    }

    private func drawPenguin(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let c = rig.creature
        let flap = rig.phase == .acting ? rig.hold(rise: 0.2, fall: 0.3) * abs(sin(rig.actTime * 13)) : 0
        let waddle = rig.moving && c.slide < 0.5 ? sin(rig.stride) : 0
        let slide = c.slide
        ctx.saveGState()
        if slide > 0.01 {
            // Over onto its belly, head first.
            let pivot = CGPoint(x: 0, y: 0.3)
            ctx.translateBy(x: pivot.x, y: pivot.y - 0.28 * slide)
            ctx.rotate(by: CGFloat(-1.45 * slide))
            ctx.translateBy(x: -pivot.x, y: -pivot.y)
        }
        let footLift = abs(waddle) * 0.03
        ctx.place(p[Penguin.foot], at: CGPoint(x: -0.09, y: waddle > 0 ? footLift : 0), angle: slide * -1.2)
        ctx.place(p[Penguin.flipperFar], at: CGPoint(x: 0.05, y: 0.64), angle: 0.25 + flap * 1.1 + slide * 1.3)
        ctx.place(p[Penguin.body], at: .zero, sy: 1 + 0.012 * rig.breath)
        ctx.place(p[Penguin.foot], at: CGPoint(x: 0.04, y: waddle < 0 ? footLift : 0), angle: slide * -1.2)
        let nod = rig.moving ? sin(rig.stride * 2) * 0.05 : sin(rig.clock * 1.1) * 0.04
        ctx.local(at: Penguin.neck, angle: nod + rig.gaze.y * 0.25 * rig.attention + 0.4 * slide) {
            ctx.place(p[Penguin.head], at: .zero)
            VistaFace.bead(ctx, 0.085, 0.165, r: 0.024, look: rig.gaze, blink: rig.blink)
        }
        ctx.place(p[Penguin.flipper], at: Penguin.shoulder, angle: -0.18 - flap * 1.25 - waddle * 0.12 + slide * 1.35)
        ctx.restoreGState()
    }

    // MARK: Seal

    private enum Seal {
        static let body = 0, head = 1, flipper = 2, flipperFar = 3, tail = 4
        static let root = CGPoint(x: -0.72, y: 0.06)
        static let neck = CGPoint(x: 0.4, y: 0.48)
        static let shoulder = CGPoint(x: 0.22, y: 0.3)
        static let tailPivot = CGPoint(x: -0.82, y: 0.13)
    }

    private func bakeSeal(_ u: Double) -> [VistaPart?] {
        let s = ink
        let outline = VistaInk.smooth([(-0.86, 0.14), (-0.66, 0.24), (-0.36, 0.38), (-0.02, 0.47), (0.26, 0.53), (0.44, 0.52), (0.5, 0.38), (0.4, 0.14),
                                       (0.16, 0.04), (-0.24, 0.02), (-0.62, 0.06)])
        let body = VistaPart.bake(u: u, pivot: Seal.root, box: CGRect(x: -0.9, y: 0.0, width: 1.44, height: 0.58)) { ctx in
            VistaInk.shade(ctx, outline, Tone.seal, s, u: u)
            VistaInk.patch(ctx, clip: outline, VistaInk.ellipse(0.0, 0.06, 0.55, 0.08), VistaInk.color(0xE4E9F0, 0.6), soft: 0.04, u: u)
            var rng = VistaInk.generator(5)
            ctx.saveGState()
            ctx.addPath(outline)
            ctx.clip()
            for _ in 0..<18 {
                let x = rng.range(-0.7, 0.4), y = rng.range(0.18, 0.48)
                VistaInk.oval(ctx, CGPoint(x: x, y: y), rx: rng.range(0.012, 0.03), ry: rng.range(0.01, 0.022), VistaInk.color(0x4E5A72, 0.4))
            }
            ctx.restoreGState()
        }
        let head = VistaPart.bake(u: u, pivot: Seal.neck, box: CGRect(x: 0.33, y: 0.46, width: 0.56, height: 0.4)) { ctx in
            let path = VistaInk.smooth([(0.34, 0.62), (0.39, 0.8), (0.53, 0.89), (0.68, 0.86), (0.78, 0.76), (0.86, 0.68), (0.85, 0.6), (0.72, 0.56), (0.52, 0.5), (0.4, 0.5)])
            VistaInk.shade(ctx, path, Tone.seal, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.78, 0.625, 0.085, 0.055), VistaInk.color(0xE6EAF0, 0.85), soft: 0.02, u: u)
            VistaInk.oval(ctx, CGPoint(x: 0.845, y: 0.66), rx: 0.026, ry: 0.02, VistaInk.color(0x1A1622))
            ctx.setStrokeColor(VistaInk.color(0xF4F6FA, 0.75))
            ctx.setLineWidth(CGFloat(1.1 / u))
            ctx.setLineCap(.round)
            for i in 0..<3 {
                let y = 0.638 - Double(i) * 0.014
                ctx.move(to: CGPoint(x: 0.8, y: y)); ctx.addQuadCurve(to: CGPoint(x: 0.95, y: y - 0.02 + Double(i) * 0.005), control: CGPoint(x: 0.88, y: y + 0.01))
            }
            ctx.strokePath()
        }
        func flipper(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.06, y: -0.28, width: 0.2, height: 0.32)) { ctx in
                VistaInk.shade(ctx, VistaInk.smooth([(-0.02, 0.02), (0.05, 0.0), (0.1, -0.16), (0.08, -0.25), (0.02, -0.2), (-0.04, -0.06)]), tone, s, u: u, gloss: 0.1)
            }
        }
        let tail = VistaPart.bake(u: u, box: CGRect(x: -0.2, y: -0.1, width: 0.24, height: 0.2)) { ctx in
            VistaInk.shade(ctx, VistaInk.smooth([(0.02, 0.0), (-0.1, 0.08), (-0.17, 0.06), (-0.12, 0.0), (-0.17, -0.06), (-0.1, -0.06)]), VistaTone(0xA9B4C4, 0x7C889C, 0x4A5470), s, u: u, gloss: 0)
        }
        return [body, head, flipper(Tone.seal), flipper(VistaTone(0x8E9AAC, 0x6E7A90, 0x434C64)), tail]
    }

    private func drawSeal(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let up = rig.hold(rise: 0.45, fall: 0.5)
        let clapping = rig.phase == .acting && rig.actTime > 0.5 && rig.actTime < rig.species.actSeconds - 0.6
        let clap = clapping ? sin(rig.actTime * 15) : 0
        // Galumphing: the front rises and falls with each heave.
        let heave = rig.moving ? max(0, sin(rig.stride)) * 0.08 : 0
        let lift = 0.16 * up + heave
        ctx.place(p[Seal.flipperFar], at: vistaTurn(CGPoint(x: Seal.shoulder.x + 0.07, y: Seal.shoulder.y + 0.02), about: Seal.root, by: lift),
                  angle: lift + 1.5 * up - 0.35 * clap * up)
        ctx.place(p[Seal.tail], at: Seal.tailPivot, angle: sin(rig.clock * 1.6) * 0.15 + (rig.moving ? sin(rig.stride) * 0.25 : 0) + 0.2 * up)
        ctx.place(p[Seal.body], at: Seal.root, angle: lift, sy: 1 + 0.014 * rig.breath)
        let neck = vistaTurn(Seal.neck, about: Seal.root, by: lift)
        ctx.local(at: neck, angle: -lift * 0.9 + 0.12 * up + rig.gaze.y * 0.25 * rig.attention + sin(rig.clock * 0.8) * 0.04) {
            ctx.place(p[Seal.head], at: .zero)
            VistaFace.bead(ctx, 0.66 - Seal.neck.x, 0.745 - Seal.neck.y, r: 0.046, look: rig.gaze, blink: rig.blink)
        }
        ctx.place(p[Seal.flipper], at: vistaTurn(Seal.shoulder, about: Seal.root, by: lift), angle: lift + 1.7 * up + 0.35 * clap * up + (rig.moving ? sin(rig.stride) * 0.3 : 0))
    }

    // MARK: Arctic fox

    private enum Fox {
        static let body = 0, head = 1, tail = 2, leg = 3, legFar = 4
        static let hip = CGPoint(x: -0.26, y: 0.38)
        static let shoulder = CGPoint(x: 0.2, y: 0.4)
        static let neck = CGPoint(x: 0.26, y: 0.56)
        static let tailRoot = CGPoint(x: -0.34, y: 0.56)
    }

    /// A fluffy outline: an ellipse with soft tufts round its edge.
    private func fluffy(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, tufts: Int, depth: Double) -> CGPath {
        var pts: [CGPoint] = []
        let n = tufts * 2
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            let k = i % 2 == 0 ? 1 + depth : 1 - depth * 0.3
            pts.append(CGPoint(x: cx + cos(a) * rx * k, y: cy + sin(a) * ry * k))
        }
        return VistaInk.smooth(pts, tension: 0.55)
    }

    private func bakeFox(_ u: Double) -> [VistaPart?] {
        let s = ink
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.48, y: 0.24, width: 0.92, height: 0.52)) { ctx in
            let path = fluffy(-0.04, 0.5, 0.37, 0.19, tufts: 12, depth: 0.05)
            VistaInk.shade(ctx, path, Tone.fox, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.16, 0.42, 0.14, 0.12), VistaInk.color(0xFFFFFF, 0.8), soft: 0.04, u: u)
            VistaInk.strokes(ctx, clip: path, width: 1.4 / u, VistaInk.color(0x9AABC4, 0.35),
                             (0..<8).map { i in let x = -0.34 + Double(i) * 0.08; return (CGPoint(x: x, y: 0.62), CGPoint(x: x + 0.02, y: 0.57), CGPoint(x: x + 0.05, y: 0.53)) })
        }
        let head = VistaPart.bake(u: u, pivot: Fox.neck, box: CGRect(x: 0.2, y: 0.46, width: 0.56, height: 0.52)) { ctx in
            let farEar = VistaInk.smooth([(0.44, 0.76), (0.49, 0.93), (0.56, 0.74)], tension: 0.25)
            VistaInk.shade(ctx, farEar, Tone.foxFar, s, u: u, gloss: 0)
            let skull = VistaInk.smooth([(0.27, 0.66), (0.32, 0.77), (0.44, 0.8), (0.55, 0.75), (0.68, 0.68), (0.71, 0.645), (0.63, 0.6), (0.48, 0.555),
                                         (0.34, 0.55), (0.27, 0.59)])
            VistaInk.shade(ctx, skull, Tone.fox, s, u: u)
            let ear = VistaInk.smooth([(0.32, 0.75), (0.355, 0.95), (0.46, 0.77)], tension: 0.25)
            VistaInk.shade(ctx, ear, Tone.fox, s, u: u, gloss: 0.1)
            VistaInk.patch(ctx, clip: ear, VistaInk.smooth([(0.355, 0.77), (0.365, 0.89), (0.43, 0.775)], tension: 0.2), VistaInk.color(0xC9B8C4, 0.8), soft: 0.01, u: u)
            VistaInk.oval(ctx, CGPoint(x: 0.705, y: 0.648), rx: 0.026, ry: 0.02, VistaInk.color(0x1A1622))
            VistaInk.patch(ctx, clip: skull, fluffy(0.38, 0.585, 0.09, 0.05, tufts: 5, depth: 0.15), VistaInk.color(0xFFFFFF, 0.95), soft: 0.01, u: u)
            ctx.setStrokeColor(VistaInk.color(0x6A7896, 0.6))
            ctx.setLineWidth(CGFloat(1.2 / u))
            ctx.move(to: CGPoint(x: 0.69, y: 0.624)); ctx.addQuadCurve(to: CGPoint(x: 0.59, y: 0.6), control: CGPoint(x: 0.64, y: 0.6))
            ctx.strokePath()
        }
        let tail = VistaPart.bake(u: u, pivot: Fox.tailRoot, box: CGRect(x: -0.96, y: 0.4, width: 0.7, height: 0.4)) { ctx in
            let path = fluffy(-0.6, 0.6, 0.3, 0.13, tufts: 9, depth: 0.07)
            var turn = CGAffineTransform(translationX: -0.6, y: 0.6).rotated(by: 0.18).translatedBy(x: 0.6, y: -0.6)
            let tilted = path.copy(using: &turn) ?? path
            VistaInk.shade(ctx, tilted, Tone.fox, s, u: u)
            VistaInk.strokes(ctx, clip: tilted, width: 1.2 / u, VistaInk.color(0x9AABC4, 0.4),
                             (0..<6).map { i in let x = -0.42 - Double(i) * 0.08; return (CGPoint(x: x, y: 0.66), CGPoint(x: x - 0.03, y: 0.62), CGPoint(x: x - 0.06, y: 0.58)) })
        }
        func leg(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.08, y: -0.42, width: 0.2, height: 0.48)) { ctx in
                VistaInk.shade(ctx, VistaInk.capsule(0, 0.02, 0.012, -0.34, 0.062, 0.04), tone, s, u: u, gloss: 0.05)
                VistaInk.shade(ctx, VistaInk.ellipse(0.03, -0.365, 0.058, 0.03), tone, s, u: u, gloss: 0)
            }
        }
        return [body, head, tail, leg(Tone.fox), leg(Tone.foxFar)]
    }

    private func drawFox(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let c = rig.creature
        // The pounce: a crouch, a leap that arcs nose-down, and a dive into the snow.
        var crouch = 0.0, pitch = 0.0, tuck = 0.0
        if rig.phase == .acting {
            let t = rig.actTime
            if t < 0.55 { crouch = min(1, t / 0.35) }
            if c.lift > 0.5 { pitch = max(-1, min(1, c.vel.y / 640)) * 0.75; tuck = 1 }
            if t > 1.38, t < 1.75 { crouch = 1 - (t - 1.38) / 0.37; pitch = -0.2 * crouch }
        }
        let s = rig.stride
        func swing(_ phase: Double) -> (Double, Double) {
            guard rig.moving else { return (0, 0) }
            return (sin(s + phase) * 0.55, max(0, cos(s + phase)) * 0.04)
        }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(-0.07 * crouch))
        if pitch != 0 {
            ctx.translateBy(x: 0, y: 0.45)
            ctx.rotate(by: CGFloat(pitch))
            ctx.translateBy(x: 0, y: -0.45)
        }
        let (fb, fbl) = swing(.pi), (ff, ffl) = swing(0)
        ctx.place(p[Fox.legFar], at: CGPoint(x: Fox.hip.x + 0.04, y: Fox.hip.y + fbl), angle: fb - 0.7 * tuck, sy: 1 - 0.18 * crouch)
        ctx.place(p[Fox.legFar], at: CGPoint(x: Fox.shoulder.x + 0.04, y: Fox.shoulder.y + ffl), angle: ff + 0.9 * tuck, sy: 1 - 0.18 * crouch)
        let wag = sin(rig.clock * 2.4) * 0.12 + (rig.moving ? sin(s) * 0.1 : 0) + 0.25 * tuck
        ctx.place(p[Fox.tail], at: Fox.tailRoot, angle: wag)
        ctx.place(p[Fox.body], at: .zero, sy: 1 + 0.015 * rig.breath)
        let (nb, nbl) = swing(0), (nf, nfl) = swing(.pi)
        ctx.place(p[Fox.leg], at: CGPoint(x: Fox.hip.x, y: Fox.hip.y + nbl), angle: nb - 0.7 * tuck, sy: 1 - 0.18 * crouch)
        ctx.place(p[Fox.leg], at: CGPoint(x: Fox.shoulder.x, y: Fox.shoulder.y + nfl), angle: nf + 0.9 * tuck, sy: 1 - 0.18 * crouch)
        // The head cocks to one side as it watches you.
        let cock = rig.attention * sin(rig.clock * 0.7) * 0.12
        ctx.local(at: Fox.neck, angle: (rig.moving ? sin(s * 2) * 0.04 : 0) + rig.gaze.y * 0.3 * rig.attention + cock - 0.25 * crouch) {
            ctx.place(p[Fox.head], at: .zero)
            VistaFace.bead(ctx, 0.49 - Fox.neck.x, 0.7 - Fox.neck.y, r: 0.026, look: rig.gaze, blink: rig.blink)
        }
        ctx.restoreGState()
    }

    // MARK: Snowy owl

    private enum Owl {
        static let body = 0, head = 1, wing = 2, wingOpen = 3, wingOpenFar = 4, feet = 5
        static let neck = CGPoint(x: 0.02, y: 0.18)
        static let shoulder = CGPoint(x: -0.02, y: 0.1)
    }

    private func bakeOwl(_ u: Double) -> [VistaPart?] {
        let s = ink
        func flecks(_ ctx: CGContext, _ clip: CGPath, _ box: CGRect, count: Int, seed: UInt64) {
            var rng = VistaInk.generator(seed)
            ctx.saveGState()
            ctx.addPath(clip)
            ctx.clip()
            ctx.setStrokeColor(VistaInk.color(0x3A4256, 0.55))
            ctx.setLineWidth(CGFloat(1.6 / u))
            ctx.setLineCap(.round)
            for _ in 0..<count {
                let x = rng.range(Double(box.minX), Double(box.maxX)), y = rng.range(Double(box.minY), Double(box.maxY))
                ctx.move(to: CGPoint(x: x - 0.016, y: y + 0.008)); ctx.addLine(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + 0.016, y: y + 0.008))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        let outline = VistaInk.smooth([(0.0, -0.4), (0.18, -0.34), (0.26, -0.12), (0.24, 0.1), (0.14, 0.24), (-0.04, 0.26), (-0.18, 0.16), (-0.24, -0.06),
                                       (-0.2, -0.28), (-0.12, -0.38)])
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.3, y: -0.46, width: 0.6, height: 0.76)) { ctx in
            VistaInk.shade(ctx, outline, Tone.owl, s, u: u)
            flecks(ctx, outline, CGRect(x: -0.22, y: -0.3, width: 0.3, height: 0.5), count: 22, seed: 3)
        }
        let head = VistaPart.bake(u: u, pivot: Owl.neck, box: CGRect(x: -0.18, y: 0.08, width: 0.44, height: 0.44)) { ctx in
            let skull = VistaInk.ellipse(0.04, 0.3, 0.19, 0.18)
            VistaInk.shade(ctx, skull, Tone.owl, s, u: u)
            flecks(ctx, skull, CGRect(x: -0.12, y: 0.36, width: 0.22, height: 0.1), count: 7, seed: 9)
            VistaInk.patch(ctx, clip: skull, VistaInk.ellipse(0.1, 0.29, 0.13, 0.12), VistaInk.color(0xFFFFFF), soft: 0.02, u: u)
            let beak = VistaInk.smooth([(0.15, 0.29), (0.2, 0.275), (0.185, 0.235), (0.155, 0.255)], tension: 0.3)
            VistaInk.shade(ctx, beak, VistaTone(0x5A5560, 0x2E2A34, 0x16141C), s, u: u, rim: 0.4, gloss: 0.2)
        }
        let wing = VistaPart.bake(u: u, box: CGRect(x: -0.18, y: -0.5, width: 0.32, height: 0.56)) { ctx in
            let path = VistaInk.smooth([(0.0, 0.03), (0.1, 0.0), (0.09, -0.24), (-0.03, -0.46), (-0.14, -0.36), (-0.12, -0.1)])
            VistaInk.shade(ctx, path, Tone.owl, s, u: u)
            flecks(ctx, path, CGRect(x: -0.12, y: -0.4, width: 0.2, height: 0.38), count: 14, seed: 5)
        }
        func open(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.76, y: -0.12, width: 0.8, height: 0.52)) { ctx in
                let path = VistaInk.smooth([(0.0, 0.04), (-0.2, 0.22), (-0.48, 0.34), (-0.7, 0.3), (-0.64, 0.2), (-0.7, 0.12), (-0.56, 0.06), (-0.6, -0.02),
                                            (-0.4, -0.06), (-0.16, -0.07)], tension: 0.45)
                VistaInk.shade(ctx, path, tone, s, u: u)
                flecks(ctx, path, CGRect(x: -0.6, y: -0.02, width: 0.5, height: 0.3), count: 18, seed: 7)
                VistaInk.strokes(ctx, clip: path, width: 1.2 / u, VistaInk.color(0x8E9CB4, 0.5),
                                 (0..<5).map { i in let x = -0.3 - Double(i) * 0.08; return (CGPoint(x: x + 0.06, y: 0.05), CGPoint(x: x, y: 0.12), CGPoint(x: x - 0.04, y: 0.22)) })
            }
        }
        let feet = VistaPart.bake(u: u, box: CGRect(x: -0.1, y: -0.52, width: 0.26, height: 0.12)) { ctx in
            for x in [-0.03, 0.07] {
                VistaInk.shade(ctx, VistaInk.ellipse(x, -0.44, 0.05, 0.035), Tone.owl, s, u: u, gloss: 0)
                ctx.setStrokeColor(VistaInk.color(0x1E1A24))
                ctx.setLineWidth(CGFloat(2 / u))
                ctx.setLineCap(.round)
                for k in 0..<3 {
                    let tx = x - 0.025 + Double(k) * 0.025
                    ctx.move(to: CGPoint(x: tx, y: -0.465)); ctx.addLine(to: CGPoint(x: tx + 0.012, y: -0.49))
                }
                ctx.strokePath()
            }
        }
        return [body, head, wing, open(Tone.owl), open(VistaTone(0xD6DEE8, 0xC0CBD8, 0x8494AE)), feet]
    }

    private func drawOwl(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let c = rig.creature
        let perched = rig.phase == .acting && c.landedAt != nil
        if perched {
            ctx.place(p[Owl.feet], at: .zero)
            ctx.place(p[Owl.body], at: .zero, sy: 1 + 0.02 * rig.breath)
            ctx.place(p[Owl.wing], at: Owl.shoulder, angle: sin(rig.clock * 0.9) * 0.03)
        } else {
            let flap = sin(c.stride * 1.4)
            ctx.place(p[Owl.wingOpenFar], at: CGPoint(x: Owl.shoulder.x + 0.05, y: Owl.shoulder.y + 0.02), angle: flap * 0.85 + 0.2, sx: 0.92, sy: 0.92)
            ctx.place(p[Owl.body], at: .zero)
            ctx.place(p[Owl.wingOpen], at: Owl.shoulder, angle: flap * 0.85)
        }
        // An owl turns its whole head to look at you.
        let swivel = rig.attention * rig.gaze.y * 0.3 + (perched ? sin(rig.clock * 0.6) * 0.12 : 0)
        ctx.local(at: Owl.neck, angle: swivel) {
            ctx.place(p[Owl.head], at: .zero)
            let o = CGPoint(x: -Owl.neck.x, y: -Owl.neck.y)
            VistaFace.iris(ctx, 0.0 + o.x, 0.335 + o.y, r: 0.042, look: rig.gaze, blink: rig.blink, iris: 0xF6C431, sclera: nil, lid: 0xE8EDF4, rest: 0.06)
            VistaFace.iris(ctx, 0.115 + o.x, 0.33 + o.y, r: 0.052, look: rig.gaze, blink: rig.blink, iris: 0xFFD23A, sclera: nil, lid: 0xF4F6FA, rest: 0.06)
        }
    }

    // MARK: Narwhal

    private enum Narwhal {
        static let body = 0, tusk = 1
        static let tuskRoot = CGPoint(x: 0.05, y: 0.8)
    }

    private func bakeNarwhal(_ u: Double) -> [VistaPart?] {
        let s = ink
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.3, y: -0.2, width: 0.6, height: 1.06)) { ctx in
            let path = VistaInk.smooth([(0.0, 0.84), (0.13, 0.8), (0.21, 0.62), (0.23, 0.3), (0.22, -0.18), (-0.22, -0.18), (-0.23, 0.3), (-0.2, 0.6), (-0.12, 0.78)])
            VistaInk.shade(ctx, path, Tone.narwhal, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.12, 0.3, 0.1, 0.45), VistaInk.color(0xE4ECF4, 0.55), soft: 0.06, u: u)
            var rng = VistaInk.generator(12)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            for _ in 0..<24 {
                VistaInk.oval(ctx, CGPoint(x: rng.range(-0.2, 0.06), y: rng.range(-0.1, 0.72)), rx: rng.range(0.015, 0.04), ry: rng.range(0.012, 0.03), VistaInk.color(0x3E4A64, 0.4))
            }
            ctx.restoreGState()
            // Flippers at the sides.
            VistaInk.shade(ctx, VistaInk.smooth([(0.2, 0.28), (0.34, 0.2), (0.36, 0.14), (0.22, 0.18)]), Tone.narwhal, s, u: u, gloss: 0)
            ctx.setStrokeColor(VistaInk.color(0x3A4660, 0.7))
            ctx.setLineWidth(CGFloat(1.6 / u))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 0.08, y: 0.66)); ctx.addQuadCurve(to: CGPoint(x: 0.16, y: 0.67), control: CGPoint(x: 0.12, y: 0.645))
            ctx.strokePath()
        }
        let tusk = VistaPart.bake(u: u, pivot: Narwhal.tuskRoot, box: CGRect(x: 0.0, y: 0.76, width: 0.16, height: 0.56)) { ctx in
            let path = VistaInk.smooth([(0.03, 0.8), (0.08, 1.12), (0.1, 1.29), (0.11, 1.12), (0.075, 0.8)], tension: 0.3)
            VistaInk.shade(ctx, path, Tone.tusk, s, u: u, rim: 0.6, gloss: 0.3)
            VistaInk.strokes(ctx, clip: path, width: 1 / u, VistaInk.color(0xA99E80, 0.6),
                             (0..<10).map { i in let y = 0.83 + Double(i) * 0.045; return (CGPoint(x: 0.02, y: y), CGPoint(x: 0.07, y: y + 0.01), CGPoint(x: 0.12, y: y + 0.035)) })
        }
        return [body, tusk]
    }

    private func drawNarwhal(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let c = rig.creature
        let rise = c.rise
        let sink = (rise - 1) * 1.32
        // Rings on the water where it is, even when it is under.
        let ripple = 0.5 + 0.5 * sin(rig.clock * 2.2)
        ctx.setStrokeColor(VistaInk.color(0xE8F6FF, 0.35 + 0.2 * rise))
        ctx.setLineWidth(CGFloat(1.4 / rig.scale))
        for k in 0..<2 {
            let rx = 0.22 + 0.12 * Double(k) + 0.05 * ripple
            ctx.strokeEllipse(in: CGRect(x: -rx, y: -0.025 - 0.01 * Double(k), width: rx * 2, height: 0.05 + 0.02 * Double(k)))
        }
        guard rise > 0.02 else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: -1, y: 0, width: 2, height: 2))
        let sway = sin(rig.clock * 1.1) * 0.08 * rise + (rig.phase == .acting ? sin(rig.actTime * 3) * 0.1 * rig.act : 0)
        ctx.translateBy(x: 0, y: CGFloat(sink))
        ctx.rotate(by: CGFloat(sway))
        ctx.place(p[Narwhal.tusk], at: Narwhal.tuskRoot)
        ctx.place(p[Narwhal.body], at: .zero)
        VistaFace.bead(ctx, 0.1, 0.62, r: 0.028, look: rig.gaze, blink: rig.blink)
        ctx.restoreGState()
        // Foam where it breaks the surface.
        VistaInk.oval(ctx, CGPoint(x: 0, y: 0.005), rx: 0.26, ry: 0.035, VistaInk.color(0xF4FAFF, 0.75 * min(1, rise * 3)))
    }
}
