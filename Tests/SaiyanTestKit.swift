import CoreGraphics
import CoreImage
import XCTest

/// Runs the pieces of the Dragon Ball lens frame by frame over the synthetic scene, composed the way the finished lens composes them, so
/// a piece can be tried and looked at before the lens exists. Pictures are saved when `BACKDROP_TEST_OUTPUT` is set (see `Output`).
final class SaiyanBench {
    let h = LensHarness()
    let scene: SyntheticScene
    private let plain: LensInput
    var gestures = HandGestureRecognizer()
    private(set) var time = 0.0
    /// What the gesture recogniser reported on the latest frame.
    private(set) var events: [HandGesture] = []

    init(scene: SyntheticScene = SyntheticScene()) {
        self.scene = scene
        plain = h.input(scene)
    }

    var rect: CGRect { plain.rect }
    var face: FaceState? { plain.face }

    /// The synthetic frame with cartoon hands painted into the picture and into the cutout, so they are part of "the person".
    func input(hands: [HandState] = [], face: Bool = true) -> LensInput {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        func context(gray: Bool) -> CGContext {
            gray ? CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                 : CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
        }
        let skin = context(gray: false), mask = context(gray: true)
        mask.setFillColor(gray: 0, alpha: 1)
        mask.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
        for (ctx, colour) in [(skin, CGColor(red: 0.93, green: 0.74, blue: 0.62, alpha: 1)), (mask, CGColor(gray: 1, alpha: 1))] {
            ctx.setFillColor(colour)
            ctx.setStrokeColor(colour)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for hand in hands {
                ctx.setLineWidth(hand.size * 0.26)
                let palm = CGMutablePath()
                palm.move(to: hand.wrist)
                for joint in [HandJoint.thumbCMC, .indexMCP, .middleMCP, .ringMCP, .littleMCP] { palm.addLine(to: hand[joint]) }
                palm.closeSubpath()
                ctx.addPath(palm)
                ctx.drawPath(using: .fillStroke)
                for finger in Finger.allCases {
                    ctx.setLineWidth(hand.size * (finger == .thumb ? 0.27 : 0.21))
                    ctx.beginPath()
                    ctx.move(to: hand[finger.knuckle])
                    ctx.addLine(to: hand[finger.middleJoint])
                    ctx.addLine(to: hand[HandJoint(rawValue: finger.middleJoint.rawValue + 1) ?? finger.tip])
                    ctx.addLine(to: hand[finger.tip])
                    ctx.strokePath()
                }
            }
        }
        var picture = plain.composed, matte = plain.matte
        if !hands.isEmpty, let drawn = skin.makeImage(), let cut = mask.makeImage() {
            picture = CIImage(cgImage: drawn).composited(over: plain.composed)
            let handMatte = CIImage(cgImage: cut)
            matte = plain.matte.map { handMatte.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: $0]).cropped(to: plain.rect) } ?? handMatte
        }
        return LensInput(time: time, dt: 1.0 / 30, rect: plain.rect, camera: picture, matte: matte, background: plain.background, composed: picture,
                         matteGrid: plain.matteGrid, face: face ? plain.face : nil, services: plain.services, hands: hands)
    }

    /// One frame's context for the moves: moves the clock on by `dt`, feeds the gesture recogniser, and reports what it saw.
    func context(hands: [HandState], form: SaiyanForm = .superSaiyan, power: Double? = nil, face withFace: Bool = true,
                 dt: Double = 1.0 / 30) -> SaiyanMoveContext {
        time += dt
        events = gestures.update(hands, dt: dt)
        return SaiyanMoveContext(hands: hands, gestures: gestures, events: events, face: withFace ? face : nil,
                                 personCenter: withFace ? scene.center : nil, form: form, power: power ?? form.power, dt: dt, time: time, rect: rect)
    }

    /// Runs the moves one frame and returns the finished picture: person, hands, the moves' light, and the whole-picture effects.
    @discardableResult
    func step(_ set: SaiyanMoveSet, hands: [HandState], form: SaiyanForm = .superSaiyan, blocked: Bool = false, face withFace: Bool = true,
              dt: Double = 1.0 / 30) -> CIImage {
        let c = context(hands: hands, form: form, face: withFace, dt: dt)
        set.update(c, blocked: blocked)
        let frame = input(hands: hands, face: withFace)
        let effect = set.screenEffect
        var layer = SaiyanCompose.person(frame, over: frame.scenery, effect: effect)
        layer = SaiyanCompose.moves(set, over: layer, input: frame)
        return SaiyanCompose.screen(effect, over: layer, rect: frame.rect, time: time)
    }

    /// Several seconds of the same hands, for holding a pose. Returns the last picture.
    @discardableResult
    func hold(_ set: SaiyanMoveSet, _ hands: [HandState], seconds: Double, form: SaiyanForm = .superSaiyan, face withFace: Bool = true) -> CIImage {
        var out = plain.composed
        for _ in 0..<max(1, Int((seconds * 30).rounded())) { out = step(set, hands: hands, form: form, face: withFace) }
        return out
    }

    /// Pictures laid out on a grid, each shrunk by `scale`, for a contact sheet.
    static func sheet(_ images: [CIImage], columns: Int, scale: Double = 0.5) -> CIImage {
        let w = 1280 * scale, hgt = 720 * scale
        var out = CIImage(color: CIColor(red: 0.05, green: 0.05, blue: 0.07)).cropped(to: CGRect(x: 0, y: 0, width: w * Double(columns),
                                                                                       height: hgt * Double(max(1, (images.count + columns - 1) / columns))))
        let rows = max(1, (images.count + columns - 1) / columns)
        for (i, image) in images.enumerated() {
            let col = i % columns, row = i / columns
            let moved = image.cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: w * Double(col), y: hgt * Double(rows - 1 - row))))
            out = moved.composited(over: out)
        }
        return out
    }
}
