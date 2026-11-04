import CoreImage
import XCTest

/// The Dragon Ball lens as a whole: the pieces joined, the ten moves told apart from each other, and the finished pictures.
final class SaiyanLensTests: XCTestCase {
    // MARK: Fixtures

    /// A hand of `fingers` with the middle of its palm at `p`.
    private func place(_ fingers: HandFixtures.Fingers, palm p: CGPoint, size: Double = 100, angle: Double = 0, mirrored: Bool = false, id: Int = 1) -> HandState {
        let probe = HandFixtures.hand(fingers, at: .zero, size: size, angle: angle, mirrored: mirrored, id: id)
        return HandFixtures.moved(probe, by: CGVector(dx: p.x - probe.palm.x, dy: p.y - probe.palm.y))
    }

    private var face: FaceState { SyntheticScene().face() }

    private func fists(size: Double = 100) -> [HandState] {
        [place(.fist, palm: CGPoint(x: 470, y: 330), size: size, mirrored: true, id: 1), place(.fist, palm: CGPoint(x: 810, y: 330), size: size, id: 2)]
    }

    /// Cupped hands at the person's right side (the picture's right), fingers pointing out.
    private func cupped(size: Double = 110) -> [HandState] {
        let c = CGPoint(x: 700, y: 190)
        return [place(.open, palm: CGPoint(x: c.x, y: c.y + 34), size: size, angle: -.pi / 2, id: 1),
                place(.open, palm: CGPoint(x: c.x, y: c.y - 34), size: size, angle: -.pi / 2, mirrored: true, id: 2)]
    }

    private func palmsUp(size: Double = 110) -> [HandState] {
        [place(.open, palm: CGPoint(x: 587, y: 200), size: size, mirrored: true, id: 1), place(.open, palm: CGPoint(x: 693, y: 200), size: size, id: 2)]
    }

    private func atForehead(size: Double = 110) -> HandState {
        let probe = HandFixtures.hand(.peace, at: .zero, size: size, angle: 0.15)
        let tips = CGPoint(x: (probe[.indexTip].x + probe[.middleTip].x) / 2, y: (probe[.indexTip].y + probe[.middleTip].y) / 2)
        return HandFixtures.moved(probe, by: CGVector(dx: face.forehead.x - tips.x, dy: face.forehead.y - tips.y))
    }

    private func overhead(count: Int) -> [HandState] {
        let ys = 625.0
        return count == 2 ? [place(.open, palm: CGPoint(x: 520, y: ys), size: 90, mirrored: true, id: 1), place(.open, palm: CGPoint(x: 760, y: ys), size: 90, id: 2)]
                          : [place(.open, palm: CGPoint(x: 790, y: ys), size: 90, id: 1)]
    }

    private func nearFace() -> [HandState] {
        [place(.open, palm: CGPoint(x: 568, y: 440), size: 100, mirrored: true, id: 1), place(.open, palm: CGPoint(x: 712, y: 440), size: 100, id: 2)]
    }

    private func still(_ hands: [HandState]) -> (Int) -> [HandState] { { _ in hands } }

    /// What a pose does to the whole move set, over `seconds`: which moves were ever posed, charging, firing or still showing light.
    private func ran(_ frames: Int, form: SaiyanForm = .superSaiyan, face withFace: Bool = true, _ hands: (Int) -> [HandState]) -> Set<String> {
        let bench = SaiyanBench()
        let set = SaiyanMoveSet()
        var seen = Set<String>()
        var echoes = false
        var before: [Int: CGPoint] = [:]
        for i in 0..<frames {
            // The tracker gives every hand its speed; the fixtures only give positions, so work it out the way the picker's mannequin does.
            let moving = hands(i).map { hand -> HandState in
                var h = hand
                if let was = before[hand.id] { h.velocity = CGVector(dx: (hand.palm.x - was.x) * 30, dy: (hand.palm.y - was.y) * 30) }
                before[hand.id] = hand.palm
                return h
            }
            let c = bench.context(hands: moving, form: form, face: withFace)
            set.update(c, blocked: false)
            for m in set.moves where m.isEngaged || m.hasLight { seen.insert(m.name) }
            if !set.screenEffect.echoes.isEmpty { echoes = true }
        }
        if echoes { seen.insert("echoes") }
        return seen
    }

    // MARK: The ten moves, one pose each

    func testEveryPoseSetsOffItsOwnMoveAndNoOtherForAnyForm() {
        for form in [SaiyanForm.base, .superSaiyan, .superSaiyanGod, .superSaiyanBlue, .ultraInstinct] {
            XCTAssertEqual(ran(120, form: form, still(cupped())), ["Kamehameha"], "cupped hands at your side, in \(form.title)")
            XCTAssertEqual(ran(120, form: form, still(palmsUp())), ["Final Flash"], "open palms up at the chest, in \(form.title)")
            XCTAssertEqual(ran(120, form: form, still([atForehead()])), ["Special Beam Cannon"], "two fingers held at the forehead, in \(form.title)")
            XCTAssertEqual(ran(120, form: form, still(overhead(count: 2))), ["Spirit Bomb"], "both hands overhead, in \(form.title)")
            XCTAssertEqual(ran(120, form: form, still(overhead(count: 1))), ["Destructo Disc"], "one hand overhead, in \(form.title)")
            XCTAssertEqual(ran(60, form: form, still(nearFace())), ["Solar Flare"], "both hands by the face, in \(form.title)")
            XCTAssertEqual(ran(150, form: form, still([place(.point, palm: CGPoint(x: 800, y: 300), angle: -.pi / 2)])), ["Finger Beam"],
                           "a finger held still, pointing across, in \(form.title)")
        }
    }

    func testAQuickTouchOfTheForeheadIsInstantTransmissionNotTheBeamCannon() {
        let touch = Array(repeating: [atForehead()], count: 12) + Array(repeating: [HandState](), count: 90)    // 0.4 s, then hands away
        XCTAssertEqual(ran(touch.count) { touch[$0] }, ["Instant Transmission", "echoes"])
        let hold = Array(repeating: [atForehead()], count: 27) + Array(repeating: [HandState](), count: 60)     // 0.9 s: too long
        let held = ran(hold.count) { hold[$0] }
        XCTAssertTrue(held.contains("Special Beam Cannon"), "a long hold charges the cannon: \(held)")
        XCTAssertFalse(held.contains("Instant Transmission"), "and is not a teleport: \(held)")
    }

    func testAPushAtTheCameraIsAKiBlastAndAFastSweepIsAZanzoken() {
        let push = (0..<60).map { i -> [HandState] in [place(.open, palm: CGPoint(x: 900, y: 330), size: 90 * (1 + 0.45 * min(1, Double(max(0, i - 20)) / 8)))] }
        XCTAssertEqual(ran(60) { push[$0] }, ["Ki Blast"], "a palm that grows quickly")
        // 600 px in six frames, sideways.
        let sweep = (0..<60).map { i -> [HandState] in
            let x = 300.0 + 600 * min(1, Double(max(0, i - 20)) / 6)
            return [place(.open, palm: CGPoint(x: x, y: 330), size: 110)]
        }
        XCTAssertEqual(ran(60) { sweep[$0] }, ["Zanzoken", "echoes"], "a very fast sideways sweep")
    }

    // MARK: Things that must not set off anything

    func testNothingFiresFromEverydayHandsOnACall() {
        func wave(_ i: Int) -> [HandState] {
            [place(.open, palm: CGPoint(x: 900 + 40 * sin(Double(i) / 30 * 2 * .pi * 2.5), y: 330), size: 110)]
        }
        XCTAssertEqual(ran(150, wave), [], "a friendly wave")
        XCTAssertEqual(ran(150, still([place(.open, palm: CGPoint(x: 940, y: 380), size: 100)])), [], "an open hand held up while talking")
        XCTAssertEqual(ran(150, still([place(.fist, palm: CGPoint(x: 900, y: 300), size: 100)])), [], "one fist")
        XCTAssertEqual(ran(150, still(fists())), [], "both fists belong to the power-up, not a move")
        XCTAssertEqual(ran(150, still([place(.open, palm: CGPoint(x: 700, y: 300), size: 100)])), [], "one open palm")
        XCTAssertEqual(ran(150, still([place(.open, palm: CGPoint(x: 700, y: 400), size: 100)])), [], "a hand by the face")
        XCTAssertEqual(ran(150, still([place(.peace, palm: CGPoint(x: 900, y: 330), size: 100)])), [], "a peace sign")
        XCTAssertEqual(ran(150, still([place(.thumbsUp, palm: CGPoint(x: 900, y: 330), size: 100, angle: .pi / 2)])), [], "a thumbs up")
        // Every move is measured from the face, so with none in view nothing fires.
        for (name, hands) in [("cupped hands", cupped()), ("fingers at the forehead", [atForehead()]), ("both hands overhead", overhead(count: 2)),
                              ("both hands by the face", nearFace())] {
            XCTAssertEqual(ran(150, face: false, still(hands)), [], "\(name) mean nothing without a face to measure from")
        }
        // Pointing while talking: the finger drifts about.
        func jab(_ i: Int) -> [HandState] {
            [place(.point, palm: CGPoint(x: 800 + 90 * sin(Double(i) / 30 * 2 * .pi * 1.3), y: 300 + 50 * sin(Double(i) / 30 * 2 * .pi * 0.9)), angle: -.pi / 2)]
        }
        XCTAssertEqual(ran(150, jab), [], "pointing while moving")
    }

    func testBothFistsClaimTheHandsSoNoMoveBegins() {
        let bench = SaiyanBench()
        let set = SaiyanMoveSet()
        let power = SaiyanTransformation()
        var time = 0.0
        for _ in 0..<60 {
            time += 1.0 / 30
            let c = bench.context(hands: fists())
            power.update(hands: fists(), gestures: c.gestures, face: c.face, dt: 1.0 / 30, time: time)
            set.update(c, blocked: power.isClaiming)
            XCTAssertNil(set.engaged, "no move begins from fists")
        }
        XCTAssertTrue(power.isClaiming)
    }

    // MARK: The whole lens

    func testTheDragonBallLensIsOnTheShelfAndNeedsWhatItUses() throws {
        let info = try XCTUnwrap(LensCatalog.info(for: "dragon-ball"))
        XCTAssertEqual(info.category, .faces)
        XCTAssertTrue(info.needsFace)
        XCTAssertTrue(info.needsHands)
        XCTAssertEqual(LensBrowserGroups.group(for: info), "Anime")
        print("catalog counts: filters \(LensCatalog.filters.count) (hands \(LensCatalog.filters.filter(\.needsHands).count)), faces \(LensCatalog.faces.count), games \(LensCatalog.games.count), scenes \(LensCatalog.scenes.count)")
        let lens = info.make()
        XCTAssertEqual(lens.needs, [.face, .matte, .hands])
        XCTAssertTrue(lens.wantsMatteGrid)
    }

    func testAPlainFrameWithNoHandsIsTheCameraPictureAndTheStatusSaysWhatToDo() {
        let h = LensHarness()
        let base = h.input()
        let lens = SaiyanLens()
        var out = base.composed
        for i in 0..<10 { out = lens.render(h.at(base, time: Double(i) / 30)) }
        let before = h.bitmap(base.composed), after = h.bitmap(out)
        // The hint hand waves at the bottom; everywhere else is untouched.
        XCTAssertLessThan(after.change(from: before, in: CGRect(x: 0, y: 200, width: 1280, height: 520)), 8, "base form draws nothing over the picture")
        XCTAssertEqual(lens.status?.title, "Hold both fists up to power up")
        XCTAssertEqual(lens.form, .base)
    }

    /// The finished lens, driven by hands only: fists up climb the forms in order, then a move fires in the form reached.
    /// The picker's thumbnail: the mannequin powers up with both fists, then charges a Kamehameha, and the picture is taken at the end.
    func testThePickerThumbnailShowsSuperSaiyanChargingAKamehameha() throws {
        let info = try XCTUnwrap(LensCatalog.info(for: "dragon-ball"))
        let renderer = LensBrowserRenderer()
        let session = LensBrowserRenderer.Session(info: info, renderer: renderer)
        let dt = 1 / max(5, session.direction.fps)
        let frames = Int((session.direction.seconds / dt).rounded())
        var shots: [CIImage] = []
        for i in 1...frames {
            let out = session.step(dt)
            if i == Int(1.0 / dt) || i == Int(1.9 / dt) || i == Int(3.2 / dt) || i == frames {
                shots.append(CIImage(cgImage: renderer.picture(out, size: LensBrowserMannequin.size)!))
            }
        }
        Output.save(SaiyanBench.sheet(shots, columns: 2), as: "dragon-ball-thumbnail-script.png")
        Output.save(shots[shots.count - 1], as: "dragon-ball-thumbnail-final.png")
        let lens = try XCTUnwrap(session.lens as? SaiyanLens)
        XCTAssertEqual(lens.form, .superSaiyan, "the shout powers the mannequin up one level")
        XCTAssertEqual(lens.engagedMove, "Kamehameha", "and the cupped hands are charging at the end")
        let thumb = try XCTUnwrap(renderer.thumbnail(for: info))
        XCTAssertEqual(thumb.width, Int(LensBrowserRenderer.thumbnailSize.width))
    }

    func testTheLensClimbsEveryFormFromBothFistsAndThenFiresAMove() throws {
        let bench = SaiyanBench()
        let lens = SaiyanLens()
        var pictures: [SaiyanForm: CIImage] = [:]
        var order: [SaiyanForm] = [.base]
        var frame = 0
        while lens.form != SaiyanForm.top, frame < 30 * 25 {
            let input = bench.input(hands: fists())
            let out = lens.render(LensInput(time: Double(frame) / 30, dt: 1.0 / 30, rect: input.rect, camera: input.camera, matte: input.matte,
                                            background: input.background, composed: input.composed, matteGrid: input.matteGrid, face: input.face,
                                            services: input.services, hands: fists()))
            if lens.form != order.last { order.append(lens.form) }
            // The first settled frame of each form, before the charge toward the next one has started to show.
            if pictures[lens.form] == nil, lens.body.transition >= 1, lens.body.flash < 0.01, lens.body.sinceChange > 0.9 || lens.form == .base && frame > 5 {
                pictures[lens.form] = out
                Output.save(out, as: "dragon-ball-\(lens.form.rawValue)-\(lens.form.shortTitle).png")
            }
            frame += 1
        }
        XCTAssertEqual(order, SaiyanForm.allCases, "every form, in order, with nothing skipped")
        XCTAssertLessThan(Double(frame) / 30, 20, "and it takes about a quarter of a minute to reach the top")
        let sheet = SaiyanBench.sheet(SaiyanForm.allCases.compactMap { pictures[$0] }, columns: 4)
        Output.save(sheet, as: "dragon-ball-forms-through-the-lens.png")
    }

    func testTheLensFiresAKamehamehaInItsFormAndStatusFollows() throws {
        let bench = SaiyanBench()
        let lens = SaiyanLens()
        var frame = 0
        func render(_ hands: [HandState]) -> CIImage {
            let input = bench.input(hands: hands)
            defer { frame += 1 }
            return lens.render(LensInput(time: Double(frame) / 30, dt: 1.0 / 30, rect: input.rect, camera: input.camera, matte: input.matte,
                                         background: input.background, composed: input.composed, matteGrid: input.matteGrid, face: input.face,
                                         services: input.services, hands: hands))
        }
        for _ in 0..<45 { _ = render(fists()) }          // up to Super Saiyan
        XCTAssertEqual(lens.form, .superSaiyan)
        for _ in 0..<20 { _ = render([]) }               // hands away: the form stays
        XCTAssertEqual(lens.form, .superSaiyan)
        var out = render([])
        for _ in 0..<70 { out = render(cupped()) }
        Output.save(out, as: "dragon-ball-kamehameha-charging.png")
        XCTAssertEqual(lens.engagedMove, "Kamehameha")
        XCTAssertNotNil(lens.status)
        let chant = ["Ka…", "me…", "ha…", "me…", "Release!"]
        XCTAssertTrue(chant.contains { lens.status?.title.hasPrefix($0.replacingOccurrences(of: "…", with: "")) ?? false },
                      "the status follows the chant: \(String(describing: lens.status?.title))")
    }

    /// For a sense of scale: the lenses we already ship, run through the same harness, next to the Dragon Ball lens in two states.
    func testWhatTheFramesCostNextToTheLensesWeAlreadyShip() {
        let h = LensHarness()
        let base = h.input()
        func mean(_ lens: Lens) -> String {
            let cost = h.cost(of: lens, base: base, frames: 60)
            return String(format: "%.1f ms (worst %.1f)", cost.mean, cost.worst)
        }
        print("frame cost, same harness: Aura \(mean(AuraLens(style: .power))), Crown \(mean(DressUpLens(kind: .crown))), Dragon Ball idle \(mean(SaiyanLens()))")
    }

    /// Where the time of one frame goes, piece by piece, each rendered all the way to the output buffer so the graphics chip's share counts.
    func testWhereTheFrameTimeGoes() {
        let h = LensHarness()
        let base = h.input()
        let buffer = h.compositor.makeOutputBuffer()!
        func ms(_ frames: Int = 60, _ make: (Int) -> CIImage) -> String {
            var total = 0.0, worst = 0.0
            for i in 0..<frames {
                let started = CFAbsoluteTimeGetCurrent()
                h.compositor.render(make(i), into: buffer)
                let took = (CFAbsoluteTimeGetCurrent() - started) * 1000
                total += took
                worst = max(worst, took)
            }
            return String(format: "%5.1f (worst %5.1f)", total / Double(frames), worst)
        }
        var lines: [String] = []
        for form in [SaiyanForm.superSaiyan, .superSaiyan3, .blueKaioken, .ultraInstinct] {
            var state = SaiyanBodyState()
            state.form = form; state.previousForm = form; state.level = form.power; state.presence = 1
            let aura = SaiyanAura()
            let back = ms { i in state.time = Double(i) / 30; return aura.backLayer(h.at(base, time: Double(i) / 30), state) }
            let front = ms { i in state.time = Double(i) / 30; return aura.frontLight(h.at(base, time: Double(i) / 30), state) ?? base.composed }
            let costume = SaiyanFace(), rig = HeadwearRig()
            let hair = ms { i in
                state.time = Double(i) / 30
                let input = h.at(base, time: Double(i) / 30)
                costume.apply(state)
                guard let frame = rig.update(input.face, dt: 1.0 / 30, bounds: input.rect) else { return base.composed }
                costume.advance(frame)
                var layer = input.services.overlay { ctx in costume.draw(HeadwearPen(ctx: ctx), frame) } ?? input.clear
                if let more = costume.hairImage(frame) { layer = more.composited(over: layer) }
                return layer.composited(over: base.composed)
            }
            lines.append("\(form.shortTitle.padding(toLength: 8, withPad: " ", startingAt: 0)) aura back \(back)  front \(front)  hair+face \(hair)")
        }
        let lens = SaiyanLens()
        lines.append("lens idle, base form: \(ms { i in lens.render(h.at(base, time: Double(i) / 30)) })")
        print("frame time by piece (ms, to the output buffer):\n" + lines.joined(separator: "\n"))
    }

    func testTheFullLensHoldsThirtyFramesASecondInTheTopFormMidMove() {
        let bench = SaiyanBench()
        let lens = SaiyanLens()
        let hands = cupped()
        var durations: [Double] = []
        let h = bench.h
        let buffer = h.compositor.makeOutputBuffer()!
        for i in 0..<(30 * 18) {
            // Fists for the first part to climb, then the pose.
            let held = i < 30 * 14 ? fists() : hands
            let input = bench.input(hands: held)
            let started = CFAbsoluteTimeGetCurrent()
            let out = lens.render(LensInput(time: Double(i) / 30, dt: 1.0 / 30, rect: input.rect, camera: input.camera, matte: input.matte,
                                            background: input.background, composed: input.composed, matteGrid: input.matteGrid, face: input.face,
                                            services: input.services, hands: held))
            h.compositor.render(out, into: buffer)
            if i >= 30 * 15 { durations.append((CFAbsoluteTimeGetCurrent() - started) * 1000) }
        }
        let mean = durations.reduce(0, +) / Double(durations.count)
        print("dragon ball lens, \(lens.form.title), mid-move: mean \(String(format: "%.1f", mean)) ms, worst \(String(format: "%.1f", durations.max() ?? 0)) ms")
        XCTAssertLessThan(mean, 33, "a frame must fit in a thirtieth of a second")
    }
}
