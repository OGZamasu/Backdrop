import SwiftUI

/// One lens in a grid: its emoji and name. `info` nil is the "no lens" chip.
private struct LensChip: View {
    let info: LensInfo?
    let selected: Bool
    var compact = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(info?.glyph ?? "🚫").font(.system(size: compact ? 22 : 30))
                Text(info?.name ?? "None")
                    .font(.system(size: compact ? 9.5 : 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 56 : 78)
            .padding(.horizontal, 2)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(selected ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(info?.blurb ?? "No lens")
        .accessibilityLabel(info?.name ?? "No lens")
        .accessibilityAddTraits(selected ? .isSelected : [])
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

/// What the current lens is saying, with a restart button for games.
struct LensStatusLine: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let info = model.selectedLens {
            HStack(alignment: .top, spacing: 8) {
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
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if info.scored {
                    Button("Restart") { model.restartLens() }.controlSize(.small).help("New game (⌃⌥R)")
                }
            }
        }
    }
}

/// The lens row of the menu bar popover.
struct LensPicker: View {
    @EnvironmentObject private var model: AppModel
    @State private var category: LensInfo.Category = .filters

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Lenses").font(.subheadline.weight(.medium))
                Spacer()
                if model.lensID != nil { Button("Remove") { model.selectLens(nil) }.buttonStyle(.link).font(.caption) }
            }
            Picker("Lens type", selection: $category) {
                ForEach(LensInfo.Category.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(LensCatalog.lenses(in: category)) { info in
                    LensChip(info: info, selected: model.lensID == info.id) {
                        model.selectLens(model.lensID == info.id ? nil : info.id)
                    }
                }
            }
            LensStatusLine()
        }
        .onChange(of: model.lensID) { _, id in
            if let id, let info = LensCatalog.info(for: id) { category = info.category }
        }
    }
}

// MARK: - Studio

struct LensesTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Lenses") {
                if model.lensID != nil { Button("Remove Lens") { model.selectLens(nil) } }
            }
            Divider()
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(LensInfo.Category.allCases) { category in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(category.rawValue).font(.headline)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                                    ForEach(LensCatalog.lenses(in: category)) { info in
                                        LensCard(info: info)
                                    }
                                }
                            }
                        }
                        Text("Face lenses need good light and your face in view. Games pause when you leave the picture and start again when you step back in. Switch lenses with ⌃⌥↑ and ⌃⌥↓, start a new game with ⌃⌥R.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                }
                Divider()
                LensInspector().frame(width: 300)
            }
        }
    }
}

private struct LensCard: View {
    @EnvironmentObject private var model: AppModel
    let info: LensInfo

    var body: some View {
        let selected = model.lensID == info.id
        Button { model.selectLens(selected ? nil : info.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(info.glyph).font(.system(size: 28))
                    Spacer()
                    if info.scored {
                        let best = model.bestScore(for: info.id)
                        if best > 0 { Label("\(best)", systemImage: "trophy.fill").font(.caption.weight(.semibold)).foregroundStyle(.yellow) }
                    }
                }
                Text(info.name).font(.system(size: 13, weight: .semibold))
                Text(info.blurb).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(selected ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The live picture, so a game can be played from the Studio, with the lens's own words beneath it.
private struct LensInspector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            if let info = model.selectedLens {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(info.glyph) \(info.name)").font(.headline)
                    Text(info.blurb).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                LensStatusLine()
                if info.scored {
                    Label("Best: \(model.bestScore(for: info.id))", systemImage: "trophy.fill").font(.caption).foregroundStyle(.secondary)
                }
                if model.preview.mirrored == false {
                    Text("This preview shows what other people see, so left and right are the other way round from a mirror.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Pick a lens to put it on the picture. It shows up in Backdrop Camera too, so everyone on your call sees it.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
    }
}
