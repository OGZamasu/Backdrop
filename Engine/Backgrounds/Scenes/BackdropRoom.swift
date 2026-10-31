import CoreGraphics
import CoreImage

/// The pieces the studio sets are built from: walls lit from the upper left, floors, shelves of books, plants, framed
/// pictures and lamps. Everything is drawn in output pixels (1280 x 720, y up) and casts its soft shadow down and to the
/// right, so every set shares one light.
enum BackdropRoom {
    typealias RGB = BackdropRGB

    // MARK: Named palettes

    /// Book spines: muted cloth and leather colours, nothing loud.
    static let spines: [RGB] = [
        RGB(hex: 0x6E2B2B), RGB(hex: 0x23395B), RGB(hex: 0x2F4F3A), RGB(hex: 0xB8893A), RGB(hex: 0xD9CDB4), RGB(hex: 0x2E6B6B),
        RGB(hex: 0xA4553A), RGB(hex: 0x3A3A40), RGB(hex: 0x7D6B8A), RGB(hex: 0x8C9A6E), RGB(hex: 0x4A2E3A), RGB(hex: 0xC4B08A),
    ]
    /// Leaf greens, deep to fresh.
    static let leaf = (deep: RGB(hex: 0x1E3B24), mid: RGB(hex: 0x2F6B3A), light: RGB(hex: 0x5E9A4E))
    /// Warm lamp light.
    static let lamplight = RGB(hex: 0xFFC982)

    // MARK: Walls and light

    /// The wall: its colour, lit from the upper left, darker toward the lower right, with the soft shade a ceiling throws.
    static func wall(_ ctx: CGContext, _ color: RGB, rect: CGRect = BackdropPainter.frame, keyLight: Double = 0.12) {
        ctx.setFillColor(color.cg)
        ctx.fill(rect)
        BackdropPainter.glow(ctx, at: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY + 40), radius: rect.width * 0.95,
                             color: RGB(1, 0.97, 0.92), alpha: keyLight)
        BackdropPainter.glow(ctx, at: CGPoint(x: rect.maxX + 60, y: rect.minY - 80), radius: rect.width * 0.8, color: RGB(0, 0, 0), alpha: 0.22)
        // The ceiling's shade along the top edge.
        if let g = BackdropPaint.gradient([(at: 0, r: 0, g: 0, b: 0, a: 0.22), (at: 1, r: 0, g: 0, b: 0, a: 0)]) {
            ctx.saveGState(); ctx.clip(to: rect)
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.maxY - 110), options: [])
            ctx.restoreGState()
        }
    }

    /// The floor below `top`, with the dark line where it meets the wall and a skirting board.
    static func floor(_ ctx: CGContext, top: CGFloat, color: RGB, skirting: RGB? = nil) {
        BackdropPainter.vertical(ctx, CGRect(x: 0, y: 0, width: 1280, height: top),
                                 [(at: 0, color: color.scaled(0.7)), (at: 1, color: color)])
        if let skirting {
            ctx.setFillColor(skirting.cg)
            ctx.fill(CGRect(x: 0, y: top, width: 1280, height: 16))
            ctx.setFillColor(RGB(1, 1, 1).cg(0.10))
            ctx.fill(CGRect(x: 0, y: top + 14, width: 1280, height: 2))
        }
        if let g = BackdropPaint.gradient([(at: 0, r: 0, g: 0, b: 0, a: 0.35), (at: 1, r: 0, g: 0, b: 0, a: 0)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: top - 26), options: [])
        }
    }

    /// `path` with its edges blurred by `blur` pixels: for light falling through a window, or a soft shadow.
    static func soft(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, blur: CGFloat) {
        let scale = max(0.01, ctx.userSpaceToDeviceSpaceTransform.a)
        let away: CGFloat = 4000
        ctx.saveGState()
        // The shape is drawn far off the canvas and only its shadow lands in place: a cheap, smooth blur.
        ctx.setShadow(offset: CGSize(width: away * scale, height: 0), blur: blur * scale, color: color)
        ctx.translateBy(x: -away, y: 0)
        ctx.addPath(path)
        ctx.setFillColor(RGB(0, 0, 0).cg)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// Sunlight through a window, landing on the wall as a slanted patch split by the window's bars.
    static func windowLight(_ ctx: CGContext, origin: CGPoint, size: CGSize, slant: CGFloat, panes: (Int, Int), color: RGB, alpha: Double, blur: CGFloat) {
        let path = CGMutablePath()
        let bar: CGFloat = size.width * 0.05
        let pw = (size.width - bar * CGFloat(panes.0 - 1)) / CGFloat(panes.0)
        let ph = (size.height - bar * CGFloat(panes.1 - 1)) / CGFloat(panes.1)
        for i in 0..<panes.0 {
            for j in 0..<panes.1 {
                let x0 = origin.x + CGFloat(i) * (pw + bar), y0 = origin.y + CGFloat(j) * (ph + bar)
                let shear = slant * (y0 - origin.y) / size.height
                let shear1 = slant * (y0 + ph - origin.y) / size.height
                path.move(to: CGPoint(x: x0 + shear, y: y0))
                path.addLine(to: CGPoint(x: x0 + pw + shear, y: y0))
                path.addLine(to: CGPoint(x: x0 + pw + shear1, y: y0 + ph))
                path.addLine(to: CGPoint(x: x0 + shear1, y: y0 + ph))
                path.closeSubpath()
            }
        }
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        soft(ctx, path, color.cg(alpha), blur: blur)
        ctx.restoreGState()
    }

    // MARK: Furniture

    /// A shelf board: its top face catching the light, the front edge, and the shadow it throws on the wall below.
    static func shelf(_ ctx: CGContext, _ rect: CGRect, wood: RGB) {
        soft(ctx, CGPath(rect: CGRect(x: rect.minX + 4, y: rect.minY - 16, width: rect.width, height: 18), transform: nil),
             RGB(0, 0, 0).cg(0.35), blur: 10)
        BackdropPainter.fill(ctx, CGPath(rect: rect, transform: nil),
                             gradient: [(at: 0, color: wood.scaled(0.72)), (at: 0.75, color: wood), (at: 1, color: wood.mixed(RGB(1, 1, 1), 0.25))],
                             from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.maxY))
    }

    /// A row of book spines standing on `shelf` (its top edge), filling `width` from `x`. Some lean, some lie in a stack.
    static func books(_ ctx: CGContext, x: CGFloat, width: CGFloat, shelf: CGFloat, maxHeight: CGFloat, rng: inout SplitMix64,
                      palette: [RGB] = spines, light: Double = 1) {
        var at = x
        while at < x + width - 8 {
            let roll = Double.random(in: 0..<1, using: &rng)
            if roll < 0.08 && at + 70 < x + width {
                // A small stack lying flat.
                var y = shelf
                for _ in 0..<Int.random(in: 2...4, using: &rng) {
                    let w = CGFloat.random(in: 52...74, using: &rng), h = CGFloat.random(in: 9...15, using: &rng)
                    spine(ctx, CGRect(x: at + CGFloat.random(in: 0...6, using: &rng), y: y, width: w, height: h),
                          palette[Int.random(in: 0..<palette.count, using: &rng)].scaled(light), horizontal: true)
                    y += h
                }
                at += 82
                continue
            }
            if roll < 0.13 { at += CGFloat.random(in: 14...40, using: &rng); continue }   // a gap
            let w = CGFloat.random(in: 11...24, using: &rng)
            let h = maxHeight * CGFloat.random(in: 0.66...0.98, using: &rng)
            let colour = palette[Int.random(in: 0..<palette.count, using: &rng)].scaled(light * Double.random(in: 0.8...1.1, using: &rng))
            if roll > 0.95 {
                // Leaning against the last one.
                ctx.saveGState()
                ctx.translateBy(x: at + w, y: shelf)
                ctx.rotate(by: -0.28)
                spine(ctx, CGRect(x: -w, y: 0, width: w, height: h), colour, horizontal: false)
                ctx.restoreGState()
                at += w + h * 0.3
            } else {
                spine(ctx, CGRect(x: at, y: shelf, width: w, height: h), colour, horizontal: false)
                at += w + CGFloat.random(in: 0...1.5, using: &rng)
            }
        }
    }

    /// One book: cloth with light from the left, a darker right edge, and a couple of gilt bands on some.
    static func spine(_ ctx: CGContext, _ rect: CGRect, _ color: RGB, horizontal: Bool) {
        let path = BackdropPainter.rounded(rect, 1.5)
        if horizontal {
            BackdropPainter.fill(ctx, path, gradient: [(at: 0, color: color.scaled(0.7)), (at: 0.6, color: color), (at: 1, color: color.mixed(RGB(1, 1, 1), 0.18))],
                                 from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.maxY))
            return
        }
        BackdropPainter.fill(ctx, path, gradient: [(at: 0, color: color.mixed(RGB(1, 1, 1), 0.16)), (at: 0.35, color: color), (at: 1, color: color.scaled(0.62))],
                             from: CGPoint(x: rect.minX, y: 0), to: CGPoint(x: rect.maxX, y: 0))
        let bands = Int(rect.width * 7 + rect.height) % 3
        if bands > 0 {
            let gilt = RGB(hex: 0xD8B868).cg(0.55)
            ctx.setFillColor(gilt)
            ctx.fill(CGRect(x: rect.minX + 1, y: rect.maxY - rect.height * 0.12, width: rect.width - 2, height: 1.6))
            if bands > 1 { ctx.fill(CGRect(x: rect.minX + 1, y: rect.minY + rect.height * 0.1, width: rect.width - 2, height: 1.6)) }
        }
    }

    /// A framed picture with a mat and a soft drop shadow. `art` paints inside the opening.
    static func picture(_ ctx: CGContext, _ rect: CGRect, frame: RGB, mat: RGB?, art: (CGContext, CGRect) -> Void) {
        BackdropPainter.fill(ctx, CGPath(rect: rect, transform: nil), frame.cg, shadow: 14, shadowAlpha: 0.4, offset: CGSize(width: 7, height: -9))
        // Moulding: lighter on the top and left, as the light comes from there.
        let edge = min(rect.width, rect.height) * 0.05
        ctx.setFillColor(RGB(1, 1, 1).cg(0.14))
        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - edge * 0.5, width: rect.width, height: edge * 0.5))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: edge * 0.5, height: rect.height))
        var inner = rect.insetBy(dx: edge, dy: edge)
        if let mat {
            ctx.setFillColor(mat.cg)
            ctx.fill(inner)
            // The bevel's shadow at the top of the opening.
            inner = inner.insetBy(dx: inner.width * 0.13, dy: inner.height * 0.13)
            soft(ctx, CGPath(rect: inner.offsetBy(dx: 1.5, dy: -2), transform: nil), RGB(0, 0, 0).cg(0.35), blur: 3)
        }
        ctx.saveGState()
        ctx.clip(to: inner)
        art(ctx, inner)
        ctx.restoreGState()
        // Glass: a faint sheen across the upper left.
        if let g = BackdropPaint.gradient([(at: 0, r: 1, g: 1, b: 1, a: 0.10), (at: 0.5, r: 1, g: 1, b: 1, a: 0), (at: 1, r: 1, g: 1, b: 1, a: 0)]) {
            ctx.saveGState(); ctx.clip(to: inner)
            ctx.drawLinearGradient(g, start: CGPoint(x: inner.minX, y: inner.maxY), end: CGPoint(x: inner.maxX, y: inner.minY), options: [])
            ctx.restoreGState()
        }
    }

    /// Calm abstract art for frames: a ground and a few soft shapes from `palette`.
    static func abstractArt(_ ctx: CGContext, _ rect: CGRect, palette: [RGB], seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        BackdropPainter.vertical(ctx, rect, [(at: 0, color: palette[0].scaled(0.92)), (at: 1, color: palette[0])])
        for k in 1..<palette.count {
            let r = min(rect.width, rect.height) * CGFloat.random(in: 0.22...0.5, using: &rng)
            let c = CGPoint(x: rect.minX + rect.width * CGFloat.random(in: 0.2...0.8, using: &rng),
                            y: rect.minY + rect.height * CGFloat.random(in: 0.2...0.8, using: &rng))
            ctx.setFillColor(palette[k].cg(0.92))
            if k % 2 == 0 {
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            } else {
                let arc = CGMutablePath()
                arc.addArc(center: CGPoint(x: c.x, y: rect.minY), radius: r * 1.3, startAngle: 0, endAngle: .pi, clockwise: false)
                arc.closeSubpath()
                ctx.addPath(arc); ctx.fillPath()
            }
        }
    }

    // MARK: Plants

    enum PlantKind { case monstera, fiddle, snake, trailing }

    /// A potted plant standing at `base` (the middle of the pot's foot), `height` tall.
    static func plant(_ ctx: CGContext, _ kind: PlantKind, base: CGPoint, height: CGFloat, pot: RGB, seed: UInt64, light: Double = 1) {
        var rng = SplitMix64(seed: seed)
        let potH = height * (kind == .trailing ? 0.42 : 0.24), potW = potH * (kind == .snake ? 0.95 : 1.05)
        let rim = base.y + potH
        // Shadow on the wall behind, down and to the right.
        soft(ctx, CGPath(ellipseIn: CGRect(x: base.x - height * 0.25 + 26, y: rim - 10, width: height * 0.6, height: height * 0.75), transform: nil),
             RGB(0, 0, 0).cg(0.16), blur: 30)
        let greens = (deep: leaf.deep.scaled(light), mid: leaf.mid.scaled(light), light: leaf.light.scaled(light))
        switch kind {
        case .monstera:
            // Leaves at the back first (darker), the front ones last.
            var leaves: [(angle: CGFloat, reach: CGFloat, size: CGFloat, shade: Double)] = []
            for k in 0..<11 {
                let angle = CGFloat(k - 5) * 0.21 + CGFloat.random(in: -0.12...0.12, using: &rng)
                leaves.append((angle, height * CGFloat.random(in: 0.34...0.58, using: &rng), height * CGFloat.random(in: 0.26...0.34, using: &rng),
                               k % 3 == 0 ? 0.72 : Double.random(in: 0.88...1.05, using: &rng)))
            }
            leaves.sort { $0.shade < $1.shade }
            for leaf in leaves {
                let tip = CGPoint(x: base.x + sin(leaf.angle) * leaf.reach, y: rim + cos(leaf.angle) * leaf.reach * 0.9)
                stem(ctx, from: CGPoint(x: base.x, y: rim), to: tip, color: greens.deep.scaled(leaf.shade), width: 3.2)
                let shaded = (deep: greens.deep.scaled(leaf.shade), mid: greens.mid.scaled(leaf.shade), light: greens.light.scaled(leaf.shade))
                // Leaves hang off their stems, tipping outward and down.
                monsteraLeaf(ctx, at: tip, size: leaf.size, angle: leaf.angle * 1.5 + (leaf.angle > 0 ? 0.5 : -0.5), greens: shaded)
            }
        case .fiddle:
            let top = CGPoint(x: base.x + 8, y: rim + height * 0.74)
            stem(ctx, from: CGPoint(x: base.x, y: rim), to: top, color: RGB(hex: 0x4A3A2A).scaled(light), width: 6)
            for k in 0..<14 {
                let f = CGFloat(k) / 13
                let at = CGPoint(x: base.x + 8 * f + CGFloat.random(in: -4...4, using: &rng), y: rim + height * (0.18 + 0.58 * f))
                let side: CGFloat = k % 2 == 0 ? -1 : 1
                let size = height * (0.13 - 0.04 * f) * CGFloat.random(in: 0.85...1.1, using: &rng)
                ovalLeaf(ctx, at: CGPoint(x: at.x + side * size * 0.55, y: at.y), size: size,
                         angle: side * CGFloat.random(in: 0.5...1.1, using: &rng), greens: greens)
            }
        case .snake:
            for k in 0..<9 {
                let lean = CGFloat(k - 4) * 0.08 + CGFloat.random(in: -0.05...0.05, using: &rng)
                let h = height * CGFloat.random(in: 0.55...0.76, using: &rng)
                let w = height * CGFloat.random(in: 0.045...0.06, using: &rng)
                let x0 = base.x + CGFloat(k - 4) * potW * 0.09
                let blade = CGMutablePath()
                blade.move(to: CGPoint(x: x0 - w, y: rim))
                blade.addQuadCurve(to: CGPoint(x: x0 + sin(lean) * h, y: rim + h), control: CGPoint(x: x0 - w * 1.3 + sin(lean) * h * 0.4, y: rim + h * 0.55))
                blade.addQuadCurve(to: CGPoint(x: x0 + w, y: rim), control: CGPoint(x: x0 + w * 1.3 + sin(lean) * h * 0.4, y: rim + h * 0.5))
                blade.closeSubpath()
                BackdropPainter.fill(ctx, blade, gradient: [(at: 0, color: greens.deep), (at: 0.5, color: greens.mid), (at: 1, color: greens.light.mixed(RGB(hex: 0xC9C77A), 0.3))],
                                     from: CGPoint(x: x0 - w, y: rim), to: CGPoint(x: x0 + w, y: rim + h))
                // Yellow edge, the plant's own.
                ctx.addPath(blade)
                ctx.setStrokeColor(RGB(hex: 0xB5B061).scaled(light).cg(0.55))
                ctx.setLineWidth(1.2)
                ctx.strokePath()
            }
        case .trailing:
            for _ in 0..<7 {
                var p = CGPoint(x: base.x + CGFloat.random(in: -potW * 0.4...potW * 0.4, using: &rng), y: rim)
                let fall = height * CGFloat.random(in: 0.5...1.2, using: &rng)
                let dir: CGFloat = Bool.random(using: &rng) ? 1 : -1
                var t: CGFloat = 0
                while t < 1 {
                    let next = CGPoint(x: p.x + dir * 6 + CGFloat.random(in: -4...4, using: &rng), y: rim + 18 - fall * t * t * 1.0 - 18 * t)
                    stem(ctx, from: p, to: next, color: greens.deep, width: 1.6)
                    if Int(t * 20) % 2 == 0 {
                        heartLeaf(ctx, at: next, size: height * 0.075, angle: CGFloat.random(in: -0.8...0.8, using: &rng) + .pi, greens: greens)
                    }
                    p = next
                    t += 0.1
                }
            }
            for _ in 0..<8 {
                heartLeaf(ctx, at: CGPoint(x: base.x + CGFloat.random(in: -potW * 0.6...potW * 0.6, using: &rng), y: rim + CGFloat.random(in: 2...24, using: &rng)),
                          size: height * 0.09, angle: CGFloat.random(in: -0.6...0.6, using: &rng), greens: greens)
            }
        }
        potShape(ctx, base: base, width: potW, height: potH, color: pot.scaled(light))
    }

    private static func stem(_ ctx: CGContext, from: CGPoint, to: CGPoint, color: RGB, width: CGFloat) {
        let mid = CGPoint(x: (from.x + to.x) / 2 + (to.y - from.y) * 0.08, y: (from.y + to.y) / 2)
        ctx.move(to: from)
        ctx.addQuadCurve(to: to, control: mid)
        ctx.setStrokeColor(color.cg)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    /// A broad heart-shaped leaf with deep splits from the edge toward the midrib and a few holes, as a monstera has.
    /// It grows from its base at `c` along `angle` (0 up, positive toward the right).
    private static func monsteraLeaf(_ ctx: CGContext, at c: CGPoint, size: CGFloat, angle: CGFloat, greens: (deep: RGB, mid: RGB, light: RGB)) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: -angle)
        let w = size * 0.62
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: size * 0.04))
        path.addCurve(to: CGPoint(x: -w, y: size * 0.30), control1: CGPoint(x: -w * 0.35, y: -size * 0.14), control2: CGPoint(x: -w * 1.02, y: size * 0.02))
        path.addCurve(to: CGPoint(x: 0, y: size), control1: CGPoint(x: -w * 0.98, y: size * 0.66), control2: CGPoint(x: -w * 0.45, y: size * 0.92))
        path.addCurve(to: CGPoint(x: w, y: size * 0.30), control1: CGPoint(x: w * 0.45, y: size * 0.92), control2: CGPoint(x: w * 0.98, y: size * 0.66))
        path.addCurve(to: CGPoint(x: 0, y: size * 0.04), control1: CGPoint(x: w * 1.02, y: size * 0.02), control2: CGPoint(x: w * 0.35, y: -size * 0.14))
        path.closeSubpath()
        // Its own layer, so the splits cut through the leaf and not through the wall behind it.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        BackdropPainter.fill(ctx, path, gradient: [(at: 0, color: greens.deep), (at: 0.55, color: greens.mid), (at: 1, color: greens.light)],
                             from: CGPoint(x: w * 0.8, y: size * 0.1), to: CGPoint(x: -w * 0.6, y: size * 0.9))
        ctx.setBlendMode(.destinationOut)
        for k in 0..<5 {
            let y = size * (0.20 + 0.15 * CGFloat(k))
            for side: CGFloat in [-1, 1] {
                // A wedge from beyond the edge in toward the midrib, curving with the veins.
                let slit = CGMutablePath()
                slit.move(to: CGPoint(x: side * w * 1.1, y: y + size * 0.02))
                slit.addQuadCurve(to: CGPoint(x: side * w * 0.22, y: y - size * 0.05), control: CGPoint(x: side * w * 0.6, y: y + size * 0.03))
                slit.addQuadCurve(to: CGPoint(x: side * w * 1.1, y: y + size * 0.085), control: CGPoint(x: side * w * 0.62, y: y + size * 0.05))
                slit.closeSubpath()
                ctx.addPath(slit); ctx.fillPath()
                if k > 0 && k < 4 {
                    ctx.fillEllipse(in: CGRect(x: side * w * 0.3 - size * 0.025, y: y + size * 0.05, width: size * 0.05, height: size * 0.035))
                }
            }
        }
        ctx.setBlendMode(.normal)
        ctx.move(to: CGPoint(x: 0, y: size * 0.04)); ctx.addLine(to: CGPoint(x: 0, y: size * 0.96))
        ctx.setStrokeColor(greens.light.cg(0.45)); ctx.setLineWidth(1.6); ctx.strokePath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private static func ovalLeaf(_ ctx: CGContext, at c: CGPoint, size: CGFloat, angle: CGFloat, greens: (deep: RGB, mid: RGB, light: RGB)) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -size * 0.55))
        path.addCurve(to: CGPoint(x: 0, y: size * 0.55), control1: CGPoint(x: -size * 0.62, y: -size * 0.4), control2: CGPoint(x: -size * 0.55, y: size * 0.55))
        path.addCurve(to: CGPoint(x: 0, y: -size * 0.55), control1: CGPoint(x: size * 0.55, y: size * 0.55), control2: CGPoint(x: size * 0.62, y: -size * 0.4))
        BackdropPainter.fill(ctx, path, gradient: [(at: 0, color: greens.deep), (at: 0.55, color: greens.mid), (at: 1, color: greens.light)],
                             from: CGPoint(x: size * 0.5, y: -size * 0.5), to: CGPoint(x: -size * 0.4, y: size * 0.5))
        ctx.move(to: CGPoint(x: 0, y: -size * 0.5)); ctx.addLine(to: CGPoint(x: 0, y: size * 0.45))
        ctx.setStrokeColor(greens.light.cg(0.45)); ctx.setLineWidth(1.1); ctx.strokePath()
        ctx.restoreGState()
    }

    private static func heartLeaf(_ ctx: CGContext, at c: CGPoint, size: CGFloat, angle: CGFloat, greens: (deep: RGB, mid: RGB, light: RGB)) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: size))
        path.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -size * 0.9, y: size * 0.6), control2: CGPoint(x: -size * 0.6, y: -size * 0.1))
        path.addCurve(to: CGPoint(x: 0, y: size), control1: CGPoint(x: size * 0.6, y: -size * 0.1), control2: CGPoint(x: size * 0.9, y: size * 0.6))
        BackdropPainter.fill(ctx, path, gradient: [(at: 0, color: greens.deep), (at: 1, color: greens.light)],
                             from: CGPoint(x: size * 0.4, y: 0), to: CGPoint(x: -size * 0.3, y: size))
        ctx.restoreGState()
    }

    /// A pot: a slightly tapered cylinder, lit from the left, with a rim.
    static func potShape(_ ctx: CGContext, base: CGPoint, width: CGFloat, height: CGFloat, color: RGB) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: base.x - width * 0.40, y: base.y))
        path.addLine(to: CGPoint(x: base.x + width * 0.40, y: base.y))
        path.addLine(to: CGPoint(x: base.x + width * 0.5, y: base.y + height * 0.88))
        path.addLine(to: CGPoint(x: base.x - width * 0.5, y: base.y + height * 0.88))
        path.closeSubpath()
        BackdropPainter.fill(ctx, path, color.cg, shadow: 12, shadowAlpha: 0.35)
        BackdropPainter.fill(ctx, path, gradient: [(at: 0, color: color.mixed(RGB(1, 1, 1), 0.22)), (at: 0.4, color: color), (at: 1, color: color.scaled(0.55))],
                             from: CGPoint(x: base.x - width * 0.5, y: 0), to: CGPoint(x: base.x + width * 0.5, y: 0))
        let rim = CGRect(x: base.x - width * 0.54, y: base.y + height * 0.84, width: width * 1.08, height: height * 0.16)
        BackdropPainter.fill(ctx, BackdropPainter.rounded(rim, 3),
                             gradient: [(at: 0, color: color.mixed(RGB(1, 1, 1), 0.3)), (at: 0.5, color: color.scaled(0.95)), (at: 1, color: color.scaled(0.6))],
                             from: CGPoint(x: rim.minX, y: 0), to: CGPoint(x: rim.maxX, y: 0))
    }

    // MARK: Lamps

    /// A pendant: cord from the top, a shade or bare bulb, and the warm light it throws.
    static func pendant(_ ctx: CGContext, x: CGFloat, y: CGFloat, shade: RGB?, glow: Double = 1) {
        ctx.setStrokeColor(RGB(0.08, 0.08, 0.08).cg(0.85))
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: x, y: 720)); ctx.addLine(to: CGPoint(x: x, y: y + 20)); ctx.strokePath()
        BackdropPainter.glow(ctx, at: CGPoint(x: x, y: y - 10), radius: 260 * glow, color: lamplight, alpha: 0.35, blend: .screen)
        if let shade {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - 8, y: y + 22)); path.addLine(to: CGPoint(x: x + 8, y: y + 22))
            path.addLine(to: CGPoint(x: x + 46, y: y - 14)); path.addLine(to: CGPoint(x: x - 46, y: y - 14)); path.closeSubpath()
            BackdropPainter.fill(ctx, path, gradient: [(at: 0, color: shade.mixed(RGB(1, 1, 1), 0.2)), (at: 0.5, color: shade), (at: 1, color: shade.scaled(0.55))],
                                 from: CGPoint(x: x - 46, y: 0), to: CGPoint(x: x + 46, y: 0))
            BackdropPainter.glow(ctx, at: CGPoint(x: x, y: y - 16), radius: 40, color: RGB(1, 0.93, 0.78), alpha: 0.95, squash: 0.35, blend: .screen)
        } else {
            BackdropPainter.glow(ctx, at: CGPoint(x: x, y: y), radius: 46 * glow, color: RGB(1, 0.86, 0.6), alpha: 0.9, blend: .screen)
            ctx.setFillColor(RGB(1, 0.95, 0.82).cg)
            ctx.fillEllipse(in: CGRect(x: x - 9, y: y - 12, width: 18, height: 24))
        }
    }

    /// A table lamp on a surface at `base`: base, shade lit from inside, and its glow up the wall.
    static func tableLamp(_ ctx: CGContext, base: CGPoint, height: CGFloat, shade: RGB, body: RGB) {
        let shadeTop = base.y + height, shadeBottom = base.y + height * 0.55
        BackdropPainter.glow(ctx, at: CGPoint(x: base.x, y: shadeTop + 10), radius: height * 1.7, color: lamplight, alpha: 0.42, squash: 1.2, blend: .screen)
        BackdropPainter.glow(ctx, at: CGPoint(x: base.x, y: shadeBottom - 4), radius: height * 1.1, color: lamplight, alpha: 0.30, squash: 0.5, blend: .screen)
        let stemPath = BackdropPainter.rounded(CGRect(x: base.x - height * 0.035, y: base.y, width: height * 0.07, height: height * 0.58), 2)
        BackdropPainter.fill(ctx, stemPath, body.cg, shadow: 8, shadowAlpha: 0.3)
        let foot = CGRect(x: base.x - height * 0.18, y: base.y, width: height * 0.36, height: height * 0.06)
        BackdropPainter.fill(ctx, BackdropPainter.rounded(foot, 3), body.cg, shadow: 8, shadowAlpha: 0.3)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: base.x - height * 0.2, y: shadeTop)); path.addLine(to: CGPoint(x: base.x + height * 0.2, y: shadeTop))
        path.addLine(to: CGPoint(x: base.x + height * 0.32, y: shadeBottom)); path.addLine(to: CGPoint(x: base.x - height * 0.32, y: shadeBottom)); path.closeSubpath()
        BackdropPainter.fill(ctx, path, gradient: [(at: 0, color: shade.mixed(RGB(1, 0.95, 0.85), 0.55)), (at: 0.5, color: shade.mixed(lamplight, 0.35)), (at: 1, color: shade.scaled(0.8))],
                             from: CGPoint(x: base.x - height * 0.3, y: 0), to: CGPoint(x: base.x + height * 0.3, y: 0))
    }

    /// A window: frame, bars and what is outside (`view` paints it), with a sill.
    static func window(_ ctx: CGContext, _ rect: CGRect, frame: RGB, panes: (Int, Int), view: (CGContext, CGRect) -> Void) {
        BackdropPainter.fill(ctx, CGPath(rect: rect.insetBy(dx: -10, dy: -10), transform: nil), frame.cg, shadow: 16, shadowAlpha: 0.35)
        ctx.saveGState()
        ctx.clip(to: rect)
        view(ctx, rect)
        ctx.restoreGState()
        let bar: CGFloat = max(5, rect.width * 0.022)
        ctx.setFillColor(frame.cg)
        for i in 1..<panes.0 { ctx.fill(CGRect(x: rect.minX + rect.width * CGFloat(i) / CGFloat(panes.0) - bar / 2, y: rect.minY, width: bar, height: rect.height)) }
        for j in 1..<panes.1 { ctx.fill(CGRect(x: rect.minX, y: rect.minY + rect.height * CGFloat(j) / CGFloat(panes.1) - bar / 2, width: rect.width, height: bar)) }
        ctx.setFillColor(frame.mixed(RGB(1, 1, 1), 0.2).cg)
        ctx.fill(CGRect(x: rect.minX - 20, y: rect.minY - 18, width: rect.width + 40, height: 10))
    }
}
