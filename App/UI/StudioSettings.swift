import AVFoundation
import AppKit
import EventKit
import SwiftUI

/// Everything about how Backdrop itself behaves, in one place: startup, shortcuts, the virtual camera, permissions, where
/// things are kept, and the app's own details.
struct SettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var permissions = PermissionStatus()
    @State private var confirmingReset = false
    @State private var confirmingRemoval = false

    /// The global shortcuts. The same list is registered in AppModel.registerHotkeys; keep them in step.
    static let shortcuts: [(keys: [String], title: String)] = [
        (["⌃", "⌥", "→"], "Next background"),
        (["⌃", "⌥", "←"], "Previous background"),
        (["⌃", "⌥", "↑"], "Next lens"),
        (["⌃", "⌥", "↓"], "Previous lens"),
        (["⌃", "⌥", "R"], "New game"),
        (["⌃", "⌥", "P"], "Pause or resume screen sharing"),
        (["⌃", "⌥", "B"], "Camera on or off"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Settings") { EmptyView() }
            Divider()
            Form {
                general
                shortcuts
                backdropCamera
                PermissionsSection(permissions: permissions)
                files
                reset
                about
            }
            .formStyle(.grouped)
        }
        .onAppear { permissions.refresh() }
        // Permissions are changed in System Settings, so look again when coming back from there.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
        .confirmationDialog("Reset settings?", isPresented: $confirmingReset) {
            Button("Reset Settings", role: .destructive) { model.resetSettings() }
        } message: {
            Text("The camera choice, cutout and look, on-screen messages and shortcuts go back to how they started. Your backgrounds, lenses, rules and scores are kept.")
        }
        .confirmationDialog("Remove Backdrop Camera?", isPresented: $confirmingRemoval) {
            Button("Remove Backdrop Camera", role: .destructive) { model.installer.uninstall() }
        } message: {
            Text("Other apps will stop seeing it. macOS may ask for your password. You can set it up again here at any time.")
        }
    }

    // MARK: Sections

    private var general: some View {
        Section {
            Toggle("Open Backdrop at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            Toggle("Show on-screen messages", isOn: $model.showsOnScreenMessages)
            Toggle("Keyboard shortcuts", isOn: $model.shortcutsEnabled)
        } header: {
            Text("General")
        } footer: {
            Text("At login Backdrop opens quietly in the menu bar. On-screen messages are the small label near the bottom of the screen when a shortcut changes your background or lens.")
        }
    }

    private var shortcuts: some View {
        Section {
            ForEach(Self.shortcuts, id: \.title) { shortcut in
                LabeledContent(shortcut.title) { KeyCaps(keys: shortcut.keys) }
            }
            .opacity(model.shortcutsEnabled ? 1 : 0.4)
            if model.shortcutsTaken && model.shortcutsEnabled {
                Label("Another app already uses some of these, so they won't work until it lets go of them.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Keyboard shortcuts")
        } footer: {
            Text(model.shortcutsEnabled
                 ? "They work in any app, so you can change your backdrop in the middle of a call."
                 : "Switched off. The keys belong to other apps again.")
        }
    }

    private var backdropCamera: some View {
        Section {
            LabeledContent("Status") { Text(cameraStatus.text).foregroundStyle(cameraStatus.color) }
            VirtualCameraStatus()
            if model.virtualCameraInstalled {
                LabeledContent("Camera Extensions") {
                    Button("Open in System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                }
                LabeledContent("Restart") {
                    Button("Restart Backdrop") { model.relaunch() }
                }
                Button("Remove Backdrop Camera…", role: .destructive) { confirmingRemoval = true }
            }
        } header: {
            Text("Backdrop Camera")
        } footer: {
            Text("The virtual camera that Zoom, Meet, Discord, FaceTime and other apps pick. Restarting Backdrop helps when macOS hasn't noticed the camera yet.")
        }
    }

    private var files: some View {
        Section {
            folder("Backgrounds", url: model.library.directory) { model.showBackgroundsFolder() }
            folder("Lenses", url: model.lensLibrary.directory) { model.lensLibrary.showFolder() }
        } header: {
            Text("Your files")
        } footer: {
            Text("Imported and generated backgrounds, and your own lenses. Lenses are folders you can copy and edit.")
        }
    }

    private var reset: some View {
        Section {
            Button("Reset Settings…") { confirmingReset = true }
        } footer: {
            Text("Puts the camera choice, cutout and look, on-screen messages and shortcuts back to how they started.")
        }
    }

    private var about: some View {
        Section("About") {
            LabeledContent("Backdrop") { Text(AppInfo.versionText).foregroundStyle(.secondary) }
            LabeledContent("Source and releases") {
                Link("github.com/OGZamasu/Backdrop", destination: AppInfo.repository)
            }
            LabeledContent("Quit") {
                Button("Quit Backdrop") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    // MARK: Helpers

    private var cameraStatus: (text: String, color: Color) {
        if model.cameraMissing { return ("Installed, but macOS hasn't started it", .orange) }
        guard model.virtualCameraInstalled else { return ("Not set up", .secondary) }
        if !model.isOn { return ("Ready. Turn the camera on to use it", .secondary) }
        return model.sinkConnected ? ("Live", .green) : ("Connecting…", .orange)
    }

    private func folder(_ title: String, url: URL, show: @escaping () -> Void) -> some View {
        LabeledContent {
            Button("Show in Finder", action: show)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text((url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

/// What the app is, read from its own bundle.
enum AppInfo {
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    static let repository = URL(string: "https://github.com/OGZamasu/Backdrop")!
}

/// A shortcut drawn as little keys.
private struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, 2)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

// MARK: - Permissions

/// What macOS has allowed Backdrop to do. It is read without asking, so looking at this pane never shows a prompt.
@MainActor
final class PermissionStatus: ObservableObject {
    enum State { case allowed, notAsked, blocked }

    @Published private(set) var camera = State.notAsked
    @Published private(set) var calendar = State.notAsked
    @Published private(set) var screen = State.notAsked

    func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: camera = .allowed
        case .notDetermined: camera = .notAsked
        default: camera = .blocked
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: calendar = .allowed
        case .notDetermined: calendar = .notAsked
        default: calendar = .blocked
        }
        // There is no way to tell "never asked" from "refused" for the screen, and no way to ask without a prompt.
        screen = CGPreflightScreenCaptureAccess() ? .allowed : .notAsked
    }
}

private struct PermissionsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var permissions: PermissionStatus

    var body: some View {
        Section {
            row("Camera", "Reads your camera to cut you out.", permissions.camera, pane: "Privacy_Camera") {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            row("Calendars", "Lets rules switch your background during meetings.", permissions.calendar, pane: "Privacy_Calendars") {
                _ = await model.requestCalendarAccess()
            }
            row("Screen Recording", "Needed to use a window or your screen as a background.", permissions.screen, pane: "Privacy_ScreenCapture", ask: nil)
        } header: {
            Text("Permissions")
        } footer: {
            Text("Backdrop asks only when a feature needs something. Changes are made in System Settings › Privacy & Security.")
        }
    }

    private func row(_ title: String, _ detail: String, _ state: PermissionStatus.State, pane: String,
                     ask: (() async -> Void)?) -> some View {
        LabeledContent {
            switch state {
            case .allowed:
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
            case .notAsked where ask != nil:
                Button("Allow…") {
                    Task {
                        await ask?()
                        permissions.refresh()
                    }
                }
            default:
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
