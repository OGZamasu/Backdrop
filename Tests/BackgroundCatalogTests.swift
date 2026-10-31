import CoreGraphics
import CoreImage
import CoreVideo
import XCTest

/// The list of built-in backgrounds: how many, which ids, and what is saved on disk.
@MainActor
final class BackgroundCatalogTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-catalog-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testThereAreSixtyEightBuiltInsBesidesOff() {
        XCTAssertGreaterThanOrEqual(Background.builtIns.count, 69)
        XCTAssertTrue(Background.builtIns.allSatisfy { $0.origin == .builtIn })
    }

    func testIDsAndNamesAreUnique() {
        let ids = Background.builtIns.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ids must be unique: rules and saved choices refer to built-ins by id")
        let names = Background.builtIns.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "names must be unique so the grid is unambiguous")
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty && $0.count <= 16 }, "names have to fit under a tile")
    }

    func testTheOriginalNineKeepTheirIDsNamesAndKinds() {
        let original: [(Int, String, BackgroundKind)] = [
            (1, "Off", .passthrough), (2, "Soft Blur", .blur(radius: 14)), (3, "Heavy Blur", .blur(radius: 40)),
            (30, "3D Pipes", .pipes), (31, "3D Maze", .maze),
            (10, "Aurora", .gradient(.aurora)), (11, "Sunset", .gradient(.sunset)), (12, "Ocean", .gradient(.ocean)), (13, "Graphite", .gradient(.graphite)),
        ]
        for (n, name, kind) in original {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))
            let found = Background.builtIns.first { $0.id == id }
            XCTAssertEqual(found?.name, name, "built-in \(n)")
            XCTAssertEqual(found?.kind, kind, "built-in \(n)")
        }
        XCTAssertEqual(Array(Background.builtIns.prefix(9).map(\.name)),
                       ["Off", "Soft Blur", "Heavy Blur", "3D Pipes", "3D Maze", "Aurora", "Sunset", "Ocean", "Graphite"],
                       "the first nine keep their places")
    }

    func testTheLibraryListsBuiltInsFirstAndKeepsWhatTheUserAdded() {
        let library = BackgroundLibrary(directory: directory)
        let screen = library.addDisplay()
        XCTAssertEqual(Array(library.items.prefix(Background.builtIns.count)), Background.builtIns)
        XCTAssertEqual(library.items.last?.id, screen.id)
        XCTAssertEqual(BackgroundLibrary(directory: directory).userItems.map(\.id), [screen.id])
    }

    func testEveryKindRoundTripsThroughJSON() throws {
        for background in Background.builtIns {
            let again = try JSONDecoder().decode(Background.self, from: JSONEncoder().encode(background))
            XCTAssertEqual(again, background, background.name)
        }
        let user = Background(id: UUID(), name: "Mine", kind: .solid(hex: "336699", lit: true), origin: .imported, parallax: true)
        XCTAssertEqual(try JSONDecoder().decode(Background.self, from: JSONEncoder().encode(user)), user)
    }

    func testALibraryFileSavedByAnOlderVersionStillLoads() throws {
        // The shapes the app wrote before the new kinds existed, one of each.
        let file = """
        [{"id":"11111111-1111-1111-1111-111111111111","name":"blur","kind":{"blur":{"radius":10}},"origin":"imported","parallax":false,"createdAt":0},
         {"id":"22222222-2222-2222-2222-222222222222","name":"gradient","kind":{"gradient":{"_0":"sunset"}},"origin":"imported","parallax":true,"createdAt":0},
         {"id":"33333333-3333-3333-3333-333333333333","name":"screen","kind":{"display":{}},"origin":"imported","parallax":false,"createdAt":0},
         {"id":"44444444-4444-4444-4444-444444444444","name":"pipes","kind":{"pipes":{}},"origin":"imported","parallax":false,"createdAt":0},
         {"id":"55555555-5555-5555-5555-555555555555","name":"window","kind":{"window":{"bundleID":"com.apple.Terminal"}},"origin":"imported","parallax":false,"createdAt":0},
         {"id":"66666666-6666-6666-6666-666666666666","name":"off","kind":{"passthrough":{}},"origin":"imported","parallax":false,"createdAt":0}]
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(file.utf8).write(to: directory.appendingPathComponent("library.json"))
        let library = BackgroundLibrary(directory: directory)
        XCTAssertEqual(library.userItems.map(\.name), ["blur", "gradient", "screen", "pipes", "window", "off"])
        XCTAssertEqual(library.userItems[1].kind, .gradient(.sunset))
        XCTAssertEqual(library.userItems[4].kind, .window(bundleID: "com.apple.Terminal", title: nil))
    }

    func testNewKindsAreStoredInASimpleShape() throws {
        let solid = try JSONDecoder().decode(BackgroundKind.self, from: Data(#"{"solid":{"hex":"00B140","lit":false}}"#.utf8))
        XCTAssertEqual(solid, .solid(hex: "00B140", lit: false))
        let live = try JSONDecoder().decode(BackgroundKind.self, from: Data(#"{"procedural":{"_0":"lavaLamp"}}"#.utf8))
        XCTAssertEqual(live, .procedural(.lavaLamp))
        let treated = try JSONDecoder().decode(BackgroundKind.self, from: Data(#"{"treated":{"_0":"frosted"}}"#.utf8))
        XCTAssertEqual(treated, .treated(.frosted))
        let preset = try JSONDecoder().decode(BackgroundKind.self, from: Data(#"{"gradient":{"_0":"roseGold"}}"#.utf8))
        XCTAssertEqual(preset, .gradient(.roseGold))
    }

    func testLiveBackgroundsAreTheOnesThatChangeOnTheirOwn() {
        for background in Background.builtIns {
            switch background.kind {
            case .gradient, .pipes, .maze: XCTAssertTrue(background.isLive, background.name)
            case .procedural(let style): XCTAssertEqual(background.isLive, style.isAnimated, "\(background.name): stills are painted once, scenes that move are live")
            case .passthrough, .blur, .solid, .treated: XCTAssertFalse(background.isLive, background.name)
            case .image, .video, .window, .display: XCTFail("\(background.name): no built-in should be a file or a window")
            }
        }
        XCTAssertEqual(ProceduralStyle.allCases.count, Background.builtIns.filter { if case .procedural = $0.kind { return true } else { return false } }.count,
                       "every live scene is in the list")
    }

    func testEveryGradientPresetHasFourColoursThatAreReallyColours() {
        for preset in GradientPreset.allCases {
            XCTAssertEqual(preset.colors.count, 4, preset.title)
            for colour in preset.colors {
                XCTAssertEqual(colour.count, 3, preset.title)
                XCTAssertTrue(colour.allSatisfy { (0...1).contains($0) }, "\(preset.title): \(colour)")
            }
            XCTAssertTrue(Background.builtIns.contains { $0.kind == .gradient(preset) }, "\(preset.title) is in the list")
        }
        XCTAssertEqual(GradientPreset.roseGold.title, "Rose Gold")
        XCTAssertEqual(GradientPreset.forest.title, "Forest")
    }

    func testEveryTreatmentAndSceneHasAWordedDescription() {
        for treatment in CameraTreatment.allCases { XCTAssertFalse(treatment.blurb.isEmpty); XCTAssertFalse(treatment.title.isEmpty) }
        for style in ProceduralStyle.allCases { XCTAssertFalse(style.blurb.isEmpty); XCTAssertFalse(style.title.isEmpty) }
    }

    func testSolidColoursParse() {
        let green = BackdropPaint.rgb(hex: "00B140")
        XCTAssertEqual(green?.r, 0)
        XCTAssertEqual(green?.g ?? 0, 177.0 / 255, accuracy: 0.001)
        XCTAssertEqual(BackdropPaint.rgb(hex: "#FFFFFF")?.b, 1)
        XCTAssertNil(BackdropPaint.rgb(hex: "nope"))
        XCTAssertNil(BackdropPaint.rgb(hex: "FFF"))
        for case .solid(let hex, _) in Background.builtIns.map(\.kind) { XCTAssertNotNil(BackdropPaint.rgb(hex: hex), hex) }
    }
}

// MARK: - Pictures

/// Renders backgrounds the way the pipeline does, so what the tests measure is what the app shows.
@MainActor
final class BackgroundCatalogRenderTests: XCTestCase {
    private let compositor = Compositor()
    private let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-catalog-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var camera: CIImage { CIImage(cvPixelBuffer: scene.cameraBuffer()) }
    private let bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)

    private func source(for background: Background) -> BackgroundSource? {
        BackgroundSourceFactory.make(for: background, library: BackgroundLibrary(directory: directory))
    }

    /// The background as the compositor lays it down, at a moment.
    private func picture(_ source: BackgroundSource, at time: Double, camera: CIImage) -> CIImage? {
        source.frame(at: time, camera: camera).map { compositor.prepareBackground($0, fits: source.fitsContent, parallax: nil) }
    }

    private func bytes(_ image: CIImage) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 1280 * 720 * 4)
        compositor.context.render(image, toBitmap: &out, rowBytes: 1280 * 4, bounds: bounds, format: .RGBA8, colorSpace: TestSupport.srgb)
        return out
    }

    /// How far apart two pictures are: the average difference per channel, 0...255.
    private func distance(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total = 0
        var i = 0
        while i < a.count {   // every 7th byte is plenty, and keeps this quick
            total += abs(Int(a[i]) - Int(b[i]))
            i += 7
        }
        return Double(total) / Double(a.count / 7 + 1)
    }

    private func isOpaque(_ image: CIImage) -> Bool {
        // Alpha of a few spots across the frame.
        for (x, y) in [(2, 2), (640, 360), (1277, 717), (200, 600), (1100, 120)] {
            var px = [UInt8](repeating: 0, count: 4)
            compositor.context.render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: TestSupport.srgb)
            if px[3] != 255 { return false }
        }
        return true
    }

    // MARK: Every built-in makes a source that draws

    func testEveryBuiltInMakesASourceExceptOff() {
        for background in Background.builtIns {
            let made = source(for: background)
            if case .passthrough = background.kind { XCTAssertNil(made, background.name) } else { XCTAssertNotNil(made, "\(background.name) has no source") }
        }
    }

    func testEverySourceDrawsAFullOpaqueFrame() throws {
        let camera = self.camera
        for background in Background.builtIns {
            guard let made = source(for: background) else { continue }
            made.start()
            defer { made.stop() }
            let frame = try XCTUnwrap(made.frame(at: 3, camera: camera), background.name)
            XCTAssertGreaterThanOrEqual(frame.extent.width, 1270, background.name)
            XCTAssertLessThanOrEqual(frame.extent.width, 1290, background.name)
            XCTAssertGreaterThanOrEqual(frame.extent.height, 710, background.name)
            XCTAssertLessThanOrEqual(frame.extent.height, 730, background.name)
            XCTAssertTrue(isOpaque(frame), "\(background.name) must not let the room show through")
        }
    }

    func testLiveScenesChangeFromMomentToMomentAndStaticOnesDoNot() throws {
        let camera = self.camera
        for background in Background.builtIns {
            switch background.kind {
            case .pipes, .maze, .passthrough: continue    // covered by their own suites
            default: break
            }
            guard let made = source(for: background) else { continue }
            let a = bytes(try XCTUnwrap(picture(made, at: 10, camera: camera), background.name))
            let b = bytes(try XCTUnwrap(picture(made, at: 10.5, camera: camera), background.name))
            let c = bytes(try XCTUnwrap(picture(made, at: 25, camera: camera), background.name))
            if background.isLive {
                XCTAssertGreaterThan(distance(a, b), 0.05, "\(background.name) should move within half a second")
                XCTAssertGreaterThan(distance(a, c), 0.5, "\(background.name) should look different 15 seconds later")
            } else {
                XCTAssertEqual(distance(a, b), 0, accuracy: 0.001, "\(background.name) holds still")
            }
        }
    }

    func testAFrameDependsOnlyOnTheClock() throws {
        // A stall, or two sources made at different times, must not change what a given moment looks like.
        let camera = self.camera
        for style in ProceduralStyle.allCases {
            let background = try XCTUnwrap(Background.builtIns.first { $0.kind == .procedural(style) })
            let first = try XCTUnwrap(source(for: background)), second = try XCTUnwrap(source(for: background))
            _ = first.frame(at: 1, camera: camera)
            _ = first.frame(at: 2, camera: camera)
            let a = bytes(try XCTUnwrap(picture(first, at: 40, camera: camera)))
            let b = bytes(try XCTUnwrap(picture(second, at: 40, camera: camera)))
            XCTAssertEqual(distance(a, b), 0, accuracy: 0.001, "\(background.name): same time, same picture")
        }
    }

    func testClocksFarFromZeroStillMoveSmoothly() throws {
        // A camera clock counts from boot, so weeks in. Frames a thirtieth of a second apart must still differ a little
        // and not jump.
        let camera = self.camera
        for style in ProceduralStyle.allCases where style.isAnimated {
            let background = try XCTUnwrap(Background.builtIns.first { $0.kind == .procedural(style) })
            let made = try XCTUnwrap(source(for: background))
            let late = 3_000_000.0
            let a = bytes(try XCTUnwrap(picture(made, at: late, camera: camera)))
            let b = bytes(try XCTUnwrap(picture(made, at: late + 1.0 / 30, camera: camera)))
            let c = bytes(try XCTUnwrap(picture(made, at: late + 2.0 / 30, camera: camera)))
            let step1 = distance(a, b), step2 = distance(b, c)
            XCTAssertGreaterThan(step1, 0.0005, "\(background.name) is frozen weeks into the clock")
            XCTAssertLessThan(abs(step1 - step2), max(0.8, step1 * 0.8), "\(background.name) jerks weeks into the clock: \(step1) then \(step2)")
        }
    }

    func testEveryBackgroundLooksDifferentFromEveryOther() throws {
        let camera = self.camera
        var shots: [(String, [UInt8])] = []
        for background in Background.builtIns {
            guard let made = source(for: background), let image = picture(made, at: 12, camera: camera) else { continue }
            shots.append((background.name, bytes(image)))
        }
        XCTAssertEqual(shots.count, Background.builtIns.count - 1)
        for i in 0..<shots.count {
            for j in (i + 1)..<shots.count {
                XCTAssertGreaterThan(distance(shots[i].1, shots[j].1), 0.8, "\(shots[i].0) and \(shots[j].0) look the same")
            }
        }
    }

    // MARK: Specific looks

    func testChromaGreenIsExactlyAndEverywhereGreen() throws {
        let made = try XCTUnwrap(source(for: .chromaGreen))
        let image = try XCTUnwrap(picture(made, at: 0, camera: camera))
        for (x, y) in [(2, 2), (640, 360), (1277, 717), (30, 690)] {
            assertColor(TestSupport.pixel(image, x: x, y: y, context: compositor.context), (0, 177, 64), tolerance: 2, "chroma key green at \(x),\(y)")
        }
    }

    func testALitWallIsBrighterInTheMiddleThanInTheCorners() throws {
        let made = try XCTUnwrap(source(for: .whiteWall))
        let image = try XCTUnwrap(picture(made, at: 0, camera: camera))
        let middle = TestSupport.pixel(image, x: 640, y: 440, context: compositor.context)
        let corner = TestSupport.pixel(image, x: 4, y: 4, context: compositor.context)
        XCTAssertGreaterThan(middle.r, corner.r + 12)
        XCTAssertGreaterThan(corner.r, 170, "still a white wall in the corner")
        XCTAssertLessThan(abs(middle.r - middle.b), 14, "and it stays neutral")
    }

    func testTreatmentsFollowTheCameraAndDoNotShowTheRoomSharply() throws {
        let camera = self.camera
        let sharp = bytes(compositor.fitted(camera))
        for treatment in CameraTreatment.allCases {
            let made = CameraTreatmentSource(treatment)
            let image = try XCTUnwrap(picture(made, at: 0, camera: camera))
            let treated = bytes(image)
            XCTAssertGreaterThan(distance(sharp, treated), 3, "\(treatment.title) must change the picture")
            // The shelf and the table in the synthetic room have hard edges; a few pixels either side of one must not show it.
            let edge = (y: 450, left: 100, right: 120)   // across the left side of the bright rectangle (x 110, y 340...590)
            let l = TestSupport.pixel(image, x: edge.left, y: edge.y, context: compositor.context)
            let r = TestSupport.pixel(image, x: edge.right, y: edge.y, context: compositor.context)
            XCTAssertLessThan(abs(l.r - r.r) + abs(l.g - r.g) + abs(l.b - r.b), 150, "\(treatment.title) is still sharp at an edge: \(l) \(r)")
        }
        // The camera is not used up: a smaller camera frame works too.
        let tiny = TestSupport.solid(0.4, 0.5, 0.6, size: CGSize(width: 640, height: 360))
        for treatment in CameraTreatment.allCases {
            let frame = CameraTreatmentSource(treatment).frame(at: 0, camera: tiny)
            XCTAssertEqual(frame?.extent, tiny.extent, treatment.title)
        }
    }

    func testTreatmentsGiveNothingForAnEmptyCamera() {
        let empty = CIImage.empty()
        for treatment in CameraTreatment.allCases { XCTAssertNil(CameraTreatmentSource(treatment).frame(at: 0, camera: empty)) }
    }

    func testTheStarfieldHasStarsOnADarkSky() throws {
        let made = StarfieldSource()
        let pixels = bytes(try XCTUnwrap(picture(made, at: 30, camera: camera)))
        var dark = 0, bright = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let v = max(pixels[i], pixels[i + 1], pixels[i + 2])
            if v < 70 { dark += 1 } else if v > 150 { bright += 1 }
        }
        let total = pixels.count / 4
        XCTAssertGreaterThan(Double(dark) / Double(total), 0.9, "mostly dark space")
        XCTAssertGreaterThan(bright, 200, "with stars")
    }

    func testTheSynthwaveHorizonSeparatesWarmSkyFromDarkFloor() throws {
        let image = try XCTUnwrap(picture(SynthwaveSource(), at: 5, camera: camera))
        let sky = TestSupport.pixel(image, x: 200, y: 700, context: compositor.context)
        let floor = TestSupport.pixel(image, x: 200, y: 20, context: compositor.context)
        XCTAssertLessThan(sky.r + sky.g + sky.b, 200, "the top of the sky is night")
        XCTAssertLessThan(floor.r + floor.g + floor.b, 220, "the floor is dark")
    }

    func testTreatmentsWorkOnACameraFrameThatDoesNotStartAtTheOrigin() throws {
        let odd = TestSupport.solid(0.3, 0.6, 0.4, size: CGSize(width: 800, height: 450)).transformed(by: CGAffineTransform(translationX: 120, y: 40))
        for treatment in CameraTreatment.allCases {
            let frame = try XCTUnwrap(CameraTreatmentSource(treatment).frame(at: 0, camera: odd), treatment.title)
            XCTAssertEqual(frame.extent.minX, odd.extent.minX, accuracy: 0.5, treatment.title)
            XCTAssertEqual(frame.extent.width, odd.extent.width, accuracy: 0.5, treatment.title)
            XCTAssertEqual(frame.extent.height, odd.extent.height, accuracy: 0.5, treatment.title)
        }
    }

    func testTheLavaLampHasWaxAndGlassAndNeitherFillsTheFrame() throws {
        let made = LavaLampSource()
        for time in [5.0, 40, 90] {
            let pixels = bytes(try XCTUnwrap(picture(made, at: time, camera: camera)))
            var wax = 0
            for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i] > 200 && pixels[i + 1] > 90 { wax += 1 }
            let share = Double(wax) / Double(pixels.count / 4)
            XCTAssertGreaterThan(share, 0.04, "t=\(time): there should be blobs")
            XCTAssertLessThan(share, 0.65, "t=\(time): and room between them")
        }
    }

    func testPlasmaStaysInTheMidTonesSoItDoesNotFightTheFace() throws {
        let pixels = bytes(try XCTUnwrap(picture(PlasmaSource(), at: 17, camera: camera)))
        var total = 0.0, brightest = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
            brightest = max(brightest, Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]))
        }
        let mean = total / Double(pixels.count / 4) / 255
        XCTAssertGreaterThan(mean, 0.12)
        XCTAssertLessThan(mean, 0.5, "a plasma brighter than a face makes the face disappear")
        XCTAssertLessThan(brightest, 3 * 235)
    }

    func testNightScenesAreDark() throws {
        for (name, made) in [("Starfield", StarfieldSource() as BackgroundSource), ("Fireflies", FirefliesSource()), ("Rainy Window", RainWindowSource())] {
            let pixels = bytes(try XCTUnwrap(picture(made, at: 9, camera: camera)))
            var total = 0.0
            for i in stride(from: 0, to: pixels.count, by: 4) { total += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2]) }
            XCTAssertLessThan(total / Double(pixels.count / 4) / 255, 0.25, name)
        }
    }

    /// The person has to stand out. Skin tone against the middle of each backdrop, around where a head would be.
    func testEveryBackdropContrastsWithSkinWhereTheHeadGoes() throws {
        let skin: RGB = (237, 189, 158)
        let camera = self.camera
        let around = CGRect(x: 480, y: 150, width: 320, height: 420)
        for background in Background.builtIns {
            switch background.kind {
            case .passthrough, .treated, .pipes, .maze: continue     // these follow the room, or have their own suites
            default: break
            }
            guard let made = source(for: background) else { continue }
            for time in [5.0, 31] {
                let image = try XCTUnwrap(picture(made, at: time, camera: camera), background.name)
                let area = image.cropped(to: around).applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: around)])
                let mean = TestSupport.pixel(area, x: Int(around.minX), y: Int(around.minY), context: compositor.context)
                let gap = abs(mean.r - skin.r) + abs(mean.g - skin.g) + abs(mean.b - skin.b)
                XCTAssertGreaterThan(gap, 45, "\(background.name) at \(time) s is too close to skin tone behind the head: \(mean)")
            }
        }
    }

    func testEveryLiveSceneMakesAPickerThumbnail() throws {
        for style in ProceduralStyle.allCases {
            let image = try XCTUnwrap(ProceduralBackdrop.thumbnail(for: style), style.title)
            XCTAssertEqual(image.width, 480, style.title)
            XCTAssertEqual(image.height, 270, style.title)
            let small = CIImage(cgImage: image)
            let a = TestSupport.pixel(small, x: 20, y: 20, context: compositor.context)
            let b = TestSupport.pixel(small, x: 400, y: 200, context: compositor.context)
            let c = TestSupport.pixel(small, x: 240, y: 135, context: compositor.context)
            XCTAssertGreaterThan(abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) + abs(a.r - c.r) + abs(a.g - c.g) + abs(a.b - c.b), 20, "\(style.title) thumbnail is blank")
        }
    }

    // MARK: Saved pictures, to look at

    /// Every new background, on its own and with the pretend person in front, plus one contact sheet of them all.
    func testSavePicturesOfEveryBackground() throws {
        guard ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] != nil else { return }
        let camera = self.camera
        let matte = compositor.refinedMatte(camera: camera, mask: Compositor.matte(from: scene.matteBuffer()))
        var sheet: [(String, CIImage)] = []
        for background in Background.builtIns {
            guard let made = source(for: background) else { continue }
            let slug = background.name.lowercased().replacingOccurrences(of: " ", with: "-")
            let times: [Double] = background.isLive ? [4, 19] : [4]
            for (i, time) in times.enumerated() {
                guard let backdrop = picture(made, at: time, camera: camera) else { continue }
                Output.save(backdrop, as: "bg-\(slug)-\(i).png")
                let composed = compositor.composite(camera: camera, matte: matte, background: backdrop)
                Output.save(composed, as: "with-person-\(slug)-\(i).png")
                if i == 0 { sheet.append((background.name, composed)) }
            }
        }
        // A contact sheet: six across.
        let columns = 6, cell = CGSize(width: 320, height: 180)
        let rows = (sheet.count + columns - 1) / columns
        var canvas = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: CGRect(x: 0, y: 0, width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows)))
        for (index, entry) in sheet.enumerated() {
            let col = index % columns, row = index / columns
            let small = entry.1.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
                .transformed(by: CGAffineTransform(translationX: CGFloat(col) * cell.width, y: CGFloat(rows - 1 - row) * cell.height))
            canvas = small.composited(over: canvas)
        }
        Output.save(canvas, as: "contact-sheet.png")
    }

    // MARK: Cost

    /// Milliseconds a frame of the background costs the pipeline: building it and actually rendering it.
    func testEachBackgroundIsCheapToDrawEveryFrame() throws {
        let camera = self.camera
        let buffer = try XCTUnwrap(compositor.makeOutputBuffer())
        var report: [String] = []
        for background in Background.builtIns {
            switch background.kind {
            case .pipes, .maze, .passthrough: continue    // SceneKit; measured by CostPerFrameTests and SwitchLatencyTests
            default: break
            }
            guard let made = source(for: background) else { continue }
            made.start()
            defer { made.stop() }
            for i in 0..<10 { if let f = picture(made, at: Double(i) / 30, camera: camera) { compositor.render(f, into: buffer) } }   // warm up
            var durations: [Double] = []
            for i in 0..<90 {
                let started = CFAbsoluteTimeGetCurrent()
                if let frame = picture(made, at: 10 + Double(i) / 30, camera: camera) { compositor.render(frame, into: buffer) }
                durations.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
            }
            let mean = durations.reduce(0, +) / Double(durations.count)
            let worst = durations.max() ?? 0
            report.append(String(format: "%-14@ mean %5.2f ms   worst %5.2f ms", background.name as NSString, mean, worst))
            // The brief is 3 ms for a release build on a quiet machine. A debug build, with other work running, gets room.
            XCTAssertLessThan(mean, 12, "\(background.name) costs \(mean) ms a frame")
        }
        print("BACKGROUND COST\n" + report.joined(separator: "\n"))
    }

    func testFirstFrameOfEverySourceIsQuick() throws {
        let camera = self.camera
        let buffer = try XCTUnwrap(compositor.makeOutputBuffer())
        var report: [String] = []
        for background in Background.builtIns {
            switch background.kind {
            case .pipes, .maze, .passthrough: continue
            default: break
            }
            let started = CFAbsoluteTimeGetCurrent()
            let made = try XCTUnwrap(source(for: background))
            if let f = picture(made, at: 0, camera: camera) { compositor.render(f, into: buffer) }
            let took = (CFAbsoluteTimeGetCurrent() - started) * 1000
            if took > 25 { report.append(String(format: "%@ %.0f ms", background.name as NSString, took)) }
            XCTAssertLessThan(took, 400, "\(background.name) takes \(took) ms to appear")
        }
        print("BACKGROUND FIRST FRAME over 25 ms: " + (report.isEmpty ? "none" : report.joined(separator: ", ")))
    }

    func testSourcesCanBeStoppedAndUsedAgain() throws {
        let camera = self.camera
        for background in Background.builtIns {
            guard let made = source(for: background) else { continue }
            if case .pipes = background.kind { continue }
            if case .maze = background.kind { continue }
            made.start()
            _ = made.frame(at: 1, camera: camera)
            made.stop()
            XCTAssertNotNil(made.frame(at: 2, camera: camera), "\(background.name) after stop")
        }
    }
}

// MARK: - Through the real pipeline

/// A few of the new backgrounds put through the whole pipeline, the way the app runs them.
final class BackgroundCatalogPipelineTests: XCTestCase {
    private func output(_ pipeline: FramePipeline, camera: CVPixelBuffer) -> CVPixelBuffer? {
        var result: CVPixelBuffer?
        pipeline.onOutput = { buffer, _ in result = buffer }
        pipeline.queue.sync { pipeline.process(camera, at: .zero) }
        return result
    }

    @MainActor
    func testWithNobodyInFrameNoRoomShowsThroughAnyNewBackdrop() throws {
        let library = BackgroundLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-catalog-\(UUID().uuidString)"))
        let red = TestSupport.cameraBuffer(r: 255, g: 0, b: 0)
        for background in Background.builtIns {
            switch background.kind {
            case .passthrough, .treated, .pipes, .maze, .blur: continue      // these are made from the room
            default: break
            }
            let pipeline = FramePipeline()
            pipeline.matteOverride = { _ in TestSupport.matteBuffer(width: 128, height: 72, leftFraction: 0) }
            pipeline.setBackground(background, source: BackgroundSourceFactory.make(for: background, library: library))
            let out = try XCTUnwrap(output(pipeline, camera: red), background.name)
            for (x, y) in [(60, 60), (640, 360), (1200, 650)] {
                let p = TestSupport.pixel(out, x: x, y: y)
                XCTAssertGreaterThan(abs(p.r - 255) + p.g + p.b, 40, "\(background.name): the red room shows at \(x),\(y): \(p)")
            }
        }
    }

    @MainActor
    func testSwitchingAcrossEveryKindKeepsFramesFlowing() throws {
        let library = BackgroundLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-catalog-\(UUID().uuidString)"))
        let scene = SyntheticScene()
        let pipeline = FramePipeline()
        pipeline.matteOverride = { _ in scene.matteBuffer() }
        let camera = scene.cameraBuffer()
        let picks: [Background] = [.chromaGreen, Background.builtIns.first { $0.kind == .procedural(.starfield) }!, .lightBlur,
                                   Background.builtIns.first { $0.kind == .treated(.frosted) }!, Background.builtIns.first { $0.kind == .procedural(.plasma) }!,
                                   .off, .whiteWall]
        for background in picks {
            pipeline.setBackground(background, source: BackgroundSourceFactory.make(for: background, library: library))
            for _ in 0..<4 { XCTAssertNotNil(output(pipeline, camera: camera), "frames must keep flowing after switching to \(background.name)") }
        }
        let wall = try XCTUnwrap(output(pipeline, camera: camera))
        assertColor(TestSupport.pixel(wall, x: 40, y: 40), (200, 200, 197), tolerance: 40, "the white wall, far from the person")
    }
}
