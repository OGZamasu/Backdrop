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

/// The glyphs, drawn once in white the first time they are needed (on the video queue, not while the lens is made) and then
/// stamped with a brightness. The colour is put on afterwards, to the whole layer at once.
enum GlyphAtlas {
    static let glyphs: [String] = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789").map(String.init)
    static let cell = CGSize(width: 20, height: 26)

    private static let lock = NSLock()
    private static var images: [CGImage] = []

    static func image(glyph: Int) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if images.isEmpty { images = bake() }
        guard !images.isEmpty else { return nil }
        return images[glyph % images.count]
    }

    private static func bake() -> [CGImage] {
        let font = NSFont.monospacedSystemFont(ofSize: 20, weight: .semibold)
        return glyphs.compactMap { glyph in
            guard let ctx = CGContext(data: nil, width: Int(cell.width), height: Int(cell.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            // Mirrored, as the code in the films is.
            ctx.translateBy(x: cell.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            let text = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: NSColor.white])
            let box = text.size()
            text.draw(at: NSPoint(x: (cell.width - box.width) / 2, y: (cell.height - box.height) / 2))
            NSGraphicsContext.restoreGraphicsState()
            return ctx.makeImage()
        }
    }
}

/// Everything goes green, and code rains down behind you: a near layer of glyphs with glowing heads, and a dimmer, smaller
/// layer further back.
final class MatrixLens: Lens {
    let needs: LensNeeds = [.matte]

    private var rain = MatrixRain(columns: 64, rows: 28, glyphCount: GlyphAtlas.glyphs.count)

    func restart() { rain = MatrixRain(columns: 64, rows: 28, glyphCount: GlyphAtlas.glyphs.count, seed: UInt64.random(in: .min ... .max)) }

    /// You, in phosphor green: deep green shadows, mint highlights, lifted so a dark face still reads.
    private static let phosphor: CIImage? = LookKit.ramp([
        (0.00, (0.00, 0.03, 0.01)), (0.30, (0.02, 0.24, 0.08)), (0.62, (0.18, 0.72, 0.32)), (0.85, (0.55, 0.95, 0.62)), (1.00, (0.88, 1.00, 0.90)),
    ]).map { CIImage(cgImage: $0) }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        rain.step(input.dt)
        let cell = GlyphAtlas.cell

        // The trails, in white with their brightness as alpha, and the leading glyphs on a layer of their own so they can glow.
        let trails = input.services.overlay { ctx in
            for column in 0..<rain.columnCount {
                for row in 0..<rain.rowCount {
                    let brightness = rain.brightness(column: column, row: row)
                    guard brightness > 0.03, brightness < 1, let image = GlyphAtlas.image(glyph: rain.glyph(column: column, row: row)) else { continue }
                    ctx.setAlpha(CGFloat(brightness))
                    ctx.draw(image, in: CGRect(x: rect.minX + CGFloat(column) * cell.width, y: rect.maxY - CGFloat(row + 1) * cell.height,
                                               width: cell.width, height: cell.height))
                }
            }
            ctx.setAlpha(1)
        }
        let heads = input.services.overlay { ctx in
            for column in 0..<rain.columnCount {
                let row = Int(rain.columns[column].head.rounded(.down))
                guard row >= 0, row < rain.rowCount, let image = GlyphAtlas.image(glyph: rain.glyph(column: column, row: row)) else { continue }
                ctx.draw(image, in: CGRect(x: rect.minX + CGFloat(column) * cell.width, y: rect.maxY - CGFloat(row + 1) * cell.height,
                                           width: cell.width, height: cell.height))
            }
        }

        let tone = LookKit.perceptual(LookKit.grey(input.composed)).applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.8])
        let you = Self.phosphor.map { LookKit.colourise(tone, with: $0) } ?? tone
        guard let trails, let heads else { return you.cropped(to: rect) }

        let green = LookKit.tint(trails, by: (0.16, 0.92, 0.38))
        let white = LookKit.tint(heads, by: (0.82, 1.0, 0.86))
        // Further back: the same rain, smaller and dimmer and a touch soft, repeated across the width.
        let far = Self.distant(green, rect: rect, scale: 0.55).applyingGaussianBlur(sigma: 0.9).cropped(to: rect)
        let glow = LookKit.glow(white.composited(over: green), rect: rect, threshold: 0.0, sigma: 3.5, tint: (0.35, 1.0, 0.5))
        let code = LookKit.screen(LookKit.levels(glow, gain: 0.55), over: white.composited(over: green.composited(over: far.fading(0.38))))
        let night = CIImage(color: CIColor(red: 0, green: 0.012, blue: 0.004)).cropped(to: rect)
        let room = code.composited(over: night)

        guard let matte = input.matte else { return LookKit.screen(code.fading(0.6), over: you).cropped(to: rect) }
        // Your outline catches a green light, and faint code runs over you too, so you sit inside it.
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        let solid = LookKit.levels(LookKit.shrink(matte, rect: rect, by: 0.5), gain: 6, bias: -2.5)
        let rim = solid.clampedToExtent().applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: 2.0])
            .applyingGaussianBlur(sigma: 3).cropped(to: half)
        let edge = LookKit.tint(LookKit.enlarge(rim, to: rect, from: half), by: (0.2, 0.9, 0.4))
        let person = LookKit.blend(you, over: room, mask: matte)
        return LookKit.screen(LookKit.screen(edge, over: code.fading(0.16)), over: person).cropped(to: rect)
    }

    /// A layer shrunk towards the top middle and tiled sideways, so it reads as more rain further away.
    private static func distant(_ layer: CIImage, rect: CGRect, scale: CGFloat) -> CIImage {
        let shrink = CGAffineTransform(translationX: -rect.midX, y: -rect.maxY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.maxY))
        let small = layer.transformed(by: shrink)
        let step = rect.width * scale
        var tiled = small
        for k in [-2.0, -1.0, 1.0, 2.0] { tiled = small.transformed(by: CGAffineTransform(translationX: step * k, y: 0)).composited(over: tiled) }
        let lower = tiled.transformed(by: CGAffineTransform(translationX: step * 0.5, y: -rect.height * scale))
        return tiled.composited(over: lower).cropped(to: rect)
    }
}
