import AppKit
import CoreImage
import XCTest

extension HandFixtures {
    /// A hand whose pinch point (between the thumb tip and the index tip) is at `point`. `amount` is 0 for fingertips apart and 1
    /// for pinched.
    static func pinching(at point: CGPoint, amount: Double, size: Double = 110, angle: Double = 0.3, mirrored: Bool = false, id: Int = 1) -> HandState {
        var fingers = Fingers.pinch
        fingers.pinch = amount
        let probe = hand(fingers, at: .zero, size: size, angle: angle, mirrored: mirrored, id: id)
        let off = probe.pinchPoint
        return hand(fingers, at: CGPoint(x: point.x - off.x, y: point.y - off.y), size: size, angle: angle, mirrored: mirrored, id: id)
    }
}

/// Pictures of every Present arrangement, preset and state, to look at: BACKDROP_TEST_OUTPUT=<folder>. Each is checked for the
/// basics too (the panel is where it should be, chrome only in the preview), but these are mostly for eyes.
final class StageRenderTests: XCTestCase {
    private var sheet: [(String, CIImage)] = []

    private func save(_ image: CIImage, _ name: String) {
        Output.save(image, as: "stage-\(name).png")
        sheet.append((name, image))
    }

    private func layout(_ preset: StagePreset?, _ change: (inout StageLayout) -> Void = { _ in }) -> StageLayout {
        var l = StageLayout()
        if let preset { l = preset.apply(to: l) }
        change(&l)
        return l
    }

    private func still(_ name: String, content: StageFixtures.Content? = .slide, layout: StageLayout, frames: Int = 24, person: Bool = true,
                       status: StageContentStatus = .live, paused: Bool = false, setup: (StageRig) -> Void = { _ in }) -> StageRig {
        let rig = StageRig(content: content, layout: layout, paused: paused)
        rig.withPerson = person
        rig.source.status = status
        setup(rig)
        rig.run(frames)
        save(rig.outputImage, name)
        return rig
    }

    func testRenderEveryArrangementAndPreset() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] == nil, "set TEST_RUNNER_BACKDROP_TEST_OUTPUT to render")
        _ = still("01-backdrop", layout: layout(nil))
        for (n, preset) in StagePreset.allCases.enumerated() {
            _ = still(String(format: "%02d-preset-%@", n + 2, preset.rawValue), layout: layout(preset))
        }
        _ = still("07-presenter-cutout", layout: StageMemory.starting(.presenter, from: StageLayout()))
        _ = still("08-presenter-rounded-square", layout: layout(.cornerBubble) { $0.presenterStyle = .roundedSquare; $0.presenter.center = CGPoint(x: 0.16, y: 0.24) })
        _ = still("09-surround-room", layout: layout(.left) { $0.surround = .room })
        _ = still("10-surround-backdrop", layout: layout(.left) { $0.surround = .backdrop }) { rig in
            rig.pipeline.setStageSurround(GradientSource(preset: .midnight))
        }
        _ = still("11-dark-code", content: .code, layout: layout(.right))
        _ = still("12-tall-document", content: .tallDocument, layout: layout(.left))
        _ = still("13-wide-dashboard", content: .wideDashboard, layout: layout(.centre))
        _ = still("14-nobody", layout: layout(.left), person: false)
        _ = still("15-label", layout: layout(.left) { $0.showsLabel = true })
        _ = still("16-paused-panel", layout: layout(.left), paused: true) { rig in
            // Live first, so the paused card has something to blur.
            rig.pipeline.setStage(self.layout(.left), paused: false, title: nil)
            rig.run(4)
            rig.pipeline.setStage(self.layout(.left), paused: true, title: nil)
        }
        _ = still("17-lost-panel", layout: layout(.left), status: .lost)
        _ = still("18-denied-panel", layout: layout(.right), status: .denied)
        _ = still("19-starting-panel", content: nil, layout: layout(.left), status: .starting)
        _ = still("20-paused-backdrop", layout: layout(nil)) { rig in
            rig.run(4)
            rig.pipeline.setStage(self.layout(nil), paused: true, title: nil)
        }
        _ = still("21-lost-backdrop", layout: layout(nil), status: .lost)
        _ = still("22-flat-square", layout: layout(.left) { $0.tilt = 0; $0.roundness = 0.1; $0.shadow = 0.3 })
        _ = still("23-tilted-round", layout: layout(.left) { $0.tilt = 1; $0.roundness = 1; $0.shadow = 1; $0.panel.center.x = 0.3 })
        writeSheet("stage-contact-arrangements.png")
    }

    func testRenderTheHandChrome() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] == nil, "set TEST_RUNNER_BACKDROP_TEST_OUTPUT to render")
        var l = layout(.left)
        l.handControl = true
        let panel = StageGeometry.panelRect(l.panel, aspect: 16.0 / 9)

        // Approaching: the ring appears.
        var rig = StageRig(layout: l)
        rig.hands = [HandFixtures.pinching(at: CGPoint(x: panel.maxX + 70, y: panel.midY), amount: 0.3)]
        rig.run(14)
        save(rig.previewAtFullSize(), "30-hover")
        XCTAssertNotNil(rig.pipeline.lastOverlay.item, "a hand near the panel brings up its ring")

        // Closing: the ring draws in and fills.
        rig.hands = [HandFixtures.pinching(at: CGPoint(x: panel.maxX + 30, y: panel.midY), amount: 0.45)]
        rig.run(6)
        rig.hands = [HandFixtures.pinching(at: CGPoint(x: panel.maxX + 30, y: panel.midY), amount: 1)]
        rig.run(2)
        save(rig.previewAtFullSize(), "31-arming")

        // Held and lifted, moved along.
        rig.run(6)
        for k in 1...10 {
            rig.hands = [HandFixtures.pinching(at: CGPoint(x: panel.maxX + 30 + Double(k) * 9, y: panel.midY + Double(k) * 3), amount: 1)]
            rig.run(1)
        }
        save(rig.previewAtFullSize(), "32-held")
        save(rig.outputImage, "33-held-as-viewers-see-it")

        // Two hands: the stretch line and the size.
        let p = rig.pipeline.lastOverlay.item?.quad ?? []
        let leftEdge = p.isEmpty ? panel.minX : p.map(\.x).min()!
        rig.hands.append(HandFixtures.pinching(at: CGPoint(x: leftEdge - 30, y: panel.midY), amount: 0.2, angle: -0.3, mirrored: true, id: 2))
        rig.run(6)
        let right = rig.hands[0].pinchPoint
        for k in 0...12 {
            rig.hands = [HandFixtures.pinching(at: CGPoint(x: right.x + Double(k) * 6, y: right.y), amount: 1),
                         HandFixtures.pinching(at: CGPoint(x: leftEdge - 30 - Double(k) * 6, y: panel.midY), amount: 1, angle: -0.3, mirrored: true, id: 2)]
            rig.run(1)
        }
        save(rig.previewAtFullSize(), "34-two-hand-resize")
        XCTAssertNotNil(rig.pipeline.lastOverlay.stretch)

        // Let go near the middle: it settles onto the guide, which flashes.
        rig = StageRig(layout: l)
        let start = CGPoint(x: panel.maxX + 20, y: panel.midY)
        rig.hands = [HandFixtures.pinching(at: start, amount: 0.2)]
        rig.run(6)
        rig.hands = [HandFixtures.pinching(at: start, amount: 1)]
        rig.run(8)
        let shift = 640 - panel.midX - 18
        for k in 1...12 {
            rig.hands = [HandFixtures.pinching(at: CGPoint(x: start.x + shift * Double(k) / 12, y: start.y), amount: 1)]
            rig.run(1)
        }
        rig.hands = [HandFixtures.pinching(at: CGPoint(x: start.x + shift, y: start.y), amount: 0.1)]
        rig.run(5)
        save(rig.previewAtFullSize(), "35-snap-flash")
        XCTAssertFalse(rig.pipeline.lastOverlay.guides.isEmpty, "the guide it settled on flashes")

        // The presenter bubble, grabbed.
        var b = layout(.cornerBubble)
        b.handControl = true
        rig = StageRig(layout: b)
        let bubble = StageGeometry.bubbleRect(b.presenter)
        rig.hands = [HandFixtures.pinching(at: CGPoint(x: bubble.minX - 10, y: bubble.maxY), amount: 0.2, angle: -0.3, mirrored: true)]
        rig.run(6)
        rig.hands = [HandFixtures.pinching(at: CGPoint(x: bubble.minX - 10, y: bubble.maxY), amount: 1, angle: -0.3, mirrored: true)]
        rig.run(12)
        save(rig.previewAtFullSize(), "36-bubble-held")

        // The how-to demo, at a moment in each step.
        let player = StageDemoPlayer()
        for (k, t) in [1.0, 1.7, 2.6, 5.2, 8.9].enumerated() {
            if let image = player.render(at: t, width: 1280, height: 720) {
                save(CIImage(cgImage: image), "4\(k)-demo-\(String(format: "%.1f", t))s")
            }
        }
        writeSheet("stage-contact-hands.png")
    }

    /// Every picture made in this test on one sheet, labelled.
    private func writeSheet(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"], !sheet.isEmpty else { return }
        let cols = 4, cellW = 480, cellH = 300, pad = 16
        let rows = (sheet.count + cols - 1) / cols
        let width = cols * cellW + (cols + 1) * pad, height = rows * cellH + (rows + 1) * pad
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: TestSupport.srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (i, item) in sheet.enumerated() {
            let col = i % cols, row = i / cols
            let x = pad + col * (cellW + pad), y = height - (row + 1) * (cellH + pad)
            if let cg = Output.context.createCGImage(item.1, from: CGRect(x: 0, y: 0, width: 1280, height: 720)) {
                ctx.draw(cg, in: CGRect(x: x, y: y + 30, width: cellW, height: 270))
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSAttributedString(string: item.0, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor(white: 0.85, alpha: 1)])
                .draw(at: CGPoint(x: x + 2, y: y + 6))
            NSGraphicsContext.restoreGraphicsState()
        }
        if let image = ctx.makeImage() {
            try? Output.context.writePNGRepresentation(of: CIImage(cgImage: image), to: URL(fileURLWithPath: folder).appendingPathComponent(name),
                                                       format: .RGBA8, colorSpace: TestSupport.srgb)
        }
        sheet.removeAll()
    }
}
