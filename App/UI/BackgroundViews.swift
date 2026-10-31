import AVFoundation
import AppKit
import ImageIO
import SwiftUI

// MARK: - Thumbnails

@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()
    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL, isVideo: Bool) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let image = await Self.render(url, isVideo: isVideo)
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    private nonisolated static func render(_ url: URL, isVideo: Bool) async -> NSImage? {
        let cgImage: CGImage?
        if isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            cgImage = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        } else {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
            ]
            cgImage = CGImageSourceCreateWithURL(url as CFURL, nil)
                .flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
        }
        return cgImage.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }
}

struct BackgroundThumbnail: View {
    @EnvironmentObject private var model: AppModel
    let background: Background
    @State private var loaded: NSImage?

    var body: some View {
        ZStack {
            switch background.kind {
            case .passthrough:
                Color(white: 0.16)
                Image(systemName: "video").font(.title2).foregroundStyle(.secondary)
            case .blur, .gradient, .solid, .treated, .procedural:
                BuiltInThumbnail(background: background)
            case .pipes:
                PipesThumbnail()
            case .maze:
                MazeThumbnail()
            case .image, .video:
                if let loaded {
                    Image(nsImage: loaded).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(white: 0.2)
                }
            case .window(let bundleID, _):
                Color(white: 0.16)
                if let icon = appIcon(bundleID) { Image(nsImage: icon).resizable().frame(width: 30, height: 30) }
            case .display:
                Color(white: 0.16)
                Image(systemName: "display").font(.title2).foregroundStyle(.secondary)
            }
        }
        .task(id: background.id) {
            guard let url = model.library.fileURL(for: background) else { return }
            let isVideo: Bool = { if case .video = background.kind { return true } else { return false } }()
            loaded = await ThumbnailStore.shared.image(for: url, isVideo: isVideo)
        }
    }

    private func appIcon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// Pictures of the built-in backdrops, made once by running the real source (on a made-up room, for the camera looks)
/// and kept for the session.
@MainActor
final class BackdropSceneThumbnails {
    static let shared = BackdropSceneThumbnails()
    private var cache: [BackgroundKind: NSImage] = [:]

    func image(for background: Background) async -> NSImage? {
        if let cached = cache[background.kind] { return cached }
        let image = await Self.render(background)
        if let image { cache[background.kind] = image }
        return image
    }

    private nonisolated static func render(_ background: Background) async -> NSImage? {
        BackdropThumbnail.render(background).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }
}

/// A built-in's real picture, with a quiet stand-in in its own colours while it is made.
private struct BuiltInThumbnail: View {
    let background: Background
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            placeholder
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: background.kind) { image = await BackdropSceneThumbnails.shared.image(for: background) }
    }

    @ViewBuilder private var placeholder: some View {
        switch background.kind {
        case .gradient(let preset):
            let c = preset.colors
            LinearGradient(colors: [rgb(c[0]), rgb(c[1]), rgb(c[2])], startPoint: .bottomLeading, endPoint: .topTrailing)
        case .solid(let hex, _):
            let c = BackdropPaint.rgb(hex: hex) ?? (r: 0.5, g: 0.5, b: 0.5)
            Color(red: c.r, green: c.g, blue: c.b)
        default:
            Color(white: 0.12)
        }
    }

    private func rgb(_ c: [Double]) -> Color { Color(red: c[0], green: c[1], blue: c[2]) }
}

/// A few shiny pipes and ball joints on black, drawn rather than rendered, so the grid stays cheap.
private struct PipesThumbnail: View {
    private let routes: [(color: Color, points: [CGPoint])] = [
        (.red, [CGPoint(x: 0.08, y: 0.78), CGPoint(x: 0.42, y: 0.78), CGPoint(x: 0.42, y: 0.34), CGPoint(x: 0.80, y: 0.34)]),
        (.cyan, [CGPoint(x: 0.22, y: 0.12), CGPoint(x: 0.22, y: 0.52), CGPoint(x: 0.62, y: 0.52), CGPoint(x: 0.62, y: 0.92)]),
        (.yellow, [CGPoint(x: 0.92, y: 0.16), CGPoint(x: 0.70, y: 0.16), CGPoint(x: 0.70, y: 0.68)]),
    ]

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            let line = h * 0.11
            ZStack {
                Color.black
                ForEach(routes.indices, id: \.self) { i in
                    let route = routes[i]
                    Path { path in
                        path.move(to: CGPoint(x: route.points[0].x * w, y: route.points[0].y * h))
                        for p in route.points.dropFirst() { path.addLine(to: CGPoint(x: p.x * w, y: p.y * h)) }
                    }
                    .stroke(route.color.gradient, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                    ForEach(1..<(route.points.count - 1), id: \.self) { j in
                        Circle()
                            .fill(RadialGradient(colors: [.white.opacity(0.9), route.color], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: line))
                            .frame(width: line * 1.5, height: line * 1.5)
                            .position(x: route.points[j].x * w, y: route.points[j].y * h)
                    }
                }
            }
        }
    }
}

/// A brick corridor running off to a vanishing point, drawn rather than rendered so the grid stays cheap.
private struct MazeThumbnail: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            // The far end of the corridor, centred a little above the middle.
            let far = CGRect(x: w * 0.38, y: h * 0.34, width: w * 0.24, height: h * 0.30)
            let brick = Color(red: 0.55, green: 0.19, blue: 0.14)
            ZStack {
                Color.black
                // Ceiling, floor, then the two side walls.
                Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: far.maxX, y: far.minY)); p.addLine(to: CGPoint(x: far.minX, y: far.minY)); p.closeSubpath() }
                    .fill(Color(white: 0.20))
                Path { p in p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: far.maxX, y: far.maxY)); p.addLine(to: CGPoint(x: far.minX, y: far.maxY)); p.closeSubpath() }
                    .fill(Color(white: 0.42))
                Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: far.minX, y: far.minY)); p.addLine(to: CGPoint(x: far.minX, y: far.maxY)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath() }
                    .fill(brick)
                Path { p in p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: far.maxX, y: far.minY)); p.addLine(to: CGPoint(x: far.maxX, y: far.maxY)); p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath() }
                    .fill(brick.opacity(0.85))
                Rectangle().fill(brick.opacity(0.55)).frame(width: far.width, height: far.height).position(x: far.midX, y: far.midY)
                // Mortar lines, converging with the walls.
                Path { p in
                    for t in stride(from: 0.2, through: 0.8, by: 0.2) {
                        let y0 = h * t, y1 = far.minY + far.height * t
                        p.move(to: CGPoint(x: 0, y: y0)); p.addLine(to: CGPoint(x: far.minX, y: y1))
                        p.move(to: CGPoint(x: w, y: y0)); p.addLine(to: CGPoint(x: far.maxX, y: y1))
                    }
                }
                .stroke(Color.black.opacity(0.45), lineWidth: 0.8)
                // Torchlight fading into the dark ahead.
                RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: h * 0.2, endRadius: w * 0.75)
            }
        }
    }
}

// MARK: - Tile and grid

struct BackgroundTile: View {
    @EnvironmentObject private var model: AppModel
    let background: Background
    var showsName = true

    private var isSelected: Bool { model.selectedID == background.id }

    var body: some View {
        VStack(spacing: 4) {
            BackgroundThumbnail(background: background)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottomTrailing) { badge }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                )
                .contentShape(Rectangle())
                .onTapGesture { model.select(background.id) }
            if showsName {
                Text(background.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(background.name)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder private var badge: some View {
        let symbol: String? = {
            switch background.kind {
            case .video: return "play.fill"
            case .window, .display: return "dot.radiowaves.left.and.right"
            case .gradient: return "sparkle"
            case .procedural(let style): return style.isAnimated ? "sparkle" : nil
            default: return background.origin == .generated ? "wand.and.stars" : nil
            }
        }()
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.45), in: Circle())
                .padding(4)
        }
    }
}

/// The grid in the menu bar popover.
///
/// A popover sizes itself from its content's *ideal* height, and a ScrollView's ideal height is close to zero,
/// so a scroll view with only a maximum height collapses to a single row. The height is therefore set explicitly:
/// every row if they fit, otherwise `maxVisibleRows` with scrolling.
struct BackgroundPicker: View {
    @EnvironmentObject private var model: AppModel
    /// Width available to the grid, which fixes the tile size.
    let contentWidth: CGFloat
    var columns = 4
    var maxVisibleRows = 3

    private let spacing: CGFloat = 8
    private let captionHeight: CGFloat = 14

    private var tileWidth: CGFloat { (contentWidth - 4 - spacing * CGFloat(columns - 1)) / CGFloat(columns) }
    private var rowHeight: CGFloat { tileWidth * 9 / 16 + 4 + captionHeight + spacing }
    private var rows: Int { max(1, (model.library.items.count + columns - 1) / columns) }

    var body: some View {
        let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: spacing), count: columns), spacing: spacing) {
            ForEach(model.library.items) { BackgroundTile(background: $0).help($0.name) }
        }
        .padding(2)

        if rows <= maxVisibleRows {
            grid
        } else {
            ScrollView { grid }.frame(height: rowHeight * CGFloat(maxVisibleRows))
        }
    }
}
