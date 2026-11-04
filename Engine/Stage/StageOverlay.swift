import CoreGraphics
import Foundation

/// The chrome drawn over the preview while you arrange things: cursors where your pinches are, the ring that answers as one comes
/// near, the selection while something is held, the guides it settles onto and the stretch line of a two-handed resize.
///
/// This is only ever laid over your own preview. The picture sent to the call never has it: viewers just see the panel move.
struct StageOverlayState: Equatable {
    struct Cursor: Equatable {
        enum Phase: Equatable {
            /// A hand shaped for pinching, nowhere in particular.
            case free
            /// Close enough to the item to grab it.
            case hovering
            /// Pinched on the item and holding: `progress` 0...1 toward taking hold.
            case arming(Double)
            case holding
        }

        /// Between the thumb tip and the index tip, in pixels.
        var point: CGPoint
        /// 0 for fingertips apart, 1 for pinched.
        var closeness: Double
        var phase: Phase
        /// Where it has just been, oldest first.
        var trail: [CGPoint]
        var alpha: Double
    }

    struct ItemChrome: Equatable {
        /// The item's outline: lower left, lower right, upper right, upper left.
        var quad: [CGPoint]
        var cornerRadius: Double
        /// 0...1: how near a hand (or the mouse) is.
        var hover: Double
        /// 0...1: how closed the nearest pinch is. The ring draws in toward the item as it closes.
        var tighten: Double
        /// 0...1: a pinch held on the item, filling toward taking hold.
        var arming: Double
        /// 0...1: the selection showing (held, or just let go).
        var selected: Double
        /// 0...1 through the pulse that marks taking hold, or nil.
        var pulse: Double?
        var readout: String?
        var showsHandles: Bool
    }

    struct GuideMark: Equatable {
        var guide: StageGuide
        var alpha: Double
    }

    struct Stretch: Equatable {
        var a: CGPoint
        var b: CGPoint
        var label: String
        var alpha: Double
    }

    var cursors: [Cursor] = []
    var item: ItemChrome?
    var guides: [GuideMark] = []
    var stretch: Stretch?

    var isEmpty: Bool { cursors.isEmpty && item == nil && guides.isEmpty && stretch == nil }
}

enum StageOverlay {
    /// Draws the chrome into `ctx`, whose drawing is already scaled so that one unit is one picture pixel. `pixel` is how many
    /// picture pixels one pixel of the finished image covers, so hairlines stay hairlines at any size.
    static func draw(_ state: StageOverlayState, in ctx: CGContext, pixel: CGFloat, picture: CGSize = StageGeometry.picture) {
        guard !state.isEmpty else { return }
        ctx.saveGState()
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        for mark in state.guides { drawGuide(mark, in: ctx, pixel: pixel, picture: picture) }
        if let item = state.item { drawItem(item, in: ctx, pixel: pixel, picture: picture) }
        if let stretch = state.stretch { drawStretch(stretch, in: ctx, pixel: pixel) }
        for cursor in state.cursors { drawCursor(cursor, in: ctx, pixel: pixel) }
        ctx.restoreGState()
    }

    // MARK: Guides

    private static func drawGuide(_ mark: StageOverlayState.GuideMark, in ctx: CGContext, pixel: CGFloat, picture: CGSize) {
        guard mark.alpha > 0.01 else { return }
        let g = mark.guide
        ctx.saveGState()
        let p = CGFloat(g.position)
        let a = g.vertical ? CGPoint(x: p, y: 0) : CGPoint(x: 0, y: p)
        let b = g.vertical ? CGPoint(x: p, y: picture.height) : CGPoint(x: picture.width, y: p)
        // A soft glow under a crisp hairline.
        ctx.setShadow(offset: .zero, blur: 5 * pixel, color: StageArt.color(StageArt.accent, 0.8 * mark.alpha))
        ctx.setStrokeColor(StageArt.color(StageArt.accent, 0.95 * mark.alpha))
        ctx.setLineWidth(1.2 * pixel)
        switch g.kind {
        case .centre: break
        case .third: ctx.setLineDash(phase: 0, lengths: [6 * pixel, 5 * pixel])
        case .margin: ctx.setLineDash(phase: 0, lengths: [1.5 * pixel, 4 * pixel])
        }
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: The item

    private static func drawItem(_ item: StageOverlayState.ItemChrome, in ctx: CGContext, pixel: CGFloat, picture: CGSize) {
        let radius = CGFloat(item.cornerRadius)
        let contrast = StageArt.black(0.38)

        // The hover ring: appears as a hand nears, and draws in toward the item as thumb and index close.
        let ringAlpha = item.hover * (0.38 + 0.62 * item.tighten) * (1 - 0.6 * item.selected)
        let gap = (11 - 7 * CGFloat(item.tighten)) * pixel
        if ringAlpha > 0.01 {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 3 * pixel, color: contrast)
            ctx.addPath(StageArt.roundedQuad(item.quad, radius: radius, grow: gap))
            ctx.setStrokeColor(StageArt.white(0.9 * ringAlpha))
            ctx.setLineWidth(1.6 * pixel)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Filling toward taking hold: the ring traced in the accent colour.
        if item.arming > 0.01 {
            let path = StageArt.roundedQuad(item.quad, radius: radius, grow: gap)
            let perimeter = length(of: path)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 6 * pixel, color: StageArt.color(StageArt.accent, 0.7))
            ctx.addPath(path)
            ctx.setStrokeColor(StageArt.color(StageArt.accent, 0.98))
            ctx.setLineWidth(2.6 * pixel)
            ctx.setLineDash(phase: 0, lengths: [CGFloat(item.arming) * perimeter, perimeter * 2])
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Took hold: a ring that leaps out and fades.
        if let p = item.pulse {
            let e = 1 - pow(1 - p, 3)
            ctx.saveGState()
            ctx.addPath(StageArt.roundedQuad(item.quad, radius: radius, grow: gap + CGFloat(e) * 22 * pixel))
            ctx.setStrokeColor(StageArt.color(StageArt.accent, 0.9 * (1 - p) * (1 - p)))
            ctx.setLineWidth((2.6 - 1.4 * CGFloat(p)) * pixel)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // The selection: a fine border, four small handles and the size.
        let s = item.selected
        guard s > 0.01 else { return }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -0.5 * pixel), blur: 2.5 * pixel, color: StageArt.black(0.45 * s))
        ctx.addPath(StageArt.roundedQuad(item.quad, radius: radius, grow: 1.5 * pixel))
        ctx.setStrokeColor(StageArt.white(0.95 * s))
        ctx.setLineWidth(1.5 * pixel)
        ctx.strokePath()
        ctx.restoreGState()

        if item.showsHandles {
            let side = 7 * pixel
            for corner in item.quad {
                let r = CGRect(x: corner.x - side / 2, y: corner.y - side / 2, width: side, height: side)
                let path = CGPath(roundedRect: r, cornerWidth: side * 0.3, cornerHeight: side * 0.3, transform: nil)
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -1 * pixel), blur: 3 * pixel, color: StageArt.black(0.4 * s))
                ctx.addPath(path)
                ctx.setFillColor(StageArt.white(s))
                ctx.fillPath()
                ctx.restoreGState()
                ctx.addPath(path)
                ctx.setStrokeColor(StageArt.color(StageArt.accent, 0.9 * s))
                ctx.setLineWidth(1.2 * pixel)
                ctx.strokePath()
            }
        }

        if let text = item.readout {
            let top = CGPoint(x: (item.quad[2].x + item.quad[3].x) / 2, y: max(item.quad[2].y, item.quad[3].y))
            let size = 11 * pixel
            var at = CGPoint(x: top.x, y: top.y + size * 1.7)
            // Above the item, unless that is off the top of the picture: then just inside it.
            if at.y + size > picture.height - 4 * pixel { at.y = top.y - size * 1.9 }
            ctx.saveGState()
            ctx.setAlpha(CGFloat(min(1, s * 1.2)))
            StageArt.pill(text, at: at, size: size, in: ctx)
            ctx.restoreGState()
        }
    }

    /// Roughly how long a path is, for tracing part of it.
    static func length(of path: CGPath) -> CGFloat {
        var total: CGFloat = 0
        var last: CGPoint?
        var start: CGPoint?
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                last = e.points[0]
                start = e.points[0]
            case .addLineToPoint:
                if let l = last { total += hypot(e.points[0].x - l.x, e.points[0].y - l.y) }
                last = e.points[0]
            case .addQuadCurveToPoint:
                if let l = last { total += hypot(e.points[1].x - l.x, e.points[1].y - l.y) }
                last = e.points[1]
            case .addCurveToPoint:
                if let l = last { total += hypot(e.points[2].x - l.x, e.points[2].y - l.y) * 1.05 }
                last = e.points[2]
            case .closeSubpath:
                if let l = last, let s = start { total += hypot(s.x - l.x, s.y - l.y) }
                last = start
            @unknown default:
                break
            }
        }
        return max(total, 1)
    }

    // MARK: Two hands

    private static func drawStretch(_ s: StageOverlayState.Stretch, in ctx: CGContext, pixel: CGFloat) {
        guard s.alpha > 0.01 else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(s.alpha))
        ctx.setShadow(offset: .zero, blur: 3 * pixel, color: StageArt.black(0.4))
        ctx.setStrokeColor(StageArt.white(0.88))
        ctx.setLineWidth(1.6 * pixel)
        ctx.setLineDash(phase: 0, lengths: [5 * pixel, 4 * pixel])
        ctx.move(to: s.a)
        ctx.addLine(to: s.b)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        for p in [s.a, s.b] {
            let r = 4.5 * pixel
            ctx.setFillColor(StageArt.color(StageArt.accent))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.setStrokeColor(StageArt.white(0.95))
            ctx.setLineWidth(1.4 * pixel)
            ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        ctx.restoreGState()
        ctx.saveGState()
        ctx.setAlpha(CGFloat(s.alpha))
        let mid = CGPoint(x: (s.a.x + s.b.x) / 2, y: (s.a.y + s.b.y) / 2 + 22 * pixel)
        StageArt.pill(s.label, at: mid, size: 12 * pixel, in: ctx, fill: StageArt.color(StageArt.accent, 0.92), rim: StageArt.white(0.35))
        ctx.restoreGState()
    }

    // MARK: Cursors

    private static func drawCursor(_ c: StageOverlayState.Cursor, in ctx: CGContext, pixel: CGFloat) {
        guard c.alpha > 0.01 else { return }
        let k = CGFloat(c.closeness)
        let holding = c.phase == .holding
        let r = (12.5 - 4.5 * k) * pixel

        ctx.saveGState()
        ctx.setAlpha(CGFloat(c.alpha))

        // A short fading trail.
        if c.trail.count > 1 {
            for i in 1..<c.trail.count {
                let t = CGFloat(i) / CGFloat(c.trail.count)
                ctx.setStrokeColor(StageArt.white(0.28 * Double(t)))
                ctx.setLineWidth(r * 0.55 * t)
                ctx.move(to: c.trail[i - 1])
                ctx.addLine(to: c.trail[i])
                ctx.strokePath()
            }
        }

        let disc = CGRect(x: c.point.x - r, y: c.point.y - r, width: r * 2, height: r * 2)
        // Body: frosted glass that fills as the fingers close; solid accent while holding.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1 * pixel), blur: 5 * pixel, color: StageArt.black(0.42))
        ctx.setFillColor(holding ? StageArt.color(StageArt.accent, 0.92) : StageArt.white(0.16 + 0.26 * Double(k)))
        ctx.fillEllipse(in: disc)
        ctx.restoreGState()
        // A glint along the upper left, as on glass.
        ctx.saveGState()
        ctx.addEllipse(in: disc)
        ctx.clip()
        let glint = [StageArt.white(holding ? 0.35 : 0.5), StageArt.white(0)] as CFArray
        if let g = CGGradient(colorsSpace: StageArt.space, colors: glint, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: disc.minX, y: disc.maxY), end: CGPoint(x: disc.midX, y: disc.midY), options: [])
        }
        ctx.restoreGState()
        // Rim.
        ctx.setStrokeColor(StageArt.white(0.92))
        ctx.setLineWidth(1.4 * pixel)
        ctx.strokeEllipse(in: disc.insetBy(dx: 0.7 * pixel, dy: 0.7 * pixel))

        if holding {
            let d = 3 * pixel
            ctx.setFillColor(StageArt.white(0.98))
            ctx.fillEllipse(in: CGRect(x: c.point.x - d, y: c.point.y - d, width: d * 2, height: d * 2))
        } else {
            // Thumb and finger: two small dots that meet as you pinch.
            let spread = r * 0.48 * (1 - k)
            let d = 1.8 * pixel
            ctx.setFillColor(StageArt.white(0.9))
            for side in [-1.0, 1.0] {
                let p = CGPoint(x: c.point.x + CGFloat(side) * spread, y: c.point.y)
                ctx.fillEllipse(in: CGRect(x: p.x - d, y: p.y - d, width: d * 2, height: d * 2))
            }
        }

        if case .arming(let progress) = c.phase {
            ctx.setStrokeColor(StageArt.color(StageArt.accent, 0.98))
            ctx.setLineWidth(2.4 * pixel)
            let ring = r + 4 * pixel
            ctx.addArc(center: c.point, radius: ring, startAngle: .pi / 2, endAngle: .pi / 2 - CGFloat(progress) * 2 * .pi, clockwise: true)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
