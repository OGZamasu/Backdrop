import AppKit
import CoreGraphics
import Foundation

/// Who lives on the reef.
enum DeepSeaCast {
    static var cast: SceneCast {
        var layout = SceneLayout()
        layout.roamLow = 150
        layout.roamHigh = 640
        layout.farGround = 150
        layout.nearGround = 90

        var blueFish = SceneSpecies(name: "blue fish", glyph: "", facesRight: true, height: 40, aspect: 1.29, speed: 110, body: .swimmer, temper: .curious, act: .orbit,
                                    home: 0.2, charge: 1.4, group: 10, actSeconds: 6)
        blueFish.band = 200...600
        var tropical = SceneSpecies(name: "tropical fish", glyph: "", facesRight: true, height: 48, aspect: 1.13, speed: 95, body: .swimmer, temper: .curious, act: .orbit,
                                    home: 0.7, charge: 1.4, group: 8, actSeconds: 6)
        tropical.band = 180...560
        var minnows = SceneSpecies(name: "minnows", glyph: "", facesRight: true, height: 30, aspect: 1.29, speed: 125, body: .swimmer, temper: .curious, act: .orbit,
                                   home: 0.28, charge: 1.5, group: 14, actSeconds: 6)
        minnows.band = 260...640
        var shark = SceneSpecies(name: "shark", glyph: "", facesRight: true, height: 120, aspect: 2.5, speed: 120, body: .swimmer, temper: .brute, act: .lunge,
                                 home: 0.25, charge: 1.6, actSeconds: 5.5)
        shark.band = 240...560
        shark.shout = "CHOMP!"
        var turtle = SceneSpecies(name: "turtle", glyph: "", facesRight: true, height: 130, aspect: 1.19, speed: 52, body: .swimmer, temper: .prey, act: .lean,
                                  home: 0.65, charge: 1.6, actSeconds: 3.2, shout: "👋")
        turtle.band = 200...520
        var jelly = SceneSpecies(name: "jellyfish", glyph: "", facesRight: true, height: 120, aspect: 0.78, speed: 40, body: .floater, temper: .curious, act: .boo,
                                 home: 0.35, charge: 1.6, actSeconds: 3.0, shout: "✨")
        jelly.band = 280...640
        var octopus = SceneSpecies(name: "octopus", glyph: "", facesRight: true, height: 150, aspect: 1.08, speed: 60, body: .swimmer, temper: .prey, act: .lean,
                                   home: 0.75, charge: 1.8, actSeconds: 3.0, shout: "👋")
        octopus.band = 100...190
        var puffer = SceneSpecies(name: "pufferfish", glyph: "", facesRight: true, height: 76, aspect: 1.11, speed: 70, body: .swimmer, temper: .prey, act: .boo,
                                  home: 0.55, charge: 1.6, actSeconds: 2.6, shout: "PUFF!")
        puffer.band = 220...480
        var dolphin = SceneSpecies(name: "dolphin", glyph: "", facesRight: true, height: 84, aspect: 2.6, speed: 160, body: .swimmer, temper: .prey, act: .orbit,
                                   home: 0.3, charge: 1.5, interest: 1.2, actSeconds: 5, shout: "♪")
        dolphin.band = 380...640

        var species = [blueFish, tropical, minnows, shark, turtle, jelly, octopus, puffer, dolphin]
        for i in species.indices { species[i].painted = true }
        return SceneCast(species: species, roster: [0, 1, 2, 3, 4, 5, 5, 6, 7, 8], layout: layout, cap: 10, visibleAtStart: 7, underwater: true)
    }
}

/// A coral reef under a bright surface: caustic light on the sand, kelp swaying, bubbles rising, and sea creatures that come to see you.
final class DeepSeaScene: SceneStyle {
    let cast = DeepSeaCast.cast
    let look = SceneLook(haze: 0x2A9AC8, hazeAmount: 0.18, dusk: 0x0A3A70, duskAmount: 0.26, warm: 0xBFF4FF, warmAmount: 0.10, shade: 0.18,
                         dust: 0xDDF2FF, shadow: 0, shadowLean: 0, water: 0xE8FFFF)
    let hint = "Wave your arms to scatter the fish!"

    private var world: SceneLayer?
    private var canvas: SceneCanvas?
    private var caustics: [CGImage] = []
    private var frontKelp: [(frames: [CGImage], x: Double, parallax: Double, phase: Double)] = []
    private static let swayFrames = 9

    private lazy var bakery = SceneBakery([
        { [unowned self] in canvas = SceneCanvas(CGRect(x: -48, y: 0, width: 1376, height: 720)); canvas?.paint { paintWater($0) } },
        { [unowned self] in canvas?.paint { paintFarReef($0); paintSand($0) } },
        { [unowned self] in canvas?.paint { paintReef($0) } },
        { [unowned self] in canvas?.paint { paintStaticKelp($0); paintVignette($0) }; world = canvas?.finish(parallax: 12); canvas = nil },
        { [unowned self] in if let tile = paintCaustics(seed: 1, strength: 0.42) { caustics.append(tile) } },
        { [unowned self] in if let tile = paintCaustics(seed: 2, strength: 0.3) { caustics.append(tile) } },
        { [unowned self] in paintFront(0..<3) },
        { [unowned self] in paintFront(3..<6) },
    ])

    func prepare(until deadline: Double) -> Bool { bakery.run(until: deadline) }

    // MARK: The reef

    private func paintWater(_ ctx: CGContext) {
        let rect = CGRect(x: -48, y: 0, width: 1376, height: 720)
        ScenePaint.fillDown(ctx, rect, [(0, ScenePaint.color(0x38C8DA)), (0.3, ScenePaint.color(0x1F9ACB)), (0.65, ScenePaint.color(0x0F6AA4)), (1, ScenePaint.color(0x063A66))])
        ScenePaint.blob(ctx, CGPoint(x: 300, y: 790), rx: 800, ry: 520, ScenePaint.color(0xA6F6F2, 0.7), inner: 0.05)
        ScenePaint.blob(ctx, CGPoint(x: 940, y: 330), rx: 560, ry: 220, ScenePaint.color(0x0A4F86, 0.35))
        // Shafts of light from the surface, slanting down and to the right from the bright water up on the left: soft at the edges,
        // all of them in one clip for each of two widths.
        var rng = ScenePaint.generator(11)
        let shafts = (0..<8).map { i in (x: -100 + Double(i) * 190 + rng.range(-40, 40), slant: rng.range(160, 330), wide: rng.range(70, 150), narrow: rng.range(30, 70)) }
        for (pass, strength) in [(0, 0.5), (1, 0.5)] {
            let path = CGMutablePath()
            for shaft in shafts {
                let width = pass == 0 ? shaft.wide : shaft.narrow
                path.move(to: CGPoint(x: shaft.x - width * 0.3, y: 740))
                path.addLine(to: CGPoint(x: shaft.x + width, y: 740))
                path.addLine(to: CGPoint(x: shaft.x + width * 2.2 + shaft.slant, y: 60))
                path.addLine(to: CGPoint(x: shaft.x - width * 0.4 + shaft.slant, y: 60))
                path.closeSubpath()
            }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(ScenePaint.gradient([(0, ScenePaint.color(0xE8FFFF, 0.26 * strength)), (0.7, ScenePaint.color(0xC0F4FF, 0.08 * strength)), (1, ScenePaint.color(0xC0F4FF, 0))]),
                                   start: CGPoint(x: 0, y: 740), end: CGPoint(x: 0, y: 60), options: [])
            ctx.restoreGState()
        }
    }

    /// Rocks and old corals far back, lost in the blue.
    private func paintFarReef(_ ctx: CGContext) {
        var rng = ScenePaint.generator(22)
        let haze = ScenePaint.color(0x1B78A8)
        for i in 0..<9 {
            let x = -40 + Double(i) * 160 + rng.range(-40, 40)
            let h = rng.range(80, 200)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - 90, y: 150))
            path.addCurve(to: CGPoint(x: x + 10, y: 150 + h), control1: CGPoint(x: x - 70, y: 150 + h * 0.8), control2: CGPoint(x: x - 30, y: 150 + h * 1.1))
            path.addCurve(to: CGPoint(x: x + 100, y: 150), control1: CGPoint(x: x + 60, y: 150 + h * 0.9), control2: CGPoint(x: x + 90, y: 150 + h * 0.4))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(haze)
            ctx.fillPath()
        }
        ScenePaint.fill(ctx, CGRect(x: -48, y: 120, width: 1376, height: 220), [(0, ScenePaint.color(0x2AA6D0, 0)), (0.5, ScenePaint.color(0x2AA6D0, 0.55)), (1, ScenePaint.color(0x2AA6D0, 0.9))],
                        from: CGPoint(x: 0, y: 340), to: CGPoint(x: 0, y: 140))
        // Far kelp: dark ribbons.
        for _ in 0..<8 {
            kelp(ctx, x: rng.range(-20, 1300), baseY: 140, height: rng.range(180, 380), width: 14, color: ScenePaint.color(0x1A7A8A, 0.7), phase: rng.range(0, 6), sway: 22)
        }
    }

    private func paintSand(_ ctx: CGContext) {
        let rect = CGRect(x: -48, y: 0, width: 1376, height: 190)
        ScenePaint.fillDown(ctx, rect, [(0, ScenePaint.color(0x5EC0C8)), (0.18, ScenePaint.color(0xB7D9B4)), (0.5, ScenePaint.color(0xDCCB92)), (1, ScenePaint.color(0xA8905A))])
        var rng = ScenePaint.generator(33)
        // Ripples in the sand: long soft ridges.
        for i in 0..<26 {
            let t = Double(i) / 26
            let y = 170 - pow(t, 1.3) * 170
            let s = 0.4 + 1.0 * t
            ctx.setStrokeColor(ScenePaint.color(i % 2 == 0 ? 0xFFF3C8 : 0x7C6A40, 0.28))
            ctx.setLineWidth(CGFloat(1.5 * s))
            ctx.move(to: CGPoint(x: -60, y: y))
            var x = -60.0
            while x < 1340 {
                x += 40
                ctx.addLine(to: CGPoint(x: x, y: y + sin(x * 0.02 + Double(i) * 1.3) * 5 * s))
            }
            ctx.strokePath()
        }
        // Pebbles and shells.
        for _ in 0..<80 {
            let t = rng.unit()
            let y = 175 - pow(t, 1.2) * 175, s = 0.4 + 1.0 * t
            ScenePaint.oval(ctx, CGPoint(x: rng.range(-40, 1320), y: y), rx: rng.range(3, 8) * s, ry: rng.range(2, 5) * s, ScenePaint.mix(0x8C7A58, 0xE8DCB8, rng.unit(), alpha: 0.8))
        }
    }

    private func paintReef(_ ctx: CGContext) {
        var rng = ScenePaint.generator(44)
        let palette: [UInt32] = [0xFF7A4A, 0xFF5E94, 0xA058D8, 0xF2C84A, 0xFF9A5A, 0x5ED0A8]
        // Clusters piled up at both sides, leaving the middle clear for you.
        for side in [0.0, 1.0] {
            for i in 0..<9 {
                let x = side < 1 ? rng.range(-60, 360) : rng.range(920, 1340)
                let y = rng.range(40, 150)
                let s = rng.range(0.7, 1.6) * (0.6 + 0.4 * (1 - y / 150))
                let pick = palette[Int(rng.unit() * Double(palette.count))]
                switch i % 4 {
                case 0: branchCoral(ctx, base: CGPoint(x: x, y: y), length: 70 * s, color: pick, rng: &rng)
                case 1: brainCoral(ctx, center: CGPoint(x: x, y: y + 12 * s), radius: 36 * s, color: pick, rng: &rng)
                case 2: seaFan(ctx, base: CGPoint(x: x, y: y), size: 80 * s, color: pick, rng: &rng)
                default: tubeSponge(ctx, base: CGPoint(x: x, y: y), height: 66 * s, color: pick, rng: &rng)
                }
            }
        }
        // A few small ones towards the middle, at the back.
        for _ in 0..<6 {
            let x = rng.range(380, 900), y = rng.range(130, 170)
            branchCoral(ctx, base: CGPoint(x: x, y: y), length: 34, color: palette[Int(rng.unit() * Double(palette.count))], rng: &rng)
        }
    }

    private func branchCoral(_ ctx: CGContext, base: CGPoint, length: Double, color: UInt32, rng: inout SceneRandom) {
        func branch(_ p: CGPoint, _ angle: Double, _ len: Double, _ depth: Int, _ rng: inout SceneRandom) {
            guard depth > 0, len > 4 else { return }
            let end = CGPoint(x: p.x + cos(angle) * len, y: p.y + sin(angle) * len)
            ctx.setStrokeColor(ScenePaint.mix(color, 0xFFFFFF, Double(3 - depth) * 0.08 + 0.05))
            ctx.setLineWidth(CGFloat(Double(depth) * length * 0.045 + 1.2))
            ctx.setLineCap(.round)
            ctx.move(to: p)
            ctx.addLine(to: end)
            ctx.strokePath()
            if depth == 1 {
                ScenePaint.oval(ctx, end, rx: len * 0.22, ry: len * 0.22, ScenePaint.mix(color, 0xFFFFFF, 0.5))
            }
            let kids = depth > 2 ? 3 : 2
            for k in 0..<kids {
                let spread = (Double(k) / Double(max(1, kids - 1)) - 0.5) * 1.1
                branch(end, angle + spread + rng.range(-0.15, 0.15), len * rng.range(0.62, 0.78), depth - 1, &rng)
            }
        }
        // A shadowed underlay, then the lit coral.
        ScenePaint.oval(ctx, CGPoint(x: base.x, y: base.y - 2), rx: length * 0.35, ry: length * 0.08, ScenePaint.color(0x06324A, 0.4))
        for k in 0..<3 { branch(base, .pi / 2 + (Double(k) - 1) * 0.5, length * 0.5, 4, &rng) }
    }

    private func brainCoral(_ ctx: CGContext, center: CGPoint, radius: Double, color: UInt32, rng: inout SceneRandom) {
        ScenePaint.oval(ctx, CGPoint(x: center.x, y: center.y - radius * 0.7), rx: radius * 1.2, ry: radius * 0.22, ScenePaint.color(0x06324A, 0.4))
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius * 0.6, width: radius * 2, height: radius * 1.4))
        ctx.clip()
        ScenePaint.fillDown(ctx, CGRect(x: center.x - radius, y: center.y - radius * 0.6, width: radius * 2, height: radius * 1.4),
                            [(0, ScenePaint.mix(color, 0xFFFFFF, 0.35)), (1, ScenePaint.mix(color, 0x203060, 0.35))])
        ctx.setStrokeColor(ScenePaint.mix(color, 0x000000, 0.35, alpha: 0.7))
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        for _ in 0..<16 {
            let p = CGPoint(x: center.x + rng.range(-radius, radius), y: center.y + rng.range(-radius * 0.5, radius * 0.7))
            ctx.move(to: p)
            ctx.addCurve(to: CGPoint(x: p.x + rng.range(-20, 20), y: p.y + rng.range(-8, 8)), control1: CGPoint(x: p.x + 12, y: p.y + 10), control2: CGPoint(x: p.x - 10, y: p.y - 10))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private func seaFan(_ ctx: CGContext, base: CGPoint, size: Double, color: UInt32, rng: inout SceneRandom) {
        ctx.setLineCap(.round)
        for i in 0..<15 {
            let angle = .pi / 2 + (Double(i) / 14 - 0.5) * 2.1
            ctx.setStrokeColor(ScenePaint.mix(color, 0xFFFFFF, 0.1, alpha: 0.9))
            ctx.setLineWidth(max(1.2, size * 0.025))
            ctx.move(to: base)
            ctx.addQuadCurve(to: CGPoint(x: base.x + cos(angle) * size, y: base.y + sin(angle) * size), control: CGPoint(x: base.x + cos(angle) * size * 0.5 + rng.range(-8, 8), y: base.y + sin(angle) * size * 0.5))
            ctx.strokePath()
        }
        ctx.setStrokeColor(ScenePaint.mix(color, 0xFFFFFF, 0.3, alpha: 0.6))
        ctx.setLineWidth(1.2)
        for ring in 1..<4 {
            let r = size * Double(ring) / 4
            ctx.addArc(center: base, radius: r, startAngle: .pi / 2 - 1.05, endAngle: .pi / 2 + 1.05, clockwise: false)
            ctx.strokePath()
        }
        ctx.setStrokeColor(ScenePaint.color(0x4A2A20))
        ctx.setLineWidth(size * 0.05)
        ctx.move(to: base); ctx.addLine(to: CGPoint(x: base.x, y: base.y - size * 0.1)); ctx.strokePath()
    }

    private func tubeSponge(_ ctx: CGContext, base: CGPoint, height: Double, color: UInt32, rng: inout SceneRandom) {
        for i in 0..<3 {
            let x = base.x + Double(i - 1) * height * 0.22, h = height * (0.7 + 0.3 * rng.unit()), w = height * 0.16
            let rect = CGRect(x: x - w, y: base.y, width: w * 2, height: h)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: w, cornerHeight: w * 0.6, transform: nil))
            ctx.clip()
            ScenePaint.fill(ctx, rect, [(0, ScenePaint.mix(color, 0xFFFFFF, 0.35)), (1, ScenePaint.mix(color, 0x203060, 0.3))], from: CGPoint(x: rect.minX, y: 0), to: CGPoint(x: rect.maxX, y: 0))
            ctx.restoreGState()
            ScenePaint.oval(ctx, CGPoint(x: x, y: base.y + h - 2), rx: w * 0.8, ry: w * 0.3, ScenePaint.mix(color, 0x203060, 0.6))
        }
    }

    /// A ribbon of kelp, swaying to one side, thick at the root.
    private func kelp(_ ctx: CGContext, x: Double, baseY: Double, height: Double, width: Double, color: CGColor, phase: Double, sway: Double) {
        let steps = 24
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let cx = x + sin(t * 4.2 + phase) * sway * t
            let y = baseY + t * height
            let w = width * (1 - 0.65 * t)
            left.append(CGPoint(x: cx - w / 2, y: y)); right.append(CGPoint(x: cx + w / 2, y: y))
        }
        let path = CGMutablePath()
        path.move(to: left[0])
        for p in left { path.addLine(to: p) }
        for p in right.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func paintStaticKelp(_ ctx: CGContext) {
        var rng = ScenePaint.generator(55)
        for i in 0..<6 {
            let x = i < 3 ? rng.range(-30, 330) : rng.range(950, 1330)
            let h = rng.range(240, 480)
            kelp(ctx, x: x, baseY: 40, height: h, width: rng.range(16, 26), color: ScenePaint.mix(0x1E8A6A, 0x4CA880, rng.unit(), alpha: 0.85), phase: rng.range(0, 6), sway: rng.range(18, 40))
        }
    }

    private func paintVignette(_ ctx: CGContext) {
        let g = ScenePaint.gradient([(0, ScenePaint.color(0x021A38, 0)), (0.55, ScenePaint.color(0x021A38, 0)), (1, ScenePaint.color(0x021A38, 0.5))])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 400), startRadius: 0, endCenter: CGPoint(x: 640, y: 400), endRadius: 820, options: [.drawsAfterEndLocation])
    }

    // MARK: Things that move

    /// A tile of the bright web that sunlight makes on the sand, which repeats without a seam.
    private func paintCaustics(seed: UInt64, strength: Double) -> CGImage? {
        let side = 256
        var rng = ScenePaint.generator(seed * 77)
        let points = (0..<46).map { _ in CGPoint(x: rng.range(0, Double(side)), y: rng.range(0, Double(side))) }
        // Each point joins its two nearest neighbours with a gentle curve.
        let web = CGMutablePath()
        for p in points {
            let near = points.filter { $0 != p }.sorted { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }.prefix(2)
            for q in near {
                let mid = CGPoint(x: (p.x + q.x) / 2 + (q.y - p.y) * 0.12, y: (p.y + q.y) / 2 - (q.x - p.x) * 0.12)
                web.move(to: p)
                web.addQuadCurve(to: q, control: mid)
            }
        }
        return ScenePaint.picture(width: side, height: side) { ctx in
            ctx.setLineCap(.round)
            for pass in 0..<2 {
                ctx.setStrokeColor(CGColor(gray: 1, alpha: (pass == 0 ? 0.10 : 0.5) * strength * 2))
                ctx.setLineWidth(pass == 0 ? 5 : 1.5)
                for dx in [-side, 0, side] {
                    for dy in [-side, 0, side] {
                        ctx.saveGState()
                        ctx.translateBy(x: CGFloat(dx), y: CGFloat(dy))
                        ctx.addPath(web)
                        ctx.strokePath()
                        ctx.restoreGState()
                    }
                }
            }
        }
    }

    /// Kelp in front, painted bent to several points of its sway (a shear above the root), so that the sway is a copy.
    private func paintFront(_ range: Range<Int>) {
        let specs: [(x: Double, height: Double, parallax: Double)] = [(40, 460, 70), (120, 300, 60), (200, 190, 50), (1070, 210, 54), (1160, 330, 64), (1245, 480, 74)]
        for index in range where index < specs.count {
            let spec = specs[index]
            let w = 210, h = Int(spec.height) + 30
            let frames = (0..<Self.swayFrames).compactMap { i -> CGImage? in
                let bend = (Double(i) / Double(Self.swayFrames - 1) - 0.5) * 0.22
                return ScenePaint.picture(width: w, height: h) { ctx in
                    ctx.translateBy(x: CGFloat(w / 2), y: 0)
                    ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: CGFloat(bend), d: 1, tx: 0, ty: 0))
                    ctx.translateBy(x: -75, y: 0)
                    var rng = ScenePaint.generator(UInt64(88 + index * 13))
                    kelp(ctx, x: 75, baseY: 0, height: spec.height, width: 26, color: ScenePaint.color(0x0F5A34), phase: rng.range(0, 6), sway: 14)
                    kelp(ctx, x: 90, baseY: 0, height: spec.height * 0.8, width: 20, color: ScenePaint.color(0x1F8A4A), phase: rng.range(0, 6), sway: 12)
                    for k in 0..<9 {
                        let y = spec.height * Double(k + 1) / 10
                        ScenePaint.leaf(ctx, from: CGPoint(x: 75 + sin(y * 0.02) * 8, y: y), angle: rng.chance(0.5) ? 0.6 : 2.5, length: rng.range(34, 60), width: 9, bend: 0.1,
                                        color: ScenePaint.mix(0x1A7A44, 0x7CC050, rng.unit(), alpha: 0.95))
                    }
                }
            }
            if frames.count == Self.swayFrames { frontKelp.append((frames, spec.x, spec.parallax, Double(index) * 1.3)) }
        }
    }

    // MARK: The animals

    private lazy var puppets: [String: ScenePuppet] = [
        "blue fish": SceneFish(.chromis), "tropical fish": SceneFish(.clown), "minnows": SceneFish(.minnow), "shark": SceneFish(.shark),
        "turtle": SceneTurtle(), "jellyfish": SceneJelly(), "octopus": SceneOctopus(), "pufferfish": ScenePuffer(), "dolphin": SceneFish(.dolphin),
    ]

    func puppet(for index: Int) -> ScenePuppet? { puppets[cast.species[index].name] }

    // MARK: Painting each frame

    func paintBackdrop(_ ctx: CGContext, frame: SceneFrame) {
        ctx.interpolationQuality = .low
        world?.draw(in: ctx, shift: frame.shift)
        // The light shimmering on the sand: a web of bright lines sliding over the floor, twice over in opposite directions so that
        // it never repeats in step. One row of tiles covers the floor; each layer only slides sideways and bobs a little.
        if caustics.count == 2 {
            let t = frame.time
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: 1280, height: 190))
            for (k, image) in caustics.enumerated() {
                let direction = k == 0 ? 1.0 : -1.0
                var ox = Int((t * 14 * direction).truncatingRemainder(dividingBy: 256))
                if ox < 0 { ox += 256 }
                let y = (k == 0 ? -40 + 10 * sin(t * 0.3) : -52 + 10 * cos(t * 0.23)).rounded()
                var x = ox - 256
                while x < 1280 {
                    ctx.draw(image, in: CGRect(x: Double(x), y: y, width: 256, height: 256))
                    x += 256
                }
            }
            ctx.restoreGState()
        }
        drawDistantShoal(ctx, time: frame.time, shift: frame.shift)
        // A fine snow of specks drifting down through the water.
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.5))
        for i in 0..<40 {
            let f = Double(i)
            let x = (f * 131.7 + sin(frame.time * 0.3 + f) * 20).truncatingRemainder(dividingBy: 1280)
            let y = 720 - (frame.time * (8 + Double(i % 5) * 3) + f * 83).truncatingRemainder(dividingBy: 700)
            ctx.fill(CGRect(x: x + Double(frame.shift.x) * 16, y: y, width: 1.6, height: 1.6))
        }
        ctx.interpolationQuality = .high
    }

    /// A shoal so far off that it is a cloud of tiny dark darts, wheeling slowly in the blue.
    private func drawDistantShoal(_ ctx: CGContext, time: Double, shift: CGPoint) {
        let centre = CGPoint(x: 880 + sin(time * 0.05) * 260 + Double(shift.x) * 6, y: 440 + sin(time * 0.11) * 40)
        let heading = cos(time * 0.05) >= 0 ? 1.0 : -1.0
        ctx.setFillColor(ScenePaint.color(0x0E4E7E, 0.55))
        for i in 0..<26 {
            let f = Double(i)
            let x = Double(centre.x) + cos(f * 2.4 + time * 0.3) * (30 + (f * 7).truncatingRemainder(dividingBy: 40))
            let y = Double(centre.y) + sin(f * 1.7 + time * 0.25) * (14 + (f * 5).truncatingRemainder(dividingBy: 18))
            let path = CGMutablePath()
            path.addLines(between: [CGPoint(x: x + 4 * heading, y: y), CGPoint(x: x - 3 * heading, y: y + 1.6), CGPoint(x: x - 3 * heading, y: y - 1.6)])
            path.closeSubpath()
            ctx.addPath(path)
        }
        ctx.fillPath()
    }

    func paintForeground(_ ctx: CGContext, frame: SceneFrame) {
        let t = frame.time
        for strand in frontKelp {
            let s = 0.5 + 0.5 * (0.7 * sin(t * 0.8 + strand.phase) + 0.3 * sin(t * 1.9 + strand.phase * 2))
            let image = strand.frames[min(Self.swayFrames - 1, max(0, Int((s * Double(Self.swayFrames - 1)).rounded())))]
            let x = (strand.x + Double(frame.shift.x) * strand.parallax - Double(image.width) / 2).rounded()
            ctx.draw(image, in: CGRect(x: x, y: -26, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        // Bubbles rising from the sand, wobbling as they go: all the rims in one stroke, all the glints in one fill.
        let rims = CGMutablePath(), glints = CGMutablePath()
        for i in 0..<26 {
            let f = Double(i)
            let speed = 40 + Double(i % 6) * 14
            let y = -20 + (t * speed + f * 97).truncatingRemainder(dividingBy: 800)
            let x = 60 + (f * 177.3).truncatingRemainder(dividingBy: 1160) + sin(t * 1.4 + f) * (10 + Double(i % 4) * 4) + Double(frame.shift.x) * 30
            let r = 2.5 + Double(i % 5) * 1.6
            rims.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            glints.addEllipse(in: CGRect(x: x - r * 0.55, y: y + r * 0.1, width: r * 0.5, height: r * 0.5))
        }
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.6))
        ctx.setLineWidth(1.3)
        ctx.addPath(rims)
        ctx.strokePath()
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.45))
        ctx.addPath(glints)
        ctx.fillPath()
    }
}
