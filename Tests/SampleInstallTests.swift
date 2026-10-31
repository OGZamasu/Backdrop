import XCTest

/// A new version of Backdrop brings new example lenses to a folder set up by an old one, without undoing what the user did to it.
@MainActor
final class SampleInstallTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-sample-install-\(UUID().uuidString)")
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "backdrop.samples.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private var directory: URL { root.appendingPathComponent("Lenses") }

    private func library() -> LensLibrary {
        LensLibrary(directory: directory, defaults: defaults, trash: { try? FileManager.default.removeItem(at: $0) })
    }

    func testAFolderSetUpByAnEarlierVersionGetsTheNewExamplesButNotBackOnesItLost() throws {
        // What the first versions did: the five examples, and one flag.
        let originals = SampleLenses.all.filter { SampleLenses.originalFolders.contains($0.folder) }
        XCTAssertEqual(originals.count, 5)
        try SampleLenses.install(originals, into: directory)
        defaults.set(true, forKey: "lensSamplesInstalled")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("Heart Eyes.backdroplens"))

        let lib = library()
        XCTAssertEqual(lib.packs.count, SampleLenses.all.count - 1, "everything new arrives; the one deleted stays deleted")
        XCTAssertNil(lib.info(for: "pack.Heart Eyes.backdroplens"))
        XCTAssertNotNil(lib.info(for: "pack.Rockstar.backdroplens"))

        try FileManager.default.removeItem(at: directory.appendingPathComponent("Rockstar.backdroplens"))
        XCTAssertEqual(library().packs.count, SampleLenses.all.count - 2, "and nothing is put back on the next launch")
    }

    func testAnEditedExampleIsNeverOverwritten() throws {
        let first = library()
        let folder = first.directory.appendingPathComponent("Golden Hour.backdroplens/lens.json")
        let mine = "{ \"format\": 1, \"name\": \"Mine\", \"look\": { \"saturation\": 2 } }"
        try mine.write(to: folder, atomically: true, encoding: .utf8)
        _ = library()
        XCTAssertEqual(try String(contentsOf: folder, encoding: .utf8), mine)
    }
}
