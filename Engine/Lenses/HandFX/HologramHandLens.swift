import CoreGraphics
import CoreImage
import simd

/// Your hand as a hologram: a glowing wireframe of its bones that draws itself on from the wrist, a turning sight on the palm, rings
/// round the fingertips, a scan line sweeping up the hand, and a small panel beside it that reads out how far each finger is open.
///
/// Every joint is steadied, so the wireframe sits calmly on a trembling hand, and every finger reading is eased, so the bars glide.
struct HologramHandRig {
    struct Reading {
        /// How far each finger is out, eased, thumb first.
        var fingers = [HandFXLevel](repeating: HandFXLevel(rise: 0.12, fall: 0.12), count: 5)
        /// Which side of the hand the readout panel sits on, and where its corner is, gliding rather than jumping when it moves.
        var panelOnRight: Bool?
        var panel: CGPoint?
    }

    /// The readout panel's size for a hand.
    static func panelSize(for hand: HandState) -> CGSize {
        let unit = min(1.4, max(0.6, hand.size / 110))
        return CGSize(width: 92 * unit, height: 70 * unit)
    }

    private(set) var memory = HandFXMemory<Reading>()
    private(set) var time = 0.0
    private var steadier = HandFXSteadier()

    mutating func removeAll() {
        memory.removeAll()
        steadier.removeAll()
    }

    mutating func update(hands raw: [HandState], dt rawDt: Double, size: CGSize = CGSize(width: 1280, height: 720)) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        let hands = steadier.update(raw, dt: dt)
        memory.update(hands, dt: dt, fade: 0.3) { _ in Reading() }
        for i in memory.entries.indices where memory.entries[i].visible {
            memory.modify(i) { entry in
                for finger in Finger.allCases {
                    entry.state.fingers[finger.rawValue].approach(HandFXPose.extended(finger, in: entry.hand), dt: dt)
                }
                Self.place(&entry.state, for: entry.hand, size: size, dt: dt)
            }
        }
    }

    /// Puts the panel beside the hand, on the side away from the middle of the picture (and the face) when there is room there, inside
    /// the safe margin. It changes sides only once the hand is well across the middle, and glides there.
    private static func place(_ reading: inout Reading, for hand: HandState, size: CGSize, dt: Double) {
        let panel = panelSize(for: hand)
        let reach = Double(hand.rect.width) / 2 + 26 * Double(panel.width) / 92
        let x = Double(hand.palm.x), w = Double(size.width), width = Double(panel.width)
        var right = reading.panelOnRight ?? (x >= w / 2)
        if right, x < w * 0.42 { right = false }
        if !right, x > w * 0.58 { right = true }
        if right, x + reach + width > w * 0.95 { right = false }
        if !right, x - reach - width < w * 0.05 { right = true }
        reading.panelOnRight = right
        let target = CGPoint(x: min(w * 0.95 - width, max(w * 0.05, right ? x + reach : x - reach - width)),
                             y: min(Double(size.height) * 0.95 - Double(panel.height), max(Double(size.height) * 0.05, Double(hand.palm.y) - Double(panel.height) / 2)))
        guard let now = reading.panel else { reading.panel = target; return }
        reading.panel = HandFXKit.lerp(now, target, 1 - exp(-dt / 0.1))
    }

    /// The bones, as pairs of joints, with how far out from the wrist each lies (0 the palm, 3 the fingertips), which sets when it draws on.
    static let bones: [(HandJoint, HandJoint, Int)] = {
        var out: [(HandJoint, HandJoint, Int)] = [(.wrist, .thumbCMC, 0), (.wrist, .indexMCP, 0), (.wrist, .littleMCP, 0),
                                                  (.indexMCP, .middleMCP, 0), (.middleMCP, .ringMCP, 0), (.ringMCP, .littleMCP, 0)]
        out += [(.thumbCMC, .thumbMP, 1), (.thumbMP, .thumbIP, 2), (.thumbIP, .thumbTip, 3)]
        for finger in Finger.long {
            let dip = HandJoint(rawValue: finger.middleJoint.rawValue + 1) ?? finger.tip
            out += [(finger.knuckle, finger.middleJoint, 1), (finger.middleJoint, dip, 2), (dip, finger.tip, 3)]
        }
        return out
    }()

    /// How much of a bone at `depth` has drawn on, for a hand seen `age` seconds ago.
    static func drawn(depth: Int, age: Double) -> Double { min(1, max(0, age * 3.2 - Double(depth) * 0.45)) }
}

final class HologramHandLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig = HologramHandRig()
    private var hint = HandFXHint()
    private let published = StatusBox()

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hand", detail: "It turns into a hologram") }

    func restart() {
        rig.removeAll()
        hint.reset()
    }

    var hands: [HandState] { rig.memory.entries.map(\.hand) }
    var readings: [[Double]] { rig.memory.entries.map { $0.state.fingers.map(\.value) } }
    var isHinting: Bool { hint.isShowing }

    func render(_ input: LensInput) -> CIImage {
        rig.update(hands: input.hands, dt: input.dt, size: input.rect.size)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        published.value = input.hands.isEmpty ? LensStatus("Hold up your hand", detail: "It turns into a hologram")
                                              : LensStatus("Scanning", detail: "Move your fingers and watch the readout")
        var out = input.composed
        if !rig.memory.isEmpty {
            for entry in rig.memory.entries {
                let c = HandFXPalette.holo.line
                out = WorldKit.adding(WorldKit.wash(center: entry.hand.palm, radius: entry.hand.size * 1.7, red: c.x, green: c.y, blue: c.z,
                                                    alpha: 0.14 * entry.presence, in: input.rect), to: out)
            }
            if let layer = input.services.overlay({ ctx in draw(in: ctx) }) {
                out = HandFXLight.add(layer, to: out, rect: input.rect, bloom: 0.7)
            }
        }
        return hint.compose(over: out, services: input.services, rect: input.rect, accent: HandFXPalette.holo.line)
    }

    // MARK: Drawing

    private static let node = HandFXKit.speckSprite(HandFXPalette.holo.line)
    private static let accentNode = HandFXKit.speckSprite(HandFXPalette.holo.accent)
    private static let scan = HandFXKit.beamSprite(HandFXPalette.holo.line, core: 0.04, body: 0.2)

    /// A sight: a dashed outer ring with ticks and a broken inner ring, drawn once and turned as it is stamped.
    private static let reticle: CGImage? = {
        let side = 200
        guard let ctx = HandFXKit.bitmap(width: side, height: side) else { return nil }
        let c = CGPoint(x: 100, y: 100)
        let line = HandFXPalette.holo.line
        ctx.setLineCap(.round)
        ctx.setStrokeColor(HandFXKit.cgColor(line, 0.9))
        ctx.setLineWidth(3)
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi
            ctx.beginPath()
            ctx.addArc(center: c, radius: 88, startAngle: CGFloat(a), endAngle: CGFloat(a + 0.36), clockwise: false)
            ctx.strokePath()
        }
        ctx.setLineWidth(2)
        for k in 0..<36 {
            let a = Double(k) / 36 * 2 * .pi, inner = k % 3 == 0 ? 70.0 : 76.0
            ctx.move(to: CGPoint(x: 100 + cos(a) * inner, y: 100 + sin(a) * inner))
            ctx.addLine(to: CGPoint(x: 100 + cos(a) * 81, y: 100 + sin(a) * 81))
        }
        ctx.strokePath()
        ctx.setStrokeColor(HandFXKit.cgColor(HandFXPalette.holo.accent, 0.9))
        ctx.setLineWidth(4)
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi
            ctx.beginPath()
            ctx.addArc(center: c, radius: 52, startAngle: CGFloat(a), endAngle: CGFloat(a + 1.4), clockwise: false)
            ctx.strokePath()
        }
        return ctx.makeImage()
    }()

    /// A ring with four gaps, for the fingertips.
    private static let tipRing: CGImage? = {
        guard let ctx = HandFXKit.bitmap(width: 64, height: 64) else { return nil }
        ctx.setLineCap(.round)
        ctx.setLineWidth(3.5)
        ctx.setStrokeColor(HandFXKit.cgColor(HandFXPalette.holo.node, 1))
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + 0.25
            ctx.beginPath()
            ctx.addArc(center: CGPoint(x: 32, y: 32), radius: 27, startAngle: CGFloat(a), endAngle: CGFloat(a + 1.05), clockwise: false)
            ctx.strokePath()
        }
        return ctx.makeImage()
    }()

    private func draw(in ctx: CGContext) {
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .medium
        let t = rig.time
        // A hologram wavers a little, never blinks.
        let waver = 0.92 + 0.08 * sin(t * 11) * sin(t * 4.3)
        for entry in rig.memory.entries {
            let hand = entry.hand
            let s = entry.presence * waver
            guard s > 0.01 else { continue }
            drawBones(of: hand, age: entry.age, strength: s, in: ctx)
            // The sight on the palm, turning one way, and the fingertip rings turning the other.
            if let reticle = Self.reticle {
                let appear = HandFXKit.easeOutBack(min(1, entry.age * 2.5))
                ctx.draw(reticle, center: hand.palm, height: CGFloat(hand.size * 1.05 * appear), rotation: CGFloat(t * 0.7), alpha: CGFloat(0.75 * s))
            }
            for finger in Finger.allCases {
                let out = entry.state.fingers[finger.rawValue].value
                let tip = hand[finger.tip]
                if let ring = Self.tipRing {
                    ctx.draw(ring, center: tip, height: CGFloat(hand.size * (0.24 + 0.08 * out)), rotation: CGFloat(-t * 1.6 + Double(finger.rawValue)),
                             alpha: CGFloat((0.3 + 0.6 * out) * s * HologramHandRig.drawn(depth: 3, age: entry.age)))
                }
            }
            drawScan(over: hand, strength: s, in: ctx)
            drawPanel(for: entry, strength: s, in: ctx)
        }
        ctx.interpolationQuality = .high
    }

    /// The wireframe: every bone at once as one path, in a soft wide pass and a bright thin one, then a glowing node at every joint.
    private func drawBones(of hand: HandState, age: Double, strength s: Double, in ctx: CGContext) {
        let path = CGMutablePath()
        for (a, b, depth) in HologramHandRig.bones {
            let k = HologramHandRig.drawn(depth: depth, age: age)
            guard k > 0 else { continue }
            path.move(to: hand[a])
            path.addLine(to: HandFXKit.lerp(hand[a], hand[b], k))
        }
        // The lines are painted rather than added (the layer is added to the picture anyway), which costs a good deal less to stroke.
        ctx.setBlendMode(.normal)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        defer { ctx.setBlendMode(.plusLighter) }
        for (width, colour, alpha) in [(hand.size * 0.06, HandFXPalette.holo.line, 0.38), (max(1.6, hand.size * 0.016), HandFXPalette.holo.line, 0.9)] {
            ctx.addPath(path)
            ctx.setLineWidth(CGFloat(width))
            ctx.setStrokeColor(HandFXKit.cgColor(colour, alpha * s))
            ctx.strokePath()
        }
        guard let node = Self.node else { return }
        for joint in HandJoint.allCases {
            // Joints come in fours from the thumb on: knuckle, middle, end, tip.
            let depth = joint == .wrist ? 0 : (joint.rawValue - 1) % 4
            let k = HologramHandRig.drawn(depth: depth, age: age)
            guard k > 0.5 else { continue }
            let tip = depth == 3
            ctx.stampDot(tip ? (Self.accentNode ?? node) : node, at: hand[joint], radius: hand.size * (tip ? 0.11 : 0.075), alpha: s)
        }
    }

    /// A band of light that sweeps from the wrist to the fingertips every couple of seconds.
    private func drawScan(over hand: HandState, strength s: Double, in ctx: CGContext) {
        guard let scan = Self.scan else { return }
        let cycle = (rig.time + Double(hand.id) * 0.7).truncatingRemainder(dividingBy: 2.4) / 1.4
        guard cycle < 1 else { return }
        let up = HandFXKit.up(of: hand), across = SIMD2(-up.y, up.x)
        let along = HandFXKit.vector(hand.wrist) + up * hand.size * (-0.1 + 2.3 * cycle)
        let half = hand.size * 1.1
        let fade = sin(.pi * cycle)
        HandFXKit.drawBeam(scan, from: HandFXKit.point(along - across * half), to: HandFXKit.point(along + across * half), width: hand.size * 0.3,
                           alpha: 0.45 * s * fade, in: ctx)
    }

    /// Five bars beside the hand, one per finger, showing how far each is open, in a bracketed frame.
    private func drawPanel(for entry: HandFXMemory<HologramHandRig.Reading>.Entry, strength s: Double, in ctx: CGContext) {
        let hand = entry.hand
        guard let origin = entry.state.panel else { return }
        let unit = min(1.4, max(0.6, hand.size / 110))
        let panel = HologramHandRig.panelSize(for: hand)
        let width = Double(panel.width), height = Double(panel.height)
        let appear = WorldKit.smoothstep(0.35, 0.8, entry.age)
        guard appear > 0.01 else { return }
        let a = s * appear
        let frame = CGRect(x: Double(origin.x), y: Double(origin.y), width: width, height: height)
        // A faint panel and corner brackets.
        ctx.setFillColor(HandFXKit.cgColor(HandFXPalette.holo.line, 0.06 * a))
        ctx.fill(frame)
        let corner = 12 * unit
        let brackets = CGMutablePath()
        for (cx, cy, dx, dy) in [(frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0), (frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0)] {
            brackets.move(to: CGPoint(x: cx + dx * corner, y: cy))
            brackets.addLine(to: CGPoint(x: cx, y: cy))
            brackets.addLine(to: CGPoint(x: cx, y: cy + dy * corner))
        }
        ctx.addPath(brackets)
        ctx.setLineWidth(2)
        ctx.setStrokeColor(HandFXKit.cgColor(HandFXPalette.holo.line, 0.8 * a))
        ctx.strokePath()
        // The bars: thumb to little finger, left to right, each with a dim track and a bright level. Filled a group at a time.
        let barWidth = 9 * unit, gap = (width - 5 * barWidth) / 6, top = height - 14 * unit
        var tracks: [CGRect] = [], bars: [CGRect] = [], thumb: [CGRect] = []
        for finger in Finger.allCases {
            let level = entry.state.fingers[finger.rawValue].value
            let bx = frame.minX + gap + Double(finger.rawValue) * (barWidth + gap)
            let track = CGRect(x: bx, y: frame.minY + 8 * unit, width: barWidth, height: top)
            tracks.append(track)
            let bar = CGRect(x: bx, y: track.minY, width: barWidth, height: max(2, top * level))
            if finger == .thumb { thumb.append(bar) } else { bars.append(bar) }
        }
        ctx.setFillColor(HandFXKit.cgColor(HandFXPalette.holo.line, 0.12 * a))
        ctx.fill(tracks)
        ctx.setFillColor(HandFXKit.cgColor(HandFXPalette.holo.line, 0.5 * a))
        ctx.fill(bars)
        ctx.setFillColor(HandFXKit.cgColor(HandFXPalette.holo.accent, 0.5 * a))
        ctx.fill(thumb)
    }
}
