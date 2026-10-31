import CoreGraphics
import CoreImage
import simd

/// Butterflies flutter about the room. Now and then one comes down to rest on the top of your head or your shoulder, opening
/// and closing its wings slowly, and it takes off again when you move nearby or after a while. A few fly further back, behind you.
struct WorldButterflySim {
    enum Species: Int, CaseIterable {
        case monarch, morpho, brimstone, paintedLady
    }

    enum State {
        case flying, landing, resting, leaving
    }

    struct Butterfly {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var flap: Double
        var species: Species
        /// Wingspan in pixels.
        var span: Double
        /// 0 far behind you ... 1 near.
        var depth: Double
        var state = State.flying
        var goal: SIMD2<Double>
        var untilNewGoal: Double
        var restLeft = 0.0
        var phase: Double

        /// Flies behind you and never lands.
        var isBehind: Bool { depth < 0.25 }
    }

    let size: CGSize
    private(set) var flies: [Butterfly] = []
    private(set) var time = 0.0
    private(set) var landings = 0
    private var rng: SplitMix64

    init(size: CGSize, count: Int = 8, seed: UInt64 = 0xB077E5) {
        self.size = size
        rng = SplitMix64(seed: seed)
        for k in 0..<count {
            let species = Species(rawValue: k % Species.allCases.count) ?? .monarch
            let depth = k == 2 || k == 6 ? Double.random(in: 0.05...0.2, using: &rng) : Double.random(in: 0.35...1, using: &rng)
            let at = randomPoint()
            flies.append(Butterfly(position: at, velocity: .zero, flap: Double.random(in: 0...(2 * .pi), using: &rng), species: species,
                                   span: Double.random(in: 120...150, using: &rng) * (depth < 0.25 ? 0.55 : 0.8 + 0.3 * depth), depth: depth,
                                   goal: randomPoint(), untilNewGoal: Double.random(in: 0.3...2.5, using: &rng), phase: Double.random(in: 0...(2 * .pi), using: &rng)))
        }
    }

    private mutating func randomPoint() -> SIMD2<Double> {
        SIMD2(Double.random(in: 80...(size.width - 80), using: &rng), Double.random(in: size.height * 0.3...(size.height - 70), using: &rng))
    }

    /// How open the wings are: 0 shut (edge on) ... 1 spread flat.
    static func openness(of b: Butterfly) -> Double {
        switch b.state {
        case .resting: return 0.45 + 0.55 * (0.5 + 0.5 * sin(b.flap))
        default: return 0.1 + 0.9 * (0.5 + 0.5 * cos(b.flap))
        }
    }

    /// Places on top of the silhouette a butterfly could sit: the highest solid cell in every few columns.
    static func perches(in grid: MatteGrid?) -> [SIMD2<Double>] {
        guard let grid else { return [] }
        var found: [SIMD2<Double>] = []
        for gx in stride(from: 2, to: grid.width - 2, by: 3) {
            let x = (Double(gx) + 0.5) * grid.cellSize
            var y = Double(grid.height) * grid.cellSize - grid.cellSize * 3
            while y > grid.cellSize * 6 {
                if grid.coverage(x: x, y: y) > 0.6 {
                    found.append(SIMD2(x, y + grid.cellSize * 0.4))
                    break
                }
                y -= grid.cellSize
            }
        }
        return found
    }

    /// Puts a butterfly somewhere. For tests.
    mutating func place(_ index: Int, at p: SIMD2<Double>, state: State) {
        guard flies.indices.contains(index) else { return }
        flies[index].position = p
        flies[index].goal = p
        flies[index].state = state
        flies[index].velocity = .zero
        if state == .resting { flies[index].restLeft = 5 }
    }

    /// `perches` are where a butterfly may land; `disturbance` is where the person just moved and how much.
    mutating func step(_ rawDt: Double, perches: [SIMD2<Double>], matte: MatteQuery?, disturbance: (point: SIMD2<Double>, strength: Double)?) {
        let dt = WorldKit.clamped(rawDt)
        time += dt
        let settled = flies.filter { $0.state == .resting || $0.state == .landing }.count
        // Roughly where your face is: a little below the top of your head. Butterflies in front steer round it.
        let face = perches.max { $0.y < $1.y }.map { $0 - SIMD2(0, 115) }
        for i in flies.indices {
            var b = flies[i]
            switch b.state {
            case .resting:
                b.flap += 2.6 * dt
                b.restLeft -= dt
                // Ride along with whatever it sits on; let go if it has gone, if you move nearby, or when it has rested enough.
                let near = perches.filter { abs($0.x - b.position.x) < 26 }.min { abs($0.y - b.position.y) < abs($1.y - b.position.y) }
                let disturbed = disturbance.map { simd_length($0.point - b.position) < 190 && $0.strength > 0.3 } ?? false
                let stillThere = matte.map { $0.coverage(x: b.position.x, y: b.position.y - 10) > 0.4 } ?? false
                if let near, stillThere, !disturbed, b.restLeft > 0 {
                    b.position += (near - b.position) * (1 - exp(-dt * 6))
                } else {
                    b.state = .leaving
                    b.velocity = SIMD2(Double.random(in: -120...120, using: &rng), Double.random(in: 150...230, using: &rng))
                    b.untilNewGoal = 1.2
                    b.goal = randomPoint()
                }
            case .flying, .landing, .leaving:
                b.flap += (b.state == .leaving ? 38 : 31) * dt
                b.untilNewGoal -= dt
                if b.state == .landing, !perches.contains(where: { simd_length($0 - b.goal) < 30 }) {
                    // The spot it was heading for has gone.
                    b.state = .flying
                    b.untilNewGoal = 0
                }
                if b.untilNewGoal <= 0 {
                    b.untilNewGoal = Double.random(in: 2...4.5, using: &rng)
                    if b.state == .leaving { b.state = .flying }
                    if !b.isBehind, !perches.isEmpty, settled < 3, Double.random(in: 0...1, using: &rng) < 0.5 {
                        b.goal = perches[Int.random(in: 0..<perches.count, using: &rng)]
                        b.state = .landing
                    } else {
                        b.goal = randomPoint()
                        if b.state == .landing { b.state = .flying }
                    }
                }
                let to = b.goal - b.position
                let distance = simd_length(to)
                if b.state == .landing, distance < 9 {
                    b.state = .resting
                    b.restLeft = Double.random(in: 4...9, using: &rng)
                    b.velocity = .zero
                    b.flap = 0
                    landings += 1
                    break
                }
                // Fluttering flight: toward the goal, but zig-zagging, and lifted a little on every wingbeat.
                let cruise = b.state == .landing ? min(110, 40 + distance * 1.4) : 95.0
                let dir = distance > 1e-6 ? to / distance : SIMD2(0, 1)
                let side = SIMD2(-dir.y, dir.x) * sin(time * 2.7 + b.phase) * 70
                let lift = SIMD2(0, sin(b.flap) * 55)
                var desired = b.state == .leaving ? b.velocity : dir * cruise + side + lift
                if let face, !b.isBehind, !(b.state == .landing && distance < 70) {
                    let away = b.position - face
                    let d = simd_length(away)
                    if d < 150, d > 1e-6 { desired += away / d * (150 - d) * 5 }
                }
                b.velocity += (desired - b.velocity) * (1 - exp(-dt * 3.2))
                b.position += b.velocity * dt
                b.position.x = min(size.width + 40, max(-40, b.position.x))
                b.position.y = min(size.height + 40, max(-40, b.position.y))
            }
            flies[i] = b
        }
    }
}

final class WorldButterfliesLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private var sim: WorldButterflySim
    private var watcher = FireflyMotionWatcher()
    /// The wing art, drawn once on first use (on the video queue) and shared by every copy of the lens.
    private static let wingArt: [CGImage?] = WorldButterflySim.Species.allCases.map { wing($0) }

    init(size: CGSize = CGSize(width: 1280, height: 720)) { sim = WorldButterflySim(size: size) }

    func restart() {
        sim = WorldButterflySim(size: sim.size)
        watcher.reset()
    }

    var flies: [WorldButterflySim.Butterfly] { sim.flies }
    var landings: Int { sim.landings }
    /// Sets a butterfly down somewhere at once. For tests and previews.
    func place(_ index: Int, at p: SIMD2<Double>, state: WorldButterflySim.State) { sim.place(index, at: p, state: state) }

    func render(_ input: LensInput) -> CIImage {
        let interest = watcher.interest(from: input.matteGrid)
        sim.step(input.dt, perches: WorldButterflySim.perches(in: input.matteGrid), matte: input.matteGrid,
                 disturbance: interest.map { ($0.point, $0.strength) })
        let rect = input.rect

        // "Garden": a fresh, sunny light from the top left.
        let sun = SIMD3(1.0, 0.95, 0.8)
        var room = WorldKit.grade(input.scenery, saturation: 1.1, tint: (1.04, 1.04, 0.98), lift: (0.008, 0.01, 0.006))
        room = WorldKit.adding(WorldKit.wash(center: CGPoint(x: rect.width * 0.06, y: rect.height * 1.05), radius: 520, red: sun.x, green: sun.y, blue: sun.z,
                                             alpha: 0.2, in: rect), to: room)
        if let layer = input.services.overlay({ ctx in draw(in: ctx, behind: true) }) { room = layer.composited(over: room) }
        let person = WorldKit.grade(input.composed, saturation: 1.05, tint: (1.03, 1.03, 0.99), lift: (0.004, 0.005, 0.003))
        var body = WorldKit.place(person: person, over: room, matte: input.matte, rect: rect)
        if let rim = WorldKit.rimLight(matte: input.matte, rect: rect, toward: WorldKit.keyLight, width: 12, colour: sun, strength: 0.28) {
            body = WorldKit.adding(rim, to: body)
        }
        guard let front = input.services.overlay({ ctx in draw(in: ctx, behind: false) }) else { return body }
        return front.composited(over: body).cropped(to: rect)
    }

    // MARK: Drawing

    private func draw(in ctx: CGContext, behind: Bool) {
        ctx.interpolationQuality = .medium
        for b in sim.flies where b.isBehind == behind {
            guard let wing = Self.wingArt[b.species.rawValue] else { continue }
            let open = WorldButterflySim.openness(of: b)
            let span = b.span
            let at = CGPoint(x: b.position.x, y: b.position.y)
            // Banks into its turns; sits upright when resting.
            let bank = b.state == .resting ? 0.12 * sin(b.phase) : max(-0.6, min(0.6, -b.velocity.x / 260))
            if b.state == .resting, let shadow = WorldKit.softGlow(0.1, 0.06, 0.06) {
                // A soft shadow where it sits, so it is on you rather than floating in front.
                ctx.stampDot(shadow, at: CGPoint(x: at.x + 5, y: at.y - span * 0.16), radius: span * 0.4 * (0.6 + 0.4 * open), alpha: 0.3)
            }
            ctx.saveGState()
            ctx.translateBy(x: at.x, y: at.y)
            ctx.rotate(by: bank)
            ctx.setAlpha(behind ? 0.85 : 1)
            let half = span / 2, tall = half * Double(wing.height) / Double(wing.width) * 0.74
            for side in [-1.0, 1.0] {
                ctx.saveGState()
                // The wing turns on the body: seen narrower as it lifts toward edge on.
                ctx.scaleBy(x: side * max(0.08, open), y: 1)
                ctx.draw(wing, in: CGRect(x: -half * Self.rootInset, y: -tall * 0.5, width: half, height: tall))
                ctx.restoreGState()
            }
            drawBody(in: ctx, span: span)
            ctx.restoreGState()
        }
        ctx.interpolationQuality = .high
    }

    /// The body: a dark furry thorax and abdomen with a lit edge, a round head, and two antennae with clubbed tips.
    private func drawBody(in ctx: CGContext, span: Double) {
        let s = span / 100
        ctx.setFillColor(CGColor(red: 0.14, green: 0.1, blue: 0.08, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: -2.6 * s, y: -15 * s, width: 5.2 * s, height: 17 * s))
        ctx.fillEllipse(in: CGRect(x: -3.4 * s, y: 0, width: 6.8 * s, height: 9 * s))
        ctx.fillCircle(center: CGPoint(x: 0, y: 10.5 * s), radius: 2.9 * s, color: CGColor(red: 0.12, green: 0.09, blue: 0.07, alpha: 1))
        ctx.setFillColor(CGColor(red: 0.6, green: 0.5, blue: 0.42, alpha: 0.6))
        ctx.fillEllipse(in: CGRect(x: -2.2 * s, y: 1.5 * s, width: 1.6 * s, height: 6 * s))
        ctx.setStrokeColor(CGColor(red: 0.14, green: 0.1, blue: 0.08, alpha: 1))
        ctx.setLineWidth(max(0.8, 0.9 * s))
        ctx.setLineCap(.round)
        for side in [-1.0, 1.0] {
            ctx.move(to: CGPoint(x: side * 1.2 * s, y: 12.5 * s))
            ctx.addQuadCurve(to: CGPoint(x: side * 7 * s, y: 24 * s), control: CGPoint(x: side * 2.2 * s, y: 20 * s))
            ctx.strokePath()
            ctx.fillCircle(center: CGPoint(x: side * 7 * s, y: 24 * s), radius: 1.3 * s, color: CGColor(red: 0.14, green: 0.1, blue: 0.08, alpha: 1))
        }
    }

    // MARK: Wing art

    /// How far into the sprite the wing root sits, as a share of its width.
    private static let rootInset = 0.04

    /// The right-hand pair of wings for a species, drawn once: shaped fore and hind wings, the species' colours and markings,
    /// veins, a soft highlight from the top left, and a darker edge.
    private static func wing(_ species: WorldButterflySim.Species) -> CGImage? {
        let w = 150, h = 220
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        func colour(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
        let unit = Double(w) * 0.94
        ctx.translateBy(x: Double(w) * rootInset, y: Double(h) / 2)
        ctx.scaleBy(x: unit, y: unit)

        let fore = CGMutablePath()
        fore.move(to: CGPoint(x: 0.02, y: 0.05))
        fore.addCurve(to: CGPoint(x: 0.9, y: 0.74), control1: CGPoint(x: 0.25, y: 0.52), control2: CGPoint(x: 0.6, y: 0.82))
        fore.addCurve(to: CGPoint(x: 0.86, y: 0.2), control1: CGPoint(x: 1.02, y: 0.62), control2: CGPoint(x: 0.98, y: 0.34))
        fore.addCurve(to: CGPoint(x: 0.04, y: -0.02), control1: CGPoint(x: 0.6, y: 0.1), control2: CGPoint(x: 0.3, y: 0.02))
        fore.closeSubpath()
        let hind = CGMutablePath()
        hind.move(to: CGPoint(x: 0.03, y: -0.02))
        hind.addCurve(to: CGPoint(x: 0.74, y: -0.2), control1: CGPoint(x: 0.35, y: 0.06), control2: CGPoint(x: 0.7, y: -0.02))
        hind.addCurve(to: CGPoint(x: 0.3, y: -0.74), control1: CGPoint(x: 0.82, y: -0.46), control2: CGPoint(x: 0.58, y: -0.76))
        hind.addCurve(to: CGPoint(x: 0.02, y: -0.12), control1: CGPoint(x: 0.12, y: -0.72), control2: CGPoint(x: 0.02, y: -0.4))
        hind.closeSubpath()

        let (inner, outer, border, veins): (CGColor, CGColor, CGColor?, CGColor)
        switch species {
        case .monarch: (inner, outer, border, veins) = (colour(1.0, 0.66, 0.16), colour(0.9, 0.36, 0.04), colour(0.08, 0.05, 0.04), colour(0.08, 0.05, 0.04, 0.9))
        case .morpho: (inner, outer, border, veins) = (colour(0.45, 0.85, 1.0), colour(0.08, 0.34, 0.92), colour(0.05, 0.05, 0.1), colour(0.05, 0.12, 0.3, 0.5))
        case .brimstone: (inner, outer, border, veins) = (colour(1.0, 0.98, 0.66), colour(0.93, 0.86, 0.34), nil, colour(0.6, 0.6, 0.25, 0.45))
        case .paintedLady: (inner, outer, border, veins) = (colour(1.0, 0.72, 0.45), colour(0.92, 0.42, 0.22), colour(0.12, 0.07, 0.06), colour(0.25, 0.1, 0.05, 0.6))
        }

        for (path, isFore) in [(hind, false), (fore, true)] {
            ctx.saveGState()
            // A soft shadow under each wing lifts it off whatever is behind.
            ctx.setShadow(offset: CGSize(width: 1.5, height: -2.5), blur: 4, color: colour(0, 0, 0, 0.3))
            ctx.addPath(path)
            ctx.setFillColor(outer)
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            if let g = CGGradient(colorsSpace: space, colors: [inner, outer] as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: 0.05, y: 0), startRadius: 0, endCenter: CGPoint(x: 0.05, y: 0), endRadius: 0.95, options: [.drawsAfterEndLocation])
            }
            // Markings.
            switch species {
            case .paintedLady where isFore:
                ctx.setFillColor(border ?? outer)
                ctx.fillEllipse(in: CGRect(x: 0.55, y: 0.3, width: 0.6, height: 0.6))
            case .brimstone:
                ctx.fillCircle(center: CGPoint(x: isFore ? 0.42 : 0.36, y: isFore ? 0.32 : -0.34), radius: 0.035, color: colour(0.95, 0.55, 0.15))
            default: break
            }
            // Veins fanning out from the root.
            ctx.setStrokeColor(veins)
            ctx.setLineWidth(species == .monarch ? 0.016 : 0.009)
            let tips: [CGPoint] = isFore ? [CGPoint(x: 0.88, y: 0.7), CGPoint(x: 0.95, y: 0.48), CGPoint(x: 0.9, y: 0.28), CGPoint(x: 0.6, y: 0.12), CGPoint(x: 0.5, y: 0.6)]
                                         : [CGPoint(x: 0.7, y: -0.22), CGPoint(x: 0.64, y: -0.48), CGPoint(x: 0.42, y: -0.7), CGPoint(x: 0.2, y: -0.66)]
            for tip in tips {
                ctx.move(to: CGPoint(x: 0.04, y: 0))
                ctx.addQuadCurve(to: tip, control: CGPoint(x: tip.x * 0.45, y: tip.y * 0.25))
            }
            ctx.strokePath()
            // A dark border band with pale spots, for the species that have one.
            if let border {
                ctx.addPath(path)
                ctx.setStrokeColor(border)
                ctx.setLineWidth(species == .morpho ? 0.2 : 0.14)
                ctx.strokePath()
                let spots: [CGPoint] = isFore ? [CGPoint(x: 0.86, y: 0.62), CGPoint(x: 0.92, y: 0.45), CGPoint(x: 0.88, y: 0.3), CGPoint(x: 0.76, y: 0.68)]
                                              : [CGPoint(x: 0.68, y: -0.32), CGPoint(x: 0.56, y: -0.56), CGPoint(x: 0.38, y: -0.68)]
                for spot in spots { ctx.fillCircle(center: spot, radius: 0.022, color: colour(1, 0.98, 0.94)) }
            }
            // Light from the top left, and a darker trailing edge.
            if let g = CGGradient(colorsSpace: space, colors: [colour(1, 1, 1, 0.22), colour(1, 1, 1, 0), colour(0, 0, 0, 0.12)] as CFArray, locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0.1, y: 0.8), end: CGPoint(x: 0.7, y: -0.6), options: [])
            }
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }
}
