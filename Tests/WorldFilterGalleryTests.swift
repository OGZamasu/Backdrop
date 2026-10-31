import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Pictures of every weather, light and particle filter in the states a real call goes through: standing still, moving about,
/// far away and tilted, right up close, nobody there, and no backdrop. One sheet per filter and one contact sheet of them all.
///
/// Only runs when BACKDROP_TEST_OUTPUT is set, since it makes pictures for people to look at rather than checking anything.
/// WORLD_ONLY=id,id narrows it to some filters.
final class WorldFilterGalleryTests: XCTestCase {
    private let h = LensHarness()
    private let size = SyntheticScene.size

    /// Everything in the world area: the catalog's world filters plus the older aura, trails and snow.
    static var items: [LensInfo] {
        ["aura", "aura-rainbow", "ghost-trails", "snow"].compactMap { LensCatalog.info(for: $0) } + WorldFilters.all
    }

    private enum State: String, CaseIterable {
        case idle, moving, farTilted = "far-tilted", near, nobody, noBackdrop = "no-backdrop"
    }

    private var folder: URL? {
        ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"].map { URL(fileURLWithPath: $0) }
    }

    /// The frame a state starts from; nil for a state where the person moves, which is made afresh every frame.
    private func still(_ state: State) -> LensInput? {
        switch state {
        case .idle: return h.input(SyntheticScene())
        case .moving: return nil
        case .farTilted: return h.input(SyntheticScene(center: CGPoint(x: 840, y: 330), scale: 0.6, roll: 0.3))
        case .near: return h.input(SyntheticScene(center: CGPoint(x: 600, y: 300), scale: 1.5))
        case .nobody:
            let base = h.input(SyntheticScene())
            let rect = base.rect
            let backdrop = SyntheticScene.backdrop()
            return LensInput(time: 0, dt: 1.0 / 30, rect: rect, camera: base.camera, matte: CIImage(color: .black).cropped(to: rect),
                             background: backdrop, composed: backdrop, matteGrid: MatteGrid(outputSize: size), face: nil, services: base.services)
        case .noBackdrop: return h.input(SyntheticScene(), background: false)
        }
    }

    /// Steps sideways across the room, swaying, and is still moving at the last frame.
    private func moving(_ i: Int, frames: Int) -> LensInput {
        let t = Double(i) / 30
        let k = min(1, Double(i) / Double(max(1, frames)))
        let eased = k * k * (3 - 2 * k) * 0.8 + k * 0.2
        let scene = SyntheticScene(center: CGPoint(x: 420 + 440 * eased, y: 410 + 14 * sin(t * 5)), roll: 0.12 * sin(t * 3))
        return h.at(h.input(scene), time: t)
    }

    func testGallery() throws {
        guard let folder else { throw XCTSkip("set TEST_RUNNER_BACKDROP_TEST_OUTPUT to make the gallery") }
        let only = ProcessInfo.processInfo.environment["WORLD_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let frames = Int(ProcessInfo.processInfo.environment["WORLD_FRAMES"] ?? "") ?? 90
        var heroes: [(String, CGImage)] = []
        for info in Self.items where only?.contains(info.id) ?? true {
            var shots: [(String, CGImage)] = []
            for state in State.allCases {
                let lens = info.make()
                let base = still(state)
                var last: CIImage?
                for i in 0..<frames { last = lens.render(base.map { h.at($0, time: Double(i) / 30) } ?? moving(i, frames: frames)) }
                guard let out = last, let image = h.ciContext.createCGImage(out, from: h.compositor.rect, format: .RGBA8, colorSpace: TestSupport.srgb) else { continue }
                shots.append((state.rawValue, image))
                if state == .idle {
                    heroes.append((info.name, image))
                    write(image, to: folder.appendingPathComponent("world-\(info.id).png"))
                }
            }
            if let sheet = Self.sheet(shots, columns: 3, cell: CGSize(width: 640, height: 360)) {
                write(sheet, to: folder.appendingPathComponent("world-sheet-\(info.id).png"))
            }
        }
        if only == nil, let contact = Self.sheet(heroes, columns: 5, cell: CGSize(width: 384, height: 216)) {
            write(contact, to: folder.appendingPathComponent("world-contact.png"))
        }
    }

    /// Lays pictures out in a grid with their names underneath.
    static func sheet(_ shots: [(String, CGImage)], columns: Int, cell: CGSize) -> CGImage? {
        guard !shots.isEmpty else { return nil }
        let rows = (shots.count + columns - 1) / columns
        let label: CGFloat = 26
        let width = Int(cell.width) * columns, height = Int(cell.height + label) * rows
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: TestSupport.srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        for (n, shot) in shots.enumerated() {
            let col = n % columns, row = n / columns
            let x = CGFloat(col) * cell.width, y = CGFloat(height) - CGFloat(row + 1) * (cell.height + label)
            ctx.draw(shot.1, in: CGRect(x: x, y: y + label, width: cell.width, height: cell.height))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSAttributedString(string: shot.0, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white])
                .draw(at: NSPoint(x: x + 8, y: y + 5))
            NSGraphicsContext.restoreGraphicsState()
        }
        return ctx.makeImage()
    }

    private func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
