import CoreGraphics
import XCTest

/// Sharing a window has to keep working when the app goes full screen. An app that has gone full screen is on a desktop of its own, so
/// from Backdrop's desktop it is "not on screen": it keeps its window id and can still be captured, but a lookup that only looks at what
/// is on screen can no longer find it, to list it or to pick it up again.
final class WindowDiscoveryTests: XCTestCase {
    /// Two screens side by side, the way macOS puts their frames: the second to the left of the main one.
    private let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let left = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
    private var screens: [CGRect] { [main, left] }

    private func window(_ id: CGWindowID, _ bundle: String = "com.example.Slides", title: String = "Deck", frame: CGRect = CGRect(x: 300, y: 200, width: 1200, height: 800),
                        layer: Int = 0, onScreen: Bool = true, regular: Bool = true) -> WindowFacts {
        WindowFacts(id: id, bundleID: bundle, appName: "Slides", title: title, frame: frame, layer: layer, onScreen: onScreen, regularApp: regular)
    }

    // MARK: Full screen

    func testAWindowTheSizeOfTheScreenIsFullScreen() {
        XCTAssertTrue(WindowFinder.fillsAScreen(main, screens: screens), "an app that went full screen")
        XCTAssertTrue(WindowFinder.fillsAScreen(CGRect(x: 0, y: 30, width: 2560, height: 1410), screens: screens), "a window stretched under the menu bar")
        XCTAssertTrue(WindowFinder.fillsAScreen(left, screens: screens), "on the other screen")
        // A laptop screen with a notch: the app is laid out below it.
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertTrue(WindowFinder.fillsAScreen(CGRect(x: 0, y: 38, width: 1512, height: 944), screens: [laptop]))
    }

    func testAnOrdinaryWindowIsNotFullScreen() {
        XCTAssertFalse(WindowFinder.fillsAScreen(CGRect(x: 300, y: 200, width: 1200, height: 800), screens: screens))
        XCTAssertFalse(WindowFinder.fillsAScreen(CGRect(x: 0, y: 0, width: 1280, height: 1440), screens: screens), "half the width")
        XCTAssertFalse(WindowFinder.fillsAScreen(CGRect(x: 0, y: 700, width: 2560, height: 700), screens: screens), "full width but not tall")
        XCTAssertFalse(WindowFinder.fillsAScreen(CGRect(x: 100, y: 0, width: 2560, height: 1440), screens: [main]), "shifted off the screen")
    }

    // MARK: What the picker offers

    func testWhatIsOnThisDesktopIsOfferedAsBefore() {
        let shown = WindowFinder.listable([window(1), window(2, layer: 25), window(3, frame: CGRect(x: 0, y: 0, width: 120, height: 90)),
                                           window(4, "com.example.Backdrop")], screens: screens, excluding: "com.example.Backdrop")
        XCTAssertEqual(shown.map(\.id), [1], "no menus or tiny windows, and not Backdrop's own")
    }

    func testAFullScreenAppOnAnotherDesktopIsOffered() {
        let fullScreen = window(7, frame: main, onScreen: false)
        let shown = WindowFinder.listable([window(1), fullScreen], screens: screens, excluding: nil)
        XCTAssertEqual(shown.map(\.id), [1, 7])
    }

    func testHiddenWindowsAreNotOffered() {
        let shown = WindowFinder.listable([
            window(1, onScreen: false),                                            // hidden, or minimised, or on another desktop
            window(2, frame: main, onScreen: false, regular: false),               // a helper that happens to cover a screen
            window(3, frame: main, layer: 3, onScreen: false),                     // not an ordinary window
        ], screens: screens, excluding: nil)
        XCTAssertTrue(shown.isEmpty, "\(shown)")
    }

    // MARK: Picking the window again

    func testTheWindowIsFoundAfterTheAppGoesFullScreen() {
        // It had an id when it was shared; going full screen moved it to another desktop and kept the id.
        let before = window(9, onScreen: true)
        let after = window(9, frame: main, onScreen: false)
        XCTAssertEqual(WindowFinder.pick(bundleID: "com.example.Slides", title: "Deck", windowID: 9, among: [before], screens: screens)?.id, 9)
        XCTAssertEqual(WindowFinder.pick(bundleID: "com.example.Slides", title: "Deck", windowID: 9, among: [after], screens: screens)?.id, 9,
                       "found on the other desktop, so a restart or a retry gets it back")
    }

    func testTheSameWindowIsPreferredToABiggerOne() {
        let wanted = window(9, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let bigger = window(10, title: "Other", frame: CGRect(x: 0, y: 0, width: 2000, height: 1300))
        XCTAssertEqual(WindowFinder.pick(bundleID: "com.example.Slides", title: nil, windowID: 9, among: [bigger, wanted], screens: screens)?.id, 9)
    }

    func testAWindowThatIsGoneIsReplacedByOneWithItsTitleOrTheLargest() {
        let deck = window(1, title: "Quarterly deck")
        let notes = window(2, title: "Notes", frame: CGRect(x: 0, y: 0, width: 1800, height: 1100))
        XCTAssertEqual(WindowFinder.pick(bundleID: "com.example.Slides", title: "quarterly", windowID: 99, among: [notes, deck], screens: screens)?.id, 1)
        XCTAssertEqual(WindowFinder.pick(bundleID: "com.example.Slides", title: "No such title", windowID: 99, among: [deck, notes], screens: screens)?.id, 2)
        XCTAssertEqual(WindowFinder.pick(bundleID: "com.example.Slides", title: "", windowID: nil, among: [deck, notes], screens: screens)?.id, 2, "an empty title names nothing")
    }

    func testWhatIsOnThisDesktopComesBeforeAFullScreenWindowElsewhere() {
        let here = window(1, frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let there = window(2, frame: main, onScreen: false)
        XCTAssertEqual(WindowFinder.pick(bundleID: "com.example.Slides", title: nil, windowID: 99, among: [there, here], screens: screens)?.id, 1)
        XCTAssertEqual(WindowFinder.pick(bundleID: "com.example.Slides", title: nil, windowID: 99, among: [there], screens: screens)?.id, 2,
                       "and when nothing is on this desktop, the full-screen one is what is left of the app")
    }

    func testAHiddenWindowIsNotMistakenForTheReplacement() {
        let hidden = [window(1, onScreen: false), window(2, frame: main, layer: 4, onScreen: false)]
        XCTAssertNil(WindowFinder.pick(bundleID: "com.example.Slides", title: nil, windowID: 99, among: hidden, screens: screens))
        XCTAssertNil(WindowFinder.pick(bundleID: "com.example.Other", title: nil, windowID: nil, among: [window(5)], screens: screens), "another app's window")
    }
}
