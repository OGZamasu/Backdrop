import Foundation

struct AutomationRule: Identifiable, Codable, Hashable {
    enum Trigger: Codable, Hashable {
        /// While this app is the one you were last using. Sticky on purpose: a rule for Zoom shouldn't
        /// flip back the moment you glance at Slack mid-call.
        case app(bundleID: String, appName: String)
        /// While a calendar event is in progress. An empty keyword matches any event.
        case calendar(keyword: String)
        /// Between two times of day, as minutes since midnight. May wrap past midnight.
        case time(startMinute: Int, endMinute: Int)
    }

    var id = UUID()
    var trigger: Trigger
    var backgroundID: UUID
    var isEnabled = true
}

struct AutomationContext {
    /// The most recent frontmost app that has a rule. Not simply the frontmost app.
    var lastRuleApp: String?
    var eventTitles: [String] = []
    var now: Date = Date()
    var calendar: Calendar = .current
}

enum RuleResolver {
    /// More specific rules win: a calendar keyword beats an app, an app beats "any event", and time of day is the fallback.
    private static func priority(of rule: AutomationRule) -> Int {
        switch rule.trigger {
        case .calendar(let keyword): return keyword.trimmingCharacters(in: .whitespaces).isEmpty ? 2 : 4
        case .app:                   return 3
        case .time:                  return 1
        }
    }

    static func matches(_ rule: AutomationRule, in context: AutomationContext) -> Bool {
        switch rule.trigger {
        case .app(let bundleID, _):
            return context.lastRuleApp == bundleID
        case .calendar(let keyword):
            let needle = keyword.trimmingCharacters(in: .whitespaces)
            if needle.isEmpty { return !context.eventTitles.isEmpty }
            return context.eventTitles.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        case .time(let start, let end):
            let parts = context.calendar.dateComponents([.hour, .minute], from: context.now)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if start == end { return false }
            return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
        }
    }

    static func resolve(_ rules: [AutomationRule], in context: AutomationContext) -> AutomationRule? {
        var best: AutomationRule?
        for rule in rules where rule.isEnabled && matches(rule, in: context) {
            if best == nil || priority(of: rule) > priority(of: best!) { best = rule }
        }
        return best
    }
}
