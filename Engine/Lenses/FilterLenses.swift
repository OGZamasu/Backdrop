import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Looks built from the picture itself: a comic panel, pixel art, a twin and a kaleidoscope.

/// A comic-book panel: flat colour in a few steps of light, Ben-Day dots in the shadows, bold ink lines (heaviest round your
/// outline), all inside a panel border on warm paper.
final class ComicLens: Lens {
    let needs: LensNeeds = [.matte]

    private static let ink: LookColour = (0.06, 0.05, 0.08)
    private static let paper: LookColour = (0.99, 0.96, 0.89)

    /// The colour kept, the light flattened into four steps with soft edges, the colour a little bolder.
    private static let cel = LookGrade { c in
        let hsv = LookTone.hsv(c)
        let steps: [Float] = [0.13, 0.40, 0.70, 0.96]
        let edges: [Float] = [0.2, 0.44, 0.7]
        var value = steps[0]
        for i in 1..<steps.count { value += (steps[i] - steps[i - 1]) * LookTone.smooth(edges[i - 1] - 0.025, edges[i - 1] + 0.025, hsv.z) }
        let saturation = min(1, hsv.y * 1.3 + 0.03)
        return LookTone.rgb(hsv: SIMD3(hsv.x, saturation, value))
    }

    private let border = LookDisplayCache()

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let half = LookKit.size(of: rect, scaledBy: 0.5)

        // Flat colour: smoothed while keeping edges, so a face becomes a few clean shapes rather than noise.
        let small = LookKit.shrink(input.composed, rect: rect, by: 0.5)
        let smooth = small.applyingFilter("CIGuidedFilter", parameters: ["inputGuideImage": small, "inputRadius": 5.0, "inputEpsilon": 0.003])
            .cropped(to: half)
        let flat = Self.cel.apply(smooth)

        // Ink, the way an inker sees it: wherever a small blur is darker than a wider one there is a line (eyes, brows, lips, the
        // edge of the hair), plus a heavier line all round your outline.
        let tone = LookKit.perceptual(LookKit.grey(smooth)).clampedToExtent()
        let near = tone.applyingGaussianBlur(sigma: 0.8), wide = tone.applyingGaussianBlur(sigma: 2.2)
        var lines = LookKit.levels(near.applyingFilter("CISubtractBlendMode", parameters: [kCIInputBackgroundImageKey: wide]).cropped(to: half), gain: 16, bias: -0.35)
        if let matte = input.matte {
            let solid = LookKit.levels(LookKit.shrink(matte, rect: rect, by: 0.5), gain: 6, bias: -2.5)
            let outline = solid.clampedToExtent().applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: 2.0]).cropped(to: half)
            lines = lines.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: outline])
        }
        // Each line, a pixel wide at half size, is drawn back at full size as a solid stroke of ink with a soft edge.
        let inkMask = LookKit.levels(LookKit.enlarge(lines, to: rect, from: half).applyingGaussianBlur(sigma: 0.6).cropped(to: rect), gain: 2.6)

        // Ben-Day dots in the shadows, in a deep blue-violet, as the old presses did.
        let colour = LookKit.enlarge(flat, to: rect, from: half)
        let shade = LookKit.levels(LookKit.perceptual(LookKit.grey(colour)), gain: -2.4, bias: 1.25)
        let dots = LookKit.levels(shade, gain: -0.55, bias: 1).applyingFilter("CIDotScreen", parameters: [
            kCIInputCenterKey: CIVector(x: rect.midX, y: rect.midY), kCIInputAngleKey: 0.785, kCIInputWidthKey: 7.0, kCIInputSharpnessKey: 0.75,
        ]).cropped(to: rect)
        let dotted = LookKit.multiply(dots.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(red: 0.42, green: 0.38, blue: 0.62), "inputColor1": CIColor(red: 1, green: 1, blue: 1),
        ]), over: colour)

        let printed = LookKit.multiply(CIImage(color: LookKit.ciColour(Self.paper)).cropped(to: rect), over: dotted)
        let inked = LookKit.blend(CIImage(color: LookKit.ciColour(Self.ink)).cropped(to: rect), over: printed, mask: inkMask)
        let paper = LookKit.grained(inked, frame: 3, rect: rect, amount: 0.07, size: 1.4)
        guard let frame = border.layer("\(Int(rect.width))x\(Int(rect.height))", size: rect.size, draw: { ctx in Self.drawBorder(ctx, rect: rect) }) else {
            return paper.cropped(to: rect)
        }
        return frame.composited(over: paper).cropped(to: rect)
    }

    /// A white gutter and a bold black panel line, like a page of a comic.
    private static func drawBorder(_ ctx: CGContext, rect: CGRect) {
        let gutter: CGFloat = 12, line: CGFloat = 5
        let space = LookKit.space
        ctx.setFillColor(CGColor(colorSpace: space, components: [CGFloat(paper.r), CGFloat(paper.g), CGFloat(paper.b), 1])!)
        ctx.addRect(rect)
        ctx.addRect(rect.insetBy(dx: gutter, dy: gutter))
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [CGFloat(ink.r), CGFloat(ink.g), CGFloat(ink.b), 1])!)
        ctx.setLineWidth(line)
        ctx.stroke(rect.insetBy(dx: gutter + line / 2, dy: gutter + line / 2))
    }
}

/// Chunky pixels in a hand-picked palette, shaded with an ordered dither, and you outlined like a sprite in a game.
final class PixelArtLens: Lens {
    let needs: LensNeeds = [.matte]
    private let block: Double

    init(block: Double = 14) { self.block = block }

    /// "Backdrop 26": greys from ink to paper, two ramps of skin, warm and cool colours, picked to sit well together.
    static let palette: [LookColour] = [
        (0.07, 0.06, 0.10), (0.16, 0.15, 0.26), (0.29, 0.31, 0.42), (0.50, 0.52, 0.60), (0.74, 0.76, 0.80), (0.96, 0.95, 0.91),   // ink to paper
        (0.30, 0.18, 0.14), (0.48, 0.30, 0.22), (0.68, 0.46, 0.34), (0.86, 0.64, 0.52), (0.97, 0.81, 0.69),                       // skin
        (0.45, 0.12, 0.18), (0.80, 0.22, 0.24), (0.94, 0.50, 0.20), (0.98, 0.78, 0.30), (0.99, 0.93, 0.60),                       // warm
        (0.12, 0.34, 0.25), (0.30, 0.62, 0.30), (0.66, 0.86, 0.40),                                                               // green
        (0.14, 0.22, 0.45), (0.22, 0.42, 0.78), (0.45, 0.72, 0.94), (0.16, 0.55, 0.60),                                           // blue
        (0.36, 0.18, 0.42), (0.58, 0.36, 0.72), (0.93, 0.52, 0.66),                                                               // violet
    ]

    private static let paletteImage: CIImage? = {
        guard let ctx = CGContext(data: nil, width: palette.count, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: LookKit.space,
                                  bitmapInfo: Sprites.bitmapInfo) else { return nil }
        for (i, c) in palette.enumerated() {
            ctx.setFillColor(CGColor(colorSpace: LookKit.space, components: [CGFloat(c.r), CGFloat(c.g), CGFloat(c.b), 1])!)
            ctx.fill(CGRect(x: i, y: 0, width: 1, height: 1))
        }
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }()

    /// A 4 by 4 ordered-dither pattern, tiled forever, values spread evenly from -0.5 to 0.5.
    private static let bayer: CIImage? = {
        let order: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
        guard let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        for (i, v) in order.enumerated() {
            ctx.setFillColor(gray: (CGFloat(v) + 0.5) / 16, alpha: 1)
            ctx.fill(CGRect(x: i % 4, y: i / 4, width: 1, height: 1))
        }
        return ctx.makeImage().map { CIImage(cgImage: $0, options: [.colorSpace: NSNull()]).samplingNearest() }
    }()

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        guard let palette = Self.paletteImage else { return input.composed }
        // The grid is anchored at the corner of the picture, one cell per block.
        let cells = CGRect(x: 0, y: 0, width: (rect.width / block).rounded(.up), height: (rect.height / block).rounded(.up))
        func down(_ image: CIImage) -> CIImage {
            let moved = image.clampedToExtent().transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = moved
            lanczos.scale = Float(1 / block)
            lanczos.aspectRatio = 1
            return (lanczos.outputImage ?? moved).cropped(to: cells)
        }

        // A little more punch than a camera gives, so the palette has something to bite on.
        let eye = LookKit.perceptual(down(input.composed))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.2, kCIInputContrastKey: 1.08])
        // Ordered dither: each cell nudged up or down by its place in the pattern before it picks a colour, so gradients become
        // the familiar checker of in-between shades.
        var dithered = eye
        if let bayer = Self.bayer {
            let tile = CIFilter.affineTile()
            tile.inputImage = bayer
            tile.transform = .identity
            // Linear light adds twice the distance from mid grey, so a pattern squeezed round 0.5 nudges by plus or minus 0.035:
            // enough to break a gradient into a checker, not so much that flat areas fizz.
            let nudge = (tile.outputImage ?? bayer)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.035, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0.035, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0.035, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0.4825, y: 0.4825, z: 0.4825, w: 1),
                ]).cropped(to: cells)
            dithered = nudge.applyingFilter("CILinearLightBlendMode", parameters: [kCIInputBackgroundImageKey: eye]).cropped(to: cells)
        }
        var art = LookKit.linear(dithered).applyingFilter("CIPalettize", parameters: ["inputPaletteImage": palette, "inputPerceptual": true])
            .cropped(to: cells)

        // A one-cell dark outline round you, as a sprite has.
        if let matte = input.matte {
            let you = LookKit.levels(down(matte), gain: 6, bias: -2.6)
            let grown = you.clampedToExtent().applyingFilter("CIMorphologyRectangleMaximum", parameters: ["inputWidth": 3.0, "inputHeight": 3.0]).cropped(to: cells)
            let outline = LookKit.levels(grown.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: you]), gain: 2, bias: -0.5)
            let c = Self.palette[1]
            art = LookKit.blend(CIImage(color: LookKit.ciColour(c)).cropped(to: cells), over: art, mask: outline).cropped(to: cells)
        }

        return art.samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: block, y: block))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            .cropped(to: rect)
    }
}

/// Where a head is, read off the top of the cutout, so a look can frame you without face tracking. Pure, so it can be tested.
enum LookHead {
    struct Found: Equatable {
        /// Roughly the middle of the face.
        var centre: CGPoint
        /// How wide the head is, in pixels.
        var width: Double
        /// The crown of the head.
        var top: Double
    }

    /// Nil when nobody is in view.
    static func find(in grid: MatteGrid) -> Found? {
        guard grid.fraction > 0.005 else { return nil }
        var top: Int?
        search: for row in 0..<grid.height {
            for column in 0..<grid.width where grid.cells[row * grid.width + column] > 127 { top = row; break search }
        }
        guard let top else { return nil }
        // Walk down the head until the outline widens sharply into the shoulders, or a head's height has passed.
        var sumX = 0.0, count = 0.0, widest = 0.0, narrowed = false
        let limit = min(grid.height, top + Int(260 / grid.cellSize))
        for row in top..<limit {
            var lo = Int.max, hi = Int.min, rowSum = 0.0, rowCount = 0.0
            for column in 0..<grid.width where grid.cells[row * grid.width + column] > 127 {
                lo = min(lo, column); hi = max(hi, column); rowSum += Double(column) + 0.5; rowCount += 1
            }
            guard hi >= lo else { continue }
            let span = Double(hi - lo + 1)
            if row - top > 3, widest > 0, span > widest * 1.3 { break }
            // Past the neck, whatever widens again is the shoulders.
            if row - top > 3, span < widest * 0.6 { narrowed = true }
            if narrowed, span > widest * 0.7 { break }
            widest = max(widest, span)
            sumX += rowSum; count += rowCount
        }
        guard count > 0 else { return nil }
        let width = widest * grid.cellSize
        let crown = Double(grid.height - top) * grid.cellSize
        return Found(centre: CGPoint(x: sumX / count * grid.cellSize, y: crown - width * 0.72), width: width, top: crown)
    }
}

/// Two of you: you are slid into the left half and mirrored into the right, so you and your twin face each other.
final class MirrorLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    /// How far you are slid sideways, in pixels, eased so the framing glides rather than jumps.
    private var slide: Double?

    func restart() { slide = nil }

    /// How far to slide someone whose head is at `x` so they stand in the middle of the left half. Never to the right when
    /// there is no backdrop, since there is nothing to fill in behind.
    static func slide(forHeadAt x: Double, width: Double, canMoveRight: Bool) -> Double {
        let wanted = width / 4 - x
        return canMoveRight ? wanted : min(0, wanted)
    }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let w = rect.width
        let separate = input.background != nil && input.matte != nil
        let head = input.matteGrid.flatMap { LookHead.find(in: $0) }
        let target = head.map { Self.slide(forHeadAt: $0.centre.x - rect.minX, width: w, canMoveRight: separate) } ?? (slide ?? 0)
        if let now = slide {
            // A dead zone, so leaning about does not swim the picture, and a calm glide to a new place.
            let gap = target - now
            if abs(gap) > 24 { slide = now + (gap - (gap > 0 ? 24 : -24)) * (1 - exp(-max(0, input.dt) * 3)) }
        } else {
            slide = target
        }
        let dx = CGFloat(slide ?? 0)

        let left: CIImage
        if separate, let matte = input.matte, let backdrop = input.background {
            let move = CGAffineTransform(translationX: dx, y: 0)
            left = LookKit.blend(input.composed.clampedToExtent().transformed(by: move), over: backdrop,
                                 mask: matte.clampedToExtent().transformed(by: move))
        } else {
            left = input.composed.clampedToExtent().transformed(by: CGAffineTransform(translationX: dx, y: 0))
        }
        let half = left.cropped(to: CGRect(x: rect.minX, y: rect.minY, width: w / 2, height: rect.height))
        let reflected = half.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2 * rect.minX + w, ty: 0))
        return half.composited(over: reflected).cropped(to: rect)
    }
}

/// A ring of you, a dozen times over, folded by mirrors round the middle of the picture, with a smaller ring inside turning the
/// other way, in rich glassy colour and seen down a tube.
final class KaleidoscopeLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    /// Where the picture is folded from and how much it is scaled first, eased so the pattern settles rather than jumps.
    private var focus: CGPoint?
    private var zoom: Double?

    func restart() { focus = nil; zoom = nil }

    /// Rich, glassy colour.
    private static let jewel = LookGrade { c in
        let curved = LookTone.filmic(c, contrast: 1.2, black: 0.03, white: 0.98)
        return LookTone.saturate(curved, 1.3)
    }

    /// The mirrors make six copies of a slice 60 degrees wide and six reflections. A face set a quarter of a slice off the
    /// mirror line sits whole in its half, so the ring holds twelve complete faces, half of them mirrored.
    private static let mirrors = 6

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect, t = input.time
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        // The ring's radius breathes a little, and the faces in it are sized to fit their slice.
        let radius = rect.height * (0.3 + 0.012 * sin(t * 0.5))
        let half = Double.pi / Double(Self.mirrors * 2)
        let faceSize = 2 * radius * tan(half) * 0.92
        let head = input.matteGrid.flatMap { LookHead.find(in: $0) }
        let wantZoom = head.map { min(2.5, max(0.3, faceSize / max(30, $0.width))) } ?? 1
        let wantFocus = head.map { CGPoint(x: $0.centre.x, y: $0.centre.y - radius / wantZoom) } ?? centre
        let ease = 1 - exp(-max(0, input.dt) * 2.5)
        if let f = focus, let z = zoom {
            focus = CGPoint(x: f.x + (wantFocus.x - f.x) * ease, y: f.y + (wantFocus.y - f.y) * ease)
            zoom = z + (wantZoom - z) * ease
        } else {
            focus = wantFocus; zoom = wantZoom
        }
        let f = focus ?? centre, z = CGFloat(zoom ?? 1)

        // Your face moved straight above the middle, one ring's radius out.
        let aligned = Self.jewel.apply(input.composed).clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: -f.x, y: -f.y).concatenating(CGAffineTransform(scaleX: z, y: z))
                .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y)))
        func ring(scale: CGFloat, turn: Double) -> CIImage {
            let source = scale == 1 ? aligned : aligned.transformed(by: CGAffineTransform(translationX: -centre.x, y: -centre.y)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: centre.x, y: centre.y)))
            return source.applyingFilter("CIKaleidoscope", parameters: [
                "inputCount": Self.mirrors, kCIInputCenterKey: CIVector(x: centre.x, y: centre.y), kCIInputAngleKey: Double.pi / 2 - half,
            ]).transformed(by: CGAffineTransform(translationX: -centre.x, y: -centre.y).concatenating(CGAffineTransform(rotationAngle: CGFloat(turn)))
                .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y))).cropped(to: rect)
        }
        let spin = t * 0.1
        let outer = ring(scale: 1, turn: spin)
        let inner = ring(scale: 0.48, turn: -spin * 1.3 + 0.26)
        let split = CIFilter.radialGradient()
        split.center = centre
        split.radius0 = Float(radius * 0.56)
        split.radius1 = Float(radius * 0.7)
        split.color0 = CIColor(red: 0, green: 0, blue: 0)
        split.color1 = CIColor(red: 1, green: 1, blue: 1)
        let rings = LookKit.blend(outer, over: inner, mask: (split.outputImage ?? CIImage(color: .white)).cropped(to: rect))

        // Glass splits the light a little towards the rim, the middle glows, and the tube darkens to a soft ring.
        let fringed = LookKit.fringe(rings, rect: rect, pixels: 4)
        let glow = LookKit.glow(fringed, rect: rect, threshold: 0.45, sigma: 6, tint: (1, 0.92, 0.85))
        let lit = LookKit.screen(LookKit.levels(glow, gain: 0.5), over: fringed)
        return LookKit.multiply(LookKit.ovalVignette(rect, reach: 0.45, edge: LookKit.lin(0.2)), over: lit).cropped(to: rect)
    }
}
