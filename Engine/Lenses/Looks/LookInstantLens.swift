import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// How an instant photo develops. Pure, so it can be tested.
enum LookInstantPlan {
    /// Seconds from a blank milky square to the finished picture.
    static let developTime = 3.0

    /// How far the picture has come through, 0 (blank) to 1 (done), with the soft start and finish the chemistry has.
    static func developed(after seconds: Double) -> Double {
        LookKit.smoothstep(0.15, developTime, seconds)
    }

    /// Where the photo sits inside the white frame: narrow borders and a deep strip at the foot to hold it by.
    static func window(in rect: CGRect) -> CGRect {
        let side = (rect.height * 0.048).rounded(), foot = (rect.height * 0.145).rounded()
        return CGRect(x: rect.minX + side, y: rect.minY + foot, width: rect.width - side * 2, height: rect.height - side - foot)
    }
}

/// An instant photo, just taken: the picture in soft, creamy instant-film colour inside a white frame with a hand-written date
/// on the strip at the bottom. When you pick it, the photo develops in front of you, from milky blue-grey to full colour.
final class LookInstantLens: Lens {
    let needs: LensNeeds = []

    private var clock: LookClock
    private let frame = LookDisplayCache()

    init(startDate: Date = Date()) { clock = LookClock(startDate: startDate) }

    func restart() { clock.restart() }

    /// Instant film: milky lifted blacks with a cyan cast, creamy warm highlights, gentle contrast and slightly quiet colour.
    private static let film = LookGrade { c in
        var x = LookTone.filmic(c, contrast: 1.12, black: 0.085, white: 0.955, pivot: 0.5)
        let l = LookTone.luma(x)
        x += SIMD3<Float>(-0.025, 0.012, 0.045) * (1 - LookTone.smooth(0.05, 0.55, l))
        x += SIMD3<Float>(0.03, 0.012, -0.045) * LookTone.smooth(0.45, 1.0, l)
        return LookTone.saturate(x, 0.9)
    }

    private static let blank: LookColour = (0.62, 0.66, 0.68)
    private static let paper: LookColour = (0.965, 0.958, 0.938)

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let t = clock.elapsed(at: input.time)
        let window = LookInstantPlan.window(in: rect)

        // The picture scaled to fill the window, keeping more of the top (where faces are) than the bottom.
        let scale = window.width / rect.width
        let tall = rect.height * scale
        let lift = (tall - window.height) * 0.62
        let placed = input.composed.clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: window.minX, y: window.minY - lift)))
            .cropped(to: window)

        // Instant colour, a gentle chemical falloff towards the edges of the photo, and soft grain.
        var photo = Self.film.apply(placed)
        let edges = LookKit.ovalVignette(window, reach: 0.55, edge: LookKit.lin(0.72))
        photo = LookKit.filmGrain(LookKit.multiply(edges, over: photo), frame: 3, rect: window, amount: 0.12, size: 1.2)

        // Developing: from blank, through a pale washed-out stage, to the finished photo.
        let done = LookInstantPlan.developed(after: t)
        if done < 1 {
            let blank = CIImage(color: LookKit.ciColour(Self.blank)).cropped(to: window)
            let ghost = LookKit.mixImages(blank, LookKit.levels(photo.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.3]), gain: 0.6, bias: 0.25),
                                          LookKit.smoothstep(0, 0.55, done))
            photo = LookKit.mixImages(ghost, photo, LookKit.smoothstep(0.4, 1, done)).cropped(to: window)
        }

        // A soft sheen across the gloss.
        let sheen = CIFilter.linearGradient()
        sheen.point0 = CGPoint(x: window.minX, y: window.maxY)
        sheen.point1 = CGPoint(x: window.minX + window.width * 0.55, y: window.minY)
        sheen.color0 = CIColor(red: 0.07, green: 0.07, blue: 0.07)
        sheen.color1 = CIColor(red: 0, green: 0, blue: 0)
        if let gloss = sheen.outputImage?.cropped(to: window) { photo = LookKit.screen(gloss, over: photo).cropped(to: window) }

        let date = clock.date(after: 0)
        let key = "\(Int(rect.width))-\(LookClock.day(date))"
        let card = CIImage(color: LookKit.ciColour(Self.paper)).cropped(to: rect)
        guard let border = frame.layer(key, size: rect.size, draw: { ctx in Self.drawFrame(ctx, rect: rect, window: window, date: date) }) else {
            return photo.composited(over: card).cropped(to: rect)
        }
        return border.composited(over: photo.composited(over: card)).cropped(to: rect)
    }

    /// "Oct 30 '26", as someone would scribble it.
    static func caption(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d ''yy"
        return formatter.string(from: date)
    }

    /// The card: a paper border with a little tooth, the photo set slightly into it, and the date in marker on the strip.
    private static func drawFrame(_ ctx: CGContext, rect: CGRect, window: CGRect, date: Date) {
        let space = LookKit.space
        // The edge of the photo sits a fraction below the card, so the card throws a hairline of shadow into it.
        ctx.saveGState()
        ctx.clip(to: window)
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 5, color: CGColor(colorSpace: space, components: [0, 0, 0, 0.45])!)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.2, 0.2, 0.2, 1])!)
        ctx.setLineWidth(6)
        ctx.stroke(window.insetBy(dx: -3, dy: -3))
        ctx.restoreGState()
        // The card itself: paper all round the photo, a hair of light along the top-left of the window and a little paper tooth.
        ctx.saveGState()
        ctx.addRect(rect)
        ctx.addRect(window)
        ctx.clip(using: .evenOdd)
        ctx.setFillColor(CGColor(colorSpace: space, components: [CGFloat(paper.r), CGFloat(paper.g), CGFloat(paper.b), 1])!)
        ctx.fill(rect)
        var rng = SplitMix64(seed: 404)
        for _ in 0..<1400 {
            let p = CGPoint(x: Double.random(in: 0..<rect.width, using: &rng), y: Double.random(in: 0..<rect.height, using: &rng))
            let shade = Double.random(in: 0.86...1.0, using: &rng)
            ctx.setFillColor(CGColor(colorSpace: space, components: [CGFloat(paper.r * shade), CGFloat(paper.g * shade), CGFloat(paper.b * shade), 0.35])!)
            ctx.fill(CGRect(x: p.x, y: p.y, width: 1.5, height: 1.5))
        }
        let shade = CGGradient(colorsSpace: space, colors: [CGColor(colorSpace: space, components: [0, 0, 0, 0.0])!, CGColor(colorSpace: space, components: [0, 0, 0, 0.06])!] as CFArray,
                               locations: [0, 1])!
        ctx.drawLinearGradient(shade, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
        ctx.restoreGState()
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [1, 1, 1, 0.8])!)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: window.minX - 0.5, y: window.minY)); ctx.addLine(to: CGPoint(x: window.minX - 0.5, y: window.maxY + 0.5))
        ctx.addLine(to: CGPoint(x: window.maxX, y: window.maxY + 0.5)); ctx.strokePath()

        // The date, in marker, a little askew, towards the right of the strip.
        let font = NSFont(name: "Noteworthy-Bold", size: 40) ?? NSFont(name: "MarkerFelt-Wide", size: 38) ?? NSFont.systemFont(ofSize: 36, weight: .semibold)
        let ink = NSColor(srgbRed: 0.13, green: 0.17, blue: 0.36, alpha: 0.92)
        let text = NSAttributedString(string: caption(for: date), attributes: [.font: font, .foregroundColor: ink])
        let size = text.size()
        ctx.saveGState()
        ctx.translateBy(x: window.maxX - size.width / 2 - rect.width * 0.06, y: rect.minY + (window.minY - rect.minY) / 2)
        ctx.rotate(by: 0.035)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        text.draw(at: NSPoint(x: -size.width / 2, y: -size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }
}
