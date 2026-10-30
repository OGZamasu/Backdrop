import CoreImage
import XCTest

// MARK: - Rules

final class RuleResolverTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    private func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func testCalendarKeywordBeatsAppBeatsAnyEventBeatsTime() {
        let time = AutomationRule(trigger: .time(startMinute: 0, endMinute: 1439), backgroundID: a)
        let anyEvent = AutomationRule(trigger: .calendar(keyword: ""), backgroundID: b)
        let app = AutomationRule(trigger: .app(bundleID: "us.zoom.xos", appName: "Zoom"), backgroundID: c)
        let keyword = AutomationRule(trigger: .calendar(keyword: "client"), backgroundID: d)
        let context = AutomationContext(lastRuleApp: "us.zoom.xos", eventTitles: ["Client sync"], now: date(hour: 12))

        let all = [time, anyEvent, app, keyword]
        XCTAssertEqual(RuleResolver.resolve(all, in: context)?.backgroundID, d)
        XCTAssertEqual(RuleResolver.resolve([time, anyEvent, app], in: context)?.backgroundID, c)
        XCTAssertEqual(RuleResolver.resolve([time, anyEvent], in: context)?.backgroundID, b)
        XCTAssertEqual(RuleResolver.resolve([time], in: context)?.backgroundID, a)
    }

    func testDisabledAndNonMatchingRulesAreIgnored() {
        var off = AutomationRule(trigger: .app(bundleID: "x", appName: "X"), backgroundID: a)
        off.isEnabled = false
        let wrongApp = AutomationRule(trigger: .app(bundleID: "y", appName: "Y"), backgroundID: b)
        let context = AutomationContext(lastRuleApp: "x", now: date(hour: 9))
        XCTAssertNil(RuleResolver.resolve([off, wrongApp], in: context))
    }

    func testCalendarKeywordIsCaseAndDiacriticInsensitive() {
        let rule = AutomationRule(trigger: .calendar(keyword: "cafe"), backgroundID: a)
        let hit = AutomationContext(eventTitles: ["Standup at Café Roma"])
        let miss = AutomationContext(eventTitles: ["Dentist"])
        XCTAssertNotNil(RuleResolver.resolve([rule], in: hit))
        XCTAssertNil(RuleResolver.resolve([rule], in: miss))
    }

    func testAnyEventRuleNeedsAnEvent() {
        let rule = AutomationRule(trigger: .calendar(keyword: "  "), backgroundID: a)
        XCTAssertNil(RuleResolver.resolve([rule], in: AutomationContext(eventTitles: [])))
        XCTAssertNotNil(RuleResolver.resolve([rule], in: AutomationContext(eventTitles: ["Anything"])))
    }

    func testTimeRangeIncludesStartExcludesEnd() {
        let rule = AutomationRule(trigger: .time(startMinute: 9 * 60, endMinute: 17 * 60), backgroundID: a)
        func matches(_ h: Int, _ m: Int = 0) -> Bool { RuleResolver.matches(rule, in: AutomationContext(now: date(hour: h, minute: m))) }
        XCTAssertFalse(matches(8, 59))
        XCTAssertTrue(matches(9))
        XCTAssertTrue(matches(16, 59))
        XCTAssertFalse(matches(17))
    }

    func testTimeRangeWrapsPastMidnight() {
        let rule = AutomationRule(trigger: .time(startMinute: 20 * 60, endMinute: 6 * 60), backgroundID: a)
        func matches(_ h: Int) -> Bool { RuleResolver.matches(rule, in: AutomationContext(now: date(hour: h))) }
        XCTAssertTrue(matches(22))
        XCTAssertTrue(matches(2))
        XCTAssertFalse(matches(12))
    }

    func testEmptyTimeRangeNeverMatches() {
        let rule = AutomationRule(trigger: .time(startMinute: 600, endMinute: 600), backgroundID: a)
        XCTAssertFalse(RuleResolver.matches(rule, in: AutomationContext(now: date(hour: 10))))
    }

    func testRulesRoundTripThroughJSON() throws {
        let rules = [
            AutomationRule(trigger: .app(bundleID: "us.zoom.xos", appName: "Zoom"), backgroundID: a),
            AutomationRule(trigger: .calendar(keyword: "1:1"), backgroundID: b),
            AutomationRule(trigger: .time(startMinute: 60, endMinute: 120), backgroundID: c),
        ]
        let decoded = try JSONDecoder().decode([AutomationRule].self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(decoded, rules)
    }
}

// MARK: - Compositor

final class CompositorTests: XCTestCase {
    private let compositor = Compositor()
    private var plain: CompositeParameters {
        // Isolate the cut itself from the colour tricks.
        CompositeParameters(edgeSoftness: 1.6, edgeShift: 0.03, lightWrap: 0, colorMatch: 0)
    }

    func testSubjectKeptWhereMatteIsWhiteAndBackgroundElsewhere() {
        let out = compositor.compose(camera: TestSupport.solid(1, 0, 0),
                                     mask: TestSupport.matte(leftFraction: 0.5),
                                     background: TestSupport.solid(0, 0, 1),
                                     params: plain)
        assertColor(TestSupport.pixel(out, x: 100, y: 360, context: compositor.context), (255, 0, 0), tolerance: 6, "inside the matte should be the camera")
        assertColor(TestSupport.pixel(out, x: 1180, y: 360, context: compositor.context), (0, 0, 255), tolerance: 6, "outside the matte should be the background")
    }

    func testEdgeIsSoftNotAStaircase() {
        let out = compositor.compose(camera: TestSupport.solid(1, 0, 0),
                                     mask: TestSupport.matte(leftFraction: 0.5),
                                     background: TestSupport.solid(0, 0, 1),
                                     params: plain)
        // Crossing the matte boundary the red channel should fall through intermediate values.
        let samples = (630...650).map { TestSupport.pixel(out, x: $0, y: 360, context: compositor.context).r }
        XCTAssertTrue(samples.contains { $0 > 20 && $0 < 235 }, "expected intermediate values across the edge, got \(samples)")
        XCTAssertEqual(samples, samples.sorted(by: >), "edge should fall monotonically from subject to background")
    }

    func testEdgeShiftTrimsHaloInward() {
        func redAtBoundary(shift: Double) -> Int {
            var p = plain; p.edgeShift = shift
            let out = compositor.compose(camera: TestSupport.solid(1, 0, 0), mask: TestSupport.matte(leftFraction: 0.5),
                                         background: TestSupport.solid(0, 0, 1), params: p)
            return TestSupport.pixel(out, x: 640, y: 360, context: compositor.context).r
        }
        XCTAssertLessThan(redAtBoundary(shift: 0.2), redAtBoundary(shift: 0.0), "a larger shift should leave less subject at the boundary")
    }

    func testNoMatteReturnsTheFittedCamera() {
        let out = compositor.compose(camera: TestSupport.solid(0, 1, 0, size: CGSize(width: 1920, height: 1080)), mask: nil, background: nil)
        XCTAssertEqual(out.extent, compositor.rect)
        assertColor(TestSupport.pixel(out, x: 640, y: 360, context: compositor.context), (0, 255, 0))
    }

    func testFillCoversTheOutputForAnyAspect() {
        let dest = CGRect(x: 0, y: 0, width: 1280, height: 720)
        for source in [CGRect(x: 0, y: 0, width: 640, height: 480), CGRect(x: 0, y: 0, width: 1080, height: 1920), CGRect(x: 0, y: 0, width: 3840, height: 1080)] {
            let covered = source.applying(Compositor.fillTransform(source, into: dest))
            XCTAssertTrue(covered.contains(dest), "\(source) → \(covered) must cover \(dest)")
            let inside = source.applying(Compositor.fitTransform(source, into: dest))
            XCTAssertTrue(dest.contains(inside.insetBy(dx: 0.01, dy: 0.01)), "\(source) → \(inside) must fit in \(dest)")
        }
    }

    func testMatteResolutionDoesNotNeedToMatchCamera() {
        // Vision returns a much smaller matte than the camera frame.
        let small = Compositor.matte(from: TestSupport.matteBuffer(width: 256, height: 144, leftFraction: 0.5))
        let out = compositor.compose(camera: TestSupport.solid(1, 0, 0), mask: small, background: TestSupport.solid(0, 0, 1), params: plain)
        assertColor(TestSupport.pixel(out, x: 100, y: 360, context: compositor.context), (255, 0, 0), tolerance: 6)
        assertColor(TestSupport.pixel(out, x: 1180, y: 360, context: compositor.context), (0, 0, 255), tolerance: 6)
    }

    func testLightWrapOnlyTouchesTheSubjectEdge() {
        var wrapped = plain; wrapped.lightWrap = 1
        let camera = TestSupport.solid(0.2, 0.2, 0.2), bg = TestSupport.solid(1, 1, 1)
        let withWrap = compositor.compose(camera: camera, mask: TestSupport.matte(leftFraction: 0.5), background: bg, params: wrapped)
        let without = compositor.compose(camera: camera, mask: TestSupport.matte(leftFraction: 0.5), background: bg, params: plain)

        let edgeWith = TestSupport.pixel(withWrap, x: 625, y: 360, context: compositor.context).r
        let edgeWithout = TestSupport.pixel(without, x: 625, y: 360, context: compositor.context).r
        XCTAssertGreaterThan(edgeWith, edgeWithout + 5, "background light should spill onto the subject's edge")

        let coreWith = TestSupport.pixel(withWrap, x: 100, y: 360, context: compositor.context).r
        let coreWithout = TestSupport.pixel(without, x: 100, y: 360, context: compositor.context).r
        XCTAssertEqual(coreWith, coreWithout, accuracy: 3, "the middle of the subject shouldn't change")
    }

    func testParallaxShiftsTheBackgroundAgainstTheSubject() {
        // A background with a left/right split so a horizontal shift is visible.
        let split = TestSupport.solid(1, 0, 0, size: CGSize(width: 640, height: 720))
            .composited(over: TestSupport.solid(0, 0, 1))
        func redAt(_ x: Int, parallax: CGPoint?) -> Int {
            let prepared = compositor.prepareBackground(split, fits: false, parallax: parallax)
            return TestSupport.pixel(prepared, x: x, y: 360, context: compositor.context).r
        }
        // Subject has moved right (+1), so the background drifts left: the red half shrinks.
        XCTAssertGreaterThan(redAt(630, parallax: nil), 200)
        XCTAssertLessThan(redAt(630, parallax: CGPoint(x: 1, y: 0)), 60)
    }

    func testFitModeLetterboxesInsteadOfCropping() {
        // A tall window: filling would crop top and bottom; fitting keeps all of it.
        let tall = TestSupport.solid(1, 0, 0, size: CGSize(width: 400, height: 800))
        let prepared = compositor.prepareBackground(tall, fits: true, parallax: nil)
        XCTAssertEqual(prepared.extent, compositor.rect)
        assertColor(TestSupport.pixel(prepared, x: 640, y: 360, context: compositor.context), (255, 0, 0), tolerance: 6, "content in the middle")
        let corner = TestSupport.pixel(prepared, x: 5, y: 360, context: compositor.context)
        XCTAssertGreaterThan(corner.r, 150, "the side bars are a blurred copy of the content, not black")
    }

    func testDissolveEndpointsAreTheInputs() {
        let red = TestSupport.solid(1, 0, 0), blue = TestSupport.solid(0, 0, 1)
        assertColor(TestSupport.pixel(compositor.dissolve(from: red, to: blue, progress: 0), x: 10, y: 10, context: compositor.context), (255, 0, 0))
        assertColor(TestSupport.pixel(compositor.dissolve(from: red, to: blue, progress: 1), x: 10, y: 10, context: compositor.context), (0, 0, 255))
        let mid = TestSupport.pixel(compositor.dissolve(from: red, to: blue, progress: 0.5), x: 10, y: 10, context: compositor.context)
        XCTAssertTrue(mid.r > 60 && mid.b > 60, "halfway should be a mix, got \(mid)")
    }

    func testOutputBuffersAreIOSurfaceBackedBGRA() {
        let buffer = compositor.makeOutputBuffer()
        XCTAssertNotNil(buffer)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(buffer!), kCVPixelFormatType_32BGRA)
        XCTAssertEqual(CVPixelBufferGetWidth(buffer!), 1280)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer!), 720)
        XCTAssertNotNil(CVPixelBufferGetIOSurface(buffer!), "needs to be shareable with the camera extension without a copy")
    }
}

// MARK: - Mask smoothing

final class MaskSmootherTests: XCTestCase {
    func testFirstFramePassesThrough() {
        let smoother = MaskSmoother()
        let out = smoother.smooth(TestSupport.matteBuffer(width: 64, height: 36, leftFraction: 1))
        XCTAssertEqual(TestSupport.matteValue(out, x: 10, y: 10), 255)
    }

    func testBlendsTowardTheNewMatte() {
        let smoother = MaskSmoother()
        smoother.responsiveness = 0.5
        _ = smoother.smooth(TestSupport.matteBuffer(width: 64, height: 36, leftFraction: 1))
        let out = smoother.smooth(TestSupport.matteBuffer(width: 64, height: 36, leftFraction: 0))
        XCTAssertEqual(TestSupport.matteValue(out, x: 10, y: 10), 127, accuracy: 2)
        let again = smoother.smooth(TestSupport.matteBuffer(width: 64, height: 36, leftFraction: 0))
        XCTAssertEqual(TestSupport.matteValue(again, x: 10, y: 10), 63, accuracy: 2)
    }

    /// The blend works 16 pixels at a time; every pixel, including the odd few at the end of a row, must come out exactly as
    /// the one-at-a-time formula says.
    func testTheFastBlendMatchesTheFormulaOnEveryPixel() {
        func buffer(width: Int, height: Int, _ value: (Int, Int) -> UInt8) -> CVPixelBuffer {
            var created: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_OneComponent8,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &created)
            let b = created!
            CVPixelBufferLockBaseAddress(b, [])
            let base = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(b)
            for y in 0..<height { for x in 0..<width { base[y * stride + x] = value(x, y) } }
            CVPixelBufferUnlockBaseAddress(b, [])
            return b
        }
        for width in [1, 15, 16, 17, 37, 64, 1280] {
            let first = buffer(width: width, height: 5) { x, y in UInt8(truncatingIfNeeded: x * 7 + y * 31) }
            let second = buffer(width: width, height: 5) { x, y in UInt8(truncatingIfNeeded: 255 - x * 13 + y * 5) }
            let smoother = MaskSmoother()
            smoother.responsiveness = 0.65
            _ = smoother.smooth(first)
            let out = smoother.smooth(second)
            let weight = Int(0.65 * 256)
            for y in 0..<5 {
                for x in 0..<width {
                    let old = Int(UInt8(truncatingIfNeeded: x * 7 + y * 31)), new = Int(UInt8(truncatingIfNeeded: 255 - x * 13 + y * 5))
                    let expected = (old * (256 - weight) + new * weight) >> 8
                    XCTAssertEqual(Int(TestSupport.matteValue(out, x: x, y: y)), expected, "width \(width), pixel \(x),\(y)")
                }
            }
        }
    }

    func testSurvivesResolutionChange() {
        let smoother = MaskSmoother()
        _ = smoother.smooth(TestSupport.matteBuffer(width: 64, height: 36, leftFraction: 1))
        let out = smoother.smooth(TestSupport.matteBuffer(width: 128, height: 72, leftFraction: 0))
        XCTAssertEqual(TestSupport.matteValue(out, x: 10, y: 10), 0, "no blending across different sizes")
    }

    func testCentroidFollowsTheSubject() {
        let smoother = MaskSmoother()
        for _ in 0..<40 { _ = smoother.smooth(TestSupport.matteBuffer(width: 128, height: 72, leftFraction: 0.25)) }
        XCTAssertLessThan(smoother.centroid.x, 0.3, "subject on the left")
        smoother.reset()
        XCTAssertEqual(smoother.centroid.x, 0.5)
    }

    func testTinyBlobDoesNotMoveTheCentroid() {
        let smoother = MaskSmoother()
        _ = smoother.smooth(TestSupport.matteBuffer(width: 128, height: 72, leftFraction: 0))
        XCTAssertEqual(smoother.centroid.x, 0.5, "with nobody in frame the parallax shouldn't wander")
    }
}

// MARK: - Library

@MainActor
final class BackgroundLibraryTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-tests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeImageFile(named name: String = "room.png") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        let context = CIContext()
        try context.writePNGRepresentation(of: TestSupport.solid(0.3, 0.5, 0.7, size: CGSize(width: 64, height: 36)),
                                           to: url, format: .RGBA8, colorSpace: TestSupport.srgb)
        return url
    }

    func testBuiltInsAreAlwaysPresentAndStable() {
        let first = BackgroundLibrary(directory: directory).items.map(\.id)
        let second = BackgroundLibrary(directory: directory).items.map(\.id)
        XCTAssertEqual(first, second, "rules refer to built-ins by ID, so they must not change between launches")
        XCTAssertTrue(first.contains(Background.off.id))
        XCTAssertEqual(Set(first).count, first.count, "IDs must be unique")
    }

    func testImportCopiesTheFileAndPersists() throws {
        let source = try makeImageFile()
        let library = BackgroundLibrary(directory: directory)
        let item = try library.importFile(at: source)

        guard case .image(let file) = item.kind else { return XCTFail("expected an image background") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.mediaDirectory.appendingPathComponent(file).path))
        try FileManager.default.removeItem(at: source)   // the library must not depend on the original

        let reloaded = BackgroundLibrary(directory: directory)
        XCTAssertEqual(reloaded.userItems.map(\.id), [item.id])
        XCTAssertNotNil(reloaded.fileURL(for: reloaded.userItems[0]))
    }

    func testRejectsUnsupportedFiles() throws {
        let text = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try BackgroundLibrary(directory: directory).importFile(at: text))
    }

    func testRemoveDeletesTheMedia() throws {
        let library = BackgroundLibrary(directory: directory)
        let item = try library.importFile(at: try makeImageFile())
        let url = library.fileURL(for: item)!
        library.remove(item.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(library.userItems.isEmpty)
    }

    func testBuiltInsCannotBeEditedOrRemoved() {
        let library = BackgroundLibrary(directory: directory)
        let count = library.items.count
        library.remove(Background.softBlur.id)
        library.update(Background.softBlur.id) { $0.name = "Hacked" }
        XCTAssertEqual(library.items.count, count)
        XCTAssertEqual(library.background(withID: Background.softBlur.id)?.name, "Soft Blur")
    }

    func testGeneratedBackgroundKeepsItsPrompt() throws {
        let library = BackgroundLibrary(directory: directory)
        let item = try library.addGenerated(from: try makeImageFile(), prompt: "a cozy library with warm lamps")
        XCTAssertEqual(item.origin, .generated)
        XCTAssertEqual(item.prompt, "a cozy library with warm lamps")
        XCTAssertEqual(item.name, "A cozy library with warm lamps")
        XCTAssertEqual(BackgroundLibrary(directory: directory).userItems.first?.prompt, item.prompt)
    }

    func testEntriesWithMissingMediaAreDroppedOnLoad() throws {
        let library = BackgroundLibrary(directory: directory)
        let keep = library.addDisplay()
        let lose = try library.importFile(at: try makeImageFile())
        try FileManager.default.removeItem(at: library.fileURL(for: lose)!)

        let reloaded = BackgroundLibrary(directory: directory)
        XCTAssertEqual(reloaded.userItems.map(\.id), [keep.id])
    }

    func testParallaxToggleIsPersisted() throws {
        let library = BackgroundLibrary(directory: directory)
        let item = try library.importFile(at: try makeImageFile())
        library.update(item.id) { $0.parallax = true }
        XCTAssertEqual(BackgroundLibrary(directory: directory).background(withID: item.id)?.parallax, true)
    }

    func testLongPromptsGetAShortTitle() throws {
        let library = BackgroundLibrary(directory: directory)
        let item = try library.addGenerated(from: try makeImageFile(), prompt: String(repeating: "mountain ", count: 20))
        XCTAssertLessThanOrEqual(item.name.count, 36)
        XCTAssertTrue(item.name.hasSuffix("…"))
    }
}

// MARK: - Pipeline, end to end

final class FramePipelineTests: XCTestCase {
    private func run(_ pipeline: FramePipeline, camera: CVPixelBuffer) -> CVPixelBuffer? {
        var result: CVPixelBuffer?
        pipeline.onOutput = { buffer, _ in result = buffer }
        pipeline.queue.sync { pipeline.process(camera, at: .zero) }
        return result
    }

    func testPassthroughShowsTheCamera() {
        let pipeline = FramePipeline()
        pipeline.setBackground(.off, source: nil)
        let out = run(pipeline, camera: TestSupport.cameraBuffer(r: 200, g: 40, b: 40))
        XCTAssertNotNil(out)
        assertColor(TestSupport.pixel(out!, x: 640, y: 360), (200, 40, 40), tolerance: 6)
    }

    func testWithNobodyInFrameTheRoomIsReplacedEntirely() {
        // A flat red frame has no person in it, so none of it may survive into a non-passthrough background.
        let pipeline = FramePipeline()
        let source = GradientSource(preset: .graphite)
        pipeline.setBackground(Background(id: UUID(), name: "g", kind: .gradient(.graphite), origin: .builtIn), source: source)
        let out = run(pipeline, camera: TestSupport.cameraBuffer(r: 255, g: 0, b: 0))
        XCTAssertNotNil(out)
        let center = TestSupport.pixel(out!, x: 640, y: 360)
        XCTAssertLessThan(center.r, 140, "camera red leaked through: \(center)")
        XCTAssertLessThan(abs(center.r - center.b), 60, "graphite should be near-neutral, got \(center)")
    }

    func testPreviewIsDeliveredOnlyWhenEnabled() {
        let pipeline = FramePipeline()
        pipeline.setBackground(.off, source: nil)
        var previews = 0
        pipeline.onPreview = { _ in previews += 1 }
        let camera = TestSupport.cameraBuffer(r: 10, g: 10, b: 10)
        _ = run(pipeline, camera: camera); _ = run(pipeline, camera: camera)
        XCTAssertEqual(previews, 0)

        pipeline.setPreviewEnabled(true)
        for _ in 0..<4 { _ = run(pipeline, camera: camera) }
        XCTAssertGreaterThan(previews, 0)
    }

    func testSwitchingBackgroundsKeepsProducingFrames() {
        let pipeline = FramePipeline()
        pipeline.setBackground(Background(id: UUID(), name: "a", kind: .gradient(.aurora), origin: .builtIn), source: GradientSource(preset: .aurora))
        let camera = TestSupport.cameraBuffer(r: 90, g: 90, b: 90)
        XCTAssertNotNil(run(pipeline, camera: camera))
        pipeline.setBackground(Background(id: UUID(), name: "b", kind: .gradient(.sunset), origin: .builtIn), source: GradientSource(preset: .sunset))
        for _ in 0..<5 { XCTAssertNotNil(run(pipeline, camera: camera), "frames must keep flowing through a crossfade") }
        pipeline.setBackground(.off, source: nil)
        XCTAssertNotNil(run(pipeline, camera: camera))
    }
}

final class SourcesTests: XCTestCase {
    func testGradientAnimatesOverTime() {
        let source = GradientSource(preset: .aurora)
        let context = CIContext()
        let camera = TestSupport.solid(0, 0, 0)
        let early = source.frame(at: 0, camera: camera)!, later = source.frame(at: 30, camera: camera)!
        let a = TestSupport.pixel(early, x: 300, y: 300, context: context)
        let b = TestSupport.pixel(later, x: 300, y: 300, context: context)
        XCTAssertGreaterThan(abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b), 6, "a live gradient should change from moment to moment")
    }

    func testBlurSourceKeepsTheFrameSize() {
        let camera = TestSupport.solid(1, 0, 0, size: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(BlurSource(radius: 20).frame(at: 0, camera: camera)?.extent, camera.extent)
    }

    func testImageSourceDownscalesHugePhotos() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try CIContext().writePNGRepresentation(of: TestSupport.solid(0.5, 0.2, 0.2, size: CGSize(width: 5000, height: 3000)),
                                               to: url, format: .RGBA8, colorSpace: TestSupport.srgb)
        defer { try? FileManager.default.removeItem(at: url) }
        let frame = ImageSource(url: url).frame(at: 0, camera: TestSupport.solid(0, 0, 0))
        XCTAssertNotNil(frame)
        XCTAssertLessThanOrEqual(max(frame!.extent.width, frame!.extent.height), 2560)
    }

    func testMissingImageYieldsNoFrameRatherThanCrashing() {
        XCTAssertNil(ImageSource(url: URL(fileURLWithPath: "/nonexistent/nope.png")).frame(at: 0, camera: TestSupport.solid(0, 0, 0)))
    }
}

// MARK: - Camera extension rules

final class CameraExtensionPolicyTests: XCTestCase {
    func testOnlyANewerBuildReplacesWhatIsInstalled() {
        XCTAssertTrue(CameraExtensionPolicy.shouldReplace(existingBuild: "7", withBuild: "8"))
        XCTAssertTrue(CameraExtensionPolicy.shouldReplace(existingBuild: "9", withBuild: "10"), "numbers, not text: 10 is newer than 9")
        XCTAssertFalse(CameraExtensionPolicy.shouldReplace(existingBuild: "8", withBuild: "8"), "never a copy for itself")
        XCTAssertFalse(CameraExtensionPolicy.shouldReplace(existingBuild: "9", withBuild: "7"), "never back to an older one")
        XCTAssertTrue(CameraExtensionPolicy.shouldReplace(existingBuild: "x", withBuild: "8"), "unreadable versions don't block an update")
    }

    func testUpgradingNeedsSomethingInstalledAndTheAppsCopyToBeNewer() {
        XCTAssertTrue(CameraExtensionPolicy.shouldUpgrade(installedBuilds: ["7"], embeddedBuild: "8"))
        XCTAssertFalse(CameraExtensionPolicy.shouldUpgrade(installedBuilds: ["8"], embeddedBuild: "8"))
        XCTAssertFalse(CameraExtensionPolicy.shouldUpgrade(installedBuilds: ["9"], embeddedBuild: "8"), "a development build beside a newer install leaves it alone")
        XCTAssertFalse(CameraExtensionPolicy.shouldUpgrade(installedBuilds: [], embeddedBuild: "8"), "a first install is the user's to start")
        XCTAssertFalse(CameraExtensionPolicy.shouldUpgrade(installedBuilds: ["7", "9"], embeddedBuild: "8"), "newer than all of them, not just one")
    }

    func testTheCameraIsOnlyCalledMissingAfterAWhileAndOnlyIfItShouldBeThere() {
        var monitor = CameraMissingMonitor()
        for _ in 0..<9 { XCTAssertFalse(monitor.poll(installedAndEnabled: true, deviceVisible: false)) }
        XCTAssertTrue(monitor.poll(installedAndEnabled: true, deviceVisible: false), "ten seconds of absence")
        XCTAssertFalse(monitor.poll(installedAndEnabled: true, deviceVisible: true), "and it's cleared the moment the camera shows")

        var notInstalled = CameraMissingMonitor()
        for _ in 0..<30 { XCTAssertFalse(notInstalled.poll(installedAndEnabled: false, deviceVisible: false), "nothing installed, nothing missing") }

        var flicker = CameraMissingMonitor()
        for _ in 0..<5 { _ = flicker.poll(installedAndEnabled: true, deviceVisible: false) }
        _ = flicker.poll(installedAndEnabled: true, deviceVisible: true)
        for _ in 0..<9 { XCTAssertFalse(flicker.poll(installedAndEnabled: true, deviceVisible: false), "the count starts again after it was seen") }
    }
}
