import SwiftUI

// The parts of the Studio that stay put whichever pane is open: the camera switch, what is being shown, anything that
// needs attention, and the live preview the panes share.

/// The camera switch and what Backdrop is showing right now, at the top of the Studio's sidebar.
struct StudioCameraCard: View {
    @EnvironmentObject private var model: AppModel

    private var status: (text: String, color: Color) {
        if model.isStarting { return ("Starting…", .orange) }
        if !model.isOn { return ("Off", .secondary) }
        if !model.virtualCameraInstalled { return ("On, preview only", .orange) }
        if !model.sinkConnected { return ("On, connecting to Backdrop Camera…", .orange) }
        return ("On, live in Backdrop Camera", .green)
    }

    var body: some View {
        let status = status
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(status.color).frame(width: 8, height: 8)
                Text("Camera").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                if model.isStarting { ProgressView().controlSize(.small) }
                Toggle("Camera", isOn: Binding(get: { model.isOn }, set: { _ in model.toggle() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(model.isStarting)
                    .help("Turn the camera on or off (⌃⌥B)")
            }
            Text(status.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                showing("photo.on.rectangle.angled", model.selectedBackground.name, pane: model.isPresenting ? .present : .backgrounds)
                showing("face.smiling", model.selectedLens.map { "\($0.glyph) \($0.name)" } ?? "No lens", pane: .lenses)
                if model.isSharingScreen { sharing }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// Whether your screen is going out right now: a red dot while it is, so it is never a surprise.
    private var sharing: some View {
        let text: String, color: Color
        if !model.isOn { (text, color) = ("Screen ready to share", .secondary) }
        else if model.sharePaused { (text, color) = ("Sharing paused", .orange) }
        else if model.stageReport?.status == .lost { (text, color) = ("Shared window closed", .orange) }
        else { (text, color) = ("Sharing your screen", .red) }
        return Button { model.studioPane = .present } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(color.opacity(0.25)).frame(width: 12, height: 12)
                    Circle().fill(color).frame(width: 6, height: 6)
                }
                .frame(width: 14)
                Text(text).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption.weight(color == .red ? .semibold : .regular))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Go to Present")
        .accessibilityLabel(text)
    }

    /// One thing that is on the picture; a click opens the pane where it is chosen.
    private func showing(_ symbol: String, _ text: String, pane: StudioView.Pane) -> some View {
        Button { model.studioPane = pane } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).frame(width: 14).foregroundStyle(.secondary)
                Text(text).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Go to \(pane.rawValue)")
    }
}

/// Things that need attention, along the top of every pane: a problem, macOS's own effects fighting the backdrop,
/// or the virtual camera not being ready. Each is the Studio's version of a notice in the menu bar popover.
struct StudioBanners: View {
    @EnvironmentObject private var model: AppModel

    /// What to say about Backdrop Camera, when it is not ready. Settings has the whole story, so it says nothing there.
    private var cameraNotice: (text: String, tint: Color, action: String)? {
        if model.virtualCameraInstalled || model.studioPane == .settings { return nil }
        if model.cameraMissing { return ("macOS hasn't started Backdrop Camera yet.", .orange, "See How to Fix") }
        switch model.installer.state {
        case .idle: return ("Other apps can't see your backdrop until Backdrop Camera is set up.", .blue, "Set Up…")
        case .failed: return ("Setting up Backdrop Camera didn't work.", .orange, "Details")
        default: return ("Backdrop Camera isn't ready yet.", .blue, "Details")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message = model.message {
                StudioBanner(symbol: "exclamationmark.triangle.fill", tint: .orange, text: message, dismiss: { model.message = nil })
            }
            if model.systemEffectsOn {
                StudioBanner(symbol: "exclamationmark.triangle.fill", tint: .orange,
                             text: "macOS's Background or Portrait effect is on for Backdrop, so it will sit on top of your backdrop.",
                             action: ("Open Video Effects…", { model.showVideoEffects() }))
            }
            if let notice = cameraNotice {
                StudioBanner(symbol: "video.badge.ellipsis", tint: notice.tint, text: notice.text,
                             action: (notice.action, { model.studioPane = .settings }))
            }
        }
    }
}

private struct StudioBanner: View {
    let symbol: String
    let tint: Color
    let text: String
    var action: (title: String, run: () -> Void)?
    var dismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let action { Button(action.title, action: action.run).controlSize(.small) }
                if let dismiss {
                    Button(action: dismiss) { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help("Dismiss")
                        .accessibilityLabel("Dismiss")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(tint.opacity(0.12))
            Divider()
        }
    }
}

/// The live picture, or a prompt to turn the camera on. Shared by the panes that put the preview beside their controls.
struct StudioPreview: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            PreviewView(relay: model.preview)
            if !model.isOn {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash").font(.title)
                    Button("Turn On Camera") { model.turnOn() }.disabled(model.isStarting)
                }
                .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(alignment: .bottomLeading) { SwitchingBadge() }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
