import Foundation
import SystemExtensions

/// Installs the Backdrop Camera system extension. macOS asks the user to approve it in System Settings.
@MainActor
final class ExtensionInstaller: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    enum State: Equatable {
        case idle
        case working
        case needsApproval
        /// macOS will finish the job when the Mac restarts.
        case needsReboot
        case finished
        case failed(String)
    }

    /// The extension is always the app's own identifier plus ".camera" (see project.yml).
    static let identifier = (Bundle.main.bundleIdentifier ?? "com.zamasu.backdrop") + ".camera"

    @Published private(set) var state: State = .idle
    /// macOS says the camera extension is installed and switched on. (Whether it has actually started is another matter:
    /// after an upgrade it can take a quit of the apps using the camera, or a restart, before it does.)
    @Published private(set) var isInstalledAndEnabled = false
    private var embeddedVersion: String?

    private enum Kind { case activate, deactivate, upgradeCheck, refresh }
    private var kinds: [ObjectIdentifier: Kind] = [:]

    func install() {
        submit(OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.identifier, queue: .main), kind: .activate)
    }

    /// Replaces the installed camera extension if this copy of Backdrop carries a different version of it.
    /// Never starts a first-time install, which needs the user's go-ahead.
    func updateIfOutdated() {
        guard let embedded = Self.embeddedVersion() else { return }
        embeddedVersion = embedded
        submitProperties(.upgradeCheck)
    }

    /// Asks macOS again what is installed, without changing anything.
    func refreshProperties() { submitProperties(.refresh) }

    private func submitProperties(_ kind: Kind) {
        let request = OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: Self.identifier, queue: .main)
        request.delegate = self
        kinds[ObjectIdentifier(request)] = kind
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private static func embeddedVersion() -> String? {
        let folder = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions")
        guard let bundle = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "systemextension" }),
              let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return info["CFBundleVersion"] as? String
    }

    func uninstall() {
        submit(OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: Self.identifier, queue: .main), kind: .deactivate)
    }

    private func submit(_ request: OSSystemExtensionRequest, kind: Kind) {
        state = .working
        request.delegate = self
        kinds[ObjectIdentifier(request)] = kind
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: OSSystemExtensionRequestDelegate

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension replacement: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        CameraExtensionPolicy.shouldReplace(existingBuild: existing.bundleVersion, withBuild: replacement.bundleVersion) ? .replace : .cancel
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let installed = properties.filter { $0.isEnabled && !$0.isUninstalling }.map(\.bundleVersion)
        let id = ObjectIdentifier(request)
        Task { @MainActor in
            let kind = self.kinds.removeValue(forKey: id)
            self.isInstalledAndEnabled = !installed.isEmpty
            guard kind == .upgradeCheck, let embedded = self.embeddedVersion,
                  CameraExtensionPolicy.shouldUpgrade(installedBuilds: installed, embeddedBuild: embedded) else { return }
            self.install()
        }
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in self.state = .needsApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let id = ObjectIdentifier(request)
        Task { @MainActor in
            let kind = self.kinds.removeValue(forKey: id)
            self.state = result == .willCompleteAfterReboot ? .needsReboot : .finished
            if kind == .deactivate { self.isInstalledAndEnabled = false }
            // Whether it is really installed now is for macOS to say, not assumed from the request having gone through.
            if kind == .activate { self.refreshProperties() }
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let message = (error as NSError).localizedDescription
        let id = ObjectIdentifier(request)
        Task { @MainActor in
            let kind = self.kinds.removeValue(forKey: id)
            // A failed check on what is installed isn't a failed install, and isn't worth showing.
            if kind == .activate || kind == .deactivate { self.state = .failed(message) }
        }
    }
}
