import CoreImage
import XCTest

/// A head drawn with a real person's proportions, for trying costumes on something less cartoonish than `SyntheticScene`:
/// the mouth sits 1.15 eye-spacings below the eyes (the test face has 0.95), the skull rises to about 1.85 above them, the head
/// is wider, the ears stick out, and the face box is the size Vision reports. Hair, skin and shirt colours can be changed, so a
/// costume can be checked over dark and light hair, dark and light skin, and a white shirt.
struct HeadwearRealHead {
    var center = CGPoint(x: 640, y: 380)
    /// Eye spacing in pixels.
    var io = 72.0
    var roll = 0.0
    var mouthOpen = 0.0
    var browRaise = 0.0
    var blink = 0.0
    var smile = 0.0
    var skin = CGColor(srgbRed: 0.87, green: 0.68, blue: 0.56, alpha: 1)
    var hair = CGColor(srgbRed: 0.16, green: 0.11, blue: 0.08, alpha: 1)
    var shirt = CGColor(srgbRed: 0.22, green: 0.24, blue: 0.3, alpha: 1)

    static let mouthDrop = 1.15

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        let c = cos(roll), s = sin(roll)
        return CGPoint(x: center.x + (x * c - y * s) * io, y: center.y + (x * s + y * c) * io)
    }

    func face() -> FaceState {
        let brow = 0.4 + 0.25 * browRaise
        // Vision's box: cheek to cheek, from above the brows to the chin.
        let rect = CGRect(x: center.x - 1.2 * io, y: center.y - 1.95 * io, width: 2.4 * io, height: 2.75 * io)
        return FaceState(leftEye: point(-0.5, 0), rightEye: point(0.5, 0), mouth: point(0, -Self.mouthDrop - 0.1 * mouthOpen),
                         mouthWidth: io * 0.78 * (1 + 0.3 * smile), browCenter: point(0, brow), rect: rect, mouthOpen: mouthOpen,
                         browRaise: browRaise, browDistance: brow / Self.mouthDrop, blink: blink, smile: smile)
    }

    /// The picture and the person's cutout.
    func pictures() -> (person: CGImage, matte: CGImage) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let person = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let matte = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        matte.setFillColor(gray: 0, alpha: 1); matte.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
        for (ctx, isMatte) in [(person, false), (matte, true)] {
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: roll)
            ctx.scaleBy(x: io, y: io)
            drawPerson(ctx, matte: isMatte)
            ctx.restoreGState()
        }
        return (person.makeImage()!, matte.makeImage()!)
    }

    private func smooth(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let n = pts.count
        path.move(to: pts[0])
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }

    private func drawPerson(_ ctx: CGContext, matte: Bool) {
        func color(_ c: CGColor) -> CGColor { matte ? CGColor(gray: 1, alpha: 1) : c }
        // Shoulders and neck.
        ctx.setFillColor(color(shirt))
        ctx.fillEllipse(in: CGRect(x: -3.6, y: -5.6, width: 7.2, height: 3.4))
        ctx.setFillColor(color(skin.copy(alpha: 1)!))
        ctx.fill(CGRect(x: -0.62, y: -2.9, width: 1.24, height: 1.6))
        // Hair at the back, ears, the face.
        ctx.setFillColor(color(hair))
        ctx.addPath(smooth([CGPoint(x: -1.3, y: -0.2), CGPoint(x: -1.35, y: 0.9), CGPoint(x: -0.9, y: 1.72), CGPoint(x: 0, y: 2.02),
                            CGPoint(x: 0.9, y: 1.72), CGPoint(x: 1.35, y: 0.9), CGPoint(x: 1.3, y: -0.2), CGPoint(x: 0, y: 0.2)]))
        ctx.fillPath()
        ctx.setFillColor(color(skin))
        for side in [-1.0, 1.0] { ctx.fillEllipse(in: CGRect(x: side * 1.22 - 0.18, y: -0.78, width: 0.36, height: 0.82)) }
        let face = smooth([CGPoint(x: 0, y: 1.6), CGPoint(x: 0.95, y: 1.3), CGPoint(x: 1.17, y: 0.3), CGPoint(x: 1.12, y: -0.45),
                           CGPoint(x: 0.95, y: -1.25), CGPoint(x: 0.5, y: -1.75), CGPoint(x: 0, y: -1.9), CGPoint(x: -0.5, y: -1.75),
                           CGPoint(x: -0.95, y: -1.25), CGPoint(x: -1.12, y: -0.45), CGPoint(x: -1.17, y: 0.3), CGPoint(x: -0.95, y: 1.3)])
        ctx.addPath(face); ctx.fillPath()
        // A fringe down to the hairline.
        ctx.setFillColor(color(hair))
        ctx.addPath(smooth([CGPoint(x: -1.2, y: 0.55), CGPoint(x: -1.05, y: 1.45), CGPoint(x: 0, y: 1.95), CGPoint(x: 1.05, y: 1.45),
                            CGPoint(x: 1.2, y: 0.55), CGPoint(x: 0.85, y: 1.12), CGPoint(x: 0.2, y: 1.2), CGPoint(x: -0.6, y: 1.15)]))
        ctx.fillPath()
        guard !matte else { return }
        let ink = CGColor(srgbRed: 0.2, green: 0.12, blue: 0.1, alpha: 1)
        // Brows, eyes, nose, mouth.
        let brow = 0.4 + 0.25 * browRaise
        ctx.setStrokeColor(ink); ctx.setLineCap(.round); ctx.setLineWidth(0.08)
        for side in [-1.0, 1.0] {
            ctx.move(to: CGPoint(x: side * 0.25, y: brow - 0.02)); ctx.addQuadCurve(to: CGPoint(x: side * 0.78, y: brow - 0.06), control: CGPoint(x: side * 0.5, y: brow + 0.06))
            ctx.strokePath()
            let open = 0.09 * (1 - 0.9 * blink)
            ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.95, blue: 0.93, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: side * 0.5 - 0.22, y: -open, width: 0.44, height: open * 2))
            if blink < 0.5 {
                ctx.setFillColor(CGColor(srgbRed: 0.3, green: 0.2, blue: 0.12, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: side * 0.5 - 0.085, y: -0.085, width: 0.17, height: 0.17))
            }
        }
        ctx.setStrokeColor(CGColor(srgbRed: 0.7, green: 0.48, blue: 0.38, alpha: 1)); ctx.setLineWidth(0.05)
        ctx.move(to: CGPoint(x: -0.04, y: -0.15)); ctx.addLine(to: CGPoint(x: -0.1, y: -0.68)); ctx.addLine(to: CGPoint(x: 0.08, y: -0.74)); ctx.strokePath()
        let w = 0.39 * (1 + 0.3 * smile), m = -Self.mouthDrop - 0.1 * mouthOpen, gap = 0.04 + 0.42 * mouthOpen
        ctx.setFillColor(CGColor(srgbRed: 0.42, green: 0.12, blue: 0.13, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: -w, y: m - gap / 2, width: w * 2, height: gap))
        ctx.setStrokeColor(CGColor(srgbRed: 0.68, green: 0.36, blue: 0.36, alpha: 1)); ctx.setLineWidth(0.06)
        ctx.move(to: CGPoint(x: -w, y: m + 0.02 * smile)); ctx.addQuadCurve(to: CGPoint(x: w, y: m + 0.02 * smile), control: CGPoint(x: 0, y: m - 0.12 * smile))
        ctx.strokePath()
    }

    /// Everything a lens is handed for one frame, with this person over the usual backdrop.
    func input(services: LensServices, time: Double = 0, dt: Double = 1.0 / 30, withFace: Bool = true) -> LensInput {
        let (person, matteImage) = pictures()
        let rect = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let personImage = CIImage(cgImage: person)
        let matte = CIImage(cgImage: matteImage)
        let backdrop = SyntheticScene.backdrop()
        let composed = personImage.composited(over: backdrop).cropped(to: rect)
        let room = CIImage(color: CIColor(red: 0.5, green: 0.55, blue: 0.6)).cropped(to: rect)
        return LensInput(time: time, dt: dt, rect: rect, camera: personImage.composited(over: room).cropped(to: rect), matte: matte,
                         background: backdrop, composed: composed, matteGrid: nil, face: withFace ? face() : nil, services: services)
    }
}
