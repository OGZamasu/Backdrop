import ImagePlayground
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case backgrounds = "Backgrounds", present = "Present", lenses = "Lenses", automation = "Automation", camera = "Camera", settings = "Settings"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .backgrounds: return "photo.on.rectangle.angled"
            case .present: return "rectangle.inset.filled.and.person.filled"
            case .lenses: return "face.smiling"
            case .automation: return "wand.and.stars"
            case .camera: return "camera.aperture"
            case .settings: return "gearshape"
            }
        }
        /// ⌘1 to ⌘6 jump between the panes.
        var key: KeyEquivalent {
            switch self {
            case .backgrounds: return "1"
            case .present: return "2"
            case .lenses: return "3"
            case .automation: return "4"
            case .camera: return "5"
            case .settings: return "6"
            }
        }
        /// What is on the picture, then how Backdrop itself is set up.
        static let content: [Pane] = [.backgrounds, .present, .lenses, .automation]
        static let setup: [Pane] = [.camera, .settings]
    }

    @EnvironmentObject private var model: AppModel

    // A fixed sidebar rather than NavigationSplitView: macOS can collapse that one on its own,
    // and then there is no way back to the other panes.
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                StudioBanners()
                Group {
                    switch model.studioPane {
                    case .backgrounds: BackgroundsTab()
                    case .present: PresentTab()
                    case .lenses: LensesTab()
                    case .automation: AutomationTab()
                    case .camera: CameraTab()
                    case .settings: SettingsTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 980, minHeight: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioCameraCard()
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Pane.content) { item in
                    SidebarItem(pane: item, selected: item == model.studioPane) { model.studioPane = item }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Setup")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
                ForEach(Pane.setup) { item in
                    SidebarItem(pane: item, selected: item == model.studioPane) { model.studioPane = item }
                }
            }
            Spacer()
            HStack {
                Text(AppInfo.versionText).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.link).font(.caption)
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// One pane in the Studio's sidebar, with a hover state and the selected one tinted.
private struct SidebarItem: View {
    let pane: StudioView.Pane
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(pane.rawValue, systemImage: pane.symbol)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(pane.key, modifiers: .command)
        .background(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.06 : 0),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Title and actions along the top of a pane. Lives in the pane itself rather than the window toolbar,
/// so there's nothing for the window to rearrange.
struct PaneHeader<Actions: View>: View {
    let title: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack {
            Text(title).font(.title2.bold())
            Spacer()
            actions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Backgrounds

struct BackgroundsTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingImporter = false
    @State private var showingGenerator = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Backgrounds") {
                Menu {
                    Button("Image or Video…", systemImage: "photo") { showingImporter = true }
                    Button("Window, Screen or Camera…", systemImage: "macwindow") { share() }
                    Divider()
                    Button("Generate with AI…", systemImage: "wand.and.stars") { showingGenerator = true }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .fixedSize()
            }
            Divider()
            HStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 18) {
                        ForEach(model.library.items) { background in
                            BackgroundTile(background: background)
                                .contextMenu {
                                    if background.origin != .builtIn {
                                        Button("Delete", role: .destructive) { model.delete(background.id) }
                                    }
                                }
                        }
                    }
                    .padding(20)
                }
                // Told to fill the space: without it the grid stops at the width it would like, and a wider window shows a gap.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                Inspector().frame(width: 320)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importFiles(urls) }
        }
        .sheet(isPresented: $showingGenerator) { GenerateSheet() }
        .onAppear { handle(model.studioRequest) }
        .onChange(of: model.studioRequest) { _, request in handle(request) }
    }

    /// Carries out an "Add" action chosen from the menu bar popover.
    private func handle(_ request: AppModel.StudioRequest?) {
        guard let request else { return }
        model.studioRequest = nil
        // Let the window finish appearing before presenting anything over it.
        DispatchQueue.main.async {
            switch request {
            case .importFile: showingImporter = true
            case .liveWindow, .share: share()
            case .generate: showingGenerator = true
            }
        }
    }

    /// Windows and screens are chosen and arranged in Present.
    private func share() {
        model.studioPane = .present
        model.studioRequest = .share
    }
}

private struct Inspector: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftName = ""

    var body: some View {
        let background = model.selectedBackground
        let editable = background.origin != .builtIn

        VStack(alignment: .leading, spacing: 14) {
            StudioPreview()

            VStack(alignment: .leading, spacing: 6) {
                if editable {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.rename(background.id, to: draftName) }
                } else {
                    Text(background.name).font(.headline)
                }
                Text(describe(background)).font(.caption).foregroundStyle(.secondary)
                if let prompt = background.prompt {
                    Text("“\(prompt)”").font(.caption).italic().foregroundStyle(.secondary)
                }
            }

            if editable {
                Toggle("Parallax", isOn: Binding(get: { background.parallax }, set: { model.setParallax($0, for: background.id) }))
                    .help("The background drifts gently as you move, which adds depth.")
                Button("Delete Background", role: .destructive) { model.delete(background.id) }
                    .buttonStyle(.link)
            }
            Spacer()
        }
        .padding(16)
        .onAppear { draftName = background.name }
        .onChange(of: background.id) { draftName = model.selectedBackground.name }
    }

    private func describe(_ background: Background) -> String {
        switch background.kind {
        case .passthrough: return "Your camera, untouched."
        case .blur: return "Your room, out of focus."
        case .gradient: return "A slowly shifting colour wash."
        case .solid: return "A plain studio colour."
        case .treated(let treatment): return treatment.blurb
        case .procedural(let style): return style.blurb
        case .pipes: return "The old Windows screensaver, growing behind you."
        case .maze: return "The old Windows maze screensaver: a walk through brick corridors."
        case .image: return background.origin == .generated ? "Generated on this Mac." : "A still image."
        case .video: return "A looping video."
        case .window: return "A live window. Arrange it in Present."
        case .display, .screen: return "Your screen. Arrange it in Present."
        case .camera: return "A second camera. Arrange it in Present."
        }
    }
}

// MARK: - Sheets

private struct GenerateSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var showingPlayground = false

    private let ideas = [
        "A cozy home library with warm lamps",
        "A bright minimalist studio with soft daylight",
        "A modern office with plants and big windows",
        "A cabin with a view of a snowy forest",
        "A rooftop terrace at sunset",
        "A space station window looking at Earth",
    ]

    private var trimmed: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var available: Bool { ImagePlaygroundViewController.isAvailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generate a Background").font(.title2.bold())
            Text("Describe the room you'd like behind you. Image Playground creates it on this Mac and lets you choose your favourite.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("A sunlit loft with plants and a bookshelf", text: $prompt, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(ideas, id: \.self) { idea in
                        Button(idea) { prompt = idea }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }

            if !available {
                Label("Image Playground isn't available on this Mac. Turn on Apple Intelligence in System Settings to use it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Generate…") { showingPlayground = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || !available)
            }
        }
        .padding(24)
        .frame(width: 540)
        // Appended so it comes out as an empty scene rather than a portrait of someone.
        .imagePlaygroundSheet(isPresented: $showingPlayground, concept: "\(trimmed), empty scene with no people") { url in
            model.saveGenerated(from: url, prompt: trimmed)
            dismiss()
        }
        .modifier(WideOutput())
    }
}

/// Ask for 16:9 where the OS supports it, so there's nothing to crop away.
private struct WideOutput: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 27, *) {
            var options = ImagePlaygroundOptions()
            options.sizeSpecification = .closest(to: CGSize(width: 1920, height: 1080))
            return AnyView(content.imagePlaygroundOptions(options))
        }
        return AnyView(content)
    }
}

// MARK: - Automation

struct AutomationTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var adding: RuleKind?

    enum RuleKind: String, Identifiable {
        case app, calendar, time
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Automation") {
                Menu {
                    Button("When I'm using an app…", systemImage: "app") { adding = .app }
                    Button("During calendar events…", systemImage: "calendar") { adding = .calendar }
                    Button("At certain times…", systemImage: "clock") { adding = .time }
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .fixedSize()
            }
            Divider()
            if model.rules.rules.isEmpty {
                ContentUnavailableView {
                    Label("No rules yet", systemImage: "wand.and.stars")
                } description: {
                    Text("Switch backgrounds for you: a tidy one when Zoom is open, a fun one for the team call, something calm after hours.")
                }
                .frame(maxHeight: .infinity)
            } else {
                RuleList(store: model.rules)
            }
            Divider()
            shortcuts.padding(14)
        }
        .sheet(item: $adding) { AddRuleSheet(kind: $0) }
    }

    private var shortcuts: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Rules run when something changes, such as switching apps or a meeting starting. Picking a background by hand holds until the next change.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button("Keyboard Shortcuts…") { model.studioPane = .settings }.buttonStyle(.link).font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RuleList: View {
    @ObservedObject var store: RuleStore
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            ForEach($store.rules) { $rule in
                HStack(spacing: 12) {
                    Toggle("Enabled", isOn: $rule.isEnabled).labelsHidden()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(for: rule.trigger))
                        if let hint = hint(for: rule.trigger) { Text(hint).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Picker("Background", selection: $rule.backgroundID) {
                        ForEach(model.library.items) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    Button { store.remove(rule.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Delete rule")
                }
                .opacity(rule.isEnabled ? 1 : 0.5)
                .padding(.vertical, 4)
            }
        }
    }

    private func title(for trigger: AutomationRule.Trigger) -> String {
        switch trigger {
        case .app(_, let name): return "When I'm using \(name)"
        case .calendar(let keyword):
            let word = keyword.trimmingCharacters(in: .whitespaces)
            return word.isEmpty ? "During any calendar event" : "During events containing “\(word)”"
        case .time(let start, let end): return "From \(clock(start)) to \(clock(end))"
        }
    }

    private func hint(for trigger: AutomationRule.Trigger) -> String? {
        switch trigger {
        case .app: return "Stays until you switch to another app that has a rule."
        case .calendar: return model.calendarAccessLabel
        case .time: return nil
        }
    }

    private func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct AddRuleSheet: View {
    let kind: AutomationTab.RuleKind
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var backgroundID = Background.softBlur.id
    @State private var apps: [(id: String, name: String)] = []
    @State private var appID = ""
    @State private var keyword = ""
    @State private var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
    @State private var end = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date())!
    @State private var calendarDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading).font(.title2.bold())

            Form {
                switch kind {
                case .app:
                    Picker("App", selection: $appID) {
                        ForEach(apps, id: \.id) { Text($0.name).tag($0.id) }
                    }
                case .calendar:
                    TextField("Event title contains", text: $keyword, prompt: Text("Leave empty for any event"))
                    if calendarDenied {
                        Text("Calendar access is off. Allow Backdrop in System Settings › Privacy & Security › Calendars.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                case .time:
                    DatePicker("From", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: $end, displayedComponents: .hourAndMinute)
                }
                Picker("Use background", selection: $backgroundID) {
                    ForEach(model.library.items) { Text($0.name).tag($0.id) }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Rule") { Task { await add() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(kind == .app && appID.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear(perform: loadApps)
    }

    private var heading: String {
        switch kind {
        case .app: return "When I'm using an app"
        case .calendar: return "During calendar events"
        case .time: return "At certain times"
        }
    }

    private func loadApps() {
        let me = Bundle.main.bundleIdentifier
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != me }
            .compactMap { app in app.bundleIdentifier.map { (id: $0, name: app.localizedName ?? $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        appID = apps.first?.id ?? ""
    }

    private func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func add() async {
        let trigger: AutomationRule.Trigger
        switch kind {
        case .app:
            trigger = .app(bundleID: appID, appName: apps.first { $0.id == appID }?.name ?? appID)
        case .calendar:
            guard await model.requestCalendarAccess() else { calendarDenied = true; return }
            trigger = .calendar(keyword: keyword)
        case .time:
            trigger = .time(startMinute: minutes(start), endMinute: minutes(end))
        }
        model.rules.rules.append(AutomationRule(trigger: trigger, backgroundID: backgroundID))
        dismiss()
    }
}
