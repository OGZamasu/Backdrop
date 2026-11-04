import CoreGraphics
import Foundation

/// A made-up right (or, mirrored, left) hand for the how-to demo, built the same way as the test fixtures: palm length `size`,
/// turned by `angle`, with `pinch` (0...1) bending the index finger and thumb together.
enum StageGhostHand {
    private static let knuckles: [Finger: (Double, Double)] = [.index: (0.30, 0.97), .middle: (0.06, 1.0), .ring: (-0.17, 0.95), .little: (-0.38, 0.83)]

    /// Where the pinch point sits relative to the wrist when fully pinched, in palms, upright.
    static let pinchOffset = (x: 0.60, y: 1.345)

    static func make(pinch: Double, pinchPoint: CGPoint, size: Double, angle: Double, mirrored: Bool = false, id: Int) -> HandState {
        var local = [(Double, Double)](repeating: (0, 0), count: HandJoint.count)
        func set(_ j: HandJoint, _ x: Double, _ y: Double) { local[j.rawValue] = (x, y) }
        set(.thumbCMC, 0.22, 0.22); set(.thumbMP, 0.40, 0.42); set(.thumbIP, 0.62, 0.66); set(.thumbTip, 0.80, 0.86)
        // Index out; the others loosely curled, as a hand reaching to pick something up holds them.
        let k = knuckles[.index]!
        set(.indexMCP, k.0, k.1)
        set(.indexPIP, k.0 + sin(0.09) * 0.40, k.1 + cos(0.09) * 0.40)
        set(.indexDIP, k.0 + sin(0.09) * 0.64, k.1 + cos(0.09) * 0.64)
        set(.indexTip, k.0 + sin(0.09) * 0.84, k.1 + cos(0.09) * 0.84)
        for (finger, mcp, pip, dip, tip) in [(Finger.middle, HandJoint.middleMCP, HandJoint.middlePIP, HandJoint.middleDIP, HandJoint.middleTip),
                                             (.ring, .ringMCP, .ringPIP, .ringDIP, .ringTip), (.little, .littleMCP, .littlePIP, .littleDIP, .littleTip)] {
            let c = knuckles[finger]!
            set(mcp, c.0, c.1); set(pip, c.0, c.1 + 0.09); set(dip, c.0, c.1 - 0.04); set(tip, c.0, c.1 - 0.18)
        }
        let p = min(1, max(0, pinch))
        for (joint, x, y) in [(HandJoint.indexPIP, 0.38, 1.25), (.indexDIP, 0.52, 1.42), (.indexTip, 0.60, 1.38),
                              (.thumbMP, 0.42, 0.45), (.thumbIP, 0.56, 0.86), (.thumbTip, 0.60, 1.31)] {
            let a = local[joint.rawValue]
            set(joint, a.0 + (x - a.0) * p, a.1 + (y - a.1) * p)
        }
        // Place it so that its pinch point lands on `pinchPoint`.
        let c = cos(angle), s = sin(angle)
        let tips = ((local[HandJoint.thumbTip.rawValue].0 + local[HandJoint.indexTip.rawValue].0) / 2,
                    (local[HandJoint.thumbTip.rawValue].1 + local[HandJoint.indexTip.rawValue].1) / 2)
        func place(_ q: (Double, Double)) -> CGPoint {
            let x = (mirrored ? -(q.0 - tips.0) : q.0 - tips.0) * size, y = (q.1 - tips.1) * size
            return CGPoint(x: Double(pinchPoint.x) + x * c - y * s, y: Double(pinchPoint.y) + x * s + y * c)
        }
        return HandState(id: id, joints: local.map(place))
    }
}

/// The animated how-to in the Present pane: a ghost hand grabs the panel and lets it glide onto a guide, two hands stretch it, and a
/// double pinch zooms it up and back. It is not a recording: scripted made-up hands are fed to the real `StageHandController` and
/// drawn with the real `StageOverlay`, so it shows exactly what the preview will.
final class StageDemoPlayer {
    static let duration = 10.6
    /// The three steps it shows, with the second each one starts.
    static let acts: [(title: String, start: Double)] = [("Pinch near the panel to grab it", 0), ("Pinch with both hands to resize", 3.4),
                                                         ("Double pinch to zoom", 6.8)]

    private var controller: StageHandController
    private var clock = 0.0
    private(set) var output: StageControlOutput?
    private(set) var hands: [HandState] = []
    private static let start: StageLayout = {
        var l = StageLayout()
        l.arrangement = .floatingPanel
        l.panel = StageFrame(center: CGPoint(x: 0.42, y: 0.56), size: 0.5)
        l.tilt = 0
        l.depth = 0
        l.handControl = true
        return l
    }()

    init() { controller = StageHandController(layout: Self.start) }

    /// Which step is showing at `time` (looping).
    static func act(at time: Double) -> Int {
        let t = time.truncatingRemainder(dividingBy: duration)
        return acts.lastIndex { t >= $0.start } ?? 0
    }

    /// How visible the whole demo is: it fades out at the end of a loop and back in at the start, so the reset is never seen.
    static func fade(at time: Double) -> Double {
        let t = time.truncatingRemainder(dividingBy: duration)
        return min(1, t / 0.3, (duration - t) / 0.35)
    }

    /// Runs the demo up to `time` seconds (it loops) and returns the frame.
    @discardableResult
    func advance(to time: Double) -> StageControlOutput? {
        let t = max(0, time).truncatingRemainder(dividingBy: Self.duration)
        if t < clock || output == nil {
            controller = StageHandController(layout: Self.start)
            clock = 0
        }
        let step = 1.0 / 60
        while clock + step <= t + 1e-9 {
            clock += step
            hands = Self.script(at: clock)
            output = controller.step(StageControlInput(hands: hands, dt: step, aspect: 16.0 / 9))
        }
        if output == nil {
            hands = Self.script(at: 0)
            output = controller.step(StageControlInput(hands: hands, dt: step, aspect: 16.0 / 9))
        }
        return output
    }

    // MARK: The script

    private struct Key {
        var t: Double
        var p: CGPoint
        var pinch: Double
    }

    private static func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }

    private static func sample(_ keys: [Key], at t: Double) -> (CGPoint, Double)? {
        guard let first = keys.first, let last = keys.last, t >= first.t, t <= last.t else { return nil }
        guard let i = keys.lastIndex(where: { $0.t <= t }), i + 1 < keys.count else { return (last.p, last.pinch) }
        let a = keys[i], b = keys[i + 1]
        let k = ease((t - a.t) / max(1e-6, b.t - a.t))
        return (CGPoint(x: a.p.x + (b.p.x - a.p.x) * k, y: a.p.y + (b.p.y - a.p.y) * k), a.pinch + (b.pinch - a.pinch) * k)
    }

    private static let open = 0.12, shut = 1.0

    // The panel starts with its right edge at x = 858 and its middle at 538; the script is laid out against that.
    private static let right: [[Key]] = [
        // Grab, drag toward the middle, let go: it glides onto the centre guide.
        [Key(t: 0.15, p: CGPoint(x: 1120, y: 150), pinch: open), Key(t: 0.95, p: CGPoint(x: 872, y: 420), pinch: open),
         Key(t: 1.1, p: CGPoint(x: 870, y: 420), pinch: open), Key(t: 1.3, p: CGPoint(x: 870, y: 420), pinch: shut),
         Key(t: 1.5, p: CGPoint(x: 870, y: 420), pinch: shut), Key(t: 2.15, p: CGPoint(x: 962, y: 426), pinch: shut),
         Key(t: 2.3, p: CGPoint(x: 968, y: 427), pinch: open), Key(t: 3.2, p: CGPoint(x: 1180, y: 90), pinch: open)],
        // The right hand of the stretch.
        [Key(t: 3.5, p: CGPoint(x: 1160, y: 140), pinch: open), Key(t: 4.2, p: CGPoint(x: 975, y: 402), pinch: open),
         Key(t: 4.3, p: CGPoint(x: 975, y: 402), pinch: open), Key(t: 4.5, p: CGPoint(x: 975, y: 402), pinch: shut),
         Key(t: 4.75, p: CGPoint(x: 975, y: 402), pinch: shut), Key(t: 5.7, p: CGPoint(x: 1078, y: 420), pinch: shut),
         Key(t: 5.85, p: CGPoint(x: 1080, y: 421), pinch: open), Key(t: 6.6, p: CGPoint(x: 1200, y: 120), pinch: open)],
        // Double pinch on the panel.
        [Key(t: 6.9, p: CGPoint(x: 1150, y: 160), pinch: open), Key(t: 7.6, p: CGPoint(x: 900, y: 520), pinch: open),
         Key(t: 7.7, p: CGPoint(x: 900, y: 520), pinch: open), Key(t: 7.8, p: CGPoint(x: 900, y: 520), pinch: shut),
         Key(t: 7.92, p: CGPoint(x: 900, y: 520), pinch: shut), Key(t: 8.0, p: CGPoint(x: 900, y: 520), pinch: open),
         Key(t: 8.07, p: CGPoint(x: 900, y: 520), pinch: open), Key(t: 8.15, p: CGPoint(x: 900, y: 520), pinch: shut),
         Key(t: 8.27, p: CGPoint(x: 900, y: 520), pinch: shut), Key(t: 8.36, p: CGPoint(x: 900, y: 520), pinch: open),
         Key(t: 9.4, p: CGPoint(x: 1190, y: 110), pinch: open)],
    ]

    private static let left: [Key] = [
        Key(t: 3.5, p: CGPoint(x: 120, y: 140), pinch: open), Key(t: 4.25, p: CGPoint(x: 305, y: 402), pinch: open),
        Key(t: 4.4, p: CGPoint(x: 305, y: 402), pinch: open), Key(t: 4.6, p: CGPoint(x: 305, y: 402), pinch: shut),
        Key(t: 4.75, p: CGPoint(x: 305, y: 402), pinch: shut), Key(t: 5.7, p: CGPoint(x: 202, y: 420), pinch: shut),
        Key(t: 5.85, p: CGPoint(x: 200, y: 421), pinch: open), Key(t: 6.6, p: CGPoint(x: 80, y: 120), pinch: open),
    ]

    /// The made-up hands in view at `t`.
    static func script(at t: Double) -> [HandState] {
        var out: [HandState] = []
        for (n, keys) in right.enumerated() {
            if let (p, pinch) = sample(keys, at: t) {
                out.append(StageGhostHand.make(pinch: pinch, pinchPoint: p, size: 120, angle: 0.42, id: 10 + n))
            }
        }
        if let (p, pinch) = sample(left, at: t) {
            out.append(StageGhostHand.make(pinch: pinch, pinchPoint: p, size: 120, angle: -0.42, mirrored: true, id: 20))
        }
        return out
    }

    // MARK: Drawing

    /// The demo at `time`, `width` by `height` pixels.
    func render(at time: Double, width: Int, height: Int) -> CGImage? {
        guard let out = advance(to: time), let ctx = StageArt.bitmap(width: width, height: height) else { return nil }
        let s = CGFloat(width) / StageGeometry.picture.width
        ctx.scaleBy(x: s, y: s)
        let pixel = 1 / s
        Self.drawRoom(in: ctx)
        Self.drawPanel(out.layout, in: ctx, pixel: pixel)
        Self.drawPresenter(in: ctx)
        for hand in hands { Self.drawGhost(hand, in: ctx, pixel: pixel) }
        StageOverlay.draw(out.overlay, in: ctx, pixel: pixel)
        return ctx.makeImage()
    }

    private static func drawRoom(in ctx: CGContext) {
        let size = StageGeometry.picture
        let colors = [StageArt.color(SIMD3(0.16, 0.18, 0.24)), StageArt.color(SIMD3(0.06, 0.065, 0.09))] as CFArray
        if let g = CGGradient(colorsSpace: StageArt.space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: size.width * 0.3, y: size.height), end: CGPoint(x: size.width * 0.6, y: 0),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        let pool = [StageArt.color(SIMD3(0.35, 0.5, 0.9), 0.16), StageArt.color(SIMD3(0.35, 0.5, 0.9), 0)] as CFArray
        if let g = CGGradient(colorsSpace: StageArt.space, colors: pool, locations: [0, 1]) {
            let c = CGPoint(x: size.width * 0.45, y: size.height * 0.55)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width * 0.5, options: [])
        }
    }

    private static func drawPanel(_ layout: StageLayout, in ctx: CGContext, pixel: CGFloat) {
        let r = StageGeometry.panelRect(layout.panel, aspect: 16.0 / 9)
        let radius = CGFloat(StageGeometry.cornerRadius(roundness: layout.roundness, height: Double(r.height)))
        let shape = StageArt.continuousRect(r, radius: radius)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -r.height * 0.05 / pixel), blur: r.height * 0.16 / pixel, color: StageArt.black(0.55))
        ctx.addPath(shape)
        ctx.setFillColor(StageArt.color(SIMD3(0.97, 0.97, 0.98)))
        ctx.fillPath()
        ctx.restoreGState()
        // A slide: a title, a few lines and a bar chart, in the accent colours.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let u = r.width / 100
        ctx.setFillColor(StageArt.color(SIMD3(0.12, 0.14, 0.2)))
        ctx.fill(CGRect(x: r.minX, y: r.maxY - u * 7, width: r.width, height: u * 7))
        ctx.setFillColor(StageArt.color(SIMD3(0.16, 0.18, 0.24)))
        ctx.addPath(CGPath(roundedRect: CGRect(x: r.minX + u * 7, y: r.maxY - u * 16, width: u * 40, height: u * 4.2), cornerWidth: u, cornerHeight: u, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(StageArt.color(SIMD3(0.62, 0.65, 0.72)))
        for k in 0..<3 {
            ctx.addPath(CGPath(roundedRect: CGRect(x: r.minX + u * 7, y: r.maxY - u * (24 + Double(k) * 5.2), width: u * (34 - Double(k) * 6), height: u * 2.2),
                               cornerWidth: u * 0.8, cornerHeight: u * 0.8, transform: nil))
            ctx.fillPath()
        }
        let bars: [(Double, SIMD3<Double>)] = [(0.42, SIMD3(0.27, 0.62, 1.0)), (0.62, SIMD3(0.27, 0.62, 1.0)), (0.5, SIMD3(0.36, 0.84, 0.74)),
                                               (0.8, SIMD3(0.27, 0.62, 1.0)), (0.66, SIMD3(0.36, 0.84, 0.74))]
        for (k, bar) in bars.enumerated() {
            let h = r.height * 0.55 * bar.0
            ctx.setFillColor(StageArt.color(bar.1))
            ctx.addPath(CGPath(roundedRect: CGRect(x: r.minX + u * (54 + Double(k) * 8.5), y: r.minY + u * 7, width: u * 6, height: h),
                               cornerWidth: u * 1.2, cornerHeight: u * 1.2, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()
        ctx.addPath(StageArt.continuousRect(r.insetBy(dx: 0.75 * pixel, dy: 0.75 * pixel), radius: radius))
        ctx.setStrokeColor(StageArt.white(0.5))
        ctx.setLineWidth(1 * pixel)
        ctx.strokePath()
    }

    /// A soft silhouette of someone standing in front, so it is clear the panel is behind you.
    private static func drawPresenter(in ctx: CGContext) {
        let ink = StageArt.color(SIMD3(0.09, 0.11, 0.17), 0.94)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 18 * ctx.ctm.a, color: StageArt.color(SIMD3(0.5, 0.65, 1.0), 0.35))
        ctx.setFillColor(ink)
        ctx.fillEllipse(in: CGRect(x: 985, y: 168, width: 110, height: 134))
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 870, y: 0))
        body.addCurve(to: CGPoint(x: 1040, y: 172), control1: CGPoint(x: 882, y: 124), control2: CGPoint(x: 960, y: 168))
        body.addCurve(to: CGPoint(x: 1210, y: 0), control1: CGPoint(x: 1120, y: 168), control2: CGPoint(x: 1198, y: 124))
        body.closeSubpath()
        ctx.addPath(body)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// A hand made of light: a soft translucent fill with a fine bright edge.
    private static func drawGhost(_ hand: HandState, in ctx: CGContext, pixel: CGFloat) {
        let path = CGMutablePath()
        let palm = [hand.wrist, hand[.thumbCMC], hand[.indexMCP], hand[.middleMCP], hand[.ringMCP], hand[.littleMCP]]
        path.addLines(between: palm)
        path.closeSubpath()
        let fingers: [[HandJoint]] = [[.thumbCMC, .thumbMP, .thumbIP, .thumbTip], [.indexMCP, .indexPIP, .indexDIP, .indexTip],
                                      [.middleMCP, .middlePIP, .middleDIP, .middleTip], [.ringMCP, .ringPIP, .ringDIP, .ringTip],
                                      [.littleMCP, .littlePIP, .littleDIP, .littleTip]]
        // One silhouette, so the bright edge runs round the outside of the hand and not between the fingers.
        var shape: CGPath = path.copy(strokingWithWidth: hand.size * 0.22, lineCap: .round, lineJoin: .round, miterLimit: 1).union(path)
        for chain in fingers {
            let line = CGMutablePath()
            line.addLines(between: chain.map { hand[$0] })
            let width = hand.size * (chain[0] == .thumbCMC ? 0.24 : 0.19)
            shape = shape.union(line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1))
        }
        // A soft dark halo first, so the hand reads over a white slide as well as the dark room.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8 / max(pixel, 0.1), color: StageArt.color(SIMD3(0.02, 0.04, 0.12), 0.45))
        ctx.addPath(shape)
        ctx.setFillColor(StageArt.color(SIMD3(0.78, 0.86, 1.0), 0.26))
        ctx.fillPath(using: .winding)
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let sheen = [StageArt.white(0.32), StageArt.white(0.04)] as CFArray
        if let g = CGGradient(colorsSpace: StageArt.space, colors: sheen, locations: [0, 1]) {
            let box = shape.boundingBox
            ctx.drawLinearGradient(g, start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), options: [])
        }
        ctx.restoreGState()
        ctx.addPath(shape)
        ctx.setStrokeColor(StageArt.white(0.85))
        ctx.setLineWidth(1.4 * pixel)
        ctx.strokePath()
    }
}
