import CoreImage
import CoreImage.CIFilterBuiltins

/// The room behind you with something done to it: milky glass, lights down, film noir, or a warm evening.
///
/// Each starts from the lens blur the blur backdrops use (worked out small and enlarged, so it is cheap), then adds the
/// look: real frosting, lamps that keep glowing when the room is dimmed, light through blinds, a low sun with its flare.
/// The extras are laid out on the camera's own frame, whatever its size and wherever it starts.
final class CameraTreatmentSource: BackgroundSource {
    private let treatment: CameraTreatment
    init(_ treatment: CameraTreatment) { self.treatment = treatment }

    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        let extent = camera.extent
        guard extent.width > 1, extent.height > 1, extent.width.isFinite, extent.height.isFinite else { return nil }
        let look: CIImage?
        switch treatment {
        case .frosted: look = frosted(camera)
        case .dimmed: look = dimmed(camera)
        case .noir: look = noir(camera)
        case .golden: look = golden(camera)
        }
        return look?.cropped(to: extent)
    }

    // MARK: Looks

    /// Seen through frosted glass: very soft, lifted toward white, a little drained of colour, with the glass's own
    /// fine sandblasted texture and its uneven frosting over the top.
    private func frosted(_ camera: CIImage) -> CIImage? {
        let extent = camera.extent
        guard let soft = BackdropLens.blurred(camera, sigma: 28, bokeh: 0.35) else { return nil }
        let lifted = Self.adjusted(soft, brightness: 0.06, contrast: 0.80, saturation: 0.72)
        let milk = CIImage(color: CIColor(red: 0.93, green: 0.96, blue: 1, alpha: 0.36)).cropped(to: extent)
        var glass = milk.composited(over: lifted)
        // Frosting is never quite even: faint cloudy patches, and light catching the top of the pane.
        glass = BackdropPainter.mottle(glass, amount: 0.045, scale: 1.7, channel: 2, offset: CGPoint(x: extent.minX, y: extent.minY))
        glass = Self.wash(glass, from: CGPoint(x: extent.minX, y: extent.maxY), to: CGPoint(x: extent.minX, y: extent.midY),
                          color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.12))
        return BackdropFinish.finish(glass, grain: 2.2)
    }

    /// The lights turned down: the room falls into a warm dusk, but lamps and windows keep glowing, as they would.
    private func dimmed(_ camera: CIImage) -> CIImage? {
        guard let soft = BackdropLens.blurred(camera, sigma: 18, bokeh: 0.9) else { return nil }
        // A curve rather than a flat cut: shadows drop a long way, the brightest things only a little.
        let curve = CIFilter.toneCurve()
        curve.inputImage = soft
        curve.point0 = CGPoint(x: 0, y: 0)
        curve.point1 = CGPoint(x: 0.25, y: 0.045)
        curve.point2 = CGPoint(x: 0.5, y: 0.12)
        curve.point3 = CGPoint(x: 0.78, y: 0.34)
        curve.point4 = CGPoint(x: 1, y: 0.86)
        let low = Self.tinted(curve.outputImage ?? soft, red: 1.08, green: 0.97, blue: 0.84)
        let extent = camera.extent
        return BackdropFinish.finish(BackdropFinish.vignette(low, strength: 0.45, centre: CGPoint(x: extent.midX, y: extent.midY + extent.height * 0.06)), grain: 1.2)
    }

    /// Film noir: black and white with punch, slatted light falling across the room through blinds, deep corners, grain.
    private func noir(_ camera: CIImage) -> CIImage? {
        let extent = camera.extent
        guard let soft = BackdropLens.blurred(camera, sigma: 20, bokeh: 0.3) else { return nil }
        let grey = Self.adjusted(soft, brightness: -0.04, contrast: 1.18, saturation: 0)
        // Slats of light: soft stripes, tilted, only within a patch toward the upper right, as if the window were there.
        let stripes = CIFilter.stripesGenerator()
        stripes.color0 = CIColor(red: 1.35, green: 1.35, blue: 1.35)
        stripes.color1 = CIColor(red: 0.62, green: 0.62, blue: 0.62)
        stripes.width = Float(extent.height * 0.045)
        stripes.sharpness = 0.25
        stripes.center = .zero
        let slats = (stripes.outputImage ?? CIImage(color: .white))
            .transformed(by: CGAffineTransform(rotationAngle: .pi / 2 - 0.42))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
            .clampedToExtent().applyingGaussianBlur(sigma: extent.height * 0.006).cropped(to: extent)
        let patch = CIFilter.radialGradient()
        patch.center = CGPoint(x: extent.minX + extent.width * 0.74, y: extent.minY + extent.height * 0.66)
        patch.radius0 = Float(extent.height * 0.18)
        patch.radius1 = Float(extent.height * 0.78)
        patch.color0 = CIColor(red: 1, green: 1, blue: 1)
        patch.color1 = CIColor(red: 0, green: 0, blue: 0)
        let neutral = CIImage(color: CIColor(red: 0.8, green: 0.8, blue: 0.8)).cropped(to: extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = slats
        blend.backgroundImage = neutral
        blend.maskImage = patch.outputImage?.cropped(to: extent)
        let light = blend.outputImage?.cropped(to: extent) ?? neutral
        let lit = grey.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: light]).cropped(to: extent)
        return BackdropFinish.finish(BackdropFinish.vignette(lit, strength: 0.55, centre: CGPoint(x: extent.midX, y: extent.midY)), grain: 2.4)
    }

    /// Warm evening light: orange-leaning colour, a low sun just out of frame at the upper right with its haze and a
    /// trail of faint lens ghosts, and a warm leak of light along that edge.
    private func golden(_ camera: CIImage) -> CIImage? {
        let extent = camera.extent
        guard let soft = BackdropLens.blurred(camera, sigma: 20, bokeh: 0.8) else { return nil }
        var warm = Self.tinted(Self.adjusted(soft, brightness: 0.02, contrast: 1.04, saturation: 1.2), red: 1.14, green: 0.99, blue: 0.74)
        let sun = CGPoint(x: extent.minX + extent.width * 0.93, y: extent.minY + extent.height * 0.97)
        warm = Self.glow(warm, at: sun, radius: extent.width * 0.75, color: CIColor(red: 1, green: 0.62, blue: 0.26, alpha: 0.55))
        warm = Self.glow(warm, at: sun, radius: extent.width * 0.16, color: CIColor(red: 1, green: 0.92, blue: 0.72, alpha: 0.7))
        // Ghosts: soft discs along the line from the sun through the middle, smaller and fainter as they go.
        let middle = CGPoint(x: extent.midX, y: extent.midY)
        for (t, size, alpha) in [(0.55, 0.035, 0.10), (0.95, 0.06, 0.07), (1.32, 0.025, 0.10), (1.6, 0.09, 0.05)] {
            let at = CGPoint(x: sun.x + (middle.x - sun.x) * t, y: sun.y + (middle.y - sun.y) * t)
            warm = Self.disc(warm, at: at, radius: extent.width * size, color: CIColor(red: 1, green: 0.78, blue: 0.5, alpha: alpha))
        }
        // A warm leak along the right edge.
        warm = Self.wash(warm, from: CGPoint(x: extent.maxX, y: extent.midY), to: CGPoint(x: extent.maxX - extent.width * 0.3, y: extent.midY),
                         color: CIColor(red: 1, green: 0.45, blue: 0.3, alpha: 0.22))
        return BackdropFinish.finish(warm, grain: 1.0)
    }

    // MARK: Pieces

    private static func adjusted(_ image: CIImage, brightness: Float, contrast: Float, saturation: Float) -> CIImage {
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.brightness = brightness
        controls.contrast = contrast
        controls.saturation = saturation
        return controls.outputImage ?? image
    }

    /// Scales each colour channel, which is how a warm or cool cast is made.
    private static func tinted(_ image: CIImage, red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: red, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: green, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: blue, w: 0)
        return matrix.outputImage ?? image
    }

    /// Light added in a soft round pool (screen blend, so it brightens without blowing out).
    private static func glow(_ image: CIImage, at centre: CGPoint, radius: CGFloat, color: CIColor) -> CIImage {
        let g = CIFilter.radialGradient()
        g.center = centre
        g.radius0 = 0
        g.radius1 = Float(radius)
        g.color0 = color
        g.color1 = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        guard let layer = g.outputImage?.cropped(to: image.extent) else { return image }
        return layer.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: image.extent)
    }

    /// A lens ghost: a soft-edged disc of light.
    private static func disc(_ image: CIImage, at centre: CGPoint, radius: CGFloat, color: CIColor) -> CIImage {
        let g = CIFilter.radialGradient()
        g.center = centre
        g.radius0 = Float(radius * 0.78)
        g.radius1 = Float(radius)
        g.color0 = color
        g.color1 = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        guard let layer = g.outputImage?.cropped(to: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)) else { return image }
        return layer.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: image.extent)
    }

    /// A straight wash of light, strongest at `from`, gone by `to`.
    private static func wash(_ image: CIImage, from: CGPoint, to: CGPoint, color: CIColor) -> CIImage {
        let g = CIFilter.smoothLinearGradient()
        g.point0 = from
        g.point1 = to
        g.color0 = color
        g.color1 = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        guard let layer = g.outputImage?.cropped(to: image.extent) else { return image }
        return layer.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: image.extent)
    }
}
