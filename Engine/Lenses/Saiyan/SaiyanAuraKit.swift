import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import simd

// The pieces the body half shares: how each form's aura looks as numbers that blend, the blend of forms for one frame, the colour ramps,
// where the person's outline is, and the flowing noise and field that the aura's flame is made of.

// MARK: - The look of an aura

/// How one form's aura moves and shines, as numbers that can be blended, so one form's aura melts into the next instead of switching.
/// Distances are output pixels for a person whose eyes are 84 pixels apart (`SaiyanOutline.unit` 1); the aura scales with the person, so a
/// face far from the camera gets a smaller aura. Read from `SaiyanForm` (style, size, lightning, strength); nothing here is a colour.
struct SaiyanAuraLook {
    /// How far the body of the flame reaches past the outline, and how soft its edge is. The body is bright enough that only a thin band
    /// next to the outline reaches the white-hot core; the rest is the form's colour.
    var reach = 6.0
    var softness = 10.0
    /// How far the flowing noise pushes the flame's edge about, and how big the ragged bits are.
    var lick = 18.0
    var grain = 26.0
    /// Tongues rising off the head and shoulders: how tall, how bright, how wide, and how separate (0 a smooth sheet, 1 apart).
    var tongue = 150.0
    var tongueGain = 0.8
    var tongueGrain = 22.0
    var tongueCut = 0.75
    /// How fast the flame climbs, in pixels a second, and how far it rolls from side to side.
    var climb = 260.0
    var roll = 0.0
    /// The shape of the noise: tall for a licking flame, wide for a rolling one.
    var stretchX = 1.0
    var stretchY = 2.6
    /// The body of the flame; the mantle, a soft flame-shaped glow round the whole figure that rises above the head; and the wide soft glow
    /// the aura throws on the room (its gain and its blur).
    var bodyGain = 1.5
    var mantle = 0.3
    /// How far the mantle spreads past the outline, against the body's reach.
    var mantleReach = 2.6
    var halo = 0.28
    var haloReach = 60.0
    /// A slow flicker (amount, and rate in hertz) and a hard random strobe.
    var flicker = 0.07
    var flickerRate = 11.0
    var strobe = 0.0
    /// Blue Kaioken's red beat, Blue's sparkle, Ultra Instinct's fine strands.
    var pulse = 0.0
    var shimmer = 0.0
    var wisps = 0.0
    /// How much the room darkens under the glow, so the light still reads against a bright wall.
    var veil = 0.62
    /// Light wrapping round the person's own edges.
    var wrap = 0.45
    /// Embers: how fast they rise and how big they are, and how many are glints or slow motes instead.
    var emberSpeed = 1.0
    var emberSize = 1.0
    var sparkles = 0.0
    var motes = 0.0

    private static let blended: [WritableKeyPath<SaiyanAuraLook, Double>] = [
        \.reach, \.softness, \.lick, \.grain, \.tongue, \.tongueGain, \.tongueGrain, \.tongueCut, \.climb, \.roll, \.stretchX, \.stretchY,
        \.bodyGain, \.mantle, \.mantleReach, \.halo, \.haloReach, \.flicker, \.flickerRate, \.strobe, \.pulse, \.shimmer, \.wisps, \.veil, \.wrap, \.emberSpeed,
        \.emberSize, \.sparkles, \.motes,
    ]

    /// Several looks weighed together (the weights need not add up to one).
    static func blend(_ parts: [(SaiyanAuraLook, Double)]) -> SaiyanAuraLook {
        let total = parts.reduce(0) { $0 + $1.1 }
        guard total > 1e-9, let first = parts.first?.0 else { return SaiyanAuraLook() }
        var out = first
        for key in blended { out[keyPath: key] = parts.reduce(0) { $0 + $1.0[keyPath: key] * $1.1 } / total }
        return out
    }

    /// The look of a form's aura: its style's character, sized by the form's `auraScale`.
    static func of(_ form: SaiyanForm) -> SaiyanAuraLook {
        var l = SaiyanAuraLook()
        switch form.auraStyle {
        case .none, .flame:
            break
        case .electric:
            // Super Saiyan 2: the same flame, taller and brighter, flickering hard.
            l.reach = 7; l.softness = 9; l.lick = 20; l.grain = 24; l.tongue = 175; l.tongueGain = 0.9; l.tongueGrain = 18; l.tongueCut = 0.8
            l.climb = 340; l.stretchY = 3.2; l.bodyGain = 1.6; l.mantle = 0.32; l.halo = 0.32; l.haloReach = 62; l.flicker = 0.08
            l.flickerRate = 15; l.strobe = 0.16; l.veil = 0.62; l.wrap = 0.55; l.emberSpeed = 1.3
        case .blaze:
            // Super Saiyan 3: wide and roaring, the flame climbing fast.
            l.reach = 9; l.softness = 11; l.lick = 26; l.grain = 34; l.tongue = 150; l.tongueGain = 0.82; l.tongueGrain = 30; l.tongueCut = 0.75
            l.climb = 430; l.stretchX = 1.3; l.stretchY = 2.8; l.bodyGain = 1.45; l.mantle = 0.5; l.mantleReach = 4.2; l.halo = 0.42
            l.haloReach = 48; l.flicker = 0.1; l.flickerRate = 13; l.strobe = 0.1; l.veil = 0.68; l.wrap = 0.6; l.emberSpeed = 1.5; l.emberSize = 1.15
        case .smooth:
            // God and Blue: calm, soft-edged, slow. A smooth aura with a little lightning in it (Blue) sparkles instead of crackling.
            l.reach = 6; l.softness = 14; l.lick = 9; l.grain = 40; l.tongue = 160; l.tongueGain = 0.66; l.tongueGrain = 38; l.tongueCut = 0.35
            l.climb = 150; l.stretchY = 3.6; l.bodyGain = 1.45; l.mantle = 0.36; l.halo = 0.32; l.haloReach = 60; l.flicker = 0.035
            l.flickerRate = 4; l.veil = 0.6; l.wrap = 0.42; l.emberSpeed = 0.7
            let sparkle = min(1, form.lightning * 6)
            l.shimmer = sparkle; l.sparkles = 0.55 * sparkle; l.lick += 4 * sparkle; l.softness -= 3 * sparkle; l.tongueCut += 0.2 * sparkle
        case .kaioken:
            // Blue Kaioken: Blue's body, bigger and hotter, with a red rim that beats.
            l.reach = 6; l.softness = 11; l.lick = 20; l.grain = 30; l.tongue = 150; l.tongueGain = 0.72; l.tongueGrain = 24; l.tongueCut = 0.68
            l.climb = 320; l.stretchY = 3; l.bodyGain = 1.35; l.mantle = 0.4; l.halo = 0.4; l.haloReach = 50; l.flicker = 0.06
            l.flickerRate = 12; l.pulse = 1; l.shimmer = 0.4; l.sparkles = 0.2; l.veil = 0.62; l.wrap = 0.7; l.emberSpeed = 1.2
        case .silver:
            // Ultra Instinct: thin and cool, fine strands drifting up, slow motes rather than embers.
            l.reach = 5; l.softness = 10; l.lick = 7; l.grain = 18; l.tongue = 150; l.tongueGain = 0.55; l.tongueGrain = 9; l.tongueCut = 0.92
            l.climb = 120; l.stretchY = 6.5; l.bodyGain = 1.4; l.mantle = 0.22; l.halo = 0.3; l.haloReach = 56; l.flicker = 0.03
            l.flickerRate = 2.5; l.wisps = 1; l.shimmer = 0.3 + 2 * form.lightning; l.veil = 0.45; l.wrap = 0.45; l.emberSpeed = 0.5
            l.emberSize = 0.8; l.motes = 0.85
        case .ego:
            // Ultra Ego: heavy, dense, slow, rolling from side to side rather than licking.
            l.reach = 8; l.softness = 13; l.lick = 64; l.grain = 90; l.tongue = 100; l.tongueGain = 0.55; l.tongueGrain = 60; l.tongueCut = 0.5
            l.climb = 95; l.roll = 90; l.stretchX = 2.4; l.stretchY = 1.1; l.bodyGain = 1.05; l.mantle = 0.5; l.mantleReach = 4; l.halo = 0.4
            l.haloReach = 42; l.flicker = 0.04; l.flickerRate = 3; l.veil = 0.7; l.wrap = 0.55; l.emberSpeed = 0.55; l.emberSize = 1.3
        }
        let s = max(0.5, form.auraScale)
        l.reach *= s
        l.tongue *= s
        l.haloReach *= s
        l.lick *= s.squareRoot()
        return l
    }
}

// MARK: - One frame's blend of forms

/// Which forms' auras show this frame and how much: the form settling in over `transition`, the old one fading or collapsing, and the next
/// one leaning in while a power-up charges. Worked out from `SaiyanBodyState` alone, so the aura, its embers and its lightning agree.
struct SaiyanAuraMix {
    var weights: [(SaiyanForm, Double)] = []
    /// 0 nothing showing ... 1 the whole aura (before presence).
    var amount = 0.0
    /// How big the aura is against its settled size: it swells while charging, draws in just before it bursts, bursts on a change and
    /// collapses on the way down.
    var swell = 1.0
    var look = SaiyanAuraLook()
    var core = SIMD3<Double>(1, 1, 1)
    var mid = SIMD3<Double>(1, 1, 1)
    var rim = SIMD3<Double>(1, 1, 1)
    var lightningColour = SIMD3<Double>(1, 1, 1)
    /// How much lightning, 0...1 and a little over while charging.
    var lightning = 0.0
    /// Embers a second.
    var embers = 0.0
    /// The change under way is a step up (shockwave, burst) rather than a collapse.
    var rising = false
    var collapsing = false

    static func of(_ s: SaiyanBodyState) -> SaiyanAuraMix {
        var m = SaiyanAuraMix()
        let t = WorldKit.smoothstep(0, 1, s.transition)
        let changing = s.form != s.previousForm && s.transition < 1
        m.rising = changing && s.form > s.previousForm
        m.collapsing = changing && s.form < s.previousForm
        var swell = 1.0
        if !changing {
            if !s.form.isBase { m.weights = [(s.form, 1)]; m.amount = 1 }
        } else if m.collapsing {
            // On the way down the old aura draws in and fades. (Down to base is the only way down, but an in-between form works too.)
            m.weights = s.form.isBase ? [(s.previousForm, 1)] : [(s.previousForm, 1 - t), (s.form, t)]
            m.amount = s.form.isBase ? 1 - t : 1
            swell *= 1 - 0.55 * t
        } else if s.previousForm.isBase {
            // Out of base: the charge already showed most of the aura, so it carries on from there.
            m.weights = [(s.form, 1)]
            m.amount = 0.9 + 0.1 * t
        } else {
            // A step up: the charge had already leaned 55% toward this form.
            let w = 0.55 + 0.45 * t
            m.weights = [(s.previousForm, 1 - w), (s.form, w)]
            m.amount = 1
        }
        if m.rising { swell *= 1 + 0.55 * burst(s.sinceChange) }

        // Charging: the next form leans in, the aura swells, then draws in just before it bursts.
        let c = min(1, max(0, s.charge))
        if c > 0.001, let next = s.form.next {
            if m.weights.isEmpty {
                m.weights = [(next, 1)]
                m.amount = max(m.amount, 0.9 * pow(c, 0.8))
                swell *= 0.45 + 0.55 * c
            } else {
                let lean = 0.55 * c * c
                m.weights = m.weights.map { ($0.0, $0.1 * (1 - lean)) } + [(next, lean)]
                swell *= 1 + 0.4 * c
            }
            swell *= 1 - 0.3 * WorldKit.smoothstep(0.86, 1, c)
        }
        m.swell = swell
        guard !m.weights.isEmpty else { return m }

        let total = max(1e-9, m.weights.reduce(0) { $0 + $1.1 })
        func colour(_ pick: (SaiyanPalette) -> SIMD3<Double>) -> SIMD3<Double> {
            m.weights.reduce(SIMD3<Double>(0, 0, 0)) { $0 + pick($1.0.palette) * ($1.1 / total) }
        }
        m.look = SaiyanAuraLook.blend(m.weights.map { (SaiyanAuraLook.of($0.0), $0.1) })
        m.core = colour(\.auraCore)
        m.mid = colour(\.auraMid)
        m.rim = colour(\.auraRim)
        m.lightningColour = colour(\.lightning)
        m.lightning = m.weights.reduce(0) { $0 + $1.0.lightning * $1.1 / total } + 0.3 * c
        m.embers = m.weights.reduce(0) { $0 + $1.0.embers * $1.1 / total } * (1 + 0.8 * c)
        return m
    }

    /// The burst of a change: up fast, a little past, and settling over about half a second.
    static func burst(_ since: Double) -> Double {
        guard since >= 0, since < 0.8 else { return 0 }
        return exp(-since * 5) * sin(min(1, since / 0.12) * .pi / 2)
    }
}

// MARK: - Colour ramps

/// The aura's colours from faint to hottest, for `CIColorMap`: the room-coloured nothing, the rim, the body, and the white-hot core
/// that hugs the outline. Each form's ramp comes from its palette; a frame's ramp is the blend of the forms showing, made on the CPU
/// (it is 128 pixels) and kept, so a blend that does not change is never rebuilt.
enum SaiyanAuraRamp {
    static let width = 128

    /// Positions and colours for one form, before the blend.
    static func stops(_ form: SaiyanForm) -> [(Double, SIMD3<Double>)] {
        let p = form.palette
        let core = p.auraCore, mid = p.auraMid, rim = p.auraRim
        func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> { a + (b - a) * t }
        let black = SIMD3<Double>(0, 0, 0)
        switch form.auraStyle {
        case .kaioken:
            // A red rim that stays red, then a sharp turn into the blue body: no muddy purple between them.
            return [(0, black), (0.05, rim * 0.2), (0.14, rim * 0.6), (0.26, rim * 0.85), (0.34, mix(rim, mid, 0.3) * 0.9), (0.42, mid * 0.92),
                    (0.66, mid), (0.82, mix(mid, core, 0.5)), (0.95, core), (1, core)]
        case .silver:
            // Cooler and thinner: more of the ramp is a faint glow, and the body is close to the core.
            return [(0, black), (0.05, rim * 0.12), (0.16, rim * 0.38), (0.3, mix(rim, mid, 0.6) * 0.78), (0.46, mid * 0.95),
                    (0.66, mix(mid, core, 0.55)), (0.86, core), (1, core)]
        case .ego:
            // A deep, dense rim before the violet body, which stays violet almost to the outline: a heavy aura, with little white in it.
            return [(0, black), (0.06, rim * 0.3), (0.18, rim * 0.75), (0.32, mix(rim, mid, 0.45)), (0.48, mid), (0.92, mid),
                    (1, mix(mid, core, 0.3))]
        default:
            return [(0, black), (0.05, rim * 0.14), (0.14, rim * 0.45), (0.26, mix(rim, mid, 0.4) * 0.85), (0.4, mid), (0.66, mid),
                    (0.8, mix(mid, core, 0.45)), (0.92, core), (1, core)]
        }
    }

    /// One form's ramp as samples, worked out once per form.
    private static let samples: [[SIMD3<Double>]] = SaiyanForm.allCases.map { form in
        let s = stops(form)
        return (0..<width).map { i in
            let x = Double(i) / Double(width - 1)
            guard let j = s.firstIndex(where: { $0.0 >= x }) else { return s.last?.1 ?? SIMD3(0, 0, 0) }
            guard j > 0 else { return s[0].1 }
            let (x0, c0) = s[j - 1], (x1, c1) = s[j]
            return c0 + (c1 - c0) * ((x - x0) / max(1e-9, x1 - x0))
        }
    }

    private static let lock = NSLock()
    private static var cache: [String: CIImage] = [:]

    /// The ramp for a blend of forms. Weights are rounded to 1/40, so a slow blend reuses a few dozen ramps.
    static func ramp(_ weights: [(SaiyanForm, Double)]) -> CIImage? {
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 1e-9 else { return nil }
        let steps = weights.map { ($0.0, (($0.1 / total) * 40).rounded()) }.filter { $0.1 > 0 }
        let key = steps.map { "\($0.0.rawValue):\(Int($0.1))" }.joined(separator: ",")
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let sum = max(1, steps.reduce(0) { $0 + $1.1 })
        var bytes = [UInt8](repeating: 255, count: width * 4)
        for i in 0..<width {
            let c = steps.reduce(SIMD3<Double>(0, 0, 0)) { $0 + samples[$1.0.rawValue][i] * ($1.1 / sum) }
            bytes[i * 4] = UInt8(min(255, max(0, c.z * 255)))
            bytes[i * 4 + 1] = UInt8(min(255, max(0, c.y * 255)))
            bytes[i * 4 + 2] = UInt8(min(255, max(0, c.x * 255)))
        }
        let image = bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)?.makeImage()
        }.map { CIImage(cgImage: $0) }
        guard let image else { return nil }
        lock.lock()
        if cache.count > 160 { cache.removeAll() }
        cache[key] = image
        lock.unlock()
        return image
    }
}

// MARK: - The outline

/// Where the person's outline is, read from the matte grid once a frame: their middle and size, an ordered rim over the top of them (left
/// shoulder, head, right shoulder) for lightning to crawl along, and the edges that face up (head, shoulders, raised fists) for embers.
struct SaiyanOutline {
    struct Rim {
        var point: CGPoint
        /// Out of the person, a unit vector.
        var normal: SIMD2<Double>
        /// The person carries on past the edge of the picture here: nothing to crawl along.
        var clipped: Bool
    }

    /// Rays cast over the top half of the person, from about the left to the right.
    static let rays = 44

    var centre = CGPoint(x: 640, y: 300)
    var top = 560.0
    var width = 500.0
    /// How big the person is: 1 for eyes 84 pixels apart.
    var unit = 1.0
    var rim: [Rim] = []
    var crown: [CGPoint] = []

    var isEmpty: Bool { rim.isEmpty }

    /// Reads the grid from the smoothed middle of the person. Cheap: the grid's cells are read straight from its buffer, a few thousand of
    /// them, with no interpolation.
    static func read(_ grid: MatteGrid, presence: WorldPresence, unit: Double, rect: CGRect) -> SaiyanOutline {
        var out = SaiyanOutline()
        out.centre = CGPoint(x: presence.centre.x, y: presence.centre.y)
        out.top = presence.top
        out.width = min(rect.width * 0.95, presence.width)
        out.unit = unit
        guard presence.level > 0.05 else { return out }
        let o = SIMD2(Double(out.centre.x), Double(out.centre.y))
        let cell = grid.cellSize
        let w = grid.width, h = grid.height
        let x0 = Double(rect.minX), x1 = Double(rect.maxX), y0 = Double(rect.minY), y1 = Double(rect.maxY)
        var points: [(SIMD2<Double>, Bool)] = []
        var crown: [CGPoint] = []
        grid.cells.withUnsafeBufferPointer { cells in
            // Rows count up from the bottom here; the grid stores the top row first.
            func solid(_ gx: Int, _ gy: Int) -> Bool { gx >= 0 && gx < w && gy >= 0 && gy < h && cells[(h - 1 - gy) * w + gx] > 127 }
            for i in 0..<rays {
                let a = Double.pi * (0.04 + 0.92 * Double(i) / Double(rays - 1))
                let d = SIMD2(cos(a), sin(a))
                var last = -1.0, r = 0.0
                while true {
                    let p = o + d * r
                    if p.x < x0 || p.x > x1 || p.y < y0 || p.y > y1 { break }
                    if solid(Int(p.x / cell), Int(p.y / cell)) { last = r }
                    r += cell
                }
                guard last >= 0 else { continue }
                let p = o + d * (last + cell * 0.5)
                let beyond = o + d * (last + cell * 1.5)
                points.append((p, beyond.x < x0 || beyond.x > x1 || beyond.y > y1))
            }
            // The edges that face up: a covered cell with an empty one two above it, every other column (plenty to pick embers from).
            for gy in stride(from: 1, to: h - 3, by: 2) {
                for gx in stride(from: 2, to: w - 2, by: 2) where solid(gx, gy) && !solid(gx, gy + 2) {
                    crown.append(CGPoint(x: (Double(gx) + 0.5) * cell, y: (Double(gy) + 1.5) * cell))
                }
            }
        }
        for (i, (p, clipped)) in points.enumerated() {
            let a = points[max(0, i - 1)].0, b = points[min(points.count - 1, i + 1)].0
            var n = SIMD2(b.y - a.y, -(b.x - a.x))
            if simd_length(n) < 1e-6 { n = p - o }
            n = simd_normalize(n)
            if simd_dot(n, p - o) < 0 { n = -n }
            out.rim.append(Rim(point: CGPoint(x: p.x, y: p.y), normal: n, clipped: clipped))
        }
        out.crown = crown
        return out
    }
}

// MARK: - The flame

/// The aura's flame as a grey strength field around the outline, worked out at quarter size on the graphics chip: 0 far from the person,
/// about 1 at the outline and more inside it. The colour comes later, from a ramp, at full size.
enum SaiyanAuraField {
    static let scale = 0.25

    /// Smooth noise in independent channels (red and green push a picture about with `CIDisplacementDistortion`, blue is for cutting
    /// tongues): blobs about `grain` pixels across, stretched, slid by `offset` so they can climb or roll. Values sit around 0.5. It is one
    /// tile of noise made once and repeated, so a frame's noise costs a move and a crop instead of a fresh random field and a blur.
    static func flow(_ box: CGRect, grain: Double, offset: CGPoint, stretch: SIMD2<Double>, seed: Double = 0) -> CIImage {
        let sx = max(0.05, grain / Double(tileCell) * stretch.x), sy = max(0.05, grain / Double(tileCell) * stretch.y)
        // The tile repeats, so the slide is taken round it: the numbers stay small however long the lens runs.
        let period = Double(tileSide)
        let tx = (seed * 37 + Double(offset.x) / sx).truncatingRemainder(dividingBy: period)
        let ty = (seed * 53 + Double(offset.y) / sy).truncatingRemainder(dividingBy: period)
        return tiled
            .transformed(by: CGAffineTransform(translationX: CGFloat(tx), y: CGFloat(ty)))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(sx), y: CGFloat(sy)))
            .cropped(to: box)
    }

    private static let tileSide = 256, tileCell = 8

    /// Smooth noise in three independent channels that repeats seamlessly: random values blurred (three box passes each way, wrapping
    /// round the edges, which is close to a gaussian) into blobs about eight pixels across. Each channel is evened out to sit at 0.5 with the
    /// spread the aura's numbers were tuned with. Not colour-managed: these are numbers, not colours.
    private static let tiled: CIImage = {
        let side = tileSide, n = side * side
        var rng = SplitMix64(seed: 0x5A1A_F1A3)
        var bytes = [UInt8](repeating: 255, count: n * 4)
        var a = [Double](repeating: 0, count: n), b = [Double](repeating: 0, count: n)
        let r = 3
        for c in 0..<3 {
            for i in 0..<n { a[i] = Double.random(in: 0...1, using: &rng) }
            for _ in 0..<3 {
                // Along rows, then down columns, each a running sum over 2r + 1 pixels, wrapping.
                for y in 0..<side {
                    var sum = 0.0
                    for k in -r...r { sum += a[y * side + (k + side) % side] }
                    for x in 0..<side {
                        b[y * side + x] = sum / Double(2 * r + 1)
                        sum += a[y * side + (x + r + 1) % side] - a[y * side + (x - r + side) % side]
                    }
                }
                for x in 0..<side {
                    var sum = 0.0
                    for k in -r...r { sum += b[((k + side) % side) * side + x] }
                    for y in 0..<side {
                        a[y * side + x] = sum / Double(2 * r + 1)
                        sum += b[((y + r + 1) % side) * side + x] - b[((y - r + side) % side) * side + x]
                    }
                }
            }
            var total = 0.0, squares = 0.0
            for v in a { total += v; squares += v * v }
            let mean = total / Double(n), spread = max(1e-6, (squares / Double(n) - mean * mean).squareRoot())
            let slot = 2 - c   // bytes run blue, green, red, alpha
            for i in 0..<n { bytes[i * 4 + slot] = UInt8(min(255, max(0, ((0.5 + (a[i] - mean) / spread * 0.07) * 255).rounded()))) }
        }
        let image = bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)?.makeImage()
        }
        guard let image else { return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)) }
        let tile = CIFilter.affineTile()
        tile.inputImage = CIImage(cgImage: image, options: [.colorSpace: NSNull()])
        tile.transform = .identity
        return tile.outputImage ?? CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
    }()

    /// The blue channel of the noise stretched to full contrast between `low` and `high`, as grey: tall gaps between tongues.
    static func cut(_ box: CGRect, grain: Double, offset: CGPoint, stretch: SIMD2<Double>, low: Double, high: Double, keep: Double) -> CIImage {
        let k = 1 / max(1e-3, high - low)
        // `keep` lifts the floor: 0 cuts the flame into separate licks, 1 leaves it whole.
        let gain = k * (1 - keep), bias = -low * k * (1 - keep) + keep
        let pick = CIVector(x: 0, y: 0, z: CGFloat(gain), w: 0)
        return flow(box, grain: grain, offset: offset, stretch: stretch, seed: 3.7)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": pick, "inputGVector": pick, "inputBVector": pick, "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: CGFloat(bias), y: CGFloat(bias), z: CGFloat(bias), w: 0),
            ])
            .applyingFilter("CIColorClamp")
            .cropped(to: box)
    }

    /// The flame's strength at quarter size, origin at zero.
    static func strength(matte: CIImage, rect: CGRect, look l: SaiyanAuraLook, unit: Double, swell: Double, time t: Double) -> CIImage {
        let k = scale * unit
        let box = CGRect(x: 0, y: 0, width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
        let small = WorldKit.shrink(matte, rect: rect, by: scale)
        let reach = l.reach * k * swell
        let grown = reach >= 0.5 ? small.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: reach]) : small
        let stretch = SIMD2(l.stretchX, l.stretchY)
        // The flow: climbing, and for a rolling aura swinging slowly from side to side as it climbs.
        let sway = l.roll * (sin(t * 0.55) * 1.6 + t * 0.35) * k
        let flow = flow(box, grain: max(2, l.grain * k), offset: CGPoint(x: sway, y: l.climb * t * k), stretch: stretch)
        let push = l.lick * k * (0.75 + 0.25 * swell)

        // The body: the outline grown and softened. It and the tongues are pushed about by the flow together, once, so the flame's edge
        // licks; the push is capped, as a big push belongs to the mantle (Ultra Ego's roll) and here it would smear the thin white-hot band.
        let body = grown.clampedToExtent().applyingGaussianBlur(sigma: max(0.6, l.softness * k * (0.8 + 0.2 * swell))).cropped(to: box)
        // The body's brightness wanders slowly along the outline, so its hot band swells and thins like living light instead of
        // reading as a drawn outline of even width.
        let wander = cut(box, grain: max(3, l.grain * 1.6 * k), offset: CGPoint(x: sway * 0.5, y: l.climb * 0.7 * t * k), stretch: SIMD2(1, 1.8),
                         low: 0.3, high: 0.7, keep: 0.62)
        var flame = WorldKit.multiply(WorldKit.tint(body, SIMD3(1, 1, 1), strength: l.bodyGain * 1.1), wander).cropped(to: box)
        if l.shimmer > 0.01 {
            // Blue's fine sparkle: a quick fine-grained flutter in the body's brightness.
            let flutter = cut(box, grain: max(2, 9 * k), offset: CGPoint(x: t * 14 * k, y: t * 90 * k), stretch: SIMD2(1, 1.6),
                              low: 0.35, high: 0.7, keep: 1 - 0.35 * min(1, l.shimmer))
            flame = WorldKit.multiply(flame, flutter).cropped(to: box)
        }

        // Tongues: the body smeared upward (a box blur along the vertical, slid up by its own length, so it tapers from the outline to its
        // tip) and cut into separate licks by tall noise climbing faster than the flow.
        let rise = l.tongue * k * swell
        if rise > 1, l.tongueGain > 0.01 {
            let tall = body.clampedToExtent()
                .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: rise / 2, kCIInputAngleKey: Double.pi / 2])
                .transformed(by: CGAffineTransform(translationX: 0, y: rise / 2))
                .cropped(to: box)
            let licks = cut(box, grain: max(2, l.tongueGrain * k), offset: CGPoint(x: sway * 0.6, y: l.climb * 1.5 * t * k),
                            stretch: SIMD2(1, l.stretchY * 1.5), low: 0.44, high: 0.62, keep: 1 - l.tongueCut)
            // Most of the body's own band is taken back out of the tongues, so they lengthen the flame without thickening its white root.
            let rootless = WorldKit.multiply(tall, SaiyanAuraKit.veil(body, 0.6).cropped(to: box))
            let tongues = WorldKit.multiply(rootless, licks).cropped(to: box)
            flame = WorldKit.adding(WorldKit.tint(tongues, SIMD3(1, 1, 1), strength: l.tongueGain), to: flame).cropped(to: box)
        }
        flame = flame.clampedToExtent()
            .applyingFilter("CIDisplacementDistortion", parameters: ["inputDisplacementImage": flow, kCIInputScaleKey: min(push * 1.3, 28 * k)])
            .cropped(to: box)
        var parts: [CIImage] = [flame]
        if rise > 1, l.wisps > 0.01 {
            // Ultra Instinct's fine strands: thinner licks again, drifting more slowly, reaching higher.
            let higher = body.clampedToExtent()
                .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: rise * 0.75, kCIInputAngleKey: Double.pi / 2])
                .transformed(by: CGAffineTransform(translationX: 0, y: rise * 0.75))
                .cropped(to: box)
            let strands = cut(box, grain: max(1.5, 5 * k), offset: CGPoint(x: t * 6 * k, y: l.climb * 0.8 * t * k), stretch: SIMD2(1, 9),
                              low: 0.5, high: 0.64, keep: 0)
            parts.append(WorldKit.tint(WorldKit.multiply(higher, strands).cropped(to: box), SIMD3(1, 1, 1), strength: 0.45 * l.wisps))
        }

        // The mantle: the whole figure grown wide, smeared up past the head and rolled about by slower, bigger noise, so the aura has a
        // flame-shaped body of its own instead of being only a glow along the outline.
        if l.mantle > 0.01 {
            let wide = small.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: max(1, reach * l.mantleReach + 3 * k)])
                .clampedToExtent().applyingGaussianBlur(sigma: max(1, (l.softness + 10) * k * 1.4))
            let lift = max(1, rise * 0.45)
            let slow = SaiyanAuraField.flow(box, grain: max(3, l.grain * 2.4 * k), offset: CGPoint(x: sway * 1.4, y: l.climb * 0.55 * t * k),
                                            stretch: stretch, seed: 7.3)
            let mantle = wide.applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: lift, kCIInputAngleKey: Double.pi / 2])
                .transformed(by: CGAffineTransform(translationX: 0, y: lift))
                .cropped(to: box).clampedToExtent()
                .applyingFilter("CIDisplacementDistortion", parameters: ["inputDisplacementImage": slow, kCIInputScaleKey: push * 2.4])
                .cropped(to: box)
            // A shell outside the body's own band, so it widens the flame without widening the white-hot core along the outline.
            let shell = WorldKit.multiply(mantle, WorldKit.inverted(body)).cropped(to: box)
            parts.append(WorldKit.tint(shell, SIMD3(1, 1, 1), strength: l.mantle))
        }

        // The wide soft glow, the light the aura throws on the room.
        if l.halo > 0.01 {
            let halo = grown.clampedToExtent().applyingGaussianBlur(sigma: max(1, l.haloReach * k * (0.7 + 0.3 * swell))).cropped(to: box)
            parts.append(WorldKit.tint(halo, SIMD3(1, 1, 1), strength: l.halo))
        }
        var total = parts[0]
        for part in parts.dropFirst() { total = WorldKit.adding(part, to: total) }
        return total.cropped(to: box)
    }

    /// The quarter-size field back at full size over `rect`, smoothly (bicubic), so the colour bands made from it have clean curved edges.
    static func enlarge(_ field: CIImage, rect: CGRect) -> CIImage {
        field.clampedToExtent()
            .applyingFilter("CIBicubicScaleTransform", parameters: [kCIInputScaleKey: 1 / scale, kCIInputAspectRatioKey: 1, "inputB": 1.0 / 3, "inputC": 1.0 / 3])
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            .cropped(to: rect)
    }
}

// MARK: - Small things

enum SaiyanAuraKit {
    /// A heartbeat: two quick beats and a rest, 0...1, about 1.4 beats a second. Blue Kaioken's red rim swells on it.
    static func heartbeat(_ t: Double) -> Double {
        let phase = (t * 0.72).truncatingRemainder(dividingBy: 1)
        func beat(_ at: Double, _ width: Double) -> Double { exp(-pow((phase - at) / width, 2)) }
        return min(1, beat(0.1, 0.06) + 0.7 * beat(0.32, 0.07))
    }

    static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> { a + (b - a) * min(1, max(0, t)) }

    /// A grey picture times a number, opaque, for adding.
    static func scaled(_ grey: CIImage, _ k: Double) -> CIImage { WorldKit.tint(grey, SIMD3(1, 1, 1), strength: k) }

    /// Coloured light times a number, opaque, for adding.
    static func gained(_ light: CIImage, _ k: Double) -> CIImage { WorldKit.brightened(light, k) }

    /// One minus `k` times a grey picture: where the room is dimmed under the glow. With `reach` over 1 the grey is first stretched and
    /// clamped, so the room under the flame's body is dimmed fully while its faint outer glow barely dims it at all.
    static func veil(_ grey: CIImage, _ k: Double, reach: Double = 1) -> CIImage {
        let field = reach == 1 ? grey : scaled(grey, reach).applyingFilter("CIColorClamp")
        return field.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(-k), y: 0, z: 0, w: 0), "inputGVector": CIVector(x: CGFloat(-k), y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: CGFloat(-k), y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 1),
        ]).applyingFilter("CIColorClamp")
    }

    /// A few rocks, lit from above and a little from behind, drawn once and kept: debris lifted off the floor by a power-up.
    static let rocks: [CIImage] = (0..<4).compactMap { variant in
        let side = 64
        guard let ctx = HandFXKit.bitmap(width: side, height: side) else { return nil }
        var rng = SplitMix64(seed: UInt64(0xB0C4 + variant * 977))
        let corners = 7 + variant % 3
        var points: [CGPoint] = []
        for i in 0..<corners {
            let a = Double(i) / Double(corners) * 2 * .pi + Double.random(in: -0.25...0.25, using: &rng)
            let r = 22 * Double.random(in: 0.62...1.0, using: &rng)
            points.append(CGPoint(x: 32 + cos(a) * r, y: 32 + sin(a) * r * 0.82))
        }
        // A rounded outline through the corners, so no hard polygon shows at any size.
        let path = CGMutablePath()
        let n = points.count
        path.move(to: CGPoint(x: (points[n - 1].x + points[0].x) / 2, y: (points[n - 1].y + points[0].y) / 2))
        for i in 0..<n {
            let p = points[i], q = points[(i + 1) % n]
            path.addQuadCurve(to: CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2), control: p)
        }
        path.closeSubpath()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let body = [CGColor(colorSpace: space, components: [0.7, 0.62, 0.55, 1])!, CGColor(colorSpace: space, components: [0.36, 0.3, 0.27, 1])!,
                    CGColor(colorSpace: space, components: [0.13, 0.11, 0.11, 1])!] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: body, locations: [0, 0.45, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 22, y: 56), end: CGPoint(x: 40, y: 8), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        // A facet: a lighter plane across the top.
        ctx.setFillColor(CGColor(colorSpace: space, components: [0.75, 0.68, 0.6, 0.22])!)
        ctx.fill(CGRect(x: 0, y: 40 + Double(variant) * 2, width: 64, height: 30))
        ctx.restoreGState()
        // A thin warm rim on the lit top edge.
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [1, 0.92, 0.75, 0.6])!)
        ctx.setLineWidth(2.5)
        ctx.strokePath()
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }
}
