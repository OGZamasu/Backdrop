import Foundation
import SystemExtensions

/// Installs the Backdrop Camera system extension. macOS asks the user to approve it in System Settings.
@MainActor
final class ExtensionInstaller: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    enum State: Equatable {
        case idle
        case working
        case needsApproval
        case finished
        case failed(String)
    }

    /// The extension is always the app's own identifier plus ".camera" (see project.yml).
    static let identifier = (Bundle.main.bundleIdentifier ?? "com.zamasu.backdrop") + ".camera"

    @Published private(set) var state: State = .idle
    private var embeddedVersion: String?

    func install() {
        submit(OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.identifier, queue: .main))
    }

    /// Replaces the installed camera extension if this copy of Backdrop carries a different version of it.
    /// Never starts a first-time install, which needs the user's go-ahead.
    func updateIfOutdated() {
        guard let embedded = Self.embeddedVersion() else { return }
        embeddedVersion = embedded
        let request = OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: Self.identifier, queue: .main)
        request.delegate = self
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
        submit(OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: Self.identifier, queue: .main))
    }

    private func submit(_ request: OSSystemExtensionRequest) {
        state = .working
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: OSSystemExtensionRequestDelegate

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension replacement: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let installed = properties.filter { $0.isEnabled && !$0.isUninstalling }.map(\.bundleVersion)
        Task { @MainActor in
            guard let embedded = self.embeddedVersion, !installed.isEmpty, !installed.contains(embedded) else { return }
            self.install()
        }
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in self.state = .needsApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in self.state = .finished }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let message = (error as NSError).localizedDescription
        Task { @MainActor in self.state = .failed(message) }
    }
}
