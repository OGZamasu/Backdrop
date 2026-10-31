import AppKit
import SwiftUI

// The lens picker's views, shared by the menu bar popover and the Studio. They know nothing of the app model: they are handed
// the lenses and what to do when one is picked, so tests can draw them offscreen and look at them.

/// What the picker shows.
struct LensBrowserData {
    var lenses: [LensInfo]
    var favourites: Set<String> = []
    /// Lens ids, newest first.
    var recents: [String] = []
    var selectedID: String?
    var bestScore: (String) -> Int = { _ in 0 }

    var categories: [LensInfo.Category] { LensInfo.Category.allCases.filter { c in lenses.contains { $0.category == c } } }
    var favouriteLenses: [LensInfo] { lenses.filter { favourites.contains($0.id) } }
    /// Lenses used lately that aren't already among the favourites.
    var recentLenses: [LensInfo] {
        recents.filter { !favourites.contains($0) }.compactMap { id in lenses.first { $0.id == id } }
    }
    var selected: LensInfo? { selectedID.flatMap { id in lenses.first { $0.id == id } } }
}

/// What the picker can do.
struct LensBrowserActions {
    var select: (String?) -> Void = { _ in }
    var toggleFavourite: (String) -> Void = { _ in }
    /// For lenses from the Lenses folder.
    var reveal: ((LensInfo) -> Void)? = nil
    var trash: ((LensInfo) -> Void)? = nil
}

/// The picker's measurements, kept in one place so the popover and the Studio stay one family.
enum LensBrowserStyle {
    static let popoverWidth: CGFloat = 352
    static let columns = 3
    static let spacing: CGFloat = 8
    static let thumbRadius: CGFloat = 8
    static let largeRadius: CGFloat = 10
    static let panelRadius: CGFloat = 12
    static let captionHeight: CGFloat = 14
    static let headerHeight: CGFloat = 16
    static let barHeight: CGFloat = 26
    static let chipHeight: CGFloat = 22

    static func cardWidth(for width: CGFloat) -> CGFloat { ((width - spacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down) }
    static func rowHeight(for width: CGFloat) -> CGFloat { (cardWidth(for: width) * 9 / 16).rounded() + 4 + captionHeight }
    /// Two rows and a heading, then it scrolls.
    static func gridHeight(for width: CGFloat) -> CGFloat { headerHeight + 6 + rowHeight(for: width) * 2 + spacing + 4 }

    /// A soft wash behind a lens's emoji while its picture is being made, tinted by category.
    static func wash(for category: LensInfo.Category) -> [Color] {
        switch category {
        case .filters: return [Color(red: 0.36, green: 0.38, blue: 0.82), Color(red: 0.16, green: 0.14, blue: 0.40)]
        case .faces: return [Color(red: 0.96, green: 0.56, blue: 0.52), Color(red: 0.62, green: 0.24, blue: 0.40)]
        case .games: return [Color(red: 0.25, green: 0.70, blue: 0.62), Color(red: 0.08, green: 0.30, blue: 0.38)]
        case .scenes: return [Color(red: 0.98, green: 0.72, blue: 0.38), Color(red: 0.66, green: 0.30, blue: 0.22)]
        case .custom: return [Color(red: 0.55, green: 0.58, blue: 0.68), Color(red: 0.22, green: 0.24, blue: 0.32)]
        }
    }
}

// MARK: - Thumbnail and card

/// A lens's picture, or its emoji on a soft wash until the picture is ready.
struct LensBrowserThumbnail: View {
    let info: LensInfo
    let store: LensThumbnailStore
    var radius: CGFloat = LensBrowserStyle.thumbRadius
    @State private var image: NSImage?

    init(info: LensInfo, store: LensThumbnailStore, radius: CGFloat = LensBrowserStyle.thumbRadius) {
        self.info = info
        self.store = store
        self.radius = radius
        _image = State(initialValue: store.cached(info))
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: LensBrowserStyle.wash(for: info.category), startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { g in
                Text(info.glyph)
                    .font(.system(size: g.size.height * 0.42))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .frame(width: g.size.width, height: g.size.height)
            }
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill).transition(.opacity)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: store.cacheKey(for: info)) {
            let ready = store.cached(info)
            if ready != image { image = ready }
            guard ready == nil, let made = await store.image(for: info) else { return }
            withAnimation(.easeOut(duration: 0.25)) { image = made }
        }
    }
}

/// Small white marks in a dark capsule on a thumbnail: needs a hand, needs your face, keeps a score.
private struct LensBrowserBadges: View {
    let badges: [LensBrowserGroups.Badge]
    var size: CGFloat = 8

    var body: some View {
        if !badges.isEmpty {
            HStack(spacing: size * 0.5) {
                ForEach(badges, id: \.self) { Image(systemName: $0.symbol) }
            }
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, size * 0.6)
            .padding(.vertical, size * 0.45)
            .background(.black.opacity(0.5), in: Capsule())
            .padding(size * 0.5)
            .accessibilityHidden(true)
        }
    }
}

/// Shrinks a little while pressed.
struct LensBrowserPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// One lens: its picture and name, with its marks, a star when it is a favourite, and a ring when it is on.
struct LensBrowserCard: View {
    enum Size { case compact, large }

    let info: LensInfo
    let store: LensThumbnailStore
    var size: Size = .compact
    var selected = false
    var favourite = false
    var best = 0
    var action: () -> Void = {}
    var toggleFavourite: () -> Void = {}
    @State private var hovering = false

    private var radius: CGFloat { size == .compact ? LensBrowserStyle.thumbRadius : LensBrowserStyle.largeRadius }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: size == .compact ? 4 : 8) {
                LensBrowserThumbnail(info: info, store: store, radius: radius)
                    .overlay(alignment: .bottomLeading) { LensBrowserBadges(badges: LensBrowserGroups.badges(for: info), size: size == .compact ? 7.5 : 9.5) }
                    .overlay(alignment: .topLeading) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .font(.system(size: size == .compact ? 13 : 16, weight: .semibold))
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                .padding(size == .compact ? 4 : 6)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.35 : 0.10),
                                          lineWidth: selected ? 2.5 : (hovering ? 1.5 : 0.5))
                    }
                    .shadow(color: .black.opacity(hovering ? 0.22 : 0.10), radius: hovering ? 6 : 2, y: hovering ? 3 : 1)
                caption
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LensBrowserPressStyle())
        .overlay(alignment: .topTrailing) { star }
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .help(info.blurb)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var accessibilityText: String {
        var parts = [info.name, LensBrowserGroups.group(for: info)]
        parts += LensBrowserGroups.badges(for: info).map(\.label)
        if favourite { parts.append("Favourite") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var caption: some View {
        switch size {
        case .compact:
            Text(info.name)
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: LensBrowserStyle.captionHeight, maxHeight: LensBrowserStyle.captionHeight, alignment: .leading)
                .padding(.horizontal, 2)
        case .large:
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(info.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if info.scored, best > 0 {
                        Label("\(best)", systemImage: "trophy.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color(red: 0.85, green: 0.62, blue: 0.10))
                            .help("Your best score")
                    }
                }
                Text(info.blurb)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder private var star: some View {
        if favourite || hovering {
            Button(action: toggleFavourite) {
                Image(systemName: favourite ? "star.fill" : "star")
                    .font(.system(size: size == .compact ? 9 : 11, weight: .bold))
                    .foregroundStyle(favourite ? Color(red: 1, green: 0.80, blue: 0.20) : .white)
                    .frame(width: size == .compact ? 18 : 22, height: size == .compact ? 18 : 22)
                    .background(.black.opacity(0.45), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(LensBrowserPressStyle())
            .padding(size == .compact ? 4 : 6)
            .help(favourite ? "Remove from Favourites" : "Add to Favourites")
            .accessibilityLabel(favourite ? "Remove \(info.name) from favourites" : "Add \(info.name) to favourites")
            .transition(.opacity)
        }
    }
}

// MARK: - Bars

/// A place in the picker: the saved lenses, every lens (Studio), or one category.
enum LensBrowserTab: Hashable, Identifiable {
    case all, saved, category(LensInfo.Category)

    var id: String {
        switch self {
        case .all: return "all"
        case .saved: return "saved"
        case .category(let c): return c.rawValue
        }
    }

    var title: String {
        switch self {
        case .all: return "All"
        case .saved: return "Favourites"
        case .category(let c): return c.rawValue
        }
    }
}

/// Tabs of equal width, sized from a given width so nothing they say can make the bar (or the popover around it) any wider.
/// The saved tab is a narrow star. A segmented picker sizes itself to its labels and once pushed the whole popover out of shape.
struct LensBrowserTabs: View {
    let tabs: [LensBrowserTab]
    @Binding var selection: LensBrowserTab
    /// Nil to fill whatever width there is.
    var width: CGFloat?
    @Environment(\.colorScheme) private var scheme

    private static let starWidth: CGFloat = 30
    private static let inset: CGFloat = 2

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let selected = tab == selection
                Button { withAnimation(.easeOut(duration: 0.15)) { selection = tab } } label: { label(tab, selected: selected) }
                    .buttonStyle(.plain)
                    .help(tab == .saved ? "Favourites and recent lenses" : "")
                    .accessibilityLabel(tab == .saved ? "Favourites and recent" : tab.title)
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(Self.inset)
        .frame(width: width, height: LensBrowserStyle.barHeight)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lens type")
    }

    private var tabWidth: CGFloat? {
        guard let width else { return nil }
        let stars = CGFloat(tabs.filter { $0 == .saved }.count)
        let others = CGFloat(max(1, tabs.count - Int(stars)))
        return ((width - Self.inset * 2 - 2 * CGFloat(tabs.count - 1) - stars * Self.starWidth) / others).rounded(.down)
    }

    private func label(_ tab: LensBrowserTab, selected: Bool) -> some View {
        Group {
            if tab == .saved && width != nil {
                Image(systemName: selected ? "star.fill" : "star").font(.system(size: 11, weight: .semibold))
            } else {
                Text(tab == .saved ? "★ Favourites" : tab.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .frame(width: tab == .saved && width != nil ? Self.starWidth : tabWidth, height: LensBrowserStyle.barHeight - Self.inset * 2)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.17) : Color.white)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.12), radius: 1.5, y: 0.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The shelves of a category as a row of chips, "All" first. Scrolls sideways if they ever don't fit.
struct LensBrowserChips: View {
    let groups: [String]
    @Binding var selection: String?
    var width: CGFloat?
    var snapshot = false

    var body: some View {
        let row = HStack(spacing: 6) {
            chip(nil)
            ForEach(groups, id: \.self) { chip($0) }
        }
        .padding(.horizontal, 1)
        Group {
            if snapshot {
                row.frame(width: width, alignment: .leading).clipped()
            } else {
                ScrollView(.horizontal, showsIndicators: false) { row }
            }
        }
        .frame(width: width, height: LensBrowserStyle.chipHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shelves")
    }

    private func chip(_ group: String?) -> some View {
        let selected = group == selection
        return Button { withAnimation(.easeOut(duration: 0.15)) { selection = group } } label: {
            Text(group ?? "All")
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .frame(height: LensBrowserStyle.chipHeight - 2)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .background(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A rounded search field with a clear button. Escape clears it.
struct LensBrowserSearchField: View {
    @Binding var text: String
    var prompt = "Search lenses"
    /// Draws the field as plain text, for offscreen pictures, where a real text field can't be drawn.
    var snapshot = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            if snapshot {
                Text(text.isEmpty ? prompt : text).foregroundStyle(text.isEmpty ? Color.secondary.opacity(0.7) : Color.primary).lineLimit(1)
                Spacer(minLength: 0)
            } else {
                TextField(prompt, text: $text).textFieldStyle(.plain).focused($focused)
                    .accessibilityLabel("Search lenses")
            }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.10), lineWidth: focused ? 1.5 : 0.5)
        }
        .onExitCommand { text = "" }
    }
}

/// A heading over a shelf of lenses.
private struct LensBrowserShelfHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text("\(count)").font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .frame(height: LensBrowserStyle.headerHeight)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Said in the middle of an empty grid.
struct LensBrowserEmpty: View {
    let symbol: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shelves

/// A list of shelves, each a heading (or none) and its lenses.
struct LensBrowserShelf: Identifiable {
    var title: String?
    var lenses: [LensInfo]
    var id: String { title ?? "all" }
}

enum LensBrowserShelves {
    /// What the picker shows for a tab, a chosen shelf and a search.
    static func shelves(_ data: LensBrowserData, tab: LensBrowserTab, group: String?, query: String) -> [LensBrowserShelf] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let hits = LensBrowserGroups.search(data.lenses, query: q)
            return data.categories.compactMap { c in
                let mine = hits.filter { $0.category == c }
                return mine.isEmpty ? nil : LensBrowserShelf(title: c.rawValue, lenses: mine)
            }
        }
        switch tab {
        case .saved:
            return [LensBrowserShelf(title: "Favourites", lenses: data.favouriteLenses),
                    LensBrowserShelf(title: "Recent", lenses: data.recentLenses)].filter { !$0.lenses.isEmpty }
        case .all:
            return data.categories.map { c in LensBrowserShelf(title: c.rawValue, lenses: data.lenses.filter { $0.category == c }) }
        case .category(let c):
            let sections = LensBrowserGroups.sections(data.lenses, in: c)
            if let group { return sections.filter { $0.group == group }.map { LensBrowserShelf(title: nil, lenses: $0.lenses) } }
            if sections.count == 1 { return [LensBrowserShelf(title: nil, lenses: sections[0].lenses)] }
            return sections.map { LensBrowserShelf(title: $0.group, lenses: $0.lenses) }
        }
    }
}

// MARK: - The popover picker

/// The lens picker in the menu bar popover: search, tabs for the kinds of lens with a star tab for favourites and recent ones,
/// shelves inside a kind, and a three-column grid of pictures that scrolls in a fixed height, so the popover keeps its size
/// whatever is shown.
struct LensBrowserPopover: View {
    let data: LensBrowserData
    var actions = LensBrowserActions()
    let store: LensThumbnailStore
    var width: CGFloat = LensBrowserStyle.popoverWidth
    /// Draws without scroll views and text fields, for offscreen pictures.
    var snapshot = false

    @State private var tab: LensBrowserTab
    @State private var group: String?
    @State private var query: String

    init(data: LensBrowserData, actions: LensBrowserActions = LensBrowserActions(), store: LensThumbnailStore,
         width: CGFloat = LensBrowserStyle.popoverWidth, snapshot: Bool = false,
         tab: LensBrowserTab? = nil, group: String? = nil, query: String = "") {
        self.data = data
        self.actions = actions
        self.store = store
        self.width = width
        self.snapshot = snapshot
        _tab = State(initialValue: tab ?? Self.startingTab(data))
        _group = State(initialValue: group)
        _query = State(initialValue: query)
    }

    /// Opens where the lens that is on lives, or on the saved lenses if there are any, or on the first kind.
    static func startingTab(_ data: LensBrowserData) -> LensBrowserTab {
        if let on = data.selected { return .category(on.category) }
        if !data.favouriteLenses.isEmpty || !data.recentLenses.isEmpty { return .saved }
        return data.categories.first.map { .category($0) } ?? .saved
    }

    private var tabs: [LensBrowserTab] { [.saved] + data.categories.map { .category($0) } }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var shownTab: LensBrowserTab { tabs.contains(tab) ? tab : .saved }
    private var groups: [String] {
        guard case .category(let c) = shownTab else { return [] }
        return LensBrowserGroups.sections(data.lenses, in: c).map(\.group)
    }
    private var showsChips: Bool { !searching && groups.count > 1 }
    /// The grid takes the room of the bars it doesn't show, so the popover never changes height.
    private var gridHeight: CGFloat {
        var height = LensBrowserStyle.gridHeight(for: width)
        if searching { height += LensBrowserStyle.barHeight + 8 }
        if !showsChips { height += LensBrowserStyle.chipHeight + 8 }
        return height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !searching {
                LensBrowserTabs(tabs: tabs, selection: Binding(get: { shownTab }, set: { tab = $0; group = nil }), width: width)
            }
            if showsChips {
                LensBrowserChips(groups: groups, selection: Binding(get: { groups.contains(group ?? "") ? group : nil }, set: { group = $0 }),
                                 width: width, snapshot: snapshot)
            }
            grid
        }
        .frame(width: width, alignment: .leading)
        .onChange(of: data.selectedID) { _, id in
            // Follow a lens picked some other way (the keyboard), unless the saved lenses are showing.
            guard let id, let info = data.lenses.first(where: { $0.id == id }), shownTab != .saved, !searching else { return }
            if tab != .category(info.category) { tab = .category(info.category); group = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Lenses").font(.subheadline.weight(.medium))
            Spacer(minLength: 4)
            LensBrowserSearchField(text: $query, snapshot: snapshot).frame(width: data.selectedID == nil ? 200 : 170)
            if data.selectedID != nil {
                Button { actions.select(nil) } label: {
                    Text("Remove")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(LensBrowserPressStyle())
                .help("Take the lens off")
                .accessibilityLabel("Remove lens")
            }
        }
        .frame(width: width, height: 24)
    }

    @ViewBuilder private var grid: some View {
        let shelves = LensBrowserShelves.shelves(data, tab: shownTab, group: group, query: query)
        Group {
            if shelves.isEmpty {
                empty
            } else if snapshot {
                VStack(alignment: .leading, spacing: 10) { content(shelves) }
                    .frame(width: width, height: gridHeight, alignment: .top)
                    .clipped()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 10) { content(shelves) }
                            .padding(.bottom, 6)
                    }
                    .onAppear { if let id = data.selectedID { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
        .frame(width: width, height: gridHeight)
    }

    @ViewBuilder private func content(_ shelves: [LensBrowserShelf]) -> some View {
        let card = LensBrowserStyle.cardWidth(for: width)
        ForEach(shelves) { shelf in
            VStack(alignment: .leading, spacing: 6) {
                if let title = shelf.title { LensBrowserShelfHeader(title: title, count: shelf.lenses.count) }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(card), spacing: LensBrowserStyle.spacing), count: LensBrowserStyle.columns),
                          alignment: .leading, spacing: LensBrowserStyle.spacing) {
                    ForEach(shelf.lenses) { info in
                        LensBrowserCard(info: info, store: store, selected: data.selectedID == info.id, favourite: data.favourites.contains(info.id),
                                        action: { actions.select(data.selectedID == info.id ? nil : info.id) },
                                        toggleFavourite: { actions.toggleFavourite(info.id) })
                            .frame(width: card)
                            .id(info.id)
                            .contextMenu { LensBrowserMenu(info: info, data: data, actions: actions) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var empty: some View {
        if searching {
            LensBrowserEmpty(symbol: "magnifyingglass", title: "No lens matches “\(query.trimmingCharacters(in: .whitespaces))”",
                             detail: "Try a word like “hat”, “hand” or “snow”.")
        } else if data.lenses.isEmpty {
            LensBrowserEmpty(symbol: "sparkles", title: "No lenses yet")
        } else {
            LensBrowserEmpty(symbol: "star", title: "Star a lens to keep it here",
                             detail: "Lenses you've used lately show up here too.")
        }
    }
}

/// The right-click menu on a lens.
struct LensBrowserMenu: View {
    let info: LensInfo
    let data: LensBrowserData
    let actions: LensBrowserActions

    var body: some View {
        Button(data.selectedID == info.id ? "Take Off" : "Use Lens") { actions.select(data.selectedID == info.id ? nil : info.id) }
        Button(data.favourites.contains(info.id) ? "Remove from Favourites" : "Add to Favourites") { actions.toggleFavourite(info.id) }
        if info.folder != nil {
            Divider()
            if let reveal = actions.reveal { Button("Show in Finder") { reveal(info) } }
            if let trash = actions.trash { Button("Move to Trash", role: .destructive) { trash(info) } }
        }
    }
}

// MARK: - The Studio

/// The Studio's lens grid: large cards in shelves under each kind of lens, favourites first.
struct LensBrowserStudioGrid: View {
    let data: LensBrowserData
    var actions = LensBrowserActions()
    let store: LensThumbnailStore
    let tab: LensBrowserTab
    let query: String
    /// The lens shown in the detail panel.
    @Binding var focusedID: String?
    var snapshot = false
    var minimumCard: CGFloat = 172
    /// A few words of help after the last lens.
    var footnote: String?

    var body: some View {
        let sections = self.sections
        Group {
            if sections.isEmpty {
                emptyState
            } else if snapshot {
                VStack(alignment: .leading, spacing: 28) { ForEach(sections, id: \.title) { section($0) }; footer }.padding(20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) { ForEach(sections, id: \.title) { section($0) }; footer }.padding(20)
                    }
                    .onAppear { if let id = focusedID { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if let footnote {
            Text(footnote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 640, alignment: .leading)
        }
    }

    /// A kind of lens (or Favourites, or search results) and its shelves.
    private struct Section {
        var title: String
        var subtitle: String?
        var shelves: [LensBrowserShelf]
        var count: Int { shelves.reduce(0) { $0 + $1.lenses.count } }
    }

    private var sections: [Section] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let shelves = LensBrowserShelves.shelves(data, tab: .all, group: nil, query: q)
            return shelves.isEmpty ? [] : [Section(title: "Results", subtitle: "for “\(q)”", shelves: shelves)]
        }
        var out: [Section] = []
        if tab == .all || tab == .saved {
            let saved = LensBrowserShelves.shelves(data, tab: .saved, group: nil, query: "")
            if !saved.isEmpty { out.append(Section(title: "Favourites & Recent", shelves: saved)) }
        }
        let categories: [LensInfo.Category]
        switch tab {
        case .all: categories = data.categories
        case .saved: categories = []
        case .category(let c): categories = [c]
        }
        for c in categories {
            let shelves = LensBrowserShelves.shelves(data, tab: .category(c), group: nil, query: "")
            out.append(Section(title: c.rawValue, shelves: shelves))
        }
        return out
    }

    private func section(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.title).font(.title3.weight(.semibold))
                if let subtitle = section.subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                Text("\(section.count)").font(.callout.monospacedDigit()).foregroundStyle(.tertiary)
            }
            .accessibilityAddTraits(.isHeader)
            ForEach(section.shelves) { shelf in
                VStack(alignment: .leading, spacing: 10) {
                    if let title = shelf.title, title != section.title {
                        Label(title, systemImage: symbol(for: shelf))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumCard, maximum: 300), spacing: 16, alignment: .top)],
                              alignment: .leading, spacing: 18) {
                        ForEach(shelf.lenses) { info in
                            LensBrowserCard(info: info, store: store, size: .large, selected: data.selectedID == info.id,
                                            favourite: data.favourites.contains(info.id), best: info.scored ? data.bestScore(info.id) : 0,
                                            action: { focusedID = info.id; actions.select(info.id) },
                                            toggleFavourite: { actions.toggleFavourite(info.id) })
                                .id(info.id)
                                .contextMenu { LensBrowserMenu(info: info, data: data, actions: actions) }
                        }
                    }
                }
            }
        }
    }

    private func symbol(for shelf: LensBrowserShelf) -> String {
        switch shelf.title {
        case "Favourites": return "star"
        case "Recent": return "clock"
        case let title?: return shelf.lenses.first.map { LensBrowserGroups.symbol(for: title, in: $0.category) } ?? "square.grid.2x2"
        case nil: return "square.grid.2x2"
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            LensBrowserEmpty(symbol: "magnifyingglass", title: "No lens matches “\(query.trimmingCharacters(in: .whitespaces))”",
                             detail: "Try a word like “hat”, “hand” or “snow”.")
        } else if tab == .saved {
            LensBrowserEmpty(symbol: "star", title: "No favourites yet", detail: "Star a lens to keep it here. Lenses you've used lately show up too.")
        } else {
            LensBrowserEmpty(symbol: "sparkles", title: "No lenses yet")
        }
    }
}

/// The Studio's panel about one lens: a big preview, what it does, what it needs, the best score for a game, and buttons to
/// put it on or take it off. The preview itself is handed in (the live camera, or the lens playing on the mannequin).
struct LensBrowserDetail<Preview: View>: View {
    let info: LensInfo?
    let data: LensBrowserData
    var actions = LensBrowserActions()
    /// What the lens on the picture is saying right now, if this is that lens.
    var status: LensStatus?
    var cameraOn = false
    /// A line of small print under everything else.
    var note: String?
    var restart: () -> Void = {}
    @ViewBuilder var preview: Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: LensBrowserStyle.panelRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: LensBrowserStyle.panelRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            if let info { about(info) } else {
                Text("Pick a lens to put it on the picture. It shows up in Backdrop Camera too, so everyone on your call sees it.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    @ViewBuilder private func about(_ info: LensInfo) -> some View {
        let on = data.selectedID == info.id
        let favourite = data.favourites.contains(info.id)
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(info.name).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text("\(info.category.rawValue) · \(LensBrowserGroups.group(for: info))").font(.caption).foregroundStyle(.secondary)
                if let author = info.author { Text("by \(author)").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            Button { actions.toggleFavourite(info.id) } label: {
                Image(systemName: favourite ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(favourite ? Color(red: 1, green: 0.78, blue: 0.16) : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(LensBrowserPressStyle())
            .help(favourite ? "Remove from Favourites" : "Add to Favourites")
            .accessibilityLabel(favourite ? "Remove from favourites" : "Add to favourites")
        }
        Text(info.blurb).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 6) {
            ForEach(LensBrowserGroups.needs(of: info), id: \.text) { need in
                Label(need.text, systemImage: need.symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            if info.scored {
                let best = data.bestScore(info.id)
                Label(best > 0 ? "Best score \(best)" : "No best score yet", systemImage: "trophy.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(best > 0 ? Color(red: 0.85, green: 0.62, blue: 0.10) : Color.secondary)
            }
        }

        if on, cameraOn, let status {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title).font(.caption.weight(.semibold))
                if let detail = status.detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }

        HStack(spacing: 8) {
            if on {
                Button("Take Off") { actions.select(nil) }
                if info.scored { Button("New Game") { restart() }.help("Start again (⌃⌥R)") }
            } else {
                Button("Use Lens") { actions.select(info.id) }.buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.regular)

        if !info.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Label("Parts of this lens were skipped", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                ForEach(info.warnings, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
        if let note { Text(note).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true) }
    }
}

/// The lens playing on the mannequin, for when there is no camera to show it on: the stored picture first, then the moving one.
struct LensBrowserDemo: View {
    let info: LensInfo
    let store: LensThumbnailStore
    @ObservedObject var player: LensBrowserLivePlayer

    var body: some View {
        ZStack {
            LensBrowserThumbnail(info: info, store: store, radius: 0)
            if player.lensID == info.id, let frame = player.frame {
                Image(decorative: frame, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            }
        }
        .overlay(alignment: .topLeading) {
            Label("Example", systemImage: "figure.stand")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(8)
                .help("The lens on a stand-in. Turn the camera on to see it on you.")
        }
        .onAppear { player.play(info) }
        .onChange(of: info.id) { _, _ in player.play(info) }
        .onDisappear { player.stop() }
        .accessibilityLabel("\(info.name) shown on a stand-in")
    }
}
