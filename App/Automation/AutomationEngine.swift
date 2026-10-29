import AppKit
import Combine
import EventKit

@MainActor
final class RuleStore: ObservableObject {
    @Published var rules: [AutomationRule] {
        didSet { save() }
    }

    private let url: URL

    init(directory: URL = BackgroundLibrary.defaultDirectory) {
        url = directory.appendingPathComponent("rules.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        rules = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([AutomationRule].self, from: $0) } ?? []
    }

    func remove(_ id: UUID) { rules.removeAll { $0.id == id } }

    /// Rules that point at a background that no longer exists would silently do nothing, so drop them.
    func forget(background id: UUID) { rules.removeAll { $0.backgroundID == id } }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Watches the three things rules can depend on, and reports when the winning rule *changes*.
///
/// Edge-triggered on purpose: if you pick a background by hand, it stays until something new happens
/// (a different app, a meeting starting), rather than being yanked back every thirty seconds.
@MainActor
final class AutomationEngine {
    var onMatch: ((AutomationRule) -> Void)?

    private let store: RuleStore
    private let events = EKEventStore()
    private var lastRuleApp: String?
    private var lastMatchID: UUID?
    private var eventTitles: [String] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var rulesSubscription: AnyCancellable?

    init(store: RuleStore) { self.store = store }

    var calendarAccessGranted: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.appActivated(bundleID) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: events, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        // Editing a rule can change the answer immediately.
        rulesSubscription = store.$rules.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.evaluate() }
        }
        evaluate()
    }

    func requestCalendarAccess() async -> Bool {
        let granted = (try? await events.requestFullAccessToEvents()) ?? false
        if granted { evaluate() }
        return granted
    }

    private func appActivated(_ bundleID: String?) {
        guard let bundleID else { return }
        // Only apps that have a rule count. Glancing at Slack mid-call mustn't change your background.
        let hasRule = store.rules.contains { if case .app(let id, _) = $0.trigger { return id == bundleID } else { return false } }
        guard hasRule else { return }
        lastRuleApp = bundleID
        evaluate()
    }

    private func evaluate() {
        eventTitles = currentEventTitles()
        let context = AutomationContext(lastRuleApp: lastRuleApp, eventTitles: eventTitles, now: Date())
        let match = RuleResolver.resolve(store.rules, in: context)
        guard match?.id != lastMatchID else { return }
        lastMatchID = match?.id
        if let match { onMatch?(match) }
    }

    private func currentEventTitles() -> [String] {
        guard calendarAccessGranted else { return [] }
        let now = Date()
        return events.events(matching: events.predicateForEvents(withStart: now, end: now.addingTimeInterval(1), calendars: nil))
            .filter { !$0.isAllDay && $0.status != .canceled }
            .compactMap(\.title)
    }
}
