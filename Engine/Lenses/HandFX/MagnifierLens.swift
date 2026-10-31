import CoreGraphics
import CoreImage
import simd

/// A magnifying glass held between thumb and finger. Hold the thumb out and the index finger up with the other fingers curled, as if
/// pinching the rim of a lens, and a glass appears between their tips, magnifying the picture behind it. Spread them for a bigger glass.
struct MagnifierRig {
    struct Loupe {
        var holding = HandFXLatch(on: 0.55, off: 0.3, holdOn: 0.1, holdOff: 0.22)
        /// 0...1: how much of the glass shows. It pops in and fades out.
        var show = HandFXLevel(rise: 0.1, fall: 0.14)
        var centre = HandFXSteady(calm: 1.8, eager: 0.03)
        var radius = HandFXLevel(rise: 0.1, fall: 0.1)
    }

    /// A glass ready to draw.
    struct Glass {
        var hand: Int
        var centre: CGPoint
        var radius: Double
        var show: Double
    }

    private(set) var memory = HandFXMemory<Loupe>()
    private var steadier = HandFXSteadier()

    mutating func removeAll() {
        memory.removeAll()
        steadier.removeAll()
    }

    /// How much a hand is holding a lens: thumb out, the last three fingers curled, and thumb and index tips a lens-width apart.
    static func holding(_ hand: HandState) -> Double {
        let others = [Finger.middle, .ring, .little].map { HandFXPose.extended($0, in: hand) }.max() ?? 0
        let spread = HandFXKit.distance(hand[.thumbTip], hand[.indexTip]) / hand.size
        let thumb = WorldKit.smoothstep(0.4, 0.75, hand.thumbOpen)
        return (1 - others) * thumb * WorldKit.smoothstep(0.42, 0.65, spread) * (1 - WorldKit.smoothstep(2.2, 2.6, spread))
    }

    /// The glass between a hand's thumb and index tips: its middle and radius.
    static func lens(of hand: HandState) -> (centre: CGPoint, radius: Double) {
        let a = hand[.thumbTip], b = hand[.indexTip]
        return (HandFXKit.lerp(a, b, 0.5), min(175, max(36, HandFXKit.distance(a, b) * 0.46)))
    }

    mutating func update(hands raw: [HandState], dt rawDt: Double) {
        let dt = WorldKit.clamped(rawDt)
        let hands = steadier.update(raw, dt: dt)
        memory.update(hands, dt: dt, fade: 0.25) { _ in Loupe() }
        for i in memory.entries.indices {
            var entry = memory.entries[i]
            if entry.visible {
                let held = entry.state.holding.update(Self.holding(entry.hand), dt: entry.age < 1e-9 ? 1 : dt)
                let target = Self.lens(of: entry.hand)
                let fresh = entry.state.show.value < 0.02
                entry.state.centre.update(target.centre, dt: dt, snap: fresh ? 0 : max(160, entry.hand.size * 2.5))
                if fresh { entry.state.radius.value = target.radius }
                entry.state.radius.approach(target.radius, dt: dt)
                entry.state.show.approach(held ? 1 : 0, dt: dt)
            } else {
                entry.state.show.approach(0, dt: dt)
            }
            memory.modify(i) { $0 = entry }
        }
    }

    var glasses: [Glass] {
        memory.entries.compactMap { entry in
            let show = entry.state.show.value * entry.presence
            guard show > 0.01, let c = entry.state.centre.point else { return nil }
            return Glass(hand: entry.hand.id, centre: c, radius: entry.state.radius.value, show: show)
        }
    }
}

final class MagnifierLens: Lens {
    let needs: LensNeeds = [.hands]

    private var rig = MagnifierRig()
    private var hint = HandFXHint()
    private let published = StatusBox()

    var status: LensStatus? { published.value }

    init() { published.value = LensStatus("Hold up your hand", detail: "Thumb out, finger up: hold a lens between them") }

    func restart() {
        rig.removeAll()
        hint.reset()
    }

    var glasses: [MagnifierRig.Glass] { rig.glasses }
    var isHinting: Bool { hint.isShowing }

    /// How much the glass magnifies the middle of what is behind it.
    static let power = 0.62

    func render(_ input: LensInput) -> CIImage {
        rig.update(hands: input.hands, dt: input.dt)
        hint.update(handsInView: !input.hands.isEmpty, dt: input.dt)
        let glasses = rig.glasses
        published.value = currentStatus(input.hands, glasses: glasses)

        var out = input.composed
        for glass in glasses {
            let r = drawnRadius(glass)
            let box = CGRect(x: glass.centre.x - r - 2, y: glass.centre.y - r - 2, width: r * 2 + 4, height: r * 2 + 4).intersection(input.rect)
            out = out.clampedToExtent().applyingFilter("CIBumpDistortion", parameters: [
                kCIInputCenterKey: CIVector(cgPoint: glass.centre), kCIInputRadiusKey: r, kCIInputScaleKey: Self.power * glass.show,
            ]).cropped(to: box).composited(over: out).cropped(to: input.rect)
        }
        if !glasses.isEmpty, let rims = input.services.overlay({ ctx in draw(glasses, in: ctx) }) {
            out = rims.composited(over: out)
        }
        return hint.compose(over: out, services: input.services, rect: input.rect, accent: SIMD3(0.55, 0.85, 1))
    }

    /// The glass springs to size as it appears.
    private func drawnRadius(_ glass: MagnifierRig.Glass) -> Double { glass.radius * (0.55 + 0.45 * HandFXKit.easeOutBack(glass.show, overshoot: 1.4)) }

    private func currentStatus(_ hands: [HandState], glasses: [MagnifierRig.Glass]) -> LensStatus {
        if hands.isEmpty { return LensStatus("Hold up your hand", detail: "Thumb out, finger up: hold a lens between them") }
        if glasses.contains(where: { $0.show > 0.5 }) { return LensStatus("Looking closer", detail: "Spread your thumb and finger for a bigger lens") }
        return LensStatus("Hold a lens", detail: "Thumb out, index finger up, other fingers curled")
    }

    // MARK: Drawing

    private func draw(_ glasses: [MagnifierRig.Glass], in ctx: CGContext) {
        guard let rim = Self.rim else { return }
        ctx.interpolationQuality = .high
        for glass in glasses {
            let r = drawnRadius(glass)
            // The sprite's glass edge sits at 0.76 of its half-width; the rest is the rim and its shadow.
            let side = r / 0.76 * 2
            ctx.setAlpha(CGFloat(min(1, glass.show * 1.3)))
            ctx.draw(rim, in: CGRect(x: glass.centre.x - side / 2, y: glass.centre.y - side / 2, width: side, height: side))
            ctx.setAlpha(1)
        }
    }

    /// The lens's metal rim, its shadow, and the glints on the glass, lit from the top left. Drawn once at a large size.
    private static let rim: CGImage? = {
        let side = 360
        guard let ctx = HandFXKit.bitmap(width: side, height: side) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGPoint(x: Double(side) / 2, y: Double(side) / 2)
        let glass = Double(side) / 2 * 0.76, outer = glass * 1.13
        func ring(_ inner: Double, _ outer: Double) -> CGMutablePath {
            let p = CGMutablePath()
            p.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
            p.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
            return p
        }
        // A soft shadow under the rim, toward the bottom right.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 5, height: -7), blur: 14, color: CGColor(gray: 0, alpha: 0.5))
        ctx.addPath(ring(glass, outer))
        ctx.setFillColor(CGColor(colorSpace: space, components: [0.3, 0.3, 0.32, 1])!)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
        // The rim: polished metal, bright at the top left and dark at the bottom right.
        ctx.saveGState()
        ctx.addPath(ring(glass, outer))
        ctx.clip(using: .evenOdd)
        let metal = [CGColor(colorSpace: space, components: [0.98, 0.97, 0.94, 1])!, CGColor(colorSpace: space, components: [0.72, 0.7, 0.68, 1])!,
                     CGColor(colorSpace: space, components: [0.36, 0.35, 0.36, 1])!, CGColor(colorSpace: space, components: [0.6, 0.58, 0.56, 1])!] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: metal, locations: [0, 0.4, 0.8, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x - outer, y: c.y + outer), end: CGPoint(x: c.x + outer, y: c.y - outer), options: [])
        }
        ctx.restoreGState()
        // A bevel: a fine bright line round the outside and a dark one where the rim meets the glass.
        ctx.setLineWidth(2)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [1, 1, 1, 0.7])!)
        ctx.strokeEllipse(in: CGRect(x: c.x - outer + 1, y: c.y - outer + 1, width: outer * 2 - 2, height: outer * 2 - 2))
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.12, 0.12, 0.14, 0.75])!)
        ctx.strokeEllipse(in: CGRect(x: c.x - glass - 1, y: c.y - glass - 1, width: glass * 2 + 2, height: glass * 2 + 2))
        // The glass: the faintest cool tint, a broad soft reflection at the top left and a small bright glint at the bottom right.
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - glass, y: c.y - glass, width: glass * 2, height: glass * 2))
        ctx.clip()
        ctx.setFillColor(CGColor(colorSpace: space, components: [0.8, 0.9, 1, 0.06])!)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let shine = CGMutablePath()
        shine.addEllipse(in: CGRect(x: c.x - glass * 0.86, y: c.y + glass * 0.05, width: glass * 1.1, height: glass * 0.78))
        let cut = CGMutablePath()
        cut.addEllipse(in: CGRect(x: c.x - glass * 0.7, y: c.y - glass * 0.12, width: glass * 1.25, height: glass * 0.9))
        ctx.addPath(shine)
        ctx.clip()
        ctx.addRect(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.addPath(cut)
        ctx.clip(using: .evenOdd)
        let sheen = [CGColor(colorSpace: space, components: [1, 1, 1, 0.42])!, CGColor(colorSpace: space, components: [1, 1, 1, 0])!] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: sheen, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x - glass * 0.6, y: c.y + glass * 0.8), end: CGPoint(x: c.x, y: c.y), options: [])
        }
        ctx.restoreGState()
        ctx.saveGState()
        let glint = CGPoint(x: c.x + glass * 0.5, y: c.y - glass * 0.52)
        let spot = [CGColor(colorSpace: space, components: [1, 1, 1, 0.75])!, CGColor(colorSpace: space, components: [1, 1, 1, 0])!] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: spot, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: glint, startRadius: 0, endCenter: glint, endRadius: glass * 0.12, options: [])
        }
        ctx.restoreGState()
        return ctx.makeImage()
    }()
}
