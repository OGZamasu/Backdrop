import AppKit
import CoreGraphics
import CoreImage
import CoreVideo

/// Something to draw sprites, text and glows on, handed back as a transparent picture to lay over the video.
///
/// Several buffers take turns, so a picture handed out this frame is never scribbled over while it is still
/// being read.
final class OverlayCanvas {
    let size: CGSize
    private var slots: [(buffer: CVPixelBuffer, context: CGContext)] = []
    private var current = 0
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!

    init?(size: CGSize, slots count: Int = 3) {
        self.size = size
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        for _ in 0..<count {
            var created: CVPixelBuffer?
            guard CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA,
                                      attributes as CFDictionary, &created) == kCVReturnSuccess, let buffer = created else { return nil }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                                    bitmapInfo: Sprites.bitmapInfo)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard let context else { return nil }
            context.setAllowsAntialiasing(true)
            context.interpolationQuality = .high
            slots.append((buffer, context))
        }
    }

    /// Moves to the next buffer, wipes it, and returns a context to draw in.
    func begin() -> CGContext {
        current = (current + 1) % slots.count
        let slot = slots[current]
        CVPixelBufferLockBaseAddress(slot.buffer, [])
        slot.context.clear(CGRect(origin: .zero, size: size))
        slot.context.setBlendMode(.normal)
        slot.context.setAlpha(1)
        return slot.context
    }

    /// What was drawn since `begin()`.
    func image() -> CIImage {
        let slot = slots[current]
        CVPixelBufferUnlockBaseAddress(slot.buffer, [])
        return CIImage(cvPixelBuffer: slot.buffer, options: [.colorSpace: space])
    }
}

// MARK: - Drawing helpers

enum Sprites {
    /// The canvas's own pixel layout (BGRA, premultiplied). Every sprite is made in it too: Core Graphics converts a sprite in
    /// any other layout on every single draw, which made a few hundred sparks cost several milliseconds of CPU a frame.
    static let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]

    /// An emoji drawn once and kept. `size` is the font size in pixels.
    static func emoji(_ character: String, size: CGFloat) -> CGImage? {
        let key = "\(character)@\(Int(size.rounded()))"
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }

        let font = NSFont(name: "AppleColorEmoji", size: size) ?? NSFont.systemFont(ofSize: size)
        let text = NSAttributedString(string: character, attributes: [.font: font])
        let box = text.size()
        let width = Int(ceil(box.width)) + 8, height = Int(ceil(box.height)) + 8
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(at: NSPoint(x: 4, y: 4))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        // Lenses can name any emoji; don't let the cache grow without end.
        if cache.count > 96 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

extension CGContext {
    /// Draws an image centred on a point, scaled to a height, optionally turned (radians, counter-clockwise).
    func draw(_ image: CGImage, center: CGPoint, height: CGFloat, rotation: CGFloat = 0, alpha: CGFloat = 1) {
        let width = height * CGFloat(image.width) / CGFloat(image.height)
        saveGState()
        translateBy(x: center.x, y: center.y)
        rotate(by: rotation)
        setAlpha(alpha)
        draw(image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        restoreGState()
    }

    func fillCircle(center: CGPoint, radius: CGFloat, color: CGColor) {
        setFillColor(color)
        fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// A soft round glow: opaque in the middle, fading to nothing at the edge.
    func glow(center: CGPoint, radius: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        guard radius > 0.5, alpha > 0.002 else { return }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [CGColor(colorSpace: space, components: [red, green, blue, alpha])!,
                      CGColor(colorSpace: space, components: [red, green, blue, 0])!] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
        drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    /// Text centred on a point, with a dark edge so it reads on any picture.
    func text(_ string: String, center: CGPoint, size: CGFloat, color: NSColor = .white, weight: NSFont.Weight = .heavy) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: self, flipped: false)
        for (offset, tint) in [(CGFloat(3), NSColor(white: 0, alpha: 0.55)), (0, color)] {
            let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: tint])
            let box = attributed.size()
            attributed.draw(at: NSPoint(x: center.x - box.width / 2 + offset, y: center.y - box.height / 2 - offset))
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
