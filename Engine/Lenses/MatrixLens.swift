import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// The falling green code, with no drawing in it: where each column's head is, and how bright each cell behind it is.
struct MatrixRain {
    struct Column {
        var head: Double       // in rows from the top; grows as it falls
        var speed: Double      // rows per second
        var length: Int
    }

    let columnCount: Int
    let rowCount: Int
    let glyphCount: Int
    private(set) var columns: [Column] = []
    private(set) var glyphs: [UInt8]
    private var rng: SplitMix64

    init(columns: Int, rows: Int, glyphCount: Int, seed: UInt64 = 0x3A7) {
        columnCount = columns
        rowCount = rows
        self.glyphCount = glyphCount
        rng = SplitMix64(seed: seed)
        glyphs = Array(repeating: 0, count: columns * rows)
        self.columns = (0..<columns).map { _ in
            Column(head: Double.random(in: -Double(rows)...Double(rows), using: &rng),
                   speed: Double.random(in: 7...19, using: &rng), length: Int.random(in: 8...24, using: &rng))
        }
        for i in glyphs.indices { glyphs[i] = UInt8(Int.random(in: 0..<glyphCount, using: &rng)) }
    }

    mutating func step(_ dt: Double) {
        for i in columns.indices {
            columns[i].head += columns[i].speed * dt
            if columns[i].head - Double(columns[i].length) > Double(rowCount) {
                columns[i] = Column(head: -Double.random(in: 0...Double(rowCount) * 0.6, using: &rng),
                                    speed: Double.random(in: 7...19, using: &rng), length: Int.random(in: 8...24, using: &rng))
            }
        }
        // Characters keep changing.
        for _ in 0..<Int(Double(glyphs.count) * dt * 0.9) {
            glyphs[Int.random(in: 0..<glyphs.count, using: &rng)] = UInt8(Int.random(in: 0..<glyphCount, using: &rng))
        }
    }

    /// Brightness of a cell: 0 where nothing is drawn, rising to 1 at the head.
    func brightness(column: Int, row: Int) -> Double {
        let behind = columns[column].head - Double(row)
        guard behind >= 0, behind < Double(columns[column].length) else { return 0 }
        return behind < 1 ? 1 : 0.85 * (1 - behind / Double(columns[column].length))
    }

    func glyph(column: Int, row: Int) -> Int { Int(glyphs[column * rowCount + row]) }
}

/// Glyphs drawn once, in a few shades of green, then stamped.
enum GlyphAtlas {
    static let glyphs: [String] = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789").map(String.init)
    static let shades = 8
    static let cell = CGSize(width: 20, height: 26)

    private static let lock = NSLock()
    private static var cache: [Int: CGImage] = [:]

    static func image(glyph: Int, shade: Int) -> CGImage? {
        let key = glyph * 16 + shade
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        guard let ctx = CGContext(data: nil, width: Int(cell.width), height: Int(cell.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        let level = Double(shade) / Double(shades - 1)
        let colour = shade == shades - 1
            ? NSColor(red: 0.8, green: 1, blue: 0.85, alpha: 1)                                    // the head glows white
            : NSColor(red: 0, green: 0.2 + 0.7 * level, blue: 0.05 + 0.2 * level, alpha: 1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let text = NSAttributedString(string: glyphs[glyph % glyphs.count],
                                      attributes: [.font: NSFont.monospacedSystemFont(ofSize: 20, weight: .bold), .foregroundColor: colour])
        let box = text.size()
        text.draw(at: NSPoint(x: (cell.width - box.width) / 2, y: (cell.height - box.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return nil }
        cache[key] = image
        return image
    }
}

/// Everything goes green, and code rains down behind you.
final class MatrixLens: Lens {
    let needs: LensNeeds = [.matte]

    private var rain = MatrixRain(columns: 64, rows: 28, glyphCount: GlyphAtlas.glyphs.count)

    init() {
        // Draw every glyph in every shade now, rather than stalling the first frame that needs them.
        for glyph in 0..<GlyphAtlas.glyphs.count { for shade in 0..<GlyphAtlas.shades { _ = GlyphAtlas.image(glyph: glyph, shade: shade) } }
    }

    func restart() { rain = MatrixRain(columns: 64, rows: 28, glyphCount: GlyphAtlas.glyphs.count, seed: UInt64.random(in: .min ... .max)) }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        rain.step(input.dt)
        let cell = GlyphAtlas.cell
        let layer = input.services.overlay { ctx in
            for column in 0..<rain.columnCount {
                for row in 0..<rain.rowCount {
                    let brightness = rain.brightness(column: column, row: row)
                    guard brightness > 0.03 else { continue }
                    let shade = brightness >= 1 ? GlyphAtlas.shades - 1 : min(GlyphAtlas.shades - 2, Int(brightness * Double(GlyphAtlas.shades - 1)))
                    guard let image = GlyphAtlas.image(glyph: rain.glyph(column: column, row: row), shade: shade) else { continue }
                    ctx.draw(image, in: CGRect(x: CGFloat(column) * cell.width, y: rect.height - CGFloat(row + 1) * cell.height,
                                               width: cell.width, height: cell.height))
                }
            }
        }

        let green = input.composed.applyingFilter("CIColorMonochrome", parameters: [
            kCIInputColorKey: CIColor(red: 0.25, green: 1, blue: 0.4), kCIInputIntensityKey: 0.92,
        ])
        guard let layer else { return green }
        guard let matte = input.matte else { return layer.fading(0.7).composited(over: green).cropped(to: rect) }

        let black = CIImage(color: CIColor(red: 0, green: 0.015, blue: 0)).cropped(to: rect)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = green
        blend.backgroundImage = layer.composited(over: black)
        blend.maskImage = matte
        // Faint rain across the person too, so they sit inside the code rather than in front of it.
        return layer.fading(0.28).composited(over: blend.outputImage ?? green).cropped(to: rect)
    }
}
