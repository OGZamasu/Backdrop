import CoreGraphics
import Foundation
import simd

/// Who lives out among the stars.
enum VistaSpaceCast {
    static let astronaut = 0, ufo = 1, robot = 2, whale = 3, alien = 4, star = 5

    static var cast: VistaCast {
        var layout = VistaLayout()
        layout.farGround = 292
        layout.nearGround = 84
        layout.roamLow = 380
        layout.roamHigh = 650

        var walker = VistaSpecies(name: "astronaut", art: astronaut, height: 190, aspect: 0.85, speed: 46)
        walker.body = .floater
        walker.home = 0.35
        walker.actSeconds = 3.2
        walker.cry = "HI THERE!"
        walker.cryAt = 0.5
        walker.band = 340...520

        var saucer = VistaSpecies(name: "flying saucer", art: ufo, height: 92, aspect: 2.1, speed: 150)
        saucer.body = .flier
        saucer.spot = .above
        saucer.home = 0.3
        saucer.charge = 1.2
        saucer.actSeconds = 4.2
        saucer.cry = "BEEP BOOP?"
        saucer.cryAt = 0.6
        saucer.band = 470...640
        saucer.emitters = [VistaEmitter(kind: .sparkle, from: 0.5, to: 3.6, rate: 22, at: .zero, velocity: SIMD2(0, 120), spread: 30, aroundPerson: true)]

        var bot = VistaSpecies(name: "robot", art: robot, height: 140, aspect: 0.8, speed: 64)
        bot.gait = .roll
        bot.home = 0.24
        bot.actSeconds = 2.8
        bot.cry = "BEEP BOOP!"
        bot.cryAt = 0.45
        bot.emitters = [VistaEmitter(kind: .heart, from: 0.6, to: 2.2, rate: 4, at: SIMD2(0.05, 1.05), velocity: SIMD2(30, 90), spread: 25)]

        var humpback = VistaSpecies(name: "space whale", art: whale, height: 340, aspect: 2.3, speed: 30)
        humpback.body = .floater
        humpback.farOnly = true
        humpback.temper = .steady
        humpback.home = 0.06
        humpback.interest = 0.7
        humpback.actSeconds = 4.4
        humpback.cry = "♪ OOOooo ♪"
        humpback.cryAt = 0.8
        humpback.band = 540...630
        humpback.emitters = [VistaEmitter(kind: .note, from: 0.8, to: 3.6, rate: 3.2, at: SIMD2(0.95, 0.05), velocity: SIMD2(40, 70), spread: 25)]

        var blob = VistaSpecies(name: "alien", art: alien, height: 86, aspect: 0.85, speed: 70)
        blob.gait = .hop
        blob.home = 0.3
        blob.actSeconds = 2.4
        blob.cry = "GLORP!"
        blob.cryAt = 0.35
        blob.beats = [VistaBeat(at: 0.3, event: .jump(380)), VistaBeat(at: 1.1, event: .jump(380)), VistaBeat(at: 1.2, event: .burst(.sparkle, 5, 0.6))]

        var twinkle = VistaSpecies(name: "star", art: star, height: 66, aspect: 1, speed: 160)
        twinkle.body = .flier
        twinkle.act = .perch
        twinkle.temper = .prey
        twinkle.perchesOnHand = true
        twinkle.home = 0.3
        twinkle.cry = "HEE HEE!"
        twinkle.band = 400...640

        return VistaCast(species: [walker, saucer, bot, humpback, blob, twinkle], roster: [0, 0, 1, 2, 3, 4, 4, 5, 5], layout: layout, cap: 10, visibleAtStart: 7)
    }
}

/// Out among the stars: a nebula glowing over a little grey moon, a ringed planet, a blue world rising, comets streaking past,
/// and visitors who float, roll and hop over to say hello.
final class VistaSpaceStage: VistaStage {
    let cast = VistaSpaceCast.cast
    let hint = "Wave to scatter them, or hold up a hand for a star"
    let accent: UInt32 = 0x7B5CE6
    let fx = VistaFXColors(dust: 0xC8C0E8, snow: 0xF0ECFF, sparkle: 0xBFF4FF, ember: 0xFF9AE0, smoke: 0xD8D0F0, water: 0xCFF6FF,
                           notes: [0x8FF0FF, 0xFFB3F0, 0xFFE38A], heart: 0xFF7AB6)
    let haze: UInt32 = 0x2C1E66
    let hazeAmount = 0.22

    private enum Night {
        static let deep: UInt32 = 0x05031A
        static let violet: UInt32 = 0x2A1252
        static let magenta: UInt32 = 0xFF4FA8
        static let teal: UInt32 = 0x36E0D8
        static let moonLit: UInt32 = 0xC9C2E6
        static let moonShade: UInt32 = 0x4E4478
    }
    private let ink = VistaInkStyle(rim: 0xA8ECFF, rimAmount: 0.55, line: 2.0, ink: 0.5, gloss: 0.24)

    private enum Tone {
        static let suit = VistaTone(0xFFFFFF, 0xE8ECF6, 0x9AA2C4)
        static let suitFar = VistaTone(0xD4D9EA, 0xBAC0D8, 0x7F86AA)
        static let metal = VistaTone(0xF2F0FF, 0xB9B6D8, 0x5E5A86)
        static let hull = VistaTone(0x9C98C8, 0x6C6898, 0x34305C)
        static let robot = VistaTone(0xB8F4F0, 0x5CC8C8, 0x24707C)
        static let robotFar = VistaTone(0x86CFCF, 0x449EA6, 0x1A5560)
        static let whale = VistaTone(0x7C8CFF, 0x4250C0, 0x1C1C64)
        static let whaleFin = VistaTone(0x6474E8, 0x3642A8, 0x161656)
        static let alien = VistaTone(0xC6FF8A, 0x74D94C, 0x2E8A2E)
        static let star = VistaTone(0xFFFBD0, 0xFFD94A, 0xE59A1C)
        static let glove = VistaTone(0xFFB37A, 0xF27E3A, 0xA6461A)
    }

    private var painting: VistaPainting?
    private var backdrop: VistaLayer?
    private var rocks: [VistaLayer] = []
    private var tail: CGImage?
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
                paintNebula(ctx)
            }
        case 1:
            painting?.paint { ctx in
                paintPlanets(ctx)
            }
        case 2:
            painting?.paint { ctx in
                paintMoonSurface(ctx)
                paintVignette(ctx)
            }
            backdrop = painting?.finish(parallax: 10)
            painting = nil
        case 3:
            rocks = paintRocks()
            tail = VistaInk.picture(width: 220, height: 24) { ctx in
                // A soft taper: glows getting smaller and fainter away from the head.
                for i in 0..<44 {
                    let k = Double(i) / 43
                    VistaInk.blob(ctx, CGPoint(x: 212 - k * 205, y: 12), rx: 10 * (1 - k * 0.85), ry: 10 * (1 - k * 0.85),
                                  VistaInk.color(VistaInk.mixHex(0xFFFFFF, 0x8FE8FF, k), 0.22 * (1 - k)))
                }
            }
        default:
            let i = step - 4
            guard figures.indices.contains(i) else { return }
            let sp = cast.species[i]
            let u = sp.height * cast.layout.scale(sp.farOnly ? min(1, sp.home + 0.06) : 1)
            let parts: [VistaPart?]
            switch sp.art {
            case VistaSpaceCast.astronaut: parts = bakeAstronaut(u)
            case VistaSpaceCast.ufo: parts = bakeSaucer(u)
            case VistaSpaceCast.robot: parts = bakeRobot(u)
            case VistaSpaceCast.whale: parts = bakeWhale(u)
            case VistaSpaceCast.alien: parts = bakeAlien(u)
            default: parts = bakeStar(u)
            }
            figures[i] = VistaFigure(parts, haze: haze, amount: hazeAmount)
        }
    }

    func isReady(species: Int) -> Bool { figures.indices.contains(species) && figures[species] != nil }

    // MARK: The world

    private func paintSky(_ ctx: CGContext) {
        VistaInk.fillDown(ctx, CGRect(x: -48, y: 260, width: 1376, height: 460), [(0, VistaInk.color(Night.deep)), (0.35, VistaInk.color(0x0E0832)),
                                                                                   (0.7, VistaInk.color(0x1E0F48)), (1, VistaInk.color(0x3A1C6A))])
        var rng = VistaInk.generator(31)
        let tints: [UInt32] = [0xFFFFFF, 0xCFE0FF, 0xFFF0D0, 0xFFD6F0]
        for _ in 0..<320 {
            let p = CGPoint(x: rng.range(-48, 1328), y: rng.range(280, 720))
            let r = rng.range(0.4, 1.3)
            ctx.setFillColor(VistaInk.color(tints[Int(rng.unit() * 4) % 4], rng.range(0.25, 0.9)))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        for _ in 0..<14 {
            let p = CGPoint(x: rng.range(0, 1280), y: rng.range(380, 710))
            let tint = tints[Int(rng.unit() * 4) % 4]
            VistaInk.blob(ctx, p, rx: 9, ry: 9, VistaInk.color(tint, 0.35))
            ctx.setStrokeColor(VistaInk.color(tint, 0.55))
            ctx.setLineWidth(0.8)
            ctx.move(to: CGPoint(x: p.x - 9, y: p.y)); ctx.addLine(to: CGPoint(x: p.x + 9, y: p.y))
            ctx.move(to: CGPoint(x: p.x, y: p.y - 9)); ctx.addLine(to: CGPoint(x: p.x, y: p.y + 9))
            ctx.strokePath()
            VistaInk.oval(ctx, p, rx: 1.6, ry: 1.6, VistaInk.color(0xFFFFFF))
        }
        // A far spiral galaxy, tilted.
        ctx.saveGState()
        ctx.translateBy(x: 560, y: 650)
        ctx.rotate(by: -0.4)
        ctx.scaleBy(x: 1, y: 0.42)
        VistaInk.blob(ctx, .zero, rx: 60, ry: 60, VistaInk.color(0xB9A8FF, 0.25))
        for arm in 0..<2 {
            for k in 0..<40 {
                let a = Double(k) * 0.16 + Double(arm) * .pi
                let r = 6 + Double(k) * 1.3
                VistaInk.blob(ctx, CGPoint(x: cos(a) * r, y: sin(a) * r), rx: 6, ry: 6, VistaInk.color(0xE8DCFF, 0.18 * (1 - Double(k) / 45)))
            }
        }
        VistaInk.blob(ctx, .zero, rx: 10, ry: 10, VistaInk.color(0xFFF6E0, 0.9))
        ctx.restoreGState()
    }

    /// Clouds of glowing gas across the sky, pink into teal, with dark lanes of dust through them.
    private func paintNebula(_ ctx: CGContext) {
        var rng = VistaInk.generator(7)
        for i in 0..<34 {
            let k = Double(i) / 33
            let x = -40 + k * 1380 + rng.range(-60, 60)
            let y = 470 + 120 * sin(k * 3.2 + 0.6) + rng.range(-50, 50)
            let tint = VistaInk.mixHex(Night.magenta, Night.teal, k)
            VistaInk.blob(ctx, CGPoint(x: x, y: y), rx: rng.range(90, 190), ry: rng.range(60, 120), VistaInk.color(tint, rng.range(0.06, 0.13)), inner: 0.2)
        }
        for _ in 0..<22 {
            let x = rng.range(-40, 1320), y = rng.range(420, 640)
            VistaInk.blob(ctx, CGPoint(x: x, y: y), rx: rng.range(30, 70), ry: rng.range(14, 30), VistaInk.color(0xFFE6F6, rng.range(0.05, 0.12)))
        }
        for _ in 0..<12 {
            let x = rng.range(-40, 1320), y = rng.range(430, 620)
            VistaInk.blob(ctx, CGPoint(x: x, y: y), rx: rng.range(60, 140), ry: rng.range(10, 24), VistaInk.color(0x0A0520, 0.3))
        }
    }

    private func paintPlanets(_ ctx: CGContext) {
        // The ringed giant, upper right, lit from the upper left.
        let giant = CGPoint(x: 1070, y: 575), r = 86.0
        let tilt = -0.32
        func ring(front: Bool) {
            ctx.saveGState()
            ctx.translateBy(x: giant.x, y: giant.y)
            ctx.rotate(by: CGFloat(tilt))
            ctx.scaleBy(x: 1, y: 0.24)
            if front { ctx.clip(to: CGRect(x: -400, y: -400, width: 800, height: 400)) } else { ctx.clip(to: CGRect(x: -400, y: 0, width: 800, height: 400)) }
            for (radius, width, tone, alpha) in [(150.0, 14.0, 0xE8C9A0 as UInt32, 0.75), (128.0, 9.0, 0xFFE2B8 as UInt32, 0.85), (112.0, 4.0, 0xC79A78 as UInt32, 0.6)] {
                ctx.setStrokeColor(VistaInk.color(tone, alpha))
                ctx.setLineWidth(CGFloat(width))
                ctx.strokeEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
            }
            ctx.restoreGState()
        }
        VistaInk.blob(ctx, giant, rx: r * 1.9, ry: r * 1.9, VistaInk.color(0xFFB880, 0.12))
        ring(front: false)
        let disc = VistaInk.ellipse(Double(giant.x), Double(giant.y), r, r)
        ctx.saveGState()
        ctx.addPath(disc)
        ctx.clip()
        ctx.setFillColor(VistaInk.color(0xE8B488))
        ctx.fill(CGRect(x: Double(giant.x) - r, y: Double(giant.y) - r, width: r * 2, height: r * 2))
        var bands = VistaInk.generator(3)
        var y = Double(giant.y) - r
        while y < Double(giant.y) + r {
            let h = bands.range(6, 18)
            ctx.setFillColor(VistaInk.color([0xF4C994, 0xE09A68, 0xFFE0B0, 0xC9785A, 0xF0B07A][Int(bands.unit() * 5) % 5], 0.75))
            ctx.fill(CGRect(x: Double(giant.x) - r, y: y, width: r * 2, height: h))
            ctx.setFillColor(VistaInk.color(0xFFFFFF, 0.08))
            ctx.fill(CGRect(x: Double(giant.x) - r, y: y + h - 2, width: r * 2, height: 2))
            y += h
        }
        VistaInk.blob(ctx, CGPoint(x: giant.x - 30, y: giant.y + 34), rx: 60, ry: 40, VistaInk.color(0xFFF2D8, 0.4))
        VistaInk.blob(ctx, CGPoint(x: giant.x + 44, y: giant.y - 40), rx: r * 1.1, ry: r * 1.1, VistaInk.color(0x2A1240, 0.75), inner: 0.35)
        ctx.restoreGState()
        ctx.addPath(disc)
        ctx.setStrokeColor(VistaInk.color(0xFFD6A8, 0.35))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        ring(front: true)

        // A little cratered moon, upper left.
        let moon = CGPoint(x: 170, y: 640)
        VistaInk.oval(ctx, moon, rx: 24, ry: 24, VistaInk.color(0xD8D0F0))
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: moon.x - 24, y: moon.y - 24, width: 48, height: 48))
        ctx.clip()
        for (dx, dy, cr) in [(-7.0, 6.0, 5.0), (8.0, -5.0, 4.0), (4.0, 11.0, 3.0)] { VistaInk.oval(ctx, CGPoint(x: moon.x + dx, y: moon.y + dy), rx: cr, ry: cr, VistaInk.color(0xA89ECB)) }
        VistaInk.blob(ctx, CGPoint(x: moon.x + 16, y: moon.y - 14), rx: 30, ry: 30, VistaInk.color(0x2A1C50, 0.6))
        ctx.restoreGState()

        // A blue world rising over the horizon on the left.
        let world = CGPoint(x: 250, y: 286), wr = 150.0
        VistaInk.blob(ctx, world, rx: wr * 1.35, ry: wr * 1.35, VistaInk.color(0x5FD0FF, 0.18))
        let globe = VistaInk.ellipse(Double(world.x), Double(world.y), wr, wr)
        VistaInk.fill(ctx, globe, [(0, VistaInk.color(0x9FE8FF)), (0.45, VistaInk.color(0x2F8FD8)), (1, VistaInk.color(0x0E2A6A))],
                      from: CGPoint(x: world.x - wr * 0.6, y: world.y + wr), to: CGPoint(x: world.x + wr * 0.6, y: world.y - wr * 0.6))
        ctx.saveGState()
        ctx.addPath(globe)
        ctx.clip()
        var land = VistaInk.generator(9)
        for _ in 0..<9 {
            let c = CGPoint(x: Double(world.x) + land.range(-120, 100), y: Double(world.y) + land.range(-40, 130))
            VistaInk.blob(ctx, c, rx: land.range(18, 48), ry: land.range(10, 26), VistaInk.color(0x5FC27A, 0.75), inner: 0.6)
        }
        for _ in 0..<14 {
            let c = CGPoint(x: Double(world.x) + land.range(-140, 140), y: Double(world.y) + land.range(-30, 140))
            VistaInk.blob(ctx, c, rx: land.range(20, 60), ry: land.range(4, 9), VistaInk.color(0xFFFFFF, 0.6))
        }
        VistaInk.blob(ctx, CGPoint(x: world.x + 70, y: world.y - 40), rx: wr * 1.05, ry: wr * 1.05, VistaInk.color(0x08103A, 0.65), inner: 0.4)
        ctx.restoreGState()
        ctx.addPath(globe)
        ctx.setStrokeColor(VistaInk.color(0xBFF0FF, 0.6))
        ctx.setLineWidth(2)
        ctx.strokePath()
    }

    private static let horizon = 300.0

    /// The surface of a small grey moon: a curved horizon, craters lit from the upper left, and a rim of planet light.
    private func paintMoonSurface(_ ctx: CGContext) {
        let ground = CGMutablePath()
        ground.move(to: CGPoint(x: -48, y: 0))
        var x = -48.0
        while x <= 1336 {
            let k = (x - 640) / 900
            ground.addLine(to: CGPoint(x: x, y: Self.horizon - 26 * k * k + 6 * (VistaInk.hills(x / 90, seed: 5) - 0.5)))
            x += 8
        }
        ground.addLine(to: CGPoint(x: 1336, y: 0))
        ground.closeSubpath()
        VistaInk.fill(ctx, ground, [(0, VistaInk.color(0xC6BEE4)), (0.18, VistaInk.color(0xA79ECC)), (0.55, VistaInk.color(0x7E74A8)), (1, VistaInk.color(0x4E4478))],
                      from: CGPoint(x: 0, y: Self.horizon), to: CGPoint(x: 0, y: 0))
        ctx.saveGState()
        ctx.addPath(ground)
        ctx.clip()
        VistaInk.blob(ctx, CGPoint(x: 240, y: 260), rx: 620, ry: 120, VistaInk.color(0xBFE6FF, 0.25))
        var rng = VistaInk.generator(19)
        // Craters in perspective.
        for _ in 0..<30 {
            let t = rng.unit()
            let cy = Self.horizon - 14 - pow(t, 1.5) * (Self.horizon - 20)
            let s = 0.25 + 1.4 * pow(t, 1.4)
            let cx = rng.range(-40, 1320)
            let rx = rng.range(18, 60) * s, ry = rx * (0.18 + 0.2 * t)
            VistaInk.blob(ctx, CGPoint(x: cx + rx * 0.08, y: cy - ry * 0.35), rx: rx * 1.2, ry: ry * 1.1, VistaInk.color(0xE2DCF8, 0.45), inner: 0.5)
            VistaInk.oval(ctx, CGPoint(x: cx, y: cy - ry * 0.08), rx: rx, ry: ry, VistaInk.color(0x5E5490))
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: cx - rx, y: cy - ry * 1.08, width: rx * 2, height: ry * 2))
            ctx.clip()
            VistaInk.oval(ctx, CGPoint(x: cx + rx * 0.18, y: cy - ry * 0.3), rx: rx * 0.9, ry: ry * 0.8, VistaInk.color(0x9A90C4))
            ctx.restoreGState()
        }
        // Grit.
        for _ in 0..<500 {
            let t = rng.unit()
            let y = Self.horizon - 8 - t * (Self.horizon - 10)
            let r = 0.5 + 1.4 * t
            ctx.setFillColor(VistaInk.color(rng.chance(0.5) ? 0x3E3468 : 0xE6E0FA, rng.range(0.2, 0.5)))
            ctx.fillEllipse(in: CGRect(x: rng.range(-40, 1320), y: y, width: r, height: r * 0.7))
        }
        ctx.restoreGState()
        // The horizon catches the light of the nebula.
        ctx.addPath(ground)
        ctx.setStrokeColor(VistaInk.color(0xE6DCFF, 0.5))
        ctx.setLineWidth(2)
        ctx.strokePath()
    }

    private func paintVignette(_ ctx: CGContext) {
        let g = VistaInk.gradient([(0, VistaInk.color(0x05031A, 0)), (0.6, VistaInk.color(0x05031A, 0)), (1, VistaInk.color(0x05031A, 0.55))])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 380), startRadius: 0, endCenter: CGPoint(x: 640, y: 380), endRadius: 820, options: [.drawsAfterEndLocation])
    }

    /// Boulders in the bottom corners, in front of everything.
    private func paintRocks() -> [VistaLayer] {
        func boulders(_ rect: CGRect, seed: UInt64) -> VistaLayer? {
            VistaInk.layer(rect, parallax: 36) { ctx in
                var rng = VistaInk.generator(seed)
                let style = VistaInkStyle(rim: 0xC8A8FF, rimAmount: 0.6, line: 2, ink: 0.5, gloss: 0.12)
                for i in 0..<4 {
                    let cx = Double(rect.minX) + Double(rect.width) * (0.15 + 0.22 * Double(i)) + rng.range(-20, 20)
                    let w = rng.range(60, 120) * (i == 1 ? 1.4 : 1), h = w * rng.range(0.45, 0.7)
                    var pts: [CGPoint] = []
                    for k in 0..<9 {
                        let a = Double(k) / 9 * 2 * .pi
                        pts.append(CGPoint(x: cx + cos(a) * w * 0.5 * rng.range(0.8, 1.1), y: max(-4, h * 0.45 + sin(a) * h * 0.55 * rng.range(0.8, 1.1))))
                    }
                    let rock = VistaInk.smooth(pts, tension: 0.35)
                    VistaInk.shade(ctx, rock, VistaTone(0xA69CCC, 0x6E6498, 0x30285A), style, u: 1)
                    for _ in 0..<3 {
                        let c = CGPoint(x: cx + rng.range(-w * 0.25, w * 0.25), y: h * rng.range(0.3, 0.7))
                        VistaInk.oval(ctx, c, rx: w * 0.07, ry: w * 0.04, VistaInk.color(0x3E3468, 0.6))
                    }
                }
            }
        }
        return [boulders(CGRect(x: -40, y: 0, width: 300, height: 110), seed: 2), boulders(CGRect(x: 1050, y: 0, width: 280, height: 100), seed: 5)].compactMap { $0 }
    }

    // MARK: Each frame

    func paintBackdrop(_ ctx: CGContext, _ frame: VistaFrame) {
        ctx.interpolationQuality = .low
        backdrop?.draw(in: ctx, shift: frame.shift)
        drawTwinkles(ctx, frame)
        drawComets(ctx, frame)
        drawSatellite(ctx, frame)
        ctx.interpolationQuality = .high
    }

    private func drawTwinkles(_ ctx: CGContext, _ frame: VistaFrame) {
        guard let twinkle = VistaSprites.twinkle(0xDCE8FF) else { return }
        for i in 0..<26 {
            let f = Double(i)
            let x = (f * 149.3 + 31).truncatingRemainder(dividingBy: 1280) + Double(frame.shift.x) * 10
            let y = 330 + (f * 97.7).truncatingRemainder(dividingBy: 380)
            let pulse = max(0, sin(frame.time * (1.2 + 0.13 * f) + f * 2.7))
            guard pulse > 0.15 else { continue }
            let s = 3 + 7 * pulse * pulse
            ctx.setAlpha(CGFloat(0.8 * pulse))
            ctx.draw(twinkle, in: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2))
        }
        ctx.setAlpha(1)
    }

    /// Comets crossing now and then, a shooting star more often.
    private func drawComets(_ ctx: CGContext, _ frame: VistaFrame) {
        guard let tail, let glow = VistaSprites.glow(0xCFF6FF) else { return }
        let t = frame.time
        for (period, offset, from, to, speed) in [(11.0, 2.0, CGPoint(x: -120, y: 690), CGPoint(x: 1400, y: 470), 4.0), (17.0, 9.0, CGPoint(x: 1400, y: 700), CGPoint(x: 300, y: 560), 5.5)] {
            let local = (t + offset).truncatingRemainder(dividingBy: period)
            guard local < speed else { continue }
            let k = local / speed
            let p = CGPoint(x: from.x + (to.x - from.x) * k, y: from.y + (to.y - from.y) * k)
            let angle = atan2(Double(to.y - from.y), Double(to.x - from.x))
            let fade = min(1, k * 6) * min(1, (1 - k) * 6)
            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: CGFloat(angle))
            ctx.setAlpha(CGFloat(fade))
            ctx.draw(tail, in: CGRect(x: -214, y: -12, width: 220, height: 24))
            ctx.restoreGState()
            ctx.stampDot(glow, at: p, radius: 14, alpha: fade)
        }
        // A shooting star: quick and thin.
        let local = t.truncatingRemainder(dividingBy: 6.5)
        if local < 0.6 {
            let k = local / 0.6
            let start = CGPoint(x: 300 + (t / 6.5).rounded(.down).truncatingRemainder(dividingBy: 5) * 160, y: 690)
            let p = CGPoint(x: start.x + 260 * k, y: start.y - 120 * k)
            ctx.setStrokeColor(VistaInk.color(0xFFFFFF, 0.7 * (1 - k)))
            ctx.setLineWidth(1.6)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: p.x - 60, y: p.y + 28)); ctx.addLine(to: p)
            ctx.strokePath()
        }
    }

    private func drawSatellite(_ ctx: CGContext, _ frame: VistaFrame) {
        let t = frame.time
        let x = (t * 14 + 200).truncatingRemainder(dividingBy: 1500) - 110 + Double(frame.shift.x) * 8
        let y = 655 - x * 0.04
        ctx.setFillColor(VistaInk.color(0x8C88B8))
        ctx.fill(CGRect(x: x - 3, y: y - 2, width: 6, height: 4))
        ctx.setFillColor(VistaInk.color(0x4E7AD0))
        ctx.fill(CGRect(x: x - 13, y: y - 1.5, width: 8, height: 3))
        ctx.fill(CGRect(x: x + 5, y: y - 1.5, width: 8, height: 3))
        if sin(t * 5) > 0.6, let dot = Sprites.dot(red: 1, green: 0.3, blue: 0.4) { ctx.stampDot(dot, at: CGPoint(x: x, y: y + 3), radius: 4, alpha: 0.9) }
    }

    func paintForeground(_ ctx: CGContext, _ frame: VistaFrame) {
        ctx.interpolationQuality = .low
        for rock in rocks { rock.draw(in: ctx, shift: frame.shift) }
        // Specks of dust drifting in the starlight.
        if let dot = Sprites.dot(red: 0.85, green: 0.9, blue: 1) {
            for i in 0..<16 {
                let f = Double(i)
                let x = (f * 83.1 + frame.time * (5 + Double(i % 4) * 2)).truncatingRemainder(dividingBy: 1320) - 20 + Double(frame.shift.x) * 24
                let y = 80 + (f * 41.3).truncatingRemainder(dividingBy: 520) + sin(frame.time * 0.4 + f) * 14
                ctx.stampDot(dot, at: CGPoint(x: x, y: y), radius: 1.6 + Double(i % 3), alpha: 0.18 + 0.14 * sin(frame.time * 1.3 + f * 2))
            }
        }
        ctx.interpolationQuality = .high
    }

    // MARK: The creatures

    func paintCreature(_ ctx: CGContext, _ rig: VistaRig) {
        guard let figure = figures[rig.creature.species] else { return }
        let p = figure.parts(for: rig)
        switch rig.species.art {
        case VistaSpaceCast.astronaut: drawAstronaut(ctx, rig, p)
        case VistaSpaceCast.ufo: drawSaucer(ctx, rig, p)
        case VistaSpaceCast.robot: drawRobot(ctx, rig, p)
        case VistaSpaceCast.whale: drawWhale(ctx, rig, p)
        case VistaSpaceCast.alien: drawAlien(ctx, rig, p)
        default: drawStar(ctx, rig, p)
        }
    }

    /// The saucer's beam: a cone of light from its belly down round the person, drawn behind them, rings sliding down it. And the
    /// star leaves a twinkling trail.
    func paintAura(_ ctx: CGContext, _ rig: VistaRig, _ world: VistaWorld, _ frame: VistaFrame) {
        let c = rig.creature
        if rig.species.art == VistaSpaceCast.star, rig.moving, let twinkle = VistaSprites.twinkle(0xFFE68A) {
            for k in 1...4 {
                let back = SIMD2(-c.vel.x, -c.vel.y) * (0.035 * Double(k))
                let s = 9 - Double(k) * 1.6
                ctx.setAlpha(CGFloat(0.6 - Double(k) * 0.12))
                ctx.draw(twinkle, in: CGRect(x: c.pos.x + back.x - s, y: c.pos.y + back.y - s, width: s * 2, height: s * 2))
            }
            ctx.setAlpha(1)
        }
        guard rig.species.art == VistaSpaceCast.ufo, let person = frame.person else { return }
        let on = rig.during(0.45, rig.species.actSeconds - 0.25, ease: 0.3)
        guard on > 0.01 else { return }
        let h = world.height(c)
        let top = CGPoint(x: c.pos.x, y: c.pos.y - h * 0.2)
        let floor = world.layout.ground(0.62)
        let halfBottom = max(160, Double(person.box.width) * 0.62) * (0.4 + 0.6 * on)
        let middle = Double(person.head.x) * 0.7 + Double(top.x) * 0.3
        let cone = CGMutablePath()
        cone.move(to: CGPoint(x: top.x - h * 0.42, y: top.y))
        cone.addLine(to: CGPoint(x: top.x + h * 0.42, y: top.y))
        cone.addLine(to: CGPoint(x: middle + halfBottom, y: floor))
        cone.addLine(to: CGPoint(x: middle - halfBottom, y: floor))
        cone.closeSubpath()
        // A wide faint cone round a brighter one, both fading out toward the ground.
        let outer = CGMutablePath()
        outer.move(to: CGPoint(x: top.x - h * 0.6, y: top.y))
        outer.addLine(to: CGPoint(x: top.x + h * 0.6, y: top.y))
        outer.addLine(to: CGPoint(x: middle + halfBottom * 1.18, y: floor))
        outer.addLine(to: CGPoint(x: middle - halfBottom * 1.18, y: floor))
        outer.closeSubpath()
        ctx.saveGState()
        ctx.addPath(outer)
        ctx.clip()
        ctx.drawLinearGradient(VistaInk.gradient([(0, VistaInk.color(0xDFFBFF, 0.18 * on)), (0.8, VistaInk.color(0x7FE8FF, 0.06 * on)), (1, VistaInk.color(0x7FE8FF, 0))]),
                               start: top, end: CGPoint(x: middle, y: floor), options: [])
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(cone)
        ctx.clip()
        ctx.drawLinearGradient(VistaInk.gradient([(0, VistaInk.color(0xEFFFFF, 0.5 * on)), (0.75, VistaInk.color(0x9FF0FF, 0.16 * on)), (1, VistaInk.color(0x7FE8FF, 0))]),
                               start: top, end: CGPoint(x: middle, y: floor), options: [])
        // Rings of light slide down the beam.
        ctx.setStrokeColor(VistaInk.color(0xEFFFFF, 0.35 * on))
        ctx.setLineWidth(3)
        for k in 0..<4 {
            let f = (frame.time * 0.6 + Double(k) / 4).truncatingRemainder(dividingBy: 1)
            let y = Double(top.y) + (floor - Double(top.y)) * f
            let half = h * 0.42 + (halfBottom - h * 0.42) * f
            let x = Double(top.x) + (middle - Double(top.x)) * f
            ctx.strokeEllipse(in: CGRect(x: x - half, y: y - 8 - 10 * f, width: half * 2, height: 16 + 20 * f))
        }
        ctx.restoreGState()
        VistaInk.blob(ctx, CGPoint(x: middle, y: floor), rx: halfBottom * 1.1, ry: 26, VistaInk.color(0xBFF6FF, 0.4 * on))
    }

    // MARK: Astronaut

    private enum Astronaut {
        static let torso = 0, helmet = 1, arm = 2, armFar = 3, leg = 4, legFar = 5
        static let neck = CGPoint(x: 0, y: 0.12)
        static let shoulder = CGPoint(x: 0.13, y: 0.06)
        static let hip = CGPoint(x: 0.06, y: -0.13)
    }

    private func bakeAstronaut(_ u: Double) -> [VistaPart?] {
        let s = ink
        let torso = VistaPart.bake(u: u, box: CGRect(x: -0.28, y: -0.2, width: 0.48, height: 0.38)) { ctx in
            let pack = VistaInk.rounded(CGRect(x: -0.26, y: -0.13, width: 0.16, height: 0.28), 0.04)
            VistaInk.shade(ctx, pack, VistaTone(0xD8DCEC, 0xA8AECC, 0x666C92), s, u: u)
            let body = VistaInk.rounded(CGRect(x: -0.17, y: -0.17, width: 0.34, height: 0.32), 0.1)
            VistaInk.shade(ctx, body, Tone.suit, s, u: u)
            let panel = VistaInk.rounded(CGRect(x: 0.0, y: -0.05, width: 0.13, height: 0.11), 0.02)
            VistaInk.shade(ctx, panel, VistaTone(0xB8C0E0, 0x8890B8, 0x4A5080), s, u: u, rim: 0, gloss: 0.1)
            for (i, color) in [0xFF5A6E, 0x5AD8FF, 0xFFD24A].enumerated() {
                VistaInk.oval(ctx, CGPoint(x: 0.03 + Double(i) * 0.035, y: 0.025), rx: 0.012, ry: 0.012, VistaInk.color(UInt32(color)))
            }
            VistaInk.patch(ctx, clip: body, CGPath(rect: CGRect(x: -0.2, y: -0.14, width: 0.4, height: 0.035), transform: nil), VistaInk.color(0x8C94B8, 0.8), u: u)
            VistaInk.patch(ctx, clip: body, VistaInk.ellipse(-0.06, -0.07, 0.035, 0.025), VistaInk.color(0xF27E3A), u: u)
        }
        let helmet = VistaPart.bake(u: u, pivot: Astronaut.neck, box: CGRect(x: -0.22, y: 0.08, width: 0.46, height: 0.46)) { ctx in
            let shell = VistaInk.ellipse(0.01, 0.3, 0.2, 0.19)
            VistaInk.shade(ctx, shell, Tone.suit, s, u: u)
            VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: -0.13, y: 0.1, width: 0.27, height: 0.06), 0.03), VistaTone(0xC8CCE0, 0x9AA0C0, 0x5C628A), s, u: u, gloss: 0)
            // The visor: dark glass with a face behind it, the nebula caught in it.
            let visor = VistaInk.ellipse(0.06, 0.3, 0.145, 0.12)
            VistaInk.fill(ctx, visor, [(0, VistaInk.color(0x6A5AA8)), (0.55, VistaInk.color(0x2A2058)), (1, VistaInk.color(0x14102E))],
                          from: CGPoint(x: 0, y: 0.42), to: CGPoint(x: 0, y: 0.18))
            VistaInk.patch(ctx, clip: visor, VistaInk.ellipse(0.07, 0.29, 0.1, 0.085), VistaInk.color(0xF2C8A8, 0.85), soft: 0.03, u: u)
            VistaInk.patch(ctx, clip: visor, VistaInk.ellipse(0.12, 0.2, 0.12, 0.05), VistaInk.color(0xFF6FB8, 0.35), soft: 0.04, u: u)
            ctx.addPath(visor)
            ctx.setStrokeColor(VistaInk.color(0x8E96BC))
            ctx.setLineWidth(CGFloat(3 / u))
            ctx.strokePath()
            // Its little aerial.
            ctx.setStrokeColor(VistaInk.color(0x8E96BC))
            ctx.setLineWidth(CGFloat(2.4 / u))
            ctx.move(to: CGPoint(x: -0.1, y: 0.46)); ctx.addLine(to: CGPoint(x: -0.13, y: 0.52)); ctx.strokePath()
        }
        func arm(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.08, y: -0.3, width: 0.18, height: 0.38)) { ctx in
                VistaInk.shade(ctx, VistaInk.capsule(0, 0.01, 0.03, -0.18, 0.062, 0.056), tone, s, u: u, gloss: 0.12)
                VistaInk.shade(ctx, VistaInk.ellipse(0.035, -0.235, 0.055, 0.05), Tone.glove, s, u: u, gloss: 0.15)
            }
        }
        func leg(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.09, y: -0.36, width: 0.22, height: 0.42)) { ctx in
                VistaInk.shade(ctx, VistaInk.capsule(0, 0.0, 0.02, -0.24, 0.078, 0.07), tone, s, u: u, gloss: 0.1)
                VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: -0.06, y: -0.33, width: 0.15, height: 0.08), 0.035), VistaTone(0x8E96BC, 0x5E6690, 0x2C3258), s, u: u, gloss: 0.1)
            }
        }
        return [torso, helmet, arm(Tone.suit), arm(Tone.suitFar), leg(Tone.suit), leg(Tone.suitFar)]
    }

    private func drawAstronaut(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let t = rig.clock
        let wave = rig.hold(rise: 0.35, fall: 0.4)
        // Floating: limbs drift slowly, as if in water.
        let drift = sin(t * 0.9)
        ctx.place(p[Astronaut.legFar], at: CGPoint(x: -Astronaut.hip.x, y: Astronaut.hip.y), angle: -0.25 + 0.15 * drift)
        ctx.place(p[Astronaut.armFar], at: CGPoint(x: -Astronaut.shoulder.x + 0.02, y: Astronaut.shoulder.y), angle: -0.5 - 0.2 * drift)
        ctx.place(p[Astronaut.torso], at: .zero, sy: 1 + 0.01 * rig.breath)
        ctx.place(p[Astronaut.leg], at: Astronaut.hip, angle: 0.2 - 0.15 * drift)
        let look = rig.gaze.y * 0.2 * rig.attention
        ctx.local(at: Astronaut.neck, angle: look + 0.06 * sin(t * 0.7)) {
            ctx.place(p[Astronaut.helmet], at: .zero)
            let o = -Double(Astronaut.neck.y)
            let blink = rig.blink
            VistaFace.bead(ctx, 0.04, 0.315 + o, r: 0.018, look: rig.gaze, blink: blink)
            VistaFace.bead(ctx, 0.11, 0.315 + o, r: 0.018, look: rig.gaze, blink: blink)
            ctx.setStrokeColor(VistaInk.color(0x7A3A3A, 0.9))
            ctx.setLineWidth(0.009)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 0.055, y: 0.255 + o))
            ctx.addQuadCurve(to: CGPoint(x: 0.1, y: 0.255 + o), control: CGPoint(x: 0.078, y: 0.235 + o - 0.012 * wave))
            ctx.strokePath()
            // A shine across the glass.
            ctx.setStrokeColor(VistaInk.color(0xFFFFFF, 0.55))
            ctx.setLineWidth(0.014)
            ctx.addArc(center: CGPoint(x: 0.06, y: 0.3 + o), radius: 0.11, startAngle: 1.9, endAngle: 2.6, clockwise: false)
            ctx.strokePath()
            if sin(t * 3) > 0.2 { VistaInk.oval(ctx, CGPoint(x: -0.13, y: 0.52 + o), rx: 0.016, ry: 0.016, VistaInk.color(0xFF5A6E)) }
        }
        // The near arm waves hello.
        let raise = -0.4 + 0.25 * drift + wave * (2.7 + 0.45 * sin(rig.actTime * 9))
        ctx.place(p[Astronaut.arm], at: Astronaut.shoulder, angle: raise)
    }

    // MARK: Flying saucer

    private enum Saucer {
        static let hull = 0, dome = 1, pilot = 2
    }

    private func bakeSaucer(_ u: Double) -> [VistaPart?] {
        let s = ink
        let hull = VistaPart.bake(u: u, box: CGRect(x: -1.06, y: -0.36, width: 2.12, height: 0.6)) { ctx in
            let belly = VistaInk.ellipse(0, -0.12, 0.56, 0.17)
            VistaInk.shade(ctx, belly, Tone.hull, s, u: u)
            VistaInk.blob(ctx, CGPoint(x: 0, y: -0.24), rx: 0.2, ry: 0.07, VistaInk.color(0x9FF4FF, 0.9), inner: 0.3)
            let disc = VistaInk.ellipse(0, 0, 1.0, 0.21)
            VistaInk.shade(ctx, disc, Tone.metal, s, u: u)
            VistaInk.patch(ctx, clip: disc, VistaInk.ellipse(0, -0.05, 1.02, 0.12), VistaInk.color(0x6E6A9A, 0.45), soft: 0.02, u: u)
            ctx.setStrokeColor(VistaInk.color(0x5E5A86, 0.6))
            ctx.setLineWidth(CGFloat(1.4 / u))
            ctx.strokeEllipse(in: CGRect(x: -0.72, y: -0.1, width: 1.44, height: 0.24))
        }
        let pilot = VistaPart.bake(u: u, box: CGRect(x: -0.22, y: 0.04, width: 0.44, height: 0.42)) { ctx in
            for side in [-1.0, 1.0] {
                ctx.setStrokeColor(VistaInk.color(0x3E8A30))
                ctx.setLineWidth(CGFloat(2.4 / u))
                ctx.move(to: CGPoint(x: side * 0.06, y: 0.3)); ctx.addLine(to: CGPoint(x: side * 0.12, y: 0.4)); ctx.strokePath()
                VistaInk.oval(ctx, CGPoint(x: side * 0.12, y: 0.41), rx: 0.025, ry: 0.025, VistaInk.color(0xFF7AC8))
            }
            VistaInk.shade(ctx, VistaInk.ellipse(0, 0.2, 0.15, 0.13), Tone.alien, s, u: u)
        }
        let dome = VistaPart.bake(u: u, box: CGRect(x: -0.46, y: 0.0, width: 0.92, height: 0.46)) { ctx in
            let glass = CGMutablePath()
            glass.addArc(center: CGPoint(x: 0, y: 0.08), radius: 0.4, startAngle: 0, endAngle: .pi, clockwise: false)
            glass.closeSubpath()
            ctx.saveGState()
            ctx.addPath(glass)
            ctx.clip()
            ctx.drawLinearGradient(VistaInk.gradient([(0, VistaInk.color(0xCFF8FF, 0.55)), (1, VistaInk.color(0x4FB8E0, 0.25))]),
                                   start: CGPoint(x: -0.2, y: 0.48), end: CGPoint(x: 0.2, y: 0.08), options: [])
            ctx.restoreGState()
            ctx.setStrokeColor(VistaInk.color(0xFFFFFF, 0.8))
            ctx.setLineWidth(CGFloat(3 / u))
            ctx.setLineCap(.round)
            ctx.addArc(center: CGPoint(x: 0, y: 0.08), radius: 0.32, startAngle: 1.9, endAngle: 2.6, clockwise: false)
            ctx.strokePath()
            ctx.addPath(glass)
            ctx.setStrokeColor(VistaInk.color(0x5E5A86, 0.7))
            ctx.setLineWidth(CGFloat(1.8 / u))
            ctx.strokePath()
        }
        return [hull, dome, pilot]
    }

    private func drawSaucer(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let t = rig.clock
        let wobble = sin(t * 2.3) * 0.04
        ctx.saveGState()
        ctx.rotate(by: CGFloat(wobble))
        // The pilot inside the dome, bobbing, looking at you.
        ctx.local(at: CGPoint(x: 0.02, y: 0.04 + sin(t * 3) * 0.015)) {
            ctx.place(p[Saucer.pilot], at: .zero)
            VistaFace.iris(ctx, 0.03 + rig.gaze.x * 0.02, 0.21, r: 0.065, look: rig.gaze, blink: rig.blink, iris: 0x7A3CC8, lid: 0x74D94C, rest: 0.1)
        }
        ctx.place(p[Saucer.dome], at: .zero)
        ctx.place(p[Saucer.hull], at: .zero)
        // Lights round the rim, chasing.
        for k in 0..<7 {
            let a = Double(k) / 6 * .pi
            let x = cos(a) * 0.82, y = -sin(a) * 0.1 - 0.02
            let on = 0.5 + 0.5 * sin(t * 7 - Double(k) * 0.9)
            let tint: UInt32 = [0xFF6FB8, 0x8FF0FF, 0xFFE38A][k % 3]
            VistaInk.oval(ctx, CGPoint(x: x, y: y), rx: 0.05, ry: 0.035, VistaInk.color(VistaInk.mixHex(0x4A4670, tint, 0.3 + 0.7 * on)))
            VistaInk.oval(ctx, CGPoint(x: x - 0.012, y: y + 0.01), rx: 0.016, ry: 0.01, VistaInk.color(0xFFFFFF, 0.5 + 0.5 * on))
        }
        ctx.restoreGState()
    }

    // MARK: Robot

    private enum Robot {
        static let body = 0, head = 1, arm = 2, armFar = 3, wheel = 4
        static let neck = CGPoint(x: 0.0, y: 0.6)
        static let shoulder = CGPoint(x: 0.16, y: 0.52)
        static let axle = CGPoint(x: 0.0, y: 0.11)
    }

    private func bakeRobot(_ u: Double) -> [VistaPart?] {
        let s = ink
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.26, y: 0.1, width: 0.52, height: 0.56)) { ctx in
            VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: -0.08, y: 0.14, width: 0.16, height: 0.1), 0.02), Tone.metal, s, u: u, gloss: 0)
            let box = VistaInk.rounded(CGRect(x: -0.2, y: 0.2, width: 0.4, height: 0.4), 0.09)
            VistaInk.shade(ctx, box, Tone.robot, s, u: u)
            let screen = VistaInk.rounded(CGRect(x: -0.08, y: 0.3, width: 0.2, height: 0.16), 0.04)
            VistaInk.shade(ctx, screen, VistaTone(0x3A3A6A, 0x1E1E44, 0x0C0C22), s, u: u, rim: 0, gloss: 0.15)
            ctx.setFillColor(VistaInk.color(0xFF7AB6))
            let heart = CGMutablePath()
            heart.move(to: CGPoint(x: 0.02, y: 0.34))
            heart.addCurve(to: CGPoint(x: 0.02, y: 0.42), control1: CGPoint(x: -0.05, y: 0.39), control2: CGPoint(x: -0.01, y: 0.45))
            heart.addCurve(to: CGPoint(x: 0.02, y: 0.34), control1: CGPoint(x: 0.05, y: 0.45), control2: CGPoint(x: 0.09, y: 0.39))
            ctx.addPath(heart)
            ctx.fillPath()
            for (x, y) in [(-0.15, 0.55), (0.15, 0.55), (-0.15, 0.25), (0.15, 0.25)] { VistaInk.oval(ctx, CGPoint(x: x, y: y), rx: 0.014, ry: 0.014, VistaInk.color(0x2A7A84)) }
        }
        let head = VistaPart.bake(u: u, pivot: Robot.neck, box: CGRect(x: -0.24, y: 0.56, width: 0.5, height: 0.36)) { ctx in
            VistaInk.shade(ctx, VistaInk.rounded(CGRect(x: -0.04, y: 0.58, width: 0.08, height: 0.06), 0.01), Tone.metal, s, u: u, gloss: 0)
            for side in [-1.0, 1.0] {
                VistaInk.shade(ctx, VistaInk.ellipse(side * 0.2, 0.75, 0.035, 0.05), Tone.metal, s, u: u, gloss: 0.2)
            }
            let shell = VistaInk.rounded(CGRect(x: -0.19, y: 0.63, width: 0.38, height: 0.25), 0.1)
            VistaInk.shade(ctx, shell, Tone.robot, s, u: u)
            let face = VistaInk.rounded(CGRect(x: -0.13, y: 0.67, width: 0.29, height: 0.17), 0.07)
            VistaInk.shade(ctx, face, VistaTone(0x3A3A6A, 0x1E1E44, 0x0C0C22), s, u: u, rim: 0, gloss: 0.2)
            ctx.setStrokeColor(VistaInk.color(Tone.metal.base))
            ctx.setLineWidth(CGFloat(2.4 / u))
            ctx.move(to: CGPoint(x: 0.0, y: 0.88)); ctx.addLine(to: CGPoint(x: 0.0, y: 0.97)); ctx.strokePath()
        }
        func arm(_ tone: VistaTone) -> VistaPart? {
            VistaPart.bake(u: u, box: CGRect(x: -0.07, y: -0.32, width: 0.2, height: 0.38)) { ctx in
                VistaInk.shade(ctx, VistaInk.capsule(0, 0, 0.03, -0.2, 0.04, 0.034), tone, s, u: u, gloss: 0.15)
                let claw = CGMutablePath()
                claw.addArc(center: CGPoint(x: 0.035, y: -0.245), radius: 0.05, startAngle: 0.5, endAngle: 2 * .pi - 0.5, clockwise: false)
                ctx.addPath(claw)
                ctx.setStrokeColor(VistaInk.color(Tone.metal.dark))
                ctx.setLineWidth(CGFloat(4.5 / u))
                ctx.setLineCap(.round)
                ctx.strokePath()
            }
        }
        let wheel = VistaPart.bake(u: u, box: CGRect(x: -0.13, y: -0.13, width: 0.26, height: 0.26)) { ctx in
            VistaInk.shade(ctx, VistaInk.ellipse(0, 0, 0.11, 0.11), VistaTone(0x5A5880, 0x34325A, 0x15142E), s, u: u, gloss: 0.1)
            VistaInk.shade(ctx, VistaInk.ellipse(0, 0, 0.055, 0.055), Tone.metal, s, u: u, rim: 0.4)
        }
        return [body, head, arm(Tone.robot), arm(Tone.robotFar), wheel]
    }

    private func drawRobot(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let t = rig.clock
        let wave = rig.hold(rise: 0.3, fall: 0.4)
        let roll = rig.moving ? rig.stride * 0.9 : 0
        let lean = rig.moving ? 0.08 : 0
        ctx.place(p[Robot.armFar], at: CGPoint(x: -Robot.shoulder.x, y: Robot.shoulder.y), angle: -0.3 + 0.1 * sin(t * 1.2))
        ctx.place(p[Robot.wheel], at: Robot.axle, angle: -roll)
        // Spokes, so the turning shows.
        ctx.setStrokeColor(VistaInk.color(0x8C88B8, 0.8))
        ctx.setLineWidth(0.012)
        for k in 0..<3 {
            let a = -roll + Double(k) * .pi / 3
            ctx.move(to: CGPoint(x: cos(a) * 0.1, y: 0.11 + sin(a) * 0.1)); ctx.addLine(to: CGPoint(x: -cos(a) * 0.1, y: 0.11 - sin(a) * 0.1))
        }
        ctx.strokePath()
        ctx.local(at: CGPoint(x: 0, y: 0.12), angle: -lean) {
            ctx.place(p[Robot.body], at: CGPoint(x: 0, y: -0.12), sy: 1 + 0.01 * rig.breath)
            let tilt = rig.gaze.y * 0.15 * rig.attention + 0.1 * wave * sin(rig.actTime * 4)
            ctx.local(at: CGPoint(x: Robot.neck.x, y: Robot.neck.y - 0.12), angle: tilt) {
                ctx.place(p[Robot.head], at: .zero)
                let o = -Double(Robot.neck.y)
                // LED eyes: round when open, a line when they blink, hearts when it is happy.
                let lx = rig.gaze.x * 0.012, ly = rig.gaze.y * 0.012
                for x in [-0.035, 0.075] {
                    let ex = x + lx, ey = 0.765 + o + ly
                    if wave > 0.5 {
                        VistaInk.oval(ctx, CGPoint(x: ex, y: ey), rx: 0.032, ry: 0.032, VistaInk.color(0xFF7AB6, 0.35))
                        VistaInk.oval(ctx, CGPoint(x: ex, y: ey), rx: 0.02, ry: 0.02, VistaInk.color(0xFFC4DE))
                    } else {
                        let open = 1 - rig.blink
                        VistaInk.oval(ctx, CGPoint(x: ex, y: ey), rx: 0.034, ry: 0.034 * max(0.15, open), VistaInk.color(0x5AE8FF, 0.35))
                        VistaInk.oval(ctx, CGPoint(x: ex, y: ey), rx: 0.021, ry: 0.024 * max(0.12, open), VistaInk.color(0xCFFAFF))
                    }
                }
                ctx.setStrokeColor(VistaInk.color(0x9FF4FF, 0.9))
                ctx.setLineWidth(0.012)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: -0.01, y: 0.71 + o)); ctx.addQuadCurve(to: CGPoint(x: 0.06, y: 0.71 + o), control: CGPoint(x: 0.025, y: 0.69 + o - 0.015 * wave))
                ctx.strokePath()
                // The aerial's light, pulsing; bright when it is pleased to see you.
                if let glow = VistaSprites.glow(wave > 0.3 ? 0xFF7AB6 : 0xFF5A6E) {
                    let pulse = 0.5 + 0.5 * sin(t * (wave > 0.3 ? 9 : 2.5))
                    ctx.draw(glow, in: CGRect(x: -0.05 - 0.02 * pulse, y: 0.95 + o - 0.02 * pulse, width: 0.1 + 0.04 * pulse, height: 0.1 + 0.04 * pulse))
                }
                VistaInk.oval(ctx, CGPoint(x: 0, y: 1.0 + o), rx: 0.022, ry: 0.022, VistaInk.color(0xFFD0E4))
            }
            let raise = -0.25 + 0.1 * sin(t * 1.4) + wave * (2.6 + 0.4 * sin(rig.actTime * 10))
            ctx.place(p[Robot.arm], at: CGPoint(x: Robot.shoulder.x, y: Robot.shoulder.y - 0.12), angle: raise)
        }
    }

    // MARK: Space whale

    private enum Whale {
        static let body = 0, fluke = 1, fin = 2
        static let tail = CGPoint(x: -0.95, y: -0.02)
        static let finRoot = CGPoint(x: 0.3, y: -0.14)
    }

    private func bakeWhale(_ u: Double) -> [VistaPart?] {
        let s = VistaInkStyle(rim: 0xFF9FE6, rimAmount: 0.45, line: 2, ink: 0.5, gloss: 0.2)
        let outline = VistaInk.smooth([(1.08, 0.06), (0.98, 0.25), (0.66, 0.38), (0.15, 0.36), (-0.42, 0.2), (-0.85, 0.05), (-0.98, 0.0), (-0.85, -0.07),
                                       (-0.4, -0.2), (0.2, -0.34), (0.72, -0.3), (1.02, -0.12)])
        let body = VistaPart.bake(u: u, box: CGRect(x: -1.02, y: -0.34, width: 2.16, height: 0.7)) { ctx in
            VistaInk.shade(ctx, outline, Tone.whale, s, u: u)
            // The pale grooved throat.
            let throat = VistaInk.smooth([(1.0, -0.08), (0.7, -0.2), (0.2, -0.25), (-0.3, -0.14), (0.1, -0.1), (0.6, -0.06)])
            VistaInk.patch(ctx, clip: outline, throat, VistaInk.color(0xB8B4F0, 0.7), soft: 0.02, u: u)
            VistaInk.strokes(ctx, clip: throat, width: 1.4 / u, VistaInk.color(0x6A64C0, 0.6),
                             (0..<6).map { i in let y = -0.1 - Double(i) * 0.025; return (CGPoint(x: 0.95, y: y + 0.02), CGPoint(x: 0.5, y: y - 0.04), CGPoint(x: -0.1, y: y + 0.04)) })
            // Glowing spots along its back, like stars on it.
            var rng = VistaInk.generator(4)
            ctx.saveGState()
            ctx.addPath(outline)
            ctx.clip()
            for _ in 0..<22 {
                let x = rng.range(-0.8, 0.85)
                let y = 0.05 + rng.range(0, 0.2) * (1 - abs(x) * 0.6)
                VistaInk.blob(ctx, CGPoint(x: x, y: y), rx: 0.035, ry: 0.035, VistaInk.color(0x8FF0FF, 0.5))
                VistaInk.oval(ctx, CGPoint(x: x, y: y), rx: 0.008, ry: 0.008, VistaInk.color(0xE8FFFF))
            }
            ctx.restoreGState()
            ctx.setStrokeColor(VistaInk.color(0x1C1C64, 0.8))
            ctx.setLineWidth(CGFloat(2.2 / u))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 1.04, y: -0.04)); ctx.addQuadCurve(to: CGPoint(x: 0.66, y: -0.06), control: CGPoint(x: 0.86, y: -0.1))
            ctx.strokePath()
        }
        let fluke = VistaPart.bake(u: u, pivot: Whale.tail, box: CGRect(x: -1.42, y: -0.3, width: 0.5, height: 0.6)) { ctx in
            VistaInk.shade(ctx, VistaInk.smooth([(-0.94, -0.01), (-1.12, 0.12), (-1.36, 0.24), (-1.3, 0.08), (-1.2, 0.0), (-1.3, -0.1), (-1.36, -0.24), (-1.12, -0.12)], tension: 0.4),
                           Tone.whaleFin, s, u: u)
        }
        let fin = VistaPart.bake(u: u, pivot: Whale.finRoot, box: CGRect(x: -0.24, y: -0.48, width: 0.62, height: 0.4)) { ctx in
            VistaInk.shade(ctx, VistaInk.smooth([(0.36, -0.12), (0.2, -0.26), (-0.05, -0.4), (-0.2, -0.44), (-0.08, -0.32), (0.2, -0.16)], tension: 0.45), Tone.whaleFin, s, u: u)
        }
        return [body, fluke, fin]
    }

    private func drawWhale(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let t = rig.clock
        let swim = sin(t * 1.1)
        ctx.place(p[Whale.fluke], at: Whale.tail, angle: swim * 0.22)
        ctx.place(p[Whale.body], at: .zero, sy: 1 + 0.008 * rig.breath)
        ctx.place(p[Whale.fin], at: Whale.finRoot, angle: 0.15 * sin(t * 0.8 + 1))
        VistaFace.bead(ctx, 0.74, 0.0, r: 0.032, look: rig.gaze, blink: rig.blink, color: 0x0E0E30)
    }

    // MARK: Alien

    private enum Alien {
        static let body = 0, antenna = 1, arm = 2
        static let antennaRoot = CGPoint(x: 0.1, y: 0.68)
        static let shoulder = CGPoint(x: 0.25, y: 0.36)
    }

    private func bakeAlien(_ u: Double) -> [VistaPart?] {
        let s = ink
        let outline = VistaInk.smooth([(0, 0.04), (0.28, 0.08), (0.36, 0.32), (0.29, 0.58), (0.11, 0.72), (-0.11, 0.72), (-0.29, 0.58), (-0.36, 0.32), (-0.28, 0.08)])
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.4, y: -0.02, width: 0.8, height: 0.78)) { ctx in
            for x in [-0.14, 0.14] { VistaInk.shade(ctx, VistaInk.ellipse(x, 0.05, 0.1, 0.055), Tone.alien, s, u: u, gloss: 0) }
            VistaInk.shade(ctx, outline, Tone.alien, s, u: u)
            VistaInk.patch(ctx, clip: outline, VistaInk.ellipse(0.06, 0.2, 0.2, 0.14), VistaInk.color(0xE6FFB8, 0.6), soft: 0.04, u: u)
            var rng = VistaInk.generator(8)
            for _ in 0..<6 {
                VistaInk.patch(ctx, clip: outline, VistaInk.ellipse(rng.range(-0.28, -0.05), rng.range(0.25, 0.6), 0.025, 0.02), VistaInk.color(0x3E9A3A, 0.55), u: u)
            }
        }
        let antenna = VistaPart.bake(u: u, box: CGRect(x: -0.06, y: -0.02, width: 0.18, height: 0.3)) { ctx in
            ctx.setStrokeColor(VistaInk.color(0x4E9E3E))
            ctx.setLineWidth(CGFloat(3 / u))
            ctx.setLineCap(.round)
            ctx.move(to: .zero); ctx.addQuadCurve(to: CGPoint(x: 0.05, y: 0.22), control: CGPoint(x: -0.03, y: 0.14)); ctx.strokePath()
            VistaInk.shade(ctx, VistaInk.ellipse(0.05, 0.23, 0.04, 0.04), VistaTone(0xFFD0F0, 0xFF7AC8, 0xC03A8A), s, u: u, rim: 0.3, gloss: 0.4)
        }
        let arm = VistaPart.bake(u: u, box: CGRect(x: -0.05, y: -0.2, width: 0.12, height: 0.24)) { ctx in
            VistaInk.shade(ctx, VistaInk.capsule(0, 0, 0.02, -0.14, 0.04, 0.035), Tone.alien, s, u: u, gloss: 0.1)
        }
        return [body, antenna, arm]
    }

    private func drawAlien(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let t = rig.clock
        let cheer = rig.hold(rise: 0.25, fall: 0.3)
        ctx.place(p[Alien.antenna], at: CGPoint(x: -0.12, y: 0.66), angle: 0.35 + sin(t * 3.1) * 0.15)
        ctx.place(p[Alien.arm], at: CGPoint(x: -0.26, y: 0.36), angle: -0.6 - cheer * 1.6)
        ctx.place(p[Alien.body], at: .zero, sy: 1 + 0.02 * rig.breath)
        ctx.place(p[Alien.antenna], at: Alien.antennaRoot, angle: -0.25 + sin(t * 2.7 + 1) * 0.18)
        // One big eye.
        VistaFace.iris(ctx, 0.06, 0.46, r: 0.13, look: rig.gaze, blink: rig.blink, iris: 0x8A4AE0, lid: 0x74D94C, rest: 0.08)
        ctx.setStrokeColor(VistaInk.color(0x1E5A1E))
        ctx.setLineWidth(0.02)
        ctx.setLineCap(.round)
        let open = 0.02 + 0.05 * cheer
        ctx.move(to: CGPoint(x: 0.0, y: 0.24)); ctx.addQuadCurve(to: CGPoint(x: 0.14, y: 0.24), control: CGPoint(x: 0.07, y: 0.24 - open))
        ctx.strokePath()
        ctx.place(p[Alien.arm], at: Alien.shoulder, angle: 0.6 + cheer * (1.8 + 0.4 * sin(rig.actTime * 12)))
    }

    // MARK: Star

    private func bakeStar(_ u: Double) -> [VistaPart?] {
        let s = VistaInkStyle(rim: 0xFFFFFF, rimAmount: 0.5, line: 2, ink: 0.45, gloss: 0.4)
        let body = VistaPart.bake(u: u, box: CGRect(x: -0.52, y: -0.52, width: 1.04, height: 1.04)) { ctx in
            var pts: [CGPoint] = []
            for i in 0..<10 {
                let r = i % 2 == 0 ? 0.48 : 0.24
                let a = .pi / 2 + Double(i) * .pi / 5
                pts.append(CGPoint(x: cos(a) * r, y: sin(a) * r - 0.03))
            }
            let shape = VistaInk.smooth(pts, tension: 0.22)
            VistaInk.shade(ctx, shape, Tone.star, s, u: u)
            for x in [-0.15, 0.17] { VistaInk.blob(ctx, CGPoint(x: x, y: -0.08), rx: 0.07, ry: 0.045, VistaInk.color(0xFF8AA8, 0.6)) }
        }
        return [body]
    }

    private func drawStar(_ ctx: CGContext, _ rig: VistaRig, _ p: [VistaPart?]) {
        let t = rig.clock
        if let glow = VistaSprites.glow(0xFFE68A) {
            let pulse = 0.5 + 0.5 * sin(t * 3)
            let r = 0.75 + 0.1 * pulse
            ctx.setAlpha(CGFloat(0.5 + 0.2 * pulse))
            ctx.draw(glow, in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            ctx.setAlpha(1)
        }
        let perched = rig.phase == .acting && rig.creature.landedAt != nil
        let spin = perched ? sin(t * 2) * 0.12 : sin(t * 1.4) * 0.3
        ctx.local(at: .zero, angle: spin) {
            ctx.place(p[0], at: .zero)
            VistaFace.bead(ctx, -0.07, 0.03, r: 0.045, look: rig.gaze, blink: rig.blink, color: 0x3A2410)
            VistaFace.bead(ctx, 0.1, 0.03, r: 0.045, look: rig.gaze, blink: rig.blink, color: 0x3A2410)
            ctx.setStrokeColor(VistaInk.color(0x7A3A10))
            ctx.setLineWidth(0.025)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: -0.02, y: -0.08)); ctx.addQuadCurve(to: CGPoint(x: 0.07, y: -0.08), control: CGPoint(x: 0.025, y: -0.14))
            ctx.strokePath()
        }
    }
}
