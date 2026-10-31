import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import simd

/// After-images of where you just were: a copy of you is kept every tenth of a second, and the copies hang in the air behind you
/// as glowing, see-through ghosts that cool from ice blue to violet and fade within a second. Stand still and they hide behind you.
final class GhostTrailsLens: Lens {
    let needs: LensNeeds = [.matte]

    /// One kept copy: a soft-edged grey ghost of you at half size, and when it was taken.
    private struct Echo {
        var buffer: CVPixelBuffer
        var time: Double
    }

    /// How often a copy is kept, and how long one lasts.
    static let interval = 0.1
    static let lifetime = 1.0
    /// Ice blue when fresh, violet as it fades: the "Spectre" palette.
    static let fresh = SIMD3<Double>(0.62, 0.93, 1.0)
    static let old = SIMD3<Double>(0.66, 0.42, 1.0)

    private let scale = 0.5
    private var echoes: [Echo] = []
    private var spare: [CVPixelBuffer] = []
    private var lastCapture = -Double.infinity
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!

    func restart() {
        spare.append(contentsOf: echoes.map(\.buffer))
        echoes.removeAll()
        lastCapture = -.infinity
    }

    var echoCount: Int { echoes.count }

    func render(_ input: LensInput) -> CIImage {
        guard let matte = input.matte else { return input.composed }
        let rect = input.rect, t = input.time
        // Time running backwards means a new run (a test, or the lens picked again): forget the old copies.
        if t < lastCapture - 1e-6 { restart() }
        let expired = echoes.filter { t - $0.time > Self.lifetime }
        spare.append(contentsOf: expired.map(\.buffer))
        echoes.removeAll { t - $0.time > Self.lifetime }

        // The oldest ghost first, so the freshest sits nearest you.
        var room = input.scenery
        let enlarge = CGAffineTransform(scaleX: CGFloat(1 / scale), y: CGFloat(1 / scale)).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        for echo in echoes {
            let k = min(1, max(0, (t - echo.time) / Self.lifetime))
            let fade = 0.82 * pow(1 - k, 1.3)
            guard fade > 0.01 else { continue }
            let c = Self.fresh + (Self.old - Self.fresh) * min(1, k * 1.3)
            let ghost = CIImage(cvPixelBuffer: echo.buffer, options: [.colorSpace: space]).transformed(by: enlarge)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: CGFloat(c.x), y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: CGFloat(c.y), z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(c.z), w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(fade)),
                ])
            room = ghost.composited(over: room)
        }
        var out = input.placingPerson(over: room.cropped(to: rect))
        // A faint spectral edge on you even when you stand still, so you can tell it is on.
        if let edge = WorldKit.edgeGlow(matte: matte, rect: rect, width: 18, colour: Self.fresh, strength: 0.22) { out = WorldKit.adding(edge, to: out) }

        if t - lastCapture >= Self.interval - 1e-6 {
            capture(composed: input.composed, matte: matte, rect: rect, services: input.services, time: t)
            lastCapture = t
        }
        return out
    }

    /// Keeps a ghost of you as you are now: your brightness, flattened and lifted, with a bright glowing edge.
    private func capture(composed: CIImage, matte: CIImage, rect: CGRect, services: LensServices, time: Double) {
        let box = CGRect(x: 0, y: 0, width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
        guard let buffer = spare.popLast() ?? makeBuffer(box.size) else { return }
        let m = WorldKit.shrink(matte, rect: rect, by: scale).cropped(to: box)
        let soft = m.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: box)
        let luma = CIVector(x: 0.2126 * 0.5, y: 0.7152 * 0.5, z: 0.0722 * 0.5, w: 0)
        let grey = WorldKit.shrink(composed, rect: rect, by: scale).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": luma, "inputGVector": luma, "inputBVector": luma, "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0.32, y: 0.32, z: 0.32, w: 1),
        ])
        // The outline glows: where the sharp and soft silhouettes differ is a band either side of the edge.
        let rim = m.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: soft])
        let lit = WorldKit.adding(WorldKit.tint(rim, SIMD3(1, 1, 1), strength: 1.6), to: grey).cropped(to: box)
        let fill = lit.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .white).cropped(to: box), kCIInputMaskImageKey: m,
        ])
        let opacity = WorldKit.tint(m, SIMD3(1, 1, 1), strength: 0.8)
        let ghost = fill.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: box), kCIInputMaskImageKey: opacity.cropped(to: box),
        ]).cropped(to: box)
        services.context.render(ghost, to: buffer, bounds: box, colorSpace: space)
        echoes.append(Echo(buffer: buffer, time: time))
    }

    private func makeBuffer(_ size: CGSize) -> CVPixelBuffer? {
        var made: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any], kCVPixelBufferMetalCompatibilityKey: true]
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &made)
        return made
    }
}
