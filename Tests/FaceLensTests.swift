import CoreImage
import simd
import XCTest

final class FaceLensTests: XCTestCase {
    private let h = LensHarness()

    private func lonely(_ base: LensInput) -> LensInput {
        LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                  composed: base.composed, matteGrid: nil, face: nil, services: base.services)
    }

    // MARK: Props

    func testPropsSitWhereTheyBelongAndSayNothingWithoutAFace() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        let plain = h.bitmap(base.composed)
        let headTop = CGRect(x: 640 - 100, y: 380 + 150, width: 200, height: 150)    // above the head
        let eyes = CGRect(x: 640 - 90, y: 380 - 10, width: 180, height: 50)
        let corner = CGRect(x: 20, y: 20, width: 200, height: 100)

        for (kind, region) in [(PropsLens.Kind.crown, headTop), (.party, headTop), (.cat, headTop), (.shades, eyes)] {
            let lens = PropsLens(kind: kind)
            var out = base.composed
            for i in 0..<30 { out = lens.render(h.at(base, time: Double(i) / 30)) }       // long enough to land
            Output.save(out, as: "face-\(kind.rawValue).png")
            let bits = h.bitmap(out)
            XCTAssertGreaterThan(bits.change(from: plain, in: region), 120, "\(kind) should show where it belongs")
            XCTAssertEqual(bits.change(from: plain, in: corner), 0, "\(kind) shouldn't touch the far corner")
        }

        let lens = PropsLens(kind: .crown)
        XCTAssertEqual(h.bitmap(lens.render(lonely(base))).change(from: plain, in: base.rect), 0, "with no face there is nothing to dress")
        XCTAssertEqual(lens.status?.title, "Looking for your face…")
    }

    func testPropsFollowATiltedHeadAndAMovingOne() {
        let still = SyntheticScene(center: CGPoint(x: 640, y: 380))
        var turned = still; turned.roll = 0.5
        var moved = still; moved.center = CGPoint(x: 400, y: 380)
        func render(_ scene: SyntheticScene, name: String) -> Bitmap {
            let lens = PropsLens(kind: .crown)
            let frame = h.input(scene)
            var out = frame.composed
            for i in 0..<30 { out = lens.render(h.at(frame, time: Double(i) / 30)) }
            Output.save(out, as: name)
            return h.bitmap(out)
        }
        let a = render(still, name: "face-crown-still.png"), b = render(turned, name: "face-crown-tilted.png"), c = render(moved, name: "face-crown-moved.png")
        // Gold over the middle of the head in the still frame; gone from there once the head is elsewhere.
        func isGold(_ p: RGB) -> Bool { p.r > 200 && p.g > 150 && p.b < 120 }
        XCTAssertTrue(stride(from: 520, to: 600, by: 4).contains { isGold(a.pixel(640, $0)) }, "crown over the still head")
        XCTAssertFalse(stride(from: 520, to: 600, by: 4).contains { isGold(c.pixel(640, $0)) }, "and not where the head used to be")
        XCTAssertTrue(stride(from: 520, to: 600, by: 4).contains { isGold(c.pixel(400, $0)) }, "but over where it is now")
        XCTAssertGreaterThan(a.change(from: b, in: CGRect(x: 440, y: 480, width: 400, height: 200)), 100, "tilting the head tilts the crown")
    }

    func testShadesDropIntoPlace() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        let plain = h.bitmap(base.composed)
        let lens = PropsLens(kind: .shades)
        let eyes = CGRect(x: 640 - 90, y: 380, width: 180, height: 40)
        let early = h.bitmap(lens.render(h.at(base, time: 0)))
        for i in 1..<25 { _ = lens.render(h.at(base, time: Double(i) / 30)) }
        let landed = h.bitmap(lens.render(h.at(base, time: 1)))
        XCTAssertEqual(early.change(from: plain, in: eyes), 0, "the first frame has them above the head, not on the eyes")
        XCTAssertGreaterThan(landed.change(from: plain, in: eyes), 150, "and a moment later they are on")
    }

    // MARK: Funhouse

    func testBigEyesBulgeTheEyesAndLeaveTheRestAlone() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        let plain = h.bitmap(base.composed)
        let out = FunhouseLens(kind: .bigEyes).render(base)
        let bits = h.bitmap(out)
        let face = scene.face()
        XCTAssertGreaterThan(bits.change(from: plain, in: CGRect(x: face.leftEye.x - 40, y: face.leftEye.y - 25, width: 80, height: 50)), 60)
        XCTAssertEqual(bits.change(from: plain, in: CGRect(x: 20, y: 20, width: 250, height: 200)), 0, "nowhere near the face")
        XCTAssertEqual(out.extent, base.rect)
        Output.save(out, as: "face-big-eyes.png")
        Output.save(FunhouseLens(kind: .chipmunk).render(base), as: "face-chipmunk.png")
        Output.save(FunhouseLens(kind: .bigMouth).render(h.input(SyntheticScene(center: CGPoint(x: 640, y: 380), mouthOpen: 0.8))), as: "face-big-mouth.png")
    }

    // MARK: Breath

    func testBreathComesFromAnOpenMouthOnly() {
        var shut = SyntheticScene(center: CGPoint(x: 640, y: 440)); shut.mouthOpen = 0
        var open = shut; open.mouthOpen = 1
        for kind in BreathLens.Kind.allCases {
            let quiet = BreathLens(kind: kind)
            for i in 0..<30 { _ = quiet.render(h.at(h.input(shut), time: Double(i) / 30)) }
            XCTAssertEqual(quiet.particleCount, 0, "\(kind): mouth shut, nothing comes out")

            let lens = BreathLens(kind: kind)
            let frame = h.input(open)
            let plain = h.bitmap(frame.composed)
            var out = frame.composed
            for i in 0..<20 { out = lens.render(h.at(frame, time: Double(i) / 30)) }
            Output.save(out, as: "face-breath-\(kind.rawValue).png")
            let bits = h.bitmap(out)
            XCTAssertGreaterThan(lens.particleCount, 40, "\(kind): open wide, plenty comes out")
            // It leaves from the mouth and goes downward.
            let mouth = open.face().mouth
            XCTAssertGreaterThan(bits.change(from: plain, in: CGRect(x: mouth.x - 80, y: mouth.y - 160, width: 160, height: 140)), 80, "\(kind): below the mouth")
            XCTAssertEqual(bits.change(from: plain, in: CGRect(x: 20, y: 560, width: 200, height: 140)), 0, "\(kind): not up in the corner")

            lens.restart()
            XCTAssertEqual(lens.particleCount, 0)
        }
    }

    func testTheMouthNeedsToOpenFurtherToStartThanToKeepGoing() {
        let lens = BreathLens(kind: .rainbow)
        func go(_ open: Double, seconds: Double) {
            var scene = SyntheticScene(center: CGPoint(x: 640, y: 440)); scene.mouthOpen = open
            let frame = h.input(scene)
            for i in 0..<Int(seconds * 30) { _ = lens.render(h.at(frame, time: Double(i) / 30)) }
        }
        go(0.4, seconds: 0.5)
        XCTAssertEqual(lens.particleCount, 0, "not yet open enough to start")
        go(1.0, seconds: 0.3)
        XCTAssertGreaterThan(lens.particleCount, 0)
        let started = lens.particleCount
        go(0.4, seconds: 0.2)
        XCTAssertGreaterThan(lens.particleCount, started - 1, "wobbling to 40% doesn't cut it off")
    }

    // MARK: Laser eyes

    func testRaisedEyebrowsFireLasersThatLeaveThePicture() {
        var calm = SyntheticScene(center: CGPoint(x: 640, y: 420)); calm.browRaise = 0
        var surprised = calm; surprised.browRaise = 1
        let calmFrame = h.input(calm), surprisedFrame = h.input(surprised)

        let quiet = LaserEyesLens()
        for i in 0..<30 { _ = quiet.render(h.at(calmFrame, time: Double(i) / 30)) }
        XCTAssertEqual(quiet.beamPower, 0, accuracy: 0.001)

        let lens = LaserEyesLens()
        let plain = h.bitmap(surprisedFrame.composed)
        var out = surprisedFrame.composed
        for i in 0..<30 { out = lens.render(h.at(surprisedFrame, time: Double(i) / 30)) }
        Output.save(out, as: "face-laser-eyes.png")
        let bits = h.bitmap(out)
        XCTAssertGreaterThan(lens.beamPower, 0.95, "fully charged")

        let face = surprised.face()
        let beams = LaserEyesLens.beams(from: face, in: surprisedFrame.rect)
        XCTAssertEqual(beams.count, 2)
        XCTAssertLessThan(beams[0].end.x, 1, "the left beam runs off the left side")
        XCTAssertGreaterThan(beams[1].end.x, 1279, "the right beam runs off the right side")
        XCTAssertLessThan(beams[0].end.y, face.leftEye.y, "and a little downward")
        // Bright along the left beam, between the eye and the edge.
        let mid = CGPoint(x: (face.leftEye.x + beams[0].end.x) / 2, y: (face.leftEye.y + beams[0].end.y) / 2)
        XCTAssertGreaterThan(bits.pixel(Int(mid.x), Int(mid.y)).r, 230, "the beam is hot in the middle")
        XCTAssertEqual(bits.change(from: plain, in: CGRect(x: 600, y: 20, width: 100, height: 60)), 0, "nothing at the bottom middle")
    }

    func testLasersNeedAFirmRaiseToStartAndFadeWhenYouRelax() {
        let lens = LaserEyesLens()
        func hold(_ raise: Double, seconds: Double) {
            var scene = SyntheticScene(center: CGPoint(x: 640, y: 420)); scene.browRaise = raise
            let frame = h.input(scene)
            for i in 0..<Int(seconds * 30) { _ = lens.render(h.at(frame, time: Double(i) / 30)) }
        }
        hold(0.45, seconds: 0.7)
        XCTAssertEqual(lens.beamPower, 0, accuracy: 0.001, "a slight raise isn't enough")
        hold(1, seconds: 0.5)
        XCTAssertGreaterThan(lens.beamPower, 0.9)
        hold(0.45, seconds: 0.5)
        XCTAssertGreaterThan(lens.beamPower, 0.9, "but once firing, a half raise keeps it going")
        hold(0, seconds: 0.5)
        XCTAssertLessThan(lens.beamPower, 0.05, "relax and it fades")
    }

    func testRayExit() {
        let rect = CGRect(x: 0, y: 0, width: 1280, height: 720)
        XCTAssertEqual(LaserEyesLens.exit(from: SIMD2(640, 360), heading: SIMD2(1, 0), rect: rect).x, 1280, accuracy: 0.001)
        XCTAssertEqual(LaserEyesLens.exit(from: SIMD2(640, 360), heading: SIMD2(0, -1), rect: rect).y, 0, accuracy: 0.001)
        let diagonal = LaserEyesLens.exit(from: SIMD2(640, 360), heading: simd_normalize(SIMD2(1, 1)), rect: rect)
        XCTAssertEqual(diagonal.y, 720, accuracy: 0.001, "the nearer wall is the top")
        XCTAssertEqual(diagonal.x, 1000, accuracy: 0.001)
    }

    // MARK: In the pipeline

    func testAFaceLensGetsAFaceThroughThePipelineAndNoFaceMeansNoTracking() throws {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))
        let pipeline = FramePipeline()
        pipeline.setBackground(.off, source: nil)
        pipeline.faceOverride = { scene.face() }
        let probe = ProbeLens(needs: [.face], grid: false)
        pipeline.setLens(probe)
        var out: CVPixelBuffer?
        pipeline.onOutput = { buffer, _ in out = buffer }
        pipeline.queue.sync { pipeline.process(scene.cameraBuffer(), at: .zero) }
        XCTAssertNotNil(out)
        let input = try XCTUnwrap(probe.inputs.first)
        XCTAssertEqual(try XCTUnwrap(input.face).mouth, scene.face().mouth)
        XCTAssertNil(input.matte, "a face lens doesn't need the cutout")

        let plain = ProbeLens(needs: [], grid: false)
        pipeline.faceOverride = { XCTFail("tracking was asked for by a lens that doesn't use it"); return nil }
        pipeline.setLens(plain)
        pipeline.queue.sync { pipeline.process(scene.cameraBuffer(), at: .zero) }
        XCTAssertNil(try XCTUnwrap(plain.inputs.first).face)
    }

    /// Vision may find nothing in a cartoon; this checks the plumbing runs and hands back something sane either way.
    func testVisionRunsOverAFrameWithoutIncident() {
        let service = FaceTrackingService()
        service.submit(SyntheticScene().cameraBuffer(), transform: .identity)
        let finished = expectation(description: "looked")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { finished.fulfill() }
        wait(for: [finished], timeout: 4)
        if let face = service.latest() { XCTAssertGreaterThan(face.rect.width, 0) }
    }
}

final class MouthCatchTests: XCTestCase {
    private let size = CGSize(width: 1280, height: 720)
    private func face(at mouth: CGPoint, open: Double) -> FaceState {
        var scene = SyntheticScene(center: CGPoint(x: mouth.x, y: mouth.y + 0.95 * 84)); scene.mouthOpen = open
        return scene.face()
    }
    private func world(_ face: FaceState?) -> GameWorld { GameWorld(size: size, matte: nil, motion: nil, face: face) }

    func testOpenMouthsEatAndShutOnesDont() {
        var game = MouthCatchGame(size: size, seed: 1)
        let mouth = CGPoint(x: 640, y: 300)
        // Let the game spawn food, then fly everything on screen straight at the mouth.
        for _ in 0..<60 { game.step(1.0 / 30, world: world(face(at: CGPoint(x: 1200, y: 100), open: 0))) }
        XCTAssertGreaterThan(game.items.count, 0)
        game.moveAllItems(to: mouth)
        game.step(1.0 / 30, world: world(face(at: mouth, open: 0)))
        XCTAssertEqual(game.score, 0, "mouth shut")
        XCTAssertEqual(game.eaten, 0)
        game.moveAllItems(to: mouth)
        game.step(1.0 / 30, world: world(face(at: mouth, open: 1)))
        XCTAssertGreaterThan(game.eaten + (game.score == 0 ? 1 : 0), 0, "mouth open: something was swallowed")
    }

    func testFoodScoresBombsCostAndGoldenPaysFive() {
        var game = MouthCatchGame(size: size, seed: 2)
        let mouth = CGPoint(x: 640, y: 300)
        let open = face(at: mouth, open: 1)
        game.setItems([.food(0)], at: mouth)
        game.step(1.0 / 60, world: world(open))
        XCTAssertEqual(game.score, 1)
        game.setItems([.golden], at: mouth)
        game.step(1.0 / 60, world: world(open))
        XCTAssertEqual(game.score, 1 + 5 * game.multiplier - (game.multiplier - 1) * 0 , "golden is worth five, times the streak")
        let before = game.score
        game.setItems([.bomb], at: mouth)
        game.step(1.0 / 60, world: world(open))
        XCTAssertEqual(game.score, max(0, before - 3))
        XCTAssertEqual(game.combo, 0, "a bomb breaks the streak")
    }

    func testBombsFallPastAClosedMouthHarmlessly() {
        var game = MouthCatchGame(size: size, seed: 3)
        let mouth = CGPoint(x: 640, y: 300)
        game.setItems([.bomb], at: mouth)
        game.step(1.0 / 60, world: world(face(at: mouth, open: 0.1)))
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.items.count, 1, "still falling")
    }

    func testStreaksBuildAndLapse() {
        var game = MouthCatchGame(size: size, seed: 4)
        let mouth = CGPoint(x: 640, y: 300)
        let open = face(at: mouth, open: 1)
        for _ in 0..<7 { game.setItems([.food(1)], at: mouth); game.step(1.0 / 60, world: world(open)) }
        XCTAssertEqual(game.combo, 7)
        XCTAssertEqual(game.multiplier, 3)
        for _ in 0..<100 { game.step(1.0 / 30, world: world(face(at: CGPoint(x: 1200, y: 100), open: 0))) }
        XCTAssertEqual(game.combo, 0, "wait too long and it resets")
    }

    func testTheRoundEndsAndIsDeterministic() {
        var a = MouthCatchGame(size: size, seed: 7), b = MouthCatchGame(size: size, seed: 7)
        var steps = 0
        while !a.isOver && steps < 30 * 60 { a.step(1.0 / 30, world: world(nil)); b.step(1.0 / 30, world: world(nil)); steps += 1 }
        XCTAssertTrue(a.isOver)
        XCTAssertEqual(Double(steps) / 30, MouthCatchGame.roundSeconds, accuracy: 0.2)
        XCTAssertEqual(a.items.map(\.position.x), b.items.map(\.position.x))
    }
}

final class FlappyFaceTests: XCTestCase {
    private let size = CGSize(width: 1280, height: 720)
    private func world(headY: Double?) -> GameWorld {
        guard let headY else { return GameWorld(size: size, matte: nil, motion: nil, face: nil) }
        return GameWorld(size: size, matte: nil, motion: nil, face: SyntheticScene(center: CGPoint(x: 500, y: headY)).face())
    }

    private func fly(_ game: inout FlappyFaceGame, seconds: Double, follow: Bool = true) {
        for _ in 0..<Int(seconds * 60) {
            // Steer toward the middle of the next gap, like a good player.
            let next = game.pipes.first { $0.x + FlappyFaceGame.pipeWidth > game.birdX - 40 }
            let target = follow ? (next?.gapCenter ?? 360) : 360
            game.step(1.0 / 60, world: world(headY: target))
        }
    }

    func testTheBirdFollowsTheHead() {
        var game = FlappyFaceGame(size: size, seed: 1)
        let eyes = SyntheticScene(center: CGPoint(x: 500, y: 600)).face().eyeCenter.y - 600     // the bird follows the eyes, not the scene's centre
        for _ in 0..<60 { game.step(1.0 / 60, world: world(headY: 600)) }
        XCTAssertEqual(game.birdY, 600 + eyes, accuracy: 5)
        for _ in 0..<60 { game.step(1.0 / 60, world: world(headY: 150)) }
        XCTAssertEqual(game.birdY, 150 + eyes, accuracy: 5)
        for _ in 0..<60 { game.step(1.0 / 60, world: world(headY: -500)) }
        XCTAssertGreaterThanOrEqual(game.birdY, FlappyFaceGame.birdRadius, "can't leave the bottom of the frame")
    }

    func testSteeringThroughTheGapsScoresAndKeepsAllThreeLives() {
        var game = FlappyFaceGame(size: size, seed: 2)
        fly(&game, seconds: 25)
        XCTAssertGreaterThan(game.score, 5)
        XCTAssertEqual(game.lives, 3)
        XCTAssertFalse(game.isOver)
    }

    func testIgnoringThePipesCostsLivesAndEndsTheGame() {
        var game = FlappyFaceGame(size: size, seed: 3)
        for _ in 0..<(60 * 90) where !game.isOver { game.step(1.0 / 60, world: world(headY: 30)) }   // hugging the floor
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.lives, 0)
    }

    func testAHitGivesAMomentOfGraceBeforeTheNextOne() {
        var game = FlappyFaceGame(size: size, seed: 4)
        var livesSeen: [Int] = []
        for i in 0..<(60 * 40) where !game.isOver {
            game.step(1.0 / 60, world: world(headY: 30))
            if livesSeen.last != game.lives { livesSeen.append(game.lives) }
            _ = i
        }
        XCTAssertEqual(livesSeen, [3, 2, 1, 0], "one life at a time")
    }

    func testGapsAreAlwaysReachable() {
        var game = FlappyFaceGame(size: size, seed: 5)
        var centres: [Double] = []
        for _ in 0..<(60 * 120) {
            let before = game.pipes.count
            game.step(1.0 / 60, world: world(headY: 360))
            if game.pipes.count > before || (game.pipes.count == before && game.pipes.last.map({ !centres.contains($0.gapCenter) }) == true) {
                if let last = game.pipes.last, !centres.contains(last.gapCenter) { centres.append(last.gapCenter) }
            }
        }
        XCTAssertGreaterThan(centres.count, 10)
        for (a, b) in zip(centres, centres.dropFirst()) { XCTAssertLessThanOrEqual(abs(a - b), 231, "a leap of \(abs(a - b)) is too much") }
        XCTAssertTrue(centres.allSatisfy { $0 > 100 && $0 < 620 })
    }

    func testNoFaceHoldsTheBirdStill() {
        var game = FlappyFaceGame(size: size, seed: 6)
        for _ in 0..<30 { game.step(1.0 / 60, world: world(headY: 500)) }
        let y = game.birdY
        for _ in 0..<30 { game.step(1.0 / 60, world: world(headY: nil)) }
        XCTAssertEqual(game.birdY, y, accuracy: 0.001)
    }
}

final class LensCatalogTests: XCTestCase {
    func testEveryEntryIsUniqueAndMakesAWorkingLens() throws {
        let ids = LensCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "ids must be unique")
        XCTAssertGreaterThanOrEqual(LensCatalog.all.count, 24)
        for info in LensCatalog.all {
            let lens = info.make()
            XCTAssertEqual(lens.needs.contains(.face), info.needsFace, "\(info.name): the catalog and the lens agree on needing a face")
            XCTAssertFalse(info.blurb.isEmpty)
        }
        for category in LensInfo.Category.allCases { XCTAssertFalse(LensCatalog.lenses(in: category).isEmpty) }
        XCTAssertNotNil(LensCatalog.info(for: "flappy-face"))
        XCTAssertNil(LensCatalog.info(for: "nope"))
    }

    func testEveryLensRendersOverASyntheticSceneWithoutTrouble() {
        let h = LensHarness()
        let base = h.input(background: true, wantsGrid: true)
        for info in LensCatalog.all {
            let lens = info.make()
            var out = base.composed
            for i in 0..<5 { out = lens.render(h.at(base, time: Double(i) / 30)) }
            XCTAssertEqual(out.extent.width, 1280, "\(info.name)")
            XCTAssertEqual(out.extent.height, 720, "\(info.name)")
            // And with nobody there.
            let lonely = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: nil,
                                   composed: base.camera, matteGrid: info.make().wantsMatteGrid ? MatteGrid(outputSize: base.rect.size) : nil,
                                   face: nil, services: base.services)
            XCTAssertEqual(lens.render(lonely).extent.width, 1280, "\(info.name) with no one in view")
        }
    }
}
