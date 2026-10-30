import Foundation

/// The user's Lenses folder: one folder per lens, each with a `lens.json`.
enum LensPackFolder {
    struct Problem: Identifiable, Equatable {
        let id: String
        let message: String
        let folder: URL
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backdrop", isDirectory: true).appendingPathComponent("Lenses", isDirectory: true)
    }

    /// Every lens in the folder, and a plain-words reason for each folder that couldn't be used.
    static func scan(_ directory: URL) -> (packs: [LensPack], problems: [Problem]) {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                                                                    options: [.skipsHiddenFiles])) ?? []
        var packs: [LensPack] = [], problems: [Problem] = []
        for url in entries.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            do { packs.append(try LensPack.load(from: url)) } catch {
                problems.append(Problem(id: url.lastPathComponent, message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription, folder: url))
            }
        }
        return (packs, problems)
    }

    /// How a lens shows up in the picker.
    static func info(for pack: LensPack) -> LensInfo {
        LensInfo(id: pack.id, name: pack.name, glyph: pack.glyph, blurb: pack.summary, category: .custom, scored: false,
                 needsFace: pack.needsFace, make: { PackLens(pack) }, author: pack.author, tags: pack.tags, warnings: pack.warnings,
                 modified: pack.modified, folder: pack.directory,
                 showsText: pack.layers.contains { if case .text = $0.content { return true } else { return false } })
    }

    /// Copies a lens folder into the Lenses folder, adding a number if the name is taken. Returns where it went.
    @discardableResult
    static func add(_ source: URL, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = try LensPack.load(from: source)              // refuse something that isn't a lens before copying it in
        var target = directory.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            let stem = source.deletingPathExtension().lastPathComponent
            target = directory.appendingPathComponent(source.pathExtension.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(source.pathExtension)")
            n += 1
        }
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }
}
