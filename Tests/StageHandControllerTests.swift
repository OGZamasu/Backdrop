import CoreGraphics
import XCTest

/// Grabbing, moving, resizing and letting go of the panel and you, with made-up hands and the mouse. And, as importantly, all the
/// things a hand does while you talk that must never grab anything.
final class StageHandControllerTests: XCTestCase {
    private let aspect = 16.0 / 10
    private var events: [StageEvent] = []
    private var last: StageControlOutput?

    /// The Left preset, flat (no tilt or depth) so the panel's outline is exactly its rectangle.
    private func panelLayout(handControl: Bool = true, snapping: Bool = true) -> StageLayout {
        var l = StagePreset.left.apply(to: StageLayout())
        l.tilt = 0
        l.depth = 0
        l.handControl = handControl
        l.snapping = snapping
        return l
    }

    private var panel: CGRect { StageGeometry.panelRect(panelLayout().panel, aspect: aspect) }

    @discardableResult
    private func run(_ c: inout StageHandController, _ hands: [HandState], frames: Int = 1, lens: Bool = false,
                     pointer: [StagePointerEvent] = [], anchor: CGPoint? = nil) -> StageControlOutput {
        var out: StageControlOutput!
        for k in 0..<frames {
            out = c.step(StageControlInput(hands: hands, dt: 1.0 / 30, pointer: k == 0 ? pointer : [], aspect: aspect, anchor: anchor, lensUsesHands: lens))
            events += out.events
        }
        last = out
        return out
    }

    private func pinch(_ p: CGPoint, _ amount: Double, id: Int = 1, mirrored: Bool = false) -> HandState {
        HandFixtures.pinching(at: p, amount: amount, angle: mirrored ? -0.3 : 0.3, mirrored: mirrored, id: id)
    }

    private func center(_ out: StageControlOutput) -> CGPoint { StageGeometry.point(out.layout.panel.center) }

    private var grabbed: Bool { events.contains { if case .grabbed = $0 { return true } else { return false } } }

    /// Opens near `p`, then pinches and holds for `hold` seconds.
    private func grab(_ c: inout StageHandController, at p: CGPoint, hold: Double = 0.2, lens: Bool = false) {
        run(&c, [pinch(p, 0.2)], frames: 6, lens: lens)
        run(&c, [pinch(p, 1)], frames: Int((hold * 30).rounded()), lens: lens)
    }

    // MARK: Grabbing

    func testAPinchStartedNearThePanelGrabsItOnceHeldBriefly() {
        var c = StageHandController(layout: panelLayout())
        let p = CGPoint(x: panel.maxX + 30, y: panel.midY)
        run(&c, [pinch(p, 0.2)], frames: 6)
        run(&c, [pinch(p, 1)], frames: 3)
        XCTAssertFalse(grabbed, "a tenth of a second is not yet a grab")
        XCTAssertGreaterThan(last?.overlay.item?.arming ?? 0, 0.5, "but the ring is filling")
        run(&c, [pinch(p, 1)], frames: 2)
        XCTAssertTrue(events.contains(.grabbed(.panel, byHand: true)), "held a little longer, it takes hold")
        XCTAssertTrue(c.isHolding)
        XCTAssertNotNil(last?.overlay.item?.pulse, "and pulses to say so")
    }

    func testDraggingKeepsWhereItWasGrabbed() {
        var c = StageHandController(layout: panelLayout())
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY + 40)
        grab(&c, at: p)
        let start = center(last!)
        let offset = CGVector(dx: start.x - p.x, dy: start.y - p.y)
        for k in 1...12 { run(&c, [pinch(CGPoint(x: p.x + Double(k) * 8, y: p.y - Double(k) * 3), 1)]) }
        let end = run(&c, [pinch(CGPoint(x: p.x + 96, y: p.y - 36), 1)], frames: 20)
        let c1 = center(end)
        XCTAssertEqual(c1.x - (p.x + 96), offset.dx, accuracy: 3, "the panel keeps the same offset from the pinch")
        XCTAssertEqual(c1.y - (p.y - 36), offset.dy, accuracy: 3)
        XCTAssertGreaterThan(end.live.panelLift, 0.9, "and is lifted while held")
    }

    func testTwoHandsResizeAboutTheirMiddleAndKeepTheShape() {
        var c = StageHandController(layout: panelLayout())
        let right = CGPoint(x: panel.maxX + 20, y: panel.midY)
        let left = CGPoint(x: panel.minX + 30, y: panel.midY)
        grab(&c, at: right)
        let size0 = last!.layout.panel.size
        run(&c, [pinch(right, 1), pinch(left, 0.2, id: 2, mirrored: true)], frames: 6)
        run(&c, [pinch(right, 1), pinch(left, 1, id: 2, mirrored: true)], frames: 4)
        XCTAssertTrue(events.contains(.resizing(.panel)))
        let d0 = right.x - left.x
        for k in 1...10 {
            run(&c, [pinch(CGPoint(x: right.x + Double(k) * 6, y: right.y), 1), pinch(CGPoint(x: left.x - Double(k) * 6, y: left.y), 1, id: 2, mirrored: true)])
        }
        let out = run(&c, [pinch(CGPoint(x: right.x + 60, y: right.y), 1), pinch(CGPoint(x: left.x - 60, y: left.y), 1, id: 2, mirrored: true)], frames: 20)
        XCTAssertEqual(out.layout.panel.size / size0, (d0 + 120) / d0, accuracy: 0.02, "it grows as far as the hands spread")
        let r = StageGeometry.panelRect(out.layout.panel, aspect: aspect)
        XCTAssertEqual(r.width / r.height, aspect, accuracy: 0.001, "keeping the content's shape")
        XCTAssertNotNil(out.overlay.stretch, "with a stretch line between the hands")
        XCTAssertEqual(out.overlay.stretch?.label, "\(Int((out.layout.panel.size * 100).rounded()))%")
        XCTAssertNil(out.overlay.item?.readout, "and the size on it, not twice")
    }

    func testLettingGoOfOneHandOfAResizeCarriesOnMovingWithTheOther() {
        var c = StageHandController(layout: panelLayout())
        let right = CGPoint(x: panel.maxX + 20, y: panel.midY)
        let left = CGPoint(x: panel.minX + 30, y: panel.midY)
        grab(&c, at: right)
        run(&c, [pinch(right, 1), pinch(left, 0.2, id: 2, mirrored: true)], frames: 6)
        run(&c, [pinch(right, 1), pinch(left, 1, id: 2, mirrored: true)], frames: 6)
        let before = center(run(&c, [pinch(right, 1), pinch(left, 0.1, id: 2, mirrored: true)], frames: 6))
        XCTAssertTrue(c.isHolding, "the other hand still holds it")
        let after = center(run(&c, [pinch(CGPoint(x: right.x - 50, y: right.y), 1)], frames: 20))
        XCTAssertEqual(after.x - before.x, -50, accuracy: 4, "and moves it, without a jump")
    }

    // MARK: Letting go

    func testAThrowGlidesOnAndOnlyEverSlowsDown() {
        var c = StageHandController(layout: panelLayout(snapping: false))
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY)
        grab(&c, at: p)
        var x = p.x
        for _ in 0..<8 { x += 20; run(&c, [pinch(CGPoint(x: x, y: p.y), 1)]) }    // 600 px a second
        let atRelease = center(run(&c, [pinch(CGPoint(x: x, y: p.y), 0.1)], frames: 2))
        var previous = atRelease.x, steps: [Double] = []
        for _ in 0..<40 {
            let now = center(run(&c, [pinch(CGPoint(x: x, y: p.y), 0.1)])).x
            steps.append(now - previous)
            previous = now
        }
        XCTAssertGreaterThan(previous - atRelease.x, 40, "it keeps going after it is let go")
        XCTAssertTrue(events.contains(.released(.panel)))
        for (a, b) in zip(steps, steps.dropFirst()) {
            XCTAssertLessThanOrEqual(b, a + 0.6, "and never speeds up after release: \(steps.map { Int($0) })")
        }
        XCTAssertLessThan(abs(steps.suffix(5).reduce(0, +)), 1.5, "it comes to rest")
    }

    func testLettingGoNearTheCentreSettlesOntoItWithAGuideFlash() {
        var c = StageHandController(layout: panelLayout())
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY)
        grab(&c, at: p)
        let shift = 640 - panel.midX - 22   // 22 px short of the centre line
        for k in 1...15 { run(&c, [pinch(CGPoint(x: p.x + shift * Double(k) / 15, y: p.y), 1)]) }
        run(&c, [pinch(CGPoint(x: p.x + shift, y: p.y), 1)], frames: 15)    // held still, then let go slowly
        let flash = run(&c, [pinch(CGPoint(x: p.x + shift, y: p.y), 0.1)], frames: 3)
        XCTAssertTrue(events.contains { if case .snapped(.panel, let g) = $0 { return g.contains { $0.vertical && $0.kind == .centre } } else { return false } })
        XCTAssertTrue(flash.overlay.guides.contains { $0.guide.vertical && $0.guide.kind == .centre && $0.alpha > 0.5 }, "the guide flashes")
        let rest = run(&c, [], frames: 45)
        XCTAssertEqual(center(rest).x, 640, accuracy: 0.5, "and it settles exactly on it")
        XCTAssertFalse(rest.isActive)
        XCTAssertTrue(rest.overlay.guides.isEmpty, "the flash fades")
    }

    func testWithSnappingOffItStaysWhereItWasLetGo() {
        var c = StageHandController(layout: panelLayout(snapping: false))
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY)
        grab(&c, at: p)
        let shift = 640 - panel.midX - 22
        for k in 1...15 { run(&c, [pinch(CGPoint(x: p.x + shift * Double(k) / 15, y: p.y), 1)]) }
        let held = center(run(&c, [pinch(CGPoint(x: p.x + shift, y: p.y), 1)], frames: 15))
        let rest = run(&c, [pinch(CGPoint(x: p.x + shift, y: p.y), 0.1)], frames: 45)
        XCTAssertEqual(center(rest).x, held.x, accuracy: 3)
    }

    func testPulledPastTheEdgeItResistsAndSettlesBackInside() {
        var c = StageHandController(layout: panelLayout())
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY)
        grab(&c, at: p)
        var worst = 0.0
        for k in 1...30 {
            let out = run(&c, [pinch(CGPoint(x: p.x + Double(k) * 30, y: p.y), 1)])
            worst = max(worst, Double(StageGeometry.panelRect(out.layout.panel, aspect: aspect).maxX))
        }
        XCTAssertLessThan(worst, 1280 - Double(StageGeometry.safeMargin) + 91, "however far the hand goes, the panel gives at most a little")
        let rest = run(&c, [pinch(CGPoint(x: p.x + 900, y: p.y), 0.1)], frames: 60)
        XCTAssertLessThanOrEqual(Double(StageGeometry.panelRect(rest.layout.panel, aspect: aspect).maxX), 1280 - Double(StageGeometry.safeMargin) + 0.5,
                                 "let go, it settles back inside the safe margin")
    }

    func testADoublePinchMaximisesAndAnotherRestores() {
        var c = StageHandController(layout: panelLayout())
        let original = c.layout.panel
        let p = CGPoint(x: panel.midX + 100, y: panel.midY + 60)
        func tap() {
            run(&c, [pinch(p, 1)], frames: 4)
            run(&c, [pinch(p, 0.1)], frames: 4)
        }
        run(&c, [pinch(p, 0.1)], frames: 8)
        tap(); tap()
        XCTAssertTrue(events.contains(.maximised(.panel, true)))
        var out = run(&c, [pinch(p, 0.1)], frames: 60)
        let big = StageGeometry.maximisedPanel(aspect: aspect)
        XCTAssertEqual(out.layout.panel.size, big.size, accuracy: 0.002, "zoomed up to fill the picture")
        XCTAssertEqual(out.layout.restorePanel, original)
        events.removeAll()
        let q = CGPoint(x: 700, y: 400)
        run(&c, [pinch(q, 0.1)], frames: 8)
        for _ in 0..<2 {
            run(&c, [pinch(q, 1)], frames: 4)
            run(&c, [pinch(q, 0.1)], frames: 4)
        }
        XCTAssertTrue(events.contains(.maximised(.panel, false)))
        out = run(&c, [pinch(q, 0.1)], frames: 60)
        XCTAssertTrue(out.layout.panel.isClose(to: original, tolerance: 0.003), "and back where it was")
        XCTAssertNil(out.layout.restorePanel)
    }

    func testTheZoomIsSmoothNotAJump() {
        var c = StageHandController(layout: panelLayout())
        let p = CGPoint(x: panel.midX, y: panel.midY)
        run(&c, [pinch(p, 0.1)], frames: 8)
        for _ in 0..<2 { run(&c, [pinch(p, 1)], frames: 4); run(&c, [pinch(p, 0.1)], frames: 4) }
        var sizes: [Double] = []
        for _ in 0..<20 { sizes.append(run(&c, [pinch(p, 0.1)]).layout.panel.size) }
        let jumps = zip(sizes, sizes.dropFirst()).map { $1 - $0 }
        XCTAssertLessThan(jumps.max() ?? 1, 0.08, "it grows over several frames: \(jumps)")
    }

    // MARK: Losing a hand

    func testAHandLostMidGrabLetsGoGentlyWhereItIs() {
        var c = StageHandController(layout: panelLayout(snapping: false))
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY)
        grab(&c, at: p)
        for k in 1...8 { run(&c, [pinch(CGPoint(x: p.x + Double(k) * 15, y: p.y), 1)]) }
        let atLoss = center(last!)
        run(&c, [])
        XCTAssertTrue(events.contains(.released(.panel)))
        XCTAssertFalse(c.isHolding)
        let rest = center(run(&c, [], frames: 45))
        XCTAssertLessThan(HandState.distance(rest, atLoss), 30, "it settles where it was, not flung away")
    }

    func testAHandBlurredForAMomentKeepsItsGrip() {
        var c = StageHandController(layout: panelLayout())
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY)
        grab(&c, at: p)
        let before = center(last!)
        var guess = pinch(CGPoint(x: p.x + 80, y: p.y + 80), 1)   // the tracker coasting somewhere odd
        guess.unseenFor = 0.06
        run(&c, [guess], frames: 3)
        XCTAssertTrue(c.isHolding, "a short gap does not let go")
        XCTAssertLessThan(HandState.distance(center(last!), before), 4, "and nothing moves on a guess")
        run(&c, [pinch(CGPoint(x: p.x + 30, y: p.y), 1)], frames: 15)
        XCTAssertTrue(c.isHolding)
        XCTAssertEqual(center(last!).x - before.x, 30, accuracy: 3, "back in view, it carries on")
    }

    // MARK: Never by accident

    private func assertNoGrab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(grabbed, "\(name) must not grab", file: file, line: line)
        XCTAssertNil(last?.overlay.item.map { $0.arming > 0 ? $0 : nil } ?? nil, "\(name) must not start filling the ring", file: file, line: line)
    }

    func testAnOpenHandOnThePanelNeverGrabs() {
        var c = StageHandController(layout: panelLayout())
        run(&c, [HandFixtures.openPalm(at: CGPoint(x: panel.midX, y: panel.midY - 120), size: 110)], frames: 60)
        assertNoGrab("an open hand")
    }

    func testAFistNeverGrabs() {
        var c = StageHandController(layout: panelLayout())
        run(&c, [HandFixtures.hand(.fist, at: CGPoint(x: panel.midX, y: panel.midY - 60), size: 110)], frames: 60)
        assertNoGrab("a fist")
    }

    func testPointingNeverGrabs() {
        var c = StageHandController(layout: panelLayout())
        for angle in [0.0, 0.6, -0.6] {
            run(&c, [HandFixtures.hand(.point, at: CGPoint(x: panel.midX, y: panel.midY - 100), size: 110, angle: angle)], frames: 30)
        }
        assertNoGrab("pointing")
    }

    func testAWaveNeverGrabs() {
        var c = StageHandController(layout: panelLayout())
        for k in 0..<60 {
            let x = panel.midX + 260 * sin(Double(k) * 0.5)
            run(&c, [HandFixtures.openPalm(at: CGPoint(x: x, y: panel.midY - 100), size: 110, angle: 0.3 * sin(Double(k) * 0.5))])
        }
        assertNoGrab("a wave")
    }

    func testAPinchMadeFarAwayAndCarriedOverThePanelDoesNothing() {
        var c = StageHandController(layout: panelLayout())
        let far = CGPoint(x: 1150, y: 600)
        run(&c, [pinch(far, 0.2)], frames: 6)
        run(&c, [pinch(far, 1)], frames: 10)
        for k in 1...20 {
            let t = Double(k) / 20
            run(&c, [pinch(CGPoint(x: far.x + (panel.midX - far.x) * t, y: far.y + (panel.midY - far.y) * t), 1)])
        }
        run(&c, [pinch(CGPoint(x: panel.midX, y: panel.midY), 1)], frames: 30)
        assertNoGrab("a pinch that started far away")
    }

    func testAQuickPinchUnderTheHoldTimeDoesNothing() {
        var c = StageHandController(layout: panelLayout())
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY)
        run(&c, [pinch(p, 0.2)], frames: 6)
        run(&c, [pinch(p, 1)], frames: 2)        // a fifteenth of a second
        run(&c, [pinch(p, 0.2)], frames: 30)
        assertNoGrab("a quick pinch")
        XCTAssertFalse(events.contains { if case .maximised = $0 { return true } else { return false } }, "and one tap is not a double")
    }

    func testAHandThatArrivesAlreadyPinchedDoesNothing() {
        var c = StageHandController(layout: panelLayout())
        run(&c, [pinch(CGPoint(x: panel.maxX + 20, y: panel.midY), 1)], frames: 30)
        assertNoGrab("a hand that comes into view pinched")
    }

    func testHandsOnAKeyboardAtTheBottomDoNothing() {
        var c = StageHandController(layout: panelLayout())
        var low = panelLayout()
        low.panel.center.y = 0.3
        c.adopt(low)
        let p = CGPoint(x: 400, y: 20)
        run(&c, [pinch(p, 0.2)], frames: 6)
        run(&c, [pinch(p, 1)], frames: 20)
        assertNoGrab("a pinch at the very bottom edge")
    }

    func testAPinchThatWandersWhileHeldIsNotAGrab() {
        var c = StageHandController(layout: panelLayout())
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY)
        run(&c, [pinch(p, 0.2)], frames: 6)
        // Fingers brushing together while gesturing, the hand sweeping across: closed, but moving a long way.
        run(&c, [pinch(p, 1)], frames: 1)
        run(&c, [pinch(CGPoint(x: p.x - 140, y: p.y + 50), 1)], frames: 1)
        run(&c, [pinch(CGPoint(x: p.x - 280, y: p.y + 100), 1)], frames: 8)
        assertNoGrab("a pinch that sweeps away while closing")
    }

    func testWithAHandLensOnAGrabTakesALongerHold() {
        var c = StageHandController(layout: panelLayout())
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY)
        run(&c, [pinch(p, 0.2)], frames: 6, lens: true)
        run(&c, [pinch(p, 1)], frames: 6, lens: true)       // 0.2 s: would have grabbed without the lens
        XCTAssertFalse(grabbed, "with a hand lens on, 0.2 s is not enough")
        let arming = last?.overlay.item?.arming ?? 0
        XCTAssertGreaterThan(arming, 0.5, "the ring visibly fills meanwhile")
        XCTAssertLessThan(arming, 0.9)
        run(&c, [pinch(p, 1)], frames: 5, lens: true)
        XCTAssertTrue(grabbed, "held deliberately, it grabs")
    }

    func testWithHandControlOffHandsAreIgnored() {
        var c = StageHandController(layout: panelLayout(handControl: false))
        grab(&c, at: CGPoint(x: panel.maxX + 20, y: panel.midY))
        XCTAssertFalse(grabbed)
        XCTAssertTrue(last?.overlay.cursors.isEmpty ?? false, "no cursors either")
    }

    // MARK: The chrome

    func testTheRingAppearsAsAHandNearsAndDrawsInAsItCloses() {
        var c = StageHandController(layout: panelLayout())
        let far = run(&c, [pinch(CGPoint(x: panel.maxX + 300, y: panel.midY), 0.2)], frames: 15)
        let near = run(&c, [pinch(CGPoint(x: panel.maxX + 30, y: panel.midY), 0.2)], frames: 15)
        XCTAssertLessThan(far.overlay.item?.hover ?? 0, 0.1)
        XCTAssertGreaterThan(near.overlay.item?.hover ?? 0, 0.8)
        let closing = run(&c, [pinch(CGPoint(x: panel.maxX + 30, y: panel.midY), 0.5)], frames: 6)
        XCTAssertGreaterThan(closing.overlay.item?.tighten ?? 0, near.overlay.item?.tighten ?? 1, "the ring draws in as the fingers close")
        XCTAssertEqual(near.overlay.cursors.count, 1)
        XCTAssertEqual(near.overlay.cursors.first?.phase, .hovering)
        XCTAssertTrue(run(&c, [HandFixtures.openPalm(at: CGPoint(x: panel.maxX + 30, y: panel.midY - 100))], frames: 60).overlay.cursors.isEmpty,
                      "an open hand gets no cursor (the last one fades away)")
    }

    // MARK: Presenter

    func testTheBubbleIsGrabbedAndMoved() {
        var l = StagePreset.cornerBubble.apply(to: StageLayout())
        l.handControl = true
        var c = StageHandController(layout: l)
        let bubble = StageGeometry.bubbleRect(l.presenter)
        let p = CGPoint(x: bubble.minX - 10, y: bubble.maxY)
        run(&c, [pinch(p, 0.2, mirrored: true)], frames: 6)
        run(&c, [pinch(p, 1, mirrored: true)], frames: 6)
        XCTAssertTrue(events.contains(.grabbed(.presenter, byHand: true)))
        let out = run(&c, [pinch(CGPoint(x: p.x - 300, y: p.y + 100), 1, mirrored: true)], frames: 30)
        XCTAssertEqual(StageGeometry.point(out.layout.presenter.center).x, StageGeometry.point(l.presenter.center).x - 300, accuracy: 4)
        XCTAssertTrue(out.layout.panel == l.panel, "the panel is not part of this arrangement")
    }

    func testYourCutoutIsGrabbedNearWhereYouAre() {
        var l = StageMemory.starting(.presenter, from: StageLayout())
        l.handControl = true
        var c = StageHandController(layout: l)
        let anchor = CGPoint(x: 640, y: 300)
        let box = StageGeometry.cutoutRect(l.presenter, anchor: anchor)
        let p = CGPoint(x: box.minX + 10, y: box.midY)
        run(&c, [pinch(p, 0.2)], frames: 6, anchor: anchor)
        run(&c, [pinch(p, 1)], frames: 6, anchor: anchor)
        XCTAssertTrue(events.contains(.grabbed(.presenter, byHand: true)))
    }

    // MARK: Mouse and trackpad

    func testTheMouseDragsScrollsAndDoubleClicks() {
        var c = StageHandController(layout: panelLayout(handControl: false))
        let at = StageGeometry.normalised(CGPoint(x: panel.midX, y: panel.midY))
        run(&c, [], pointer: [.down(at)])
        XCTAssertTrue(events.contains(.grabbed(.panel, byHand: false)))
        let moved = CGPoint(x: at.x + 0.05, y: at.y)
        run(&c, [], frames: 20, pointer: [.drag(moved)])
        var out = run(&c, [], frames: 40, pointer: [.up(moved)])
        XCTAssertEqual(StageGeometry.point(out.layout.panel.center).x, panel.midX + 64, accuracy: 3)

        let size = out.layout.panel.size
        out = run(&c, [], frames: 30, pointer: [.scroll(40, at: moved)])
        XCTAssertGreaterThan(out.layout.panel.size, size * 1.15, "scrolling up makes it bigger")
        out = run(&c, [], frames: 30, pointer: [.magnify(-0.2, at: moved)])
        XCTAssertLessThan(out.layout.panel.size, size * 1.15)

        out = run(&c, [], frames: 60, pointer: [.doubleClick(moved)])
        XCTAssertEqual(out.layout.panel.size, StageGeometry.maximisedPanel(aspect: aspect).size, accuracy: 0.002, "a double click maximises")
    }

    func testTheMouseCanTakeACornerHandleToResize() {
        var c = StageHandController(layout: panelLayout(handControl: false))
        let middle = StageGeometry.normalised(CGPoint(x: panel.midX, y: panel.midY))
        run(&c, [], frames: 2, pointer: [.down(middle)])
        run(&c, [], frames: 2, pointer: [.up(middle)])
        let size = last!.layout.panel.size
        let corner = StageGeometry.normalised(CGPoint(x: panel.maxX, y: panel.maxY))
        run(&c, [], pointer: [.down(corner)])
        XCTAssertTrue(events.contains(.resizing(.panel)))
        run(&c, [], frames: 20, pointer: [.drag(StageGeometry.normalised(CGPoint(x: panel.maxX + 60, y: panel.maxY + 37)))])
        let out = run(&c, [], frames: 20, pointer: [.up(corner)])
        XCTAssertGreaterThan(out.layout.panel.size, size * 1.08)
    }

    // MARK: Taking layouts from the interface

    func testAPresetGlidesIntoPlace() {
        var c = StageHandController(layout: panelLayout())
        let from = StageGeometry.point(c.layout.panel.center)
        var right = StagePreset.right.apply(to: panelLayout())
        right.tilt = 0
        c.adopt(right)
        let first = center(run(&c, []))
        XCTAssertGreaterThan(first.x, from.x + 1, "it starts moving")
        XCTAssertLessThan(first.x, StageGeometry.point(right.panel.center).x - 50, "but does not jump there")
        let end = run(&c, [], frames: 60)
        XCTAssertTrue(end.layout.panel.isClose(to: right.panel, tolerance: 0.001))
    }

    func testTheInterfaceEchoingTheLayoutBackDoesNotPullItBack() {
        var c = StageHandController(layout: panelLayout(snapping: false))
        let p = CGPoint(x: panel.maxX + 20, y: panel.midY)
        grab(&c, at: p)
        var x = p.x
        for _ in 0..<8 { x += 20; run(&c, [pinch(CGPoint(x: x, y: p.y), 1)]) }
        let reported = run(&c, [pinch(CGPoint(x: x, y: p.y), 0.1)], frames: 3).layout
        c.didReport(reported)
        var echo = reported
        echo.tilt = 0.8                     // a slider moved while the panel was still gliding
        run(&c, [pinch(CGPoint(x: x, y: p.y), 0.1)], frames: 2)
        c.adopt(echo)
        let after = run(&c, [pinch(CGPoint(x: x, y: p.y), 0.1)])
        XCTAssertGreaterThan(center(after).x, StageGeometry.point(reported.panel.center).x, "the glide carries on")
        XCTAssertEqual(after.layout.tilt, 0.8, "and the slider's change is taken")
    }
}
