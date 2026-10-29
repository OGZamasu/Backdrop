import Foundation
import os

/// Decides when a camera that has gone quiet should be restarted, and not more often than is useful.
struct StallWatchdog {
    /// How long without a frame counts as stalled.
    var quietLimit: TimeInterval = 2.0
    /// Minimum gap between restarts, so a camera that is genuinely gone isn't hammered.
    var retryInterval: TimeInterval = 4.0

    private var lastRestart = -TimeInterval.infinity

    mutating func shouldRestart(now: TimeInterval, lastFrame: TimeInterval, sessionRunning: Bool) -> Bool {
        guard !sessionRunning || now - lastFrame >= quietLimit else { return false }
        guard now - lastRestart >= retryInterval else { return false }
        lastRestart = now
        return true
    }
}

/// Tracks how long the queue into the camera extension has been continuously full. A queue that stays full means the
/// extension has stopped taking frames, so the connection needs rebuilding rather than waiting on.
struct DropStreak {
    var limit: TimeInterval = 1.5
    private var since: TimeInterval?

    mutating func recordFull(at now: TimeInterval) {
        if since == nil { since = now }
    }

    mutating func recordAccepted() { since = nil }

    func isStalled(at now: TimeInterval) -> Bool {
        guard let since else { return false }
        return now - since >= limit
    }
}

/// Log messages that survive. Unlike `.info`, `.notice` is kept on disk, so what happened is still there to read
/// after the fact:  /usr/bin/log show --last 1h --predicate 'subsystem == "<bundle id>"'
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.backdrop"
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let sink = Logger(subsystem: subsystem, category: "virtual-camera")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
}
