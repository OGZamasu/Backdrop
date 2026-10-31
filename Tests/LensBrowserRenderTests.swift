import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Saves a CGImage as a PNG when BACKDROP_TEST_OUTPUT is set.
enum LensBrowserOutput {
    static var folder: URL? {
        ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"].map { URL(fileURLWithPath: $0) }
    }

    static func save(_ image: CGImage?, as name: String) {
        guard let image, let folder else { return }
        let url = folder.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

final class LensBrowserRenderTests: XCTestCase {
    func testTheMannequinLooksLikeAPersonAndReportsWhereItsFaceIs() throws {
        let renderer = LensBrowserRenderer()
        for (name, pose) in [("calm", LensBrowserDirections.calm(0)),
                             ("open", LensBrowserPose(mouthOpen: 0.85, browRaise: 1, smile: 0.8)),
                             ("blink", LensBrowserPose(mouthOpen: 0.3, smile: 1, blink: 1)),
                             ("lean", LensBrowserPose(offset: CGVector(dx: 120, dy: 0), lean: 0.2, smile: 0.4))] {
            LensBrowserOutput.save(renderer.picture(renderer.plain(pose), size: LensBrowserMannequin.size), as: "browser/mannequin-\(name).png")
        }
        var pose = LensBrowserDirections.calm(0)
        pose.hands = [LensBrowserHand(fingers: .open, wrist: CGPoint(x: 335, y: 250), size: 92),
                      LensBrowserHand(fingers: .peace, wrist: CGPoint(x: 945, y: 250), size: 92, mirrored: true)]
        LensBrowserOutput.save(renderer.picture(renderer.plain(pose), size: LensBrowserMannequin.size), as: "browser/mannequin-hands.png")
        LensBrowserOutput.save(renderer.picture(renderer.mannequin.room, size: LensBrowserMannequin.size), as: "browser/room.png")
    }
}

final class LensBrowserThumbnailSheetTests: XCTestCase {
    /// Renders every lens's thumbnail, saved one file per lens for the contact sheet. Only when BACKDROP_TEST_OUTPUT is set.
    func testRenderEveryThumbnailForLooking() throws {
        guard LensBrowserOutput.folder != nil else { throw XCTSkip("only for looking at") }
        let renderer = LensBrowserRenderer()
        let only = ProcessInfo.processInfo.environment["LENS_BROWSER_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        var times: [(String, Double)] = []
        for info in LensCatalog.all where only?.contains(info.id) ?? true {
            let started = CFAbsoluteTimeGetCurrent()
            let image = renderer.thumbnail(for: info)
            times.append((info.id, CFAbsoluteTimeGetCurrent() - started))
            LensBrowserOutput.save(image, as: "browser/thumbs/\(info.category.rawValue)-\(info.id).png")
        }
        let total = times.reduce(0) { $0 + $1.1 }
        print("LENSBROWSER total \(String(format: "%.1f", total)) s for \(times.count); slowest:",
              times.sorted { $0.1 > $1.1 }.prefix(8).map { "\($0.0) \(String(format: "%.2f", $0.1))" }.joined(separator: ", "))
    }
}

final class LensBrowserPackSheetTests: XCTestCase {
    /// The sample lenses' thumbnails, for looking at. Only when BACKDROP_TEST_OUTPUT is set.
    func testRenderEverySamplePackForLooking() throws {
        guard LensBrowserOutput.folder != nil else { throw XCTSkip("only for looking at") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lens-browser-packs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try SampleLenses.install(into: folder)
        let renderer = LensBrowserRenderer()
        for pack in LensPackFolder.scan(folder).packs {
            let info = LensPackFolder.info(for: pack)
            LensBrowserOutput.save(renderer.thumbnail(for: info), as: "browser/packs/\(pack.name).png")
        }
    }
}
