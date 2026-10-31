import CoreGraphics
import Foundation
import simd

/// Who lives round the castle.
enum VistaDragonCast {
    static let dragon = 0, knight = 1, bat = 2, unicorn = 3, raven = 4, hatchling = 5

    static var cast: VistaCast {
        var layout = VistaLayout()
        layout.farGround = 300
        layout.nearGround = 84
        layout.roamLow = 400
        layout.roamHigh = 660

        var wyrm = VistaSpecies(name: "dragon", art: dragon, height: 250, aspect: 1.9, speed: 125)
        wyrm.body = .soarer
        wyrm.farOnly = true
        wyrm.temper = .brute
        wyrm.spot = .flank
        wyrm.home = 0.16
        wyrm.interest = 1.1
        wyrm.actSeconds = 3.6
        wyrm.cry = "ROOOAR!"
        wyrm.cryAt = 0.55
        wyrm.band = 520...640
        wyrm.beats = [VistaBeat(at: 0.75, event: .shake(4))]
        wyrm.emitters = [VistaEmitter(kind: .ember, from: 0.8, to: 2.9, rate: 28, at: SIMD2(0.95, -0.2), velocity: SIMD2(160, -120), spread: 90)]

        var squire = VistaSpecies(name: "knight", art: knight, height: 150, aspect: 0.7, speed: 66)
        squire.home = 0.24
        squire.actSeconds = 2.6
        squire.cry = "HUZZAH!"
        squire.cryAt = 0.55
        squire.beats = [VistaBeat(at: 0.7, event: .burst(.sparkle, 4, 0.6))]

        var flitter = VistaSpecies(name: "bat", art: bat, height: 58, aspect: 1.8, speed: 210)
        flitter.body = .flier
        flitter.act = .orbit
        flitter.temper = .prey
        flitter.home = 0.3
        flitter.actSeconds = 4.6
        flitter.cry = "EEK!"
        flitter.band = 430...660

        var horn = VistaSpecies(name: "unicorn", art: unicorn, height: 250, aspect: 1.3, speed: 70)
        horn.farOnly = true
        horn.temper = .prey
        horn.home = 0.1
        horn.charge = 1.6
        horn.actSeconds = 3.0
        horn.actReach = 1.25
        horn.cry = "NEIGH!"
        horn.cryAt = 0.7
        horn.beats = [VistaBeat(at: 0.75, event: .burst(.sparkle, 10, 1))]
        horn.emitters = [VistaEmitter(kind: .sparkle, from: 0.7, to: 2.4, rate: 14, at: SIMD2(0.28, 1.32), velocity: SIMD2(40, 60), spread: 50)]

        var crow = VistaSpecies(name: "raven", art: raven, height: 74, aspect: 0.95, speed: 165)
        crow.body = .flier
        crow.act = .perch
        crow.temper = .prey
        crow.perchesOnHand = true
        crow.home = 0.3
        crow.cry = "CAW!"
        crow.band = 430...640

        var baby = VistaSpecies(name: "baby dragon", art: hatchling, height: 96, aspect: 1.15, speed: 52)
        baby.gait = .waddle
        baby.home = 0.3
        baby.actSeconds = 2.4
        baby.cry = "ACHOO!"
        baby.cryAt = 1.0
        baby.beats = [VistaBeat(at: 1.0, event: .jump(260)), VistaBeat(at: 1.0, event: .burst(.smoke, 6, 0.8))]
        baby.emitters = [VistaEmitter(kind: .ember, from: 1.0, to: 1.25, rate: 40, at: SIMD2(0.5, 0.5), velocity: SIMD2(180, 40), spread: 60)]

        return VistaCast(species: [wyrm, squire, flitter, horn, crow, baby], roster: [0, 1, 1, 2, 2, 3, 4, 5], layout: layout, cap: 9, visibleAtStart: 6)
    }
}

/// A castle on a hill at dusk: the sky going from gold to violet, flags snapping on the towers, torches on the old wall, and a
/// dragon that circles overhead and comes down to breathe fire beside you.
final class VistaDragonStage: VistaStage {
    let cast = VistaDragonCast.cast
    let hint = "Wave to scatter them, or hold up a hand for the raven"
    let accent: UInt32 = 0xD8643C
    let fx = VistaFXColors(dust: 0xC9B08A, snow: 0xFFF6E0, sparkle: 0xFFE6A8, ember: 0xFF8A2A, smoke: 0x8E8496, water: 0xDDF2FF,
                           notes: [0xFFD166], heart: 0xFF6F91)
    let haze: UInt32 = 0x9A6A92
    let hazeAmount = 0.24

    private enum Dusk {
        static let top: UInt32 = 0x191338
        static let glow: UInt32 = 0xFFB060
        static let stoneLit: UInt32 = 0xD8A48A
        static let stoneShade: UInt32 = 0x5E4668
        static let roof: UInt32 = 0x4A3C9A
        static let window: UInt32 = 0xFFD27A
        static let meadow: UInt32 = 0x3E5C3A
    }
    private let ink = VistaInkStyle(rim: 0xFFB070, rimAmount: 0.5, line: 2.0, ink: 0.5, gloss: 0.2)

    private enum Tone {
        static let dragon = VistaTone(0x7CE8A8, 0x2E9E6E, 0x12483A)
        static let dragonFar = VistaTone(0x56B884, 0x247A58, 0x0C3428)
        static let belly = VistaTone(0xFFF0B8, 0xF2CF7A, 0xB0883A)
        static let membrane = VistaTone(0xFFA27A, 0xE0664A, 0x8A2E2E)
        static let membraneFar = VistaTone(0xD87A60, 0xB04A3A, 0x6A2228)
        static let horn = VistaTone(0xFFF8E4, 0xE8D8B0, 0x9A8460)
        static let steel = VistaTone(0xFFFFFF, 0xC4CCDC, 0x6A7290)
        static let steelFar = VistaTone(0xD6DCE8, 0x9EA6BC, 0x50587A)
        static let tabard = VistaTone(0x6A8CFF, 0x3550C8, 0x1A2470)
        static let bat = VistaTone(0x9C88C0, 0x5E4C80, 0x2A2040)
        static let batWing = VistaTone(0x7A6098, 0x4A3868, 0x22182E)
        static let unicorn = VistaTone(0xFFFFFF, 0xF2EEFA, 0xB4A8D4)
        static let unicornFar = VistaTone(0xE0DAEE, 0xCCC4E2, 0x9488B8)
        static let gold = VistaTone(0xFFF2B0, 0xF2C94A, 0xA87A1A)
        static let raven = VistaTone(0x5A5A7E, 0x26263C, 0x0C0C16)
        static let baby = VistaTone(0xFFB27A, 0xF0703A, 0x9A3418)
    }

    private var painting: VistaPainting?
    private var backdrop: VistaLayer?
    private var walls: [VistaLayer] = []
    private var figures: [VistaFigure?]

    init() { figures = Array(repeating: nil, count: cast.species.count) }

    // MARK: Painting, in steps

    var backdropSteps: Int { 3 }
    var bakeSteps: Int { 4 + cast.species.count }

    func bake(step: Int) {
        switch step {
        case 0:
            painting = VistaPainting(CGRect(x: -48, y: 0, width: 1376, height: 720))
            painting?.paint { ctx in
                paintSky(ctx)
                paintHills(ctx)
            }
        case 1:
            painting?.paint { ctx in paintCastle(ctx) }
        case 2:
            painting?.paint { ctx in
                paintMeadow(ctx)
                paintVignette(ctx)
            }
            backdrop = painting?.finish(parallax: 12)
            painting = nil
        case 3:
            walls = paintWalls()
        default:
            let i = step - 4
            guard figures.indices.contains(i) else { return }
            let sp = cast.species[i]
            let u = sp.height * cast.layout.scale(sp.farOnly ? min(1, sp.home + 0.06) : 1)
            let parts: [VistaPart?]
            switch sp.art {
            case VistaDragonCast.dragon: parts = bakeDragon(u)
            case VistaDragonCast.knight: parts = bakeKnight(u)
            case VistaDragonCast.bat: parts = bakeBat(u)
            case VistaDragonCast.unicorn: parts = bakeUnicorn(u)
            case VistaDragonCast.raven: parts = bakeRaven(u)
            default: parts = bakeHatchling(u)
            }
            figures[i] = VistaFigure(parts, haze: haze, amount: hazeAmount)
        }
    }

    func isReady(species: Int) -> Bool { figures.indices.contains(species) && figures[species] != nil }

    // MARK: The world

    private static let sun = CGPoint(x: 300, y: 338)
    /// The castle: where its towers stand, for the flags and windows that move.
    private static let flagTips: [CGPoint] = [CGPoint(x: 907, y: 512), CGPoint(x: 1015, y: 596), CGPoint(x: 1127, y: 502)]
    private static let windows: [CGPoint] = [CGPoint(x: 1010, y: 430), CGPoint(x: 907, y: 425), CGPoint(x: 1127, y: 418), CGPoint(x: 1015, y: 500), CGPoint(x: 960, y: 384), CGPoint(x: 1068, y: 384)]

    private func paintSky(_ ctx: CGContext) {
        VistaInk.fillDown(ctx, CGRect(x: -48, y: 280, width: 1376, height: 440), [(0, VistaInk.color(Dusk.top)), (0.28, VistaInk.color(0x33215E)), (0.52, VistaInk.color(0x7A3A78)),
                                                                                   (0.76, VistaInk.color(0xD8625E)), (0.9, VistaInk.color(0xF79A5A)), (1, VistaInk.color(0xFFC478))])
        var rng = VistaInk.generator(13)
        for _ in 0..<60 {
            let p = CGPoint(x: rng.range(-48, 1328), y: rng.range(560, 720))
            let r = rng.range(0.5, 1.2)
            ctx.setFillColor(VistaInk.color(0xFFFFFF, rng.range(0.2, 0.7) * Double(p.y - 540) / 180))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        // The sun has just gone down behind the hills on the left.
        VistaInk.blob(ctx, Self.sun, rx: 700, ry: 260, VistaInk.color(0xFF9A50, 0.4))
        VistaInk.blob(ctx, Self.sun, rx: 260, ry: 110, VistaInk.color(0xFFD890, 0.6))
        VistaInk.blob(ctx, Self.sun, rx: 70, ry: 40, VistaInk.color(0xFFF2C8, 0.9))
        // A crescent moon, high on the right.
        let moon = CGPoint(x: 1150, y: 650)
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: moon.x - 22, y: moon.y - 22, width: 44, height: 44))
        ctx.clip()
        ctx.addRect(CGRect(x: moon.x - 60, y: moon.y - 60, width: 120, height: 120))
        ctx.addEllipse(in: CGRect(x: moon.x - 12, y: moon.y - 16, width: 44, height: 44))
        ctx.clip(using: .evenOdd)
        VistaInk.blob(ctx, moon, rx: 60, ry: 60, VistaInk.color(0xFFF4D8, 1), inner: 0.4)
        ctx.restoreGState()
        VistaInk.blob(ctx, moon, rx: 80, ry: 80, VistaInk.color(0xFFE8C0, 0.12))
        // Long clouds lit from below by the sunset.
        for (i, spec) in [(x: 200.0, y: 470.0, w: 520.0, h: 46.0), (x: 760, y: 540, w: 460, h: 40), (x: 1120, y: 470, w: 380, h: 34), (x: 480, y: 610, w: 420, h: 30), (x: 980, y: 640, w: 300, h: 24)].enumerated() {
            let warm = 1 - Double(spec.y - 440) / 260
            VistaInk.cloud(ctx, centre: CGPoint(x: spec.x, y: spec.y), width: spec.w, height: spec.h, body: VistaInk.mixHex(0x8A4A86, 0x5A3470, 1 - warm),
                           lit: VistaInk.mixHex(0xFFB27A, 0xE88A9A, 1 - warm), alpha: 0.55, seed: UInt64(i + 3))
        }
    }

    private func paintHills(_ ctx: CGContext) {
        // Far ranges, lost in the haze.
        let far = VistaInk.ridge(left: -48, width: 1376, base: 372, bottom: 280, amplitude: 44, wavelength: 210, seed: 2)
        VistaInk.fill(ctx, far, [(0, VistaInk.color(0x8A5A8E)), (1, VistaInk.color(0xC27A86))], from: CGPoint(x: 0, y: 420), to: CGPoint(x: 0, y: 300))
        let mid = VistaInk.ridge(left: -48, width: 1376, base: 345, bottom: 280, amplitude: 26, wavelength: 150, seed: 6)
        VistaInk.fill(ctx, mid, [(0, VistaInk.color(0x6A4478)), (1, VistaInk.color(0x8E5A80))], from: CGPoint(x: 0, y: 370), to: CGPoint(x: 0, y: 300))
        VistaInk.blob(ctx, CGPoint(x: Self.sun.x, y: 330), rx: 420, ry: 40, VistaInk.color(0xFFC078, 0.45))
        // The castle's hill on the right, and the unicorn's hill on the left.
        let castleHill = VistaInk.smooth([(640, 280), (760, 318), (880, 350), (1010, 362), (1160, 352), (1290, 330), (1360, 300), (1360, 280)])
        VistaInk.fill(ctx, castleHill, [(0, VistaInk.color(0x5E5470)), (1, VistaInk.color(0x2E2C40))], from: CGPoint(x: 0, y: 362), to: CGPoint(x: 0, y: 280))
        let leftHill = VistaInk.smooth([(-60, 280), (-40, 326), (120, 346), (260, 352), (420, 340), (560, 310), (640, 284)])
        VistaInk.fill(ctx, leftHill, [(0, VistaInk.color(0x6A6A5A)), (1, VistaInk.color(0x34384A))], from: CGPoint(x: 0, y: 352), to: CGPoint(x: 0, y: 280))
        ctx.addPath(leftHill)
        ctx.setStrokeColor(VistaInk.color(0xFFC078, 0.5))
        ctx.setLineWidth(1.6)
        ctx.strokePath()
        // Trees on the slopes, dark against the glow, rimmed with gold on the side toward the sun.
        var rng = VistaInk.generator(21)
        for _ in 0..<26 {
            let x = rng.range(-30, 1310)
            if x > 860, x < 1170 { continue }
            let base = 300 + rng.range(-6, 36) * (x < 640 ? 1 : 0.6)
            let h = rng.range(26, 54)
            if rng.chance(0.5) {
                let pine = CGMutablePath()
                pine.move(to: CGPoint(x: x, y: base + h)); pine.addLine(to: CGPoint(x: x + h * 0.26, y: base)); pine.addLine(to: CGPoint(x: x - h * 0.26, y: base)); pine.closeSubpath()
                ctx.addPath(pine)
                ctx.setFillColor(VistaInk.color(0x2A2238))
                ctx.fillPath()
            } else {
                for k in 0..<4 {
                    VistaInk.oval(ctx, CGPoint(x: x + rng.range(-h * 0.25, h * 0.25), y: base + h * 0.5 + rng.range(-h * 0.1, h * 0.25)), rx: h * 0.32, ry: h * 0.28, VistaInk.color(0x2E2640))
                    if k == 0 { VistaInk.oval(ctx, CGPoint(x: x - h * 0.2, y: base + h * 0.62), rx: h * 0.14, ry: h * 0.14, VistaInk.color(0xC27A5A, 0.35)) }
                }
                ctx.setFillColor(VistaInk.color(0x2A2238))
                ctx.fill(CGRect(x: x - 2, y: base, width: 4, height: h * 0.4))
            }
        }
    }

    /// The castle: curtain wall, keep, three towers with pointed roofs, lit windows, a gate.
    private func paintCastle(_ ctx: CGContext) {
        func stone(_ rect: CGRect) {
            VistaInk.fill(ctx, CGPath(rect: rect, transform: nil), [(0, VistaInk.color(Dusk.stoneLit)), (0.55, VistaInk.color(0xA07890)), (1, VistaInk.color(Dusk.stoneShade))],
                          from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.minY))
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.setStrokeColor(VistaInk.color(0x3E2A48, 0.35))
            ctx.setLineWidth(0.8)
            var y = Double(rect.minY) + 7
            var row = 0
            while y < Double(rect.maxY) {
                ctx.move(to: CGPoint(x: rect.minX, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                var x = Double(rect.minX) + (row % 2 == 0 ? 0 : 7)
                while x < Double(rect.maxX) { ctx.move(to: CGPoint(x: x, y: y - 7)); ctx.addLine(to: CGPoint(x: x, y: y)); x += 14 }
                y += 7
                row += 1
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        func battlements(_ x0: Double, _ x1: Double, _ y: Double) {
            var x = x0
            while x < x1 - 4 { stone(CGRect(x: x, y: y, width: min(8, x1 - x), height: 8)); x += 13 }
        }
        func tower(_ cx: Double, _ width: Double, _ top: Double, _ roof: Double) {
            stone(CGRect(x: cx - width / 2, y: 340, width: width, height: top - 340))
            // A cylinder: darker toward the right.
            VistaInk.fill(ctx, CGRect(x: cx - width / 2, y: 340, width: width, height: top - 340),
                          [(0, VistaInk.color(0x000000, 0)), (0.6, VistaInk.color(0x2A1A38, 0.1)), (1, VistaInk.color(0x2A1A38, 0.45))],
                          from: CGPoint(x: cx - width / 2, y: 0), to: CGPoint(x: cx + width / 2, y: 0))
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: cx - width / 2 - 6, y: top)); cone.addLine(to: CGPoint(x: cx, y: roof)); cone.addLine(to: CGPoint(x: cx + width / 2 + 6, y: top)); cone.closeSubpath()
            VistaInk.fill(ctx, cone, [(0, VistaInk.color(0x8A7ADA)), (0.45, VistaInk.color(Dusk.roof)), (1, VistaInk.color(0x1E1848))],
                          from: CGPoint(x: cx - width / 2, y: roof), to: CGPoint(x: cx + width / 2, y: top))
            ctx.addPath(cone)
            ctx.setStrokeColor(VistaInk.color(0x1A1438, 0.7))
            ctx.setLineWidth(1)
            ctx.strokePath()
            ctx.setStrokeColor(VistaInk.color(0xFFC078, 0.6))
            ctx.setLineWidth(1.4)
            ctx.move(to: CGPoint(x: cx - width / 2 - 6, y: top)); ctx.addLine(to: CGPoint(x: cx, y: roof)); ctx.strokePath()
            // The flagpole.
            ctx.setStrokeColor(VistaInk.color(0x2A2030))
            ctx.setLineWidth(1.6)
            ctx.move(to: CGPoint(x: cx, y: roof)); ctx.addLine(to: CGPoint(x: cx, y: roof + 22)); ctx.strokePath()
        }
        VistaInk.blob(ctx, CGPoint(x: 1015, y: 420), rx: 220, ry: 140, VistaInk.color(0xFFB878, 0.12))
        tower(1015, 34, 520, 592)
        stone(CGRect(x: 975, y: 340, width: 76, height: 130))
        battlements(975, 1051, 470)
        stone(CGRect(x: 890, y: 340, width: 250, height: 62))
        battlements(890, 1140, 402)
        tower(907, 36, 450, 508)
        tower(1127, 36, 440, 498)
        // The gate.
        let gate = CGMutablePath()
        gate.move(to: CGPoint(x: 1000, y: 340)); gate.addLine(to: CGPoint(x: 1000, y: 366))
        gate.addArc(center: CGPoint(x: 1015, y: 366), radius: 15, startAngle: .pi, endAngle: 0, clockwise: true)
        gate.addLine(to: CGPoint(x: 1030, y: 340)); gate.closeSubpath()
        ctx.addPath(gate)
        ctx.setFillColor(VistaInk.color(0x1E1424))
        ctx.fillPath()
        ctx.setStrokeColor(VistaInk.color(0x6A5A40, 0.8))
        ctx.setLineWidth(1)
        for x in stride(from: 1003.0, through: 1027, by: 6) { ctx.move(to: CGPoint(x: x, y: 340)); ctx.addLine(to: CGPoint(x: x, y: 378)) }
        ctx.strokePath()
        // Windows, warm inside.
        for w in Self.windows {
            VistaInk.blob(ctx, w, rx: 14, ry: 14, VistaInk.color(Dusk.window, 0.35))
            let arch = CGMutablePath()
            arch.move(to: CGPoint(x: w.x - 3.5, y: w.y - 6)); arch.addLine(to: CGPoint(x: w.x - 3.5, y: w.y + 2))
            arch.addArc(center: CGPoint(x: w.x, y: w.y + 2), radius: 3.5, startAngle: .pi, endAngle: 0, clockwise: true)
            arch.addLine(to: CGPoint(x: w.x + 3.5, y: w.y - 6)); arch.closeSubpath()
            ctx.addPath(arch)
            ctx.setFillColor(VistaInk.color(Dusk.window))
            ctx.fillPath()
        }
    }

    private func paintMeadow(_ ctx: CGContext) {
        let ground = VistaInk.ridge(left: -48, width: 1376, base: 300, bottom: 0, amplitude: 8, wavelength: 200, seed: 9)
        VistaInk.fill(ctx, ground, [(0, VistaInk.color(0x7A6A6A)), (0.15, VistaInk.color(0x5E6A50)), (0.5, VistaInk.color(Dusk.meadow)), (1, VistaInk.color(0x1C2C1E))],
                      from: CGPoint(x: 0, y: 300), to: CGPoint(x: 0, y: 0))
        ctx.saveGState()
        ctx.addPath(ground)
        ctx.clip()
        VistaInk.blob(ctx, CGPoint(x: Self.sun.x, y: 290), rx: 700, ry: 120, VistaInk.color(0xFFB070, 0.28))
        // A dirt path winding down toward the castle.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1000, y: 302))
        path.addCurve(to: CGPoint(x: 760, y: 170), control1: CGPoint(x: 900, y: 270), control2: CGPoint(x: 700, y: 230))
        path.addCurve(to: CGPoint(x: 900, y: -10), control1: CGPoint(x: 820, y: 110), control2: CGPoint(x: 940, y: 60))
        path.addLine(to: CGPoint(x: 1180, y: -10))
        path.addCurve(to: CGPoint(x: 850, y: 170), control1: CGPoint(x: 1080, y: 60), control2: CGPoint(x: 860, y: 110))
        path.addCurve(to: CGPoint(x: 1012, y: 302), control1: CGPoint(x: 800, y: 240), control2: CGPoint(x: 950, y: 280))
        path.closeSubpath()
        VistaInk.fill(ctx, path, [(0, VistaInk.color(0xB89A86)), (1, VistaInk.color(0x6E5440))], from: CGPoint(x: 0, y: 300), to: CGPoint(x: 0, y: 0))
        var rng = VistaInk.generator(33)
        // Grass, finer far off; flowers; stones.
        let tones: [UInt32] = [0x2E4A2C, 0x4E6E3E, 0x6A8A4A, 0x243A24, 0x8AA05A]
        for _ in 0..<1500 {
            let t = rng.unit()
            let y = 296 - pow(t, 1.3) * 300
            let s = 0.2 + 1.1 * pow(t, 1.2)
            VistaInk.blade(ctx, at: CGPoint(x: rng.range(-48, 1328), y: y), height: rng.range(6, 16) * s, lean: rng.range(-4, 4) * s, width: max(0.7, 1.5 * s),
                           color: VistaInk.color(tones[Int(rng.unit() * 5) % 5], rng.range(0.4, 0.8)))
        }
        let petals: [UInt32] = [0xFF9AC8, 0xFFE38A, 0xFFFFFF, 0xC8A8FF]
        for _ in 0..<220 {
            let t = rng.unit()
            let y = 294 - pow(t, 1.3) * 296
            let r = 0.8 + 2.4 * t
            ctx.setFillColor(VistaInk.color(petals[Int(rng.unit() * 4) % 4], rng.range(0.6, 0.95)))
            ctx.fillEllipse(in: CGRect(x: rng.range(-48, 1328), y: y, width: r, height: r))
        }
        ctx.restoreGState()
    }

    private func paintVignette(_ ctx: CGContext) {
        let g = VistaInk.gradient([(0, VistaInk.color(0x140C24, 0)), (0.62, VistaInk.color(0x140C24, 0)), (1, VistaInk.color(0x140C24, 0.5))])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 380), startRadius: 0, endCenter: CGPoint(x: 640, y: 380), endRadius: 820, options: [.drawsAfterEndLocation])
    }

    /// The old stone wall across the bottom corners, each end with a torch bracket.
    private func paintWalls() -> [VistaLayer] {
        func wall(_ rect: CGRect, seed: UInt64) -> VistaLayer? {
            VistaInk.layer(rect, parallax: 40) { ctx in
                var rng = VistaInk.generator(seed)
                let style = VistaInkStyle(rim: 0xFFB070, rimAmount: 0.55, line: 2, ink: 0.55, gloss: 0.1)
                for row in 0..<3 {
                    var x = Double(rect.minX) - 20 + Double(row % 2) * 24
                    let y = 2 + Double(row) * 28
                    while x < Double(rect.maxX) + 10 {
                        let w = rng.range(40, 62)
                        let lift = row == 2 ? rng.range(-6, 10) : 0
                        let block = VistaInk.rounded(CGRect(x: x, y: y, width: w - 3, height: 26 + lift), 6)
                        VistaInk.shade(ctx, block, VistaTone(0xC8A0A0, 0x86687A, 0x3E2C44), style, u: 1)
                        if rng.chance(0.4) { VistaInk.oval(ctx, CGPoint(x: x + w * 0.4, y: y + 22 + lift), rx: w * 0.3, ry: 4, VistaInk.color(0x5E8A4A, 0.85)) }
                        x += w
                    }
                }
                // The torch: a wooden pole in an iron bracket.
                let torchX = Double(rect.midX) + (Double(rect.minX) < 400 ? 40 : -40)
                VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: torchX - 6, y: 70, width: 12, height: 62), 4), VistaTone(0xB08458, 0x7A5432, 0x3A2414), style, u: 1)
                VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: torchX - 10, y: 120, width: 20, height: 14), 4), VistaTone(0x8A8A9A, 0x4A4A5A, 0x1E1E28), style, u: 1)
            }
        }
        return [wall(CGRect(x: -30, y: 0, width: 280, height: 140), seed: 4), wall(CGRect(x: 1040, y: 0, width: 270, height: 140), seed: 8)].compactMap { $0 }
    }

    // MARK: Each frame

    func paintBackdrop(_ ctx: CGContext, _ frame: VistaFrame) {
        ctx.interpolationQuality = .low
        backdrop?.draw(in: ctx, shift: frame.shift)
        let dx = Double(frame.shift.x) * 12
        // Candlelight in the windows.
        if let glow = VistaSprites.glow(Dusk.window) {
            for (i, w) in Self.windows.enumerated() {
                let flicker = 0.6 + 0.25 * sin(frame.time * (5 + Double(i)) + Double(i) * 2) + 0.15 * sin(frame.time * 13.7 + Double(i))
                ctx.stampDot(glow, at: CGPoint(x: Double(w.x) + dx, y: w.y), radius: 9, alpha: 0.35 * flicker)
            }
        }
        // Flags snapping in the wind on the towers.
        for (i, tip) in Self.flagTips.enumerated() {
            drawFlag(ctx, at: CGPoint(x: Double(tip.x) + dx, y: Double(tip.y) + 20), time: frame.time + Double(i) * 1.7, colors: i == 1 ? (0xE84A4A, 0xFFD24A) : (0x3E5CD8, 0xFFD24A))
        }
        drawBats(ctx, frame)
        ctx.interpolationQuality = .high
    }

    /// A pennant: a strip with a wave running along it, lit where it faces the sunset.
    private func drawFlag(_ ctx: CGContext, at top: CGPoint, time: Double, colors: (UInt32, UInt32)) {
        let length = 30.0, height = 11.0
        let steps = 8
        var upper: [CGPoint] = [], lower: [CGPoint] = []
        for k in 0...steps {
            let f = Double(k) / Double(steps)
            let wave = sin(time * 7 - f * 4.5) * 3.2 * f
            let droop = f * 2
            let taper = height * (1 - f * 0.55)
            upper.append(CGPoint(x: Double(top.x) - f * length, y: Double(top.y) + wave - droop))
            lower.append(CGPoint(x: Double(top.x) - f * length, y: Double(top.y) + wave - droop - taper))
        }
        let flag = CGMutablePath()
        flag.addLines(between: upper + lower.reversed())
        flag.closeSubpath()
        ctx.addPath(flag)
        ctx.setFillColor(VistaInk.color(colors.0))
        ctx.fillPath()
        // Folds: lighter on the crests.
        for k in 0..<steps {
            let f = Double(k) / Double(steps)
            let light = 0.5 + 0.5 * cos(time * 7 - f * 4.5)
            let quad = CGMutablePath()
            quad.addLines(between: [upper[k], upper[k + 1], lower[k + 1], lower[k]])
            quad.closeSubpath()
            ctx.addPath(quad)
            ctx.setFillColor(VistaInk.color(light > 0.5 ? 0xFFFFFF : 0x000000, abs(light - 0.5) * 0.35))
            ctx.fillPath()
        }
        ctx.setStrokeColor(VistaInk.color(colors.1, 0.9))
        ctx.setLineWidth(1.2)
        ctx.addLines(between: upper)
        ctx.strokePath()
    }

    /// A few far bats flitting round the towers.
    private func drawBats(_ ctx: CGContext, _ frame: VistaFrame) {
        ctx.setFillColor(VistaInk.color(0x1E1430, 0.85))
        for i in 0..<4 {
            let f = Double(i)
            let a = frame.time * (0.6 + 0.1 * f) + f * 1.7
            let x = 1015 + cos(a) * (110 + 20 * f) + Double(frame.shift.x) * 12
            let y = 560 + sin(a * 1.3) * 40 + f * 8
            let flap = sin(frame.time * 14 + f) * 3
            let bat = CGMutablePath()
            bat.move(to: CGPoint(x: x - 6, y: y + flap)); bat.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 3, y: y - 2))
            bat.addQuadCurve(to: CGPoint(x: x + 6, y: y + flap), control: CGPoint(x: x + 3, y: y - 2))
            bat.addLine(to: CGPoint(x: x, y: y + 1.5))
            bat.closeSubpath()
            ctx.addPath(bat)
            ctx.fillPath()
        }
    }

    func paintForeground(_ ctx: CGContext, _ frame: VistaFrame) {
        ctx.interpolationQuality = .low
        for wall in walls { wall.draw(in: ctx, shift: frame.shift) }
        // The torches burn.
        for (i, base) in [CGPoint(x: 150, y: 134), CGPoint(x: 1135, y: 134)].enumerated() {
            let p = CGPoint(x: Double(base.x) + Double(frame.shift.x) * 40, y: base.y)
            drawFlame(ctx, at: p, time: frame.time + Double(i) * 3.1, size: 30)
        }
        ctx.interpolationQuality = .high
    }

    /// A torch flame: glow, then layered tongues of fire that flicker and lean.
    private func drawFlame(_ ctx: CGContext, at p: CGPoint, time: Double, size: Double) {
        if let glow = VistaSprites.glow(0xFF9A3A) {
            ctx.stampDot(glow, at: CGPoint(x: p.x, y: p.y + size * 0.6), radius: size * (3.2 + 0.3 * sin(time * 9)), alpha: 0.35)
        }
        let lean = sin(time * 2.3) * 0.25 + sin(time * 7.1) * 0.1
        for (k, (tone, scale)) in [(0xE8401E as UInt32, 1.0), (0xFF8A2A as UInt32, 0.78), (0xFFD24A as UInt32, 0.55), (0xFFF6D0 as UInt32, 0.32)].enumerated() {
            let h = size * scale * (1.2 + 0.12 * sin(time * (11 + Double(k) * 3) + Double(k)))
            let w = size * scale * 0.42
            let tip = CGPoint(x: Double(p.x) + lean * h, y: Double(p.y) + h * 1.4)
            let flame = CGMutablePath()
            flame.move(to: CGPoint(x: p.x, y: Double(p.y) - w * 0.2))
            flame.addCurve(to: tip, control1: CGPoint(x: Double(p.x) + w * 1.1, y: Double(p.y) + h * 0.2), control2: CGPoint(x: Double(p.x) + w * 0.4 + lean * h * 0.5, y: Double(p.y) + h * 0.9))
            flame.addCurve(to: CGPoint(x: p.x, y: Double(p.y) - w * 0.2), control1: CGPoint(x: Double(p.x) - w * 0.4 + lean * h * 0.5, y: Double(p.y) + h * 0.9), control2: CGPoint(x: Double(p.x) - w * 1.1, y: Double(p.y) + h * 0.2))
            ctx.addPath(flame)
            ctx.setFillColor(VistaInk.color(tone, 0.92))
            ctx.fillPath()
        }
        // A spark or two.
        if let ember = VistaSprites.glow(0xFFB24A) {
            for k in 0..<3 {
                let f = (time * 0.9 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                ctx.stampDot(ember, at: CGPoint(x: Double(p.x) + sin(time * 3 + Double(k) * 2) * 8 * f, y: Double(p.y) + size * 1.3 + f * 70), radius: 3.5 * (1 - f), alpha: 1 - f)
            }
        }
    }

    // MARK: The creatures

    func paintCreature(_ ctx: CGContext, _ rig: VistaRig) {
        guard let figure = figures[rig.creature.species] else { return }
        let p = figure.parts(for: rig)
        switch rig.species.art {
        case VistaDragonCast.dragon: drawDragon(ctx, rig, p)
        case VistaDragonCast.knight: drawKnight(ctx, rig, p)
        case VistaDragonCast.bat: drawBat(ctx, rig, p)
        case VistaDragonCast.unicorn: drawUnicorn(ctx, rig, p)
        case VistaDragonCast.raven: drawRaven(ctx, rig, p)
        default: drawHatchling(ctx, rig, p)
        }
    }

    // MARK: Dragon

    private enum Dragon {
        static let body = 0, head = 1, jaw = 2, wing = 3, wingFar = 4, tail = 5, leg = 6, legFar = 7
        static let neck = CGPoint(x: 0.34, y: 0.06)
        static let jawPivot = CGPoint(x: 0.66, y: 0.15)
        static let shoulder = CGPoint(x: 0.12, y: 0.14)
        static let tailRoot = CGPoint(x: -0.46, y: 0.0)
        /// The tip of the snout, in the head's frame before it turns.
        static let snout = CGPoint(x: 0.86, y: 0.15)
    }

    /// How far the dragon's head is turned down toward where it breathes, and how hard it is breathing right now.
    private func breath(_ rig: VistaRig) -> (angle: Double, fire: Double) {
        let fire = rig.during(0.65, rig.species.actSeconds - 0.6, ease: 0.2)
        guard rig.phase == .acting else { return (0, 0) }
        let c = rig.creature
        let mouth = rig.point(Double(Dragon.snout.x), Double(Dragon.snout.y))
        var toward = SIMD2(c.aim.x - Double(mouth.x), c.aim.y - Double(mouth.y))
        toward.x *= c.turn >= 0 ? 1 : -1
        let angle = max(-1.1, min(0.15, atan2(toward.y, max(1, toward.x))))
        return (angle * rig.hold(rise: 0.5, fall: 0.5), fire)
    }

    private func bakeDragon(_ u: Double) -> [VistaPart?] {
        let s = ink
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.56, y: -0.24, width: 1.0, height: 0.52)) { ctx in
            let outline = VistaInk.smooth([(0.38, 0.06), (0.24, 0.17), (0.0, 0.19), (-0.24, 0.15), (-0.46, 0.07), (-0.52, -0.04), (-0.36, -0.14), (-0.08, -0.18), (0.22, -0.15), (0.38, -0.06)])
            // Spines along the back.
            for k in 0..<7 {
                let x = -0.4 + Double(k) * 0.11
                let y = 0.17 - pow(abs(x + 0.02) / 0.5, 2) * 0.1
                let spike = CGMutablePath()
                spike.move(to: CGPoint(x: x - 0.035, y: y - 0.02)); spike.addLine(to: CGPoint(x: x - 0.01, y: y + 0.07)); spike.addLine(to: CGPoint(x: x + 0.035, y: y - 0.02)); spike.closeSubpath()
                VistaInk.shade(ctx, spike, Tone.horn, s, u: u, rim: 0.4, gloss: 0)
            }
            VistaInk.shade(ctx, outline, Tone.dragon, s, u: u)
            let belly = VistaInk.smooth([(0.36, -0.04), (0.2, -0.13), (-0.08, -0.16), (-0.34, -0.12), (-0.2, -0.06), (0.1, -0.05)])
            VistaInk.patch(ctx, clip: outline, belly, VistaInk.color(Tone.belly.base), soft: 0.004, u: u)
            VistaInk.strokes(ctx, clip: belly, width: 1.4 / u, VistaInk.color(Tone.belly.dark, 0.7),
                             (0..<7).map { i in let x = 0.3 - Double(i) * 0.09; return (CGPoint(x: x, y: -0.02), CGPoint(x: x - 0.02, y: -0.08), CGPoint(x: x - 0.01, y: -0.15)) })
            // Scales: a scatter of small arcs.
            var rng = VistaInk.generator(6)
            VistaInk.strokes(ctx, clip: outline, width: 1.2 / u, VistaInk.color(Tone.dragon.dark, 0.35),
                             (0..<26).map { _ in let x = rng.range(-0.44, 0.3), y = rng.range(-0.02, 0.15); return (CGPoint(x: x - 0.02, y: y), CGPoint(x: x, y: y - 0.02), CGPoint(x: x + 0.02, y: y)) })
        }
        let head = VistaPart.bake(u: u, pivot: Dragon.neck, box: CGRect(x: 0.24, y: -0.06, width: 0.7, height: 0.52)) { ctx in
            let neck = VistaInk.capsule(0.34, 0.04, 0.58, 0.18, 0.1, 0.075)
            VistaInk.shade(ctx, neck, Tone.dragon, s, u: u)
            VistaInk.patch(ctx, clip: neck, VistaInk.capsule(0.38, -0.02, 0.6, 0.11, 0.05, 0.03), VistaInk.color(Tone.belly.base), soft: 0.004, u: u)
            for (a, b, c) in [((0.6, 0.27), (0.5, 0.38), (0.46, 0.4)), ((0.66, 0.27), (0.6, 0.4), (0.55, 0.44))] {
                let horn = VistaInk.smooth([(a.0 - 0.025, a.1), (b.0, b.1), (c.0, c.1), (b.0 + 0.03, b.1 - 0.02), (a.0 + 0.025, a.1)], tension: 0.35)
                VistaInk.shade(ctx, horn, Tone.horn, s, u: u, gloss: 0.3)
            }
            let skull = VistaInk.smooth([(0.55, 0.2), (0.6, 0.28), (0.7, 0.29), (0.79, 0.24), (0.88, 0.2), (0.9, 0.165), (0.84, 0.145), (0.7, 0.14), (0.58, 0.13)])
            VistaInk.shade(ctx, skull, Tone.dragon, s, u: u)
            VistaInk.oval(ctx, CGPoint(x: 0.86, y: 0.19), rx: 0.012, ry: 0.008, VistaInk.color(0x0C2A20))
            // A brow ridge over the eye.
            ctx.setStrokeColor(VistaInk.color(Tone.dragon.dark, 0.8))
            ctx.setLineWidth(CGFloat(2 / u))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 0.66, y: 0.255)); ctx.addQuadCurve(to: CGPoint(x: 0.75, y: 0.245), control: CGPoint(x: 0.7, y: 0.27))
            ctx.strokePath()
        }
        let jaw = VistaPart.bake(u: u, pivot: Dragon.jawPivot, box: CGRect(x: 0.6, y: 0.04, width: 0.3, height: 0.14)) { ctx in
            VistaInk.shade(ctx, VistaInk.smooth([(0.62, 0.15), (0.78, 0.145), (0.87, 0.135), (0.84, 0.105), (0.7, 0.095), (0.62, 0.11)]), Tone.belly, s, u: u, gloss: 0)
        }
        func wing(_ tone: VistaTone, _ bone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.72, y: -0.06, width: 0.8, height: 0.68)) { ctx in
                let tips = [CGPoint(x: -0.56, y: 0.58), CGPoint(x: -0.68, y: 0.36), CGPoint(x: -0.6, y: 0.14)]
                let wrist = CGPoint(x: -0.16, y: 0.5)
                let membrane = CGMutablePath()
                membrane.move(to: CGPoint(x: 0.02, y: 0.02))
                membrane.addLine(to: wrist)
                membrane.addLine(to: tips[0])
                membrane.addQuadCurve(to: tips[1], control: CGPoint(x: -0.5, y: 0.44))
                membrane.addQuadCurve(to: tips[2], control: CGPoint(x: -0.52, y: 0.24))
                membrane.addQuadCurve(to: CGPoint(x: -0.12, y: -0.02), control: CGPoint(x: -0.36, y: 0.12))
                membrane.closeSubpath()
                VistaInk.shade(ctx, membrane, tone, s, u: u, gloss: 0.12)
                ctx.setStrokeColor(VistaInk.color(bone.base))
                ctx.setLineCap(.round)
                ctx.setLineWidth(CGFloat(0.03))
                ctx.move(to: CGPoint(x: 0.02, y: 0.02)); ctx.addLine(to: wrist); ctx.strokePath()
                ctx.setLineWidth(CGFloat(0.016))
                for tip in tips { ctx.move(to: wrist); ctx.addLine(to: tip) }
                ctx.strokePath()
                VistaInk.shade(ctx, VistaInk.star(Double(wrist.x), Double(wrist.y) + 0.03, outer: 0.035, inner: 0.012, points: 3), Tone.horn, s, u: u, rim: 0, gloss: 0)
            }
        }
        let tail = VistaPart.bake(u: u, pivot: Dragon.tailRoot, box: CGRect(x: -1.02, y: -0.14, width: 0.62, height: 0.3)) { ctx in
            let path = VistaInk.smooth([(-0.42, 0.06), (-0.62, 0.05), (-0.8, 0.08), (-0.9, 0.06), (-0.8, 0.03), (-0.62, -0.02), (-0.42, -0.08)], tension: 0.45)
            VistaInk.shade(ctx, path, Tone.dragon, s, u: u)
            let spade = VistaInk.smooth([(-0.88, 0.06), (-0.96, 0.13), (-1.0, 0.06), (-0.96, -0.0), (-0.88, 0.05)], tension: 0.3)
            VistaInk.shade(ctx, spade, Tone.membrane, s, u: u)
        }
        func leg(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.08, y: -0.22, width: 0.22, height: 0.28)) { ctx in
                VistaInk.shade(ctx, VistaInk.capsule(0, 0, 0.06, -0.14, 0.06, 0.035), tone, s, u: u, gloss: 0.05)
                ctx.setStrokeColor(VistaInk.color(0xF2E8D0))
                ctx.setLineWidth(CGFloat(2.4 / u))
                ctx.setLineCap(.round)
                for k in 0..<3 {
                    let x = 0.05 + Double(k) * 0.025
                    ctx.move(to: CGPoint(x: x, y: -0.165)); ctx.addLine(to: CGPoint(x: x + 0.018, y: -0.19))
                }
                ctx.strokePath()
            }
        }
        return [body, head, jaw, wing(Tone.membrane, Tone.dragon), wing(Tone.membraneFar, Tone.dragonFar), tail, leg(Tone.dragon), leg(Tone.dragonFar)]
    }

    private func drawDragon(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let t = rig.clock
        let c = rig.creature
        // Wings beat steadily; hovering to breathe, they beat harder.
        let hovering = rig.phase == .acting || rig.phase == .noticing
        let beat = sin(t * (hovering ? 7.5 : 5.2))
        let (headAngle, fire) = breath(rig)
        ctx.place(p[Dragon.wingFar], at: CGPoint(x: Dragon.shoulder.x + 0.06, y: Dragon.shoulder.y + 0.03), angle: 0.15 + beat * 0.55, sx: 0.92, sy: 0.92)
        ctx.place(p[Dragon.legFar], at: CGPoint(x: -0.26, y: -0.1), angle: -0.4)
        ctx.place(p[Dragon.tail], at: Dragon.tailRoot, angle: sin(t * 1.6) * 0.18 + (c.vel.y > 30 ? -0.1 : 0))
        ctx.place(p[Dragon.body], at: .zero, sy: 1 + 0.015 * rig.breath)
        ctx.place(p[Dragon.leg], at: CGPoint(x: -0.32, y: -0.12), angle: -0.5)
        ctx.place(p[Dragon.leg], at: CGPoint(x: 0.24, y: -0.1), angle: -0.2 + 0.1 * beat)
        let look = rig.attention * rig.gaze.y * 0.25 * (1 - rig.act)
        ctx.local(at: Dragon.neck, angle: headAngle + look + sin(t * 1.2) * 0.04) {
            let o = CGPoint(x: -Dragon.neck.x, y: -Dragon.neck.y)
            let open = 0.5 * fire + 0.15 * rig.during(0.3, 0.7)
            if open > 0.02 {
                let mouth = CGMutablePath()
                mouth.move(to: CGPoint(x: 0.6 + o.x, y: 0.15 + o.y))
                mouth.addLine(to: CGPoint(x: 0.88 + o.x, y: 0.16 + o.y))
                let tip = vistaTurn(CGPoint(x: 0.86, y: 0.12), about: Dragon.jawPivot, by: -0.6 * open)
                mouth.addLine(to: CGPoint(x: tip.x + o.x, y: tip.y + o.y))
                mouth.closeSubpath()
                ctx.addPath(mouth)
                ctx.setFillColor(VistaInk.color(0x5A1418))
                ctx.fillPath()
            }
            ctx.place(p[Dragon.jaw], at: CGPoint(x: Dragon.jawPivot.x + o.x, y: Dragon.jawPivot.y + o.y), angle: -0.6 * open)
            ctx.place(p[Dragon.head], at: .zero)
            VistaFace.iris(ctx, 0.71 + o.x, 0.215 + o.y, r: 0.03, look: rig.gaze, blink: rig.blink, iris: 0xFFB020, slit: true, lid: Tone.dragon.base, rest: 0.25)
        }
        ctx.place(p[Dragon.wing], at: Dragon.shoulder, angle: beat * 0.6)
    }

    /// The breath of fire: a roaring plume from the jaws down to the ground beside you, behind you, that never touches you.
    func paintAura(_ ctx: CGContext, _ rig: VistaRig, _ world: VistaWorld, _ frame: VistaFrame) {
        guard rig.species.art == VistaDragonCast.dragon else { return }
        let (angle, fire) = breath(rig)
        guard fire > 0.01 else { return }
        let c = rig.creature
        let tip = vistaTurn(Dragon.snout, about: Dragon.neck, by: angle)
        let mouth = rig.point(Double(tip.x) + 0.02, Double(tip.y) - 0.02)
        let target = CGPoint(x: c.aim.x, y: c.aim.y)
        let reach = 0.35 + 0.65 * min(1, (rig.actTime - 0.65) / 0.35)
        let count = 26
        let t = frame.time
        // Hot and bright at the jaws; orange, red, then smoke toward the end.
        let colours: [UInt32] = [0xFFF6C8, 0xFFD24A, 0xFF9A2A, 0xF0501E, 0xB8301E]
        func spot(_ along: Double, _ k: Double) -> CGPoint {
            let x = Double(mouth.x) + (Double(target.x) - Double(mouth.x)) * along + sin(t * 13 + k * 1.7) * 9 * along
            let y = Double(mouth.y) + (Double(target.y) - Double(mouth.y)) * along + 30 * along * (1 - along) * 4
            return CGPoint(x: x, y: y)
        }
        for k in (0..<count).reversed() {
            let along = (Double(k) + (t * 7).truncatingRemainder(dividingBy: 1)) / Double(count) * reach
            let r = (12 + 62 * along) * (0.8 + 0.2 * sin(t * 17 + Double(k)))
            let tone = colours[min(colours.count - 1, Int(along * Double(colours.count)))]
            if let glow = VistaSprites.glow(tone) { ctx.stampDot(glow, at: spot(along, Double(k)), radius: r, alpha: fire * (0.95 - 0.45 * along)) }
        }
        // A white-hot core near the jaws.
        if let core = VistaSprites.glow(0xFFFBE8) {
            for k in 0..<8 {
                let along = (Double(k) + (t * 9).truncatingRemainder(dividingBy: 1)) / 8 * reach * 0.45
                ctx.stampDot(core, at: spot(along, Double(k) + 40), radius: 10 + 18 * along, alpha: fire * 0.9)
            }
        }
        // Where it lands, the ground blazes.
        if reach > 0.9 {
            if let glow = VistaSprites.glow(0xFF8A2A) { ctx.stampDot(glow, at: target, radius: 110 + 14 * sin(t * 11), alpha: 0.55 * fire) }
            for k in 0..<5 {
                let x = Double(target.x) + (Double(k) - 2) * 26
                drawFlame(ctx, at: CGPoint(x: x, y: Double(target.y) - 10), time: t * 1.3 + Double(k) * 1.9, size: (26 + 12 * sin(Double(k) * 2.3)) * fire)
            }
        }
    }

    // MARK: Knight

    private enum Knight {
        static let body = 0, head = 1, plume = 2, arm = 3, armFar = 4, leg = 5, legFar = 6
        static let neck = CGPoint(x: 0.0, y: 0.52)
        static let shoulder = CGPoint(x: 0.12, y: 0.46)
        static let hip = CGPoint(x: 0.05, y: 0.22)
    }

    private func bakeKnight(_ u: Double) -> [VistaPart?] {
        let s = ink
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.22, y: 0.14, width: 0.44, height: 0.44)) { ctx in
            let plate = VistaInk.rounded(CGRect(x: -0.16, y: 0.18, width: 0.32, height: 0.36), 0.1)
            VistaInk.shade(ctx, plate, Tone.steel, s, u: u)
            let tabard = VistaInk.smooth([(-0.04, 0.48), (0.15, 0.48), (0.17, 0.3), (0.13, 0.17), (0.0, 0.17), (-0.06, 0.3)], tension: 0.3)
            VistaInk.shade(ctx, tabard, Tone.tabard, s, u: u, rim: 0.6)
            VistaInk.shade(ctx, VistaInk.star(0.06, 0.34, outer: 0.05, inner: 0.022), Tone.gold, s, u: u, rim: 0, gloss: 0.3)
            VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: -0.17, y: 0.2, width: 0.34, height: 0.04), 0.02), VistaTone(0xB08458, 0x7A5432, 0x3A2414), s, u: u, rim: 0, gloss: 0)
        }
        let head = VistaPart.bake(u: u, pivot: Knight.neck, box: CGRect(x: -0.24, y: 0.48, width: 0.5, height: 0.48)) { ctx in
            let helm = VistaInk.ellipse(0.02, 0.73, 0.2, 0.2)
            VistaInk.shade(ctx, helm, Tone.steel, s, u: u)
            // The face in the open visor.
            let face = VistaInk.rounded(CGRect(x: 0.0, y: 0.62, width: 0.2, height: 0.15), 0.05)
            VistaInk.patch(ctx, clip: helm, face, VistaInk.color(0xF2C2A0), u: u)
            VistaInk.patch(ctx, clip: face, VistaInk.ellipse(0.14, 0.645, 0.03, 0.02), VistaInk.color(0xFF8A8A, 0.5), soft: 0.01, u: u)
            // The raised visor over the brow, and a crest down the middle.
            VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: -0.02, y: 0.77, width: 0.24, height: 0.07), 0.03), Tone.steel, s, u: u, gloss: 0.3)
            ctx.setStrokeColor(VistaInk.color(Tone.steel.dark, 0.8))
            ctx.setLineWidth(CGFloat(1.4 / u))
            for k in 0..<3 { let x = 0.03 + Double(k) * 0.06; ctx.move(to: CGPoint(x: x, y: 0.795)); ctx.addLine(to: CGPoint(x: x + 0.03, y: 0.795)) }
            ctx.strokePath()
        }
        let plume = VistaPart.bake(u: u, box: CGRect(x: -0.24, y: -0.04, width: 0.3, height: 0.24)) { ctx in
            let feather = VistaInk.smooth([(0, 0), (-0.06, 0.12), (-0.16, 0.17), (-0.22, 0.12), (-0.14, 0.08), (-0.05, -0.01)], tension: 0.45)
            VistaInk.shade(ctx, feather, VistaTone(0xFF8A7A, 0xE0383A, 0x8A1424), s, u: u)
        }
        let arm = VistaPart.bake(u: u, box: CGRect(x: -0.08, y: -0.52, width: 0.22, height: 0.58)) { ctx in
            VistaInk.shade(ctx, VistaInk.capsule(0, 0, 0.02, -0.12, 0.045, 0.04), Tone.steel, s, u: u, gloss: 0.15)
            // The sword, carried on from the fist: blade, gold cross-guard, then the gauntlet over the grip.
            let blade = VistaInk.smooth([(0.02, -0.18), (0.075, -0.44), (0.085, -0.49), (0.09, -0.44), (0.05, -0.18)], tension: 0.15)
            VistaInk.shade(ctx, blade, VistaTone(0xFFFFFF, 0xD6DEEA, 0x7A84A0), s, u: u, gloss: 0.4)
            ctx.setStrokeColor(VistaInk.color(0x8A94B0, 0.8))
            ctx.setLineWidth(CGFloat(1 / u))
            ctx.move(to: CGPoint(x: 0.037, y: -0.2)); ctx.addLine(to: CGPoint(x: 0.08, y: -0.45)); ctx.strokePath()
            let guardBar = CGMutablePath()
            guardBar.addPath(VistaInk.rounded(CGRect(x: -0.035, y: -0.19, width: 0.13, height: 0.026), 0.012), transform: CGAffineTransform(translationX: 0.03, y: -0.177).rotated(by: 0.15).translatedBy(x: -0.03, y: 0.177))
            VistaInk.shade(ctx, guardBar, Tone.gold, s, u: u, rim: 0)
            VistaInk.shade(ctx, VistaInk.ellipse(0.03, -0.15, 0.045, 0.04), Tone.steelFar, s, u: u, gloss: 0.15)
        }
        let armFar = VistaPart.bake(u: u, box: CGRect(x: -0.22, y: -0.3, width: 0.3, height: 0.34)) { ctx in
            VistaInk.shade(ctx, VistaInk.capsule(0, 0, -0.02, -0.12, 0.04, 0.036), Tone.steelFar, s, u: u)
            let shield = VistaInk.ellipse(-0.05, -0.15, 0.13, 0.13)
            VistaInk.shade(ctx, shield, Tone.tabard, s, u: u)
            ctx.addPath(shield)
            ctx.setStrokeColor(VistaInk.color(Tone.gold.base))
            ctx.setLineWidth(CGFloat(3 / u))
            ctx.strokePath()
            VistaInk.shade(ctx, VistaInk.ellipse(-0.05, -0.15, 0.03, 0.03), Tone.gold, s, u: u, rim: 0)
        }
        func leg(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.07, y: -0.25, width: 0.2, height: 0.3)) { ctx in
                VistaInk.shade(ctx, VistaInk.capsule(0, 0, 0, -0.17, 0.055, 0.05), tone, s, u: u, gloss: 0.15)
                VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: -0.05, y: -0.225, width: 0.15, height: 0.06), 0.025), tone, s, u: u, gloss: 0.1)
            }
        }
        return [body, head, plume, arm, armFar, leg(Tone.steel), leg(Tone.steelFar)]
    }

    private func drawKnight(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let s = rig.stride
        let salute = rig.hold(rise: 0.35, fall: 0.4)
        let swing = rig.moving ? sin(s) : 0
        let flee = rig.phase == .fleeing ? 1.0 : 0
        ctx.place(p[Knight.legFar], at: CGPoint(x: -Knight.hip.x, y: Knight.hip.y), angle: -swing * 0.45)
        ctx.place(p[Knight.armFar], at: CGPoint(x: -0.12, y: 0.45), angle: swing * 0.3 + flee * sin(rig.time * 18) * 0.8)
        ctx.place(p[Knight.leg], at: Knight.hip, angle: swing * 0.45)
        ctx.place(p[Knight.body], at: .zero, sy: 1 + 0.012 * rig.breath)
        let tilt = rig.gaze.y * 0.2 * rig.attention + (rig.moving ? sin(s * 2) * 0.04 : 0)
        ctx.local(at: Knight.neck, angle: tilt) {
            let o = -Double(Knight.neck.y)
            ctx.place(p[Knight.plume], at: CGPoint(x: -0.04, y: 0.9 + o), angle: sin(rig.clock * 2.4) * 0.12 - (rig.moving ? 0.15 : 0))
            ctx.place(p[Knight.head], at: .zero)
            VistaFace.bead(ctx, 0.07, 0.705 + o, r: 0.022, look: rig.gaze, blink: rig.blink)
            VistaFace.bead(ctx, 0.155, 0.705 + o, r: 0.02, look: rig.gaze, blink: rig.blink)
            ctx.setStrokeColor(VistaInk.color(0x7A3A2A))
            ctx.setLineWidth(0.012)
            ctx.setLineCap(.round)
            let smile = 0.012 + 0.02 * salute
            ctx.move(to: CGPoint(x: 0.08, y: 0.655 + o)); ctx.addQuadCurve(to: CGPoint(x: 0.15, y: 0.655 + o), control: CGPoint(x: 0.115, y: 0.655 + o - smile))
            ctx.strokePath()
        }
        // The sword arm: swings as it walks, held high to salute, flailing as it runs.
        let raise = 0.45 + swing * -0.35 + salute * (2.45 + 0.06 * sin(rig.actTime * 3)) + flee * (1.6 + sin(rig.time * 16) * 0.6)
        ctx.place(p[Knight.arm], at: Knight.shoulder, angle: raise)
        if salute > 0.8, let twinkle = VistaSprites.twinkle(0xFFF6D0) {
            let tip = vistaTurn(CGPoint(x: Knight.shoulder.x + 0.085, y: Knight.shoulder.y - 0.49), about: Knight.shoulder, by: raise)
            let k = 0.5 + 0.5 * sin(rig.actTime * 6)
            ctx.draw(twinkle, in: CGRect(x: Double(tip.x) - 0.08 * k, y: Double(tip.y) - 0.08 * k, width: 0.16 * k, height: 0.16 * k))
        }
    }

    // MARK: Bat

    private enum Bat {
        static let body = 0, wing = 1, wingFar = 2
        static let shoulder = CGPoint(x: 0.0, y: 0.06)
    }

    private func bakeBat(_ u: Double) -> [VistaPart?] {
        let s = VistaInkStyle(rim: 0xFFB070, rimAmount: 0.6, line: 1.6, ink: 0.5, gloss: 0.2)
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.24, y: -0.3, width: 0.48, height: 0.66)) { ctx in
            for (dx, lean) in [(-0.07, -0.25), (0.08, 0.2)] {
                let ear = VistaInk.smooth([(dx - 0.05, 0.12), (dx + lean * 0.12, 0.34), (dx + 0.05, 0.12)], tension: 0.25)
                VistaInk.shade(ctx, ear, Tone.bat, s, u: u, gloss: 0)
                VistaInk.patch(ctx, clip: ear, VistaInk.ellipse(dx + lean * 0.05, 0.2, 0.02, 0.06), VistaInk.color(0xE09AB8, 0.7), u: u)
            }
            let fur = VistaInk.ellipse(0.0, -0.02, 0.16, 0.2)
            VistaInk.shade(ctx, fur, Tone.bat, s, u: u)
            VistaInk.patch(ctx, clip: fur, VistaInk.ellipse(0.04, -0.08, 0.09, 0.11), VistaInk.color(0xB8A4D4, 0.6), soft: 0.03, u: u)
            ctx.setFillColor(VistaInk.color(0xFFFFFF))
            for x in [0.03, 0.08] { ctx.move(to: CGPoint(x: x, y: -0.02)); ctx.addLine(to: CGPoint(x: x + 0.02, y: -0.02)); ctx.addLine(to: CGPoint(x: x + 0.01, y: -0.06)); ctx.fillPath() }
        }
        func wing(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.92, y: -0.2, width: 0.96, height: 0.64)) { ctx in
                let path = CGMutablePath()
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: -0.3, y: 0.36))
                path.addLine(to: CGPoint(x: -0.86, y: 0.3))
                path.addQuadCurve(to: CGPoint(x: -0.68, y: 0.06), control: CGPoint(x: -0.7, y: 0.22))
                path.addQuadCurve(to: CGPoint(x: -0.42, y: -0.06), control: CGPoint(x: -0.5, y: 0.08))
                path.addQuadCurve(to: CGPoint(x: -0.1, y: -0.12), control: CGPoint(x: -0.22, y: 0.0))
                path.closeSubpath()
                VistaInk.shade(ctx, path, tone, s, u: u)
                ctx.setStrokeColor(VistaInk.color(tone.dark, 0.9))
                ctx.setLineWidth(CGFloat(1.6 / u))
                for tip in [CGPoint(x: -0.86, y: 0.3), CGPoint(x: -0.68, y: 0.06), CGPoint(x: -0.42, y: -0.06)] { ctx.move(to: CGPoint(x: -0.3, y: 0.36)); ctx.addLine(to: tip) }
                ctx.strokePath()
            }
        }
        return [body, wing(Tone.batWing), wing(VistaTone(0x5E4A78, 0x382A52, 0x181024))]
    }

    private func drawBat(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let flap = sin(rig.creature.stride * 2.2)
        ctx.place(p[Bat.wingFar], at: CGPoint(x: 0.04, y: 0.08), angle: -0.3 + flap * 0.8, sx: -0.85, sy: 0.85)
        ctx.place(p[Bat.body], at: .zero)
        VistaFace.bead(ctx, 0.0, 0.05, r: 0.03, look: rig.gaze, blink: rig.blink, color: 0x1A0E20)
        VistaFace.bead(ctx, 0.09, 0.05, r: 0.028, look: rig.gaze, blink: rig.blink, color: 0x1A0E20)
        ctx.place(p[Bat.wing], at: Bat.shoulder, angle: 0.2 - flap * 0.85)
    }

    // MARK: Unicorn

    private enum Unicorn {
        static let body = 0, head = 1, tail = 2, leg = 3, legFar = 4
        static let hip = CGPoint(x: -0.36, y: 0.46)
        static let shoulder = CGPoint(x: 0.2, y: 0.47)
        static let neck = CGPoint(x: 0.24, y: 0.62)
        static let tailRoot = CGPoint(x: -0.44, y: 0.66)
        static let rainbow: [UInt32] = [0xFF9AB8, 0xFFC48A, 0xFFF0A0, 0xA8F0B8, 0x9AD8FF, 0xC8A8FF]
    }

    private func bakeUnicorn(_ u: Double) -> [VistaPart?] {
        let s = VistaInkStyle(rim: 0xFFB070, rimAmount: 0.45, line: 1.8, ink: 0.45, gloss: 0.25)
        let body = VistaPart.bake(u: u, pivot: Unicorn.hip, box: CGRect(x: -0.56, y: 0.36, width: 0.92, height: 0.42)) { ctx in
            let path = VistaInk.smooth([(-0.52, 0.56), (-0.45, 0.73), (-0.2, 0.77), (0.1, 0.76), (0.32, 0.72), (0.37, 0.56), (0.26, 0.4), (-0.1, 0.37), (-0.42, 0.4)])
            VistaInk.shade(ctx, path, Tone.unicorn, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(-0.05, 0.4, 0.32, 0.06), VistaInk.color(0xD4C8EC, 0.5), soft: 0.03, u: u)
        }
        let head = VistaPart.bake(u: u, pivot: Unicorn.neck, box: CGRect(x: 0.1, y: 0.5, width: 0.62, height: 0.84)) { ctx in
            // The mane, in pastel waves down the back of the neck.
            for (k, tone) in Unicorn.rainbow.enumerated() {
                let off = Double(k) * 0.025
                let strand = VistaInk.smooth([(0.36 - off * 0.3, 1.02 - off), (0.22 - off, 0.92 - off), (0.12 - off * 0.5, 0.74 - off), (0.08 - off * 0.3, 0.6 - off * 0.5),
                                              (0.16 - off * 0.3, 0.66 - off * 0.5), (0.26 - off * 0.5, 0.86 - off), (0.4 - off * 0.3, 0.98 - off)], tension: 0.45)
                VistaInk.shade(ctx, strand, VistaTone(VistaInk.mixHex(tone, 0xFFFFFF, 0.4), tone, VistaInk.mixHex(tone, 0x6A4A8A, 0.4)), s, u: u, rim: 0.3, gloss: 0.2, line: k == 0)
            }
            let neck = VistaInk.smooth([(0.18, 0.62), (0.26, 0.86), (0.36, 1.0), (0.46, 1.02), (0.4, 0.86), (0.36, 0.66), (0.3, 0.56)], tension: 0.45)
            VistaInk.shade(ctx, neck, Tone.unicorn, s, u: u)
            let skull = VistaInk.smooth([(0.34, 1.0), (0.44, 1.07), (0.54, 1.04), (0.66, 0.9), (0.7, 0.84), (0.64, 0.8), (0.52, 0.86), (0.4, 0.92)], tension: 0.45)
            VistaInk.shade(ctx, skull, Tone.unicorn, s, u: u)
            VistaInk.patch(ctx, clip: skull, VistaInk.ellipse(0.66, 0.845, 0.05, 0.04), VistaInk.color(0xF0C8D8, 0.8), soft: 0.01, u: u)
            VistaInk.oval(ctx, CGPoint(x: 0.67, y: 0.86), rx: 0.008, ry: 0.006, VistaInk.color(0x8A5A7A))
            let ear = VistaInk.smooth([(0.42, 1.04), (0.42, 1.14), (0.47, 1.06)], tension: 0.25)
            VistaInk.shade(ctx, ear, Tone.unicorn, s, u: u, gloss: 0)
            // The horn: gold, spiralled.
            let horn = VistaInk.smooth([(0.47, 1.06), (0.56, 1.3), (0.53, 1.06)], tension: 0.15)
            VistaInk.shade(ctx, horn, Tone.gold, s, u: u, gloss: 0.4)
            VistaInk.strokes(ctx, clip: horn, width: 1.2 / u, VistaInk.color(Tone.gold.dark, 0.7),
                             (0..<5).map { i in let y = 1.09 + Double(i) * 0.04; return (CGPoint(x: 0.46, y: y), CGPoint(x: 0.5, y: y + 0.01), CGPoint(x: 0.56, y: y + 0.03)) })
        }
        let tail = VistaPart.bake(u: u, pivot: Unicorn.tailRoot, box: CGRect(x: -0.78, y: 0.26, width: 0.38, height: 0.44)) { ctx in
            for (k, tone) in Unicorn.rainbow.enumerated() {
                let off = Double(k) * 0.03
                let strand = VistaInk.smooth([(-0.44, 0.66 - off * 0.3), (-0.58 - off * 0.3, 0.62 - off), (-0.7 - off * 0.2, 0.46 - off), (-0.64 - off * 0.2, 0.32 - off * 0.5),
                                              (-0.62 - off * 0.2, 0.44 - off), (-0.54 - off * 0.2, 0.56 - off)], tension: 0.45)
                VistaInk.shade(ctx, strand, VistaTone(VistaInk.mixHex(tone, 0xFFFFFF, 0.4), tone, VistaInk.mixHex(tone, 0x6A4A8A, 0.4)), s, u: u, rim: 0.3, gloss: 0.2, line: k == 0)
            }
        }
        func leg(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.07, y: -0.5, width: 0.16, height: 0.56)) { ctx in
                VistaInk.shade(ctx, VistaInk.capsule(0, 0.02, 0.01, -0.4, 0.05, 0.03), tone, s, u: u, gloss: 0.1)
                VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: -0.025, y: -0.47, width: 0.075, height: 0.06), 0.015), Tone.gold, s, u: u, rim: 0, gloss: 0.3)
            }
        }
        return [body, head, tail, leg(Tone.unicorn), leg(Tone.unicornFar)]
    }

    private func drawUnicorn(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let rear = rig.hold(rise: 0.6, fall: 0.6)
        let lean = 0.5 * rear
        let s = rig.stride
        func swing(_ phase: Double) -> (Double, Double) {
            guard rig.moving else { return (0, 0) }
            return (sin(s + phase) * 0.4, max(0, cos(s + phase)) * 0.04)
        }
        let shoulder = vistaTurn(Unicorn.shoulder, about: Unicorn.hip, by: lean)
        let (fb, fbl) = swing(.pi / 2), (ff, ffl) = swing(.pi * 1.5)
        ctx.place(p[Unicorn.legFar], at: CGPoint(x: Unicorn.hip.x + 0.05, y: Unicorn.hip.y + fbl), angle: fb - 0.2 * rear)
        ctx.place(p[Unicorn.legFar], at: CGPoint(x: shoulder.x + 0.05, y: shoulder.y + ffl), angle: ff + lean + 1.3 * rear)
        let tailRoot = vistaTurn(Unicorn.tailRoot, about: Unicorn.hip, by: lean)
        ctx.place(p[Unicorn.tail], at: tailRoot, angle: lean + sin(rig.clock * 2) * 0.1 + (rig.moving ? 0.15 : 0))
        ctx.place(p[Unicorn.body], at: Unicorn.hip, angle: lean, sy: 1 + 0.012 * rig.breath)
        let (nb, nbl) = swing(0), (nf, nfl) = swing(.pi)
        ctx.place(p[Unicorn.leg], at: CGPoint(x: Unicorn.hip.x, y: Unicorn.hip.y + nbl), angle: nb - 0.25 * rear)
        let neck = vistaTurn(Unicorn.neck, about: Unicorn.hip, by: lean)
        ctx.local(at: neck, angle: lean * 0.2 + rig.gaze.y * 0.2 * rig.attention + (rig.moving ? sin(s * 2) * 0.05 : sin(rig.clock * 0.8) * 0.03)) {
            ctx.place(p[Unicorn.head], at: .zero)
            VistaFace.bead(ctx, 0.52 - Unicorn.neck.x, 0.965 - Unicorn.neck.y, r: 0.024, look: rig.gaze, blink: rig.blink, color: 0x3A2A5A)
        }
        ctx.place(p[Unicorn.leg], at: CGPoint(x: shoulder.x, y: shoulder.y + nfl), angle: nf + lean + 1.5 * rear + 0.3 * rear * sin(rig.actTime * 8))
    }

    // MARK: Raven

    private enum Raven {
        static let body = 0, head = 1, wing = 2, wingOpen = 3, wingOpenFar = 4, feet = 5
        static let neck = CGPoint(x: 0.06, y: 0.16)
        static let shoulder = CGPoint(x: -0.02, y: 0.08)
    }

    private func bakeRaven(_ u: Double) -> [VistaPart?] {
        let s = VistaInkStyle(rim: 0x9AB8FF, rimAmount: 0.6, line: 1.6, ink: 0.4, gloss: 0.3)
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.48, y: -0.44, width: 0.8, height: 0.72)) { ctx in
            let tail = VistaInk.smooth([(-0.12, -0.2), (-0.44, -0.4), (-0.36, -0.26), (-0.14, -0.08)], tension: 0.3)
            VistaInk.shade(ctx, tail, Tone.raven, s, u: u)
            let path = VistaInk.smooth([(0.2, 0.12), (0.22, -0.06), (0.1, -0.24), (-0.1, -0.26), (-0.22, -0.14), (-0.2, 0.06), (-0.06, 0.18)])
            VistaInk.shade(ctx, path, Tone.raven, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(-0.02, 0.06, 0.14, 0.08), VistaInk.color(0x6A5AC8, 0.35), soft: 0.04, u: u)
        }
        let head = VistaPart.bake(u: u, pivot: Raven.neck, box: CGRect(x: -0.08, y: 0.06, width: 0.48, height: 0.36)) { ctx in
            let skull = VistaInk.ellipse(0.1, 0.25, 0.14, 0.13)
            VistaInk.shade(ctx, skull, Tone.raven, s, u: u)
            let beak = VistaInk.smooth([(0.2, 0.3), (0.36, 0.25), (0.38, 0.22), (0.2, 0.2)], tension: 0.3)
            VistaInk.shade(ctx, beak, VistaTone(0x6A6A80, 0x30303C, 0x101018), s, u: u, gloss: 0.4)
        }
        let wing = VistaPart.bake(u: u, box: CGRect(x: -0.4, y: -0.34, width: 0.5, height: 0.42)) { ctx in
            let path = VistaInk.smooth([(0.04, 0.02), (0.08, -0.12), (-0.04, -0.26), (-0.36, -0.3), (-0.2, -0.16), (-0.1, 0.0)], tension: 0.4)
            VistaInk.shade(ctx, path, Tone.raven, s, u: u)
            VistaInk.strokes(ctx, clip: path, width: 1.2 / u, VistaInk.color(0x8A8AC8, 0.4),
                             (0..<4).map { i in let x = -0.08 - Double(i) * 0.06; return (CGPoint(x: x + 0.04, y: -0.04), CGPoint(x: x, y: -0.14), CGPoint(x: x - 0.06, y: -0.24)) })
        }
        func open(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.7, y: -0.1, width: 0.76, height: 0.5)) { ctx in
                let path = VistaInk.smooth([(0.02, 0.04), (-0.2, 0.24), (-0.46, 0.34), (-0.66, 0.32), (-0.58, 0.22), (-0.64, 0.14), (-0.5, 0.08), (-0.54, 0.0), (-0.34, -0.04), (-0.12, -0.06)], tension: 0.45)
                VistaInk.shade(ctx, path, tone, s, u: u)
            }
        }
        let feet = VistaPart.bake(u: u, box: CGRect(x: -0.08, y: -0.42, width: 0.2, height: 0.18)) { ctx in
            ctx.setStrokeColor(VistaInk.color(0x2A2A34))
            ctx.setLineWidth(CGFloat(2.4 / u))
            ctx.setLineCap(.round)
            for x in [-0.02, 0.06] {
                ctx.move(to: CGPoint(x: x, y: -0.26)); ctx.addLine(to: CGPoint(x: x, y: -0.36))
                ctx.move(to: CGPoint(x: x - 0.03, y: -0.37)); ctx.addLine(to: CGPoint(x: x + 0.05, y: -0.37))
            }
            ctx.strokePath()
        }
        return [body, head, wing, open(Tone.raven), open(VistaTone(0x40405C, 0x1C1C2C, 0x08080E)), feet]
    }

    private func drawRaven(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let c = rig.creature
        let perched = rig.phase == .acting && c.landedAt != nil
        if perched {
            ctx.place(p[Raven.feet], at: .zero)
            ctx.place(p[Raven.body], at: .zero, sy: 1 + 0.02 * rig.breath)
            ctx.place(p[Raven.wing], at: Raven.shoulder)
        } else {
            let flap = sin(c.stride * 1.5)
            ctx.place(p[Raven.wingOpenFar], at: CGPoint(x: Raven.shoulder.x + 0.05, y: Raven.shoulder.y + 0.02), angle: flap * 0.8 + 0.2, sx: 0.92, sy: 0.92)
            ctx.place(p[Raven.body], at: .zero)
            ctx.place(p[Raven.wingOpen], at: Raven.shoulder, angle: flap * 0.8)
        }
        // Ravens cock their heads, quick and curious.
        let cock = perched ? (sin(rig.clock * 1.7) > 0.3 ? 0.18 : -0.05) : 0
        ctx.local(at: Raven.neck, angle: cock + rig.gaze.y * 0.25 * rig.attention) {
            ctx.place(p[Raven.head], at: .zero)
            VistaFace.iris(ctx, 0.16 - Raven.neck.x, 0.28 - Raven.neck.y, r: 0.035, look: rig.gaze, blink: rig.blink, iris: 0x3A2A1A, sclera: 0xE8E4F4, lid: 0x26263C, rest: 0.1)
        }
    }

    // MARK: Baby dragon

    private enum Baby {
        static let body = 0, head = 1, wing = 2, tail = 3, leg = 4, legFar = 5
        static let neck = CGPoint(x: 0.1, y: 0.46)
        static let hip = CGPoint(x: -0.12, y: 0.16)
    }

    private func bakeHatchling(_ u: Double) -> [VistaPart?] {
        let s = ink
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.36, y: 0.06, width: 0.66, height: 0.5)) { ctx in
            let path = VistaInk.ellipse(-0.02, 0.3, 0.28, 0.22)
            VistaInk.shade(ctx, path, Tone.baby, s, u: u)
            VistaInk.patch(ctx, clip: path, VistaInk.ellipse(0.1, 0.26, 0.15, 0.16), VistaInk.color(Tone.belly.light), soft: 0.02, u: u)
            VistaInk.strokes(ctx, clip: VistaInk.ellipse(0.1, 0.26, 0.15, 0.16), width: 1.4 / u, VistaInk.color(Tone.belly.dark, 0.5),
                             (0..<4).map { i in let y = 0.16 + Double(i) * 0.06; return (CGPoint(x: 0.0, y: y), CGPoint(x: 0.1, y: y - 0.02), CGPoint(x: 0.22, y: y)) })
        }
        let head = VistaPart.bake(u: u, pivot: Baby.neck, box: CGRect(x: -0.14, y: 0.4, width: 0.66, height: 0.6)) { ctx in
            for (x, lean) in [(0.0, -0.05), (0.12, 0.02)] {
                let nub = VistaInk.smooth([(x - 0.03, 0.82), (x + lean, 0.94), (x + 0.04, 0.82)], tension: 0.3)
                VistaInk.shade(ctx, nub, Tone.horn, s, u: u, gloss: 0.2)
            }
            let skull = VistaInk.smooth([(-0.08, 0.68), (-0.04, 0.84), (0.12, 0.9), (0.28, 0.84), (0.42, 0.72), (0.46, 0.64), (0.36, 0.56), (0.12, 0.52), (-0.04, 0.56)])
            VistaInk.shade(ctx, skull, Tone.baby, s, u: u)
            VistaInk.patch(ctx, clip: skull, VistaInk.ellipse(0.34, 0.6, 0.1, 0.05), VistaInk.color(Tone.belly.light, 0.9), soft: 0.01, u: u)
            VistaInk.oval(ctx, CGPoint(x: 0.42, y: 0.67), rx: 0.012, ry: 0.009, VistaInk.color(0x6A1E10))
            VistaInk.blob(ctx, CGPoint(x: 0.24, y: 0.62), rx: 0.05, ry: 0.03, VistaInk.color(0xFF6A8A, 0.5))
        }
        let wing = VistaPart.bake(u: u, box: CGRect(x: -0.24, y: -0.04, width: 0.28, height: 0.26)) { ctx in
            let path = CGMutablePath()
            path.move(to: .zero); path.addLine(to: CGPoint(x: -0.06, y: 0.2)); path.addLine(to: CGPoint(x: -0.2, y: 0.16))
            path.addQuadCurve(to: CGPoint(x: -0.16, y: 0.06), control: CGPoint(x: -0.14, y: 0.12)); path.addQuadCurve(to: CGPoint(x: -0.04, y: -0.02), control: CGPoint(x: -0.08, y: 0.04))
            path.closeSubpath()
            VistaInk.shade(ctx, path, Tone.membrane, s, u: u)
        }
        let tail = VistaPart.bake(u: u, box: CGRect(x: -0.32, y: -0.06, width: 0.34, height: 0.22)) { ctx in
            VistaInk.shade(ctx, VistaInk.smooth([(0, 0.05), (-0.14, 0.04), (-0.26, 0.1), (-0.3, 0.14), (-0.22, 0.04), (-0.12, -0.03), (0, -0.04)], tension: 0.45), Tone.baby, s, u: u)
        }
        func leg(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.08, y: -0.18, width: 0.2, height: 0.22)) { ctx in
                VistaInk.shade(ctx, VistaInk.capsule(0, 0, 0.02, -0.1, 0.06, 0.05), tone, s, u: u, gloss: 0.1)
                VistaInk.shade(ctx, VistaInk.ellipse(0.04, -0.13, 0.065, 0.035), tone, s, u: u, gloss: 0)
            }
        }
        return [body, head, wing, tail, leg(Tone.baby), leg(VistaTone(0xD88A5A, 0xB8582E, 0x6A2410))]
    }

    private func drawHatchling(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        // The sneeze: it draws a breath (leaning back), then ACHOO, head snapping forward.
        let t = rig.actTime
        let inhale = rig.phase == .acting ? (t < 0.95 ? min(1, t / 0.8) : max(0, 1 - (t - 0.95) / 0.12)) : 0
        let snap = rig.during(0.95, 1.35, ease: 0.08)
        let waddle = rig.moving ? sin(rig.stride) : 0
        ctx.place(p[Baby.legFar], at: CGPoint(x: Baby.hip.x + 0.2, y: Baby.hip.y + max(0, -waddle) * 0.03), angle: -waddle * 0.3)
        ctx.place(p[Baby.tail], at: CGPoint(x: -0.26, y: 0.22), angle: sin(rig.clock * 2.2) * 0.2)
        ctx.place(p[Baby.body], at: .zero, sx: 1 - 0.04 * inhale, sy: 1 + 0.02 * rig.breath + 0.08 * inhale)
        ctx.place(p[Baby.wing], at: CGPoint(x: -0.08, y: 0.42), angle: sin(rig.clock * (rig.moving ? 9 : 2)) * 0.3 + 0.4 * snap)
        ctx.place(p[Baby.leg], at: Baby.hip, angle: waddle * 0.3)
        let headAngle = 0.3 * inhale - 0.35 * snap + rig.gaze.y * 0.2 * rig.attention
        ctx.local(at: Baby.neck, angle: headAngle) {
            ctx.place(p[Baby.head], at: .zero)
            let o = -Double(Baby.neck.y)
            let squint = max(rig.blink, 0.85 * snap + 0.4 * inhale)
            VistaFace.iris(ctx, 0.2 - Double(Baby.neck.x), 0.74 + o, r: 0.06, look: rig.gaze, blink: squint, iris: 0xFFB020, lid: Tone.baby.base, rest: 0.08)
            ctx.setStrokeColor(VistaInk.color(0x6A1E10))
            ctx.setLineWidth(0.016)
            ctx.setLineCap(.round)
            let open = 0.01 + 0.06 * snap
            ctx.move(to: CGPoint(x: 0.2 - Double(Baby.neck.x), y: 0.58 + o)); ctx.addQuadCurve(to: CGPoint(x: 0.36 - Double(Baby.neck.x), y: 0.6 + o), control: CGPoint(x: 0.28 - Double(Baby.neck.x), y: 0.56 + o - open))
            ctx.strokePath()
        }
    }
}
