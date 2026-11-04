import SwiftUI

/// Which camera Backdrop reads and how the cutout looks, with the live picture beside the controls so a change can be judged
/// as it is made.
struct CameraTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Camera") {
                Button { model.resetLook() } label: { Label("Reset Look", systemImage: "arrow.counterclockwise") }
                    .disabled(model.lookIsDefault)
                    .help("Cutout quality and the three sliders back to how they started")
            }
            Divider()
            HStack(spacing: 0) {
                form
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    StudioPreview()
                    Text("Look at the edge of your outline, around your hair and shoulders, while you adjust.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(16)
                .frame(width: 320)
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker("Use", selection: $model.cameraID) {
                    Text("Automatic").tag(String?.none)
                    ForEach(model.cameras, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
                }
                if model.cameras.isEmpty {
                    Label("No camera found. Plug one in, or allow Backdrop in System Settings › Privacy & Security › Camera.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Camera")
            } footer: {
                Text("The camera Backdrop reads. Automatic uses the one your Mac prefers, and a different pick takes effect straight away.")
            }

            Section {
                Picker("Cutout quality", selection: $model.quality) {
                    Text("Fast").tag(PersonSegmenter.Quality.fast)
                    Text("Balanced").tag(PersonSegmenter.Quality.balanced)
                    Text("Accurate").tag(PersonSegmenter.Quality.accurate)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Cutout")
            } footer: {
                Text(qualityNote)
            }

            Section {
                slider("Edge softness", value: $model.edgeSoftness, range: 0.5...5) { String(format: "%.1f px", $0) }
                slider("Light wrap", value: $model.lightWrap, range: 0...1, format: Self.percent)
                slider("Colour match", value: $model.colorMatch, range: 0...1, format: Self.percent)
            } header: {
                Text("Edges and colour")
            } footer: {
                Text("Softness blurs the edge of the cutout so it doesn't look cut with scissors. Light wrap lets the background's glow touch your edges. Colour match nudges your skin tones toward the scene.")
            }
        }
        .formStyle(.grouped)
    }

    private var qualityNote: String {
        switch model.quality {
        case .fast: return "Lightest on your Mac. Edges can look rougher around hair."
        case .balanced: return "A good mix of clean edges and low power use."
        case .accurate: return "The cleanest edges around hair, but uses the most power."
        }
    }

    private static let percent: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                        format: @escaping (Double) -> String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: value, in: range).frame(minWidth: 120, idealWidth: 180, maxWidth: 220)
                Text(format(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}
