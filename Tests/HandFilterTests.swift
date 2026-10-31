import CoreImage
import XCTest

/// The hand filters: Air Paint, Energy Ball, Finger Lightning, Sparkle Trail and Laser Pointer.
final class HandFilterTests: XCTestCase {
    private let h = LensHarness()
    private let size = CGSize(width: 1280, height: 720)
    private lazy var base = h.input()
    private var frame = 0

    private func brightness(_ p: RGB) -> Int { p.r + p.g + p.b }
    private func plainBrightness(_ x: Int, _ y: Int) -> Int { brightness(h.pixel(base.composed, x, y)) }

    /// Renders one frame at 30 a second with these hands in view.
    @discardableResult
    private func step(_ lens: Lens, _ hands: [HandState], dt: Double = 1.0 / 30) -> CIImage {
        defer { frame += 1 }
        return lens.render(h.at(base, time: Double(frame) / 30, dt: dt, hands: hands))
    }

    private func run(_ lens: Lens, _ hands: [HandState], frames: Int) {
        for _ in 0..<frames { step(lens, hands) }
    }

    /// A pointing hand whose fingertip is at `tip`.
    private func pointing(at tip: CGPoint, size: Double = 100, id: Int = 1, velocity: CGVector = .zero) -> HandState {
        let hand = HandFixtures.hand(.point, at: CGPoint(x: 640, y: 300), size: size, id: id)
        return HandFixtures.moved(hand, by: CGVector(dx: tip.x - hand.indexTip.x, dy: tip.y - hand.indexTip.y), velocity: velocity)
    }

    private func openPalm(at wrist: CGPoint = CGPoint(x: 640, y: 260), size: Double = 120, id: Int = 1, velocity: CGVector = .zero) -> HandState {
        HandFixtures.hand(.open, at: wrist, size: size, id: id, velocity: velocity)
    }

    private func moved(_ hand: HandState, to wrist: CGPoint, velocity: CGVector = .zero) -> HandState {
        HandFixtures.moved(hand, by: CGVector(dx: wrist.x - hand.wrist.x, dy: wrist.y - hand.wrist.y), velocity: velocity)
    }

    private func makeLenses() -> [(name: String, lens: Lens)] {
        HandFilters.all.map { ($0.id, $0.make()) }
    }

    // MARK: Registration and the things they all do

    func testTheFiveHandFiltersAreRegisteredAndNeedHands() {
        XCTAssertEqual(Array(HandFilters.all.map(\.id).prefix(5)), ["air-paint", "energy-ball", "finger-lightning", "sparkle-trail", "laser-pointer"])
        for info in HandFilters.all {
            XCTAssertEqual(info.category, .filters)
            XCTAssertTrue(info.needsHands, info.name)
            XCTAssertFalse(info.needsFace)
            XCTAssertTrue(info.make().needs.contains(.hands), info.name)
            XCTAssertNotNil(LensCatalog.info(for: info.id))
        }
    }

    func testWithNoHandsEveryHandFilterOnlyShowsAWavingHandHintForAFewSeconds() {
        let hintArea = HandFXHint.area(in: size)
        for (name, lens) in makeLenses() {
            XCTAssertTrue(lens.status?.title.hasPrefix("Hold up your hand") ?? false, "\(name) says so before it has seen anything")
            var out = base.composed
            for _ in 0..<12 { out = step(lens, []) }
            XCTAssertEqual(h.bitmap(out).change(from: h.bitmap(base.composed), in: base.rect), 0, "\(name) leaves the picture alone at first")
            XCTAssertTrue(lens.status?.title.hasPrefix("Hold up your hand") ?? false, name)
            XCTAssertNotNil(lens.status?.detail, name)
            XCTAssertEqual(out.extent, base.rect)
            // Then a small hand waves at the bottom of the picture, and only there.
            for _ in 0..<30 { out = step(lens, []) }
            let shown = h.bitmap(out), plain = h.bitmap(base.composed)
            if name == "air-paint" { Output.save(out, as: "hint-air-paint.png") }
            XCTAssertGreaterThan(shown.change(from: plain, in: hintArea), 200, "\(name) shows the hint")
            for outside in [CGRect(x: 0, y: 0, width: 1280, height: hintArea.minY), CGRect(x: 0, y: hintArea.maxY, width: 1280, height: 720 - hintArea.maxY),
                            CGRect(x: 0, y: 0, width: hintArea.minX, height: 720), CGRect(x: hintArea.maxX, y: 0, width: 1280 - hintArea.maxX, height: 720)] {
                XCTAssertEqual(shown.change(from: plain, in: outside), 0, "\(name) draws nothing else")
            }
            // It goes away by itself after a few seconds, and for good while nobody is there.
            for _ in 0..<200 { out = step(lens, []) }
            XCTAssertEqual(h.bitmap(out).change(from: plain, in: base.rect), 0, "\(name) lets the hint go")
        }
    }

    func testTheHintComesBackOnlyAfterTheHandsHaveBeenAwayAWhile() {
        var hint = HandFXHint()
        for _ in 0..<30 { hint.update(handsInView: false, dt: 1.0 / 30) }
        XCTAssertTrue(hint.isShowing)
        hint.update(handsInView: true, dt: 1.0 / 30)
        for _ in 0..<12 { hint.update(handsInView: true, dt: 1.0 / 30) }
        XCTAssertFalse(hint.isShowing, "a hand sends it away at once")
        // The hand drops for a moment, as tracking does: no hint.
        for _ in 0..<60 { hint.update(handsInView: false, dt: 1.0 / 30) }
        XCTAssertFalse(hint.isShowing, "two seconds without a hand is not long enough to nag")
        for _ in 0..<90 { hint.update(handsInView: false, dt: 1.0 / 30) }
        XCTAssertTrue(hint.isShowing, "five seconds is")
        for _ in 0..<200 { hint.update(handsInView: false, dt: 1.0 / 30) }
        XCTAssertFalse(hint.isShowing, "and it does not stay")
        for _ in 0..<10 { hint.update(handsInView: false, dt: 5) }
        XCTAssertFalse(hint.isShowing, "a stalled frame changes nothing")
    }

    func testEveryHandFilterShowsSomethingForAHandAndSaysWhatToDo() {
        let shows: [(String, [HandState])] = [
            ("air-paint", [pointing(at: CGPoint(x: 300, y: 400))]),
            ("energy-ball", [openPalm()]),
            ("finger-lightning", [openPalm()]),
            ("sparkle-trail", [openPalm()]),
            ("laser-pointer", [pointing(at: CGPoint(x: 300, y: 400))]),
        ]
        for (name, hands) in shows {
            let lens = HandFilters.all.first { $0.id == name }!.make()
            var out = base.composed
            for i in 0..<20 {
                // A little motion so that anything which needs movement has some.
                out = step(lens, hands.map { HandFixtures.moved($0, by: CGVector(dx: Double(i % 4) * 6, dy: 0), velocity: CGVector(dx: 180, dy: 0)) })
            }
            XCTAssertGreaterThan(h.bitmap(out).change(from: h.bitmap(base.composed), in: base.rect), 150, "\(name) draws something for a hand")
            XCTAssertNotEqual(lens.status?.title, "Hold up your hand", "\(name) notices the hand")
        }
    }

    func testEveryHandFilterFadesAwayWhenTheHandVanishesAndNeverCrashesOnOddInput() {
        for (name, lens) in makeLenses() {
            let hands = [openPalm(), HandFixtures.hand(.point, at: CGPoint(x: 300, y: 200), size: 90, mirrored: true, id: 2)]
            run(lens, hands, frames: 25)
            // A hand lost for a few frames is not the end of the effect, and a long absence is.
            run(lens, [], frames: 3)
            run(lens, [], frames: 400)
            if name != "air-paint" {   // Air Paint keeps what was drawn until it fades; the others have nothing left
                let out = step(lens, [])
                XCTAssertEqual(h.bitmap(out).change(from: h.bitmap(base.composed), in: base.rect), 0, "\(name) has let go once the hand has been gone a while")
            }
            // Hands at the very edge, absurdly large, tiny, and a stalled frame.
            let odd = [HandFixtures.hand(.open, at: CGPoint(x: 1275, y: 715), size: 400), HandFixtures.hand(.point, at: CGPoint(x: -50, y: -50), size: 8, id: 2)]
            for dt in [1.0 / 30, 5.0, 0.0, 1.0 / 30] { step(lens, odd, dt: dt) }
            XCTAssertEqual(step(lens, odd).extent, base.rect, name)
            lens.restart()
            XCTAssertEqual(step(lens, odd).extent, base.rect, "\(name) after a restart")
        }
    }

    func testEveryHandFilterIsCheapEvenWithTwoHandsMovingFast() {
        let buffer = h.compositor.makeOutputBuffer()!
        /// The median milliseconds to make and render a frame: the middle value ignores the odd slow frame when the machine is busy.
        func median(_ lens: Lens) -> Double {
            var durations: [Double] = []
            for i in 0..<140 {
                let t = Double(i) / 30
                let a = HandFixtures.moved(i % 40 < 20 ? openPalm() : pointing(at: CGPoint(x: 400, y: 450)), by: CGVector(dx: 160 * sin(t * 6), dy: 60 * cos(t * 5)),
                                           velocity: CGVector(dx: 1900 * cos(t * 6), dy: -300 * sin(t * 5)))
                let b = HandFixtures.moved(HandFixtures.hand(.open, at: CGPoint(x: 900, y: 250), size: 110, mirrored: true, id: 2), by: CGVector(dx: -120 * sin(t * 5), dy: 40 * sin(t * 7)))
                let started = CFAbsoluteTimeGetCurrent()
                h.compositor.render(lens.render(h.at(base, time: t, hands: [a, b])), into: buffer)
                if i >= 30 { durations.append((CFAbsoluteTimeGetCurrent() - started) * 1000) }
            }
            return durations.sorted()[durations.count / 2]
        }
        final class Nothing: Lens {
            let needs: LensNeeds = [.hands]
            func render(_ input: LensInput) -> CIImage { input.composed }
        }
        let baseline = median(Nothing())
        for (name, lens) in makeLenses() {
            let added = median(lens) - baseline
            XCTAssertLessThan(added, 9, "\(name) adds \(added) ms a frame to the \(baseline) ms of doing nothing")
        }
    }

    // MARK: Air Paint

    func testAirPaintDrawsASmoothGlowingLineWhereTheFingerGoes() {
        let lens = AirPaintLens()
        var path: [CGPoint] = []
        var out = base.composed
        for i in 0..<60 {
            let a = Double(i) / 60 * 2 * .pi * 0.9
            let tip = CGPoint(x: 300 + 120 * cos(a), y: 400 + 120 * sin(a))
            path.append(tip)
            out = step(lens, [pointing(at: tip)])
        }
        Output.save(out, as: "airpaint-circle.png")
        XCTAssertEqual(lens.strokes.count, 1, "one continuous stroke")
        XCTAssertTrue(lens.isDrawing)
        // The line is a smoothed version of the path, a few pixels inside it, and it glows all along.
        let line = lens.strokes[0].curve
        XCTAssertGreaterThan(line.count, 50)
        for p in line.dropLast(6).enumerated().filter({ $0.offset % 4 == 0 }).map(\.element) {
            XCTAssertGreaterThan(brightness(h.pixel(out, Int(p.x), Int(p.y))), plainBrightness(Int(p.x), Int(p.y)) + 300, "glowing at \(p)")
        }
        for tip in path.dropLast(3) where Int(tip.x) % 2 == 0 {
            XCTAssertGreaterThan(brightness(h.pixel(out, Int(tip.x), Int(tip.y))), plainBrightness(Int(tip.x), Int(tip.y)) + 150, "and the glow reaches the finger's path at \(tip)")
        }
        XCTAssertLessThan(brightness(h.pixel(out, 300, 400)), plainBrightness(300, 400) + 60, "the middle of the circle is empty")
        XCTAssertEqual(lens.status?.title, "Drawing")
    }

    func testAirPaintJoinsUpFastMovesWithASmoothCurveNotGaps() {
        var canvas = AirPaintCanvas()
        // 25 looks a second of a quick swoop: 110 px between looks.
        for i in 0..<14 {
            let x = 200 + Double(i) * 110, y = 400 + 140 * sin(Double(i) * 0.5)
            canvas.update(hands: [pointing(at: CGPoint(x: x, y: y))], dt: 1.0 / 25)
        }
        XCTAssertEqual(canvas.strokes.count, 1, "a fast move is not a break")
        let line = canvas.smoothLine(of: canvas.strokes[0])
        XCTAssertGreaterThan(line.count, 100, "many samples between the looks")
        for i in 1..<line.count { XCTAssertLessThan(HandFXKit.distance(line[i].position, line[i - 1].position), 9, "no gaps at sample \(i)") }
        // It bends through the looks without cusps: the direction never turns back on itself.
        for i in 2..<line.count {
            let a = line[i - 1].position - line[i - 2].position, b = line[i].position - line[i - 1].position
            XCTAssertGreaterThan(a.dx * b.dx + a.dy * b.dy, 0, "turns back at sample \(i)")
        }
    }

    func testTheCurveGoesThroughItsPointsAndNeverLoopsOnAJump() {
        let p0 = CGPoint(x: 0, y: 0), p1 = CGPoint(x: 100, y: 50), p2 = CGPoint(x: 300, y: 40), p3 = CGPoint(x: 340, y: 200)
        let start = AirPaintCanvas.curve(p0, p1, p2, p3, 0), end = AirPaintCanvas.curve(p0, p1, p2, p3, 1)
        XCTAssertEqual(start.x, p1.x, accuracy: 0.01)
        XCTAssertEqual(start.y, p1.y, accuracy: 0.01)
        XCTAssertEqual(end.x, p2.x, accuracy: 0.01)
        XCTAssertEqual(end.y, p2.y, accuracy: 0.01)
        for k in 0...20 {
            let p = AirPaintCanvas.curve(p0, p1, p2, p3, Double(k) / 20)
            XCTAssertTrue(p.x >= 95 && p.x <= 305 && p.y >= 20 && p.y <= 120, "stays near the segment: \(p)")
        }
        // A hairpin: close points then a long jump must not overshoot wildly.
        let q = (0...20).map { AirPaintCanvas.curve(CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 400, y: 0), CGPoint(x: 405, y: 3), Double($0) / 20) }
        XCTAssertTrue(q.allSatisfy { $0.x >= -20 && $0.x <= 430 && abs($0.y) < 20 })
    }

    func testTheLineBreaksWhenTheFingerLiftsNotWhenTheTrackerFlickers() {
        let lens = AirPaintLens()
        for i in 0..<20 { step(lens, [pointing(at: CGPoint(x: 200 + Double(i) * 6, y: 450))]) }
        XCTAssertEqual(lens.strokes.count, 1)
        // The pose flickers for two frames (the middle finger half out): the pen stays down.
        let flicker = HandFixtures.moved(HandFixtures.hand(.peace, at: CGPoint(x: 640, y: 300), size: 100), by: .zero)
        let tip = pointing(at: CGPoint(x: 320, y: 450))
        let flickering = HandFixtures.moved(flicker, by: CGVector(dx: tip.indexTip.x - flicker.indexTip.x, dy: tip.indexTip.y - flicker.indexTip.y))
        XCTAssertNotEqual(flickering.pose, .point)
        for _ in 0..<2 { step(lens, [flickering]) }
        for i in 0..<10 { step(lens, [pointing(at: CGPoint(x: 322 + Double(i) * 6, y: 450))]) }
        XCTAssertEqual(lens.strokes.count, 1, "a flicker does not break the line")

        // A real lift: a fist for a third of a second, then pointing somewhere new.
        let fist = HandFixtures.hand(.fist, at: CGPoint(x: 640, y: 300), size: 100)
        run(lens, [fist], frames: 10)
        XCTAssertFalse(lens.isDrawing, "the pen is up")
        for i in 0..<10 { step(lens, [pointing(at: CGPoint(x: 700 + Double(i) * 6, y: 520))]) }
        XCTAssertEqual(lens.strokes.count, 2, "a new stroke starts, not a line across")
        let out = step(lens, [pointing(at: CGPoint(x: 770, y: 520))])
        // Nothing joins the end of the first stroke (about x = 380) to the start of the second (x = 700).
        XCTAssertLessThan(brightness(h.pixel(out, 540, 485)), plainBrightness(540, 485) + 100)
    }

    func testTheLineBreaksWhenTheHandIsLostAndAJumpStartsANewLine() {
        var canvas = AirPaintCanvas()
        for i in 0..<10 { canvas.update(hands: [pointing(at: CGPoint(x: 300 + Double(i) * 8, y: 400))], dt: 1.0 / 30) }
        XCTAssertTrue(canvas.isDrawing)
        canvas.update(hands: [], dt: 1.0 / 30)
        XCTAssertFalse(canvas.isDrawing, "the pen goes with the hand")
        XCTAssertEqual(canvas.strokes.count, 1, "but what was drawn stays")
        // The hand comes back (same id) somewhere else: a new line, not a join.
        canvas.update(hands: [pointing(at: CGPoint(x: 900, y: 600))], dt: 1.0 / 30)
        XCTAssertEqual(canvas.strokes.count, 2)

        var glitch = AirPaintCanvas()
        for i in 0..<5 { glitch.update(hands: [pointing(at: CGPoint(x: 300 + Double(i) * 8, y: 400))], dt: 1.0 / 30) }
        glitch.update(hands: [pointing(at: CGPoint(x: 1100, y: 100))], dt: 1.0 / 30)
        XCTAssertEqual(glitch.strokes.count, 2, "a leap across the picture in one look is a tracking glitch, not a stroke")
    }

    func testAStillFingerAddsNoPointsAndALongScribbleStaysWithinBudget() {
        var canvas = AirPaintCanvas()
        let still = pointing(at: CGPoint(x: 400, y: 400))
        for _ in 0..<60 { canvas.update(hands: [still], dt: 1.0 / 30) }
        XCTAssertEqual(canvas.totalPoints, 1, "the same place again and again is one point")
        var scribble = AirPaintCanvas()
        for i in 0..<2500 {
            let t = Double(i) * 0.15
            scribble.update(hands: [pointing(at: CGPoint(x: 640 + 380 * sin(t * 1.3), y: 400 + 250 * sin(t * 1.9)))], dt: 1.0 / 30)
            XCTAssertLessThanOrEqual(scribble.totalPoints, AirPaintCanvas.maxPoints)
        }
        XCTAssertGreaterThan(scribble.totalPoints, 120, "seven seconds of drawing is still there")
        XCTAssertLessThan(scribble.totalPoints, 300, "and what is older has faded out and been dropped")
        let lens = AirPaintLens()
        for i in 0..<30 { step(lens, [pointing(at: CGPoint(x: 400 + Double(i) * 8, y: 300 + 80 * sin(Double(i) * 0.4)))]) }
        XCTAssertGreaterThan(lens.pointCount, 20)
    }

    func testStrokesHoldThenFadeSlowlyAndAnOpenPalmWipesThemQuickly() {
        // How strong a point is as it ages: full for a few seconds, then slowly out.
        var canvas = AirPaintCanvas()
        for i in 0..<12 { canvas.update(hands: [pointing(at: CGPoint(x: 200 + Double(i) * 8, y: 450))], dt: 1.0 / 30) }
        canvas.update(hands: [], dt: 1.0 / 30)
        let first = canvas.strokes[0].points[0], stroke = canvas.strokes[0]
        XCTAssertEqual(canvas.strength(of: first, in: stroke), 1, accuracy: 0.001)
        var levels: [Double] = []
        for _ in 0..<7 {
            for _ in 0..<30 { canvas.update(hands: [], dt: 1.0 / 30) }
            levels.append(canvas.strokes.first.map { canvas.strength(of: first, in: $0) } ?? 0)
        }
        XCTAssertEqual(levels[1], 1, accuracy: 0.001, "still at full strength two seconds on")
        XCTAssertLessThan(levels[3], 0.9, "fading by four seconds")
        XCTAssertGreaterThan(levels[3], 0.5, "but slowly")
        XCTAssertGreaterThan(levels[4], 0.1)
        XCTAssertLessThan(levels[4], levels[3])
        XCTAssertEqual(levels[6], 0, accuracy: 0.001, "gone in seven seconds")
        XCTAssertTrue(canvas.strokes.isEmpty)

        // The same through the picture.
        let lens = AirPaintLens()
        for i in 0..<40 { step(lens, [pointing(at: CGPoint(x: 200 + Double(i) * 5, y: 450))]) }
        step(lens, [])
        func glow(_ out: CIImage) -> Int { brightness(h.pixel(out, 280, 450)) - plainBrightness(280, 450) }
        var out = step(lens, [])
        XCTAssertGreaterThan(glow(out), 300)
        for _ in 0..<60 { out = step(lens, []) }
        XCTAssertGreaterThan(glow(out), 300, "two seconds later it is still glowing")
        for _ in 0..<300 { out = step(lens, []) }
        XCTAssertTrue(lens.strokes.isEmpty)
        XCTAssertEqual(h.bitmap(out).change(from: h.bitmap(base.composed), in: base.rect), 0, "and eventually the picture is clean")

        // Wipe: draw again, then hold a palm open.
        for i in 0..<40 { step(lens, [pointing(at: CGPoint(x: 200 + Double(i) * 5, y: 450))]) }
        XCTAssertFalse(lens.strokes.isEmpty)
        let palm = openPalm(at: CGPoint(x: 700, y: 200))
        var wiping = base.composed
        var frames = 0
        for i in 0..<30 {
            wiping = step(lens, [palm])
            frames += 1
            if i == 6 { Output.save(wiping, as: "airpaint-wipe.png") }
            if lens.strokes.isEmpty { break }
        }
        XCTAssertTrue(lens.strokes.isEmpty, "a palm held open for about half a second clears the page")
        XCTAssertLessThan(frames, 24)
    }

    func testAWipeThatStartedFinishesEvenIfThePalmCloses() {
        var canvas = AirPaintCanvas()
        for i in 0..<20 { canvas.update(hands: [pointing(at: CGPoint(x: 300 + Double(i) * 8, y: 400))], dt: 1.0 / 30) }
        let palm = openPalm()
        for _ in 0..<6 { canvas.update(hands: [palm], dt: 1.0 / 30) }
        XCTAssertTrue(canvas.isWiping)
        XCTAssertFalse(canvas.ripples.isEmpty, "a ring spreads from the palm")
        for _ in 0..<20 { canvas.update(hands: [HandFixtures.hand(.fist)], dt: 1.0 / 30) }
        XCTAssertTrue(canvas.strokes.isEmpty)
        // Opening a palm with nothing drawn makes no fuss.
        var empty = AirPaintCanvas()
        for _ in 0..<12 { empty.update(hands: [palm], dt: 1.0 / 30) }
        XCTAssertTrue(empty.ripples.isEmpty)
    }

    func testEachStrokeHasItsOwnNeonColourAndTwoHandsDrawAtOnce() {
        var canvas = AirPaintCanvas()
        for i in 0..<10 { canvas.update(hands: [pointing(at: CGPoint(x: 200 + Double(i) * 8, y: 300))], dt: 1.0 / 30) }
        for _ in 0..<6 { canvas.update(hands: [HandFixtures.hand(.fist)], dt: 1.0 / 30) }
        for i in 0..<10 { canvas.update(hands: [pointing(at: CGPoint(x: 200 + Double(i) * 8, y: 500))], dt: 1.0 / 30) }
        XCTAssertEqual(canvas.strokes.count, 2)
        XCTAssertNotEqual(canvas.strokes[0].points[0].hue, canvas.strokes[1].points[0].hue)

        var two = AirPaintCanvas()
        for i in 0..<10 {
            two.update(hands: [pointing(at: CGPoint(x: 200 + Double(i) * 8, y: 300), id: 1), pointing(at: CGPoint(x: 800 - Double(i) * 8, y: 500), id: 2)], dt: 1.0 / 30)
        }
        XCTAssertEqual(two.strokes.count, 2)
        XCTAssertEqual(Set(two.strokes.map(\.hand)), [1, 2])
    }

    func testAirPaintPicturesWithHandsDrawnIn() {
        let lens = AirPaintLens()
        var out = base.composed
        for i in 0..<110 {
            let t = Double(i) / 110
            // A heart-ish loop, then a zig-zag.
            let tip = i < 70
                ? CGPoint(x: 400 + 190 * sin(t * 9), y: 420 + 150 * sin(t * 7 + 1))
                : CGPoint(x: 700 + Double(i - 70) * 12, y: 430 + (i % 8 < 4 ? 70 : -70))
            let hand = pointing(at: tip, size: 110)
            out = lens.render(handPicture([hand], time: Double(i) / 30))
        }
        Output.save(out, as: "airpaint-scribble.png")
        XCTAssertGreaterThan(lens.strokes.count, 0)
    }

    // MARK: Energy Ball

    func testAnOpenPalmChargesAnOrbThatGrowsWhileHeld() {
        let lens = EnergyBallLens()
        let palm = openPalm()
        run(lens, [palm], frames: 36)
        XCTAssertEqual(lens.charge, 0.5, accuracy: 0.12, "about half charged after a second and a bit")
        let half = lens.charge
        let out = step(lens, [palm])
        Output.save(out, as: "energy-half.png")
        let centre = EnergyBallRig.center(of: palm, radius: EnergyBallRig.radius(charge: half, handSize: palm.size))
        XCTAssertGreaterThan(brightness(h.pixel(out, Int(centre.x), Int(centre.y))), 600, "the orb glows white-hot in the middle")
        run(lens, [palm], frames: 70)
        XCTAssertGreaterThan(lens.charge, 0.98, "full in about two seconds")
        let full = step(lens, [palm])
        Output.save(full, as: "energy-full.png")
        XCTAssertEqual(lens.status?.title, "Fully charged!")
        XCTAssertGreaterThan(EnergyBallRig.radius(charge: 1, handSize: 120), EnergyBallRig.radius(charge: 0.5, handSize: 120) * 1.4)
        XCTAssertGreaterThan(EnergyBallRig.radius(charge: 0.5, handSize: 120), EnergyBallRig.radius(charge: 0.1, handSize: 120))
    }

    func testAFistOrAPointedFingerChargesNothing() {
        for hand in [HandFixtures.hand(.fist, at: CGPoint(x: 640, y: 260), size: 120), HandFixtures.hand(.point, at: CGPoint(x: 640, y: 260), size: 120)] {
            let lens = EnergyBallLens()
            let out = { () -> CIImage in self.run(lens, [hand], frames: 60); return self.step(lens, [hand]) }()
            XCTAssertEqual(lens.charge, 0, accuracy: 0.001)
            XCTAssertEqual(h.bitmap(out).change(from: h.bitmap(base.composed), in: base.rect), 0)
        }
    }

    func testAFastFlickThrowsTheOrbTheWayTheHandWentAndANewOneCharges() {
        let lens = EnergyBallLens()
        let palm = openPalm(at: CGPoint(x: 400, y: 260))
        run(lens, [palm], frames: 50)
        let before = lens.charge
        XCTAssertGreaterThan(before, 0.6)
        XCTAssertTrue(lens.shots.isEmpty)

        let flick = moved(palm, to: CGPoint(x: 430, y: 270), velocity: CGVector(dx: 2400, dy: 300))
        step(lens, [flick])
        XCTAssertEqual(lens.thrownCount, 1)
        XCTAssertEqual(lens.shots.count, 1)
        XCTAssertEqual(lens.charge, 0, accuracy: 0.001, "the orb is gone from the hand")
        let shot = lens.shots[0]
        XCTAssertGreaterThan(shot.velocity.dx, 1500)
        XCTAssertEqual(shot.velocity.dy / shot.velocity.dx, 300.0 / 2400.0, accuracy: 0.02, "in the direction of the flick")
        XCTAssertGreaterThan(shot.radius, 20)

        let hand = HandFixtures.moved(flick, by: .zero, velocity: .zero)
        var out = base.composed
        for i in 0..<4 { out = step(lens, [hand]); if i == 2 { Output.save(out, as: "energy-thrown.png") } }
        XCTAssertGreaterThan(lens.shots[0].position.x, shot.position.x + 250, "it flies")
        let ahead = lens.shots[0].position
        XCTAssertGreaterThan(brightness(h.pixel(out, Int(ahead.x), Int(ahead.y))), 600, "a bright head")
        let behind = lens.shots[0].trail[lens.shots[0].trail.count - 3]
        XCTAssertGreaterThan(brightness(h.pixel(out, Int(behind.x), Int(behind.y))), min(700, plainBrightness(Int(behind.x), Int(behind.y)) + 50), "and a glowing trail behind it")

        // It leaves the picture and is removed; meanwhile the open palm does not charge straight away.
        var frames = 0
        while !lens.shots.isEmpty, frames < 80 { step(lens, [hand]); frames += 1 }
        XCTAssertTrue(lens.shots.isEmpty, "it has left the frame")
        XCTAssertLessThan(frames, 50)
        run(lens, [hand], frames: 60)
        XCTAssertGreaterThan(lens.charge, 0.2, "a new one is charging")
        XCTAssertEqual(lens.thrownCount, 1, "and the still hand throws nothing")
    }

    func testFlicksInOtherDirectionsAndTooSlowOrTooEarlyFlicksThrowNothing() {
        // Up and to the left.
        let lens = EnergyBallLens()
        let palm = openPalm()
        run(lens, [palm], frames: 45)
        step(lens, [moved(palm, to: CGPoint(x: 600, y: 300), velocity: CGVector(dx: -1500, dy: 1500))])
        XCTAssertEqual(lens.shots.count, 1)
        XCTAssertLessThan(lens.shots[0].velocity.dx, -800)
        XCTAssertGreaterThan(lens.shots[0].velocity.dy, 800)
        var frames = 0
        while !lens.shots.isEmpty, frames < 90 { step(lens, [palm]); frames += 1 }
        XCTAssertTrue(lens.shots.isEmpty, "flying up and left it leaves too")

        // Waving about at ordinary speed does not throw.
        let calm = EnergyBallLens()
        run(calm, [palm], frames: 45)
        for i in 0..<30 { step(calm, [moved(palm, to: CGPoint(x: 640 + 80 * sin(Double(i) / 5), y: 260), velocity: CGVector(dx: 500 * cos(Double(i) / 5), dy: 0))]) }
        XCTAssertEqual(calm.thrownCount, 0)
        XCTAssertGreaterThan(calm.charge, 0.9)

        // A flick before there is any charge has nothing to throw.
        let early = EnergyBallLens()
        run(early, [palm], frames: 4)
        step(early, [moved(palm, to: CGPoint(x: 700, y: 260), velocity: CGVector(dx: 3000, dy: 0))])
        XCTAssertEqual(early.thrownCount, 0)

        // A hand held up to 6 palms long moves far faster in pixels: the flick speed scales with the hand.
        let near = EnergyBallLens()
        let big = openPalm(at: CGPoint(x: 640, y: 150), size: 260)
        run(near, [big], frames: 50)
        step(near, [moved(big, to: CGPoint(x: 640, y: 150), velocity: CGVector(dx: 1200, dy: 0))])
        XCTAssertEqual(near.thrownCount, 0, "1200 px/s is a gentle wave for a hand this close")
        step(near, [moved(big, to: CGPoint(x: 640, y: 150), velocity: CGVector(dx: 3200, dy: 0))])
        XCTAssertEqual(near.thrownCount, 1)
    }

    func testAFlickThrowsEvenIfTheTrackerCallsTheHandSomethingElseForAFewFrames() {
        let lens = EnergyBallLens()
        let palm = openPalm()
        run(lens, [palm], frames: 45)
        // The blurred hand in the middle of a flick looks like a fist.
        let blur = moved(HandFixtures.hand(.fist, size: 120), to: palm.wrist)
        for _ in 0..<5 { step(lens, [blur]) }
        XCTAssertGreaterThan(lens.charge, 0.5, "the charge survives a few frames of bad pose")
        step(lens, [HandFixtures.moved(blur, by: .zero, velocity: CGVector(dx: 2400, dy: 0))])
        XCTAssertEqual(lens.thrownCount, 1)
    }

    func testALostHandShrinksTheOrbAwayInsteadOfPopping() {
        let lens = EnergyBallLens()
        let palm = openPalm()
        run(lens, [palm], frames: 60)
        let charge = lens.charge
        let centre = EnergyBallRig.center(of: palm, radius: EnergyBallRig.radius(charge: charge, handSize: palm.size))
        var out = step(lens, [])
        XCTAssertGreaterThan(lens.presence, 0.5)
        XCTAssertGreaterThan(brightness(h.pixel(out, Int(centre.x), Int(centre.y))), 500, "one lost frame does not make it vanish")
        var last = lens.presence
        for _ in 0..<8 {
            out = step(lens, [])
            XCTAssertLessThanOrEqual(lens.presence, last, "it only fades")
            last = lens.presence
        }
        XCTAssertEqual(lens.thrownCount, 0, "a vanished hand throws nothing")
        run(lens, [], frames: 10)
        XCTAssertEqual(lens.presence, 0)
        XCTAssertEqual(h.bitmap(step(lens, [])).change(from: h.bitmap(base.composed), in: base.rect), 0)
    }

    func testTwoHandsEachChargeTheirOwnOrb() {
        let lens = EnergyBallLens()
        let a = openPalm(at: CGPoint(x: 330, y: 250), id: 1), b = HandFixtures.hand(.open, at: CGPoint(x: 950, y: 250), size: 110, mirrored: true, id: 2)
        run(lens, [a, b], frames: 40)
        let out = step(lens, [a, b])
        Output.save(out, as: "energy-two.png")
        let ca = EnergyBallRig.center(of: a, radius: 60), cb = EnergyBallRig.center(of: b, radius: 55)
        XCTAssertGreaterThan(brightness(h.pixel(out, Int(ca.x), Int(ca.y))), 500)
        XCTAssertGreaterThan(brightness(h.pixel(out, Int(cb.x), Int(cb.y))), 500)
    }

    // MARK: Finger Lightning

    func testArcsJumpBetweenTheFingersOfASpreadHandAndNotAFist() {
        let open = openPalm()
        let arcs = FingerLightningArcs.arcs(within: open, salt: 1)
        XCTAssertEqual(arcs.count, 4, "thumb to index to middle to ring to little")
        let tips = Finger.allCases.map { open[$0.tip] }
        for arc in arcs {
            XCTAssertTrue(tips.contains(arc.from) && tips.contains(arc.to), "arcs run from fingertip to fingertip")
        }
        XCTAssertEqual(FingerLightningArcs.arcs(within: HandFixtures.hand(.peace), salt: 1).count, 1, "one arc between two fingers")
        XCTAssertTrue(FingerLightningArcs.arcs(within: HandFixtures.hand(.fist), salt: 1).isEmpty)
        XCTAssertTrue(FingerLightningArcs.arcs(within: HandFixtures.hand(.point), salt: 1).isEmpty, "one finger has nothing to jump to")
        XCTAssertGreaterThan(FingerLightningArcs.arcs(within: open, salt: 3).count, 4, "now and then one skips a finger")
    }

    func testBoltsKeepTheirShapeForAFewFramesThenAreThrownAgain() {
        let arc = FingerLightningArcs.Arc(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 250), weight: 1, key: 7)
        let a = FingerLightningArcs.points(of: arc, beat: 4), b = FingerLightningArcs.points(of: arc, beat: 4), c = FingerLightningArcs.points(of: arc, beat: 5)
        XCTAssertEqual(a, b, "the same beat is the same bolt")
        XCTAssertNotEqual(a, c, "the next beat is a new one")
        XCTAssertEqual(a.first, arc.from)
        XCTAssertEqual(a.last, arc.to)
        XCTAssertGreaterThan(a.count, 8)
        let length = HandFXKit.distance(arc.from, arc.to)
        for p in a {
            // It never wanders further from the straight line than its jitter allows.
            let cross = abs((arc.to.x - arc.from.x) * (arc.from.y - p.y) - (arc.from.x - p.x) * (arc.to.y - arc.from.y)) / length
            XCTAssertLessThan(cross, 60)
        }
        XCTAssertEqual(FingerLightningArcs.framesPerBeat, 3)

        // Through the lens the arcs hold for three frames and change on the fourth.
        let lens = FingerLightningLens()
        let palm = openPalm()
        step(lens, [palm])               // frame 1: beat 0
        let first = lens.arcs
        step(lens, [palm]); step(lens, [palm])   // frames 2 and 3: still beat 0 and 1: shapes follow the beat
        XCTAssertEqual(first.map(\.key).filter { $0 % 100 < 50 }, lens.arcs.map(\.key).filter { $0 % 100 < 50 }, "the same fingertips stay joined")
    }

    func testLightningLightsUpBetweenTheFingertips() {
        let lens = FingerLightningLens()
        let palm = openPalm(at: CGPoint(x: 250, y: 200), size: 130)
        var out = base.composed
        for _ in 0..<8 { out = step(lens, [palm]) }
        Output.save(out, as: "lightning-one-hand.png")
        let tips = Finger.allCases.map { palm[$0.tip] }
        let between = CGRect(x: (tips[1].x + tips[2].x) / 2 - 16, y: (tips[1].y + tips[2].y) / 2 - 16, width: 32, height: 32)
        let lit = h.average(out, between), plain = h.average(base.composed, between)
        XCTAssertGreaterThan(lit.r + lit.g + lit.b, plain.r + plain.g + plain.b + 0.1, "an arc crackles between the index and middle fingertips")
        XCTAssertGreaterThan(lit.b - plain.b, lit.r - plain.r, "and it is blue-white")
        for tip in tips {
            XCTAssertGreaterThan(brightness(h.pixel(out, Int(tip.x), Int(tip.y))), plainBrightness(Int(tip.x), Int(tip.y)) + 350, "a bright spot at the tip \(tip)")
        }
        XCTAssertEqual(lens.status?.title, "Zap!")
        // A fist makes none.
        let quiet = FingerLightningLens()
        run(quiet, [HandFixtures.hand(.fist, at: CGPoint(x: 640, y: 200), size: 130)], frames: 6)
        XCTAssertTrue(quiet.arcs.isEmpty)
    }

    func testBoltsLeapFromOneHandToTheOtherAndFadeWhenOneIsLost() {
        let a = openPalm(at: CGPoint(x: 280, y: 220), size: 120)
        let b = HandFixtures.hand(.open, at: CGPoint(x: 1000, y: 220), size: 120, mirrored: true, id: 2)
        let between = FingerLightningArcs.arcs(between: a, and: b)
        XCTAssertGreaterThanOrEqual(between.count, 5, "a bolt for each fingertip and one between the palms")
        XCTAssertEqual(between.map(\.weight).max(), 1.6, "the palm-to-palm one is the thickest")
        XCTAssertTrue(between.contains { $0.from == a.palm && $0.to == b.palm })

        let lens = FingerLightningLens()
        var out = base.composed
        for _ in 0..<8 { out = step(lens, [a, b]) }
        Output.save(out, as: "lightning-two-hands.png")
        XCTAssertGreaterThan(lens.arcs.count, 8)
        XCTAssertEqual(lens.status?.title, "Zap!")
        // Somewhere along the gap between the palms there is light.
        var best = 0
        let lit = h.bitmap(out), plain = h.bitmap(base.composed)
        for x in stride(from: 420, to: 880, by: 4) {
            for y in 240...480 {
                let a = lit.pixel(x, y), b = plain.pixel(x, y)
                best = max(best, a.r + a.g + a.b - (b.r + b.g + b.b))
            }
        }
        XCTAssertGreaterThan(best, 400, "the bolt crosses the gap")

        // One hand goes: the bolts to it go with it, over a few frames.
        for _ in 0..<2 { out = step(lens, [a]) }
        XCTAssertGreaterThan(lens.presence, 0.3)
        for _ in 0..<12 { step(lens, [a]) }
        XCTAssertTrue(lens.arcs.allSatisfy { !FingerLightningArcs.isBetweenHands($0.key) }, "only the arcs within the remaining hand are left")
    }

    // MARK: Sparkle Trail

    func testSparklesFlowThickerTheFasterYouMove() {
        func emitted(speed: Double) -> Int {
            var stream = SparkleTrailStream()
            var hand = openPalm()
            for i in 0..<45 {
                hand = HandFixtures.moved(openPalm(), by: CGVector(dx: speed * Double(i) / 30 - 200, dy: 0))
                stream.update(hands: [hand], dt: 1.0 / 30)
            }
            return stream.emitted
        }
        let still = emitted(speed: 0), slow = emitted(speed: 250), fast = emitted(speed: 1100)
        XCTAssertGreaterThan(still, 20, "a still hand still glitters a little")
        XCTAssertGreaterThan(slow, still * 2)
        XCTAssertGreaterThan(fast, slow * 2, "a fast sweep is a thick stream")
        XCTAssertLessThanOrEqual(SparkleTrailStream.rate(atSpeed: 5000), 100, "but never an unbounded flood")
        XCTAssertGreaterThan(SparkleTrailStream.spread(atSpeed: 1200), SparkleTrailStream.spread(atSpeed: 0) * 3, "and the stream widens")
        XCTAssertGreaterThan(SparkleTrailStream.rate(atSpeed: 600), SparkleTrailStream.rate(atSpeed: 100))
    }

    func testSparklesStreamFromEveryFingertipOfEveryHandAndFollowThePath() {
        var stream = SparkleTrailStream()
        for i in 0..<20 {
            let a = HandFixtures.moved(openPalm(at: CGPoint(x: 300, y: 250), id: 1), by: CGVector(dx: Double(i) * 30, dy: 0))
            let b = HandFixtures.moved(HandFixtures.hand(.open, at: CGPoint(x: 1000, y: 250), size: 110, mirrored: true, id: 2), by: CGVector(dx: -Double(i) * 30, dy: 0))
            stream.update(hands: [a, b], dt: 1.0 / 30)
        }
        let points = stream.particles.particles.map { CGPoint(x: $0.position.x, y: $0.position.y) }
        XCTAssertGreaterThan(points.count, 150)
        // Sparkles lie between where the tips started and where they got to, left hand and right hand alike.
        XCTAssertTrue(points.contains { $0.x < 500 && $0.y > 350 }, "from the left hand")
        XCTAssertTrue(points.contains { $0.x > 800 && $0.y > 350 }, "from the right hand")
        XCTAssertLessThanOrEqual(stream.particles.particles.count, 420)
    }

    func testSparklesDriftFadeAndOutliveTheHandButAJumpLeavesNoStreak() {
        var stream = SparkleTrailStream()
        for i in 0..<12 { stream.update(hands: [HandFixtures.moved(openPalm(), by: CGVector(dx: Double(i) * 40, dy: 0))], dt: 1.0 / 30) }
        let living = stream.particles.particles.count
        XCTAssertGreaterThan(living, 30)
        for _ in 0..<12 { stream.update(hands: [], dt: 1.0 / 30) }
        XCTAssertGreaterThan(stream.particles.particles.count, 10, "they linger after the hand has gone")
        for _ in 0..<60 { stream.update(hands: [], dt: 1.0 / 30) }
        XCTAssertEqual(stream.particles.particles.count, 0, "and fade away")

        var jump = SparkleTrailStream()
        jump.update(hands: [openPalm(at: CGPoint(x: 200, y: 250))], dt: 1.0 / 30)
        let count = jump.emitted
        jump.update(hands: [openPalm(at: CGPoint(x: 1100, y: 250))], dt: 1.0 / 30)
        XCTAssertEqual(jump.emitted, count, "a tracking glitch makes no streak across the picture")
    }

    func testSparkleTrailDrawsGlitterAlongTheSweep() {
        let lens = SparkleTrailLens()
        var out = base.composed
        for i in 0..<50 {
            let t = Double(i) / 30
            let hand = HandFixtures.moved(openPalm(at: CGPoint(x: 300, y: 220), size: 100), by: CGVector(dx: 80 + 560 * t / 1.6, dy: 120 * sin(t * 4)))
            out = lens.render(handPicture([hand], time: t))
        }
        Output.save(out, as: "sparkle-sweep.png")
        XCTAssertGreaterThan(lens.particleCount, 100)
        XCTAssertGreaterThan(lens.fastestFingertip, 300)
        XCTAssertEqual(lens.status?.title, "Sparkle!")
        // Glitter fades out after the hand is gone.
        for _ in 0..<80 { out = step(lens, []) }
        XCTAssertEqual(lens.particleCount, 0)
    }

    // MARK: Laser Pointer

    func testAPointedFingerShootsABeamAlongItToTheEdgeOfThePicture() {
        let lens = LaserPointerLens()
        let hand = HandFixtures.gun(from: CGPoint(x: 400, y: 300), toward: CGPoint(x: 800, y: 300), thumb: 0)
        XCTAssertEqual(hand.pose, .point)
        var out = base.composed
        for _ in 0..<8 { out = step(lens, [hand]) }
        Output.save(out, as: "laser-right.png")
        XCTAssertEqual(lens.beams.count, 1)
        let beam = lens.beams[0]
        let edge = HandGeometry.exit(from: SIMD2(Double(hand.indexTip.x), Double(hand.indexTip.y)), direction: SIMD2(Double(hand.aim.dx), Double(hand.aim.dy)),
                                     rect: CGRect(origin: .zero, size: size))
        XCTAssertEqual(beam.to.x, 1280, accuracy: 1, "the beam runs to the right-hand edge")
        XCTAssertEqual(beam.to.y, edge.y, accuracy: 8, "along the finger")
        XCTAssertEqual(beam.from.x, hand.indexTip.x, accuracy: 12, "from the fingertip")
        // White-hot along the middle of the beam, red glow either side, and plain picture away from it.
        let normal = (x: -beam.direction.y, y: beam.direction.x)
        for f in [0.25, 0.5, 0.75, 0.95] {
            let cx = Double(beam.from.x) + Double(beam.to.x - beam.from.x) * f, cy = Double(beam.from.y) + Double(beam.to.y - beam.from.y) * f
            // The white-hot core is a few pixels wide, so look at the brightest of the pixels across it.
            let across = (-3...3).map { h.pixel(out, Int(cx + normal.x * Double($0)), Int(cy + normal.y * Double($0))) }
            XCTAssertGreaterThan(across.map(\.r).max() ?? 0, 230, "hot along the beam at \(f)")
            let side = h.pixel(out, Int(cx + normal.x * 6), Int(cy + normal.y * 6)), sidePlain = h.pixel(base.composed, Int(cx + normal.x * 6), Int(cy + normal.y * 6))
            XCTAssertGreaterThan(side.r - sidePlain.r, side.g - sidePlain.g + 25, "a red glow beside it at \(f)")
        }
        XCTAssertLessThan(brightness(h.pixel(out, 900, 420)), plainBrightness(900, 420) + 40, "nothing off the beam")
        XCTAssertGreaterThan(brightness(h.pixel(out, 1276, Int(beam.to.y))), 500, "a hot dot where it lands")
        XCTAssertEqual(lens.status?.title, "Laser on")
        XCTAssertTrue(lens.dots.isEmpty)
    }

    func testTheBeamFollowsWhereYouPointAndSparksFlyBackFromTheEdge() {
        for (target, edge) in [(CGPoint(x: 700, y: 560), "top"), (CGPoint(x: 100, y: 250), "left"), (CGPoint(x: 600, y: 20), "bottom")] {
            let lens = LaserPointerLens()
            let hand = HandFixtures.gun(from: CGPoint(x: 500, y: 300), toward: target, thumb: 0)
            run(lens, [hand], frames: 14)
            guard let beam = lens.beams.first else { return XCTFail("no beam to the \(edge)") }
            let aim = hand.aim
            let expected = HandGeometry.exit(from: SIMD2(Double(hand.indexTip.x), Double(hand.indexTip.y)), direction: SIMD2(Double(aim.dx), Double(aim.dy)),
                                             rect: CGRect(origin: .zero, size: size))
            XCTAssertEqual(beam.to.x, expected.x, accuracy: 8, edge)
            XCTAssertEqual(beam.to.y, expected.y, accuracy: 8, edge)
            XCTAssertGreaterThan(lens.sparkCount, 12, "sparks at the \(edge) edge")
        }
        // At the right edge, sparks fly back to the left.
        let lens = LaserPointerLens()
        run(lens, [HandFixtures.gun(from: CGPoint(x: 400, y: 300), toward: CGPoint(x: 800, y: 300), thumb: 0)], frames: 12)
        let hit = lens.beams[0].to
        XCTAssertGreaterThan(lens.sparkCount, 15)
        _ = hit
        let rig = LaserPointerRig.bounce(of: SIMD2(1, 0), at: CGPoint(x: 1280, y: 300), in: CGRect(origin: .zero, size: size))
        XCTAssertEqual(rig.x, -1, accuracy: 1e-9)
        let corner = LaserPointerRig.bounce(of: SIMD2(0.7071, 0.7071), at: CGPoint(x: 1280, y: 720), in: CGRect(origin: .zero, size: size))
        XCTAssertLessThan(corner.x, 0)
        XCTAssertLessThan(corner.y, 0)
    }

    func testAFingerPointingAtTheCameraGetsJustAGlowingDot() {
        // A finger the tracker still sees as out, but short in the picture because it points toward the lens.
        var hand = HandFixtures.hand(.point, at: CGPoint(x: 640, y: 250), size: 110)
        let knuckle = hand[.indexMCP]
        let tip = CGPoint(x: knuckle.x + 5, y: knuckle.y + 53)
        hand.joints[HandJoint.indexPIP.rawValue] = HandFXKit.lerp(knuckle, tip, 0.4)
        hand.joints[HandJoint.indexDIP.rawValue] = HandFXKit.lerp(knuckle, tip, 0.75)
        hand.joints[HandJoint.indexTip.rawValue] = tip
        XCTAssertEqual(hand.pose, .point)
        XCTAssertLessThan(hand.aimLength, LaserPointerRig.towardCameraBelow)

        let lens = LaserPointerLens()
        var out = base.composed
        for _ in 0..<10 { out = step(lens, [hand]) }
        Output.save(out, as: "laser-camera.png")
        XCTAssertTrue(lens.beams.isEmpty, "no beam when there is no direction to shoot in")
        XCTAssertEqual(lens.dots.count, 1)
        XCTAssertGreaterThan(brightness(h.pixel(out, Int(hand.indexTip.x), Int(hand.indexTip.y))), 600, "a glowing dot on the fingertip")
        XCTAssertLessThan(brightness(h.pixel(out, Int(hand.indexTip.x) + 300, Int(hand.indexTip.y))), plainBrightness(Int(hand.indexTip.x) + 300, Int(hand.indexTip.y)) + 30)
        XCTAssertEqual(lens.status?.title, "Pointing at the camera")
        XCTAssertEqual(LaserPointerRig.beamShare(of: HandFixtures.hand(.point)), 1, accuracy: 0.001, "an ordinary pointing finger is all beam")
    }

    func testTheBeamEasesInAndOutAndFollowsTheFingerSmoothly() {
        let lens = LaserPointerLens()
        let hand = HandFixtures.gun(from: CGPoint(x: 400, y: 300), toward: CGPoint(x: 800, y: 300), thumb: 0)
        step(lens, [hand])
        let first = lens.beams.first?.strength ?? 0
        XCTAssertLessThan(first, 0.6, "it fades in rather than switching on")
        run(lens, [hand], frames: 6)
        XCTAssertGreaterThan(lens.beams.first?.strength ?? 0, 0.95)

        // Shaky tracking: the finger's angle jitters by plus and minus 4 degrees every frame. The beam shakes far less.
        var angles: [Double] = []
        for i in 0..<40 {
            let wobble = (i % 2 == 0 ? 4.0 : -4.0) * .pi / 180
            step(lens, [HandFixtures.hand(.point, at: CGPoint(x: 300, y: 300), size: 100, angle: -.pi / 2 + wobble)])
            if i >= 10, let beam = lens.beams.first { angles.append(atan2(beam.direction.y, beam.direction.x)) }
        }
        XCTAssertGreaterThan(angles.count, 20)
        XCTAssertLessThan((angles.max() ?? 0) - (angles.min() ?? 0), 4.0 * .pi / 180, "the beam moves less than half as much as the raw 8 degrees of wobble")

        // Lost hand: the beam fades out over a few frames and is gone.
        step(lens, [])
        XCTAssertFalse(lens.beams.isEmpty, "one lost frame does not switch it off")
        run(lens, [], frames: 25)
        XCTAssertTrue(lens.beams.isEmpty)
        XCTAssertEqual(h.bitmap(step(lens, [])).change(from: h.bitmap(base.composed), in: base.rect), 0)
    }

    func testOnlyAPointedFingerShootsAndTwoHandsShootTwoBeams() {
        let lens = LaserPointerLens()
        run(lens, [openPalm(), HandFixtures.hand(.fist, at: CGPoint(x: 300, y: 200), id: 2)], frames: 12)
        XCTAssertTrue(lens.beams.isEmpty, "an open palm or a fist is not a pointer")
        XCTAssertEqual(lens.status?.title, "Point your finger")

        let a = HandFixtures.gun(from: CGPoint(x: 300, y: 300), toward: CGPoint(x: 100, y: 500), thumb: 0, id: 1)
        let b = HandFixtures.gun(from: CGPoint(x: 900, y: 300), toward: CGPoint(x: 1100, y: 450), thumb: 1, id: 2)
        var out = base.composed
        for _ in 0..<12 { out = step(lens, [a, b]) }
        Output.save(out, as: "laser-two.png")
        XCTAssertEqual(lens.beams.count, 2)
        XCTAssertEqual(Set(lens.beams.map(\.hand)), [1, 2])
    }

    func testLaserPicturesWithHandsDrawnIn() {
        let lens = LaserPointerLens()
        var out = base.composed
        let hand = HandFixtures.gun(from: CGPoint(x: 560, y: 330), toward: CGPoint(x: 900, y: 520), size: 110, thumb: 0)
        for i in 0..<12 { out = lens.render(handPicture([hand], time: Double(i) / 30)) }
        Output.save(out, as: "laser-hand.png")
        XCTAssertEqual(lens.beams.count, 1)
    }

    func testLightningAndEnergyPicturesWithHandsDrawnIn() {
        let lens = FingerLightningLens()
        var out = base.composed
        let a = openPalm(at: CGPoint(x: 330, y: 190), size: 120), b = HandFixtures.hand(.open, at: CGPoint(x: 960, y: 210), size: 125, angle: 0.15, mirrored: true, id: 2)
        for i in 0..<10 { out = lens.render(handPicture([a, b], time: Double(i) / 30)) }
        Output.save(out, as: "lightning-hands.png")
        let ball = EnergyBallLens()
        let palm = openPalm(at: CGPoint(x: 640, y: 190), size: 130)
        for i in 0..<70 { out = ball.render(handPicture([palm], time: Double(i) / 30)) }
        Output.save(out, as: "energy-hand.png")
        XCTAssertGreaterThan(ball.charge, 0.9)
    }

    // MARK: Pictures

    /// A frame with cartoon hands painted into the picture, so the saved pictures show where the effect sits on a hand.
    private func handPicture(_ hands: [HandState], time: Double) -> LensInput {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let skin = CGColor(red: 0.93, green: 0.74, blue: 0.62, alpha: 1)
        ctx.setFillColor(skin)
        ctx.setStrokeColor(skin)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for hand in hands {
            ctx.setLineWidth(hand.size * 0.26)
            let palm = CGMutablePath()
            palm.move(to: hand.wrist)
            for joint in [HandJoint.thumbCMC, .indexMCP, .middleMCP, .ringMCP, .littleMCP] { palm.addLine(to: hand[joint]) }
            palm.closeSubpath()
            ctx.addPath(palm)
            ctx.drawPath(using: .fillStroke)
            for finger in Finger.allCases {
                ctx.setLineWidth(hand.size * (finger == .thumb ? 0.27 : 0.21))
                ctx.beginPath()
                ctx.move(to: hand[finger.knuckle])
                ctx.addLine(to: hand[finger.middleJoint])
                let tip = hand[finger.tip]
                ctx.addLine(to: hand[HandJoint(rawValue: finger.middleJoint.rawValue + 1) ?? finger.tip])
                ctx.addLine(to: tip)
                ctx.strokePath()
            }
        }
        let picture = ctx.makeImage().map { CIImage(cgImage: $0).composited(over: base.composed) } ?? base.composed
        return LensInput(time: time, dt: 1.0 / 30, rect: base.rect, camera: picture, matte: base.matte, background: base.background, composed: picture,
                         matteGrid: base.matteGrid, face: nil, services: base.services, hands: hands)
    }
}
