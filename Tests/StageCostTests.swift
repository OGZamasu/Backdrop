import CoreImage
import CoreMedia
import XCTest

/// What Present costs per frame, and that its static layers are kept rather than redrawn.
final class StageCostTests: XCTestCase {
    /// Milliseconds to make and send one frame (no Vision: the cutout is supplied), mean and 95th percentile, with a live 1280x720
    /// screen that changes every frame.
    private func cost(_ layout: StageLayout, frames: Int = 90, hands: [HandState] = [], buffer: CVPixelBuffer) -> (mean: Double, p95: Double) {
        let rig = StageRig(content: nil, layout: layout)
        rig.visionSized = true
        rig.source.buffer = buffer
        rig.hands = hands
        rig.run(20)
        var times: [Double] = []
        for _ in 0..<frames {
            let start = CACurrentMediaTime()
            rig.run(1)
            times.append((CACurrentMediaTime() - start) * 1000)
        }
        times.sort()
        return (times.reduce(0, +) / Double(times.count), times[Int(Double(times.count - 1) * 0.95)])
    }

    func testAFloatingPanelWithALiveScreenStaysWellInsideAFrame() {
        let screen = Self.screen(width: 1280, height: 720)
        let plain = cost(StageLayout(), buffer: screen)
        var panel = StagePreset.left.apply(to: StageLayout())
        let floating = cost(panel, buffer: screen)
        panel.handControl = true
        let r = StageGeometry.panelRect(panel.panel, aspect: 16.0 / 9)
        let chromed = cost(panel, hands: [HandFixtures.pinching(at: CGPoint(x: r.maxX + 30, y: r.midY), amount: 0.4)], buffer: screen)
        let bubble = cost(StagePreset.cornerBubble.apply(to: StageLayout()), buffer: screen)
        let big = cost(StagePreset.left.apply(to: StageLayout()), buffer: Self.screen(width: 2560, height: 1600))
        print(String(format: "COST present: backdrop %.2f ms (p95 %.2f) | floating panel %.2f (p95 %.2f) | with hand chrome %.2f (p95 %.2f) | bubble %.2f (p95 %.2f) | panel of a 2560x1600 screen %.2f (p95 %.2f)",
                     plain.mean, plain.p95, floating.mean, floating.p95, chromed.mean, chromed.p95, bubble.mean, bubble.p95, big.mean, big.p95))
        // The cutout runs on its own queue; compositing has the rest of the 33 ms frame. These limits hold in a debug build on a busy
        // machine; an optimised build is several times faster (see the report).
        XCTAssertLessThan(floating.mean, 24, "a floating panel with a live 720p screen fits in a 30 fps frame")
        XCTAssertLessThan(floating.mean - plain.mean, 8, "and costs little more than the plain backdrop")
        XCTAssertLessThan(chromed.mean, 26, "the preview's chrome included")
        XCTAssertLessThan(big.mean, 26)
        XCTAssertLessThan(floating.p95, 33)
    }

    func testThePanelsShadowAndMaskAreDrawnOnceNotEveryFrame() {
        let composer = StageComposer(context: CIContext())
        let camera = TestSupport.solid(0.3, 0.3, 0.3)
        var layout = StagePreset.left.apply(to: StageLayout())
        func frame() -> StageComposer.Inputs {
            StageComposer.Inputs(content: StageFixtures.image(.slide), layout: layout, camera: camera)
        }
        for _ in 0..<30 { _ = composer.backdrop(frame()) }
        XCTAssertEqual(composer.panelArtBuilds, 1, "thirty frames, one drawing of the shadow and mask")
        layout.panel.center = CGPoint(x: 0.6, y: 0.4)
        for _ in 0..<10 { _ = composer.backdrop(frame()) }
        XCTAssertEqual(composer.panelArtBuilds, 1, "moving the panel only moves its layers")
        layout.tilt = 1
        for _ in 0..<10 { _ = composer.backdrop(frame()) }
        XCTAssertEqual(composer.panelArtBuilds, 1, "turning it only warps them")
        layout.panel.size = 0.7
        _ = composer.backdrop(frame())
        XCTAssertEqual(composer.panelArtBuilds, 2, "a new size draws them again")
        layout.shadow = 0.2
        _ = composer.backdrop(frame())
        XCTAssertEqual(composer.panelArtBuilds, 3, "as does a new shadow")
    }

    func testThePausedCardIsDrawnOnce() {
        let composer = StageComposer(context: CIContext())
        let layout = StagePreset.left.apply(to: StageLayout())
        let camera = TestSupport.solid(0.3, 0.3, 0.3)
        for _ in 0..<20 {
            _ = composer.backdrop(StageComposer.Inputs(content: StageFixtures.image(.slide), status: .paused, layout: layout, camera: camera))
        }
        XCTAssertEqual(composer.cardBuilds, 1)
    }

    func testHandTrackingDropsToAnIdleRateAndComesBackAtOnce() {
        var pacer = HandLookPacer(now: 0)
        func looks(from start: Double, seconds: Double, hand: Bool) -> Int {
            var n = 0
            var t = start
            while t < start + seconds - 1e-9 {
                if pacer.shouldLook(at: t) {
                    n += 1
                    pacer.found(hand, at: t)
                }
                t += 1.0 / 60
            }
            return n
        }
        XCTAssertGreaterThanOrEqual(looks(from: 0, seconds: 1, hand: false), 28, "full rate at first")
        _ = looks(from: 1, seconds: 2, hand: false)
        let idle = looks(from: 3, seconds: 2, hand: false)
        XCTAssertEqual(Double(idle), 16, accuracy: 2, "about eight looks a second once no hand has been seen for a couple of seconds")
        XCTAssertTrue(pacer.isIdle(at: 5))
        pacer.found(true, at: 5)
        XCTAssertFalse(pacer.isIdle(at: 5.01), "a hand found: straight back to full rate")
        XCTAssertGreaterThanOrEqual(looks(from: 5.2, seconds: 1, hand: true), 28)
    }

    static func screen(width: Int, height: Int) -> CVPixelBuffer {
        var created: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &created)
        let content = StageFixtures.image(.code)
        Output.context.render(content.transformed(by: Compositor.fillTransform(content.extent, into: CGRect(x: 0, y: 0, width: width, height: height))), to: created!)
        return created!
    }
}
