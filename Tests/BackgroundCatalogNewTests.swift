import CoreGraphics
import CoreImage
import XCTest

/// The thirty-four backgrounds added in round two, and the finishing pieces every built-in now shares.
@MainActor
final class BackdropNewBackgroundTests: XCTestCase {
    private let compositor = Compositor()
    private let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))
    private let bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)

    /// Ids of the new built-ins: six gradients and twenty-eight scenes.
    private static let newNumbers = Array(70...75) + Array(80...107)

    private var newBackgrounds: [Background] {
        let ids = Set(Self.newNumbers.compactMap { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0)) })
        return Background.builtIns.filter { ids.contains($0.id) }
    }

    private func source(_ background: Background) -> BackgroundSource? {
        BackgroundSourceFactory.make(for: background, library: BackgroundLibrary(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("backdrop-new-\(UUID().uuidString)")))
    }

    private func alpha(_ image: CIImage, x: Int, y: Int) -> UInt8 {
        var px = [UInt8](repeating: 0, count: 4)
        compositor.context.render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: TestSupport.srgb)
        return px[3]
    }

    // MARK: The list

    func testThereAreThirtyFourNewBuiltInsWithFreshIDs() {
        XCTAssertEqual(newBackgrounds.count, 34, "six gradients and twenty-eight scenes")
        let oldNumbers = [1, 2, 3, 10, 11, 12, 13, 30, 31] + Array(40...49) + Array(51...66)
        XCTAssertTrue(Set(oldNumbers).isDisjoint(with: Self.newNumbers), "new built-ins take fresh numbers")
        // Every built-in from before round two is still there under its old id.
        for n in oldNumbers {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))
            XCTAssertTrue(Background.builtIns.contains { $0.id == id }, "built-in \(n) is gone")
        }
        let kinds = newBackgrounds.map(\.kind)
        XCTAssertEqual(kinds.filter { if case .gradient = $0 { return true } else { return false } }.count, 6)
        XCTAssertEqual(kinds.filter { if case .procedural = $0 { return true } else { return false } }.count, 28)
        XCTAssertEqual(ProceduralStyle.allCases.count, 35)
        XCTAssertEqual(GradientPreset.allCases.count, 18)
    }

    func testNewKindsDecodeFromTheSimpleShapeOnDisk() throws {
        let scene = try JSONDecoder().decode(BackgroundKind.self, from: Data(#"{"procedural":{"_0":"northernLights"}}"#.utf8))
        XCTAssertEqual(scene, .procedural(.northernLights))
        let preset = try JSONDecoder().decode(BackgroundKind.self, from: Data(#"{"gradient":{"_0":"lagoon"}}"#.utf8))
        XCTAssertEqual(preset, .gradient(.lagoon))
    }

    func testEveryNewSceneHasAShortNameAndAPlainBlurb() {
        for style in ProceduralStyle.allCases {
            XCTAssertLessThanOrEqual(style.title.count, 16, style.title)
            XCTAssertTrue(style.blurb.hasSuffix("."), "\(style.title): one sentence")
            XCTAssertLessThan(style.blurb.count, 80, "\(style.title): one short sentence")
        }
    }

    // MARK: Pictures

    /// Every new backdrop draws a whole, opaque 1280 x 720 picture, on its own and with a person in front, and the person
    /// is still there afterwards.
    func testEveryNewBackgroundRendersWithAndWithoutAPerson() throws {
        let camera = CIImage(cvPixelBuffer: scene.cameraBuffer())
        let matte = compositor.refinedMatte(camera: camera, mask: Compositor.matte(from: scene.matteBuffer()))
        for background in newBackgrounds {
            let made = try XCTUnwrap(source(background), background.name)
            made.start()
            defer { made.stop() }
            let frame = try XCTUnwrap(made.frame(at: 7, camera: camera), background.name)
            let backdrop = compositor.prepareBackground(frame, fits: made.fitsContent, parallax: nil)
            XCTAssertEqual(backdrop.extent, bounds, background.name)
            for (x, y) in [(2, 2), (640, 360), (1277, 717), (100, 650), (1180, 80)] {
                XCTAssertEqual(alpha(backdrop, x: x, y: y), 255, "\(background.name) lets the room through at \(x),\(y)")
            }
            let composed = compositor.composite(camera: camera, matte: matte, background: backdrop)
            // The middle of the face is the person, not the backdrop.
            let face = TestSupport.pixel(composed, x: 640, y: 400, context: compositor.context)
            XCTAssertGreaterThan(face.r, 180, "\(background.name): the face is gone")
            let slug = background.name.lowercased().replacingOccurrences(of: " ", with: "-")
            Output.save(backdrop, as: "new-bg-\(slug).png")
            Output.save(composed, as: "new-with-person-\(slug).png")
        }
    }

    /// A stall, a clock weeks old, or a time before zero must still give a picture, and stills must not move.
    func testScenesSurviveHugeAndOddTimes() throws {
        let camera = CIImage(cvPixelBuffer: scene.cameraBuffer())
        for background in newBackgrounds {
            let made = try XCTUnwrap(source(background), background.name)
            for time in [0.0, -3.5, 12, 9_000_000.25, 0.001] {
                let frame = try XCTUnwrap(made.frame(at: time, camera: camera), "\(background.name) at \(time)")
                XCTAssertEqual(alpha(frame, x: 640, y: 360), 255, "\(background.name) at \(time)")
            }
        }
    }

    // MARK: The shared finish

    /// Dither: down one column of a smooth dark wall, no run of identical pixels is long enough to show as a band.
    func testDitherBreaksUpBandsInSmoothGradients() throws {
        let navy = try XCTUnwrap(SolidBackdropSource(hex: "14213D", lit: true).frame(at: 0, camera: .empty()))
        var column = [UInt8](repeating: 0, count: 720 * 4)
        compositor.context.render(navy, toBitmap: &column, rowBytes: 4, bounds: CGRect(x: 200, y: 0, width: 1, height: 720), format: .RGBA8, colorSpace: TestSupport.srgb)
        var longest = 1, run = 1
        for y in 1..<720 {
            let same = column[y * 4] == column[(y - 1) * 4] && column[y * 4 + 1] == column[(y - 1) * 4 + 1] && column[y * 4 + 2] == column[(y - 1) * 4 + 2]
            run = same ? run + 1 : 1
            longest = max(longest, run)
        }
        XCTAssertLessThan(longest, 12, "a run of \(longest) identical pixels is a visible band")
    }

    /// The finish is fixed in place: a still backdrop is exactly the same from one frame to the next.
    func testGrainAndDitherDoNotFlicker() throws {
        let image = try XCTUnwrap(SolidBackdropSource(hex: "7E8185", lit: true).frame(at: 0, camera: .empty()))
        let again = try XCTUnwrap(SolidBackdropSource(hex: "7E8185", lit: true).frame(at: 99, camera: .empty()))
        for (x, y) in [(10, 10), (640, 360), (901, 77)] {
            let a = TestSupport.pixel(image, x: x, y: y, context: compositor.context), b = TestSupport.pixel(again, x: x, y: y, context: compositor.context)
            XCTAssertEqual(a.r, b.r); XCTAssertEqual(a.g, b.g); XCTAssertEqual(a.b, b.b)
        }
    }

    /// The shared noise repeats seamlessly, so things drawn with it can drift forever without a seam.
    func testTheNoiseTileJoinsUpWithItself() {
        let field = BackdropNoise.field(0, scale: 1, extent: CGRect(x: 0, y: 0, width: 1024, height: 600))
        for (x, y) in [(13, 40), (100, 7), (250, 200)] {
            let a = TestSupport.pixel(field, x: x, y: y, context: compositor.context)
            let b = TestSupport.pixel(field, x: x + BackdropNoise.period, y: y, context: compositor.context)
            let c = TestSupport.pixel(field, x: x, y: y + BackdropNoise.period, context: compositor.context)
            XCTAssertLessThanOrEqual(abs(a.r - b.r), 1, "seam across at \(x),\(y)")
            XCTAssertLessThanOrEqual(abs(a.r - c.r), 1, "seam up at \(x),\(y)")
        }
    }

    /// Mixing in Oklab keeps the middle of a mix lively: halfway from blue to yellow is not a grey.
    func testOklabMixesStayColourful() {
        let middle = BackdropInk.mix(BackdropRGB(0, 0, 1), BackdropRGB(1, 1, 0), 0.5)
        XCTAssertGreaterThan(middle.r + middle.g + middle.b, 1.2, "\(middle)")
        let same = BackdropInk.mix(BackdropRGB(0.3, 0.5, 0.7), BackdropRGB(0.3, 0.5, 0.7), 0.4)
        XCTAssertEqual(same.r, 0.3, accuracy: 0.002); XCTAssertEqual(same.g, 0.5, accuracy: 0.002); XCTAssertEqual(same.b, 0.7, accuracy: 0.002)
    }

    // MARK: Cost

    /// Live scenes must be cheap enough to run every frame: under 3 ms in a release build. This debug-build measurement,
    /// on a busy machine, gets room; it catches anything gone badly wrong.
    func testNewLiveScenesAreCheapEveryFrame() throws {
        let camera = CIImage(cvPixelBuffer: scene.cameraBuffer())
        let buffer = try XCTUnwrap(compositor.makeOutputBuffer())
        var report: [String] = []
        for background in newBackgrounds where background.isLive {
            let made = try XCTUnwrap(source(background))
            for i in 0..<6 { if let f = made.frame(at: Double(i) / 30, camera: camera) { compositor.render(compositor.prepareBackground(f, fits: false, parallax: nil), into: buffer) } }
            var durations: [Double] = []
            for i in 0..<45 {
                let started = CFAbsoluteTimeGetCurrent()
                if let f = made.frame(at: 20 + Double(i) / 30, camera: camera) { compositor.render(compositor.prepareBackground(f, fits: false, parallax: nil), into: buffer) }
                durations.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
            }
            durations.sort()
            let median = durations[durations.count / 2]
            report.append(String(format: "%-16@ median %5.2f ms", background.name as NSString, median))
            XCTAssertLessThan(median, 12, "\(background.name) costs \(median) ms a frame")
        }
        print("NEW BACKGROUND COST\n" + report.joined(separator: "\n"))
    }
}
