import SwiftUI
import UniformTypeIdentifiers

// The lens picker as the app shows it: the shared views in Engine/LensPreview, fed from the app model.

extension AppModel {
    /// Everything the lens picker shows, as it is now.
    func lensBrowserData(recents: [String]) -> LensBrowserData {
        LensBrowserData(lenses: lensLibrary.all, favourites: lensLibrary.favourites, recents: recents, selectedID: lensID,
                        bestScore: { [weak self] id in self?.bestScore(for: id) ?? 0 })
    }

    /// What the lens picker's buttons and menus do.
    var lensBrowserActions: LensBrowserActions {
        LensBrowserActions(
            select: { [weak self] id in self?.selectLens(id) },
            toggleFavourite: { [weak self] id in self?.lensLibrary.toggleFavourite(id) },
            reveal: { [weak self] info in self?.lensLibrary.reveal(info) },
            trash: { [weak self] info in
                guard let self else { return }
                if self.lensID == info.id { self.selectLens(nil) }
                self.lensLibrary.trash(info)
            })
    }
}

/// Keeps the lens picker's helpers in step with the app: recent lenses noted as they are used, and thumbnails made more gently
/// while the camera is on.
private struct LensBrowserUpkeep: ViewModifier {
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        content
            .onAppear {
                LensBrowserRecents.shared.follow(model.$lensID)
                LensThumbnailStore.shared.cameraBusy = model.isOn
            }
            .onChange(of: model.isOn) { _, on in LensThumbnailStore.shared.cameraBusy = on }
    }
}

/// "Switching to Maze…", shown over a preview from the moment something is chosen until it is actually on the picture.
struct SwitchingBadge: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let name = model.switching {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Switching to \(name)…").font(.caption.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .padding(8)
            .transition(.opacity)
        }
    }
}

/// What the current lens is saying, with a new-game button for games.
struct LensStatusLine: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let info = model.selectedLens {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if !model.isOn {
                        Text("Turn the camera on to use \(info.name).").font(.caption.weight(.semibold))
                    } else if let status = model.lensStatus {
                        Text(status.title).font(.caption.weight(.semibold))
                        if let detail = status.detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                    } else {
                        Text(info.name).font(.caption.weight(.semibold))
                    }
                }
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if info.scored {
                    Button("New Game") { model.restartLens() }.controlSize(.small).help("Start again (⌃⌥R)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// The lens section of the menu bar popover.
struct LensPicker: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var recents = LensBrowserRecents.shared
    var width: CGFloat = LensBrowserStyle.popoverWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LensBrowserPopover(data: model.lensBrowserData(recents: recents.ids), actions: model.lensBrowserActions,
                               store: .shared, width: width)
            LensStatusLine()
        }
        .frame(width: width)
        .modifier(LensBrowserUpkeep())
    }
}

// MARK: - Studio

struct LensesTab: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var recents = LensBrowserRecents.shared
    @StateObject private var player = LensBrowserLivePlayer()
    @State private var query = ""
    @State private var tab: LensBrowserTab = .all
    @State private var focusedID: String?
    @State private var importing = false
    @State private var importError: String?

    private var library: LensLibrary { model.lensLibrary }
    private var focused: LensInfo? { (focusedID ?? model.lensID).flatMap(library.info(for:)) }

    private static let help = "Face lenses need good light and your face in view. Lenses marked with a hand need a hand held up where the camera can see it (hold it still for a moment first; a very fast swipe can blur it). Scenes put you in a living place. Games pause when you leave the picture and start again when you step back in. Switch lenses with ⌃⌥↑ and ⌃⌥↓, start a new game with ⌃⌥R.\n\nTo make your own, copy a folder from the Lenses folder and edit its lens.json (see docs/LENS_FORMAT.md in the Backdrop repository)."

    var body: some View {
        let data = model.lensBrowserData(recents: recents.ids)
        VStack(spacing: 0) {
            PaneHeader(title: "Lenses") {
                HStack(spacing: 10) {
                    LensBrowserSearchField(text: $query).frame(width: 220)
                    Menu {
                        Button("Add Lens…", systemImage: "plus") { importing = true }
                        Button("Open Lenses Folder", systemImage: "folder") { library.showFolder() }
                        Button("Reload", systemImage: "arrow.clockwise") { model.reloadLenses() }
                        if model.lensID != nil {
                            Divider()
                            Button("Remove Lens") { model.selectLens(nil) }
                        }
                    } label: {
                        Label("Lenses", systemImage: "ellipsis.circle")
                    }
                    .fixedSize()
                }
            }
            HStack {
                LensBrowserTabs(tabs: [.all, .saved] + data.categories.map { .category($0) }, selection: $tab)
                    .frame(maxWidth: 620)
                    .disabled(!query.isEmpty)
                    .opacity(query.isEmpty ? 1 : 0.5)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if !library.problems.isEmpty { problemsBanner.padding([.horizontal, .top], 20) }
                    LensBrowserStudioGrid(data: data, actions: model.lensBrowserActions, store: .shared, tab: tab, query: query,
                                          focusedID: $focusedID, footnote: Self.help)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ScrollView {
                    LensBrowserDetail(info: focused, data: data, actions: model.lensBrowserActions, status: model.lensStatus,
                                      cameraOn: model.isOn, note: mirrorNote, restart: { model.restartLens() }) { preview }
                }
                .frame(width: 320)
            }
        }
        .modifier(LensBrowserUpkeep())
        .onAppear {
            model.reloadLenses()
            if focusedID == nil { focusedID = model.lensID }
        }
        .onChange(of: model.lensID) { _, id in if let id { focusedID = id } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                do { try library.add(url) } catch { importError = "\(url.lastPathComponent): \(error.localizedDescription)" }
            }
        }
        .alert("Couldn't add that lens", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
    }

    private var mirrorNote: String? {
        guard model.isOn, model.preview.mirrored == false else { return nil }
        return "This preview shows what other people see, so left and right are the other way round from a mirror."
    }

    /// The camera when it is on; otherwise the lens playing on a stand-in, with a way to turn the camera on.
    @ViewBuilder private var preview: some View {
        ZStack {
            if model.isOn {
                PreviewView(relay: model.preview)
            } else if let info = focused {
                LensBrowserDemo(info: info, store: .shared, player: player)
            } else {
                Color(white: 0.12)
                Image(systemName: "video.slash").font(.title).foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottomLeading) { SwitchingBadge() }
        .overlay(alignment: .bottomTrailing) {
            if !model.isOn {
                Button { model.turnOn() } label: { Label("Turn On Camera", systemImage: "video.fill") }
                    .controlSize(.small)
                    .disabled(model.isStarting)
                    .padding(8)
            }
        }
    }

    private var problemsBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(library.problems.count) lens\(library.problems.count == 1 ? "" : "es") in your Lenses folder couldn't be used", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            ForEach(library.problems) { problem in
                HStack(alignment: .firstTextBaseline) {
                    Text("**\(problem.id):** \(problem.message)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([problem.folder]) }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
