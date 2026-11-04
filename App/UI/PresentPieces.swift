import AppKit
import SwiftUI

// The parts of Present shared by the Studio pane and the menu bar popover.

// MARK: - Drawn layouts

/// A small drawing of a layout, made from the very geometry the picture is built with, so a card shows exactly where things go.
struct LayoutSketch: View {
    let layout: StageLayout
    var aspect: Double = 16.0 / 10
    /// Draws a fine dashed outline round whatever moves in this arrangement: the panel, or you.
    var marksMovable = false

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / StageGeometry.picture.width
            func p(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x * s, y: size.height - q.y * s) }
            let full = CGRect(origin: .zero, size: size)
            // The room.
            ctx.fill(Path(full), with: .linearGradient(Gradient(colors: [Color(red: 0.17, green: 0.19, blue: 0.25), Color(red: 0.07, green: 0.075, blue: 0.1)]),
                                                         startPoint: CGPoint(x: size.width * 0.3, y: 0), endPoint: CGPoint(x: size.width * 0.6, y: size.height)))
            switch layout.arrangement {
            case .backdrop, .presenter:
                slide(in: &ctx, quad: [CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height), CGPoint(x: size.width, y: 0), .zero], scale: size.width / 100)
            case .floatingPanel:
                let quad = StageGeometry.panelQuad(layout, aspect: aspect).map(p)
                var shadow = ctx
                shadow.addFilter(.shadow(color: .black.opacity(0.55), radius: size.width * 0.025, y: size.width * 0.012))
                shadow.fill(Path { $0.addLines(quad); $0.closeSubpath() }, with: .color(.white))
                // Light from the screen on the wall round it.
                let bounds = Path { $0.addLines(quad); $0.closeSubpath() }.boundingRect
                ctx.fill(Path(ellipseIn: bounds.insetBy(dx: -bounds.width * 0.35, dy: -bounds.height * 0.45)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.14), .clear]), center: CGPoint(x: bounds.midX, y: bounds.midY),
                                               startRadius: 0, endRadius: bounds.width * 0.85))
                slide(in: &ctx, quad: quad, scale: bounds.width / 100)
            }
            // You.
            if layout.showsBubble {
                let r = StageGeometry.bubbleRect(layout.presenter)
                let box = CGRect(x: r.minX * s, y: size.height - r.maxY * s, width: r.width * s, height: r.height * s)
                let shape = layout.presenterStyle == .circle ? Path(ellipseIn: box) : Path(roundedRect: box, cornerRadius: box.width * 0.24, style: .continuous)
                var shadow = ctx
                shadow.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, y: 1.5))
                shadow.fill(shape, with: .color(Color(red: 0.2, green: 0.24, blue: 0.32)))
                var inside = ctx
                inside.clip(to: shape)
                person(in: &inside, center: CGPoint(x: box.midX, y: box.midY + box.height * 0.12), scale: box.height / 120)
                ctx.stroke(shape, with: .color(.white.opacity(0.9)), lineWidth: max(1, box.width * 0.04))
            } else {
                let t = layout.arrangement == .backdrop ? .identity : StageGeometry.presenterTransform(layout.presenter)
                let c = p(CGPoint(x: 640, y: 300).applying(t))
                person(in: &ctx, center: c, scale: size.height / 120 * layout.presenter.size)
            }
            guard marksMovable, let item = layout.handItem else { return }
            let quad = StageGeometry.itemQuad(item, layout: layout, aspect: aspect, anchor: CGPoint(x: 640, y: 330)).map(p)
            let box = Path { $0.addLines(quad); $0.closeSubpath() }.boundingRect.insetBy(dx: -3, dy: -3)
            let mark = item == .panel ? Path { $0.addLines(quad.map { CGPoint(x: $0.x + ($0.x < box.midX ? -3 : 3), y: $0.y + ($0.y < box.midY ? -3 : 3)) }); $0.closeSubpath() }
                : (layout.showsBubble ? Path(ellipseIn: box) : Path(roundedRect: box.intersection(full.insetBy(dx: 2, dy: 2)), cornerRadius: 4))
            ctx.stroke(mark, with: .color(Color(red: 0.27, green: 0.62, blue: 1).opacity(0.95)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
        }
    }

    private func slide(in ctx: inout GraphicsContext, quad: [CGPoint], scale u: CGFloat) {
        let outline = Path { $0.addLines(quad); $0.closeSubpath() }
        ctx.fill(outline, with: .color(Color(white: 0.97)))
        var inside = ctx
        inside.clip(to: outline)
        let r = outline.boundingRect
        inside.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: max(1.5, r.height * 0.1))), with: .color(Color(red: 0.14, green: 0.16, blue: 0.22)))
        for k in 0..<3 {
            inside.fill(Path(roundedRect: CGRect(x: r.minX + r.width * 0.08, y: r.minY + r.height * (0.24 + Double(k) * 0.12), width: r.width * (0.36 - Double(k) * 0.07), height: max(1, r.height * 0.05)),
                             cornerRadius: 1), with: .color(Color(white: 0.7)))
        }
        for (k, h) in [0.35, 0.5, 0.45, 0.66, 0.58].enumerated() {
            let bar = CGRect(x: r.minX + r.width * (0.56 + Double(k) * 0.075), y: r.maxY - r.height * (0.1 + h * 0.62), width: r.width * 0.05, height: r.height * h * 0.62)
            inside.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(k % 2 == 0 ? Color(red: 0.27, green: 0.62, blue: 1) : Color(red: 0.36, green: 0.84, blue: 0.74)))
        }
        _ = u
    }

    private func person(in ctx: inout GraphicsContext, center c: CGPoint, scale k: CGFloat) {
        let ink = Color(red: 0.33, green: 0.42, blue: 0.82)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 13 * k, y: c.y - 16 * k, width: 26 * k, height: 30 * k)), with: .color(Color(red: 0.93, green: 0.76, blue: 0.64)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 14 * k, y: c.y - 18 * k, width: 28 * k, height: 15 * k)), with: .color(Color(red: 0.25, green: 0.17, blue: 0.12)))
        var body = Path()
        body.move(to: CGPoint(x: c.x - 40 * k, y: c.y + 60 * k))
        body.addQuadCurve(to: CGPoint(x: c.x, y: c.y + 14 * k), control: CGPoint(x: c.x - 36 * k, y: c.y + 16 * k))
        body.addQuadCurve(to: CGPoint(x: c.x + 40 * k, y: c.y + 60 * k), control: CGPoint(x: c.x + 36 * k, y: c.y + 16 * k))
        body.closeSubpath()
        ctx.fill(body, with: .color(ink))
    }
}

/// One of the three arrangements, as a card with its drawing.
struct ArrangementCard: View {
    let arrangement: StageArrangement
    let layout: StageLayout
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                LayoutSketch(layout: layout, marksMovable: true)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.28 : 0.12), lineWidth: selected ? 2.5 : 1))
                Text(arrangement.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(arrangement.blurb)
        .accessibilityLabel(arrangement.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A preset as a small drawn chip.
struct PresetChip: View {
    let preset: StagePreset
    let base: StageLayout
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                LayoutSketch(layout: preset.apply(to: base))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.28 : 0.1), lineWidth: selected ? 2 : 1))
                Text(preset.title).font(.caption).foregroundStyle(selected ? Color.accentColor : Color.secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(preset.blurb)
    }
}

// MARK: - The mouse on the preview

/// Lays over the Studio preview so the panel or you can be dragged, pinch-zoomed or scrolled to resize, and double-clicked to zoom.
/// Events go to the same controller your hands drive, so both move things the same way.
struct StagePointerSurface: NSViewRepresentable {
    let onEvent: (StagePointerEvent) -> Void
    /// Whether a point (normalised, y up) is over something that can be moved, for the cursor.
    let isOverItem: (CGPoint) -> Bool

    func makeNSView(context: Context) -> PointerView {
        let view = PointerView()
        view.onEvent = onEvent
        view.isOverItem = isOverItem
        return view
    }

    func updateNSView(_ view: PointerView, context: Context) {
        view.onEvent = onEvent
        view.isOverItem = isOverItem
    }

    final class PointerView: NSView {
        var onEvent: ((StagePointerEvent) -> Void)?
        var isOverItem: ((CGPoint) -> Bool)?
        private var dragging = false
        private var tracking: NSTrackingArea?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }

        private func point(_ event: NSEvent) -> CGPoint {
            let p = convert(event.locationInWindow, from: nil)
            return CGPoint(x: p.x / max(bounds.width, 1), y: p.y / max(bounds.height, 1))
        }

        private func updateCursor(_ p: CGPoint) {
            if dragging { NSCursor.closedHand.set() } else if isOverItem?(p) == true { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
        }

        override func cursorUpdate(with event: NSEvent) { updateCursor(point(event)) }

        override func mouseDown(with event: NSEvent) {
            let p = point(event)
            if event.clickCount == 2 {
                onEvent?(.doubleClick(p))
                return
            }
            dragging = isOverItem?(p) == true
            onEvent?(.down(p))
            updateCursor(p)
        }

        override func mouseDragged(with event: NSEvent) { onEvent?(.drag(point(event))) }

        override func mouseUp(with event: NSEvent) {
            let p = point(event)
            onEvent?(.up(p))
            dragging = false
            updateCursor(p)
        }

        override func mouseMoved(with event: NSEvent) {
            let p = point(event)
            onEvent?(.hover(p))
            updateCursor(p)
        }

        override func mouseExited(with event: NSEvent) {
            onEvent?(.hover(nil))
            NSCursor.arrow.set()
        }

        override func scrollWheel(with event: NSEvent) {
            let raw = Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : 10)
            // Upward makes it bigger, however the scroll direction is set.
            onEvent?(.scroll(event.isDirectionInvertedFromDevice ? -raw : raw, at: point(event)))
        }

        override func magnify(with event: NSEvent) { onEvent?(.magnify(Double(event.magnification), at: point(event))) }
    }
}

/// The Studio preview, which in an arrangement can also be grabbed with the mouse.
struct PresentPreview: View {
    @EnvironmentObject private var model: AppModel

    private var interactive: Bool { model.isOn && model.isSharingScreen && model.stage.arrangement.isArranged }

    var body: some View {
        StudioPreview()
            .overlay {
                if interactive {
                    StagePointerSurface(onEvent: { model.stagePointer($0) }, isOverItem: { p in
                        let at = StageGeometry.point(p)
                        return StageGeometry.item(at: at, layout: model.stage, aspect: model.stageReport?.aspect ?? 16.0 / 10) != nil
                    })
                }
            }
            .overlay(alignment: .topTrailing) {
                if model.isOn && model.isSharingScreen { ShareStatusPill().padding(8) }
            }
    }
}

// MARK: - How it works

/// The how-to: a ghost hand grabbing, two hands resizing and a double pinch zooming, played by the real controller and drawn by
/// the real overlay, with the three steps beside it.
struct PresentHowTo: View {
    @State private var player = StageDemoPlayer()
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSince(start)
            let act = StageDemoPlayer.act(at: t)
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if let image = player.render(at: t, width: 640, height: 360) {
                        Image(decorative: image, scale: 2)
                            .resizable()
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .opacity(StageDemoPlayer.fade(at: t))
                    } else {
                        Color.black.aspectRatio(16 / 9, contentMode: .fit)
                    }
                }
                .background(Color(red: 0.07, green: 0.075, blue: 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("An animation of hands grabbing, resizing and zooming the panel")

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(StageDemoPlayer.acts.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Text("\(i + 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(i == act ? Color.white : Color.secondary)
                                .frame(width: 18, height: 18)
                                .background(i == act ? Color.accentColor : Color.primary.opacity(0.08), in: Circle())
                            Text(StageDemoPlayer.acts[i].title)
                                .font(.callout.weight(i == act ? .medium : .regular))
                                .foregroundStyle(i == act ? Color.primary : Color.secondary)
                        }
                        .animation(.easeOut(duration: 0.25), value: act)
                    }
                }
            }
        }
    }
}

/// Whether hand tracking is seeing anything, so it can be checked before trying a grab.
struct HandTrackingIndicator: View {
    @EnvironmentObject private var model: AppModel

    private var state: (text: String, color: Color) {
        guard model.isOn else { return ("Turn the camera on to try it.", .secondary) }
        guard model.isSharingScreen else { return ("Share a window or screen to use your hands.", .secondary) }
        guard model.stage.arrangement.isArranged else { return ("Choose Floating Panel or Presenter to use your hands.", .secondary) }
        guard let seen = model.stageReport?.handsSeen else { return ("Starting hand tracking…", .secondary) }
        switch seen {
        case 0: return ("Hand tracking: no hands in view", .secondary)
        case 1: return ("Hand tracking: seeing 1 hand", .green)
        default: return ("Hand tracking: seeing \(seen) hands", .green)
        }
    }

    var body: some View {
        let s = state
        HStack(spacing: 7) {
            Circle()
                .fill(s.color == .secondary ? Color.secondary.opacity(0.5) : s.color)
                .frame(width: 7, height: 7)
                .shadow(color: s.color == .green ? .green.opacity(0.7) : .clear, radius: 3)
            Text(s.text).font(.callout).foregroundStyle(s.color == .green ? .primary : .secondary)
        }
        .animation(.easeOut(duration: 0.2), value: s.text)
        .accessibilityElement(children: .combine)
    }
}

/// What the share is doing, as a small pill: live, paused, closed, starting or not allowed.
struct ShareStatusPill: View {
    @EnvironmentObject private var model: AppModel

    static func describe(_ model: AppModel) -> (text: String, color: Color) {
        if model.sharePaused { return ("Paused", .orange) }
        switch model.stageReport?.status ?? .starting {
        case .live: return (model.isOn ? "Sharing" : "Ready", model.isOn ? .red : .secondary)
        case .starting: return ("Starting…", .secondary)
        case .paused: return ("Paused", .orange)
        case .lost: return ("Window closed", .orange)
        case .denied: return ("Not allowed", .orange)
        }
    }

    var body: some View {
        let s = Self.describe(model)
        HStack(spacing: 5) {
            Circle().fill(s.color).frame(width: 6, height: 6)
            Text(s.text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - The menu bar

/// Present at a glance in the popover while a screen is shared: the arrangement, pause, hands, and a way to the full controls.
struct PresentQuickControls: View {
    @EnvironmentObject private var model: AppModel
    let openPane: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Present").font(.subheadline.weight(.medium))
                let s = ShareStatusPill.describe(model)
                HStack(spacing: 4) {
                    Circle().fill(s.color).frame(width: 6, height: 6)
                    Text(s.text).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("More…", action: openPane).buttonStyle(.link).font(.caption)
            }
            HStack(spacing: 8) {
                Picker("Arrangement", selection: Binding(get: { model.stage.arrangement }, set: { model.setArrangement($0) })) {
                    Image(systemName: "rectangle.inset.filled").help("Backdrop").tag(StageArrangement.backdrop)
                    Image(systemName: "rectangle.on.rectangle.angled").help("Floating Panel").tag(StageArrangement.floatingPanel)
                    Image(systemName: "person.crop.rectangle.badge.plus").help("Presenter").tag(StageArrangement.presenter)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 132)
                Spacer(minLength: 0)
                Toggle(isOn: Binding(get: { model.stage.handControl }, set: { on in model.updateStage { $0.handControl = on } })) {
                    Image(systemName: "hand.pinch")
                }
                .toggleStyle(.button)
                .help("Control with your hands")
                .disabled(!model.stage.arrangement.isArranged)
                Button { model.togglePause() } label: {
                    Label(model.sharePaused ? "Resume" : "Pause", systemImage: model.sharePaused ? "play.fill" : "pause.fill")
                }
                .help(model.sharePaused ? "Resume sharing (⌃⌥P)" : "Pause sharing (⌃⌥P)")
            }
            .controlSize(.small)
        }
    }
}

/// The menu bar icon: the usual camera glyph, with a small red dot while your screen is going out, so it is never a surprise.
enum MenuBarIcon {
    static func image(on: Bool, sharing: Bool) -> NSImage {
        let name = on ? "person.crop.rectangle.fill" : "person.crop.rectangle"
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Backdrop")?.withSymbolConfiguration(configuration) else {
            return NSImage()
        }
        guard sharing else {
            symbol.isTemplate = true
            return symbol
        }
        let size = NSSize(width: symbol.size.width + 4, height: max(symbol.size.height, 16))
        let image = NSImage(size: size, flipped: false) { rect in
            let glyph = NSRect(x: 0, y: (rect.height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height)
            // The glyph in the menu bar's own text colour, which follows light and dark menu bars.
            NSGraphicsContext.saveGraphicsState()
            symbol.draw(in: glyph)
            NSColor.labelColor.set()
            glyph.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
            let dot = NSRect(x: rect.width - 7.5, y: rect.height - 7.5, width: 7, height: 7)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemRed.set()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Backdrop, sharing your screen"
        return image
    }
}
