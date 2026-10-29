import AppKit
import SwiftUI

/// Fans preview frames out to whichever preview views are on screen, and tells the pipeline whether anyone is looking,
/// so no time is spent making preview images nobody sees.
final class PreviewRelay {
    private let views = NSHashTable<PreviewLayerView>.weakObjects()
    var onDemandChanged: ((Bool) -> Void)?

    func attach(_ view: PreviewLayerView) {
        views.add(view)
        onDemandChanged?(true)
    }

    func detach(_ view: PreviewLayerView) {
        views.remove(view)
        onDemandChanged?(views.count > 0)
    }

    func show(_ image: CGImage?) {
        DispatchQueue.main.async {
            for view in self.views.allObjects { view.imageLayer.contents = image }
        }
    }
}

final class PreviewLayerView: NSView {
    let imageLayer = CALayer()
    var relay: PreviewRelay?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        // Mirrored, like looking in a mirror. Other people still see you the right way round.
        imageLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }
}

struct PreviewView: NSViewRepresentable {
    let relay: PreviewRelay

    func makeNSView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView(frame: .zero)
        view.relay = relay
        relay.attach(view)
        return view
    }

    func updateNSView(_ nsView: PreviewLayerView, context: Context) {}

    static func dismantleNSView(_ nsView: PreviewLayerView, coordinator: ()) {
        nsView.relay?.detach(nsView)
    }
}
