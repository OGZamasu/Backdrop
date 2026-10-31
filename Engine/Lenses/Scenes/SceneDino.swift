import AppKit
import CoreGraphics
import Foundation

/// Who lives in the valley.
enum DinoCast {
    static var cast: SceneCast {
        var layout = SceneLayout()
        layout.farGround = 250
        layout.nearGround = 80
        layout.roamLow = 420
        layout.roamHigh = 660

        var trex = SceneSpecies(name: "t-rex", glyph: "", facesRight: true, height: 280, aspect: 1.15, speed: 100, temper: .brute, act: .roar,
                                home: 0.2, charge: 2.3, actSeconds: 2.8)
        trex.shout = "RAWR!"
        var raptor = SceneSpecies(name: "raptor", glyph: "", facesRight: true, height: 130, aspect: 0.99, speed: 170, temper: .prey, act: .hop,
                                  home: 0.2, charge: 2.4, actSeconds: 2.2, shout: "SKREE!")
        raptor.interest = 1.1
        let triceratops = SceneSpecies(name: "triceratops", glyph: "", facesRight: true, height: 175, aspect: 1.75, speed: 70, temper: .brute, act: .stomp,
                                       home: 0.2, charge: 1.9, actSeconds: 2.6, painted: true)
        let bronto = SceneSpecies(name: "brontosaurus", glyph: "", facesRight: true, height: 380, aspect: 1.0, speed: 38, temper: .prey, act: .lean,
                                  home: 0.3, farOnly: true, charge: 1.8, actSeconds: 3.4, shout: "💛")
        let ptero = SceneSpecies(name: "pterodactyl", glyph: "", facesRight: true, height: 84, aspect: 2.4, speed: 190, body: .flier, temper: .prey, act: .orbit,
                                 home: 0.3, charge: 1.5, actSeconds: 6, painted: true, band: 430...660, shout: "SKRAW!")
        var baby = SceneSpecies(name: "baby rex", glyph: "", facesRight: true, height: 130, aspect: 1.15, speed: 95, temper: .prey, act: .hop,
                                home: 0.8, charge: 1.8, actSeconds: 2.4, shout: "RAWR!")
        baby.interest = 1.2
        let lizard = SceneSpecies(name: "lizard", glyph: "", facesRight: true, height: 72, aspect: 0.99, speed: 110, gait: .hop, temper: .prey, act: .hop,
                                  home: 0.85, charge: 1.6, actSeconds: 2.0, shout: "♪")

        var species = [trex, raptor, triceratops, bronto, ptero, baby, lizard]
        for i in species.indices { species[i].painted = true }
        return SceneCast(species: species, roster: [0, 1, 1, 2, 3, 4, 4, 5, 6], layout: layout, cap: 9, visibleAtStart: 6)
    }
}

/// A prehistoric valley with a smoking volcano. A T-rex charges up and roars, raptors dart about, and pterodactyls wheel overhead.
final class DinoScene: SceneStyle {
    let cast = DinoCast.cast
    let look = SceneLook(haze: 0xE8B070, hazeAmount: 0.2, dusk: 0x3A2A3A, duskAmount: 0.2, warm: 0xFFB060, warmAmount: 0.14, shade: 0.3,
                         dust: 0xC8A878, shadow: 0.42, shadowLean: 0.2, water: 0xE8F6FF)
    let hint = "Wave your arms to scare the dinosaurs away!"

    private static let horizon = 300.0
    private static let crater = CGPoint(x: 1010, y: 560)

    private var world: SceneLayer?
    private var canvas: SceneCanvas?
    private var clouds: [(layer: SceneLayer, speed: Double, offset: Double)] = []
    private var fronds: [(frames: [CGImage], x: Double, parallax: Double, phase: Double)] = []
    private var ember: [CGImage] = []
    private static let swayFrames = 9

    private lazy var bakery = SceneBakery([
        { [unowned self] in canvas = SceneCanvas(CGRect(x: -48, y: 0, width: 1376, height: 720)); canvas?.paint { paintSky($0); paintMountains($0) } },
        { [unowned self] in canvas?.paint { paintVolcano($0); paintFarTrees($0) } },
        { [unowned self] in canvas?.paint { paintGround($0) } },
        { [unowned self] in canvas?.paint { paintPlants($0) } },
        { [unowned self] in canvas?.paint { paintFerns($0); paintVignette($0) }; world = canvas?.finish(parallax: 12); canvas = nil },
        { [unowned self] in clouds = paintClouds() },
        { [unowned self] in
            ember = (0..<4).compactMap { i in ScenePaint.picture(width: 240, height: 120) { ScenePaint.blob($0, CGPoint(x: 120, y: 60), rx: 120, ry: 60, ScenePaint.color(0xFF7A20, 0.2 + 0.1 * Double(i)), inner: 0.1) } }
        },
        { [unowned self] in paintFront(0) },
        { [unowned self] in paintFront(1) },
    ])

    func prepare(until deadline: Double) -> Bool { bakery.run(until: deadline) }

    // MARK: The valley

    private func paintSky(_ ctx: CGContext) {
        let rect = CGRect(x: -48, y: Self.horizon - 40, width: 1376, height: 720 - Self.horizon + 40)
        ScenePaint.fillDown(ctx, rect, [(0, ScenePaint.color(0x2A5A92)), (0.3, ScenePaint.color(0x4F8AB8)), (0.6, ScenePaint.color(0xE8B888)), (0.85, ScenePaint.color(0xF8B870)), (1, ScenePaint.color(0xFCD090))])
        ScenePaint.blob(ctx, CGPoint(x: 300, y: 420), rx: 560, ry: 300, ScenePaint.color(0xFFD890, 0.6))
        ScenePaint.blob(ctx, CGPoint(x: 300, y: 420), rx: 120, ry: 120, ScenePaint.color(0xFFF0C8, 0.95))
        ScenePaint.oval(ctx, CGPoint(x: 300, y: 420), rx: 42, ry: 42, ScenePaint.color(0xFFF8E0))
        // The ash that drifts out of the volcano, painted into the sky as a dark haze on the right.
        ScenePaint.blob(ctx, CGPoint(x: 1180, y: 640), rx: 520, ry: 220, ScenePaint.color(0x4A3A44, 0.6))
    }

    private func paintMountains(_ ctx: CGContext) {
        let h = Self.horizon
        let far = ScenePaint.ridgePath(width: 1376, left: -48, baseY: h + 70, bottom: h - 40, amplitude: 48, wavelength: 230, seed: 41)
        ctx.addPath(far); ctx.setFillColor(ScenePaint.color(0x9C7A98)); ctx.fillPath()
        let near = ScenePaint.ridgePath(width: 1376, left: -48, baseY: h + 36, bottom: h - 40, amplitude: 32, wavelength: 150, seed: 43)
        ctx.addPath(near); ctx.setFillColor(ScenePaint.color(0x7A5A7C)); ctx.fillPath()
        ScenePaint.fill(ctx, CGRect(x: -48, y: h - 40, width: 1376, height: 90), [(0, ScenePaint.color(0xF2B678, 0)), (0.6, ScenePaint.color(0xF2B678, 0.7)), (1, ScenePaint.color(0xF8C890, 1))],
                        from: CGPoint(x: 0, y: h + 50), to: CGPoint(x: 0, y: h - 6))
    }

    private func paintVolcano(_ ctx: CGContext) {
        let base = Self.horizon - 20, crater = Self.crater
        let left = 650.0, right = 1420.0
        let cone = CGMutablePath()
        cone.move(to: CGPoint(x: left, y: base))
        cone.addCurve(to: CGPoint(x: crater.x - 70, y: crater.y - 10), control1: CGPoint(x: left + 200, y: base + 40), control2: CGPoint(x: crater.x - 150, y: crater.y - 120))
        cone.addQuadCurve(to: CGPoint(x: crater.x + 70, y: crater.y - 10), control: CGPoint(x: crater.x, y: crater.y - 36))
        cone.addCurve(to: CGPoint(x: right, y: base), control1: CGPoint(x: crater.x + 150, y: crater.y - 120), control2: CGPoint(x: right - 220, y: base + 40))
        cone.closeSubpath()
        ctx.saveGState()
        ctx.addPath(cone)
        ctx.clip()
        ScenePaint.fillDown(ctx, CGRect(x: left, y: base, width: right - left, height: crater.y - base + 20), [(0, ScenePaint.color(0x6A4A52)), (0.5, ScenePaint.color(0x4A3440)), (1, ScenePaint.color(0x3A2A38))])
        // Lava running down the slopes.
        var rng = ScenePaint.generator(61)
        for i in 0..<7 {
            let dx = Double(i - 3) * 22 + rng.range(-8, 8)
            ctx.setStrokeColor(ScenePaint.color(0xFF6A18, 0.85))
            ctx.setLineWidth(CGFloat(rng.range(2.5, 5)))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: crater.x + dx * 0.3, y: crater.y - 20))
            ctx.addCurve(to: CGPoint(x: crater.x + dx * 2.6, y: crater.y - rng.range(130, 220)), control1: CGPoint(x: crater.x + dx, y: crater.y - 60), control2: CGPoint(x: crater.x + dx * 2.2 + rng.range(-20, 20), y: crater.y - 120))
            ctx.strokePath()
        }
        ScenePaint.blob(ctx, CGPoint(x: crater.x, y: crater.y - 150), rx: 190, ry: 140, ScenePaint.color(0xFF5A18, 0.25))
        ctx.restoreGState()
        // The glow at the lip of the crater, and the light on the cone's sunward edge.
        ScenePaint.blob(ctx, CGPoint(x: crater.x, y: crater.y), rx: 150, ry: 70, ScenePaint.color(0xFF8A30, 0.6))
        ScenePaint.oval(ctx, CGPoint(x: crater.x, y: crater.y - 14), rx: 62, ry: 12, ScenePaint.color(0xFFB040))
        ctx.setStrokeColor(ScenePaint.color(0xF0A060, 0.7))
        ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: left + 30, y: base + 6))
        ctx.addCurve(to: CGPoint(x: crater.x - 70, y: crater.y - 10), control1: CGPoint(x: left + 200, y: base + 44), control2: CGPoint(x: crater.x - 150, y: crater.y - 120))
        ctx.strokePath()
    }

    /// Tall araucarias and tree ferns along the horizon, small and blue with distance.
    private func paintFarTrees(_ ctx: CGContext) {
        var rng = ScenePaint.generator(71)
        let h = Self.horizon
        for i in 0..<22 {
            let x = -40 + Double(i) * 64 + rng.range(-20, 20)
            if x > 760, x < 1280 { continue }
            let s = rng.range(0.6, 1.1)
            ctx.setStrokeColor(ScenePaint.color(0x4A6A5A))
            ctx.setLineWidth(CGFloat(4 * s))
            ctx.move(to: CGPoint(x: x, y: h - 6)); ctx.addLine(to: CGPoint(x: x, y: h + 60 * s)); ctx.strokePath()
            for k in 0..<4 {
                ScenePaint.frond(ctx, base: CGPoint(x: x, y: h + 58 * s), angle: .pi / 2 + (Double(k) / 3 - 0.5) * 2.2, length: 46 * s, droop: 0.9, leaflets: 8, leafLength: 14 * s,
                                 stem: ScenePaint.color(0x4A6A5A), leafColor: ScenePaint.color(0x5E8A62), highlight: nil)
            }
        }
        // A mist hangs over the swamp.
        ScenePaint.blob(ctx, CGPoint(x: 260, y: h - 8), rx: 560, ry: 40, ScenePaint.color(0xF4DCA8, 0.55))
    }

    private func paintGround(_ ctx: CGContext) {
        let h = Self.horizon
        let rect = CGRect(x: -48, y: 0, width: 1376, height: h)
        ScenePaint.fillDown(ctx, rect, [(0, ScenePaint.color(0x9AB050)), (0.12, ScenePaint.color(0x6E9A3C)), (0.5, ScenePaint.color(0x44702E)), (1, ScenePaint.color(0x244A22))])
        var rng = ScenePaint.generator(81)
        ScenePaint.blob(ctx, CGPoint(x: 330, y: h - 14), rx: 520, ry: 60, ScenePaint.color(0xFFE6A0, 0.5))
        // A swamp pool with the sun in it.
        let pool = CGPoint(x: 250, y: 238)
        ScenePaint.oval(ctx, pool, rx: 240, ry: 28, ScenePaint.color(0x2C4A2C, 0.8))
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: pool.x - 226, y: pool.y - 22, width: 452, height: 44))
        ctx.clip()
        ScenePaint.fillDown(ctx, CGRect(x: pool.x - 226, y: pool.y - 22, width: 452, height: 44), [(0, ScenePaint.color(0xFFD890)), (0.5, ScenePaint.color(0x9AA860)), (1, ScenePaint.color(0x3A5A3A))])
        ctx.restoreGState()
        // Mud, moss and ferns, bigger toward the bottom of the picture.
        for _ in 0..<30 {
            let t = rng.unit()
            let y = h - 8 - pow(t, 1.4) * (h - 8)
            let s = 0.3 + 1.2 * pow(t, 1.3)
            ScenePaint.blob(ctx, CGPoint(x: rng.range(-40, 1320), y: y), rx: rng.range(50, 130) * s, ry: rng.range(5, 12) * s, rng.chance(0.5) ? ScenePaint.color(0x5A4A2A, 0.35) : ScenePaint.color(0xC8E060, 0.28))
        }
        let tones: [UInt32] = [0x5E9A34, 0x86BC48, 0x34622A, 0xB8D060, 0x6A5A32]
        for _ in 0..<1900 {
            let t = rng.unit()
            let y = h - 6 - pow(t, 1.3) * (h - 6)
            let s = 0.2 + 1.1 * pow(t, 1.2)
            ScenePaint.blade(ctx, at: CGPoint(x: rng.range(-40, 1320), y: y), height: rng.range(7, 20) * s, lean: rng.range(-5, 5) * s, width: max(0.8, 1.5 * s),
                             color: ScenePaint.color(tones[Int(rng.unit() * Double(tones.count))], rng.range(0.3, 0.7)))
        }
        // Rocks.
        for _ in 0..<8 {
            let t = rng.range(0.1, 0.9), x = rng.range(-20, 1300), y = 30 + t * 200, s = 0.4 + 0.9 * (1 - t)
            ScenePaint.oval(ctx, CGPoint(x: x, y: y), rx: 40 * s, ry: 20 * s, ScenePaint.color(0x3A3238))
            ScenePaint.oval(ctx, CGPoint(x: x + 6 * s, y: y + 6 * s), rx: 30 * s, ry: 12 * s, ScenePaint.color(0x8A7A78, 0.7))
        }
    }

    /// Tree ferns and cycads in the middle distance, left and right, leaving the middle clear, and ferns in the foreground.
    private func paintPlants(_ ctx: CGContext) {
        var rng = ScenePaint.generator(83)
        for _ in 0..<10 {
            let x = rng.chance(0.55) ? rng.range(-30, 330) : rng.range(930, 1320)
            let y = rng.range(150, 260), s = 0.5 + 0.7 * (1 - y / 280)
            cycad(ctx, base: CGPoint(x: x, y: y), scale: s, rng: &rng)
        }
    }

    /// Ferns in the foreground of the valley floor.
    private func paintFerns(_ ctx: CGContext) {
        var rng = ScenePaint.generator(87)
        for _ in 0..<12 {
            let x = rng.range(-30, 1320), y = rng.range(30, 230), s = 0.4 + 0.9 * (1 - y / 280)
            for i in 0..<7 {
                ScenePaint.frond(ctx, base: CGPoint(x: x, y: y), angle: .pi / 2 + (Double(i) / 6 - 0.5) * 2.2 + rng.range(-0.1, 0.1), length: 70 * s * rng.range(0.7, 1.1), droop: 1.1, leaflets: 11, leafLength: 20 * s,
                                 stem: ScenePaint.color(0x2A5A28), leafColor: ScenePaint.mix(0x3A8A36, 0x7CC048, rng.unit()), highlight: nil)
            }
        }
    }

    private func cycad(_ ctx: CGContext, base: CGPoint, scale s: Double, rng: inout SceneRandom) {
        let height = 110 * s
        ctx.setStrokeColor(ScenePaint.color(0x3A2E26))
        ctx.setLineWidth(CGFloat(14 * s))
        ctx.setLineCap(.round)
        ctx.move(to: base); ctx.addQuadCurve(to: CGPoint(x: base.x + rng.range(-10, 10), y: base.y + height), control: CGPoint(x: base.x + 8, y: base.y + height * 0.5)); ctx.strokePath()
        let top = CGPoint(x: base.x, y: base.y + height)
        for i in 0..<9 {
            ScenePaint.frond(ctx, base: top, angle: .pi / 2 + (Double(i) / 8 - 0.5) * 3.0, length: 120 * s, droop: 1.3, leaflets: 14, leafLength: 34 * s,
                             stem: ScenePaint.color(0x1F4A24), leafColor: ScenePaint.mix(0x2C7A36, 0x68B848, rng.unit()), highlight: ScenePaint.color(0xA8DC70, 0.4))
        }
    }

    private func paintVignette(_ ctx: CGContext) {
        let g = ScenePaint.gradient([(0, ScenePaint.color(0x1A1020, 0)), (0.6, ScenePaint.color(0x1A1020, 0)), (1, ScenePaint.color(0x1A1020, 0.4))])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 640, y: 380), startRadius: 0, endCenter: CGPoint(x: 640, y: 380), endRadius: 800, options: [.drawsAfterEndLocation])
    }

    // MARK: Things that move

    private func paintClouds() -> [(layer: SceneLayer, speed: Double, offset: Double)] {
        var out: [(layer: SceneLayer, speed: Double, offset: Double)] = []
        var rng = ScenePaint.generator(91)
        let specs: [(y: Double, w: Double, h: Double, speed: Double)] = [(560, 520, 70, 4), (640, 460, 56, 3), (480, 560, 60, 6), (610, 360, 44, 2.5)]
        for spec in specs {
            let rect = CGRect(x: 0, y: spec.y, width: spec.w, height: spec.h)
            if let layer = ScenePaint.layer(rect, { ctx in
                for _ in 0..<16 {
                    let c = CGPoint(x: rng.range(spec.w * 0.3, spec.w * 0.7), y: spec.y + spec.h * rng.range(0.4, 0.6))
                    let rx = rng.range(spec.w * 0.08, spec.w * 0.2), ry = rng.range(spec.h * 0.12, spec.h * 0.26)
                    ScenePaint.blob(ctx, c, rx: rx, ry: ry, ScenePaint.color(0xD8B0A0, 0.5), inner: 0.2)
                    ScenePaint.blob(ctx, CGPoint(x: c.x, y: c.y - ry * 0.4), rx: rx * 0.85, ry: ry * 0.45, ScenePaint.color(0xFFD8A0, 0.6), inner: 0.1)
                }
            }) { out.append((layer.faded(0.8), spec.speed, rng.range(0, 1280))) }
        }
        return out
    }

    /// Big fronds at the bottom corners, painted bent to each point of their sway.
    private func paintFront(_ index: Int) {
        let (x, flip) = index == 0 ? (0.0, 1.0) : (1280.0, -1.0)
        let frames = (0..<Self.swayFrames).compactMap { i -> CGImage? in
            let bend = (Double(i) / Double(Self.swayFrames - 1) - 0.5) * 0.12
            return ScenePaint.picture(width: 440, height: 280) { ctx in
                if flip < 0 { ctx.translateBy(x: 440, y: 0); ctx.scaleBy(x: -1, y: 1) }
                ctx.translateBy(x: 20, y: 0)
                ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: CGFloat(bend), d: 1, tx: 0, ty: 0))
                var rng = ScenePaint.generator(UInt64(95 + index * 7))
                for k in 0..<6 {
                    ScenePaint.frond(ctx, base: CGPoint(x: 0, y: -10), angle: 0.2 + Double(k) * 0.24, length: rng.range(200, 340), droop: 0.9, leaflets: 15, leafLength: 58,
                                     stem: ScenePaint.color(0x143A1C), leafColor: ScenePaint.mix(0x1C5A2C, 0x3E9A3E, rng.unit()), highlight: ScenePaint.color(0x9CD860, 0.5))
                }
            }
        }
        if frames.count == Self.swayFrames { fronds.append((frames, x, 40, Double(index) * 2.3)) }
    }

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
        drawVolcanoLife(ctx, time: frame.time, shift: frame.shift)
        drawFlock(ctx, time: frame.time, shift: frame.shift)
        drawDragonflies(ctx, time: frame.time, shift: frame.shift)
        ctx.interpolationQuality = .high
    }

    /// Smoke rolling up out of the crater, and the glow of the lava breathing.
    private func drawVolcanoLife(_ ctx: CGContext, time: Double, shift: CGPoint) {
        let crater = CGPoint(x: Self.crater.x + Double(shift.x) * 12, y: Self.crater.y)
        if ember.count == 4 {
            let level = min(3, max(0, Int((0.5 + 0.5 * sin(time * 1.7)) * 3.99)))
            ctx.draw(ember[level], in: CGRect(x: (crater.x - 120).rounded(), y: crater.y - 60, width: 240, height: 120))
        }
        for i in 0..<14 {
            let age = ((time * 0.16 + Double(i) / 14).truncatingRemainder(dividingBy: 1))
            let sway = sin(age * 5 + Double(i)) * 14
            let x = crater.x + age * 240 + sway - 20
            let y = crater.y + 10 + age * 330
            let r = 22 + age * 80
            let fade = sin(min(1, age * 1.15) * .pi) * 0.5
            ctx.setFillColor(CGColor(red: 0.30, green: 0.24, blue: 0.27, alpha: CGFloat(fade * 0.8)))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.8, width: r * 2, height: r * 1.6))
            ctx.setFillColor(CGColor(red: 0.55, green: 0.38, blue: 0.30, alpha: CGFloat(fade * (1 - age) * 0.45)))
            ctx.fillEllipse(in: CGRect(x: x - r * 0.5 - 6, y: y - r * 0.2 - 4, width: r, height: r * 0.8))
        }
        // Sparks thrown from the crater.
        ctx.setFillColor(CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 0.9))
        for i in 0..<10 {
            let age = ((time * 0.7 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1))
            let x = crater.x + (Double(i) - 4.5) * 14 * age * 3
            let y = crater.y + 20 + sin(age * .pi) * (80 + Double(i % 3) * 50) - age * age * 40
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: 3.2 * (1 - age) + 1, height: 3.2 * (1 - age) + 1))
        }
    }

    /// A few pterosaurs, tiny with distance, crossing the sun now and then.
    private func drawFlock(_ ctx: CGContext, time: Double, shift: CGPoint) {
        let period = 38.0, crossing = 20.0
        let t = time.truncatingRemainder(dividingBy: period)
        guard t < crossing else { return }
        let k = t / crossing
        ctx.setStrokeColor(ScenePaint.color(0x3A2A34, 0.8))
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        for i in 0..<5 {
            let x = -60 + k * 1450 - Double(i) * 46 + Double(shift.x) * 5
            let y = 560 + Double(i % 3) * 22 + sin(k * 7 + Double(i)) * 10
            let flap = sin(time * 4 + Double(i) * 1.1) * 0.5
            let span = 15.0
            ctx.move(to: CGPoint(x: x - span, y: y + flap * span))
            ctx.addLine(to: CGPoint(x: x - span * 0.35, y: y + span * 0.2 + flap * span * 0.4))
            ctx.addLine(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + span * 0.35, y: y + span * 0.2 + flap * span * 0.4))
            ctx.addLine(to: CGPoint(x: x + span, y: y + flap * span))
            ctx.strokePath()
        }
    }

    /// Two dragonflies darting about over the swamp pool, stopping and starting.
    private func drawDragonflies(_ ctx: CGContext, time: Double, shift: CGPoint) {
        for i in 0..<2 {
            let f = Double(i)
            let hop = floor(time * 0.8 + f * 0.5)
            let k = SceneRig.ease((time * 0.8 + f * 0.5) - hop)
            let a = CGPoint(x: 150 + ScenePaint.noise(hop, 3 + f) * 220, y: 250 + ScenePaint.noise(hop, 7 + f) * 60)
            let b = CGPoint(x: 150 + ScenePaint.noise(hop + 1, 3 + f) * 220, y: 250 + ScenePaint.noise(hop + 1, 7 + f) * 60)
            let x = Double(a.x) + Double(b.x - a.x) * k + Double(shift.x) * 10, y = Double(a.y) + Double(b.y - a.y) * k
            ctx.setStrokeColor(ScenePaint.color(0x2A4A6A, 0.9))
            ctx.setLineWidth(2)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: x - 7, y: y)); ctx.addLine(to: CGPoint(x: x + 5, y: y)); ctx.strokePath()
            let flap = sin(time * 60 + f) * 3
            ctx.setFillColor(ScenePaint.color(0xD8F0FF, 0.55))
            ctx.fillEllipse(in: CGRect(x: x - 4, y: y + 0.5, width: 6, height: 3 + flap))
            ctx.fillEllipse(in: CGRect(x: x - 4, y: y - 3.5 - flap, width: 6, height: 3 + flap))
        }
    }

    func paintForeground(_ ctx: CGContext, frame: SceneFrame) {
        let t = frame.time
        for frond in fronds {
            let s = 0.5 + 0.5 * (0.7 * sin(t * 0.8 + frond.phase) + 0.3 * sin(t * 1.9 + frond.phase * 2))
            let image = frond.frames[min(Self.swayFrames - 1, max(0, Int((s * Double(Self.swayFrames - 1)).rounded())))]
            let x = (frond.x < 100 ? -20 + Double(frame.shift.x) * frond.parallax : 1280 - Double(image.width) + 20 + Double(frame.shift.x) * frond.parallax).rounded()
            ctx.draw(image, in: CGRect(x: x, y: -26, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        // Ash falling, and a few embers rising on the heat.
        ctx.setFillColor(CGColor(red: 0.35, green: 0.3, blue: 0.3, alpha: 0.55))
        for i in 0..<30 {
            let f = Double(i)
            let x = (f * 149.3 + t * (14 + Double(i % 4) * 5)).truncatingRemainder(dividingBy: 1340) - 30
            let y = 730 - (t * (22 + Double(i % 5) * 8) + f * 71).truncatingRemainder(dividingBy: 760)
            ctx.fill(CGRect(x: x + Double(frame.shift.x) * 20, y: y, width: 2 + Double(i % 3), height: 2))
        }
    }

    // MARK: The animals

    private lazy var puppets: [String: ScenePuppet] = [
        "t-rex": SceneTheropod(.trex), "raptor": SceneTheropod(.raptor), "triceratops": SceneTriceratops(), "brontosaurus": SceneSauropod(),
        "pterodactyl": SceneMembrane(.pterodactyl), "baby rex": SceneTheropod(.baby), "lizard": SceneTheropod(.compy),
    ]

    func puppet(for index: Int) -> ScenePuppet? { puppets[cast.species[index].name] }
}
