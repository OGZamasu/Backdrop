import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Backdrop").font(.headline)
                Spacer()
                if model.isStarting { ProgressView().controlSize(.small) }
                Toggle("Camera", isOn: Binding(get: { model.isOn }, set: { _ in model.toggle() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(model.isStarting)
                    .help("Turn the camera on or off (⌃⌥B)")
            }

            preview

            if let message = model.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SystemEffectsNotice()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Backgrounds").font(.subheadline.weight(.medium))
                    Spacer()
                    Menu {
                        Button("Generate with AI…", systemImage: "wand.and.stars") { openStudio(request: .generate) }
                        Button("Image or Video…", systemImage: "photo") { openStudio(request: .importFile) }
                        Button("Live Window…", systemImage: "macwindow") { openStudio(request: .liveWindow) }
                        Button("Screen", systemImage: "display") { model.addScreen() }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                BackgroundPicker(contentWidth: Self.width - Self.padding * 2)
            }

            LensPicker()

            VirtualCameraStatus()

            Divider()
            HStack {
                Button("Studio…") { openStudio() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.link)
        }
        .padding(Self.padding)
        .frame(width: Self.width)
    }

    private static let width: CGFloat = 380
    private static let padding: CGFloat = 14

    private var preview: some View {
        ZStack {
            PreviewView(relay: model.preview)
            if !model.isOn {
                VStack(spacing: 6) {
                    Image(systemName: "video.slash").font(.title)
                    Text("Camera is off").font(.callout)
                }
                .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(alignment: .bottomLeading) { SwitchingBadge() }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func openStudio(request: AppModel.StudioRequest? = nil) {
        if request != nil { model.studioPane = .backgrounds }
        model.studioRequest = request
        openWindow(id: "studio")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Tells people what to do next to get the new background into Zoom, Meet and the rest.
struct VirtualCameraStatus: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.virtualCameraInstalled {
            if model.isOn && !model.sinkConnected {
                Label("Connecting to Backdrop Camera…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Choose “Backdrop Camera” in Zoom, Meet, FaceTime or any other app.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            switch model.installer.state {
            case .finished:
                // macOS says it's installed, but this copy of Backdrop started before that and can't see the new camera yet.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Backdrop Camera is installed. Restart Backdrop to start using it.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Restart Backdrop") { model.relaunch() }.controlSize(.small)
                }
            case .needsApproval:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Almost there: approve Backdrop Camera in System Settings › General › Login Items & Extensions › Camera Extensions.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    .controlSize(.small)
                }
            case .working:
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Setting up…").font(.caption) }
            case .failed(let reason):
                VStack(alignment: .leading, spacing: 6) {
                    Text(reason).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") { model.installer.install() }.controlSize(.small)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Other apps can't see your new background yet. Backdrop Camera needs a one-time setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Set Up Backdrop Camera") { model.installer.install() }.controlSize(.small)
                }
            }
        }
    }
}

/// Shown when macOS's own Background or Portrait effect is on for Backdrop's camera input.
struct SystemEffectsNotice: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.systemEffectsOn {
            VStack(alignment: .leading, spacing: 6) {
                Label("macOS's Background or Portrait effect is on for Backdrop, so it will sit on top of your backdrop.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Video Effects…") { model.showVideoEffects() }.controlSize(.small)
            }
        }
    }
}
