import AppKit
import SwiftUI
import XCTest

/// Helpers for looking at small pictures.
enum LensBrowserPixels {
    /// A picture shrunk to a few pixels, RGB bytes, for comparing pictures roughly.
    static func tiny(_ image: CGImage, width: Int = 64, height: Int = 36) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    /// Mean difference per channel, 0...255.
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total = 0
        for i in 0..<min(a.count, b.count) where i % 4 != 3 { total += abs(Int(a[i]) - Int(b[i])) }
        return Double(total) / Double(min(a.count, b.count) / 4 * 3)
    }

    /// The biggest difference anywhere: the mean difference of the most different `block` x `block` patch, 0...255. Two pictures that
    /// differ only around the eyes still count as different.
    static func patchDifference(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int, block: Int = 4) -> Double {
        var worst = 0.0
        for by in stride(from: 0, to: height - block + 1, by: block) {
            for bx in stride(from: 0, to: width - block + 1, by: block) {
                var total = 0
                for y in by..<(by + block) {
                    for x in bx..<(bx + block) {
                        let i = (y * width + x) * 4
                        total += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
                    }
                }
                worst = max(worst, Double(total) / Double(block * block * 3))
            }
        }
        return worst
    }

    /// Processor time this process has used, all threads, in seconds.
    static func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// How much the picture varies: the standard deviation of brightness.
    static func spread(_ a: [UInt8]) -> Double {
        let lum = stride(from: 0, to: a.count, by: 4).map { (Double(a[$0]) + Double(a[$0 + 1]) + Double(a[$0 + 2])) / 3 }
        let mean = lum.reduce(0, +) / Double(lum.count)
        return (lum.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lum.count)).squareRoot()
    }
}

// MARK: - Shelves, search, badges

final class LensBrowserGroupTests: XCTestCase {
    func testEveryBuiltInLensIsOnAShelfItsCategoryHas() {
        for info in LensCatalog.all {
            let shelf = LensBrowserGroups.table[info.id]
            XCTAssertNotNil(shelf, "\(info.id) is missing from the shelf table")
            XCTAssertTrue(LensBrowserGroups.order(for: info.category).contains(shelf ?? ""), "\(info.id): \(shelf ?? "nil") isn't a \(info.category) shelf")
            XCTAssertNotEqual(LensBrowserGroups.group(for: info), LensBrowserGroups.more, "\(info.id) should have a proper shelf")
        }
        // Nothing in the table that isn't a lens (a typo would quietly send a lens to More).
        let ids = Set(LensCatalog.all.map(\.id))
        for id in LensBrowserGroups.table.keys { XCTAssertTrue(ids.contains(id), "\(id) in the shelf table is not in the catalog") }
    }

    func testANewLensLandsSomewhereSensible() {
        func lens(_ id: String, _ category: LensInfo.Category, face: Bool = false, hands: Bool = false, subgroup: String? = nil) -> LensInfo {
            var info = LensInfo(id: id, name: id, glyph: "✨", blurb: "New.", category: category, scored: category == .games, needsFace: face) { MirrorLens() }
            info.needsHands = hands
            info.subgroup = subgroup
            return info
        }
        XCTAssertEqual(LensBrowserGroups.group(for: lens("brand-new-look", .filters)), "More")
        XCTAssertEqual(LensBrowserGroups.group(for: lens("brand-new-hand", .filters, hands: true)), "Hands")
        XCTAssertEqual(LensBrowserGroups.group(for: lens("brand-new-hat", .faces, face: true)), "More")
        XCTAssertEqual(LensBrowserGroups.group(for: lens("brand-new-game", .games, hands: true)), "Hands")
        XCTAssertEqual(LensBrowserGroups.group(for: lens("brand-new-face-game", .games, face: true)), "Face")
        XCTAssertEqual(LensBrowserGroups.group(for: lens("brand-new-body-game", .games)), "More")
        XCTAssertEqual(LensBrowserGroups.group(for: lens("brand-new-scene", .scenes)), "More")
        XCTAssertEqual(LensBrowserGroups.group(for: lens("pack.Mine", .custom, face: true)), "Face")
        XCTAssertEqual(LensBrowserGroups.group(for: lens("pack.Screen", .custom)), "Screen")
        XCTAssertEqual(LensBrowserGroups.group(for: lens("own-shelf", .filters, subgroup: "Looks")), "Looks", "a lens can name its shelf")

        // An unknown shelf a lens names for itself comes before More; More is always last.
        let lenses = [lens("a", .filters, subgroup: "Retro"), lens("b", .filters), lens("comic", .filters), lens("c", .filters, hands: true)]
        XCTAssertEqual(LensBrowserGroups.sections(lenses, in: .filters).map(\.group), ["Looks", "Hands", "Retro", "More"])
    }

    func testShelvesKeepTheCatalogOrderAndLeaveNothingOut() {
        for category in LensInfo.Category.allCases {
            let sections = LensBrowserGroups.sections(LensCatalog.all, in: category)
            XCTAssertEqual(sections.reduce(0) { $0 + $1.lenses.count }, LensCatalog.lenses(in: category).count)
            XCTAssertTrue(sections.allSatisfy { !$0.lenses.isEmpty })
        }
        XCTAssertEqual(LensBrowserGroups.sections(LensCatalog.all, in: .filters).map(\.group), ["Looks", "Weather & Light", "Hands"])
        XCTAssertEqual(LensBrowserGroups.sections(LensCatalog.all, in: .games).map(\.group), ["Hands", "Face", "Body", "Classic"])
    }

    func testSearchFindsByNameWordsAndNeedsBestFirst() {
        let all = LensCatalog.all
        XCTAssertEqual(LensBrowserGroups.search(all, query: "snow").first?.id, "snow", "a name that starts with the words comes first")
        XCTAssertTrue(LensBrowserGroups.search(all, query: "hand").allSatisfy { $0.needsHands || "\($0.name) \($0.blurb)".lowercased().contains("hand") })
        XCTAssertFalse(LensBrowserGroups.search(all, query: "hand").isEmpty)
        XCTAssertTrue(LensBrowserGroups.search(all, query: "costumes hat").contains { $0.id == "dress-party-hat" }, "every word must match, across fields")
        XCTAssertTrue(LensBrowserGroups.search(all, query: "zzzz-nothing").isEmpty)
        XCTAssertEqual(LensBrowserGroups.search(all, query: "  ").count, all.count)
    }

    func testBadgesAndNeeds() throws {
        let fruit = try XCTUnwrap(LensCatalog.info(for: "fruit-slash"))
        XCTAssertEqual(LensBrowserGroups.badges(for: fruit), [.hand, .score])
        let flappy = try XCTUnwrap(LensCatalog.info(for: "flappy-face"))
        XCTAssertEqual(LensBrowserGroups.badges(for: flappy), [.face, .score])
        let crown = try XCTUnwrap(LensCatalog.info(for: "dress-crown"))
        XCTAssertEqual(LensBrowserGroups.badges(for: crown), [], "every face lens needs a face, so it isn't marked")
        XCTAssertEqual(LensBrowserGroups.needs(of: crown).map(\.text), ["Needs your face"])
        XCTAssertEqual(LensBrowserGroups.needs(of: try XCTUnwrap(LensCatalog.info(for: "air-paint"))).map(\.text), ["Needs a hand in view"])
        XCTAssertEqual(LensBrowserGroups.needs(of: try XCTUnwrap(LensCatalog.info(for: "comic"))).map(\.text), ["Works on any picture"])
    }
}

// MARK: - Cache keys, the store and its queue

final class LensBrowserCacheTests: XCTestCase {
    func testKeysFollowTheIdBuildRendererAndEdits() {
        let a = LensThumbnailStore.cacheKey(id: "aura", build: "10", modified: nil)
        XCTAssertEqual(a, "aura--b10--r\(LensThumbnailStore.rendererVersion)")
        XCTAssertEqual(a, LensThumbnailStore.cacheKey(id: "aura", build: "10", modified: nil), "the same lens and build keep the same file")
        XCTAssertNotEqual(a, LensThumbnailStore.cacheKey(id: "aura", build: "11", modified: nil), "a new build makes it again")
        let edited = Date(timeIntervalSince1970: 1_800_000_000)
        let pack = LensThumbnailStore.cacheKey(id: "pack.Heart Eyes", build: "10", modified: edited)
        XCTAssertNotEqual(pack, LensThumbnailStore.cacheKey(id: "pack.Heart Eyes", build: "10", modified: edited.addingTimeInterval(1)),
                          "an edited lens.json makes it again")
        XCTAssertNotEqual(LensThumbnailStore.cacheKey(id: "pack.a b", build: "1", modified: nil), LensThumbnailStore.cacheKey(id: "pack.a_b", build: "1", modified: nil),
                          "ids that clean up the same still get different files")
        for key in [pack, LensThumbnailStore.cacheKey(id: "pack.../../évil/name", build: "1 (2)", modified: nil)] {
            XCTAssertFalse(key.contains("/"), key)
            XCTAssertTrue(key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }, key)
            XCTAssertLessThan(key.count, 160)
        }
    }

    @MainActor
    func testTheStoreMakesSavesReloadsAndSweepsPictures() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lens-thumbs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stale = folder.appendingPathComponent("aura--b9--r1.png")
        try Data([1, 2, 3]).write(to: stale)

        let info = try XCTUnwrap(LensCatalog.info(for: "aura"))
        let store = LensThumbnailStore(directory: folder, build: "77")
        XCTAssertNil(store.cached(info))
        let made = await store.image(for: info)
        XCTAssertEqual(made.map { Int($0.size.width) }, 320)
        XCTAssertEqual(made.map { Int($0.size.height) }, 180)
        XCTAssertNotNil(store.cached(info), "kept in memory")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: info).path), "saved as a PNG")
        XCTAssertTrue(store.fileURL(for: info).path.contains("/lens-thumbs-"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "a picture from another build is swept away")

        // A fresh store (a new launch) reads it from disk, quickly, without making it again.
        let again = LensThumbnailStore(directory: folder, build: "77")
        let started = CFAbsoluteTimeGetCurrent()
        let loaded = await again.image(for: info)
        XCTAssertNotNil(loaded)
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - started, 0.25, "loading from disk doesn't run the lens")
    }

    @MainActor
    func testACardThatGoesAwayWithdrawsItsRequest() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lens-thumbs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LensThumbnailStore(directory: folder, build: "1", concurrency: 1)
        let lenses = Array(LensCatalog.all.prefix(6))
        let tasks = lenses.map { info in Task { await store.image(for: info) } }
        try await Task.sleep(for: .milliseconds(50))
        for task in tasks.dropFirst() { task.cancel() }
        let first = await tasks[0].value
        XCTAssertNotNil(first)
        for task in tasks.dropFirst() { _ = await task.value }
        try await Task.sleep(for: .milliseconds(300))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        XCTAssertLessThanOrEqual(files.filter { $0.hasSuffix(".png") }.count, 2, "withdrawn pictures aren't made: \(files)")
        XCTAssertEqual(store.outstanding, 0)
    }

    func testTheQueueNeverRunsMoreThanTwoAndOnlyOneWhileTheCameraIsOn() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lens-thumbs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = LensThumbnailQueue(directory: folder, build: "1", concurrency: 2)
        let lenses = Array(LensCatalog.all.filter { $0.category == .filters }.prefix(6))
        let done = expectation(description: "all made")
        done.expectedFulfillmentCount = lenses.count
        for info in lenses { queue.enqueue(key: "k-\(info.id)", info: info) { _ in done.fulfill() } }
        wait(for: [done], timeout: 60)
        XCTAssertEqual(queue.peakRunning, 2, "two at a time")

        let busy = LensThumbnailQueue(directory: folder, build: "1", concurrency: 2)
        busy.setBusy(true)
        let slow = expectation(description: "made one at a time")
        slow.expectedFulfillmentCount = 3
        for info in lenses.prefix(3) { busy.enqueue(key: "b-\(info.id)", info: info) { _ in slow.fulfill() } }
        wait(for: [slow], timeout: 60)
        XCTAssertEqual(busy.peakRunning, 1, "one at a time while the camera is on")
    }

    @MainActor
    func testRecentLensesAreNewestFirstWithoutRepeatsAndKept() {
        let suite = "lens-browser-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let recents = LensBrowserRecents(defaults: defaults)
        for id in ["a", "b", "c", "a"] { recents.note(id) }
        XCTAssertEqual(recents.ids, ["a", "c", "b"])
        for i in 0..<20 { recents.note("x\(i)") }
        XCTAssertEqual(recents.ids.count, LensBrowserRecents.limit)
        XCTAssertEqual(recents.ids.first, "x19")
        XCTAssertEqual(LensBrowserRecents(defaults: defaults).ids, recents.ids, "kept between launches")
        recents.forget("x19")
        XCTAssertFalse(recents.ids.contains("x19"))
    }
}

// MARK: - Thumbnails

final class LensBrowserThumbnailTests: XCTestCase {
    private static func samplePacks() throws -> (infos: [LensInfo], folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lens-browser-samples-\(UUID().uuidString)", isDirectory: true)
        try SampleLenses.install(into: folder)
        return (LensPackFolder.scan(folder).packs.map(LensPackFolder.info), folder)
    }

    func testTheMannequinsFaceIsWhereItSaysItIs() {
        let renderer = LensBrowserRenderer()
        let pose = LensBrowserPose(smile: 0.5)
        let face = LensBrowserMannequin.face(for: pose)
        XCTAssertEqual(face.interocular, 84 * LensBrowserMannequin.scale, accuracy: 0.01)
        XCTAssertEqual(face.roll, 0, accuracy: 1e-9)
        guard let picture = renderer.picture(renderer.plain(pose), size: LensBrowserMannequin.size) else { return XCTFail("no picture") }
        let width = picture.width, height = picture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        func brightness(_ p: CGPoint) -> Int {
            let i = ((height - 1 - Int(p.y)) * width + Int(p.x)) * 4
            return (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
        }
        for eye in [face.leftEye, face.rightEye] { XCTAssertLessThan(brightness(eye), 100, "an iris is drawn where the eye is reported") }
        XCTAssertGreaterThan(brightness(CGPoint(x: face.eyeCenter.x, y: face.eyeCenter.y - 30)), 150, "skin between the eyes")
        XCTAssertLessThan(brightness(CGPoint(x: face.mouth.x, y: face.mouth.y + 4)), 160, "lips at the mouth")

        // Leaning tips the face and its report together.
        let leaning = LensBrowserMannequin.face(for: LensBrowserPose(lean: 0.2))
        XCTAssertEqual(leaning.roll, 0.2, accuracy: 1e-6)
        XCTAssertEqual(leaning.interocular, face.interocular, accuracy: 0.01)
    }

    /// Every lens, the user's sample lenses included: a picture of the right size, not blank, not the plain mannequin, and not
    /// the same as any other lens's; all of them made, two at a time, in a reasonable time.
    func testEveryLensGetsItsOwnPictureInTime() throws {
        let packs = try Self.samplePacks()
        defer { try? FileManager.default.removeItem(at: packs.folder) }
        let lenses = LensCatalog.all + packs.infos
        XCTAssertGreaterThanOrEqual(packs.infos.count, 15)

        // Best scores are put back after a game is tried on.
        let scoreKeys = lenses.filter(\.scored).map { "backdrop.best.\($0.id)" }
        let scoresBefore = scoreKeys.map { UserDefaults.standard.object(forKey: $0) as? Int }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lens-thumbs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = LensThumbnailQueue(directory: folder, build: "test", concurrency: 2)
        let lock = NSLock()
        var pictures: [String: CGImage] = [:]
        let done = expectation(description: "every picture")
        done.expectedFulfillmentCount = lenses.count
        let started = CFAbsoluteTimeGetCurrent(), cpuStarted = LensBrowserPixels.processCPUSeconds()
        for info in lenses {
            queue.enqueue(key: LensThumbnailStore.cacheKey(id: info.id, build: "test", modified: info.modified), info: info) { picture in
                lock.withLock { pictures[info.id] = picture }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 600)
        let took = CFAbsoluteTimeGetCurrent() - started, cpu = LensBrowserPixels.processCPUSeconds() - cpuStarted
        // The work itself (processor time, which other people's builds on this Mac don't inflate much), and a generous wall-clock
        // limit that only catches something stuck: the pictures ask the GPU for low priority, so a busy machine slows them down.
        XCTAssertLessThan(cpu / Double(lenses.count), 0.8, "\(String(format: "%.1f", cpu)) s of processor time for \(lenses.count) lenses")
        XCTAssertLessThan(took / Double(lenses.count), 5, "\(String(format: "%.1f", took)) s for \(lenses.count) lenses")
        print("LENSBROWSER made \(lenses.count) thumbnails in \(String(format: "%.1f", took)) s, two at a time, \(String(format: "%.1f", cpu)) s of processor time")

        let renderer = LensBrowserRenderer()
        let (w, h) = (128, 72)
        let plains = [renderer.picture(renderer.plain()), renderer.picture(renderer.plain(setting: .room))].compactMap { $0 }
            .map { LensBrowserPixels.tiny($0, width: w, height: h) }
        var tinies: [(String, [UInt8])] = []
        var leastChange = (Double.infinity, "")
        for info in lenses {
            guard let picture = pictures[info.id] else { XCTFail("\(info.id): no picture"); continue }
            XCTAssertEqual(picture.width, 320, info.id)
            XCTAssertEqual(picture.height, 180, info.id)
            let tiny = LensBrowserPixels.tiny(picture, width: w, height: h)
            XCTAssertGreaterThan(LensBrowserPixels.spread(tiny), 8, "\(info.id): the picture isn't blank")
            let change = plains.map { LensBrowserPixels.patchDifference(tiny, $0, width: w, height: h) }.min() ?? 0
            if change < leastChange.0 { leastChange = (change, info.id) }
            XCTAssertGreaterThan(change, 12, "\(info.id): the lens shows in its picture")
            tinies.append((info.id, tiny))
        }
        var closest = (Double.infinity, "", "")
        for i in 0..<tinies.count {
            for j in (i + 1)..<tinies.count {
                let d = LensBrowserPixels.patchDifference(tinies[i].1, tinies[j].1, width: w, height: h)
                if d < closest.0 { closest = (d, tinies[i].0, tinies[j].0) }
                XCTAssertGreaterThan(d, 12, "\(tinies[i].0) and \(tinies[j].0) look the same")
            }
        }
        print("LENSBROWSER least changed: \(leastChange.1) by \(String(format: "%.1f", leastChange.0)); closest pair: \(closest.1) / \(closest.2) differ by \(String(format: "%.1f", closest.0))")

        let scoresAfter = scoreKeys.map { UserDefaults.standard.object(forKey: $0) as? Int }
        XCTAssertEqual(scoresAfter, scoresBefore, "trying a game on for its picture doesn't touch the best scores")
    }

    func testAGameOverDuringFilmingKeepsAnEarlierPictureAndPutsTheScoreBack() throws {
        let id = "lens-browser-test-game"
        let info = LensInfo(id: id, name: "Test", glyph: "🧪", blurb: "Ends in a second.", category: .games, scored: true, needsFace: false) {
            GameLens<LensBrowserTestGame>(id: id, needs: [.matte])
        }
        let key = "backdrop.best.\(id)"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let renderer = LensBrowserRenderer()
        let session = LensBrowserRenderer.Session(info: info, renderer: renderer)
        session.skipToPlay()
        XCTAssertEqual(session.game?.lensBrowserIsPlaying, true, "two long frames get a game past its countdown")

        let picture = try XCTUnwrap(renderer.thumbnail(for: info))
        XCTAssertNil(UserDefaults.standard.object(forKey: key), "the score the game wrote down when it ended is taken back")
        // The picture is from play (the game paints a green square in the middle), not the game-over screen.
        let tiny = LensBrowserPixels.tiny(picture, width: 32, height: 18)
        let middle = ((9 * 32) + 16) * 4
        XCTAssertGreaterThan(Int(tiny[middle + 1]), Int(tiny[middle]) + 80, "kept a picture from before the end")
    }

    func testTheLivePreviewPlaysAndStops() async throws {
        let info = try XCTUnwrap(LensCatalog.info(for: "snow"))
        let player = await LensBrowserLivePlayer()
        await player.play(info)
        var frame: CGImage?
        for _ in 0..<60 where frame == nil {
            try await Task.sleep(for: .milliseconds(100))
            frame = await player.frame
        }
        XCTAssertEqual(frame?.width, Int(LensBrowserLivePlayer.size.width))
        await player.stop()
        let stopped = await player.frame
        XCTAssertNil(stopped)
    }
}

/// A game that scores 99 and ends after a second, painting a green square while it plays.
struct LensBrowserTestGame: Game {
    static var title: String { "Test" }
    static var hint: String { "Wait" }
    private(set) var score = 0
    private var elapsed = 0.0
    var isOver: Bool { elapsed > 1.0 }
    var summary: String { "" }

    init(size: CGSize, seed: UInt64) {}

    mutating func step(_ dt: Double, world: GameWorld) {
        elapsed += dt
        score = 99
    }

    func draw(in ctx: CGContext, time: Double) {
        ctx.setFillColor(CGColor(red: 0.1, green: 0.9, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 440, y: 160, width: 400, height: 400))
    }
}

final class LensBrowserCacheTidyTests: XCTestCase {
    func testAnEditedLensLeavesNoOldPictureBehind() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lens-thumbs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = LensThumbnailQueue(directory: folder, build: "5", concurrency: 1)
        let info = try XCTUnwrap(LensCatalog.info(for: "comic"))
        let old = LensThumbnailStore.cacheKey(id: "pack.My Lens", build: "5", modified: Date(timeIntervalSince1970: 1))
        let new = LensThumbnailStore.cacheKey(id: "pack.My Lens", build: "5", modified: Date(timeIntervalSince1970: 2))
        let other = LensThumbnailStore.cacheKey(id: "pack.My_Lens", build: "5", modified: Date(timeIntervalSince1970: 1))
        for key in [old, other] {
            let done = expectation(description: key)
            queue.enqueue(key: key, info: info) { _ in done.fulfill() }
            wait(for: [done], timeout: 60)
        }
        let done = expectation(description: "edited")
        queue.enqueue(key: new, info: info) { _ in done.fulfill() }
        wait(for: [done], timeout: 60)
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        XCTAssertEqual(files, [new + ".png", other + ".png"], "the edited lens's old picture is gone; a different lens's is kept")
    }
}
