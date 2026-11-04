import CoreGraphics
import CoreImage
import Foundation
import simd

// What the five beam moves (Kamehameha, Final Flash, Special Beam Cannon, Ki Blast, Finger Beam) share: how their light looks, and the
// small pieces of hand reading they all need.
//
// Every beam is drawn the same way, so the five read as one family, in the cel-shaded style of the show: nested bands of light, each a
// smooth vector outline with rippling edges and round ends (a white-hot thread, a pale core, the vivid body, two faint halo bands), added
// over the picture, with rings of energy running along them, a burst of tapered spikes where the beam leaves the hands and a splash of
// spikes and sparks where it meets the edge of the picture. The lens's bloom softens the bands; the wide soft light is left to the
// graphics chip (`SaiyanWash`). The CPU only fills crisp shapes, which is cheap however big the beam.

// MARK: - Colour

/// A move's energy in one form: its signature colour with the form's tint blended in, and the shades made from it.
struct SaiyanKi: Equatable {
    /// Near white with a breath of the colour: the hottest middle.
    var core: SIMD3<Double>
    /// The body of the light.
    var body: SIMD3<Double>
    /// Deeper and more saturated: the edge of a solid ball and the underside of a beam.
    var deep: SIMD3<Double>

    /// `amount` is how far toward the form's tint to go (see `SaiyanPalette.tinting`).
    init(_ signature: SIMD3<Double>, palette: SaiyanPalette, tint amount: Double = 0.7) {
        // Snapped to a coarse step, so the glow sprites made from these colours are shared.
        let body = SaiyanBeamKit.snap(palette.tinting(signature, amount: amount))
        self.body = body
        core = SaiyanBeamKit.snap(body + (SIMD3(1, 1, 1) - body) * 0.84)
        let luma = simd_dot(body, SIMD3(0.2126, 0.7152, 0.0722))
        deep = SaiyanBeamKit.snap((body + (body - SIMD3(repeating: luma)) * 0.6) * 0.6)
    }

    /// The body lifted toward white by `k`.
    func lit(_ k: Double) -> SIMD3<Double> { body + (SIMD3(1, 1, 1) - body) * min(1, max(0, k)) }
}

// MARK: - The kit

enum SaiyanBeamKit {
    static let white = SIMD3<Double>(1, 1, 1)

    /// Colours rounded to steps of 1/20, clamped to 0...1.
    static func snap(_ c: SIMD3<Double>) -> SIMD3<Double> { (simd_clamp(c, .zero, white) * 20).rounded(.toNearestOrAwayFromZero) / 20 }

    static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> { a + (b - a) * min(1, max(0, t)) }

    static func easeInQuad(_ t: Double) -> Double { let x = min(1, max(0, t)); return x * x }

    /// How much of a size to use for a hand: a palm of 110 pixels is 1. Clamped, so a hand right up at the lens does not make a beam that
    /// fills the picture, nor a hand across the room one too thin to see.
    static func handScale(_ size: Double) -> Double { min(1.7, max(0.6, size / 110)) }

    // MARK: Small shapes

    // Everything here is filled vector shapes, batched into as few fills as possible: on the CPU a filled shape costs a nanosecond or two
    // a pixel, a stamped sprite five to ten times that, and each stroke a fixed price to turn into a shape before it is filled.

    /// A filled circle of flat light.
    static func disc(at p: CGPoint, radius r: Double, colour: SIMD3<Double>, alpha: Double, in ctx: CGContext) {
        guard r > 0.3, alpha > 0.004 else { return }
        ctx.setFillColor(HandFXKit.cgColor(colour, alpha))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// A round light of nested flat discs, white in the middle through the pale colour to the body: the cel-shaded glow of the show, which
    /// the bloom softens.
    static func glowDisc(at p: CGPoint, radius r: Double, ki: SaiyanKi, alpha: Double, in ctx: CGContext) {
        guard r > 0.5, alpha > 0.01 else { return }
        disc(at: p, radius: r, colour: ki.body, alpha: 0.12 * alpha, in: ctx)
        disc(at: p, radius: r * 0.7, colour: ki.lit(0.4), alpha: 0.26 * alpha, in: ctx)
        disc(at: p, radius: r * 0.44, colour: ki.core, alpha: 0.6 * alpha, in: ctx)
        disc(at: p, radius: r * 0.22, colour: white, alpha: alpha, in: ctx)
    }

    /// A ring: the band between two ellipses, filled, turned by `rotation`.
    static func ring(at p: CGPoint, rx: Double, ry: Double, thickness t: Double, rotation: Double = 0, colour: SIMD3<Double>, alpha: Double,
                     in ctx: CGContext) {
        guard alpha > 0.004, rx > 0.5, ry > 0.5, t > 0.2 else { return }
        let path = CGMutablePath()
        addRing(path, at: p, rx: rx, ry: ry, thickness: t, rotation: rotation)
        ctx.addPath(path)
        ctx.setFillColor(HandFXKit.cgColor(colour, alpha))
        ctx.fillPath(using: .evenOdd)
    }

    /// Adds a ring to `path`, to be filled even-odd.
    static func addRing(_ path: CGMutablePath, at p: CGPoint, rx: Double, ry: Double, thickness t: Double, rotation: Double = 0) {
        let turn = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: CGFloat(rotation))
        let ox = rx + t / 2, oy = ry + t / 2, ix = max(0.1, rx - t / 2), iy = max(0.1, ry - t / 2)
        path.addEllipse(in: CGRect(x: -ox, y: -oy, width: ox * 2, height: oy * 2), transform: turn)
        path.addEllipse(in: CGRect(x: -ix, y: -iy, width: ix * 2, height: iy * 2), transform: turn)
    }

    /// Adds a comet shape to `path`: round at `head` (`width` across), its flanks curving in to a fine point `length` behind it. The tail of
    /// a flying blast, a mote rushing in.
    static func teardrop(_ path: CGMutablePath, head: CGPoint, angle: Double, length: Double, width: Double) {
        guard length > 0.5, width > 0.2 else { return }
        let d = SIMD2(cos(angle), sin(angle)), n = SIMD2(-d.y, d.x), r = width / 2
        func at(_ back: Double, _ side: Double) -> CGPoint { CGPoint(x: head.x - d.x * back + n.x * side, y: head.y - d.y * back + n.y * side) }
        path.move(to: at(length, 0))
        path.addQuadCurve(to: at(0, r), control: at(length * 0.35, r * 0.55))
        path.addArc(center: head, radius: r, startAngle: CGFloat(angle + .pi / 2), endAngle: CGFloat(angle - .pi / 2), clockwise: true)
        path.addQuadCurve(to: at(length, 0), control: at(length * 0.35, -r * 0.55))
        path.closeSubpath()
    }

    static func fill(_ path: CGPath, colour: SIMD3<Double>, alpha: Double, in ctx: CGContext) {
        guard !path.isEmpty, alpha > 0.004 else { return }
        ctx.addPath(path)
        ctx.setFillColor(HandFXKit.cgColor(colour, alpha))
        ctx.fillPath()
    }

    /// A burst of tapered spikes round `p`, like a hand-drawn flare: each flickers to its own length, and those along `axis` (and opposite
    /// it) reach furthest when `bias` is up. A thinner white spike runs down the middle of each.
    static func spikes(at p: CGPoint, count: Int, rotation: Double, length: Double, base: Double, axis: Double = 0, bias: Double = 0,
                       spread: Double = .pi, colour: SIMD3<Double>, alpha: Double, time: Double, seed: Int, in ctx: CGContext) {
        guard count > 0, length > 1, alpha > 0.01 else { return }
        // All the spikes of one pass go in one path, so a burst is two fills however many spikes it has.
        for pass in 0..<2 {
            let inner = pass == 1
            let path = CGMutablePath()
            for i in 0..<count {
                let f = count == 1 ? 0.5 : Double(i) / Double(count - (spread < .pi ? 1 : 0))
                let a = spread < .pi ? rotation + (f - 0.5) * 2 * spread : rotation + f * 2 * .pi
                let flicker = 0.62 + 0.38 * sin(time * (13 + Double((i * 7 + seed) % 9)) + Double(i * 5 + seed))
                let along = abs(cos(a - axis))
                let l = length * flicker * (1 - bias + bias * (0.35 + 0.65 * along)) * (inner ? 0.62 : 1)
                let b = base * (inner ? 0.4 : 1) * (0.7 + 0.3 * flicker)
                let d = SIMD2(cos(a), sin(a)), n = SIMD2(-d.y, d.x)
                path.move(to: CGPoint(x: p.x + d.x * l, y: p.y + d.y * l))
                path.addLine(to: CGPoint(x: p.x + n.x * b / 2 - d.x * b * 0.3, y: p.y + n.y * b / 2 - d.y * b * 0.3))
                path.addLine(to: CGPoint(x: p.x - n.x * b / 2 - d.x * b * 0.3, y: p.y - n.y * b / 2 - d.y * b * 0.3))
                path.closeSubpath()
            }
            ctx.addPath(path)
            ctx.setFillColor(HandFXKit.cgColor(inner ? mix(colour, white, 0.8) : colour, (inner ? 0.9 : 0.7) * alpha))
            ctx.fillPath()
        }
    }

    /// Electric lines: one hot stroke, pale toward white, for every bolt in `path` at once; the bloom gives them their coloured glow.
    /// `thread` adds a thin white line down them.
    static func bolts(_ path: CGPath, colour: SIMD3<Double>, strength: Double, width: Double, thread: Bool = false, in ctx: CGContext) {
        guard !path.isEmpty, strength > 0.01 else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.setLineWidth(CGFloat(max(1, 2.4 * width)))
        ctx.setStrokeColor(HandFXKit.cgColor(mix(colour, white, 0.45), 0.85 * strength))
        ctx.strokePath()
        guard thread else { return }
        ctx.addPath(path)
        ctx.setLineWidth(CGFloat(max(0.8, 0.9 * width)))
        ctx.setStrokeColor(HandFXKit.cgColor(white, strength))
        ctx.strokePath()
    }

    /// Crackling arcs: up to `count` jagged bolts leaping off a ball, changing every couple of frames and flickering on and off.
    static func crackle(around c: CGPoint, radius r: Double, count: Int, reach: ClosedRange<Double> = 1.35...2.1, time: Double, seed: Int,
                        colour: SIMD3<Double>, strength: Double, in ctx: CGContext) {
        guard count > 0, strength > 0.01, r > 1 else { return }
        let beat = Int(time * 15)
        let path = CGMutablePath()
        for k in 0..<count {
            var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: beat &* 7919 &+ k &* 104_729 &+ seed &* 31))
            guard Double.random(in: 0...1, using: &rng) < 0.8 else { continue }
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let far = r * Double.random(in: reach, using: &rng) + 6
            let drift = Double.random(in: -0.5...0.5, using: &rng)
            let start = CGPoint(x: c.x + cos(angle) * r * 0.9, y: c.y + sin(angle) * r * 0.9)
            let end = CGPoint(x: c.x + cos(angle + drift) * far, y: c.y + sin(angle + drift) * far)
            path.addLines(between: HandFXKit.zigzag(from: start, to: end, seed: UInt64(truncatingIfNeeded: beat &* 31 &+ k &* 977 &+ seed),
                                                     amplitude: max(4, r * 0.22), segments: 9))
        }
        bolts(path, colour: colour, strength: strength, width: 0.6 + 0.5 * min(1, r / 70), thread: true, in: ctx)
    }

    // MARK: Orbs

    /// The solid ball of a charging orb: a small white-hot middle, shading through the pale colour and the body to a deep rim with a soft
    /// edge. Painted normally, so it reads as a coloured ball even over a bright face.
    static func drawOrbSolid(at c: CGPoint, radius r: Double, ki: SaiyanKi, alpha: Double, in ctx: CGContext) {
        guard r > 1, alpha > 0.01 else { return }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func stop(_ colour: SIMD3<Double>, _ a: Double) -> CGColor { HandFXKit.cgColor(colour, a * alpha) }
        let colours = [stop(white, 1), stop(ki.core, 1), stop(ki.lit(0.4), 1), stop(ki.body, 0.97), stop(ki.deep, 0.9), stop(ki.deep, 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.18, 0.42, 0.72, 0.91, 1]) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * 1.06, options: [])
        ctx.restoreGState()
    }

    /// The light of an orb, added over its solid ball: a hot glow in the middle, swirls turning inside, a lit crescent and rim, crackling
    /// arcs, and a slowly turning burst of spikes once it is full (`full` 0...1). Its wide halo is a wash.
    static func drawOrbLight(at c: CGPoint, radius r: Double, ki: SaiyanKi, alpha: Double, time: Double, seed: Int, crackle arcs: Int,
                             full: Double = 0, in ctx: CGContext) {
        guard r > 1, alpha > 0.01 else { return }
        disc(at: c, radius: r * 0.5, colour: ki.core, alpha: 0.4 * alpha, in: ctx)
        disc(at: c, radius: r * 0.27, colour: white, alpha: 0.7 * alpha, in: ctx)

        // Swirls of energy turning inside, each its own speed and way round, in one stroke.
        let swirls = CGMutablePath()
        for k in 0..<4 {
            let start = time * (2.2 + 0.9 * Double(k)) * (k % 2 == 0 ? 1 : -1) + Double(k) * 1.7 + Double(seed)
            let sweep = 1.1 + 0.5 * sin(time * 3 + Double(k))
            let radius = r * (0.3 + 0.15 * Double(k))
            swirls.move(to: CGPoint(x: c.x + cos(start) * radius, y: c.y + sin(start) * radius))
            swirls.addArc(center: c, radius: radius, startAngle: start, endAngle: start + sweep, clockwise: false)
        }
        ctx.setLineCap(.round)
        ctx.addPath(swirls)
        ctx.setStrokeColor(HandFXKit.cgColor(ki.lit(0.6), 0.5 * alpha))
        ctx.setLineWidth(max(1.2, r * 0.05))
        ctx.strokePath()
        // The rim: a thin lit line all round, and a bright crescent over the top where the light catches it.
        ring(at: c, rx: r * 0.97, ry: r * 0.97, thickness: max(1.2, r * 0.035), colour: ki.lit(0.35), alpha: 0.5 * alpha, in: ctx)
        let crescent = CGMutablePath()
        crescent.addArc(center: c, radius: r * 0.92, startAngle: 0.5 * .pi - 0.3, endAngle: 0.5 * .pi + 1.1, clockwise: false)
        crescent.addArc(center: CGPoint(x: c.x + r * 0.05, y: c.y - r * 0.07), radius: r * 0.86, startAngle: 0.5 * .pi + 1.1, endAngle: 0.5 * .pi - 0.3,
                        clockwise: true)
        crescent.closeSubpath()
        fill(crescent, colour: ki.lit(0.85), alpha: 0.75 * alpha, in: ctx)

        crackle(around: c, radius: r, count: arcs, time: time, seed: seed, colour: ki.lit(0.3), strength: alpha, in: ctx)

        if full > 0.01 {
            let pulse = 1 + 0.12 * sin(time * 9)
            spikes(at: c, count: 8, rotation: time * 0.8, length: r * 2.1 * pulse, base: r * 0.2, colour: ki.lit(0.5), alpha: 0.6 * full * alpha,
                   time: time, seed: seed, in: ctx)
        }
    }

    // MARK: Beams

    /// How wide a beam is at `x` pixels along it: narrow where it leaves the hands, swelling into a bulb behind the head, and breathing.
    static func width(at x: Double, _ look: SaiyanBeamLook) -> Double {
        let w = look.width, t = look.time, s = Double(look.seed)
        let taper = 0.45 + 0.55 * WorldKit.smoothstep(look.tail - w * 0.1, look.tail + w * 1.4, x)
        let bulb = 1 + 0.2 * look.bulb * exp(-pow((look.head - w * 0.5 - x) / (w * 0.75), 2))
        let breathe = 1 + 0.035 * sin(t * 17 + s) + 0.02 * sin(t * 43 + s * 3)
        return w * taper * bulb * breathe
    }

    /// The outline of one band of a beam, in the beam's frame (x along it, y across): `k` times the beam's width, its two edges rippling on
    /// beats of their own (`salt` keeps the bands apart), round at both ends.
    static func band(_ look: SaiyanBeamLook, k: Double, salt: Double) -> CGPath? {
        let len = look.head - look.tail
        guard len > 1, k > 0 else { return nil }
        let w = look.width, t = look.time, s = Double(look.seed) * 0.37 + salt
        let rTail = min(width(at: look.tail, look) * 0.5 * k, len * 0.3)
        let rHead = min(width(at: look.head, look) * 0.5 * k, len * 0.45)
        let x0 = look.tail + rTail, x1 = look.head - rHead
        guard x1 > x0 + 1 else {
            return CGPath(ellipseIn: CGRect(x: look.tail, y: -max(rTail, rHead), width: len, height: max(rTail, rHead) * 2), transform: nil)
        }
        let step = max(5, min(16, w * 0.11))
        var top: [CGPoint] = [], bottom: [CGPoint] = []
        var x = x0
        while true {
            let half = width(at: x, look) * 0.5 * k
            // The ripples fade toward the ends, so the round caps meet the edges cleanly.
            let calm = look.wobble * WorldKit.smoothstep(x0, x0 + w * 0.6, x) * (1 - WorldKit.smoothstep(x1 - w * 0.4, x1, x))
            let up = 0.06 * sin(x / (w * 0.37) - t * 27 + s) + 0.035 * sin(x / (w * 0.14) + t * 41 + s * 1.7)
            let down = 0.06 * sin(x / (w * 0.41) - t * 23 + s * 2.9) + 0.035 * sin(x / (w * 0.13) + t * 37 + s * 0.6)
            top.append(CGPoint(x: x, y: half * (1 + up * calm)))
            bottom.append(CGPoint(x: x, y: -half * (1 + down * calm)))
            if x >= x1 { break }
            x = min(x1, x + step)
        }
        let path = CGMutablePath()
        let h0 = top[0].y, h1 = top[top.count - 1].y
        path.move(to: CGPoint(x: x0, y: -h0))
        path.addArc(center: CGPoint(x: x0, y: 0), radius: h0, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
        smooth(top, into: path)
        path.addArc(center: CGPoint(x: x1, y: 0), radius: h1, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        smooth(bottom.reversed(), into: path)
        path.closeSubpath()
        return path
    }

    /// Continues `path` through `points` with curves that pass between them, so the outline has no corners.
    private static func smooth(_ points: [CGPoint], into path: CGMutablePath) {
        guard let first = points.first else { return }
        path.addLine(to: first)
        guard points.count > 2 else {
            if let last = points.last { path.addLine(to: last) }
            return
        }
        for i in 1..<(points.count - 1) {
            let p = points[i], q = points[i + 1]
            path.addQuadCurve(to: CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2), control: p)
        }
        path.addLine(to: points[points.count - 1])
    }

    /// The bands of a beam's light, from the outside in: how wide (times the beam's width), how far toward white, how strong, and whether
    /// it is one of the two innermost (which widen for a thin beam). A big beam paints its body solid (`drawBeamSolid`) and adds only the
    /// inner three; a thin one adds its body and a faint halo too. The wide halo round either is a wash.
    private static let bodyBands: [(k: Double, tone: Double, alpha: Double, core: Bool)] = [(1.3, 0, 0.16, false), (1.0, 0, 0.62, false)]
    private static let innerBands: [(k: Double, tone: Double, alpha: Double, core: Bool)] = [(0.62, 0.3, 0.5, false), (0.3, 0.82, 0.92, true),
                                                                                              (0.12, 1, 1, true)]
    private static let bodySalt = 3.8

    /// The solid body of a big beam, painted normally under its light, with a deeper line round its edge the way the show inks a beam: it
    /// keeps the beam a vivid colour over anything bright, where added light alone would turn white. Opaque while it pours, which is also
    /// what makes it cheap: an opaque fill is a plain copy.
    static func drawBeamSolid(_ look: SaiyanBeamLook, in ctx: CGContext) {
        guard look.alpha > 0.01, look.solid > 0.01, let path = band(look, k: 1, salt: bodySalt) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.translateBy(x: look.origin.x, y: look.origin.y)
        ctx.rotate(by: CGFloat(look.angle))
        ctx.addPath(path)
        ctx.setFillColor(HandFXKit.cgColor(look.ki.body, look.solid * look.alpha))
        ctx.fillPath()
        // The inked edge: the band between this outline and one a little inside it.
        let inset = 1 - max(0.05, min(0.12, 3 / max(1, look.width)))
        if let inner = band(look, k: inset, salt: bodySalt) {
            ctx.addPath(path)
            ctx.addPath(inner)
            ctx.setFillColor(HandFXKit.cgColor(look.ki.deep, look.solid * look.alpha))
            ctx.fillPath(using: .evenOdd)
        }
        ctx.restoreGState()
    }

    /// A beam's light, added: its bands, rings running along it, threads of energy winding round it, and arcs crackling off its edge.
    static func drawBeamLight(_ look: SaiyanBeamLook, in ctx: CGContext) {
        let len = look.head - look.tail
        guard look.alpha > 0.01, len > 1 else { return }
        let w = look.width, t = look.time, ki = look.ki
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.translateBy(x: look.origin.x, y: look.origin.y)
        ctx.rotate(by: CGFloat(look.angle))

        // A thin beam gets a fatter core, so it still reads as white-hot.
        let coreScale = min(2.2, max(1, look.core / 0.11))
        for (i, b) in ((look.solid > 0.01 ? [] : bodyBands) + innerBands).enumerated() {
            let k = b.core ? min(0.9, b.k * coreScale) : b.k
            guard let path = band(look, k: k, salt: b.k == 1 ? bodySalt : Double(i) * 1.9 + 0.7) else { continue }
            ctx.addPath(path)
            ctx.setFillColor(HandFXKit.cgColor(b.core ? mix(ki.core, white, b.tone) : ki.lit(b.tone), b.alpha * look.alpha))
            ctx.fillPath()
        }

        // Rings of energy running out along it, widening as they go: ellipses seen side on, fading in near the hands and out near the head
        // in two steps, so they are two fills.
        if look.rings, len > w * 0.8 {
            let spacing = max(36, w * look.ringSpacing)
            let bright = CGMutablePath(), faint = CGMutablePath()
            var x = look.tail + w * 0.3 + (t * look.ringSpeed).truncatingRemainder(dividingBy: spacing)
            while x < look.head - w * 0.4 {
                let f = (x - look.tail) / len
                let across = width(at: x, look) * (0.56 + 0.1 * f)
                addRing(f > 0.12 && f < 0.75 ? bright : faint, at: CGPoint(x: x, y: 0), rx: across * (0.18 + 0.06 * f), ry: across,
                        thickness: max(1.2, min(5, w * 0.022)))
                x += spacing
            }
            for (path, a) in [(bright, 0.7), (faint, 0.3)] where !path.isEmpty {
                ctx.addPath(path)
                ctx.setFillColor(HandFXKit.cgColor(ki.lit(0.6), a * look.alpha))
                ctx.fillPath(using: .evenOdd)
            }
        }

        // Threads of energy winding along it.
        if look.filaments > 0, len > w {
            ctx.setLineJoin(.round)
            ctx.setLineWidth(max(1.2, min(4, w * 0.016)))
            ctx.setStrokeColor(HandFXKit.cgColor(ki.lit(0.75), 0.4 * look.alpha))
            let step = max(8, w * 0.1)
            let threads = CGMutablePath()
            for j in 0..<look.filaments {
                let phase = Double(j) * 2 * .pi / Double(look.filaments) + Double(look.seed)
                let wavelength = w * (1.5 + 0.45 * Double(j))
                var x = look.tail + w * 0.5
                var first = true
                while x < look.head - w * 0.45 {
                    let p = CGPoint(x: x, y: width(at: x, look) * 0.32 * sin(2 * .pi * x / wavelength - t * 22 + phase))
                    if first { threads.move(to: p); first = false } else { threads.addLine(to: p) }
                    x += step
                }
            }
            ctx.setLineCap(.round)
            ctx.addPath(threads)
            ctx.strokePath()
        }

        // Arcs leaping off the edge: more of them the stronger the form.
        if look.crackle > 0, len > w {
            let beat = Int(t * 15)
            let arcs = CGMutablePath()
            for k in 0..<look.crackle {
                var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: beat &* 7919 &+ k &* 104_729 &+ look.seed &* 13))
                let x0 = look.tail + Double.random(in: 0.12...0.85, using: &rng) * len
                let reach = w * Double.random(in: 0.7...1.6, using: &rng)
                let side: Double = Bool.random(using: &rng) ? 1 : -1
                let y0 = side * width(at: x0, look) * 0.42
                let y1 = side * width(at: x0, look) * Double.random(in: 0.6...1.0, using: &rng)
                arcs.addLines(between: HandFXKit.zigzag(from: CGPoint(x: x0, y: y0), to: CGPoint(x: min(look.head, x0 + reach), y: y1),
                                                         seed: UInt64(truncatingIfNeeded: beat &* 131 &+ k &* 7 &+ look.seed), amplitude: w * 0.14, segments: 8))
            }
            bolts(arcs, colour: ki.lit(0.3), strength: look.alpha * 0.8, width: 0.55 + min(1.0, w / 300), in: ctx)
        }
        ctx.restoreGState()
    }

    /// A spiral winding round a beam, in the beam's frame: the turns behind the core dimmer and thinner, the turns in front bright with a
    /// white thread down their middle. Draw the back (`front: false`) before the beam and the front after it, so the core sits between.
    static func drawSpiral(_ look: SaiyanBeamLook, radius: Double, pitch: Double, spin: Double, colour: SIMD3<Double>, lineWidth: Double,
                           front: Bool, in ctx: CGContext) {
        guard look.head - look.tail > 2, look.alpha > 0.01, pitch > 4 else { return }
        // Runs of points on one side of the core; the point where it crosses over ends one run and starts the next, so nothing gaps.
        var runs: [[CGPoint]] = []
        var run: [CGPoint] = []
        let step = max(2.5, min(6, pitch / 14))
        var x = look.tail
        while x <= look.head {
            let theta = 2 * .pi * x / pitch - spin
            let ramp = WorldKit.smoothstep(look.tail, look.tail + pitch * 0.9, x) * (1 - WorldKit.smoothstep(look.head - pitch * 0.4, look.head, x))
            let p = CGPoint(x: x, y: radius * ramp * sin(theta))
            if (cos(theta) >= 0) == front {
                run.append(p)
            } else if !run.isEmpty {
                run.append(p)
                runs.append(run)
                run = []
            }
            x += step
        }
        if run.count > 1 { runs.append(run) }
        guard !runs.isEmpty else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.translateBy(x: look.origin.x, y: look.origin.y)
        ctx.rotate(by: CGFloat(look.angle))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let a = look.alpha * (front ? 1 : 0.45)
        let passes: [(Double, SIMD3<Double>, Double)] = front
            ? [(3.6, colour, 0.24), (1.0, mix(colour, white, 0.25), 0.95), (0.36, white, 0.85)]
            : [(2.6, colour, 0.2), (0.7, colour, 0.8)]
        for (w, c, k) in passes {
            ctx.setLineWidth(CGFloat(max(0.8, lineWidth * w)))
            ctx.setStrokeColor(HandFXKit.cgColor(c, k * a))
            for r in runs where r.count > 1 { HandFXKit.stroke(r, in: ctx) }
        }
        ctx.restoreGState()
    }

    /// The soft light a beam throws on the room: a row of washes along it.
    static func beamWashes(_ look: SaiyanBeamLook, strength: Double = 0.13) -> [SaiyanWash] {
        let len = look.head - look.tail
        guard len > 1, look.alpha > 0.01 else { return [] }
        let n = min(9, max(2, Int(len / (look.width * 1.1)) + 1))
        let d = SIMD2(cos(look.angle), sin(look.angle))
        return (0..<n).map { i in
            let x = look.tail + len * (Double(i) + 0.5) / Double(n)
            return SaiyanWash(center: CGPoint(x: look.origin.x + d.x * x, y: look.origin.y + d.y * x), radius: look.width * 1.3,
                              colour: look.ki.body, alpha: strength * look.alpha)
        }
    }

    /// The flare where a beam leaves the hands: nested discs of light, a burst of spikes longest along the beam, and for a moment after
    /// firing (`burst` 0...1 through it) two rings bursting outward across the beam.
    static func drawMuzzle(at p: CGPoint, angle: Double, width w: Double, ki: SaiyanKi, alpha: Double, burst: Double?, time: Double, seed: Int = 0,
                           in ctx: CGContext) {
        guard alpha > 0.01 else { return }
        let pulse = 1 + 0.07 * sin(time * 31 + Double(seed)) + 0.04 * sin(time * 13)
        // The hot middle is kept to a hand's size, so a wide beam does not bury the hands and the chest in white.
        glowDisc(at: p, radius: min(w, 150) * 0.72 * pulse, ki: ki, alpha: alpha, in: ctx)
        spikes(at: p, count: 8, rotation: angle + time * 0.45, length: min(w, 200) * 1.05, base: min(w, 200) * 0.11, axis: angle, bias: 0.7,
               colour: ki.lit(0.5), alpha: 0.75 * alpha, time: time, seed: seed, in: ctx)
        guard let k = burst, k < 1 else { return }
        let d = SIMD2(cos(angle), sin(angle))
        for (i, delay) in [0.0, 0.2].enumerated() {
            let f = (k - delay) / (1 - delay)
            guard f > 0, f < 1 else { continue }
            let r = w * (0.5 + 1.5 * HandFXKit.easeOutCubic(f))
            let at = CGPoint(x: p.x + d.x * w * 0.2 * f, y: p.y + d.y * w * 0.2 * f)
            let fade = (1 - f) * (1 - f) * alpha
            ring(at: at, rx: r * (0.3 + 0.12 * Double(i)), ry: r, thickness: max(3, w * 0.12 * (1 - f)), rotation: angle, colour: ki.body,
                 alpha: 0.35 * fade, in: ctx)
            ring(at: at, rx: r * (0.3 + 0.12 * Double(i)), ry: r, thickness: max(1.2, w * 0.03 * (1 - f)), rotation: angle, colour: ki.lit(0.7),
                 alpha: 0.9 * fade, in: ctx)
        }
    }
}

/// One beam as it should be drawn this frame. Distances are in pixels along the beam from `origin`.
struct SaiyanBeamLook {
    var origin: CGPoint
    /// Which way it runs, radians.
    var angle: Double
    /// Where the light starts (0 while it pours; it runs out toward the head when the beam ends) and where its head is.
    var tail: Double
    var head: Double
    /// The body's width.
    var width: Double
    var alpha: Double
    var ki: SaiyanKi
    var time: Double
    var seed: Int
    /// How much of the half width the white core takes; above 0.11 the core bands widen (for thin beams).
    var core = 0.11
    var wobble = 1.0
    var rings = true
    /// Between rings, in widths, and how fast they run out, in pixels a second.
    var ringSpacing = 1.1
    var ringSpeed = 1400.0
    var filaments = 2
    var crackle = 0
    /// The round swell at the head, 0...1.
    var bulb = 1.0
    /// How opaque the solid body under the light is, 0 for none (a thin beam adds its body as light instead).
    var solid = 0.0
}

// MARK: - Impact

/// Where a beam meets the edge of the picture: a white burst at first contact, a hot splash that boils while the beam pours in, spikes of
/// light splashing back off the edge, a quick shock ring, and sparks (the sparks belong to whoever owns the impact). Its glow is a wash.
struct SaiyanImpact {
    var point: CGPoint
    /// Back into the picture, away from the edge.
    var normal: SIMD2<Double>
    var size: Double
    var ki: SaiyanKi
    var seed: Int
    var age = 0.0
    /// 1 while the beam is still landing here, easing to 0 when it stops.
    var pour = 1.0

    var isAlive: Bool { age < 0.6 || pour > 0.01 }
    /// The first-contact flash, 1 falling to 0.
    var burst: Double { exp(-age / 0.12) }

    mutating func update(dt: Double, pouring: Bool) {
        age += dt
        pour = pouring ? min(1, pour + dt / 0.08) : max(0, pour - dt / 0.3)
    }

    func washes() -> [SaiyanWash] {
        let strength = min(1, 0.5 * pour + 0.7 * burst)
        guard strength > 0.01 else { return [] }
        return [SaiyanWash(center: point, radius: size * (1.6 + 0.8 * burst), colour: ki.body, alpha: 0.45 * strength),
                SaiyanWash(center: point, radius: size * 0.8, colour: ki.lit(0.5), alpha: 0.4 * strength)]
    }

    func draw(time: Double, in ctx: CGContext) {
        let boil = pour * (0.88 + 0.08 * sin(time * 41 + Double(seed)) + 0.04 * sin(time * 97))
        let flash = burst
        let strength = min(1, boil + flash)
        guard strength > 0.01 || age < 0.6 else { return }
        let s = size
        let facing = atan2(normal.y, normal.x)
        SaiyanBeamKit.disc(at: point, radius: s * (0.55 + 0.25 * flash), colour: ki.lit(0.4), alpha: 0.55 * strength, in: ctx)
        SaiyanBeamKit.disc(at: point, radius: s * (0.32 + 0.2 * flash), colour: ki.core, alpha: strength, in: ctx)
        // Light splashing back off the edge in a fan of spikes, each flickering on its own.
        SaiyanBeamKit.spikes(at: point, count: 7, rotation: facing, length: s * (1.35 + 0.8 * flash), base: s * 0.17, spread: 1.3,
                             colour: ki.lit(0.5), alpha: 0.85 * strength, time: time, seed: seed, in: ctx)
        // A quick, thick shock pulse at first contact.
        let f = age / 0.3
        if f < 1 {
            let r = s * (0.45 + 0.9 * HandFXKit.easeOutCubic(f))
            SaiyanBeamKit.ring(at: point, rx: r, ry: r, thickness: max(1.5, s * 0.16 * (1 - f)), colour: ki.lit(0.55), alpha: 0.6 * (1 - f) * (1 - f), in: ctx)
        }
    }
}

// MARK: - Sparks and motes

/// Hot specks thrown off an impact or a muzzle, cooling from white to the move's colour as they fly: a short streak while they are fast,
/// a dot once they slow.
struct SaiyanSparks {
    private(set) var system: ParticleSystem
    private var rng: SplitMix64

    init(seed: UInt64, capacity: Int = 90, gravity: Double = -520, drag: Double = 1.2) {
        system = ParticleSystem(capacity: capacity)
        system.gravity = SIMD2(0, gravity)
        system.drag = drag
        rng = SplitMix64(seed: seed)
    }

    var count: Int { system.particles.count }
    var isEmpty: Bool { system.particles.isEmpty }

    mutating func removeAll() { system.removeAll() }

    /// Throws `count` sparks from `p`, round `direction` (any way when nil) within `spread` radians either side.
    mutating func burst(at p: CGPoint, count: Int, direction: SIMD2<Double>? = nil, spread: Double = .pi, speed: ClosedRange<Double> = 160...520,
                        life: ClosedRange<Double> = 0.25...0.6, size: ClosedRange<Double> = 1.6...3.8) {
        let base = direction.map { atan2($0.y, $0.x) } ?? 0
        for _ in 0..<max(0, count) {
            let a = direction == nil ? Double.random(in: 0..<(2 * .pi), using: &rng) : base + Double.random(in: -spread...spread, using: &rng)
            let v = Double.random(in: speed, using: &rng)
            system.emit(Particle(position: SIMD2(Double(p.x), Double(p.y)), velocity: SIMD2(cos(a), sin(a)) * v, age: 0,
                                 life: Double.random(in: life, using: &rng), size: Double.random(in: size, using: &rng)))
        }
    }

    /// Emits at a steady `rate` a second (a fraction carried over by chance).
    mutating func stream(at p: CGPoint, rate: Double, dt: Double, direction: SIMD2<Double>? = nil, spread: Double = .pi,
                         speed: ClosedRange<Double> = 160...520, life: ClosedRange<Double> = 0.25...0.6, size: ClosedRange<Double> = 1.6...3.8) {
        let wanted = rate * dt
        var n = Int(wanted)
        if Double.random(in: 0..<1, using: &rng) < wanted - Double(n) { n += 1 }
        burst(at: p, count: n, direction: direction, spread: spread, speed: speed, life: life, size: size)
    }

    mutating func step(_ dt: Double) { system.step(dt) }

    /// Each spark is a thin sliver along its flight, pointed behind and blunt in front, so a whole spray is four fills: one per step of
    /// cooling, from white-hot to the move's colour, each fainter than the last.
    func draw(colour: SIMD3<Double>, alpha: Double = 1, in ctx: CGContext) {
        guard alpha > 0.01, !system.particles.isEmpty else { return }
        for step in 0..<4 {
            let path = CGMutablePath()
            var any = false
            for p in system.particles where min(3, Int(p.progress * 4)) == step {
                let speed = max(1, simd_length(p.velocity))
                let d = p.velocity / speed, n = SIMD2(-d.y, d.x) * (p.size * 0.5 * (1 - 0.5 * p.progress))
                let tail = p.position - d * max(p.size * 1.5, min(36, speed * 0.04))
                path.move(to: CGPoint(x: tail.x, y: tail.y))
                path.addLine(to: CGPoint(x: p.position.x + n.x, y: p.position.y + n.y))
                path.addLine(to: CGPoint(x: p.position.x + d.x * p.size * 0.5, y: p.position.y + d.y * p.size * 0.5))
                path.addLine(to: CGPoint(x: p.position.x - n.x, y: p.position.y - n.y))
                path.closeSubpath()
                any = true
            }
            guard any else { continue }
            let k = Double(step) / 3
            ctx.addPath(path)
            ctx.setFillColor(HandFXKit.cgColor(SaiyanBeamKit.mix(SaiyanBeamKit.white, colour, 0.2 + 0.8 * k), (1 - 0.65 * k) * alpha))
            ctx.fillPath()
        }
    }
}

/// Specks of energy drawn in toward a charging ball from all round it, curling a little and quickening as they arrive.
struct SaiyanMotes {
    struct Mote {
        var angle: Double
        var distance: Double
        var age = 0.0
        var life: Double
        var curl: Double
    }

    private(set) var motes: [Mote] = []
    private var rng: SplitMix64
    private let capacity: Int

    init(seed: UInt64, capacity: Int = 28) {
        rng = SplitMix64(seed: seed)
        self.capacity = capacity
    }

    var isEmpty: Bool { motes.isEmpty }
    mutating func removeAll() { motes.removeAll() }

    /// Moves them on, and lets in about `rate` new ones a second from `reach` pixels out.
    mutating func update(dt: Double, rate: Double, reach: Double) {
        for i in motes.indices { motes[i].age += dt }
        motes.removeAll { $0.age >= $0.life }
        let wanted = rate * dt
        var n = Int(wanted)
        if Double.random(in: 0..<1, using: &rng) < wanted - Double(n) { n += 1 }
        for _ in 0..<n where motes.count < capacity {
            motes.append(Mote(angle: Double.random(in: 0..<(2 * .pi), using: &rng), distance: reach * Double.random(in: 0.85...1.3, using: &rng),
                              life: Double.random(in: 0.35...0.6, using: &rng), curl: Double.random(in: -0.8...0.8, using: &rng)))
        }
    }

    /// Each mote a small teardrop rushing in, its head pale: two fills for all of them. A mote fades in by growing from nothing rather than
    /// by its own alpha, so they can share one fill.
    func draw(at c: CGPoint, radius r: Double, colour: SIMD3<Double>, alpha: Double, in ctx: CGContext) {
        guard alpha > 0.01, !motes.isEmpty else { return }
        let tails = CGMutablePath(), heads = CGMutablePath()
        for m in motes {
            let k = m.age / m.life
            let d = r + (m.distance - r) * (1 - k * k)
            let a = m.angle + m.curl * k * k
            let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
            let grow = min(1, k * 3) * (1 - WorldKit.smoothstep(0.8, 1, k))
            SaiyanBeamKit.teardrop(tails, head: p, angle: a + .pi, length: (8 + 24 * k) * grow, width: 5 * grow)
            heads.addEllipse(in: CGRect(x: p.x - 2 * grow, y: p.y - 2 * grow, width: 4 * grow, height: 4 * grow))
        }
        SaiyanBeamKit.fill(tails, colour: colour, alpha: 0.75 * alpha, in: ctx)
        SaiyanBeamKit.fill(heads, colour: SaiyanBeamKit.mix(colour, SaiyanBeamKit.white, 0.7), alpha: alpha, in: ctx)
    }
}

// MARK: - A fired beam

/// A beam from the moment it leaves the hands until its tail has run out: its head shoots out to the edge of the picture, it pours there
/// for a while (or for as long as it is held), then its tail runs after its head and it thins away. It owns its impact and sparks, and
/// knows how hard it kicks.
struct SaiyanBeamRig {
    /// How a move's beams look and behave.
    struct Style {
        var core = 0.11
        var rings = true
        var ringSpacing = 1.1
        var ringSpeed = 1400.0
        var filaments = 2
        var wobble = 1.0
        /// The solid body under the light, 0 for none.
        var solid = 0.0
        /// Seconds for the head to reach the edge, and for the tail to run out.
        var grow = 0.2
        var fade = 0.45
        /// The jolt of firing and the rumble while it pours, 0...1 of the lens's shake.
        var kick = 0.5
        var rumble = 0.12
        /// The flash over the whole picture at the moment of firing.
        var flash = 0.3
        /// Sparks a second off the impact while it pours, per 100 pixels of width.
        var sparks = 60.0
        /// How big the splash at the edge is, as a part of the width.
        var impact = 1.0
    }

    /// The beam itself.
    struct Shot {
        var origin: CGPoint
        var angle: Double
        var width: Double
        var ki: SaiyanKi
        /// How long it pours once it has landed; `.infinity` while it is held.
        var pour: Double
        var crackle: Int
        var age = 0.0
        /// Seconds since it began to run out, once it has.
        var ending: Double?
        /// From the origin to the edge of the picture, this frame.
        var reach = 0.0
        var landed = false
        var seed: Int
    }

    var style: Style
    private(set) var shot: Shot?
    private(set) var impact: SaiyanImpact?
    private(set) var sparks: SaiyanSparks
    /// Seconds since the last shot was fired, and since it landed.
    private(set) var sinceFire = 99.0
    private(set) var sinceLanding = 99.0
    private(set) var fired = 0
    private(set) var time = 0.0
    private var rect = CGRect(x: 0, y: 0, width: 1280, height: 720)

    init(style: Style, seed: UInt64) {
        self.style = style
        sparks = SaiyanSparks(seed: seed)
    }

    mutating func reset() {
        shot = nil
        impact = nil
        sparks.removeAll()
        sinceFire = 99
        sinceLanding = 99
    }

    /// Fires a new beam (replacing any still running out).
    mutating func fire(from origin: CGPoint, angle: Double, width: Double, ki: SaiyanKi, pour: Double, crackle: Int, rect: CGRect) {
        self.rect = rect
        fired += 1
        var s = Shot(origin: Self.inside(origin, rect), angle: angle, width: width, ki: ki, pour: pour, crackle: crackle, seed: fired * 7919 + 3)
        s.reach = reach(from: s.origin, angle: angle)
        shot = s
        impact = nil
        sinceFire = 0
        sparks.burst(at: origin, count: Int(8 + min(16, width * 0.08)), direction: SIMD2(cos(angle), sin(angle)), spread: 1.1, speed: 220...700,
                     life: 0.2...0.45)
    }

    /// Starts the beam running out now, if it has not already.
    mutating func release() {
        guard var s = shot, s.ending == nil else { return }
        s.ending = 0
        shot = s
    }

    var isPouring: Bool { shot.map { $0.ending == nil } ?? false }
    var isRunning: Bool { shot != nil }
    var hasLight: Bool { shot != nil || (impact?.isAlive ?? false) || !sparks.isEmpty }

    /// Moves on one frame. `origin` and `angle` are where the beam leaves from now (it follows the hands); nil keeps the last.
    mutating func update(dt: Double, time: Double, origin: CGPoint?, angle: Double?, rect: CGRect) {
        self.rect = rect
        self.time = time
        sinceFire += dt
        sinceLanding += dt
        if var s = shot {
            s.age += dt
            if let origin { s.origin = HandFXKit.lerp(s.origin, Self.inside(origin, rect), min(1, dt / 0.05)) }
            if let angle {
                let delta = atan2(sin(angle - s.angle), cos(angle - s.angle))
                s.angle += delta * min(1, dt / 0.12)
            }
            s.reach = reach(from: s.origin, angle: s.angle)
            let d = SIMD2(cos(s.angle), sin(s.angle))
            let hit = CGPoint(x: s.origin.x + d.x * s.reach, y: s.origin.y + d.y * s.reach)
            let normal = Self.normal(at: hit, rect, fallback: -d)
            if !s.landed, s.age >= style.grow {
                s.landed = true
                sinceLanding = 0
                impact = SaiyanImpact(point: hit, normal: normal, size: min(170, s.width * style.impact), ki: s.ki, seed: s.seed)
                sparks.burst(at: hit, count: Int(12 + min(20, s.width * 0.12)), direction: normal, spread: 1.35, speed: 200...760, life: 0.3...0.7,
                             size: 1.8...4.4)
            }
            if s.ending == nil, s.landed, s.age >= style.grow + s.pour { s.ending = 0 }
            if let e = s.ending { s.ending = e + dt }
            let pouring = s.landed && (s.ending.map { $0 < style.fade * 0.6 } ?? true)
            if var i = impact {
                i.point = hit
                i.normal = normal
                i.size = min(170, s.width * style.impact) * (1 - 0.5 * fadeProgress(s))
                i.update(dt: dt, pouring: pouring)
                impact = i
                if pouring {
                    sparks.stream(at: hit, rate: style.sparks * min(2.5, s.width / 100), dt: dt, direction: normal, spread: 1.3, speed: 180...640,
                                  life: 0.25...0.55, size: 1.5...3.8)
                }
            }
            shot = (s.ending ?? 0) >= style.fade ? nil : s
        } else if var i = impact {
            i.update(dt: dt, pouring: false)
            impact = i.isAlive ? i : nil
        }
        sparks.step(dt)
    }

    private func fadeProgress(_ s: Shot) -> Double { s.ending.map { min(1, $0 / max(style.fade, 1e-3)) } ?? 0 }

    /// The beam as it should be drawn now, if there is one.
    var look: SaiyanBeamLook? {
        guard let s = shot else { return nil }
        let grow = HandFXKit.easeOutCubic(s.age / max(style.grow, 1e-3))
        let f = fadeProgress(s)
        let head = s.reach * grow
        let tail = head * SaiyanBeamKit.easeInQuad(f)
        // It swells for a moment as it is fired, starts narrow while its head is still flying, and thins as it runs out.
        let swell = 1 + 0.16 * exp(-s.age / 0.12)
        let width = s.width * swell * (1 - 0.55 * f) * (0.6 + 0.4 * WorldKit.smoothstep(0, 0.8, s.age / max(style.grow, 1e-3)))
        return SaiyanBeamLook(origin: s.origin, angle: s.angle, tail: tail, head: head, width: width, alpha: 1 - f * f, ki: s.ki, time: time,
                              seed: s.seed, core: style.core, wobble: style.wobble, rings: style.rings, ringSpacing: style.ringSpacing,
                              ringSpeed: style.ringSpeed, filaments: style.filaments, crackle: s.crackle, bulb: s.landed ? 0.5 : 1, solid: style.solid)
    }

    func washes() -> [SaiyanWash] {
        var out: [SaiyanWash] = []
        if let look {
            out += SaiyanBeamKit.beamWashes(look)
            let fresh = exp(-sinceFire / 0.18)
            out.append(SaiyanWash(center: look.origin, radius: look.width * (1.2 + 0.8 * fresh), colour: look.ki.body,
                                  alpha: (0.26 + 0.3 * fresh) * look.alpha * (1 - look.tail / max(1, look.head))))
        }
        if let impact { out += impact.washes() }
        return out
    }

    func drawSolids(in ctx: CGContext) {
        guard style.solid > 0, let look else { return }
        SaiyanBeamKit.drawBeamSolid(look, in: ctx)
    }

    func drawLight(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        if let look {
            SaiyanBeamKit.drawBeamLight(look, in: ctx)
            let burst = sinceFire < 0.4 ? sinceFire / 0.4 : nil
            // Once the tail leaves the hands, the flare there goes out.
            let attached = 1 - WorldKit.smoothstep(0, 0.2, look.tail / max(1, look.head))
            SaiyanBeamKit.drawMuzzle(at: look.origin, angle: look.angle, width: look.width, ki: look.ki, alpha: look.alpha * attached,
                                     burst: burst, time: time, seed: look.seed, in: ctx)
        }
        impact?.draw(time: time, in: ctx)
        sparks.draw(colour: shot?.ki.body ?? impact?.ki.body ?? SaiyanBeamKit.white, in: ctx)
        ctx.restoreGState()
    }

    /// How hard the picture shakes: a jolt when it fires, a smaller one when it lands, and a rumble while it pours.
    var shake: Double {
        let pouring = isPouring && (shot?.landed ?? false) ? 1.0 : 0
        let v = style.kick * exp(-sinceFire / 0.22) + style.kick * 0.4 * exp(-sinceLanding / 0.2) + style.rumble * pouring
        return v < 0.003 ? 0 : min(1, v)
    }

    /// The flash over the whole picture as it fires.
    var flash: Double {
        let v = style.flash * exp(-sinceFire / 0.1)
        return v < 0.003 ? 0 : v
    }

    var flashTint: SIMD3<Double> { (shot?.ki ?? impact?.ki).map { $0.lit(0.55) } ?? SaiyanBeamKit.white }

    /// From `origin` along `angle` to the edge of the picture.
    private func reach(from origin: CGPoint, angle: Double) -> Double {
        let o = SIMD2(Double(origin.x), Double(origin.y)), d = SIMD2(cos(angle), sin(angle))
        return simd_distance(o, HandGeometry.exit(from: o, direction: d, rect: rect))
    }

    private static func inside(_ p: CGPoint, _ rect: CGRect) -> CGPoint {
        CGPoint(x: min(rect.maxX - 2, max(rect.minX + 2, p.x)), y: min(rect.maxY - 2, max(rect.minY + 2, p.y)))
    }

    /// The way back into the picture from a point on its edge.
    static func normal(at p: CGPoint, _ rect: CGRect, fallback: SIMD2<Double>) -> SIMD2<Double> {
        var n = SIMD2<Double>(0, 0)
        if abs(p.x - rect.maxX) < 2 { n.x -= 1 }
        if abs(p.x - rect.minX) < 2 { n.x += 1 }
        if abs(p.y - rect.maxY) < 2 { n.y -= 1 }
        if abs(p.y - rect.minY) < 2 { n.y += 1 }
        return simd_length(n) > 0 ? simd_normalize(n) : fallback
    }
}

// MARK: - Reading hands

/// How long a pose has been held, with patience for the tracker: a frame or two of something else neither resets it nor counts toward it,
/// and a frame the tracker is only guessing at (a hand carried through a blur, `posed == nil`) freezes it.
struct SaiyanHold {
    /// How long the pose may be missing before the hold starts again.
    var grace: Double
    private(set) var held = 0.0
    /// Seconds since the pose was last seen.
    private(set) var missing = 0.0
    private var unsure = 0.0

    init(grace: Double) { self.grace = grace }

    mutating func update(_ posed: Bool?, dt: Double) {
        switch posed {
        case .some(true):
            held += dt
            missing = 0
            unsure = 0
        case .none:
            // A guess is held as it is, but not for ever.
            unsure += dt
            if unsure > 0.4 { missing += dt }
        case .some(false):
            missing += dt
            unsure = 0
        }
        if missing > grace { held = 0 }
    }

    /// Whether the pose is being held now (allowing for the grace).
    var isHeld: Bool { held > 0 && missing <= grace }

    mutating func reset() {
        held = 0
        missing = 0
        unsure = 0
    }
}

/// A short memory of a reading, newest last, for telling a thrust, a push or a spring apart over the last fraction of a second.
struct SaiyanTrail<Value> {
    private(set) var marks: [(time: Double, value: Value)] = []
    let span: Double

    init(span: Double) { self.span = span }

    mutating func add(_ value: Value, at time: Double) {
        marks.append((time, value))
        marks.removeAll { time - $0.time > span }
    }

    mutating func removeAll() { marks.removeAll() }

    var last: Value? { marks.last?.value }

    /// The marks from the last `seconds`.
    func within(_ seconds: Double, of now: Double) -> [Value] { marks.filter { now - $0.time <= seconds + 1e-9 }.map { $0.value } }

    /// The oldest mark no older than `seconds`.
    func since(_ seconds: Double, of now: Double) -> (time: Double, value: Value)? { marks.first { now - $0.time <= seconds + 1e-9 } }
}

enum SaiyanBeamHands {
    /// How fast a hand moves, in palm lengths a second.
    static func speed(_ h: HandState) -> Double { hypot(Double(h.velocity.dx), Double(h.velocity.dy)) / h.size }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    /// `p` moved `distance` pixels along the unit vector `v`.
    static func offset(_ p: CGPoint, _ v: SIMD2<Double>, by distance: Double) -> CGPoint { CGPoint(x: p.x + v.x * distance, y: p.y + v.y * distance) }

    /// The middle of the index and middle fingertips.
    static func twoTips(_ h: HandState) -> CGPoint { midpoint(h[.indexTip], h[.middleTip]) }

    /// An angle turned toward sideways: `side` (+1 right, -1 left) is kept and the slope is held within `limit` radians of level.
    static func sideways(_ angle: Double, side: Double, limit: Double) -> Double {
        let slope = atan2(sin(angle), abs(cos(angle)))
        let clamped = min(limit, max(-limit, slope))
        return side >= 0 ? clamped : .pi - clamped
    }
}
