import XCTest

/// What Present saves, and what older versions saved, must keep loading.
final class StageCodableTests: XCTestCase {
    func testOldSavedWindowsAndScreensStillDecode() throws {
        // Exactly what versions before Present wrote.
        let old = """
        [{"id":"33333333-3333-3333-3333-333333333333","name":"Screen","kind":{"display":{}},"origin":"imported","parallax":false,"createdAt":0},
         {"id":"55555555-5555-5555-5555-555555555555","name":"Keynote","kind":{"window":{"bundleID":"com.apple.iWork.Keynote","title":"Roadmap"}},"origin":"imported","parallax":false,"createdAt":0},
         {"id":"66666666-6666-6666-6666-666666666666","name":"Terminal","kind":{"window":{"bundleID":"com.apple.Terminal"}},"origin":"imported","parallax":true,"createdAt":0}]
        """
        let items = try JSONDecoder().decode([Background].self, from: Data(old.utf8))
        XCTAssertEqual(items[0].kind, .display)
        XCTAssertEqual(items[1].kind, .window(bundleID: "com.apple.iWork.Keynote", title: "Roadmap", windowID: nil))
        XCTAssertEqual(items[2].kind, .window(bundleID: "com.apple.Terminal", title: nil))
        XCTAssertTrue(items.allSatisfy(\.isScreenShare))
        XCTAssertTrue(items[2].parallax)
    }

    func testTheNewKindsRoundTrip() throws {
        for kind in [BackgroundKind.window(bundleID: "com.apple.Safari", title: "Docs", windowID: 4242), .screen(displayID: 69_733_382), .display] {
            let again = try JSONDecoder().decode(BackgroundKind.self, from: JSONEncoder().encode(kind))
            XCTAssertEqual(again, kind)
        }
    }

    @MainActor
    func testTheLibraryPicksAWindowOrScreenAgainRatherThanAddingACopy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = BackgroundLibrary(directory: folder)
        let a = library.addWindow(bundleID: "com.apple.Safari", appName: "Safari", title: "Docs", windowID: 7)
        let b = library.addWindow(bundleID: "com.apple.Safari", appName: "Safari", title: "Docs", windowID: 7)
        XCTAssertEqual(a.id, b.id)
        let s1 = library.addDisplay(displayID: 2, name: "LG UltraFine")
        let s2 = library.addDisplay(displayID: 2)
        XCTAssertEqual(s1.id, s2.id)
        XCTAssertEqual(s1.name, "LG UltraFine")
        XCTAssertEqual(BackgroundLibrary(directory: folder).userItems.count, 2, "and it is saved")
    }

    func testALayoutRoundTripsAndAMissingSettingTakesItsDefault() throws {
        var layout = StagePreset.sideBySide.apply(to: StageLayout())
        layout.surround = .backdrop
        layout.surroundBackdrop = UUID()
        layout.handControl = true
        layout.restorePanel = StageFrame(center: CGPoint(x: 0.2, y: 0.3), size: 0.4)
        XCTAssertEqual(try JSONDecoder().decode(StageLayout.self, from: JSONEncoder().encode(layout)), layout)

        // A save from a version that had fewer settings, or none at all.
        let partial = try JSONDecoder().decode(StageLayout.self, from: Data(#"{"arrangement":"floatingPanel","tilt":0.9}"#.utf8))
        XCTAssertEqual(partial.arrangement, .floatingPanel)
        XCTAssertEqual(partial.tilt, 0.9)
        XCTAssertEqual(partial.shadow, StageLayout().shadow)
        XCTAssertEqual(try JSONDecoder().decode(StageLayout.self, from: Data("{}".utf8)), StageLayout())
        // Nonsense is brought into range, not trusted.
        let wild = try JSONDecoder().decode(StageLayout.self, from: Data(#"{"panel":{"center":[9,-3],"size":40},"tilt":7}"#.utf8))
        XCTAssertEqual(wild.panel.size, StageLayout.panelSizes.upperBound)
        XCTAssertEqual(wild.tilt, 1)
        XCTAssertEqual(wild.panel.center, CGPoint(x: 1, y: 0))
    }

    func testEachArrangementRemembersItsOwnPlacesButSharesTheLook() {
        var memory = StageMemory()
        memory.switchTo(.floatingPanel)
        var moved = memory.current
        moved.panel.center = CGPoint(x: 0.7, y: 0.6)
        moved.shadow = 0.95
        memory.update(moved)
        memory.switchTo(.presenter)
        XCTAssertEqual(memory.current.arrangement, .presenter)
        XCTAssertEqual(memory.current.shadow, 0.95, "the look carries over")
        memory.switchTo(.floatingPanel)
        XCTAssertEqual(memory.current.panel.center, CGPoint(x: 0.7, y: 0.6), "the panel is where it was left")
        let again = try? JSONDecoder().decode(StageMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(again, memory)
    }

    func testEveryPresetIsRecognisedOnceApplied() {
        for preset in StagePreset.allCases {
            let l = preset.apply(to: StageLayout())
            XCTAssertTrue(preset.matches(l), preset.title)
            for other in StagePreset.allCases where other != preset {
                XCTAssertFalse(other.matches(l), "\(preset.title) is not \(other.title)")
            }
        }
    }
}
