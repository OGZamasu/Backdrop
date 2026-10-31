import CoreGraphics
import CoreImage
import Foundation

/// What the mannequin is doing at one moment: where it leans, what its face does, where its hands are.
struct LensBrowserPose: Equatable {
    /// Slides the whole person, in output pixels.
    var offset = CGVector.zero
    /// Tips the whole person, radians counter-clockwise, about a point below the picture (as a body sways from the hips).
    var lean = 0.0
    var mouthOpen = 0.0
    var browRaise = 0.0
    var smile = 0.0
    var blink = 0.0
    /// Raised hands, in output pixels. The arms are drawn up to them from the shoulders.
    var hands: [LensBrowserHand] = []
}

/// A drawn person in a studio, to try lenses on with no camera and no Vision: a soft backdrop, shoulders in a coral jumper, a
/// head with short dark hair, and a face whose eyes, brows and mouth are drawn from the same numbers it reports as a `FaceState`,
/// so a lens that puts something on the nose puts it on the nose.
///
/// Light comes from the top left everywhere. The face keeps the proportions of the test scene (`SyntheticScene`) that every
/// face lens is tuned against, a little larger so a face still reads in a small thumbnail.
///
/// Not thread-safe: each renderer owns one.
final class LensBrowserMannequin {
    static let size = CGSize(width: 1280, height: 720)
    /// Head size against the test scene's.
    static let scale = 1.15
    static let headCenter = CGPoint(x: 640, y: 396)
    /// What the body sways about.
    static let pivot = CGPoint(x: 640, y: -260)

    /// The studio backdrop the person stands in front of, as a lens is handed it.
    let backdrop: CIImage
    /// The room behind the person as the camera sees it; also the backdrop for lenses that restyle the whole picture.
    let room: CIImage

    private let torso: CIImage
    private var heads: [String: CIImage] = [:]
    private let limbs: CGContext?
    private let rect = CGRect(origin: .zero, size: LensBrowserMannequin.size)

    init() {
        backdrop = Self.image(Self.size) { Self.drawBackdrop($0) } ?? CIImage(color: LensBrowserPaint.ciDusk).cropped(to: CGRect(origin: .zero, size: Self.size))
        room = Self.image(Self.size) { Self.drawRoom($0) } ?? CIImage(color: .gray).cropped(to: CGRect(origin: .zero, size: Self.size))
        // The body's layer reaches well below the picture, so a lean never lifts its hem into view.
        let torsoBox = CGRect(x: 200, y: -340, width: 880, height: 700)
        torso = (Self.image(torsoBox.size) { ctx in
            ctx.translateBy(x: -torsoBox.minX, y: -torsoBox.minY)
            Self.drawTorso(ctx)
        } ?? CIImage.empty()).transformed(by: CGAffineTransform(translationX: torsoBox.minX, y: torsoBox.minY))
        limbs = CGContext(data: nil, width: Int(Self.size.width), height: Int(Self.size.height), bitsPerComponent: 8, bytesPerRow: 0,
                          space: LensBrowserPaint.space, bitmapInfo: Sprites.bitmapInfo)
        limbs?.setAllowsAntialiasing(true)
    }

    struct Frame {
        /// The person over the room, as a camera would see it.
        let camera: CIImage
        /// White where the person is, black elsewhere, before the pipeline's edge softening.
        let mask: CIImage
        let face: FaceState
        let hands: [HandState]
    }

    /// The transform that sways the body for a pose.
    static func sway(_ pose: LensBrowserPose) -> CGAffineTransform {
        CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(rotationAngle: pose.lean))
            .concatenating(CGAffineTransform(translationX: pivot.x + pose.offset.dx, y: pivot.y + pose.offset.dy))
    }

    /// Where the face is, drawn and reported from the same numbers.
    static func face(for pose: LensBrowserPose) -> FaceState {
        let s = scale, t = sway(pose)
        let io = 84 * s, eyeHeight = 20 * s
        let browDistance = 0.40 + 0.28 * pose.browRaise
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: headCenter.x + x, y: headCenter.y + y).applying(t) }
        let centre = at(0, 0)
        return FaceState(leftEye: at(-io / 2, eyeHeight), rightEye: at(io / 2, eyeHeight), mouth: at(0, -60 * s),
                         mouthWidth: 70 * s * (1 + 0.35 * pose.smile), browCenter: at(0, eyeHeight + io * browDistance),
                         rect: CGRect(x: centre.x - 95 * s, y: centre.y - 120 * s, width: 190 * s, height: 240 * s),
                         mouthOpen: pose.mouthOpen, browRaise: pose.browRaise, browDistance: browDistance,
                         blink: pose.blink, smile: pose.smile)
    }

    func frame(_ pose: LensBrowserPose) -> Frame {
        let t = Self.sway(pose)
        var person = head(pose).composited(over: torso).transformed(by: t)
        if !pose.hands.isEmpty, let limbs {
            limbs.clear(rect)
            for hand in pose.hands { Self.drawArm(limbs, hand: hand, sway: t) }
            for hand in pose.hands { Self.drawHand(limbs, hand: hand) }
            if let picture = limbs.makeImage() { person = CIImage(cgImage: picture).composited(over: person) }
        }
        person = person.cropped(to: rect)
        let camera = person.composited(over: room).cropped(to: rect)
        let mask = person.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).composited(over: CIImage(color: .black)).cropped(to: rect)
        return Frame(camera: camera, mask: mask, face: Self.face(for: pose), hands: pose.hands.map { $0.state() })
    }

    // MARK: - Layers

    /// The head for an expression, drawn once and kept (expressions are rounded so a slow change reuses a few drawings).
    private func head(_ pose: LensBrowserPose) -> CIImage {
        func q(_ v: Double) -> Double { (min(1, max(0, v)) * 20).rounded() / 20 }
        let expression = (mouth: q(pose.mouthOpen), brow: q(pose.browRaise), smile: q(pose.smile), blink: q(pose.blink))
        let key = "\(expression.mouth)|\(expression.brow)|\(expression.smile)|\(expression.blink)"
        if let hit = heads[key] { return hit }
        let s = Self.scale
        let box = CGRect(x: -140 * s, y: -150 * s, width: 280 * s, height: 330 * s).integral
        let image = (Self.image(box.size) { ctx in
            ctx.translateBy(x: -box.minX, y: -box.minY)
            Self.drawHead(ctx, mouthOpen: expression.mouth, browRaise: expression.brow, smile: expression.smile, blink: expression.blink)
        } ?? CIImage.empty()).transformed(by: CGAffineTransform(translationX: Self.headCenter.x + box.minX, y: Self.headCenter.y + box.minY))
        if heads.count > 24 { heads.removeAll() }
        heads[key] = image
        return image
    }

    private static func image(_ size: CGSize, _ draw: (CGContext) -> Void) -> CIImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width.rounded(.up)), height: Int(size.height.rounded(.up)), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: LensBrowserPaint.space, bitmapInfo: Sprites.bitmapInfo) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        draw(ctx)
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }

    // MARK: - Studio

    private static func drawBackdrop(_ ctx: CGContext) {
        let w = size.width, h = size.height
        // A deep dusk-blue paper sweep, lit from the top left.
        ctx.drawLinearGradient(LensBrowserPaint.gradient([LensBrowserPaint.duskHigh, LensBrowserPaint.duskMid, LensBrowserPaint.duskLow], [0, 0.55, 1]),
                               start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // Warm key light spilling across the top left.
        ctx.drawRadialGradient(LensBrowserPaint.gradient([LensBrowserPaint.rgb(1.0, 0.72, 0.56, 0.34), LensBrowserPaint.rgb(1.0, 0.72, 0.56, 0)], [0, 1]),
                               startCenter: CGPoint(x: 170, y: 700), startRadius: 0, endCenter: CGPoint(x: 170, y: 700), endRadius: 760, options: [])
        // Out-of-focus lights, varied in size and tint.
        let bokeh: [(x: Double, y: Double, r: Double, c: CGColor)] = [
            (120, 560, 54, LensBrowserPaint.rgb(1.0, 0.80, 0.55, 0.16)), (250, 655, 30, LensBrowserPaint.rgb(1.0, 0.70, 0.75, 0.15)),
            (330, 470, 22, LensBrowserPaint.rgb(0.75, 0.85, 1.0, 0.12)), (1010, 640, 46, LensBrowserPaint.rgb(0.70, 0.80, 1.0, 0.12)),
            (1150, 520, 64, LensBrowserPaint.rgb(0.95, 0.65, 0.95, 0.10)), (1080, 380, 26, LensBrowserPaint.rgb(1.0, 0.85, 0.65, 0.10)),
            (180, 330, 34, LensBrowserPaint.rgb(0.80, 0.70, 1.0, 0.09)), (930, 520, 18, LensBrowserPaint.rgb(1.0, 1.0, 1.0, 0.10)),
        ]
        for b in bokeh {
            let c = CGPoint(x: b.x, y: b.y)
            ctx.drawRadialGradient(LensBrowserPaint.gradient([b.c, b.c, b.c.copy(alpha: 0) ?? b.c], [0, 0.72, 1]), startCenter: c, startRadius: 0,
                                   endCenter: c, endRadius: b.r, options: [])
        }
        // The person's soft shadow on the sweep, falling down and to the right, away from the light.
        ctx.saveGState()
        ctx.translateBy(x: 690, y: 110); ctx.scaleBy(x: 1.9, y: 0.95)
        ctx.drawRadialGradient(LensBrowserPaint.gradient([LensBrowserPaint.rgb(0.02, 0.02, 0.10, 0.42), LensBrowserPaint.rgb(0.02, 0.02, 0.10, 0)], [0, 1]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 250, options: [])
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: 672, y: 392); ctx.scaleBy(x: 1, y: 1.2)
        ctx.drawRadialGradient(LensBrowserPaint.gradient([LensBrowserPaint.rgb(0.02, 0.02, 0.10, 0.30), LensBrowserPaint.rgb(0.02, 0.02, 0.10, 0)], [0, 1]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 190, options: [])
        ctx.restoreGState()
        // A gentle vignette to hold the eye in the middle.
        ctx.saveGState()
        ctx.translateBy(x: w / 2, y: h / 2); ctx.scaleBy(x: w / h, y: 1)
        ctx.drawRadialGradient(LensBrowserPaint.gradient([LensBrowserPaint.rgb(0, 0, 0, 0), LensBrowserPaint.rgb(0.01, 0.0, 0.06, 0.38)], [0.55, 1]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: h * 0.62, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// A cosy room, for the camera's own view and as the backdrop for lenses that restyle the whole picture (a comic, a
    /// painting), which need real shapes to work on: a sage wall, a window with a mustard curtain, a lamp, a shelf of books,
    /// a framed print and a big leafy plant.
    private static func drawRoom(_ ctx: CGContext) {
        typealias C = LensBrowserPaint
        let w = size.width, h = size.height
        // Wall, lit from the window on the left, with a skirting board.
        ctx.drawLinearGradient(C.gradient([C.rgb(0.66, 0.76, 0.70), C.rgb(0.47, 0.58, 0.55), C.rgb(0.30, 0.38, 0.38)], [0, 0.55, 1]),
                               start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
        ctx.drawRadialGradient(C.gradient([C.rgb(1, 0.92, 0.78, 0.35), C.rgb(1, 0.92, 0.78, 0)], [0, 1]),
                               startCenter: CGPoint(x: 220, y: 430), startRadius: 0, endCenter: CGPoint(x: 220, y: 430), endRadius: 560, options: [])
        ctx.setFillColor(C.rgb(0.88, 0.86, 0.80)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: 46))
        ctx.setFillColor(C.rgb(0.40, 0.30, 0.24)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: 30))

        // The window: daylight sky, a far hill, cream frame and bars.
        let window = CGRect(x: 70, y: 250, width: 270, height: 360)
        ctx.setFillColor(C.rgb(0.93, 0.91, 0.85)); ctx.fill(window.insetBy(dx: -14, dy: -14))
        ctx.saveGState(); ctx.clip(to: window)
        ctx.drawLinearGradient(C.gradient([C.rgb(0.52, 0.74, 0.95), C.rgb(0.86, 0.92, 0.97), C.rgb(1.0, 0.90, 0.78)], [0, 0.65, 1]),
                               start: CGPoint(x: 0, y: window.maxY), end: CGPoint(x: 0, y: window.minY), options: [])
        let hill = CGMutablePath()
        hill.move(to: CGPoint(x: window.minX, y: window.minY + 70))
        hill.addCurve(to: CGPoint(x: window.maxX, y: window.minY + 110), control1: CGPoint(x: window.minX + 90, y: window.minY + 150),
                      control2: CGPoint(x: window.minX + 170, y: window.minY + 60))
        hill.addLine(to: CGPoint(x: window.maxX, y: window.minY)); hill.addLine(to: CGPoint(x: window.minX, y: window.minY)); hill.closeSubpath()
        ctx.addPath(hill); ctx.setFillColor(C.rgb(0.45, 0.66, 0.46)); ctx.fillPath()
        ctx.fillCircle(center: CGPoint(x: window.minX + 200, y: window.maxY - 80), radius: 26, color: C.rgb(1, 0.97, 0.85, 0.9))
        ctx.restoreGState()
        ctx.setFillColor(C.rgb(0.93, 0.91, 0.85))
        ctx.fill(CGRect(x: window.midX - 6, y: window.minY, width: 12, height: window.height))
        ctx.fill(CGRect(x: window.minX, y: window.midY - 6, width: window.width, height: 12))
        // A mustard curtain gathered at the side, with folds.
        let curtain = CGMutablePath()
        curtain.move(to: CGPoint(x: 20, y: 640)); curtain.addLine(to: CGPoint(x: 150, y: 640))
        curtain.addCurve(to: CGPoint(x: 96, y: 330), control1: CGPoint(x: 150, y: 520), control2: CGPoint(x: 100, y: 430))
        curtain.addCurve(to: CGPoint(x: 120, y: 40), control1: CGPoint(x: 92, y: 230), control2: CGPoint(x: 126, y: 120))
        curtain.addLine(to: CGPoint(x: 20, y: 40)); curtain.closeSubpath()
        ctx.saveGState(); ctx.addPath(curtain); ctx.clip()
        ctx.drawLinearGradient(C.gradient([C.rgb(0.98, 0.78, 0.36), C.rgb(0.82, 0.56, 0.20)], [0, 1]),
                               start: CGPoint(x: 20, y: 600), end: CGPoint(x: 150, y: 100), options: [])
        ctx.setStrokeColor(C.rgb(0.62, 0.38, 0.10, 0.35)); ctx.setLineWidth(6); ctx.setLineCap(.round)
        for x in [52.0, 84] { ctx.move(to: CGPoint(x: x, y: 630)); ctx.addCurve(to: CGPoint(x: x + 10, y: 50), control1: CGPoint(x: x + 14, y: 420), control2: CGPoint(x: x - 10, y: 220)); ctx.strokePath() }
        ctx.restoreGState()
        ctx.setFillColor(C.rgb(0.40, 0.30, 0.24)); ctx.fill(CGRect(x: 10, y: 640, width: 360, height: 10))

        // A framed print: a sunset over the sea.
        let print = CGRect(x: 960, y: 470, width: 200, height: 150)
        ctx.setFillColor(C.rgb(0.25, 0.20, 0.18)); ctx.fill(print.insetBy(dx: -10, dy: -10))
        ctx.saveGState(); ctx.clip(to: print)
        ctx.drawLinearGradient(C.gradient([C.rgb(0.98, 0.52, 0.42), C.rgb(1.0, 0.80, 0.50)], [0, 1]),
                               start: CGPoint(x: 0, y: print.maxY), end: CGPoint(x: 0, y: print.midY), options: [])
        ctx.fillCircle(center: CGPoint(x: print.midX + 30, y: print.midY + 6), radius: 26, color: C.rgb(1, 0.95, 0.70))
        ctx.setFillColor(C.rgb(0.20, 0.42, 0.62)); ctx.fill(CGRect(x: print.minX, y: print.minY, width: print.width, height: print.height * 0.45))
        ctx.restoreGState()

        // A shelf of books with a little plant.
        ctx.setFillColor(C.rgb(0.52, 0.36, 0.24)); ctx.fill(CGRect(x: 930, y: 360, width: 300, height: 16))
        let books: [(Double, Double, Double, CGColor)] = [
            (944, 22, 86, C.rgb(0.80, 0.30, 0.28)), (968, 18, 72, C.rgb(0.20, 0.40, 0.58)), (988, 26, 94, C.rgb(0.95, 0.75, 0.30)),
            (1016, 20, 80, C.rgb(0.32, 0.52, 0.40)), (1038, 16, 66, C.rgb(0.90, 0.88, 0.82)), (1056, 24, 88, C.rgb(0.55, 0.32, 0.52)),
        ]
        for (x, width, height, colour) in books {
            ctx.setFillColor(colour); ctx.fill(CGRect(x: x, y: 376, width: width, height: height))
            ctx.setFillColor(C.rgb(1, 1, 1, 0.25)); ctx.fill(CGRect(x: x + 3, y: 376 + height - 16, width: width - 6, height: 4))
        }
        ctx.setFillColor(C.rgb(0.80, 0.45, 0.30)); ctx.fill(CGRect(x: 1130, y: 376, width: 48, height: 40))
        for (dx, dy, r) in [(-14.0, 52.0, 18.0), (12, 60, 20), (0, 74, 16), (22, 44, 14), (-24, 38, 13)] {
            ctx.fillCircle(center: CGPoint(x: 1154 + dx, y: 376 + dy), radius: r, color: C.rgb(0.25, 0.55, 0.32))
        }

        // A tall leafy plant in a terracotta pot in the corner.
        let leaves: [(x: Double, y: Double, angle: Double, length: Double)] = [
            (1180, 240, 0.5, 150), (1220, 250, -0.2, 170), (1150, 200, 1.0, 140), (1240, 190, -0.7, 150), (1190, 300, 0.1, 140),
        ]
        for leaf in leaves {
            ctx.saveGState()
            ctx.translateBy(x: leaf.x, y: leaf.y); ctx.rotate(by: leaf.angle)
            let shape = CGMutablePath()
            shape.move(to: .zero)
            shape.addCurve(to: CGPoint(x: 0, y: leaf.length), control1: CGPoint(x: -leaf.length * 0.45, y: leaf.length * 0.35), control2: CGPoint(x: -leaf.length * 0.2, y: leaf.length * 0.9))
            shape.addCurve(to: .zero, control1: CGPoint(x: leaf.length * 0.2, y: leaf.length * 0.9), control2: CGPoint(x: leaf.length * 0.45, y: leaf.length * 0.35))
            ctx.addPath(shape); ctx.setFillColor(C.rgb(0.18, 0.46, 0.30)); ctx.fillPath()
            ctx.setStrokeColor(C.rgb(0.40, 0.66, 0.42, 0.8)); ctx.setLineWidth(3)
            ctx.move(to: .zero); ctx.addLine(to: CGPoint(x: 0, y: leaf.length * 0.92)); ctx.strokePath()
            ctx.restoreGState()
        }
        let pot = CGMutablePath()
        pot.move(to: CGPoint(x: 1140, y: 160)); pot.addLine(to: CGPoint(x: 1270, y: 160))
        pot.addLine(to: CGPoint(x: 1250, y: 30)); pot.addLine(to: CGPoint(x: 1160, y: 30)); pot.closeSubpath()
        ctx.saveGState(); ctx.addPath(pot); ctx.clip()
        ctx.drawLinearGradient(C.gradient([C.rgb(0.86, 0.50, 0.34), C.rgb(0.62, 0.32, 0.22)], [0, 1]),
                               start: CGPoint(x: 1140, y: 160), end: CGPoint(x: 1270, y: 30), options: [])
        ctx.restoreGState()

        // A table lamp glowing at the left.
        ctx.drawRadialGradient(C.gradient([C.rgb(1, 0.86, 0.55, 0.55), C.rgb(1, 0.86, 0.55, 0)], [0, 1]),
                               startCenter: CGPoint(x: 330, y: 210), startRadius: 0, endCenter: CGPoint(x: 330, y: 210), endRadius: 170, options: [])
        ctx.setFillColor(C.rgb(0.45, 0.32, 0.25)); ctx.fill(CGRect(x: 250, y: 40, width: 170, height: 90))
        ctx.setFillColor(C.rgb(0.35, 0.25, 0.20)); ctx.fill(CGRect(x: 326, y: 130, width: 8, height: 50))
        let shade = CGMutablePath()
        shade.move(to: CGPoint(x: 290, y: 180)); shade.addLine(to: CGPoint(x: 370, y: 180))
        shade.addLine(to: CGPoint(x: 352, y: 250)); shade.addLine(to: CGPoint(x: 308, y: 250)); shade.closeSubpath()
        ctx.addPath(shade); ctx.setFillColor(C.rgb(1, 0.92, 0.72)); ctx.fillPath()

        // The person's soft shadow on the wall behind them.
        ctx.saveGState()
        ctx.translateBy(x: 690, y: 120); ctx.scaleBy(x: 1.8, y: 1)
        ctx.drawRadialGradient(C.gradient([C.rgb(0.10, 0.14, 0.14, 0.35), C.rgb(0.10, 0.14, 0.14, 0)], [0, 1]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 260, options: [])
        ctx.restoreGState()
    }

    // MARK: - Body

    /// Where the shoulders are, for hanging the arms from.
    static let shoulderSpan = 232.0, shoulderHeight = 168.0

    private static func drawTorso(_ ctx: CGContext) {
        typealias C = LensBrowserPaint
        let cx = 640.0
        // Neck, shaded under the jaw.
        let neck = CGPath(roundedRect: CGRect(x: cx - 44, y: 150, width: 88, height: 190), cornerWidth: 30, cornerHeight: 30, transform: nil)
        ctx.saveGState()
        ctx.addPath(neck); ctx.clip()
        ctx.drawLinearGradient(C.gradient([C.skin, C.skinShade], [0, 1]), start: CGPoint(x: cx - 44, y: 300),
                               end: CGPoint(x: cx + 44, y: 220), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.saveGState()
        ctx.translateBy(x: cx + 4, y: 268); ctx.scaleBy(x: 1.5, y: 0.75)
        ctx.drawRadialGradient(C.gradient([C.rgb(0.50, 0.28, 0.22, 0.55), C.rgb(0.50, 0.28, 0.22, 0)], [0, 1]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 50, options: [.drawsBeforeStartLocation])
        ctx.restoreGState()
        ctx.restoreGState()

        // The jumper: sloping shoulders and a crew neck, lit from the top left.
        let body = CGMutablePath()
        body.move(to: CGPoint(x: cx - 330, y: -340))
        body.addLine(to: CGPoint(x: cx - 330, y: -10))
        body.addCurve(to: CGPoint(x: cx - 240, y: 170), control1: CGPoint(x: cx - 330, y: 90), control2: CGPoint(x: cx - 300, y: 152))
        body.addCurve(to: CGPoint(x: cx - 58, y: 226), control1: CGPoint(x: cx - 175, y: 190), control2: CGPoint(x: cx - 96, y: 212))
        body.addCurve(to: CGPoint(x: cx + 58, y: 226), control1: CGPoint(x: cx - 32, y: 196), control2: CGPoint(x: cx + 32, y: 196))
        body.addCurve(to: CGPoint(x: cx + 240, y: 170), control1: CGPoint(x: cx + 96, y: 212), control2: CGPoint(x: cx + 175, y: 190))
        body.addCurve(to: CGPoint(x: cx + 330, y: -10), control1: CGPoint(x: cx + 300, y: 152), control2: CGPoint(x: cx + 330, y: 90))
        body.addLine(to: CGPoint(x: cx + 330, y: -340))
        body.closeSubpath()
        ctx.saveGState()
        ctx.addPath(body); ctx.clip()
        ctx.drawLinearGradient(C.gradient([C.jumperLight, C.jumper, C.jumperShade], [0, 0.42, 1]),
                               start: CGPoint(x: cx - 320, y: 210), end: CGPoint(x: cx + 260, y: -100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // Sheen on the lit shoulder, the chin's shadow on the chest, and the far side turning away into shade.
        ctx.drawRadialGradient(C.gradient([C.rgb(1, 0.93, 0.86, 0.32), C.rgb(1, 0.93, 0.86, 0)], [0, 1]),
                               startCenter: CGPoint(x: cx - 250, y: 160), startRadius: 0, endCenter: CGPoint(x: cx - 250, y: 160), endRadius: 140, options: [])
        ctx.saveGState()
        ctx.translateBy(x: cx + 8, y: 206); ctx.scaleBy(x: 2.0, y: 0.6)
        ctx.drawRadialGradient(C.gradient([C.rgb(0.40, 0.08, 0.14, 0.42), C.rgb(0.40, 0.08, 0.14, 0)], [0, 1]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 66, options: [])
        ctx.restoreGState()
        ctx.drawLinearGradient(C.gradient([C.rgb(0.30, 0.05, 0.14, 0), C.rgb(0.30, 0.05, 0.14, 0.28)], [0, 1]),
                               start: CGPoint(x: cx + 200, y: 0), end: CGPoint(x: cx + 330, y: 0), options: [.drawsAfterEndLocation])
        // Sleeve seams.
        ctx.setLineCap(.round)
        ctx.setStrokeColor(C.rgb(0.45, 0.10, 0.16, 0.20)); ctx.setLineWidth(4)
        for side in [-1.0, 1.0] {
            ctx.move(to: CGPoint(x: cx + side * 214, y: 182))
            ctx.addCurve(to: CGPoint(x: cx + side * 262, y: -20), control1: CGPoint(x: cx + side * 236, y: 128), control2: CGPoint(x: cx + side * 262, y: 50))
            ctx.strokePath()
        }
        ctx.restoreGState()

        // Ribbed collar.
        let collar = CGMutablePath()
        collar.move(to: CGPoint(x: cx - 60, y: 224))
        collar.addCurve(to: CGPoint(x: cx + 60, y: 224), control1: CGPoint(x: cx - 34, y: 192), control2: CGPoint(x: cx + 34, y: 192))
        ctx.setLineCap(.round)
        ctx.addPath(collar); ctx.setStrokeColor(C.jumperShade); ctx.setLineWidth(17); ctx.strokePath()
        ctx.saveGState(); ctx.translateBy(x: -1, y: 2)
        ctx.addPath(collar); ctx.setStrokeColor(C.rgb(1, 0.66, 0.58, 0.55)); ctx.setLineWidth(3); ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Head

    /// The head in pixels around its own centre: hair, ears, face.
    private static func drawHead(_ ctx: CGContext, mouthOpen: Double, browRaise: Double, smile: Double, blink: Double) {
        typealias C = LensBrowserPaint
        let s = scale
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }

        // Hair at the back: full on top, tapering to the nape behind the ears.
        let back = CGMutablePath()
        back.move(to: p(-100, -30))
        back.addCurve(to: p(-30, 172), control1: p(-118, 80), control2: p(-92, 160))
        back.addCurve(to: p(104, 128), control1: p(30, 184), control2: p(86, 166))
        back.addCurve(to: p(100, -30), control1: p(120, 90), control2: p(114, 20))
        back.addCurve(to: p(-100, -30), control1: p(60, -6), control2: p(-60, -6))
        ctx.saveGState()
        ctx.addPath(back); ctx.clip()
        ctx.drawLinearGradient(C.gradient([C.hairMid, C.hairDark], [0, 1]), start: p(-80, 175), end: p(90, -10), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()

        // Ears, the far one in shade.
        for side in [-1.0, 1.0] {
            ctx.setFillColor(side < 0 ? C.skin : C.skinShade)
            ctx.fillEllipse(in: CGRect(origin: p(side * 92 - 14, -20), size: CGSize(width: 28 * s, height: 50 * s)))
            ctx.setFillColor(C.rgb(0.72, 0.45, 0.37, 0.6))
            ctx.fillEllipse(in: CGRect(origin: p(side * 93 - 6, -10), size: CGSize(width: 12 * s, height: 30 * s)))
        }

        // The face: an egg, broad at the brow and narrowing to the chin.
        let face = CGMutablePath()
        face.move(to: p(0, 122))
        face.addCurve(to: p(96, 16), control1: p(56, 122), control2: p(96, 80))
        face.addCurve(to: p(0, -122), control1: p(96, -58), control2: p(52, -122))
        face.addCurve(to: p(-96, 16), control1: p(-52, -122), control2: p(-96, -58))
        face.addCurve(to: p(0, 122), control1: p(-96, 80), control2: p(-56, 122))
        ctx.saveGState()
        ctx.addPath(face); ctx.clip()
        ctx.drawLinearGradient(C.gradient([C.skinLight, C.skin, C.skinShade], [0, 0.55, 1]), start: p(-90, 110), end: p(95, -120),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // Light on the forehead and the near cheek; shade along the far jaw.
        ctx.drawRadialGradient(C.gradient([C.rgb(1, 0.95, 0.88, 0.34), C.rgb(1, 0.95, 0.88, 0)], [0, 1]),
                               startCenter: p(-30, 50), startRadius: 0, endCenter: p(-30, 50), endRadius: 84 * s, options: [])
        ctx.drawRadialGradient(C.gradient([C.rgb(0.58, 0.34, 0.27, 0), C.rgb(0.58, 0.34, 0.27, 0.32)], [0.6, 1]),
                               startCenter: p(-24, 24), startRadius: 0, endCenter: p(-24, 24), endRadius: 150 * s, options: [])
        // Blush, warmer with a smile.
        for side in [-1.0, 1.0] {
            let c = p(side * 54, -20 + 4 * smile)
            let a = 0.20 + 0.16 * smile
            ctx.drawRadialGradient(C.gradient([C.rgb(0.97, 0.45, 0.45, a), C.rgb(0.97, 0.45, 0.45, 0)], [0, 1]),
                                   startCenter: c, startRadius: 0, endCenter: c, endRadius: 27 * s, options: [])
        }
        // The fringe's soft shadow on the forehead.
        ctx.saveGState()
        ctx.translateBy(x: 6 * s, y: -7 * s)
        ctx.addPath(fringePath(s)); ctx.setFillColor(C.rgb(0.45, 0.24, 0.18, 0.22)); ctx.fillPath()
        ctx.restoreGState()
        ctx.restoreGState()

        drawNose(ctx, s: s, smile: smile)
        for side in [-1.0, 1.0] { drawEye(ctx, side: side, s: s, smile: smile, blink: blink) }
        for side in [-1.0, 1.0] { drawBrow(ctx, side: side, s: s, raise: browRaise) }
        drawMouth(ctx, s: s, open: mouthOpen, smile: smile)

        // The fringe, swept from a parting on the left across to the right, kept clear of raised brows.
        let fringe = fringePath(s)
        ctx.saveGState()
        ctx.addPath(fringe); ctx.clip()
        ctx.drawLinearGradient(C.gradient([C.hairMid, C.hairDark], [0, 1]), start: p(-80, 175), end: p(90, -10), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.setLineCap(.round)
        // A broad sheen where the light catches the sweep, and fine strands following it.
        ctx.setStrokeColor(C.hairSheen.copy(alpha: 0.42) ?? C.hairSheen); ctx.setLineWidth(12 * s)
        ctx.move(to: p(-46, 154)); ctx.addCurve(to: p(70, 128), control1: p(-14, 168), control2: p(36, 156)); ctx.strokePath()
        ctx.setStrokeColor(C.hairSheen.copy(alpha: 0.24) ?? C.hairSheen); ctx.setLineWidth(2 * s)
        for k in 0..<6 {
            let d = Double(k)
            ctx.move(to: p(-48 + d * 4, 164 - d * 9))
            ctx.addCurve(to: p(96 - d * 6, 70 + d * 4), control1: p(0 + d * 2, 158 - d * 10), control2: p(78 - d * 4, 128 - d * 8))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// The front hair's outline: up from the left temple, over the crown, down to the right temple, then a wavy edge back across the forehead.
    private static func fringePath(_ s: Double) -> CGPath {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        let fringe = CGMutablePath()
        fringe.move(to: p(-99, 12))
        fringe.addCurve(to: p(-54, 158), control1: p(-108, 80), control2: p(-90, 140))
        fringe.addCurve(to: p(70, 160), control1: p(-14, 178), control2: p(36, 178))
        fringe.addCurve(to: p(104, 30), control1: p(102, 140), control2: p(110, 80))
        fringe.addCurve(to: p(64, 92), control1: p(96, 62), control2: p(84, 84))
        fringe.addCurve(to: p(-6, 110), control1: p(42, 102), control2: p(18, 104))
        fringe.addCurve(to: p(-52, 114), control1: p(-24, 114), control2: p(-38, 116))
        fringe.addCurve(to: p(-82, 74), control1: p(-66, 108), control2: p(-78, 94))
        fringe.addCurve(to: p(-93, 10), control1: p(-86, 52), control2: p(-92, 30))
        fringe.closeSubpath()
        return fringe
    }

    private static func drawNose(_ ctx: CGContext, s: Double, smile: Double) {
        typealias C = LensBrowserPaint
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        // Shade down the far side of the bridge, a lit tip, and a soft curve under it.
        let side = CGMutablePath()
        side.move(to: p(4, 6))
        side.addCurve(to: p(12, -30), control1: p(9, -6), control2: p(14, -20))
        side.addCurve(to: p(4, -30), control1: p(10, -34), control2: p(6, -33))
        side.addCurve(to: p(4, 6), control1: p(8, -16), control2: p(4, -6))
        ctx.addPath(side); ctx.setFillColor(C.rgb(0.70, 0.44, 0.34, 0.30)); ctx.fillPath()
        ctx.setFillColor(C.rgb(1, 0.93, 0.86, 0.38))
        ctx.fillEllipse(in: CGRect(origin: p(-9, -33), size: CGSize(width: 14 * s, height: 10 * s)))
        ctx.setLineCap(.round)
        ctx.setStrokeColor(C.rgb(0.58, 0.33, 0.27, 0.55)); ctx.setLineWidth(2.6 * s)
        ctx.move(to: p(-13, -34)); ctx.addCurve(to: p(13, -34), control1: p(-8, -42), control2: p(8, -42)); ctx.strokePath()
        ctx.setFillColor(C.rgb(0.50, 0.27, 0.23, 0.45))
        for x in [-1.0, 1.0] { ctx.fillEllipse(in: CGRect(origin: p(x * 8 - 3.5, -38), size: CGSize(width: 7 * s, height: 4 * s))) }
    }

    private static func drawEye(_ ctx: CGContext, side: Double, s: Double, smile: Double, blink: Double) {
        typealias C = LensBrowserPaint
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        let cx = side * 42, cy = 20.0
        let open = max(0, 1 - blink)
        let top = 11.5 * open * (1 - 0.10 * smile), bottom = 8.5 * open * (1 - 0.40 * smile)
        let half = 19.0
        let ink = C.rgb(0.15, 0.09, 0.07)
        ctx.setLineCap(.round)
        // The crease of the lid, for depth.
        ctx.setStrokeColor(C.rgb(0.62, 0.38, 0.30, 0.40)); ctx.setLineWidth(1.6 * s)
        ctx.move(to: p(cx - half + 3, cy + 9)); ctx.addCurve(to: p(cx + half - 2, cy + 10), control1: p(cx - 8, cy + 21), control2: p(cx + 8, cy + 21))
        ctx.strokePath()
        if open < 0.2 {
            // Shut: a soft downward curve with a heavier outer corner.
            ctx.setStrokeColor(ink); ctx.setLineWidth(3.2 * s)
            ctx.move(to: p(cx - half, cy + 1)); ctx.addQuadCurve(to: p(cx + half, cy + 1), control: p(cx, cy - 8)); ctx.strokePath()
            return
        }
        let almond = CGMutablePath()
        almond.move(to: p(cx - half, cy))
        almond.addCurve(to: p(cx + half, cy + 1), control1: p(cx - 10, cy + top * 1.45), control2: p(cx + 10, cy + top * 1.45))
        almond.addCurve(to: p(cx - half, cy), control1: p(cx + 10, cy - bottom * 1.3), control2: p(cx - 10, cy - bottom * 1.3))
        ctx.saveGState()
        ctx.addPath(almond); ctx.clip()
        ctx.setFillColor(C.rgb(0.98, 0.97, 0.96)); ctx.fill(CGRect(origin: p(cx - 22, cy - 14), size: CGSize(width: 44 * s, height: 30 * s)))
        // The iris looks just past the camera, with the lid's shadow across its top.
        let iris = p(cx - side * 1.5, cy - 0.5)
        ctx.drawRadialGradient(C.gradient([C.rgb(0.56, 0.37, 0.21), C.rgb(0.31, 0.19, 0.10), C.rgb(0.16, 0.09, 0.05)], [0, 0.65, 1]),
                               startCenter: iris, startRadius: 0, endCenter: iris, endRadius: 9.5 * s, options: [])
        ctx.fillCircle(center: iris, radius: 4.4 * s, color: C.rgb(0.05, 0.03, 0.03))
        ctx.drawLinearGradient(C.gradient([C.rgb(0.35, 0.20, 0.16, 0.45), C.rgb(0.35, 0.20, 0.16, 0)], [0, 1]),
                               start: p(cx, cy + top), end: p(cx, cy + top - 7), options: [])
        ctx.fillCircle(center: CGPoint(x: iris.x - 2.8 * s, y: iris.y + 3.2 * s), radius: 2.4 * s, color: C.rgb(1, 1, 1, 0.95))
        ctx.fillCircle(center: CGPoint(x: iris.x + 3 * s, y: iris.y - 2.6 * s), radius: 1.1 * s, color: C.rgb(1, 1, 1, 0.7))
        ctx.restoreGState()
        // Lash line, heavier at the outer corner, and a faint lower lid.
        ctx.setStrokeColor(ink); ctx.setLineWidth(3 * s)
        ctx.move(to: p(cx - half, cy)); ctx.addCurve(to: p(cx + half, cy + 1), control1: p(cx - 10, cy + top * 1.45), control2: p(cx + 10, cy + top * 1.45))
        ctx.strokePath()
        ctx.setLineWidth(2.4 * s)
        let outer = cx + side * half
        ctx.move(to: p(outer, cy + 1)); ctx.addLine(to: p(outer + side * 4, cy + 4)); ctx.strokePath()
        ctx.setStrokeColor(C.rgb(0.55, 0.33, 0.27, 0.35)); ctx.setLineWidth(1.4 * s)
        ctx.move(to: p(cx - half + 3, cy - 1)); ctx.addCurve(to: p(cx + half - 3, cy), control1: p(cx - 8, cy - bottom * 1.35), control2: p(cx + 8, cy - bottom * 1.35))
        ctx.strokePath()
    }

    /// A brow: full at the inner end, a gentle arch two thirds out, tapering to the tail.
    private static func drawBrow(_ ctx: CGContext, side: Double, s: Double, raise: Double) {
        typealias C = LensBrowserPaint
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: side * x * s, y: y * s) }
        let y = 20 + 84 * (0.40 + 0.28 * raise)
        let arch = 3 + 5 * raise
        let brow = CGMutablePath()
        brow.move(to: p(20, y - 3))
        brow.addCurve(to: p(64, y - 2 - arch * 0.4), control1: p(30, y + 2 + arch), control2: p(50, y + 4 + arch))
        brow.addCurve(to: p(20, y + 5), control1: p(52, y + 9 + arch), control2: p(30, y + 9 + arch))
        brow.closeSubpath()
        ctx.addPath(brow)
        ctx.setFillColor(C.rgb(0.22, 0.13, 0.10))
        ctx.setStrokeColor(C.rgb(0.22, 0.13, 0.10)); ctx.setLineWidth(1.5 * s); ctx.setLineJoin(.round)
        ctx.drawPath(using: .fillStroke)
    }

    private static func drawMouth(_ ctx: CGContext, s: Double, open: Double, smile: Double) {
        typealias C = LensBrowserPaint
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: -60 * s + y * s) }
        let half = 35 * (1 + 0.35 * smile)
        let lift = 4 + 9 * smile
        let lip = C.rgb(0.82, 0.40, 0.42), lipDark = C.rgb(0.68, 0.30, 0.34)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        if open < 0.08 {
            // Closed: a smile line with a fuller lower lip beneath it and a cupid's bow above.
            let dip = -2 - 5 * smile
            let upper = CGMutablePath()
            upper.move(to: p(-half, lift))
            upper.addCurve(to: p(0, 6 - 2 * smile), control1: p(-half * 0.55, lift + 4), control2: p(-9, 10 - 2 * smile))
            upper.addCurve(to: p(half, lift), control1: p(9, 10 - 2 * smile), control2: p(half * 0.55, lift + 4))
            upper.addCurve(to: p(-half, lift), control1: p(half * 0.45, dip), control2: p(-half * 0.45, dip))
            ctx.addPath(upper); ctx.setFillColor(lipDark); ctx.fillPath()
            let lower = CGMutablePath()
            lower.move(to: p(-half * 0.92, lift - 1))
            lower.addCurve(to: p(half * 0.92, lift - 1), control1: p(-half * 0.45, dip), control2: p(half * 0.45, dip))
            lower.addCurve(to: p(-half * 0.92, lift - 1), control1: p(half * 0.5, dip - 13), control2: p(-half * 0.5, dip - 13))
            ctx.addPath(lower); ctx.setFillColor(lip); ctx.fillPath()
            ctx.setFillColor(C.rgb(1, 0.86, 0.86, 0.40))
            ctx.fillEllipse(in: CGRect(origin: p(-13, dip - 9), size: CGSize(width: 18 * s, height: 3.6 * s)))
            ctx.setStrokeColor(C.rgb(0.42, 0.12, 0.16)); ctx.setLineWidth(2.4 * s)
            ctx.move(to: p(-half - 1, lift + 1)); ctx.addCurve(to: p(half + 1, lift + 1), control1: p(-half * 0.45, dip), control2: p(half * 0.45, dip))
            ctx.strokePath()
            return
        }
        let h = 6 + 46 * open
        let mouth = CGMutablePath()
        mouth.move(to: p(-half, lift))
        mouth.addCurve(to: p(half, lift), control1: p(-half * 0.55, h * 0.36 + lift * 0.3), control2: p(half * 0.55, h * 0.36 + lift * 0.3))
        mouth.addCurve(to: p(-half, lift), control1: p(half * 0.62, -h * 0.92 - 4 * smile), control2: p(-half * 0.62, -h * 0.92 - 4 * smile))
        mouth.closeSubpath()
        ctx.saveGState()
        ctx.addPath(mouth); ctx.clip()
        ctx.setFillColor(C.rgb(0.30, 0.06, 0.10)); ctx.fill(CGRect(origin: p(-half - 4, -h - 10), size: CGSize(width: (half * 2 + 8) * s, height: (h * 2 + 30) * s)))
        // Tongue, then the top teeth.
        ctx.setFillColor(C.rgb(0.86, 0.40, 0.44))
        ctx.fillEllipse(in: CGRect(origin: p(-half * 0.55, -h * 0.85), size: CGSize(width: half * 1.1 * s, height: h * 0.55 * s)))
        let teeth = min(9.0, h * 0.30)
        ctx.setFillColor(C.rgb(0.98, 0.97, 0.94))
        ctx.fill(CGRect(origin: p(-half, h * 0.36 - teeth + lift * 0.25), size: CGSize(width: half * 2 * s, height: (teeth + 6) * s)))
        ctx.restoreGState()
        ctx.addPath(mouth); ctx.setStrokeColor(lip); ctx.setLineWidth(6 * s); ctx.strokePath()
        ctx.setFillColor(C.rgb(1, 0.86, 0.86, 0.32))
        ctx.fillEllipse(in: CGRect(origin: p(-10, -h * 0.70 - 4.5), size: CGSize(width: 16 * s, height: 3.5 * s)))
    }

    // MARK: - Arms and hands

    /// An arm raised to a hand: the upper arm down and out from the shoulder to an elbow by the body's side, the forearm up to the wrist.
    private static func drawArm(_ ctx: CGContext, hand: LensBrowserHand, sway: CGAffineTransform) {
        typealias C = LensBrowserPaint
        let joints = hand.joints
        let wrist = hand.wrist, size = hand.size
        let side: Double = hand.mirrored ? 1 : -1
        let shoulder = CGPoint(x: 640 + side * shoulderSpan, y: shoulderHeight).applying(sway)
        let up = CGVector(dx: Double(joints[HandJoint.middleMCP.rawValue].x - wrist.x) / size,
                          dy: Double(joints[HandJoint.middleMCP.rawValue].y - wrist.y) / size)
        // The forearm is about two and a half palms long and continues the line of the hand; the elbow never rises above the shoulder.
        let forearm = size * 2.5
        var elbow = CGPoint(x: wrist.x - up.dx * forearm, y: wrist.y - up.dy * forearm)
        elbow.x += side * size * 0.25
        elbow.y = min(elbow.y, shoulder.y - size * 0.6)
        let cuff = CGPoint(x: wrist.x - up.dx * size * 0.42, y: wrist.y - up.dy * size * 0.42)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        // A little skin between the cuff and the hand.
        ctx.setStrokeColor(C.skin); ctx.setLineWidth(size * 0.56)
        ctx.move(to: cuff); ctx.addLine(to: wrist); ctx.strokePath()
        // The upper arm sits a little back, so it is a shade darker; the forearm comes forward over it.
        let upper = CGMutablePath(); upper.move(to: shoulder); upper.addLine(to: elbow)
        let lower = CGMutablePath(); lower.move(to: elbow); lower.addLine(to: cuff)
        ctx.addPath(upper); ctx.setStrokeColor(C.jumperShade); ctx.setLineWidth(size * 1.02); ctx.strokePath()
        ctx.addPath(upper); ctx.setStrokeColor(C.jumperMid); ctx.setLineWidth(size * 0.90); ctx.strokePath()
        ctx.addPath(lower); ctx.setStrokeColor(C.jumperShade); ctx.setLineWidth(size * 0.88); ctx.strokePath()
        ctx.addPath(lower); ctx.setStrokeColor(C.jumper); ctx.setLineWidth(size * 0.76); ctx.strokePath()
        // A soft highlight down the lit side of the forearm.
        let across = CGVector(dx: up.dy, dy: -up.dx)
        ctx.saveGState()
        ctx.translateBy(x: -size * 0.17, y: size * 0.04)
        ctx.addPath(lower); ctx.setStrokeColor(C.jumperLight.copy(alpha: 0.5) ?? C.jumperLight); ctx.setLineWidth(size * 0.20); ctx.strokePath()
        ctx.restoreGState()
        // Ribbed cuff.
        ctx.setStrokeColor(C.jumperShade); ctx.setLineWidth(size * 0.15)
        ctx.move(to: CGPoint(x: cuff.x - across.dx * size * 0.36, y: cuff.y - across.dy * size * 0.36))
        ctx.addLine(to: CGPoint(x: cuff.x + across.dx * size * 0.36, y: cuff.y + across.dy * size * 0.36))
        ctx.strokePath()
    }

    private static func drawHand(_ ctx: CGContext, hand: LensBrowserHand) {
        let j = hand.joints, size = hand.size
        func at(_ joint: HandJoint) -> CGPoint { j[joint.rawValue] }
        let up = CGVector(dx: Double(at(.middleMCP).x - at(.wrist).x) / size, dy: Double(at(.middleMCP).y - at(.wrist).y) / size)
        let across = CGVector(dx: up.dy, dy: -up.dx)
        let w = at(.wrist)
        // The palm: wrist, the base of the thumb, and the four knuckles, with rounded corners.
        let palm = CGMutablePath()
        let wristA = CGPoint(x: w.x + across.dx * size * 0.30, y: w.y + across.dy * size * 0.30)
        let wristB = CGPoint(x: w.x - across.dx * size * 0.30, y: w.y - across.dy * size * 0.30)
        let thumbSide = hand.mirrored ? wristB : wristA, littleSide = hand.mirrored ? wristA : wristB
        palm.addLines(between: [littleSide, thumbSide, at(.thumbCMC), at(.thumbMP), at(.indexMCP), at(.middleMCP), at(.ringMCP), at(.littleMCP)])
        palm.closeSubpath()
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        ctx.addPath(palm); ctx.setStrokeColor(LensBrowserPaint.skinShade); ctx.setLineWidth(size * 0.30); ctx.strokePath()
        ctx.addPath(palm); ctx.setFillColor(LensBrowserPaint.skin); ctx.fillPath()
        ctx.addPath(palm); ctx.setStrokeColor(LensBrowserPaint.skin); ctx.setLineWidth(size * 0.24); ctx.strokePath()
        ctx.saveGState()
        ctx.addPath(palm); ctx.clip()
        let mid = hand.state().palm
        ctx.drawRadialGradient(LensBrowserPaint.gradient([LensBrowserPaint.rgb(1, 0.92, 0.84, 0.35), LensBrowserPaint.rgb(1, 0.92, 0.84, 0)], [0, 1]),
                               startCenter: CGPoint(x: mid.x - size * 0.15, y: mid.y + size * 0.1), startRadius: 0,
                               endCenter: CGPoint(x: mid.x - size * 0.15, y: mid.y + size * 0.1), endRadius: size * 0.7, options: [])
        ctx.restoreGState()

        // Fingers: a darker edge, then the finger, then a nail on the ones held out.
        let fingers: [(Finger, Double)] = [(.little, 0.17), (.ring, 0.19), (.middle, 0.20), (.index, 0.20), (.thumb, 0.22)]
        let shadow = CGVector(dx: size * 0.018, dy: -size * 0.018)
        for (finger, width) in fingers {
            let chain: [HandJoint] = finger == .thumb ? [.thumbCMC, .thumbMP, .thumbIP, .thumbTip]
                : [finger.knuckle, finger.middleJoint, HandJoint(rawValue: finger.middleJoint.rawValue + 1) ?? finger.tip, finger.tip]
            let path = CGMutablePath()
            path.addLines(between: chain.map(at))
            ctx.saveGState(); ctx.translateBy(x: shadow.dx, y: shadow.dy)
            ctx.addPath(path); ctx.setStrokeColor(LensBrowserPaint.skinShade); ctx.setLineWidth(size * (width + 0.035)); ctx.strokePath()
            ctx.restoreGState()
            ctx.addPath(path); ctx.setStrokeColor(LensBrowserPaint.skin); ctx.setLineWidth(size * width); ctx.strokePath()
            let tip = at(finger.tip), before = at(chain[2])
            let length = max(1e-6, hypot(Double(tip.x - before.x), Double(tip.y - before.y)))
            guard length > size * 0.12 else { continue }
            let dir = CGVector(dx: Double(tip.x - before.x) / length, dy: Double(tip.y - before.y) / length)
            ctx.saveGState()
            ctx.translateBy(x: tip.x - dir.dx * size * 0.035, y: tip.y - dir.dy * size * 0.035)
            ctx.rotate(by: atan2(dir.dy, dir.dx))
            ctx.setFillColor(LensBrowserPaint.rgb(1, 0.90, 0.86, 0.85))
            ctx.fillEllipse(in: CGRect(x: -size * 0.055, y: -size * 0.05, width: size * 0.09, height: size * 0.10))
            ctx.restoreGState()
        }
    }
}

/// The mannequin's palette, named so it stays one family.
private enum LensBrowserPaint {
    static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(colorSpace: space, components: [r, g, b, a]) ?? CGColor(gray: 0.5, alpha: a)
    }

    static func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)
            ?? CGGradient(colorsSpace: space, colors: [rgb(0, 0, 0), rgb(1, 1, 1)] as CFArray, locations: [0, 1])!
    }

    // Studio dusk: the backdrop's blues.
    static let duskHigh = rgb(0.38, 0.40, 0.84)
    static let duskMid = rgb(0.21, 0.20, 0.52)
    static let duskLow = rgb(0.09, 0.08, 0.24)
    static let ciDusk = CIColor(red: 0.21, green: 0.20, blue: 0.52)

    // Warm honey skin.
    static let skinLight = rgb(0.97, 0.80, 0.67)
    static let skin = rgb(0.92, 0.70, 0.56)
    static let skinShade = rgb(0.80, 0.55, 0.43)

    // Espresso hair.
    static let hairDark = rgb(0.13, 0.08, 0.07)
    static let hairMid = rgb(0.30, 0.19, 0.14)
    static let hairSheen = rgb(0.62, 0.44, 0.32)

    // Coral jumper.
    static let jumperLight = rgb(0.98, 0.58, 0.50)
    static let jumper = rgb(0.92, 0.43, 0.41)
    static let jumperShade = rgb(0.70, 0.25, 0.30)
    static let jumperMid = rgb(0.84, 0.36, 0.37)
}
