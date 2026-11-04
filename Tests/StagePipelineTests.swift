import CoreImage
import CoreMedia
import XCTest

/// Present inside the real pipeline: the stage drawn where the layout says, the chrome only ever on the preview, the cards, the
/// person moved with their cutout, and the layout reported back as it moves.
final class StagePipelineTests: XCTestCase {
    private let context = CIContext()

    private func pixel(_ image: CIImage, _ p: CGPoint) -> RGB { TestSupport.pixel(image, x: Int(p.x), y: Int(p.y), context: context) }
    private func brightness(_ c: RGB) -> Int { c.r + c.g + c.b }

    private func panelLayout(_ change: (inout StageLayout) -> Void = { _ in }) -> StageLayout {
        var l = StagePreset.left.apply(to: StageLayout())
        l.tilt = 0
        l.depth = 0
        change(&l)
        return l
    }

    /// The largest difference between two pictures, in any channel, over a region.
    private func difference(_ a: CIImage, _ b: CIImage, in rect: CGRect) -> Int {
        let w = Int(rect.width), h = Int(rect.height)
        var pa = [UInt8](repeating: 0, count: w * h * 4), pb = pa
        context.render(a, toBitmap: &pa, rowBytes: w * 4, bounds: rect, format: .RGBA8, colorSpace: TestSupport.srgb)
        context.render(b, toBitmap: &pb, rowBytes: w * 4, bounds: rect, format: .RGBA8, colorSpace: TestSupport.srgb)
        var worst = 0
        for i in 0..<pa.count where i % 4 != 3 { worst = max(worst, abs(Int(pa[i]) - Int(pb[i]))) }
        return worst
    }

    // MARK: The chrome stays private

    func testThePictureSentOutNeverHasTheChromeButThePreviewDoes() {
        let layout = panelLayout { $0.handControl = true }
        let panel = StageGeometry.panelRect(layout.panel, aspect: 16.0 / 9)
        let hover = HandFixtures.pinching(at: CGPoint(x: panel.maxX + 40, y: panel.midY), amount: 0.4)

        let chromed = StageRig(layout: layout)
        chromed.withPerson = false
        chromed.hands = [hover]
        chromed.run(20)
        var plain = layout
        plain.handControl = false
        let bare = StageRig(layout: plain)
        bare.withPerson = false
        bare.hands = [hover]
        bare.run(20)

        XCTAssertFalse(chromed.pipeline.lastOverlay.isEmpty, "the hand brought up a cursor and a ring")
        XCTAssertTrue(bare.pipeline.lastOverlay.isEmpty)
        XCTAssertLessThanOrEqual(difference(chromed.outputImage, bare.outputImage, in: CGRect(x: 0, y: 0, width: 1280, height: 720)), 2,
                                 "the outgoing picture is the same with or without the chrome")
        // The preview is half size; the cursor sits at the pinch point.
        let a = CIImage(cgImage: chromed.preview!), b = CIImage(cgImage: bare.preview!)
        let cursor = CGRect(x: (panel.maxX + 40) / 2 - 12, y: panel.midY / 2 - 12, width: 24, height: 24)
        XCTAssertGreaterThan(difference(a, b, in: cursor), 40, "while the preview shows the cursor")
        let ring = CGRect(x: panel.maxX / 2 - 3, y: panel.midY / 2 - 40, width: 12, height: 80)
        XCTAssertGreaterThan(difference(a, b, in: ring), 25, "and the ring round the panel")
    }

    func testHandsAreOnlyLookedForWhenSomethingNeedsThem() {
        let off = StageRig(layout: panelLayout())
        off.hands = [HandFixtures.pinching(at: CGPoint(x: 600, y: 400), amount: 0.3)]
        off.run(3)
        XCTAssertNil(off.reports.last?.handsSeen, "hand control off and no hand lens: no hand tracking")
        let on = StageRig(layout: panelLayout { $0.handControl = true })
        on.hands = [HandFixtures.pinching(at: CGPoint(x: 600, y: 400), amount: 0.3)]
        on.run(3)
        XCTAssertEqual(on.reports.last?.handsSeen, 1, "with hand control on, the interface hears a hand is seen")
    }

    // MARK: The stage

    func testTheFloatingPanelSitsWhereTheLayoutSays() {
        let layout = panelLayout()
        let rig = StageRig(layout: layout)
        rig.withPerson = false
        rig.run(6)
        let panel = StageGeometry.panelRect(layout.panel, aspect: 16.0 / 9)
        let inside = pixel(rig.outputImage, CGPoint(x: panel.minX + 30, y: panel.midY))
        XCTAssertGreaterThan(brightness(inside), 700, "the slide's white is inside the panel: \(inside)")
        let outside = pixel(rig.outputImage, CGPoint(x: 1240, y: 680))
        XCTAssertLessThan(brightness(outside), 200, "around it, a dim room: \(outside)")
        let corner = pixel(rig.outputImage, CGPoint(x: panel.minX + 1.5, y: panel.maxY - 1.5))
        XCTAssertLessThan(brightness(corner), brightness(inside) - 200, "with its corners rounded off")
    }

    func testThePlainBackdropArrangementIsExactlyAsBefore() {
        // Today's behaviour: the screen letterboxed over a blurred copy of itself, behind you.
        let rig = StageRig(layout: StageLayout())
        rig.run(4)
        let compositor = Compositor()
        let scene = SyntheticScene(center: CGPoint(x: 900, y: 400))
        let camera = CIImage(cvPixelBuffer: scene.cameraBuffer())
        let matte = compositor.refinedMatte(camera: camera, mask: Compositor.matte(from: scene.matteBuffer()))
        let expected = compositor.composite(camera: camera, matte: matte,
                                            background: compositor.prepareBackground(StageFixtures.image(.slide), fits: true, parallax: nil))
        XCTAssertLessThanOrEqual(difference(rig.outputImage, expected, in: CGRect(x: 0, y: 0, width: 1280, height: 720)), 3)
    }

    func testPausingShowsTheCalmCardAndRestsTheCapture() {
        let layout = panelLayout()
        let rig = StageRig(layout: layout)
        rig.withPerson = false
        rig.run(3)
        rig.pipeline.setStage(layout, paused: true, title: nil)
        rig.run(3)
        XCTAssertTrue(rig.source.paused, "the capture is told to rest")
        XCTAssertEqual(rig.reports.last?.status, .paused)
        let panel = StageGeometry.panelRect(layout.panel, aspect: 16.0 / 9)
        let inside = pixel(rig.outputImage, CGPoint(x: panel.minX + 40, y: panel.minY + 40))
        XCTAssertLessThan(brightness(inside), 300, "nothing of the slide is readable: a dark card instead: \(inside)")
        rig.pipeline.setStage(layout, paused: false, title: nil)
        rig.run(2)
        XCTAssertFalse(rig.source.paused)
        XCTAssertGreaterThan(brightness(pixel(rig.outputImage, CGPoint(x: panel.minX + 40, y: panel.midY))), 700, "and back")
    }

    func testALostWindowShowsACardNeverBlack() {
        for arrangement in [StageArrangement.backdrop, .floatingPanel] {
            let rig = StageRig(layout: StageMemory.starting(arrangement, from: StageLayout()))
            rig.withPerson = false
            rig.source.status = .lost
            rig.run(3)
            let middle = pixel(rig.outputImage, CGPoint(x: 300, y: 400))
            XCTAssertGreaterThan(brightness(middle), 25, "\(arrangement): a card, not a black hole")
            XCTAssertEqual(rig.reports.last?.status, .lost)
        }
    }

    func testAWindowChangingShapeEasesRatherThanJumps() {
        let rig = StageRig(layout: panelLayout())
        rig.run(3)
        XCTAssertEqual(rig.reports.last?.aspect ?? 0, 1.78, accuracy: 0.01)
        rig.source.image = StageFixtures.image(.tallDocument)
        rig.run(1)
        let first = rig.reports.last?.aspect ?? 0
        XCTAssertGreaterThan(first, 0.9, "one frame later it has only started to change shape: \(first)")
        rig.run(30)
        XCTAssertEqual(rig.reports.last?.aspect ?? 0, 900.0 / 1400, accuracy: 0.01, "and a second later it has the window's shape")
    }

    // MARK: Moving things

    func testDraggingByHandIsReportedWhileMovingAndOnceSettled() {
        let layout = panelLayout { $0.handControl = true; $0.snapping = false }
        let panel = StageGeometry.panelRect(layout.panel, aspect: 16.0 / 9)
        let rig = StageRig(layout: layout)
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY)
        rig.hands = [HandFixtures.pinching(at: p, amount: 0.2)]
        rig.run(6)
        rig.hands = [HandFixtures.pinching(at: p, amount: 1)]
        rig.run(6)
        for k in 1...30 {
            rig.hands = [HandFixtures.pinching(at: CGPoint(x: p.x + Double(k) * 4, y: p.y), amount: 1)]
            rig.run(1)
        }
        let whileMoving = rig.layouts.count
        XCTAssertGreaterThan(whileMoving, 3, "the sliders hear about it as it moves")
        XCTAssertLessThan(whileMoving, 16, "about ten times a second, not every frame")
        rig.run(10)       // held still a moment (the panel catches up with the hand), then the hand leaves the picture
        rig.hands = []
        rig.run(60)
        let final = rig.layouts.last!
        XCTAssertEqual(StageGeometry.point(final.panel.center).x - panel.midX, 120, accuracy: 3, "and the place it settled is reported")
    }

    func testThePresenterMovesYourCameraAndCutoutTogether() {
        var layout = StageMemory.starting(.presenter, from: StageLayout())
        layout.presenter = StageFrame(center: CGPoint(x: 0.25, y: 0.42), size: 0.6)
        let rig = StageRig(layout: layout)
        let probe = StageProbeLens()
        rig.pipeline.setLens(probe)
        rig.hands = [HandFixtures.openPalm(at: CGPoint(x: 900, y: 200))]
        rig.run(4)
        // Your shirt (blue, at the bottom middle of you in the camera) is now where the transform puts it.
        let t = StageGeometry.presenterTransform(layout.presenter)
        let shirt = CGPoint(x: 900, y: 120).applying(t)
        // The shirt's own colour, colour-matched a little toward the slide.
        func isShirt(_ c: RGB) -> Bool { abs(c.r - 64) < 30 && abs(c.g - 89) < 30 && abs(c.b - 199) < 40 }
        let c = pixel(rig.outputImage, shirt)
        XCTAssertTrue(isShirt(c), "the shirt moved with the cutout: \(c)")
        let left = pixel(rig.outputImage, CGPoint(x: 900, y: 120))
        XCTAssertFalse(isShirt(left), "and is gone from where the camera had it: \(left)")
        // A lens on top gets your hands where you now are.
        let wrist = probe.hands.first?.wrist ?? .zero
        XCTAssertEqual(wrist.x, CGPoint(x: 900, y: 200).applying(t).x, accuracy: 0.5)
    }

    func testABubbleCanBeChosenAndYouSitInIt() {
        var layout = StagePreset.cornerBubble.apply(to: StageLayout())
        layout.presenterStyle = .roundedSquare
        let rig = StageRig(layout: layout)
        rig.run(8)
        let bubble = StageGeometry.bubbleRect(layout.presenter)
        let ring = pixel(rig.outputImage, CGPoint(x: bubble.midX, y: bubble.maxY - 2))
        XCTAssertGreaterThan(brightness(ring), 600, "a light border runs round the bubble: \(ring)")
    }
}

/// A lens that only records what it was handed.
private final class StageProbeLens: Lens {
    var needs: LensNeeds { [.hands, .matte] }
    private(set) var hands: [HandState] = []
    func render(_ input: LensInput) -> CIImage {
        hands = input.hands
        return input.composed
    }
}
