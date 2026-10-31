import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// When and where the tape tracks badly. Pure, so it can be tested without drawing anything.
enum LookVHSPlan {
    /// A band of bad tracking across the picture. `y` is its lower edge (the origin is the bottom of the frame).
    struct Band: Equatable {
        var y: Double
        var height: Double
        /// 0 as it appears, 1 in the middle of its run, 0 as it leaves.
        var strength: Double
    }

    static let cycle = 8.5

    /// The band of tracking noise that rolls up the picture every so often. Nil in between.
    static func tracking(at time: Double, frameHeight: Double) -> Band? {
        let index = Int((time / cycle).rounded(.down))
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(index)) &* 0xD1B5_4A32 &+ 7)
        guard Double.random(in: 0..<1, using: &rng) < 0.85 else { return nil }
        let start = Double.random(in: 0...2.5, using: &rng)
        let duration = Double.random(in: 2.4...3.8, using: &rng)
        let height = Double.random(in: 70...130, using: &rng)
        let progress = (time - Double(index) * cycle - start) / duration
        guard progress >= 0, progress < 1 else { return nil }
        return Band(y: -height + (frameHeight + height) * progress, height: height, strength: sin(.pi * progress))
    }

    /// How far each strip of a band is knocked sideways. They shake about 20 times a second.
    static func shifts(of band: Band, count: Int, time: Double) -> [Double] {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64((time * 20).rounded(.down))) &* 0xBF58_476D &+ 11)
        return (0..<count).map { i in
            band.strength * (Double.random(in: -1...1, using: &rng) * 34 + 16 * sin(Double(i) * 0.8 + time * 6))
        }
    }

    /// The two lines at the foot of the picture where the heads switch over are always a little out of true.
    static func headSwitch(at time: Double) -> [Double] {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64((time * 30).rounded(.down))) &* 0x94D0_49BB &+ 3)
        return [Double.random(in: 10...46, using: &rng), Double.random(in: -30...30, using: &rng)]
    }
}

/// A worn home video: soft, smeared colour, scan lines, a band of bad tracking rolling up and the camcorder's own PLAY and date.
final class LookVHSLens: Lens {
    let needs: LensNeeds = []

    private var clock: LookClock
    private let display = LookDisplayCache()
    private let player = LookDisplayCache()

    init(startDate: Date = Date()) { clock = LookClock(startDate: startDate) }

    func restart() { clock.restart(); display.reset(); player.reset() }

    func render(_ input: LensInput) -> CIImage {
        let rect = input.rect
        let t = clock.elapsed(at: input.time)
        let frame = Int(t * 30)

        // The camcorder's date was recorded onto the tape, so it goes on first and gets smeared like everything else. The
        // player's own PLAY and counter are drawn by the player over the picture, so they go on last and stay crisp.
        var base = input.composed
        if let words = display.layer(String(Int(t)), size: rect.size, draw: { ctx in self.drawDisplay(ctx, rect: rect, time: t) }) {
            base = words.composited(over: base).cropped(to: rect)
        }

        // A tape holds little detail, so all of this is done at half size: it is cheaper, and softer in just the right way.
        let half = LookKit.size(of: rect, scaledBy: 0.5)
        let small = LookKit.shrink(base, rect: rect, by: 0.5)

        // Colour is recorded far more coarsely than brightness: green (most of the brightness) stays crisp, while red and blue
        // are smeared along the line and arrive late, so colour bleeds to the right of every edge.
        func channel(_ source: CIImage, r: Double, g: Double, b: Double) -> CIImage {
            source.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(r), y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: CGFloat(g), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(b), w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        }
        let smeared = small.clampedToExtent().applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 6.0, kCIInputAngleKey: 0.0])
        let wobble = 0.6 * sin(t * 2.3)
        func late(_ image: CIImage, by pixels: Double) -> CIImage {
            image.transformed(by: CGAffineTransform(translationX: CGFloat(pixels + wobble), y: 0)).cropped(to: half)
        }
        var picture = LookKit.screen(channel(late(smeared, by: 3.5), r: 1, g: 0, b: 0),
                                     over: LookKit.screen(channel(small, r: 0, g: 1, b: 0), over: channel(late(smeared, by: 1.5), r: 0, g: 0, b: 1)))
            .cropped(to: half)

        // Tape colour: a little washed, a little blue in the shadows, a little too colourful.
        picture = LookKit.levels(picture.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.2]), gain: 0.96, bias: LookKit.lin(0.05))
            .applyingFilter("CIColorMatrix", parameters: ["inputBiasVector": CIVector(x: 0, y: CGFloat(LookKit.lin(0.02)), z: CGFloat(LookKit.lin(0.09)), w: 0)])

        // Strips of the picture knocked sideways: the foot of the frame always, and a rolling band every so often. Each is cut
        // from the untouched picture, so they can all be laid on in one go.
        var pieces: [CIImage] = []
        func sideways(_ y: Double, _ height: Double, _ shift: Double) {
            let strip = CGRect(x: 0, y: y, width: half.width, height: height).intersection(half)
            guard !strip.isEmpty else { return }
            pieces.append(picture.clampedToExtent().transformed(by: CGAffineTransform(translationX: CGFloat(shift / 2), y: 0)).cropped(to: strip))
        }
        let feet = LookVHSPlan.headSwitch(at: t)
        sideways(0, 3.5, feet[0])
        sideways(3.5, 3.5, feet[1] * 0.5)
        var snow: [CIImage] = [LookKit.speckle(CGRect(x: 0, y: 0, width: half.width, height: 7), frame: frame, coverage: 0.4, strength: 0.6,
                                               size: 1, stretch: 2, colour: (0.95, 0.97, 1))]
        if let band = LookVHSPlan.tracking(at: t, frameHeight: rect.height) {
            let count = max(2, Int(band.height / 14))
            let strip = band.height / Double(count)
            for (i, shift) in LookVHSPlan.shifts(of: band, count: count, time: t).enumerated() { sideways((band.y + Double(i) * strip) / 2, strip / 2 + 0.5, shift) }
            let low = max(0, band.y / 2), high = min(half.height, (band.y + band.height) / 2)
            if high > low {
                snow.append(LookKit.speckle(CGRect(x: 0, y: low, width: half.width, height: high - low), frame: frame, coverage: 0.12 + 0.18 * band.strength,
                                            strength: 0.5 * band.strength, size: 1, stretch: 3, colour: (0.92, 0.95, 1)))
            }
        }
        for piece in pieces + snow { picture = piece.composited(over: picture) }

        // Faint grain over everything, then back to full size, with the scan lines drawn crisp on top.
        picture = LookKit.grained(picture, frame: frame, rect: half, amount: 0.22, size: 1)
        let lines = LookKit.scanlines(rect, period: 4, darkness: 0.17)
        let tape = lines.composited(over: LookKit.enlarge(picture, to: rect, from: half)).cropped(to: rect)
        guard let osd = player.layer(String(Int(t)), size: rect.size, draw: { ctx in self.drawPlayer(ctx, rect: rect, time: t) }) else { return tape }
        return osd.composited(over: tape).cropped(to: rect)
    }

    private static let margin: CGFloat = 70

    /// The camcorder's date stamp, recorded on the tape: chunky white figures with a dark edge, as camcorders burned them in.
    private func drawDisplay(_ ctx: CGContext, rect: CGRect, time t: Double) {
        let white = NSColor(white: 0.97, alpha: 1)
        let edge = NSColor(red: 0.05, green: 0.05, blue: 0.12, alpha: 0.9)
        let margin = Self.margin
        let date = clock.date(after: t)
        LookKit.text(LookClock.time(date), in: ctx, at: CGPoint(x: margin, y: margin + 46), size: 40, colour: white, weight: .heavy, tracking: 2, edge: edge)
        LookKit.text(LookClock.day(date), in: ctx, at: CGPoint(x: margin, y: margin), size: 40, colour: white, weight: .heavy, tracking: 2, edge: edge)
    }

    /// The player's on-screen display: PLAY with its arrow, and the tape counter, in the player's blue-white glow.
    private func drawPlayer(_ ctx: CGContext, rect: CGRect, time t: Double) {
        let white = NSColor(white: 0.98, alpha: 1)
        let glow = NSColor(red: 0.45, green: 0.6, blue: 1, alpha: 0.85)
        let edge = NSColor(red: 0.04, green: 0.05, blue: 0.16, alpha: 0.75)
        let margin = Self.margin
        let top = rect.maxY - margin - 34
        LookKit.text("PLAY", in: ctx, at: CGPoint(x: margin, y: top), size: 46, colour: white, weight: .heavy, tracking: 3, glow: glow, edge: edge)
        LookKit.playMark(in: ctx, at: CGPoint(x: margin + 150, y: top + 5), height: 36, colour: white.cgColor, glow: glow.cgColor)
        LookKit.text("SP " + LookClock.counter(t), in: ctx, at: CGPoint(x: rect.maxX - margin, y: top), size: 40, colour: white, weight: .heavy, tracking: 2,
                     glow: glow, edge: edge, anchor: .trailing)
    }
}
