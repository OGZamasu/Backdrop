import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Adds pictures together, each scaled by its weight (all on the GPU).
private func backdropBlend(_ parts: [(CIImage, Double)], extent: CGRect) -> CIImage {
    var total: CIImage?
    for (image, w) in parts {
        let scaled = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: w, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: w, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: w, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        total = total.map { scaled.applyingFilter("CILinearDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: $0]) } ?? scaled
    }
    return (total ?? CIImage(color: .black)).cropped(to: extent)
}

// MARK: - Liquid marble

/// Deep green marble with veins of gold and cloudy white, flowing very slowly, polished to a soft sheen.
///
/// The veins are levels of a smooth field (noise, bent by more noise, plus a gentle slope so they run diagonally),
/// coloured through a table with thin gold lines and broader white clouds in it. All on the GPU, all from the clock.
final class BackdropLiquidMarble: BackdropScene {
    typealias RGB = BackdropRGB
    private var table: CIImage?

    override func paint() -> CIImage? {
        // The polish: only a soft sheen across the upper left, laid over the moving stone each frame.
        BackdropPainter.paint(width: 320, height: 180) { ctx in
            ctx.setFillColor(RGB(0, 0, 0).cg); ctx.fill(BackdropPainter.frame)
            BackdropPainter.glow(ctx, at: CGPoint(x: 260, y: 640), radius: 760, color: RGB(1, 1, 1), alpha: 0.14, squash: 0.6)
        }
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        if table == nil { table = Self.makeTable() }
        guard let table else { return nil }
        let frame = BackdropPainter.frame
        let slope = CIFilter.linearGradient()
        slope.point0 = CGPoint(x: 0, y: 720); slope.point1 = CGPoint(x: 1280, y: 0)
        slope.color0 = CIColor(red: 0, green: 0, blue: 0)
        slope.color1 = CIColor(red: 1, green: 1, blue: 1, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? BackdropCanvas.space) ?? CIColor(red: 1, green: 1, blue: 1)
        let diagonal = slope.outputImage?.cropped(to: frame) ?? CIImage(color: .gray).cropped(to: frame)
        let flow = BackdropNoise.field(0, scale: 3.6, offset: CGPoint(x: -time * 3.2, y: time * 2.1), extent: frame)
        let bend = BackdropNoise.field(1, scale: 8.5, offset: CGPoint(x: time * 2.4, y: -time * 1.3), extent: frame)
        let fine = BackdropNoise.field(2, scale: 1.9, offset: CGPoint(x: time * 1.5, y: time * 4), extent: frame)
        // Mostly the diagonal slope, so the veins run across the stone in long bands; the noise bends and frays them.
        let field = backdropBlend([(diagonal, 0.56), (flow, 0.24), (bend, 0.14), (fine, 0.06)], extent: frame)
        let stone = BackdropInk.colored(field, table)
        let polished = still.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: stone]).cropped(to: frame)
        return BackdropFinish.finish(BackdropFinish.vignette(polished, strength: 0.25), grain: 0.6)
    }

    /// Deep green stone, its colour drifting slowly through darker and lighter, crossed by many fine gold veins and a few
    /// soft white ones. The field only spans part of the table across the frame, so the pattern repeats often enough to
    /// read as many veins.
    private static func makeTable() -> CIImage {
        let deep = RGB(hex: 0x0A1C17), stone = RGB(hex: 0x15382E), light = RGB(hex: 0x1F4A3B)
        let gold = RGB(hex: 0xE2BE68), white = RGB(hex: 0xE4E2D6)
        var stops: [(at: Double, color: RGB, alpha: Double)] = []
        let bands = 9
        for k in 0..<bands {
            let a = Double(k) / Double(bands), span = 1 / Double(bands)
            let base = k % 3 == 0 ? deep : (k % 3 == 1 ? stone : light)
            let next = (k + 1) % 3 == 0 ? deep : ((k + 1) % 3 == 1 ? stone : light)
            stops.append((a, base, 1))
            // A hairline of gold through each band, and in every third a broad, soft white vein beside it.
            let v = a + span * 0.62
            stops += [(v - 0.0035, base.mixed(next, 0.6), 1), (v, gold, 1), (v + 0.0035, base.mixed(next, 0.62), 1)]
            if k % 3 == 1 {
                let w = a + span * 0.3
                stops += [(w - 0.018, base.mixed(next, 0.3), 1), (w - 0.004, white.mixed(base, 0.3), 1), (w, white, 1), (w + 0.006, white.mixed(base, 0.45), 1), (w + 0.02, base.mixed(next, 0.35), 1)]
            }
        }
        stops.append((1, deep, 1))
        var cleaned: [(at: Double, color: RGB, alpha: Double)] = []
        for s in stops.sorted(by: { $0.at < $1.at }) where cleaned.last.map({ s.at - $0.at > 0.0005 }) ?? true { cleaned.append(s) }
        return BackdropInk.table(cleaned)
    }
}

// MARK: - Northern lights

/// Curtains of green and violet light rippling over a snowy ridge and a line of pines, under a sky full of stars.
final class BackdropNorthernLights: BackdropScene {
    typealias RGB = BackdropRGB
    private var sky: CIImage?
    private var land: CIImage?
    private var colours: CIImage?
    private var profile: CIImage?
    private var patchTable: CIImage?

    override func paint() -> CIImage? {
        sky = BackdropBake.flatten(BackdropPainter.paint { ctx in
            BackdropPainter.vertical(ctx, BackdropPainter.frame, [(at: 0, color: RGB(hex: 0x0D2A3A)), (at: 0.35, color: RGB(hex: 0x081A2C)), (at: 1, color: RGB(hex: 0x02060F))])
            var rng = SplitMix64(seed: 0xA020)
            for _ in 0..<260 {
                let p = CGPoint(x: .random(in: 0..<1280, using: &rng), y: .random(in: 200..<720, using: &rng))
                let r = CGFloat.random(in: 0.45...1.3, using: &rng)
                ctx.setFillColor(RGB(0.9, 0.95, 1).cg(Double.random(in: 0.2...0.85, using: &rng) * Double(min(1, (p.y - 180) / 300))))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        }.map { BackdropFinish.finish($0, grain: 0.5) })
        land = BackdropBake.flatten(BackdropPainter.paint { ctx in
            // A snowy ridge, lit faintly green by the sky, and a line of pines in front.
            let ridge = BackdropPainter.ridgeLine(base: 150, height: 120, seed: 4.2, wavelength: 300, rough: 0.6, step: 5)
            BackdropPainter.fill(ctx, BackdropPainter.ridge(ridge, floor: -10), gradient: [(at: 0, color: RGB(hex: 0x1B2E3C)), (at: 1, color: RGB(hex: 0x6F9AA6))],
                                 from: CGPoint(x: 0, y: 150), to: CGPoint(x: 0, y: 270))
            var rng = SplitMix64(seed: 0xA021)
            for _ in 0..<42 {
                var x = CGFloat.random(in: -20...1300, using: &rng)
                if x > 470 && x < 810 { x = x < 640 ? x - 220 : x + 220 }
                BackdropLandscape.pine(ctx, x: x, base: 60, height: CGFloat.random(in: 90...230, using: &rng), color: RGB(hex: 0x050B12).cg, rng: &rng)
            }
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: 70), [(at: 0, color: RGB(hex: 0x3E525C)), (at: 1, color: RGB(hex: 0x667F8A))])
            ctx.setFillColor(RGB(hex: 0x050B12).cg); ctx.fill(CGRect(x: 0, y: 66, width: 1280, height: 6))
        })
        // Height up the sky, as a plain number: 0 at 300 pixels, 1 at the top.
        let height = CIFilter.linearGradient()
        height.point0 = CGPoint(x: 0, y: 330); height.point1 = CGPoint(x: 0, y: 720)
        // Linear colours, so the numbers arrive as they are and are not taken for display values.
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? BackdropCanvas.space
        height.color0 = CIColor(red: 0.5, green: 0.5, blue: 0.5, colorSpace: linear) ?? CIColor(red: 0.5, green: 0.5, blue: 0.5)
        height.color1 = CIColor(red: 1.5, green: 1.5, blue: 1.5, colorSpace: linear) ?? CIColor(red: 1, green: 1, blue: 1)
        colours = height.outputImage?.cropped(to: BackdropPainter.frame)
        // The curtain by how far above its foot a point is: nothing below, a bright green foot, then teal and violet rays
        // fading upward.
        profile = BackdropInk.table([
            (at: 0, color: RGB(0, 0, 0), alpha: 1), (at: 0.5, color: RGB(0, 0, 0), alpha: 1), (at: 0.515, color: RGB(0.3, 1, 0.62), alpha: 1),
            (at: 0.6, color: RGB(0.2, 0.8, 0.6), alpha: 1), (at: 0.75, color: RGB(0.25, 0.45, 0.62), alpha: 1), (at: 0.92, color: RGB(0.3, 0.12, 0.38), alpha: 1),
            (at: 1, color: RGB(0, 0, 0), alpha: 1),
        ])
        patchTable = BackdropInk.table([(at: 0, color: RGB(0.05, 0.05, 0.05)), (at: 0.3, color: RGB(0.1, 0.1, 0.1)), (at: 0.72, color: RGB(1, 1, 1)), (at: 1, color: RGB(1, 1, 1))])
        guard let sky, let land else { return nil }
        return land.composited(over: sky)
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        guard let sky, let land, let colours, let profile, let patchTable else { return still }
        let frame = BackdropPainter.frame
        // All worked out at half size (the light is soft) and enlarged at the end.
        let half = BackdropPainter.half
        let heights = colours.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)).cropped(to: half)
        // Where the curtain's foot hangs, column by column: a slow wave across the sky (noise so tall it only changes across).
        let foot = BackdropNoise.field(1, scale: 3, offset: CGPoint(x: time * 4, y: 0), stretch: 60, extent: half)
        // How far above its foot each point is: height minus foot (shifted so the foot sits at 0.5 in the colour table).
        let above = backdropBlend([(heights, 1), (foot, -0.7)], extent: half)
        let curtain = BackdropInk.colored(above, profile)
        // Rays: noise stretched so tall it only changes across, drifting sideways; a slower one varies their strength.
        let rays = BackdropNoise.field(0, scale: 0.9, offset: CGPoint(x: time * 5.5, y: 0), stretch: 60, extent: half)
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.6, kCIInputBrightnessKey: -0.08])
        let patch = BackdropInk.colored(BackdropNoise.field(1, scale: 4, offset: CGPoint(x: -time * 4.5, y: 0), stretch: 30, extent: half), patchTable)
        let lightHalf = curtain
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: rays])
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: patch]).cropped(to: half)
        let light = BackdropPainter.enlarged(lightHalf)
        let glow = lightHalf.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)).clampedToExtent().applyingGaussianBlur(sigma: 6)
            .transformed(by: CGAffineTransform(scaleX: 4, y: 4)).cropped(to: frame)
        let aurora = backdropBlend([(light, 1.0), (glow, 0.8)], extent: frame)
        let lit = aurora.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: sky]).cropped(to: frame)
        return BackdropFinish.finish(land.composited(over: lit))
    }
}

// MARK: - Topographic

/// A contour map drifting slowly: fine pale lines on deep navy, every fifth one stronger, with a faint tint by height.
final class BackdropTopographic: BackdropScene {
    typealias RGB = BackdropRGB
    private var lines: CIImage?
    private var tint: CIImage?

    override func paint() -> CIImage? {
        let navy = RGB(hex: 0x0F1E33)
        var stops: [(at: Double, color: RGB, alpha: Double)] = []
        let count = 16
        for k in 0...count {
            let v = Double(k) / Double(count)
            let index = k % 5 == 0
            let w = index ? 0.0055 : 0.0035
            let ink = index ? RGB(hex: 0xF2D9A6) : RGB(hex: 0x9FC3D6)
            stops += [(max(0, v - w), ink, 0), (v, ink, index ? 0.95 : 0.6), (min(1, v + w), ink, 0)]
        }
        var cleaned: [(at: Double, color: RGB, alpha: Double)] = []
        for s in stops.sorted(by: { $0.at < $1.at }) where cleaned.last.map({ s.at - $0.at > 0.0005 }) ?? true { cleaned.append(s) }
        lines = BackdropInk.table(cleaned)
        tint = BackdropInk.table([(at: 0, color: navy.scaled(0.7)), (at: 0.5, color: navy), (at: 1, color: RGB(hex: 0x1D3550))])
        return BackdropPainter.paint(width: 64, height: 36) { ctx in ctx.setFillColor(navy.cg); ctx.fill(BackdropPainter.frame) }
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        guard let lines, let tint else { return still }
        let frame = BackdropPainter.frame
        let ground = BackdropNoise.field(0, scale: 6.5, offset: CGPoint(x: time * 2.2, y: time * 1.1), extent: frame)
        let detail = BackdropNoise.field(1, scale: 3.1, offset: CGPoint(x: -time * 1.4, y: time * 0.8), extent: frame)
        let height = backdropBlend([(ground, 0.86), (detail, 0.14)], extent: frame)
        let map = BackdropInk.colored(height, lines).composited(over: BackdropInk.colored(height, tint))
        return BackdropFinish.finish(BackdropFinish.vignette(map, strength: 0.3), grain: 0.6)
    }
}

// MARK: - Low poly

/// A landscape of facets: a jittered mesh of triangles over gentle hills, each triangle shaded by how it faces the light,
/// coloured from deep teal through violet to a warm glow. A still.
final class BackdropLowPoly: BackdropScene {
    typealias RGB = BackdropRGB

    override func paint() -> CIImage? {
        BackdropPainter.paint { ctx in
            let cols = 20, rows = 12
            var rng = SplitMix64(seed: 0x10F0)
            var points: [[SIMD3<Double>]] = []
            for j in 0...rows {
                var row: [SIMD3<Double>] = []
                for i in 0...cols {
                    let edgeX = i == 0 || i == cols, edgeY = j == 0 || j == rows
                    let x = Double(i) / Double(cols) * 1280 + (edgeX ? 0 : .random(in: -24...24, using: &rng))
                    let y = Double(j) / Double(rows) * 720 + (edgeY ? 0 : .random(in: -20...20, using: &rng))
                    let z = 90 * BackdropNoise.ridge(x / 260, seed: 2.1) + 70 * BackdropNoise.ridge(y / 190 + x / 600, seed: 5.3)
                    row.append(SIMD3(x, y, z))
                }
                points.append(row)
            }
            let light = simd_normalize(SIMD3<Double>(-0.55, 0.6, 0.6))
            let palette = [RGB(hex: 0x0C2F3F), RGB(hex: 0x1F4E6B), RGB(hex: 0x4A3B86), RGB(hex: 0x8A4A8E), RGB(hex: 0xD86A72)]
            func colour(at p: SIMD3<Double>) -> RGB {
                // Diagonal: deep teal at the lower left to warm coral at the upper right.
                let t = min(1, max(0, (p.x / 1280 * 0.55 + p.y / 720 * 0.45)))
                let scaled = t * Double(palette.count - 1)
                let k = min(palette.count - 2, Int(scaled))
                return palette[k].mixed(palette[k + 1], scaled - Double(k))
            }
            ctx.setLineJoin(.round)
            for j in 0..<rows {
                for i in 0..<cols {
                    let a = points[j][i], b = points[j][i + 1], c = points[j + 1][i], d = points[j + 1][i + 1]
                    let tris = (i + j) % 2 == 0 ? [[a, b, d], [a, d, c]] : [[a, b, c], [b, d, c]]
                    for t in tris {
                        let n = simd_normalize(simd_cross(t[1] - t[0], t[2] - t[0]))
                        let facing = max(0, simd_dot(n.z < 0 ? -n : n, light))
                        let centre = (t[0] + t[1] + t[2]) / 3
                        let base = colour(at: centre)
                        // Pull the middle down a little, where a head sits, so the face stands out.
                        let calm = 1 - 0.18 * exp(-pow((centre.x - 640) / 300, 2) - pow((centre.y - 420) / 220, 2))
                        let shade = base.scaled((0.62 + 0.55 * facing) * calm)
                        let path = CGMutablePath()
                        path.addLines(between: t.map { CGPoint(x: $0.x, y: $0.y) })
                        path.closeSubpath()
                        ctx.addPath(path)
                        ctx.setFillColor(shade.cg)
                        ctx.setStrokeColor(shade.mixed(RGB(1, 1, 1), 0.08).cg)
                        ctx.setLineWidth(0.8)
                        ctx.drawPath(using: .fillStroke)
                    }
                }
            }
        }.map { BackdropFinish.finish(BackdropFinish.vignette($0, strength: 0.2), grain: 0.5) }
    }
}

// MARK: - Vaporwave

/// Pastel dusk: a striped sun, palms, a pink and violet sky, a chequered floor rolling toward you and two wireframe
/// shapes turning slowly in the air.
final class BackdropVaporwave: BackdropScene {
    typealias RGB = BackdropRGB
    private static let horizon: CGFloat = 300
    private var canvas: BackdropCanvas?

    override func paint() -> CIImage? {
        BackdropPainter.paint { ctx in
            let h = Self.horizon
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: h, width: 1280, height: 720 - h), [
                (at: 0, color: RGB(hex: 0xFF9ED8)), (at: 0.3, color: RGB(hex: 0xC77DDB)), (at: 0.7, color: RGB(hex: 0x5A4BB0)), (at: 1, color: RGB(hex: 0x241A5C)),
            ])
            // The sun, pastel and sliced.
            let c = CGPoint(x: 880, y: h + 140), r: CGFloat = 140
            BackdropPainter.glow(ctx, at: c, radius: r * 2.2, color: RGB(hex: 0xFFC2E8), alpha: 0.45, blend: .screen)
            ctx.saveGState()
            let disc = CGMutablePath()
            disc.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            var y = c.y - r * 0.05, gap: CGFloat = 4
            while y > c.y - r { disc.addRect(CGRect(x: c.x - r - 2, y: y - gap, width: r * 2 + 4, height: gap)); y -= gap + 14; gap += 3 }
            ctx.addPath(disc); ctx.clip(using: .evenOdd)
            BackdropPainter.vertical(ctx, CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), [(at: 0, color: RGB(hex: 0xFF71CE)), (at: 1, color: RGB(hex: 0xFFF6A8))])
            ctx.restoreGState()
            // Palms on both sides.
            for (x, lean) in [(CGFloat(120), CGFloat(1)), (1170, -1)] {
                let top = CGPoint(x: x + lean * 60, y: h + 330)
                ctx.move(to: CGPoint(x: x, y: h)); ctx.addQuadCurve(to: top, control: CGPoint(x: x - lean * 10, y: h + 200))
                ctx.setStrokeColor(RGB(hex: 0x2A1650).cg); ctx.setLineWidth(14); ctx.strokePath()
                for k in 0..<8 {
                    let a = Double(k) * 0.8 + 0.2
                    let tip = CGPoint(x: top.x + cos(a) * 150, y: top.y + sin(a) * 60 - 50)
                    ctx.move(to: top); ctx.addQuadCurve(to: tip, control: CGPoint(x: top.x + cos(a) * 80, y: top.y + sin(a) * 60 + 30))
                    ctx.setStrokeColor(RGB(hex: 0x2A1650).cg); ctx.setLineWidth(9); ctx.strokePath()
                }
            }
            BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: h), [(at: 0, color: RGB(hex: 0x12082A)), (at: 1, color: RGB(hex: 0x3A1E6A))])
        }.map { BackdropFinish.finish($0, grain: 0.7) }
    }

    override func animate(_ still: CIImage, at time: Double) -> CIImage? {
        let frame = BackdropPainter.frame
        let h = Self.horizon
        // The floor: a chequerboard laid in perspective, slid toward you a square at a time.
        let squares: CGFloat = 80
        let board = CIFilter.checkerboardGenerator()
        board.color0 = CIColor(red: 0.78, green: 0.30, blue: 0.72)
        board.color1 = CIColor(red: 0.07, green: 0.03, blue: 0.18)
        board.width = Float(squares)
        board.sharpness = 0.9
        board.center = CGPoint(x: 0, y: -CGFloat(BackdropMath.fract(time * 0.35)) * squares * 2)
        let plane = (board.outputImage ?? CIImage(color: .black)).cropped(to: CGRect(x: 0, y: 0, width: squares * 24, height: squares * 14))
        let floor = CIFilter.perspectiveTransform()
        floor.inputImage = plane
        floor.bottomLeft = CGPoint(x: -1500, y: -120)
        floor.bottomRight = CGPoint(x: 2780, y: -120)
        floor.topLeft = CGPoint(x: 340, y: h)
        floor.topRight = CGPoint(x: 940, y: h)
        let laid = (floor.outputImage ?? plane).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: h))
        // Haze toward the horizon.
        let haze = CIFilter.linearGradient()
        haze.point0 = CGPoint(x: 0, y: h); haze.point1 = CGPoint(x: 0, y: h - 160)
        haze.color0 = CIColor(red: 1, green: 0.6, blue: 0.85, alpha: 0.85); haze.color1 = CIColor(red: 1, green: 0.6, blue: 0.85, alpha: 0)
        let floorLit = (haze.outputImage?.cropped(to: laid.extent)).map { $0.composited(over: laid) } ?? laid

        // Two wireframe shapes turning in the air.
        if canvas == nil { canvas = BackdropCanvas(width: 640, height: 360) }
        guard let canvas else { return floorLit.composited(over: still) }
        canvas.clear()
        let ctx = canvas.context
        ctx.setLineJoin(.round)
        Self.wire(ctx, centre: CGPoint(x: 120, y: 280), size: 46, angle: time * 0.35, tilt: 0.5, shape: .octahedron, colour: RGB(hex: 0x6FF3FF))
        Self.wire(ctx, centre: CGPoint(x: 545, y: 300), size: 34, angle: -time * 0.28, tilt: 0.4, shape: .cube, colour: RGB(hex: 0xFFF6A8))
        guard let shapes = canvas.image(scale: 2) else { return floorLit.composited(over: still) }
        return BackdropFinish.finish(shapes.composited(over: floorLit.composited(over: still)).cropped(to: frame))
    }

    private enum Shape { case cube, octahedron }

    private static func wire(_ ctx: CGContext, centre: CGPoint, size: Double, angle: Double, tilt: Double, shape: Shape, colour: RGB) {
        let vertices: [SIMD3<Double>]
        let edges: [(Int, Int)]
        switch shape {
        case .cube:
            vertices = [SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1), SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)]
            edges = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
        case .octahedron:
            vertices = [SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1.3, 0), SIMD3(0, -1.3, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)]
            edges = [(0, 2), (0, 3), (0, 4), (0, 5), (1, 2), (1, 3), (1, 4), (1, 5), (2, 4), (4, 3), (3, 5), (5, 2)]
        }
        let a = 2 * Double.pi * BackdropMath.fract(angle / (2 * .pi))
        let projected = vertices.map { v -> CGPoint in
            let x = v.x * cos(a) + v.z * sin(a), z = -v.x * sin(a) + v.z * cos(a)
            let y = v.y * cos(tilt) - z * sin(tilt)
            return CGPoint(x: centre.x + x * size, y: centre.y + y * size)
        }
        let path = CGMutablePath()
        for (i, j) in edges { path.move(to: projected[i]); path.addLine(to: projected[j]) }
        for (width, alpha) in [(CGFloat(5), 0.18), (CGFloat(1.4), 0.95)] {
            ctx.addPath(path); ctx.setStrokeColor(colour.cg(alpha)); ctx.setLineWidth(width); ctx.strokePath()
        }
    }
}
