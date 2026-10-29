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
            case .blur:
                LinearGradient(colors: [.gray.opacity(0.5), .gray.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "circle.lefthalf.filled").font(.title2).foregroundStyle(.white.opacity(0.85))
            case .gradient(let preset):
                let c = preset.colors
                LinearGradient(colors: [rgb(c[0]), rgb(c[1]), rgb(c[2])], startPoint: .bottomLeading, endPoint: .topTrailing)
            case .pipes:
                PipesThumbnail()
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

    private func rgb(_ c: [Double]) -> Color { Color(red: c[0], green: c[1], blue: c[2]) }

    private func appIcon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
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
