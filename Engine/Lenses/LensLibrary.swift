import AppKit
import SwiftUI

/// Everything that can go in the picker: the lenses that come with Backdrop and the ones in the user's Lenses folder.
@MainActor
final class LensLibrary: ObservableObject {
    private enum Keys {
        static let samples = "lensSamplesInstalled", given = "lensSamplesGiven", favourites = "favouriteLenses"
    }

    let directory: URL
    private let defaults: UserDefaults
    private let trasher: (URL) -> Void

    @Published private(set) var packs: [LensInfo] = []
    @Published private(set) var problems: [LensPackFolder.Problem] = []
    @Published private(set) var favourites: Set<String>

    /// `trash` is how a lens leaves the folder: the Trash, unless a test says otherwise.
    init(directory: URL = LensPackFolder.defaultDirectory, defaults: UserDefaults = .standard,
         trash: @escaping (URL) -> Void = { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.directory = directory
        self.defaults = defaults
        trasher = trash
        favourites = Set(defaults.stringArray(forKey: Keys.favourites) ?? [])
        // Put the examples there to open, copy and change. Each is given once: a later version's new examples arrive, and
        // one the user has deleted does not come back. After that the folder is the user's.
        var given = Set(defaults.stringArray(forKey: Keys.given) ?? [])
        if given.isEmpty && defaults.bool(forKey: Keys.samples) { given = Set(SampleLenses.originalFolders) }
        let fresh = SampleLenses.all.filter { !given.contains($0.folder) }
        if !fresh.isEmpty {
            try? SampleLenses.install(fresh, into: directory)
            defaults.set(Array(given.union(fresh.map(\.folder))).sorted(), forKey: Keys.given)
        }
        defaults.set(true, forKey: Keys.samples)
        reload()
    }

    var all: [LensInfo] { LensCatalog.all + packs }

    func info(for id: String) -> LensInfo? { all.first { $0.id == id } }

    func lenses(in category: LensInfo.Category) -> [LensInfo] { all.filter { $0.category == category } }

    /// The categories that have something in them.
    var categories: [LensInfo.Category] { LensInfo.Category.allCases.filter { !lenses(in: $0).isEmpty } }

    /// Looks at the folder again, to pick up lenses that were added, changed or removed.
    func reload() { apply(LensPackFolder.scan(directory)) }

    /// The same, with the folder read off the main thread, for when the app comes to the front and the folder may be large.
    func reloadAsync() async {
        let directory = self.directory
        let found = await Task.detached(priority: .utility) { LensPackFolder.scan(directory) }.value
        apply(found)
    }

    private func apply(_ found: (packs: [LensPack], problems: [LensPackFolder.Problem])) {
        packs = found.packs.map(LensPackFolder.info)
        problems = found.problems
        // Favourites are kept even for a lens that can't be read right now: a typo in lens.json shouldn't cost the star.
    }

    // MARK: Favourites

    func isFavourite(_ id: String) -> Bool { favourites.contains(id) }

    func toggleFavourite(_ id: String) {
        if favourites.contains(id) { favourites.remove(id) } else { favourites.insert(id) }
        saveFavourites()
    }

    var favouriteLenses: [LensInfo] { all.filter { favourites.contains($0.id) } }

    private func saveFavourites() { defaults.set(Array(favourites).sorted(), forKey: Keys.favourites) }

    // MARK: Files

    /// Adds a lens folder from anywhere to the Lenses folder.
    func add(_ source: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try LensPackFolder.add(source, to: directory)
        reload()
    }

    /// Moves a lens from the Lenses folder to the Trash.
    func trash(_ info: LensInfo) {
        guard let folder = info.folder else { return }
        trasher(folder)
        reload()
    }

    func showFolder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func reveal(_ info: LensInfo) {
        if let folder = info.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
    }
}
