import AppKit

/// A brief label near the bottom of the screen. Hotkeys change things while the menu is closed,
/// so without this they'd be invisible.
@MainActor
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var label: NSTextField?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String) {
        let panel = panel ?? makePanel()
        label?.stringValue = text
        label?.sizeToFit()

        let size = NSSize(width: max((label?.frame.width ?? 0) + 44, 120), height: 44)
        if let screen = NSScreen.main {
            panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 140, width: size.width, height: size.height), display: true)
        }
        label?.frame = NSRect(x: 0, y: (size.height - (label?.frame.height ?? 0)) / 2, width: size.width, height: label?.frame.height ?? 20)

        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled, let panel = self?.panel else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }
            if !Task.isCancelled { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 22
        background.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        background.addSubview(label)

        panel.contentView = background
        self.panel = panel
        self.label = label
        return panel
    }
}
