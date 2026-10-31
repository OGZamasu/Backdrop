import CoreGraphics
import Foundation
import simd

/// Who lives in the enchanted wood.
enum VistaForestCast {
    static let fairy = 0, stag = 1, owl = 2, fox = 3, rabbit = 4, cat = 5

    static var cast: VistaCast {
        var layout = VistaLayout()
        layout.farGround = 300
        layout.nearGround = 84
        layout.roamLow = 380
        layout.roamHigh = 640

        var sprite = VistaSpecies(name: "fairy", art: fairy, height: 66, aspect: 1.0, speed: 150)
        sprite.body = .flier
        sprite.act = .orbit
        sprite.temper = .prey
        sprite.home = 0.32
        sprite.actSeconds = 5.0
        sprite.cry = "HEE HEE!"
        sprite.band = 360...620
        sprite.emitters = [VistaEmitter(kind: .sparkle, from: 0, to: 5, rate: 9, at: SIMD2(-0.2, 0), velocity: SIMD2(-20, -20), spread: 20)]

        var hart = VistaSpecies(name: "stag", art: stag, height: 290, aspect: 1.05, speed: 60)
        hart.farOnly = true
        hart.temper = .prey
        hart.home = 0.16
        hart.charge = 1.5
        hart.actSeconds = 3.2
        hart.cry = "💚"
        hart.cryAt = 1.2
        hart.beats = [VistaBeat(at: 1.2, event: .burst(.sparkle, 8, 0.8))]

        var hoot = VistaSpecies(name: "owl", art: owl, height: 84, aspect: 0.9, speed: 140)
        hoot.body = .flier
        hoot.act = .perch
        hoot.temper = .prey
        hoot.perchesOnHand = true
        hoot.home = 0.3
        hoot.cry = "HOO!"
        hoot.band = 430...630

        var red = VistaSpecies(name: "fox", art: fox, height: 104, aspect: 1.45, speed: 105)
        red.home = 0.22
        red.charge = 1.6
        red.actSeconds = 3.0
        red.cry = "YIP!"
        red.cryAt = 0.9
        red.emitters = [VistaEmitter(kind: .heart, from: 1.0, to: 2.4, rate: 2.5, at: SIMD2(0.35, 0.95), velocity: SIMD2(20, 70), spread: 20)]

        var bunny = VistaSpecies(name: "rabbit", art: rabbit, height: 74, aspect: 0.95, speed: 64)
        bunny.gait = .hop
        bunny.temper = .prey
        bunny.home = 0.28
        bunny.actSeconds = 2.4
        bunny.cry = "SNIFF SNIFF"
        bunny.cryAt = 0.3
        bunny.beats = [VistaBeat(at: 1.4, event: .jump(300)), VistaBeat(at: 1.8, event: .burst(.dust, 3, 0.4))]

        var giant = VistaSpecies(name: "giant cat", art: cat, height: 440, aspect: 0.95, speed: 48)
        // Behind the hedge it pads over to you quickly, out of sight.
        giant.charge = 3.5
        giant.body = .emerger
        giant.farOnly = true
        giant.temper = .steady
        giant.home = 0.02
        giant.interest = 0.75
        giant.actSeconds = 4.6
        giant.cry = "PURRRR~"
        giant.cryAt = 1.2
        giant.emitters = [VistaEmitter(kind: .heart, from: 1.4, to: 3.6, rate: 2.2, at: SIMD2(0.1, 0.7), velocity: SIMD2(10, 70), spread: 25)]

        return VistaCast(species: [sprite, hart, hoot, red, bunny, giant], roster: [0, 0, 1, 2, 3, 4, 4, 5], layout: layout, cap: 9, visibleAtStart: 6)
    }
}

/// An enchanted wood at twilight: great mossy trunks fading into blue mist, shafts of moonlight, mushrooms that glow, fireflies
/// that gather round you, and gentle creatures who come to say hello.
final class VistaForestStage: VistaStage {
    let cast = VistaForestCast.cast
    let hint = "Wave to scatter them, or hold up a hand for the owl"
    let accent: UInt32 = 0x2FA88A
    let fx = VistaFXColors(dust: 0xA8C8B0, snow: 0xE8FFF4, sparkle: 0xE8FFB0, ember: 0xD8FF8A, smoke: 0xB8D8C8, water: 0xDDF2FF,
                           notes: [0xB8FFE0], heart: 0xFF8AB8)
    let haze: UInt32 = 0x3E7A86
    let hazeAmount = 0.28

    private enum Wood {
        static let sky: UInt32 = 0x0E1E3A
        static let mist: UInt32 = 0x6AB8B8
        static let moss: UInt32 = 0x3E7A4A
        static let glowCyan: UInt32 = 0x7AF4FF
        static let glowPink: UInt32 = 0xFF8AE0
        static let firefly: UInt32 = 0xE8FF8A
    }
    private let ink = VistaInkStyle(rim: 0xA8FFD8, rimAmount: 0.5, line: 1.9, ink: 0.5, gloss: 0.2)

    private enum Tone {
        static let fur = VistaTone(0xFFB27A, 0xE8742E, 0x8A3412)
        static let furFar = VistaTone(0xD88A5A, 0xB85A28, 0x6A2A10)
        static let cream = VistaTone(0xFFFFFF, 0xF6EEE2, 0xBCA894)
        static let sock = VistaTone(0x5A4A50, 0x2E2428, 0x120C10)
        static let deer = VistaTone(0xE8B886, 0xB87E4E, 0x6A3E22)
        static let deerFar = VistaTone(0xC8986A, 0x98643A, 0x52301A)
        static let antler = VistaTone(0xFFF4DC, 0xE0CCA4, 0x98805A)
        static let owl = VistaTone(0xE0B888, 0xA87444, 0x5A3418)
        static let bunny = VistaTone(0xE8DCD0, 0xB8A898, 0x6E6058)
        static let bunnyFar = VistaTone(0xC8BCB0, 0x988878, 0x564A44)
        static let cat = VistaTone(0xE6DCF4, 0xB8A8D8, 0x6A5A94)
        static let skin = VistaTone(0xFFF0E4, 0xFFD4BC, 0xC8907A)
    }

    private var painting: VistaPainting?
    private var backdrop: VistaLayer?
    private var trunks: [VistaLayer] = []
    private var ferns: [VistaLayer] = []
    private var figures: [VistaFigure?]

    init() { figures = Array(repeating: nil, count: cast.species.count) }

    // MARK: Painting, in steps

    var backdropSteps: Int { 3 }
    var bakeSteps: Int { 5 + cast.species.count }

    func bake(step: Int) {
        switch step {
        case 0:
            painting = VistaPainting(CGRect(x: -48, y: 0, width: 1376, height: 720))
            painting?.paint { ctx in
                paintSky(ctx)
                paintFarTrees(ctx)
            }
        case 1:
            painting?.paint { ctx in
                paintMidTrees(ctx)
                paintBeams(ctx)
            }
        case 2:
            painting?.paint { ctx in
                paintFloor(ctx)
                paintVignette(ctx)
            }
            backdrop = painting?.finish(parallax: 12)
            painting = nil
        case 3:
            trunks = paintTrunks()
        case 4:
            ferns = paintFerns()
        default:
            let i = step - 5
            guard figures.indices.contains(i) else { return }
            let sp = cast.species[i]
            let u = sp.height * cast.layout.scale(sp.farOnly ? min(1, sp.home + 0.06) : 1)
            let parts: [VistaPart?]
            switch sp.art {
            case VistaForestCast.fairy: parts = bakeFairy(u)
            case VistaForestCast.stag: parts = bakeStag(u)
            case VistaForestCast.owl: parts = bakeOwl(u)
            case VistaForestCast.fox: parts = bakeFox(u)
            case VistaForestCast.rabbit: parts = bakeRabbit(u)
            default: parts = bakeCat(u)
            }
            figures[i] = VistaFigure(parts, haze: haze, amount: hazeAmount)
        }
    }

    func isReady(species: Int) -> Bool { figures.indices.contains(species) && figures[species] != nil }

    // MARK: The world

    private static let moon = CGPoint(x: 260, y: 650)
    /// Clusters of glowing mushrooms in the backdrop, which pulse.
    private static let shrooms: [(CGPoint, Double, UInt32)] = [(CGPoint(x: 190, y: 268), 1.0, 0x7AF4FF), (CGPoint(x: 1090, y: 262), 1.1, 0xFF8AE0),
                                                              (CGPoint(x: 820, y: 286), 0.6, 0x7AF4FF), (CGPoint(x: 430, y: 290), 0.55, 0xFF8AE0)]

    private func paintSky(_ ctx: CGContext) {
        VistaInk.fillDown(ctx, CGRect(x: -48, y: 200, width: 1376, height: 520), [(0, VistaInk.color(0x08142A)), (0.4, VistaInk.color(Wood.sky)),
                                                                                   (0.75, VistaInk.color(0x1E4A5A)), (1, VistaInk.color(0x3E7A7A))])
        VistaInk.blob(ctx, Self.moon, rx: 420, ry: 300, VistaInk.color(0x9AE8E0, 0.18))
        VistaInk.blob(ctx, Self.moon, rx: 90, ry: 90, VistaInk.color(0xE8FFF8, 0.45))
        VistaInk.oval(ctx, Self.moon, rx: 30, ry: 30, VistaInk.color(0xF4FFFA))
        var rng = VistaInk.generator(5)
        for _ in 0..<60 {
            let p = CGPoint(x: rng.range(-48, 1328), y: rng.range(520, 720))
            ctx.setFillColor(VistaInk.color(0xFFFFFF, rng.range(0.2, 0.6)))
            ctx.fillEllipse(in: CGRect(x: p.x, y: p.y, width: 1.5, height: 1.5))
        }
    }

    /// One straight-ish trunk with a few branches, as a soft-edged column.
    private func trunk(_ ctx: CGContext, x: Double, base: Double, width: Double, top: Double, tone: UInt32, lit: UInt32, lean: Double, seed: UInt64) {
        var rng = VistaInk.generator(seed)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x - width * 0.7, y: base))
        path.addCurve(to: CGPoint(x: x - width * 0.5 + lean, y: top), control1: CGPoint(x: x - width * 0.45, y: base + 30), control2: CGPoint(x: x - width * 0.5 + lean * 0.5, y: (base + top) / 2))
        path.addLine(to: CGPoint(x: x + width * 0.5 + lean, y: top))
        path.addCurve(to: CGPoint(x: x + width * 0.7, y: base), control1: CGPoint(x: x + width * 0.5 + lean * 0.5, y: (base + top) / 2), control2: CGPoint(x: x + width * 0.45, y: base + 30))
        path.closeSubpath()
        VistaInk.fill(ctx, path, [(0, VistaInk.color(lit)), (0.35, VistaInk.color(tone)), (1, VistaInk.color(VistaInk.mixHex(tone, 0x000000, 0.35)))],
                      from: CGPoint(x: x - width * 0.6, y: 0), to: CGPoint(x: x + width * 0.6, y: 0))
        // Branches reaching up and out.
        ctx.setStrokeColor(VistaInk.color(tone))
        ctx.setLineCap(.round)
        for _ in 0..<2 {
            let y = rng.range(base + (top - base) * 0.55, top - 20)
            let side = rng.sign()
            ctx.setLineWidth(CGFloat(width * 0.16))
            ctx.move(to: CGPoint(x: x + lean * (y - base) / (top - base), y: y))
            ctx.addQuadCurve(to: CGPoint(x: x + side * width * 2.2, y: y + width * 1.6), control: CGPoint(x: x + side * width, y: y + width * 0.3))
            ctx.strokePath()
        }
    }

    private func paintFarTrees(_ ctx: CGContext) {
        var rng = VistaInk.generator(9)
        // Three ranks of trunks, each further one paler with mist.
        for (rank, (count, width, tone, lit)) in [(14, 18.0, 0x3A6A78 as UInt32, 0x6A9AA0 as UInt32), (10, 30.0, 0x2A4E5E as UInt32, 0x5A8A88 as UInt32)].enumerated() {
            for i in 0..<count {
                let x = -30 + Double(i) * 1380 / Double(count) + rng.range(-30, 30)
                trunk(ctx, x: x, base: 290 + Double(rank) * 5, width: width * rng.range(0.8, 1.2), top: 760, tone: tone, lit: lit, lean: rng.range(-20, 20), seed: UInt64(rank * 20 + i))
            }
            VistaInk.fill(ctx, CGRect(x: -48, y: 260, width: 1376, height: 260), [(0, VistaInk.color(Wood.mist, 0)), (0.7, VistaInk.color(Wood.mist, 0.22)), (1, VistaInk.color(Wood.mist, 0.35))],
                          from: CGPoint(x: 0, y: 520), to: CGPoint(x: 0, y: 280))
        }
        // Leaf canopy at the top: dark masses with moonlit edges.
        for _ in 0..<26 {
            let c = CGPoint(x: rng.range(-60, 1340), y: rng.range(640, 760))
            let r = rng.range(60, 130)
            VistaInk.oval(ctx, c, rx: r, ry: r * 0.6, VistaInk.color(0x0E2430))
            VistaInk.blob(ctx, CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.2), rx: r * 0.5, ry: r * 0.25, VistaInk.color(0x4A8A7A, 0.25))
        }
    }

    private func paintMidTrees(_ ctx: CGContext) {
        var rng = VistaInk.generator(17)
        for i in 0..<6 {
            let x = 60 + Double(i) * 230 + rng.range(-40, 40)
            if x > 470, x < 810 { continue }
            trunk(ctx, x: x, base: 284, width: rng.range(46, 64), top: 760, tone: 0x1E3440, lit: 0x4E7A70, lean: rng.range(-30, 30), seed: UInt64(60 + i))
            // Moss on the lit side.
            VistaInk.blob(ctx, CGPoint(x: x - 20, y: 330), rx: 26, ry: 50, VistaInk.color(0x5A9A5A, 0.4))
        }
        VistaInk.fill(ctx, CGRect(x: -48, y: 270, width: 1376, height: 140), [(0, VistaInk.color(Wood.mist, 0)), (1, VistaInk.color(Wood.mist, 0.3))],
                      from: CGPoint(x: 0, y: 410), to: CGPoint(x: 0, y: 285))
    }

    /// Shafts of moonlight slanting down from the upper left.
    private func paintBeams(_ ctx: CGContext) {
        for (i, (x, width)) in [(200.0, 70.0), (420.0, 110.0), (700.0, 80.0), (930.0, 120.0)].enumerated() {
            let beam = CGMutablePath()
            beam.move(to: CGPoint(x: x - width / 2, y: 740))
            beam.addLine(to: CGPoint(x: x + width / 2, y: 740))
            beam.addLine(to: CGPoint(x: x + width / 2 + 220, y: 240))
            beam.addLine(to: CGPoint(x: x - width / 2 + 160, y: 240))
            beam.closeSubpath()
            VistaInk.fill(ctx, beam, [(0, VistaInk.color(0xD8FFF4, 0.16 - Double(i % 2) * 0.04)), (1, VistaInk.color(0xD8FFF4, 0))],
                          from: CGPoint(x: x, y: 740), to: CGPoint(x: x + 200, y: 260))
        }
    }

    private func paintFloor(_ ctx: CGContext) {
        let floor = VistaInk.ridge(left: -48, width: 1376, base: 296, bottom: 0, amplitude: 6, wavelength: 180, seed: 4)
        VistaInk.fill(ctx, floor, [(0, VistaInk.color(0x4E8A7A)), (0.2, VistaInk.color(0x3A6E52)), (0.6, VistaInk.color(0x24503A)), (1, VistaInk.color(0x102A20))],
                      from: CGPoint(x: 0, y: 296), to: CGPoint(x: 0, y: 0))
        ctx.saveGState()
        ctx.addPath(floor)
        ctx.clip()
        // A pool of moonlight in the clearing.
        VistaInk.blob(ctx, CGPoint(x: 660, y: 170), rx: 560, ry: 120, VistaInk.color(0xB8FFE0, 0.18))
        var rng = VistaInk.generator(27)
        // Moss and grass, and a scatter of tiny flowers.
        let tones: [UInt32] = [0x2E5E3E, 0x4A8A5A, 0x6AAA6A, 0x1E3E2A, 0x8AC88A]
        for _ in 0..<1300 {
            let t = rng.unit()
            let y = 292 - pow(t, 1.3) * 296
            let s = 0.2 + 1.1 * pow(t, 1.2)
            VistaInk.blade(ctx, at: CGPoint(x: rng.range(-48, 1328), y: y), height: rng.range(5, 14) * s, lean: rng.range(-4, 4) * s, width: max(0.7, 1.5 * s),
                           color: VistaInk.color(tones[Int(rng.unit() * 5) % 5], rng.range(0.4, 0.8)))
        }
        for _ in 0..<160 {
            let t = rng.unit()
            let y = 290 - pow(t, 1.3) * 292
            let r = 0.8 + 2.2 * t
            ctx.setFillColor(VistaInk.color(rng.chance(0.5) ? 0xC8F0FF : 0xFFE0F4, rng.range(0.5, 0.9)))
            ctx.fillEllipse(in: CGRect(x: rng.range(-48, 1328), y: y, width: r, height: r))
        }
        // A log and stones.
        let log = VistaInk.rounded(CGRect(x: 880, y: 236, width: 150, height: 26), 13)
        VistaInk.shade(ctx, log, VistaTone(0x8A6A4A, 0x5A4030, 0x2A1C14), ink, u: 1)
        VistaInk.oval(ctx, CGPoint(x: 1022, y: 249), rx: 9, ry: 12, VistaInk.color(0xC8A47A))
        VistaInk.blob(ctx, CGPoint(x: 940, y: 262), rx: 60, ry: 7, VistaInk.color(0x6AAA5A, 0.8))
        ctx.restoreGState()
        // A hedge of low bushes along the far edge of the clearing.
        var hedge = VistaInk.generator(44)
        for k in 0..<40 {
            let x = -40 + Double(k) * 35 + hedge.range(-10, 10)
            let r = hedge.range(16, 30)
            VistaInk.oval(ctx, CGPoint(x: x, y: 292 + hedge.range(-3, 5)), rx: r * 1.3, ry: r * 0.6, VistaInk.color(k % 2 == 0 ? 0x1E4A34 : 0x2A5A3E))
            VistaInk.oval(ctx, CGPoint(x: x - r * 0.3, y: 298), rx: r * 0.6, ry: r * 0.22, VistaInk.color(0x5A9A6A, 0.5))
        }
        // Glowing mushrooms.
        for (p, size, tint) in Self.shrooms { mushrooms(ctx, at: p, size: size, tint: tint, seed: UInt64(abs(p.x))) }
    }

    /// A cluster of glowing toadstools.
    private func mushrooms(_ ctx: CGContext, at p: CGPoint, size: Double, tint: UInt32, seed: UInt64) {
        var rng = VistaInk.generator(seed)
        VistaInk.blob(ctx, CGPoint(x: p.x, y: p.y + 10 * size), rx: 70 * size, ry: 40 * size, VistaInk.color(tint, 0.18))
        for _ in 0..<4 {
            let x = Double(p.x) + rng.range(-30, 30) * size, h = rng.range(14, 30) * size, w = rng.range(12, 22) * size
            let stem = VistaInk.rounded(CGRect(x: x - w * 0.18, y: Double(p.y), width: w * 0.36, height: h), w * 0.15)
            VistaInk.shade(ctx, stem, VistaTone(0xF4FFF8, 0xC8E8E0, 0x7A9A98), ink, u: 1, rim: 0.3, line: false)
            let cap = CGMutablePath()
            cap.addArc(center: CGPoint(x: x, y: Double(p.y) + h), radius: CGFloat(w * 0.55), startAngle: 0, endAngle: .pi, clockwise: false)
            cap.closeSubpath()
            VistaInk.shade(ctx, cap, VistaTone(VistaInk.mixHex(tint, 0xFFFFFF, 0.6), tint, VistaInk.mixHex(tint, 0x1A2A4A, 0.5)), ink, u: 1, rim: 0.4, gloss: 0.4, line: false)
            for _ in 0..<3 { VistaInk.oval(ctx, CGPoint(x: x + rng.range(-w * 0.3, w * 0.3), y: Double(p.y) + h + rng.range(w * 0.1, w * 0.35)), rx: w * 0.06, ry: w * 0.05, VistaInk.color(0xFFFFFF, 0.8)) }
        }
    }

    private func paintVignette(_ ctx: CGContext) {
        let g = VistaInk.gradient([(0, VistaInk.color(0x041014, 0)), (0.58, VistaInk.color(0x041014, 0)), (1, VistaInk.color(0x041014, 0.6))])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 360), startRadius: 0, endCenter: CGPoint(x: 640, y: 360), endRadius: 800, options: [.drawsAfterEndLocation])
    }

    /// Two great mossy trunks framing the clearing, roots spreading.
    private func paintTrunks() -> [VistaLayer] {
        func big(_ rect: CGRect, x: Double, flip: Double) -> VistaLayer? {
            VistaInk.layer(rect, parallax: 22) { ctx in
                trunk(ctx, x: x, base: -10, width: 120, top: 760, tone: 0x162A30, lit: 0x3E6A60, lean: flip * -20, seed: 3)
                // Moss, glowing a little at the edges.
                var rng = VistaInk.generator(UInt64(abs(x)) + 1)
                for _ in 0..<14 {
                    VistaInk.blob(ctx, CGPoint(x: x + flip * 40 + rng.range(-20, 20), y: rng.range(60, 600)), rx: rng.range(16, 36), ry: rng.range(10, 30), VistaInk.color(0x5AAA6A, 0.45))
                }
                VistaInk.blob(ctx, CGPoint(x: x + flip * 62, y: 380), rx: 18, ry: 320, VistaInk.color(0xA8FFD8, 0.14))
            }
        }
        return [big(CGRect(x: -120, y: 0, width: 320, height: 720), x: -10, flip: 1), big(CGRect(x: 1100, y: 0, width: 300, height: 720), x: 1300, flip: -1)].compactMap { $0 }
    }

    /// Ferns and mushrooms spilling in from the bottom corners, in front of everything.
    private func paintFerns() -> [VistaLayer] {
        func clump(_ rect: CGRect, seed: UInt64, flip: Double) -> VistaLayer? {
            VistaInk.layer(rect, parallax: 44) { ctx in
                var rng = VistaInk.generator(seed)
                let base = CGPoint(x: flip > 0 ? rect.minX + 40 : rect.maxX - 40, y: -10)
                for k in 0..<9 {
                    let angle = .pi / 2 + flip * (-0.15 - Double(k) * 0.16) + rng.range(-0.08, 0.08)
                    frond(ctx, base: base, angle: angle, length: rng.range(130, 190), seed: seed + UInt64(k))
                }
                mushrooms(ctx, at: CGPoint(x: Double(base.x) + flip * 110, y: 4), size: 1.4, tint: flip > 0 ? Wood.glowCyan : Wood.glowPink, seed: seed + 50)
            }
        }
        return [clump(CGRect(x: -20, y: 0, width: 290, height: 200), seed: 3, flip: 1), clump(CGRect(x: 1010, y: 0, width: 290, height: 200), seed: 8, flip: -1)].compactMap { $0 }
    }

    private func frond(_ ctx: CGContext, base: CGPoint, angle: Double, length: Double, seed: UInt64) {
        var rng = VistaInk.generator(seed)
        let bend = (cos(angle) >= 0 ? 1.0 : -1.0) * 0.7
        func point(_ k: Double) -> (CGPoint, Double) {
            var p = base
            let steps = 12
            for i in 0..<steps {
                let along = Double(i) / Double(steps) * k
                let heading = angle - bend * along * along
                p.x += cos(heading) * length * k / Double(steps)
                p.y += sin(heading) * length * k / Double(steps)
            }
            return (p, angle - bend * k * k)
        }
        let dark = 0x1E4A32 as UInt32, light = 0x6ABA7A as UInt32
        for i in 1...16 {
            let k = Double(i) / 17
            let (p, a) = point(k)
            let size = length * 0.2 * (1 - 0.7 * k) * rng.range(0.9, 1.1)
            for side in [-1.0, 1.0] {
                let la = a + side * 1.0
                let tip = CGPoint(x: Double(p.x) + cos(la) * size, y: Double(p.y) + sin(la) * size)
                let leaf = CGMutablePath()
                leaf.move(to: p)
                leaf.addQuadCurve(to: tip, control: CGPoint(x: Double(p.x) + cos(la + 0.3) * size * 0.6, y: Double(p.y) + sin(la + 0.3) * size * 0.6))
                leaf.addQuadCurve(to: p, control: CGPoint(x: Double(p.x) + cos(la - 0.3) * size * 0.6, y: Double(p.y) + sin(la - 0.3) * size * 0.6))
                ctx.addPath(leaf)
                ctx.setFillColor(VistaInk.mix(dark, light, 0.25 + 0.5 * k + (side > 0 ? 0.15 : 0)))
                ctx.fillPath()
            }
        }
        ctx.setStrokeColor(VistaInk.color(0x2E5E3A))
        ctx.setLineWidth(2)
        ctx.move(to: base)
        for i in 1...12 { ctx.addLine(to: point(Double(i) / 12).0) }
        ctx.strokePath()
    }

    // MARK: Each frame

    func paintBackdrop(_ ctx: CGContext, _ frame: VistaFrame) {
        ctx.interpolationQuality = .low
        backdrop?.draw(in: ctx, shift: frame.shift)
        let dx = Double(frame.shift.x) * 12
        // The mushrooms breathe light.
        for (i, (p, size, tint)) in Self.shrooms.enumerated() {
            guard let glow = VistaSprites.glow(tint) else { continue }
            let pulse = 0.5 + 0.5 * sin(frame.time * 1.3 + Double(i) * 1.7)
            ctx.stampDot(glow, at: CGPoint(x: Double(p.x) + dx, y: Double(p.y) + 16 * size), radius: 46 * size * (0.85 + 0.25 * pulse), alpha: 0.2 + 0.25 * pulse)
        }
        // Motes drifting down the moonbeams.
        if let dot = Sprites.dot(red: 0.9, green: 1, blue: 0.95) {
            for i in 0..<18 {
                let f = Double(i)
                let k = (frame.time * (0.03 + 0.01 * Double(i % 3)) + f * 0.137).truncatingRemainder(dividingBy: 1)
                let x = 220 + Double(i % 4) * 240 + k * 200 + sin(frame.time * 0.6 + f) * 12 + dx
                let y = 700 - k * 440
                ctx.stampDot(dot, at: CGPoint(x: x, y: y), radius: 1.6 + Double(i % 3), alpha: 0.45 * sin(k * .pi))
            }
        }
        for t in trunks { t.draw(in: ctx, shift: frame.shift) }
        drawFireflies(ctx, frame, front: false)
        ctx.interpolationQuality = .high
    }

    /// Fireflies: they wander the clearing and drift in close round you when you are there.
    private func drawFireflies(_ ctx: CGContext, _ frame: VistaFrame, front: Bool) {
        guard let glow = VistaSprites.glow(Wood.firefly) else { return }
        let t = frame.time
        let count = front ? 10 : 22
        let centre = frame.person.map { CGPoint(x: $0.head.x, y: $0.head.y - CGFloat($0.headRadius) * 0.5) }
        for i in 0..<count {
            let f = Double(i) + (front ? 100 : 0)
            var x = (f * 173.3).truncatingRemainder(dividingBy: 1240) + 20 + sin(t * 0.31 + f) * 60
            var y = 120 + (f * 89.1).truncatingRemainder(dividingBy: 440) + sin(t * 0.43 + f * 1.3) * 40
            if let centre, i % 2 == 0 {
                // Half of them gather round you, in a loose ring that keeps off your face.
                let a = t * 0.25 * (i % 4 == 0 ? 1 : -1) + f * 0.9
                let r = 190 + 50 * sin(t * 0.5 + f)
                x = x * 0.25 + (Double(centre.x) + cos(a) * r) * 0.75
                y = y * 0.25 + (Double(centre.y) + sin(a) * r * 0.6) * 0.75
            }
            var blink = max(0, sin(t * (1.1 + 0.2 * Double(i % 5)) + f * 2.3))
            guard blink > 0.05 else { continue }
            // They keep off your face.
            if let zone = frame.person?.faceZone.insetBy(dx: -12, dy: -12), zone.contains(CGPoint(x: x, y: y)) { blink *= 0.12 }
            ctx.stampDot(glow, at: CGPoint(x: x + Double(frame.shift.x) * (front ? 30 : 16), y: y), radius: (front ? 9 : 6) * (0.6 + 0.4 * blink), alpha: blink * 0.9)
        }
    }

    func paintForeground(_ ctx: CGContext, _ frame: VistaFrame) {
        ctx.interpolationQuality = .low
        for fern in ferns { fern.draw(in: ctx, shift: frame.shift) }
        drawFireflies(ctx, frame, front: true)
        ctx.interpolationQuality = .high
    }

    // MARK: The creatures

    func paintCreature(_ ctx: CGContext, _ rig: VistaRig) {
        guard let figure = figures[rig.creature.species] else { return }
        let p = figure.parts(for: rig)
        switch rig.species.art {
        case VistaForestCast.fairy: drawFairy(ctx, rig, p)
        case VistaForestCast.stag: drawStag(ctx, rig, p)
        case VistaForestCast.owl: drawOwl(ctx, rig, p)
        case VistaForestCast.fox: drawFox(ctx, rig, p)
        case VistaForestCast.rabbit: drawRabbit(ctx, rig, p)
        default: drawCat(ctx, rig, p)
        }
    }

    // MARK: Fairy

    private enum Fairy {
        static let body = 0, bodyTeal = 1, wing = 2, head = 3
    }

    private func bakeFairy(_ u: Double) -> [VistaPart?] {
        let s = VistaInkStyle(rim: 0xFFFFFF, rimAmount: 0.5, line: 1.4, ink: 0.4, gloss: 0.3)
        func body(_ dress: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.2, y: -0.46, width: 0.4, height: 0.56)) { ctx in
                for x in [-0.03, 0.04] { VistaInk.shade(ctx, VistaInk.capsule(x, -0.18, x + 0.01, -0.4, 0.025, 0.02), Tone.skin, s, u: u, rim: 0.3, gloss: 0) }
                let skirt = VistaInk.smooth([(0.0, 0.06), (0.1, -0.02), (0.17, -0.2), (0.08, -0.16), (0.0, -0.24), (-0.08, -0.16), (-0.17, -0.2), (-0.1, -0.02)], tension: 0.4)
                VistaInk.shade(ctx, skirt, dress, s, u: u)
                VistaInk.shade(ctx, VistaInk.ellipse(0, 0.02, 0.06, 0.08), dress, s, u: u, rim: 0.3)
            }
        }
        let wing = VistaPart.bake(u: u, box: CGRect(x: -0.46, y: -0.24, width: 0.48, height: 0.62)) { ctx in
            for (tip, size) in [(CGPoint(x: -0.36, y: 0.3), 0.26), (CGPoint(x: -0.32, y: -0.16), 0.18)] {
                let wing = CGMutablePath()
                wing.move(to: .zero)
                wing.addQuadCurve(to: tip, control: CGPoint(x: -0.05, y: Double(tip.y) * 1.3))
                wing.addQuadCurve(to: .zero, control: CGPoint(x: Double(tip.x) * 1.15, y: Double(tip.y) * 0.2))
                ctx.addPath(wing)
                ctx.setFillColor(VistaInk.color(0xE0FFF8, 0.45))
                ctx.fillPath()
                ctx.addPath(wing)
                ctx.setStrokeColor(VistaInk.color(0xFFFFFF, 0.85))
                ctx.setLineWidth(CGFloat(1.4 / u))
                ctx.strokePath()
                VistaInk.blob(ctx, CGPoint(x: Double(tip.x) * 0.6, y: Double(tip.y) * 0.6), rx: size * 0.3, ry: size * 0.3, VistaInk.color(0xB8FFF0, 0.4))
            }
        }
        let head = VistaPart.bake(u: u, box: CGRect(x: -0.18, y: 0.04, width: 0.36, height: 0.4)) { ctx in
            VistaInk.shade(ctx, VistaInk.ellipse(-0.02, 0.3, 0.12, 0.1), VistaTone(0xFFE8A0, 0xF2B84A, 0x9A6A1A), s, u: u, gloss: 0.3)
            VistaInk.shade(ctx, VistaInk.ellipse(0.0, 0.2, 0.12, 0.12), Tone.skin, s, u: u, rim: 0.4)
            VistaInk.shade(ctx, VistaInk.smooth([(-0.12, 0.22), (-0.08, 0.32), (0.06, 0.33), (0.12, 0.28), (0.02, 0.27), (-0.08, 0.2)], tension: 0.4),
                           VistaTone(0xFFE8A0, 0xF2B84A, 0x9A6A1A), s, u: u, gloss: 0.3)
            VistaInk.blob(ctx, CGPoint(x: 0.06, y: 0.16), rx: 0.03, ry: 0.02, VistaInk.color(0xFF8AA8, 0.6))
        }
        return [body(VistaTone(0xFFC8F0, 0xF07AC8, 0x9A2A7A)), body(VistaTone(0xB8FFF0, 0x4AD8C8, 0x1A7A7A)), wing, head]
    }

    private func drawFairy(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let t = rig.clock
        let pink = rig.creature.id % 2 == 0
        if let glow = VistaSprites.glow(pink ? 0xFFB8F0 : 0xB8FFF0) {
            let pulse = 0.5 + 0.5 * sin(t * 4)
            let r = 0.7 + 0.12 * pulse
            ctx.setAlpha(CGFloat(0.55 + 0.2 * pulse))
            ctx.draw(glow, in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            ctx.setAlpha(1)
        }
        // Wings a blur of fluttering.
        let flutter = sin(t * 38)
        ctx.place(p[Fairy.wing], at: CGPoint(x: -0.04, y: 0.04), angle: 0.25 + flutter * 0.25, sx: 0.85 + 0.15 * flutter)
        ctx.place(p[Fairy.wing], at: CGPoint(x: 0.02, y: 0.04), angle: -0.1 - flutter * 0.25, sx: -(0.75 + 0.15 * flutter), sy: 0.9)
        ctx.place(p[pink ? Fairy.body : Fairy.bodyTeal], at: .zero, angle: sin(t * 1.3) * 0.08)
        ctx.local(at: .zero, angle: rig.gaze.y * 0.2 * rig.attention + sin(t * 1.1) * 0.06) {
            ctx.place(p[Fairy.head], at: .zero)
            VistaFace.bead(ctx, -0.02, 0.21, r: 0.022, look: rig.gaze, blink: rig.blink, color: 0x2A1A3A)
            VistaFace.bead(ctx, 0.06, 0.21, r: 0.02, look: rig.gaze, blink: rig.blink, color: 0x2A1A3A)
        }
    }

    // MARK: Stag

    private enum Stag {
        static let body = 0, head = 1, leg = 2, legFar = 3
        static let hip = CGPoint(x: -0.32, y: 0.5)
        static let shoulder = CGPoint(x: 0.22, y: 0.52)
        static let neck = CGPoint(x: 0.26, y: 0.64)
    }

    private func bakeStag(_ u: Double) -> [VistaPart?] {
        let s = ink
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.5, y: 0.4, width: 0.88, height: 0.34)) { ctx in
            let path = VistaInk.smooth([(-0.46, 0.6), (-0.4, 0.7), (-0.15, 0.72), (0.15, 0.74), (0.32, 0.7), (0.36, 0.58), (0.26, 0.47), (-0.1, 0.45), (-0.38, 0.48)])
            VistaInk.shade(ctx, path, Tone.deer, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(-0.05, 0.47, 0.34, 0.04), VistaInk.color(0xF4E0C8, 0.7), soft: 0.02, u: u)
            VistaInk.shade(ctx, VistaInk.ellipse(-0.45, 0.64, 0.04, 0.05), Tone.cream, s, u: u, gloss: 0)
            // A few pale spots along the back, like a fawn's that never faded.
            var rng = VistaInk.generator(2)
            for _ in 0..<8 { VistaInk.patch(ctx, clip: path, VistaInk.ellipse(rng.range(-0.35, 0.2), rng.range(0.6, 0.68), 0.014, 0.01), VistaInk.color(0xFFF0DC, 0.7), u: u) }
        }
        let head = VistaPart.bake(u: u, pivot: Stag.neck, box: CGRect(x: 0.1, y: 0.54, width: 0.66, height: 0.72)) { ctx in
            let neck = VistaInk.smooth([(0.2, 0.6), (0.28, 0.82), (0.36, 0.94), (0.46, 0.92), (0.42, 0.78), (0.36, 0.6)], tension: 0.45)
            VistaInk.shade(ctx, neck, Tone.deer, s, u: u)
            VistaInk.patch(ctx, clip: neck, VistaInk.ellipse(0.4, 0.78, 0.05, 0.08), VistaInk.color(0xF4E8D8, 0.8), soft: 0.02, u: u)
            // Antlers: branching tines, tipped with a little light.
            ctx.setLineCap(.round)
            for (dx, tone) in [(0.03, Tone.antler.dark), (0.0, Tone.antler.base)] {
                ctx.setStrokeColor(VistaInk.color(tone))
                ctx.setLineWidth(CGFloat(0.022))
                let root = CGPoint(x: 0.42 + dx, y: 0.98)
                let beam = [CGPoint(x: 0.38 + dx, y: 1.08), CGPoint(x: 0.3 + dx, y: 1.16), CGPoint(x: 0.24 + dx, y: 1.22)]
                ctx.move(to: root)
                for b in beam { ctx.addLine(to: b) }
                ctx.strokePath()
                ctx.setLineWidth(CGFloat(0.016))
                for (from, to) in [(beam[0], CGPoint(x: 0.48 + dx, y: 1.14)), (beam[1], CGPoint(x: 0.36 + dx, y: 1.24)), (beam[1], CGPoint(x: 0.2 + dx, y: 1.14)), (beam[0], CGPoint(x: 0.3 + dx, y: 1.06))] {
                    ctx.move(to: from); ctx.addLine(to: to)
                }
                ctx.strokePath()
            }
            for tip in [CGPoint(x: 0.24, y: 1.22), CGPoint(x: 0.48, y: 1.14), CGPoint(x: 0.36, y: 1.24), CGPoint(x: 0.2, y: 1.14)] {
                VistaInk.blob(ctx, tip, rx: 0.04, ry: 0.04, VistaInk.color(0xC8FFE8, 0.6))
            }
            let skull = VistaInk.smooth([(0.36, 0.94), (0.46, 1.0), (0.56, 0.96), (0.68, 0.86), (0.72, 0.8), (0.66, 0.77), (0.54, 0.82), (0.42, 0.86)], tension: 0.45)
            VistaInk.shade(ctx, skull, Tone.deer, s, u: u)
            VistaInk.patch(ctx, clip: skull, VistaInk.ellipse(0.66, 0.8, 0.05, 0.035), VistaInk.color(0xF4E8D8, 0.8), soft: 0.01, u: u)
            VistaInk.oval(ctx, CGPoint(x: 0.71, y: 0.81), rx: 0.014, ry: 0.011, VistaInk.color(0x2A1A14))
            let ear = VistaInk.smooth([(0.42, 0.96), (0.34, 1.02), (0.3, 1.0), (0.38, 0.93)], tension: 0.3)
            VistaInk.shade(ctx, ear, Tone.deer, s, u: u, gloss: 0)
        }
        func leg(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.06, y: -0.54, width: 0.14, height: 0.6)) { ctx in
                VistaInk.shade(ctx, VistaInk.capsule(0, 0.02, 0.01, -0.46, 0.042, 0.022), tone, s, u: u, gloss: 0.1)
                VistaInk.oval(ctx, CGPoint(x: 0.012, y: -0.485), rx: 0.024, ry: 0.018, VistaInk.color(0x2A1A14))
            }
        }
        return [body, head, leg(Tone.deer), leg(Tone.deerFar)]
    }

    private func drawStag(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        // The bow: head lowered, antlers forward, held, then raised again.
        let bow = rig.hold(rise: 0.8, fall: 0.8)
        let s = rig.stride
        func swing(_ phase: Double) -> (Double, Double) {
            guard rig.moving else { return (0, 0) }
            return (sin(s + phase) * 0.38, max(0, cos(s + phase)) * 0.035)
        }
        let (fb, fbl) = swing(.pi / 2), (ff, ffl) = swing(.pi * 1.5)
        ctx.place(p[Stag.legFar], at: CGPoint(x: Stag.hip.x + 0.05, y: Stag.hip.y + fbl), angle: fb)
        ctx.place(p[Stag.legFar], at: CGPoint(x: Stag.shoulder.x + 0.05, y: Stag.shoulder.y + ffl), angle: ff + 0.25 * bow)
        ctx.place(p[Stag.body], at: .zero, sy: 1 + 0.01 * rig.breath)
        let (nb, nbl) = swing(0), (nf, nfl) = swing(.pi)
        ctx.place(p[Stag.leg], at: CGPoint(x: Stag.hip.x, y: Stag.hip.y + nbl), angle: nb)
        ctx.place(p[Stag.leg], at: CGPoint(x: Stag.shoulder.x, y: Stag.shoulder.y + nfl), angle: nf - 0.15 * bow)
        let graze = rig.phase == .wandering && !rig.moving ? max(0, sin(rig.clock * 0.25)) * 0.9 : 0
        ctx.local(at: Stag.neck, angle: -0.75 * bow - graze + rig.gaze.y * 0.15 * rig.attention + (rig.moving ? sin(s * 2) * 0.04 : 0)) {
            ctx.place(p[Stag.head], at: .zero)
            VistaFace.bead(ctx, 0.56 - Stag.neck.x, 0.9 - Stag.neck.y, r: 0.02, look: rig.gaze, blink: max(rig.blink, 0.6 * bow), color: 0x1A100C)
        }
    }

    // MARK: Owl

    private enum Owl {
        static let body = 0, head = 1, wing = 2, wingOpen = 3, wingOpenFar = 4, feet = 5
        static let neck = CGPoint(x: 0.02, y: 0.16)
        static let shoulder = CGPoint(x: -0.02, y: 0.08)
    }

    private func bakeOwl(_ u: Double) -> [VistaPart?] {
        let s = ink
        let outline = VistaInk.smooth([(0.0, -0.42), (0.18, -0.36), (0.26, -0.14), (0.24, 0.08), (0.14, 0.22), (-0.04, 0.24), (-0.18, 0.14), (-0.24, -0.08), (-0.2, -0.3), (-0.12, -0.4)])
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.3, y: -0.48, width: 0.6, height: 0.76)) { ctx in
            VistaInk.shade(ctx, outline, Tone.owl, s, u: u)
            VistaInk.patch(ctx, clip: outline, VistaInk.ellipse(0.08, -0.12, 0.14, 0.24), VistaInk.color(0xF2DCB8, 0.85), soft: 0.03, u: u)
            VistaInk.strokes(ctx, clip: VistaInk.ellipse(0.08, -0.12, 0.14, 0.24), width: 1.4 / u, VistaInk.color(0x8A5A30, 0.6),
                             (0..<10).map { i in let y = -0.3 + Double(i / 2) * 0.08, x = 0.02 + Double(i % 2) * 0.08; return (CGPoint(x: x - 0.02, y: y + 0.01), CGPoint(x: x, y: y - 0.01), CGPoint(x: x + 0.02, y: y + 0.01)) })
        }
        let head = VistaPart.bake(u: u, pivot: Owl.neck, box: CGRect(x: -0.2, y: 0.08, width: 0.46, height: 0.48)) { ctx in
            for (x, lean) in [(-0.08, -0.06), (0.1, 0.04)] {
                let tuft = VistaInk.smooth([(x - 0.04, 0.4), (x + lean, 0.52), (x + 0.04, 0.4)], tension: 0.25)
                VistaInk.shade(ctx, tuft, Tone.owl, s, u: u, gloss: 0)
            }
            let skull = VistaInk.ellipse(0.03, 0.3, 0.19, 0.17)
            VistaInk.shade(ctx, skull, Tone.owl, s, u: u)
            VistaInk.patch(ctx, clip: skull, VistaInk.ellipse(0.0, 0.3, 0.09, 0.09), VistaInk.color(0xF2DCB8), soft: 0.02, u: u)
            VistaInk.patch(ctx, clip: skull, VistaInk.ellipse(0.12, 0.3, 0.09, 0.09), VistaInk.color(0xF2DCB8), soft: 0.02, u: u)
            VistaInk.shade(ctx, VistaInk.smooth([(0.05, 0.27), (0.1, 0.25), (0.075, 0.2)], tension: 0.2), VistaTone(0xFFD07A, 0xE89A2A, 0x8A5A10), s, u: u, rim: 0, gloss: 0.2)
        }
        let wing = VistaPart.bake(u: u, box: CGRect(x: -0.18, y: -0.5, width: 0.32, height: 0.56)) { ctx in
            let path = VistaInk.smooth([(0.0, 0.03), (0.1, 0.0), (0.09, -0.24), (-0.03, -0.46), (-0.14, -0.36), (-0.12, -0.1)])
            VistaInk.shade(ctx, path, VistaTone(0xC89868, 0x8A5A30, 0x4A2A12), s, u: u)
            VistaInk.strokes(ctx, clip: path, width: 1.4 / u, VistaInk.color(0xF2DCB8, 0.5),
                             (0..<4).map { i in let y = -0.1 - Double(i) * 0.08; return (CGPoint(x: -0.08, y: y), CGPoint(x: 0.0, y: y - 0.03), CGPoint(x: 0.06, y: y - 0.02)) })
        }
        func open(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.76, y: -0.12, width: 0.8, height: 0.52)) { ctx in
                let path = VistaInk.smooth([(0.0, 0.04), (-0.2, 0.22), (-0.48, 0.34), (-0.7, 0.3), (-0.64, 0.2), (-0.7, 0.12), (-0.56, 0.06), (-0.6, -0.02), (-0.4, -0.06), (-0.16, -0.07)], tension: 0.45)
                VistaInk.shade(ctx, path, tone, s, u: u)
                VistaInk.strokes(ctx, clip: path, width: 1.4 / u, VistaInk.color(0xF2DCB8, 0.45),
                                 (0..<5).map { i in let x = -0.3 - Double(i) * 0.08; return (CGPoint(x: x + 0.06, y: 0.05), CGPoint(x: x, y: 0.12), CGPoint(x: x - 0.04, y: 0.22)) })
            }
        }
        let feet = VistaPart.bake(u: u, box: CGRect(x: -0.1, y: -0.52, width: 0.26, height: 0.12)) { ctx in
            for x in [-0.03, 0.07] {
                VistaInk.shade(ctx, VistaInk.ellipse(x, -0.44, 0.045, 0.03), VistaTone(0xFFE0A0, 0xE8B05A, 0x8A6A2A), s, u: u, gloss: 0)
            }
        }
        return [body, head, wing, open(VistaTone(0xC89868, 0x8A5A30, 0x4A2A12)), open(VistaTone(0xA87A50, 0x6E4426, 0x3A200E)), feet]
    }

    private func drawOwl(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let c = rig.creature
        let perched = rig.phase == .acting && c.landedAt != nil
        if perched {
            ctx.place(p[Owl.feet], at: .zero)
            ctx.place(p[Owl.body], at: .zero, sy: 1 + 0.02 * rig.breath)
            ctx.place(p[Owl.wing], at: Owl.shoulder)
        } else {
            let flap = sin(c.stride * 1.4)
            ctx.place(p[Owl.wingOpenFar], at: CGPoint(x: Owl.shoulder.x + 0.05, y: Owl.shoulder.y + 0.02), angle: flap * 0.85 + 0.2, sx: 0.92, sy: 0.92)
            ctx.place(p[Owl.body], at: .zero)
            ctx.place(p[Owl.wingOpen], at: Owl.shoulder, angle: flap * 0.85)
        }
        let tilt = rig.attention * (rig.gaze.y * 0.3 + sin(rig.clock * 0.7) * 0.15)
        ctx.local(at: Owl.neck, angle: tilt) {
            ctx.place(p[Owl.head], at: .zero)
            let o = -Double(Owl.neck.y)
            VistaFace.iris(ctx, 0.0, 0.31 + o, r: 0.055, look: rig.gaze, blink: rig.blink, iris: 0xFFA21A, sclera: nil, lid: Tone.owl.base, rest: 0.08)
            VistaFace.iris(ctx, 0.12, 0.31 + o, r: 0.055, look: rig.gaze, blink: rig.blink, iris: 0xFFA21A, sclera: nil, lid: Tone.owl.base, rest: 0.08)
        }
    }

    // MARK: Fox

    private enum Fox {
        static let body = 0, head = 1, tail = 2, leg = 3, legFar = 4
        static let hip = CGPoint(x: -0.24, y: 0.36)
        static let shoulder = CGPoint(x: 0.2, y: 0.38)
        static let neck = CGPoint(x: 0.26, y: 0.54)
        static let tailRoot = CGPoint(x: -0.34, y: 0.52)
    }

    private func bakeFox(_ u: Double) -> [VistaPart?] {
        let s = ink
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.46, y: 0.24, width: 0.86, height: 0.46)) { ctx in
            let path = VistaInk.smooth([(-0.4, 0.46), (-0.34, 0.6), (-0.1, 0.64), (0.18, 0.64), (0.34, 0.58), (0.36, 0.44), (0.24, 0.34), (-0.1, 0.32), (-0.36, 0.36)])
            VistaInk.shade(ctx, path, Tone.fur, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.24, 0.42, 0.1, 0.1), VistaInk.color(0xFFF4E8), soft: 0.03, u: u)
        }
        let head = VistaPart.bake(u: u, pivot: Fox.neck, box: CGRect(x: 0.18, y: 0.44, width: 0.56, height: 0.5)) { ctx in
            let farEar = VistaInk.smooth([(0.44, 0.74), (0.49, 0.91), (0.56, 0.72)], tension: 0.25)
            VistaInk.shade(ctx, farEar, Tone.furFar, s, u: u, gloss: 0)
            let skull = VistaInk.smooth([(0.26, 0.64), (0.31, 0.75), (0.44, 0.78), (0.55, 0.73), (0.68, 0.66), (0.71, 0.63), (0.62, 0.58), (0.48, 0.54), (0.34, 0.53), (0.26, 0.57)])
            VistaInk.shade(ctx, skull, Tone.fur, s, u: u)
            VistaInk.patch(ctx, clip: skull, VistaInk.smooth([(0.4, 0.6), (0.56, 0.62), (0.7, 0.63), (0.62, 0.56), (0.46, 0.53), (0.36, 0.56)]), VistaInk.color(0xFFF4E8), soft: 0.01, u: u)
            let ear = VistaInk.smooth([(0.32, 0.73), (0.35, 0.93), (0.45, 0.75)], tension: 0.25)
            VistaInk.shade(ctx, ear, Tone.fur, s, u: u, gloss: 0.1)
            VistaInk.patch(ctx, clip: ear, VistaInk.smooth([(0.35, 0.86), (0.355, 0.93), (0.39, 0.86)], tension: 0.2), VistaInk.color(0x2E2428), u: u)
            VistaInk.oval(ctx, CGPoint(x: 0.705, y: 0.633), rx: 0.024, ry: 0.019, VistaInk.color(0x1A1214))
        }
        let tail = VistaPart.bake(u: u, pivot: Fox.tailRoot, box: CGRect(x: -0.92, y: 0.36, width: 0.62, height: 0.4)) { ctx in
            let path = VistaInk.smooth([(-0.32, 0.56), (-0.48, 0.64), (-0.68, 0.66), (-0.86, 0.6), (-0.88, 0.52), (-0.76, 0.46), (-0.56, 0.46), (-0.4, 0.48)], tension: 0.55)
            VistaInk.shade(ctx, path, Tone.fur, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(-0.84, 0.56, 0.08, 0.08), VistaInk.color(0xFFF8F0), soft: 0.02, u: u)
        }
        func leg(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.07, y: -0.38, width: 0.18, height: 0.44)) { ctx in
                VistaInk.shade(ctx, VistaInk.capsule(0, 0.02, 0.01, -0.3, 0.05, 0.034), tone, s, u: u, gloss: 0.05)
                let sock = VistaInk.union([VistaInk.capsule(0.0, -0.18, 0.01, -0.3, 0.04, 0.034), VistaInk.ellipse(0.025, -0.32, 0.045, 0.025)])
                VistaInk.shade(ctx, sock, Tone.sock, s, u: u, rim: 0.3, gloss: 0)
            }
        }
        return [body, head, tail, leg(Tone.fur), leg(Tone.furFar)]
    }

    private func drawFox(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        // It sits down, wraps its tail round, cocks its head and wags.
        let sit = rig.hold(rise: 0.5, fall: 0.5)
        let s = rig.stride
        func swing(_ phase: Double) -> (Double, Double) {
            guard rig.moving else { return (0, 0) }
            return (sin(s + phase) * 0.5, max(0, cos(s + phase)) * 0.04)
        }
        let lean = 0.5 * sit
        let (fb, fbl) = swing(.pi), (ff, ffl) = swing(0)
        let shoulder = vistaTurn(Fox.shoulder, about: Fox.hip, by: lean)
        ctx.place(p[Fox.legFar], at: CGPoint(x: Fox.hip.x + 0.04, y: Fox.hip.y + fbl - 0.2 * sit), angle: fb - 1.2 * sit, sy: 1 - 0.4 * sit)
        ctx.place(p[Fox.legFar], at: CGPoint(x: shoulder.x + 0.04, y: shoulder.y + ffl - 0.22 * sit), angle: ff - lean * 0.9, sy: 1 + 0.2 * sit)
        let wag = sin(rig.clock * (sit > 0.5 ? 9 : 2.2)) * (sit > 0.5 ? 0.3 : 0.12) + (rig.moving ? sin(s) * 0.1 : 0)
        ctx.place(p[Fox.tail], at: CGPoint(x: Fox.tailRoot.x, y: Fox.tailRoot.y - 0.25 * sit), angle: wag - 0.5 * sit)
        ctx.local(at: CGPoint(x: Fox.hip.x, y: Fox.hip.y - 0.22 * sit), angle: lean) {
            ctx.place(p[Fox.body], at: CGPoint(x: -Fox.hip.x, y: -Fox.hip.y), sy: 1 + 0.015 * rig.breath)
        }
        let (nb, nbl) = swing(0), (nf, nfl) = swing(.pi)
        ctx.place(p[Fox.leg], at: CGPoint(x: Fox.hip.x, y: Fox.hip.y + nbl - 0.2 * sit), angle: nb - 1.2 * sit, sy: 1 - 0.4 * sit)
        ctx.place(p[Fox.leg], at: CGPoint(x: shoulder.x, y: shoulder.y + nfl - 0.22 * sit), angle: nf - lean * 0.9, sy: 1 + 0.2 * sit)
        let neck = vistaTurn(Fox.neck, about: Fox.hip, by: lean)
        let cock = (rig.attention * 0.6 + 0.6 * sit) * sin(rig.clock * 0.9) * 0.2
        ctx.local(at: CGPoint(x: neck.x, y: neck.y - 0.22 * sit), angle: -lean * 0.8 + cock + rig.gaze.y * 0.25 * rig.attention + (rig.moving ? sin(s * 2) * 0.04 : 0)) {
            ctx.place(p[Fox.head], at: .zero)
            VistaFace.bead(ctx, 0.5 - Fox.neck.x, 0.685 - Fox.neck.y, r: 0.027, look: rig.gaze, blink: rig.blink, color: 0x2A1810)
        }
    }

    // MARK: Rabbit

    private enum Rabbit {
        static let body = 0, head = 1, ear = 2, earFar = 3, foot = 4
        static let neck = CGPoint(x: 0.12, y: 0.5)
    }

    private func bakeRabbit(_ u: Double) -> [VistaPart?] {
        let s = ink
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.44, y: -0.02, width: 0.82, height: 0.62)) { ctx in
            VistaInk.shade(ctx, VistaInk.ellipse(-0.38, 0.28, 0.07, 0.07), Tone.cream, s, u: u, gloss: 0.3)
            let path = VistaInk.smooth([(-0.36, 0.2), (-0.32, 0.42), (-0.12, 0.54), (0.1, 0.52), (0.26, 0.4), (0.28, 0.2), (0.18, 0.04), (-0.12, 0.02), (-0.32, 0.06)])
            VistaInk.shade(ctx, path, Tone.bunny, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.16, 0.18, 0.12, 0.14), VistaInk.color(0xFFF8F0, 0.85), soft: 0.04, u: u)
        }
        let head = VistaPart.bake(u: u, pivot: Rabbit.neck, box: CGRect(x: 0.0, y: 0.38, width: 0.46, height: 0.4)) { ctx in
            let skull = VistaInk.smooth([(0.06, 0.56), (0.12, 0.7), (0.26, 0.72), (0.38, 0.64), (0.42, 0.55), (0.36, 0.47), (0.22, 0.44), (0.1, 0.47)])
            VistaInk.shade(ctx, skull, Tone.bunny, s, u: u)
            VistaInk.patch(ctx, clip: skull, VistaInk.ellipse(0.36, 0.52, 0.07, 0.05), VistaInk.color(0xFFF8F0, 0.9), soft: 0.02, u: u)
            VistaInk.oval(ctx, CGPoint(x: 0.415, y: 0.555), rx: 0.018, ry: 0.013, VistaInk.color(0xE87A9A))
        }
        func ear(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.08, y: -0.02, width: 0.16, height: 0.42)) { ctx in
                let path = VistaInk.smooth([(-0.04, 0.0), (-0.06, 0.2), (-0.02, 0.38), (0.03, 0.36), (0.05, 0.18), (0.04, 0.0)], tension: 0.45)
                VistaInk.shade(ctx, path, tone, s, u: u, gloss: 0.1)
                VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.0, 0.2, 0.02, 0.13), VistaInk.color(0xF2B8C8, 0.85), soft: 0.01, u: u)
            }
        }
        let foot = VistaPart.bake(u: u, box: CGRect(x: -0.1, y: -0.02, width: 0.26, height: 0.1)) { ctx in
            VistaInk.shade(ctx, VistaInk.ellipse(0.03, 0.035, 0.11, 0.035), Tone.cream, s, u: u, gloss: 0)
        }
        return [body, head, ear(Tone.bunny), ear(Tone.bunnyFar), foot]
    }

    private func drawRabbit(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let t = rig.clock
        let sniff = rig.during(0.2, 1.3)
        ctx.place(p[Rabbit.foot], at: CGPoint(x: -0.14, y: 0))
        ctx.local(at: Rabbit.neck, angle: rig.gaze.y * 0.2 * rig.attention + sniff * 0.12 * sin(rig.actTime * 20)) {
            let o = CGPoint(x: -Rabbit.neck.x, y: -Rabbit.neck.y)
            // Ears: they swivel and flop with the hop.
            let flop = rig.moving ? max(0, -sin(rig.stride)) * 0.4 : 0
            ctx.place(p[Rabbit.earFar], at: CGPoint(x: 0.17 + o.x, y: 0.68 + o.y), angle: -0.35 - flop + sin(t * 0.9) * 0.08)
            ctx.place(p[Rabbit.ear], at: CGPoint(x: 0.12 + o.x, y: 0.69 + o.y), angle: -0.15 - flop * 1.2 + sin(t * 0.7 + 1) * 0.12)
        }
        ctx.place(p[Rabbit.body], at: .zero, sy: 1 + 0.02 * rig.breath)
        ctx.local(at: Rabbit.neck, angle: rig.gaze.y * 0.2 * rig.attention + sniff * 0.12 * sin(rig.actTime * 20)) {
            ctx.place(p[Rabbit.head], at: .zero)
            let o = CGPoint(x: -Rabbit.neck.x, y: -Rabbit.neck.y)
            VistaFace.bead(ctx, 0.28 + o.x, 0.6 + o.y, r: 0.03, look: rig.gaze, blink: rig.blink, color: 0x2A1A1A)
            // The nose twitches.
            let twitch = sniff > 0 ? sin(rig.actTime * 30) * 0.008 : 0
            VistaInk.oval(ctx, CGPoint(x: 0.415 + o.x, y: 0.555 + o.y + twitch), rx: 0.02, ry: 0.015, VistaInk.color(0xE87A9A))
        }
        ctx.place(p[Rabbit.foot], at: CGPoint(x: -0.02, y: 0))
    }

    // MARK: Giant cat

    private enum Cat {
        static let head = 0, paw = 1, body = 2
    }

    private func bakeCat(_ u: Double) -> [VistaPart?] {
        let s = VistaInkStyle(rim: 0xA8FFD8, rimAmount: 0.45, line: 2.2, ink: 0.45, gloss: 0.18)
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.5, y: -0.3, width: 1.0, height: 0.62)) { ctx in
            let path = VistaInk.smooth([(-0.44, -0.3), (-0.42, 0.06), (-0.3, 0.24), (0.0, 0.3), (0.3, 0.24), (0.42, 0.06), (0.44, -0.3)])
            VistaInk.shade(ctx, path, Tone.cat, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.0, -0.05, 0.22, 0.28), VistaInk.color(0xF8F4FF, 0.85), soft: 0.05, u: u)
        }
        let head = VistaPart.bake(u: u, box: CGRect(x: -0.46, y: 0.2, width: 0.92, height: 0.74)) { ctx in
            for side in [-1.0, 1.0] {
                let ear = VistaInk.smooth([(side * 0.36, 0.62), (side * 0.36, 0.92), (side * 0.12, 0.76)], tension: 0.25)
                VistaInk.shade(ctx, ear, Tone.cat, s, u: u, gloss: 0)
                VistaInk.patch(ctx, clip: ear, VistaInk.smooth([(side * 0.32, 0.66), (side * 0.33, 0.85), (side * 0.18, 0.75)], tension: 0.2), VistaInk.color(0xF6B8D0, 0.9), soft: 0.01, u: u)
            }
            let skull = VistaInk.smooth([(-0.42, 0.44), (-0.36, 0.7), (0.0, 0.8), (0.36, 0.7), (0.42, 0.44), (0.34, 0.28), (0.0, 0.22), (-0.34, 0.28)], tension: 0.5)
            VistaInk.shade(ctx, skull, Tone.cat, s, u: u)
            VistaInk.patch(ctx, clip: skull, VistaInk.ellipse(0.0, 0.33, 0.2, 0.12), VistaInk.color(0xF8F4FF, 0.9), soft: 0.03, u: u)
            // Stripes on the brow.
            VistaInk.strokes(ctx, clip: skull, width: 3 / u, VistaInk.color(0x8A7AB8, 0.5),
                             [(CGPoint(x: -0.06, y: 0.78), CGPoint(x: -0.05, y: 0.72), CGPoint(x: -0.04, y: 0.66)), (CGPoint(x: 0.0, y: 0.8), CGPoint(x: 0.0, y: 0.73), CGPoint(x: 0.0, y: 0.66)),
                              (CGPoint(x: 0.06, y: 0.78), CGPoint(x: 0.05, y: 0.72), CGPoint(x: 0.04, y: 0.66))])
            let nose = VistaInk.smooth([(-0.035, 0.4), (0.035, 0.4), (0.0, 0.365)], tension: 0.3)
            VistaInk.shade(ctx, nose, VistaTone(0xFFC8DC, 0xF08AB0, 0xA04A70), s, u: u, rim: 0, gloss: 0.3)
            ctx.setStrokeColor(VistaInk.color(0x5A4A7A, 0.9))
            ctx.setLineWidth(CGFloat(2.4 / u))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 0.0, y: 0.365)); ctx.addLine(to: CGPoint(x: 0.0, y: 0.335))
            ctx.move(to: CGPoint(x: -0.06, y: 0.32)); ctx.addQuadCurve(to: CGPoint(x: 0.0, y: 0.335), control: CGPoint(x: -0.03, y: 0.31))
            ctx.move(to: CGPoint(x: 0.06, y: 0.32)); ctx.addQuadCurve(to: CGPoint(x: 0.0, y: 0.335), control: CGPoint(x: 0.03, y: 0.31))
            ctx.strokePath()
            ctx.setStrokeColor(VistaInk.color(0xFFFFFF, 0.85))
            ctx.setLineWidth(CGFloat(1.6 / u))
            for side in [-1.0, 1.0] {
                for k in 0..<3 {
                    let y = 0.36 - Double(k) * 0.025
                    ctx.move(to: CGPoint(x: side * 0.12, y: y)); ctx.addQuadCurve(to: CGPoint(x: side * 0.4, y: y + 0.02 - Double(k) * 0.03), control: CGPoint(x: side * 0.26, y: y + 0.02))
                }
            }
            ctx.strokePath()
        }
        let paw = VistaPart.bake(u: u, box: CGRect(x: -0.14, y: -0.06, width: 0.28, height: 0.2)) { ctx in
            VistaInk.shade(ctx, VistaInk.ellipse(0, 0.04, 0.12, 0.08), Tone.cat, s, u: u)
            ctx.setStrokeColor(VistaInk.color(Tone.cat.dark, 0.7))
            ctx.setLineWidth(CGFloat(1.8 / u))
            for x in [-0.04, 0.04] { ctx.move(to: CGPoint(x: x, y: 0.12)); ctx.addLine(to: CGPoint(x: x, y: 0.07)) }
            ctx.strokePath()
        }
        return [head, paw, body]
    }

    private func drawCat(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let c = rig.creature
        let rise = c.rise
        // It sits behind the bushes; only what rises above them shows.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: -2, y: 0, width: 4, height: 3))
        let sink = (rise - 1) * 1.0
        ctx.translateBy(x: 0, y: CGFloat(sink))
        let sway = sin(rig.clock * 0.8) * 0.04
        ctx.place(p[Cat.body], at: CGPoint(x: 0, y: 0.0), sy: 1 + 0.02 * rig.breath)
        // A slow blink is how a cat says it likes you.
        let slow = rig.during(1.6, 2.6, ease: 0.35)
        ctx.local(at: CGPoint(x: 0, y: 0.18), angle: sway + rig.gaze.x * 0.0 + (rig.attention > 0 ? sin(rig.clock * 0.6) * 0.06 : 0)) {
            ctx.place(p[Cat.head], at: CGPoint(x: 0, y: -0.18))
            for x in [-0.17, 0.17] {
                VistaFace.iris(ctx, x, 0.36, r: 0.085, look: rig.gaze, blink: max(rig.blink, slow), iris: 0x7AE88A, slit: rig.attention < 0.5, lid: Tone.cat.base, rest: 0.1)
            }
            if rig.act > 0.1 {
                VistaInk.blob(ctx, CGPoint(x: -0.26, y: 0.2), rx: 0.06, ry: 0.035, VistaInk.color(0xFF8AB8, 0.5 * rig.act))
                VistaInk.blob(ctx, CGPoint(x: 0.26, y: 0.2), rx: 0.06, ry: 0.035, VistaInk.color(0xFF8AB8, 0.5 * rig.act))
            }
        }
        // Paws over the edge, one lifting to wave.
        let wave = rig.during(2.6, rig.species.actSeconds - 0.6, ease: 0.25)
        ctx.place(p[Cat.paw], at: CGPoint(x: -0.26, y: 0.02 + 0.3 * wave), angle: -0.3 * wave + 0.25 * wave * sin(rig.actTime * 7))
        ctx.place(p[Cat.paw], at: CGPoint(x: 0.26, y: 0.02))
        ctx.restoreGState()
        // The bushes it hides behind, over the foot of it.
        if rise > 0.02 {
            for k in 0..<7 {
                let x = -0.6 + Double(k) * 0.2
                VistaInk.oval(ctx, CGPoint(x: x, y: 0.01 + 0.02 * sin(Double(k) * 2.1)), rx: 0.13, ry: 0.07, VistaInk.color(k % 2 == 0 ? 0x1E4A34 : 0x2A5A3E))
                VistaInk.oval(ctx, CGPoint(x: x - 0.03, y: 0.04), rx: 0.06, ry: 0.025, VistaInk.color(0x5A9A6A, 0.6))
            }
        }
    }
}
