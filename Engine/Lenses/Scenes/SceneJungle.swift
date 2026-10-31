import AppKit
import CoreGraphics
import Foundation

/// Who lives in the jungle.
enum JungleCast {
    static var cast: SceneCast {
        var layout = SceneLayout()
        layout.farGround = 236
        layout.nearGround = 70
        layout.roamLow = 360
        layout.roamHigh = 640

        let monkey = SceneSpecies(name: "monkey", glyph: "", facesRight: true, height: 150, aspect: 1.0, speed: 120, temper: .prey, act: .climb,
                                  home: 0.2, charge: 1.9, actSeconds: 8, painted: true)
        var parrot = SceneSpecies(name: "parrot", glyph: "", facesRight: true, height: 96, aspect: 1.04, speed: 170, body: .flier, temper: .prey, act: .perch,
                                  home: 0.35, charge: 1.5, perchesOnHand: true, actSeconds: 8, painted: true)
        parrot.shout = "SQUAWK!"
        let snake = SceneSpecies(name: "snake", glyph: "", facesRight: true, height: 84, aspect: 3.2, speed: 95, gait: .slither, temper: .prey, act: .rear,
                                 home: 0.86, charge: 1.6, actSeconds: 3.0, painted: true)
        let tiger = SceneSpecies(name: "tiger", glyph: "", facesRight: true, height: 150, aspect: 1.6, speed: 118, temper: .brute, act: .roar,
                                 home: 0.2, charge: 1.3, stalks: true, actSeconds: 2.6, painted: true)
        let gorilla = SceneSpecies(name: "gorilla", glyph: "", facesRight: true, height: 240, aspect: 1.0, speed: 66, temper: .brute, act: .chestBeat,
                                   home: 0.2, charge: 1.8, actSeconds: 3.0, painted: true)
        var frog = SceneSpecies(name: "frog", glyph: "", facesRight: true, height: 70, aspect: 1.26, speed: 85, gait: .hop, temper: .prey, act: .hop,
                                home: 0.8, charge: 1.5, actSeconds: 2.2, painted: true)
        frog.shout = "RIBBIT!"
        let butterfly = SceneSpecies(name: "butterfly", glyph: "", facesRight: true, height: 58, aspect: 1.18, speed: 80, body: .flier, temper: .prey, act: .perch,
                                     home: 0.45, charge: 1.2, perchesOnHand: true, interest: 1.2, actSeconds: 8, painted: true, shout: "✨")

        let species = [monkey, parrot, snake, tiger, gorilla, frog, butterfly]
        return SceneCast(species: species, roster: [0, 0, 1, 1, 2, 3, 4, 5, 5, 6, 6], layout: layout, cap: 10, visibleAtStart: 6)
    }
}

/// A dense jungle: trunks and vines in layers of mist, shafts of light through a gap in the canopy up on the left, a waterfall far
/// back on the right, and animals that come out of the leaves to look at you.
final class JungleScene: SceneStyle {
    let cast = JungleCast.cast
    let look = SceneLook(haze: 0x7FB08A, hazeAmount: 0.18, dusk: 0x0C2A20, duskAmount: 0.26, warm: 0xD8F090, warmAmount: 0.12, shade: 0.34,
                         dust: 0x8A7A55, shadow: 0.5, shadowLean: 0.1, water: 0xDDF2FF)
    let hint = "Wave your arms to scare the animals! Hold up a hand for a parrot."

    private static let ground = 280.0
    /// The gap in the canopy the daylight comes through: up and to the left, like every light in the scenes.
    private static let gap = CGPoint(x: 380, y: 700)
    private static let fall = CGPoint(x: 1040, y: 250)

    private var world: SceneLayer?
    private var canvas: SceneCanvas?
    private var mist: [(layer: SceneLayer, speed: Double, offset: Double, alpha: Double)] = []
    private var vines: [(frames: [CGImage], x: Double, top: Double, phase: Double, parallax: Double)] = []
    private var fronds: [(frames: [CGImage], x: Double, y: Double, phase: Double)] = []
    private static let swayFrames = 9

    private lazy var bakery = SceneBakery([
        { [unowned self] in canvas = SceneCanvas(CGRect(x: -48, y: 0, width: 1376, height: 720)); canvas?.paint { paintBackground($0); paintFarForest($0) } },
        { [unowned self] in canvas?.paint { paintWaterfall($0); paintGround($0) } },
        { [unowned self] in canvas?.paint { paintGroundPlants($0) } },
        { [unowned self] in canvas?.paint { paintMidForest($0) } },
        { [unowned self] in canvas?.paint { paintCanopy($0) } },
        { [unowned self] in canvas?.paint { paintShafts($0); paintVignette($0) }; world = canvas?.finish(parallax: 12); canvas = nil },
        { [unowned self] in mist = paintMist() },
        { [unowned self] in paintVines(0..<3) },
        { [unowned self] in paintVines(3..<6) },
        { [unowned self] in paintCornerFronds() },
    ])

    func prepare(until deadline: Double) -> Bool { bakery.run(until: deadline) }

    // MARK: The world

    private func paintBackground(_ ctx: CGContext) {
        let rect = CGRect(x: -48, y: 0, width: 1376, height: 720)
        ScenePaint.fillDown(ctx, rect, [(0, ScenePaint.color(0x2A6A3C)), (0.25, ScenePaint.color(0x1B5236)), (0.6, ScenePaint.color(0x124030)), (1, ScenePaint.color(0x0A2A20))])
        // Daylight coming down through a gap in the canopy, up on the left.
        ScenePaint.blob(ctx, Self.gap, rx: 700, ry: 520, ScenePaint.color(0xD6EE8A, 0.75), inner: 0.05)
        ScenePaint.blob(ctx, CGPoint(x: Self.gap.x - 40, y: 720), rx: 300, ry: 260, ScenePaint.color(0xFFFFC8, 0.8))
        // And a soft clearing behind where you sit, so that you stand out from the leaves.
        ScenePaint.blob(ctx, CGPoint(x: 640, y: 430), rx: 520, ry: 380, ScenePaint.color(0xA4D890, 0.34))
    }

    /// Slim, hazy trunks far back in the forest, with mist between them.
    private func paintFarForest(_ ctx: CGContext) {
        var rng = ScenePaint.generator(101)
        for i in 0..<16 {
            let x = -40 + Double(i) * 88 + rng.range(-30, 30)
            trunk(ctx, x: x, width: rng.range(14, 30), lean: rng.range(-18, 18), color: ScenePaint.color(0x1D5A44), rim: ScenePaint.color(0x7CC088, 0.5), baseY: 250, rng: &rng, bark: false)
        }
        // Far leaf masses between them.
        for _ in 0..<26 {
            let c = CGPoint(x: rng.range(-40, 1320), y: rng.range(420, 700))
            ScenePaint.blob(ctx, c, rx: rng.range(60, 160), ry: rng.range(40, 100), ScenePaint.mix(0x1C6A44, 0x4C9A4A, rng.unit(), alpha: 0.55), inner: 0.2)
        }
        mistBand(ctx, y: 360, alpha: 0.30)
        mistBand(ctx, y: 440, alpha: 0.18)
    }

    /// A waterfall far back on the right: a pale cascade down a dark cliff into a misty pool. The falling water is drawn each frame.
    private func paintWaterfall(_ ctx: CGContext) {
        let f = Self.fall
        let cliff = CGMutablePath()
        cliff.move(to: CGPoint(x: f.x - 150, y: f.y - 10))
        cliff.addCurve(to: CGPoint(x: f.x - 60, y: 640), control1: CGPoint(x: f.x - 160, y: 420), control2: CGPoint(x: f.x - 90, y: 560))
        cliff.addLine(to: CGPoint(x: f.x + 70, y: 650))
        cliff.addCurve(to: CGPoint(x: f.x + 170, y: f.y - 10), control1: CGPoint(x: f.x + 110, y: 540), control2: CGPoint(x: f.x + 180, y: 420))
        cliff.closeSubpath()
        ctx.addPath(cliff)
        ctx.setFillColor(ScenePaint.color(0x2A5A48))
        ctx.fillPath()
        ScenePaint.fill(ctx, CGRect(x: f.x - 40, y: f.y, width: 84, height: 640 - f.y), [(0, ScenePaint.color(0xB8DCCF, 0.8)), (0.5, ScenePaint.color(0xE8F8F0, 0.95)), (1, ScenePaint.color(0xCDEBE0, 0.85))],
                        from: CGPoint(x: f.x - 40, y: 0), to: CGPoint(x: f.x + 44, y: 0))
        ScenePaint.blob(ctx, CGPoint(x: f.x, y: f.y + 6), rx: 120, ry: 34, ScenePaint.color(0xE8F8F0, 0.7))
        mistBand(ctx, y: f.y + 30, alpha: 0.12)
    }

    private func mistBand(_ ctx: CGContext, y: Double, alpha: Double) {
        var rng = ScenePaint.generator(UInt64(y))
        for i in 0..<9 {
            ScenePaint.blob(ctx, CGPoint(x: -20 + Double(i) * 170 + rng.range(-40, 40), y: y + rng.range(-20, 20)), rx: rng.range(160, 260), ry: rng.range(30, 52),
                            ScenePaint.color(0xCDEBC0, alpha), inner: 0.1)
        }
    }

    /// The forest floor: moss and leaf litter, with a muddy track across it.
    private func paintGround(_ ctx: CGContext) {
        let g = Self.ground
        let rect = CGRect(x: -48, y: 0, width: 1376, height: g + 8)
        ScenePaint.fillDown(ctx, rect, [(0, ScenePaint.color(0x2C6B38)), (0.12, ScenePaint.color(0x1F5530)), (0.55, ScenePaint.color(0x143F26)), (1, ScenePaint.color(0x0A2416))])
        var rng = ScenePaint.generator(202)
        // The track.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -60, y: 20))
        path.addCurve(to: CGPoint(x: 1340, y: 60), control1: CGPoint(x: 300, y: 120), control2: CGPoint(x: 900, y: -20))
        path.addLine(to: CGPoint(x: 1340, y: 150))
        path.addCurve(to: CGPoint(x: -60, y: 130), control1: CGPoint(x: 900, y: 100), control2: CGPoint(x: 300, y: 210))
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ScenePaint.fillDown(ctx, CGRect(x: -60, y: -20, width: 1400, height: 230), [(0, ScenePaint.color(0x6B4A2E, 0.8)), (1, ScenePaint.color(0x4A3322, 0.8))])
        ctx.restoreGState()
        // Moss patches, in perspective.
        for _ in 0..<40 {
            let t = rng.unit()
            let y = g - pow(t, 1.4) * g
            let s = 0.3 + 1.2 * pow(t, 1.3)
            ScenePaint.blob(ctx, CGPoint(x: rng.range(-40, 1320), y: y), rx: rng.range(50, 120) * s, ry: rng.range(5, 12) * s,
                            rng.chance(0.5) ? ScenePaint.color(0x6FB04A, 0.30) : ScenePaint.color(0x08180E, 0.30))
        }
        // Leaf litter and tufts.
        let tones: [UInt32] = [0x2F7A3A, 0x4FA047, 0x1B4A2A, 0x8AB84A, 0x5A3E22]
        for _ in 0..<1700 {
            let t = rng.unit()
            let y = g - 6 - pow(t, 1.3) * (g - 6)
            let s = 0.2 + 1.1 * pow(t, 1.2)
            let tone = tones[Int(rng.unit() * Double(tones.count))]
            ScenePaint.blade(ctx, at: CGPoint(x: rng.range(-40, 1320), y: y), height: rng.range(6, 18) * s, lean: rng.range(-5, 5) * s, width: max(0.8, 1.4 * s), color: ScenePaint.color(tone, rng.range(0.3, 0.7)))
        }
    }

    /// Rocks and ferns by the track, and the shade where the ground meets the forest.
    private func paintGroundPlants(_ ctx: CGContext) {
        let g = Self.ground
        var rng = ScenePaint.generator(203)
        // Rocks and ferns by the track.
        for _ in 0..<9 {
            let t = rng.range(0.1, 0.9), x = rng.range(-20, 1300), y = 30 + t * 220, s = 0.4 + 0.9 * (1 - t)
            ScenePaint.oval(ctx, CGPoint(x: x, y: y), rx: 34 * s, ry: 18 * s, ScenePaint.color(0x1F3A32))
            ScenePaint.oval(ctx, CGPoint(x: x + 5 * s, y: y + 5 * s), rx: 26 * s, ry: 11 * s, ScenePaint.color(0x4C7660, 0.7))
            ScenePaint.oval(ctx, CGPoint(x: x - 8 * s, y: y + 9 * s), rx: 22 * s, ry: 7 * s, ScenePaint.color(0x6FB04A, 0.8))
        }
        for _ in 0..<14 {
            let x = rng.range(-20, 1300), y = rng.range(40, 250), s = 0.35 + 0.8 * (1 - y / 280)
            fern(ctx, base: CGPoint(x: x, y: y), scale: s, rng: &rng)
        }
        // Where the ground meets the forest.
        ScenePaint.fill(ctx, CGRect(x: -48, y: g - 30, width: 1376, height: 60), [(0, ScenePaint.color(0x0F2E22, 0)), (0.5, ScenePaint.color(0x0F2E22, 0.7)), (1, ScenePaint.color(0x0F2E22, 0))],
                        from: CGPoint(x: 0, y: g + 28), to: CGPoint(x: 0, y: g - 28))
    }

    private func fern(_ ctx: CGContext, base: CGPoint, scale s: Double, rng: inout SceneRandom) {
        for i in 0..<7 {
            let angle = .pi / 2 + (Double(i) / 6 - 0.5) * 2.1 + rng.range(-0.1, 0.1)
            ScenePaint.frond(ctx, base: base, angle: angle, length: 70 * s * rng.range(0.7, 1.1), droop: 1.1, leaflets: 11, leafLength: 20 * s,
                             stem: ScenePaint.color(0x1F5A2E), leafColor: ScenePaint.mix(0x2E8A3E, 0x6CBE4A, rng.unit()), highlight: nil)
        }
    }

    /// Thick trunks close in, with roots, bark and hanging vines, lit on the side toward the canopy gap.
    private func paintMidForest(_ ctx: CGContext) {
        var rng = ScenePaint.generator(303)
        let xs: [Double] = [30, 245, 470, 830, 1060, 1280]
        for (i, x) in xs.enumerated() {
            let w = rng.range(46, 78)
            trunk(ctx, x: x, width: w, lean: rng.range(-30, 30), color: ScenePaint.mix(0x0C2A1E, 0x143828, rng.unit()), rim: ScenePaint.color(0x8CCB6A, 0.65), baseY: 190 + Double(i % 3) * 10, rng: &rng, bark: true)
        }
        mistBand(ctx, y: 330, alpha: 0.16)
        // Vines looping between them.
        for _ in 0..<9 {
            let x0 = rng.range(0, 1280), y0 = rng.range(560, 720), span = rng.range(120, 280), sag = rng.range(90, 220)
            vine(ctx, from: CGPoint(x: x0, y: y0), to: CGPoint(x: x0 + span, y: y0 + rng.range(-40, 20)), sag: sag, rng: &rng)
        }
    }

    private func trunk(_ ctx: CGContext, x: Double, width w: Double, lean: Double, color: CGColor, rim: CGColor, baseY: Double, rng: inout SceneRandom, bark: Bool) {
        let top = 740.0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x - w * 0.9, y: baseY - 30))
        // The roots flare out at the foot.
        path.addCurve(to: CGPoint(x: x - w * 0.5, y: baseY + 70), control1: CGPoint(x: x - w * 0.55, y: baseY - 4), control2: CGPoint(x: x - w * 0.5, y: baseY + 30))
        path.addCurve(to: CGPoint(x: x - w * 0.42 + lean, y: top), control1: CGPoint(x: x - w * 0.48 + lean * 0.3, y: baseY + 260), control2: CGPoint(x: x - w * 0.4 + lean * 0.8, y: 560))
        path.addLine(to: CGPoint(x: x + w * 0.42 + lean, y: top))
        path.addCurve(to: CGPoint(x: x + w * 0.5, y: baseY + 70), control1: CGPoint(x: x + w * 0.4 + lean * 0.8, y: 560), control2: CGPoint(x: x + w * 0.48 + lean * 0.3, y: baseY + 260))
        path.addCurve(to: CGPoint(x: x + w * 0.9, y: baseY - 30), control1: CGPoint(x: x + w * 0.5, y: baseY + 30), control2: CGPoint(x: x + w * 0.55, y: baseY - 4))
        path.closeSubpath()
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        // The lit side, toward the gap in the canopy.
        ctx.setStrokeColor(rim)
        ctx.setLineWidth(max(2, w * 0.1))
        ctx.move(to: CGPoint(x: x - w * 0.4, y: baseY + 60))
        ctx.addCurve(to: CGPoint(x: x - w * 0.38 + lean, y: top), control1: CGPoint(x: x - w * 0.44 + lean * 0.3, y: baseY + 260), control2: CGPoint(x: x - w * 0.36 + lean * 0.8, y: 560))
        ctx.strokePath()
        if bark {
            for _ in 0..<Int(w / 3) {
                let bx = x + rng.range(-w * 0.4, w * 0.4)
                ctx.setStrokeColor(CGColor(gray: 0, alpha: rng.range(0.15, 0.35)))
                ctx.setLineWidth(rng.range(1, 2.4))
                ctx.move(to: CGPoint(x: bx, y: baseY + rng.range(40, 120)))
                ctx.addLine(to: CGPoint(x: bx + lean * 0.4, y: baseY + rng.range(300, 560)))
                ctx.strokePath()
            }
            // Moss and ferns clinging on, catching the light on the left.
            for _ in 0..<8 {
                ScenePaint.blob(ctx, CGPoint(x: x + rng.range(-w * 0.3, w * 0.45), y: baseY + rng.range(60, 400)), rx: rng.range(10, 24), ry: rng.range(16, 50), ScenePaint.color(0x6EC050, 0.45))
            }
        }
        ctx.restoreGState()
    }

    /// A vine sagging between two points, with a leaf here and there.
    private func vine(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, sag: Double, rng: inout SceneRandom) {
        let control = CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - sag)
        ctx.setStrokeColor(ScenePaint.color(0x14341F))
        ctx.setLineWidth(rng.range(3, 6))
        ctx.setLineCap(.round)
        ctx.move(to: a)
        ctx.addQuadCurve(to: b, control: control)
        ctx.strokePath()
        for i in 1..<9 {
            let t = Double(i) / 9
            let p = CGPoint(x: (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * control.x + t * t * b.x, y: (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * control.y + t * t * b.y)
            ScenePaint.leaf(ctx, from: p, angle: rng.range(0, 2 * .pi), length: rng.range(14, 30), width: 6, bend: 0.1, color: ScenePaint.mix(0x2A7A3A, 0x7CC04A, rng.unit()))
        }
    }

    /// The canopy overhead: layers of big leaves hanging from the top edge.
    private func paintCanopy(_ ctx: CGContext) {
        var rng = ScenePaint.generator(404)
        for layer in 0..<3 {
            let dark = [0x0B3020, 0x14502E, 0x2A7A3C][layer]
            let light = [0x1A5A34, 0x3A8A44, 0x7CC04A][layer]
            let count = [34, 30, 20][layer]
            for _ in 0..<count {
                // Keep the gap in the canopy up on the left open.
                var x = rng.range(-60, 1340)
                if layer > 0, x > 200, x < 560, rng.chance(0.8) { x = rng.range(600, 1340) }
                let y = 770 - Double(layer) * 22 - rng.range(0, 60 + Double(layer) * 40)
                let angle = rng.range(-2.6, -0.55)       // hanging down
                let length = rng.range(150, 300) - Double(layer) * 30
                ScenePaint.leaf(ctx, from: CGPoint(x: x, y: y), angle: angle, length: length, width: length * 0.2, bend: rng.range(-0.1, 0.1), color: ScenePaint.mix(UInt32(dark), UInt32(light), rng.unit()))
            }
        }
        // Big fronds arching in from the sides.
        for side in [-1.0, 1.0] {
            for i in 0..<4 {
                let base = CGPoint(x: side < 0 ? -30 : 1310, y: 470 + Double(i) * 62)
                ScenePaint.frond(ctx, base: base, angle: side < 0 ? 0.35 - Double(i) * 0.12 : .pi - 0.35 + Double(i) * 0.12, length: rng.range(300, 420), droop: 1.4,
                                 leaflets: 18, leafLength: 70, stem: ScenePaint.color(0x0F3A22), leafColor: ScenePaint.mix(0x14502E, 0x2F8A42, rng.unit()), highlight: ScenePaint.color(0x8CD060, 0.5))
            }
        }
    }

    /// Slanting shafts of sunlight from the gap in the canopy.
    private func paintShafts(_ ctx: CGContext) {
        var rng = ScenePaint.generator(505)
        for i in 0..<7 {
            let topX = 160 + Double(i) * 70 + rng.range(-30, 30)
            let width = rng.range(40, 120)
            let slant = rng.range(340, 520)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: topX, y: 730))
            path.addLine(to: CGPoint(x: topX + width, y: 730))
            path.addLine(to: CGPoint(x: topX + width + slant, y: 120))
            path.addLine(to: CGPoint(x: topX + slant - width * 0.3, y: 120))
            path.closeSubpath()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let strength = rng.range(0.10, 0.2)
            ctx.drawLinearGradient(ScenePaint.gradient([(0, ScenePaint.color(0xFFF8B0, strength)), (0.6, ScenePaint.color(0xE8F4A0, strength * 0.5)), (1, ScenePaint.color(0xE8F4A0, 0))]),
                                   start: CGPoint(x: topX, y: 730), end: CGPoint(x: topX + slant, y: 120), options: [])
            ctx.restoreGState()
        }
    }

    private func paintVignette(_ ctx: CGContext) {
        let g = ScenePaint.gradient([(0, ScenePaint.color(0x021008, 0)), (0.55, ScenePaint.color(0x021008, 0)), (1, ScenePaint.color(0x021008, 0.5))])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 400), startRadius: 0, endCenter: CGPoint(x: 640, y: 400), endRadius: 820, options: [.drawsAfterEndLocation])
    }

    // MARK: Things that move

    private func paintMist() -> [(layer: SceneLayer, speed: Double, offset: Double, alpha: Double)] {
        var out: [(layer: SceneLayer, speed: Double, offset: Double, alpha: Double)] = []
        let specs: [(y: Double, speed: Double, alpha: Double)] = [(262, 7, 0.40), (305, -5, 0.30), (205, 4, 0.24)]
        var rng = ScenePaint.generator(606)
        for spec in specs {
            let rect = CGRect(x: 0, y: spec.y - 50, width: 900, height: 100)
            if let layer = ScenePaint.layer(rect, { ctx in
                for _ in 0..<7 {
                    ScenePaint.blob(ctx, CGPoint(x: rng.range(260, 640), y: spec.y + rng.range(-12, 12)), rx: rng.range(130, 250), ry: rng.range(18, 36), ScenePaint.color(0xD8F0D0, 0.5), inner: 0.1)
                }
            }) { out.append((layer.faded(spec.alpha), spec.speed, rng.range(0, 1200), spec.alpha)) }
        }
        return out
    }

    /// Hanging vines for the front, each painted bent to several points of its sway, so that the sway is a copy. Bending is a shear
    /// below the point it hangs from.
    private func paintVines(_ range: Range<Int>) {
        let specs: [(x: Double, length: Double, parallax: Double)] = [(70, 380, 70), (150, 250, 60), (230, 170, 50), (1050, 200, 56), (1140, 330, 66), (1230, 440, 74)]
        for index in range where index < specs.count {
            let spec = specs[index]
            let frames = (0..<Self.swayFrames).compactMap { i -> CGImage? in
                let bend = (Double(i) / Double(Self.swayFrames - 1) - 0.5) * 0.2
                return ScenePaint.picture(width: 200, height: Int(spec.length) + 40) { ctx in
                    let top = spec.length + 20
                    ctx.translateBy(x: 100, y: CGFloat(top + 20))
                    ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: CGFloat(-bend), d: 1, tx: 0, ty: 0))
                    ctx.translateBy(x: -60, y: -CGFloat(top + 20))
                    var rng = ScenePaint.generator(UInt64(707 + index * 31))
                    ctx.setLineCap(.round)
                    for strand in 0..<2 {
                        let x = 60 + Double(strand) * 14 - 7
                        ctx.setStrokeColor(ScenePaint.color(0x0E2C18))
                        ctx.setLineWidth(CGFloat(4 - Double(strand)))
                        ctx.move(to: CGPoint(x: x, y: top))
                        ctx.addCurve(to: CGPoint(x: x + rng.range(-16, 16), y: top - spec.length * (0.8 + 0.2 * Double(strand))), control1: CGPoint(x: x + 14, y: top - spec.length * 0.3),
                                     control2: CGPoint(x: x - 16, y: top - spec.length * 0.6))
                        ctx.strokePath()
                    }
                    for k in 0..<12 {
                        let y = top - Double(k) * spec.length / 12.5
                        ScenePaint.leaf(ctx, from: CGPoint(x: 60 + sin(Double(k) * 1.4) * 10, y: y), angle: rng.chance(0.5) ? -0.5 - rng.range(0, 0.9) : -2.6 + rng.range(0, 0.9),
                                        length: rng.range(24, 46), width: 9, bend: 0.1, color: ScenePaint.mix(0x1B5A2E, 0x6CB848, rng.unit()))
                    }
                }
            }
            if frames.count == Self.swayFrames { vines.append((frames, spec.x, 720, Double(index) * 1.7, spec.parallax)) }
        }
    }

    /// A pair of big leaves at the bottom corners, bent to each point of their sway.
    private func paintCornerFronds() {
        for (x, flip) in [(0.0, 1.0), (1280.0, -1.0)] {
            let frames = (0..<Self.swayFrames).compactMap { i -> CGImage? in
                let bend = (Double(i) / Double(Self.swayFrames - 1) - 0.5) * 0.12
                return ScenePaint.picture(width: 420, height: 260) { ctx in
                    if flip < 0 { ctx.translateBy(x: 420, y: 0); ctx.scaleBy(x: -1, y: 1) }
                    ctx.translateBy(x: 20, y: 0)
                    ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: CGFloat(bend), d: 1, tx: 0, ty: 0))
                    var rng = ScenePaint.generator(UInt64(808 + Int(x)))
                    for k in 0..<5 {
                        ScenePaint.frond(ctx, base: CGPoint(x: 0, y: -10), angle: 0.25 + Double(k) * 0.26, length: rng.range(190, 320), droop: 0.9, leaflets: 14, leafLength: 56,
                                         stem: ScenePaint.color(0x0B2A18), leafColor: ScenePaint.mix(0x0F4A28, 0x2C8A40, rng.unit()), highlight: ScenePaint.color(0x7CC850, 0.5))
                    }
                }
            }
            if frames.count == Self.swayFrames { fronds.append((frames, x, -20, x > 0 ? 2.1 : 0.4)) }
        }
    }

    // MARK: Painting each frame

    func paintBackdrop(_ ctx: CGContext, frame: SceneFrame) {
        ctx.interpolationQuality = .low
        world?.draw(in: ctx, shift: frame.shift)
        drawFallingWater(ctx, time: frame.time, shift: frame.shift)
        for band in mist {
            let width = Double(band.layer.image.width)
            let travel = 1280 + width
            var x = (band.offset + frame.time * band.speed).truncatingRemainder(dividingBy: travel)
            if x < 0 { x += travel }
            var moved = band.layer
            moved.origin.x = CGFloat(x - width)
            moved.parallax = 18
            moved.draw(in: ctx, shift: frame.shift)
        }
        ctx.interpolationQuality = .high
    }

    /// Streaks running down the waterfall, and spray where it lands.
    private func drawFallingWater(_ ctx: CGContext, time: Double, shift: CGPoint) {
        let f = Self.fall
        let dx = Double(shift.x) * 12
        let path = CGMutablePath()
        for i in 0..<14 {
            let x = Double(f.x) - 34 + Double(i) * 5 + dx
            let run = (time * (180 + Double(i % 3) * 40) + Double(i) * 97).truncatingRemainder(dividingBy: 420)
            let top = 640 - run
            path.move(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x, y: max(Double(f.y), top - 50)))
        }
        ctx.setStrokeColor(ScenePaint.color(0xFFFFFF, 0.55))
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.setFillColor(ScenePaint.color(0xF4FFF8, 0.35))
        for i in 0..<6 {
            let k = (time * 0.8 + Double(i) / 6).truncatingRemainder(dividingBy: 1)
            let r = 6 + 16 * k
            ctx.fillEllipse(in: CGRect(x: Double(f.x) + dx - 40 + Double(i) * 16 - r, y: Double(f.y) + 4 + 20 * k - r * 0.6, width: r * 2, height: r * 1.2))
        }
    }

    func paintForeground(_ ctx: CGContext, frame: SceneFrame) {
        let t = frame.time
        func sway(_ phase: Double, _ rate: Double) -> Int {
            let s = 0.5 + 0.5 * (0.7 * sin(t * rate + phase) + 0.3 * sin(t * rate * 2.3 + phase * 2))
            return min(Self.swayFrames - 1, max(0, Int((s * Double(Self.swayFrames - 1)).rounded())))
        }
        for vine in vines {
            let image = vine.frames[sway(vine.phase, 0.9)]
            let x = (vine.x + Double(frame.shift.x) * vine.parallax - Double(image.width) / 2).rounded()
            ctx.draw(image, in: CGRect(x: x, y: CGFloat(720 - image.height + 14), width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        for frond in fronds {
            let image = frond.frames[sway(frond.phase, 0.7)]
            let x = (frond.x < 100 ? -20 + Double(frame.shift.x) * 40 : 1280 - Double(image.width) + 20 + Double(frame.shift.x) * 40).rounded()
            ctx.draw(image, in: CGRect(x: x, y: CGFloat(frond.y), width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        drawFallingLeaves(ctx, time: t, shift: frame.shift)
        // Fireflies and floating pollen in the light.
        if let glow = Sprites.dot(red: 0.85, green: 1, blue: 0.5) {
            for i in 0..<18 {
                let f = Double(i)
                let x = 80 + (f * 211.7).truncatingRemainder(dividingBy: 1120) + sin(t * 0.4 + f * 1.7) * 40
                let y = 90 + (f * 97.3).truncatingRemainder(dividingBy: 500) + cos(t * 0.5 + f) * 26
                let pulse = 0.5 + 0.5 * sin(t * (1.1 + Double(i % 4) * 0.4) + f * 2)
                ctx.stampDot(glow, at: CGPoint(x: (x + Double(frame.shift.x) * 20).rounded(), y: y.rounded()), radius: (2 + 4 * pulse).rounded(), alpha: 0.2 + 0.55 * pulse)
            }
        }
    }

    /// A few leaves twirling down through the light.
    private func drawFallingLeaves(_ ctx: CGContext, time: Double, shift: CGPoint) {
        for i in 0..<6 {
            let f = Double(i)
            let speed = 26 + f * 5
            let y = 760 - (time * speed + f * 157).truncatingRemainder(dividingBy: 820)
            let x = 120 + (f * 233).truncatingRemainder(dividingBy: 1040) + sin(time * 0.9 + f * 2) * 50 + Double(shift.x) * 30
            let spin = time * (1.3 + f * 0.2) + f
            let flip = cos(spin)
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(x), y: CGFloat(y))
            ctx.rotate(by: CGFloat(sin(spin * 0.7) * 0.8))
            ctx.scaleBy(x: CGFloat(max(0.15, abs(flip))), y: 1)
            ScenePaint.leaf(ctx, from: CGPoint(x: -9, y: 0), angle: 0, length: 18, width: 5, bend: 0.1, color: ScenePaint.color(flip > 0 ? 0x8AC04A : 0x5A9A3A, 0.95))
            ctx.restoreGState()
        }
    }

    // MARK: The animals

    private lazy var puppets: [String: ScenePuppet] = [
        "monkey": SceneMonkey(), "parrot": SceneBird(.parrot), "snake": SceneSnake(), "tiger": SceneBigCat(.tiger), "gorilla": SceneGorilla(),
        "frog": SceneFrog(), "butterfly": SceneButterfly(),
    ]

    func puppet(for index: Int) -> ScenePuppet? { puppets[cast.species[index].name] }
}
