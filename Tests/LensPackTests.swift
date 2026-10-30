import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// A scratch folder that is deleted when the test ends.
private final class Scratch {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-lens-tests-\(UUID().uuidString)", isDirectory: true)
    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }

    /// A lens folder with this lens.json.
    @discardableResult
    func lens(_ name: String, json: String) -> URL {
        let folder = url.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? json.write(to: folder.appendingPathComponent("lens.json"), atomically: true, encoding: .utf8)
        return folder
    }

    /// A plain colour square saved as a PNG.
    func png(_ name: String, in folder: URL, red: Double, green: Double, blue: Double, side: Int = 64, width: Int? = nil, height: Int? = nil) {
        let w = width ?? side, h = height ?? side
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
    }
}

final class LensPackLoadingTests: XCTestCase {
    private let scratch = Scratch()

    func testEverySampleLensLoadsCleanly() throws {
        try SampleLenses.install(into: scratch.url)
        let (packs, problems) = LensPackFolder.scan(scratch.url)
        XCTAssertEqual(problems, [], "samples must load")
        XCTAssertEqual(packs.count, SampleLenses.all.count)
        for pack in packs {
            XCTAssertEqual(pack.warnings, [], "\(pack.name) has warnings")
            XCTAssertFalse(pack.summary.isEmpty)
        }
        let byName = Dictionary(uniqueKeysWithValues: packs.map { ($0.name, $0) })
        XCTAssertFalse(try XCTUnwrap(byName["Golden Hour"]).needsFace, "a look needs no face")
        XCTAssertFalse(try XCTUnwrap(byName["Name Tag"]).needsFace, "screen-pinned text needs no face")
        XCTAssertTrue(try XCTUnwrap(byName["Heart Eyes"]).needsFace)
        XCTAssertTrue(try XCTUnwrap(byName["Bubble Talk"]).needsFace)
        XCTAssertEqual(try XCTUnwrap(byName["Halo and Horns"]).layers.count, 2)
        XCTAssertEqual(try XCTUnwrap(byName["Halo and Horns"]).layers[1].show.signal, .browRaise)
    }

    func testInstallingSamplesLeavesEditedOnesAlone() throws {
        try SampleLenses.install(into: scratch.url)
        let edited = scratch.url.appendingPathComponent("Golden Hour.backdroplens/lens.json")
        try "{ \"format\": 1, \"name\": \"Mine now\", \"look\": { \"saturation\": 2 } }".write(to: edited, atomically: true, encoding: .utf8)
        try SampleLenses.install(into: scratch.url)
        XCTAssertTrue(try String(contentsOf: edited, encoding: .utf8).contains("Mine now"))
    }

    // MARK: Things that are wrong

    func testMissingAndBrokenFilesGiveClearErrors() {
        XCTAssertThrowsError(try LensPack.load(from: scratch.url.appendingPathComponent("nope"))) {
            XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains("no lens.json") == true)
        }
        let bad = scratch.lens("bad", json: "{ not json")
        XCTAssertThrowsError(try LensPack.load(from: bad)) { XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains("couldn't be read") == true) }
        let noName = scratch.lens("noname", json: "{ \"format\": 1 }")
        XCTAssertThrowsError(try LensPack.load(from: noName)) { XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains("name") == true, "\($0)") }
    }

    func testALensMadeForANewerBackdropSaysSo() {
        let folder = scratch.lens("future", json: "{ \"format\": 99, \"name\": \"Future\", \"look\": {} }")
        XCTAssertThrowsError(try LensPack.load(from: folder)) {
            XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains("newer Backdrop") == true)
        }
    }

    func testALensThatDoesNothingIsRefused() {
        let folder = scratch.lens("empty", json: "{ \"format\": 1, \"name\": \"Empty\" }")
        XCTAssertThrowsError(try LensPack.load(from: folder)) { XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains("wouldn't do anything") == true) }
    }

    func testBadPartsAreDroppedWithAWarningAndTheRestStillWorks() throws {
        let folder = scratch.lens("mixed", json: """
        { "format": 1, "name": "Mixed", "layers": [
            { "type": "emoji", "emoji": "🎩", "anchor": "headTop" },
            { "type": "emoji", "emoji": "🎩", "anchor": "elbow" },
            { "type": "sticker" },
            { "type": "image", "image": "missing.png" },
            { "type": "image", "image": "../outside.png" },
            { "type": "shape", "shape": "hexagon" },
            { "type": "emoji", "emoji": "🎩", "color": "banana", "show": { "when": "wink" }, "animate": { "kind": "explode" }, "blend": "glow" }
          ],
          "warps": [ { "kind": "twist" }, { "kind": "bulge", "anchor": "screen" } ],
          "emitters": [ { "preset": "lava" } ] }
        """)
        let pack = try LensPack.load(from: folder)
        XCTAssertEqual(pack.layers.count, 2, "the hat, and the last one with its bad details defaulted")
        XCTAssertEqual(pack.warps.count, 0)
        XCTAssertEqual(pack.emitters.count, 0)
        let text = pack.warnings.joined(separator: "\n")
        for expected in ["anchor must be one of", "type must be image, emoji, text or shape", "isn't in the lens's folder", "isn't inside the lens's folder",
                         "shape must be one of", "isn't a colour", "show.when must be one of", "animate.kind must be one of", "blend must be one of",
                         "kind must be bulge or pinch", "a warp needs a face anchor", "preset must be one of"] {
            XCTAssertTrue(text.contains(expected), "expected a warning containing “\(expected)” in:\n\(text)")
        }
    }

    func testNumbersAreKeptWithinSaneLimits() throws {
        let folder = scratch.lens("big", json: """
        { "format": 1, "name": "Big", "layers": [ { "type": "emoji", "emoji": "🎩", "size": 9999, "opacity": 7, "offset": [500, -500],
          "show": { "above": 4, "fade": 0 } } ],
          "look": { "saturation": 99, "vignette": 50 } }
        """)
        let pack = try LensPack.load(from: folder)
        let layer = try XCTUnwrap(pack.layers.first)
        XCTAssertLessThanOrEqual(layer.size, 20)
        XCTAssertEqual(layer.opacity, 1)
        XCTAssertLessThanOrEqual(abs(layer.offset.x), 20)
        XCTAssertEqual(layer.show.above, 1)
        XCTAssertGreaterThan(layer.show.fade, 0)
        XCTAssertLessThanOrEqual(pack.look.saturation, 3)
        XCTAssertLessThanOrEqual(pack.look.vignette, 2)
    }

    func testPicturesLoadFromTheLensFolderOnly() throws {
        let folder = scratch.lens("pics", json: """
        { "format": 1, "name": "Pics", "layers": [ { "type": "image", "image": "red.png", "anchor": "forehead" },
                                                    { "type": "image", "image": "notes.txt" } ] }
        """)
        scratch.png("red.png", in: folder, red: 1, green: 0, blue: 0)
        try "just words".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let pack = try LensPack.load(from: folder)
        XCTAssertEqual(pack.layers.count, 1)
        XCTAssertTrue(pack.warnings.joined().contains("picture Backdrop can open"))
    }

    func testColoursParse() {
        let hat = scratch.lens("colours", json: """
        { "format": 1, "name": "Colours", "layers": [
          { "type": "shape", "shape": "circle", "color": "#F80" },
          { "type": "shape", "shape": "circle", "color": "#336699" },
          { "type": "shape", "shape": "circle", "color": "#33669980" } ] }
        """)
        let pack = try? LensPack.load(from: hat)
        XCTAssertEqual(pack?.layers.count, 3)
        XCTAssertEqual(pack?.warnings, [])
        let alpha = pack?.layers.last?.color.alpha ?? 0
        XCTAssertEqual(Double(alpha), 0.5, accuracy: 0.01)
    }

    // MARK: Folders

    func testScanningListsGoodLensesAndExplainsTheBadOnes() throws {
        scratch.lens("B good", json: "{ \"format\": 1, \"name\": \"B\", \"look\": { \"saturation\": 2 } }")
        scratch.lens("A good", json: "{ \"format\": 1, \"name\": \"A\", \"look\": { \"saturation\": 2 } }")
        scratch.lens("broken", json: "{ oops")
        try FileManager.default.createDirectory(at: scratch.url.appendingPathComponent("no manifest"), withIntermediateDirectories: true)
        try "hello".write(to: scratch.url.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: scratch.url.appendingPathComponent(".hidden"), withIntermediateDirectories: true)

        let (packs, problems) = LensPackFolder.scan(scratch.url)
        XCTAssertEqual(packs.map(\.name), ["A", "B"], "in name order")
        XCTAssertEqual(Set(problems.map(\.id)), ["broken", "no manifest"], "files and hidden folders are ignored")
        XCTAssertEqual(packs.first?.id, "pack.A good")
        XCTAssertTrue(LensPackFolder.scan(scratch.url.appendingPathComponent("not here")).packs.isEmpty, "no folder is just no lenses")
    }

    func testAddingALensCopiesItAndNeverOverwrites() throws {
        let source = Scratch()
        let lens = source.lens("Cool.backdroplens", json: "{ \"format\": 1, \"name\": \"Cool\", \"look\": { \"saturation\": 2 } }")
        let library = scratch.url.appendingPathComponent("Lenses")
        let first = try LensPackFolder.add(lens, to: library)
        let second = try LensPackFolder.add(lens, to: library)
        XCTAssertEqual(first.lastPathComponent, "Cool.backdroplens")
        XCTAssertEqual(second.lastPathComponent, "Cool 2.backdroplens")
        XCTAssertEqual(LensPackFolder.scan(library).packs.count, 2)

        let notALens = source.url.appendingPathComponent("random")
        try FileManager.default.createDirectory(at: notALens, withIntermediateDirectories: true)
        XCTAssertThrowsError(try LensPackFolder.add(notALens, to: library))
        XCTAssertEqual(LensPackFolder.scan(library).packs.count, 2, "nothing was copied")
    }

    func testPackInfoMatchesWhatTheLensNeeds() throws {
        try SampleLenses.install(into: scratch.url)
        for pack in LensPackFolder.scan(scratch.url).packs {
            let info = LensPackFolder.info(for: pack)
            XCTAssertEqual(info.category, .custom)
            XCTAssertEqual(info.needsFace, info.make().needs.contains(.face), pack.name)
            XCTAssertEqual(info.id, pack.id)
        }
    }
}

final class PackTriggerTests: XCTestCase {
    func testAboveAndBelowAndALittleStickiness() {
        let open = PackTrigger(signal: .mouthOpen, above: 0.5, below: nil, fade: 0.1)
        XCTAssertFalse(open.isOn(0.45, wasOn: false))
        XCTAssertTrue(open.isOn(0.55, wasOn: false))
        XCTAssertTrue(open.isOn(0.45, wasOn: true), "once on, a little under the line stays on")
        XCTAssertFalse(open.isOn(0.3, wasOn: true))

        let calm = PackTrigger(signal: .browRaise, above: nil, below: 0.3, fade: 0.1)
        XCTAssertTrue(calm.isOn(0.1, wasOn: false))
        XCTAssertFalse(calm.isOn(0.5, wasOn: false))

        let band = PackTrigger(signal: .smile, above: 0.2, below: 0.8, fade: 0.1)
        XCTAssertTrue(band.isOn(0.5, wasOn: false))
        XCTAssertFalse(band.isOn(0.9, wasOn: false))
    }

    func testASignalWithNoThresholdsUsesAHalf() {
        let blink = PackTrigger(signal: .blink)
        XCTAssertFalse(blink.isOn(0.4, wasOn: false))
        XCTAssertTrue(blink.isOn(0.6, wasOn: false))
        XCTAssertTrue(blink.isOn(0.4, wasOn: true))
        XCTAssertTrue(PackTrigger(signal: .always).isOn(0, wasOn: false))
    }

    func testFaceFrameRoundTripsAndFollowsTilt() {
        for roll in [0.0, 0.5, -0.8] {
            var scene = SyntheticScene(center: CGPoint(x: 500, y: 300)); scene.roll = roll
            let frame = FaceFrame(scene.face())
            for p in [SIMD2(0.0, 0.0), SIMD2(1.2, -0.7), SIMD2(-0.5, 1.55)] {
                let back = frame.local(frame.pixel(p))
                XCTAssertEqual(back.x, p.x, accuracy: 1e-6); XCTAssertEqual(back.y, p.y, accuracy: 1e-6)
            }
            XCTAssertEqual(frame.local(.leftEye).x, -0.5)
            XCTAssertEqual(Double(frame.pixel(frame.local(.leftEye)).x), Double(scene.face().leftEye.x), accuracy: 0.5, "left eye lands on the left eye at roll \(roll)")
            XCTAssertEqual(Double(frame.pixel(frame.local(.mouth)).y), Double(scene.face().mouth.y), accuracy: 0.5)
        }
        // The top of the head is above the eyes however the head is turned.
        var turned = SyntheticScene(); turned.roll = 0.6
        let f = FaceFrame(turned.face())
        XCTAssertGreaterThan(f.local(CGPoint(x: Double(f.pixel(SIMD2(0, 1.5)).x), y: Double(f.pixel(SIMD2(0, 1.5)).y))).y, 1.4)
    }
}

@MainActor
final class LensLibraryTests: XCTestCase {
    private let scratch = Scratch()
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "backdrop.library.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    /// Lenses are deleted outright here, not sent to the real Trash.
    private func library() -> LensLibrary {
        LensLibrary(directory: scratch.url.appendingPathComponent("Lenses"), defaults: defaults, trash: { try? FileManager.default.removeItem(at: $0) })
    }

    func testTheFirstRunPutsTheExamplesInAndLaterRunsLeaveTheFolderAlone() throws {
        let first = library()
        XCTAssertEqual(first.packs.count, SampleLenses.all.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.directory.appendingPathComponent("README.txt").path))
        try FileManager.default.removeItem(at: first.directory.appendingPathComponent("Heart Eyes.backdroplens"))
        let second = library()
        XCTAssertEqual(second.packs.count, SampleLenses.all.count - 1, "a lens the user deleted stays deleted")
    }

    func testBuiltInsAndOwnLensesShareOnePicker() {
        let lib = library()
        XCTAssertEqual(lib.all.count, LensCatalog.all.count + SampleLenses.all.count)
        XCTAssertEqual(lib.categories, LensInfo.Category.allCases, "all four categories have something")
        XCTAssertEqual(lib.lenses(in: .custom).count, SampleLenses.all.count)
        XCTAssertNotNil(lib.info(for: "flappy-face"))
        XCTAssertNotNil(lib.info(for: "pack.Heart Eyes.backdroplens"))
        XCTAssertNil(lib.info(for: "pack.nope"))
    }

    func testMyLensesDisappearsFromThePickerWhenThereAreNone() throws {
        let lib = library()
        for pack in lib.packs { lib.trash(pack) }
        XCTAssertTrue(lib.lenses(in: .custom).isEmpty)
        XCTAssertFalse(lib.categories.contains(.custom))
    }

    func testReloadNoticesLensesComingAndGoingAndBrokenOnes() throws {
        let lib = library()
        let before = lib.packs.count
        scratch.lens("Lenses/Fresh", json: "{ \"format\": 1, \"name\": \"Fresh\", \"look\": { \"saturation\": 2 } }")
        scratch.lens("Lenses/Oops", json: "{ nope")
        lib.reload()
        XCTAssertEqual(lib.packs.count, before + 1)
        XCTAssertEqual(lib.problems.map(\.id), ["Oops"])
        try FileManager.default.removeItem(at: lib.directory.appendingPathComponent("Oops"))
        lib.reload()
        XCTAssertTrue(lib.problems.isEmpty)
    }

    func testEditingALensChangesItsModifiedDate() throws {
        let lib = library()
        let folder = scratch.lens("Lenses/Editable", json: "{ \"format\": 1, \"name\": \"Editable\", \"look\": { \"saturation\": 2 } }")
        lib.reload()
        let first = try XCTUnwrap(lib.info(for: "pack.Editable")?.modified)
        Thread.sleep(forTimeInterval: 1.1)
        try "{ \"format\": 1, \"name\": \"Editable v2\", \"look\": { \"saturation\": 3 } }".write(to: folder.appendingPathComponent("lens.json"), atomically: true, encoding: .utf8)
        lib.reload()
        let after = try XCTUnwrap(lib.info(for: "pack.Editable"))
        XCTAssertGreaterThan(try XCTUnwrap(after.modified), first)
        XCTAssertEqual(after.name, "Editable v2")
    }

    func testFavouritesAreKeptEvenWhenALensCantBeReadForAMoment() throws {
        let lib = library()
        lib.toggleFavourite("breakout"); lib.toggleFavourite("pack.Heart Eyes.backdroplens")
        XCTAssertEqual(lib.favouriteLenses.map(\.id).sorted(), ["breakout", "pack.Heart Eyes.backdroplens"])
        XCTAssertEqual(library().favourites, ["breakout", "pack.Heart Eyes.backdroplens"], "they survive a relaunch")

        // A typo in lens.json for a moment doesn't cost the star.
        let manifest = lib.directory.appendingPathComponent("Heart Eyes.backdroplens/lens.json")
        let good = try String(contentsOf: manifest, encoding: .utf8)
        try "{ typo".write(to: manifest, atomically: true, encoding: .utf8)
        lib.reload()
        XCTAssertNil(lib.info(for: "pack.Heart Eyes.backdroplens"))
        XCTAssertEqual(lib.favouriteLenses.map(\.id), ["breakout"], "not shown while it can't be read")
        try good.write(to: manifest, atomically: true, encoding: .utf8)
        lib.reload()
        XCTAssertEqual(lib.favouriteLenses.map(\.id).sorted(), ["breakout", "pack.Heart Eyes.backdroplens"], "and back again once it is fixed")
        lib.toggleFavourite("breakout")
        XCTAssertFalse(lib.isFavourite("breakout"))
    }

    func testAddingAndTrashing() throws {
        let lib = library()
        let source = Scratch()
        let lens = source.lens("Mine", json: "{ \"format\": 1, \"name\": \"Mine\", \"look\": { \"saturation\": 2 } }")
        try lib.add(lens)
        let info = try XCTUnwrap(lib.info(for: "pack.Mine"))
        XCTAssertEqual(info.category, .custom)
        lib.trash(info)
        XCTAssertNil(lib.info(for: "pack.Mine"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.directory.appendingPathComponent("Mine").path))
    }
}

// MARK: - Hostile and careless lenses

final class LensPackSafetyTests: XCTestCase {
    private let scratch = Scratch()

    private func linkedLens(_ build: (URL, URL) throws -> Void) throws -> LensPack {
        let outside = scratch.url.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        scratch.png("secret.png", in: outside, red: 1, green: 0, blue: 0)
        let folder = scratch.lens("Linked", json: """
        { "format": 1, "name": "Linked", "layers": [ { "type": "image", "image": "pic.png" }, { "type": "image", "image": "sub/secret.png" } ] }
        """)
        try build(folder, outside)
        return try LensPack.load(from: folder)
    }

    func testALinkToAFileOutsideTheLensFolderIsRefused() throws {
        let pack = try {
            let outside = scratch.url.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            scratch.png("secret.png", in: outside, red: 1, green: 0, blue: 0)
            let folder = scratch.lens("Sneaky", json: """
            { "format": 1, "name": "Sneaky", "layers": [ { "type": "image", "image": "pic.png" }, { "type": "emoji", "emoji": "🎩" } ] }
            """)
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("pic.png"), withDestinationURL: outside.appendingPathComponent("secret.png"))
            return try LensPack.load(from: folder)
        }()
        XCTAssertEqual(pack.layers.count, 1, "only the emoji; the linked picture is dropped")
        XCTAssertTrue(pack.warnings.joined().contains("links aren't followed"), "\(pack.warnings)")
    }

    func testALinkedSubFolderThatLeadsElsewhereIsRefused() throws {
        let pack = try linkedLens { folder, outside in
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("sub"), withDestinationURL: outside)
            scratch.png("pic.png", in: folder, red: 0, green: 1, blue: 0)
        }
        XCTAssertEqual(pack.layers.count, 1, "the plain picture loads; the one reached through the linked folder doesn't")
        XCTAssertTrue(pack.warnings.joined().contains("isn't inside the lens's folder"))
    }

    func testEvenALinkToAnotherFileInsideTheFolderIsRefused() throws {
        let folder = scratch.lens("Inner", json: """
        { "format": 1, "name": "Inner", "layers": [ { "type": "image", "image": "alias.png" }, { "type": "emoji", "emoji": "🎩" } ] }
        """)
        scratch.png("real.png", in: folder, red: 0, green: 0, blue: 1)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("alias.png"), withDestinationURL: folder.appendingPathComponent("real.png"))
        XCTAssertEqual(try LensPack.load(from: folder).layers.count, 1)
    }

    func testPicturesAreCheckedFromTheirHeaderAndTooWideOnesAreRefused() throws {
        let folder = scratch.lens("Wide", json: """
        { "format": 1, "name": "Wide", "layers": [ { "type": "image", "image": "ok.png" }, { "type": "image", "image": "wide.png" },
                                                    { "type": "emoji", "emoji": "🎩" } ] }
        """)
        scratch.png("ok.png", in: folder, red: 0, green: 0, blue: 1)
        scratch.png("wide.png", in: folder, red: 0, green: 0, blue: 1, width: LensPack.maxImageEdge + 1, height: 1)
        let pack = try LensPack.load(from: folder)
        XCTAssertEqual(pack.layers.count, 2)
        XCTAssertTrue(pack.warnings.joined().contains("pictures can be at most"), "\(pack.warnings)")
    }

    func testPicturesAreNotDecodedUntilTheLensIsPutOnAndThenAreSmall() throws {
        let folder = scratch.lens("Lazy", json: """
        { "format": 1, "name": "Lazy", "layers": [ { "type": "image", "image": "big.png" } ] }
        """)
        scratch.png("big.png", in: folder, red: 1, green: 1, blue: 0, width: 3000, height: 2000)
        let pack = try LensPack.load(from: folder)
        guard case .image(let picture) = pack.layers[0].content else { return XCTFail() }
        XCTAssertEqual(picture.width, 3000, "its size is known from the header")
        let decoded = try XCTUnwrap(picture.cgImage)
        XCTAssertLessThanOrEqual(max(decoded.width, decoded.height), LensPack.decodedEdge, "and it is scaled down when it is read")
        XCTAssertTrue(picture.cgImage === decoded, "and read only once")
    }

    func testOnePictureUsedByManyLayersIsLoadedOnce() throws {
        let layers = (0..<40).map { _ in "{ \"type\": \"image\", \"image\": \"a.png\" }" }.joined(separator: ",")
        let folder = scratch.lens("Many", json: "{ \"format\": 1, \"name\": \"Many\", \"layers\": [\(layers)] }")
        scratch.png("a.png", in: folder, red: 1, green: 0, blue: 0)
        let pack = try LensPack.load(from: folder)
        let pictures = Set(pack.layers.compactMap { layer -> ObjectIdentifier? in if case .image(let p) = layer.content { return ObjectIdentifier(p) } else { return nil } })
        XCTAssertEqual(pack.layers.count, 40)
        XCTAssertEqual(pictures.count, 1)
    }

    func testOnlySoManyDifferentPicturesAreAllowed() throws {
        let names = (0..<(LensPack.maxImages + 3)).map { "p\($0).png" }
        let layers = names.map { "{ \"type\": \"image\", \"image\": \"\($0)\" }" }.joined(separator: ",")
        let folder = scratch.lens("Lots", json: "{ \"format\": 1, \"name\": \"Lots\", \"layers\": [\(layers)] }")
        for n in names { scratch.png(n, in: folder, red: 0, green: 1, blue: 1, side: 8) }
        let pack = try LensPack.load(from: folder)
        XCTAssertEqual(pack.layers.count, LensPack.maxImages)
        XCTAssertEqual(pack.warnings.count, 3)
    }

    func testLimitsOnEmittersWarpsEmojiAndTheFileItself() throws {
        let emitters = (0..<20).map { _ in "{ \"preset\": \"fire\", \"rate\": 50, \"size\": 50 }" }.joined(separator: ",")
        let warps = (0..<20).map { _ in "{ \"kind\": \"bulge\" }" }.joined(separator: ",")
        let folder = scratch.lens("Greedy", json: """
        { "format": 1, "name": "\(String(repeating: "N", count: 500))", "emitters": [\(emitters)], "warps": [\(warps)],
          "layers": [ { "type": "emoji", "emoji": "\(String(repeating: "🎩", count: 3000))" } ] }
        """)
        let pack = try LensPack.load(from: folder)
        XCTAssertEqual(pack.emitters.count, LensPack.maxEmitters)
        XCTAssertEqual(pack.warps.count, LensPack.maxWarps)
        XCTAssertLessThanOrEqual(pack.emitters[0].rate, 2)
        XCTAssertLessThanOrEqual(pack.emitters[0].size, 2)
        XCTAssertLessThanOrEqual(pack.name.count, 60)
        guard case .emoji(let emoji) = pack.layers[0].content else { return XCTFail() }
        XCTAssertLessThanOrEqual(emoji.count, LensPack.maxEmojiLength)

        let huge = scratch.lens("Huge", json: "{ \"format\": 1, \"name\": \"Huge\", \"description\": \"\(String(repeating: "x", count: LensPack.maxManifestBytes + 10))\", \"look\": { \"saturation\": 2 } }")
        XCTAssertThrowsError(try LensPack.load(from: huge)) { XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains("limit") == true) }
    }

    func testAZeroOrNegativeFormatIsRefused() {
        let folder = scratch.lens("Zero", json: "{ \"format\": 0, \"name\": \"Zero\", \"look\": { \"saturation\": 2 } }")
        XCTAssertThrowsError(try LensPack.load(from: folder))
    }

    func testASyntaxErrorSaysWhereItIs() {
        let folder = scratch.lens("Typo", json: "{\n  \"format\": 1,\n  \"name\": \"Typo\" oops\n}")
        XCTAssertThrowsError(try LensPack.load(from: folder)) {
            let message = ($0 as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.lowercased().contains("line"), "should say which line: \(message)")
        }
    }

    func testFoldersWithTheSameNameBeforeTheDotGetDifferentIDs() throws {
        let a = scratch.lens("Foo", json: "{ \"format\": 1, \"name\": \"A\", \"look\": { \"saturation\": 2 } }")
        let b = scratch.lens("Foo.backdroplens", json: "{ \"format\": 1, \"name\": \"B\", \"look\": { \"saturation\": 2 } }")
        XCTAssertNotEqual(try LensPack.load(from: a).id, try LensPack.load(from: b).id)
    }

    func testEditingAPictureCountsAsChangingTheLens() throws {
        let folder = scratch.lens("Edit", json: "{ \"format\": 1, \"name\": \"Edit\", \"layers\": [ { \"type\": \"image\", \"image\": \"a.png\" } ] }")
        scratch.png("a.png", in: folder, red: 1, green: 0, blue: 0)
        let before = try LensPack.load(from: folder).modified
        Thread.sleep(forTimeInterval: 1.1)
        scratch.png("a.png", in: folder, red: 0, green: 1, blue: 0)
        XCTAssertGreaterThan(try LensPack.load(from: folder).modified, before)
    }
}
