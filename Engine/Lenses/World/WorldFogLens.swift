import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Fog rolling in: banks of mist drift slowly through the room behind you, a low layer creeps across in front and parts round
/// you, and a cold lamp somewhere behind lights the haze and the edge of your silhouette.
///
/// All of it is soft noise worked out at quarter size on the graphics chip: two sizes of cloud drifting at different speeds,
/// stretched sideways into banks, thicker toward the floor.
final class WorldFogLens: Lens {
    let needs: LensNeeds = [.matte]

    /// "Moor": the fog's own colour, the cold lamp behind it, and the dim room.
    static let mist = SIMD3<Double>(0.66, 0.72, 0.78)
    static let lamp = SIMD3<Double>(0.78, 0.87, 1.0)

    /// How thick the fog is right now, 0.75...1: it thickens and thins over a minute.
    static func thickness(at t: Double) -> Double { 0.87 + 0.09 * sin(t * 0.13) + 0.04 * sin(t * 0.41 + 2) }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect, t = input.time
        let scale = 0.25
        let box = CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale)
        let thick = Self.thickness(at: t)

        // The room, drained and grey-blue, its darks lifted by the haze.
        var room = WorldKit.grade(input.scenery, saturation: 0.5, tint: (0.46, 0.5, 0.56), lift: (0.012, 0.014, 0.018))
        let lampAt = CGPoint(x: rect.width * 0.74, y: rect.height * 0.86)
        room = WorldKit.adding(WorldKit.wash(center: lampAt, radius: 420, red: Self.lamp.x, green: Self.lamp.y, blue: Self.lamp.z, alpha: 0.3, in: rect), to: room)

        // Far banks: big and slow, thickest low down, lit brighter near the lamp.
        let far = density(box: box, time: t, grain: 52, speed: -9, low: 0.36, high: 0.74, seed: 0)
        let farFall = verticalFade(box: box, bottom: 1, top: 0.35, height: 1)
        let farDensity = WorldKit.multiply(far, farFall)
        let lampGlow = WorldKit.wash(center: CGPoint(x: lampAt.x * scale, y: lampAt.y * scale), radius: 140, red: 1, green: 1, blue: 1, alpha: 0.55, in: box)
        let farColour = WorldKit.adding(WorldKit.tint(lampGlow.settingAlphaOne(in: box), Self.lamp, strength: 0.6),
                                        to: CIImage(color: colour(Self.mist * 0.82)).cropped(to: box))
        room = over(room, colour: farColour, density: farDensity, strength: 0.78 * thick, rect: rect, box: box)

        let person = WorldKit.grade(input.composed, saturation: 0.75, tint: (0.66, 0.7, 0.76), lift: (0.008, 0.009, 0.012))
        var body = WorldKit.place(person: person, over: room, matte: input.matte, rect: rect)
        // Lit from behind: a cold edge all round, strongest on the side toward the lamp.
        if let edge = WorldKit.edgeGlow(matte: input.matte, rect: rect, width: 22, colour: Self.lamp, strength: 0.22) { body = WorldKit.adding(edge, to: body) }
        if let rim = WorldKit.rimLight(matte: input.matte, rect: rect, toward: simd_normalize(SIMD2(0.6, 0.8)), width: 12, colour: Self.lamp, strength: 0.4) {
            body = WorldKit.adding(rim, to: body)
        }

        // Near fog: a low creeping layer in front of everything, which thins where you are, so you stand in it.
        let near = density(box: box, time: t, grain: 34, speed: -26, low: 0.34, high: 0.72, seed: 900)
        var nearDensity = WorldKit.multiply(near, verticalFade(box: box, bottom: 1, top: 0, height: 0.55))
        if let matte = input.matte {
            let you = WorldKit.halo(matte: matte, rect: rect, sigma: 36, grow: 16)
            nearDensity = WorldKit.multiply(nearDensity, WorldKit.inverted(WorldKit.tint(you, SIMD3(1, 1, 1), strength: 0.5)))
        }
        body = over(body, colour: CIImage(color: colour(Self.mist)).cropped(to: box), density: nearDensity, strength: 0.85 * thick, rect: rect, box: box)
        return body.cropped(to: rect)
    }

    private func colour(_ c: SIMD3<Double>) -> CIColor { CIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z)) }

    /// Two sizes of soft cloud drifting sideways at different speeds, mixed and stretched into banks, then shaped so there are
    /// clear gaps between them.
    private func density(box: CGRect, time t: Double, grain: Double, speed: Double, low: Double, high: Double, seed: Double) -> CIImage {
        let big = WorldKit.clouds(box, grain: grain, offset: CGPoint(x: t * speed + seed, y: t * 0.8), stretch: CGSize(width: 4.5, height: 1))
        let small = WorldKit.clouds(box, grain: grain * 0.45, offset: CGPoint(x: t * speed * 1.7 + seed * 1.3, y: -t * 1.2), stretch: CGSize(width: 3, height: 1))
        let mixed = WorldKit.adding(WorldKit.tint(big, SIMD3(1, 1, 1), strength: 0.65), to: WorldKit.tint(small, SIMD3(1, 1, 1), strength: 0.35))
        return WorldKit.levels(mixed.cropped(to: box), low: low, high: high)
    }

    /// 1 at the bottom of the picture fading to `top` at `height` (a fraction of the picture) and above.
    private func verticalFade(box: CGRect, bottom: Double, top: Double, height: Double) -> CIImage {
        let g = CIFilter.linearGradient()
        g.point0 = CGPoint(x: 0, y: 0)
        g.point1 = CGPoint(x: 0, y: box.height * height)
        g.color0 = CIColor(red: CGFloat(bottom), green: CGFloat(bottom), blue: CGFloat(bottom))
        g.color1 = CIColor(red: CGFloat(top), green: CGFloat(top), blue: CGFloat(top))
        return (g.outputImage ?? CIImage.empty()).cropped(to: box)
    }

    /// Lays fog of a colour over a picture, as thick as `density` says (at quarter size), times `strength`.
    private func over(_ image: CIImage, colour: CIImage, density: CIImage, strength: Double, rect: CGRect, box: CGRect) -> CIImage {
        let mask = WorldKit.enlarge(WorldKit.tint(density, SIMD3(1, 1, 1), strength: strength).settingAlphaOne(in: box), rect: rect, from: 0.25)
        let fog = WorldKit.enlarge(colour.settingAlphaOne(in: box), rect: rect, from: 0.25)
        return fog.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask]).cropped(to: rect)
    }
}
