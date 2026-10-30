import Foundation

/// The rules for when to swap the installed camera extension for the one inside the app, and when to say it has gone missing.
/// Kept apart from the system calls so they can be tested.
enum CameraExtensionPolicy {
    /// Builds are whole numbers that only go up. Replace when the app's copy is newer than what is installed; never go back
    /// to an older one (a development build opened next to an installed release would swap it back and forth), and never
    /// replace a copy with itself.
    static func shouldReplace(existingBuild: String, withBuild replacement: String) -> Bool {
        guard let old = Int(existingBuild), let new = Int(replacement) else { return true }
        return new > old
    }

    /// Whether the extension inside the app is newer than every enabled copy already installed. With none installed the
    /// answer is no: a first install needs the user's go-ahead and is not done behind their back.
    static func shouldUpgrade(installedBuilds: [String], embeddedBuild: String) -> Bool {
        let installed = installedBuilds.compactMap(Int.init)
        guard let newest = installed.max(), let embedded = Int(embeddedBuild) else { return false }
        return embedded > newest
    }
}

/// Notices when macOS says the camera extension is installed and enabled but "Backdrop Camera" hasn't turned up in the list of
/// cameras for a while, which is what happened after an upgrade made while other apps were using the camera.
struct CameraMissingMonitor {
    /// Seconds (polls) to wait, since the camera is also briefly absent while the extension starts.
    var threshold = 10
    private var polls = 0

    /// Call once a second. Returns whether the camera should be reported missing.
    mutating func poll(installedAndEnabled: Bool, deviceVisible: Bool) -> Bool {
        polls = deviceVisible || !installedAndEnabled ? 0 : polls + 1
        return polls >= threshold
    }
}
