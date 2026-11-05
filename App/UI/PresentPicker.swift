import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// What can be shared right now, with small live pictures of each, refreshed every few seconds while the picker is open.
@MainActor
final class ShareCatalog: ObservableObject {
    @Published private(set) var windows: [WindowChoice] = []
    @Published private(set) var displays: [DisplayChoice] = []
    /// Keyed by `key(window:)` and `key(display:)`.
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var loading = true
    /// macOS has not let Backdrop see the screen.
    @Published private(set) var denied = false
    private var content: SCShareableContent?
    private var refresher: Task<Void, Never>?

    static func key(window id: CGWindowID) -> String { "w\(id)" }
    static func key(display id: CGDirectDisplayID) -> String { "d\(id)" }

    /// Looks for windows and screens. The first time ever, this is what makes macOS ask for Screen Recording.
    func load() async {
        do {
            let found = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            content = found
            windows = AppModel.windows(in: found)
            denied = false
        } catch {
            content = nil
            windows = []
            denied = !CGPreflightScreenCaptureAccess()
        }
        displays = AppModel.displays()
        loading = false
        await refreshThumbnails()
    }

    /// Keeps the pictures fresh while the picker is open.
    func startLive() {
        refresher?.cancel()
        refresher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await self?.refreshThumbnails()
            }
        }
    }

    func stop() { refresher?.cancel() }

    private func refreshThumbnails() async {
        guard let content else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let ours = content.windows.filter { $0.owningApplication?.processID == me }
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: ours)
            if let image = await Self.capture(filter, size: CGSize(width: display.width, height: display.height)) {
                thumbnails[Self.key(display: display.displayID)] = image
            }
        }
        let wanted = Set(windows.map(\.id))
        for window in content.windows where wanted.contains(window.windowID) {
            guard !Task.isCancelled else { return }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = await Self.capture(filter, size: window.frame.size) {
                thumbnails[Self.key(window: window.windowID)] = image
            }
        }
    }

    private static func capture(_ filter: SCContentFilter, size: CGSize) async -> NSImage? {
        let configuration = SCStreamConfiguration()
        let scale = min(1, 480 / max(size.width, size.height, 1))
        configuration.width = max(2, Int(size.width * scale * 2))
        configuration.height = max(2, Int(size.height * scale * 2))
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2))
    }
}

/// The picker for what to share: screens first, then cameras, then every window grouped by its app. Screens and windows have a live
/// picture; cameras do not, since looking would turn every camera on. A search narrows all of them.
struct SharePickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var catalog = ShareCatalog()
    @State private var search = ""
    @State private var selection: Choice?

    enum Choice: Hashable {
        case window(CGWindowID)
        case display(CGDirectDisplayID)
        case camera(String)
    }

    private var groups: [(app: String, bundleID: String, windows: [WindowChoice])] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let shown = catalog.windows.filter {
            query.isEmpty || $0.appName.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query)
        }
        var order: [String] = []
        var byApp: [String: [WindowChoice]] = [:]
        for window in shown {
            if byApp[window.bundleID] == nil { order.append(window.bundleID) }
            byApp[window.bundleID, default: []].append(window)
        }
        return order.compactMap { id in byApp[id].map { (app: $0[0].appName, bundleID: id, windows: $0) } }
    }

    private var shownCameras: [CameraChoice] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return model.extraCameras.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.kind.label.localizedCaseInsensitiveContains(query)
                || "camera".contains(query.lowercased())
        }
    }

    private var cameraSelected: Bool {
        if case .camera? = selection { return true }
        return false
    }

    private var shownDisplays: [DisplayChoice] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return catalog.displays.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || "screen".contains(query.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Share a Window, Screen or Camera").font(.title2.bold())
                Text("It goes out through Backdrop Camera, so it works in Discord, Zoom or any other app. Backdrop’s own windows are always left out, and a second camera is only on while it is showing.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 14)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()

            HStack {
                if case .window? = selection {
                    Text("Tip: resize the window and the panel follows its shape.").font(.caption).foregroundStyle(.secondary)
                } else if cameraSelected {
                    Text("Tip: float it as a panel, or put it behind you, and move it with your hands.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(cameraSelected ? "Show" : "Share") { share() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            .padding(16)
        }
        .frame(width: 760, height: 600)
        .task {
            await catalog.load()
            catalog.startLive()
            model.refreshScreenRecording()
        }
        .onDisappear { catalog.stop() }
    }

    @ViewBuilder private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if catalog.loading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for windows…").foregroundStyle(.secondary)
                    }
                } else if catalog.denied {
                    ScreenPermissionCard(compact: true)
                        .padding(14)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    screensSection
                }
                camerasSection
                if !catalog.loading && !catalog.denied { windowSections }
            }
            .padding(24)
        }
    }

    @ViewBuilder private var screensSection: some View {
        if !shownDisplays.isEmpty {
            section(title: shownDisplays.count > 1 ? "Screens" : "Your Screen", icon: Image(systemName: "display")) {
                ForEach(shownDisplays) { display in
                    ShareCard(title: display.name, subtitle: "\(Int(display.size.width)) × \(Int(display.size.height))" + (display.isMain ? " · Main" : ""),
                              image: catalog.thumbnails[ShareCatalog.key(display: display.id)], aspect: display.size.width / max(display.size.height, 1),
                              placeholder: Image(systemName: "display"), selected: selection == .display(display.id)) {
                        selection = .display(display.id)
                    } onDouble: {
                        selection = .display(display.id)
                        share()
                    }
                }
            }
        }
    }

    /// Second cameras: not the main camera, and not Backdrop's own. No live picture, since that would turn every camera on.
    @ViewBuilder private var camerasSection: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        if !shownCameras.isEmpty || query.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                section(title: "Cameras", icon: Image(systemName: "video")) {
                    ForEach(shownCameras) { camera in
                        ShareCard(title: camera.name, subtitle: camera.kind.label, image: nil, aspect: 16.0 / 9,
                                  placeholder: Image(systemName: camera.kind.symbol), selected: selection == .camera(camera.id)) {
                            selection = .camera(camera.id)
                        } onDouble: {
                            selection = .camera(camera.id)
                            share()
                        }
                    }
                }
                if model.extraCameras.isEmpty {
                    Text("No second camera found. Plug one in, or connect an iPhone as a Continuity Camera, and it appears here. Your main camera is left out.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("A camera turns on only when it is showing. Your main camera is left out.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video)) {
                    CameraPermissionCard()
                }
            }
        }
    }

    @ViewBuilder private var windowSections: some View {
        ForEach(groups, id: \.bundleID) { group in
            section(title: group.app, icon: appIcon(group.bundleID).map { Image(nsImage: $0) } ?? Image(systemName: "app")) {
                ForEach(group.windows) { window in
                    ShareCard(title: window.title.isEmpty ? window.appName : window.title, subtitle: nil,
                              image: catalog.thumbnails[ShareCatalog.key(window: window.id)], aspect: window.size.width / max(window.size.height, 1),
                              placeholder: appIcon(window.bundleID).map { Image(nsImage: $0) } ?? Image(systemName: "macwindow"),
                              selected: selection == .window(window.id)) {
                        selection = .window(window.id)
                    } onDouble: {
                        selection = .window(window.id)
                        share()
                    }
                }
            }
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        if groups.isEmpty && shownCameras.isEmpty && shownDisplays.isEmpty && !query.isEmpty {
            Text("Nothing matches “\(search)”.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30)
        } else if catalog.windows.isEmpty && query.isEmpty {
            Text("No other windows are open. Open the window you want to share, and it appears here.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 10)
        }
    }

    private func section<Cards: View>(title: String, icon: Image, @ViewBuilder cards: () -> Cards) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                icon.resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18).foregroundStyle(.secondary)
                Text(title).font(.headline)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)], alignment: .leading, spacing: 14) { cards() }
        }
    }

    private func appIcon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private func share() {
        switch selection {
        case .window(let id)?:
            if let choice = catalog.windows.first(where: { $0.id == id }) { model.addWindow(choice) }
        case .display(let id)?:
            if let choice = catalog.displays.first(where: { $0.id == id }) { model.addScreen(choice) }
        case .camera(let id)?:
            if let choice = model.extraCameras.first(where: { $0.id == id }) { model.addCamera(choice) }
        case nil:
            return
        }
        dismiss()
    }
}

/// One window or screen in the picker: its live picture in its own shape, and its name.
private struct ShareCard: View {
    let title: String
    let subtitle: String?
    let image: NSImage?
    let aspect: CGFloat
    let placeholder: Image
    let selected: Bool
    let onTap: () -> Void
    let onDouble: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.28))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .padding(8)
                        .transition(.opacity)
                } else {
                    placeholder.resizable().aspectRatio(contentMode: .fit).frame(width: 34, height: 34).foregroundStyle(.secondary).opacity(0.8)
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.25 : 0.1), lineWidth: selected ? 3 : 1)
            )
            .animation(.easeOut(duration: 0.2), value: image != nil)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(selected ? .semibold : .regular)).lineLimit(1).truncationMode(.middle)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onDouble)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Screen Recording is not allowed yet: says so plainly and goes straight to the right place in System Settings.
struct ScreenPermissionCard: View {
    @EnvironmentObject private var model: AppModel
    var compact = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.16))
                Image(systemName: "rectangle.dashed.badge.record").font(.system(size: compact ? 17 : 24, weight: .medium)).foregroundStyle(.orange)
            }
            .frame(width: compact ? 38 : 54, height: compact ? 38 : 54)
            VStack(alignment: .leading, spacing: 6) {
                Text("Backdrop can’t see your screen yet").font(compact ? .headline : .title3.bold())
                Text("To share a window or your screen, turn on Backdrop under Screen Recording in System Settings. macOS may ask you to reopen Backdrop afterwards.")
                    .font(compact ? .callout : .body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Open Settings") { model.openScreenRecordingSettings() }.buttonStyle(.borderedProminent)
                    Button("Check Again") { model.refreshScreenRecording() }
                }
                .controlSize(compact ? .small : .regular)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, compact ? 4 : 0)
    }
}

/// Camera access is off, so a second camera cannot open: says so and goes to the right place in System Settings.
struct CameraPermissionCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "video.slash.fill").font(.system(size: 18, weight: .medium)).foregroundStyle(.orange).frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text("Backdrop can’t use cameras yet").font(.headline)
                Text("Turn on Backdrop under Camera in System Settings › Privacy & Security.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
