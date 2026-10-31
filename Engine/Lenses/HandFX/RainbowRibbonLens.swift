import CoreGraphics
import CoreImage
import simd

/// A long satin ribbon trailing from each hand, like a rhythmic gymnast's. It swings and loops with real weight, twists as it flows,
/// and runs through a soft rainbow. Let go (lower the hand) and it drifts down and fades.
///
/// The ribbon is a chain of points pulled along by the hand and by gravity and kept the right length apart, so a jerky, dropping-out hand
/// still moves it smoothly: the chain itself does the smoothing.
struct RainbowRibbonRig {
    struct Ribbon {
        var points: [SIMD2<Double>] = []
        var previous: [SIMD2<Double>] = []
        var anchor = HandFXSteady(calm: 3.2, eager: 0.03)
        /// Whether a hand is holding it; a dropped ribbon falls.
        var held = true
        /// Where along the rainbow it starts and where its twist is, so two ribbons differ.
        var shift: Double
    }

    /// Points along a ribbon and the gap between them.
    static let count = 52
    static let segment = 11.0
    static let gravity = SIMD2<Double>(0, -560)

    private(set) var memory = HandFXMemory<Ribbon>()
    private(set) var time = 0.0
    private var made = 0

    mutating func removeAll() {
        memory.removeAll()
        made = 0
    }

    /// Where a hand holds its ribbon: the index fingertip when the finger is out, the knuckles when it is curled, and in between when unsure.
    static func grip(of hand: HandState) -> CGPoint {
        HandFXKit.lerp(hand[.middleMCP], hand.indexTip, HandFXPose.extended(.index, in: hand))
    }

    mutating func update(hands: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        var fresh = made
        memory.update(hands, dt: dt, fade: 1.1) { hand in
            defer { fresh += 1 }
            let start = HandFXKit.vector(Self.grip(of: hand))
            let hanging = (0..<Self.count).map { start + SIMD2(0, -Double($0) * Self.segment) }
            return Ribbon(points: hanging, previous: hanging, shift: Double(fresh) * 0.43)
        }
        made = fresh
        for i in memory.entries.indices {
            var entry = memory.entries[i]
            let from = entry.state.anchor.point.map(HandFXKit.vector)
            if entry.visible {
                entry.state.held = true
                entry.state.anchor.update(Self.grip(of: entry.hand), dt: dt, snap: max(220, entry.hand.size * 3))
            } else {
                entry.state.held = false
            }
            let to = entry.state.anchor.point.map(HandFXKit.vector)
            simulate(&entry.state, from: from ?? to, to: to, dt: dt)
            memory.modify(i) { $0 = entry }
        }
    }

    /// Moves the chain on by `dt` in small steps, with its first point following the hand from `from` to `to`.
    private func simulate(_ ribbon: inout Ribbon, from: SIMD2<Double>?, to: SIMD2<Double>?, dt: Double) {
        guard dt > 0, ribbon.points.count == Self.count else { return }
        let steps = max(1, min(4, Int((dt * 120).rounded(.up))))
        let h = dt / Double(steps)
        for step in 1...steps {
            let pin: SIMD2<Double>? = ribbon.held ? (from.flatMap { a in to.map { b in a + (b - a) * (Double(step) / Double(steps)) } } ?? to) : nil
            for i in 0..<Self.count {
                if i == 0, let pin {
                    ribbon.previous[0] = ribbon.points[0]
                    ribbon.points[0] = pin
                    continue
                }
                let p = ribbon.points[i]
                // A slow breeze, so even a still ribbon lives a little.
                let breeze = SIMD2(sin(time * 0.8 + Double(i) * 0.21) * 26, 0)
                let velocity = (p - ribbon.previous[i]) * 0.986
                ribbon.previous[i] = p
                ribbon.points[i] = p + velocity + (Self.gravity + breeze) * h * h
            }
            for _ in 0..<4 {
                for j in 0..<(Self.count - 1) {
                    let d = ribbon.points[j + 1] - ribbon.points[j]
                    let length = max(1e-6, simd_length(d))
                    let off = d * ((length - Self.segment) / length)
                    if j == 0, ribbon.held {
                        ribbon.points[1] -= off
                    } else {
                        ribbon.points[j] += off * 0.5
                        ribbon.points[j + 1] -= off * 0.5
                    }
                }
            }
        }
    }
}

final class RainbowRibbonLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig = RainbowRibbonRig()
    private var hint = HandFXHint()
    private let published = StatusBox()

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hand", detail: "Wave it to swirl a ribbon") }

    func restart() {
        rig.removeAll()
        hint.reset()
    }

    var ribbons: [[CGPoint]] { rig.memory.entries.map { $0.state.points.map(HandFXKit.point) } }
    var isHinting: Bool { hint.isShowing }

    func render(_ input: LensInput) -> CIImage {
        rig.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        published.value = input.hands.isEmpty ? LensStatus("Hold up your hand", detail: "Wave it to swirl a ribbon")
                                              : LensStatus("Twirl!", detail: "Big circles make big loops")
        var out = input.composed
        if !rig.memory.isEmpty, let layer = input.services.overlay({ ctx in draw(in: ctx) }) {
            // Satin is painted, not lit: it sits over the picture with no glow.
            out = layer.composited(over: out).cropped(to: input.rect)
        }
        return hint.compose(over: out, services: input.services, rect: input.rect, accent: HandFXPalette.ribbon[0])
    }

    // MARK: Drawing

    private func draw(in ctx: CGContext) {
        let t = rig.time
        for entry in rig.memory.entries {
            let pts = entry.state.points
            let n = pts.count
            guard n > 2, entry.presence > 0.01 else { continue }
            let scale = min(1.4, max(0.7, entry.hand.size / 110))
            let width = 40 * scale
            // Each point's sideways direction, half-width and which face of the satin shows.
            var left: [CGPoint] = [], right: [CGPoint] = [], facing: [Double] = []
            for i in 0..<n {
                let a = pts[max(0, i - 1)], b = pts[min(n - 1, i + 1)]
                let tangent = simd_length(b - a) > 1e-6 ? simd_normalize(b - a) : SIMD2(0, -1)
                let normal = SIMD2(-tangent.y, tangent.x)
                let twist = cos(Double(i) * 0.25 - t * 2.4 + entry.state.shift * 7)
                let taper = min(1, 0.45 + Double(i) * 0.12) * (i > n - 14 ? 0.35 + 0.65 * Double(n - 1 - i) / 13 : 1)
                let half = width / 2 * (0.2 + 0.8 * abs(twist)) * taper
                left.append(HandFXKit.point(pts[i] + normal * half))
                right.append(HandFXKit.point(pts[i] - normal * half))
                facing.append(twist)
            }
            // A ribbon that is fading is drawn into a layer of its own and faded as a whole, so its overlapping pieces do not show through
            // one another. The layer covers only the ribbon, to keep it cheap.
            let fading = entry.presence < 0.995
            ctx.saveGState()
            if fading {
                let xs = (left + right).map(\.x), ys = (left + right).map(\.y)
                if let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() {
                    ctx.clip(to: CGRect(x: x0 - 4, y: y0 - 4, width: x1 - x0 + 8, height: y1 - y0 + 8))
                }
                ctx.setAlpha(CGFloat(entry.presence))
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            for i in 0..<(n - 1) {
                let base = HandFXPalette.along(HandFXPalette.ribbon, Double(i) / Double(n) * 0.85 + entry.state.shift + t * 0.04)
                // Facing the camera, the satin is bright; turned edge-on it darkens; the back is a deeper shade.
                let f = (facing[i] + facing[i + 1]) / 2
                let shade = (0.62 + 0.38 * abs(f)) * (f < 0 ? 0.8 : 1)
                let colour = base * shade + (f > 0.85 ? (SIMD3(1, 1, 1) - base) * 0.18 * (f - 0.85) / 0.15 : .zero)
                // Each piece reaches a pixel into the next, so no seam shows between them.
                let along = SIMD2(Double(left[i + 1].x - left[i].x), Double(left[i + 1].y - left[i].y))
                let push = simd_length(along) > 1e-6 ? simd_normalize(along) * 0.8 : .zero
                ctx.beginPath()
                ctx.move(to: left[i])
                ctx.addLine(to: HandFXKit.point(HandFXKit.vector(left[i + 1]) + push))
                ctx.addLine(to: HandFXKit.point(HandFXKit.vector(right[i + 1]) + push))
                ctx.addLine(to: right[i])
                ctx.closePath()
                ctx.setFillColor(HandFXKit.cgColor(colour))
                ctx.fillPath()
            }
            // A fine bright hem along the lit edge of the front face.
            let hem = CGMutablePath()
            var drawing = false
            for i in 0..<n {
                if facing[i] > 0.2 {
                    if drawing { hem.addLine(to: left[i]) } else { hem.move(to: left[i]); drawing = true }
                } else {
                    drawing = false
                }
            }
            ctx.addPath(hem)
            ctx.setLineWidth(CGFloat(1.6 * scale))
            ctx.setLineCap(.round)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
            ctx.strokePath()
            if fading { ctx.endTransparencyLayer() }
            ctx.restoreGState()
        }
    }
}
