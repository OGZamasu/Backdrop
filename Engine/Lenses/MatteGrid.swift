import CoreGraphics
import CoreImage
import simd

/// Asks how much of a person is at a point. Lets games run against a real silhouette in the app and a made-up one in tests.
protocol MatteQuery {
    /// 0...1, at an output pixel (origin lower left, y up). Zero outside the frame.
    func coverage(x: Double, y: Double) -> Double
}

/// The person's silhouette as a small grid the CPU can read.
final class MatteGrid: MatteQuery {
    let width: Int
    let height: Int
    /// Output pixels per grid cell.
    let cellSize: Double
    /// Row 0 is the top of the picture, as in any bitmap.
    private(set) var cells: [UInt8]

    init(outputSize: CGSize, cellSize: Double = 8) {
        self.cellSize = cellSize
        width = max(1, Int((outputSize.width / cellSize).rounded()))
        height = max(1, Int((outputSize.height / cellSize).rounded()))
        cells = Array(repeating: 0, count: width * height)
    }

    /// A grid with solid rectangles in it. For tests and previews.
    static func filled(_ rects: [CGRect], outputSize: CGSize, cellSize: Double = 8) -> MatteGrid {
        let grid = MatteGrid(outputSize: outputSize, cellSize: cellSize)
        for gy in 0..<grid.height {
            for gx in 0..<grid.width {
                let centre = CGPoint(x: (Double(gx) + 0.5) * cellSize, y: (Double(gy) + 0.5) * cellSize)
                if rects.contains(where: { $0.contains(centre) }) { grid.cells[(grid.height - 1 - gy) * grid.width + gx] = 255 }
            }
        }
        return grid
    }

    /// Refreshes from a matte image covering `rect`. One small read-back from the GPU.
    func update(from matte: CIImage, rect: CGRect, context: CIContext) {
        let scaled = matte
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / rect.width, y: CGFloat(height) / rect.height))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        cells.withUnsafeMutableBytes { bytes in
            context.render(scaled, toBitmap: bytes.baseAddress!, rowBytes: width,
                           bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .R8, colorSpace: nil)
        }
    }

    func coverage(x: Double, y: Double) -> Double {
        let gx = x / cellSize - 0.5, gy = y / cellSize - 0.5
        let x0 = Int(gx.rounded(.down)), y0 = Int(gy.rounded(.down))
        let fx = gx - Double(x0), fy = gy - Double(y0)
        func cell(_ cx: Int, _ cy: Int) -> Double {
            guard cx >= 0, cx < width, cy >= 0, cy < height else { return 0 }
            return Double(cells[(height - 1 - cy) * width + cx]) / 255
        }
        let top = cell(x0, y0) * (1 - fx) + cell(x0 + 1, y0) * fx
        let bottom = cell(x0, y0 + 1) * (1 - fx) + cell(x0 + 1, y0 + 1) * fx
        return top * (1 - fy) + bottom * fy
    }

    /// How much of the frame a person fills, 0...1. Tells a lens whether anyone is there.
    var fraction: Double {
        Double(cells.reduce(0) { $0 + ($1 > 127 ? 1 : 0) }) / Double(cells.count)
    }

    /// A frozen copy, since the grid itself is rewritten every frame.
    func snapshot() -> MatteGrid {
        let copy = MatteGrid(outputSize: CGSize(width: Double(width) * cellSize, height: Double(height) * cellSize), cellSize: cellSize)
        copy.cells = cells
        return copy
    }

    /// Where the silhouette has changed since `previous`: moving arms and hands light up, a still body does not.
    func motion(since previous: MatteGrid) -> MatteQuery { MotionQuery(current: self, previous: previous) }

    /// Every cell on the silhouette's outline, in output pixels. Scanned once per call.
    func edges() -> [CGPoint] {
        var found: [CGPoint] = []
        guard width > 2, height > 2 else { return found }
        func solid(_ gx: Int, _ gy: Int) -> Bool { cells[(height - 1 - gy) * width + gx] > 127 }
        for gy in 1..<(height - 1) {
            for gx in 1..<(width - 1) where solid(gx, gy) {
                if !solid(gx - 1, gy) || !solid(gx + 1, gy) || !solid(gx, gy - 1) || !solid(gx, gy + 1) {
                    found.append(CGPoint(x: (Double(gx) + 0.5) * cellSize, y: (Double(gy) + 0.5) * cellSize))
                }
            }
        }
        return found
    }

    /// A point on the outline chosen by `random` in 0..<1. Nil if nobody is there.
    func edgePoint(_ random: Double) -> CGPoint? {
        let all = edges()
        return all.isEmpty ? nil : all[min(all.count - 1, Int(random * Double(all.count)))]
    }
}

/// Bouncing things off a person: the physics behind the ball pit and breakout.
enum Silhouette {
    struct Contact {
        /// Unit vector pointing out of the person, toward where the ball should go.
        var normal: SIMD2<Double>
        /// How far along `normal` the ball must move to be clear.
        var depth: Double
    }

    private static let ringSamples = 16

    /// Whether a circle overlaps the silhouette and, if so, which way is out.
    static func contact(center c: SIMD2<Double>, radius r: Double, in matte: MatteQuery) -> Contact? {
        var push = SIMD2<Double>.zero
        var touching = 0
        for i in 0..<ringSamples {
            let d = direction(i)
            let v = matte.coverage(x: c.x + d.x * r, y: c.y + d.y * r)
            if v > 0.5 { push -= d * v; touching += 1 }
        }
        let inside = matte.coverage(x: c.x, y: c.y) > 0.5
        guard inside || touching > 0 else { return nil }

        // Straddling an edge, the covered samples point at the person. Deep inside they cancel out, so look wider.
        var normal = push
        if inside || simd_length(normal) < 1e-6 { normal = escape(from: c, radius: r, in: matte) }
        let n = simd_length(normal) > 1e-9 ? simd_normalize(normal) : SIMD2<Double>(0, 1)

        var travelled = 0.0
        while travelled < r * 10, !isClear(c + n * travelled, radius: r, in: matte) { travelled += r / 8 }
        return Contact(normal: n, depth: travelled)
    }

    /// Moves a ball out of the silhouette and bounces it. Returns whether it touched.
    @discardableResult
    static func resolve(position: inout SIMD2<Double>, velocity: inout SIMD2<Double>, radius: Double,
                        in matte: MatteQuery, restitution: Double) -> Bool {
        guard let hit = contact(center: position, radius: radius, in: matte) else { return false }
        position += hit.normal * hit.depth
        let approach = simd_dot(velocity, hit.normal)
        if approach < 0 { velocity -= (1 + restitution) * approach * hit.normal }
        return true
    }

    private static func direction(_ i: Int) -> SIMD2<Double> {
        let a = Double(i) / Double(ringSamples) * 2 * .pi
        return SIMD2(cos(a), sin(a))
    }

    private static func isClear(_ p: SIMD2<Double>, radius r: Double, in matte: MatteQuery) -> Bool {
        if matte.coverage(x: p.x, y: p.y) > 0.5 { return false }
        for i in 0..<ringSamples {
            let d = direction(i)
            if matte.coverage(x: p.x + d.x * r, y: p.y + d.y * r) > 0.5 { return false }
        }
        return true
    }

    private static func escape(from c: SIMD2<Double>, radius r: Double, in matte: MatteQuery) -> SIMD2<Double> {
        for scale in [2.0, 4.0, 8.0] {
            var push = SIMD2<Double>.zero
            for i in 0..<ringSamples {
                let d = direction(i)
                push -= d * matte.coverage(x: c.x + d.x * r * scale, y: c.y + d.y * r * scale)
            }
            if simd_length(push) > 1e-6 { return push }
        }
        return SIMD2(0, 1)
    }
}

/// How much the silhouette changed between two frames, 0...1. A hand swatting through the air shows up; a body sitting still does not.
struct MotionQuery: MatteQuery {
    let current: MatteGrid
    let previous: MatteGrid

    func coverage(x: Double, y: Double) -> Double {
        min(1, abs(current.coverage(x: x, y: y) - previous.coverage(x: x, y: y)) * 1.6)
    }
}
