import Foundation
import UniformTypeIdentifiers

@MainActor
final class BackgroundLibrary: ObservableObject {
    enum LibraryError: LocalizedError {
        case unsupported(String)
        var errorDescription: String? {
            switch self {
            case .unsupported(let name): return "\(name) isn't an image or video Backdrop can use."
            }
        }
    }

    @Published private(set) var userItems: [Background] = []

    /// Built-ins first, then everything the user added.
    var items: [Background] { Background.builtIns + userItems }

    let directory: URL
    var mediaDirectory: URL { directory.appendingPathComponent("Media", isDirectory: true) }
    private var indexURL: URL { directory.appendingPathComponent("library.json") }

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backdrop", isDirectory: true)
    }

    init(directory: URL = BackgroundLibrary.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: Lookup

    func background(withID id: UUID) -> Background? {
        items.first { $0.id == id }
    }

    /// Where the background's media lives on disk, for image and video backgrounds.
    func fileURL(for background: Background) -> URL? {
        switch background.kind {
        case .image(let file), .video(let file): return mediaDirectory.appendingPathComponent(file)
        default: return nil
        }
    }

    // MARK: Adding

    @discardableResult
    func importFile(at url: URL) throws -> Background {
        let type = UTType(filenameExtension: url.pathExtension)
        let isVideo = type?.conforms(to: .movie) == true
        let isImage = type?.conforms(to: .image) == true
        guard isVideo || isImage else { throw LibraryError.unsupported(url.lastPathComponent) }

        let stored = try copyIntoMedia(url)
        let item = Background(id: UUID(),
                              name: url.deletingPathExtension().lastPathComponent,
                              kind: isVideo ? .video(file: stored) : .image(file: stored),
                              origin: .imported)
        append(item)
        return item
    }

    @discardableResult
    func addGenerated(from url: URL, prompt: String) throws -> Background {
        let stored = try copyIntoMedia(url)
        let item = Background(id: UUID(),
                              name: Self.title(from: prompt),
                              kind: .image(file: stored),
                              origin: .generated,
                              prompt: prompt)
        append(item)
        return item
    }

    @discardableResult
    func addWindow(bundleID: String, appName: String, title: String?) -> Background {
        let name = [appName, title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ")
        let item = Background(id: UUID(), name: name, kind: .window(bundleID: bundleID, title: title), origin: .imported)
        append(item)
        return item
    }

    @discardableResult
    func addDisplay() -> Background {
        let item = Background(id: UUID(), name: "Screen", kind: .display, origin: .imported)
        append(item)
        return item
    }

    // MARK: Editing

    func update(_ id: UUID, _ change: (inout Background) -> Void) {
        guard let index = userItems.firstIndex(where: { $0.id == id }) else { return }
        change(&userItems[index])
        save()
    }

    func remove(_ id: UUID) {
        guard let index = userItems.firstIndex(where: { $0.id == id }) else { return }
        if let url = fileURL(for: userItems[index]) { try? FileManager.default.removeItem(at: url) }
        userItems.remove(at: index)
        save()
    }

    // MARK: Persistence

    private func append(_ item: Background) {
        userItems.append(item)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Background].self, from: data) else { return }
        // Drop entries whose media went missing rather than failing every time they're selected.
        userItems = decoded.filter { item in
            guard let url = fileURL(for: item) else { return true }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(userItems) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func copyIntoMedia(_ url: URL) throws -> String {
        let name = "\(UUID().uuidString).\(url.pathExtension.lowercased())"
        try FileManager.default.copyItem(at: url, to: mediaDirectory.appendingPathComponent(name))
        return name
    }

    private static func title(from prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "Generated" }
        let sentence = first.uppercased() + trimmed.dropFirst()
        return sentence.count > 36 ? String(sentence.prefix(35)) + "…" : sentence
    }
}
