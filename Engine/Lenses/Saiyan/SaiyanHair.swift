import CoreGraphics
import CoreImage
import Foundation
import simd

// The hair of every form of the Dragon Ball lens. It is drawn over the person's own hair, so it starts with a mass over the skull and
// temples that hides theirs, edged with a hairline of small points; spikes stand out of the crown, more rise from the hairline and sweep
// back, and a fringe of bangs hangs over the forehead. Super Saiyan 3's hair also falls to the waist behind the shoulders.
//
// Every lock is a blade painted once per colour (`SaiyanLock.paint`) and kept. Each frame the locks are copied, at whole pixels, into an
// upright picture of the hair in the head's own units (cheap), moved by their springs, and that one picture is laid over the face with the
// head's tilt and size. Turning each lock separately onto the picture would cost several times as much.

// MARK: - Designs

/// The mass over the skull: it hides the person's own hair, and its lower edge is a hairline of small points over the forehead.
struct SaiyanCap {
    /// The top, from the bottom of the left sideburn over the head to the bottom of the right one.
    let outer: [CGPoint]
    /// The lower edge, from the right sideburn along the forehead to the left one.
    let hairline: [CGPoint]
    /// Lines combed up from the hairline toward the crown.
    let partings: [[CGPoint]]

    /// How high the hairline is above the eyes in the middle, on the test head.
    static let hairlineY = 0.74

    static func baseY(_ x: Double) -> Double { hairlineY - 0.28 * x * x }

    init(scale s: Double) {
        func scaled(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: Self.hairlineY + (y - Self.hairlineY) * s) }
        let top: [(Double, Double)] = [(-1.2, -0.44), (-1.36, 0.06), (-1.39, 0.6), (-1.25, 1.12), (-0.93, 1.52), (-0.47, 1.77), (0, 1.85),
                                      (0.47, 1.77), (0.93, 1.52), (1.25, 1.12), (1.39, 0.6), (1.36, 0.06), (1.2, -0.44)]
        outer = top.map { scaled($0.0, $0.1) }
        var edge: [CGPoint] = [scaled(1.02, -0.36), scaled(0.9, 0.02), scaled(0.87, 0.42)]
        for j in 0...12 {
            let x = 0.84 - Double(j) * 1.68 / 12
            edge.append(scaled(x, Self.baseY(x) - (j % 2 == 1 ? 0.07 : 0)))
        }
        edge += [scaled(-0.87, 0.42), scaled(-0.9, 0.02), scaled(-1.02, -0.36)]
        hairline = edge
        partings = stride(from: -1.12, through: 1.13, by: 0.28).map { x in
            [scaled(x * 0.86, Self.baseY(x * 0.86) + 0.05), scaled(x * 1.02, 1.16), scaled(x * 0.62, 1.74)]
        }
    }

    /// The outline, its points moved by `place` (onto a head of some shape).
    func path(_ place: (CGPoint) -> CGPoint) -> CGPath {
        let top = outer.map(place), edge = hairline.map(place)
        let path = CGMutablePath()
        path.move(to: top[0])
        SaiyanFaceKit.addCurve(through: top, to: path)
        path.addLine(to: edge[0])
        SaiyanFaceKit.addCurve(through: Array(edge[0...2]), to: path)
        for p in edge[3..<(edge.count - 3)] { path.addLine(to: p) }
        SaiyanFaceKit.addCurve(through: Array(edge[(edge.count - 3)...]), to: path)
        path.closeSubpath()
        return path
    }

    /// Paints the mass, its points moved by `place`: lit from the upper left, combed lines, a shadow along the hairline where it turns
    /// under, and the aura's light along its top.
    func paint(_ pen: HeadwearPen, _ ink: SaiyanInk, _ place: (CGPoint) -> CGPoint) {
        let shape = path(place)
        // Mostly in its own shadow, a little lit toward the upper left.
        let mass = SaiyanInk.massColour(ink)
        let colours = [mass.mixed(with: ink.base, 0.5), mass, mass.mixed(with: ink.shade, 0.6)]
        pen.paintRound(shape, center: place(hwp(-0.45, 1.5)), radius: 2.5, colours)
        pen.clipped(to: shape) {
            for line in partings {
                let p = line.map(place)
                pen.stroke(SaiyanFaceKit.openCurve(p), ink.shade.darker(0.15).faded(0.5), width: 0.055)
                pen.stroke(SaiyanFaceKit.openCurve(p.map { hwp($0.x + 0.06, $0.y) }), ink.light.faded(0.26), width: 0.026)
            }
            pen.stroke(HeadwearShape.polygon(hairline.map(place)), ink.shade.darker(0.3).faded(0.4), width: 0.14, join: .miter)
            pen.stroke(SaiyanFaceKit.openCurve(outer.map(place)), ink.rim.faded(0.5), width: 0.1)
        }
        pen.stroke(shape, ink.line.faded(0.9), width: 0.024)
    }
}

/// One form's hair: its locks in the order they are drawn, its mass, and the loose strands that float off it.
struct SaiyanHairDesign {
    let style: SaiyanForm.HairStyle
    let name: String
    /// Back tier first, then the rest; the mass goes between them.
    let locks: [SaiyanLock]
    let cap: SaiyanCap
    let capScale: Double
    /// How many loose strands float off it (Ultra Instinct).
    let strands: Int
    /// The first lock drawn over the mass.
    let firstOverCap: Int
    /// Super Saiyan 3's hair falling behind the shoulders.
    let hasLongHair: Bool

    init(style: SaiyanForm.HairStyle, name: String, locks: [SaiyanLock], capScale: Double, strands: Int = 0, longHair: Bool = false) {
        self.style = style
        self.name = name
        let ordered = locks.enumerated().map { i, lock -> SaiyanLock in
            var l = lock
            l.seed += i * 7 + 3
            l.omega = (l.hangs ? 12.5 : 10.5) / sqrt(max(0.3, l.length))
            l.sway = l.hangs ? 1.5 : 1
            // Out from the middle, the back a beat late, the fringe last: the hair bursts up rather than appearing all at once.
            l.delay = min(0.3, 0.03 + 0.1 * abs(l.root.x) + (l.tier == .back ? 0.06 : 0) + (l.tier == .fringe ? 0.1 : 0))
            return l.finished()
        }.sorted { $0.tier.rawValue < $1.tier.rawValue }
        self.locks = ordered
        firstOverCap = ordered.firstIndex { $0.tier != .back } ?? ordered.count
        self.capScale = capScale
        cap = SaiyanCap(scale: capScale)
        self.strands = strands
        hasLongHair = longHair
    }

    static func of(_ style: SaiyanForm.HairStyle) -> SaiyanHairDesign? {
        switch style {
        case .natural: return nil
        case .spiky: return spiky
        case .jagged: return jagged
        case .long: return long
        case .swept: return swept
        case .silver: return silver
        }
    }

    private static func l(_ tier: SaiyanLock.Tier, _ x: Double, _ y: Double, _ deg: Double, bend: Double = 0, len: Double, w: Double,
                          sharp: Double = 1, belly: Double = 0.25, wave: Double = 0, hangs: Bool = false, depth: Double? = nil) -> SaiyanLock {
        var lock = SaiyanLock(tier: tier, root: hwp(x, y), heading: deg * .pi / 180, bend: bend * .pi / 180, length: len, width: w)
        lock.wave = wave * .pi / 180
        lock.sharp = sharp
        lock.belly = belly
        lock.hangs = hangs
        lock.depth = depth ?? (tier == .back ? 0.85 : tier == .crown ? 0.18 : 0)
        return lock
    }

    /// Super Saiyan's spikes: a few broad ones swept up out of the crown, the low side ones curling up, three rising off the forehead.
    private static let spikyCrown: [SaiyanLock] = [
        l(.back, -0.62, 1.25, 122, bend: -16, len: 1.6, w: 0.46, belly: 0.3), l(.back, 0.0, 1.45, 96, bend: -6, len: 1.8, w: 0.5, belly: 0.3),
        l(.back, 0.6, 1.3, 66, bend: 14, len: 1.6, w: 0.46, belly: 0.3), l(.back, -1.0, 0.95, 148, bend: -28, len: 1.15, w: 0.38, belly: 0.3),
        l(.back, 1.0, 0.95, 34, bend: 26, len: 1.1, w: 0.38, belly: 0.3),
        l(.crown, -1.08, 0.55, 168, bend: -42, len: 1.15, w: 0.36, belly: 0.32), l(.crown, -0.92, 1.0, 143, bend: -30, len: 1.5, w: 0.42, belly: 0.32),
        l(.crown, -0.52, 1.36, 118, bend: -18, len: 1.8, w: 0.46, belly: 0.32), l(.crown, 0.02, 1.52, 92, bend: 2, len: 1.95, w: 0.46, belly: 0.32),
        l(.crown, 0.55, 1.36, 64, bend: 18, len: 1.75, w: 0.46, belly: 0.32), l(.crown, 0.94, 0.98, 38, bend: 30, len: 1.45, w: 0.42, belly: 0.32),
        l(.crown, 1.1, 0.52, 13, bend: 40, len: 1.1, w: 0.36, belly: 0.32),
        l(.front, -0.52, 0.92, 108, bend: -18, len: 1.85, w: 0.46, belly: 0.3, wave: 6), l(.front, 0.04, 0.98, 93, bend: -6, len: 2.0, w: 0.48, belly: 0.3, wave: -4),
        l(.front, 0.58, 0.94, 73, bend: 16, len: 1.8, w: 0.46, belly: 0.3, wave: -6),
        l(.front, -1.14, 0.24, 238, bend: -12, len: 0.36, w: 0.2, hangs: true), l(.front, 1.14, 0.24, 302, bend: 12, len: 0.35, w: 0.2, hangs: true),
    ]

    static let spiky = SaiyanHairDesign(style: .spiky, name: "spiky", locks: spikyCrown + [
        // The one lock that hangs between the brows, and a few short bangs along the hairline.
        l(.fringe, 0.0, 0.9, 268, bend: -34, len: 0.78, w: 0.15, sharp: 1.15, wave: 10, hangs: true),
        l(.fringe, -0.4, 0.86, 250, bend: 24, len: 0.5, w: 0.15, sharp: 1.2, hangs: true), l(.fringe, -0.76, 0.76, 238, bend: 20, len: 0.44, w: 0.14, sharp: 1.2, hangs: true),
        l(.fringe, 0.42, 0.86, 290, bend: -24, len: 0.48, w: 0.15, sharp: 1.2, hangs: true), l(.fringe, 0.78, 0.74, 302, bend: -20, len: 0.42, w: 0.14, sharp: 1.2, hangs: true),
    ], capScale: 1)

    /// Super Saiyan 2: more spikes, straighter and sharper, standing up and back, and a single lock over the forehead.
    static let jagged: SaiyanHairDesign = {
        var locks: [SaiyanLock] = []
        func root(_ deg: Double, _ r: Double) -> (Double, Double) { (r * 1.05 * cos(deg * .pi / 180), 0.5 + r * 0.98 * sin(deg * .pi / 180)) }
        for deg in [140.0, 116, 94, 72, 48] {
            let (x, y) = root(deg, 0.9)
            let s = sin(deg * .pi / 180)
            locks.append(l(.back, x, y, deg, bend: (90 - deg) * 0.1, len: 1.3 + 0.7 * pow(s, 1.5), w: 0.4, sharp: 1.15, belly: 0.14))
        }
        for deg in [168.0, 150, 132, 113, 95, 77, 58, 40, 20] {
            let (x, y) = root(deg, 1)
            let s = sin(deg * .pi / 180)
            locks.append(l(.crown, x, y, deg, bend: (90 - deg) * 0.12, len: 1.0 + 1.1 * pow(s, 1.5), w: 0.37, sharp: 1.2, belly: 0.14))
        }
        locks += [
            l(.front, -0.48, 0.82, 103, bend: -6, len: 2.0, w: 0.44, sharp: 1.15, belly: 0.16),
            l(.front, 0.02, 0.9, 90, bend: -2, len: 2.15, w: 0.46, sharp: 1.15, belly: 0.16),
            l(.front, 0.52, 0.84, 78, bend: 6, len: 1.95, w: 0.44, sharp: 1.15, belly: 0.16),
            l(.front, -1.14, 0.22, 250, bend: -10, len: 0.5, w: 0.19, sharp: 1.25, hangs: true),
            l(.front, -1.2, 0.0, 234, bend: -6, len: 0.38, w: 0.15, sharp: 1.3, hangs: true),
            l(.front, 1.14, 0.22, 291, bend: 10, len: 0.48, w: 0.19, sharp: 1.25, hangs: true),
            l(.front, 1.2, 0.0, 306, bend: 6, len: 0.36, w: 0.15, sharp: 1.3, hangs: true),
            l(.fringe, 0.14, 0.86, 266, bend: -18, len: 0.72, w: 0.15, sharp: 1.2, wave: 7, hangs: true),
            l(.fringe, -0.5, 0.76, 241, bend: 10, len: 0.32, w: 0.18, sharp: 1.25, hangs: true),
            l(.fringe, 0.62, 0.74, 301, bend: -10, len: 0.3, w: 0.17, sharp: 1.25, hangs: true),
        ]
        return SaiyanHairDesign(style: .jagged, name: "jagged", locks: locks, capScale: 1)
    }()

    /// Super Saiyan 3: a towering mane that flares as it rises, long sideburns, three long bangs; the rest falls behind (`SaiyanLongHair`).
    static let long: SaiyanHairDesign = {
        var locks: [SaiyanLock] = []
        func root(_ deg: Double, _ r: Double) -> (Double, Double) { (r * 1.1 * cos(deg * .pi / 180), 0.55 + r * 1.02 * sin(deg * .pi / 180)) }
        for deg in [150.0, 120, 92, 64, 34] {
            let (x, y) = root(deg, 0.88)
            let s = sin(deg * .pi / 180)
            locks.append(l(.back, x, y, deg, bend: (90 - deg) * 0.22, len: 1.8 + 1.0 * pow(s, 1.2), w: 0.54, belly: 0.32, wave: 5))
        }
        for (i, deg) in [170.0, 152, 134, 116, 99, 82, 65, 47, 29, 11].enumerated() {
            let (x, y) = root(deg, 1)
            let s = sin(deg * .pi / 180)
            locks.append(l(.crown, x, y, deg, bend: (90 - deg) * 0.3, len: 1.35 + 1.45 * pow(s, 1.2), w: 0.46, belly: 0.32,
                           wave: i % 2 == 0 ? 6 : -5))
        }
        locks += [
            l(.front, -0.66, 0.8, 112, bend: -14, len: 2.3, w: 0.5, belly: 0.32, wave: 5),
            l(.front, -0.1, 0.9, 95, bend: -5, len: 2.55, w: 0.54, belly: 0.32, wave: -4),
            l(.front, 0.5, 0.84, 76, bend: 12, len: 2.35, w: 0.5, belly: 0.32, wave: 4),
            l(.front, -1.16, 0.24, 258, bend: -8, len: 0.84, w: 0.22, sharp: 1.05, wave: 6, hangs: true),
            l(.front, 1.16, 0.24, 283, bend: 8, len: 0.82, w: 0.22, sharp: 1.05, wave: -6, hangs: true),
            l(.fringe, -0.32, 0.84, 256, bend: 14, len: 0.6, w: 0.17, sharp: 1.1, wave: 6, hangs: true),
            l(.fringe, 0.1, 0.87, 268, bend: -8, len: 0.7, w: 0.16, sharp: 1.1, wave: 9, hangs: true),
            l(.fringe, 0.5, 0.81, 287, bend: -14, len: 0.54, w: 0.17, sharp: 1.1, wave: -6, hangs: true),
        ]
        return SaiyanHairDesign(style: .long, name: "long", locks: locks, capScale: 1.06, longHair: true)
    }()

    /// The Super Saiyan spikes reshaped: longer, gathered up toward the vertical, finer at the tips.
    private static func reshaped(_ locks: [SaiyanLock], length: Double, gather: Double, sharp: Double, belly: Double, wave: Double,
                                 dropBack: Set<Int> = []) -> [SaiyanLock] {
        locks.enumerated().compactMap { i, lock in
            if lock.tier == .back && dropBack.contains(i) { return nil }
            var out = lock
            guard !lock.hangs else { return out }
            out.heading = .pi / 2 + (lock.heading - .pi / 2) * gather
            out.bend = lock.bend * gather
            out.length = lock.length * length
            out.sharp = sharp
            out.belly = belly
            out.wave = lock.wave + (i % 2 == 0 ? wave : -wave) * .pi / 180
            return out
        }
    }

    /// God, Blue, Ultra Ego: the Super Saiyan silhouette, taller and cleaner, with sharper tips and three bangs.
    static let swept = SaiyanHairDesign(style: .swept, name: "swept", locks: reshaped(spikyCrown, length: 1.13, gather: 0.86, sharp: 1.3,
                                                                                         belly: 0.18, wave: 0, dropBack: [3, 4]) + [
        l(.fringe, 0.04, 0.86, 266, bend: -20, len: 0.62, w: 0.14, sharp: 1.25, wave: 6, hangs: true),
        l(.fringe, -0.42, 0.79, 250, bend: 12, len: 0.38, w: 0.18, sharp: 1.25, hangs: true),
        l(.fringe, 0.48, 0.79, 292, bend: -12, len: 0.37, w: 0.18, sharp: 1.25, hangs: true),
    ], capScale: 1)

    /// Ultra Instinct: a little lower and softer, every spike with a flowing S, two locks over the forehead, and strands that float free.
    static let silver = SaiyanHairDesign(style: .silver, name: "silver", locks: reshaped(spikyCrown, length: 0.94, gather: 0.92, sharp: 1.1,
                                                                                           belly: 0.3, wave: 6) + [
        l(.fringe, -0.05, 0.87, 258, bend: 20, len: 0.58, w: 0.15, sharp: 1.1, wave: 8, hangs: true),
        l(.fringe, 0.32, 0.83, 280, bend: -10, len: 0.44, w: 0.16, sharp: 1.1, wave: -6, hangs: true),
        l(.fringe, -0.62, 0.7, 238, bend: 10, len: 0.32, w: 0.17, hangs: true), l(.fringe, 0.76, 0.64, 304, bend: -10, len: 0.3, w: 0.16, hangs: true),
    ], capScale: 0.98, strands: 6)
}

// MARK: - The long hair behind

/// Super Saiyan 3's hair falling from the back of the head to the waist, behind the shoulders. It hangs, so it does not turn with the head;
/// each side is painted once at exactly the size it is shown and copied at whole pixels, which costs next to nothing for its size.
struct SaiyanLongHair {
    /// Where the hair hangs from, on the test head.
    static let pivot = CGPoint(x: 0, y: 1.0)

    /// The right side's locks, from the pivot; the left is their mirror.
    static let locks: [SaiyanLock] = {
        func l(_ x: Double, _ y: Double, _ deg: Double, bend: Double, wave: Double, len: Double, w: Double) -> SaiyanLock {
            var lock = SaiyanLock(tier: .back, root: hwp(x, y - pivot.y), heading: deg * .pi / 180, bend: bend * .pi / 180, length: len, width: w)
            lock.wave = wave * .pi / 180
            lock.sharp = 0.55
            lock.belly = 0.18
            lock.depth = 0.4
            return lock
        }
        let right = [
            l(0.32, 1.62, 303, bend: -30, wave: 5, len: 5.4, w: 0.42), l(0.72, 1.45, 311, bend: -38, wave: -5, len: 5.8, w: 0.48),
            l(1.04, 1.12, 320, bend: -46, wave: 6, len: 5.2, w: 0.47), l(1.22, 0.66, 326, bend: -50, wave: -6, len: 4.7, w: 0.43),
            l(1.26, 0.18, 306, bend: -32, wave: 5, len: 4.2, w: 0.37),
        ]
        return right.enumerated().map { i, lock in var l = lock; l.seed = 211 + i * 5; return l.finished() }
    }()

    static var window: CGRect {
        locks.reduce(CGRect.null) { $0.union($1.window.offsetBy(dx: $1.root.x, dy: $1.root.y)) }.insetBy(dx: -0.05, dy: -0.05)
    }

    /// One side (+1 right, -1 left), painted with its root at the pivot.
    static func paint(_ pen: HeadwearPen, _ ink: SaiyanInk, side: Double) {
        pen.ctx.saveGState()
        pen.ctx.scaleBy(x: CGFloat(side), y: 1)
        // Back to front: the outermost locks are farthest round the back.
        for lock in locks.reversed() {
            pen.placed(at: lock.root) { lock.paint(pen, ink) }
        }
        pen.ctx.restoreGState()
    }
}

// MARK: - Putting it together

/// Something painted once and kept that goes into the hair's picture with the hair: a brow, the skin over the real brows, the shadow
/// under the hairline. Putting them in the same picture costs nothing extra when it is laid over the face.
struct SaiyanPiece {
    enum Layer {
        /// Under the hair and coloured with it: the brows.
        case underHair
        /// Slid in under everything already there, and never coloured: skin.
        case skin
    }
    let name: String
    /// Where it goes, in face units, and the box its painting fills around that point.
    let at: CGPoint
    let window: CGRect
    var alpha: Double
    let layer: Layer
    /// Paints around the origin, in face units.
    let paint: (HeadwearPen) -> Void
}

/// A colour washed over the hair, keeping its shape and shading in proportion: `amount` 0 leaves it, 1 makes it the flat colour.
/// Mixed in sRGB everywhere (painted here, or laid by the graphics chip), so the front hair and the long hair behind always agree.
struct SaiyanTint {
    var colour: SIMD3<Double>
    var amount: Double

    /// The same wash on the graphics chip. Core Image works in linear light, so the picture is taken to sRGB for the mix and back.
    func wash(_ image: CIImage) -> CIImage {
        let keep = CGFloat(1 - amount), a = CGFloat(amount)
        return image.applyingFilter("CILinearToSRGBToneCurve").applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: keep, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: keep, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: keep, w: 0),
            "inputBiasVector": CIVector(x: CGFloat(colour.x) * a, y: CGFloat(colour.y) * a, z: CGFloat(colour.z) * a, w: 0),
        ]).applyingFilter("CISRGBToneCurveToLinear")
    }
}

/// One frame's pictures of the hair and of the skin that goes under it, upright in the head's own units, and how to lay them: scaled by
/// `scale` into face units, faded by `alpha`, the hair washed by `tint` (left for whoever lays them).
struct SaiyanHairPicture {
    let hair: CGImage
    let box: CGRect
    let skin: CGImage?
    let skinBox: CGRect
    let scale: Double
    let alpha: Double
    let tint: SaiyanTint?
}

/// The upright picture of the hair, in the head's own units, built each frame from the kept paintings.
final class SaiyanHairCanvas {
    private var context: CGContext?
    private var width = 0, height = 0
    private(set) var density = 0.0
    /// The point, in units, at the lower left corner of the picture.
    private(set) var origin = CGPoint.zero
    /// What has been drawn on this frame, in pixels.
    private var used = CGRect.null

    /// Starts a frame covering `box` (units) at `density` pixels to a unit, reusing the picture when it is big enough.
    func begin(covering box: CGRect, density: Double) -> Bool {
        let w = Int(ceil(box.width * density)) + 2, h = Int(ceil(box.height * density)) + 2
        guard w > 0, h > 0, w * h < 6_000_000 else { return false }
        if context == nil || w > width || h > height || density != self.density {
            let grow = density == self.density ? 1.15 : 1.08
            width = max(w, Int(Double(w) * grow)); height = max(h, Int(Double(h) * grow))
            context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: Sprites.bitmapInfo)
            context?.interpolationQuality = .low
        }
        guard let context else { return false }
        self.density = density
        origin = box.origin
        context.setBlendMode(.normal)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        used = .null
        return true
    }

    private func pixel(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) * density, y: (p.y - origin.y) * density) }

    /// A painting copied as it is, at whole pixels: `window` is the box it fills, in units.
    func copy(_ image: CGImage, window: CGRect, alpha: Double = 1, blend: CGBlendMode = .normal) {
        guard let context, alpha > 0.004 else { return }
        let p = pixel(window.origin)
        let rect = CGRect(x: p.x.rounded(), y: p.y.rounded(), width: CGFloat(image.width), height: CGFloat(image.height))
        context.setAlpha(CGFloat(min(1, alpha)))
        if blend != .normal { context.setBlendMode(blend) }
        context.draw(image, in: rect)
        if blend != .normal { context.setBlendMode(.normal) }
        if blend != .destinationOver || !used.isNull { used = used.union(rect) }
    }

    /// A painting turned by `turn` and grown by `scale` about `pivot` (units): the slow way, kept for the moments things grow.
    func draw(_ image: CGImage, window: CGRect, pivot: CGPoint, offset: CGVector = .zero, turn: Double, scale: Double, alpha: Double = 1,
              blend: CGBlendMode = .normal) {
        guard let context, alpha > 0.004, scale > 0.001 else { return }
        let p = pixel(CGPoint(x: pivot.x + offset.dx, y: pivot.y + offset.dy))
        let local = CGRect(x: (window.minX - pivot.x) * density, y: (window.minY - pivot.y) * density,
                           width: CGFloat(image.width), height: CGFloat(image.height))
        let move = CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)).concatenating(CGAffineTransform(rotationAngle: CGFloat(turn)))
            .concatenating(CGAffineTransform(translationX: p.x, y: p.y))
        context.saveGState()
        context.concatenate(move)
        context.setAlpha(CGFloat(min(1, alpha)))
        context.setBlendMode(blend)
        context.draw(image, in: local)
        context.restoreGState()
        used = used.union(local.applying(move))
    }

    /// Washes everything drawn so far toward a colour, keeping its shape (an old form's colour fading, the next form's showing through).
    func tint(_ colour: SIMD3<Double>, alpha: Double) {
        guard let context, alpha > 0.004, !used.isNull else { return }
        context.saveGState()
        context.setBlendMode(.sourceAtop)
        context.setFillColor(SaiyanFaceKit.colour(colour, min(1, alpha)).cg)
        context.fill(used.integral)
        context.restoreGState()
    }

    /// Draws in units, for the few things painted fresh each frame (loose strands, a glint); `area` (units) is what they cover.
    func inUnits(area: CGRect, _ draw: (HeadwearPen) -> Void) {
        guard let context, !area.isNull else { return }
        context.saveGState()
        context.scaleBy(x: CGFloat(density), y: CGFloat(density))
        context.translateBy(x: -origin.x, y: -origin.y)
        draw(HeadwearPen(ctx: context))
        context.restoreGState()
        let a = pixel(area.origin)
        used = used.union(CGRect(x: a.x, y: a.y, width: area.width * density, height: area.height * density))
    }

    /// What was drawn this frame and the box it covers, in units.
    func finish() -> (image: CGImage, box: CGRect)? {
        guard let context, !used.isNull else { return nil }
        let crop = used.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !crop.isEmpty, let whole = context.makeImage(),
              let part = whole.cropping(to: CGRect(x: crop.minX, y: CGFloat(height) - crop.maxY, width: crop.width, height: crop.height))
        else { return nil }
        let box = CGRect(x: origin.x + crop.minX / density, y: origin.y + crop.minY / density, width: crop.width / density, height: crop.height / density)
        return (part, box)
    }
}

/// The hair of the Dragon Ball lens: which design and colours show for the body's state, the springs of every lock, and the drawing.
final class SaiyanHair {
    /// How long a change of form takes, the time scale of the springing up (`SaiyanBodyState.transition` runs over about this).
    static let changeSeconds = 0.7

    private var swings: [String: [HeadwearSwing]] = [:]
    private var longSway = [HeadwearSwing(omega: 3.4, damping: 0.13, gain: 0.02, limit: 0.5), HeadwearSwing(omega: 3.8, damping: 0.13, gain: 0.02, limit: 0.5)]
    private let canvas = SaiyanHairCanvas()
    /// The skin that goes under the hair, kept apart so the hair's washes never colour it.
    private let skinCanvas = SaiyanHairCanvas()
    private var density = 0.0
    private var longDensity = 0.0
    private var queue: [(key: String, make: () -> Void)] = []
    private var queued: Set<String> = []
    private var frameCount = 0

    /// How far grown the current form's locks are, on average (1 at rest; above 1 while they overshoot). Read by the tests.
    private(set) var growth = 0.0
    /// How hard the hair is trembling, 0...1.
    private(set) var trembling = 0.0
    /// Whether anything of the hair was drawn on the latest frame.
    private(set) var isShowing = false
    /// The pictures of the latest frame, for the lens to lay on the graphics chip when it asks for them (see `SaiyanFace.hairImage`).
    private(set) var picture: SaiyanHairPicture?
    /// The wash on the long hair behind, on the latest frame (the same as the front hair's), when it was left for the graphics chip.
    private(set) var backTint: SaiyanTint?
    /// Every spring's position, for checking nothing has run away.
    var springs: [Double] { swings.values.flatMap { $0.map(\.x) } + longSway.map(\.x) }

    /// Lets go of the latest picture (nothing is showing).
    func forget() {
        picture = nil
        isShowing = false
    }

    func reset() {
        swings.removeAll()
        for i in longSway.indices { longSway[i].reset() }
        growth = 0
        trembling = 0
        isShowing = false
        picture = nil
    }

    // MARK: State

    struct Pass {
        let form: SaiyanForm
        let design: SaiyanHairDesign
        let ink: SaiyanInk
        var growth: [Double]
        var capGrowth = 1.0
        var capAlpha = 1.0
        var alpha = 1.0
        /// Powering down: the spikes sag outward.
        var droop = 0.0
        /// Powering up: the hair rises and trembles.
        var lift = 0.0
    }

    struct Plan {
        var passes: [Pass] = []
        /// The whole hair's opacity: arriving, flickering before the first change, fading out on the way back to base.
        var alpha = 1.0
        /// Colours washed over the hair in turn: an old form's fading, the next form's showing through, white-hot in the flash.
        var tints: [(colour: SIMD3<Double>, alpha: Double)] = []

        /// The washes as one: the same as laying each over the last, in order.
        var tint: SaiyanTint? {
            var colour = SIMD3<Double>(0, 0, 0), keep = 1.0
            for t in tints where t.alpha > 0.004 {
                let a = min(1, t.alpha)
                colour = colour * (1 - a) + t.colour * a
                keep *= 1 - a
            }
            guard keep < 0.996 else { return nil }
            return SaiyanTint(colour: colour / (1 - keep), amount: 1 - keep)
        }
    }

    private static func design(_ form: SaiyanForm) -> SaiyanHairDesign? { SaiyanHairDesign.of(form.hairStyle) }

    /// The growth of one lock `transition` of the way through a change, starting from `start`: it springs past full size and settles.
    static func springGrowth(_ transition: Double, delay: Double, from start: Double) -> Double {
        let tau = HeadwearEase.clamp01((transition - delay) / max(0.05, 1 - delay))
        let g = start + (1 - start) * SaiyanFaceKit.spring(tau * changeSeconds)
        return SaiyanFaceKit.lerp(g, 1, HeadwearEase.smoothstep((tau - 0.78) / 0.22))
    }

    /// What to draw for this state, at `clock` seconds, `seen` seconds after the face appeared.
    func plan(_ s: SaiyanBodyState, clock: Double, seen: Double) -> Plan {
        var plan = Plan()
        let tr = HeadwearEase.clamp01(s.transition)
        let changing = tr < 0.999 && s.previousForm != s.form
        let charge = HeadwearEase.clamp01(s.charge)
        let pulse = 0.82 + 0.18 * sin(clock * 13)
        if s.form.isBase {
            if changing, !s.previousForm.isBase, let d = Self.design(s.previousForm) {
                // Powering down: the hair sags, shrinks, darkens toward your own colour and fades.
                let e = HeadwearEase.smoothstep(tr)
                var p = Pass(form: s.previousForm, design: d, ink: SaiyanInk(s.previousForm), growth: Array(repeating: 1 - 0.36 * e, count: d.locks.count))
                p.droop = e
                p.alpha = 1 - HeadwearEase.smoothstep((tr - 0.3) / 0.7)
                plan.passes.append(p)
                plan.tints.append((SaiyanForm.base.palette.hairBase, 0.85 * HeadwearEase.smoothstep(tr / 0.55)))
            }
            if charge > 0.02, let next = s.form.next, let d = Self.design(next) {
                // Before the first change the hair flickers gold, more often and longer as the charge fills.
                let burst = pow(max(0, SaiyanFaceKit.wobble(clock * 11, 5)), 1.5)
                let flicker = HeadwearEase.smoothstep((charge - 0.04) / 0.5) * SaiyanFaceKit.lerp(burst, 1, pow(charge, 3))
                var p = Pass(form: next, design: d, ink: SaiyanInk(next), growth: Array(repeating: 0.62 + 0.3 * charge, count: d.locks.count))
                p.lift = charge
                p.alpha = 0.85 * flicker
                plan.passes.append(p)
                plan.tints.append((next.palette.auraCore, 0.3 + 0.3 * burst))
            }
        } else if let d = Self.design(s.form) {
            if changing, !s.previousForm.isBase, s.previousForm.hairStyle != s.form.hairStyle, tr < 0.5, let old = Self.design(s.previousForm) {
                // The old hair shrinks away under the new.
                let e = HeadwearEase.smoothstep(tr / 0.5)
                plan.passes.append(Pass(form: s.previousForm, design: old, ink: SaiyanInk(s.previousForm),
                                        growth: Array(repeating: 1 - 0.97 * e, count: old.locks.count)))
            }
            var p = Pass(form: s.form, design: d, ink: SaiyanInk(s.form), growth: Array(repeating: 1, count: d.locks.count))
            if changing {
                let from = s.previousForm
                let start = from.isBase ? 0.2 : (from.hairStyle == s.form.hairStyle ? 0.84 : 0.42)
                p.growth = d.locks.map { Self.springGrowth(tr, delay: $0.delay, from: start) }
                if from.isBase {
                    p.capGrowth = 0.9 + 0.1 * SaiyanFaceKit.spring(tr * Self.changeSeconds, omega: 16)
                    p.capAlpha = HeadwearEase.smoothstep(tr / 0.12)
                }
                // The colour starts as the old form's and crosses to the new; out of your own dark hair it turns quickly, under the flash.
                let turn = from.isBase ? (0.7, 0.3) : (0.88, 0.6)
                plan.tints.append((from.palette.hairBase, turn.0 * (1 - HeadwearEase.smoothstep(tr / turn.1))))
            }
            if charge > 0.01 {
                // Powering up toward the next form: the hair takes on its colour, pulsing, and burns brighter; at the top it only burns.
                if let next = s.form.next { plan.tints.append((next.palette.hairBase, 0.42 * pow(charge, 1.3) * pulse)) }
                plan.tints.append((s.form.palette.auraCore, (s.form.next == nil ? 0.32 : 0.14) * charge * pulse))
                p.lift = charge
            }
            if s.flash > 0.01 {
                // The flash: white-hot, cooling back to the form's colour.
                plan.tints.append((s.form.palette.auraCore, 0.62 * pow(min(1, s.flash), 1.2)))
            }
            plan.passes.append(p)
        }
        // Arriving: the hair springs up out of the head and fades in quickly.
        if seen < 1.2 {
            for i in plan.passes.indices {
                plan.passes[i].growth = zip(plan.passes[i].growth, plan.passes[i].design.locks).map { g, lock in
                    g * SaiyanFaceKit.spring(max(0, seen - 0.5 * lock.delay), omega: 12)
                }
                plan.passes[i].capGrowth *= 0.9 + 0.1 * SaiyanFaceKit.spring(seen, omega: 16)
            }
            plan.alpha *= HeadwearEase.smoothstep(seen / 0.12)
        }
        // With one pass the opacity goes on the whole picture, so locks do not show through each other as it fades.
        if plan.passes.count == 1 {
            plan.alpha *= plan.passes[0].alpha
            plan.passes[0].alpha = 1
        }
        return plan
    }

    // MARK: Moving

    func advance(_ f: HeadwearFrame, _ s: SaiyanBodyState) {
        frameCount += 1
        var designs: [SaiyanHairDesign] = []
        if let d = Self.design(s.form) { designs.append(d) }
        if s.transition < 1, let d = Self.design(s.previousForm), d.name != designs.first?.name { designs.append(d) }
        if s.form.isBase, s.charge > 0, let next = s.form.next, let d = Self.design(next) { designs.append(d) }
        let c = cos(f.roll), sn = sin(f.roll)
        for d in designs {
            var list = swings[d.name] ?? d.locks.map { lock in
                HeadwearSwing(omega: lock.omega, damping: lock.hangs ? 0.14 : 0.17, gain: 0.0022 * lock.length * lock.sway, limit: lock.hangs ? 0.6 : 0.35)
            }
            for (i, lock) in d.locks.enumerated() {
                let u = lock.direction
                // Inertia turns a lock against the head's acceleration; gravity pulls on it when the head tilts (stiff spikes barely).
                let push = -(Double(u.dy) * f.accel.x - Double(u.dx) * f.accel.y)
                let pull = (lock.hangs ? 0.3 : 0.04) * ((-Double(u.dx) * c + Double(u.dy) * sn) + Double(u.dx))
                list[i].step(dt: f.dt, accel: push, rest: pull)
            }
            swings[d.name] = list
        }
        // Super Saiyan 3's long hair swings like a pendulum, a little behind the head.
        if s.form.hairStyle == .long || s.previousForm.hairStyle == .long {
            for i in longSway.indices { longSway[i].step(dt: f.dt, accel: f.accel.x * (i == 0 ? 1 : 1.12), rest: f.hang * 0.25) }
        }
        trembling = s.form.isBase && s.charge < 0.02 ? 0 : HeadwearEase.clamp01(s.charge) * (s.screaming ? 1.4 : 1)
    }

    // MARK: Drawing

    /// The size a painting is kept at for a face of this many pixels to a unit: steps of the shared ladder, held a little past each step so
    /// a face hovering near one does not repaint everything.
    private func keptDensity(for pixels: Double, current: Double) -> Double {
        if current > 0, pixels * 1.05 <= current, pixels >= current / 1.65 { return current }
        return HeadwearSprites.density(for: pixels)
    }

    private func spriteName(_ d: SaiyanHairDesign, _ i: Int, _ ink: SaiyanInk) -> String { "saiyan-\(d.name)-\(i)-\(ink.id)" }

    /// A lock's painting, made on the spot if it has not been.
    private func sprite(_ d: SaiyanHairDesign, _ i: Int, _ ink: SaiyanInk) -> CGImage? {
        let lock = d.locks[i]
        return SaiyanSprites.image(spriteName(d, i, ink), window: lock.window, density: density) { lock.paint($0, ink) }
    }

    private func enqueue(_ key: String, _ make: @escaping () -> Void) {
        guard !queued.contains(key) else { return }
        queued.insert(key)
        queue.append((key, make))
    }

    /// While the charge builds, paints the next form's hair a lock a frame, so the change itself never waits on a painting.
    private func prepare(_ s: SaiyanBodyState, head: HeadwearHead, k: Double) {
        guard s.charge > 0, let next = s.form.next, let d = Self.design(next) else { return }
        let ink = SaiyanInk(next), density = self.density
        if queue.isEmpty {
            for (i, lock) in d.locks.enumerated() where SaiyanSprites.peek(spriteName(d, i, ink), density: density) == nil {
                let name = spriteName(d, i, ink)
                enqueue(SaiyanSprites.key(name, density: density)) { _ = SaiyanSprites.image(name, window: lock.window, density: density) { lock.paint($0, ink) } }
            }
            let (name, window, paint) = capPainting(d, ink, head: head, k: k)
            if SaiyanSprites.peek(name, density: density) == nil {
                enqueue(SaiyanSprites.key(name, density: density)) { _ = SaiyanSprites.image(name, window: window, density: density, paint) }
            }
        }
        if let job = queue.first {
            queue.removeFirst()
            queued.remove(job.key)
            job.make()
        }
    }

    /// Where a point of the test head lands on this head, in the picture's units (face units over `k`).
    private static func place(_ p: CGPoint, _ head: HeadwearHead, _ k: Double) -> CGPoint {
        let q = head.at(p.x, p.y)
        return CGPoint(x: q.x / k, y: q.y / k)
    }

    /// How much bigger than on the test head the hair is drawn on this head.
    static func size(of head: HeadwearHead) -> Double { sqrt(head.wide * head.tall) }

    /// The head's shape, steadied to a few steps so the mass is not repainted for every wobble of the reading.
    static func steadied(_ head: HeadwearHead) -> HeadwearHead {
        let wide = (head.wide * 50).rounded() / 50, tall = (head.tall * 50).rounded() / 50
        return HeadwearHead(mouthDrop: tall * HeadwearHead.reference.mouthDrop, halfWidth: wide * HeadwearHead.reference.halfWidth, brow: head.brow)
    }

    private func capPainting(_ d: SaiyanHairDesign, _ ink: SaiyanInk, head: HeadwearHead, k: Double) -> (String, CGRect, (HeadwearPen) -> Void) {
        let place = { (p: CGPoint) in Self.place(p, head, k) }
        let window = d.cap.path(place).boundingBoxOfPath.insetBy(dx: -0.05, dy: -0.05)
        let name = "saiyan-cap-\(d.name)-\(Int((head.wide * 50).rounded()))-\(Int((head.tall * 50).rounded()))-\(ink.id)"
        let cap = d.cap
        return (name, window, { cap.paint($0, ink, place) })
    }

    /// Builds this frame's pictures of the hair (with `pieces`, the brows and skin that go with it) and, unless `layOver` is false, lays
    /// them over the face. They are kept in `picture` either way.
    func draw(_ pen: HeadwearPen, _ f: HeadwearFrame, _ s: SaiyanBodyState, pieces: [SaiyanPiece], layOver: Bool = true) {
        let plan = self.plan(s, clock: f.clock, seen: f.seen)
        isShowing = false
        picture = nil
        growth = plan.passes.last.map { $0.growth.reduce(0, +) / Double(max(1, $0.growth.count)) } ?? 0
        let visiblePieces = pieces.filter { $0.alpha > 0.004 }
        guard (!plan.passes.isEmpty || !visiblePieces.isEmpty), plan.alpha > 0.004 else { return }
        let head = Self.steadied(f.head)
        let k = Self.size(of: head)
        density = keptDensity(for: f.io * k, current: density)
        prepare(s, head: head, k: k)

        // Everything that could be drawn this frame, for the size of the pictures.
        var box = CGRect.null, skinBox = CGRect.null
        for pass in plan.passes {
            box = box.union(capPainting(pass.design, pass.ink, head: head, k: k).1)
            for (i, lock) in pass.design.locks.enumerated() {
                let r = Self.place(lock.root, head, k)
                let g = max(1, pass.growth[i])
                let w = lock.window
                box = box.union(CGRect(x: r.x + w.minX * g, y: r.y + w.minY * g, width: w.width * g, height: w.height * g))
            }
        }
        func spot(_ piece: SaiyanPiece) -> CGRect {
            CGRect(x: (piece.at.x + piece.window.minX) / k, y: (piece.at.y + piece.window.minY) / k, width: piece.window.width / k, height: piece.window.height / k)
        }
        for piece in visiblePieces {
            if piece.layer == .skin { skinBox = skinBox.union(spot(piece)) } else { box = box.union(spot(piece)) }
        }
        let pieceDensity = density / k
        var skin: (image: CGImage, box: CGRect)?
        if !skinBox.isNull, skinCanvas.begin(covering: skinBox.insetBy(dx: -0.05, dy: -0.05), density: density) {
            // Last given at the bottom.
            for piece in visiblePieces.reversed() where piece.layer == .skin {
                if let image = SaiyanSprites.image(piece.name, window: piece.window, density: pieceDensity, piece.paint) {
                    skinCanvas.copy(image, window: spot(piece), alpha: piece.alpha)
                }
            }
            skin = skinCanvas.finish()
        }
        let margin = plan.passes.contains { $0.design.strands > 0 } ? 0.9 : 0.35
        guard !box.isNull, canvas.begin(covering: box.insetBy(dx: -margin, dy: -margin), density: density) else { return }

        // The brows go in first, under the fringe.
        for piece in visiblePieces where piece.layer == .underHair {
            if let image = SaiyanSprites.image(piece.name, window: piece.window, density: pieceDensity, piece.paint) {
                canvas.copy(image, window: spot(piece), alpha: piece.alpha)
            }
        }
        let tremble = trembling, t = f.clock
        let useLockAlpha = plan.passes.count > 1
        for pass in plan.passes {
            let d = pass.design
            let list = swings[d.name] ?? []
            let alpha = useLockAlpha ? pass.alpha : 1
            for (i, lock) in d.locks.enumerated() {
                if i == d.firstOverCap { drawCap(pass, head: head, k: k, alpha: alpha) }
                let g = pass.growth[i]
                guard g > 0.02, let image = sprite(d, i, pass.ink) else { continue }
                let root = Self.place(lock.root, head, k)
                let u = lock.direction
                var turn = i < list.count ? list[i].x : 0
                if pass.droop > 0, !lock.hangs { turn += (u.dx < 0 ? 1 : -1) * 0.42 * pass.droop }
                // Powering up: spikes stand taller and shiver, the fringe floats up.
                var offset = CGVector.zero
                if pass.lift > 0 {
                    let rise = 0.05 * pass.lift * lock.length
                    offset.dx += lock.hangs ? 0 : u.dx * rise
                    offset.dy += 0.035 * pass.lift + (lock.hangs ? 0 : u.dy * rise)
                    let shiver = 0.016 * tremble * SaiyanFaceKit.wobble(t * 47, lock.seed)
                    offset.dx += lock.across.dx * shiver
                    offset.dy += lock.across.dy * shiver + 0.006 * tremble * SaiyanFaceKit.wobble(t * 53, lock.seed + 9)
                }
                if abs(g - 1) < 0.004 && pass.droop < 0.001 {
                    // At rest a swing is a slide of the lock across itself: as far as turning would move its middle.
                    let slide = turn * lock.length * 0.5
                    canvas.copy(image, window: lock.window.offsetBy(dx: root.x + lock.across.dx * slide + offset.dx, dy: root.y + lock.across.dy * slide + offset.dy),
                                alpha: alpha)
                } else {
                    canvas.draw(image, window: lock.window.offsetBy(dx: root.x, dy: root.y), pivot: root, offset: offset, turn: turn, scale: g, alpha: alpha)
                }
            }
            if d.firstOverCap >= d.locks.count { drawCap(pass, head: head, k: k, alpha: alpha) }
        }
        // The loose strands and the glint, painted fresh, go in the same picture.
        if let main = plan.passes.last {
            canvas.inUnits(area: sparkleArea(f, main, head: head, k: k)) { pen in drawSparkle(pen, f, main, head: head, k: k) }
            if main.design.strands > 0 {
                let strands = self.strands(f, main, head: head, k: k)
                canvas.inUnits(area: strands.area) { pen in paintStrands(pen, strands.list, f, main.form) }
            }
        }
        let tint = plan.tint
        // Laid here, the washes are painted into the picture; laid by the lens, they are left to the graphics chip.
        if layOver, let tint { canvas.tint(tint.colour, alpha: tint.amount) }
        guard let (image, region) = canvas.finish() else { return }
        isShowing = !plan.passes.isEmpty
        picture = SaiyanHairPicture(hair: image, box: region, skin: skin?.image, skinBox: skin?.box ?? .null, scale: k, alpha: plan.alpha,
                                    tint: layOver ? nil : tint)
        guard layOver else { return }
        f.inFace(pen.ctx) {
            pen.ctx.saveGState()
            pen.ctx.scaleBy(x: CGFloat(k), y: CGFloat(k))
            pen.ctx.setAlpha(CGFloat(plan.alpha))
            pen.ctx.interpolationQuality = .medium
            if let skin { pen.ctx.draw(skin.image, in: skin.box) }
            pen.ctx.draw(image, in: region)
            pen.ctx.restoreGState()
        }
    }

    private func drawCap(_ pass: Pass, head: HeadwearHead, k: Double, alpha: Double) {
        let (name, window, paint) = capPainting(pass.design, pass.ink, head: head, k: k)
        guard let image = SaiyanSprites.image(name, window: window, density: density, paint) else { return }
        let a = alpha * pass.capAlpha
        if abs(pass.capGrowth - 1) < 0.002 {
            canvas.copy(image, window: window, alpha: a)
        } else {
            canvas.draw(image, window: window, pivot: Self.place(hwp(0, SaiyanCap.hairlineY), head, k), turn: 0, scale: pass.capGrowth, alpha: a)
        }
    }

    /// Which spike the glint is on, how far along, and how big, or nil between glints.
    private func glint(_ f: HeadwearFrame, _ pass: Pass, head: HeadwearHead, k: Double) -> (at: CGPoint, size: Double)? {
        let d = pass.design
        let candidates = d.locks.indices.filter { d.locks[$0].tier == .crown || d.locks[$0].tier == .front }
        guard !candidates.isEmpty else { return nil }
        let period = pass.form.hairStyle == .silver ? 1.3 : 2.4
        let beat = Int(floor(f.clock / period))
        let phase = (f.clock / period - Double(beat)) / 0.45
        guard phase < 1 else { return nil }
        let i = candidates[Int(HeadwearNoise.unit(beat, 77) * Double(candidates.count)) % candidates.count]
        let lock = d.locks[i]
        let root = Self.place(lock.root, head, k)
        let g = pass.growth[i], along = 0.55 + 0.4 * phase
        return (hwp(root.x + lock.tip.x * g * along, root.y + lock.tip.y * g * along), sin(phase * .pi) * 0.13)
    }

    private func sparkleArea(_ f: HeadwearFrame, _ pass: Pass, head: HeadwearHead, k: Double) -> CGRect {
        guard let g = glint(f, pass, head: head, k: k), g.size > 0.002 else { return .null }
        let r = g.size * 2.7
        return CGRect(x: g.at.x - r, y: g.at.y - r, width: r * 2, height: r * 2)
    }

    /// Now and then a glint runs up a spike toward its tip and twinkles there. In the picture's units.
    private func drawSparkle(_ pen: HeadwearPen, _ f: HeadwearFrame, _ pass: Pass, head: HeadwearHead, k: Double) {
        guard let g = glint(f, pass, head: head, k: k), g.size > 0.002 else { return }
        let light = SaiyanFaceKit.colour(pass.form.palette.hairHighlight).lighter(0.5)
        pen.glow(at: g.at, radius: g.size * 2.6, light.faded(0.45), additive: true)
        pen.sparkle(at: g.at, radius: g.size, HeadwearColor(1, 1, 1, 0.95), turn: f.clock * 0.8, additive: true)
    }

    /// Ultra Instinct's loose strands: fine hairs that drift up off the crown, waving slowly. Their centre lines, in the picture's units.
    private func strands(_ f: HeadwearFrame, _ pass: Pass, head: HeadwearHead, k: Double) -> (list: [(spine: [CGPoint], seed: Int)], area: CGRect) {
        let d = pass.design
        let crown = d.locks.indices.filter { d.locks[$0].tier == .crown }
        guard !crown.isEmpty else { return ([], .null) }
        let count = pass.form == .ultraInstinctSign ? max(2, d.strands / 2) : d.strands
        var list: [(spine: [CGPoint], seed: Int)] = []
        var area = CGRect.null
        for j in 0..<count {
            let i = crown[(j * 5 + 2) % crown.count]
            let lock = d.locks[i]
            let g = pass.growth[i]
            guard g > 0.3 else { continue }
            let root = Self.place(lock.root, head, k)
            let at = 0.45 + 0.25 * HeadwearNoise.unit(j, 41)
            let start = hwp(root.x + lock.tip.x * g * at, root.y + lock.tip.y * g * at)
            let base = atan2(Double(lock.direction.dy), Double(lock.direction.dx)) + (HeadwearNoise.unit(j, 42) - 0.5) * 0.7
            let phase = HeadwearNoise.unit(j, 43) * 6.283
            let length = (0.75 + 0.5 * HeadwearNoise.unit(j, 44)) * g
            let spine = HeadwearShape.spine(from: start, length: length, steps: 10) { t in base + 0.5 * t * sin(f.clock * 1.25 + phase + t * 3.2) }
            list.append((spine, j))
            for p in spine { area = area.union(CGRect(x: p.x - 0.2, y: p.y - 0.2, width: 0.4, height: 0.4)) }
        }
        return (list, area)
    }

    /// Paints the strands, each with a glint running along it.
    private func paintStrands(_ pen: HeadwearPen, _ list: [(spine: [CGPoint], seed: Int)], _ f: HeadwearFrame, _ form: SaiyanForm) {
        let ink = SaiyanInk(form)
        for (spine, j) in list {
            let strand = SaiyanFaceKit.blade(spine) { t in 0.026 * pow(1 - t, 0.7) + 0.002 }
            let phase = HeadwearNoise.unit(j, 43) * 6.283
            let fade = 0.6 + 0.4 * sin(f.clock * 0.9 + phase)
            pen.fill(strand.path, ink.light.faded(0.85 * fade))
            let u = (f.clock * 0.32 + HeadwearNoise.unit(j, 45)).truncatingRemainder(dividingBy: 1)
            let p = spine[min(spine.count - 1, Int(u * Double(spine.count - 1)))]
            let size = 0.06 * sin(u * .pi)
            pen.glow(at: p, radius: size * 3, HeadwearColor(0.85, 0.92, 1, 0.5 * fade), additive: true)
            pen.sparkle(at: p, radius: size, HeadwearColor(1, 1, 1, 0.9 * fade), turn: f.clock + Double(j), additive: true)
        }
    }

    // MARK: The long hair

    /// Whether the long hair shows behind the person for this state (Super Saiyan 3, growing in or going).
    static func showsLongHair(_ s: SaiyanBodyState) -> Bool {
        s.form.hairStyle == .long || (s.previousForm.hairStyle == .long && s.transition < 0.999)
    }

    /// The wash on the long hair: exactly the front hair's while it is Super Saiyan 3's (charging toward God, the flash, a change into it);
    /// while it goes, it is the old form's hair, so it crosses toward the new colour as the front crosses away from the old.
    func longHairTint(_ s: SaiyanBodyState, clock: Double, seen: Double) -> SaiyanTint? {
        if s.form.hairStyle == .long { return plan(s, clock: clock, seen: seen).tint }
        let tr = HeadwearEase.clamp01(s.transition)
        var tints: [(colour: SIMD3<Double>, alpha: Double)] = [(s.form.palette.hairBase, 0.88 * HeadwearEase.smoothstep(tr / 0.6))]
        if s.flash > 0.01 { tints.append((s.form.palette.auraCore, 0.62 * pow(min(1, s.flash), 1.2))) }
        return Plan(passes: [], alpha: 1, tints: tints).tint
    }

    /// Super Saiyan 3's long hair, behind the person, in output pixels. Its wash is painted here when `washHere`, or left in `backTint`.
    func drawBack(_ pen: HeadwearPen, _ f: HeadwearFrame, _ s: SaiyanBodyState, entrance: Double, washHere: Bool = true) {
        backTint = nil
        guard Self.showsLongHair(s) else { return }
        let tr = HeadwearEase.clamp01(s.transition)
        let changing = tr < 0.999 && s.previousForm != s.form
        var length = 1.0, alpha = entrance
        let form = s.form.hairStyle == .long ? s.form : s.previousForm
        if s.form.hairStyle == .long, changing, s.previousForm.hairStyle != .long {
            // Growing in: the hair pours down from behind the head.
            length = 0.15 + 0.85 * SaiyanFaceKit.lerp(SaiyanFaceKit.spring(tr * Self.changeSeconds, omega: 9, damping: 0.55), 1, HeadwearEase.smoothstep((tr - 0.8) / 0.2))
            alpha *= HeadwearEase.smoothstep(tr / 0.15)
        } else if s.form.hairStyle != .long {
            // Going: it draws back up behind the head, fading at the end.
            length = 1 - 0.85 * HeadwearEase.smoothstep(tr / 0.45)
            alpha *= 1 - HeadwearEase.smoothstep((tr - 0.15) / 0.3)
        }
        guard alpha > 0.004 else { return }
        let ink = SaiyanInk(form)
        let wide = (f.head.wide * 50).rounded() / 50, tall = (f.head.tall * 50).rounded() / 50
        let k = sqrt(wide * tall)
        // Painted at exactly the size it is shown, so it can be copied at whole pixels; repainted when the face moves nearer or farther.
        let wanted = f.io * k
        if longDensity == 0 || abs(wanted / longDensity - 1) > 0.035 { longDensity = (wanted * 4).rounded() / 4 }
        let density = longDensity
        let window = SaiyanLongHair.window
        let pivot = f.toScreen(hwp(0, SaiyanLongHair.pivot.y * tall))
        let ctx = pen.ctx
        var drawn = CGRect.null
        ctx.saveGState()
        ctx.setAlpha(CGFloat(alpha))
        for (n, side) in [-1.0, 1.0].enumerated() {
            let name = "saiyan-longhair-\(side > 0 ? "r" : "l")-\(ink.id)"
            let box = side > 0 ? window : CGRect(x: -window.maxX, y: window.minY, width: window.width, height: window.height)
            guard let image = SaiyanSprites.image(name, window: box, density: density, { SaiyanLongHair.paint($0, ink, side: side) }) else { continue }
            let sway = longSway[n].x * f.io
            // On a wider head it hangs a little farther out.
            let x = Double(pivot.x) + box.minX * density + side * 1.2 * (wide - 1) * f.io + sway
            let y = Double(pivot.y) + box.minY * density
            drawn = drawn.union(CGRect(x: x, y: y, width: Double(image.width), height: Double(image.height)))
            if abs(length - 1) < 0.003 {
                ctx.draw(image, in: CGRect(x: x.rounded(), y: y.rounded(), width: CGFloat(image.width), height: CGFloat(image.height)))
            } else {
                let top = Double(pivot.y) + box.maxY * density
                ctx.saveGState()
                ctx.translateBy(x: 0, y: CGFloat(top))
                ctx.scaleBy(x: 1, y: CGFloat(length))
                ctx.translateBy(x: 0, y: CGFloat(-top))
                ctx.draw(image, in: CGRect(x: x, y: y, width: Double(image.width), height: Double(image.height)))
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
        // The same wash as the mane, over the whole of it, so the locks are one colour from the crown to the tips.
        guard let tint = longHairTint(s, clock: f.clock, seen: f.seen), !drawn.isNull else { return }
        guard washHere else { backTint = tint; return }
        ctx.saveGState()
        ctx.setBlendMode(.sourceAtop)
        ctx.setFillColor(SaiyanFaceKit.colour(tint.colour, tint.amount).cg)
        ctx.fill(drawn.integral.insetBy(dx: -2, dy: -2))
        ctx.restoreGState()
    }
}
