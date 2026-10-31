import CoreGraphics
import CoreImage

/// Rooms to sit in front of: painted once, slightly out of focus as a real camera would have them behind you, with the
/// busy things kept to the sides and a calm, softly lit patch of wall where your head goes.
final class BackdropStudioSet: BackdropScene {
    enum Kind { case homeOffice, library, brickLoft, plantCorner, podcast, gallery, woodSlats, coffeeShop }
    typealias RGB = BackdropRGB
    private let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    override func paint() -> CIImage? {
        let painted: CIImage?
        let focus: Double, grain: Double, vignette: Double
        switch kind {
        case .homeOffice: painted = BackdropPainter.paint(width: 960, height: 540, Self.homeOffice); focus = 2.2; grain = 0.8; vignette = 0.16
        case .library: painted = BackdropPainter.paint(width: 960, height: 540, Self.library); focus = 2.6; grain = 0.9; vignette = 0.28
        case .brickLoft: painted = BackdropPainter.paint(width: 960, height: 540, Self.brickLoft); focus = 2.0; grain = 0.9; vignette = 0.22
        case .plantCorner: painted = BackdropPainter.paint(width: 960, height: 540, Self.plantCorner); focus = 1.8; grain = 0.7; vignette = 0.14
        case .podcast: painted = BackdropPainter.paint(width: 960, height: 540, Self.podcast); focus = 2.0; grain = 1.0; vignette = 0.3
        case .gallery: painted = BackdropPainter.paint(width: 960, height: 540, Self.gallery); focus = 1.8; grain = 0.6; vignette = 0.12
        case .woodSlats: painted = BackdropPainter.paint(width: 960, height: 540, Self.woodSlats); focus = 1.6; grain = 0.8; vignette = 0.22
        case .coffeeShop: painted = BackdropPainter.paint(width: 960, height: 540, Self.coffeeShop); focus = 5.5; grain = 1.0; vignette = 0.24
        }
        guard let painted else { return nil }
        let soft = BackdropPainter.defocus(painted, sigma: focus)
        let textured = BackdropPainter.mottle(soft, amount: 0.025, scale: 1.6, channel: 2)
        return BackdropFinish.finish(BackdropFinish.vignette(textured, strength: vignette), grain: grain)
    }

    // MARK: Home office

    /// A bright, warm room: a window on the left throwing daylight across the wall, a shelf with books, a plant and a
    /// print on the right, and a desk lamp glowing at the edge of the desk.
    private static func homeOffice(_ ctx: CGContext) {
        var rng = SplitMix64(seed: 0x0FF1CE)
        BackdropRoom.wall(ctx, RGB(hex: 0xD9CFC1), keyLight: 0.16)
        BackdropRoom.windowLight(ctx, origin: CGPoint(x: 330, y: 250), size: CGSize(width: 330, height: 360), slant: 120, panes: (2, 3),
                                 color: RGB(1, 0.94, 0.8), alpha: 0.22, blur: 22)
        BackdropRoom.window(ctx, CGRect(x: 40, y: 230, width: 210, height: 400), frame: RGB(hex: 0xF4F1EA), panes: (2, 3)) { ctx, r in
            BackdropPainter.vertical(ctx, r, [(at: 0, color: RGB(hex: 0xBFD8C0)), (at: 0.45, color: RGB(hex: 0xDDE9EC)), (at: 1, color: RGB(hex: 0xEAF2F7))])
            // Trees outside, soft.
            for k in 0..<6 {
                BackdropPainter.glow(ctx, at: CGPoint(x: r.minX + CGFloat(k) * 46, y: r.minY + 60 + CGFloat(k % 3) * 30), radius: 90,
                                     color: RGB(hex: 0x6F9A62), alpha: 0.55)
            }
        }
        // A sheer curtain gathered at the window's right.
        BackdropPainter.fill(ctx, BackdropPainter.rounded(CGRect(x: 238, y: 200, width: 44, height: 450), 18),
                             gradient: [(at: 0, color: RGB(hex: 0xEDE6DA)), (at: 0.5, color: RGB(hex: 0xF8F4EC)), (at: 1, color: RGB(hex: 0xD6CCBD))],
                             from: CGPoint(x: 238, y: 0), to: CGPoint(x: 282, y: 0))
        // Desk along the bottom.
        BackdropRoom.floor(ctx, top: 150, color: RGB(hex: 0x9C7A55))
        ctx.setFillColor(RGB(hex: 0xB89468).cg); ctx.fill(CGRect(x: 0, y: 138, width: 1280, height: 12))
        // Right: print, shelf of books with a trailing plant, lamp.
        BackdropRoom.picture(ctx, CGRect(x: 930, y: 450, width: 240, height: 190), frame: RGB(hex: 0x2B2B2E), mat: RGB(hex: 0xF3EFE7)) { ctx, r in
            BackdropRoom.abstractArt(ctx, r, palette: [RGB(hex: 0xE9DCC6), RGB(hex: 0xC8714B), RGB(hex: 0x2F5B5B), RGB(hex: 0xE2B45A)], seed: 3)
        }
        BackdropRoom.shelf(ctx, CGRect(x: 860, y: 330, width: 420, height: 16), wood: RGB(hex: 0xB08A60))
        BackdropRoom.books(ctx, x: 1000, width: 270, shelf: 346, maxHeight: 100, rng: &rng)
        BackdropRoom.plant(ctx, .trailing, base: CGPoint(x: 925, y: 346), height: 150, pot: RGB(hex: 0xEDE7DD), seed: 11)
        BackdropRoom.tableLamp(ctx, base: CGPoint(x: 1150, y: 150), height: 190, shade: RGB(hex: 0xEFE6D6), body: RGB(hex: 0x3B3B3E))
        BackdropRoom.plant(ctx, .snake, base: CGPoint(x: 330, y: 150), height: 260, pot: RGB(hex: 0x3F3F44), seed: 12)
    }

    // MARK: Library

    /// Floor-to-ceiling shelves of books in dark wood, a warm reading lamp and a lit panel behind you.
    private static func library(_ ctx: CGContext) {
        var rng = SplitMix64(seed: 0x11B2A27)
        let wood = RGB(hex: 0x4A2F1E)
        BackdropRoom.wall(ctx, RGB(hex: 0x2A1C15), keyLight: 0.10)
        // Bookcases on both sides; a quieter panelled middle.
        for (x0, x1) in [(CGFloat(0), CGFloat(470)), (CGFloat(810), CGFloat(1280))] {
            ctx.setFillColor(RGB(hex: 0x1E130D).cg); ctx.fill(CGRect(x: x0, y: 0, width: x1 - x0, height: 720))
            for (k, y) in [CGFloat(40), 200, 360, 520].enumerated() {
                let light = 0.82 + 0.08 * Double(k)
                BackdropRoom.books(ctx, x: x0 + 16, width: x1 - x0 - 32, shelf: y + 16, maxHeight: 130, rng: &rng, light: light)
                BackdropRoom.shelf(ctx, CGRect(x: x0, y: y, width: x1 - x0, height: 16), wood: wood)
            }
            for x in [x0, x1 - 18] { BackdropPainter.fill(ctx, CGPath(rect: CGRect(x: x, y: 0, width: 18, height: 720), transform: nil), wood.scaled(0.9).cg, shadow: 10, shadowAlpha: 0.5) }
        }
        // The panel behind you, with a soft warm wash.
        BackdropPainter.vertical(ctx, CGRect(x: 470, y: 0, width: 340, height: 720), [(at: 0, color: RGB(hex: 0x3A2618)), (at: 1, color: RGB(hex: 0x4B3322))])
        for x in [CGFloat(500), 640, 780] {
            ctx.setStrokeColor(RGB(0, 0, 0).cg(0.25)); ctx.setLineWidth(3)
            ctx.stroke(CGRect(x: x - 10, y: 80, width: 0.5, height: 560))
        }
        BackdropPainter.glow(ctx, at: CGPoint(x: 640, y: 520), radius: 360, color: BackdropRoom.lamplight, alpha: 0.18, blend: .screen)
        // Brass sconces between the cases.
        for x in [CGFloat(470), 810] {
            BackdropPainter.glow(ctx, at: CGPoint(x: x, y: 600), radius: 200, color: BackdropRoom.lamplight, alpha: 0.45, blend: .screen)
            BackdropPainter.fill(ctx, BackdropPainter.rounded(CGRect(x: x - 16, y: 586, width: 32, height: 40), 6),
                                 gradient: [(at: 0, color: RGB(hex: 0xFFE4B0)), (at: 1, color: RGB(hex: 0xE8B866))], from: CGPoint(x: x - 16, y: 0), to: CGPoint(x: x + 16, y: 0))
        }
        BackdropRoom.tableLamp(ctx, base: CGPoint(x: 1120, y: 56), height: 140, shade: RGB(hex: 0x2F4A3A), body: RGB(hex: 0xB8924A))
    }

    // MARK: Brick loft

    /// Old red brick, a tall steel-framed window full of daylight on the right, and two bare bulbs hanging on the left.
    private static func brickLoft(_ ctx: CGContext) {
        var rng = SplitMix64(seed: 0xB21C)
        let bricks = [RGB(hex: 0x8A4A35), RGB(hex: 0x7A3E2C), RGB(hex: 0x965540), RGB(hex: 0x6E3A2C), RGB(hex: 0xA0634A), RGB(hex: 0x834636)]
        ctx.setFillColor(RGB(hex: 0xB7A796).cg)      // mortar
        ctx.fill(BackdropPainter.frame)
        let bh: CGFloat = 26, bw: CGFloat = 78, gap: CGFloat = 5
        var row = 0
        var y: CGFloat = -4
        while y < 720 {
            var x: CGFloat = row % 2 == 0 ? -bw / 2 : 0
            while x < 1280 {
                let tone = bricks[Int.random(in: 0..<bricks.count, using: &rng)].scaled(Double.random(in: 0.86...1.08, using: &rng))
                let rect = CGRect(x: x + gap / 2, y: y + gap / 2, width: bw - gap, height: bh - gap)
                BackdropPainter.fill(ctx, BackdropPainter.rounded(rect, 2),
                                     gradient: [(at: 0, color: tone.scaled(0.85)), (at: 1, color: tone.mixed(RGB(1, 0.9, 0.8), 0.08))],
                                     from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.maxY))
                x += bw
            }
            y += bh
            row += 1
        }
        // Light and shade over the whole wall: the window's glow on the right, dusk on the left.
        BackdropPainter.glow(ctx, at: CGPoint(x: 1080, y: 420), radius: 900, color: RGB(1, 0.93, 0.85), alpha: 0.28, blend: .screen)
        BackdropPainter.glow(ctx, at: CGPoint(x: -100, y: 200), radius: 800, color: RGB(0, 0, 0), alpha: 0.4)
        BackdropPainter.glow(ctx, at: CGPoint(x: 640, y: 420), radius: 420, color: RGB(0.1, 0.05, 0.04), alpha: 0.25)
        BackdropRoom.window(ctx, CGRect(x: 930, y: 150, width: 300, height: 520), frame: RGB(hex: 0x1C1D1F), panes: (3, 5)) { ctx, r in
            BackdropPainter.vertical(ctx, r, [(at: 0, color: RGB(hex: 0xC9D4DA)), (at: 0.5, color: RGB(hex: 0xE4ECF0)), (at: 1, color: RGB(hex: 0xF4F7F8))])
            // A far city in haze.
            var rng = SplitMix64(seed: 77)
            var x = r.minX
            while x < r.maxX {
                let w = CGFloat.random(in: 26...60, using: &rng), h = CGFloat.random(in: 60...220, using: &rng)
                ctx.setFillColor(RGB(hex: 0xA9B6BF).cg(0.8)); ctx.fill(CGRect(x: x, y: r.minY, width: w, height: h))
                x += w + 4
            }
        }
        for (x, y) in [(CGFloat(170), CGFloat(500)), (CGFloat(330), CGFloat(440))] { BackdropRoom.pendant(ctx, x: x, y: y, shade: nil, glow: 1.8) }
        BackdropRoom.floor(ctx, top: 70, color: RGB(hex: 0x2A2420))
    }

    // MARK: Plant corner

    /// A calm limewash wall, a big monstera in a white pot, a low oak sideboard with a vase and a leaning print, and leaf
    /// shadows from an unseen window drifting across the wall.
    private static func plantCorner(_ ctx: CGContext) {
        BackdropRoom.wall(ctx, RGB(hex: 0xCFC6BA), keyLight: 0.18)
        BackdropRoom.windowLight(ctx, origin: CGPoint(x: 560, y: 260), size: CGSize(width: 520, height: 380), slant: 140, panes: (3, 2),
                                 color: RGB(1, 0.95, 0.84), alpha: 0.20, blur: 30)
        // Leaf shadows from a plant outside the window, very soft: long pointed leaves along arching stems.
        var rng = SplitMix64(seed: 0x1EAF)
        let shadows = CGMutablePath()
        for _ in 0..<4 {
            var p = CGPoint(x: CGFloat.random(in: 760...1240, using: &rng), y: 720)
            let lean = CGFloat.random(in: -0.6...0.2, using: &rng)
            for k in 0..<7 {
                p = CGPoint(x: p.x + sin(lean) * 40, y: p.y - 38)
                let side: CGFloat = k % 2 == 0 ? 1 : -1
                let leaf = CGMutablePath()
                leaf.move(to: p)
                leaf.addQuadCurve(to: CGPoint(x: p.x + side * 70, y: p.y - 30), control: CGPoint(x: p.x + side * 30, y: p.y + 14))
                leaf.addQuadCurve(to: p, control: CGPoint(x: p.x + side * 40, y: p.y - 30))
                shadows.addPath(leaf)
            }
        }
        BackdropRoom.soft(ctx, shadows, RGB(0.22, 0.18, 0.14).cg(0.13), blur: 9)
        BackdropRoom.floor(ctx, top: 96, color: RGB(hex: 0xB59C80), skirting: RGB(hex: 0xD8D0C4))
        // Sideboard on the right.
        let board = CGRect(x: 880, y: 96, width: 400, height: 150)
        BackdropPainter.fill(ctx, CGPath(rect: board, transform: nil), RGB(hex: 0xA8825A).cg, shadow: 18, shadowAlpha: 0.35)
        BackdropPainter.fill(ctx, CGPath(rect: board, transform: nil), gradient: [(at: 0, color: RGB(hex: 0x8E6C49)), (at: 1, color: RGB(hex: 0xB89068))],
                             from: CGPoint(x: 0, y: board.minY), to: CGPoint(x: 0, y: board.maxY))
        for k in 1..<3 {
            ctx.setFillColor(RGB(0, 0, 0).cg(0.18))
            ctx.fill(CGRect(x: board.minX + board.width * CGFloat(k) / 3, y: board.minY + 10, width: 2, height: board.height - 20))
        }
        ctx.setFillColor(RGB(hex: 0xC9A47A).cg); ctx.fill(CGRect(x: board.minX, y: board.maxY - 6, width: board.width, height: 6))
        // A tall vase with a few dry stems, and a print leaning on the wall.
        BackdropRoom.picture(ctx, CGRect(x: 1080, y: 246, width: 150, height: 190), frame: RGB(hex: 0xE9E4DA), mat: nil) { ctx, r in
            BackdropRoom.abstractArt(ctx, r, palette: [RGB(hex: 0xE4D8C6), RGB(hex: 0x9A6B4F), RGB(hex: 0x5D6B57)], seed: 8)
        }
        // Pampas plumes in a stone vase: soft, feathery heads on thin arching stems.
        for k in 0..<5 {
            let a = CGFloat(k - 2) * 0.2 + 0.05
            let tip = CGPoint(x: 960 + sin(a) * 170, y: 350 + cos(a) * 190)
            ctx.move(to: CGPoint(x: 960, y: 350)); ctx.addQuadCurve(to: tip, control: CGPoint(x: 960 + a * 50, y: 470))
            ctx.setStrokeColor(RGB(hex: 0x9C8762).cg); ctx.setLineWidth(2); ctx.strokePath()
            for j in 0..<9 {
                let f = CGFloat(j) / 8
                let at = CGPoint(x: tip.x - sin(a) * 90 * f, y: tip.y - cos(a) * 100 * f)
                BackdropPainter.glow(ctx, at: at, radius: 22 - 8 * abs(f - 0.4), color: RGB(hex: 0xE3D3B0), alpha: 0.75)
            }
        }
        BackdropRoom.potShape(ctx, base: CGPoint(x: 960, y: 246), width: 70, height: 118, color: RGB(hex: 0x8A8F86))
        BackdropRoom.plant(ctx, .monstera, base: CGPoint(x: 220, y: 96), height: 560, pot: RGB(hex: 0xF1EEE8), seed: 21)
    }

    // MARK: Podcast studio

    /// Dark acoustic panels, a soft neon soundwave glowing on the wall, records on a shelf and a warm edge light.
    private static func podcast(_ ctx: CGContext) {
        ctx.setFillColor(RGB(hex: 0x15181E).cg); ctx.fill(BackdropPainter.frame)
        // Foam: a grid of shallow pyramids, each face shaded by the light from the upper left.
        let cell: CGFloat = 64
        for gy in stride(from: CGFloat(0), to: 720, by: cell) {
            for gx in stride(from: CGFloat(0), to: 1280, by: cell) {
                let base = RGB(hex: 0x262B35)
                let c = CGPoint(x: gx + cell / 2, y: gy + cell / 2)
                let faces: [(CGPoint, CGPoint, Double)] = [
                    (CGPoint(x: gx, y: gy + cell), CGPoint(x: gx + cell, y: gy + cell), 1.25), (CGPoint(x: gx, y: gy), CGPoint(x: gx, y: gy + cell), 1.12),
                    (CGPoint(x: gx + cell, y: gy + cell), CGPoint(x: gx + cell, y: gy), 0.78), (CGPoint(x: gx + cell, y: gy), CGPoint(x: gx, y: gy), 0.64),
                ]
                for (a, b, shade) in faces {
                    let tri = CGMutablePath(); tri.move(to: a); tri.addLine(to: b); tri.addLine(to: c); tri.closeSubpath()
                    ctx.addPath(tri); ctx.setFillColor(base.scaled(shade).cg); ctx.fillPath()
                }
            }
        }
        // Wash of light: cool from the left, deep shadow in the corners.
        BackdropPainter.glow(ctx, at: CGPoint(x: 640, y: 430), radius: 520, color: RGB(hex: 0x4A5A78), alpha: 0.35, blend: .screen)
        BackdropPainter.glow(ctx, at: CGPoint(x: 1280, y: 0), radius: 700, color: RGB(0, 0, 0), alpha: 0.5)
        // The neon soundwave, upper right: a soft halo on the wall, then the bright tube.
        let wave = CGMutablePath()
        let left: CGFloat = 860, mid: CGFloat = 560
        wave.move(to: CGPoint(x: left, y: mid))
        for k in 0..<24 {
            let x = left + CGFloat(k) * 14
            let h = [10, 22, 48, 30, 64, 40, 18, 52, 80, 44, 26, 58, 34, 70, 46, 20, 38, 60, 28, 16, 34, 22, 12, 8][k]
            wave.addLine(to: CGPoint(x: x + 7, y: mid + CGFloat(h) * 0.9))
            wave.addLine(to: CGPoint(x: x + 14, y: mid - CGFloat(h) * 0.7))
        }
        wave.addLine(to: CGPoint(x: left + 24 * 14 + 10, y: mid))
        let pink = RGB(hex: 0xFF4FA8), cyan = RGB(hex: 0x4FE3FF)
        BackdropPainter.glow(ctx, at: CGPoint(x: 1030, y: 560), radius: 330, color: pink, alpha: 0.40, squash: 0.55, blend: .screen)
        ctx.saveGState()
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        for (width, alpha) in [(CGFloat(22), 0.10), (14, 0.18), (8, 0.35)] {
            ctx.addPath(wave); ctx.setStrokeColor(pink.cg(alpha)); ctx.setLineWidth(width); ctx.strokePath()
        }
        ctx.addPath(wave); ctx.setStrokeColor(RGB(1, 0.86, 0.94).cg); ctx.setLineWidth(3.2); ctx.strokePath()
        ctx.restoreGState()
        // Records on a shelf at the left, edge-lit in cyan.
        BackdropRoom.shelf(ctx, CGRect(x: 40, y: 330, width: 300, height: 12), wood: RGB(hex: 0x3A2A22))
        var rng = SplitMix64(seed: 0xD15C)
        for k in 0..<16 {
            let x = 56 + CGFloat(k) * 8.5
            let sleeve = [RGB(hex: 0xC9473A), RGB(hex: 0x2B3F7A), RGB(hex: 0xE2B14A), RGB(hex: 0x1F1F24), RGB(hex: 0x4E8A6E)][Int.random(in: 0..<5, using: &rng)]
            BackdropPainter.fill(ctx, CGPath(rect: CGRect(x: x, y: 342, width: 7, height: 150), transform: nil),
                                 gradient: [(at: 0, color: sleeve.mixed(RGB(1, 1, 1), 0.15)), (at: 1, color: sleeve.scaled(0.6))], from: CGPoint(x: x, y: 0), to: CGPoint(x: x + 7, y: 0))
        }
        let disc = CGRect(x: 216, y: 346, width: 140, height: 140)
        BackdropPainter.fill(ctx, CGPath(ellipseIn: disc, transform: nil), RGB(hex: 0x0E0E10).cg, shadow: 10, shadowAlpha: 0.5)
        ctx.setFillColor(RGB(hex: 0xE2B14A).cg); ctx.fillEllipse(in: disc.insetBy(dx: 52, dy: 52))
        BackdropPainter.glow(ctx, at: CGPoint(x: 0, y: 420), radius: 380, color: cyan, alpha: 0.30, squash: 1.4, blend: .screen)
        BackdropRoom.floor(ctx, top: 60, color: RGB(hex: 0x101216))
    }

    // MARK: Gallery wall

    /// A bright white wall hung salon style: frames of different sizes around the top and sides, one with a picture light.
    private static func gallery(_ ctx: CGContext) {
        BackdropRoom.wall(ctx, RGB(hex: 0xECE9E3), keyLight: 0.10)
        let frames: [(CGRect, RGB, RGB?, [RGB])] = [
            (CGRect(x: 60, y: 430, width: 200, height: 250), RGB(hex: 0x1E1E20), RGB(hex: 0xF7F5F0), [RGB(hex: 0xEDE3D2), RGB(hex: 0x2F4858), RGB(hex: 0xD9A35F)]),
            (CGRect(x: 290, y: 520, width: 150, height: 150), RGB(hex: 0xB89B72), nil, [RGB(hex: 0x30473F), RGB(hex: 0xC97B5A), RGB(hex: 0xE8D9B5)]),
            (CGRect(x: 80, y: 190, width: 150, height: 200), RGB(hex: 0xF4F2EE), RGB(hex: 0xFFFFFF), [RGB(hex: 0xC9D3D6), RGB(hex: 0x4B6A88), RGB(hex: 0xE9C46A)]),
            (CGRect(x: 840, y: 500, width: 220, height: 170), RGB(hex: 0x1E1E20), RGB(hex: 0xF7F5F0), [RGB(hex: 0xF0E6D8), RGB(hex: 0xB5523B), RGB(hex: 0x1F3A4A), RGB(hex: 0xD8B26E)]),
            (CGRect(x: 1090, y: 450, width: 150, height: 220), RGB(hex: 0xB89B72), RGB(hex: 0xFAF8F4), [RGB(hex: 0xDCE3DA), RGB(hex: 0x5C7A5A), RGB(hex: 0xA8C3A0)]),
            (CGRect(x: 1040, y: 160, width: 190, height: 240), RGB(hex: 0x2A2A2C), nil, [RGB(hex: 0x23303B), RGB(hex: 0xC4875C), RGB(hex: 0xE6D3B3)]),
            (CGRect(x: 520, y: 600, width: 240, height: 90), RGB(hex: 0xF4F2EE), RGB(hex: 0xFFFFFF), [RGB(hex: 0xE8E2D6), RGB(hex: 0x8E5B4A), RGB(hex: 0x3C5A6B)]),
        ]
        for (k, f) in frames.enumerated() {
            BackdropRoom.picture(ctx, f.0, frame: f.1, mat: f.2) { ctx, r in BackdropRoom.abstractArt(ctx, r, palette: f.3, seed: UInt64(40 + k)) }
        }
        // A brass picture light over the big frame on the right, and its warm spill.
        BackdropPainter.glow(ctx, at: CGPoint(x: 950, y: 640), radius: 220, color: BackdropRoom.lamplight, alpha: 0.35, squash: 0.6, blend: .screen)
        BackdropPainter.fill(ctx, BackdropPainter.rounded(CGRect(x: 890, y: 684, width: 120, height: 14), 6),
                             gradient: [(at: 0, color: RGB(hex: 0xF2D79A)), (at: 1, color: RGB(hex: 0xA77E3C))], from: CGPoint(x: 0, y: 698), to: CGPoint(x: 0, y: 684))
        BackdropRoom.floor(ctx, top: 70, color: RGB(hex: 0xC7B9A5), skirting: RGB(hex: 0xF2F0EC))
    }

    // MARK: Wood slats

    /// A modern room: oak slats with dark gaps across the wall, a warm cove light washing down from the top and a strip
    /// light glowing along the floor, a snake plant at the side.
    private static func woodSlats(_ ctx: CGContext) {
        ctx.setFillColor(RGB(hex: 0x17120E).cg); ctx.fill(BackdropPainter.frame)
        var rng = SplitMix64(seed: 0x51A75)
        let oak = RGB(hex: 0xA77B4F)
        var x: CGFloat = 4
        while x < 1280 {
            let tone = oak.scaled(Double.random(in: 0.86...1.06, using: &rng))
            let rect = CGRect(x: x, y: 0, width: 26, height: 720)
            BackdropPainter.fill(ctx, CGPath(rect: rect, transform: nil),
                                 gradient: [(at: 0, color: tone.mixed(RGB(1, 0.95, 0.85), 0.12)), (at: 0.5, color: tone), (at: 1, color: tone.scaled(0.68))],
                                 from: CGPoint(x: rect.minX, y: 0), to: CGPoint(x: rect.maxX, y: 0))
            // Grain, faint.
            for _ in 0..<3 {
                let gx = rect.minX + CGFloat.random(in: 4...22, using: &rng)
                ctx.setStrokeColor(tone.scaled(0.8).cg(0.35)); ctx.setLineWidth(0.8)
                ctx.move(to: CGPoint(x: gx, y: 0)); ctx.addLine(to: CGPoint(x: gx + CGFloat.random(in: -3...3, using: &rng), y: 720)); ctx.strokePath()
            }
            x += 36
        }
        // Cove light from above and a strip along the floor; dark in between, warmer in the middle.
        if let down = BackdropPaint.gradient([(at: 0, r: 1, g: 0.78, b: 0.48, a: 0.55), (at: 1, r: 1, g: 0.78, b: 0.48, a: 0)]) {
            ctx.saveGState(); ctx.setBlendMode(.screen)
            ctx.drawLinearGradient(down, start: CGPoint(x: 0, y: 720), end: CGPoint(x: 0, y: 420), options: [])
            ctx.drawLinearGradient(down, start: CGPoint(x: 0, y: 40), end: CGPoint(x: 0, y: 230), options: [])
            ctx.restoreGState()
        }
        if let shade = BackdropPaint.gradient([(at: 0, r: 0, g: 0, b: 0, a: 0), (at: 0.5, r: 0, g: 0, b: 0, a: 0.42), (at: 1, r: 0, g: 0, b: 0, a: 0)]) {
            ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: 120), end: CGPoint(x: 0, y: 640), options: [])
        }
        BackdropPainter.glow(ctx, at: CGPoint(x: 640, y: 420), radius: 380, color: RGB(1, 0.8, 0.55), alpha: 0.16, blend: .screen)
        BackdropPainter.glow(ctx, at: CGPoint(x: 1300, y: 300), radius: 600, color: RGB(0, 0, 0), alpha: 0.4)
        ctx.setFillColor(RGB(1, 0.86, 0.62).cg); ctx.fill(CGRect(x: 0, y: 36, width: 1280, height: 4))
        BackdropRoom.floor(ctx, top: 36, color: RGB(hex: 0x1D1712))
        BackdropRoom.plant(ctx, .snake, base: CGPoint(x: 1110, y: 36), height: 330, pot: RGB(hex: 0x2E2E31), seed: 33, light: 0.8)
    }

    // MARK: Coffee shop

    /// A café seen past your shoulder, well out of focus: green tiles, shelves of jars, warm pendant bulbs and a chalkboard.
    private static func coffeeShop(_ ctx: CGContext) {
        // Tiled wall.
        ctx.setFillColor(RGB(hex: 0x1F3A33).cg); ctx.fill(BackdropPainter.frame)
        var rng = SplitMix64(seed: 0xCAFE)
        var row = 0
        for y in stride(from: CGFloat(0), to: 720, by: 30) {
            var x: CGFloat = row % 2 == 0 ? 0 : -30
            while x < 1280 {
                let tone = RGB(hex: 0x2E5A4E).scaled(Double.random(in: 0.88...1.1, using: &rng))
                BackdropPainter.fill(ctx, BackdropPainter.rounded(CGRect(x: x + 2, y: y + 2, width: 56, height: 26), 3),
                                     gradient: [(at: 0, color: tone.scaled(0.85)), (at: 1, color: tone.mixed(RGB(1, 1, 1), 0.12))], from: CGPoint(x: 0, y: y), to: CGPoint(x: 0, y: y + 28))
                x += 60
            }
            row += 1
        }
        // Chalkboard, left.
        let board = CGRect(x: 60, y: 300, width: 300, height: 260)
        BackdropPainter.fill(ctx, CGPath(rect: board.insetBy(dx: -10, dy: -10), transform: nil), RGB(hex: 0x6B4A30).cg, shadow: 14, shadowAlpha: 0.4)
        ctx.setFillColor(RGB(hex: 0x1E2321).cg); ctx.fill(board)
        ctx.setStrokeColor(RGB(0.92, 0.92, 0.88).cg(0.55)); ctx.setLineWidth(3); ctx.setLineCap(.round)
        for k in 0..<7 {
            let y = board.maxY - 40 - CGFloat(k) * 30
            let w = CGFloat.random(in: 120...220, using: &rng)
            ctx.move(to: CGPoint(x: board.minX + 26, y: y))
            var px = board.minX + 26
            while px < board.minX + 26 + w { px += 9; ctx.addLine(to: CGPoint(x: px, y: y + CGFloat.random(in: -4...4, using: &rng))) }
            ctx.strokePath()
            ctx.move(to: CGPoint(x: board.maxX - 60, y: y)); ctx.addLine(to: CGPoint(x: board.maxX - 30, y: y)); ctx.strokePath()
        }
        // Shelves of jars and cups, right.
        for y in [CGFloat(330), 470] {
            BackdropRoom.shelf(ctx, CGRect(x: 880, y: y, width: 400, height: 12), wood: RGB(hex: 0x7A5638))
            var x: CGFloat = 900
            while x < 1260 {
                let w = CGFloat.random(in: 34...56, using: &rng), h = CGFloat.random(in: 50...100, using: &rng)
                let tint = [RGB(hex: 0xD9C7A8), RGB(hex: 0x8C5A3A), RGB(hex: 0xEFE8DA), RGB(hex: 0x3B2A20)][Int.random(in: 0..<4, using: &rng)]
                BackdropPainter.fill(ctx, BackdropPainter.rounded(CGRect(x: x, y: y + 12, width: w, height: h), 6),
                                     gradient: [(at: 0, color: tint.mixed(RGB(1, 1, 1), 0.25)), (at: 0.4, color: tint), (at: 1, color: tint.scaled(0.6))],
                                     from: CGPoint(x: x, y: 0), to: CGPoint(x: x + w, y: 0))
                x += w + CGFloat.random(in: 8...20, using: &rng)
            }
        }
        // Counter along the bottom.
        BackdropRoom.floor(ctx, top: 120, color: RGB(hex: 0x3A281C))
        ctx.setFillColor(RGB(hex: 0x8A6440).cg); ctx.fill(CGRect(x: 0, y: 110, width: 1280, height: 10))
        // Warm pendants: these become big soft discs once out of focus.
        for (x, y) in [(CGFloat(210), CGFloat(640)), (CGFloat(560), CGFloat(610)), (CGFloat(1040), CGFloat(650)), (CGFloat(1220), CGFloat(600))] {
            BackdropRoom.pendant(ctx, x: x, y: y, shade: nil, glow: 2.2)
        }
        BackdropPainter.glow(ctx, at: CGPoint(x: 640, y: 380), radius: 500, color: RGB(1, 0.75, 0.45), alpha: 0.14, blend: .screen)
        // Far lights of the room, which the lens turns into discs.
        for _ in 0..<14 {
            let c = CGPoint(x: CGFloat.random(in: 0...1280, using: &rng), y: CGFloat.random(in: 420...700, using: &rng))
            let r = CGFloat.random(in: 18...42, using: &rng)
            ctx.setFillColor(RGB(1, 0.8, 0.52).cg(Double.random(in: 0.10...0.22, using: &rng)))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        for (x, y) in [(CGFloat(210), CGFloat(640)), (CGFloat(560), CGFloat(610)), (CGFloat(1040), CGFloat(650)), (CGFloat(1220), CGFloat(600))] {
            ctx.setFillColor(RGB(1, 0.86, 0.6).cg(0.5))
            ctx.fillEllipse(in: CGRect(x: x - 36, y: y - 36, width: 72, height: 72))
        }
    }
}
