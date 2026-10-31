import AppKit
import CoreGraphics
import Foundation

/// Who haunts the manor.
enum HauntedCast {
    static var cast: SceneCast {
        var layout = SceneLayout()
        layout.farGround = 236
        layout.nearGround = 76
        layout.roamLow = 380
        layout.roamHigh = 680

        func ghost(_ home: Double) -> SceneSpecies {
            var g = SceneSpecies(name: "ghost", glyph: "", facesRight: true, height: 170, aspect: 1.12, speed: 58, body: .floater, temper: .prey, act: .boo,
                                 home: home, charge: 2.2, actSeconds: 3.0, shout: "BOO!")
            g.opacity = 0.84
            g.band = 200...600
            return g
        }
        func bat(_ home: Double) -> SceneSpecies {
            var b = SceneSpecies(name: "bat", glyph: "", facesRight: true, height: 104, aspect: 1.5, speed: 210, body: .flier, temper: .prey, act: .orbit,
                                 home: home, charge: 1.5, actSeconds: 5.5, shout: "SKREE!")
            b.band = 400...680
            return b
        }
        var spider = SceneSpecies(name: "spider", glyph: "", facesRight: true, height: 62, aspect: 0.86, speed: 44, body: .floater, temper: .prey, act: .drop,
                                  home: 0.3, charge: 1.6, actSeconds: 4.2, shout: "!")
        spider.band = 470...690
        spider.hangs = true
        func pumpkin(_ home: Double) -> SceneSpecies {
            var p = SceneSpecies(name: "pumpkin", glyph: "", facesRight: true, height: 96, aspect: 0.99, speed: 74, gait: .hop, temper: .prey, act: .hop,
                                 home: home, charge: 1.7, actSeconds: 2.4, shout: "HEE HEE!")
            p.glow = 0xFF8A20
            return p
        }

        var species = [ghost(0.3), ghost(0.78), bat(0.3), bat(0.8), spider, pumpkin(0.22), pumpkin(0.86)]
        for i in species.indices { species[i].painted = true }
        return SceneCast(species: species, roster: [0, 0, 1, 2, 2, 3, 4, 4, 5, 6], layout: layout, cap: 10, visibleAtStart: 7)
    }
}

/// A moonlit graveyard below a dark manor: ghosts float over to say boo, bats wheel around your head, spiders drop on threads, and pumpkins grin.
final class HauntedScene: SceneStyle {
    let cast = HauntedCast.cast
    let look = SceneLook(haze: 0x3A4A9A, hazeAmount: 0.2, dusk: 0x0A0A28, duskAmount: 0.28, warm: 0xB8C4FF, warmAmount: 0.14, shade: 0.34,
                         dust: 0x6A7AB0, shadow: 0.3, shadowLean: 0.1, water: 0xDDEEFF)
    let hint = "Wave your arms to scare the ghosts away!"

    private static let horizon = 290.0
    private static let moon = CGPoint(x: 330, y: 540)

    private var world: SceneLayer?
    private var canvas: SceneCanvas?
    private var clouds: [(layer: SceneLayer, speed: Double, offset: Double)] = []
    private var fog: [(layer: SceneLayer, speed: Double, offset: Double, alpha: Double)] = []
    private var windowGlow: [CGImage] = []
    private var web: CGImage?
    private static let windows: [CGPoint] = [CGPoint(x: 905, y: 395), CGPoint(x: 965, y: 395), CGPoint(x: 1045, y: 402), CGPoint(x: 1105, y: 392), CGPoint(x: 935, y: 340),
                                             CGPoint(x: 1010, y: 338), CGPoint(x: 1075, y: 345), CGPoint(x: 1010, y: 452)]

    private lazy var bakery = SceneBakery([
        { [unowned self] in canvas = SceneCanvas(CGRect(x: -48, y: 0, width: 1376, height: 720)); canvas?.paint { paintSky($0); paintHill($0) } },
        { [unowned self] in canvas?.paint { paintManor($0); paintGraveyard($0) } },
        { [unowned self] in canvas?.paint { paintTombs($0) } },
        { [unowned self] in canvas?.paint { paintTrees($0); paintVignette($0) }; world = canvas?.finish(parallax: 12); canvas = nil },
        { [unowned self] in clouds = paintClouds() },
        { [unowned self] in fog = paintFog() },
        { [unowned self] in
            windowGlow = (0..<4).compactMap { i in ScenePaint.picture(width: 90, height: 90) { ScenePaint.blob($0, CGPoint(x: 45, y: 45), rx: 45, ry: 45, ScenePaint.color(0xFFB040, 0.15 + 0.12 * Double(i)), inner: 0.1) } }
            web = paintWeb()
        },
    ])

    func prepare(until deadline: Double) -> Bool { bakery.run(until: deadline) }

    // MARK: The night

    private func paintSky(_ ctx: CGContext) {
        let h = Self.horizon
        let rect = CGRect(x: -48, y: h - 60, width: 1376, height: 720 - h + 60)
        ScenePaint.fillDown(ctx, rect, [(0, ScenePaint.color(0x04051A)), (0.35, ScenePaint.color(0x0E1236)), (0.7, ScenePaint.color(0x211F58)), (1, ScenePaint.color(0x3A3A78))])
        var rng = ScenePaint.generator(7)
        for _ in 0..<150 {
            let p = CGPoint(x: rng.range(0, 1280), y: rng.range(h + 40, 720))
            ctx.setFillColor(CGColor(gray: 1, alpha: rng.range(0.15, 0.8) * min(1, (p.y - h) / 200)))
            let r = rng.range(0.7, 1.8)
            ctx.fillEllipse(in: CGRect(x: p.x, y: p.y, width: r, height: r))
        }
        // The moon, big and low, with a sick green glow around it.
        let moon = Self.moon
        ScenePaint.blob(ctx, moon, rx: 520, ry: 420, ScenePaint.color(0x6A8AD0, 0.32))
        ScenePaint.blob(ctx, moon, rx: 250, ry: 220, ScenePaint.color(0xA8C8E8, 0.4))
        ScenePaint.blob(ctx, moon, rx: 130, ry: 130, ScenePaint.color(0xD8E8F0, 0.6))
        ScenePaint.oval(ctx, moon, rx: 86, ry: 86, ScenePaint.color(0xF4F0D8))
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: moon.x - 86, y: moon.y - 86, width: 172, height: 172))
        ctx.clip()
        for (dx, dy, r) in [(-30.0, 24.0, 22.0), (26.0, -18.0, 30.0), (-8.0, -44.0, 14.0), (38.0, 40.0, 12.0), (-50.0, -10.0, 10.0)] {
            ScenePaint.blob(ctx, CGPoint(x: moon.x + dx, y: moon.y + dy), rx: r, ry: r, ScenePaint.color(0xBDB898, 0.55), inner: 0.4)
        }
        ScenePaint.blob(ctx, CGPoint(x: moon.x + 50, y: moon.y - 30), rx: 100, ry: 100, ScenePaint.color(0x8890B0, 0.25))
        ctx.restoreGState()
        // Haze along the horizon.
        ScenePaint.fill(ctx, CGRect(x: -48, y: h - 20, width: 1376, height: 120), [(0, ScenePaint.color(0x4A5A9A, 0)), (0.6, ScenePaint.color(0x4A5A9A, 0.45)), (1, ScenePaint.color(0x5A7AA8, 0.8))],
                        from: CGPoint(x: 0, y: h + 100), to: CGPoint(x: 0, y: h - 10))
    }

    private func paintHill(_ ctx: CGContext) {
        let h = Self.horizon
        let ridge = ScenePaint.ridgePath(width: 1376, left: -48, baseY: h + 30, bottom: 0, amplitude: 22, wavelength: 260, seed: 5)
        ctx.addPath(ridge); ctx.setFillColor(ScenePaint.color(0x161A3C)); ctx.fillPath()
        // The hill the manor stands on.
        let hill = CGMutablePath()
        hill.move(to: CGPoint(x: 640, y: 0))
        hill.addCurve(to: CGPoint(x: 1040, y: h + 90), control1: CGPoint(x: 760, y: h - 20), control2: CGPoint(x: 900, y: h + 90))
        hill.addCurve(to: CGPoint(x: 1420, y: h + 10), control1: CGPoint(x: 1180, y: h + 90), control2: CGPoint(x: 1320, y: h + 40))
        hill.addLine(to: CGPoint(x: 1420, y: 0))
        hill.closeSubpath()
        ctx.addPath(hill); ctx.setFillColor(ScenePaint.color(0x0C0F26)); ctx.fillPath()
        ctx.setStrokeColor(ScenePaint.color(0x6A7AC0, 0.5)); ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: 760, y: h - 10))
        ctx.addCurve(to: CGPoint(x: 1040, y: h + 90), control1: CGPoint(x: 820, y: h + 10), control2: CGPoint(x: 900, y: h + 90))
        ctx.strokePath()
    }

    private func paintManor(_ ctx: CGContext) {
        let h = Self.horizon
        let dark = ScenePaint.color(0x080614), rim = ScenePaint.color(0x7A86C8, 0.6)
        func block(_ rect: CGRect) { ctx.setFillColor(dark); ctx.fill(rect) }
        func roof(_ left: Double, _ right: Double, _ y: Double, _ peak: Double) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: left, y: y)); path.addLine(to: CGPoint(x: (left + right) / 2, y: y + peak)); path.addLine(to: CGPoint(x: right, y: y)); path.closeSubpath()
            ctx.addPath(path); ctx.setFillColor(dark); ctx.fillPath()
            ctx.setStrokeColor(rim); ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: left, y: y)); ctx.addLine(to: CGPoint(x: (left + right) / 2, y: y + peak)); ctx.strokePath()
        }
        let baseY = h + 70
        // Wings, the main block, tower, turret.
        block(CGRect(x: 860, y: baseY, width: 130, height: 150))
        block(CGRect(x: 990, y: baseY, width: 150, height: 210))
        block(CGRect(x: 1140, y: baseY, width: 100, height: 130))
        roof(850, 1000, baseY + 150, 56)
        roof(980, 1150, baseY + 210, 90)
        roof(1130, 1250, baseY + 130, 54)
        block(CGRect(x: 925, y: baseY + 150, width: 34, height: 86))      // chimney
        block(CGRect(x: 1160, y: baseY + 130, width: 24, height: 60))
        // The tower with the pointed roof.
        block(CGRect(x: 1010, y: baseY + 190, width: 62, height: 130))
        let spire = CGMutablePath()
        spire.move(to: CGPoint(x: 1000, y: baseY + 320)); spire.addLine(to: CGPoint(x: 1041, y: baseY + 430)); spire.addLine(to: CGPoint(x: 1082, y: baseY + 320)); spire.closeSubpath()
        ctx.addPath(spire); ctx.setFillColor(dark); ctx.fillPath()
        ctx.setStrokeColor(rim); ctx.setLineWidth(2); ctx.move(to: CGPoint(x: 1000, y: baseY + 320)); ctx.addLine(to: CGPoint(x: 1041, y: baseY + 430)); ctx.strokePath()
        ctx.setStrokeColor(dark); ctx.setLineWidth(2); ctx.move(to: CGPoint(x: 1041, y: baseY + 430)); ctx.addLine(to: CGPoint(x: 1041, y: baseY + 462)); ctx.strokePath()
        // Windows, lit from inside.
        func window(_ p: CGPoint, _ w: Double, _ h: Double, lit: Bool) {
            let r = CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
            ctx.setFillColor(lit ? ScenePaint.color(0xFFC060) : ScenePaint.color(0x1A1630))
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)); ctx.fillPath()
            ctx.setStrokeColor(dark); ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: p.x, y: r.minY)); ctx.addLine(to: CGPoint(x: p.x, y: r.maxY)); ctx.move(to: CGPoint(x: r.minX, y: p.y)); ctx.addLine(to: CGPoint(x: r.maxX, y: p.y)); ctx.strokePath()
        }
        for (i, p) in Self.windows.enumerated() { window(p, 22, 34, lit: i % 3 != 2) }
        window(CGPoint(x: 1041, y: baseY + 250), 20, 40, lit: true)
        window(CGPoint(x: 1041, y: baseY + 290), 14, 24, lit: false)
        window(CGPoint(x: 880, y: baseY + 70), 18, 30, lit: false)
        // The door.
        ctx.setFillColor(ScenePaint.color(0x1A1228))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 1020, y: baseY, width: 42, height: 62), cornerWidth: 21, cornerHeight: 21, transform: nil)); ctx.fillPath()
        // A fence of iron spears along the front of the hill.
        ctx.setStrokeColor(dark); ctx.setLineWidth(2.4)
        for i in 0..<30 {
            let x = 780 + Double(i) * 18
            let y = baseY - 12 - max(0, 40 - abs(x - 1040) * 0.1)
            ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x, y: y + 44)); ctx.strokePath()
            ctx.setFillColor(dark)
            ctx.move(to: CGPoint(x: x - 4, y: y + 44)); ctx.addLine(to: CGPoint(x: x, y: y + 56)); ctx.addLine(to: CGPoint(x: x + 4, y: y + 44)); ctx.fillPath()
        }
        ctx.move(to: CGPoint(x: 780, y: baseY + 14)); ctx.addLine(to: CGPoint(x: 1320, y: baseY + 14)); ctx.strokePath()
    }

    private func paintGraveyard(_ ctx: CGContext) {
        let h = Self.horizon
        let rect = CGRect(x: -48, y: 0, width: 1376, height: h - 20)
        ScenePaint.fillDown(ctx, rect, [(0, ScenePaint.color(0x1C2A44)), (0.2, ScenePaint.color(0x142038)), (0.6, ScenePaint.color(0x0C1426)), (1, ScenePaint.color(0x070B18))])
        var rng = ScenePaint.generator(15)
        // Moonlight on the grass.
        ScenePaint.blob(ctx, CGPoint(x: Self.moon.x, y: h - 40), rx: 520, ry: 60, ScenePaint.color(0x7A9AD0, 0.3))
        // A gravel path winding toward the manor.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 350, y: -10))
        path.addCurve(to: CGPoint(x: 1010, y: h - 24), control1: CGPoint(x: 480, y: 120), control2: CGPoint(x: 900, y: 90))
        path.addLine(to: CGPoint(x: 1050, y: h - 24))
        path.addCurve(to: CGPoint(x: 560, y: -10), control1: CGPoint(x: 960, y: 70), control2: CGPoint(x: 640, y: 150))
        path.closeSubpath()
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        ScenePaint.fillDown(ctx, CGRect(x: 300, y: -10, width: 800, height: h), [(0, ScenePaint.color(0x6A7694, 0.5)), (1, ScenePaint.color(0x424C68, 0.5))])
        ctx.restoreGState()
        // Grass: cool, short strokes, bigger toward the bottom of the picture.
        let tones: [UInt32] = [0x2A5A62, 0x3A6A70, 0x1C3A4A, 0x5A8A8A, 0x20304A]
        for _ in 0..<1700 {
            let t = rng.unit()
            let y = h - 24 - pow(t, 1.3) * (h - 24)
            let s = 0.2 + 1.1 * pow(t, 1.2)
            ScenePaint.blade(ctx, at: CGPoint(x: rng.range(-40, 1320), y: y), height: rng.range(7, 20) * s, lean: rng.range(-5, 5) * s, width: max(0.8, 1.4 * s), color: ScenePaint.color(tones[Int(rng.unit() * Double(tones.count))], rng.range(0.3, 0.65)))
        }
    }

    /// Tombstones: rounded, crosses and slabs, each with a lit edge, smaller far away; and mist lying in the hollows.
    private func paintTombs(_ ctx: CGContext) {
        let h = Self.horizon
        var rng = ScenePaint.generator(16)
        for i in 0..<18 {
            let t = rng.range(0.05, 1.0), y = 26 + pow(t, 0.9) * (h - 70)
            let s = 0.4 + 0.9 * (1 - (y - 26) / (h - 70))
            var x = rng.range(-30, 1310)
            if x > 330, x < 940, y < 190 { x = rng.chance(0.5) ? rng.range(-30, 300) : rng.range(960, 1310) }
            tombstone(ctx, x: x, y: y, scale: s, kind: i % 4)
        }
        // Mist lies low in the hollows.
        ScenePaint.blob(ctx, CGPoint(x: 300, y: h - 30), rx: 520, ry: 40, ScenePaint.color(0x9AB0E0, 0.28))
        ScenePaint.blob(ctx, CGPoint(x: 940, y: h - 50), rx: 380, ry: 30, ScenePaint.color(0x9AB0E0, 0.22))
    }

    private func tombstone(_ ctx: CGContext, x: Double, y: Double, scale s: Double, kind: Int) {
        let body = ScenePaint.color(0x3A4468), rim = ScenePaint.color(0x8A9ADA, 0.7), dark = ScenePaint.color(0x0A0E1C, 0.6)
        ScenePaint.oval(ctx, CGPoint(x: x + 6 * s, y: y), rx: 40 * s, ry: 8 * s, dark)
        switch kind {
        case 0:
            let r = CGRect(x: x - 22 * s, y: y, width: 44 * s, height: 62 * s)
            let p = CGMutablePath(); p.addRoundedRect(in: r, cornerWidth: 22 * s, cornerHeight: 22 * s)
            p.addRect(CGRect(x: r.minX, y: y, width: r.width, height: 30 * s))
            ctx.addPath(p); ctx.setFillColor(body); ctx.fillPath()
            ctx.setStrokeColor(rim); ctx.setLineWidth(2 * s); ctx.addArc(center: CGPoint(x: x, y: y + 40 * s), radius: 22 * s, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false); ctx.strokePath()
        case 1:
            ctx.setFillColor(body)
            ctx.fill(CGRect(x: x - 7 * s, y: y, width: 14 * s, height: 70 * s))
            ctx.fill(CGRect(x: x - 24 * s, y: y + 42 * s, width: 48 * s, height: 13 * s))
            ctx.setFillColor(rim); ctx.fill(CGRect(x: x + 5 * s, y: y, width: 2 * s, height: 70 * s))
        case 2:
            ctx.setFillColor(body)
            ctx.fill(CGRect(x: x - 26 * s, y: y, width: 52 * s, height: 46 * s))
            ctx.setFillColor(rim); ctx.fill(CGRect(x: x - 26 * s, y: y + 44 * s, width: 52 * s, height: 3 * s))
        default:
            let r = CGRect(x: x - 18 * s, y: y, width: 36 * s, height: 56 * s)
            let p = CGMutablePath(); p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.minX, y: y + 40 * s)); p.addLine(to: CGPoint(x: x, y: y + 58 * s)); p.addLine(to: CGPoint(x: r.maxX, y: y + 40 * s)); p.addLine(to: CGPoint(x: r.maxX, y: y)); p.closeSubpath()
            ctx.addPath(p); ctx.setFillColor(body); ctx.fillPath()
            ctx.setStrokeColor(rim); ctx.setLineWidth(2 * s); ctx.move(to: CGPoint(x: r.minX, y: y + 40 * s)); ctx.addLine(to: CGPoint(x: x, y: y + 58 * s)); ctx.strokePath()
        }
    }

    /// Bare, twisted trees.
    private func paintTrees(_ ctx: CGContext) {
        var rng = ScenePaint.generator(25)
        func branch(_ p: CGPoint, _ angle: Double, _ length: Double, _ width: Double, _ depth: Int, _ rng: inout SceneRandom, _ color: CGColor, _ rim: CGColor, _ offset: Double) {
            guard depth > 0, length > 6 else { return }
            let end = CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length)
            let mid = CGPoint(x: (p.x + end.x) / 2 + rng.range(-length * 0.15, length * 0.15), y: (p.y + end.y) / 2 + rng.range(-length * 0.1, length * 0.1))
            for (c, o) in [(rim, offset), (color, 0.0)] {
                ctx.setStrokeColor(c)
                ctx.setLineWidth(CGFloat(max(1.2, width)))
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: p.x + o, y: p.y + o))
                ctx.addQuadCurve(to: CGPoint(x: end.x + o, y: end.y + o), control: CGPoint(x: mid.x + o, y: mid.y + o))
                ctx.strokePath()
            }
            let kids = rng.chance(0.35) ? 3 : 2
            for k in 0..<kids {
                let spread = (Double(k) / Double(max(1, kids - 1)) - 0.5) * 1.5 + rng.range(-0.25, 0.25)
                branch(end, angle + spread, length * rng.range(0.66, 0.82), width * 0.68, depth - 1, &rng, color, rim, offset)
            }
        }
        let dark = ScenePaint.color(0x06040E), rim = ScenePaint.color(0x7A8AD0, 0.55)
        // A big dead tree on the left, a smaller one on the right, and some far off.
        branch(CGPoint(x: 120, y: 120), .pi / 2 + 0.08, 190, 26, 8, &rng, dark, rim, 2.4)
        branch(CGPoint(x: 90, y: 150), .pi / 2 + 0.7, 140, 14, 7, &rng, dark, rim, 2.0)
        branch(CGPoint(x: 1240, y: 110), .pi / 2 - 0.05, 130, 20, 7, &rng, dark, rim, 2.0)
        for i in 0..<7 {
            let x = 420 + Double(i) * 66 + rng.range(-20, 20)
            if x > 770 { continue }
            branch(CGPoint(x: x, y: Self.horizon + 6), .pi / 2 + rng.range(-0.3, 0.3), 36, 3.5, 5, &rng, ScenePaint.color(0x0E1230), ScenePaint.color(0x6A7AC0, 0.3), 1)
        }
    }

    private func paintVignette(_ ctx: CGContext) {
        let g = ScenePaint.gradient([(0, ScenePaint.color(0x000008, 0)), (0.55, ScenePaint.color(0x000008, 0)), (1, ScenePaint.color(0x000008, 0.6))])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 380), startRadius: 0, endCenter: CGPoint(x: 640, y: 380), endRadius: 800, options: [.drawsAfterEndLocation])
    }

    // MARK: Things that move

    private func paintClouds() -> [(layer: SceneLayer, speed: Double, offset: Double)] {
        var out: [(layer: SceneLayer, speed: Double, offset: Double)] = []
        var rng = ScenePaint.generator(33)
        let specs: [(y: Double, w: Double, h: Double, speed: Double)] = [(520, 520, 60, 6), (580, 640, 70, 4), (470, 420, 50, 8), (640, 480, 54, 3)]
        for spec in specs {
            let rect = CGRect(x: 0, y: spec.y, width: spec.w, height: spec.h)
            if let layer = ScenePaint.layer(rect, { ctx in
                for _ in 0..<18 {
                    let c = CGPoint(x: rng.range(spec.w * 0.3, spec.w * 0.7), y: spec.y + spec.h * rng.range(0.4, 0.6))
                    let rx = rng.range(spec.w * 0.08, spec.w * 0.2), ry = rng.range(spec.h * 0.12, spec.h * 0.26)
                    ScenePaint.blob(ctx, c, rx: rx, ry: ry, ScenePaint.color(0x0C1030, 0.65), inner: 0.2)
                    ScenePaint.blob(ctx, CGPoint(x: c.x - rx * 0.1, y: c.y + ry * 0.4), rx: rx * 0.8, ry: ry * 0.4, ScenePaint.color(0x8898D0, 0.35), inner: 0.1)
                }
            }) { out.append((layer.faded(0.9), spec.speed, rng.range(0, 1280))) }
        }
        return out
    }

    private func paintFog() -> [(layer: SceneLayer, speed: Double, offset: Double, alpha: Double)] {
        var out: [(layer: SceneLayer, speed: Double, offset: Double, alpha: Double)] = []
        var rng = ScenePaint.generator(44)
        let specs: [(y: Double, speed: Double, alpha: Double)] = [(250, 9, 0.5), (190, -7, 0.4), (120, 12, 0.38), (60, -9, 0.32)]
        for spec in specs {
            let rect = CGRect(x: 0, y: spec.y - 50, width: 900, height: 100)
            if let layer = ScenePaint.layer(rect, { ctx in
                for _ in 0..<7 {
                    ScenePaint.blob(ctx, CGPoint(x: rng.range(260, 640), y: spec.y + rng.range(-12, 12)), rx: rng.range(130, 250), ry: rng.range(16, 34), ScenePaint.color(0xB8C8F0, 0.5), inner: 0.1)
                }
            }) { out.append((layer.faded(spec.alpha), spec.speed, rng.range(0, 1200), spec.alpha)) }
        }
        return out
    }

    /// A cobweb for a corner of the picture.
    private func paintWeb() -> CGImage? {
        ScenePaint.picture(width: 330, height: 330) { ctx in
            ctx.setStrokeColor(CGColor(gray: 0.9, alpha: 0.38))
            ctx.setLineWidth(1.4)
            ctx.setLineCap(.round)
            let corner = CGPoint(x: 0, y: 330)
            for i in 0..<7 {
                let a = -.pi / 2 * (Double(i) / 6) * 0.98 - 0.01
                ctx.move(to: corner)
                ctx.addLine(to: CGPoint(x: cos(a) * 320, y: 330 + sin(a) * 320))
                ctx.strokePath()
            }
            for ring in 1..<7 {
                let r = Double(ring) * 46
                ctx.move(to: CGPoint(x: r, y: 330))
                for i in 1...6 {
                    let a = -.pi / 2 * Double(i) / 6
                    let mid = -.pi / 2 * (Double(i) - 0.5) / 6
                    let sag = r * 0.88
                    ctx.addQuadCurve(to: CGPoint(x: cos(a) * r, y: 330 + sin(a) * r), control: CGPoint(x: cos(mid) * sag, y: 330 + sin(mid) * sag))
                }
                ctx.strokePath()
            }
        }
    }

    // MARK: The animals

    private lazy var puppets: [String: ScenePuppet] = ["ghost": SceneGhost(), "bat": SceneMembrane(.bat), "spider": SceneSpider(), "pumpkin": ScenePumpkin()]

    func puppet(for index: Int) -> ScenePuppet? { puppets[cast.species[index].name] }

    // MARK: Painting each frame

    func paintBackdrop(_ ctx: CGContext, frame: SceneFrame) {
        ctx.interpolationQuality = .low
        world?.draw(in: ctx, shift: frame.shift)
        for cloud in clouds {
            let width = Double(cloud.layer.image.width)
            let travel = 1280 + width
            var x = (cloud.offset - frame.time * cloud.speed).truncatingRemainder(dividingBy: travel)
            if x < 0 { x += travel }
            var moved = cloud.layer
            moved.origin.x = CGFloat(x - width)
            moved.parallax = 5
            moved.draw(in: ctx, shift: frame.shift)
        }
        drawBats(ctx, time: frame.time, shift: frame.shift)
        // The windows flicker.
        if windowGlow.count == 4 {
            for (i, p) in Self.windows.enumerated() where i % 3 != 2 {
                let flicker = 0.5 + 0.5 * sin(frame.time * (2.4 + Double(i) * 0.7) + Double(i) * 1.9) * sin(frame.time * 0.9 + Double(i))
                let level = min(3, max(0, Int(flicker * 3.99)))
                ctx.draw(windowGlow[level], in: CGRect(x: (p.x - 45 + Double(frame.shift.x) * 12).rounded(), y: p.y - 45, width: 90, height: 90))
            }
        }
        for band in fog {
            let width = Double(band.layer.image.width)
            let travel = 1280 + width
            var x = (band.offset + frame.time * band.speed).truncatingRemainder(dividingBy: travel)
            if x < 0 { x += travel }
            var moved = band.layer
            moved.origin.x = CGFloat(x - width)
            moved.parallax = 20
            moved.draw(in: ctx, shift: frame.shift)
        }
        ctx.interpolationQuality = .high
    }

    /// Little bats against the moon.
    private func drawBats(_ ctx: CGContext, time: Double, shift: CGPoint) {
        ctx.setFillColor(ScenePaint.color(0x05030C))
        let moon = Self.moon
        for i in 0..<7 {
            let f = Double(i)
            let a = time * (0.35 + 0.08 * f) + f * 1.3
            let x = moon.x + cos(a) * (150 + f * 30) + sin(time * 0.5 + f) * 40 + Double(shift.x) * 5
            let y = moon.y + sin(a * 1.3) * (70 + f * 12)
            let flap = sin(time * 11 + f * 2) * 0.7
            let span = 9.0 + Double(i % 3) * 2
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - span, y: y + flap * span * 0.7))
            path.addQuadCurve(to: CGPoint(x: x - span * 0.2, y: y - span * 0.15), control: CGPoint(x: x - span * 0.6, y: y + span * 0.5 + flap * span * 0.3))
            path.addLine(to: CGPoint(x: x, y: y + span * 0.25))
            path.addLine(to: CGPoint(x: x + span * 0.2, y: y - span * 0.15))
            path.addQuadCurve(to: CGPoint(x: x + span, y: y + flap * span * 0.7), control: CGPoint(x: x + span * 0.6, y: y + span * 0.5 + flap * span * 0.3))
            path.addQuadCurve(to: CGPoint(x: x, y: y - span * 0.35), control: CGPoint(x: x + span * 0.4, y: y - span * 0.1))
            path.closeSubpath()
            ctx.addPath(path)
        }
        ctx.fillPath()
    }

    func paintForeground(_ ctx: CGContext, frame: SceneFrame) {
        // Cobwebs in the top corners.
        if let web {
            ctx.draw(web, in: CGRect(x: 0, y: 720 - 230, width: 230, height: 230))
            ctx.saveGState()
            ctx.translateBy(x: 1280, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ctx.draw(web, in: CGRect(x: 0, y: 720 - 230, width: 230, height: 230))
            ctx.restoreGState()
        }
        // Wisps drifting through the graveyard.
        if let glow = Sprites.dot(red: 0.6, green: 1, blue: 0.85) {
            let t = frame.time
            for i in 0..<14 {
                let f = Double(i)
                let x = 60 + (f * 233.1).truncatingRemainder(dividingBy: 1160) + sin(t * 0.35 + f * 1.7) * 60
                let y = 70 + (f * 89.3).truncatingRemainder(dividingBy: 420) + cos(t * 0.45 + f) * 30
                let pulse = 0.5 + 0.5 * sin(t * (0.9 + Double(i % 4) * 0.3) + f * 2)
                ctx.stampDot(glow, at: CGPoint(x: x + Double(frame.shift.x) * 20, y: y), radius: 3 + 5 * pulse, alpha: 0.15 + 0.5 * pulse)
            }
        }
    }
}
