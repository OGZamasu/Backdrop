import CoreGraphics
import Foundation
import simd

/// Who lives in the cove.
enum VistaPirateCast {
    static let parrot = 0, crab = 1, kraken = 2, gull = 3, chest = 4, turtle = 5

    static var cast: VistaCast {
        var layout = VistaLayout()
        layout.farGround = 312
        layout.nearGround = 84
        layout.roamLow = 400
        layout.roamHigh = 650

        var macaw = VistaSpecies(name: "parrot", art: parrot, height: 88, aspect: 0.85, speed: 165)
        macaw.body = .flier
        macaw.act = .perch
        macaw.temper = .prey
        macaw.perchesOnHand = true
        macaw.home = 0.3
        macaw.cry = "AHOY!"
        macaw.band = 420...640

        var nipper = VistaSpecies(name: "crab", art: crab, height: 62, aspect: 1.6, speed: 80)
        nipper.gait = .scuttle
        nipper.temper = .prey
        nipper.home = 0.3
        nipper.actSeconds = 2.4
        nipper.cry = "SNIP SNAP!"
        nipper.cryAt = 0.45
        nipper.beats = [VistaBeat(at: 0.5, event: .burst(.dust, 3, 0.4)), VistaBeat(at: 1.4, event: .jump(200))]

        var arm = VistaSpecies(name: "kraken", art: kraken, height: 500, aspect: 0.6, speed: 56)
        // Under the water it moves over to you quickly; you only see the ripples.
        arm.charge = 3.5
        arm.body = .emerger
        arm.farOnly = true
        arm.temper = .steady
        arm.home = 0.03
        arm.interest = 0.9
        arm.actSeconds = 4.4
        arm.cry = "SPLOOSH!"
        arm.cryAt = 0.5
        arm.beats = [VistaBeat(at: 0.3, event: .burst(.splash, 16, 1.1)), VistaBeat(at: 0.4, event: .shake(3)), VistaBeat(at: 3.8, event: .burst(.splash, 10, 0.8))]

        var gull = VistaSpecies(name: "seagull", art: VistaPirateCast.gull, height: 64, aspect: 1.6, speed: 190)
        gull.body = .flier
        gull.act = .orbit
        gull.temper = .prey
        gull.home = 0.3
        gull.actSeconds = 4.4
        gull.cry = "SQUAWK!"
        gull.band = 470...660

        var loot = VistaSpecies(name: "treasure chest", art: chest, height: 112, aspect: 1.25, speed: 0)
        loot.body = .prop
        loot.temper = .steady
        loot.home = 0.95
        loot.anchorX = 0.87
        loot.interest = 0.9
        loot.actSeconds = 3.4
        loot.beats = [VistaBeat(at: 0.75, event: .burst(.coin, 12, 1)), VistaBeat(at: 0.8, event: .burst(.sparkle, 10, 0.8)),
                      VistaBeat(at: 1.5, event: .burst(.coin, 8, 0.9)), VistaBeat(at: 0.7, event: .say("✨ ✨ ✨", 1.6))]

        var shell = VistaSpecies(name: "sea turtle", art: turtle, height: 72, aspect: 1.6, speed: 30)
        shell.temper = .curious
        shell.home = 0.26
        shell.charge = 1.3
        shell.actSeconds = 2.6
        shell.cry = "ALOHA!"
        shell.cryAt = 0.6
        shell.emitters = [VistaEmitter(kind: .heart, from: 0.8, to: 2.0, rate: 2.5, at: SIMD2(0.6, 0.6), velocity: SIMD2(20, 60), spread: 20)]

        return VistaCast(species: [macaw, nipper, arm, gull, loot, shell], roster: [0, 0, 1, 1, 2, 3, 3, 4, 5], layout: layout, cap: 10, visibleAtStart: 7)
    }
}

/// A tropical cove at sunset: a sun sinking into a glittering sea, palms leaning over the sand, a pirate ship sailing past, and
/// a kraken that rises out of the bay beside you.
final class VistaPirateStage: VistaStage {
    let cast = VistaPirateCast.cast
    let hint = "Wave to scatter them, or hold up a hand for a parrot"
    let accent: UInt32 = 0xE0702E
    let fx = VistaFXColors(dust: 0xF2D2A2, snow: 0xFFF8E8, sparkle: 0xFFE68A, ember: 0xFFB24A, smoke: 0xC8B8A8, water: 0xE0F8FF,
                           notes: [0xFFD166], heart: 0xFF6F91)
    let haze: UInt32 = 0xC8808E
    let hazeAmount = 0.22

    private enum Cove {
        static let sky: UInt32 = 0x2C2464
        static let sun: UInt32 = 0xFFE8A0
        static let sea: UInt32 = 0x2A5A7A
        static let sand: UInt32 = 0xE8B888
        static let foam: UInt32 = 0xFFF6EA
    }
    private let ink = VistaInkStyle(rim: 0xFFC46A, rimAmount: 0.55, line: 2.0, ink: 0.5, gloss: 0.22)

    private enum Tone {
        static let red = VistaTone(0xFF8A6A, 0xE0302A, 0x7A1018)
        static let yellow = VistaTone(0xFFF2A0, 0xFFC830, 0xA8781A)
        static let blue = VistaTone(0x7AC8FF, 0x2A70D8, 0x123A80)
        static let crab = VistaTone(0xFFA27A, 0xF0582E, 0x8A2410)
        static let crabFar = VistaTone(0xE07E5E, 0xC0441E, 0x6A1A0C)
        static let tentacle = VistaTone(0xE89AE0, 0xA8489E, 0x4A1A5A)
        static let underside = VistaTone(0xFFE0E8, 0xF4B4C8, 0xB8708A)
        static let gull = VistaTone(0xFFFFFF, 0xEEF0F4, 0xA8ACC0)
        static let gullWing = VistaTone(0xD8DCE8, 0xA8AEC4, 0x5E6480)
        static let wood = VistaTone(0xC88A52, 0x8A5428, 0x4A2A12)
        static let iron = VistaTone(0x9AA0B8, 0x5A6078, 0x262A38)
        static let gold = VistaTone(0xFFF2B0, 0xF2C94A, 0xA87A1A)
        static let turtle = VistaTone(0xA8E08A, 0x5AA85A, 0x245A2E)
        static let turtleFar = VistaTone(0x88C070, 0x468A48, 0x1C4824)
        static let shell = VistaTone(0xD8B87A, 0x8A6A3A, 0x4A3418)
    }

    private var painting: VistaPainting?
    private var backdrop: VistaLayer?
    private var palms: [VistaLayer] = []
    private var fronds: [[CGImage]] = []
    private var ship: CGImage?
    private var figures: [VistaFigure?]
    private static let swayFrames = 7

    init() { figures = Array(repeating: nil, count: cast.species.count) }

    // MARK: Painting, in steps

    var backdropSteps: Int { 3 }
    var bakeSteps: Int { 6 + cast.species.count }

    func bake(step: Int) {
        switch step {
        case 0:
            painting = VistaPainting(CGRect(x: -48, y: 0, width: 1376, height: 720))
            painting?.paint { ctx in
                paintSky(ctx)
                paintSea(ctx)
            }
        case 1:
            painting?.paint { ctx in paintBeach(ctx) }
        case 2:
            painting?.paint { ctx in paintVignette(ctx) }
            backdrop = painting?.finish(parallax: 12)
            painting = nil
        case 3:
            palms = paintPalms()
        case 4:
            fronds = paintFronds()
        case 5:
            ship = paintShip()
        default:
            let i = step - 6
            guard figures.indices.contains(i) else { return }
            let sp = cast.species[i]
            let u = sp.height * cast.layout.scale(sp.farOnly ? min(1, sp.home + 0.06) : 1)
            let parts: [VistaPart?]
            switch sp.art {
            case VistaPirateCast.parrot: parts = bakeParrot(u)
            case VistaPirateCast.crab: parts = bakeCrab(u)
            case VistaPirateCast.kraken: parts = bakeKraken(u)
            case VistaPirateCast.gull: parts = bakeGull(u)
            case VistaPirateCast.chest: parts = bakeChest(u)
            default: parts = bakeTurtle(u)
            }
            figures[i] = VistaFigure(parts, haze: haze, amount: hazeAmount)
        }
    }

    func isReady(species: Int) -> Bool { figures.indices.contains(species) && figures[species] != nil }

    // MARK: The world

    private static let sun = CGPoint(x: 400, y: 372)
    private static let horizon = 372.0
    private static let shore = 300.0

    private func paintSky(_ ctx: CGContext) {
        VistaInk.fillDown(ctx, CGRect(x: -48, y: Self.horizon - 4, width: 1376, height: 720 - Self.horizon + 4),
                          [(0, VistaInk.color(Cove.sky)), (0.3, VistaInk.color(0x6A3C8A)), (0.58, VistaInk.color(0xD85A7A)), (0.82, VistaInk.color(0xFF8A5A)), (1, VistaInk.color(0xFFC86A))])
        VistaInk.blob(ctx, Self.sun, rx: 760, ry: 300, VistaInk.color(0xFFA060, 0.4))
        VistaInk.blob(ctx, Self.sun, rx: 230, ry: 150, VistaInk.color(0xFFD890, 0.6))
        // The sun, half down.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: -48, y: Self.horizon, width: 1376, height: 400))
        VistaInk.blob(ctx, Self.sun, rx: 110, ry: 110, VistaInk.color(0xFFF2C0, 0.8))
        VistaInk.fill(ctx, VistaInk.ellipse(Double(Self.sun.x), Double(Self.sun.y), 66, 66), [(0, VistaInk.color(0xFFFBE0)), (1, VistaInk.color(0xFFC860))],
                      from: CGPoint(x: 0, y: Self.horizon + 66), to: CGPoint(x: 0, y: Self.horizon))
        ctx.restoreGState()
        for (i, spec) in [(x: 260.0, y: 520.0, w: 560.0, h: 42.0), (x: 860, y: 590, w: 480, h: 38), (x: 1150, y: 480, w: 360, h: 30), (x: 560, y: 650, w: 420, h: 26)].enumerated() {
            VistaInk.cloud(ctx, centre: CGPoint(x: spec.x, y: spec.y), width: spec.w, height: spec.h, body: 0x8A4A8A, lit: 0xFFB08A, alpha: 0.5, seed: UInt64(i + 11))
        }
        // Far islands on the horizon, a few palms on them, and a sea arch on the right.
        let island = VistaInk.smooth([(700, Self.horizon - 2), (760, Self.horizon + 18), (840, Self.horizon + 26), (930, Self.horizon + 14), (990, Self.horizon - 2)])
        ctx.addPath(island)
        ctx.setFillColor(VistaInk.color(0x7A4A7E))
        ctx.fillPath()
        for x in [780.0, 830.0] {
            ctx.setStrokeColor(VistaInk.color(0x5A3460))
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: x, y: Self.horizon + 20)); ctx.addQuadCurve(to: CGPoint(x: x + 6, y: Self.horizon + 46), control: CGPoint(x: x - 2, y: Self.horizon + 36)); ctx.strokePath()
            for a in [0.3, 1.2, 2.0, 2.8] {
                ctx.move(to: CGPoint(x: x + 6, y: Self.horizon + 46)); ctx.addLine(to: CGPoint(x: x + 6 + cos(a) * 12, y: Self.horizon + 46 + sin(a) * 6 - 2))
            }
            ctx.strokePath()
        }
        let arch = CGMutablePath()
        arch.move(to: CGPoint(x: 1080, y: Self.horizon - 2))
        arch.addCurve(to: CGPoint(x: 1150, y: Self.horizon + 70), control1: CGPoint(x: 1086, y: Self.horizon + 50), control2: CGPoint(x: 1110, y: Self.horizon + 72))
        arch.addCurve(to: CGPoint(x: 1250, y: Self.horizon - 2), control1: CGPoint(x: 1200, y: Self.horizon + 70), control2: CGPoint(x: 1240, y: Self.horizon + 40))
        arch.addLine(to: CGPoint(x: 1222, y: Self.horizon - 2))
        arch.addCurve(to: CGPoint(x: 1112, y: Self.horizon - 2), control1: CGPoint(x: 1205, y: Self.horizon + 40), control2: CGPoint(x: 1130, y: Self.horizon + 40))
        arch.closeSubpath()
        VistaInk.fill(ctx, arch, [(0, VistaInk.color(0xA86A7A)), (1, VistaInk.color(0x5A3460))], from: CGPoint(x: 1080, y: Self.horizon + 70), to: CGPoint(x: 1250, y: Self.horizon))
    }

    private func paintSea(_ ctx: CGContext) {
        let rect = CGRect(x: -48, y: Self.shore - 10, width: 1376, height: Self.horizon - Self.shore + 10)
        VistaInk.fillDown(ctx, rect, [(0, VistaInk.color(0xE88A8A)), (0.12, VistaInk.color(0xA85A8A)), (0.5, VistaInk.color(0x4A4A8A)), (0.8, VistaInk.color(Cove.sea)),
                                      (1, VistaInk.color(0x4E8A98))])
        // The sun's path across the water.
        VistaInk.blob(ctx, CGPoint(x: Self.sun.x, y: Self.horizon - 30), rx: 120, ry: 50, VistaInk.color(0xFFC878, 0.35))
        var rng = VistaInk.generator(19)
        ctx.setLineCap(.round)
        for _ in 0..<70 {
            let y = rng.range(Self.shore + 4, Self.horizon - 2)
            let k = (Self.horizon - y) / (Self.horizon - Self.shore)
            let spread = 40 + 90 * k
            let x = Double(Self.sun.x) + rng.range(-spread, spread)
            ctx.setStrokeColor(VistaInk.color(0xFFE8A8, rng.range(0.4, 0.85) * (1 - abs(x - Double(Self.sun.x)) / spread * 0.7)))
            ctx.setLineWidth(CGFloat(1 + 1.5 * k))
            ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + rng.range(6, 24) * (0.4 + k), y: y)); ctx.strokePath()
        }
        // Gentle swell lines.
        for _ in 0..<50 {
            let y = rng.range(Self.shore + 4, Self.horizon - 3)
            let k = (Self.horizon - y) / (Self.horizon - Self.shore)
            let x = rng.range(-40, 1320)
            ctx.setStrokeColor(VistaInk.color(0xFFD8E8, 0.18 + 0.15 * k))
            ctx.setLineWidth(CGFloat(0.8 + k))
            ctx.move(to: CGPoint(x: x, y: y)); ctx.addQuadCurve(to: CGPoint(x: x + 40 + 60 * k, y: y), control: CGPoint(x: x + 25 + 30 * k, y: y + 2))
            ctx.strokePath()
        }
    }

    private func paintBeach(_ ctx: CGContext) {
        let beach = CGMutablePath()
        beach.move(to: CGPoint(x: -48, y: 0))
        var x = -48.0
        while x <= 1336 {
            beach.addLine(to: CGPoint(x: x, y: Self.shore - 8 + 8 * sin(x / 160) + 4 * sin(x / 53)))
            x += 8
        }
        beach.addLine(to: CGPoint(x: 1336, y: 0))
        beach.closeSubpath()
        VistaInk.fill(ctx, beach, [(0, VistaInk.color(0xC89A7A)), (0.08, VistaInk.color(0xF2C890)), (0.45, VistaInk.color(Cove.sand)), (1, VistaInk.color(0x9A6040))],
                      from: CGPoint(x: 0, y: Self.shore), to: CGPoint(x: 0, y: 0))
        ctx.saveGState()
        ctx.addPath(beach)
        ctx.clip()
        // Wet sand at the water's edge, shining with the sky.
        VistaInk.fill(ctx, CGRect(x: -48, y: Self.shore - 30, width: 1376, height: 30), [(0, VistaInk.color(0xD88A8A, 0.55)), (1, VistaInk.color(0xB87A6A, 0))],
                      from: CGPoint(x: 0, y: Self.shore), to: CGPoint(x: 0, y: Self.shore - 30))
        VistaInk.blob(ctx, CGPoint(x: Self.sun.x, y: Self.shore - 14), rx: 160, ry: 10, VistaInk.color(0xFFE0A0, 0.5))
        VistaInk.blob(ctx, CGPoint(x: Self.sun.x, y: 200), rx: 640, ry: 130, VistaInk.color(0xFFD8A0, 0.25))
        var rng = VistaInk.generator(31)
        // Ripples in the sand, in perspective.
        for _ in 0..<90 {
            let t = rng.unit()
            let y = Self.shore - 34 - pow(t, 1.3) * (Self.shore - 40)
            let s = 0.3 + 1.2 * t
            let x0 = rng.range(-40, 1320), w = rng.range(30, 90) * s
            ctx.setStrokeColor(VistaInk.color(rng.chance(0.5) ? 0xFFE6C0 : 0xA87050, rng.range(0.2, 0.4)))
            ctx.setLineWidth(CGFloat(max(0.8, 1.5 * s)))
            ctx.move(to: CGPoint(x: x0, y: y)); ctx.addQuadCurve(to: CGPoint(x: x0 + w, y: y), control: CGPoint(x: x0 + w / 2, y: y + 3 * s))
            ctx.strokePath()
        }
        // Grains.
        for _ in 0..<600 {
            let t = rng.unit()
            let y = Self.shore - 20 - t * (Self.shore - 22)
            let r = 0.5 + 1.3 * t
            ctx.setFillColor(VistaInk.color(rng.chance(0.5) ? 0xFFF0D0 : 0x8A5A3A, rng.range(0.2, 0.5)))
            ctx.fillEllipse(in: CGRect(x: rng.range(-40, 1320), y: y, width: r, height: r))
        }
        // Shells, starfish and stones.
        for _ in 0..<12 {
            let t = rng.unit()
            let y = Self.shore - 40 - t * (Self.shore - 60)
            let s = 0.4 + 0.9 * t
            let p = CGPoint(x: rng.range(0, 1280), y: y)
            switch Int(rng.unit() * 3) {
            case 0:
                VistaInk.shade(ctx, VistaInk.star(Double(p.x), Double(p.y), outer: 9 * s, inner: 4 * s), VistaTone(0xFFB8A8, 0xF07A6A, 0xA03A3A), ink, u: 1, line: false)
            case 1:
                let shell = VistaInk.smooth([(Double(p.x) - 6 * s, Double(p.y)), (Double(p.x), Double(p.y) + 8 * s), (Double(p.x) + 6 * s, Double(p.y)), (Double(p.x), Double(p.y) - 2 * s)], tension: 0.4)
                VistaInk.shade(ctx, shell, VistaTone(0xFFF4E8, 0xF2D8C8, 0xB89A8A), ink, u: 1, line: false)
            default:
                VistaInk.shade(ctx, VistaInk.ellipse(Double(p.x), Double(p.y), 10 * s, 6 * s), VistaTone(0xB8A8A8, 0x7A6A6E, 0x3E3438), ink, u: 1, line: false)
            }
        }
        ctx.restoreGState()
    }

    private func paintVignette(_ ctx: CGContext) {
        let g = VistaInk.gradient([(0, VistaInk.color(0x2A1030, 0)), (0.62, VistaInk.color(0x2A1030, 0)), (1, VistaInk.color(0x2A1030, 0.45))])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 380), startRadius: 0, endCenter: CGPoint(x: 640, y: 380), endRadius: 820, options: [.drawsAfterEndLocation])
    }

    /// Two palms leaning in from the edges: ringed trunks, lit gold on the sunset side.
    private func paintPalms() -> [VistaLayer] {
        func palm(_ rect: CGRect, base: CGPoint, top: CGPoint, bend: Double) -> VistaLayer? {
            VistaInk.layer(rect, parallax: 26) { ctx in
                let steps = 14
                var pts: [CGPoint] = []
                for i in 0...steps {
                    let k = Double(i) / Double(steps)
                    let x = Double(base.x) + (Double(top.x) - Double(base.x)) * k + bend * sin(k * .pi) * 60
                    let y = Double(base.y) + (Double(top.y) - Double(base.y)) * k
                    pts.append(CGPoint(x: x, y: y))
                }
                for i in 0..<steps {
                    let k = Double(i) / Double(steps)
                    let w = 26 - 12 * k
                    let seg = VistaInk.capsule(pts[i], pts[i + 1], w * 0.55, (26 - 12 * (k + 1 / Double(steps))) * 0.55)
                    VistaInk.shade(ctx, seg, VistaTone(0xE8B07A, 0x9A6438, 0x4A2A14), ink, u: 1, rim: 0.6, gloss: 0.1, line: false)
                    ctx.setStrokeColor(VistaInk.color(0x4A2A14, 0.6))
                    ctx.setLineWidth(1.4)
                    ctx.move(to: CGPoint(x: Double(pts[i].x) - w * 0.5, y: pts[i].y)); ctx.addLine(to: CGPoint(x: Double(pts[i].x) + w * 0.5, y: Double(pts[i].y) + 3))
                    ctx.strokePath()
                }
                // Coconuts.
                for (dx, dy) in [(-8.0, -6.0), (6.0, -10.0), (12.0, -2.0)] {
                    VistaInk.shade(ctx, VistaInk.ellipse(Double(top.x) + dx, Double(top.y) + dy, 9, 9), VistaTone(0x9A7A4A, 0x5A3E1E, 0x2A1A0A), ink, u: 1, rim: 0.5, line: false)
                }
            }
        }
        return [palm(CGRect(x: -40, y: 0, width: 300, height: 720), base: CGPoint(x: 40, y: 0), top: CGPoint(x: 130, y: 600), bend: 1),
                palm(CGRect(x: 1020, y: 0, width: 300, height: 720), base: CGPoint(x: 1250, y: 0), top: CGPoint(x: 1150, y: 560), bend: -1)].compactMap { $0 }
    }

    /// The palm crowns at the top corners, in front of everything, drawn at a few angles so that swaying is just a copy.
    private func paintFronds() -> [[CGImage]] {
        func crown(seed: UInt64, flip: Double) -> [CGImage] {
            guard let still = VistaInk.picture(width: 520, height: 300, { ctx in
                var rng = VistaInk.generator(seed)
                let base = CGPoint(x: 260, y: 150)
                for k in 0..<9 {
                    let angle = Double(k) / 9 * 2 * .pi + rng.range(-0.2, 0.2)
                    let length = rng.range(170, 240)
                    let droop = 0.9
                    let bend = droop * (cos(angle) >= 0 ? 1 : -1)
                    var p = base
                    var prev = base
                    let spine = CGMutablePath()
                    spine.move(to: base)
                    for i in 1...14 {
                        let f = Double(i) / 14
                        let heading = angle - bend * f * f * (sin(angle) > -0.3 ? 1 : 0.3)
                        prev = p
                        p = CGPoint(x: Double(p.x) + cos(heading) * length / 14, y: Double(p.y) + sin(heading) * length / 14)
                        spine.addLine(to: p)
                        let size = length * 0.18 * (1 - 0.6 * f)
                        for side in [-1.0, 1.0] {
                            let la = heading + side * 1.25 - 0.25 * side
                            let tip = CGPoint(x: Double(p.x) + cos(la) * size, y: Double(p.y) + sin(la) * size - size * 0.3)
                            let leaf = CGMutablePath()
                            leaf.move(to: prev)
                            leaf.addQuadCurve(to: tip, control: CGPoint(x: (Double(prev.x) + Double(tip.x)) / 2 + cos(la + 0.5) * 4, y: (Double(prev.y) + Double(tip.y)) / 2 + sin(la + 0.5) * 4))
                            leaf.addLine(to: p)
                            leaf.closeSubpath()
                            ctx.addPath(leaf)
                            ctx.setFillColor(VistaInk.mix(0x1E3A22, 0x5A8A3A, 0.2 + 0.6 * f + (side > 0 ? 0.15 : 0)))
                            ctx.fillPath()
                        }
                    }
                    ctx.addPath(spine)
                    ctx.setStrokeColor(VistaInk.color(0x2E4A1E))
                    ctx.setLineWidth(3)
                    ctx.strokePath()
                    // The sunset catches the top of each frond.
                    ctx.addPath(spine)
                    ctx.setStrokeColor(VistaInk.color(0xFFC46A, 0.35))
                    ctx.setLineWidth(1.2)
                    ctx.strokePath()
                }
            }) else { return [] }
            return (0..<Self.swayFrames).compactMap { i in
                let angle = (Double(i) / Double(Self.swayFrames - 1) - 0.5) * 0.08
                return VistaInk.picture(width: 560, height: 340) { ctx in
                    ctx.translateBy(x: 280, y: 170)
                    ctx.rotate(by: CGFloat(angle))
                    if flip < 0 { ctx.scaleBy(x: -1, y: 1) }
                    ctx.draw(still, in: CGRect(x: -260, y: -150, width: 520, height: 300))
                }
            }
        }
        return [crown(seed: 3, flip: 1), crown(seed: 7, flip: -1)].filter { $0.count == Self.swayFrames }
    }

    /// The pirate ship, side on: dark hull with a gold stripe, three masts of sunlit sails, a skull flag.
    private func paintShip() -> CGImage? {
        VistaInk.picture(width: 240, height: 220) { ctx in
            let s = VistaInkStyle(rim: 0xFFC46A, rimAmount: 0.6, line: 1.6, ink: 0.5, gloss: 0.15)
            let hull = CGMutablePath()
            hull.move(to: CGPoint(x: 10, y: 60))
            hull.addLine(to: CGPoint(x: 230, y: 64))
            hull.addCurve(to: CGPoint(x: 196, y: 14), control1: CGPoint(x: 226, y: 40), control2: CGPoint(x: 212, y: 20))
            hull.addLine(to: CGPoint(x: 50, y: 14))
            hull.addCurve(to: CGPoint(x: 10, y: 60), control1: CGPoint(x: 30, y: 18), control2: CGPoint(x: 14, y: 36))
            hull.closeSubpath()
            VistaInk.shade(ctx, hull, VistaTone(0x8A5A3A, 0x4A2A1A, 0x1E1008), s, u: 1)
            ctx.setStrokeColor(VistaInk.color(0xF2C94A))
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: 16, y: 48)); ctx.addLine(to: CGPoint(x: 226, y: 52)); ctx.strokePath()
            for k in 0..<6 { VistaInk.oval(ctx, CGPoint(x: 60 + Double(k) * 24, y: 34), rx: 3.5, ry: 3.5, VistaInk.color(0xFFD27A)) }
            // Masts and sails.
            for (x, top, w) in [(70.0, 170.0, 56.0), (126.0, 200.0, 66.0), (182.0, 160.0, 50.0)] {
                ctx.setStrokeColor(VistaInk.color(0x3A2210))
                ctx.setLineWidth(3)
                ctx.move(to: CGPoint(x: x, y: 60)); ctx.addLine(to: CGPoint(x: x, y: top)); ctx.strokePath()
                for (y0, h) in [(top - 70, 52.0), (top - 22, 34.0)] {
                    let sail = CGMutablePath()
                    sail.move(to: CGPoint(x: x - w / 2, y: y0 + h))
                    sail.addLine(to: CGPoint(x: x + w / 2, y: y0 + h))
                    sail.addQuadCurve(to: CGPoint(x: x + w / 2 - 3, y: y0), control: CGPoint(x: x + w / 2 + 10, y: y0 + h / 2))
                    sail.addLine(to: CGPoint(x: x - w / 2 + 3, y: y0))
                    sail.addQuadCurve(to: CGPoint(x: x - w / 2, y: y0 + h), control: CGPoint(x: x - w / 2 + 8, y: y0 + h / 2))
                    sail.closeSubpath()
                    VistaInk.shade(ctx, sail, VistaTone(0xFFF4E0, 0xF2DCC0, 0xB89878), s, u: 1)
                }
            }
            // The flag: black, with a little white skull.
            let flag = CGRect(x: 126, y: 200, width: 30, height: 18)
            ctx.setFillColor(VistaInk.color(0x1A1418))
            ctx.fill(flag)
            VistaInk.oval(ctx, CGPoint(x: 141, y: 211), rx: 5, ry: 4.5, VistaInk.color(0xFFFFFF))
            ctx.setFillColor(VistaInk.color(0x1A1418))
            ctx.fillEllipse(in: CGRect(x: 137.5, y: 210, width: 3, height: 3))
            ctx.fillEllipse(in: CGRect(x: 141.5, y: 210, width: 3, height: 3))
            ctx.setStrokeColor(VistaInk.color(0xFFFFFF))
            ctx.setLineWidth(1.6)
            ctx.move(to: CGPoint(x: 134, y: 203)); ctx.addLine(to: CGPoint(x: 148, y: 207))
            ctx.move(to: CGPoint(x: 134, y: 207)); ctx.addLine(to: CGPoint(x: 148, y: 203))
            ctx.strokePath()
        }
    }

    // MARK: Each frame

    func paintBackdrop(_ ctx: CGContext, _ frame: VistaFrame) {
        ctx.interpolationQuality = .low
        backdrop?.draw(in: ctx, shift: frame.shift)
        let t = frame.time
        let dx = Double(frame.shift.x) * 12
        drawShip(ctx, t: t, dx: dx)
        // The sun's path glitters.
        if let twinkle = VistaSprites.twinkle(0xFFE8A8) {
            for i in 0..<12 {
                let f = Double(i)
                let k = (f * 0.618).truncatingRemainder(dividingBy: 1)
                let y = Self.shore + 6 + k * (Self.horizon - Self.shore - 10)
                let spread = 40 + 90 * (Self.horizon - y) / (Self.horizon - Self.shore)
                let x = Double(Self.sun.x) + sin(f * 2.3 + t * 0.4) * spread + dx
                let flash = max(0, sin(t * (2 + 0.3 * f) + f * 1.7))
                guard flash > 0.3 else { continue }
                let s = 3 + 6 * flash
                ctx.setAlpha(CGFloat(flash))
                ctx.draw(twinkle, in: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2))
            }
            ctx.setAlpha(1)
        }
        drawFoam(ctx, t: t, dx: dx)
        drawGulls(ctx, t: t, dx: dx)
        for palm in palms { palm.draw(in: ctx, shift: frame.shift) }
        ctx.interpolationQuality = .high
    }

    /// The ship sails slowly across the bay, rocking on the swell.
    private func drawShip(_ ctx: CGContext, t: Double, dx: Double) {
        guard let ship else { return }
        let period = 95.0
        let k = ((t + 38) / period).truncatingRemainder(dividingBy: 1)
        let x = 1380 - k * 1600 + dx
        guard x > -140, x < 1420 else { return }
        let rock = sin(t * 0.9) * 0.025
        let w = 118.0, h = 108.0
        ctx.saveGState()
        ctx.translateBy(x: x, y: Self.horizon - 26 + sin(t * 1.3) * 1.5)
        ctx.rotate(by: CGFloat(rock))
        ctx.draw(ship, in: CGRect(x: -w / 2, y: 0, width: w, height: h))
        ctx.restoreGState()
        ctx.setFillColor(VistaInk.color(0x3A2A5A, 0.35))
        ctx.fillEllipse(in: CGRect(x: x - w * 0.45, y: Self.horizon - 30, width: w * 0.9, height: 6))
    }

    /// Waves washing up the sand and sliding back, a line of foam that comes and goes.
    private func drawFoam(_ ctx: CGContext, t: Double, dx: Double) {
        let wash = 0.5 + 0.5 * sin(t * 0.8)
        ctx.setLineCap(.round)
        for layer in 0..<2 {
            let reach = Self.shore - 6 - wash * 14 - Double(layer) * 6
            let path = CGMutablePath()
            var x = -48.0
            path.move(to: CGPoint(x: x, y: reach))
            while x <= 1336 {
                path.addLine(to: CGPoint(x: x + dx, y: reach + 3 * sin(x / 37 + t * 1.2 + Double(layer)) + 2 * sin(x / 13 + t * 2)))
                x += 16
            }
            ctx.addPath(path)
            ctx.setStrokeColor(VistaInk.color(Cove.foam, layer == 0 ? 0.7 * (0.4 + 0.6 * wash) : 0.35))
            ctx.setLineWidth(layer == 0 ? 3 : 2)
            ctx.strokePath()
        }
    }

    private func drawGulls(_ ctx: CGContext, t: Double, dx: Double) {
        ctx.setStrokeColor(VistaInk.color(0x3A2A4A, 0.7))
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        for i in 0..<3 {
            let f = Double(i)
            let x = (t * (18 + 4 * f) + f * 500).truncatingRemainder(dividingBy: 1500) - 110 + dx * 0.5
            let y = 560 + f * 30 + sin(t * 0.7 + f) * 14
            let flap = sin(t * 6 + f * 2) * 4
            ctx.move(to: CGPoint(x: x - 9, y: y + flap)); ctx.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 4, y: y + 3))
            ctx.addQuadCurve(to: CGPoint(x: x + 9, y: y + flap), control: CGPoint(x: x + 4, y: y + 3))
            ctx.strokePath()
        }
    }

    func paintForeground(_ ctx: CGContext, _ frame: VistaFrame) {
        ctx.interpolationQuality = .low
        let spots: [(x: Double, y: Double, phase: Double)] = [(140, 600, 0), (1150, 570, 2.3)]
        for (i, spot) in spots.enumerated() where i < fronds.count {
            let sway = 0.5 + 0.5 * (0.7 * sin(frame.time * 0.9 + spot.phase) + 0.3 * sin(frame.time * 2.3 + spot.phase * 2))
            let frames = fronds[i]
            let image = frames[min(frames.count - 1, max(0, Int((sway * Double(frames.count - 1)).rounded())))]
            let x = (spot.x + Double(frame.shift.x) * 30 - Double(image.width) / 2).rounded()
            ctx.draw(image, in: CGRect(x: x, y: spot.y - Double(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        ctx.interpolationQuality = .high
    }

    // MARK: The creatures

    func paintCreature(_ ctx: CGContext, _ rig: VistaRig) {
        guard let figure = figures[rig.creature.species] else { return }
        let p = figure.parts(for: rig)
        switch rig.species.art {
        case VistaPirateCast.parrot: drawParrot(ctx, rig, p)
        case VistaPirateCast.crab: drawCrab(ctx, rig, p)
        case VistaPirateCast.kraken: drawKraken(ctx, rig, p)
        case VistaPirateCast.gull: drawGull(ctx, rig, p)
        case VistaPirateCast.chest: drawChest(ctx, rig, p)
        default: drawTurtle(ctx, rig, p)
        }
    }

    /// The chest's golden light, shining up out of it when it opens.
    func paintAura(_ ctx: CGContext, _ rig: VistaRig, _ world: VistaWorld, _ frame: VistaFrame) {
        guard rig.species.art == VistaPirateCast.chest else { return }
        let open = rig.hold(rise: 0.6, fall: 0.5)
        guard open > 0.02, let glow = VistaSprites.glow(0xFFD24A) else { return }
        let top = rig.point(0, 0.62)
        ctx.stampDot(glow, at: top, radius: rig.scale * (0.9 + 0.1 * sin(rig.time * 6)), alpha: 0.75 * open)
        let beam = CGMutablePath()
        beam.move(to: CGPoint(x: Double(top.x) - rig.scale * 0.45, y: top.y))
        beam.addLine(to: CGPoint(x: Double(top.x) + rig.scale * 0.45, y: top.y))
        beam.addLine(to: CGPoint(x: Double(top.x) + rig.scale * 0.85, y: Double(top.y) + rig.scale * 1.4))
        beam.addLine(to: CGPoint(x: Double(top.x) - rig.scale * 0.85, y: Double(top.y) + rig.scale * 1.4))
        beam.closeSubpath()
        VistaInk.fill(ctx, beam, [(0, VistaInk.color(0xFFF2B0, 0.5 * open)), (1, VistaInk.color(0xFFD24A, 0))], from: top, to: CGPoint(x: top.x, y: Double(top.y) + rig.scale * 1.4))
    }

    // MARK: Parrot

    private enum Parrot {
        static let body = 0, head = 1, wing = 2, wingOpen = 3, wingOpenFar = 4, feet = 5, tail = 6
        static let neck = CGPoint(x: 0.04, y: 0.16)
        static let shoulder = CGPoint(x: -0.02, y: 0.1)
    }

    private func bakeParrot(_ u: Double) -> [VistaPart?] {
        let s = ink
        let tail = VistaPart.bake(u: u, box: CGRect(x: -0.3, y: -0.64, width: 0.32, height: 0.5)) { ctx in
            for (k, tone) in [Tone.blue, Tone.red, Tone.yellow].enumerated() {
                let off = Double(k) * 0.04
                let feather = VistaInk.smooth([(-0.04 + off, -0.18), (-0.16 + off, -0.42), (-0.22 + off, -0.6), (-0.12 + off, -0.42), (0.02 + off, -0.2)], tension: 0.4)
                VistaInk.shade(ctx, feather, tone, s, u: u, gloss: 0.1)
            }
        }
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.26, y: -0.36, width: 0.5, height: 0.62)) { ctx in
            let path = VistaInk.smooth([(0.16, 0.16), (0.2, -0.04), (0.12, -0.24), (-0.04, -0.3), (-0.16, -0.18), (-0.18, 0.04), (-0.04, 0.2)])
            VistaInk.shade(ctx, path, Tone.red, s, u: u)
        }
        let head = VistaPart.bake(u: u, pivot: Parrot.neck, box: CGRect(x: -0.14, y: 0.08, width: 0.44, height: 0.38)) { ctx in
            let skull = VistaInk.ellipse(0.06, 0.28, 0.15, 0.14)
            VistaInk.shade(ctx, skull, Tone.red, s, u: u)
            VistaInk.patch(ctx, clip: skull, VistaInk.ellipse(0.13, 0.27, 0.07, 0.06), VistaInk.color(0xFFF8F4), soft: 0.01, u: u)
            let beak = VistaInk.smooth([(0.17, 0.32), (0.27, 0.3), (0.29, 0.22), (0.24, 0.17), (0.25, 0.23), (0.18, 0.24)], tension: 0.35)
            VistaInk.shade(ctx, beak, VistaTone(0xF4ECE0, 0xC8BCAE, 0x5A5048), s, u: u, gloss: 0.3)
            VistaInk.shade(ctx, VistaInk.ellipse(0.2, 0.215, 0.035, 0.025), VistaTone(0x5A5050, 0x2A2224, 0x0A0808), s, u: u, rim: 0, gloss: 0)
        }
        let wing = VistaPart.bake(u: u, box: CGRect(x: -0.24, y: -0.44, width: 0.38, height: 0.5)) { ctx in
            let path = VistaInk.smooth([(0.02, 0.02), (0.1, -0.06), (0.06, -0.24), (-0.06, -0.4), (-0.16, -0.32), (-0.12, -0.08)])
            VistaInk.shade(ctx, path, Tone.blue, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.02, -0.02, 0.1, 0.08), VistaInk.color(Tone.yellow.base), soft: 0.01, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.04, -0.1, 0.08, 0.05), VistaInk.color(0x3AA84A, 0.9), soft: 0.01, u: u)
        }
        func open(_ main: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.76, y: -0.12, width: 0.8, height: 0.52)) { ctx in
                let path = VistaInk.smooth([(0.0, 0.04), (-0.2, 0.22), (-0.48, 0.34), (-0.7, 0.3), (-0.64, 0.2), (-0.7, 0.12), (-0.56, 0.06), (-0.6, -0.02), (-0.4, -0.06), (-0.16, -0.07)], tension: 0.45)
                VistaInk.shade(ctx, path, main, s, u: u)
                VistaInk.patch(ctx, clip: path, VistaInk.ellipse(-0.1, 0.06, 0.16, 0.1), VistaInk.color(Tone.yellow.base), soft: 0.02, u: u)
                VistaInk.patch(ctx, clip: path, VistaInk.ellipse(-0.06, 0.02, 0.08, 0.06), VistaInk.color(Tone.red.base), soft: 0.02, u: u)
            }
        }
        let feet = VistaPart.bake(u: u, box: CGRect(x: -0.1, y: -0.42, width: 0.24, height: 0.14)) { ctx in
            for x in [-0.03, 0.06] { VistaInk.shade(ctx, VistaInk.ellipse(x, -0.33, 0.04, 0.03), VistaTone(0x9A9AA8, 0x5A5A68, 0x2A2A34), s, u: u, gloss: 0) }
        }
        return [body, head, wing, open(Tone.blue), open(VistaTone(0x5A9ADA, 0x1E50A8, 0x0C2A60)), feet, tail]
    }

    private func drawParrot(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let c = rig.creature
        let perched = rig.phase == .acting && c.landedAt != nil
        ctx.place(p[Parrot.tail], at: .zero, angle: perched ? sin(rig.clock * 1.2) * 0.05 : -0.3)
        if perched {
            ctx.place(p[Parrot.feet], at: .zero)
            ctx.place(p[Parrot.body], at: .zero, sy: 1 + 0.02 * rig.breath)
            ctx.place(p[Parrot.wing], at: Parrot.shoulder)
        } else {
            let flap = sin(c.stride * 1.5)
            ctx.place(p[Parrot.wingOpenFar], at: CGPoint(x: Parrot.shoulder.x + 0.05, y: Parrot.shoulder.y + 0.02), angle: flap * 0.85 + 0.2, sx: 0.92, sy: 0.92)
            ctx.place(p[Parrot.body], at: .zero)
            ctx.place(p[Parrot.wingOpen], at: Parrot.shoulder, angle: flap * 0.85)
        }
        // A parrot bobs its head when it talks.
        let bob = rig.phase == .acting ? sin(rig.actTime * 10) * 0.1 * rig.during(1.3, 3.0) : 0
        ctx.local(at: Parrot.neck, angle: bob + rig.gaze.y * 0.25 * rig.attention) {
            ctx.place(p[Parrot.head], at: .zero)
            let o = -Double(Parrot.neck.y)
            VistaFace.iris(ctx, 0.12, 0.3 + o, r: 0.03, look: rig.gaze, blink: rig.blink, iris: 0xF2E8A0, lid: 0xFFF8F4, rest: 0.1)
        }
    }

    // MARK: Crab

    private enum Crab {
        static let shell = 0, claw = 1, clawFar = 2
    }

    private func bakeCrab(_ u: Double) -> [VistaPart?] {
        let s = ink
        let shell = VistaPart.bake(u: u, box: CGRect(x: -0.46, y: 0.04, width: 0.92, height: 0.78)) { ctx in
            // Eye stalks.
            for x in [-0.1, 0.1] {
                VistaInk.shade(ctx, VistaInk.capsule(x, 0.44, x * 1.2, 0.66, 0.025, 0.022), Tone.crab, s, u: u, gloss: 0)
                VistaInk.shade(ctx, VistaInk.ellipse(x * 1.2, 0.7, 0.065, 0.065), VistaTone(0xFFFFFF, 0xF4F0F0, 0xB8B0B0), s, u: u, rim: 0.3)
            }
            let path = VistaInk.smooth([(-0.4, 0.26), (-0.34, 0.42), (0.0, 0.5), (0.34, 0.42), (0.4, 0.26), (0.3, 0.12), (0.0, 0.08), (-0.3, 0.12)], tension: 0.5)
            VistaInk.shade(ctx, path, Tone.crab, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0, 0.14, 0.26, 0.06), VistaInk.color(0xFFD8B8, 0.6), soft: 0.03, u: u)
            for x in [-0.22, -0.08, 0.08, 0.22] { VistaInk.patch(ctx, clip: path, VistaInk.ellipse(x, 0.38, 0.025, 0.018), VistaInk.color(0xFFC8A8, 0.7), u: u) }
        }
        func claw(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.1, y: -0.08, width: 0.46, height: 0.58)) { ctx in
                VistaInk.shade(ctx, VistaInk.capsule(0, 0, 0.08, 0.18, 0.055, 0.05), tone, s, u: u, gloss: 0.1)
                let pincer = VistaInk.smooth([(0.02, 0.2), (0.2, 0.22), (0.3, 0.4), (0.26, 0.48), (0.17, 0.46), (0.16, 0.36), (0.12, 0.42), (0.04, 0.34)], tension: 0.4)
                VistaInk.shade(ctx, pincer, tone, s, u: u, gloss: 0.3)
            }
        }
        return [shell, claw(Tone.crab), claw(Tone.crabFar)]
    }

    private func drawCrab(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let t = rig.clock
        let snap = rig.hold(rise: 0.25, fall: 0.35)
        let pinch = rig.phase == .acting ? max(0, sin(rig.actTime * 16)) : 0
        // Legs: little scuttling strokes on both sides.
        ctx.setStrokeColor(VistaInk.color(Tone.crab.dark))
        ctx.setLineWidth(0.03)
        ctx.setLineCap(.round)
        for side in [-1.0, 1.0] {
            for k in 0..<3 {
                let phase = rig.moving ? sin(rig.stride + Double(k) * 2.1 + (side > 0 ? 1 : 0)) : 0
                let root = CGPoint(x: side * (0.2 + Double(k) * 0.06), y: 0.18)
                let knee = CGPoint(x: side * (0.34 + Double(k) * 0.06), y: 0.2 + 0.04 * phase)
                let foot = CGPoint(x: side * (0.4 + Double(k) * 0.05), y: 0.0 + 0.03 * max(0, phase))
                ctx.move(to: root); ctx.addLine(to: knee); ctx.addLine(to: foot)
            }
        }
        ctx.strokePath()
        let raise = 0.6 * snap
        ctx.place(p[Crab.clawFar], at: CGPoint(x: 0.3, y: 0.26), angle: -0.5 + raise + 0.25 * pinch * snap, sx: -1)
        ctx.place(p[Crab.claw], at: CGPoint(x: -0.3, y: 0.26), angle: 0.5 - raise - 0.25 * pinch * snap)
        ctx.place(p[Crab.shell], at: .zero, sy: 1 + 0.02 * rig.breath)
        for x in [-0.12, 0.12] {
            VistaFace.bead(ctx, x + rig.gaze.x * 0.01, 0.7 + rig.gaze.y * 0.01 + sin(t * 2 + x * 10) * 0.004, r: 0.032, look: rig.gaze, blink: rig.blink)
        }
        ctx.setStrokeColor(VistaInk.color(0x6A1A0E))
        ctx.setLineWidth(0.02)
        ctx.move(to: CGPoint(x: -0.06, y: 0.24)); ctx.addQuadCurve(to: CGPoint(x: 0.06, y: 0.24), control: CGPoint(x: 0, y: 0.2 - 0.04 * snap))
        ctx.strokePath()
    }

    // MARK: Kraken

    private static let segments = 9

    private func bakeKraken(_ u: Double) -> [VistaPart?] {
        let s = VistaInkStyle(rim: 0xFFC46A, rimAmount: 0.6, line: 2.0, ink: 0.5, gloss: 0.25)
        // One piece of arm per joint, each a little thinner, with suckers down the inner side.
        return (0..<Self.segments).map { i in
            let k = Double(i) / Double(Self.segments)
            let w0 = 0.21 * (1 - 0.85 * k), w1 = 0.21 * (1 - 0.85 * (k + 1 / Double(Self.segments)))
            let length = 0.13
            return VistaPart.bake(u: u, box: CGRect(x: -0.2, y: -0.06, width: 0.4, height: length + 0.16)) { ctx in
                let piece = VistaInk.capsule(0, 0, 0, length, w0 * 0.5, max(0.01, w1 * 0.5))
                VistaInk.shade(ctx, piece, Tone.tentacle, s, u: u, gloss: 0.15, line: true)
                let inner = VistaInk.capsule(w0 * 0.22, 0, w1 * 0.22, length, w0 * 0.24, max(0.006, w1 * 0.24))
                VistaInk.patch(ctx, clip: piece, inner, VistaInk.color(Tone.underside.base), soft: 0.004, u: u)
                for j in 0..<2 {
                    let f = (Double(j) + 0.5) / 2
                    let r = (w0 + (w1 - w0) * f) * 0.13
                    let c = CGPoint(x: (w0 + (w1 - w0) * f) * 0.3, y: length * f)
                    VistaInk.oval(ctx, c, rx: r, ry: r, VistaInk.color(Tone.underside.dark))
                    VistaInk.oval(ctx, c, rx: r * 0.55, ry: r * 0.55, VistaInk.color(Tone.underside.light))
                }
            }
        }
    }

    private func drawKraken(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let c = rig.creature
        let t = rig.clock
        let rise = c.rise
        // Rings on the water, and the swirl where it is.
        ctx.setStrokeColor(VistaInk.color(0xFFE8F0, 0.3 + 0.3 * rise))
        ctx.setLineWidth(CGFloat(1.4 / rig.scale))
        let ripple = (t * 0.6).truncatingRemainder(dividingBy: 1)
        for k in 0..<2 {
            let rx = 0.15 + 0.25 * ((ripple + Double(k) * 0.5).truncatingRemainder(dividingBy: 1))
            ctx.strokeEllipse(in: CGRect(x: -rx, y: -0.02, width: rx * 2, height: 0.05))
        }
        guard rise > 0.02 else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: -2, y: 0, width: 4, height: 3))
        // The arm: a chain of pieces that sways, and curls over at the tip as it waves.
        func arm(_ base: CGPoint, scale: Double, phase: Double, lean: Double) {
            var point = base
            var angle = lean
            let wave = rig.act
            for i in 0..<Self.segments {
                let k = Double(i) / Double(Self.segments)
                angle += (sin(t * 1.6 - Double(i) * 0.6 + phase) * 0.16 + wave * sin(rig.actTime * 3.2 - Double(i) * 0.7) * 0.14) * (0.4 + k)
                angle += -0.09 * k * k * (1 + wave)
                ctx.place(p[i], at: point, angle: angle, sx: scale, sy: scale)
                point = CGPoint(x: Double(point.x) - sin(angle) * 0.13 * scale, y: Double(point.y) + cos(angle) * 0.13 * scale)
            }
        }
        let sink = (rise - 1) * 1.2
        arm(CGPoint(x: 0.18, y: sink - 0.1), scale: 0.62, phase: 2.4, lean: -0.35)
        arm(CGPoint(x: -0.05, y: sink), scale: 1.0, phase: 0, lean: 0.12)
        ctx.restoreGState()
        // Foam where it breaks the surface.
        VistaInk.oval(ctx, CGPoint(x: 0.0, y: 0.0), rx: 0.2, ry: 0.035, VistaInk.color(0xFFF6EA, 0.8 * min(1, rise * 3)))
        VistaInk.oval(ctx, CGPoint(x: 0.17, y: 0.0), rx: 0.12, ry: 0.025, VistaInk.color(0xFFF6EA, 0.6 * min(1, rise * 3)))
    }

    // MARK: Seagull

    private enum Gull {
        static let body = 0, wing = 1, wingFar = 2
    }

    private func bakeGull(_ u: Double) -> [VistaPart?] {
        let s = ink
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.52, y: -0.22, width: 1.0, height: 0.42)) { ctx in
            let tail = VistaInk.smooth([(-0.3, 0.0), (-0.5, 0.04), (-0.46, -0.06), (-0.28, -0.06)], tension: 0.3)
            VistaInk.shade(ctx, tail, Tone.gullWing, s, u: u)
            let path = VistaInk.smooth([(0.34, 0.06), (0.24, 0.12), (0.0, 0.1), (-0.32, 0.02), (-0.3, -0.06), (0.0, -0.1), (0.26, -0.06)], tension: 0.5)
            VistaInk.shade(ctx, path, Tone.gull, s, u: u)
            let head = VistaInk.ellipse(0.28, 0.08, 0.1, 0.09)
            VistaInk.shade(ctx, head, Tone.gull, s, u: u)
            let beak = VistaInk.smooth([(0.36, 0.1), (0.47, 0.07), (0.48, 0.05), (0.36, 0.05)], tension: 0.3)
            VistaInk.shade(ctx, beak, VistaTone(0xFFF0A0, 0xF2C230, 0xA87A10), s, u: u, gloss: 0.2)
            VistaInk.oval(ctx, CGPoint(x: 0.455, y: 0.055), rx: 0.008, ry: 0.006, VistaInk.color(0xE0302A))
        }
        func wing(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.5, y: -0.06, width: 0.56, height: 0.56)) { ctx in
                let path = VistaInk.smooth([(0.04, 0.0), (-0.08, 0.24), (-0.2, 0.46), (-0.3, 0.44), (-0.26, 0.24), (-0.16, 0.02)], tension: 0.4)
                VistaInk.shade(ctx, path, tone, s, u: u)
                VistaInk.patch(ctx, clip: path, VistaInk.ellipse(-0.24, 0.42, 0.08, 0.06), VistaInk.color(0x2A2A34), soft: 0.01, u: u)
            }
        }
        return [body, wing(Tone.gullWing), wing(VistaTone(0xB8BCC8, 0x868CA4, 0x464C64))]
    }

    private func drawGull(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let flap = sin(rig.creature.stride * 1.3)
        ctx.place(p[Gull.wingFar], at: CGPoint(x: 0.06, y: 0.04), angle: -0.2 + flap * 0.7, sx: 0.9, sy: 0.9 * (0.6 + 0.4 * abs(flap)))
        ctx.place(p[Gull.body], at: .zero)
        VistaFace.bead(ctx, 0.31, 0.1, r: 0.018, look: rig.gaze, blink: rig.blink)
        ctx.place(p[Gull.wing], at: CGPoint(x: 0.0, y: 0.02), angle: -flap * 0.75, sy: 0.6 + 0.4 * abs(flap))
    }

    // MARK: Treasure chest

    private enum Chest {
        static let box = 0, lid = 1, inside = 2, lidInside = 3
        static let hinge = CGPoint(x: 0, y: 0.56)
    }

    private func bakeChest(_ u: Double) -> [VistaPart?] {
        let s = ink
        let box = VistaPart.bake(u: u, box: CGRect(x: -0.56, y: -0.04, width: 1.12, height: 0.66)) { ctx in
            let body = VistaInk.rounded(CGRect(x: -0.48, y: 0.0, width: 0.96, height: 0.56), 0.06)
            VistaInk.shade(ctx, body, Tone.wood, s, u: u)
            VistaInk.strokes(ctx, clip: body, width: 1.4 / u, VistaInk.color(Tone.wood.dark, 0.6),
                             (0..<4).map { i in let y = 0.1 + Double(i) * 0.12; return (CGPoint(x: -0.48, y: y), CGPoint(x: 0, y: y + 0.01), CGPoint(x: 0.48, y: y)) })
            for x in [-0.34, 0.34] { VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: x - 0.05, y: 0.0, width: 0.1, height: 0.56), 0.02), Tone.iron, s, u: u, gloss: 0.15) }
            let plate = VistaInk.rounded(CGRect(x: -0.08, y: 0.32, width: 0.16, height: 0.18), 0.03)
            VistaInk.shade(ctx, plate, Tone.gold, s, u: u, gloss: 0.4)
            VistaInk.oval(ctx, CGPoint(x: 0, y: 0.41), rx: 0.022, ry: 0.022, VistaInk.color(0x3A2410))
            ctx.setFillColor(VistaInk.color(0x3A2410))
            ctx.fill(CGRect(x: -0.008, y: 0.355, width: 0.016, height: 0.05))
        }
        let lid = VistaPart.bake(u: u, pivot: Chest.hinge, box: CGRect(x: -0.52, y: 0.5, width: 1.04, height: 0.36)) { ctx in
            let top = CGMutablePath()
            top.move(to: CGPoint(x: -0.5, y: 0.56))
            top.addLine(to: CGPoint(x: 0.5, y: 0.56))
            top.addCurve(to: CGPoint(x: -0.5, y: 0.56), control1: CGPoint(x: 0.5, y: 0.9), control2: CGPoint(x: -0.5, y: 0.9))
            top.closeSubpath()
            VistaInk.shade(ctx, top, Tone.wood, s, u: u)
            for x in [-0.34, 0.34] {
                let band = CGMutablePath()
                band.addRect(CGRect(x: x - 0.05, y: 0.55, width: 0.1, height: 0.3))
                ctx.saveGState()
                ctx.addPath(top)
                ctx.clip()
                VistaInk.shade(ctx, band, Tone.iron, s, u: u, gloss: 0.15, line: false)
                ctx.restoreGState()
            }
            VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: -0.07, y: 0.5, width: 0.14, height: 0.12), 0.03), Tone.gold, s, u: u, gloss: 0.4)
        }
        let inside = VistaPart.bake(u: u, box: CGRect(x: -0.48, y: 0.4, width: 0.96, height: 0.3)) { ctx in
            VistaInk.oval(ctx, CGPoint(x: 0, y: 0.56), rx: 0.44, ry: 0.06, VistaInk.color(0x3A1E0A))
            var rng = VistaInk.generator(3)
            for _ in 0..<26 {
                let c = CGPoint(x: rng.range(-0.38, 0.38), y: 0.56 + rng.range(0, 0.08))
                VistaInk.shade(ctx, VistaInk.ellipse(Double(c.x), Double(c.y), 0.045, 0.03), Tone.gold, s, u: u, rim: 0.3, gloss: 0.5, line: false)
            }
            VistaInk.shade(ctx, VistaInk.star(-0.12, 0.64, outer: 0.06, inner: 0.028), VistaTone(0xFFC8E0, 0xF04A8A, 0x8A1040), s, u: u, gloss: 0.6)
            VistaInk.shade(ctx, VistaInk.ellipse(0.16, 0.64, 0.05, 0.04), VistaTone(0xC8F4FF, 0x3AB8E0, 0x0A5A7A), s, u: u, gloss: 0.6)
        }
        // The underside of the lid, seen when it stands open behind the chest.
        let lidInside = VistaPart.bake(u: u, pivot: Chest.hinge, box: CGRect(x: -0.5, y: 0.5, width: 1.0, height: 0.42)) { ctx in
            let face = VistaInk.rounded(CGRect(x: -0.46, y: 0.56, width: 0.92, height: 0.32), 0.05)
            VistaInk.shade(ctx, face, VistaTone(0x8A5428, 0x5A3418, 0x2A1608), s, u: u, rim: 0.4, gloss: 0.05)
            for x in [-0.34, 0.34] { VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: x - 0.05, y: 0.56, width: 0.1, height: 0.32), 0.02), Tone.iron, s, u: u, gloss: 0.1) }
        }
        return [box, lid, inside, lidInside]
    }

    private func drawChest(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let open = rig.hold(rise: 0.6, fall: 0.5)
        // It rattles when it notices you; it snaps shut with a jump when you wave.
        let rattle = rig.phase == .noticing ? sin(rig.creature.phaseTime * 40) * 0.05 * max(0, 1 - rig.creature.phaseTime / 0.8) : 0
        let shut = rig.phase == .backingOff ? max(0, 1 - rig.creature.phaseTime / 0.4) : 0
        ctx.local(at: CGPoint(x: 0, y: 0.02 * shut), angle: rattle) {
            // The lid tips back: its front face shrinks toward the hinge, then its inside rises up behind.
            if open > 0.5 { ctx.place(p[Chest.lidInside], at: Chest.hinge, sy: (open - 0.5) * 2) }
            if open > 0.05 { ctx.place(p[Chest.inside], at: .zero) }
            ctx.place(p[Chest.box], at: .zero)
            if open < 0.5 { ctx.place(p[Chest.lid], at: CGPoint(x: Chest.hinge.x, y: Double(Chest.hinge.y) + abs(rattle) * 0.4), sy: 1 - open * 2) }
        }
    }

    // MARK: Sea turtle

    private enum Turtle {
        static let shell = 0, head = 1, flipper = 2, flipperFar = 3
        static let neck = CGPoint(x: 0.36, y: 0.3)
    }

    private func bakeTurtle(_ u: Double) -> [VistaPart?] {
        let s = ink
        let shell = VistaPart.bake(u: u, box: CGRect(x: -0.54, y: 0.0, width: 1.0, height: 0.62)) { ctx in
            let belly = VistaInk.ellipse(-0.04, 0.16, 0.42, 0.1)
            VistaInk.shade(ctx, belly, VistaTone(0xFFF0C0, 0xE8D090, 0x9A8048), s, u: u, gloss: 0)
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: -0.48, y: 0.16))
            dome.addCurve(to: CGPoint(x: 0.38, y: 0.18), control1: CGPoint(x: -0.42, y: 0.64), control2: CGPoint(x: 0.3, y: 0.66))
            dome.closeSubpath()
            VistaInk.shade(ctx, dome, Tone.shell, s, u: u)
            // Plates on the shell.
            ctx.saveGState()
            ctx.addPath(dome)
            ctx.clip()
            for (x, y, r) in [(-0.06, 0.42, 0.11), (-0.28, 0.32, 0.09), (0.16, 0.32, 0.09), (-0.06, 0.24, 0.08)] {
                let plate = VistaInk.star(x, y, outer: r, inner: r * 0.86, points: 6, turn: 0)
                VistaInk.shade(ctx, plate, VistaTone(0xF2D898, 0xB8904A, 0x6A4A20), s, u: u, rim: 0, gloss: 0.3)
            }
            ctx.restoreGState()
        }
        let head = VistaPart.bake(u: u, pivot: Turtle.neck, box: CGRect(x: 0.26, y: 0.16, width: 0.38, height: 0.3)) { ctx in
            let path = VistaInk.smooth([(0.3, 0.22), (0.4, 0.34), (0.54, 0.38), (0.62, 0.32), (0.6, 0.24), (0.48, 0.2), (0.36, 0.18)], tension: 0.5)
            VistaInk.shade(ctx, path, Tone.turtle, s, u: u)
            var rng = VistaInk.generator(4)
            for _ in 0..<6 { VistaInk.patch(ctx, clip: path, VistaInk.ellipse(rng.range(0.38, 0.56), rng.range(0.26, 0.34), 0.018, 0.014), VistaInk.color(0xD8F0B8, 0.6), u: u) }
            ctx.setStrokeColor(VistaInk.color(0x245A2E))
            ctx.setLineWidth(CGFloat(1.6 / u))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 0.6, y: 0.27)); ctx.addQuadCurve(to: CGPoint(x: 0.52, y: 0.26), control: CGPoint(x: 0.56, y: 0.24))
            ctx.strokePath()
        }
        func flipper(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.06, y: -0.06, width: 0.36, height: 0.16)) { ctx in
                VistaInk.shade(ctx, VistaInk.smooth([(0, 0.03), (0.16, 0.04), (0.28, 0.0), (0.16, -0.03), (0, -0.03)], tension: 0.45), tone, s, u: u, gloss: 0.1)
            }
        }
        return [shell, head, flipper(Tone.turtle), flipper(Tone.turtleFar)]
    }

    private func drawTurtle(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let paddle = rig.moving ? sin(rig.stride) : 0
        ctx.place(p[Turtle.flipperFar], at: CGPoint(x: 0.24, y: 0.12), angle: -0.5 + paddle * 0.4, sx: 0.9, sy: 0.9)
        ctx.place(p[Turtle.flipperFar], at: CGPoint(x: -0.36, y: 0.1), angle: -2.7 - paddle * 0.3, sx: 0.6, sy: 0.6)
        let nod = rig.phase == .acting ? sin(rig.actTime * 5) * 0.12 * rig.act : 0
        ctx.local(at: Turtle.neck, angle: nod + rig.gaze.y * 0.2 * rig.attention + (rig.moving ? sin(rig.stride * 2) * 0.05 : 0)) {
            ctx.place(p[Turtle.head], at: .zero)
            VistaFace.bead(ctx, 0.52 - Turtle.neck.x, 0.32 - Turtle.neck.y, r: 0.026, look: rig.gaze, blink: rig.blink)
        }
        ctx.place(p[Turtle.shell], at: .zero, sy: 1 + 0.012 * rig.breath)
        ctx.place(p[Turtle.flipper], at: CGPoint(x: 0.18, y: 0.1), angle: -0.6 - paddle * 0.4)
        ctx.place(p[Turtle.flipper], at: CGPoint(x: -0.4, y: 0.08), angle: -2.6 + paddle * 0.3, sx: 0.65, sy: 0.65)
    }
}
