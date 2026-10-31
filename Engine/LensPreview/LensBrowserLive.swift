import AppKit
import Combine
import CoreGraphics

/// The lenses used lately, newest first, kept between launches. A lens only counts once it has stayed on for a moment, so
/// flicking through lenses with the keyboard doesn't fill the list.
@MainActor
final class LensBrowserRecents: ObservableObject {
    static let shared = LensBrowserRecents()
    static let limit = 9
    /// How long a lens has to stay on to count as used.
    static let settle = 2.5

    @Published private(set) var ids: [String]
    private let defaults: UserDefaults
    private let key = "lensBrowserRecent"
    private var following: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = defaults.stringArray(forKey: key) ?? []
    }

    func note(_ id: String) {
        var list = ids.filter { $0 != id }
        list.insert(id, at: 0)
        ids = Array(list.prefix(Self.limit))
        defaults.set(ids, forKey: key)
    }

    func forget(_ id: String) {
        ids.removeAll { $0 == id }
        defaults.set(ids, forKey: key)
    }

    /// Watches the chosen lens for the rest of the run. Calling it again does nothing.
    func follow<P: Publisher>(_ lens: P) where P.Output == String?, P.Failure == Never {
        guard following == nil else { return }
        following = lens
            .removeDuplicates()
            .debounce(for: .seconds(Self.settle), scheduler: RunLoop.main)
            .sink { [weak self] id in
                guard let id else { return }
                MainActor.assumeIsolated { self?.note(id) }
            }
    }
}

/// Plays a lens on the mannequin, for the Studio's detail panel while the camera is off: the same direction the thumbnail was
/// made from, looping, at a modest frame rate on a low-priority thread.
@MainActor
final class LensBrowserLivePlayer: ObservableObject {
    @Published private(set) var frame: CGImage?
    @Published private(set) var lensID: String?

    nonisolated static let fps = 12.0
    nonisolated static let size = CGSize(width: 640, height: 360)

    private let worker = DispatchQueue(label: "app.backdrop.lens-preview", qos: .utility)
    /// Which play is current; the worker stops as soon as it is not its own. Read from the worker, so behind a lock.
    private nonisolated let current = LensBrowserTicket()
    /// Kept across plays so switching lenses doesn't rebuild the studio; let go when playing stops.
    private nonisolated(unsafe) var renderer: LensBrowserRenderer?

    func play(_ info: LensInfo?) {
        guard info?.id != lensID else { return }
        let mine = current.next(playing: info != nil)
        lensID = info?.id
        frame = nil
        guard let info else { return }
        worker.async { [weak self] in self?.run(info, ticket: mine) }
    }

    func stop() { play(nil) }

    private nonisolated func run(_ info: LensInfo, ticket mine: Int) {
        let renderer = self.renderer ?? LensBrowserRenderer()
        self.renderer = renderer
        let session = LensBrowserRenderer.Session(info: info, renderer: renderer)
        session.skipToPlay()
        let loop = max(3, session.direction.seconds + 1.2)
        let dt = 1 / Self.fps
        var elapsed = 0.0
        while current.value == mine {
            let started = CFAbsoluteTimeGetCurrent()
            let picture = autoreleasepool { renderer.picture(session.step(dt, poseTime: elapsed.truncatingRemainder(dividingBy: loop)), size: Self.size) }
            elapsed += dt
            Task { @MainActor [weak self] in
                guard let self, self.current.value == mine else { return }
                self.frame = picture
            }
            let spare = dt - (CFAbsoluteTimeGetCurrent() - started)
            if spare > 0 { Thread.sleep(forTimeInterval: spare) }
        }
        // Nothing is playing any more: give the renderer's memory back.
        if current.stopped { self.renderer = nil }
    }
}

/// Which play is current (a number that only goes up) and whether anything is playing at all, readable from any thread.
final class LensBrowserTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    private var playing = false

    var value: Int { lock.withLock { stored } }
    var stopped: Bool { lock.withLock { !playing } }

    /// A new ticket for a play (or for stopping), which ends whatever was playing.
    func next(playing now: Bool = true) -> Int {
        lock.withLock {
            stored += 1
            playing = now
            return stored
        }
    }
}
