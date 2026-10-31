import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest

/// Pictures to try the look filters on. The cartoon in `SyntheticScene` is flat colour, which hides what a texture filter does to
/// a real webcam frame, so this dresses it up: a room with a window, a bookshelf and a lamp, soft focus, window light from the
/// left, shaded skin and sensor noise.
enum LookFixture {
    enum State: String, CaseIterable {
        /// You in your own room, no backdrop.
        case room
        /// You over a backdrop.
        case backdrop
        /// Standing well back from the camera, over a backdrop.
        case far
        /// Head turned over to one side, over a backdrop.
        case tilted
        /// Nobody there, over a backdrop.
        case empty
        /// Someone with deeper skin in a white top, in their own room: grades must not crush dark skin or blow out white cloth.
        case deep
    }

    static let rect = CGRect(origin: .zero, size: SyntheticScene.size)

    static func input(_ h: LensHarness, _ state: State, time: Double = 0, dt: Double = 1.0 / 30) -> LensInput {
        // Pictures are judged with each look's finished textures, not the stand-ins used while they are made in the background.
        LookBake.waitsInline = true
        switch state {
        case .room: return webcam(h, SyntheticScene(), backdrop: false, time: time, dt: dt)
        case .backdrop: return webcam(h, SyntheticScene(), backdrop: true, time: time, dt: dt)
        case .far: return webcam(h, SyntheticScene(center: CGPoint(x: 800, y: 390), scale: 0.5), backdrop: true, time: time, dt: dt)
        case .tilted: return webcam(h, SyntheticScene(center: CGPoint(x: 560, y: 410), scale: 1.1, roll: 0.35, smile: 0.6), backdrop: true, time: time, dt: dt)
        case .empty: return webcam(h, nil, backdrop: true, time: time, dt: dt)
        case .deep: return webcam(h, SyntheticScene(center: CGPoint(x: 600, y: 400), scale: 0.95), backdrop: false, time: time, dt: dt, look: .deep)
        }
    }

    /// `scene` nil means the room with nobody in it.
    static func webcam(_ h: LensHarness, _ scene: SyntheticScene?, backdrop: Bool, time: Double, dt: Double, look: Look = .fair) -> LensInput {
        let base = h.input(scene ?? SyntheticScene(), time: time, dt: dt, background: false)
        let room = roomPicture()
        let matte = scene == nil ? CIImage(color: .black).cropped(to: rect) : (base.matte ?? CIImage(color: .black).cropped(to: rect))

        var photo = room
        if let scene {
            let lit = paintedPerson(scene, look: look)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = lit
            blend.backgroundImage = room
            blend.maskImage = matte
            photo = blend.outputImage ?? room
        }
        // The lens: a touch soft, window light from the left, a little sensor noise, colour not quite as rich as it was.
        let light = CIFilter.linearGradient()
        light.point0 = CGPoint(x: 0, y: 0); light.point1 = CGPoint(x: 1280, y: 180)
        light.color0 = CIColor(red: 1.08, green: 1.06, blue: 1.0); light.color1 = CIColor(red: 0.74, green: 0.76, blue: 0.82)
        photo = LookKit.multiply(light.outputImage!.cropped(to: rect), over: photo.clampedToExtent().applyingGaussianBlur(sigma: 0.8).cropped(to: rect))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.92])
        photo = LookKit.grained(photo, frame: 4, rect: rect, amount: 0.08, size: 1)

        var composed = photo
        if backdrop {
            let blend = CIFilter.blendWithMask()
            blend.inputImage = photo
            blend.backgroundImage = SyntheticScene.backdrop()
            blend.maskImage = matte
            composed = (blend.outputImage ?? photo).cropped(to: rect)
        }
        let grid = scene == nil ? MatteGrid(outputSize: SyntheticScene.size) : base.matteGrid
        return LensInput(time: time, dt: dt, rect: rect, camera: photo.cropped(to: rect), matte: matte, background: backdrop ? SyntheticScene.backdrop() : nil,
                         composed: composed.cropped(to: rect), matteGrid: grid, face: scene == nil ? nil : base.face, services: base.services)
    }

    /// Skin, hair and clothes for the painted stand-in.
    struct Look {
        var skin: LookColour
        var hair: LookColour
        var top: LookColour
        var collar: LookColour
        static let fair = Look(skin: (0.90, 0.71, 0.60), hair: (0.20, 0.13, 0.09), top: (0.24, 0.33, 0.42), collar: (0.93, 0.92, 0.89))
        static let deep = Look(skin: (0.47, 0.31, 0.23), hair: (0.07, 0.06, 0.06), top: (0.90, 0.89, 0.86), collar: (0.82, 0.80, 0.76))
    }

    /// A person painted with light and shade on the same silhouette as the cartoon (so the cutout, the face and the matte grid
    /// all still line up): a knitted top with a collar, a neck in the jaw's shadow, a shaded face with eyes, brows, nose and lips,
    /// and hair made of strands. Lit from the upper left like the room.
    static func paintedPerson(_ s: SyntheticScene, look: Look) -> CIImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else {
            return CIImage(color: .gray).cropped(to: rect)
        }
        var rng = SplitMix64(seed: 77)
        func colour(_ c: LookColour, _ k: Double = 1, _ a: Double = 1) -> CGColor {
            CGColor(colorSpace: space, components: [min(1, c.r * k), min(1, c.g * k), min(1, c.b * k), a])!
        }
        func gradient(_ stops: [(Double, CGColor)]) -> CGGradient {
            CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map { CGFloat($0.0) })!
        }
        func soft(_ ctx: CGContext, at p: CGPoint, radius: Double, _ c: LookColour, _ k: Double, alpha: Double) {
            ctx.drawRadialGradient(gradient([(0, colour(c, k, alpha)), (1, colour(c, k, 0))]), startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
        }
        let c = s.center, k = s.scale
        let skin = look.skin, hair = look.hair

        // The top: knit fabric, lit from the left, with soft folds.
        let body = CGRect(x: c.x - 270 * k, y: c.y - 470 * k, width: 540 * k, height: 340 * k)
        ctx.saveGState()
        ctx.addEllipse(in: body); ctx.clip()
        ctx.drawLinearGradient(gradient([(0, colour(look.top, 1.25)), (0.55, colour(look.top, 1.0)), (1, colour(look.top, 0.62))]),
                               start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
        for _ in 0..<9 {
            let p = CGPoint(x: body.minX + Double.random(in: 0.1...0.9, using: &rng) * body.width, y: body.minY + Double.random(in: 0.1...0.8, using: &rng) * body.height)
            soft(ctx, at: p, radius: Double.random(in: 40...110, using: &rng) * k, look.top, Double.random(in: 0.5...1.4, using: &rng), alpha: 0.35)
        }
        ctx.setLineWidth(1.6 * k)
        var x = body.minX
        while x < body.maxX {
            ctx.setStrokeColor(colour(look.top, 0.7, 0.35))
            ctx.move(to: CGPoint(x: x, y: body.minY)); ctx.addLine(to: CGPoint(x: x + 6 * k, y: body.maxY)); ctx.strokePath()
            x += 5 * k
        }
        // The collar of a shirt underneath, and the shadow the head throws on the chest.
        ctx.setFillColor(colour(look.collar))
        ctx.fillEllipse(in: CGRect(x: c.x - 70 * k, y: c.y - 175 * k, width: 140 * k, height: 60 * k))
        soft(ctx, at: CGPoint(x: c.x + 10 * k, y: c.y - 150 * k), radius: 150 * k, (0, 0, 0), 1, alpha: 0.45)
        ctx.restoreGState()

        // The neck, darker under the jaw.
        let neck = CGRect(x: c.x - 40 * k, y: c.y - 190 * k, width: 80 * k, height: 110 * k)
        ctx.saveGState()
        ctx.clip(to: neck)
        ctx.drawLinearGradient(gradient([(0, colour(skin, 0.92)), (0.55, colour(skin, 0.74)), (1, colour(skin, 0.5))]),
                               start: CGPoint(x: 0, y: neck.minY), end: CGPoint(x: 0, y: neck.maxY), options: [])
        ctx.drawLinearGradient(gradient([(0, colour(skin, 1.05, 0.0)), (1, colour(skin, 0.55, 0.6))]),
                               start: CGPoint(x: neck.midX - 10 * k, y: 0), end: CGPoint(x: neck.maxX, y: 0), options: [])
        ctx.restoreGState()

        // The head, in its own turned frame.
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: s.roll); ctx.scaleBy(x: k, y: k)
        let head = CGRect(x: -100, y: -120, width: 200, height: 258)
        ctx.saveGState()
        ctx.addEllipse(in: head); ctx.clip()
        // The jaw's edge in shade, and hair down the sides behind the face.
        ctx.setFillColor(colour(skin, 0.6)); ctx.fill(head)
        ctx.setFillColor(colour(hair)); ctx.fill(CGRect(x: -100, y: -26, width: 200, height: 170))
        // The face: lit from the upper left, falling into shade at the jaw and the far cheek.
        let face = CGRect(x: -88, y: -120, width: 176, height: 226)
        ctx.saveGState()
        ctx.addEllipse(in: face); ctx.clip()
        ctx.drawRadialGradient(gradient([(0, colour(skin, 1.1)), (0.45, colour(skin, 1.0)), (0.85, colour(skin, 0.78)), (1, colour(skin, 0.62))]),
                               startCenter: CGPoint(x: -28, y: 30), startRadius: 0, endCenter: CGPoint(x: -10, y: 0), endRadius: 135, options: [.drawsAfterEndLocation])
        // Ears, cheeks and the shading of the brow, nose and chin.
        for side in [-1.0, 1.0] {
            soft(ctx, at: CGPoint(x: side * 50, y: -30), radius: 34, (0.95, 0.45, 0.42), 1, alpha: 0.22)       // cheeks
            soft(ctx, at: CGPoint(x: side * 42, y: 22), radius: 30, skin, 0.62, alpha: 0.55)                  // eye sockets
        }
        soft(ctx, at: CGPoint(x: 10, y: -16), radius: 13, skin, 0.7, alpha: 0.3)                              // shade of the nose
        soft(ctx, at: CGPoint(x: -4, y: 0), radius: 12, skin, 1.25, alpha: 0.45)                              // bridge
        soft(ctx, at: CGPoint(x: -3, y: -24), radius: 9, skin, 1.3, alpha: 0.5)                               // tip
        soft(ctx, at: CGPoint(x: 2, y: -38), radius: 14, skin, 0.6, alpha: 0.45)                              // under the nose
        soft(ctx, at: CGPoint(x: 0, y: -96), radius: 30, skin, 1.08, alpha: 0.4)                              // chin
        soft(ctx, at: CGPoint(x: 0, y: -84), radius: 26, skin, 0.7, alpha: 0.35)                              // under the lip
        soft(ctx, at: CGPoint(x: -36, y: 70), radius: 40, skin, 1.15, alpha: 0.35)                            // forehead light
        ctx.restoreGState()
        // Ears.
        for side in [-1.0, 1.0] {
            ctx.setFillColor(colour(skin, side < 0 ? 0.9 : 0.7))
            ctx.fillEllipse(in: CGRect(x: side * 92 - 8, y: -22, width: 16, height: 38))
        }
        // The hair: a mass with a hairline, then strands, then a sheen where the light catches it.
        let hairline = CGMutablePath()
        hairline.move(to: CGPoint(x: -100, y: 40))
        hairline.addCurve(to: CGPoint(x: 6, y: 66), control1: CGPoint(x: -84, y: 92), control2: CGPoint(x: -40, y: 60))
        hairline.addCurve(to: CGPoint(x: 100, y: 34), control1: CGPoint(x: 50, y: 74), control2: CGPoint(x: 88, y: 82))
        hairline.addLine(to: CGPoint(x: 100, y: 140)); hairline.addLine(to: CGPoint(x: -100, y: 140)); hairline.closeSubpath()
        ctx.addPath(hairline); ctx.setFillColor(colour(hair)); ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(hairline); ctx.clip()
        for _ in 0..<260 {
            let start = CGPoint(x: Double.random(in: -30...40, using: &rng), y: Double.random(in: 120...140, using: &rng))
            let side = Double.random(in: -1...1, using: &rng)
            let end = CGPoint(x: side * 105, y: Double.random(in: 10...60, using: &rng))
            let shade = Double.random(in: 0.5...2.4, using: &rng)
            ctx.setStrokeColor(colour(hair, shade, Double.random(in: 0.25...0.6, using: &rng)))
            ctx.setLineWidth(Double.random(in: 0.8...2.2, using: &rng))
            ctx.move(to: start)
            ctx.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2 + side * 30, y: start.y + 8))
            ctx.strokePath()
        }
        soft(ctx, at: CGPoint(x: -40, y: 110), radius: 50, (1, 0.95, 0.85), 1, alpha: 0.22)
        ctx.restoreGState()
        ctx.restoreGState()

        // Eyes, brows and the mouth sit on top.
        let eyeY = 20.0, io = 84.0
        for side in [-1.0, 1.0] {
            let ex = side * io / 2
            let open = 1 - 0.85 * s.blink
            let eye = CGRect(x: ex - 16, y: eyeY - 8 * open, width: 32, height: 16 * open)
            if s.blink < 0.5 {
                ctx.saveGState()
                let almond = CGMutablePath()
                almond.move(to: CGPoint(x: eye.minX, y: eyeY))
                almond.addQuadCurve(to: CGPoint(x: eye.maxX, y: eyeY), control: CGPoint(x: ex, y: eyeY + 15 * open))
                almond.addQuadCurve(to: CGPoint(x: eye.minX, y: eyeY), control: CGPoint(x: ex, y: eyeY - 11 * open))
                ctx.addPath(almond); ctx.clip()
                ctx.setFillColor(colour((0.93, 0.91, 0.88))); ctx.fill(eye.insetBy(dx: -2, dy: -4))
                ctx.drawRadialGradient(gradient([(0, colour((0.42, 0.27, 0.15))), (0.7, colour((0.30, 0.18, 0.10))), (1, colour((0.12, 0.07, 0.05)))]),
                                       startCenter: CGPoint(x: ex, y: eyeY), startRadius: 0, endCenter: CGPoint(x: ex, y: eyeY), endRadius: 8.5, options: [])
                ctx.setFillColor(colour((0.03, 0.02, 0.02))); ctx.fillEllipse(in: CGRect(x: ex - 3.5, y: eyeY - 3.5, width: 7, height: 7))
                ctx.setFillColor(colour((1, 1, 1), 1, 0.9)); ctx.fillEllipse(in: CGRect(x: ex - 4.5, y: eyeY + 1.5, width: 3.2, height: 3.2))
                soft(ctx, at: CGPoint(x: ex, y: eyeY + 9), radius: 12, (0, 0, 0), 1, alpha: 0.35)              // the lid's shadow
                ctx.restoreGState()
            }
            ctx.setStrokeColor(colour(hair, 0.8, 0.95)); ctx.setLineWidth(2.4); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: eye.minX - 1, y: eyeY)); ctx.addQuadCurve(to: CGPoint(x: eye.maxX + 1, y: eyeY), control: CGPoint(x: ex, y: eyeY + 16 * open)); ctx.strokePath()
            // Brows: a tapered stroke of short hairs.
            let browY = eyeY + io * (0.40 + 0.28 * s.browRaise)
            for i in 0..<26 {
                let f = Double(i) / 25
                let bx = ex + side * (-20 + 40 * f)
                let by = browY + 4 * sin(f * .pi) - 1.5
                ctx.setStrokeColor(colour(hair, 1.2, 0.7)); ctx.setLineWidth(1.6)
                ctx.move(to: CGPoint(x: bx, y: by - 3 * (1 - f))); ctx.addLine(to: CGPoint(x: bx + side * 5, y: by + 3)); ctx.strokePath()
            }
        }
        // Nostrils.
        for side in [-1.0, 1.0] {
            ctx.setFillColor(colour(skin, 0.42, 0.8)); ctx.fillEllipse(in: CGRect(x: side * 8 - 4, y: -33, width: 8, height: 4.5))
        }
        // The mouth: lips with a darker upper lip and a highlight on the lower, open when the mouth is.
        let mouthW = 70 * (1 + 0.35 * s.smile), mouthY = -60.0
        let gap = (2 + 40 * s.mouthOpen)
        let lip = CGMutablePath()
        lip.move(to: CGPoint(x: -mouthW / 2, y: mouthY))
        lip.addCurve(to: CGPoint(x: 0, y: mouthY + 8 + gap / 2), control1: CGPoint(x: -mouthW / 4, y: mouthY + 9 + gap / 2), control2: CGPoint(x: -6, y: mouthY + 12 + gap / 2))
        lip.addCurve(to: CGPoint(x: mouthW / 2, y: mouthY), control1: CGPoint(x: 6, y: mouthY + 12 + gap / 2), control2: CGPoint(x: mouthW / 4, y: mouthY + 9 + gap / 2))
        lip.addCurve(to: CGPoint(x: -mouthW / 2, y: mouthY), control1: CGPoint(x: mouthW / 4, y: mouthY - 14 - gap / 2), control2: CGPoint(x: -mouthW / 4, y: mouthY - 14 - gap / 2))
        ctx.addPath(lip); ctx.setFillColor(colour((0.74, 0.38, 0.37), skin.r < 0.6 ? 0.6 : 1)); ctx.fillPath()
        if s.mouthOpen > 0.05 {
            ctx.setFillColor(colour((0.22, 0.05, 0.06)))
            ctx.fillEllipse(in: CGRect(x: -mouthW * 0.38, y: mouthY - gap / 2, width: mouthW * 0.76, height: gap))
            ctx.setFillColor(colour((0.94, 0.92, 0.86)))
            ctx.fill(CGRect(x: -mouthW * 0.25, y: mouthY + gap / 2 - 6, width: mouthW * 0.5, height: 5))
        } else {
            ctx.setStrokeColor(colour((0.30, 0.10, 0.10), 1, 0.85)); ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: -mouthW / 2, y: mouthY)); ctx.addQuadCurve(to: CGPoint(x: mouthW / 2, y: mouthY), control: CGPoint(x: 0, y: mouthY - 3 - 6 * s.smile)); ctx.strokePath()
        }
        soft(ctx, at: CGPoint(x: -8, y: mouthY - 7), radius: 10, (1, 0.9, 0.85), 1, alpha: 0.3)
        ctx.restoreGState()

        guard let image = ctx.makeImage() else { return CIImage(color: .gray).cropped(to: rect) }
        // A real lens is never quite this crisp, and real skin has a fine texture.
        let picture = CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: 0.9).cropped(to: rect)
        return LookKit.grained(picture, frame: 17, rect: rect, amount: 0.09, size: 1.5)
    }

    private static var cachedRoom: CIImage?

    /// A lived-in room, out of focus: a wall, a window, a shelf of books, a lamp.
    static func roomPicture() -> CIImage {
        if let cachedRoom { return cachedRoom }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: Sprites.bitmapInfo) else {
            return CIImage(color: .gray).cropped(to: rect)
        }
        var rng = SplitMix64(seed: 2026)
        func colour(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
        let wall = CGGradient(colorsSpace: space, colors: [colour(0.82, 0.72, 0.62), colour(0.50, 0.40, 0.34)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(wall, start: CGPoint(x: 0, y: 720), end: CGPoint(x: 0, y: 0), options: [])
        // The window.
        ctx.setFillColor(colour(0.96, 0.98, 1.0)); ctx.fill(CGRect(x: 70, y: 280, width: 210, height: 330))
        ctx.setStrokeColor(colour(0.35, 0.27, 0.22)); ctx.setLineWidth(8)
        ctx.stroke(CGRect(x: 70, y: 280, width: 210, height: 330)); ctx.move(to: CGPoint(x: 175, y: 280)); ctx.addLine(to: CGPoint(x: 175, y: 610)); ctx.strokePath()
        // The shelf.
        ctx.setFillColor(colour(0.22, 0.15, 0.11)); ctx.fill(CGRect(x: 930, y: 0, width: 350, height: 720))
        for shelf in 0..<4 {
            let floor = 40.0 + Double(shelf) * 170
            var x = 944.0
            while x < 1260 {
                let width = Double.random(in: 16...36, using: &rng), height = Double.random(in: 90...150, using: &rng)
                let (r, g, b) = Palette.rgb(hue: Double.random(in: 0..<1, using: &rng), saturation: Double.random(in: 0.25...0.7, using: &rng), brightness: Double.random(in: 0.35...0.8, using: &rng))
                ctx.setFillColor(colour(r, g, b)); ctx.fill(CGRect(x: x, y: floor, width: width, height: height))
                ctx.setFillColor(colour(min(1, r + 0.25), min(1, g + 0.25), min(1, b + 0.25)))
                ctx.fill(CGRect(x: x + 2, y: floor + height * Double.random(in: 0.3...0.8, using: &rng), width: width - 4, height: 6))
                x += width + 2
            }
            ctx.setFillColor(colour(0.4, 0.29, 0.2)); ctx.fill(CGRect(x: 930, y: floor - 12, width: 350, height: 12))
        }
        // A lamp.
        ctx.glow(center: CGPoint(x: 830, y: 560), radius: 180, red: 1, green: 0.85, blue: 0.55, alpha: 0.9)
        ctx.setFillColor(colour(1, 0.95, 0.8)); ctx.fillEllipse(in: CGRect(x: 810, y: 540, width: 40, height: 40))
        // A few points of light left in the background.
        for _ in 0..<7 {
            ctx.glow(center: CGPoint(x: Double.random(in: 300...900, using: &rng), y: Double.random(in: 520...690, using: &rng)),
                     radius: Double.random(in: 12...34, using: &rng), red: 1, green: 0.9, blue: 0.7, alpha: 0.7)
        }
        guard let image = ctx.makeImage() else { return CIImage(color: .gray).cropped(to: rect) }
        // Out of focus, but not by much, and with plaster on the wall.
        let blurred = LookKit.grained(CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: 2.4).cropped(to: rect), frame: 31, rect: rect, amount: 0.12, size: 3)
        cachedRoom = blurred
        return blurred
    }

    /// Pictures laid out in a grid, so a dozen can be judged at a glance.
    static func sheet(_ images: [CIImage], columns: Int, scale: Double) -> CIImage {
        let cellW = rect.width * scale, cellH = rect.height * scale
        let rows = (images.count + columns - 1) / columns
        var sheet = CIImage(color: CIColor(red: 0.08, green: 0.08, blue: 0.08)).cropped(to: CGRect(x: 0, y: 0, width: cellW * Double(columns), height: cellH * Double(rows)))
        for (i, image) in images.enumerated() {
            let column = Double(i % columns), row = Double(rows - 1 - i / columns)
            let placed = image.cropped(to: rect).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: column * cellW, y: row * cellH))
            sheet = placed.composited(over: sheet)
        }
        return sheet
    }
}

/// Every look, in every state: renders at the right size with and without a person, and leaves pictures to look at.
final class LookFilterGalleryTests: XCTestCase {
    private let h = LensHarness()
    private let startOfUptime = 5000.0

    /// Seconds into the look to photograph it at: when the interesting thing is happening.
    private func moment(for id: String) -> Double {
        switch id {
        case "vhs":
            return stride(from: 0.0, to: 120, by: 0.1).first { (LookVHSPlan.tracking(at: $0, frameHeight: 720)?.strength ?? 0) > 0.95 } ?? 3
        case "duotone":
            // Halfway through a pair, not part-way into the next.
            return (ceil(startOfUptime / LookDuotonePlan.hold) + 0.25) * LookDuotonePlan.hold - startOfUptime
        case "neon-outline":
            return 2
        default:
            return 3.1
        }
    }

    /// Runs a few frames first, since several looks follow you from one frame to the next.
    private func render(_ info: LensInfo, _ state: LookFixture.State, at offset: Double) -> CIImage {
        let lens = info.make()
        let base = LookFixture.input(h, state)
        for i in 0..<6 { _ = lens.render(h.at(base, time: startOfUptime + Double(i) / 30)) }
        let image = lens.render(h.at(base, time: startOfUptime + offset)).cropped(to: LookFixture.rect)
        return image
    }

    func testEveryLookRendersInEveryStateAndLeavesPicturesToLookAt() {
        var sheets: [LookFixture.State: [CIImage]] = [:]
        for info in LookFilters.all {
            for state in LookFixture.State.allCases {
                let image = render(info, state, at: moment(for: info.id))
                XCTAssertEqual(image.extent, LookFixture.rect, "\(info.id) \(state)")
                let centre = h.pixel(image, 640, 360)
                XCTAssertTrue((0...255).contains(centre.r) && (0...255).contains(centre.g) && (0...255).contains(centre.b))
                Output.save(image, as: "look-\(info.id)-\(state.rawValue).png")
                // The sheets are for judging, so keep what they hold: render now, since lens pictures share drawing buffers.
                if let cg = h.ciContext.createCGImage(image, from: LookFixture.rect) { sheets[state, default: []].append(CIImage(cgImage: cg)) }
            }
        }
        for (state, images) in sheets { Output.save(LookFixture.sheet(images, columns: 2, scale: 0.5), as: "sheet-\(state.rawValue).png") }
    }

    func testTheOriginalsToCompareWith() {
        for state in LookFixture.State.allCases {
            Output.save(LookFixture.input(h, state).composed, as: "original-\(state.rawValue).png")
        }
        Output.save(h.input().composed, as: "original-cartoon.png")
    }

    func testEveryLookCopesWithAMissingCutoutBackdropFaceAndAHugePause() {
        let base = LookFixture.input(h, .backdrop)
        let bare = LensInput(time: 9_000_000, dt: 7, rect: base.rect, camera: base.camera, matte: nil, background: nil, composed: base.camera,
                             matteGrid: nil, face: nil, services: base.services)
        for info in LookFilters.all {
            let lens = info.make()
            for input in [bare, h.at(base, time: 12, dt: 5), h.at(base, time: 0, dt: 0)] {
                let image = lens.render(input).cropped(to: input.rect)
                XCTAssertEqual(image.extent, input.rect, info.id)
                _ = h.pixel(image, 10, 10)
            }
            lens.restart()
            XCTAssertEqual(lens.render(base).cropped(to: base.rect).extent, base.rect, "\(info.id) after a restart")
        }
    }

    func testTheCartoonFromTheSharedSceneAlsoRenders() {
        let base = h.input()
        for info in LookFilters.all {
            let image = info.make().render(h.at(base, time: 2)).cropped(to: base.rect)
            Output.save(image, as: "look-\(info.id)-cartoon.png")
            XCTAssertEqual(image.extent, base.rect)
        }
    }
}

/// What each look does to the picture, in numbers.
final class LookFilterBehaviourTests: XCTestCase {
    private let h = LensHarness()
    private let t0 = 5000.0

    private func diff(_ a: RGB, _ b: RGB) -> Int { abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) }

    private func lens(_ id: String) -> Lens { guard let info = LookFilters.all.first(where: { $0.id == id }) else { fatalError("no look \(id)") }; return info.make() }

    private func run(_ id: String, _ base: LensInput, seconds: Double, frames: Int = 8) -> CIImage {
        let l = lens(id)
        var out = base.composed
        for i in 0...frames { out = l.render(h.at(base, time: t0 + seconds * Double(i) / Double(frames))) }
        return out.cropped(to: base.rect)
    }

    // MARK: Neon

    func testNeonTraceTheOutlineInGlowingColourAndDarkensTheRoom() {
        let base = LookFixture.input(h, .backdrop)
        let out = run("neon-outline", base, seconds: 2)
        // Just outside the side of the head the tube glows brightly; the face is as it was; the far room is much darker.
        var best = 0
        for x in 730...790 { best = max(best, diff(h.pixel(out, x, 440), h.pixel(base.composed, x, 440))) }
        XCTAssertGreaterThan(best, 200, "a bright tube round the head")
        XCTAssertLessThan(diff(h.pixel(out, 640, 400), h.pixel(base.composed, 640, 400)), 70, "your face is left alone")
        let room = h.average(out, CGRect(x: 20, y: 500, width: 200, height: 200)), before = h.average(base.composed, CGRect(x: 20, y: 500, width: 200, height: 200))
        XCTAssertLessThan(room.r + room.g + room.b, (before.r + before.g + before.b) * 0.7, "the room is dark")
    }

    func testNeonColourWandersAroundTheWheelAndTheSignStutters() {
        XCTAssertNotEqual(LookNeonPlan.hue(at: 0), LookNeonPlan.hue(at: 12), accuracy: 0.3)
        for t in stride(from: 0.0, to: 300, by: 0.37) {
            XCTAssertTrue((0..<1).contains(LookNeonPlan.hue(at: t)))
            XCTAssertTrue((0.25...1).contains(LookNeonPlan.brightness(at: t)))
        }
        let dim = stride(from: 0.0, to: 120, by: 1.0 / 30).filter { LookNeonPlan.brightness(at: $0) < 0.9 }.count
        XCTAssertGreaterThan(dim, 5, "it flickers sometimes")
        XCTAssertLessThan(dim, 600, "but not most of the time")
        XCTAssertEqual(LookNeonPlan.brightness(at: 33.3), LookNeonPlan.brightness(at: 33.3))
        let base = LookFixture.input(h, .backdrop)
        let a = run("neon-outline", base, seconds: 0.1), b = LookNeonLens().render(h.at(base, time: t0 + 12.5)).cropped(to: base.rect)
        XCTAssertGreaterThan(diff(h.pixel(a, 640, 580), h.pixel(b, 640, 580)) + diff(h.pixel(a, 757, 440), h.pixel(b, 757, 440)), 30, "the colour has moved on")
    }

    // MARK: Thermal

    func testThermalMakesYouWarmAndTheRoomCold() {
        let base = LookFixture.input(h, .backdrop)
        let out = run("thermal", base, seconds: 1)
        let face = h.average(out, CGRect(x: 600, y: 380, width: 80, height: 60)), room = h.average(out, CGRect(x: 30, y: 30, width: 200, height: 200))
        XCTAssertGreaterThan(face.r, 0.8, "a face reads yellow or white, got \(face)")
        XCTAssertGreaterThan(face.g, room.g + 0.3, "and the cold room stays dark and purple, got \(room)")
        XCTAssertLessThan(room.g, 0.2)
    }

    func testThermalAimsAtTheTopOfTheHeadAndAnnouncesNothingWhenEmpty() {
        let base = LookFixture.input(h, .backdrop)
        let aim = LookThermalPlan.aim(in: base.matteGrid!)
        XCTAssertNotNil(aim)
        if let aim { XCTAssertEqual(aim.x, 640, accuracy: 40); XCTAssertEqual(aim.y, 506, accuracy: 60, "just inside the crown, at \(aim)") }
        XCTAssertNil(LookThermalPlan.aim(in: MatteGrid(outputSize: SyntheticScene.size)))
        for t in stride(from: 0.0, to: 60, by: 0.3) { XCTAssertTrue((35...38).contains(LookThermalPlan.reading(at: t))); XCTAssertTrue((20...23).contains(LookThermalPlan.ambient(at: t))) }
    }

    // MARK: Old film

    func testOldFilmIsOneWarmToneWithDarkCorners() {
        let base = LookFixture.input(h, .backdrop)
        let out = run("old-film", base, seconds: 1)
        let corner = h.average(out, CGRect(x: 0, y: 0, width: 80, height: 80)), middle = h.average(out, CGRect(x: 560, y: 300, width: 160, height: 120))
        XCTAssertLessThan(corner.r + corner.g + corner.b, (middle.r + middle.g + middle.b) * 0.8, "vignette")
        XCTAssertGreaterThan(middle.r, middle.b + 0.03, "warm tone, got \(middle)")
        XCTAssertLessThan(middle.r - middle.b, 0.35, "but not colourful, got \(middle)")
        XCTAssertGreaterThan(middle.g, middle.b)
    }

    func testOldFilmDirtIsDifferentOnEachFrameButTheSameEachTime() {
        let a = LookFilmPlan.marks(frame: 10, size: SyntheticScene.size), b = LookFilmPlan.marks(frame: 11, size: SyntheticScene.size)
        XCTAssertEqual(a, LookFilmPlan.marks(frame: 10, size: SyntheticScene.size))
        XCTAssertNotEqual(a, b)
        var scratches = 0
        for frame in 0..<600 {
            for case let .scratch(x, from, to, _, _) in LookFilmPlan.marks(frame: frame, size: SyntheticScene.size) {
                scratches += 1
                XCTAssertTrue((0...1280).contains(x) && (0...720).contains(from) && (0...720).contains(to) && from > to)
            }
            let shake = LookFilmPlan.weave(frame: frame)
            XCTAssertTrue(abs(shake.dx) <= 2.2 && abs(shake.dy) <= 1.6)
            XCTAssertTrue((0.7...1.05).contains(LookFilmPlan.exposure(frame: frame)))
        }
        XCTAssertGreaterThan(scratches, 100, "scratches come and go")
        XCTAssertEqual(LookFilmPlan.frame(at: 1.0), 12)
    }

    // MARK: VHS

    func testVHSTrackingRollsUpTheFrameNowAndThen() {
        var seen = 0
        var lastY: [Int: Double] = [:]
        for t in stride(from: 0.0, to: 200, by: 1.0 / 30) {
            guard let band = LookVHSPlan.tracking(at: t, frameHeight: 720) else { continue }
            seen += 1
            XCTAssertTrue((0...1).contains(band.strength) && band.height >= 70 && band.height <= 130)
            let cycle = Int(t / LookVHSPlan.cycle)
            if let before = lastY[cycle] { XCTAssertGreaterThan(band.y, before, "it rolls upwards") }
            lastY[cycle] = band.y
        }
        let share = Double(seen) / (200 * 30)
        XCTAssertGreaterThan(share, 0.1, "it tracks badly fairly often")
        XCTAssertLessThan(share, 0.5)
        XCTAssertEqual(LookVHSPlan.tracking(at: 21.7, frameHeight: 720), LookVHSPlan.tracking(at: 21.7, frameHeight: 720))
        let band = LookVHSPlan.Band(y: 100, height: 100, strength: 1)
        XCTAssertEqual(LookVHSPlan.shifts(of: band, count: 9, time: 3).count, 9)
        XCTAssertTrue(LookVHSPlan.shifts(of: LookVHSPlan.Band(y: 100, height: 100, strength: 0), count: 9, time: 3).allSatisfy { $0 == 0 })
    }

    func testVHSPutsPlayAndADateOnThePictureAndBleedsColourRight() {
        let base = LookFixture.input(h, .backdrop)
        let fixed = Date(timeIntervalSince1970: 1_000_000_000)      // 2001-09-09
        let tape = LookVHSLens(startDate: fixed)
        var out = base.composed
        for i in 0...6 { out = tape.render(h.at(base, time: t0 + Double(i) / 30)) }
        out = out.cropped(to: base.rect)
        let picture = h.bitmap(out)
        func whiteCount(_ r: CGRect) -> Int {
            var n = 0
            for x in stride(from: Int(r.minX), to: Int(r.maxX), by: 2) { for y in stride(from: Int(r.minY), to: Int(r.maxY), by: 2) { let p = picture.pixel(x, y); if min(p.r, p.g, p.b) > 150 { n += 1 } } }
            return n
        }
        XCTAssertGreaterThan(whiteCount(CGRect(x: 60, y: 600, width: 260, height: 70)), 40, "PLAY is up in the corner")
        XCTAssertGreaterThan(whiteCount(CGRect(x: 60, y: 50, width: 360, height: 110)), 40, "and the date is down in the other")
        XCTAssertEqual(LookClock.day(fixed).prefix(4), "SEP.")
        // Scan lines: neighbouring rows differ in brightness more than they do in the original.
        var lines = 0
        for y in 200..<260 { lines += abs(picture.pixel(400, y).g - picture.pixel(400, y + 1).g) }
        XCTAssertGreaterThan(lines, 150, "scan lines")
    }

    // MARK: Night vision

    func testNightVisionIsGreenAndShowsARedDotOnlyWhileItBlinksOn() {
        let base = LookFixture.input(h, .backdrop)
        let lit = LookNightVisionLens(), unlit = LookNightVisionLens()
        _ = lit.render(h.at(base, time: t0)); _ = unlit.render(h.at(base, time: t0))
        let on = lit.render(h.at(base, time: t0 + 0.2)).cropped(to: base.rect), off = unlit.render(h.at(base, time: t0 + 0.8)).cropped(to: base.rect)
        let face = h.average(on, CGRect(x: 600, y: 380, width: 80, height: 60))
        XCTAssertGreaterThan(face.g, face.r * 1.3, "green, got \(face)")
        XCTAssertGreaterThan(face.g, face.b * 1.3)
        XCTAssertGreaterThan(face.g, 0.2, "and bright enough to see you")
        let dot = h.pixel(on, 77, 720 - 64 - 30 + 19)
        XCTAssertGreaterThan(dot.r, 180, "REC dot, got \(dot)")
        XCTAssertLessThan(dot.g, 90)
        XCTAssertLessThan(h.pixel(off, 77, 720 - 64 - 30 + 19).r, 120, "dot is off")
        XCTAssertTrue(LookNightVisionLens.recordDotIsLit(at: 0.2) && !LookNightVisionLens.recordDotIsLit(at: 0.8))
        let centre = h.average(on, CGRect(x: 560, y: 300, width: 160, height: 120)), corner = h.average(on, CGRect(x: 0, y: 0, width: 60, height: 60))
        XCTAssertLessThan(corner.g, centre.g * 0.7, "the infra-red light gives out at the edges")
    }

    func testCameraClocksReadLikeCameras() {
        XCTAssertEqual(LookClock.counter(83.4), "0:01:23")
        XCTAssertEqual(LookClock.counter(-5), "0:00:00")
        XCTAssertEqual(LookClock.counter(3725), "1:02:05")
        XCTAssertEqual(LookClock.timecode(83.5, fps: 30), "00:01:23:15")
        XCTAssertEqual(LookClock.timecode(0.999, fps: 30), "00:00:00:29")
        var clock = LookClock(startDate: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(clock.elapsed(at: 7000), 0)
        XCTAssertEqual(clock.elapsed(at: 7002.5), 2.5, accuracy: 1e-9)
        XCTAssertEqual(clock.elapsed(at: 6000), 0, "never runs backwards")
        clock.restart()
        XCTAssertEqual(clock.elapsed(at: 9000), 0)
        XCTAssertEqual(clock.date(after: 60).timeIntervalSince1970, 60)
    }

    // MARK: Halftone

    func testHalftoneBuildsThePictureOutOfDotsOnCreamPaper() {
        let base = LookFixture.input(h, .room)
        let out = run("halftone", base, seconds: 1)
        let picture = h.bitmap(out)
        var jumps = 0, samples = 0
        for x in stride(from: 100, to: 500, by: 3) {
            for y in stride(from: 100, to: 300, by: 6) { jumps += diff(picture.pixel(x, y), picture.pixel(x + 3, y)); samples += 1 }
        }
        XCTAssertGreaterThan(Double(jumps) / Double(samples), 25, "dots make the picture busy at a fine scale")
        // The window is bright, so it prints as bare cream paper.
        let window = picture.pixel(120, 450)
        XCTAssertGreaterThan(window.r, 215); XCTAssertGreaterThan(window.g, 200); XCTAssertGreaterThan(window.b, 150); XCTAssertLessThan(window.b, window.r, "cream, not white")
        XCTAssertNotEqual(LookHalftoneLens.screenAngle(at: 0), LookHalftoneLens.screenAngle(at: 4.5), accuracy: 0.05)
    }

    // MARK: Pencil

    func testPencilIsMostlyPaperWithDarkLinesOnIt() {
        let base = LookFixture.input(h, .room)
        let out = run("pencil-sketch", base, seconds: 1)
        let wall = h.average(out, CGRect(x: 400, y: 600, width: 200, height: 80))
        XCTAssertGreaterThan(wall.r + wall.g + wall.b, 2.0, "flat areas are paper, got \(wall)")
        let drawing = h.bitmap(out)
        var darkest = 255
        for x in stride(from: 560, to: 720, by: 1) { for y in 535..<575 { let p = drawing.pixel(x, y); darkest = min(darkest, min(p.r, p.g, p.b)) } }
        XCTAssertLessThan(darkest, 120, "the crown of the head is drawn in")
        XCTAssertLessThan(abs(wall.r - wall.b), 0.15, "graphite and paper, not colour")
    }

    func testPencilLinesBoilWhilePaperStaysPut() {
        let base = LookFixture.input(h, .room)
        let lens = LookPencilLens()
        let a = lens.render(h.at(base, time: t0)).cropped(to: base.rect), bitmapA = h.bitmap(a)
        let b = lens.render(h.at(base, time: t0 + 1.0 / 8 + 0.01)).cropped(to: base.rect), bitmapB = h.bitmap(b)
        let c = lens.render(h.at(base, time: t0 + 0.01)).cropped(to: base.rect), bitmapC = h.bitmap(c)
        XCTAssertGreaterThan(bitmapA.change(from: bitmapB, in: CGRect(x: 500, y: 540, width: 300, height: 60)), 40, "redrawn")
        XCTAssertEqual(bitmapA.change(from: bitmapC, in: CGRect(x: 500, y: 540, width: 300, height: 60)), 0, "but steady between redraws")
    }

    // MARK: Oil

    func testOilPaintKeepsTheShapesAndLosesTheFineDetail() {
        let base = LookFixture.input(h, .room)
        let out = run("oil-painting", base, seconds: 1)
        let before = h.average(base.composed, CGRect(x: 560, y: 300, width: 160, height: 120)), after = h.average(out, CGRect(x: 560, y: 300, width: 160, height: 120))
        XCTAssertEqual(after.r, before.r, accuracy: 0.14); XCTAssertEqual(after.g, before.g, accuracy: 0.14); XCTAssertEqual(after.b, before.b, accuracy: 0.14)
        XCTAssertGreaterThan(diff(h.pixel(out, 640, 400), h.pixel(base.composed, 640, 400)) + diff(h.pixel(out, 300, 500), h.pixel(base.composed, 300, 500)), 8)
    }

    // MARK: Cyberpunk

    func testCyberpunkGradePullsShadowsToTealAndLightsToPink() {
        let shadow = LookCyberpunkLens.grade(SIMD3<Float>(0.12, 0.12, 0.12)), light = LookCyberpunkLens.grade(SIMD3<Float>(0.92, 0.92, 0.92))
        XCTAssertGreaterThan(shadow.y, shadow.x + 0.05, "shadows lean teal, got \(shadow)")
        XCTAssertGreaterThan(shadow.z, shadow.x + 0.05)
        XCTAssertGreaterThan(light.x, light.y + 0.05, "highlights lean pink, got \(light)")
        XCTAssertGreaterThan(light.z, light.y)
        for v: Float in [0, 0.3, 0.7, 1] { let g = LookCyberpunkLens.grade(SIMD3<Float>(v, 1 - v, v)); XCTAssertTrue((0...1).contains(g.x) && (0...1).contains(g.y) && (0...1).contains(g.z)) }
        XCTAssertNil(LookCyberpunkLens.flare(at: 5), "a flare crosses now and then, not always")
        XCTAssertNotNil(LookCyberpunkLens.flare(at: 1.4))
    }

    func testCyberpunkChangesTheColourButNotTheScene() {
        let base = LookFixture.input(h, .room)
        let out = run("cyberpunk", base, seconds: 1)
        XCTAssertGreaterThan(diff(h.pixel(out, 640, 400), h.pixel(base.composed, 640, 400)), 30)
        let a = h.average(out, CGRect(x: 600, y: 380, width: 80, height: 60)), b = h.average(base.composed, CGRect(x: 600, y: 380, width: 80, height: 60))
        XCTAssertGreaterThan(a.r + a.g + a.b, (b.r + b.g + b.b) * 0.5, "still bright enough to see you")
        XCTAssertGreaterThan(a.b, b.b * 0.9, "the colour has moved toward magenta, got \(a) from \(b)")
    }

    // MARK: Duotone

    func testDuotonePrintsYouAndTheRoomInTheSameInksAStepApart() {
        let base = LookFixture.input(h, .backdrop)
        let out = run("duotone", base, seconds: 0.2, frames: 2)
        let inks = LookDuotonePlan.inks(at: t0 + 0.2)
        // Every pixel inside you sits on the line between your two inks; so does every pixel in the room.
        func onLine(_ p: RGB, _ a: LookColour, _ b: LookColour) -> Bool {
            let lo = (min(a.r, b.r) * 255 - 25, min(a.g, b.g) * 255 - 25, min(a.b, b.b) * 255 - 25)
            let hi = (max(a.r, b.r) * 255 + 25, max(a.g, b.g) * 255 + 25, max(a.b, b.b) * 255 + 25)
            return Double(p.r) >= lo.0 && Double(p.r) <= hi.0 && Double(p.g) >= lo.1 && Double(p.g) <= hi.1 && Double(p.b) >= lo.2 && Double(p.b) <= hi.2
        }
        let poster = h.bitmap(out)
        var inside = 0, total = 0
        for x in stride(from: 560, to: 720, by: 5) { for y in stride(from: 330, to: 480, by: 5) { total += 1; if onLine(poster.pixel(x, y), inks.dark, inks.light) { inside += 1 } } }
        XCTAssertGreaterThan(Double(inside) / Double(total), 0.4, "much of the face is near the line between the two inks (the vivid middle colour strays from it)")
        // You are brighter than the room, which sits a step darker.
        let faceLight = h.average(out, CGRect(x: 600, y: 380, width: 80, height: 60)), wall = h.average(out, CGRect(x: 20, y: 20, width: 200, height: 100))
        XCTAssertGreaterThan(faceLight.r + faceLight.g + faceLight.b, wall.r + wall.g + wall.b)
    }

    func testDuotoneInksChangeSmoothlyAndAlwaysBelongToThePalette() {
        var previous = LookDuotonePlan.inks(at: 0)
        for t in stride(from: 0.1, to: 120, by: 0.1) {
            let now = LookDuotonePlan.inks(at: t)
            XCTAssertLessThan(abs(now.dark.r - previous.dark.r) + abs(now.dark.g - previous.dark.g) + abs(now.dark.b - previous.dark.b), 0.25, "no jumps at \(t)")
            XCTAssertLessThan(abs(now.light.r - previous.light.r) + abs(now.light.g - previous.light.g) + abs(now.light.b - previous.light.b), 0.35)
            previous = now
        }
        let first = LookDuotonePlan.inks(at: 0), later = LookDuotonePlan.inks(at: LookDuotonePlan.hold * 2)
        XCTAssertGreaterThan(abs(first.light.r - later.light.r) + abs(first.light.g - later.light.g) + abs(first.light.b - later.light.b), 0.3, "the inks change")
        let before = LookDuotonePlan.inks(at: -3)
        XCTAssertTrue((0...1).contains(before.dark.r) && (0...1).contains(before.light.g), "a clock that starts before zero still gives real colours")
    }
}

/// How the looks are listed in the picker.
final class LookFilterCatalogTests: XCTestCase {
    func testTwentyLooksAreOfferedAsFiltersThatNeedNoFaceOrHands() {
        XCTAssertEqual(LookFilters.all.count, 20)
        XCTAssertEqual(Set(LookFilters.all.map(\.id)).count, 20, "ids are unique")
        for info in LookFilters.all {
            XCTAssertEqual(info.category, .filters)
            XCTAssertFalse(info.needsFace); XCTAssertFalse(info.needsHands); XCTAssertFalse(info.scored)
            XCTAssertNotNil(info.id.range(of: "^[a-z]+(-[a-z]+)*$", options: .regularExpression), "\(info.id) is kebab-case")
            XCTAssertEqual(info.glyph.count, 1, "\(info.id) has one emoji")
            XCTAssertFalse(info.name.isEmpty)
            XCTAssertTrue(info.blurb.hasSuffix("."), info.id)
            XCTAssertLessThan(info.blurb.count, 80, "\(info.id): the blurb should be short")
            XCTAssertEqual(info.make().needs.contains(.face), info.needsFace)
            XCTAssertEqual(info.make().needs.contains(.hands), info.needsHands)
            XCTAssertNotNil(LensCatalog.info(for: info.id), "\(info.id) is in the catalog")
        }
    }

    func testTheLooksThatWriteOnThePictureSayTheyDo() {
        let writers = Set(LookFilters.all.filter(\.showsText).map(\.id))
        XCTAssertEqual(writers, ["thermal", "vhs", "night-vision", "instant-photo", "blueprint"])
    }

    func testLooksThatNeedTheCutoutAskForIt() {
        let needing = Set(LookFilters.all.filter { $0.make().needs.contains(.matte) }.map(\.id))
        XCTAssertEqual(needing, ["neon-outline", "thermal", "duotone", "film-noir", "dreamy-glow", "golden-hour", "hologram", "stained-glass",
                                 "watercolour", "blueprint"])
    }

    func testNoIdClashesWithTheFiltersAlreadyThere() {
        let ids = LensCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "every id in the catalog is unique")
    }
}

/// Speed: each look should add only a few milliseconds to a frame.
final class LookFilterCostTests: XCTestCase {
    private let h = LensHarness()

    func testEveryLookIsCheap() {
        let base = LookFixture.input(h, .backdrop)
        let baseline = h.cost(of: PassThroughLookProbe(), base: base).mean
        print(String(format: "LOOK-COST baseline mean %.1f ms", baseline))
        for info in LookFilters.all {
            // About fourteen builds share this Mac, so a busy moment can double a reading: the better of two runs is the one to trust.
            let first = h.cost(of: info.make(), base: base, frames: 45), second = h.cost(of: info.make(), base: base, frames: 45)
            let cost = first.mean < second.mean ? first : second
            print(String(format: "LOOK-COST %@ mean %.1f ms (+%.1f), worst %.1f ms", info.id, cost.mean, cost.mean - baseline, cost.worst))
            XCTAssertLessThan(cost.mean - baseline, 9, "\(info.id) adds \(Int(cost.mean - baseline)) ms a frame")
        }
    }
}

private final class PassThroughLookProbe: Lens {
    let needs: LensNeeds = []
    func render(_ input: LensInput) -> CIImage { input.composed }
}
