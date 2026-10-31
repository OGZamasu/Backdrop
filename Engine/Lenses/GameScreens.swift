import AppKit
import CoreGraphics
import simd

// The one look every game wears for everything that is not the game's own art: the waiting card, the countdown, the plates in the
// corners while it is played, the hints in the first seconds, the pause, and the result card. Games of every kind (played with the
// body, the hands or the face) share it, so the thirty-odd games read as one product.
//
// Layout, on a 1280 x 720 picture with a 5% safe border (64 x 36 pixels):
// - score plate top left, status plate (hearts, clock, a word) top right, a combo badge beside the score;
// - call-outs ("ROUND 3", "GOAL!") in the band between the two plates;
// - hints, tips and the pause along the bottom middle;
// - the waiting, countdown and result cards low in the middle, under the player's chin, never over the face.
// Everything is baked once (type, plates, hearts, icons) and stamped, so the screens cost well under a millisecond a frame.

// MARK: - Palette

/// The colours of the game screens. Warm and slightly soft, never a pure primary; the dark is a deep blue-violet ink, so plates and
/// edges sit softly on any room, skin, white shirt or dark hoodie.
enum GameUIPalette {
    /// Plates, edges and shadows.
    static let ink = SIMD3<Double>(0.07, 0.06, 0.16)
    /// The lit top of a plate.
    static let dusk = SIMD3<Double>(0.2, 0.15, 0.4)
    /// Words.
    static let cream = SIMD3<Double>(1.0, 0.97, 0.92)
    /// Scores, records, rewards.
    static let gold = SIMD3<Double>(1.0, 0.8, 0.28)
    /// Good news.
    static let mint = SIMD3<Double>(0.36, 0.89, 0.62)
    /// Bad news: a lost life, the last seconds.
    static let coral = SIMD3<Double>(1.0, 0.43, 0.41)
    /// Calm information, a round that ran out of time.
    static let sky = SIMD3<Double>(0.36, 0.74, 1.0)
    /// Combos and streaks.
    static let berry = SIMD3<Double>(0.78, 0.26, 0.62)
    static let violet = SIMD3<Double>(0.6, 0.45, 1.0)
    static let tangerine = SIMD3<Double>(1.0, 0.62, 0.26)

    static func cg(_ c: SIMD3<Double>, _ alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: CGFloat(alpha))
    }

    static func ns(_ c: SIMD3<Double>, _ alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: CGFloat(alpha))
    }

    /// A colour mixed toward white (positive `amount`) or toward ink (negative).
    static func shade(_ c: SIMD3<Double>, _ amount: Double) -> SIMD3<Double> {
        amount >= 0 ? c + (SIMD3(1, 1, 1) - c) * min(1, amount) : c + (ink - c) * min(1, -amount)
    }

    /// A short name for sprite caches.
    static func key(_ c: SIMD3<Double>) -> String { String(Int(c.x * 255) << 16 | Int(c.y * 255) << 8 | Int(c.z * 255), radix: 16) }
}

// MARK: - Easing

/// The curves the screens move on: nothing slides linearly or pops.
enum GameUIEase {
    static func clamp(_ t: Double) -> Double { min(1, max(0, t)) }
    static func outCubic(_ t: Double) -> Double { let u = 1 - clamp(t); return 1 - u * u * u }
    static func inOut(_ t: Double) -> Double { let t = clamp(t); return t * t * (3 - 2 * t) }
    /// Runs a little past the end and settles back: for things that arrive.
    static func outBack(_ t: Double, _ s: Double = 1.7) -> Double { let u = clamp(t) - 1; return 1 + u * u * ((s + 1) * u + s) }
    /// A damped wobble from 1 down to 0: for a jolt that rings out.
    static func wobble(_ t: Double, frequency: Double = 3, damping: Double = 6) -> Double {
        exp(-damping * max(0, t)) * cos(2 * .pi * frequency * max(0, t))
    }
    /// Rises over `rise` seconds, holds, and falls over the last `fall` seconds of `life`.
    static func envelope(_ age: Double, life: Double, rise: Double, fall: Double) -> Double {
        guard age >= 0, age <= life else { return 0 }
        return min(outCubic(age / max(rise, 1e-6)), clamp((life - age) / max(fall, 1e-6)))
    }
}

// MARK: - Baked pictures

/// Every picture the screens use, painted once and kept: type, plates, hearts, icons. Keyed by what they show and their size.
enum GameUISprites {
    private static let lock = NSLock()
    private struct Entry { var image: CGImage; var used: Int }
    private static var cache: [String: Entry] = [:]
    private static var clock = 0
    /// How many pictures have been painted: tests use it to check nothing is baked during play.
    private(set) static var baked = 0
    /// The last few pictures painted, for finding out what a frame baked.
    private(set) static var recent: [String] = []
    private static let limit = 900

    static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// The picture for `key` if it has been painted already.
    static func cached(_ key: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        clock += 1
        guard let hit = cache[key] else { return nil }
        cache[key]?.used = clock
        return hit.image
    }

    /// The picture for `key`, painted by `paint` the first time. The context is `width` x `height` pixels, origin bottom left, y up.
    static func image(_ key: String, width: Int, height: Int, paint: (CGContext) -> Void) -> CGImage? {
        lock.lock()
        clock += 1
        if let hit = cache[key] {
            cache[key]?.used = clock
            lock.unlock()
            return hit.image
        }
        lock.unlock()
        guard width > 0, height > 0, width < 4096, height < 4096,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: Sprites.bitmapInfo) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        paint(ctx)
        guard let image = ctx.makeImage() else { return nil }
        lock.lock()
        baked += 1
        recent.append(key)
        if recent.count > 24 { recent.removeFirst() }
        if cache.count >= limit {
            // Let the least recently used half go; anything needed again is simply painted again.
            for (k, _) in cache.sorted(by: { $0.value.used < $1.value.used }).prefix(limit / 2) { cache.removeValue(forKey: k) }
        }
        cache[key] = Entry(image: image, used: clock)
        lock.unlock()
        return image
    }

    /// Stamps a picture with its bottom-left corner at `origin`, at its own pixel size: on whole pixels, the fast path.
    static func stamp(_ ctx: CGContext, _ image: CGImage?, origin: CGPoint, alpha: CGFloat = 1) {
        guard let image, alpha > 0.004 else { return }
        let rect = CGRect(x: origin.x.rounded(), y: origin.y.rounded(), width: CGFloat(image.width), height: CGFloat(image.height))
        if alpha < 0.995 {
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.draw(image, in: rect)
            ctx.restoreGState()
        } else {
            ctx.draw(image, in: rect)
        }
    }

    /// Stamps a picture centred on `center`, grown by `scale` and turned by `rotation` for a moment (a pop, a wobble).
    static func stamp(_ ctx: CGContext, _ image: CGImage?, center: CGPoint, scale: CGFloat = 1, rotation: CGFloat = 0, alpha: CGFloat = 1) {
        guard let image, alpha > 0.004, scale > 0.005 else { return }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        if abs(scale - 1) < 0.004 && abs(rotation) < 0.002 {
            stamp(ctx, image, origin: CGPoint(x: center.x - w / 2, y: center.y - h / 2), alpha: alpha)
            return
        }
        ctx.saveGState()
        if alpha < 0.995 { ctx.setAlpha(alpha) }
        ctx.translateBy(x: center.x, y: center.y)
        if rotation != 0 { ctx.rotate(by: rotation) }
        ctx.scaleBy(x: scale, y: scale)
        ctx.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        ctx.restoreGState()
    }
}

// MARK: - Type

/// The one typeface of every game: the rounded system font, heavy, in cream (or a game's colour) on a thin ink edge with a soft
/// shadow, so it reads on skin, a white wall and a dark room alike. Lines are baked whole; numbers that change every frame are put
/// together from baked digits, so a running score never costs a fresh layout.
enum GameUIType {
    enum Align { case left, center, right }

    private static let lock = NSLock()
    private static var fonts: [String: NSFont] = [:]
    private static var widths: [String: CGFloat] = [:]

    /// The rounded system font at `size`, with digits all one width so a running number does not jiggle.
    static func font(_ size: CGFloat, weight: NSFont.Weight = .heavy) -> NSFont {
        let px = max(4, size.rounded())
        let key = "\(Int(px))|\(weight.rawValue)"
        lock.lock()
        if let hit = fonts[key] { lock.unlock(); return hit }
        lock.unlock()
        let base = NSFont.systemFont(ofSize: px, weight: weight)
        var descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        descriptor = descriptor.addingAttributes([.featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                                                      NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
        let made = NSFont(descriptor: descriptor, size: px) ?? base
        lock.lock()
        fonts[key] = made
        lock.unlock()
        return made
    }

    /// How wide a line comes out, without the edge and shadow around it. Remembered.
    static func width(_ string: String, size: CGFloat, weight: NSFont.Weight = .heavy) -> CGFloat {
        let key = "\(string)|\(Int(size.rounded()))|\(weight.rawValue)"
        lock.lock()
        if let hit = widths[key] { lock.unlock(); return hit }
        lock.unlock()
        let w = NSAttributedString(string: string, attributes: [.font: font(size, weight: weight)]).size().width
        lock.lock()
        if widths.count > 2000 { widths.removeAll() }
        widths[key] = w
        lock.unlock()
        return w
    }

    /// The room around the letters for the edge and the shadow, in pixels.
    static func pad(_ size: CGFloat) -> CGFloat { (size.rounded() * 0.3).rounded(.up) + 2 }

    /// Which parts of a line to bake: the ink edge and shadow, the coloured letters, or both.
    private enum Layer: String { case under, fill, both }

    /// A line baked as a picture, `pad(size)` pixels of room on every side of the letters.
    private static func picture(_ string: String, size: CGFloat, color: SIMD3<Double>, weight: NSFont.Weight, layer: Layer,
                                edge: Double) -> CGImage? {
        let px = max(4, size.rounded())
        let key = "t|\(string)|\(Int(px))|\(GameUIPalette.key(color))|\(weight.rawValue)|\(layer.rawValue)|\(Int(edge * 100))"
        // Laying text out costs far more than drawing its picture, so it is only done once, when the picture is first made.
        if let hit = GameUISprites.cached(key) { return hit }
        let f = font(px, weight: weight)
        let box = NSAttributedString(string: string, attributes: [.font: f]).size()
        let pad = Self.pad(px)
        let w = Int(ceil(box.width + pad * 2)), h = Int(ceil(box.height + pad * 2))
        return GameUISprites.image(key, width: w, height: h) { ctx in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            let origin = NSPoint(x: pad, y: pad)
            if layer != .fill && edge > 0 {
                // A filled, stroked silhouette in ink under the letters, with the soft shadow baked in.
                ctx.setShadow(offset: CGSize(width: 0, height: -px * 0.07), blur: px * 0.16, color: GameUIPalette.cg(GameUIPalette.ink, 0.55))
                NSAttributedString(string: string, attributes: [
                    .font: f, .foregroundColor: GameUIPalette.ns(GameUIPalette.ink, 0.9), .strokeColor: GameUIPalette.ns(GameUIPalette.ink, 0.9),
                    .strokeWidth: -edge * 100,
                ]).draw(at: origin)
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
            }
            if layer != .under {
                NSAttributedString(string: string, attributes: [.font: f, .foregroundColor: GameUIPalette.ns(color)]).draw(at: origin)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// The whole line as one picture (letters, edge and shadow).
    static func image(_ string: String, size: CGFloat, color: SIMD3<Double> = GameUIPalette.cream, weight: NSFont.Weight = .heavy,
                      edge: Double = 0.16) -> CGImage? {
        picture(string, size: size, color: color, weight: weight, layer: .both, edge: edge)
    }

    /// Draws a line with its centre (or its left or right end) at `point`, vertically centred on it.
    static func draw(_ ctx: CGContext, _ string: String, at point: CGPoint, size: CGFloat, color: SIMD3<Double> = GameUIPalette.cream,
                     weight: NSFont.Weight = .heavy, align: Align = .center, alpha: CGFloat = 1, scale: CGFloat = 1, rotation: CGFloat = 0,
                     edge: Double = 0.16) {
        guard !string.isEmpty, alpha > 0.01, let image = image(string, size: size, color: color, weight: weight, edge: edge) else { return }
        let w = CGFloat(image.width), pad = Self.pad(size)
        let cx: CGFloat
        switch align {
        case .center: cx = point.x
        case .left: cx = point.x - pad + w / 2
        case .right: cx = point.x + pad - w / 2
        }
        let anchor = CGPoint(x: point.x, y: point.y)
        if scale == 1 && rotation == 0 {
            GameUISprites.stamp(ctx, image, center: CGPoint(x: cx, y: point.y + verticalNudge(size)), alpha: alpha)
        } else {
            // Grow about the anchor, so a left-aligned score swells from its left edge.
            ctx.saveGState()
            ctx.translateBy(x: anchor.x, y: anchor.y)
            ctx.rotate(by: rotation)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -anchor.x, y: -anchor.y)
            GameUISprites.stamp(ctx, image, center: CGPoint(x: cx, y: point.y + verticalNudge(size)), alpha: alpha)
            ctx.restoreGState()
        }
    }

    /// Text boxes include room for descenders; letters and digits look centred a touch lower, so lift them back.
    private static func verticalNudge(_ size: CGFloat) -> CGFloat { -size * 0.04 }

    // MARK: Numbers

    private static func advance(_ c: Character, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        width(String(c), size: size, weight: weight)
    }

    /// How wide a number (or any short changing string) comes out when put together from single characters.
    static func numberWidth(_ string: String, size: CGFloat, weight: NSFont.Weight = .heavy) -> CGFloat {
        string.reduce(0) { $0 + advance($1, size: size, weight: weight) }
    }

    /// Draws a changing number from baked single characters: all the ink edges first, then all the letters, so one character's edge
    /// never lies over its neighbour. Any characters work; digits, ".", ":", "s", "×", "+" are the usual ones.
    static func number(_ ctx: CGContext, _ string: String, at point: CGPoint, size: CGFloat, color: SIMD3<Double> = GameUIPalette.cream,
                       weight: NSFont.Weight = .heavy, align: Align = .center, alpha: CGFloat = 1, scale: CGFloat = 1) {
        guard !string.isEmpty, alpha > 0.01 else { return }
        let total = numberWidth(string, size: size, weight: weight)
        var x: CGFloat
        switch align {
        case .center: x = point.x - total / 2
        case .left: x = point.x
        case .right: x = point.x - total
        }
        let pad = Self.pad(size)
        let y = point.y + verticalNudge(size)
        ctx.saveGState()
        if alpha < 0.995 { ctx.setAlpha(alpha) }
        if scale != 1 {
            ctx.translateBy(x: point.x, y: point.y)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -point.x, y: -point.y)
        }
        var places: [(Character, CGFloat)] = []
        for c in string {
            places.append((c, x))
            x += advance(c, size: size, weight: weight)
        }
        for layer in [Layer.under, .fill] {
            for (c, left) in places where c != " " {
                guard let image = picture(String(c), size: size, color: color, weight: weight, layer: layer, edge: 0.16) else { continue }
                let h = CGFloat(image.height)
                let origin = CGPoint(x: left - pad, y: y - h / 2)
                if scale == 1 {
                    GameUISprites.stamp(ctx, image, origin: origin)
                } else {
                    ctx.draw(image, in: CGRect(x: origin.x, y: origin.y, width: CGFloat(image.width), height: h))
                }
            }
        }
        ctx.restoreGState()
    }

    /// Splits words that carry numbers ("Round 2/5", "Wave 3") into runs: the words are baked whole (with their kerning) and the
    /// numbers put together from single characters, so a label that counts up never bakes a new picture.
    private static func runs(_ string: String) -> [(text: String, isNumber: Bool)] {
        var out: [(String, Bool)] = []
        for c in string {
            let numeric = c.isNumber || ((c == "/" || c == ":" || c == "." || c == "×") && out.last?.1 == true)
            if let last = out.last, last.1 == numeric { out[out.count - 1].0.append(c) } else { out.append((String(c), numeric)) }
        }
        return out
    }

    /// How wide `mixed` draws a line.
    static func mixedWidth(_ string: String, size: CGFloat, weight: NSFont.Weight = .heavy) -> CGFloat {
        runs(string).reduce(0) { $0 + ($1.isNumber ? numberWidth($1.text, size: size, weight: weight) : width($1.text, size: size, weight: weight)) }
    }

    /// Draws a line of words and numbers with its left end at `point`: words baked whole, numbers from single characters.
    static func mixed(_ ctx: CGContext, _ string: String, at point: CGPoint, size: CGFloat, color: SIMD3<Double> = GameUIPalette.cream,
                      weight: NSFont.Weight = .heavy) {
        var x = point.x
        for run in runs(string) {
            if run.isNumber {
                number(ctx, run.text, at: CGPoint(x: x, y: point.y), size: size, color: color, weight: weight, align: .left)
                x += numberWidth(run.text, size: size, weight: weight)
            } else {
                let w = width(run.text, size: size, weight: weight)
                if !run.text.allSatisfy(\.isWhitespace) {
                    draw(ctx, run.text, at: CGPoint(x: x, y: point.y), size: size, color: color, weight: weight, align: .left)
                }
                x += w
            }
        }
    }

    // MARK: Lines

    /// Words cut into sentences: "Swat the balloons. Dodge the bombs!" is two.
    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            if ".!?".contains(c) && (i + 1 == chars.count || chars[i + 1] == " ") {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    /// Breaks words into at most `maxLines` lines no wider than `maxWidth`: at a sentence end first, then at the space that balances
    /// the lines best.
    static func lines(_ text: String, size: CGFloat, maxWidth: CGFloat, maxLines: Int = 2, weight: NSFont.Weight = .bold) -> [String] {
        if width(text, size: size, weight: weight) <= maxWidth || maxLines <= 1 { return [text] }
        for stop in [". ", "! ", "? ", "; "] {
            if let r = text.range(of: stop) {
                let first = String(text[..<r.lowerBound]) + String(stop.first ?? ".")
                let rest = String(text[r.upperBound...])
                if width(first, size: size, weight: weight) <= maxWidth && width(rest, size: size, weight: weight) <= maxWidth { return [first, rest] }
            }
        }
        let words = text.split(separator: " ").map(String.init)
        var best: [String] = [text], bestScore = CGFloat.infinity
        for cut in 1..<max(1, words.count) {
            let a = words[..<cut].joined(separator: " "), b = words[cut...].joined(separator: " ")
            let wa = width(a, size: size, weight: weight), wb = width(b, size: size, weight: weight)
            let score = max(wa, wb)
            if score < bestScore { bestScore = score; best = [a, b] }
        }
        return best
    }
}

// MARK: - Plates

/// The dark glass every word sits on: a rounded ink plate lit softly from the top, with a fine light rim and a soft shadow, baked
/// once for each size.
enum GameUIPlate {
    /// The room left round a plate picture for its shadow.
    static let shadowPad: CGFloat = 22

    static func image(width: Int, height: Int, radius: Int, fill: SIMD3<Double> = GameUIPalette.ink, opacity: Double = 0.86,
                      rim: SIMD3<Double>? = nil) -> CGImage? {
        let pad = Int(shadowPad)
        let key = "plate|\(width)x\(height)|r\(radius)|\(GameUIPalette.key(fill))|\(Int(opacity * 100))|\(rim.map(GameUIPalette.key) ?? "-")"
        return GameUISprites.image(key, width: width + pad * 2, height: height + pad * 2) { ctx in
            let rect = CGRect(x: CGFloat(pad), y: CGFloat(pad), width: CGFloat(width), height: CGFloat(height))
            let r = min(CGFloat(radius), rect.height / 2, rect.width / 2)
            let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 15, color: GameUIPalette.cg(GameUIPalette.ink, 0.42))
            ctx.addPath(path)
            ctx.setFillColor(GameUIPalette.cg(fill, opacity))
            ctx.fillPath()
            ctx.restoreGState()
            // Light from above: the top of the plate a little brighter.
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let top = fill == GameUIPalette.ink ? GameUIPalette.dusk : GameUIPalette.shade(fill, 0.35)
            if let g = CGGradient(colorsSpace: GameUISprites.space, colors: [GameUIPalette.cg(top, 0.55), GameUIPalette.cg(top, 0)] as CFArray,
                                  locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.midY), options: [])
            }
            ctx.restoreGState()
            let inner = rect.insetBy(dx: 0.75, dy: 0.75)
            ctx.addPath(CGPath(roundedRect: inner, cornerWidth: max(0, r - 0.75), cornerHeight: max(0, r - 0.75), transform: nil))
            ctx.setStrokeColor(rim.map { GameUIPalette.cg($0, 0.85) } ?? GameUIPalette.cg(GameUIPalette.cream, 0.14))
            ctx.setLineWidth(rim == nil ? 1.5 : 2.5)
            ctx.strokePath()
        }
    }

    private static let sliceLock = NSLock()
    private static var slices: [String: (left: CGImage, middle: CGImage, right: CGImage)] = [:]

    /// The plate cut in three: a left end, a middle that stretches, a right end. One picture per height and look serves every width,
    /// so a plate that grows with its score never bakes a new picture.
    private static func threeSlice(height h: Int, radius r: Int, fill: SIMD3<Double>, opacity: Double, rim: SIMD3<Double>?)
        -> (left: CGImage, middle: CGImage, right: CGImage)? {
        let key = "\(h)|\(r)|\(GameUIPalette.key(fill))|\(Int(opacity * 100))|\(rim.map(GameUIPalette.key) ?? "-")"
        sliceLock.lock()
        if let hit = slices[key] { sliceLock.unlock(); return hit }
        sliceLock.unlock()
        let pad = Int(shadowPad)
        guard let full = image(width: 2 * r + 8, height: h, radius: r, fill: fill, opacity: opacity, rim: rim) else { return nil }
        let end = pad + r + 2
        let height = CGFloat(full.height)
        guard let left = full.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(end), height: height)),
              let middle = full.cropping(to: CGRect(x: CGFloat(end), y: 0, width: 4, height: height)),
              let right = full.cropping(to: CGRect(x: CGFloat(end + 4), y: 0, width: CGFloat(full.width - end - 4), height: height)) else { return nil }
        let made = (left, middle, right)
        sliceLock.lock()
        slices[key] = made
        sliceLock.unlock()
        return made
    }

    /// Draws a plate covering `rect`, on whole pixels: the two ends stamped and the middle stretched between them.
    static func draw(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, fill: SIMD3<Double> = GameUIPalette.ink, opacity: Double = 0.86,
                     rim: SIMD3<Double>? = nil, alpha: CGFloat = 1) {
        let w = Int(rect.width.rounded()), h = Int((rect.height / 2).rounded()) * 2
        guard w > 0, h > 0 else { return }
        let r = min(Int(radius.rounded()), h / 2, w / 2)
        let pad = Int(shadowPad)
        let x0 = Int((rect.midX - CGFloat(w) / 2).rounded()), y0 = Int((rect.midY - CGFloat(h) / 2).rounded()) - pad
        guard w >= 2 * r + 4, let parts = threeSlice(height: h, radius: r, fill: fill, opacity: opacity, rim: rim) else {
            let small = image(width: w, height: h, radius: r, fill: fill, opacity: opacity, rim: rim)
            GameUISprites.stamp(ctx, small, origin: CGPoint(x: x0 - pad, y: y0), alpha: alpha)
            return
        }
        let end = pad + r + 2
        let height = CGFloat(parts.left.height)
        ctx.saveGState()
        if alpha < 0.995 { ctx.setAlpha(alpha) }
        // Every column of the middle is the same, so the cheapest resampling is also exact.
        ctx.interpolationQuality = .none
        ctx.draw(parts.left, in: CGRect(x: CGFloat(x0 - pad), y: CGFloat(y0), width: CGFloat(end), height: height))
        let middleWidth = w - 2 * (r + 2)
        if middleWidth > 0 {
            ctx.draw(parts.middle, in: CGRect(x: CGFloat(x0 + r + 2), y: CGFloat(y0), width: CGFloat(middleWidth), height: height))
        }
        ctx.draw(parts.right, in: CGRect(x: CGFloat(x0 + w - r - 2), y: CGFloat(y0), width: CGFloat(parts.right.width), height: height))
        ctx.restoreGState()
    }
}

// MARK: - Pieces

/// The small drawn pieces of the screens: hearts, the clock ring, the pause sign, the icons that show how a game is played.
enum GameUIPieces {
    /// A heart `side` pixels wide: glossy coral, or a hollow one for a life lost.
    static func heart(full: Bool, side: Int = 32) -> CGImage? {
        let pad = 8
        return GameUISprites.image("heart|\(full)|\(side)", width: side + pad * 2, height: side + pad * 2) { ctx in
            let s = CGFloat(side)
            let r = CGRect(x: CGFloat(pad), y: CGFloat(pad) + s * 0.04, width: s, height: s * 0.92)
            let path = heartPath(in: r)
            if full {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.06), blur: s * 0.14, color: GameUIPalette.cg(GameUIPalette.ink, 0.55))
                ctx.addPath(path)
                ctx.setFillColor(CGColor(srgbRed: 0.86, green: 0.22, blue: 0.32, alpha: 1))
                ctx.fillPath()
                ctx.restoreGState()
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                let colors = [CGColor(srgbRed: 1, green: 0.66, blue: 0.64, alpha: 1), CGColor(srgbRed: 0.98, green: 0.36, blue: 0.42, alpha: 1),
                              CGColor(srgbRed: 0.7, green: 0.12, blue: 0.26, alpha: 1)] as CFArray
                if let g = CGGradient(colorsSpace: GameUISprites.space, colors: colors, locations: [0, 0.5, 1]) {
                    ctx.drawRadialGradient(g, startCenter: CGPoint(x: r.minX + s * 0.32, y: r.minY + r.height * 0.74), startRadius: 1,
                                           endCenter: CGPoint(x: r.midX, y: r.midY), endRadius: s * 0.68, options: [.drawsAfterEndLocation])
                }
                ctx.restoreGState()
                // The shine, top left.
                ctx.saveGState()
                ctx.translateBy(x: r.minX + s * 0.28, y: r.minY + r.height * 0.7)
                ctx.rotate(by: 0.6)
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.82))
                ctx.fillEllipse(in: CGRect(x: -s * 0.1, y: -s * 0.045, width: s * 0.2, height: s * 0.09))
                ctx.restoreGState()
                ctx.addPath(path)
                ctx.setStrokeColor(CGColor(srgbRed: 0.42, green: 0.04, blue: 0.14, alpha: 0.8))
                ctx.setLineWidth(max(1.2, s * 0.04))
                ctx.strokePath()
            } else {
                ctx.addPath(path)
                ctx.setFillColor(GameUIPalette.cg(GameUIPalette.ink, 0.45))
                ctx.fillPath()
                ctx.addPath(path)
                ctx.setStrokeColor(GameUIPalette.cg(GameUIPalette.cream, 0.5))
                ctx.setLineWidth(max(1.5, s * 0.07))
                ctx.strokePath()
            }
        }
    }

    static func heartPath(in r: CGRect) -> CGPath {
        let p = CGMutablePath()
        let bottom = CGPoint(x: r.midX, y: r.minY)
        p.move(to: bottom)
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.62), control1: CGPoint(x: r.midX - r.width * 0.12, y: r.minY + r.height * 0.16),
                   control2: CGPoint(x: r.minX, y: r.minY + r.height * 0.38))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.8), control1: CGPoint(x: r.minX, y: r.maxY + r.height * 0.06),
                   control2: CGPoint(x: r.midX - r.width * 0.06, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.62), control1: CGPoint(x: r.midX + r.width * 0.06, y: r.maxY),
                   control2: CGPoint(x: r.maxX, y: r.maxY + r.height * 0.06))
        p.addCurve(to: bottom, control1: CGPoint(x: r.maxX, y: r.minY + r.height * 0.38),
                   control2: CGPoint(x: r.midX + r.width * 0.12, y: r.minY + r.height * 0.16))
        p.closeSubpath()
        return p
    }

    /// A ring that drains clockwise from the top: a track, then the part left in `tone`.
    static func ring(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat, width: CGFloat, fraction: Double, tone: SIMD3<Double>) {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineWidth(width + 3)
        ctx.setStrokeColor(GameUIPalette.cg(GameUIPalette.ink, 0.5))
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.setLineWidth(width)
        ctx.setStrokeColor(GameUIPalette.cg(GameUIPalette.cream, 0.16))
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let f = GameUIEase.clamp(fraction)
        if f > 0.002 {
            ctx.setStrokeColor(GameUIPalette.cg(tone))
            ctx.addArc(center: c, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * CGFloat(f), clockwise: true)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Two rounded bars: paused.
    static func pause(_ ctx: CGContext, center c: CGPoint, height: CGFloat, tone: SIMD3<Double>, alpha: Double) {
        let w = height * 0.3, gap = height * 0.22
        for dx in [-gap / 2 - w, gap / 2] {
            let bar = CGRect(x: c.x + dx, y: c.y - height / 2, width: w, height: height)
            ctx.addPath(CGPath(roundedRect: bar.insetBy(dx: -1.5, dy: -1.5), cornerWidth: w / 2 + 1.5, cornerHeight: w / 2 + 1.5, transform: nil))
        }
        ctx.setFillColor(GameUIPalette.cg(GameUIPalette.ink, 0.6 * alpha))
        ctx.fillPath()
        for dx in [-gap / 2 - w, gap / 2] {
            let bar = CGRect(x: c.x + dx, y: c.y - height / 2, width: w, height: height)
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil))
        }
        ctx.setFillColor(GameUIPalette.cg(tone, alpha))
        ctx.fillPath()
    }

    /// A five-pointed star with a bevel lit from the top left, for records.
    static func star(side: Int) -> CGImage? {
        GameUISprites.image("star|\(side)", width: side + 12, height: side + 12) { ctx in
            let c = CGPoint(x: CGFloat(side + 12) / 2, y: CGFloat(side + 12) / 2)
            let r = CGFloat(side) / 2
            let outer = CGMutablePath()
            for i in 0..<10 {
                let rr = i % 2 == 0 ? r : r * 0.46
                let a = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let p = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                if i == 0 { outer.move(to: p) } else { outer.addLine(to: p) }
            }
            outer.closeSubpath()
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 3, color: GameUIPalette.cg(GameUIPalette.ink, 0.5))
            ctx.addPath(outer)
            ctx.setFillColor(GameUIPalette.cg(GameUIPalette.shade(GameUIPalette.gold, -0.2)))
            ctx.fillPath()
            ctx.restoreGState()
            for i in 0..<10 {
                let a0 = CGFloat.pi / 2 + CGFloat(i) * .pi / 5, a1 = CGFloat.pi / 2 + CGFloat(i + 1) * .pi / 5
                let r0 = i % 2 == 0 ? r : r * 0.46, r1 = i % 2 == 0 ? r * 0.46 : r
                let facet = CGMutablePath()
                facet.move(to: c)
                facet.addLine(to: CGPoint(x: c.x + cos(a0) * r0, y: c.y + sin(a0) * r0))
                facet.addLine(to: CGPoint(x: c.x + cos(a1) * r1, y: c.y + sin(a1) * r1))
                facet.closeSubpath()
                let light = 0.5 + 0.5 * Double(cos((a0 + a1) / 2 - 2.3))
                ctx.addPath(facet)
                ctx.setFillColor(GameUIPalette.cg(GameUIPalette.shade(GameUIPalette.gold, light * 0.45 - 0.18)))
                ctx.fillPath()
            }
            ctx.addPath(outer)
            ctx.setStrokeColor(GameUIPalette.cg(GameUIPalette.shade(GameUIPalette.gold, -0.45)))
            ctx.setLineWidth(1.2)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
    }

    // MARK: Icons

    /// Fills `path` as cream card lit from the top left, with an ink outline: the look of the figure icon.
    private static func paintCutout(_ ctx: CGContext, _ path: CGPath, top: SIMD3<Double>, edge: CGFloat) {
        ctx.addPath(path)
        ctx.setStrokeColor(GameUIPalette.cg(GameUIPalette.ink, 0.95))
        ctx.setLineWidth(edge * 2)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let box = path.boundingBoxOfPath
        if let g = CGGradient(colorsSpace: GameUISprites.space,
                              colors: [GameUIPalette.cg(GameUIPalette.shade(top, 0.25)), GameUIPalette.cg(top), GameUIPalette.cg(GameUIPalette.shade(top, -0.2))] as CFArray,
                              locations: [0, 0.45, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), options: [])
        }
        ctx.restoreGState()
    }

    private static let skin = SIMD3<Double>(1.0, 0.82, 0.68)
    private static let shirt = SIMD3<Double>(0.98, 0.95, 0.88)

    /// A little figure, head and shoulders, for games played with the whole body: a cut-out lit from the top left with an ink edge.
    /// Its waving arm is a picture of its own (`figureArm`), turned about the shoulder as it is drawn.
    static func figure(radius: Int) -> CGImage? {
        let side = radius * 2
        return GameUISprites.image("figure|\(radius)", width: side, height: side) { ctx in
            let r = CGFloat(radius)
            let c = CGPoint(x: r, y: r)
            let edge = max(1.5, r * 0.07)
            let body = CGMutablePath()
            body.move(to: CGPoint(x: c.x - r * 0.66, y: c.y - r * 0.9))
            body.addCurve(to: CGPoint(x: c.x, y: c.y - r * 0.12), control1: CGPoint(x: c.x - r * 0.7, y: c.y - r * 0.3),
                          control2: CGPoint(x: c.x - r * 0.46, y: c.y - r * 0.12))
            body.addCurve(to: CGPoint(x: c.x + r * 0.66, y: c.y - r * 0.9), control1: CGPoint(x: c.x + r * 0.46, y: c.y - r * 0.12),
                          control2: CGPoint(x: c.x + r * 0.7, y: c.y - r * 0.3))
            body.closeSubpath()
            paintCutout(ctx, body, top: shirt, edge: edge)
            let head = CGPath(ellipseIn: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.02, width: r * 0.6, height: r * 0.66), transform: nil)
            paintCutout(ctx, head, top: skin, edge: edge)
            // A cheerful face: two dots and a smile.
            ctx.setFillColor(GameUIPalette.cg(GameUIPalette.ink, 0.9))
            for dx in [-0.1, 0.1] as [CGFloat] {
                ctx.fillEllipse(in: CGRect(x: c.x + r * dx - r * 0.035, y: c.y + r * 0.33, width: r * 0.07, height: r * 0.09))
            }
            ctx.setStrokeColor(GameUIPalette.cg(GameUIPalette.ink, 0.9))
            ctx.setLineWidth(max(1.2, r * 0.045))
            ctx.addArc(center: CGPoint(x: c.x, y: c.y + r * 0.26), radius: r * 0.1, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
            ctx.strokePath()
        }
    }

    /// The figure's arm, pointing straight up from its shoulder at the bottom middle of the picture, with a round hand.
    static func figureArm(radius: Int) -> CGImage? {
        let r = CGFloat(radius)
        let w = Int((r * 0.5).rounded(.up)) + 4, h = Int((r * 1.08).rounded(.up)) + 4
        return GameUISprites.image("figure-arm|\(radius)", width: w, height: h) { ctx in
            let x = CGFloat(w) / 2
            let edge = max(1.5, r * 0.07)
            let arm = CGMutablePath()
            arm.move(to: CGPoint(x: x, y: r * 0.12))
            arm.addLine(to: CGPoint(x: x, y: r * 0.74))
            paintCutout(ctx, arm.copy(strokingWithWidth: r * 0.2, lineCap: .round, lineJoin: .round, miterLimit: 1), top: shirt, edge: edge)
            let hand = CGPath(ellipseIn: CGRect(x: x - r * 0.14, y: r * 0.7, width: r * 0.28, height: r * 0.28), transform: nil)
            paintCutout(ctx, hand, top: skin, edge: edge)
        }
    }

    /// Draws the icon for how a game is played, `radius` pixels round, moving gently with the clock.
    static func icon(_ ctx: CGContext, _ icon: GameUIIcon, center c: CGPoint, radius r: CGFloat, time: Double) {
        switch icon {
        case .automatic, .body:
            // A figure waving one arm from its shoulder, the arm behind the body.
            let size = Int(r.rounded())
            let wave = CGFloat(-0.62 + 0.36 * sin(time * 3.4))
            if let arm = figureArm(radius: size) {
                let shoulder = CGPoint(x: c.x + r * 0.42, y: c.y - r * 0.36)
                ctx.saveGState()
                ctx.translateBy(x: shoulder.x, y: shoulder.y)
                ctx.rotate(by: wave)
                ctx.draw(arm, in: CGRect(x: -CGFloat(arm.width) / 2, y: -r * 0.12, width: CGFloat(arm.width), height: CGFloat(arm.height)))
                ctx.restoreGState()
            }
            GameUISprites.stamp(ctx, figure(radius: size), center: c)
        case .hand(let pose):
            let wave = pose == .open ? CGFloat(sin(time * 3.2) * 0.2) : CGFloat(sin(time * 2.4) * 0.06)
            GameUISprites.stamp(ctx, HandPlayGlove.image(pose, height: r * 1.7), center: CGPoint(x: c.x, y: c.y + r * 0.05), rotation: -wave)
        case .face(let move):
            FaceGameMascot.act(ctx, move, center: c, radius: Double(r * 0.86), time: time)
        }
    }
}

// MARK: - What a game shows

/// How a game is played, for the icon on its cards and hints.
enum GameUIIcon: Equatable {
    /// Picked from what the game is played with: a figure, a hand or a face.
    case automatic
    case body
    case hand(HandPlayPose)
    case face(FaceGameMove)
}

/// What the player is asked to bring: the runner waits for it, and its absence pauses the game.
enum GameUIPlayer: Equatable {
    case body, hands, face

    /// What the pause asks for.
    var comeBack: String {
        switch self {
        case .body: return "Step back in to keep playing"
        case .hands: return "Hold up your hand to keep playing"
        case .face: return "Look at the camera to keep playing"
        }
    }

    var icon: GameUIIcon {
        switch self {
        case .body: return .body
        case .hands: return .hand(.open)
        case .face: return .face(.keepEyesOpen)
        }
    }
}

/// The plates in the corners while a game is played: the score, and beside it whatever else belongs there.
struct GameUIReadout {
    var score: Int
    /// Hearts: how many are left, of how many.
    var lives: (left: Int, of: Int)?
    /// Seconds left, of how many.
    var time: (left: Double, of: Double)?
    /// A multiplier or streak worth bragging about, shown as "×3" beside the score; 0 or 1 shows nothing.
    var combo = 0
    /// A short word for the status plate: "Round 2/5", "Level 3", "Length 7".
    var label: String?
    /// A tip for the bottom of the picture while there is something worth saying.
    var tip: String?

    init(score: Int, lives: (left: Int, of: Int)? = nil, time: (left: Double, of: Double)? = nil, combo: Int = 0, label: String? = nil,
         tip: String? = nil) {
        self.score = score
        self.lives = lives
        self.time = time
        self.combo = combo
        self.label = label
        self.tip = tip
    }
}

/// How a round went, for the result card.
struct GameUIResult {
    enum Kind: Equatable {
        /// Beat the game outright: gold, light rays and confetti.
        case won
        /// Lost: a coral headline that lands with a shake.
        case lost
        /// The clock ran out: not a loss, just a score.
        case timeUp
    }

    /// What happened, in two or three words: "Time's up!", "Out of lives".
    var headline: String
    /// One line on how it went.
    var line: String
    /// Up to three numbers worth knowing, each with a word.
    var stats: [(value: String, label: String)]
    var kind: Kind

    init(headline: String, line: String = "", stats: [(value: String, label: String)] = [], kind: Kind = .lost) {
        self.headline = headline
        self.line = line
        self.stats = stats
        self.kind = kind
    }
}

/// The springs and memories the plates animate with: the score bouncing when it goes up, a heart shaking as it is lost, the combo
/// badge popping in, the gold of a new record. Stepped by the runner each frame of play.
struct GameUIMotion {
    private(set) var scoreAge = 9.0
    private(set) var comboAge = 9.0
    private(set) var lifeAge = 9.0
    private(set) var recordAge = 9.0
    private(set) var shownScore = 0
    private var lastCombo = 0
    private var lastLives: Int?
    private var wasRecord = false

    mutating func reset() { self = GameUIMotion() }

    mutating func step(_ dt: Double, readout: GameUIReadout, record: Bool) {
        let dt = max(0, min(dt, 0.25))
        scoreAge += dt
        comboAge += dt
        lifeAge += dt
        recordAge += dt
        if readout.score != shownScore {
            if readout.score > shownScore { scoreAge = 0 }
            shownScore = readout.score
        }
        if readout.combo != lastCombo {
            if readout.combo > max(1, lastCombo) { comboAge = 0 }
            lastCombo = readout.combo
        }
        if let lives = readout.lives?.left {
            if let last = lastLives, lives < last { lifeAge = 0 }
            lastLives = lives
        }
        if record && !wasRecord { recordAge = 0 }
        wasRecord = record
    }
}

// MARK: - The screens

/// Draws every screen a game has. The runner (`GameLens`) decides which one and when; the screens only draw.
enum GameScreens {
    /// The safe border: 5% of a 1280 x 720 picture.
    static let margin = CGSize(width: 64, height: 36)
    static let scorePlateHeight: CGFloat = 92
    static let statusPlateHeight: CGFloat = 64
    static let pillHeight: CGFloat = 60

    /// The line below which a game's own words and fixed art belong: the plates sit above it in the corners.
    static func topBand(_ size: CGSize) -> CGFloat { size.height - margin.height - scorePlateHeight - 12 }
    /// Where a call-out sits: top middle, between the plates.
    static func calloutCenter(_ size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: size.height - margin.height - 38) }
    /// Where hints and tips sit: bottom middle.
    static func pillCenter(_ size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: margin.height + pillHeight / 2) }

    /// What the screens need to know about a game.
    struct Look {
        var title: String
        var hint: String
        var presenceHint: String
        var accent: SIMD3<Double>
        var icon: GameUIIcon
        var scoreLabel: String
        var player: GameUIPlayer
    }

    // MARK: Getting ready

    private static let preparedLock = NSLock()
    private static var prepared = Set<String>()

    /// Bakes, off the video queue and once per game, the pictures of its first screens (the waiting card and the countdown) and the
    /// shared pieces of play, so neither the first frame of a game nor the first frame of play stalls. Called when a game's lens is
    /// made; it returns at once.
    static func prepare(_ look: Look) {
        preparedLock.lock()
        let fresh = prepared.insert("\(look.title)|\(look.player)|\(GameUIPalette.key(look.accent))").inserted
        preparedLock.unlock()
        guard fresh else { return }
        DispatchQueue.global(qos: .utility).async {
            let size = CGSize(width: 1280, height: 720)
            guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: GameUISprites.space, bitmapInfo: Sprites.bitmapInfo) else { return }
            waiting(ctx, size: size, look: look, progress: 0.5, best: nil, age: 1, time: 0)
            for n in [3.0, 2.0, 1.0] { countdown(ctx, size: size, look: look, remaining: n - 0.5, total: 3, time: 0) }
            var step = 0
            while warmUp(step, look: look) { step += 1 }
        }
    }

    /// Bakes one more of the shared pieces of play and of the result card; false when there is nothing left. The runner calls it once
    /// a frame during the countdown, so whatever `prepare` has not done yet is spread over many frames.
    static func warmUp(_ step: Int, look: Look) -> Bool {
        guard step <= 7 else { return false }
        guard let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: GameUISprites.space,
                                  bitmapInfo: Sprites.bitmapInfo) else { return false }
        let size = CGSize(width: 1280, height: 720)
        switch step {
        case 0:
            _ = GameUIPieces.heart(full: true)
            _ = GameUIPieces.heart(full: false)
        case 1, 2:
            // The digits of the score, in cream and in record gold.
            let tone = step == 1 ? GameUIPalette.cream : GameUIPalette.gold
            for c in "0123456789" { GameUIType.number(ctx, String(c), at: .zero, size: 48, color: tone) }
        case 3:
            for c in "0123456789×" { GameUIType.number(ctx, String(c), at: .zero, size: 30) }
            for c in "0123456789" { GameUIType.number(ctx, String(c), at: .zero, size: 30, color: GameUIPalette.coral) }
            for c in "0123456789×" { GameUIType.number(ctx, String(c), at: .zero, size: 30, color: GameUIPalette.gold) }
            // The numbers in status words ("Wave 3", "Round 2/5").
            for c in "0123456789/:." { GameUIType.number(ctx, String(c), at: .zero, size: 24) }
        case 4:
            _ = GameUIType.image(look.scoreLabel, size: 15, color: look.accent)
            _ = GameUIType.image("NEW BEST", size: 15, color: GameUIPalette.gold)
            _ = GameUIType.image("GO!", size: 64, color: GameUIPalette.mint, edge: 0.22)
            GameUIPlate.draw(ctx, CGRect(x: 0, y: 0, width: 300, height: scorePlateHeight), radius: 26)
            GameUIPlate.draw(ctx, CGRect(x: 0, y: 0, width: 300, height: statusPlateHeight), radius: 24)
        case 5:
            pill(ctx, size: size, text: look.player.comeBack, look: look, alpha: 1, time: 0)
            paused(ctx, size: size, look: look, age: 1, time: 0)
        case 6:
            ribbon(ctx, at: .zero, time: 0, age: 2)
            shade(ctx, size: size, strength: 1)
        default:
            rays(ctx, center: .zero, time: 0, alpha: 0.5)
        }
        return true
    }

    // MARK: Cards

    /// The disc the icon sits in on every card, tinted with the game's colour.
    private static func iconDisc(_ ctx: CGContext, _ look: Look, center c: CGPoint, radius r: CGFloat, time: Double) {
        let disc = GameUISprites.image("disc|\(Int(r))|\(GameUIPalette.key(look.accent))", width: Int(r * 2) + 4, height: Int(r * 2) + 4) { ctx in
            let o = CGPoint(x: r + 2, y: r + 2)
            ctx.addEllipse(in: CGRect(x: o.x - r, y: o.y - r, width: r * 2, height: r * 2))
            ctx.clip()
            if let g = CGGradient(colorsSpace: GameUISprites.space, colors: [GameUIPalette.cg(look.accent, 0.34), GameUIPalette.cg(look.accent, 0.12)] as CFArray,
                                  locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: o.x - r, y: o.y + r), end: CGPoint(x: o.x + r, y: o.y - r), options: [])
            }
        }
        GameUISprites.stamp(ctx, disc, center: c)
        GameUIPieces.icon(ctx, look.icon, center: c, radius: r * 0.78, time: time)
    }

    /// Before a round: a card low in the picture with the game's name, what to do, and a ring round the icon that fills while the
    /// player settles in. `age` is seconds since the waiting screen came up.
    static func waiting(_ ctx: CGContext, size: CGSize, look: Look, progress: Double, best: String?, age: Double, time: Double) {
        let titleWidth = GameUIType.width(look.title, size: 40)
        let hintWidth = GameUIType.width(look.presenceHint, size: 24, weight: .bold)
        let w = min(size.width - margin.width * 2, max(560, max(titleWidth, hintWidth) + 210))
        let h: CGFloat = 132
        let rise = GameUIEase.outBack(age / 0.5, 1.2)
        let rect = CGRect(x: (size.width / 2 - w / 2).rounded(), y: margin.height + 6 - CGFloat(1 - rise) * 50, width: w, height: h)
        let alpha = CGFloat(GameUIEase.clamp(age / 0.3))
        ctx.saveGState()
        if alpha < 1 { ctx.setAlpha(alpha) }
        GameUIPlate.draw(ctx, rect, radius: 34)
        let iconCenter = CGPoint(x: rect.minX + 78, y: rect.midY)
        iconDisc(ctx, look, center: iconCenter, radius: 46, time: time)
        let filled = GameUIEase.outCubic(progress)
        if filled > 0.01 {
            GameUIPieces.ring(ctx, center: iconCenter, radius: 52, width: 6, fraction: filled, tone: look.accent)
        }
        let textX = rect.minX + 148
        GameUIType.draw(ctx, look.title, at: CGPoint(x: textX, y: rect.midY + 22), size: 40, color: look.accent, align: .left)
        // The prompt breathes gently, so the card reads as waiting, not frozen.
        let breathe = 0.82 + 0.18 * (0.5 + 0.5 * sin(time * 2.6))
        GameUIType.draw(ctx, look.presenceHint, at: CGPoint(x: textX, y: rect.midY - 24), size: 24, weight: .bold, align: .left, alpha: CGFloat(breathe))
        if let best {
            let text = "BEST \(best)"
            let bw = GameUIType.width(text, size: 17) + 34
            let chip = CGRect(x: rect.maxX - bw - 22, y: rect.maxY - 18, width: bw, height: 36)
            GameUIPlate.draw(ctx, chip, radius: 18, fill: GameUIPalette.shade(GameUIPalette.ink, 0.06), opacity: 0.95, rim: GameUIPalette.gold)
            GameUIType.draw(ctx, text, at: CGPoint(x: chip.midX, y: chip.midY), size: 17, color: GameUIPalette.gold)
        }
        ctx.restoreGState()
    }

    /// Lays the countdown card out: the same frame for the countdown and for the moment it leaves.
    private static func countdownCard(_ size: CGSize, look: Look) -> (rect: CGRect, lines: [String]) {
        let lines = GameUIType.lines(look.hint, size: 25, maxWidth: min(620, size.width - margin.width * 2 - 330))
        let widest = max(GameUIType.width(look.title, size: 34), lines.map { GameUIType.width($0, size: 25, weight: .bold) }.max() ?? 0)
        let w = min(size.width - margin.width * 2, max(640, widest + 330))
        return (CGRect(x: (size.width / 2 - w / 2).rounded(), y: margin.height + 6, width: w, height: 164), lines)
    }

    /// The countdown, in a card in the lower third: the move acted out, the name, how to play, and the count in a ring that drains
    /// over each second.
    static func countdown(_ ctx: CGContext, size: CGSize, look: Look, remaining: Double, total: Double, time: Double) {
        let (base, lines) = countdownCard(size, look: look)
        let elapsed = total - remaining
        let rise = GameUIEase.outBack(elapsed / 0.45, 1.2)
        let rect = base.offsetBy(dx: 0, dy: -CGFloat(1 - rise) * 60)
        ctx.saveGState()
        let alpha = CGFloat(GameUIEase.clamp(elapsed / 0.25))
        if alpha < 1 { ctx.setAlpha(alpha) }
        drawCountdownCard(ctx, rect: rect, lines: lines, look: look, time: time)
        let n = max(1, Int(remaining.rounded(.up)))
        let within = remaining - Double(n - 1)                // 1 at the start of each second, down to 0
        let ringCenter = CGPoint(x: rect.maxX - 86, y: rect.midY)
        GameUIPieces.ring(ctx, center: ringCenter, radius: 50, width: 8, fraction: within, tone: look.accent)
        let pop = GameUIEase.outBack((1 - within) / 0.28, 2.2)
        GameUIType.number(ctx, "\(n)", at: CGPoint(x: ringCenter.x, y: ringCenter.y + 2), size: 64, scale: CGFloat(0.55 + 0.45 * pop))
        ctx.restoreGState()
    }

    private static func drawCountdownCard(_ ctx: CGContext, rect: CGRect, lines: [String], look: Look, time: Double) {
        GameUIPlate.draw(ctx, rect, radius: 38)
        iconDisc(ctx, look, center: CGPoint(x: rect.minX + 90, y: rect.midY), radius: 58, time: time)
        let textX = rect.minX + 178
        let top = rect.maxY - (lines.count > 1 ? 42 : 56)
        GameUIType.draw(ctx, look.title, at: CGPoint(x: textX, y: top), size: 34, color: look.accent, align: .left)
        for (i, line) in lines.enumerated() {
            GameUIType.draw(ctx, line, at: CGPoint(x: textX, y: top - 46 - CGFloat(i) * 34), size: 25, weight: .bold, align: .left)
        }
    }

    /// The first moment of play: the countdown card drops away and "GO!" pops where the count was. `age` is seconds of play.
    static func go(_ ctx: CGContext, size: CGSize, look: Look, age: Double, time: Double) {
        guard age < 0.7 else { return }
        let (base, lines) = countdownCard(size, look: look)
        let leave = GameUIEase.inOut(age / 0.4)
        if leave < 1 {
            // It settles back a little and fades, staying inside the border as it goes.
            let k = CGFloat(1 - 0.06 * leave)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(1 - leave))
            ctx.translateBy(x: base.midX, y: base.minY)
            ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: -base.midX, y: -base.minY)
            drawCountdownCard(ctx, rect: base, lines: lines, look: look, time: time)
            ctx.restoreGState()
        }
        let pop = GameUIEase.outBack(age / 0.22, 2.4)
        let fade = GameUIEase.clamp((0.7 - age) / 0.3)
        GameUIType.draw(ctx, "GO!", at: CGPoint(x: base.maxX - 86, y: base.midY + 4 + CGFloat(age) * 40), size: 64, color: GameUIPalette.mint,
                        alpha: CGFloat(fade), scale: CGFloat(max(0.05, pop)), edge: 0.22)
    }

    // MARK: Play

    /// The plates in the corners: the score (with the best beside its label) at the top left, a combo badge beside it, and hearts,
    /// the clock and a word in one plate at the top right.
    static func plates(_ ctx: CGContext, size: CGSize, look: Look, readout: GameUIReadout, scoreText: String, best: String?, record: Bool,
                       motion: GameUIMotion, time: Double) {
        let top = size.height - margin.height
        // The score.
        let bestText = record ? "NEW BEST" : best.map { "BEST \($0)" }
        let labelWidth = GameUIType.width(look.scoreLabel, size: 15)
        let bestWidth = bestText.map { GameUIType.width($0, size: 15) } ?? 0
        let numberWidth = GameUIType.numberWidth(scoreText, size: 48)
        let rawWidth = max(206, labelWidth + bestWidth + (bestText == nil ? 48 : 68), numberWidth + 52)
        let scoreRect = CGRect(x: margin.width, y: top - scorePlateHeight, width: (rawWidth / 16).rounded(.up) * 16, height: scorePlateHeight)
        GameUIPlate.draw(ctx, scoreRect, radius: 26)
        GameUIType.draw(ctx, look.scoreLabel, at: CGPoint(x: scoreRect.minX + 22, y: scoreRect.maxY - 22), size: 15, color: look.accent, align: .left)
        if let bestText {
            let pop = record ? 1 + 0.3 * GameUIEase.wobble(motion.recordAge, frequency: 2.4, damping: 7) : 1
            GameUIType.draw(ctx, bestText, at: CGPoint(x: scoreRect.maxX - 20, y: scoreRect.maxY - 22), size: 15,
                            color: record ? GameUIPalette.gold : GameUIPalette.shade(GameUIPalette.cream, -0.32), align: .right, scale: CGFloat(pop))
        }
        let bounce = 1 + 0.2 * GameUIEase.wobble(motion.scoreAge, frequency: 2.2, damping: 8)
        GameUIType.number(ctx, scoreText, at: CGPoint(x: scoreRect.minX + 22, y: scoreRect.minY + 34), size: 48,
                          color: record ? GameUIPalette.gold : GameUIPalette.cream, align: .left, scale: CGFloat(bounce))

        // The combo badge.
        if readout.combo > 1 {
            let grow = GameUIEase.outBack(motion.comboAge / 0.3, 2)
            let text = "×\(readout.combo)"
            let w = GameUIType.numberWidth(text, size: 30) + 34
            let badge = CGRect(x: scoreRect.maxX + 12, y: scoreRect.midY - 25, width: (w / 4).rounded(.up) * 4, height: 50)
            let image = GameUIPlate.image(width: Int(badge.width), height: Int(badge.height), radius: 25, fill: GameUIPalette.berry, opacity: 0.92)
            GameUISprites.stamp(ctx, image, center: CGPoint(x: badge.midX, y: badge.midY), scale: CGFloat(max(0.05, grow)))
            GameUIType.number(ctx, text, at: CGPoint(x: badge.midX, y: badge.midY), size: 30, color: GameUIPalette.gold, scale: CGFloat(max(0.05, grow)))
        }

        // The status plate: a word, the clock, the hearts, left to right.
        var parts: [(width: CGFloat, draw: (CGFloat, CGFloat) -> Void)] = []
        if let label = readout.label, !label.isEmpty {
            let w = GameUIType.mixedWidth(label, size: 24)
            parts.append((w, { x, y in GameUIType.mixed(ctx, label, at: CGPoint(x: x, y: y), size: 24) }))
        }
        if let clock = readout.time {
            let text = "\(Int(max(0, clock.left).rounded(.up)))"
            let w = 40 + GameUIType.numberWidth(text, size: 30)
            parts.append((w, { x, y in
                let urgent = clock.left <= 5.0
                let tone = urgent ? GameUIPalette.coral : GameUIPalette.mint
                GameUIPieces.ring(ctx, center: CGPoint(x: x + 15, y: y), radius: 13, width: 5, fraction: clock.left / max(clock.of, 1e-6), tone: tone)
                // In the last seconds the number swells softly once a second: a pulse, never a flash.
                let into = clock.left - clock.left.rounded(.down)
                let pulse = urgent && clock.left > 0 ? 1 + 0.12 * GameUIEase.outCubic(into) * into : 1
                GameUIType.number(ctx, text, at: CGPoint(x: x + 40, y: y), size: 30, color: urgent ? GameUIPalette.coral : GameUIPalette.cream,
                                  align: .left, scale: CGFloat(pulse))
            }))
        }
        if let lives = readout.lives, lives.of > 0 {
            let w = CGFloat(lives.of) * 36 - 4
            parts.append((w, { x, y in
                for i in 0..<lives.of {
                    let full = i < lives.left
                    let shaking = i == lives.left && motion.lifeAge < 0.6
                    let jolt = shaking ? CGFloat(7 * GameUIEase.wobble(motion.lifeAge, frequency: 5, damping: 6)) : 0
                    let beat = full && lives.left == 1 ? 1 + 0.08 * max(0, sin(time * 6)) : 1
                    let c = CGPoint(x: x + 16 + CGFloat(i) * 36 + jolt, y: y)
                    GameUISprites.stamp(ctx, GameUIPieces.heart(full: full), center: c, scale: CGFloat(beat))
                    if shaking {
                        let k = motion.lifeAge / 0.6
                        GameUISprites.stamp(ctx, GameUIPieces.heart(full: true), center: CGPoint(x: c.x, y: c.y + CGFloat(k) * 10),
                                            scale: CGFloat(1 + 0.6 * GameUIEase.outCubic(k)), alpha: CGFloat(1 - k))
                    }
                }
            }))
        }
        guard !parts.isEmpty else { return }
        let gap: CGFloat = 22
        let inner = parts.reduce(0) { $0 + $1.width } + gap * CGFloat(parts.count - 1)
        let w = ((inner + 44) / 8).rounded(.up) * 8
        let statusRect = CGRect(x: size.width - margin.width - w, y: top - statusPlateHeight, width: w, height: statusPlateHeight)
        GameUIPlate.draw(ctx, statusRect, radius: 24)
        var x = statusRect.minX + 22
        for part in parts {
            part.draw(x, statusRect.midY)
            x += part.width + gap
        }
    }

    /// A hint or tip in a pill at the bottom middle, with the game's icon beside it. `alpha` fades it in and out.
    static func pill(_ ctx: CGContext, size: CGSize, text: String, look: Look, alpha: Double, time: Double) {
        guard alpha > 0.01, !text.isEmpty else { return }
        let textWidth = GameUIType.width(text, size: 25, weight: .bold)
        let w = min(size.width - margin.width * 2, textWidth + 104)
        let rect = CGRect(x: (size.width / 2 - w / 2).rounded(), y: margin.height, width: w, height: pillHeight)
        ctx.saveGState()
        if alpha < 0.995 { ctx.setAlpha(CGFloat(alpha)) }
        GameUIPlate.draw(ctx, rect, radius: pillHeight / 2)
        GameUIPieces.icon(ctx, look.icon, center: CGPoint(x: rect.minX + 38, y: rect.midY), radius: 21, time: time)
        GameUIType.draw(ctx, text, at: CGPoint(x: rect.minX + 70, y: rect.midY), size: 25, weight: .bold, align: .left)
        ctx.restoreGState()
    }

    /// Shown while the player has been gone a while: the game is paused until they come back. Low in the picture, like every card.
    static func paused(_ ctx: CGContext, size: CGSize, look: Look, age: Double, time: Double) {
        let line = look.player.comeBack
        let w = GameUIType.width(line, size: 26, weight: .bold) + 130
        let rise = GameUIEase.outBack(age / 0.35, 1.3)
        let rect = CGRect(x: (size.width / 2 - w / 2).rounded(), y: margin.height - CGFloat(1 - rise) * 30, width: w, height: 84)
        ctx.saveGState()
        let alpha = CGFloat(GameUIEase.clamp(age / 0.25))
        if alpha < 1 { ctx.setAlpha(alpha) }
        GameUIPlate.draw(ctx, rect, radius: 30)
        let breathe = 0.7 + 0.3 * (0.5 + 0.5 * sin(time * 3))
        GameUIPieces.pause(ctx, center: CGPoint(x: rect.minX + 52, y: rect.midY), height: 36, tone: GameUIPalette.gold, alpha: breathe)
        GameUIType.draw(ctx, "PAUSED", at: CGPoint(x: rect.minX + 92, y: rect.midY + 18), size: 16, color: GameUIPalette.gold, align: .left)
        GameUIType.draw(ctx, line, at: CGPoint(x: rect.minX + 92, y: rect.midY - 12), size: 26, weight: .bold, align: .left)
        ctx.restoreGState()
    }

    // MARK: Result

    /// The result card, low in the picture: a headline that lands on its top edge, the score counting up, the best (or a NEW BEST
    /// ribbon), a line on how it went, up to three stats, and a thin line running down to the next round. A win or a record gets
    /// confetti; a win gets light behind its headline. All of it is a function of `age`, the seconds since the round ended.
    static func result(_ ctx: CGContext, size: CGSize, look: Look, result: GameUIResult, score: Int, scoreText: (Int) -> String, best: String?,
                       newBest: Bool, age: Double, total: Double, time: Double, shaded: Bool = true) {
        let tone: SIMD3<Double>
        switch result.kind {
        case .won: tone = GameUIPalette.gold
        case .lost: tone = GameUIPalette.coral
        case .timeUp: tone = GameUIPalette.sky
        }
        if shaded { shade(ctx, size: size, strength: GameUIEase.outCubic(age / 0.5)) }
        if result.kind == .won || newBest { confetti(ctx, size: size, age: age) }

        let stats = Array(result.stats.prefix(3))
        let lineWidth = GameUIType.width(result.line, size: 22, weight: .bold)
        let w = min(size.width - margin.width * 2, max(640, lineWidth + 80))
        let h: CGFloat = stats.isEmpty ? 176 : 212
        let rise = GameUIEase.outBack(age / 0.5, 1.3)
        let rect = CGRect(x: (size.width / 2 - w / 2).rounded(), y: margin.height - CGFloat(1 - rise) * 90, width: w, height: h)
        ctx.saveGState()
        let alpha = CGFloat(GameUIEase.clamp(age / 0.25))
        if alpha < 1 { ctx.setAlpha(alpha) }
        GameUIPlate.draw(ctx, rect, radius: 40, opacity: 0.9)

        // The headline lands on the top edge with a bounce, or a shake for a loss.
        let head = CGPoint(x: rect.midX, y: rect.maxY + 2)
        if result.kind == .won { rays(ctx, center: head, time: time, alpha: 0.5 * GameUIEase.clamp(age / 0.6)) }
        let land = GameUIEase.outBack(max(0, age - 0.12) / 0.4, 2.4)
        let shake = result.kind == .lost ? GameUIEase.wobble(max(0, age - 0.3) / 0.7 * 0.9, frequency: 2.2, damping: 4) * 0.06 : 0
        // A long headline is set smaller, so it never runs into the corners of the card.
        let headline = result.headline.uppercased()
        let headlineSize = min(56, (56 * (rect.width - 200) / max(1, GameUIType.width(headline, size: 56))).rounded(.down))
        GameUIType.draw(ctx, headline, at: head, size: headlineSize, color: tone, scale: CGFloat(max(0.02, land)),
                        rotation: CGFloat(-0.03 + shake), edge: 0.26)

        GameUIType.draw(ctx, look.scoreLabel, at: CGPoint(x: rect.midX, y: rect.maxY - 50), size: 15, color: GameUIPalette.shade(GameUIPalette.cream, -0.32))
        let counted = Int((Double(score) * GameUIEase.outCubic(max(0, age - 0.2) / 0.8)).rounded())
        let settle = GameUIEase.outBack(max(0, age - 0.2) / 0.35, 1.8)
        GameUIType.number(ctx, scoreText(counted), at: CGPoint(x: rect.midX, y: rect.maxY - 88), size: 54, color: newBest ? GameUIPalette.gold : GameUIPalette.cream,
                          scale: CGFloat(max(0.02, settle)))
        if !result.line.isEmpty {
            GameUIType.draw(ctx, result.line, at: CGPoint(x: rect.midX, y: rect.maxY - 130), size: 22,
                            color: GameUIPalette.shade(GameUIPalette.cream, -0.12), weight: .bold)
        }
        for (i, stat) in stats.enumerated() {
            let x = rect.midX + (CGFloat(i) - CGFloat(stats.count - 1) / 2) * 180
            GameUIType.draw(ctx, stat.value, at: CGPoint(x: x, y: rect.minY + 48), size: 26)
            GameUIType.draw(ctx, stat.label.uppercased(), at: CGPoint(x: x, y: rect.minY + 24), size: 13, color: GameUIPalette.shade(GameUIPalette.cream, -0.38))
        }
        if newBest {
            // Beside the score it celebrates.
            let numberHalf = GameUIType.numberWidth(scoreText(score), size: 54) / 2
            ribbon(ctx, at: CGPoint(x: min(rect.maxX - 104, rect.midX + numberHalf + 112), y: rect.maxY - 86), time: time, age: age)
        } else if let best {
            GameUIType.draw(ctx, "BEST \(best)", at: CGPoint(x: rect.maxX - 28, y: rect.maxY - 30), size: 16, color: GameUIPalette.gold, align: .right)
        }
        // How long until the next round.
        let left = GameUIEase.clamp(1 - age / max(total, 0.1))
        if left > 0.005 {
            let track = CGRect(x: rect.minX + 44, y: rect.minY + 9, width: (rect.width - 88) * CGFloat(left), height: 4)
            ctx.addPath(CGPath(roundedRect: track, cornerWidth: 2, cornerHeight: 2, transform: nil))
            ctx.setFillColor(GameUIPalette.cg(look.accent, 0.7))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    /// Darkens the bottom of the picture under the result card, without hiding the player: a baked strip stretched across.
    private static func shade(_ ctx: CGContext, size: CGSize, strength: Double) {
        guard strength > 0.01 else { return }
        let strip = GameUISprites.image("shade", width: 4, height: 256) { ctx in
            if let g = CGGradient(colorsSpace: GameUISprites.space, colors: [GameUIPalette.cg(GameUIPalette.ink, 0.6), GameUIPalette.cg(GameUIPalette.ink, 0.28),
                                                                             GameUIPalette.cg(GameUIPalette.ink, 0)] as CFArray, locations: [0, 0.45, 1]) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
            }
        }
        guard let strip else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(strength))
        ctx.interpolationQuality = .medium
        ctx.draw(strip, in: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.56))
        ctx.restoreGState()
    }

    /// Slowly turning rays of light behind a winning headline, baked once and turned.
    private static func rays(_ ctx: CGContext, center c: CGPoint, time: Double, alpha: Double) {
        // Squashed into a wide, low fan along the card's top edge, so the light never washes over the player's face.
        let image = GameUISprites.image("rays", width: 380, height: 380) { ctx in
            let o = CGPoint(x: 190, y: 190)
            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi
                ctx.move(to: o)
                ctx.addLine(to: CGPoint(x: o.x + cos(a - 0.11) * 190, y: o.y + sin(a - 0.11) * 190))
                ctx.addLine(to: CGPoint(x: o.x + cos(a + 0.11) * 190, y: o.y + sin(a + 0.11) * 190))
                ctx.closePath()
            }
            ctx.clip()
            if let g = CGGradient(colorsSpace: GameUISprites.space, colors: [GameUIPalette.cg(GameUIPalette.gold, 0.85), GameUIPalette.cg(GameUIPalette.gold, 0)] as CFArray,
                                  locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: o, startRadius: 20, endCenter: o, endRadius: 190, options: [])
            }
        }
        guard let image, alpha > 0.01 else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(alpha))
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: 1.3, y: 0.42)
        ctx.rotate(by: CGFloat(time * 0.35))
        ctx.draw(image, in: CGRect(x: -190, y: -190, width: 380, height: 380))
        ctx.restoreGState()
    }

    /// A gold "NEW BEST!" ribbon pinned to the corner of the result card.
    private static func ribbon(_ ctx: CGContext, at p: CGPoint, time: Double, age: Double) {
        let pop = GameUIEase.outBack(max(0, age - 0.55) / 0.35, 2.6)
        guard pop > 0.01 else { return }
        let image = GameUISprites.image("ribbon", width: 236, height: 84) { ctx in
            let c = CGPoint(x: 118, y: 42)
            let rect = CGRect(x: c.x - 84, y: c.y - 21, width: 168, height: 42)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX - 16, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX + 16, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX + 3, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX + 16, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX - 16, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX - 3, y: rect.midY))
            path.closeSubpath()
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: GameUIPalette.cg(GameUIPalette.ink, 0.5))
            ctx.addPath(path)
            ctx.setFillColor(GameUIPalette.cg(GameUIPalette.shade(GameUIPalette.gold, -0.15)))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            if let g = CGGradient(colorsSpace: GameUISprites.space, colors: [GameUIPalette.cg(GameUIPalette.shade(GameUIPalette.gold, 0.35)),
                                                                             GameUIPalette.cg(GameUIPalette.gold),
                                                                             GameUIPalette.cg(GameUIPalette.shade(GameUIPalette.gold, -0.22))] as CFArray,
                                  locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
            }
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(GameUIPalette.cg(GameUIPalette.shade(GameUIPalette.gold, -0.5)))
            ctx.setLineWidth(2)
            ctx.strokePath()
            if let text = GameUIType.image("NEW BEST!", size: 22, color: GameUIPalette.ink, edge: 0) {
                ctx.draw(text, in: CGRect(x: c.x - CGFloat(text.width) / 2, y: c.y - CGFloat(text.height) / 2 - 1, width: CGFloat(text.width),
                                          height: CGFloat(text.height)))
            }
        }
        GameUISprites.stamp(ctx, image, center: p, scale: CGFloat(pop) * 0.86, rotation: CGFloat(0.1 + 0.03 * sin(time * 3)))
    }

    /// Confetti for a win or a record: paper, dots and curls in the palette's colours, thrown in from both sides, slowed by the air and
    /// drifting down with a flutter, thinning out after three seconds. The same every time for the same `age`.
    static func confetti(_ ctx: CGContext, size: CGSize, age: Double) {
        guard age > 0, age < 4 else { return }
        ctx.saveGState()
        ctx.setLineCap(.round)
        for (i, piece) in confettiPieces.enumerated() {
            let t = age - piece.delay
            guard t > 0 else { continue }
            let fromLeft = i % 2 == 0
            let start = CGPoint(x: fromLeft ? -20 : size.width + 20, y: size.height * CGFloat(0.1 + 0.25 * piece.height))
            let angle = fromLeft ? piece.angle : .pi - piece.angle
            let drag = 1.6
            let travel = piece.speed * (1 - exp(-drag * t)) / drag
            let x = Double(start.x) + cos(angle) * travel + sin(t * piece.flutter + piece.phase) * 18
            let y = Double(start.y) + sin(angle) * travel - 80 * t * t - 40 * t + cos(t * piece.flutter) * 4
            guard y > -30, x > -40, x < Double(size.width) + 40 else { continue }
            let fade = 1 - GameUIEase.inOut((t - 2.6) / 0.8)
            guard fade > 0.01 else { continue }
            let spin = t * piece.spin + piece.phase
            let flip = CGFloat(abs(cos(spin * 1.3)))
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(x), y: CGFloat(y))
            ctx.rotate(by: CGFloat(spin))
            let tone = GameUIPalette.shade(piece.tone, -0.35 * Double(1 - flip))
            ctx.setFillColor(GameUIPalette.cg(tone, fade))
            switch i % 3 {
            case 0: ctx.fill(CGRect(x: -7, y: -4 * flip - 1, width: 14, height: 8 * flip + 2))
            case 1: ctx.fillEllipse(in: CGRect(x: -5, y: -5 * flip - 0.5, width: 10, height: 10 * flip + 1))
            default:
                ctx.setStrokeColor(GameUIPalette.cg(piece.tone, fade))
                ctx.setLineWidth(3.5)
                ctx.move(to: CGPoint(x: -8, y: 0))
                ctx.addCurve(to: CGPoint(x: 8, y: 0), control1: CGPoint(x: -3, y: 8 * flip), control2: CGPoint(x: 3, y: -8 * flip))
                ctx.strokePath()
            }
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    private struct ConfettiPiece {
        var height: Double, angle: Double, speed: Double, delay: Double, flutter: Double, phase: Double, spin: Double, tone: SIMD3<Double>
    }

    /// The same 72 pieces every time, made once.
    private static let confettiPieces: [ConfettiPiece] = {
        let colours = [GameUIPalette.gold, GameUIPalette.coral, GameUIPalette.mint, GameUIPalette.sky, GameUIPalette.violet, GameUIPalette.berry]
        var rng = SplitMix64(seed: 7)
        func unit() -> Double { Double.random(in: 0..<1, using: &rng) }
        return (0..<72).map { i in
            ConfettiPiece(height: unit(), angle: 0.35 + (unit() - 0.5) * 0.9, speed: 520 + 620 * unit(), delay: unit() * 0.35, flutter: 3 + 3 * unit(),
                          phase: unit() * 6, spin: 4 + 6 * unit(), tone: colours[i % colours.count])
        }
    }()

    // MARK: For the games

    /// A short shout in the band between the plates ("ROUND 3", "GOAL!", "PERFECT"): it springs in, holds and fades. Games draw it
    /// from their own `draw`, so their news looks like every other game's. `age` is seconds since it appeared.
    static func callout(_ ctx: CGContext, size: CGSize, text: String, age: Double, tone: SIMD3<Double> = GameUIPalette.gold, life: Double = 1.3,
                        textSize: CGFloat = 46) {
        guard age >= 0, age < life, !text.isEmpty else { return }
        let grow = GameUIEase.outBack(age / 0.26, 2.2)
        let fade = min(GameUIEase.clamp(age / 0.1), GameUIEase.clamp((life - age) / 0.35))
        let c = calloutCenter(size)
        GameUIType.draw(ctx, text, at: CGPoint(x: c.x, y: c.y + CGFloat(1 - GameUIEase.outCubic(age / 0.3)) * 14), size: textSize, color: tone,
                        alpha: CGFloat(fade), scale: CGFloat(0.55 + 0.45 * grow), edge: 0.24)
    }

    /// A small coloured tag in the game's world, beside the thing it is about: "+5" on a handful of stars.
    static func tag(_ ctx: CGContext, _ text: String, at p: CGPoint, tone: SIMD3<Double>, alpha: Double = 1, textSize: CGFloat = 26) {
        guard alpha > 0.01 else { return }
        let textWidth = GameUIType.mixedWidth(text, size: textSize)
        let w = textWidth + textSize * 1.1, h = (textSize * 1.55 / 2).rounded() * 2
        ctx.saveGState()
        if alpha < 0.995 { ctx.setAlpha(CGFloat(alpha)) }
        GameUIPlate.draw(ctx, CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), radius: h / 2, fill: tone, opacity: 0.94)
        GameUIType.mixed(ctx, text, at: CGPoint(x: p.x - textWidth / 2, y: p.y), size: textSize)
        ctx.restoreGState()
    }

    /// A word on a small plate at the top middle that stays while it is true ("WATCH", "DUCK!", "3 OF 5"): a prompt, not news.
    static func prompt(_ ctx: CGContext, size: CGSize, text: String, tone: SIMD3<Double> = GameUIPalette.cream, alpha: Double = 1, scale: Double = 1,
                       textSize: CGFloat = 32) {
        guard alpha > 0.01, !text.isEmpty else { return }
        let textWidth = GameUIType.mixedWidth(text, size: textSize)
        let w = textWidth + textSize * 1.4
        let h = (textSize * 1.7 / 2).rounded() * 2
        let c = calloutCenter(size)
        ctx.saveGState()
        if alpha < 0.995 { ctx.setAlpha(CGFloat(alpha)) }
        if abs(scale - 1) > 0.004 {
            ctx.translateBy(x: c.x, y: c.y)
            ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            ctx.translateBy(x: -c.x, y: -c.y)
        }
        GameUIPlate.draw(ctx, CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), radius: h / 2, opacity: 0.8,
                         rim: tone == GameUIPalette.cream ? nil : tone)
        GameUIType.mixed(ctx, text, at: CGPoint(x: c.x - textWidth / 2, y: c.y), size: textSize, color: tone)
        ctx.restoreGState()
    }
}
