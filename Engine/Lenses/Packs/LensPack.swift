import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - What a lens pack says

/// Where on the face something is pinned. Positions are in eye-spacings from the middle of the eyes: x along the eyes,
/// y up the face, so a hat at y = 1.5 sits on top of the head at any distance and follows every tilt.
enum PackAnchor: String, CaseIterable {
    case eyes, leftEye, rightEye, nose, mouth, forehead, headTop, chin, cheekLeft, cheekRight, face
    /// The picture itself, not the face: x and y are fractions of the picture, from its middle.
    case screen
}

/// A reading from the face that can switch something on.
enum PackSignal: String, CaseIterable {
    case always, faceFound, mouthOpen, browRaise, blink, smile

    func value(in face: FaceState) -> Double {
        switch self {
        case .always, .faceFound: return 1
        case .mouthOpen: return face.mouthOpen
        case .browRaise: return face.browRaise
        case .blink: return face.blink
        case .smile: return face.smile
        }
    }
}

struct PackTrigger: Equatable {
    var signal = PackSignal.always
    /// On while the reading is above this (0...1), if set.
    var above: Double?
    /// On while the reading is below this, if set.
    var below: Double?
    /// Seconds to fade in or out.
    var fade = 0.12

    /// Whether this needs a face to be in view to mean anything.
    var needsFace: Bool { signal != .always }

    /// On or off for a reading, leaning toward `wasOn` near the edge so a reading that hovers there doesn't flicker.
    func isOn(_ reading: Double, wasOn: Bool) -> Bool {
        let margin = wasOn ? -0.08 : 0.0
        var on = true
        if let above { on = on && reading > above + margin }
        if let below { on = on && reading < below - margin }
        if above == nil, below == nil, signal != .always, signal != .faceFound { on = reading > (wasOn ? 0.35 : 0.5) }
        return on
    }
}

enum PackShape: String, CaseIterable { case circle, rect, roundRect, triangle, star, heart }

/// A picture in a lens folder. Checked cheaply when the lens is read (type, size, dimensions from the header) and only
/// decoded, scaled down, when the lens is put on, so a library full of lenses is quick to list.
final class PackImage {
    let url: URL
    let width: Int
    let height: Int
    private let lock = NSLock()
    private var decoded: CGImage?
    private var tried = false

    init(url: URL, width: Int, height: Int) {
        self.url = url
        self.width = width
        self.height = height
    }

    /// The picture, scaled to fit `LensPack.decodedEdge` pixels, or nil if it can't be decoded after all.
    var cgImage: CGImage? {
        lock.lock(); defer { lock.unlock() }
        if !tried {
            tried = true
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: LensPack.decodedEdge]
            decoded = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
        }
        return decoded
    }
}

enum PackContent {
    case image(PackImage)
    case emoji(String)
    case text(String)
    case shape(PackShape)
}

enum PackBlend: String, CaseIterable {
    case normal, add, multiply, screen
    var mode: CGBlendMode {
        switch self {
        case .normal: return .normal
        case .add: return .plusLighter
        case .multiply: return .multiply
        case .screen: return .screen
        }
    }
}

enum PackAnimationKind: String, CaseIterable { case bob, pulse, spin, wiggle, dropIn, float }

struct PackAnimation: Equatable {
    var kind: PackAnimationKind
    var speed = 1.0
    var amount = 0.15
}

struct PackLayer {
    var content: PackContent
    var color: CGColor
    var stroke: CGColor?
    /// In the same units as `size`; nil for a hairline in proportion to the shape.
    var strokeWidth: Double?
    var anchor: PackAnchor
    /// Eye-spacings (or picture fractions for `.screen`).
    var offset: SIMD2<Double>
    /// Height, in eye-spacings (or picture heights for `.screen`).
    var size: Double
    var width: Double
    /// Radians, on top of the head's tilt.
    var rotation: Double
    var followsHead: Bool
    var opacity: Double
    var blend: PackBlend
    var show: PackTrigger
    var animation: PackAnimation?
    /// Also draw a mirror image on the other side of the face.
    var mirror: Bool
    var weight: Double
}

struct PackWarp {
    enum Kind: String, CaseIterable { case bulge, pinch }
    var kind: Kind
    var anchor: PackAnchor
    var offset: SIMD2<Double>
    var radius: Double
    var strength: Double
    var show: PackTrigger
}

struct PackEmitter {
    enum Preset: String, CaseIterable { case rainbow, fire, hearts, sparkles, confetti, bubbles }
    var preset: Preset
    var anchor: PackAnchor
    var offset: SIMD2<Double>
    var show: PackTrigger
    var rate: Double
    var size: Double
}

/// A look for the whole picture.
struct PackLook: Equatable {
    var saturation = 1.0
    var contrast = 1.0
    var brightness = 0.0
    /// Degrees.
    var hue = 0.0
    var vignette = 0.0
    var tint: [Double]?
    var tintAmount = 0.25

    var isNeutral: Bool { self == PackLook() }
}

// MARK: - A pack on disk

enum LensPackError: LocalizedError {
    case noManifest(String)
    case unreadable(String)
    case tooNew(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .noManifest(let name): return "“\(name)” has no lens.json."
        case .unreadable(let why): return "lens.json couldn't be read: \(why)"
        case .tooNew(let version): return "This lens was made for a newer Backdrop (format \(version)); update Backdrop to use it."
        case .empty: return "This lens doesn't have any layers, warps, emitters or look, so it wouldn't do anything."
        }
    }
}

/// A lens made of plain files: a folder with a `lens.json` and any pictures it names. Nothing in it runs code.
struct LensPack {
    static let supportedFormat = 1
    static let maxLayers = 64
    static let maxEmitters = 6
    static let maxWarps = 6
    static let maxManifestBytes = 1_000_000
    static let maxImageBytes = 20_000_000
    /// A picture may be at most this many pixels along a side, and this many in all (a PNG has to be unpacked in full to be
    /// read, so the size on disk says little about the time it takes).
    static let maxImageEdge = 8192
    static let maxImagePixels = 40_000_000
    /// Across all the pictures in one lens.
    static let maxTotalPixels = 100_000_000
    static let maxImages = 16
    /// Pictures are drawn on a 1280 x 720 frame, so this is plenty.
    static let decodedEdge = 1024
    static let maxEmojiLength = 8

    var id: String
    var name: String
    var author: String?
    var glyph: String
    var summary: String
    var tags: [String]
    var layers: [PackLayer]
    var warps: [PackWarp]
    var emitters: [PackEmitter]
    var look: PackLook
    /// Things that were wrong but not fatal, in plain words, so whoever is writing the lens can fix them.
    var warnings: [String]
    var directory: URL
    var modified: Date

    /// Whether the lens needs a face in view.
    var needsFace: Bool {
        layers.contains { $0.anchor != .screen || $0.show.needsFace } || !warps.isEmpty || !emitters.isEmpty
    }

    static func load(from folder: URL) throws -> LensPack {
        let manifestURL = folder.appendingPathComponent("lens.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw LensPackError.noManifest(folder.lastPathComponent) }
        if let size = (try? FileManager.default.attributesOfItem(atPath: manifestURL.path)[.size] as? Int), size > maxManifestBytes {
            throw LensPackError.unreadable("lens.json is \(size / 1000) KB; the limit is \(maxManifestBytes / 1000) KB")
        }
        let data: Data
        do { data = try Data(contentsOf: manifestURL) } catch { throw LensPackError.unreadable(error.localizedDescription) }
        let raw: RawManifest
        do { raw = try JSONDecoder().decode(RawManifest.self, from: data) } catch { throw LensPackError.unreadable(Self.describe(error)) }
        guard raw.format >= 1 else { throw LensPackError.unreadable("format must be 1") }
        guard raw.format <= supportedFormat else { throw LensPackError.tooNew(raw.format) }

        var warnings: [String] = []
        let resolver = Resolver(folder: folder)
        var layers: [PackLayer] = []
        for (i, layer) in (raw.layers ?? []).prefix(maxLayers).enumerated() {
            if let resolved = resolver.layer(layer, label: "layer \(i + 1)", warnings: &warnings) { layers.append(resolved) }
        }
        if (raw.layers?.count ?? 0) > maxLayers { warnings.append("Only the first \(maxLayers) layers are used.") }
        if (raw.warps?.count ?? 0) > maxWarps { warnings.append("Only the first \(maxWarps) warps are used.") }
        if (raw.emitters?.count ?? 0) > maxEmitters { warnings.append("Only the first \(maxEmitters) emitters are used.") }
        let warps = (raw.warps ?? []).prefix(maxWarps).enumerated().compactMap { resolver.warp($1, label: "warp \($0 + 1)", warnings: &warnings) }
        let emitters = (raw.emitters ?? []).prefix(maxEmitters).enumerated().compactMap { resolver.emitter($1, label: "emitter \($0 + 1)", warnings: &warnings) }
        let look = resolver.look(raw.look, warnings: &warnings)

        guard !layers.isEmpty || !warps.isEmpty || !emitters.isEmpty || !look.isNeutral else { throw LensPackError.empty }

        // The newest change to anything in the folder, so editing a picture counts as much as editing lens.json.
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let modified = files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max() ?? .distantPast
        return LensPack(id: "pack." + folder.lastPathComponent, name: String(raw.name.prefix(60)), author: raw.author.map { String($0.prefix(60)) },
                        glyph: raw.glyph.flatMap { $0.isEmpty ? nil : String($0.prefix(2)) } ?? "✨",
                        summary: String((raw.description ?? "A lens from your Lenses folder.").prefix(300)),
                        tags: (raw.tags ?? []).prefix(16).map { String($0.prefix(40)) },
                        layers: layers, warps: warps, emitters: emitters, look: look, warnings: warnings, directory: folder, modified: modified)
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .keyNotFound(let key, _): return "“\(key.stringValue)” is missing"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            // The reason and the line and column are in the underlying error, not the top one.
            let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String ?? context.debugDescription
            return path.isEmpty ? detail : "\(path): \(detail)"
        @unknown default: return error.localizedDescription
        }
    }
}

// MARK: - Reading lens.json

private struct RawManifest: Decodable {
    var format: Int
    var name: String
    var author: String?
    var glyph: String?
    var description: String?
    var tags: [String]?
    var layers: [RawLayer]?
    var warps: [RawWarp]?
    var emitters: [RawEmitter]?
    var look: RawLook?
}

private struct RawTrigger: Decodable {
    var when: String?
    var above: Double?
    var below: Double?
    var fade: Double?
}

private struct RawAnimation: Decodable {
    var kind: String
    var speed: Double?
    var amount: Double?
}

private struct RawLayer: Decodable {
    var type: String
    var image: String?
    var emoji: String?
    var text: String?
    var shape: String?
    var color: String?
    var stroke: String?
    var strokeWidth: Double?
    var anchor: String?
    var offset: [Double]?
    var size: Double?
    var width: Double?
    var rotation: Double?
    var follow: String?
    var opacity: Double?
    var blend: String?
    var show: RawTrigger?
    var animate: RawAnimation?
    var mirror: Bool?
    var weight: Double?
}

private struct RawWarp: Decodable {
    var kind: String
    var anchor: String?
    var offset: [Double]?
    var radius: Double?
    var strength: Double?
    var show: RawTrigger?
}

private struct RawEmitter: Decodable {
    var preset: String
    var anchor: String?
    var offset: [Double]?
    var show: RawTrigger?
    var rate: Double?
    var size: Double?
}

private struct RawLook: Decodable {
    var saturation: Double?
    var contrast: Double?
    var brightness: Double?
    var hue: Double?
    var vignette: Double?
    var tint: String?
    var tintAmount: Double?
}

/// Turns what was written into what can be drawn, noting anything it had to drop.
private final class Resolver {
    let folder: URL
    private var images: [String: PackImage] = [:]
    private var totalPixels = 0

    init(folder: URL) { self.folder = folder }

    func layer(_ raw: RawLayer, label: String, warnings: inout [String]) -> PackLayer? {
        let content: PackContent
        switch raw.type {
        case "image":
            guard let name = raw.image, let image = imageRef(name, label: label, warnings: &warnings) else { return nil }
            content = .image(image)
        case "emoji":
            guard let emoji = raw.emoji, !emoji.isEmpty else { warnings.append("\(label): an emoji layer needs an \"emoji\"."); return nil }
            content = .emoji(String(emoji.prefix(LensPack.maxEmojiLength)))
        case "text":
            guard let text = raw.text, !text.isEmpty else { warnings.append("\(label): a text layer needs \"text\"."); return nil }
            content = .text(String(text.prefix(80)))
        case "shape":
            guard let name = raw.shape, let shape = PackShape(rawValue: name) else {
                warnings.append("\(label): shape must be one of \(PackShape.allCases.map(\.rawValue).joined(separator: ", ")).")
                return nil
            }
            content = .shape(shape)
        default:
            warnings.append("\(label): type must be image, emoji, text or shape, not “\(raw.type)”.")
            return nil
        }
        guard let anchor = self.anchor(raw.anchor, label: label, warnings: &warnings) else { return nil }
        let blend = raw.blend.map { PackBlend(rawValue: $0) } ?? .normal
        if blend == nil { warnings.append("\(label): blend must be one of \(PackBlend.allCases.map(\.rawValue).joined(separator: ", ")).") }
        let size = clamp(raw.size ?? 1, 0.01, 20)
        return PackLayer(content: content, color: color(raw.color, fallback: .white, label: label, warnings: &warnings),
                         stroke: raw.stroke.flatMap { color($0, fallback: .black, label: label, warnings: &warnings) },
                         strokeWidth: raw.strokeWidth.map { clamp($0, 0.001, 2) }, anchor: anchor, offset: offset(raw.offset), size: size, width: clamp(raw.width ?? size, 0.01, 20),
                         rotation: (raw.rotation ?? 0) * .pi / 180, followsHead: raw.follow != "none",
                         opacity: clamp(raw.opacity ?? 1, 0, 1), blend: blend ?? .normal, show: trigger(raw.show, label: label, warnings: &warnings),
                         animation: animation(raw.animate, label: label, warnings: &warnings), mirror: raw.mirror ?? false,
                         weight: clamp(raw.weight ?? 0.8, 0, 1))
    }

    func warp(_ raw: RawWarp, label: String, warnings: inout [String]) -> PackWarp? {
        guard let kind = PackWarp.Kind(rawValue: raw.kind) else {
            warnings.append("\(label): kind must be bulge or pinch, not “\(raw.kind)”.")
            return nil
        }
        guard let anchor = self.anchor(raw.anchor, label: label, warnings: &warnings) else { return nil }
        guard anchor != .screen else { warnings.append("\(label): a warp needs a face anchor."); return nil }
        return PackWarp(kind: kind, anchor: anchor, offset: offset(raw.offset), radius: clamp(raw.radius ?? 0.6, 0.05, 5),
                        strength: clamp(raw.strength ?? 0.6, 0, 1), show: trigger(raw.show, label: label, warnings: &warnings))
    }

    func emitter(_ raw: RawEmitter, label: String, warnings: inout [String]) -> PackEmitter? {
        guard let preset = PackEmitter.Preset(rawValue: raw.preset) else {
            warnings.append("\(label): preset must be one of \(PackEmitter.Preset.allCases.map(\.rawValue).joined(separator: ", ")).")
            return nil
        }
        guard let anchor = self.anchor(raw.anchor ?? "mouth", label: label, warnings: &warnings) else { return nil }
        guard anchor != .screen else { warnings.append("\(label): an emitter needs a face anchor."); return nil }
        return PackEmitter(preset: preset, anchor: anchor, offset: offset(raw.offset), show: trigger(raw.show, label: label, warnings: &warnings),
                           rate: clamp(raw.rate ?? 1, 0.1, 2), size: clamp(raw.size ?? 1, 0.2, 2))
    }

    func look(_ raw: RawLook?, warnings: inout [String]) -> PackLook {
        guard let raw else { return PackLook() }
        var look = PackLook()
        look.saturation = clamp(raw.saturation ?? 1, 0, 3)
        look.contrast = clamp(raw.contrast ?? 1, 0.25, 4)
        look.brightness = clamp(raw.brightness ?? 0, -1, 1)
        look.hue = clamp(raw.hue ?? 0, -360, 360)
        look.vignette = clamp(raw.vignette ?? 0, 0, 2)
        if let tint = raw.tint {
            if let parsed = Self.parseColor(tint) { look.tint = parsed } else { warnings.append("look: “\(tint)” isn't a colour like #FF8800.") }
        }
        look.tintAmount = clamp(raw.tintAmount ?? 0.25, 0, 1)
        return look
    }

    // MARK: Pieces

    private func anchor(_ name: String?, label: String, warnings: inout [String]) -> PackAnchor? {
        guard let name else { return .eyes }
        guard let anchor = PackAnchor(rawValue: name) else {
            warnings.append("\(label): anchor must be one of \(PackAnchor.allCases.map(\.rawValue).joined(separator: ", ")), not “\(name)”.")
            return nil
        }
        return anchor
    }

    private func trigger(_ raw: RawTrigger?, label: String, warnings: inout [String]) -> PackTrigger {
        guard let raw else { return PackTrigger() }
        var trigger = PackTrigger()
        if let when = raw.when {
            if let signal = PackSignal(rawValue: when) { trigger.signal = signal } else {
                warnings.append("\(label): show.when must be one of \(PackSignal.allCases.map(\.rawValue).joined(separator: ", ")), not “\(when)”.")
            }
        }
        trigger.above = raw.above.map { clamp($0, 0, 1) }
        trigger.below = raw.below.map { clamp($0, 0, 1) }
        trigger.fade = clamp(raw.fade ?? 0.12, 0.01, 3)
        return trigger
    }

    private func animation(_ raw: RawAnimation?, label: String, warnings: inout [String]) -> PackAnimation? {
        guard let raw else { return nil }
        guard let kind = PackAnimationKind(rawValue: raw.kind) else {
            warnings.append("\(label): animate.kind must be one of \(PackAnimationKind.allCases.map(\.rawValue).joined(separator: ", ")), not “\(raw.kind)”.")
            return nil
        }
        return PackAnimation(kind: kind, speed: clamp(raw.speed ?? 1, 0.05, 10), amount: clamp(raw.amount ?? 0.15, 0, 2))
    }

    private func offset(_ raw: [Double]?) -> SIMD2<Double> {
        guard let raw, raw.count >= 2 else { return .zero }
        return SIMD2(clamp(raw[0], -20, 20), clamp(raw[1], -20, 20))
    }

    private func color(_ text: String?, fallback: CGColor, label: String, warnings: inout [String]) -> CGColor {
        guard let text else { return fallback }
        guard let c = Self.parseColor(text) else {
            warnings.append("\(label): “\(text)” isn't a colour like #FF8800 or #FF880080.")
            return fallback
        }
        return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [c[0], c[1], c[2], c[3]])!
    }

    /// `#RGB`, `#RRGGBB` or `#RRGGBBAA` as red, green, blue, alpha in 0...1.
    static func parseColor(_ text: String) -> [Double]? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return [r, g, b, a]
    }

    /// Looks a picture up by name, once however many layers use it, and checks it is safe to load later: a plain file that really is
    /// inside the lens folder (a link to somewhere else is refused), of a kind Backdrop reads, and not enormous.
    private func imageRef(_ name: String, label: String, warnings: inout [String]) -> PackImage? {
        if let known = images[name] { return known }
        guard images.count < LensPack.maxImages else {
            warnings.append("\(label): a lens can use \(LensPack.maxImages) different pictures; “\(name)” is skipped.")
            return nil
        }
        let base = folder.resolvingSymlinksInPath().standardizedFileURL
        let candidate = folder.appendingPathComponent(name)
        // The file itself must not be a link, and wherever it really lives must be inside the folder (which also catches a
        // linked sub-folder that leads somewhere else, and ../).
        let isLink = (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        let real = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard !isLink, real.path.hasPrefix(base.path + "/") else {
            warnings.append("\(label): “\(name)” isn't inside the lens's folder (links aren't followed).")
            return nil
        }
        guard let values = try? real.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true, let size = values.fileSize else {
            warnings.append("\(label): the picture “\(name)” isn't in the lens's folder.")
            return nil
        }
        guard size <= LensPack.maxImageBytes else {
            warnings.append("\(label): “\(name)” is over \(LensPack.maxImageBytes / 1_000_000) MB.")
            return nil
        }
        // What kind of picture, and how big, from the header alone.
        guard let source = CGImageSourceCreateWithURL(real as CFURL, nil), let type = CGImageSourceGetType(source).flatMap({ UTType($0 as String) }),
              [UTType.png, .jpeg, .heic, .webP].contains(where: { type.conforms(to: $0) }),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            warnings.append("\(label): “\(name)” isn't a PNG, JPEG, HEIC or WebP picture Backdrop can open.")
            return nil
        }
        guard width > 0, height > 0, width <= LensPack.maxImageEdge, height <= LensPack.maxImageEdge, width * height <= LensPack.maxImagePixels else {
            warnings.append("\(label): “\(name)” is \(width) × \(height); pictures can be at most \(LensPack.maxImageEdge) pixels along a side and \(LensPack.maxImagePixels / 1_000_000) million in all.")
            return nil
        }
        guard totalPixels + width * height <= LensPack.maxTotalPixels else {
            warnings.append("\(label): the pictures in this lens are too big altogether; “\(name)” is skipped.")
            return nil
        }
        totalPixels += width * height
        let image = PackImage(url: real, width: width, height: height)
        images[name] = image
        return image
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v.isFinite ? v : lo)) }
}
