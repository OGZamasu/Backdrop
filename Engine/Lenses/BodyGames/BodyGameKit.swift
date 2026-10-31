import AppKit
import CoreGraphics
import simd

/// A line of text that rises from where something happened and fades: "+10", "CLOSE CALL".
struct BodyFloater {
    static let good = BodyGamePalette.gold
    static let bad = BodyGamePalette.coral
    static let cool = BodyGamePalette.sky

    var text: String
    var position: SIMD2<Double>
    var color: NSColor = BodyFloater.good
    var size: CGFloat = 52
    var life = 0.95
    var rise = 70.0
    var age = 0.0

    var isDone: Bool { age >= life }

    mutating func advance(_ dt: Double) {
        age += dt
        // Quick at first, then drifting to a stop.
        position.y += rise * dt * 2.2 * max(0, 1 - age / life)
    }

    func draw(in ctx: CGContext) {
        let fade = max(0, 1 - max(0, age - life * 0.5) / (life * 0.5))
        let pop = 0.6 + 0.4 * BodyEase.outBack(age / 0.22, overshoot: 2.6)
        BodyGameHUD.text(ctx, text, center: CGPoint(x: position.x, y: position.y), size: size * CGFloat(pop), color: color, alpha: CGFloat(fade))
    }

    /// The same floater kept clear of the picture's edges and of the HUD band along the top, so it is never clipped.
    /// `avoiding` is where the player's head is: words that would land on it are moved out to the side.
    static func placed(_ text: String, at p: SIMD2<Double>, size: CGSize, color: NSColor = BodyFloater.good, fontSize: CGFloat = 52,
                       life: Double = 0.95, rise: Double = 70, avoiding head: CGRect? = nil) -> BodyFloater {
        let half = Double(BodyGameHUD.width(of: text, size: fontSize)) / 2 + 12
        let low = 60.0, high = size.height - 170 - rise * 0.9
        var x = bodyClamp(p.x, half + 40, size.width - half - 40)
        var y = bodyClamp(p.y, low, high)
        if let head {
            let zone = head.insetBy(dx: -half - 18, dy: -Double(fontSize) * 0.6 - rise * 0.5)
            if zone.contains(CGPoint(x: x, y: y)) {
                let left = Double(zone.minX), right = Double(zone.maxX)
                let goLeft = x < Double(zone.midX)
                x = goLeft ? left : right
                if x < half + 40 || x > size.width - half - 40 {
                    x = goLeft ? right : left
                    if x < half + 40 || x > size.width - half - 40 { x = bodyClamp(p.x, half + 40, size.width - half - 40); y = max(low, Double(zone.minY) - 10) }
                }
            }
        }
        return BodyFloater(text: text, position: SIMD2(x, y), color: color, size: fontSize, life: life, rise: rise)
    }
}

/// A silhouette made of solid rectangles. Games use it to ask "would this pose fit?", and tests use it as a stand-in person.
struct BodyRectsMatte: MatteQuery {
    var rects: [CGRect] = []

    func coverage(x: Double, y: Double) -> Double {
        rects.contains { $0.contains(CGPoint(x: x, y: y)) } ? 1 : 0
    }
}

/// A coarse look at the silhouette on a grid of sample points, for games that aim at you or build themselves around you.
struct BodyScan {
    let step: Double
    let columns: Int
    let rows: Int
    /// Coverage at each sample. Row 0 is the bottom of the picture, as in output pixels.
    private(set) var weights: [Float]
    private(set) var solidCount = 0
    /// The box around the person, ignoring stray specks. Nil when nobody is there.
    private(set) var box: CGRect?
    private(set) var topRow = -1
    private(set) var bottomRow = -1
    private(set) var centroid = CGPoint.zero

    init(matte: MatteQuery?, size: CGSize, step: Double = 16) {
        self.step = step
        columns = max(1, Int((size.width / step).rounded(.up)))
        rows = max(1, Int((size.height / step).rounded(.up)))
        weights = [Float](repeating: 0, count: columns * rows)
        guard let matte else { return }

        var rowCounts = [Int](repeating: 0, count: rows), columnCounts = [Int](repeating: 0, count: columns)
        var sumX = 0.0, sumY = 0.0
        for gy in 0..<rows {
            for gx in 0..<columns {
                let at = Self.point(gx, gy, step: step)
                let value = matte.coverage(x: at.x, y: at.y)
                weights[gy * columns + gx] = Float(value)
                if value > 0.5 {
                    rowCounts[gy] += 1
                    columnCounts[gx] += 1
                    solidCount += 1
                    sumX += at.x
                    sumY += at.y
                }
            }
        }
        guard solidCount > 0 else { return }
        centroid = CGPoint(x: sumX / Double(solidCount), y: sumY / Double(solidCount))
        let usedRows = (0..<rows).filter { rowCounts[$0] >= 2 }, usedColumns = (0..<columns).filter { columnCounts[$0] >= 2 }
        guard let top = usedRows.last, let bottom = usedRows.first, let left = usedColumns.first, let right = usedColumns.last else { return }
        topRow = top
        bottomRow = bottom
        box = CGRect(x: Double(left) * step, y: Double(bottom) * step,
                     width: Double(right - left + 1) * step, height: Double(top - bottom + 1) * step)
    }

    /// Where the head probably is: the top of the silhouette, as wide as it is there. Nil when nobody is in view.
    var headZone: CGRect? {
        guard present, let box else { return nil }
        let rowsDown = max(2, Int((max(110, Double(box.height) * 0.32) / step).rounded()))
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        let lowest = max(bottomRow, topRow - rowsDown)
        // The head is the narrow top of the person: take the widest run near the top, but no wider than the box allows.
        for gy in lowest...topRow {
            for gx in 0..<columns where weights[gy * columns + gx] > 0.5 {
                let x = (Double(gx) + 0.5) * step
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        guard minX <= maxX else { return nil }
        let width = min(maxX - minX + step, max(120, Double(box.width) * 0.6))
        let middle = (minX + maxX) / 2
        let top = Double(box.maxY)
        let height = Double(topRow - lowest + 1) * step
        return CGRect(x: middle - width / 2, y: top - height, width: width, height: height)
    }

    /// How much of the picture a person fills, 0...1.
    var fraction: Double { Double(solidCount) / Double(max(1, columns * rows)) }
    /// Whether anyone is really there, not just a speck of noise.
    var present: Bool { fraction >= 0.015 && box != nil }

    private static func point(_ gx: Int, _ gy: Int, step: Double) -> CGPoint {
        CGPoint(x: (Double(gx) + 0.5) * step, y: (Double(gy) + 0.5) * step)
    }

    func center(_ gx: Int, _ gy: Int) -> CGPoint { Self.point(gx, gy, step: step) }
    func weight(_ gx: Int, _ gy: Int) -> Double { Double(weights[gy * columns + gx]) }

    /// How wide the person is across one row of samples, in pixels.
    func rowWidth(_ gy: Int) -> Double {
        guard gy >= 0, gy < rows else { return 0 }
        var count = 0
        for gx in 0..<columns where weights[gy * columns + gx] > 0.5 { count += 1 }
        return Double(count) * step
    }

    /// Sample points that are on the person, every `n`th one.
    func solidPoints(every n: Int = 1) -> [CGPoint] {
        var found: [CGPoint] = []
        var seen = 0
        for gy in 0..<rows {
            for gx in 0..<columns where weights[gy * columns + gx] > 0.5 {
                if seen % max(1, n) == 0 { found.append(center(gx, gy)) }
                seen += 1
            }
        }
        return found
    }
}

/// Reading the silhouette and its motion the same way in every body game.
enum BodySense {
    /// How many of nine points around `p` (the middle and a ring at `radius`) see motion. A real cutout's edge flickers by a
    /// pixel or two even when the person is still; asking for two or more of these ignores that and still catches a swat.
    static func motionHits(at p: SIMD2<Double>, radius: Double, in motion: MatteQuery) -> Int {
        var seen = motion.coverage(x: p.x, y: p.y) > 0.5 ? 1 : 0
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi
            if motion.coverage(x: p.x + cos(a) * radius, y: p.y + sin(a) * radius) > 0.5 { seen += 1 }
        }
        return seen
    }

    /// How many of nine points around `p` are on the person.
    static func bodyHits(at p: SIMD2<Double>, radius: Double, in matte: MatteQuery) -> Int {
        var seen = matte.coverage(x: p.x, y: p.y) > 0.5 ? 1 : 0
        for i in 0..<8 {
            let a = (Double(i) + 0.5) / 8 * 2 * .pi
            if matte.coverage(x: p.x + cos(a) * radius, y: p.y + sin(a) * radius) > 0.5 { seen += 1 }
        }
        return seen
    }
}

/// Pictures drawn once and kept: a rock, a bubble, a wall. Drawing them every frame would be far too slow.
enum BodyArtCache {
    private static let lock = NSLock()
    private static var images: [String: CGImage] = [:]

    /// The picture for `key`, made by `draw` the first time it is asked for.
    /// The lock is not held while drawing, so one picture can be built from others, and a background warm-up never holds up the video.
    static func image(_ key: String, width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        lock.lock()
        if let hit = images[key] { lock.unlock(); return hit }
        lock.unlock()
        guard let image = render(width: width, height: height, draw: draw) else { return nil }
        lock.lock(); defer { lock.unlock() }
        // Two threads may have drawn the same picture at once; keep the first so everyone shares one.
        if let first = images[key] { return first }
        // Every body game's pictures together come to about a hundred; don't let the cache grow without end.
        if images.count > 256 { images.removeAll() }
        images[key] = image
        return image
    }

    private static var warmed: Set<String> = []

    /// Runs `work` (drawing a game's pictures into the cache) once, on a background queue, so the first frames of play don't stall.
    static func warm(_ key: String, _ work: @escaping () -> Void) {
        lock.lock()
        let fresh = warmed.insert(key).inserted
        lock.unlock()
        guard fresh else { return }
        DispatchQueue.global(qos: .utility).async(execute: work)
    }

    /// A picture that is not kept in the shared cache: the caller owns it.
    static func render(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()
    }
}

/// A number held between two bounds, for the body games.
func bodyClamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T { min(max(value, low), high) }
