import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Where every lens's picture comes from: kept in memory once seen, saved as a PNG under Application Support so the next launch
/// doesn't make it again, and otherwise made on demand by running the lens over the mannequin in the background.
///
/// A picture is only made when a card asks for it (a card that scrolls away before its turn withdraws the request), at most two at
/// a time on low-priority threads, one at a time with a pause between while the camera is on, and not at all while the Mac is
/// running hot. Pictures are kept per app build (a new build may have changed a lens) and, for the user's own lenses, per edit of
/// their lens.json; old ones are swept away the first time a picture is made.
@MainActor
final class LensThumbnailStore: ObservableObject {
    static let shared = LensThumbnailStore()

    /// Bumped when the mannequin or the way lenses are filmed changes, so old pictures are made again.
    nonisolated static let rendererVersion = 1

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backdrop", isDirectory: true).appendingPathComponent("LensThumbnails", isDirectory: true)
    }

    nonisolated static var appBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "0"
    }

    let directory: URL
    let build: String
    private let queue: LensThumbnailQueue
    private var memory: [String: NSImage] = [:]
    private var waiters: [String: [(id: Int, continuation: CheckedContinuation<NSImage?, Never>)]] = [:]
    private var nextWaiter = 0

    init(directory: URL = LensThumbnailStore.defaultDirectory, build: String = LensThumbnailStore.appBuild, concurrency: Int = 2) {
        self.directory = directory
        self.build = build
        queue = LensThumbnailQueue(directory: directory, build: build, concurrency: concurrency)
    }

    // MARK: Keys

    /// The name a lens's picture is kept under: its id, the app build and the renderer version, plus the time its lens.json was last
    /// changed for a lens from the Lenses folder. Ids that aren't plain file names get a hash so two can never share a file.
    nonisolated static func cacheKey(id: String, build: String, modified: Date?) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_.")
        let lowered = id.lowercased()
        let safe = String(lowered.map { allowed.contains($0) ? $0 : "_" }.prefix(80))
        var key = safe
        if safe != id { key += "--h" + String(fnv1a(id), radix: 16) }
        key += "--b\(String(build.map { allowed.contains($0) ? $0 : "_" }))--r\(rendererVersion)"
        if let modified { key += "--m\(Int64((modified.timeIntervalSince1970 * 1000).rounded()))" }
        return key
    }

    func cacheKey(for info: LensInfo) -> String { Self.cacheKey(id: info.id, build: build, modified: info.modified) }

    func fileURL(for info: LensInfo) -> URL { directory.appendingPathComponent(cacheKey(for: info) + ".png") }

    private nonisolated static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return hash
    }

    // MARK: Pictures

    /// The picture if it is already in memory. Never waits.
    func cached(_ info: LensInfo) -> NSImage? { memory[cacheKey(for: info)] }

    /// Puts a picture in memory, as if it had been made. For previews and tests.
    func remember(_ image: NSImage, for info: LensInfo) { memory[cacheKey(for: info)] = image }

    /// Whether the camera is on, which slows the making of pictures to one at a time.
    var cameraBusy = false {
        didSet { queue.setBusy(cameraBusy) }
    }

    /// The lens's picture: from memory, from disk, or made now. Nil if it couldn't be made, or if the caller stopped waiting.
    func image(for info: LensInfo) async -> NSImage? {
        let key = cacheKey(for: info)
        if let hit = memory[key] { return hit }
        let url = directory.appendingPathComponent(key + ".png")
        let fromDisk = await Task.detached(priority: .utility) { LensThumbnailStore.load(url) }.value
        if let hit = memory[key] { return hit }
        if let fromDisk {
            memory[key] = fromDisk
            return fromDisk
        }
        if Task.isCancelled { return nil }
        nextWaiter += 1
        let me = nextWaiter
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let first = waiters[key] == nil
                waiters[key, default: []].append((me, continuation))
                if first {
                    queue.enqueue(key: key, info: info) { [weak self] picture in
                        Task { @MainActor in self?.finish(key, picture) }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.abandon(key, waiter: me) }
        }
    }

    private func finish(_ key: String, _ picture: CGImage?) {
        let image = picture.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        if let image { memory[key] = image }
        for waiter in waiters.removeValue(forKey: key) ?? [] { waiter.continuation.resume(returning: image) }
    }

    /// A card went away. If nobody else wants that picture and it hasn't been started, don't make it.
    private func abandon(_ key: String, waiter: Int) {
        guard var list = waiters[key], let index = list.firstIndex(where: { $0.id == waiter }) else { return }
        list.remove(at: index).continuation.resume(returning: nil)
        if list.isEmpty {
            waiters[key] = nil
            queue.cancel(key: key)
        } else {
            waiters[key] = list
        }
    }

    nonisolated static func load(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// How many pictures are waiting or being made. For tests.
    var outstanding: Int { waiters.count }
}

/// The line of pictures to make, and the renderers that make them. Thread-safe; works on its own low-priority threads, never the
/// video queue.
final class LensThumbnailQueue: @unchecked Sendable {
    private struct Job {
        let key: String
        let info: LensInfo
        let done: (CGImage?) -> Void
    }

    private let lock = NSLock()
    private var pending: [Job] = []
    private var running = 0
    private var peak = 0
    private var busy = false
    private var idleRenderers: [LensBrowserRenderer] = []
    private var swept = false
    private var idleGeneration = 0
    private let concurrency: Int
    private let directory: URL
    private let build: String
    private let workers = DispatchQueue(label: "app.backdrop.lens-thumbnails", qos: .utility, attributes: .concurrent)

    /// Seconds between pictures while the camera is on, so the live video always comes first.
    static let busyPause = 0.6
    /// Renderers are let go after this long with nothing to do, to give their memory back.
    static let idleRelease = 20.0

    init(directory: URL, build: String, concurrency: Int) {
        self.directory = directory
        self.build = build
        self.concurrency = max(1, concurrency)
    }

    /// The most pictures ever made at once. For tests.
    var peakRunning: Int { lock.withLock { peak } }

    func setBusy(_ value: Bool) {
        lock.withLock { busy = value }
        if !value { pump() }
    }

    func enqueue(key: String, info: LensInfo, done: @escaping (CGImage?) -> Void) {
        lock.withLock { pending.append(Job(key: key, info: info, done: done)) }
        pump()
    }

    func cancel(key: String) {
        lock.withLock { pending.removeAll { $0.key == key } }
    }

    /// Starts as many jobs as are allowed right now.
    private func pump() {
        while let job = nextJob() {
            workers.async { self.run(job) }
        }
    }

    private func nextJob() -> Job? {
        lock.withLock {
            let limit = busy ? 1 : concurrency
            guard running < limit, !pending.isEmpty else { return nil }
            running += 1
            peak = max(peak, running)
            idleGeneration += 1
            return pending.removeFirst()
        }
    }

    private func run(_ job: Job) {
        // Hold off while the Mac is struggling to stay cool; a picture can wait.
        while ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            Thread.sleep(forTimeInterval: 3)
        }
        sweepOnce()
        let renderer = lock.withLock { idleRenderers.popLast() } ?? LensBrowserRenderer()
        let picture = autoreleasepool { renderer.thumbnail(for: job.info) }
        if let picture { write(picture, key: job.key) }
        let (pause, generation): (Double, Int) = lock.withLock {
            idleRenderers.append(renderer)
            running -= 1
            idleGeneration += 1
            return (busy ? Self.busyPause : 0, idleGeneration)
        }
        job.done(picture)
        if pause > 0 {
            workers.asyncAfter(deadline: .now() + pause) { self.pump() }
        } else {
            pump()
        }
        workers.asyncAfter(deadline: .now() + Self.idleRelease) { self.releaseIfIdle(since: generation) }
    }

    private func releaseIfIdle(since generation: Int) {
        lock.withLock {
            if running == 0, pending.isEmpty, idleGeneration == generation { idleRenderers.removeAll() }
        }
    }

    private func write(_ picture: CGImage, key: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(key + ".png")
        let temporary = directory.appendingPathComponent(".\(key)-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, picture, nil)
        guard CGImageDestinationFinalize(destination) else { try? fm.removeItem(at: temporary); return }
        _ = try? fm.replaceItemAt(target, withItemAt: temporary)
        if fm.fileExists(atPath: temporary.path) { try? fm.removeItem(at: temporary) }
        // A lens from the Lenses folder that was edited leaves its old picture behind: remove it.
        if let edit = key.range(of: "--m") {
            let stem = String(key[..<edit.lowerBound]) + "--m"
            let files = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in files where name.hasPrefix(stem) && name != key + ".png" && name.hasSuffix(".png") {
                try? fm.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    /// Pictures from other builds or an older renderer are never shown again; remove them once per run.
    private func sweepOnce() {
        let first = lock.withLock { () -> Bool in
            defer { swept = true }
            return !swept
        }
        guard first else { return }
        let current = "--b\(String(build.map { Set("abcdefghijklmnopqrstuvwxyz0123456789-_.").contains($0) ? $0 : "_" }))--r\(LensThumbnailStore.rendererVersion)"
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "png" && !file.lastPathComponent.contains(current) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
