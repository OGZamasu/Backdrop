import AppKit
import CoreGraphics
import Foundation

/// Who lives on the savanna.
enum SafariCast {
    static var cast: SceneCast {
        var layout = SceneLayout()
        layout.farGround = 262
        layout.nearGround = 86
        layout.roamLow = 470
        layout.roamHigh = 650

        let lion = SceneSpecies(name: "lion", glyph: "", facesRight: true, height: 222, aspect: 1.62, speed: 118, temper: .brute, act: .roar,
                                home: 0.22, charge: 1.25, stalks: true, actSeconds: 2.6, painted: true)
        let elephant = SceneSpecies(name: "elephant", glyph: "", facesRight: true, height: 268, aspect: 1.19, speed: 64, temper: .brute, act: .trumpet,
                                    home: 0.2, charge: 1.9, actSeconds: 2.8, painted: true)
        let giraffe = SceneSpecies(name: "giraffe", glyph: "", facesRight: true, height: 400, aspect: 0.89, speed: 62, temper: .prey, act: .lean,
                                   home: 0.3, farOnly: true, charge: 1.8, actSeconds: 3.2, painted: true, shout: "💛")
        let zebra = SceneSpecies(name: "zebra", glyph: "", facesRight: true, height: 205, aspect: 1.16, speed: 100, temper: .prey, act: .hop,
                                 home: 0.2, charge: 2.0, actSeconds: 2.2, painted: true, shout: "NEIGH!")
        let rhino = SceneSpecies(name: "rhino", glyph: "", facesRight: true, height: 215, aspect: 1.30, speed: 80, temper: .brute, act: .stomp,
                                 home: 0.2, charge: 1.8, actSeconds: 2.6, painted: true)
        let cheetah = SceneSpecies(name: "cheetah", glyph: "", facesRight: true, height: 150, aspect: 1.27, speed: 170, temper: .prey, act: .lean,
                                   home: 0.2, charge: 2.6, actSeconds: 2.6, painted: true, shout: "PURR~")
        let buffalo = SceneSpecies(name: "buffalo", glyph: "", facesRight: true, height: 195, aspect: 1.15, speed: 70, temper: .brute, act: .stomp,
                                   home: 0.2, charge: 1.7, actSeconds: 2.4, painted: true, shout: "HUFF!")
        let vulture = SceneSpecies(name: "vulture", glyph: "", facesRight: true, height: 150, aspect: 1.3, speed: 55, body: .soarer, temper: .prey,
                                   act: .perch, home: 0.1, charge: 1, perchesOnHand: true, interest: 0.8, actSeconds: 6, painted: true)

        let species = [lion, elephant, giraffe, zebra, rhino, cheetah, buffalo, vulture]
        return SceneCast(species: species, roster: [0, 1, 2, 3, 3, 4, 5, 6, 7, 7, 7], layout: layout, cap: 9, visibleAtStart: 6)
    }
}

/// Golden hour on the savanna: a low sun on the left, acacias against the sky, a waterhole catching the light, a herd on the
/// horizon, and animals who come over to look at you.
final class SafariScene: SceneStyle {
    let cast = SafariCast.cast
    let look = SceneLook(haze: 0xF0A070, hazeAmount: 0.14, dusk: 0x5A2E50, duskAmount: 0.26, warm: 0xFF9A40, warmAmount: 0.16, shade: 0.30,
                         dust: 0xE9C48A, shadow: 0.42, shadowLean: 0.2, water: 0xE8F6FF)
    let hint = "Wave your arms to scare the animals away!"

    /// The sun, low and to the upper left, which is where every animal is lit from.
    private static let sun = CGPoint(x: 300, y: 420)
    private static let horizon = 346.0
    private static let pond = CGPoint(x: 330, y: 288)

    /// Sky, sun, hills, horizon and plain painted as one opaque picture: one cheap copy a frame.
    private var world: SceneLayer?
    private var canvas: SceneCanvas?
    private var clouds: [(layer: SceneLayer, speed: Double, offset: Double)] = []
    private var trees: [SceneLayer] = []
    /// Each clump of grass in front, painted bent to several points of its sway, so that swaying is a copy.
    private var grass: [[CGImage]] = []
    private static let swayFrames = 9

    private lazy var bakery = SceneBakery([
        { [unowned self] in canvas = SceneCanvas(CGRect(x: -48, y: 0, width: 1376, height: 720)); canvas?.paint { paintSky($0) } },
        { [unowned self] in canvas?.paint { paintRays($0); paintMountains($0); paintFarTrees($0) } },
        { [unowned self] in canvas?.paint { paintPlain($0) } },
        { [unowned self] in canvas?.paint { paintGrass($0, part: 0) } },
        { [unowned self] in canvas?.paint { paintGrass($0, part: 1); paintVignette($0) }; world = canvas?.finish(parallax: 14); canvas = nil },
        { [unowned self] in clouds = paintClouds() },
        { [unowned self] in trees = paintTrees() },
        { [unowned self] in grass.append(contentsOf: [0, 1].compactMap { paintGrassClump(seed: UInt64($0) + 4) }) },
        { [unowned self] in grass.append(contentsOf: [2, 3].compactMap { paintGrassClump(seed: UInt64($0) + 4) }) },
    ])

    func prepare(until deadline: Double) -> Bool { bakery.run(until: deadline) }

    // MARK: The world

    private func paintSky(_ ctx: CGContext) {
        let h = Self.horizon
        let size = CGSize(width: 1280, height: 720)
        let rect = CGRect(x: -48, y: h - 60, width: size.width + 96, height: size.height - h + 60)
        ScenePaint.fillDown(ctx, rect, [(0, ScenePaint.color(0x161C4A)), (0.22, ScenePaint.color(0x3E3578)), (0.42, ScenePaint.color(0x9A4F84)),
                                       (0.60, ScenePaint.color(0xE0707A)), (0.80, ScenePaint.color(0xFBA860)), (1, ScenePaint.color(0xFFD98C))])
        // A few early stars high up, away from the sun.
        var rng = ScenePaint.generator(11)
        for _ in 0..<40 {
            let p = CGPoint(x: rng.range(500, size.width), y: rng.range(size.height * 0.84, size.height))
            ctx.setFillColor(CGColor(gray: 1, alpha: rng.range(0.15, 0.5)))
            ctx.fillEllipse(in: CGRect(x: p.x, y: p.y, width: 1.8, height: 1.8))
        }
        let sun = Self.sun
        ScenePaint.blob(ctx, sun, rx: 760, ry: 420, ScenePaint.color(0xFFB45A, 0.55))
        ScenePaint.blob(ctx, sun, rx: 340, ry: 230, ScenePaint.color(0xFFD27A, 0.65))
        ScenePaint.blob(ctx, CGPoint(x: sun.x, y: h + 4), rx: 900, ry: 70, ScenePaint.color(0xFFE6A8, 0.75))
        ScenePaint.blob(ctx, sun, rx: 130, ry: 130, ScenePaint.color(0xFFF0C0, 0.95))
        ScenePaint.oval(ctx, sun, rx: 47, ry: 47, ScenePaint.color(0xFFF6DA))
    }

    /// Long shafts of light fanning out from the sun: all the shafts in one clip, lit by one gradient.
    private func paintRays(_ ctx: CGContext) {
        let sun = Self.sun
        var rng = ScenePaint.generator(31)
        for (width, strength) in [(1.0, 0.5), (0.5, 0.55)] {
            let path = CGMutablePath()
            for i in 0..<10 {
                let angle = .pi / 2 + (Double(i) / 9 - 0.42) * 2.4 + rng.range(-0.08, 0.08)
                let spread = rng.range(0.04, 0.09) * width
                path.move(to: sun)
                path.addLine(to: CGPoint(x: sun.x + cos(angle - spread) * 1300, y: sun.y + sin(angle - spread) * 1300))
                path.addLine(to: CGPoint(x: sun.x + cos(angle + spread) * 1300, y: sun.y + sin(angle + spread) * 1300))
                path.closeSubpath()
            }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.clip(to: CGRect(x: -48, y: Self.horizon - 10, width: 1376, height: 740 - Self.horizon))
            ctx.drawRadialGradient(ScenePaint.gradient([(0, ScenePaint.color(0xFFE2A0, 0.16 * strength)), (0.5, ScenePaint.color(0xFFC878, 0.06 * strength)), (1, ScenePaint.color(0xFFC878, 0))]),
                                   startCenter: sun, startRadius: 30, endCenter: sun, endRadius: 1000, options: [])
            ctx.restoreGState()
        }
    }

    private func paintClouds() -> [(layer: SceneLayer, speed: Double, offset: Double)] {
        var out: [(layer: SceneLayer, speed: Double, offset: Double)] = []
        var rng = ScenePaint.generator(77)
        let specs: [(y: Double, w: Double, h: Double, speed: Double)] = [(560, 520, 70, 5), (620, 420, 52, 3.5), (470, 640, 60, 7.5), (676, 360, 40, 2.5), (520, 380, 46, 6)]
        for spec in specs {
            let rect = CGRect(x: 0, y: spec.y, width: spec.w, height: spec.h)
            if let layer = ScenePaint.layer(rect, { ctx in
                // Long streaks: a violet body, lit gold along the edge that faces the sun.
                for _ in 0..<12 {
                    let c = CGPoint(x: rng.range(spec.w * 0.3, spec.w * 0.7), y: spec.y + spec.h * rng.range(0.4, 0.6))
                    let rx = rng.range(spec.w * 0.08, spec.w * 0.2), ry = rng.range(spec.h * 0.12, spec.h * 0.26)
                    ScenePaint.blob(ctx, c, rx: rx, ry: ry, ScenePaint.color(0xB86A92, 0.55), inner: 0.2)
                    ScenePaint.blob(ctx, CGPoint(x: c.x - rx * 0.1, y: c.y - ry * 0.45), rx: rx * 0.85, ry: ry * 0.45, ScenePaint.color(0xFFC278, 0.7), inner: 0.1)
                }
            }) { out.append((layer.faded(0.85), spec.speed, rng.range(0, 1280))) }
        }
        return out
    }

    private func paintMountains(_ ctx: CGContext) {
        let h = Self.horizon
        let left = -48.0
        // Two ranges, the far one nearly lost in the haze.
        let far = ScenePaint.ridgePath(width: 1360, left: left, baseY: h + 58, bottom: h - 30, amplitude: 42, wavelength: 190, seed: 3)
        ctx.addPath(far)
        ctx.setFillColor(ScenePaint.color(0xB56A8C))
        ctx.fillPath()
        let near = ScenePaint.ridgePath(width: 1360, left: left, baseY: h + 28, bottom: h - 30, amplitude: 30, wavelength: 130, seed: 9)
        ctx.addPath(near)
        ctx.setFillColor(ScenePaint.color(0x8D5078))
        ctx.fillPath()
        // The sun side of the hills glows.
        ScenePaint.blob(ctx, CGPoint(x: Self.sun.x, y: h + 10), rx: 520, ry: 70, ScenePaint.color(0xFFC070, 0.55))
        // Haze lying at the foot of them.
        ScenePaint.fill(ctx, CGRect(x: left, y: h - 30, width: 1360, height: 70), [(0, ScenePaint.color(0xF7B77A, 0)), (0.6, ScenePaint.color(0xF9BE80, 0.75)), (1, ScenePaint.color(0xFFD08A, 1))],
                        from: CGPoint(x: 0, y: h + 40), to: CGPoint(x: 0, y: h - 6))
    }

    private func paintFarTrees(_ ctx: CGContext) {
        let h = Self.horizon
        var rng = ScenePaint.generator(5)
        // A line of little acacias on the horizon, thinning out in the glare of the sun.
        for i in 0..<13 {
            let x = -20 + Double(i) * 108 + rng.range(-34, 34)
            if abs(x - Self.sun.x) < 110 { continue }
            acacia(ctx, x: x, baseY: h - 6 + rng.range(-8, 4), height: rng.range(34, 58), spread: rng.range(48, 80), lean: rng.range(-6, 6),
                   color: ScenePaint.color(0x6B3F5E), rim: ScenePaint.color(0xE39A68), seed: Double(i))
        }
    }

    private func paintPlain(_ ctx: CGContext) {
        let h = Self.horizon
        let rect = CGRect(x: -48, y: 0, width: 1376, height: h + 4)
        ScenePaint.fillDown(ctx, rect, [(0, ScenePaint.color(0xF6C070)), (0.12, ScenePaint.color(0xE9A650)), (0.40, ScenePaint.color(0xC98B3C)),
                                       (0.75, ScenePaint.color(0x8C5E28)), (1, ScenePaint.color(0x573A1A))])
        // The glare of the sun on dry ground.
        ScenePaint.blob(ctx, CGPoint(x: Self.sun.x + 20, y: h - 6), rx: 640, ry: 90, ScenePaint.color(0xFFE6A0, 0.55))
        // Patches of bare earth and darker scrub, in perspective: smaller far away.
        var rng = ScenePaint.generator(21)
        for _ in 0..<26 {
            let t = rng.unit()
            let y = h - 10 - pow(t, 1.5) * (h - 10)
            let s = 0.25 + 1.25 * pow(t, 1.4)
            let x = rng.range(rect.minX, rect.maxX)
            ScenePaint.blob(ctx, CGPoint(x: x, y: y), rx: rng.range(60, 140) * s, ry: rng.range(5, 12) * s, rng.chance(0.5) ? ScenePaint.color(0x7A4E22, 0.30) : ScenePaint.color(0xF0C27A, 0.30))
        }
        // The waterhole, with the sun in it.
        let pond = Self.pond
        ScenePaint.oval(ctx, pond, rx: 214, ry: 28, ScenePaint.color(0x6E4A2A, 0.75))
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: pond.x - 198, y: pond.y - 20, width: 396, height: 40))
        ctx.clip()
        ScenePaint.fillDown(ctx, CGRect(x: pond.x - 198, y: pond.y - 20, width: 396, height: 40), [(0, ScenePaint.color(0xFFD98C)), (0.5, ScenePaint.color(0xE98A74)), (1, ScenePaint.color(0x8A5B86))])
        ScenePaint.blob(ctx, CGPoint(x: Self.sun.x, y: pond.y + 6), rx: 60, ry: 12, ScenePaint.color(0xFFF4C8, 0.9))
        ctx.setStrokeColor(ScenePaint.color(0xFFF3CC, 0.8))
        ctx.setLineWidth(1.6)
        for i in 0..<8 {
            let y = pond.y + 13 - Double(i) * 3.6
            let x = pond.x - 120 + rng.range(-40, 200)
            ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + rng.range(10, 36), y: y)); ctx.strokePath()
        }
        ctx.restoreGState()
        // Reeds at the water's edge.
        for i in 0..<26 {
            let x = pond.x - 210 + Double(i) * 16 + rng.range(-5, 5)
            if abs(x - pond.x) < 150 && i % 3 != 0 { continue }
            ScenePaint.blade(ctx, at: CGPoint(x: x, y: pond.y - 18 + rng.range(-4, 4)), height: rng.range(14, 30), lean: rng.range(-5, 5), width: 1.6, color: ScenePaint.color(0x5A4020, 0.8))
        }
    }

    /// Grass: short strokes, thick and dark near the bottom of the picture, fine and pale in the distance. In two halves.
    private func paintGrass(_ ctx: CGContext, part: Int) {
        let h = Self.horizon
        var rng = ScenePaint.generator(UInt64(41 + part))
        let tones: [UInt32] = [0xB8832F, 0xDBA850, 0x8B6226, 0xF0C878, 0x6E4A1F]
        for _ in 0..<1300 {
            let t = rng.unit()
            let y = h - 6 - pow(t, 1.35) * (h - 6)
            let s = 0.18 + 1.1 * pow(t, 1.2)
            let x = rng.range(-48, 1328)
            let tone = tones[Int(rng.unit() * Double(tones.count))]
            ScenePaint.blade(ctx, at: CGPoint(x: x, y: y), height: rng.range(7, 19) * s, lean: rng.range(-4, 4) * s, width: max(0.7, 1.4 * s),
                             color: ScenePaint.color(tone, rng.range(0.25, 0.6)))
        }
    }

    /// The corners of the picture darken a little, painted in once.
    private func paintVignette(_ ctx: CGContext) {
        let g = ScenePaint.gradient([(0, ScenePaint.color(0x2A0F20, 0)), (0.6, ScenePaint.color(0x2A0F20, 0)), (1, ScenePaint.color(0x2A0F20, 0.4))])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 380), startRadius: 0, endCenter: CGPoint(x: 640, y: 380), endRadius: 800, options: [.drawsAfterEndLocation])
    }

    /// The trees, each its own small picture so that only the part with a tree in it is copied. Rim-lit from the sun on the left.
    private func paintTrees() -> [SceneLayer] {
        let dark = ScenePaint.color(0x2C1B2E), rim = ScenePaint.color(0xF29A58)
        func acaciaRect(_ x: Double, _ base: Double, _ h: Double, _ spread: Double, _ lean: Double) -> CGRect {
            CGRect(x: x + lean - spread * 0.62 - 8, y: base - 6, width: spread * 1.24 + 16, height: h * 1.12 + 12)
        }
        var out: [SceneLayer?] = []
        // A baobab far off on the left, a pair of acacias right of the middle, and a big acacia framing the right edge.
        out.append(ScenePaint.layer(CGRect(x: -60, y: 300, width: 300, height: 240), parallax: 22) { baobab($0, x: 70, baseY: 306, height: 190, color: ScenePaint.color(0x3A2238), rim: rim) })
        var r = acaciaRect(930, 300, 120, 190, -10)
        out.append(ScenePaint.layer(r, parallax: 24) { acacia($0, x: 930, baseY: 300, height: 120, spread: 190, lean: -10, color: ScenePaint.color(0x4A2C44), rim: rim, seed: 2) })
        r = acaciaRect(1010, 288, 150, 240, 12)
        out.append(ScenePaint.layer(r, parallax: 26) { acacia($0, x: 1010, baseY: 288, height: 150, spread: 240, lean: 12, color: ScenePaint.color(0x3A2438), rim: rim, seed: 4) })
        r = acaciaRect(1190, 270, 250, 380, 20)
        out.append(ScenePaint.layer(r, parallax: 30) { acacia($0, x: 1190, baseY: 270, height: 250, spread: 380, lean: 20, color: dark, rim: rim, seed: 1) })
        return out.compactMap { $0 }
    }

    // MARK: Plants

    /// A flat-topped acacia as a silhouette against the sky, its upper edge lit by the low sun.
    private func acacia(_ ctx: CGContext, x: Double, baseY: Double, height h: Double, spread: Double, lean: Double, color: CGColor, rim: CGColor, seed: Double) {
        func draw(_ color: CGColor, _ dx: Double, _ dy: Double) {
            ctx.saveGState()
            ctx.translateBy(x: dx, y: dy)
            ctx.setFillColor(color)
            ctx.setStrokeColor(color)
            ctx.setLineCap(.round)
            // The trunk, forking low.
            let fork = CGPoint(x: x + lean * 0.5, y: baseY + h * 0.52)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - h * 0.035, y: baseY))
            path.addQuadCurve(to: CGPoint(x: fork.x - h * 0.022, y: fork.y), control: CGPoint(x: x - h * 0.02, y: baseY + h * 0.3))
            path.addLine(to: CGPoint(x: fork.x + h * 0.022, y: fork.y))
            path.addQuadCurve(to: CGPoint(x: x + h * 0.035, y: baseY), control: CGPoint(x: x + h * 0.03, y: baseY + h * 0.3))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
            // The limbs reaching up to the canopy.
            let top = baseY + h * 0.88
            let limbs: [(CGPoint, Double)] = [(CGPoint(x: x + lean - spread * 0.36, y: top - h * 0.04), 0.03), (CGPoint(x: x + lean * 1.2, y: top + h * 0.03), 0.034),
                                              (CGPoint(x: x + lean + spread * 0.38, y: top - h * 0.06), 0.03), (CGPoint(x: x + lean - spread * 0.14, y: top), 0.022),
                                              (CGPoint(x: x + lean + spread * 0.16, y: top + h * 0.01), 0.022)]
            for (end, width) in limbs {
                ctx.setLineWidth(max(1.2, h * width))
                ctx.move(to: fork)
                ctx.addQuadCurve(to: end, control: CGPoint(x: (fork.x + end.x) / 2 + (end.x - fork.x) * 0.1, y: fork.y + (end.y - fork.y) * 0.8))
                ctx.strokePath()
            }
            // The canopy: a flat, layered cap with a lumpy top.
            let cx = x + lean, cy = baseY + h * 0.93
            var rng = ScenePaint.generator(UInt64(seed * 13 + 3))
            for layer in 0..<3 {
                let w = spread * (1 - Double(layer) * 0.12), yy = cy + Double(layer) * h * 0.035
                let n = max(5, Int(w / (h * 0.16)))
                for i in 0..<n {
                    let k = Double(i) / Double(n - 1) - 0.5
                    let rx = w * rng.range(0.15, 0.24), ry = h * rng.range(0.045, 0.07)
                    ctx.fillEllipse(in: CGRect(x: cx + k * w * 0.82 - rx, y: yy + (1 - 4 * k * k) * h * 0.02 - ry, width: rx * 2, height: ry * 2))
                }
            }
            ctx.restoreGState()
        }
        // The rim of light is on the side toward the sun, up and to the left.
        draw(rim, -2.4, 3.0)
        draw(color, 0, 0)
    }

    private func baobab(_ ctx: CGContext, x: Double, baseY: Double, height h: Double, color: CGColor, rim: CGColor) {
        func draw(_ color: CGColor, _ dx: Double, _ dy: Double) {
            ctx.saveGState()
            ctx.translateBy(x: dx, y: dy)
            ctx.setFillColor(color)
            ctx.setStrokeColor(color)
            ctx.setLineCap(.round)
            let trunk = CGMutablePath()
            trunk.move(to: CGPoint(x: x - h * 0.2, y: baseY))
            trunk.addCurve(to: CGPoint(x: x - h * 0.11, y: baseY + h * 0.66), control1: CGPoint(x: x - h * 0.06, y: baseY + h * 0.18), control2: CGPoint(x: x - h * 0.2, y: baseY + h * 0.4))
            trunk.addLine(to: CGPoint(x: x + h * 0.11, y: baseY + h * 0.66))
            trunk.addCurve(to: CGPoint(x: x + h * 0.2, y: baseY), control1: CGPoint(x: x + h * 0.2, y: baseY + h * 0.4), control2: CGPoint(x: x + h * 0.06, y: baseY + h * 0.18))
            trunk.closeSubpath()
            ctx.addPath(trunk)
            ctx.fillPath()
            // Stubby branches, each ending in a tuft of leaves.
            let tips: [(Double, Double)] = [(-0.34, 0.95), (-0.14, 1.04), (0.1, 1.06), (0.32, 0.96), (-0.22, 0.84), (0.22, 0.86)]
            for (dx, up) in tips {
                let end = CGPoint(x: x + dx * h * 1.1, y: baseY + up * h)
                ctx.setLineWidth(h * 0.05)
                ctx.move(to: CGPoint(x: x + dx * h * 0.15, y: baseY + h * 0.64))
                ctx.addQuadCurve(to: end, control: CGPoint(x: x + dx * h * 0.5, y: baseY + h * 0.78))
                ctx.strokePath()
                ctx.fillEllipse(in: CGRect(x: end.x - h * 0.1, y: end.y - h * 0.028, width: h * 0.2, height: h * 0.07))
            }
            ctx.restoreGState()
        }
        draw(rim, -2.4, 3.0)
        draw(color, 0, 0)
    }

    /// A clump of tall grass, dark at the root and lit gold at the tips, for the foreground: painted bent to each point of its sway.
    /// Bending is a shear, so the roots stay put and the tips move most, as grass does.
    private func paintGrassClump(seed: UInt64) -> [CGImage]? {
        let frames: [CGImage] = (0..<Self.swayFrames).compactMap { i in
            let bend = (Double(i) / Double(Self.swayFrames - 1) - 0.5) * 0.16
            return ScenePaint.picture(width: 340, height: 230) { ctx in
                ctx.translateBy(x: 170, y: 0)
                ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: CGFloat(bend), d: 1, tx: 0, ty: 0))
                var rng = ScenePaint.generator(seed * 9973)
                for k in 0..<64 {
                    let t = Double(k) / 64
                    let height = rng.range(80, 200) * (0.65 + 0.35 * (1 - abs(t - 0.5) * 1.4))
                    let base = CGPoint(x: rng.range(-70, 70), y: -2)
                    let lean = rng.range(-60, 60) + Double(base.x) * 0.5
                    let tone = rng.range(0, 1)
                    ScenePaint.blade(ctx, at: base, height: height, lean: lean, width: rng.range(2.4, 5), color: ScenePaint.mix(0x2C2410, tone > 0.5 ? 0x9A7A30 : 0x6E5622, 0.3 + 0.5 * height / 200))
                    // The tip catches the sun.
                    ScenePaint.blade(ctx, at: CGPoint(x: base.x + lean * 0.42, y: base.y + height * 0.62), height: height * 0.38, lean: lean * 0.58, width: 2.2,
                                     color: ScenePaint.color(0xF2C46A, 0.85))
                }
            }
        }
        return frames.count == Self.swayFrames ? frames : nil
    }

    // MARK: Painting each frame

    func paintBackdrop(_ ctx: CGContext, frame: SceneFrame) {
        ctx.interpolationQuality = .low
        world?.draw(in: ctx, shift: frame.shift)
        // Clouds drift slowly right to left, wrapping round.
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
        drawBirds(ctx, time: frame.time, shift: frame.shift)
        drawHerd(ctx, time: frame.time, shift: frame.shift)
        drawHeat(ctx, time: frame.time, shift: frame.shift)
        drawPond(ctx, time: frame.time, shift: frame.shift)
        for tree in trees { tree.draw(in: ctx, shift: frame.shift) }
        ctx.interpolationQuality = .high
    }

    /// Air shimmering above the hot ground under the sun.
    private func drawHeat(_ ctx: CGContext, time: Double, shift: CGPoint) {
        let h = Self.horizon
        ctx.setLineCap(.round)
        ctx.setLineWidth(2.2)
        for i in 0..<9 {
            let y = h - 16 - Double(i) * 6
            let phase = time * 0.9 + Double(i) * 1.3
            let x = Self.sun.x - 240 + Double(i % 3) * 170 + sin(phase) * 28 + Double(shift.x) * 16
            ctx.setStrokeColor(ScenePaint.color(0xFFF0C0, 0.07 + 0.04 * sin(phase * 1.3)))
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addCurve(to: CGPoint(x: x + 150, y: y + sin(phase + 1) * 1.6), control1: CGPoint(x: x + 50, y: y + sin(phase) * 3), control2: CGPoint(x: x + 100, y: y - sin(phase) * 3))
            ctx.strokePath()
        }
    }

    /// Glints dancing on the waterhole.
    private func drawPond(_ ctx: CGContext, time: Double, shift: CGPoint) {
        let pond = Self.pond
        let dx = Double(shift.x) * 14
        ctx.setFillColor(ScenePaint.color(0xFFF8DA, 0.85))
        for i in 0..<10 {
            let f = Double(i)
            let life = (time * 0.6 + f * 0.37).truncatingRemainder(dividingBy: 1)
            let w = 10 * sin(life * .pi)
            guard w > 1 else { continue }
            let x = Self.sun.x - 60 + (f * 37).truncatingRemainder(dividingBy: 150) + dx
            let y = pond.y + 4 - (f * 7).truncatingRemainder(dividingBy: 22)
            ctx.fill(CGRect(x: x - w / 2, y: y, width: w, height: 1.4))
        }
    }

    /// A herd so far off that it is a line of tiny silhouettes, walking slowly along the horizon.
    private func drawHerd(_ ctx: CGContext, time: Double, shift: CGPoint) {
        let base = Self.horizon - 18
        ctx.setFillColor(ScenePaint.color(0x4E2E46, 0.85))
        for i in 0..<16 {
            let f = Double(i)
            var x = (760 + f * 23 + (f * 7).truncatingRemainder(dividingBy: 9) - time * 3.2).truncatingRemainder(dividingBy: 1500)
            if x < -40 { x += 1500 }
            x += Double(shift.x) * 8
            let y = base + (f * 3).truncatingRemainder(dividingBy: 5) - 2
            let step = sin(time * 5 + f * 1.7)
            ctx.fill(CGRect(x: x, y: y + 2.2, width: 6.5, height: 2.6))
            ctx.fill(CGRect(x: x + 5.5, y: y + 3.2, width: 2.2, height: 2.4))
            ctx.fill(CGRect(x: x + 0.6 + step * 0.4, y: y, width: 0.9, height: 2.4))
            ctx.fill(CGRect(x: x + 5 - step * 0.4, y: y, width: 0.9, height: 2.4))
        }
    }

    /// A flock crossing the sky now and then, far away.
    private func drawBirds(_ ctx: CGContext, time: Double, shift: CGPoint) {
        let period = 42.0, crossing = 21.0
        let t = time.truncatingRemainder(dividingBy: period)
        guard t < crossing else { return }
        let k = t / crossing
        ctx.setStrokeColor(ScenePaint.color(0x35203C, 0.75))
        ctx.setLineWidth(1.9)
        ctx.setLineCap(.round)
        let path = CGMutablePath()
        for i in 0..<7 {
            let lead = Double(i % 4) * 26 + Double(i / 4) * 14
            let x = 1360 - k * 1500 + lead * 1.4 + Double(shift.x) * 5
            let y = 540 + sin(Double(i) * 1.7) * 18 + Double(i) * 6 - Double(i % 2) * 22 + sin(k * 6 + Double(i)) * 6
            let flap = sin(time * 8 + Double(i) * 0.9) * 0.55
            let span = 10.0 + Double(i % 3)
            path.move(to: CGPoint(x: x - span, y: y + flap * span * 0.9))
            path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - span * 0.5, y: y + span * 0.35 + flap * span * 0.6))
            path.addQuadCurve(to: CGPoint(x: x + span, y: y + flap * span * 0.9), control: CGPoint(x: x + span * 0.5, y: y + span * 0.35 + flap * span * 0.6))
        }
        ctx.addPath(path)
        ctx.strokePath()
    }

    func paintForeground(_ ctx: CGContext, frame: SceneFrame) {
        // Dust motes drifting through the light.
        if let dot = Sprites.dot(red: 1, green: 0.84, blue: 0.5) {
            for i in 0..<20 {
                let f = Double(i)
                let x = (f * 97.3 + frame.time * (6 + Double(i % 5) * 3)).truncatingRemainder(dividingBy: 1340) - 30
                let y = 70 + (f * 53.1).truncatingRemainder(dividingBy: 560) + sin(frame.time * 0.5 + f) * 16
                let alpha = 0.22 + 0.2 * sin(frame.time * 1.6 + f * 2.1)
                ctx.stampDot(dot, at: CGPoint(x: (x + Double(frame.shift.x) * 20).rounded(), y: y.rounded()), radius: Double(2 + i % 4), alpha: alpha)
            }
        }
        // Tall grass swaying in the corners.
        let spots: [(x: Double, phase: Double, index: Int)] = [(40, 0.0, 0), (210, 1.6, 1), (1075, 3.1, 2), (1250, 4.4, 3)]
        for spot in spots where spot.index < grass.count {
            let sway = 0.5 + 0.5 * (0.7 * sin(frame.time * 1.1 + spot.phase) + 0.3 * sin(frame.time * 2.7 + spot.phase * 2))
            let image = grass[spot.index][min(Self.swayFrames - 1, max(0, Int((sway * Double(Self.swayFrames - 1)).rounded())))]
            let x = (spot.x + Double(frame.shift.x) * 60 - Double(image.width) / 2).rounded()
            ctx.draw(image, in: CGRect(x: x, y: -16, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
    }

    // MARK: The animals

    private lazy var puppets: [String: ScenePuppet] = [
        "lion": SceneBigCat(.lion), "cheetah": SceneBigCat(.cheetah), "elephant": SceneElephant(), "giraffe": SceneGrazer(.giraffe),
        "zebra": SceneGrazer(.zebra), "rhino": SceneHeavy(.rhino), "buffalo": SceneHeavy(.buffalo), "vulture": SceneBird(.vulture),
    ]

    func puppet(for index: Int) -> ScenePuppet? { puppets[cast.species[index].name] }
}
