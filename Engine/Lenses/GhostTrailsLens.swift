import CoreImage
import CoreImage.CIFilterBuiltins

/// Echoes of where you just were, fading and drifting off behind you.
final class GhostTrailsLens: Lens {
    let needs: LensNeeds = [.matte]

    private var trail: CVPixelBuffer?
    private let decay = 0.84
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!

    func restart() { trail = nil }

    func render(_ input: LensInput) -> CIImage {
        guard let matte = input.matte else { return input.composed }
        let rect = input.rect

        // What was left behind: last frame's trail, a little larger and lifted, and fainter.
        var echo = input.clear
        if let trail {
            let about = CGAffineTransform(translationX: -rect.midX, y: -rect.midY)
                .concatenating(CGAffineTransform(scaleX: 1.012, y: 1.012))
                .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY + 2.5))
            echo = CIImage(cvPixelBuffer: trail, options: [.colorSpace: space])
                .transformed(by: about).fading(decay).cropped(to: rect)
        }

        // Remember the person, in a ghostly wash that slowly turns through the colours.
        let blend = CIFilter.blendWithMask()
        blend.inputImage = input.composed
        blend.backgroundImage = input.clear
        blend.maskImage = matte
        let ghost = (blend.outputImage ?? input.clear)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.55, kCIInputBrightnessKey: 0.12])
            .applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: input.time * 0.9])
        let remembered = ghost.composited(over: echo).cropped(to: rect)
        if let next = input.services.makeBuffer() {
            input.services.context.render(remembered, to: next, bounds: rect, colorSpace: space)
            trail = next
        }

        // Echoes sit behind the person, in front of the room.
        return input.placingPerson(over: echo.composited(over: input.scenery))
    }
}
