import AppKit
import SwiftUI
import XCTest

/// The picker drawn offscreen with ImageRenderer, in dark and light, with no lenses, a few and a great many, saved for looking at
/// and measured: nothing in the popover may be wider than the popover.
@MainActor
final class LensBrowserViewTests: XCTestCase {
    private static let popoverWidth: CGFloat = 380
    private static let padding: CGFloat = 14
    private static var content: CGFloat { popoverWidth - padding * 2 }

    /// Real pictures of every built-in lens, made once for all the tests here.
    private static var pictures: [String: NSImage] = [:]

    private func store(for lenses: [LensInfo]) -> LensThumbnailStore {
        if Self.pictures.isEmpty {
            let renderer = LensBrowserRenderer()
            for info in LensCatalog.all {
                if let picture = renderer.thumbnail(for: info) {
                    Self.pictures[info.id] = NSImage(cgImage: picture, size: NSSize(width: 320, height: 180))
                }
            }
        }
        let store = LensThumbnailStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("lens-browser-view-\(UUID().uuidString)"),
                                       build: "view-test")
        for info in lenses {
            let source = info.id.components(separatedBy: "~").first ?? info.id
            if let picture = Self.pictures[source] { store.remember(picture, for: info) }
        }
        return store
    }

    /// The catalog, then copies with longer and longer names, up to `count`.
    private func lenses(_ count: Int) -> [LensInfo] {
        let all = LensCatalog.all
        return (0..<count).map { i in
            let base = all[i % all.count]
            guard i >= all.count else { return base }
            let name = i % 7 == 0 ? "An Extraordinarily Long Lens Name Number \(i)" : "\(base.name) \(i / all.count + 1)"
            var copy = LensInfo(id: "\(base.id)~\(i)", name: name, glyph: base.glyph, blurb: base.blurb, category: base.category,
                                scored: base.scored, needsFace: base.needsFace, make: base.make)
            copy.needsHands = base.needsHands
            return copy
        }
    }

    // MARK: Drawing

    /// Renders a view at its own size, at 2x, as the popover would show it in dark or light, and returns its size in points.
    @discardableResult
    private func render<V: View>(_ view: V, dark: Bool, name: String, background: Bool = true, width: CGFloat? = nil) -> CGSize {
        // The popover's own colour behind it; `background` false draws the view alone, at its own size, with no margin.
        let framed = view
            .padding(background ? Self.padding : 0)
            .background(dark ? Color(red: 0.16, green: 0.16, blue: 0.18) : Color(red: 0.93, green: 0.93, blue: 0.94))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        if let width { renderer.proposedSize = ProposedViewSize(width: width, height: nil) }
        var image: CGImage?
        (NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            image = renderer.cgImage
        }
        guard let image else { XCTFail("\(name) didn't render"); return .zero }
        LensBrowserOutput.save(image, as: "browser/ui/\(name)-\(dark ? "dark" : "light").png")
        return CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
    }

    private func popover(_ data: LensBrowserData, store: LensThumbnailStore, tab: LensBrowserTab? = nil, group: String? = nil, query: String = "") -> some View {
        LensBrowserPopover(data: data, store: store, width: Self.content, snapshot: true, tab: tab, group: group, query: query)
    }

    // MARK: Tests

    func testThePopoverPickerFitsThePopoverWithNoneAFewAndAGreatManyLenses() {
        for (count, label) in [(0, "none"), (5, "five"), (200, "many")] {
            let list = lenses(count)
            let store = store(for: list)
            var data = LensBrowserData(lenses: list, favourites: Set(list.prefix(3).map(\.id)), recents: list.dropFirst(2).prefix(5).map(\.id))
            if count > 4 { data.selectedID = list[min(4, count - 1)].id }
            for dark in [true, false] {
                let size = render(popover(data, store: store), dark: dark, name: "popover-\(label)")
                XCTAssertLessThanOrEqual(size.width, Self.popoverWidth, "\(label): the popover would grow")
                XCTAssertEqual(size.width, Self.popoverWidth, accuracy: 0.5)
                // And the picker on its own, at its natural size, is exactly as wide as it was given.
                XCTAssertEqual(render(popover(data, store: store), dark: dark, name: "bare-\(label)", background: false).width, Self.content, accuracy: 0.5)
            }
        }
    }

    func testEveryTabShelfAndSearchKeepsToTheWidthAndTheSameHeight() {
        let list = lenses(200)
        let store = store(for: list)
        let data = LensBrowserData(lenses: list, favourites: ["aura", "crown", "breakout", "scene-jungle"], recents: ["snow", "cat", "fruit-slash"],
                                   selectedID: "crown")
        var heights: Set<Int> = []
        var states: [(LensBrowserTab, String?, String, String)] = [(.saved, nil, "", "saved")]
        for category in data.categories {
            states.append((.category(category), nil, "", "tab-\(category.rawValue)"))
            for group in LensBrowserGroups.sections(list, in: category).map(\.group) {
                states.append((.category(category), group, "", "shelf-\(category.rawValue)-\(group)"))
            }
        }
        states += [(.saved, nil, "hand", "search-hand"), (.saved, nil, "qqqq", "search-nothing")]
        for (tab, group, query, name) in states {
            let file = name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "&", with: "and")
            let size = render(popover(data, store: store, tab: tab, group: group, query: query), dark: true, name: file, background: false)
            XCTAssertEqual(size.width, Self.content, accuracy: 0.5, name)
            heights.insert(Int(size.height.rounded()))
        }
        XCTAssertEqual(heights.count, 1, "the picker keeps one height whatever it shows, so the popover doesn't jump: \(heights)")
        render(popover(data, store: store, tab: .category(.filters)), dark: false, name: "tab-Filters-light-check", background: true)
    }

    func testCardsTabsAndChipsNeverGrowWithLongWords() {
        let store = store(for: [])
        let long = LensInfo(id: "long", name: String(repeating: "Supercalifragilistic ", count: 4), glyph: "🦄", blurb: String(repeating: "Very long words. ", count: 12),
                            category: .games, scored: true, needsFace: true) { MirrorLens() }
        let card = LensBrowserStyle.cardWidth(for: Self.content)
        for dark in [true, false] {
            let size = render(LensBrowserCard(info: long, store: store, selected: true, favourite: true).frame(width: card), dark: dark, name: "card-long", background: false)
            XCTAssertEqual(size.width, card, accuracy: 0.5)
            XCTAssertEqual(size.height, LensBrowserStyle.rowHeight(for: Self.content), accuracy: 1, "a long name stays on one line")
        }
        let tabs = LensBrowserTabs(tabs: [.saved] + LensInfo.Category.allCases.map { .category($0) }, selection: .constant(.category(.custom)), width: Self.content)
        XCTAssertEqual(render(tabs, dark: true, name: "tabs", background: false).width, Self.content, accuracy: 0.5)
        let chips = LensBrowserChips(groups: ["Looks", "Weather & Light", "Hands", "Something Rather Long", "Another Long Shelf", "More"],
                                     selection: .constant("Hands"), width: Self.content, snapshot: true)
        XCTAssertEqual(render(chips, dark: true, name: "chips", background: false).width, Self.content, accuracy: 0.5)
    }

    func testTheStudioGridAndDetailPanel() throws {
        let list = LensCatalog.all
        let store = store(for: list)
        let data = LensBrowserData(lenses: list, favourites: ["aura", "crown", "breakout"], recents: ["snow", "fruit-slash"], selectedID: "fruit-slash",
                                   bestScore: { $0 == "fruit-slash" ? 42 : 0 })
        for dark in [true, false] {
            render(LensBrowserStudioGrid(data: data, store: store, tab: .category(.games), query: "", focusedID: .constant("fruit-slash"), snapshot: true)
                .frame(width: 640), dark: dark, name: "studio-games")
            render(LensBrowserStudioGrid(data: data, store: store, tab: .saved, query: "", focusedID: .constant(nil), snapshot: true)
                .frame(width: 640), dark: dark, name: "studio-saved")
            let info = try XCTUnwrap(list.first { $0.id == "fruit-slash" })
            let detail = LensBrowserDetail(info: info, data: data, status: LensStatus("Score 12", detail: "♥♥♥ · Best 42"), cameraOn: true) {
                LensBrowserThumbnail(info: info, store: store, radius: 0)
            }
            render(detail.frame(width: 320), dark: dark, name: "studio-detail")
            let face = try XCTUnwrap(list.first { $0.id == "dress-wizard" })
            render(LensBrowserDetail(info: face, data: data) { LensBrowserThumbnail(info: face, store: store, radius: 0) }.frame(width: 320),
                   dark: dark, name: "studio-detail-face")
        }
        render(LensBrowserStudioGrid(data: data, store: store, tab: .all, query: "zzz", focusedID: .constant(nil), snapshot: true).frame(width: 640, height: 200),
               dark: true, name: "studio-search-empty")
    }

    func testThePopoverOpensWhereItIsUseful() {
        let list = LensCatalog.all
        XCTAssertEqual(LensBrowserPopover.startingTab(LensBrowserData(lenses: list, selectedID: "breakout")), .category(.games))
        XCTAssertEqual(LensBrowserPopover.startingTab(LensBrowserData(lenses: list, favourites: ["aura"])), .saved)
        XCTAssertEqual(LensBrowserPopover.startingTab(LensBrowserData(lenses: list)), .category(.filters))
        XCTAssertEqual(LensBrowserPopover.startingTab(LensBrowserData(lenses: [])), .saved)
        // Recent leaves out what is already a favourite, and anything that has gone.
        let data = LensBrowserData(lenses: list, favourites: ["aura"], recents: ["aura", "gone-lens", "snow"])
        XCTAssertEqual(data.recentLenses.map(\.id), ["snow"])
    }
}
