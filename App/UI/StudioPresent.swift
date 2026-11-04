import SwiftUI

/// Sharing a window or your screen into the call, and arranging it: behind you, as a panel floating in the room, or filling the
/// picture with you over it. The live preview sits beside the controls and can be grabbed with the mouse; with "Control with your
/// hands" on, a pinch in the air does the same.
struct PresentTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingPicker = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Present") {
                if model.isSharingScreen {
                    Button { model.togglePause() } label: {
                        Label(model.sharePaused ? "Resume Sharing" : "Pause Sharing", systemImage: model.sharePaused ? "play.fill" : "pause.fill")
                    }
                    .help(model.sharePaused ? "Show your screen again (⌃⌥P)" : "Show a calm “Paused” card instead of your screen (⌃⌥P)")
                }
                Button { model.resetStage() } label: { Label("Reset Layout", systemImage: "arrow.counterclockwise") }
                    .help("The panel, you and the look back to how they started")
            }
            Divider()
            HStack(spacing: 0) {
                form.frame(minWidth: 430)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        PresentPreview()
                        Text(previewHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider().padding(.vertical, 4)
                        Text("How it works").font(.headline)
                        PresentHowTo()
                    }
                    .padding(16)
                }
                .frame(width: 360)
            }
        }
        .sheet(isPresented: $showingPicker) { SharePickerSheet() }
        .onAppear {
            model.refreshScreenRecording()
            handle(model.studioRequest)
        }
        .onChange(of: model.studioRequest) { _, request in handle(request) }
    }

    private var previewHint: String {
        if !model.isSharingScreen { return "Share a window or screen to see it here." }
        if !model.stage.arrangement.isArranged { return "Choose Floating Panel or Presenter to move and resize your screen and yourself." }
        return "Drag to move. Pinch or scroll to resize. Double-click to zoom. The preview shows what everyone on the call sees, so your slides read the right way round."
    }

    private func handle(_ request: AppModel.StudioRequest?) {
        guard request == .share || request == .liveWindow else { return }
        model.studioRequest = nil
        DispatchQueue.main.async { showingPicker = true }
    }

    // MARK: The form

    private var form: some View {
        Form {
            sharing
            arrangement
            if model.stage.arrangement == .floatingPanel { panel }
            if model.stage.arrangement.isArranged { you }
            hands
        }
        .formStyle(.grouped)
    }

    private var sharing: some View {
        Section {
            if !model.screenRecordingAllowed && !model.isSharingScreen {
                ScreenPermissionCard()
                Button("Choose Window or Screen…") { showingPicker = true }.buttonStyle(.link)
            } else if !model.isSharingScreen {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing is shared yet").font(.headline)
                    Text("Pick a window (your slides, a browser tab, a design) or a whole screen. It goes out through Backdrop Camera, so it works in any call.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Choose Window or Screen…") { showingPicker = true }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
            } else {
                SharedSourceRow(change: { showingPicker = true })
                if model.stageReport?.status == .denied { ScreenPermissionCard() }
                Toggle("Show the pointer", isOn: $model.captureShowsCursor)
                Picker("Frame rate", selection: $model.captureFrameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                Toggle("Name under the panel", isOn: binding(\.showsLabel))
                    .disabled(model.stage.arrangement != .floatingPanel)
                    .help("A small label with the window’s name, under the floating panel")
            }
        } header: {
            Text("Sharing")
        } footer: {
            Text(model.isSharingScreen
                 ? "60 fps is smoother for scrolling and video, and uses more power. Pause with ⌃⌥P from any app: everyone sees a calm “Paused” card until you resume."
                 : "Only what you pick is shared, and Backdrop’s own windows are always left out.")
        }
    }

    private var arrangement: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                ForEach(StageArrangement.allCases) { kind in
                    ArrangementCard(arrangement: kind, layout: sketch(for: kind), selected: model.stage.arrangement == kind) {
                        withAnimation(.easeOut(duration: 0.2)) { model.setArrangement(kind) }
                    }
                }
            }
            .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("Presets").font(.subheadline.weight(.medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(StagePreset.allCases) { preset in
                        PresetChip(preset: preset, base: model.stage, selected: preset.matches(model.stage)) { model.applyPreset(preset) }
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Arrangement")
        } footer: {
            Text(model.stage.arrangement.blurb + " Each arrangement remembers where you left things.")
        }
    }

    /// What each card shows: the layout that arrangement would have, as remembered.
    private func sketch(for kind: StageArrangement) -> StageLayout {
        if kind == model.stage.arrangement { return model.stage }
        var memory = StageMemory(current: model.stage)
        memory.switchTo(kind)
        return memory.current
    }

    private var panel: some View {
        Section {
            slider("Size", value: frameBinding(\.panel), range: StageLayout.panelSizes, format: Self.percent)
            slider("Tilt", value: binding(\.tilt), range: 0...1, format: Self.amount)
            slider("Depth", value: binding(\.depth), range: 0...1, format: Self.amount)
            slider("Corners", value: binding(\.roundness), range: 0...1, format: Self.amount)
            slider("Shadow", value: binding(\.shadow), range: 0...1, format: Self.amount)
            Picker("Around the panel", selection: binding(\.surround)) {
                ForEach(StageSurround.allCases) { Text($0.title).tag($0) }
            }
            if model.stage.surround == .backdrop {
                Picker("Backdrop", selection: Binding(get: { model.stage.surroundBackdrop ?? Self.defaultSurround },
                                                      set: { id in model.updateStage { $0.surroundBackdrop = id } })) {
                    ForEach(model.surroundChoices) { Text($0.name).tag($0.id) }
                }
            }
        } header: {
            Text("Panel")
        } footer: {
            Text("Tilt turns the panel toward the middle as it moves to the side. Depth shifts it a little as you move your head, as a real screen behind you would.")
        }
    }

    private static var defaultSurround: UUID { Background.builtIns.first { $0.kind == .gradient(.midnight) }?.id ?? Background.softBlur.id }

    private var you: some View {
        Section {
            if model.stage.arrangement == .presenter {
                Picker("Show me as", selection: binding(\.presenterStyle)) {
                    ForEach(PresenterStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            slider("Size", value: frameBinding(\.presenter), range: model.stage.presenterSizes, format: Self.percent)
            LabeledContent("Position") {
                Button("Put Me Back") {
                    model.updateStage { layout in
                        layout.presenter = layout.arrangement == .presenter ? StageMemory.starting(.presenter, from: layout).presenter : .identity
                        layout.restorePresenter = nil
                    }
                }
            }
        } header: {
            Text("You")
        } footer: {
            Text(model.stage.arrangement == .presenter
                 ? "Drag yourself on the preview, or pinch near yourself with hand control on. A bubble frames your head and shoulders and keeps up as you move."
                 : "You stand in front of the panel. Drag yourself on the preview to stand somewhere else; your hands move only the panel here.")
        }
    }

    private var hands: some View {
        Section {
            Toggle("Control with your hands", isOn: binding(\.handControl))
                .disabled(!model.stage.arrangement.isArranged)
            if model.stage.handControl { HandTrackingIndicator() }
            Toggle("Snap to guides", isOn: binding(\.snapping))
        } header: {
            Text("Hands")
        } footer: {
            Text("Pinch near the panel to grab it, pinch with both hands to resize, and double pinch to zoom. Only a pinch held still for a moment grabs, so talking with your hands moves nothing. The cursors and guides appear only in your preview, never in the call.")
        }
    }

    // MARK: Helpers

    private static let percent: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }
    private static let amount: (Double) -> String = { "\(Int(($0 * 100).rounded()))" }

    private func binding<T>(_ path: WritableKeyPath<StageLayout, T>) -> Binding<T> {
        Binding(get: { model.stage[keyPath: path] }, set: { value in model.updateStage { $0[keyPath: path] = value } })
    }

    private func frameBinding(_ path: WritableKeyPath<StageLayout, StageFrame>) -> Binding<Double> {
        Binding(get: { model.stage[keyPath: path].size }, set: { value in model.updateStage { $0[keyPath: path].size = value } })
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: value, in: range).frame(minWidth: 120, idealWidth: 180, maxWidth: 220)
                Text(format(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

/// What is being shared: its icon, its name, how it is doing, and buttons to change or stop it.
private struct SharedSourceRow: View {
    @EnvironmentObject private var model: AppModel
    let change: () -> Void

    var body: some View {
        let background = model.selectedBackground
        HStack(spacing: 12) {
            icon(for: background)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(background.name).font(.headline).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 5) {
                    let s = ShareStatusPill.describe(model)
                    Circle().fill(s.color).frame(width: 6, height: 6)
                    Text(detail(s.text)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Change…", action: change)
            Button("Stop Sharing") { model.stopSharing() }
        }
        .padding(.vertical, 2)
    }

    private func detail(_ status: String) -> String {
        switch model.stageReport?.status {
        case .lost?: return "Window closed. It comes back here when it’s open again."
        case .denied?: return "Screen Recording is off for Backdrop."
        default: return model.isOn ? status : "Ready. Turn the camera on to share it."
        }
    }

    @ViewBuilder private func icon(for background: Background) -> some View {
        switch background.kind {
        case .window(let bundleID, _, _):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "macwindow").font(.title2).foregroundStyle(.secondary)
            }
        default:
            Image(systemName: "display").font(.title2).foregroundStyle(.secondary)
        }
    }
}
